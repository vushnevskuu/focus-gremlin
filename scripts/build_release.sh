#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

xcode_action build Release release
echo "Release app: $(built_app_path Release release)"
