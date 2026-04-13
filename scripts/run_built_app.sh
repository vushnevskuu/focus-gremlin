#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

TARGET="${1:-debug}"
case "$TARGET" in
  debug)
    APP_PATH="$(built_app_path Debug dev)"
    ;;
  release)
    APP_PATH="$(built_app_path Release release)"
    ;;
  *)
    APP_PATH="$TARGET"
    ;;
esac

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  echo "Build it first with bash scripts/dev.sh or bash scripts/build_release.sh" >&2
  exit 1
fi

killall FocusGremlin 2>/dev/null || true
open "$APP_PATH"
echo "Launched: $APP_PATH"
