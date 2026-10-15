<div align="center">

<img src="docs/assets/logo.svg" width="120" height="120" alt="AltLoad logo">

# AltLoad

### Install AltStore Classic on-device.

No Mac, no PC, no cable. SideStore and LiveContainer too.

[![Download](https://img.shields.io/github/v/release/mirazbakis/AltLoad?label=stable&style=for-the-badge&color=2ea44f)](https://github.com/mirazbakis/AltLoad/releases/latest)
[![Beta](https://img.shields.io/badge/beta-1.2.0%20beta%201-6e40c9?style=for-the-badge)](https://github.com/mirazbakis/AltLoad/releases/tag/v1.2.0-beta.1)
[![Platform](https://img.shields.io/badge/iOS-18%2B-lightgrey?style=for-the-badge&logo=apple)](#compatibility)
[![License](https://img.shields.io/badge/license-AltLoad-orange?style=for-the-badge)](LICENSE.md)

[Website](https://mirazbakis.github.io/AltLoad.html) · [Releases](https://github.com/mirazbakis/AltLoad/releases) · [How it works](docs/HOW-IT-WORKS.md) · [Report a problem](https://github.com/mirazbakis/AltLoad/issues)

</div>

---

> [!CAUTION]
> **Download AltLoad only from here:**
>
> - **Website:** <https://mirazbakis.github.io/AltLoad.html>
> - **GitHub:** <https://github.com/mirazbakis/AltLoad/releases>
>
> You sign in to AltLoad with your Apple ID. Anyone can take public source code, add a few lines that send your password to their own server, and hand it out under the same name and icon. Copies from other websites, app sources, signing services, Discord or Telegram aren't AltLoad, however official they look. Re-uploading AltLoad builds also isn't allowed by the [license](LICENSE.md).

## What it is

AltStore Classic keeps your sideloaded apps signed with your own Apple ID. Getting it onto the iPhone in the first place has always meant a computer running AltServer.

AltLoad is that computer, running on the iPhone itself. It pairs the iPhone with itself, signs AltStore with your Apple ID and installs it. It also runs an AltServer right on the phone, so AltStore can keep refreshing your apps afterwards without ever looking for a Mac or PC.

Prefer SideStore? AltLoad installs **SideStore** and **SideStore + LiveContainer** the same way, and drops the pairing file into SideStore so it can refresh on its own.

## Features

- **AltStore Classic, Beta, SideStore and SideStore + LiveContainer.** Stable or nightly, always the newest build from each project's own source.
- **A built-in AltServer** that keeps running in the background.
- **The pairing code in your Dynamic Island** <sup>new</sup>: read it while you're in Settings, no switching back and forth. iPhones without a Dynamic Island show it on the Lock Screen.
- **Import a pairing file** <sup>new</sup>: on iOS 18–26, or if you'd rather pair with a computer.
- **Sign-in that keeps working.** AltLoad finds an anisette server Apple still accepts and switches when one stops working.
- **Fallbacks for when SideStore's servers are down**, and Install IPA from Files as a last resort.
- **Extras:** entitlements like Increased Memory Limit, JIT, location simulation, and a reminder the day before your apps expire.

## Requirements

- An iPhone or iPad on **iOS 18 or later** (iOS 27 to pair on the device itself)
- **Developer Mode** on
- **[LocalDevVPN](https://apps.apple.com/app/id6755608044)**, free on the App Store
- An **Apple ID**. A free one works: apps last 7 days, 3 at a time
- **Wi-Fi**, the first time only

## Compatibility

| iOS | Works? |
| :-- | :-- |
| **27 and later** | ✅ Yes. Pairs entirely on the device. |
| **18 – 26** | ⚠️ Yes, from 1.2.0 beta 1, with a [pairing file made on a computer](#on-ios-18-26) once. |
| **17 and earlier** | ❌ No |

## How to use it

1. **Get AltLoad.** Download `AltLoad.ipa` from the [latest release](https://github.com/mirazbakis/AltLoad/releases/latest), or the [1.2.0 beta](https://github.com/mirazbakis/AltLoad/releases/tag/v1.2.0-beta.1) for the newest features, and install it once with any signing tool you already use.
2. **Pair.** Open **Tools › Pair › Pair This iPhone or iPad**. Go to **Settings › Privacy & Security › Developer Mode**, tap **Pair with AltLoad** and type the code, which is waiting for you in the Dynamic Island.
3. **Connect LocalDevVPN.**
4. **Install.** On the **Install** tab, choose **AltStore** (or another store), tap **Install** and sign in with your Apple ID.
5. **Done.** AltStore finds AltLoad's AltServer on the same iPhone and works like it would with a computer. Refresh once a week in AltStore or AltLoad; AltLoad reminds you the day before.

### On iOS 18–26

These versions can't pair with an app on the device itself, so make the pairing file on a Mac or PC once, for example with [iloader](https://github.com/nab138/iloader) or [idevice_pair](https://github.com/jkcoxson/idevice_pair). Then save it to Files on the iPhone, open **Tools › Pair › Import Pairing File** and choose it. Everything after that is the same.

## Is it safe?

AltLoad works entirely on your iPhone, and all of its code is here for anyone to check.

- **Your Apple ID password only goes to Apple.** If you choose *Remember password*, it stays in this iPhone's Keychain and never syncs.
- **No AltLoad server, no analytics, no account.** Anisette servers help with sign-in but never see your password.
- **Pairing files give access to your device.** Only put them in apps you trust.

> [!WARNING]
> This applies to AltLoad as published in this repository and on the website above. A modified copy can do anything with the Apple ID you type into it.

Found a security issue? Please follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## Questions

**Sign-in fails.** Apple now refuses many public anisette servers. Leave **Settings › Anisette** on **Automatic** and AltLoad picks one that works. Still failing? Tap **Reset Anisette Data** and try again in a few minutes.

**SideStore won't download.** AltLoad tries SideStore's source, its mirror, GitHub and a known-good build in turn. If all of them are down, use **Install IPA from Files** in the Install tab's **…** menu.

**AltLoad can't reach the iPhone.** Check that LocalDevVPN is connected, Developer Mode is on, and this iPhone shows up in **Tools › Pair**.

**Why does the beta take 2 App IDs?** The Dynamic Island code comes from a small widget extension inside AltLoad, and each one needs its own App ID when you sideload AltLoad with a free account.

## Project layout

| Path | What's in it |
| :-- | :-- |
| `App/` | The SwiftUI app: Install, Tools, Settings and About, plus the install flow, pairing and the on-device AltServer |
| `Widgets/` | The extension that draws the pairing code in the Dynamic Island and on the Lock Screen |
| `Shared/` | Code used by both the app and the extension |
| `rust/` | The Rust core: pairing host, Apple ID sign-in, signing and the tunnel to the device |
| `scripts/` | `build-rust.sh`, which builds the Rust core into `AltLoadFFI.xcframework` |
| `docs/` | [How it works](docs/HOW-IT-WORKS.md), the logo and release notes |
| `.github/` | The **Build IPA** workflow, started by hand |

### Build it yourself

Fork the repository, enable Actions and run **Build IPA**; the IPA is attached to the run. Or on a Mac with Xcode 27, Homebrew and Rust:

```sh
brew install xcodegen
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
./scripts/build-rust.sh
xcodegen generate
open AltLoad.xcodeproj
```

## Contributing

Issues and pull requests are welcome. For a bug, please include your iOS version, the AltLoad version, the store you picked and the step where it went wrong.

## Thanks

AltLoad builds on [idevice](https://github.com/jkcoxson/idevice) and [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN) by **jkcoxson**, [isideload](https://github.com/nab138/isideload) by **nab138**, and [StikPair](https://github.com/StephenDev0/StikPair) by **StephenDev0**. It installs [AltStore](https://altstore.io) by **Riley Testut**, [SideStore](https://github.com/SideStore) and [LiveContainer](https://github.com/LiveContainer/LiveContainer), always downloaded from their own sources and never redistributed.

## License

See [LICENSE.md](LICENSE.md). In short, you can use AltLoad, build it yourself and send changes back. Redistributing builds, publishing a modified version or making money from it needs written permission. Code from StikPair, idevice and isideload keeps its own license ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)). Using AltLoad means you agree to the [Terms of Service](https://mirazbakis.github.io/terms.html).

<div align="center">

<sub>Not affiliated with AltStore, SideStore, LiveContainer, Riley Testut or Apple.</sub>

**AltLoad by [mirazbakis](https://github.com/mirazbakis)**

</div>
