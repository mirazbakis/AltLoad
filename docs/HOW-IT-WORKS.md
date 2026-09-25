# How AltLoad installs AltStore on-device

This document describes each stage of the install, with the protocol, the library, and the file in this repo that does the work.

## Components

| Layer | What | Where |
|---|---|---|
| UI | SwiftUI, iOS 27 Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` buttons, `glassEffectUnion`), `TabView` with `Tab`, aurora `MeshGradient` background | `App/*.swift` |
| Orchestration | `InstallController` (download, discovery, FFI session, prompts, expiry reminder), `PairingController` (pairing host) | `App/InstallController.swift`, `App/PairingController.swift` |
| FFI | A C header plus a Rust static library packaged as `AltLoadFFI.xcframework` | `rust/include/altload.h`, `rust/src/*.rs` |
| Device protocols | [`idevice`](https://github.com/jkcoxson/idevice) (git `d32c818`): `remote_pairing`, `rsd`, `tunnel_tcp_stack`, `afc`, `installation_proxy` | `rust/src/lib.rs`, `rust/src/install.rs` |
| Apple ID + signing | [`isideload`](https://github.com/nab138/isideload) 0.4 (uses idevice, a fork of apple-codesign, rcgen, keyring) | `rust/src/install.rs` |
| Discovery | `NetServiceBrowser` / `NetService` (mDNSResponder), so no multicast entitlement is needed | `App/SelfDiscovery.swift`, `App/AppleTVDiscovery.swift` |
| Catalog | AltStore source JSON (`https://apps.altstore.io`), `URLSession` download with progress, IPA cache in Application Support | `App/AltStoreCatalog.swift` |
| Secrets | Keychain (`kSecClassGenericPassword`, `WhenUnlockedThisDeviceOnly`) for the Apple ID password. isideload's `KeyringStorage` for the certificate key and anisette state | `App/AppleIDStore.swift` |

## 1. Pairing (the Pair tab)

iOS 27 lets a device pair wirelessly with a host that advertises `_remotepairing-pairable-host._tcp`.

1. `altload_run_host` binds a TCP listener and generates a host identity (`RpPairingFile::generate`, `PairableHostInfo::generate`). It then calls back into Swift with the service ID, port and TXT records.
2. Swift publishes those records with `NetService`, so the Bonjour registration goes through mDNSResponder and only needs the Local Network permission.
3. The user taps **Settings › Privacy & Security › Developer Mode › Pair with AltLoad**. The device connects, and `PairableHost::accept` runs SRP pair-setup. The PIN goes to the UI and to a Live Activity.
4. The resulting **RPPairing file** is moved to `Documents/Pairings/<Device>-<id>/rp_pairing_file.plist`. It holds AltLoad's Ed25519 identity, the device's public key and its `altIRK`.

`BGContinuedProcessingTask` keeps the listener alive while the user is in Settings. Silent audio or location can do the same as optional fallbacks.

Apple TV uses the reverse direction: AltLoad is the client for the TV's `_remotepairing-manual-pairing._tcp` service, via `RemotePairingClient::connect`.

## 2. Tunnel to this iPhone (Install, step 1)

AltLoad talks to the phone it's running on, the same way a Mac does over Wi-Fi.

1. **Discover:** `SelfDiscovery` browses `_remotepairing._tcp` for about 4 seconds and passes each `(host, port, identifier, authTag)` to Rust.
2. **Match:** Rust checks `PeerDevice::validate_auth_tag(altIRK, identifier, authTag)`, which is SipHash-2-4 of the identifier keyed by the device's `altIRK`. Endpoints that verify are tried first.
3. **Pair-verify:** `RemotePairingClient::attempt_pair_verify` and `validate_pairing` run with the saved file. AltLoad never falls back to a new pair-setup here. If verification fails, the user is sent back to the Pair tab.
4. **Tunnel:** `create_tcp_listener` asks remotepairingd for a tunnel port. AltLoad connects to it and runs `connect_tls_psk_tunnel_native`, a TLS 1.2 PSK tunnel keyed with the pair-verify session key. This is the CoreDevice "CDTunnel" handshake, which returns client and server IPv6 addresses, the MTU and the RSD port.
5. **User-space TCP:** the tunnel carries raw IPv6 packets, so `idevice::tcp::adapter::Adapter` (jktcp) runs a TCP stack over it. That means no VPN or `NEPacketTunnelProvider` is needed.
6. **RSD:** `RsdHandshake` lists the device's services and properties. AltLoad reads `UniqueDeviceID` from those properties.

## 3. Apple ID sign-in (Install, step 2)

This comes from isideload's `AppleAccount`.

- **Anisette:** Apple's servers require `X-Apple-I-MD`, `X-Apple-I-MD-M` and related machine-identity headers. `RemoteV3AnisetteProvider` provisions a virtual machine identity through an anisette v3 server over a websocket, then caches the state. The default is `https://ani.stikstore.app`, and you can change it in Settings.
- **GrandSlam (GSA):** the SRP-6a login to `gsa.apple.com`, which never sends the password in plaintext.
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
| `ALTCertificateID` + `ALTCertificate.p12` | isideload (`apply_special_app_behavior`) | The signing identity AltStore uses to re-sign the apps *it* installs |
| `ALTAppGroups` | isideload | The registered app group |

isideload then re-signs every bundle with the matching profile's entitlements, using `apple-codesign-quick`.

## 6. Install (Install, step 5)

`isideload::sideload::install::install_app_rsd` uses the same tunnel:

1. `AfcClient::connect_rsd` uploads the signed `.app` folder to `PublicStaging/` in 1 MB chunks. This covers 0–70% of the progress bar.
2. `InstallationProxyClient::connect_rsd` → `install_with_callback(PackageType: Developer)`. This covers 70–100%.

Afterwards AltLoad reads `CFBundleIdentifier`, the version, `TeamIdentifier` and `ExpirationDate` from the embedded profile. It stores them and schedules a reminder for 24 hours before expiry.

## Refreshing

A free-account profile lasts 7 days. AltStore's built-in refresh expects to find AltServer on the network, which doesn't exist in this setup. Tapping **Refresh AltStore** in AltLoad runs the same pipeline with the cached IPA. Because the bundle ID and team are the same, iOS treats it as an update, and AltStore's data and the apps it manages are kept.

## FFI surface

```c
// pairing (rust/src/lib.rs)
int32_t altload_run_host(...);                         // host mode, device pairs to us
AltLoadAppleTvSession *altload_apple_tv_session_new(void);
int32_t altload_apple_tv_session_run(...);             // client mode, Apple TV
// install (rust/src/install.rs)
AltLoadInstallSession *altload_install_session_new(void);
int32_t altload_install_session_run(session, config, progress_cb, prompt_cb, ctx, out); // blocking
int32_t altload_install_session_respond(session, response);                             // answer a prompt
void    altload_install_session_cancel(session);
```

`altload_install_session_run` runs on a background queue. Callbacks arrive on that thread, and Swift hops to the main actor.

## Known limitations

- Needs iOS 27+ (RPPairing host mode) and Wi-Fi, because the tunnel goes to the device's own LAN address.
- Free Apple IDs are limited to 3 sideloaded apps, 10 App IDs per 7 days, and 7-day signatures.
- The anisette server is a third party. Self-host one if you'd rather not depend on it.
- The install pipeline hasn't been compiled or tested on a device yet. The first build may need small API fixes against the pinned idevice and isideload versions.
