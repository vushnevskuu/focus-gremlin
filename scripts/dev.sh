#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

xcode_action build Debug dev
APP_PATH="$(built_app_path Debug dev)"
killall FocusGremlin 2>/dev/null || true
open "$APP_PATH"
echo "Launched: $APP_PATH"
