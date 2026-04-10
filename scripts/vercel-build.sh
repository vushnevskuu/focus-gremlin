#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rm -rf dist
mkdir -p dist
cp -R docs/. dist/

# На Vercel подставляем реальный хост в canonical / Open Graph (VERCEL_URL без схемы).
if [[ -n "${VERCEL_URL:-}" ]]; then
  export SITE_BASE="https://${VERCEL_URL}"
  if command -v perl >/dev/null 2>&1; then
    LC_ALL=C LANG=C perl -pi -e 's|https://vushnevskuu.github.io/focus-gremlin|$ENV{SITE_BASE}|g' dist/index.html
  fi
fi
