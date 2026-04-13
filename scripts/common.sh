#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/FocusGremlin.xcodeproj"
SCHEME="FocusGremlin"
DESTINATION="platform=macOS"
DERIVED_BASE="$ROOT/.derivedDataBuild"

ensure_command() {
  local name="${1:?command name required}"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Required command not found: $name" >&2
    exit 1
  fi
}

ensure_project() {
  if [[ ! -d "$PROJECT" ]]; then
    if ! command -v xcodegen >/dev/null 2>&1; then
      echo "FocusGremlin.xcodeproj is missing and xcodegen is not installed." >&2
      echo "Install xcodegen with: brew install xcodegen" >&2
      exit 1
    fi
    echo "Generating Xcode project from project.yml"
    (cd "$ROOT" && xcodegen generate)
    return
  fi

  if command -v xcodegen >/dev/null 2>&1 && [[ "$ROOT/project.yml" -nt "$PROJECT/project.pbxproj" ]]; then
    echo "project.yml is newer than FocusGremlin.xcodeproj; regenerating project"
    (cd "$ROOT" && xcodegen generate)
  fi
}

derived_dir_for() {
  local bucket="${1:?bucket required}"
  printf '%s\n' "$DERIVED_BASE/$bucket"
}

built_app_path() {
  local configuration="${1:?configuration required}"
  local bucket="${2:?bucket required}"
  printf '%s\n' "$DERIVED_BASE/$bucket/Build/Products/$configuration/FocusGremlin.app"
}

xcode_action() {
  local action="${1:?action required}"
  local configuration="${2:?configuration required}"
  local bucket="${3:?bucket required}"
  ensure_command xcodebuild
  ensure_project

  xcodebuild \
    "$action" \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$configuration" \
    -derivedDataPath "$(derived_dir_for "$bucket")" \
    -destination "$DESTINATION"
}
