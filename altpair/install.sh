#!/bin/sh
# Installs altpair, then runs it to install AltLoad onto the iPhone this runs on,
# signed with your own Apple ID.
#
# In the Open Minis terminal on the iPhone, with LocalDevVPN connected:
#
#   wget -qO- https://mirazbakis.github.io/AltLoad/install.sh | sh
#
# Arguments after "sh -s --" are passed to altpair, for example:
#
#   wget -qO- https://mirazbakis.github.io/AltLoad/install.sh | sh -s -- --repair
#
# altpair is downloaded from AltLoad's latest release, checked against its
# published SHA-256, and kept in ~/.altload/bin. Nothing is installed unless the
# checksum matches, and nothing is left behind when a step fails.

set -eu

BASE="https://github.com/mirazbakis/AltLoad/releases/latest/download"
BIN_NAME="altpair-aarch64"

fail() {
    printf 'install.sh: %s\n' "$1" >&2
    exit 1
}

[ -n "${HOME:-}" ] || fail "HOME is not set."

DIR="$HOME/.altload"
BIN_DIR="$DIR/bin"
TARGET="$BIN_DIR/altpair"

case "$(uname -s)" in
    Linux) ;;
    *) fail "run this in the Open Minis terminal on the iPhone (this is $(uname -s))." ;;
esac

case "$(uname -m)" in
    aarch64 | arm64) ;;
    *) fail "altpair runs on 64-bit ARM only (this is $(uname -m))." ;;
esac

# fetch URL FILE: downloads with a connect timeout, an overall limit and retries.
if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 2 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q -T 30 -t 3 -O "$2" "$1"; }
else
    fail "needs curl or wget. Install one with: apk add curl"
fi

command -v sha256sum >/dev/null 2>&1 || fail "needs sha256sum."

umask 077
mkdir -p "$BIN_DIR" || fail "couldn't create $BIN_DIR."
chmod 700 "$DIR"

# Leftovers from a run that was cut off.
rm -rf "$DIR"/install.* 2>/dev/null || true

TMP="$(mktemp -d "$DIR/install.XXXXXX")" || fail "couldn't make a temporary folder (is the storage full?)."
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 130' INT TERM HUP

# Runs altpair. When this script arrives through a pipe, stdin is the script
# itself, so give altpair the terminal to read from.
run_altpair() {
    if [ -t 0 ]; then
        exec "$TARGET" "$@"
    elif (: </dev/tty) 2>/dev/null; then
        exec "$TARGET" "$@" </dev/tty
    else
        fail "no terminal to read from. Run $TARGET yourself."
    fi
}

# Without the network, an altpair that is already here still works.
# use_existing MESSAGE [altpair arguments...]
use_existing() {
    msg="$1"
    shift
    if [ -x "$TARGET" ]; then
        printf 'install.sh: %s\n' "$msg" >&2
        echo "Using the altpair already installed."
        echo
        run_altpair "$@"
    fi
    fail "$msg"
}

echo "Downloading altpair…"
# The checksum is small, so it also tells "no network" from "no such file".
if ! fetch "$BASE/$BIN_NAME.sha256" "$TMP/$BIN_NAME.sha256"; then
    if ! fetch "https://github.com" "$TMP/probe" 2>/dev/null; then
        use_existing "can't reach github.com. Check Wi-Fi, and that LocalDevVPN isn't blocking DNS." "$@"
    fi
    use_existing "this release has no $BIN_NAME.sha256 yet. Try again later." "$@"
fi
fetch "$BASE/$BIN_NAME" "$TMP/$BIN_NAME" || use_existing "couldn't download $BIN_NAME. Check your connection and run this again." "$@"
[ -s "$TMP/$BIN_NAME" ] || fail "the download of $BIN_NAME was empty. Run this again."

# The .sha256 file holds the hash, optionally followed by a file name.
expected="$(cut -d ' ' -f 1 <"$TMP/$BIN_NAME.sha256" | tr -d '\r\n' | tr 'A-F' 'a-f')"
actual="$(sha256sum "$TMP/$BIN_NAME" | cut -d ' ' -f 1)"
case "$expected" in
    *[!0-9a-f]* | "") fail "the published checksum is not a SHA-256." ;;
esac
[ "${#expected}" -eq 64 ] || fail "the published checksum is not a SHA-256."
[ "$expected" = "$actual" ] || fail "checksum mismatch, so altpair was not installed. Run this again; if it repeats, tell us."

chmod 755 "$TMP/$BIN_NAME"
# Same folder tree, so this replaces the old file in one step.
mv -f "$TMP/$BIN_NAME" "$TARGET" || fail "couldn't write $TARGET."

if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    ln -sf "$TARGET" /usr/local/bin/altpair
fi

rm -rf "$TMP"
trap - EXIT INT TERM HUP

echo "altpair installed in $TARGET"
echo

run_altpair "$@"
