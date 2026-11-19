<div align="center">

<img src="docs/assets/logo.svg" width="120" height="120" alt="AltLoad">

# AltLoad

**Install AltStore, SideStore and LiveContainer from your iPhone, signed with your own Apple ID. No computer, no shared certificate.**

[Install](https://mirazbakis.github.io/AltLoad/) · [Download the IPA](https://github.com/mirazbakis/AltLoad/releases/latest/download/AltLoad.ipa) · [Add the source](https://altdirect.app/?url=https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json) · [Releases](https://github.com/mirazbakis/AltLoad/releases)

English · [简体中文](README.zh-Hans.md) · [Русский](README.ru.md) · [Français](README.fr.md)

</div>

> [!CAUTION]
> **Only install AltLoad from the [official website](https://mirazbakis.github.io/AltLoad/) or [this repository](https://github.com/mirazbakis/AltLoad).**
>
> AltLoad handles your Apple ID password and your iPhone's pairing data, and a modified copy could send both to someone else. Any other website, source, file host, Telegram channel or Discord server is unofficial, however real it looks. That includes **applejr.net**, which is not affiliated with AltLoad: its copies aren't published or checked by me and may be modified. AltLoad is free. The only builds I publish are on the official website and in this repository, and forks may not publish builds.
>
> Already used an unofficial copy? Delete it, change your Apple ID password at [account.apple.com](https://account.apple.com), remove any devices you don't recognize, and delete any pairing files it could reach.

## What it does

Sideloading usually means one of two things. Either a computer pairs with your iPhone, signs the app and refreshes it every 7 days, or you install from a shared certificate that its owner pays for and Apple can revoke at any time, taking every app signed with it.

AltLoad does the computer's job on the iPhone. It pairs the phone with itself, signs the store with your own Apple ID, installs it, and then acts as AltServer on the same device so AltStore can refresh. It works with a free Apple ID, and your password goes to Apple only.

- **No computer** at any step on iOS 27. On iOS 18 to 26 you make one pairing file on a computer, once.
- **Your own certificate,** so there's nothing shared for someone else to revoke.
- **Stores and apps:** AltStore, SideStore, LiveContainer, Husk, UTM, MeloNX and Madeira, or any IPA from Files.
- **Refreshes on the phone:** AltStore refreshes itself once Remote AltServer is set up, or through AltLoad's built-in AltServer.
- **Free and open source.** Nothing leaves the phone except the sign-in to Apple.

| | With a computer | With a shared certificate | With AltLoad |
| :-- | :-- | :-- | :-- |
| Needs a computer | Yes, for install and every refresh | Usually only to set up | No on iOS 27. One pairing file on iOS 18 to 26 |
| Can be revoked without notice | No | Yes, by Apple or the certificate's owner | No. The certificate is yours |
| Weekly refresh | Computer on the same network | Not tied to your Apple ID | On the iPhone |
| JIT | Needs a computer-side tool | Not part of the certificate | Built in |
| Cost | Free Apple ID works | Set by whoever runs the certificate | Free |

## Compatibility

| iOS | Installing and signing | Pairing |
| :-- | :-- | :-- |
| **27 and later** | Supported | On the iPhone, with no computer |
| **18 to 26** | Supported | Import a remote pairing file made once on a computer with [iloader](https://github.com/nab138/iloader) or [idevice_pair](https://github.com/jkcoxson/idevice_pair) |
| **17 and earlier** | Not supported | Not supported |

You also need [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [LocalDevVPN](https://apps.apple.com/app/id6755608044) from the App Store and an Apple ID. With a free Apple ID, apps last 7 days.

## Install

**1. Get AltLoad.** Pick one route:

- **Apple ID Install (altpair).** Signed with your own Apple ID, with no computer and no DNS profile. You install three free App Store apps and follow the steps on the [official website](https://mirazbakis.github.io/AltLoad/). See [altpair/README.md](altpair/README.md).
- **Direct Install.** The fastest route, using a shared certificate. Open the [official website](https://mirazbakis.github.io/AltLoad/) in Safari, accept the Terms, add the DNS profile and tap a signed install.
- **AltStore or SideStore.** If you already run one, [add the source](https://altdirect.app/?url=https://raw.githubusercontent.com/mirazbakis/AltLoad/main/source.json) and get updates there.
- **Your own signer.** Download `AltLoad.ipa` from [Releases](https://github.com/mirazbakis/AltLoad/releases).

**2. Pair your iPhone.** In AltLoad, open **Tools › Pair**, then go to **Settings › Privacy & Security › Developer Mode › Pair with AltLoad** and enter the code.

**3. Install a store.** Turn on LocalDevVPN, choose a store on the **Install** tab and sign in.

## Features

| | |
| :-- | :-- |
| **On-device pairing** | On iOS 27, pair by entering a code from your Dynamic Island |
| **On-device AltServer** | AltStore finds AltLoad the way it finds a computer, and it can stay running in the background |
| **Stores** | AltStore Classic and Beta, SideStore and SideStore + LiveContainer, stable or nightly |
| **Your own apps** | Sign and install any IPA from Files |
| **Developer team** | Pick which team signs, if your Apple ID belongs to more than one |
| **Entitlements** | Per-app capabilities, presets for emulators and network tools, and what the last profile actually granted |
| **JIT** | Open apps with JIT from Tools, Shortcuts, Siri or the Home Screen. Pin the ones you use, run scripts, and take requests from links |
| **AltStore without AltServer** | AltLoad leaves this iPhone's pairing file where AltStore 2.3.1 and later look for it, so AltStore can refresh by itself |
| **Several Apple IDs** | Save more than one and switch when you sign in. Each app remembers the Apple ID that signed it |
| **Pairing files** | Place this iPhone's pairing file in SideStore, StikDebug and other sideloaded apps |
| **Automatic refresh** | Refreshes apps before they expire and re-signs revoked ones in the background, with LocalDevVPN on and the password saved |
| **Logs** | See what AltLoad did, and copy a report when something fails. Emails are masked and passwords are never logged |
| **More tools** | Location simulation, certificates, App IDs, and app extension options |
| **Languages** | English, Chinese, French, German, Italian, Japanese, Portuguese (Brazil), Russian and Spanish |

## Troubleshooting

When something fails, open **Tools › Support › Logs** and tap **Copy**, or tap **Copy Log** on the error screen. Paste it into an [issue](https://github.com/mirazbakis/AltLoad/issues).

<details>
<summary><b>"Can't connect to this iPhone" or "Connection refused"</b></summary>
<br>

LocalDevVPN must be connected, Developer Mode on, and this iPhone paired in **Tools › Pair**. Allow Local Network access if AltLoad asks. Turn off any other VPN or proxy app. If it still fails, turn LocalDevVPN off and on, or pair again.
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

## Building

You need Xcode, Rust with the `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets, and XcodeGen.

```sh
make test   # Rust tests for the core and altpair
make ipa    # build/AltLoad.ipa, ad-hoc signed like the release builds
make sim    # a Simulator build
```

| Path | Contents |
| :-- | :-- |
| `ios/` | The SwiftUI app, Live Activity extension and translations |
| `core/` | The Rust core for pairing, the device tunnel, sign-in, signing and installing |
| `altpair/` | AltLoad's own tools that install it with your Apple ID, no computer. See its [README](altpair/README.md) |
| `site/` | The install page on GitHub Pages |
| `signing/` | Scripts and certificate packs for the signed installs |
| `docs/` | [How it works](docs/HOW-IT-WORKS.md) and release notes |

## License

AltLoad is open source under a custom MIT-based license. You can read it, change it, build it for yourself and reuse parts in non-commercial projects with the credit *"Based on AltLoad by mirazbakis"*. Builds may only be distributed through this repository and the official website. See [LICENSE.md](LICENSE.md).

Report security issues as described in [SECURITY.md](SECURITY.md). Using AltLoad means agreeing to the [Terms of Service](https://mirazbakis.github.io/AltLoad/terms.html). AltLoad isn't affiliated with Apple or with any app it installs.

See [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md) for the projects AltLoad relies on, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for licenses.
