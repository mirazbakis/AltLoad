# Third-party notices

AltLoad includes or is derived from the following software. Each is used under the license reproduced below.

| Project | How AltLoad uses it | License |
|---|---|---|
| [StikPair](https://github.com/StephenDev0/StikPair) by StephenDev0 | On-device pairing flow, pairing host FFI, build scripts. Derived files: `ios/App/Core/Pairing/PairingController.swift`, `KeepAlive.swift`, `LocalNetworkAuthorization.swift`, `AppleTVDiscovery.swift`, `core/src/lib.rs`, `scripts/build-rust.sh` | StikPair License (MIT, Non-Commercial) |
| [idevice](https://github.com/jkcoxson/idevice) by Jackson Coxson | Device pairing, tunnel, AFC, installation_proxy, Developer Disk Image mounting, debugserver (JIT) and location simulation. `core/src/lib.rs` is derived from its `ffi/src/pairable_host.rs` | MIT |
| [isideload](https://github.com/nab138/isideload) by nab138 | Apple ID sign-in, developer services and code signing (compiled into builds) | MIT |
| [apple-codesign-quick](https://crates.io/crates/apple-codesign-quick) | Code signing, pulled in by isideload and statically linked into builds. You may modify it and relink AltLoad with your version; see LICENSE.md section 4 | LGPL-2.1-or-later |

Builds also include the Rust crates these projects depend on. Each is under its own license, mostly MIT and/or Apache-2.0. Run `cargo about generate` or `cargo license` in `core/` to see the full list.

AltLoad does **not** include or redistribute [AltStore](https://altstore.io), [LocalDevVPN](https://github.com/jkcoxson/LocalDevVPN) or Apple's Developer Disk Image. AltStore is downloaded from its official source when you install it, LocalDevVPN is installed separately from the App Store, and the Developer Disk Image is downloaded from [doronz88/DeveloperDiskImage](https://github.com/doronz88/DeveloperDiskImage) the first time you use JIT or Location.

---

## StikPair License (MIT, Non-Commercial)

```
StikPair License (MIT, Non-Commercial)

Copyright (c) 2026 StephenDev0

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software for NON-COMMERCIAL purposes, including without limitation the rights
to use, copy, modify, merge, publish, and distribute copies of the Software, and
to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

COMMERCIAL USE of the Software — including, without limitation, selling it,
bundling it into a paid product or service, or otherwise using it to generate
revenue — is NOT permitted without prior written permission from the copyright
holder. For a commercial license, contact StephenDev0@outlook.com.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN
AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

---

## idevice (MIT)

```
Copyright 2026 Jackson Coxson

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

---

## isideload (MIT)

```
MIT License

Copyright (c) 2025 nab138

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
