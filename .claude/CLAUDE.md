# AltLoad

App (iOS 18+, on-device pairing on iOS 27+) that signs and installs AltStore, SideStore and LiveContainer on the iPhone itself. SwiftUI front end, Rust core (pairing, tunnel, Apple ID sign-in, signing, installing) linked as a static library through a C FFI.

## Layout

- `ios/App/AltLoadApp.swift`: entry point and tab bar (Install, Tools, About; Settings is a sheet behind the gear on every tab).
- `ios/App/Core/`: logic, no views.
  - `Install/`: `InstallController` (install flow, Rust bridge, `ExtensionsMode`), `StoreCatalog` (stores, sources, fallbacks, IPA cache), `Entitlements` (capability settings).
  - `Account/`: Apple ID storage, anisette server list and health checks, certificate manager bridge.
  - `Device/`: device ops over the tunnel, Developer Disk Image, LocalDevVPN, location simulation.
  - `Pairing/`: pairing host, saved pairing files, Apple TV discovery, background keep-alive, the pairing-code Live Activity.
  - `AltServer/`: the on-device AltServer AltStore talks to.
- `ios/App/Features/<Tab>/`: SwiftUI screens only. Install shows the installed apps ("Your Apps"); Tools › Pair lists every saved pairing file; Tools › Entitlements; Tools › App IDs (list + refresh, shares the Certificates session); Tools › Pairing File to Apps only offers sideloaded (development-signed) apps.
- `ios/Shared/`: code compiled into both the app and the widget extension (`PairingActivityAttributes`).
- `ios/Widgets/`: `AltLoadWidgets` extension that draws the pairing code in the Dynamic Island and on the Lock Screen.
- `ios/App/UI/`: `Theme.swift` (palette, still named `Aurora`), `Background.swift`, `Components.swift` (shared views; some keep old `Glass*` names).
- `core/src/lib.rs`: pairing host FFI. `core/src/install/`: install and account sessions, split into `sign_in`, `storage`, `tunnel`, `bundle`, `extensions` (keep / main profile / remove), `prompts`, `account`, `device`.
- `core/include/altload.h`: the C header Swift imports as `AltLoadFFI`. Keep it in sync with every `#[no_mangle]` function and `#[repr(C)]` struct.
- `site/`: the GitHub Pages install page. `signing/`: cert packs (never open them) and the scripts both signing workflows use.
- `docs/releases/<tag>.md`: release notes, used as the GitHub release body.

## Build

```sh
bash scripts/build-rust.sh     # Rust → AltLoadFFI.xcframework (needed after any core/ change)
xcodegen generate              # project.yml → AltLoad.xcodeproj (needed after adding/moving files)
xcodebuild -project AltLoad.xcodeproj -scheme AltLoad -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
```

`AltLoad.xcodeproj`, `AltLoadFFI.xcframework`, `build/` and `core/target/` are generated and git-ignored.

## Conventions

- Bundle ID `com.mirazbakis.altload` (widgets: `com.mirazbakis.altload.widgets`). Version and build number live in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`); `ALTLOAD_PRERELEASE` ("beta 1", or empty) is shown after the version in About.
- Deployment target is iOS 18.0 (also `IPHONEOS_DEPLOYMENT_TARGET` in `scripts/build-rust.sh`). Guard iOS 26/27 APIs with `#available`; on-device pairing is gated by `PairingController.canPairOnDevice`, and older versions import a pairing file instead.
- Commits are authored as the owner's own git identity. No co-author or "Generated with" trailers on commits or PRs.
- The owner pushes through GitHub Desktop; there are no GitHub credentials in the shell.
- CI (`.github/workflows/build.yml`) runs only when started by hand. See the `release` skill. `sign-ota.yml` re-signs every cert pack and deploys `site/` (on push, release and weekly); `sign-ipa.yml` signs any IPA with one pack into an artifact.
- License is proprietary (LICENSE.md v3). Keep the LGPL carve-out for apple-codesign-quick.
- UI: midnight background with one navy spotlight, solid `cardSurface()` cards, Liquid Glass `AltLoadButtonStyle` buttons at least 44 pt tall (`liquidGlass(tint:in:)` falls back to material before iOS 26). Icons (`IconTile`) are plain symbols with no tile behind them; prefer symbols without a built-in box or circle.
- Anisette: default is `AnisetteServers.automatic`; anything that needs a server URL must go through `AnisetteServers.signInList(preferred:)`, never use `anisetteURL` directly.
- Comments explain why, in plain sentences, like the surrounding code.
