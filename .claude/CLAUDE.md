# AltLoad

iOS 27 app that signs and installs AltStore, SideStore and LiveContainer on the iPhone itself. SwiftUI front end, Rust core (pairing, tunnel, Apple ID sign-in, signing, installing) linked as a static library through a C FFI.

## Layout

- `App/AltLoadApp.swift`: entry point and tab bar (Install, Tools, About; Settings is a sheet behind the gear on every tab).
- `App/Core/`: logic, no views.
  - `Install/`: `InstallController` (install flow, Rust bridge), `StoreCatalog` (stores, sources, fallbacks, IPA cache), `Entitlements` (capability settings).
  - `Account/`: Apple ID storage, anisette server list and health checks, certificate manager bridge.
  - `Device/`: device ops over the tunnel, Developer Disk Image, LocalDevVPN, location simulation.
  - `Pairing/`: pairing host, saved pairing files, Apple TV discovery, background keep-alive.
  - `AltServer/`: the on-device AltServer AltStore talks to.
- `App/Features/<Tab>/`: SwiftUI screens only.
- `App/UI/`: `Theme.swift` (palette, still named `Aurora`), `Background.swift`, `Components.swift` (shared views; some keep old `Glass*` names).
- `rust/src/lib.rs`: pairing host FFI. `rust/src/install/`: install and account sessions, split into `sign_in`, `storage`, `tunnel`, `bundle`, `prompts`, `account`, `device`.
- `rust/include/altload.h`: the C header Swift imports as `AltLoadFFI`. Keep it in sync with every `#[no_mangle]` function.
- `docs/releases/<tag>.md`: release notes, used as the GitHub release body.

## Build

```sh
bash scripts/build-rust.sh     # Rust → AltLoadFFI.xcframework (needed after any rust/ change)
xcodegen generate              # project.yml → AltLoad.xcodeproj (needed after adding/moving files)
xcodebuild -project AltLoad.xcodeproj -scheme AltLoad -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
```

`AltLoad.xcodeproj`, `AltLoadFFI.xcframework`, `build/` and `rust/target/` are generated and git-ignored.

## Conventions

- Bundle ID `com.mirazbakis.altload`. Version and build number live in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
- Commits are authored as the owner's own git identity. No co-author or "Generated with" trailers on commits or PRs.
- The owner pushes through GitHub Desktop; there are no GitHub credentials in the shell.
- CI (`.github/workflows/build.yml`) runs only when started by hand. See the `release` skill.
- UI: midnight background with one navy spotlight, solid `cardSurface()` cards, `AltLoadButtonStyle` buttons at least 44 pt tall. No glass on content.
- Anisette: default is `AnisetteServers.automatic`; anything that needs a server URL must go through `AnisetteServers.signInList(preferred:)`, never use `anisetteURL` directly.
- Comments explain why, in plain sentences, like the surrounding code.
