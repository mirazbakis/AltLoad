#!/bin/bash
# Builds the Rust FFI shim for iOS (device + Apple-Silicon simulator) and
# repackages AltLoadFFI.xcframework. Run this whenever rust/ changes.
set -euo pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
# Match project.yml's deployment target, or the C parts (ring) are built for the
# SDK's iOS version and may not load on older devices.
export IPHONEOS_DEPLOYMENT_TARGET=18.0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/rust"

echo "==> Building Rust static libs (release)"
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

echo "==> Repackaging AltLoadFFI.xcframework"
rm -rf "$ROOT/AltLoadFFI.xcframework"
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libaltload_ffi.a -headers include \
  -library target/aarch64-apple-ios-sim/release/libaltload_ffi.a -headers include \
  -output "$ROOT/AltLoadFFI.xcframework"

echo "==> Done. (Re)generate the project with: xcodegen generate"
