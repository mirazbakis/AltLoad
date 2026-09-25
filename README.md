# AltLoad

**Install AltStore on your iPhone using just your iPhone, with no computer involved.**

Normally, installing [AltStore](https://altstore.io) requires AltServer running on a Mac or PC. AltLoad does that job on the iPhone itself. It pairs the iPhone with itself, signs AltStore with your Apple ID, and installs it. When the 7-day signature is about to run out, you refresh it in AltLoad with one tap.

Built with SwiftUI for iOS 27, with a dark aurora theme and Liquid Glass.

> [!WARNING]
> **Early preview.** AltLoad hasn't been tested properly yet. Expect bugs, and please [open an issue](https://github.com/mirazbakis/AltLoad/issues) if something doesn't work.

> AltLoad is an independent project. It is not affiliated with AltStore, Riley Testut, SideStore or Apple.

---

## What you need

- An iPhone or iPad on **iOS 27 or later**.
- **Developer Mode** turned on (**Settings › Privacy & Security › Developer Mode**).
- **[LocalDevVPN](https://apps.apple.com/app/id6755608044)**, a free app from the App Store. It lets the iPhone connect to itself (see [How it works](#how-it-works)).
- An **Apple ID**. A free one is fine: apps then last 7 days, and you can have up to 3 sideloaded apps at once.
- Wi-Fi, for the one-time pairing step.

## Installing AltLoad

AltLoad is a sideloaded app, so you install the `.ipa` the same way as any other sideloaded app.

1. Download **`AltLoad.ipa`**:
   - the latest stable build is on the [**Releases**](https://github.com/mirazbakis/AltLoad/releases) page, or
   - the newest development build is on the [**Actions**](https://github.com/mirazbakis/AltLoad/actions) page. Open the latest green run and download **AltLoad-unsigned** from **Artifacts**. You need to be signed in to GitHub for this.
2. Sign and install it with whatever you already use to sideload: AltStore, SideStore, Sideloadly, Xcode or another signing tool.
3. If iOS says the developer isn't trusted, go to **Settings › General › VPN & Device Management**, tap your Apple ID and choose **Trust**.

## Using AltLoad

1. **Pair this iPhone (once).** Open the **Pair** tab and tap **Pair This iPhone or iPad**. Then go to **Settings › Privacy & Security › Developer Mode**, scroll down, tap **Pair with AltLoad**, and enter the code AltLoad shows you.
2. **Set up LocalDevVPN (once).** Install it from the App Store and open it once so it can add its VPN configuration.
3. **Install AltStore.** Open the **Install** tab, tap **Install AltStore**, sign in with your Apple ID and enter the two-factor code. If LocalDevVPN is off, AltLoad asks you to turn it on, then continues by itself.
4. **Trust it.** The first time you open AltStore, trust your Apple ID in **Settings › General › VPN & Device Management**.
5. **Refresh every week.** With a free Apple ID, AltStore stops opening after 7 days. AltLoad reminds you the day before, and you open the **Install** tab and tap **Refresh AltStore**.

> **Why refresh in AltLoad and not in AltStore?** AltStore's built-in refresh looks for AltServer on a computer, which this setup doesn't have. AltLoad does the refreshing instead, and your AltStore data and apps are kept.

### What's in the app

| Tab | What it does |
|---|---|
| **Install** | Installs, refreshes or updates AltStore, always the newest version from the official AltStore source. It can also install an `.ipa` file you pick. |
| **Pair** | Creates pairing files on the device, for this iPhone, another iPhone or iPad, or an Apple TV. |
| **Library** | Your saved pairing files (also in **Files › On My iPhone › AltLoad**) and AltStore's expiry date. |
| **Settings** | Apple ID, anisette server, AltStore source, LocalDevVPN and background options. |

## Building the IPA yourself

You don't need a Mac for this: GitHub can build it for you.

### On GitHub (no Mac needed)

1. **Fork** this repository (the **Fork** button at the top right).
2. In your fork, open the **Actions** tab and enable workflows if GitHub asks.
3. Run **Build unsigned IPA**, either by clicking **Run workflow** or by pushing a commit.
4. When it finishes (about 10–20 minutes the first time), download **AltLoad-unsigned** from the run's **Artifacts**. The zip contains `AltLoad.ipa`.

To publish a release, push a tag starting with `v` (for example `v1.0.0`). The workflow attaches `AltLoad.ipa` to a GitHub Release automatically.

> Actions minutes are free for public repositories. Private repositories use your monthly allowance, and macOS minutes count 10×.

### On a Mac

You need **Xcode 27**, [Homebrew](https://brew.sh) and [Rust](https://rustup.rs).

```sh
brew install xcodegen
rustup target add aarch64-apple-ios aarch64-apple-ios-sim

git clone https://github.com/mirazbakis/AltLoad.git
cd AltLoad
./build-rust.sh        # compiles the Rust part into AltLoadFFI.xcframework
xcodegen generate      # creates AltLoad.xcodeproj from project.yml
```

Then do one of the following:

- **Run it from Xcode:** `open AltLoad.xcodeproj`, choose your Team under **Signing & Capabilities**, set a unique bundle identifier (for example `com.yourname.AltLoad`), plug in your iPhone and press **Run**.
- **Make an unsigned IPA:**
  ```sh
  xcodebuild -project AltLoad.xcodeproj -scheme AltLoad -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/dd \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
  mkdir -p build/Payload
  cp -R build/dd/Build/Products/Release-iphoneos/AltLoad.app build/Payload/
  (cd build && zip -qr ../AltLoad.ipa Payload)
  ```

Xcode doesn't need to know about new source files: anything in `App/` is picked up automatically. Run `xcodegen generate` again after adding files.

## How it works

The short version is below. [`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) covers every step in detail.

1. **Pairing.** On iOS 27, a device can pair wirelessly with a "host" it finds on the network. AltLoad acts as that host, so the iPhone pairs with AltLoad the same way it would pair with a Mac. The result is a pairing file.
2. **Reaching itself.** An app can't normally talk to its own iPhone's system services the way a computer can. LocalDevVPN routes one address (`10.7.0.1`) back into the phone, so AltLoad's connection looks like it's coming from another device. AltLoad then opens the same secure tunnel that Xcode uses.
3. **Apple ID.** AltLoad signs in to Apple's developer services with your Apple ID. It registers your iPhone, gets a development certificate, and creates the App IDs and provisioning profiles AltStore needs.
4. **Signing.** It adds the details AltServer would normally write into AltStore, then signs AltStore and its extensions.
5. **Installing.** It copies the signed app onto the iPhone through the tunnel and asks iOS to install it.

## Privacy and security

- **Your Apple ID password goes only to Apple.** If you choose *Remember password*, it's stored in the iPhone's Keychain, is only readable while the phone is unlocked, and never syncs to iCloud.
- **Anisette server:** Apple requires extra device-identity headers ("anisette") before it accepts a sign-in. AltLoad gets them from a public anisette server, SideStore's `ani.sidestore.io` by default. You can choose another server or your own in Settings. The anisette server never sees your password.
- **Pairing files** give access to your device. Only share them with apps you trust.
- **Using a secondary Apple ID** is a common choice for sideloading. It works fine with AltLoad.

## FAQ

**Does this need a computer at all?**
You don't need one to install or refresh AltStore. You do need some way to sideload AltLoad itself the first time.

**Why iOS 27?**
The on-device pairing AltLoad depends on (**Pair with…** under Developer Mode) was added in iOS 27.

**Sign-in fails with an anisette error.**
The anisette server may be down. Pick another one in **Settings › Anisette server** and try again.

**It says the certificate limit is reached.**
Free Apple IDs can only have a few development certificates. AltLoad asks which one to revoke. Apps signed with the revoked certificate, for example by another computer, stop opening until they're signed again.

**It can't connect to the iPhone.**
Check that LocalDevVPN is connected, Developer Mode is on, and you've paired this iPhone in the Pair tab. If it still fails, pair again.

## Credits

AltLoad is built on the work of:

- [**idevice**](https://github.com/jkcoxson/idevice) by Jackson Coxson: device pairing, the tunnel, and file transfer and installation.
- [**isideload**](https://github.com/nab138/isideload) by nab138: Apple ID sign-in, developer services and code signing.
- [**StikPair**](https://github.com/StephenDev0/StikPair) by StephenDev0: the on-device pairing flow AltLoad is based on.
- [**LocalDevVPN**](https://github.com/jkcoxson/LocalDevVPN) by jkcoxson and Stossy11: the loopback VPN.
- [**AltStore**](https://altstore.io) by Riley Testut and Shane Gill. AltLoad downloads AltStore from its official source at install time and does not redistribute it.

## License

AltLoad keeps StikPair's **non-commercial MIT license**. See [LICENSE](LICENSE). Copyright (c) 2026 StephenDev0.

You may use, modify and share AltLoad for **non-commercial** purposes. Selling it or including it in a paid product requires written permission from the original author.
