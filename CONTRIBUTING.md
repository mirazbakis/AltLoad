# Contributing

Bug reports, fixes and translations are welcome. For a larger change, open an issue first so we can agree on the approach.

## Reporting a bug

Use the [bug report form](https://github.com/mirazbakis/AltLoad/issues/new/choose) and paste the log from **Settings › Logs**. Say which iOS version and iPhone you have, and how you installed AltLoad. Report security issues privately, as described in [SECURITY.md](SECURITY.md).

## Building

You need Xcode, Rust with the `aarch64-apple-ios` and `aarch64-apple-ios-sim` targets, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make test     # Rust tests for the core and altpair
make sim      # a Simulator build
make ipa      # build/AltLoad.ipa, ad-hoc signed like the release builds
make altpair  # altpair.wasm and the altpair installer
```

`AltLoad.xcodeproj` is generated from `project.yml`; don't edit it by hand. Installing, JIT and pairing need a real iPhone with LocalDevVPN. The Simulator is useful for the interface.

## Project layout

| Path | Contents |
| :-- | :-- |
| `ios/App/Core/` | App logic: installing, sources, pairing, JIT, AltServer, logging |
| `ios/App/Features/` | Screens, one folder per tab plus Settings |
| `ios/App/UI/` | Shared components and the theme |
| `ios/Shared/Localizable.xcstrings` | Translations for the app and the Live Activity |
| `core/` | The Rust core: pairing, the device tunnel, sign-in, signing and installing, exposed to Swift over C FFI |
| `altpair/` | The tools that install AltLoad with an Apple ID, without a computer |
| `site/` | altload.org |
| `docs/` | How it works, guides and release notes |

[How it works](docs/HOW-IT-WORKS.md) walks through an install from pairing to the finished app.

## Pull requests

- Keep each pull request to one change, and describe what it changes and how you tested it.
- Run `make test`, and build for the Simulator if you changed Swift code.
- Add new interface text to `Localizable.xcstrings` with translations for every language the app has, or leave it in English and say so.
- Write plainly in interface text and docs: say what happens and what to do next.

By submitting a contribution, you agree to the terms in [LICENSE.md](LICENSE.md).

## Translations

AltLoad is in English, Chinese, French, German, Italian, Japanese, Korean, Portuguese (Brazil), Russian and Spanish. To fix or add a translation, edit `ios/Shared/Localizable.xcstrings` in Xcode, or the `README.*.md` files for the readme.
