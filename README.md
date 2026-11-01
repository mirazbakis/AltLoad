<div align="center">

<img src="docs/assets/logo.svg" width="120" height="120" alt="AltLoad">

# AltLoad

**Sideload AltStore, SideStore and LiveContainer from your iPhone. No computer required.**

[![Install](https://img.shields.io/badge/Install-AltLoad-2f6fed?style=for-the-badge)](https://mirazbakis.github.io/AltLoad/)
[![Version](https://img.shields.io/github/v/release/mirazbakis/AltLoad?label=version&style=for-the-badge&color=2f6fed)](https://github.com/mirazbakis/AltLoad/releases)
[![Platform](https://img.shields.io/badge/iOS-18%2B-lightgrey?style=for-the-badge&logo=apple)](#compatibility)
[![License](https://img.shields.io/badge/license-Custom_MIT-lightgrey?style=for-the-badge)](LICENSE.md)

<a href="https://altdirect.app/?url=https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json"><img src="https://altdirect.app/assets/png/AltSource_Blue.png" width="180" alt="Add AltSource"></a>
&nbsp;
<a href="https://github.com/mirazbakis/AltLoad/releases/latest/download/AltLoad.ipa"><img src="https://altdirect.app/assets/png/Download_Blue.png" width="180" alt="Download .ipa"></a>

</div>

> [!CAUTION]
> **Only install AltLoad from the [official website](https://mirazbakis.github.io/AltLoad/) or [this repository](https://github.com/mirazbakis/AltLoad).**
>
> AltLoad handles your Apple ID password and your iPhone's pairing data, and a modified copy could send both to someone else. Any other website, source, file host, Telegram channel or Discord server is unofficial, however real it looks. AltLoad is free, and forks may not publish builds.
>
> Already used an unofficial copy? Delete it, change your Apple ID password at [account.apple.com](https://account.apple.com), remove any devices you don't recognize, and delete any pairing files it could reach.

## Why AltLoad

Stores like AltStore normally depend on a computer to pair with your iPhone, sign the app, install it and refresh it every week. AltLoad does that work on the iPhone itself.

It pairs your iPhone with itself, signs the store with your own Apple ID and installs it. It can then run AltServer on the same device, so AltStore can refresh without a computer on the network. It works with a free Apple ID, and it's fully local.

## Compatibility

| iOS | Installing and signing | Pairing |
| :-- | :-- | :-- |
| **27 and later** | Supported | On the iPhone, with no computer |
| **18 to 26** | Supported | Import a remote pairing file made once on a computer with [iloader](https://github.com/nab138/iloader) or [idevice_pair](https://github.com/jkcoxson/idevice_pair) |
| **17 and earlier** | Not supported | Not supported |

You also need [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [LocalDevVPN](https://apps.apple.com/app/id6755608044) from the App Store and an Apple ID. With a free Apple ID, apps last 7 days.

## Features

| | |
| :-- | :-- |
| **Stores** | AltStore Classic and Beta, SideStore and SideStore + LiveContainer, stable or nightly |
| **Your own apps** | Sign and install any IPA from Files. Husk is also available from the store list |
| **On-device AltServer** | AltStore finds AltLoad the way it finds a computer, and it can stay running in the background |
| **On-device pairing** | On iOS 27, pair by entering a code from your Dynamic Island |
| **Pairing files** | Place this iPhone's pairing file in SideStore, StikDebug and other sideloaded apps |
| **App extensions** | Keep them, share the main app's profile to use one App ID, or remove them |
| **Developer tools** | JIT, location simulation, entitlements, certificates and App IDs |
| **Careful sign-in** | Pauses after repeated failures, forgets a password Apple rejects, and checks which anisette servers respond |
| **Stays current** | Reminders before a signature expires, update notices, and fallbacks when a store's source is down |
| **Languages** | English, French, German, Italian, Chinese and Russian |

## Install

**1. Get AltLoad** using one of these:

- **Signed install:** open the [official website](https://mirazbakis.github.io/AltLoad/) in Safari, accept the Terms, add the DNS profile and tap a signed install.
- **AltStore or SideStore:** [add the source with AltDirect](https://altdirect.app/?url=https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json) to get updates there.
- **Your own signer:** download `AltLoad.ipa` from [Releases](https://github.com/mirazbakis/AltLoad/releases).

**2. Pair your iPhone.** In AltLoad, open **Tools › Pair**, then go to **Settings › Privacy & Security › Developer Mode › Pair with AltLoad** and enter the code.

**3. Install a store.** Turn on LocalDevVPN, choose a store on the **Install** tab and sign in.

## Troubleshooting

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
<summary><b>"Can't connect to this iPhone"</b></summary>
<br>

LocalDevVPN must be connected, Developer Mode on, and this iPhone paired in **Tools › Pair**. If all three are true, pair again.
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

## How it's built

| Path | Contents |
| :-- | :-- |
| `ios/` | The SwiftUI app, Live Activity extension and translations |
| `core/` | The Rust core for pairing, the device tunnel, sign-in, signing and installing |
| `site/` | The install page on GitHub Pages |
| `signing/` | Scripts and certificate packs for the signed installs |
| `scripts/` | Build scripts |
| `docs/` | [How it works](docs/HOW-IT-WORKS.md) and release notes |

## License

AltLoad is open source under a custom MIT-based license. You can read it, change it, build it for yourself and reuse parts in non-commercial projects with the credit *"Based on AltLoad by mirazbakis"*. Builds may only be distributed through this repository and the official website. See [LICENSE.md](LICENSE.md).

Report security issues as described in [SECURITY.md](SECURITY.md). Using AltLoad means agreeing to the [Terms of Service](https://mirazbakis.github.io/AltLoad/terms.html). AltLoad isn't affiliated with Apple or with any app it installs.

See [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md) for the projects AltLoad relies on, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for licenses.
