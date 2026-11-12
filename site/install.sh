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
# published SHA-256, and kept in ~/.altload/bin.

set -eu

BASE="https://github.com/mirazbakis/AltLoad/releases/latest/download"
BIN_NAME="altpair-aarch64"
DIR="$HOME/.altload"
BIN_DIR="$DIR/bin"
TARGET="$BIN_DIR/altpair"

fail() {
    printf 'install.sh: %s\n' "$1" >&2
    exit 1
}

case "$(uname -m)" in
    aarch64 | arm64) ;;
    *) fail "altpair runs on 64-bit ARM only (this is $(uname -m))." ;;
esac

if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL --retry 2 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q -O "$2" "$1"; }
else
    fail "needs curl or wget."
fi

command -v sha256sum >/dev/null 2>&1 || fail "needs sha256sum."

umask 077
mkdir -p "$BIN_DIR"
chmod 700 "$DIR"

TMP="$(mktemp -d "$DIR/install.XXXXXX")" || fail "couldn't make a temporary folder."
trap 'rm -rf "$TMP"' EXIT
trap 'rm -rf "$TMP"; exit 130' INT TERM HUP

echo "Downloading altpair…"
fetch "$BASE/$BIN_NAME" "$TMP/$BIN_NAME" || fail "couldn't download $BIN_NAME."
fetch "$BASE/$BIN_NAME.sha256" "$TMP/$BIN_NAME.sha256" || fail "couldn't download $BIN_NAME.sha256."

# The .sha256 file holds the hash, optionally followed by a file name.
expected="$(cut -d ' ' -f 1 <"$TMP/$BIN_NAME.sha256" | tr -d '\r\n' | tr 'A-F' 'a-f')"
actual="$(sha256sum "$TMP/$BIN_NAME" | cut -d ' ' -f 1)"
case "$expected" in
    *[!0-9a-f]* | "") fail "the published checksum is not a SHA-256." ;;
esac
[ "${#expected}" -eq 64 ] || fail "the published checksum is not a SHA-256."
[ "$expected" = "$actual" ] || fail "checksum mismatch; not installing."

chmod 755 "$TMP/$BIN_NAME"
mv -f "$TMP/$BIN_NAME" "$TARGET"

if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    ln -sf "$TARGET" /usr/local/bin/altpair
fi

rm -rf "$TMP"
trap - EXIT INT TERM HUP

echo "altpair installed in $TARGET"
echo

# When this script arrives through a pipe, stdin is the script itself, so give
# altpair the terminal to read from.
if [ -t 0 ]; then
    exec "$TARGET" "$@"
elif (: </dev/tty) 2>/dev/null; then
    exec "$TARGET" "$@" </dev/tty
else
    fail "no terminal to read from. Run $TARGET yourself."
fi
