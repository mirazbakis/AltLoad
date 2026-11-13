#!/bin/sh
# Builds altpair.wasm for rootshell and copies it to dist/.
set -eu
cd "$(dirname "$0")"
cargo build --release --target wasm32-wasip1
mkdir -p dist
cp target/wasm32-wasip1/release/altpair.wasm dist/altpair.wasm
ls -l dist/altpair.wasm
