#!/usr/bin/env bash
#
# Re-sign one IPA with a signing identity + provisioning profile, and rewrite
# its bundle identifier to a per-slot value (so AltLoad can be signed under
# com.mirazbakis.altload1 .. altload11, one per cert pack).
#
# Usage:
#   resign.sh <input.ipa> <profile.mobileprovision> <signing-identity> <new-bundle-id> <output.ipa>
#
# What it does:
#  - Rewrites the main app's CFBundleIdentifier to <new-bundle-id>.
#  - Rewrites each embedded app extension (PlugIns/*.appex) to
#    "<new-bundle-id>.<original-last-component>" (e.g. ...altload3.widgets),
#    keeping the required parent-prefix relationship.
#  - Embeds the provisioning profile and regenerates entitlements from it so the
#    main app's entitlements match what the profile allows.
#  - Signs nested code (frameworks, dylibs, app extensions) before the app.
#
# Note: extensions are signed with the identity only (no app-id entitlements),
# since each slot's profile targets the main app id. On a single-app explicit
# profile the widget may not activate; the main app is what the OTA link installs.

set -euo pipefail

INPUT_IPA="$1"
PROFILE="$2"
IDENTITY="$3"
NEW_BUNDLE_ID="$4"
OUTPUT_IPA="$5"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pb() { /usr/libexec/PlistBuddy "$@"; }

echo ">> Unpacking $(basename "$INPUT_IPA")"
unzip -q -o "$INPUT_IPA" -d "$WORK/extracted"

APP_PATH="$(ls -d "$WORK"/extracted/Payload/*.app 2>/dev/null | head -n1)"
if [ -z "$APP_PATH" ]; then
  echo "ERROR: No .app found inside Payload/"; exit 1
fi
echo ">> App bundle: $(basename "$APP_PATH")"

# --- Rewrite bundle identifiers -------------------------------------------
echo ">> Setting app bundle id -> $NEW_BUNDLE_ID"
pb -c "Set :CFBundleIdentifier $NEW_BUNDLE_ID" "$APP_PATH/Info.plist"

if [ -d "$APP_PATH/PlugIns" ]; then
  for EXT in "$APP_PATH"/PlugIns/*.appex; do
    [ -d "$EXT" ] || continue
    ORIG_EXT_ID="$(pb -c "Print :CFBundleIdentifier" "$EXT/Info.plist" 2>/dev/null || true)"
    SUFFIX="${ORIG_EXT_ID##*.}"
    [ -n "$SUFFIX" ] || SUFFIX="ext"
    NEW_EXT_ID="$NEW_BUNDLE_ID.$SUFFIX"
    echo "   - extension $(basename "$EXT") -> $NEW_EXT_ID"
    pb -c "Set :CFBundleIdentifier $NEW_EXT_ID" "$EXT/Info.plist"
  done
fi

# --- Embed profile + derive entitlements ----------------------------------
echo ">> Embedding provisioning profile"
cp "$PROFILE" "$APP_PATH/embedded.mobileprovision"

echo ">> Extracting entitlements from provisioning profile"
ENTITLEMENTS="$WORK/entitlements.plist"
security cms -D -i "$PROFILE" > "$WORK/profile.plist"
pb -x -c "Print :Entitlements" "$WORK/profile.plist" > "$ENTITLEMENTS"

# --- Revoked/expired identity: codesign won't use it, so sign with rcodesign -
# RCODESIGN_P12 / RCODESIGN_PASSWORD are set by the workflow for those packs.
# rcodesign signs nested bundles itself; unscoped entitlements apply to the app.
if [ -n "${RCODESIGN_P12:-}" ]; then
  echo ">> Signing with rcodesign (identity isn't valid for codesign)"
  printf '%s' "${RCODESIGN_PASSWORD:-}" > "$WORK/p12pw"
  rcodesign sign \
    --p12-file "$RCODESIGN_P12" \
    --p12-password-file "$WORK/p12pw" \
    --entitlements-xml-file "$ENTITLEMENTS" \
    "$APP_PATH"
  rm -f "$WORK/p12pw"
else

# --- Sign nested code first, then the app ---------------------------------
echo ">> Signing nested frameworks / dylibs"
find "$APP_PATH" \( -name "*.framework" -o -name "*.dylib" \) -print0 \
  | while IFS= read -r -d '' COMP; do
      echo "   - $(basename "$COMP")"
      codesign --force --sign "$IDENTITY" --timestamp=none "$COMP"
    done

echo ">> Signing app extensions"
find "$APP_PATH" -name "*.appex" -print0 \
  | while IFS= read -r -d '' COMP; do
      echo "   - $(basename "$COMP")"
      codesign --force --sign "$IDENTITY" --timestamp=none "$COMP"
    done

echo ">> Signing app bundle"
codesign --force --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$APP_PATH"

echo ">> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

echo ">> Repacking -> $(basename "$OUTPUT_IPA")"
mkdir -p "$(dirname "$OUTPUT_IPA")"
OUT_ABS="$(cd "$(dirname "$OUTPUT_IPA")" && pwd)/$(basename "$OUTPUT_IPA")"
rm -f "$OUT_ABS"
( cd "$WORK/extracted" && zip -q -r -y "$OUT_ABS" Payload )

echo ">> Done"
