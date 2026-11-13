# How AltLoad installs AltStore on-device

This document describes each stage of the install, with the protocol, the library, and the file in this repo that does the work.

## Components

| Layer | What | Where |
|---|---|---|
| UI | SwiftUI, Liquid Glass on iOS 26+ (`glassEffect` buttons, `GlassEffectContainer`) with a material fallback on iOS 18–25, `TabView` with `Tab`, midnight gradient background | `ios/App/` |
| Live Activity | ActivityKit + a WidgetKit extension that shows the pairing code in the Dynamic Island and on the Lock Screen | `ios/App/Core/Pairing/PairingLiveActivity.swift`, `ios/Shared/`, `ios/Widgets/` |
| Orchestration | `InstallController` (download, discovery, FFI session, prompts, expiry reminder), `PairingController` (pairing host) | `ios/App/Core/Install/InstallController.swift`, `ios/App/Core/Pairing/PairingController.swift` |
| FFI | A C header plus a Rust static library packaged as `AltLoadFFI.xcframework` | `core/include/altload.h`, `core/src/*.rs` |
| Device protocols | [`idevice`](https://github.com/jkcoxson/idevice) (git `d32c818`): `remote_pairing`, `rsd`, `tunnel_tcp_stack`, `afc`, `installation_proxy`, `misagent`, `house_arrest`, `cryptexd`, `dvt`, `debug_proxy` | `core/src/lib.rs`, `core/src/install/` |
| Apple ID + signing | [`isideload`](https://github.com/nab138/isideload) 0.4.6 (uses idevice, a fork of apple-codesign, rcgen, keyring) | `core/src/install/sign_in.rs`, `core/src/install/bundle.rs` |
| Discovery | `NetServiceBrowser` / `NetService` (mDNSResponder), used for pairing, so no multicast entitlement is needed | `ios/App/Core/Pairing/PairingController.swift` |
| Loopback | [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN): detection via `getifaddrs`, and control via `localdevvpn://` and `altload://` URLs | `ios/App/Core/Device/LocalDevVPN.swift` |
| Catalog | AltStore-format sources (`https://apps.altstore.io` for AltStore and Beta, `https://apps.sidestore.io` for SideStore), GitHub releases for LiveContainer and both nightlies, Husk's `altsource.json` for Husk, the latest-release listings for UTM (GitHub), MeloNX (its Forgejo host) and Madeira (GitHub), which publish no source, with fallbacks for when SideStore's repository is down; `URLSession` download with progress, IPA cache in Application Support | `ios/App/Core/Install/StoreCatalog.swift` |
| Secrets | Keychain (`kSecClassGenericPassword`, `WhenUnlockedThisDeviceOnly`) for the Apple ID password. files in `Application Support/AltLoad` (`FileStorage` in `core/src/install/storage.rs`) for the certificate key and anisette state, one folder per anisette server; values left in the Keychain by older builds are moved over | `ios/App/Core/Account/AppleIDStore.swift`, `core/src/install/storage.rs` |

## 1. Pairing (the Pair tab)

iOS 27 lets a device pair wirelessly with a host that advertises `_remotepairing-pairable-host._tcp`.

1. `altload_run_host` binds a TCP listener and generates a host identity (`RpPairingFile::generate`, `PairableHostInfo::generate`). It then calls back into Swift with the service ID, port and TXT records.
2. Swift publishes those records with `NetService`, so the Bonjour registration goes through mDNSResponder and only needs the Local Network permission.
3. The user taps **Settings › Privacy & Security › Developer Mode › Pair with AltLoad**. The device connects, and `PairableHost::accept` runs SRP pair-setup. The PIN goes to the UI and to the Live Activity.
4. The resulting **RPPairing file** is moved to `Documents/Pairings/<Device>-<id>/rp_pairing_file.plist`. It holds AltLoad's Ed25519 identity, the device's public key and its `altIRK`.

`BGContinuedProcessingTask` keeps the listener alive while the user is in Settings. Silent audio or location can do the same as optional fallbacks.

**Dynamic Island.** iOS only lets an app start a Live Activity while it's in the foreground, so `PairingLiveActivity` starts one when the user taps Pair, in a "waiting" state. When `pinCallback` fires, by then from the background, the activity is updated with the code, so it shows in the Dynamic Island (or on the Lock Screen on iPhones without one) while Settings is open. It ends a few seconds after pairing succeeds or fails. The views live in the `AltLoadWidgets` extension (`ios/Widgets/`), and `PairingActivityAttributes` (`ios/Shared/`) is compiled into both targets.

**Below iOS 27** there is no RPPairing host mode, so the iPhone can't pair with AltLoad. AltLoad still runs from iOS 18: the Pair screen offers **Import Pairing File** instead, `PairingStore.importForThisDevice` copies a pairing file made on a computer into `Documents/Pairings` and marks it as this device's, and everything from step 2 on works the same.

## 2. Tunnel to this iPhone (Install, step 1)

AltLoad has to talk to the phone it's running on, the same way a Mac does over Wi-Fi. An app can't simply connect to its own device's address, because iOS delivers that connection over loopback and the device services don't treat it like a connection from another machine. **LocalDevVPN** solves this without a computer:

- LocalDevVPN is a `NEPacketTunnelProvider` that routes only `10.7.0.1/32`, with the interface at `10.7.1.1`. Your normal traffic doesn't go through it.
- For every IPv4 packet it reads, it swaps the source and destination addresses and writes the packet straight back. When AltLoad opens `10.7.1.1 → 10.7.0.1:49152`, the phone's network stack receives it as `10.7.0.1 → 10.7.1.1:49152`, an inbound connection to its own RemotePairing service (port 49152) from an "external" peer. Replies are reflected back the same way.

The steps:

1. **VPN check:** `LocalDevVPN.isActive` uses `getifaddrs` to look for a `utun*` interface with a `10.7.x.x` address. If there isn't one, the install pauses at `.needsVPN` and AltLoad opens `localdevvpn://enable?scheme=altload`. LocalDevVPN turns the VPN on and reopens AltLoad via `altload://`. AltLoad polls for the interface for up to 6 s, then resumes.
2. **Pair-verify:** AltLoad connects to `10.7.0.1:49152` (the address can be changed in Settings) and runs `RemotePairingClient::attempt_pair_verify` and `validate_pairing` with the saved RPPairing file. It never falls back to a new pair-setup. If verification fails, the user is sent back to the Pair tab.
3. **Tunnel:** `create_tcp_listener` asks remotepairingd for a tunnel port. AltLoad connects to `10.7.0.1:<port>`, also through the VPN, and runs `connect_tls_psk_tunnel_native`. That is a TLS 1.2 PSK tunnel keyed with the pair-verify session key, and it performs the CoreDevice "CDTunnel" handshake, which returns client and server IPv6 addresses, the MTU and the RSD port.
4. **User-space TCP:** the tunnel carries raw IPv6 packets, so `idevice::tcp::adapter::Adapter` (jktcp) runs a TCP stack over it. AltLoad needs no VPN entitlement of its own. The only VPN involved is LocalDevVPN's simple reflector.
5. **RSD:** `RsdHandshake` lists the device's services and properties. AltLoad reads `UniqueDeviceID` from those properties.

This is the same path StikDebug uses (`tunnel_create_rppairing` to `10.7.0.1:49152`) with pairing files from StikPair.

## 3. Apple ID sign-in (Install, step 2)

This comes from isideload's `AppleAccount`.

- **Anisette:** Apple's servers require `X-Apple-I-MD`, `X-Apple-I-MD-M` and related machine-identity headers. `RemoteV3AnisetteProvider` provisions a virtual machine identity through an anisette v3 server over a websocket, then caches the state. The default is **Automatic**: before signing in, AltLoad checks which servers answer `/v3/client_info` (Windows-ADI servers first, since Apple refuses most others since 12 October 2026) and passes up to four to Rust, which tries at most two per sign-in, moving on when Apple or a server rejects the anisette data. Wrong passwords, 2FA problems and cancellations are not retried. Settings also offers a picker built from `https://servers.sidestore.io/servers.json` (HTTPS entries only, merged with a built-in list), a custom URL, and **Reset Anisette Data**. AltServer's `AnisetteDataRequest` uses the same list.
- **GrandSlam (GSA):** the SRP-6a login to `gsa.apple.com`, which never sends the password in plaintext.
- **Failed sign-ins:** the account screens only sign in when you tap. Apple's error code decides what happens next. A rejected password is removed from the Keychain, and a second rejection in a row pauses sign-ins for that Apple ID for 15 minutes. A locked account also removes the saved password and pauses sign-ins straight away, and Apple's "too many requests" error pauses them without removing it. The pause is kept in `Application Support/AltLoad/signin`, so it survives relaunching. Developer tokens aren't saved between runs.
- **2FA:** trusted-device push or SMS. Rust calls `AltLoadPromptCb(kind: 1, json)`. Swift shows `TwoFactorSheet` and answers with `altload_install_session_respond("code:123456" | "sms:<id>" | "devices" | "resend" | "abort")`.

## 4. Developer services (Install, step 3)

isideload's `DeveloperSession` uses Xcode's developer-services API:

- `ensure_device_registered(team, name, UDID)`
- `CertificateIdentity::retrieve` reuses the stored "AltLoad" development certificate, or creates one. At the certificate limit, `MaxCertsBehavior::Prompt` calls Swift with `kind: 2`, and the user picks which certificates to revoke.
- App IDs are registered for the main app and each extension as `com.rileytestut.AltStore.<TEAMID>` and so on. Then the app group `group.com.rileytestut.AltStore.<TEAMID>`.
- Provisioning profiles are downloaded per App ID.

The team is selected with `TeamSelection::First`. People with more than one team can change this in `install.rs`.

## 5. Preparing AltStore (Install, step 4)

AltServer normally writes these keys, and AltStore reads them at runtime:

| Key | Written by | Purpose |
|---|---|---|
| `ALTDeviceID` | AltLoad (`prepare_app`) | UDID of the device AltStore runs on |
| `ALTServerID` | AltLoad | ID of the "server" that installed it. This is a stable per-install UUID |
| `ALTCertificateID` + `ALTCertificate.p12` | isideload (`apply_special_app_behavior`); for AltStore Beta, AltLoad (`inject_store_keys`) | The signing identity AltStore uses to re-sign the apps *it* installs |
| `ALTAppGroups` | isideload; for AltStore Beta, AltLoad (`inject_store_keys`) | The registered app group |
| `ALTPairingFile.dat` | isideload (`apply_special_app_behavior`); for AltStore Beta, AltLoad (`seal_pairing_file`) | This iPhone's pairing file, sealed, for AltStore's Remote AltServer setup |

`ALTPairingFile.dat` is a file in the bundle, not an Info.plist key. `pairing_for_altstore` in `core/src/install/bundle.rs` reads this iPhone's pairing file and adds the `UDID` when it's missing. The file is then sealed with AES-256-GCM: a 12-byte nonce followed by the ciphertext, keyed with the SHA-256 of the certificate's machine ID. It is written before signing, so the signature covers it. AltLoad is still AltStore's AltServer; the file is there so AltStore's Remote AltServer setup already has one and skips pairing. AltStore works without it, so a pairing file that can't be read doesn't stop the install.

The IPA is unpacked on a background thread (`unpack_ipa`, started with `spawn_blocking`) while the Apple ID sign-in and the device link run, so this stage only waits for it to finish. `stamp_app` then writes `ALTDeviceID` and `ALTServerID`, which need the UDID from the tunnel.

isideload then re-signs every bundle with the matching profile's entitlements, using `apple-codesign-quick`.

## 6. Install (Install, step 5)

`isideload::sideload::install::install_app_rsd` uses the same tunnel:

1. `AfcClient::connect_rsd` uploads the signed `.app` folder to `PublicStaging/` in 1 MB chunks. This covers 0–70% of the progress bar.
2. `InstallationProxyClient::connect_rsd` → `install_with_callback(PackageType: Developer)`. This covers 70–100%.

Afterwards AltLoad reads `CFBundleIdentifier`, the version, `TeamIdentifier` and `ExpirationDate` from the embedded profile. It stores them and schedules a reminder for 24 hours before expiry. The success screen shows how long the install took, measured from the start of the run to the end of the install, pairing-file step included.

## Refreshing

A free-account profile lasts 7 days. AltStore's built-in refresh expects to find AltServer on the network, which doesn't exist in this setup. Tapping **Refresh AltStore** in AltLoad runs the same pipeline with the cached IPA. Because the bundle ID and team are the same, iOS treats it as an update, and AltStore's data and the apps it manages are kept.

### Automatic refresh

`ios/App/Core/Install/AutoRefresh.swift` refreshes apps without the install screen (`InstallController.refreshQuietly`): ones that expire within two days, and ones whose signing certificate is gone. It runs when AltLoad comes to the front (at most every six hours, unless something expires within a day) and in a `BGProcessingTask` (`<bundle id>.autorefresh`) that iOS starts when it sees fit, usually overnight. Each refresh uses the Apple ID that signed the app and needs its password saved and LocalDevVPN on. A prompt (two-factor, or a full set of certificates) is declined rather than shown, and the user gets a notification saying what to do; so do a closed VPN and a missing password, once per app until it's refreshed.

A refresh is also how a revoked certificate is replaced: `sign_app` looks for the account's certificate (`CertificateIdentity::retrieve`), requests a new one when it's gone, and always downloads a new provisioning profile. To notice a revocation, AltLoad keeps the developer certificates from each app's profile (`DeveloperCertificates`, returned by the core as `certificates`) and, once a day per Apple ID, lists the account's active certificates through the developer services AltLoad signs with (`CertificateCheck.swift`, the core's `overview`). An app whose profile names a certificate that's no longer active is signed again. It doesn't use Apple's OCSP servers, which DNS profiles often block. The new profile only lists active certificates, so this happens once.

## Update notice

`UpdateChecker` asks GitHub for AltLoad's latest release when the app opens or returns to the foreground, at most every 6 hours. If it's newer than the running version, an alert links to the install site. **Later** hides that version until a newer one is out.

## FFI surface

```c
// pairing (core/src/lib.rs)
int32_t altload_run_host(...);                         // host mode, device pairs to us
// install (core/src/install/)
AltLoadInstallSession *altload_install_session_new(void);
int32_t altload_install_session_run(session, config, progress_cb, prompt_cb, ctx, out); // blocking
int32_t altload_install_session_respond(session, response);                             // answer a prompt
void    altload_install_session_cancel(session);
```

`altload_install_session_run` runs on a background queue. Callbacks arrive on that thread, and Swift hops to the main actor.

## Known limitations

- On-device pairing needs iOS 27+ (RPPairing host mode) and Wi-Fi. iOS 18–26 needs a pairing file made on a computer. LocalDevVPN has to be on during installs.
- The widget extension takes a second App ID when AltLoad itself is sideloaded with a free Apple ID.
- Free Apple IDs are limited to 3 sideloaded apps, 10 App IDs per 7 days, and 7-day signatures.
- The anisette server is a third party. Self-host one if you'd rather not depend on it.

## On-device AltServer

`ios/App/Core/AltServer/AltServerHost.swift` makes AltLoad the AltServer for the AltStore on the same iPhone.

- **Discovery, on-device link (preferred).** AltStore's `FindServerOperation` posts the Darwin notification `io.altstore.Request.WiredServerConnectionAvailable` and waits one second for `io.altstore.Response.WiredServerConnectionAvailable`. AltLoad answers, so AltStore treats it as a USB-connected AltServer, posts `io.altstore.Request.WiredServerConnectionStart` and listens on `127.0.0.1:28151`. AltLoad connects there and becomes the server side of that connection.
- **Discovery, Wi-Fi.** A Bonjour `_altserver._tcp` service with TXT `serverID` = the ALTServerID AltLoad wrote into AltStore, which makes it AltStore's preferred network server.
- **Protocol.** AltServer's: an Int32 little-endian length, then JSON; one request per connection. Handled: `AnisetteDataRequest` (v1 headers from the anisette server, mapped to `ALTAnisetteData`), `PrepareAppRequest` + raw app data + `BeginInstallationRequest` (with `InstallationProgressResponse` updates), `InstallProvisioningProfilesRequest`, `RemoveProvisioningProfilesRequest`, `RemoveAppRequest`. JIT (`EnableUnsignedCodeExecutionRequest`) returns an error.
- **Device work.** `altload_device_run` (`core/src/install/device.rs`) opens the same LocalDevVPN tunnel and uses installation_proxy + AFC (via isideload's `install_app_rsd`) and misagent. Profile handling mirrors AltServer's `ALTDeviceManager`: free profiles are taken off before an install and the active ones put back after, so a free Apple ID stays under 3 active apps. AltLoad's own profile is always protected.
- **Background.** iOS suspends AltLoad in the background, so AltServer only answers while AltLoad is open or kept awake (silent audio, Tools › AltServer).

## Pairing file into apps

`place_file` uses house_arrest (`VendDocuments`, falling back to `VendContainer`) to write this iPhone's pairing file into another app, as an XML plist with the device's `UDID` added.

| App | Paths |
|---|---|
| SideStore | `Documents/ALTPairingFile.mobiledevicepairing`, `Documents/PairingFile_RemoteRP.plist`, plus `Documents/PairingFile_Lockdown.plist` when the file has a complete lockdown record |
| SideStore + LiveContainer | The same files under `Documents/SideStore/Documents/` |
| Husk, Madeira | `Documents/StikJIT/pairingFile.plist` |
| AltStore, AltStore Beta | `Documents/ALTPairingFile.plist`, with only the Remote Pairing keys (`identifier`, `public_key`, `private_key`, `alt_irk`) |
| StikDebug and other idevice apps | `Documents/rp_pairing_file.plist` |

Newer SideStore builds also need `isPairingReset = false` and `activePairingProtocol` in their preferences, so `merge_plist` sets them in `Library/Preferences/<bundle id>.plist`, or `Documents/SideStore/Library/Preferences/com.SideStore.SideStore.plist` inside LiveContainer. iOS caches an app's settings once it has run, so these take effect after a reinstall or restart.

After installing SideStore, SideStore + LiveContainer, Husk, Madeira, AltStore or AltStore Beta, AltLoad does this automatically. Madeira is recognised by the store that was picked, not by its bundle ID, because it has its own JIT helper that reads the same path as Husk's.

UTM and MeloNX get no pairing file. They need a debugger's help to run, so the success screen offers **Open with JIT** (see below).

### AltStore without AltServer

AltStore 2.3.1 and later can install and refresh apps by themselves ("Remote AltServer"). They need this iPhone's pairing file for that, and look for it at `Documents/ALTPairingFile.plist` in their own container, where AltServer leaves it after an install (altstoreio/AltStore 5811912). When the user opens AltStore › Settings › Set up Remote AltServer, AltStore moves the file into its Keychain, skips its own pairing step, and from then on doesn't need AltServer or AltLoad running. AltLoad writes the same file after every AltStore install or refresh. AltStore 2.3.0 read it from its bundle instead, sealed as `ALTPairingFile.dat` (see step 5), so AltLoad writes that too. Until the user runs the setup, AltLoad keeps working as AltStore's AltServer.


## JIT and location

Both need the Developer Disk Image, which iOS 27 takes as a personalised cryptex. `ios/App/Core/Device/DeveloperDiskImage.swift` downloads it once (from [doronz88/DeveloperDiskImage](https://github.com/doronz88/DeveloperDiskImage)); `ensure_ddi` in `core/src/install/device.rs` asks cryptexd whether it's installed and, if not, personalises it through TSS and installs it.

- **JIT** (a JIT session, `core/src/install/jit.rs` and `ios/App/Core/JIT/`): DVT process control launches the app suspended (or the session takes a running process by pid), and a script attaches debugserver with `vAttach;<pid>`. The attach marks the process as debugged, so it can map executable memory until it exits. Only development-signed apps (`get-task-allow`) can be attached.
- **Location** (`simulate_location`): DVT location simulation. The device keeps a simulated location only while the connection is open, so the op holds the tunnel and re-sends the coordinate every few seconds until `altload_location_stop`. It runs on its own queue so AltServer's device ops aren't blocked.

### JIT sessions and scripts

Being attached once is enough for most apps. Where iOS checks each executable page it isn't, so emulators ask the attached debugger for help by stopping on a `brk` instruction with the request in their registers. What to answer is up to a JavaScript script, run with JavaScriptCore on a thread of its own (`JITSession.swift`), against a session the Rust core holds open:

| Function | Rust (`jit.rs`) | What it does |
|---|---|---|
| `send_command(packet)` | `altload_debug_send` | One GDB remote packet, returns the reply |
| `continue_for(resume, ms)` | `altload_debug_continue` | Resumes with `resume` (`c`, or `vCont;S…` to hand back a signal), returns the stop reply, or `""` when the app stayed quiet that long; it is then paused |
| `prepare_memory_region(address, length)` | `altload_debug_prepare` | Writes one byte into each 16 KiB page through debugserver, in batches of 128 packets. Over 16 GiB is refused |
| `get_pid()`, `get_bundle_id()`, `log(text)` | | The session's process and app, and a line for the JIT screen |

AltLoad's own script (`ios/App/Resources/JIT/altload-jit.js`) answers:

| Request | Registers | What it does |
|---|---|---|
| `brk #0xf00d` | `x16 = 0` | Detaches: the app is done asking |
| `brk #0xf00d` | `x16 = 1`, `x0` = address, `x1` = length | Prepares the region. With address 0 it allocates the region first (`_M<len>,rx`) and returns the address in `x0` |
| `brk #0xf00d` | `x16 = 2`, `x0` = text, `x1` = length | Runs the script the app sent, in the same context, so it can add handlers to `commands` (by `x16`) or `legacyCommands` (by `brk` immediate) |
| `brk #0x68` | as `x16 = 2` | The older form of the same |
| `brk #0x69` | `x0` = address, `x1` = length | The older form of a JIT request, used by UTM and others: prepares the region once, then detaches |

Any other stop is not a request: the app gets its signal back as it would without a debugger, and an unknown `brk` isn't stepped over. The script detaches when the app asks, when it exits, or when it goes quiet: 8 seconds with no first request (the app only needed the attach), or 5 minutes without another one. `scripts/test-jit-script.js` runs it against a fake debugserver (`node scripts/test-jit-script.js`).

Users can import their own `.js` scripts and pick one per app (Tools › JIT › Scripts, `JITScripts.swift`). Sessions also start from links, `altload://enable-jit?bundle-id=…` (with `pid=`, `script-name=` or `script-data=` in Base64), which AltLoad always confirms first, and from the Shortcuts action Enable JIT (`EnableJITIntent.swift`). One session runs at a time. While it runs, AltLoad keeps itself awake in the background with silent audio, since the app it serves is in front.

The request protocol and the script functions are the ones the [StikDebug](https://github.com/StikDebug/StikDebug) project uses, so scripts written for it run here. AltLoad's script and its debugger side are independent implementations; no StikDebug code is used.

> [!WARNING]
> AltLoad's JIT script is tested against a fake debugserver, but JIT sessions have **not been tested on a device yet**.

## Installing AltLoad with an Apple ID

The install page's **Apple ID Install** route signs AltLoad with the user's own Apple ID, on the iPhone, before AltLoad is there to do it. It runs on altpair, two tools written for AltLoad:

- **`altpair.wasm`** (`altpair/pair/`, built as `altpair.wasm`) runs in the rootshell app and pairs the iPhone with itself. It is written against the WASM socket interface documented in rootshell's MIT repository. It adds a **Pair with AltLoad** row to Settings › Privacy & Security › Developer Mode.
- **`altpair`** (`altpair/installer/`) runs in the Open Minis app. It signs AltLoad with the user's Apple ID and installs it over the LocalDevVPN tunnel, using AltLoad's own Rust core (`core/`).

The steps:

1. In rootshell, the user downloads `altpair.wasm` from the latest release and runs it, then taps **Pair with AltLoad** in Settings.
2. `altpair.wasm` hands the pairing file to `altpair` on the same iPhone over the loopback address. The hand-off is protected by a 6-digit transfer code that `altpair.wasm` shows and `altpair` asks for.
3. In Open Minis's terminal, with LocalDevVPN connected, the user runs `site/install.sh`. It downloads the `altpair-aarch64` binary from AltLoad's latest GitHub release, checks its SHA-256 and runs it.
4. `altpair` asks for the transfer code and the Apple ID, signs AltLoad and installs it. The password is typed into `altpair` on the iPhone and goes to Apple only.

`.github/workflows/altpair.yml` builds both tools and attaches them to each AltLoad release.

> [!WARNING]
> altpair has **not been tested on a device yet**.

## Entitlements

Tools › Entitlements lists App Store Connect capabilities (free-team ones and paid-only ones). Before `sign_app`, `enable_capabilities` in `core/src/install/bundle.rs` finds or registers the App ID `sign_app` will use (`<bundle id>.<team id>`) and enables each capability with the same JSON:API call isideload uses for Increased Memory Limit. The provisioning profile Apple then issues carries the entitlements, and the signature uses the profile's entitlements.
