//! altpair: a WASI program for rootshell's local shell. It pairs the iPhone
//! with itself through the iOS "Pair with …" row in Developer Mode settings,
//! saves `rp_pairing_file.plist`, and hands that file to the installer over
//! 127.0.0.1:47627.
//!
//! Modules that do not touch rootshell's host functions are plain Rust and are
//! unit-tested on the build machine with `cargo test`.

#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]

mod abi;
mod args;
mod bigdigits;
mod dns;
mod handoff;
mod ifconfig;
mod plistfix;

#[cfg(target_arch = "wasm32")]
mod app;
#[cfg(target_arch = "wasm32")]
mod host;

#[cfg(target_arch = "wasm32")]
fn main() {
    let code = app::main();
    let _ = std::io::Write::flush(&mut std::io::stdout());
    std::process::exit(code);
}

#[cfg(not(target_arch = "wasm32"))]
fn main() {
    println!("altpair runs inside rootshell on an iPhone.");
    println!("Build it with ./build.sh (wasm32-wasip1).");
    std::process::exit(1);
}
