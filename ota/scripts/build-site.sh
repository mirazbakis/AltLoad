#!/usr/bin/env bash
#
# Assemble the Pages site: copy the static web/ pages into _site, then emit
# installs/index.json describing every signed slot. The landing page fetches
# that JSON and renders one install button per slot.
#
# Usage:
#   build-site.sh <web_dir> <out_dir>
#
# Expects per-slot output already written under <out_dir>/installs/<slug>/ by
# build-manifest.sh (each with a meta.txt).

set -euo pipefail

WEB_DIR="$1"
OUT_DIR="$2"

mkdir -p "$OUT_DIR"
# Copy static site (index.html, terms.html, assets, images) into the artifact.
cp -R "$WEB_DIR"/. "$OUT_DIR"/

# JSON-escape a string value (backslash, double-quote, tab, newline).
json_esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'
}
read_meta() { grep -E "^$1=" "$2" | head -n1 | cut -d= -f2-; }

INDEX="$OUT_DIR/installs/index.json"
mkdir -p "$OUT_DIR/installs"

SLOTS=""
COUNT=0
for meta in "$OUT_DIR"/installs/*/meta.txt; do
  [ -f "$meta" ] || continue

  SLUG="$(read_meta SLUG "$meta")"
  TITLE="$(read_meta TITLE "$meta")"
  VERSION="$(read_meta VERSION "$meta")"
  BUNDLE_ID="$(read_meta BUNDLE_ID "$meta")"
  MANIFEST_URL="$(read_meta MANIFEST_URL "$meta")"
  ICON_URL="$(read_meta ICON_URL "$meta")"
  INSTALL_URL="itms-services://?action=download-manifest&url=${MANIFEST_URL}"

  OBJ="$(cat <<JSON
    {
      "slug": "$(json_esc "$SLUG")",
      "title": "$(json_esc "$TITLE")",
      "version": "$(json_esc "$VERSION")",
      "bundleId": "$(json_esc "$BUNDLE_ID")",
      "manifestUrl": "$(json_esc "$MANIFEST_URL")",
      "iconUrl": "$(json_esc "$ICON_URL")",
      "installUrl": "$(json_esc "$INSTALL_URL")"
    }
JSON
)"

  if [ "$COUNT" -eq 0 ]; then SLOTS="$OBJ"; else SLOTS="$SLOTS,
$OBJ"; fi
  COUNT=$((COUNT+1))
done

cat > "$INDEX" <<JSON
{
  "app": "AltLoad",
  "generatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "count": $COUNT,
  "slots": [
$SLOTS
  ]
}
JSON

echo ">> Wrote $INDEX with $COUNT slot(s)"
