#!/usr/bin/env bash
#
# Build one slot's OTA output: copy the signed IPA, write manifest.plist, and a
# meta.txt line-file that build-site.sh reads to make the install buttons.
#
# Usage:
#   build-manifest.sh <signed.ipa> <base_url> <out_dir> <slug> [icon.png] [title-override]
#
# Writes:
#   <out_dir>/installs/<slug>/app.ipa
#   <out_dir>/installs/<slug>/manifest.plist
#   <out_dir>/installs/<slug>/icon.png   (if an icon was given)
#   <out_dir>/installs/<slug>/meta.txt

set -euo pipefail

SIGNED_IPA="$1"
BASE_URL="${2%/}"
OUT_DIR="$3"
SLUG="$4"
ICON_SRC="${5:-}"
TITLE_OVERRIDE="${6:-}"

APP_OUT="$OUT_DIR/installs/$SLUG"
mkdir -p "$APP_OUT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q -o "$SIGNED_IPA" -d "$WORK"
APP_PATH="$(ls -d "$WORK"/Payload/*.app | head -n1)"
INFO="$APP_PATH/Info.plist"

pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null || true; }

BUNDLE_ID="$(pb CFBundleIdentifier)"
BUNDLE_VERSION="$(pb CFBundleShortVersionString)"
[ -z "$BUNDLE_VERSION" ] && BUNDLE_VERSION="$(pb CFBundleVersion)"
TITLE="$TITLE_OVERRIDE"
[ -z "$TITLE" ] && TITLE="$(pb CFBundleDisplayName)"
[ -z "$TITLE" ] && TITLE="$(pb CFBundleName)"
[ -z "$TITLE" ] && TITLE="$SLUG"

echo ">> [$SLUG] $TITLE  v$BUNDLE_VERSION  ($BUNDLE_ID)"

cp "$SIGNED_IPA" "$APP_OUT/app.ipa"

ICON_URL=""
if [ -n "$ICON_SRC" ] && [ -f "$ICON_SRC" ]; then
  cp "$ICON_SRC" "$APP_OUT/icon.png"
  ICON_URL="$BASE_URL/installs/$SLUG/icon.png"
fi

IPA_URL="$BASE_URL/installs/$SLUG/app.ipa"
MANIFEST_URL="$BASE_URL/installs/$SLUG/manifest.plist"

IMAGE_ASSETS=""
if [ -n "$ICON_URL" ]; then
  IMAGE_ASSETS="
        <dict>
          <key>kind</key><string>display-image</string>
          <key>url</key><string>${ICON_URL}</string>
        </dict>
        <dict>
          <key>kind</key><string>full-size-image</string>
          <key>url</key><string>${ICON_URL}</string>
        </dict>"
fi

cat > "$APP_OUT/manifest.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>${IPA_URL}</string>
        </dict>${IMAGE_ASSETS}
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>${BUNDLE_ID}</string>
        <key>bundle-version</key><string>${BUNDLE_VERSION}</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>${TITLE}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
EOF

{
  echo "SLUG=$SLUG"
  echo "TITLE=$TITLE"
  echo "VERSION=$BUNDLE_VERSION"
  echo "BUNDLE_ID=$BUNDLE_ID"
  echo "MANIFEST_URL=$MANIFEST_URL"
  echo "ICON_URL=$ICON_URL"
} > "$APP_OUT/meta.txt"
