#!/usr/bin/env bash
set -euo pipefail

# Создаёт на Рабочем столе псевдоним (alias) на FocusGremlin.app.
# Использование:
#   ./create_desktop_shortcut.sh
#   ./create_desktop_shortcut.sh /полный/путь/к/FocusGremlin.app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP="$HOME/Desktop"

if [[ "${1-}" != "" ]]; then
  APP_PATH="$1"
else
  # Типичный путь после сборки в папку проекта
  APP_PATH="$SCRIPT_DIR/build/Build/Products/Debug/FocusGremlin.app"
  if [[ ! -d "$APP_PATH" ]]; then
    APP_PATH="$SCRIPT_DIR/build/Build/Products/Release/FocusGremlin.app"
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Не найден FocusGremlin.app по пути: $APP_PATH"
  echo "Соберите проект в Xcode или выполните:"
  echo "  cd \"$SCRIPT_DIR\" && xcodebuild -scheme FocusGremlin -configuration Debug -derivedDataPath ./build -destination 'platform=macOS' build"
  echo "Затем снова запустите скрипт или передайте путь к .app первым аргументом."
  exit 1
fi

osascript <<EOF
tell application "Finder"
  set appFile to POSIX file "$APP_PATH" as alias
  set desk to POSIX file "$DESKTOP" as alias
  make alias file to appFile at desk with properties {name:"Focus Gremlin"}
end tell
EOF

echo "Готово: на рабочем столе появился ярлык «Focus Gremlin»."
