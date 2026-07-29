#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"
swift build -c release

APP_PATH="$SCRIPT_DIR/dist/Codex Tower.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$SCRIPT_DIR/.build/release/CodexTower" "$APP_PATH/Contents/MacOS/CodexTower"
cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$SCRIPT_DIR/../server/sync-existing.mjs" "$APP_PATH/Contents/Resources/sync-existing.mjs"
cp "$SCRIPT_DIR/../server/task-store.mjs" "$APP_PATH/Contents/Resources/task-store.mjs"
codesign --force --sign - "$APP_PATH"
echo "Built: $APP_PATH"
