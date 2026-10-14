#!/bin/bash
set -euo pipefail
SHARESAFE_EXTENSION_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHARESAFE_OUTPUT="$SHARESAFE_EXTENSION_ROOT/dist"
SHARESAFE_STAGE="$(mktemp -d)"
trap 'rm -rf "$SHARESAFE_STAGE"' EXIT
mkdir -p "$SHARESAFE_OUTPUT" "$SHARESAFE_STAGE/ChromeExtension/demo"
for file in manifest.json background.js content.js help.html help.css help.js INSTALL.html README.md; do
  cp "$SHARESAFE_EXTENSION_ROOT/$file" "$SHARESAFE_STAGE/ChromeExtension/$file"
done
cp "$SHARESAFE_EXTENSION_ROOT/demo/index.html" "$SHARESAFE_STAGE/ChromeExtension/demo/index.html"
rm -f "$SHARESAFE_OUTPUT/ShareSafe-Companion.zip"
(cd "$SHARESAFE_STAGE" && zip -qr "$SHARESAFE_OUTPUT/ShareSafe-Companion.zip" ChromeExtension)
echo "Created $SHARESAFE_OUTPUT/ShareSafe-Companion.zip"
