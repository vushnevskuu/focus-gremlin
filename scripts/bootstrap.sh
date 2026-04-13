#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"

ensure_command xcodebuild
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode command line tools are not configured. Open Xcode once, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

ensure_project

echo "Tooling looks good."
echo "Next steps:"
echo "  bash scripts/dev.sh"
echo "  bash scripts/test.sh"
