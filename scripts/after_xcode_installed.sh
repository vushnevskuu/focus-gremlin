#!/usr/bin/env bash
# Запусти после того, как Xcode появится в /Applications (из App Store или xcodes).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -d "/Applications/Xcode.app" ]]; then
  echo "Нет /Applications/Xcode.app — сначала установи Xcode (App Store открыт командой: open macappstore://...)."
  exit 1
fi

echo "Нужен пароль администратора для xcode-select и первого запуска инструментов."
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept || true
xcodebuild -runFirstLaunch || true

cd "$ROOT"
bash scripts/bootstrap.sh
bash scripts/dev.sh
