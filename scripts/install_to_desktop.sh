#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
xcodebuild -scheme FocusGremlin -configuration Release -derivedDataPath ./build build -quiet
killall FocusGremlin 2>/dev/null || true
for p in \
  "$HOME/Desktop/FocusGremlin.app" \
  "$HOME/Desktop/Focus Gremlin.app" \
  "$HOME/Applications/FocusGremlin.app" \
  "$HOME/Applications/Focus Gremlin.app"
do
  rm -rf "$p"
done
DEST="$HOME/Desktop/Focus Gremlin.app"
cp -R ./build/Build/Products/Release/FocusGremlin.app "$DEST"
codesign --force --deep --sign - "$DEST" 2>/dev/null || true
xattr -cr "$DEST" 2>/dev/null || true
echo "Готово: $DEST"
