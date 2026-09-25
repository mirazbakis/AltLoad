# AltLoad

**Install AltStore on your iPhone using only the iPhone.** AltLoad pairs your iPhone with itself, signs AltStore with your Apple ID, and installs it on the same iPhone. A computer normally does this job with AltServer. The only other thing you need is [LocalDevVPN](https://apps.apple.com/app/id6755608044), a free loopback VPN from the App Store.

It has a dark aurora theme with Liquid Glass, built in SwiftUI for iOS 27.

> AltLoad is an independent project. It is not affiliated with AltStore, Riley Testut, SideStore or Apple.

## Features

- **Install tab:** fetches the newest AltStore from the official source (`https://apps.altstore.io`). It then downloads, signs and installs AltStore on this iPhone. A single tap refreshes or updates it later. You can also install from an `.ipa` file.
- **Pair tab:** creates an iOS 27 wireless pairing file on the device. It uses the same mechanism as [StikPair](https://github.com/StephenDev0/StikPair), and works for this iPhone, another iPhone or iPad, or an Apple TV.
- **Library tab:** shows saved pairing files (also visible in the Files app), lets you choose which file is *This iPhone*, import files, and see AltStore's expiry.
- **Settings tab:** Apple ID, anisette server, AltStore source and background keep-alive options.
- A reminder notification the day before a 7-day free-account signature expires.
- Two-factor authentication (trusted device or SMS) and a certificate-limit picker, both handled in the app.

## How it works

There's a short version below. [`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) covers every protocol and library in detail.

```
┌──────────── AltLoad (this iPhone) ─────────────┐
│ SwiftUI UI ─► InstallController ─► Rust FFI    │
│                                   │            │
│  idevice ─ RPPairing ─► TLS-PSK tunnel ─► RSD  │──► LocalDevVPN (10.7.0.1)
│                                   │            │    ↺ back into this iPhone's
│                                   │            │    remotepairingd / AFC /
│  isideload ─ Apple ID + dev portal + codesign  │    installation_proxy
└────────────────────────────────────────────────┘──► Apple (GSA, developer services)
```

1. **Pair:** AltLoad advertises itself as a pairable host (`_remotepairing-pairable-host._tcp`). In **Settings › Privacy & Security › Developer Mode › Pair with AltLoad** you enter the PIN, and this produces an RPPairing file.
2. **Tunnel:** AltLoad connects to `10.7.0.1:49152`. LocalDevVPN swaps the source and destination addresses of each packet and sends it back into the phone, so the connection reaches the iPhone's own RemotePairing service as if it came from another machine. StikDebug uses the same approach. AltLoad then pair-verifies and opens a TLS-PSK CoreDevice tunnel with a user-space TCP stack, followed by the RemoteServiceDiscovery handshake.
3. **Sign in:** AltLoad signs in to your Apple ID with GrandSlam SRP and anisette headers. It handles 2FA.
4. **Provision:** AltLoad registers this iPhone's UDID and creates or reuses a development certificate. It then registers App IDs and the app group, and downloads provisioning profiles.
5. **Prepare and sign:** AltLoad writes `ALTDeviceID`, `ALTServerID`, `ALTCertificate.p12`, `ALTCertificateID` and `ALTAppGroups` into AltStore, as AltServer would. It then re-signs the app and its extensions.
6. **Install:** AltLoad uploads the app to `PublicStaging` over AFC, and `installation_proxy` installs it. Both steps go through the tunnel.

## Requirements

- An iPhone or iPad on **iOS 27 or later** with **Developer Mode** on. You need Wi-Fi for pairing.
- **[LocalDevVPN](https://apps.apple.com/app/id6755608044)**, free on the App Store, switched on during installs. AltLoad can turn it on for you with `localdevvpn://enable?scheme=altload`.
- An Apple ID. A free account works, and apps then last 7 days, with 3 active apps and 10 App IDs per week.
- To build: Xcode 27, Rust with `aarch64-apple-ios` + `aarch64-apple-ios-sim`, and `xcodegen`.

## Build

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
./build-rust.sh      # builds rust/ -> AltLoadFFI.xcframework
xcodegen generate    # generates AltLoad.xcodeproj from project.yml
open AltLoad.xcodeproj
```

Set your signing team, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to your own, and run the app on a device. CI (`.github/workflows/build.yml`) builds an unsigned IPA on every push, and attaches it to releases when you push a `v*` tag.

> **Status:** early. The on-device install pipeline is written but hasn't been built or tested on hardware yet. Expect the first build to need small fixes.

## First run

1. **Pair tab:** tap **Pair This iPhone or iPad**, then follow the steps. Settings › Privacy & Security › Developer Mode › **Pair with AltLoad**, then enter the code.
2. Install **LocalDevVPN** from the App Store and open it once to add its VPN configuration.
3. **Install tab:** tap **Install AltStore**, sign in, and approve 2FA. If the VPN is off, AltLoad asks you to turn it on and continues automatically when you come back.
4. The first time you open AltStore, go to **Settings › General › VPN & Device Management**, tap your Apple ID and choose **Trust**.
5. Within 7 days, come back to AltLoad and tap **Refresh AltStore**. AltStore's own refresh expects AltServer on a computer, so on this setup AltLoad does the refreshing.

## Privacy and security

- Your Apple ID password is sent only to Apple. If you choose to remember it, it's stored in the Keychain as `WhenUnlockedThisDeviceOnly`, which never syncs.
- Apple requires *anisette* headers, a machine identity, to sign in. AltLoad fetches them from a remote anisette server, SideStore's `https://ani.sidestore.io` by default. In Settings you can pick another server from SideStore's community list or enter your own. The anisette server never sees your password.
- The development certificate's private key and the anisette state are stored in the Keychain.
- Pairing files grant access to your device, so only share them with tools you trust.

## Credits

- [idevice](https://github.com/jkcoxson/idevice) by Jackson Coxson (MIT): RPPairing, the tunnel, RSD, AFC and installation_proxy.
- [isideload](https://github.com/nab138/isideload) by nab138 (MIT): Apple ID authentication, developer services and signing. It builds on work from Sideloader, Impactor and apple-platform-rs.
- [StikPair](https://github.com/StephenDev0/StikPair) by StephenDev0: the on-device pairing flow AltLoad is based on.
- [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN) by jkcoxson and Stossy11: the loopback VPN that lets the iPhone reach itself.
- [AltStore](https://altstore.io) by Riley Testut and Shane Gill: the app AltLoad installs. AltLoad downloads it from the official source at install time and doesn't redistribute it.

## License

AltLoad keeps StikPair's **non-commercial MIT** license (see [LICENSE](LICENSE)): Copyright (c) 2026 StephenDev0. It is free for personal and non-commercial use. Commercial use requires the original author's written permission.
