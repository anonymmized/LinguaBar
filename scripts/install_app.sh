#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="$ROOT_DIR/build/LinguaBar.app"
APP_TARGET="/Applications/LinguaBar.app"

"$ROOT_DIR/scripts/build_app.sh"
codesign --force --deep --sign - "$APP_SOURCE"
rm -rf "$APP_TARGET"
cp -R "$APP_SOURCE" "$APP_TARGET"
xattr -dr com.apple.quarantine "$APP_TARGET" 2>/dev/null || true
open "$APP_TARGET"

echo "$APP_TARGET"
