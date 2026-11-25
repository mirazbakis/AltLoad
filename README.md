<div align="center">

<img src="docs/assets/logo.svg" width="120" height="120" alt="AltLoad">

# AltLoad

**Install AltStore, SideStore and LiveContainer from your iPhone, signed with your own Apple ID. No computer, no shared certificate.**

[![Latest release](https://img.shields.io/github/v/release/mirazbakis/AltLoad?label=release)](https://github.com/mirazbakis/AltLoad/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/mirazbakis/AltLoad/total)](https://github.com/mirazbakis/AltLoad/releases)
[![iOS](https://img.shields.io/badge/iOS-18%2B-blue)](#requirements)
[![Stars](https://img.shields.io/github/stars/mirazbakis/AltLoad)](https://github.com/mirazbakis/AltLoad/stargazers)

[Install](https://altload.org/) · [Download the IPA](https://github.com/mirazbakis/AltLoad/releases/latest/download/AltLoad.ipa) · [Add the source](https://altdirect.app/?url=https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json) · [Releases](https://github.com/mirazbakis/AltLoad/releases)

English · [简体中文](README.zh-Hans.md) · [Русский](README.ru.md) · [Français](README.fr.md) · [한국어](README.ko.md)

</div>

> [!CAUTION]
> **altload.org** and this repository are the only official sources. AltLoad is free and handles your Apple ID password and pairing data, so a copy from anywhere else could be modified to steal them. Already used one? Delete it and change your Apple ID password at [account.apple.com](https://account.apple.com).

## What it does

Sideloading usually needs either a computer that signs your apps and refreshes them every 7 days, or a shared certificate that Apple can revoke at any time. AltLoad does the computer's job on the iPhone: it pairs the phone with itself, signs the store with your own Apple ID, installs it, and then acts as AltServer on the same device so AltStore can refresh. It works with a free Apple ID, and your password goes to Apple only.

| | With a computer | With a shared certificate | With AltLoad |
| :-- | :-- | :-- | :-- |
| Needs a computer | Yes, for install and every refresh | Usually only to set up | No on iOS 27. One pairing file on iOS 18 to 26 |
| Can be revoked without notice | No | Yes, by Apple or the certificate's owner | No. The certificate is yours |
| Weekly refresh | Computer on the same network | Not tied to your Apple ID | On the iPhone |
| JIT | Needs a computer-side tool | Not part of the certificate | Built in |
| Cost | Free Apple ID works | Set by whoever runs the certificate | Free |

## Requirements

| iOS | Installing and signing | Pairing |
| :-- | :-- | :-- |
| **27 and later** | Supported | On the iPhone, with no computer |
| **18 to 26** | Supported | Import a remote pairing file made once on a computer with [iloader](https://github.com/nab138/iloader) or [idevice_pair](https://github.com/jkcoxson/idevice_pair) |
| **17 and earlier** | Not supported | Not supported |

You also need:

- [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) turned on
- [LocalDevVPN](https://apps.apple.com/app/id6755608044) from the App Store
- An Apple ID. With a free one, apps last 7 days

## Install

**1. Get AltLoad.** Pick one route:

| Route | Best for | How |
| :-- | :-- | :-- |
| **Apple ID Install** (recommended) | Signing with your own Apple ID, no computer and no DNS profile | Install three free App Store apps and follow the steps on [altload.org](https://altload.org/). See [AltPair](https://github.com/mirazbakis/AltPair) |
| **Direct Install** | The fastest route. Uses a shared certificate, so it can be revoked | Open [altload.org](https://altload.org/) in Safari, accept the Terms, add the DNS profile and tap a signed install |
| **AltStore or SideStore** | You already run one | [Add the source](https://altdirect.app/?url=https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json) and get updates there |
| **Your own signer** | You sign IPAs yourself | Download `AltLoad.ipa` from [Releases](https://github.com/mirazbakis/AltLoad/releases) |

**2. Pair your iPhone.** In AltLoad, open **Tools › Pair**, then go to **Settings › Privacy & Security › Developer Mode › Pair with AltLoad** and enter the code.

**3. Install a store.** Turn on LocalDevVPN, choose a store on the **Install** tab and sign in.

**4. Install more apps (optional).** In the Install tab's **…** menu, open **Sources** to add an AltStore-format source and install its apps, or **Install IPA from Files** for an IPA you have. See [Sources](docs/SOURCES.md).

## Features

**Installing and signing**
- **Stores:** AltStore Classic and Beta, SideStore and SideStore + LiveContainer, stable or nightly. Also Husk, UTM, MeloNX and Madeira
- **Your own apps:** sign and install any IPA from Files
- **Sources:** add AltStore and SideStore sources, browse their apps, read release notes, install older versions, and see when an update is out
- **Developer team:** pick which team signs, if your Apple ID belongs to more than one
- **Several Apple IDs:** save more than one and switch when you sign in. Each app remembers the Apple ID that signed it
- **Certificate name:** choose the name AltLoad gives the development certificate it requests, in Settings
- **Entitlements:** per-app capabilities, presets for emulators and network tools, and what the last profile actually granted

**Pairing and refresh**
- **On-device pairing:** on iOS 27, pair by entering a code from your Dynamic Island
- **On-device AltServer:** AltStore finds AltLoad the way it finds a computer, and it can stay running in the background
- **AltStore without AltServer:** AltLoad leaves this iPhone's pairing file where AltStore 2.3.1 and later look for it, so AltStore can refresh by itself
- **Automatic refresh:** refreshes apps before they expire and re-signs revoked ones in the background, with LocalDevVPN on and the password saved
- **Pairing files:** place this iPhone's pairing file in SideStore, StikDebug and other sideloaded apps

**JIT and tools**
- **JIT:** open apps with JIT from Tools, Shortcuts, Siri or the Home Screen. Pin the ones you use, run scripts, and take requests from links
- **More tools:** location simulation, certificates, App IDs, and app extension options
- **Logs:** in Settings, see what AltLoad did and copy a report when something fails. Emails are masked and passwords are never logged

**Languages:** English, Chinese, French, German, Italian, Japanese, Korean, Portuguese (Brazil), Russian and Spanish.

## Troubleshooting

When something fails, open **Settings › Logs** and tap **Copy**, or tap **Copy Log** on the error screen. Paste it into an [issue](https://github.com/mirazbakis/AltLoad/issues). The most common problems are below; [Troubleshooting](docs/TROUBLESHOOTING.md) has the full list.

<details>
<summary><b>"Can't connect to this iPhone" or "Connection refused"</b></summary>
<br>

LocalDevVPN must be connected, Developer Mode on, and this iPhone paired in **Tools › Pair**. Allow Local Network access if AltLoad asks. Turn off any other VPN or proxy app. If it still fails, turn LocalDevVPN off and on, or pair again.
</details>

<details>
<summary><b>"Couldn't open a tunnel to this device"</b></summary>
<br>

The pairing service answered, but the next connection stalled. Turn LocalDevVPN off and on, wait a few seconds and try again. AltLoad 1.8.0 and later set up one connection at a time, so an install and the JIT tab no longer stall each other.
</details>

<details>
<summary><b>Sign-in fails</b></summary>
<br>

Leave **Settings › Anisette** on **Automatic**. If sign-in still fails, tap **Reset Anisette Data** and try again a few minutes later. If AltLoad says sign-ins are paused, wait for the time it shows.
</details>

<details>
<summary><b>"Not enough available App IDs"</b></summary>
<br>

A free Apple ID can create 10 App IDs a week, and each app extension normally needs one. Before installing, set **App Extensions** to **Keep, Use Main Profile** or **Remove Extensions**.
</details>

<details>
<summary><b>"Certificate limit reached"</b></summary>
<br>

Free Apple IDs get only a few development certificates. AltLoad asks which one to revoke. Apps signed with it elsewhere stop opening until they're signed again.
</details>

<details>
<summary><b>A store won't download</b></summary>
<br>

If a store's sources are all down, get its IPA another way and use **Install IPA from Files** in the Install tab's **…** menu.
</details>

## Documentation

| Guide | What's in it |
| :-- | :-- |
| [FAQ](docs/FAQ.md) | Passwords, limits, revocation, and how AltLoad differs from AltStore and SideStore |
| [Sources](docs/SOURCES.md) | Adding sources, updates, and the source fields AltLoad reads |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Errors and what to do about them |
| [How it works](docs/HOW-IT-WORKS.md) | Pairing, the tunnel, signing and installing, step by step |
| [altpair](https://github.com/mirazbakis/AltPair) | Installing AltLoad with your Apple ID, without a computer |
| [Contributing](CONTRIBUTING.md) | Building, the project layout and pull requests |

## Building

You need Xcode, Rust with the `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets, and XcodeGen.

```sh
make test   # Rust tests for the core and altpair
make ipa    # build/AltLoad.ipa, ad-hoc signed like the release builds
make sim    # a Simulator build
```

See [Contributing](CONTRIBUTING.md) before opening a pull request.

| Path | Contents |
| :-- | :-- |
| `ios/` | The SwiftUI app, Live Activity extension and translations |
| `core/` | The Rust core for pairing, the device tunnel, sign-in, signing and installing |
| `altpair/` | AltLoad's own tools that install it with your Apple ID, no computer. See its [README](https://github.com/mirazbakis/AltPair) |
| `site/` | The install page on GitHub Pages |
| `signing/` | Scripts and certificate packs for the signed installs |
| `docs/` | Guides, [How it works](docs/HOW-IT-WORKS.md) and release notes |

## License

AltLoad is open source under a custom MIT-based license. You can read it, change it, build it for yourself and reuse parts in non-commercial projects with the credit *"Based on AltLoad by mirazbakis"*. Builds may only be distributed through this repository and the official website. See [LICENSE.md](LICENSE.md).

Report security issues as described in [SECURITY.md](SECURITY.md). Using AltLoad means agreeing to the [Terms of Service](https://altload.org/terms.html). AltLoad isn't affiliated with Apple or with any app it installs.

See [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md) for the projects AltLoad relies on, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for licenses.
