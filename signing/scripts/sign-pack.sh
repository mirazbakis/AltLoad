#!/usr/bin/env bash
#
# Sign one IPA with one cert pack (signing/certs/<N>/: a .p12 and a .mobileprovision).
# Used by both workflows: sign-ota.yml (every pack, for the site) and sign-ipa.yml
# (any IPA, one pack).
#
# Usage:
#   sign-pack.sh <pack_dir> <input.ipa> <new-bundle-id> <output.ipa>
#
# Env:
#   P12_PASSWORD       .p12 password (default WSF; "WSF!" is also tried)
#   KEYCHAIN_PASSWORD  password for the throwaway keychain
#
# Prints "STATUS=valid|revoked|expired|unverified" as its last line. Revoked and
# expired identities are signed with rcodesign (which must be on PATH), since
# Apple's codesign refuses them.

set -euo pipefail

PACK_DIR="${1%/}"
SRC_IPA="$2"
BUNDLE_ID="$3"
OUT_IPA="$4"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
: "${P12_PASSWORD:=WSF}"
: "${KEYCHAIN_PASSWORD:=ota-signing-temp}"
TMP="${RUNNER_TEMP:-$(mktemp -d)}"

shopt -s nullglob
p12s=( "$PACK_DIR"/*.p12 ); profiles=( "$PACK_DIR"/*.mobileprovision )
P12="${p12s[0]:-}"; PROFILE="${profiles[0]:-}"
if [ -z "$P12" ] || [ -z "$PROFILE" ]; then
  echo "$PACK_DIR needs one .p12 and one .mobileprovision" >&2
  exit 1
fi
NAME="$(basename "$PACK_DIR")"
OPENSSL="$(brew --prefix openssl@3 2>/dev/null)/bin/openssl"

# Import the .p12 into a keychain. Tries the password as given and with a trailing
# "!". macOS can't read .p12 files written with OpenSSL 3's default encryption, so
# if a direct import fails, re-export it in the legacy format first. On success
# SIGN_P12/SIGN_PW name the file and password that worked, for rcodesign.
import_identity() {
  local kc="$1" pw tmp="$TMP/legacy-$NAME"
  for pw in "$P12_PASSWORD" "${P12_PASSWORD}!"; do
    if security import "$P12" -P "$pw" -A -t cert -f pkcs12 -k "$kc"; then
      SIGN_P12="$P12"; SIGN_PW="$pw"; return 0
    fi
    if [ -x "$OPENSSL" ] \
      && "$OPENSSL" pkcs12 -in "$P12" -passin "pass:$pw" -nodes -out "$tmp.pem" 2>/dev/null \
      && "$OPENSSL" pkcs12 -export -legacy -in "$tmp.pem" -out "$tmp.p12" -passout "pass:$pw"; then
      rm -f "$tmp.pem"
      if security import "$tmp.p12" -P "$pw" -A -t cert -f pkcs12 -k "$kc"; then
        SIGN_P12="$tmp.p12"; SIGN_PW="$pw"; return 0
      fi
    fi
    rm -f "$tmp.pem" "$tmp.p12"
  done
  echo "could not import $(basename "$P12"): wrong password or unreadable .p12" >&2
  return 1
}

# A dedicated keychain per pack, so the identity is unambiguous.
KC="$TMP/kc-$NAME-$$.keychain-db"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KC"
trap 'security delete-keychain "$KC" 2>/dev/null || true' EXIT
security set-keychain-settings -lut 21600 "$KC"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KC"
import_identity "$KC"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KC" >/dev/null
security list-keychain -d user -s "$KC" login.keychain-db

PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES_DIR"
cp "$PROFILE" "$PROFILES_DIR/pack-$NAME.mobileprovision"

STATUS="valid"
HASH="$(security find-identity -v -p codesigning "$KC" | awk 'NR==1 && $2 ~ /^[0-9A-F]+$/ {print $2}')"
if [ -z "$HASH" ]; then
  # -v hides revoked and expired identities. Those are still signed (the owner
  # wants them published), with whatever identity is there.
  ALL="$(security find-identity -p codesigning "$KC")"
  HASH="$(printf '%s\n' "$ALL" | awk '$1 ~ /^[0-9]+\)$/ && $2 ~ /^[0-9A-F]+$/ {print $2; exit}')"
  case "$ALL" in
    *REVOKED*) STATUS="revoked" ;;
    *EXPIRED*) STATUS="expired" ;;
    *)         STATUS="unverified" ;;
  esac
fi
if [ -z "$HASH" ]; then
  echo "no codesigning identity in $(basename "$P12") after import" >&2
  exit 1
fi

if [ "$STATUS" = "valid" ]; then
  "$SCRIPTS/resign.sh" "$SRC_IPA" "$PROFILE" "$HASH" "$BUNDLE_ID" "$OUT_IPA"
else
  RCODESIGN_P12="$SIGN_P12" RCODESIGN_PASSWORD="$SIGN_PW" \
    "$SCRIPTS/resign.sh" "$SRC_IPA" "$PROFILE" "$HASH" "$BUNDLE_ID" "$OUT_IPA"
fi

echo "STATUS=$STATUS"
