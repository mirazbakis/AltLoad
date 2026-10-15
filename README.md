<p align="center">
  <img src="docs/assets/logo.svg" width="128" height="128" alt="AltLoad logo">
</p>

<h1 align="center">AltLoad</h1>

<p align="center"><b>Install AltStore, SideStore and LiveContainer completely on device.</b></p>

<p align="center">
  <a href="https://github.com/mirazbakis/AltLoad/releases/latest"><b>Download</b></a> ·
  <a href="https://mirazbakis.github.io/AltLoad.html">Website</a> ·
  <a href="docs/HOW-IT-WORKS.md">How it works</a> ·
  <a href="https://github.com/mirazbakis/AltLoad/issues">Issues</a>
</p>

Normally, installing [AltStore](https://altstore.io) needs AltServer running on a Mac or PC. AltLoad does that job on the iPhone itself: it pairs the iPhone with itself, signs AltStore with **your own Apple ID** and installs it. When the 7-day signature is about to run out, you refresh it in AltLoad with one tap.

AltLoad simulates AltServer using some advanced tools introduced in the **iOS 27** update.

> [!WARNING]
> AltLoad is still in active development. The features and the design are not final; and is subject to change. If you find bugs, please report them as specified in SECURITY.md, not in a public issue.

> AltLoad is an independent project. It isn't affiliated with AltStore, Riley Testut or Apple.

## Features

- **AltStore or AltStore Beta**, always the newest build from AltStore's official source.
- **SideStore and SideStore + LiveContainer**, stable or nightly. If SideStore's repository is down, AltLoad falls back to a mirror, GitHub releases, a known-good build or its own saved copy.
- **Knows what's really installed.** AltLoad checks the iPhone for AltStore instead of trusting its own records, so a deleted or separately installed AltStore shows up correctly.
- **Built-in AltServer**, on by default and kept alive in the background, so AltStore can install and refresh apps without a computer.
- **Entitlements.** Switch on capabilities such as Increased Memory Limit for AltStore's signature. Free-account and paid-account capabilities are listed separately.
- **JIT.** Open emulators and other JIT apps with JIT enabled.
- **Location.** Make the iPhone report any place on the map, for every app.
- **Refresh reminders** the day before a free signature expires.
- **Private by design.** Your password goes only to Apple. No analytics, no tracking.

## What you need

- An iPhone or iPad on **iOS 27 or later**, with **Developer Mode** on (**Settings › Privacy & Security › Developer Mode**).
- **[LocalDevVPN](https://apps.apple.com/app/id6755608044)**, free on the App Store. It lets the iPhone connect to itself.
- An **Apple ID**. A free one works: apps then last 7 days, with up to 3 sideloaded apps at once.
- **Wi-Fi**, for the one-time pairing step.

## Install AltLoad

1. Download **`AltLoad.ipa`** from the [**latest release**](https://github.com/mirazbakis/AltLoad/releases/latest). The newest build of `main` is also available as [**Nightly**](https://github.com/mirazbakis/AltLoad/releases/tag/nightly), but it's untested.
2. Sideload it once with any signing tool you already use.
3. If iOS says the developer isn't trusted, go to **Settings › General › VPN & Device Management** and trust your Apple ID.

## Use it

1. **Pair (once).** **Tools › Pair › Pair This iPhone or iPad**, then in **Settings › Privacy & Security › Developer Mode** tap **Pair with AltLoad** and enter the code.
2. **LocalDevVPN (once).** Install it and open it once so it adds its VPN configuration.
3. **Install AltStore.** On the **Install** tab, pick **Release** or **Beta**, tap **Install**, sign in with your Apple ID and enter the two-factor code.
4. **Use AltStore normally.** It finds AltLoad's AltServer on the same iPhone. LocalDevVPN has to be on.
5. **Refresh weekly** in AltStore or AltLoad. AltLoad reminds you the day before.

| Tab | What's there |
|---|---|
| **Install** | Release / Beta picker, what's on the iPhone, install, update or refresh, setup checklist. |
| **Tools** | AltServer · JIT · Location · Pair · Pairing File to Apps · Library · Certificates |
| **About** | Version, special thanks, legal links. The gear at the top right of every tab opens **Settings**: Apple ID (with a sign-in check), entitlements, anisette, LocalDevVPN, sources, background keep-alive. |

## Repository layout

```
App/
  AltLoadApp.swift        entry point and tab bar
  Features/
    Install/              Install tab, install flow, store catalog, entitlements
    Tools/                AltServer, JIT, Location, Pair, Library, Certificates
    Settings/             Settings and anisette servers
  Services/               device link, AltServer host, pairing, Keychain, LocalDevVPN, DDI
  UI/                     theme, background and shared glass components
  Resources/              Info.plist and the app icon
rust/                     Rust core: pairing, tunnel, signing and device ops (C FFI)
  include/altload.h       the FFI header Swift imports as AltLoadFFI
scripts/build-rust.sh     builds rust/ into AltLoadFFI.xcframework
docs/                     how it works, logo
project.yml               XcodeGen project definition
```

## Build it yourself

**On GitHub (no Mac needed):** fork the repository, enable Actions in your fork, run **Build IPA**, and download `AltLoad.ipa` from the run's artifacts. Pushing a `v*` tag publishes a release.

**On a Mac** with Xcode 27, [Homebrew](https://brew.sh) and [Rust](https://rustup.rs):

```sh
brew install xcodegen
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
./scripts/build-rust.sh   # Rust core → AltLoadFFI.xcframework
xcodegen generate         # project.yml → AltLoad.xcodeproj
open AltLoad.xcodeproj
```

New Swift files anywhere under `App/` are picked up after `xcodegen generate`.

## How it works

[`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) has the details. In short:

1. **Pairing.** iOS 27 can pair wirelessly with a host it finds on the network. AltLoad is that host, so the iPhone pairs with AltLoad the way it pairs with a Mac.
2. **Reaching itself.** LocalDevVPN routes `10.7.0.1` back into the phone, so AltLoad can open the same secure tunnel Xcode uses.
3. **Apple ID.** AltLoad signs in to Apple's developer services, registers the iPhone, gets a development certificate and creates the App IDs and profiles AltStore needs.
4. **Signing and installing.** It adds what AltServer would write into AltStore, signs it and installs it through the tunnel.

## Privacy and security

- **Your Apple ID password goes only to Apple.** If you choose *Remember password*, it's kept in the iPhone's Keychain, readable only while unlocked, and never synced.
- **Anisette.** Apple requires device-identity headers ("anisette") to sign in. AltLoad gets them from a public anisette server (picked automatically by default), which never sees your password. You can pick another in Settings.
- **Pairing files** give access to your device. Only share them with apps you trust.
- Security issues: see [SECURITY.md](SECURITY.md). Please don't report them in a public issue.

## FAQ

**Sign-in fails.** Since 12 October 2026 Apple refuses sign-in data from many anisette servers. Keep **Settings › Anisette** on **Automatic**: AltLoad checks which servers answer and moves on to the next when Apple refuses one. If it still fails, tap **Reset Anisette Data** and try again later. **Settings › Apple ID › Sign In** checks your account without installing anything.

**It says the certificate limit is reached.** Free Apple IDs can only have a few development certificates. AltLoad asks which one to revoke. Apps signed with it elsewhere stop opening until they're signed again.

**An entitlement makes the install fail.** Paid-only capabilities can't be enabled on a free Apple ID. Turn it off in **Settings › Entitlements**.

**It can't connect to the iPhone.** Check that LocalDevVPN is connected, Developer Mode is on, and this iPhone is paired in **Tools › Pair**. If it still fails, pair again.

## Special thanks

- [**jkcoxson**](https://github.com/jkcoxson) for [idevice](https://github.com/jkcoxson/idevice) and [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN), which make talking to the iPhone from the iPhone possible.
- [**nab138**](https://github.com/nab138) for [isideload](https://github.com/nab138/isideload): Apple ID sign-in, developer services and code signing.
- [**StephenDev0**](https://github.com/StephenDev0) for [StikPair](https://github.com/StephenDev0/StikPair), the pairing flow AltLoad is based on, and StikDebug.
- [**Riley Testut**](https://github.com/rileytestut) and the AltStore team for [AltStore](https://altstore.io). AltLoad downloads it from its official source and doesn't redistribute it.

## License

**Copyright (c) 2026 mirazbakis. All rights reserved.** See the [AltLoad License](LICENSE) for what you may do (personal use, building it yourself, contributing). Parts derived from StikPair and idevice stay under their own licenses, listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Using AltLoad means you agree to the [Terms of Service](https://mirazbakis.github.io/terms.html).
