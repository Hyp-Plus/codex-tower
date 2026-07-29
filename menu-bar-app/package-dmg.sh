#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"

zsh ./build-app.sh

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-tower-dmg.XXXXXX")"
DMG_PATH="$SCRIPT_DIR/dist/Codex-Tower-${VERSION}-macos-arm64.dmg"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$SCRIPT_DIR/dist/Codex Tower.app" "$STAGING_DIR/Codex Tower.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Codex Tower" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

echo "Built: $DMG_PATH"
