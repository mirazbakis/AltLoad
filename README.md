<div align="center">

<img src="docs/assets/logo.svg" width="120" height="120" alt="AltLoad">

# AltLoad

**Sideload AltStore, SideStore and LiveContainer from the iPhone itself.**<br>
No computer, no subscription, your own Apple ID.

<p>
<a href="https://mirazbakis.github.io/AltLoad/altstore.html"><picture><source media="(prefers-color-scheme: dark)" srcset="docs/assets/altstore-badge-dark.png"><img src="docs/assets/altstore-badge-light.png" width="200" alt="Download on AltStore"></picture></a>
&nbsp;
<a href="https://altdirect.app/?url=https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json"><img src="https://altdirect.app/assets/png/AltSource_Blue.png" width="200" alt="Add AltSource"></a>
&nbsp;
<a href="https://github.com/mirazbakis/AltLoad/releases/latest/download/AltLoad.ipa"><img src="https://altdirect.app/assets/png/Download_Blue.png" width="200" alt="Download .ipa"></a>
</p>

[![Install](https://img.shields.io/badge/Install-AltLoad-3be0a0?style=for-the-badge)](https://mirazbakis.github.io/AltLoad/)
[![Version](https://img.shields.io/github/v/release/mirazbakis/AltLoad?label=version&style=for-the-badge&color=4c8dff)](https://github.com/mirazbakis/AltLoad/releases)
[![Platform](https://img.shields.io/badge/iOS-18%2B-0a1740?style=for-the-badge&logo=apple)](#compatibility)
[![License](https://img.shields.io/badge/license-Custom_MIT-0a1740?style=for-the-badge)](LICENSE.md)

[Install](#install) · [Features](#features) · [Troubleshooting](#troubleshooting) · [Privacy](#privacy) · [How it works](docs/HOW-IT-WORKS.md)

</div>

> [!CAUTION]
> **Only get AltLoad from [this repository](https://github.com/mirazbakis/AltLoad) or [its website](https://mirazbakis.github.io/AltLoad/).**
> AltLoad handles your Apple ID password and your iPhone's pairing data, and an unofficial build could send them to anyone. [How to spot one](#official-builds-only).

## What is AltLoad?

Normally a store like AltStore needs a computer: to pair with the iPhone, sign the app and install it, then to keep refreshing it every week. AltLoad is that computer, running on the phone. It pairs the iPhone with itself, signs the store with your Apple ID, installs it, and then keeps an AltServer running so AltStore refreshes on its own.

## Install

### 1. Get AltLoad

| Method | How |
| :-- | :-- |
| **Signed install** | Open **[mirazbakis.github.io/AltLoad](https://mirazbakis.github.io/AltLoad/)** in Safari, accept the Terms, add the DNS profile and tap any signed install. |
| **AltStore or SideStore** | Add the source `https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json`, or tap **Add to AltStore** / **Add to SideStore** on the website. You get updates there too. |
| **Your own signer** | Download `AltLoad.ipa` from [Releases](https://github.com/mirazbakis/AltLoad/releases) and sign it with a tool you already have. |

### 2. Set it up

1. Turn on **Developer Mode** and get **[LocalDevVPN](https://apps.apple.com/app/id6755608044)** from the App Store.
2. In AltLoad, go to **Tools › Pair**. The code shows up in your Dynamic Island. Open **Settings › Developer › Pair with AltLoad** and type it in. On iOS 18 to 26, import a pairing file instead (see [Compatibility](#compatibility)).
3. Switch LocalDevVPN on, pick a store on the **Install** tab and sign in.

A free Apple ID works; apps last 7 days. AltLoad reminds you the day before anything expires.

### Compatibility

| iOS | Support |
| :-- | :-- |
| **27 and later** | Everything, including pairing on the device |
| **18 to 26** | Make a pairing file once on a computer with [iloader](https://github.com/nab138/iloader) or [idevice_pair](https://github.com/jkcoxson/idevice_pair), then **Tools › Pair › Import Pairing File** |
| **17 and earlier** | Not supported |

## Official builds only

AltLoad and its builds are distributed in exactly these places. Anything else is unofficial, whatever it calls itself.

| Official | Link |
| :-- | :-- |
| Repository and Releases | [github.com/mirazbakis/AltLoad](https://github.com/mirazbakis/AltLoad) |
| Website | [mirazbakis.github.io/AltLoad](https://mirazbakis.github.io/AltLoad/) |
| AltStore / SideStore source | `https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json` |

**Treat it as unofficial if:**

- it's on another website, file host, app repository or AltStore/SideStore source, or in a Telegram or Discord channel;
- it asks you to pay, or puts the download behind ads, a link shortener or a donation;
- it's sold as part of a signing, certificate or UDID-registration service;
- it's a release or source published from a fork. Forks may not publish builds.

AltLoad is free, and the [license](LICENSE.md) doesn't allow any of the above. Building it yourself from this repository for your own devices is fine.

**If you already used an unofficial build,** delete it, change your Apple ID password at [account.apple.com](https://account.apple.com), remove any devices you don't recognize, and delete any pairing files it made or had access to.

**Found one?** [Open an issue](https://github.com/mirazbakis/AltLoad/issues) with the link.

## Features

- **Stores.** AltStore Classic and Beta, SideStore, SideStore + LiveContainer, stable or nightly, or any IPA from Files.
- **App extensions, your choice.** Keep them, keep them on the main app's profile (one App ID), or remove them. That matters with a free Apple ID's 10 App IDs a week.
- **AltServer on the phone.** AltStore finds it like it would find a computer, and it keeps running in the background.
- **Sign-in that keeps working.** AltLoad health-checks anisette servers (Windows ADI first, then jkcoxson's Mac ADI and the rest) and moves on when Apple refuses one.
- **When sources go down.** Mirrors, GitHub releases, a known-good build and AltLoad's own saved copy, in that order.
- **Tools.** Pairing files for sideloaded apps like SideStore and StikDebug, entitlements, JIT, location simulation and certificate management.

## Troubleshooting

<details>
<summary><b>Sign-in fails</b></summary>

Apple has been refusing many public anisette servers since October 2026. Leave **Settings › Anisette** on **Automatic**. If it still fails, tap **Reset Anisette Data** and try again a few minutes later. **Settings › Apple ID › Sign In** tests your account without installing anything.
</details>

<details>
<summary><b>"Not enough available App IDs"</b></summary>

A free Apple ID can create 10 App IDs a week, and each app extension normally needs one. Before installing, set **App Extensions** to **Keep, Use Main Profile** or **Remove Extensions**.
</details>

<details>
<summary><b>"Can't connect to this iPhone"</b></summary>

LocalDevVPN must be connected, Developer Mode on, and this iPhone paired in **Tools › Pair**. If all three are true, pair again.
</details>

<details>
<summary><b>"Certificate limit reached"</b></summary>

Free Apple IDs get only a few development certificates. AltLoad asks which one to revoke. Apps signed with it elsewhere stop opening until they're signed again.
</details>

<details>
<summary><b>SideStore won't download</b></summary>

If SideStore's source, mirror, GitHub and the known-good build are all down, get a SideStore IPA another way and use **Install IPA from Files** in the Install tab's **…** menu.
</details>

## Privacy

AltLoad has no servers, no accounts and no analytics. Your Apple ID password goes to Apple and nowhere else. If you choose *Remember password*, it stays in this iPhone's Keychain and never syncs. Anisette servers never see it.

This only holds for [official builds](#official-builds-only). Report security issues privately as described in [SECURITY.md](SECURITY.md).

## How it's built

A SwiftUI app on top of a Rust core. Rust pairs, opens the tunnel through LocalDevVPN, signs in to Apple, signs and installs. Swift draws the screens, runs the on-device AltServer and the pairing-code Live Activity. [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) walks through every step.

```
ios/
  App/          SwiftUI app: Core/ (logic), Features/ (screens), UI/, Resources/
  Widgets/      Live Activity extension (Dynamic Island, Lock Screen)
  Shared/       code compiled into both targets
core/           Rust core, exposed to Swift through core/include/altload.h
site/           the install page on GitHub Pages
signing/        cert packs and scripts for the signed installs on the site
scripts/        build-rust.sh → AltLoadFFI.xcframework
docs/           how it works, release notes, logo
.github/        Build IPA, Sign IPAs & Deploy OTA, Sign IPA
```

## License

AltLoad is open source under a custom MIT-based license. You can read it, change it, build it for yourself and send pull requests, and reuse pieces of it in non-commercial projects with the credit *"Based on AltLoad by mirazbakis"*. AltLoad and its builds may only be distributed here and on the [official website](https://mirazbakis.github.io/AltLoad/): no mirrors, re-uploads, other sources or paywalls. See [LICENSE.md](LICENSE.md).

## Credits

Built on [idevice](https://github.com/jkcoxson/idevice), [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN) and the anisette servers of **Jackson Coxson**, [isideload](https://github.com/nab138/isideload) by **nab138** and [StikPair](https://github.com/StephenDev0/StikPair) by **StephenDev0**. Installs [AltStore](https://altstore.io) by **Riley Testut**, [SideStore](https://github.com/SideStore) and [LiveContainer](https://github.com/LiveContainer/LiveContainer), always downloaded from their own sources. Full notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

<sub>© 2026 mirazbakis. Licensed under the [AltLoad License](LICENSE.md). Distributed only through this repository and its website. Using AltLoad means agreeing to the [Terms of Service](https://mirazbakis.github.io/AltLoad/terms.html). Not affiliated with Apple, AltStore, Riley Testut, SideStore or LiveContainer.</sub>
