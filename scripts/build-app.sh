#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TASK_ROOT/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$TASK_ROOT/.build/cache" "$TASK_ROOT/.build/config" "$TASK_ROOT/.build/security"
swift build --disable-sandbox --cache-path "$TASK_ROOT/.build/cache" --config-path "$TASK_ROOT/.build/config" --security-path "$TASK_ROOT/.build/security" -c release
TASK_BIN="$(swift build --disable-sandbox --cache-path "$TASK_ROOT/.build/cache" --config-path "$TASK_ROOT/.build/config" --security-path "$TASK_ROOT/.build/security" -c release --show-bin-path)"
TASK_BUNDLE="$TASK_ROOT/dist/ShareSafe.app"
mkdir -p "$TASK_BUNDLE/Contents/MacOS" "$TASK_BUNDLE/Contents/Resources"
cp "$TASK_BIN/ShareSafe" "$TASK_BUNDLE/Contents/MacOS/ShareSafe"
cp "$TASK_ROOT/Resources/Info.plist" "$TASK_BUNDLE/Contents/Info.plist"
if [[ -f "$TASK_ROOT/ChromeExtension/manifest.json" ]]; then
  mkdir -p "$TASK_BUNDLE/Contents/Resources/ChromeExtension"
  # Bundle only runtime files and the local installation guide.
  for TASK_EXTENSION_FILE in manifest.json background.js content.js help.html help.css help.js INSTALL.html README.md; do
    if [[ -f "$TASK_ROOT/ChromeExtension/$TASK_EXTENSION_FILE" ]]; then
      cp "$TASK_ROOT/ChromeExtension/$TASK_EXTENSION_FILE" "$TASK_BUNDLE/Contents/Resources/ChromeExtension/"
    fi
  done
  if [[ -f "$TASK_ROOT/ChromeExtension/demo/index.html" ]]; then
    mkdir -p "$TASK_BUNDLE/Contents/Resources/ChromeExtension/demo"
    cp "$TASK_ROOT/ChromeExtension/demo/index.html" "$TASK_BUNDLE/Contents/Resources/ChromeExtension/demo/index.html"
  fi
  TASK_EXTENSION_ZIP="$TASK_ROOT/dist/ShareSafe-Chrome.zip"
  # Recreate the development archive so removed runtime files cannot linger.
  if [[ -f "$TASK_EXTENSION_ZIP" ]]; then rm "$TASK_EXTENSION_ZIP"; fi
  (cd "$TASK_BUNDLE/Contents/Resources/ChromeExtension" && /usr/bin/zip -qr "$TASK_EXTENSION_ZIP" . -x '.*')
fi
codesign --force --sign - "$TASK_BUNDLE"
codesign --verify --strict "$TASK_BUNDLE"
printf 'Built %s\n' "$TASK_BUNDLE"
