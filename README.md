<img src="docs/assets/logo.svg" align="right" width="112" height="112" alt="AltLoad logo">

# AltLoad

> **Install AltStore Classic on-device.**

[![Stable](https://img.shields.io/github/v/release/mirazbakis/AltLoad?label=stable&style=flat-square&color=3c7ae3)](https://github.com/mirazbakis/AltLoad/releases/latest)
[![Beta](https://img.shields.io/badge/beta-1.2.0%20beta%201-176b4a?style=flat-square)](https://github.com/mirazbakis/AltLoad/releases/tag/v1.2.0-beta.1)
[![iOS](https://img.shields.io/badge/iOS-18%2B-0a101e?style=flat-square&logo=apple)](#which-ios-versions)

AltStore Classic, SideStore and LiveContainer, signed with your own Apple ID and installed from the iPhone that will run them. AltLoad stands in for the computer you'd normally need: it pairs the iPhone with itself, signs the store and installs it, then keeps an AltServer running on the phone so AltStore can refresh your apps on its own.

**[Website](https://mirazbakis.github.io/AltLoad.html)** · **[Releases](https://github.com/mirazbakis/AltLoad/releases)** · **[How it works](docs/HOW-IT-WORKS.md)**

---

## Quick start

You'll need Developer Mode turned on, [LocalDevVPN](https://apps.apple.com/app/id6755608044) from the App Store, an Apple ID (a free one is fine) and Wi-Fi for the first pairing.

```
1  Sideload AltLoad.ipa once        →  any signing tool you already have
2  Tools › Pair                      →  the code appears in your Dynamic Island
3  Settings › Developer Mode         →  Pair with AltLoad, type the code
4  Turn on LocalDevVPN
5  Install tab › AltStore › Install  →  sign in with your Apple ID
```

That's it. AltStore finds AltLoad's AltServer on the same iPhone, and AltLoad reminds you the day before your apps need their weekly refresh.

## Which iOS versions?

- **iOS 27 and newer:** everything, including pairing on the device itself.
- **iOS 18 to 26** (from 1.2.0 beta 1): these versions can't pair with an app on the same device, so you make the pairing file on a computer once, with [iloader](https://github.com/nab138/iloader) or [idevice_pair](https://github.com/jkcoxson/idevice_pair), then bring it in through **Tools › Pair › Import Pairing File**. Everything after that is the same.
- **iOS 17 and older:** not supported.

## What's inside

| | |
| :-- | :-- |
| **Stores** | AltStore Classic and Beta, SideStore, SideStore + LiveContainer, each stable or nightly |
| **AltServer** | Runs on the iPhone and stays alive in the background |
| **Dynamic Island** | Shows the pairing code while you're in Settings, or on the Lock Screen without an island |
| **Pairing files** | Made on the device, imported from a computer, or handed to SideStore, StikDebug and others |
| **Sign-in** | Moves between anisette servers until Apple accepts one |
| **When servers are down** | Mirrors, GitHub releases, a known-good build, a saved copy, or any IPA from Files |
| **Tools** | Entitlements, JIT, location simulation, certificate management |

## Your Apple ID

AltLoad has no server of its own, no account to make and no analytics. Your password is sent to Apple and nowhere else. If you turn on *Remember password*, it lives in this iPhone's Keychain and never syncs. The anisette servers AltLoad uses for sign-in never see it.

That's only true of the real AltLoad, so get it from [the website](https://mirazbakis.github.io/AltLoad.html) or [this repository's releases](https://github.com/mirazbakis/AltLoad/releases). An IPA passed around elsewhere could be a modified build that keeps your password, and the [license](LICENSE.md) doesn't allow re-uploading AltLoad anyway.

Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Troubleshooting

<details>
<summary><b>Sign-in keeps failing</b></summary>

Apple has been refusing many public anisette servers since October 2026. Keep **Settings › Anisette** on **Automatic**, and if it still fails, tap **Reset Anisette Data** and wait a few minutes. **Settings › Apple ID › Sign In** tests your account without installing anything.
</details>

<details>
<summary><b>SideStore won't download</b></summary>

AltLoad already falls back through SideStore's mirror, GitHub and a known-good build. If every one of them is down, grab a SideStore IPA another way and use **Install IPA from Files** in the Install tab's **…** menu.
</details>

<details>
<summary><b>"Can't connect to this iPhone"</b></summary>

LocalDevVPN has to be connected, Developer Mode on, and the device listed in **Tools › Pair**. If all three are true, pair again.
</details>

<details>
<summary><b>"Certificate limit reached"</b></summary>

Free Apple IDs only get a few development certificates. AltLoad asks which one to revoke; apps signed with it elsewhere stop opening until they're re-signed.
</details>

<details>
<summary><b>The beta uses 2 App IDs</b></summary>

The Dynamic Island code is drawn by a small widget extension inside AltLoad, and every extension needs its own App ID when sideloaded with a free account.
</details>

## For developers

AltLoad is a SwiftUI app over a Rust core. The Rust side pairs, opens the tunnel through LocalDevVPN, signs in to Apple, signs and installs; Swift handles the screens, the on-device AltServer and the Live Activity. [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) walks through every step.

```
App/        SwiftUI app: install flow, pairing, AltServer, screens
Widgets/    Live Activity extension (Dynamic Island, Lock Screen)
Shared/     code compiled into both of the above
rust/       Rust core, exposed to Swift through rust/include/altload.h
scripts/    build-rust.sh → AltLoadFFI.xcframework
docs/       how it works, logo, release notes
```

**Build on GitHub:** fork, enable Actions and run **Build IPA**. **Build on a Mac** (Xcode 27, Homebrew, Rust):

```sh
brew install xcodegen
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
./scripts/build-rust.sh && xcodegen generate && open AltLoad.xcodeproj
```

Pull requests are welcome. When something breaks, an issue with your iOS version, the AltLoad version and a screenshot of the error helps the most.

## Credits

Built on [idevice](https://github.com/jkcoxson/idevice) and [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN) by **jkcoxson**, [isideload](https://github.com/nab138/isideload) by **nab138** and [StikPair](https://github.com/StephenDev0/StikPair) by **StephenDev0**. Installs [AltStore](https://altstore.io) by **Riley Testut**, [SideStore](https://github.com/SideStore) and [LiveContainer](https://github.com/LiveContainer/LiveContainer), always fetched from their own sources.

---

<sub>© 2026 mirazbakis. All rights reserved under the [AltLoad License](LICENSE.md); third-party code keeps its own licenses ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)). Using AltLoad means agreeing to the [Terms of Service](https://mirazbakis.github.io/terms.html). Not affiliated with AltStore, SideStore, LiveContainer, Riley Testut or Apple.</sub>
