#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

bash "$ROOT/scripts/build_release.sh" >/dev/null
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
cp -R "$(built_app_path Release release)" "$DEST"
codesign --force --deep --sign - "$DEST" 2>/dev/null || true
xattr -cr "$DEST" 2>/dev/null || true
echo "Готово: $DEST"
