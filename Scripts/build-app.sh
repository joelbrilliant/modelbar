#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CONFIGURATION=${1:-release}

swift build --package-path "$PROJECT_DIR" -c "$CONFIGURATION"

BUILD_DIR=$(swift build --package-path "$PROJECT_DIR" -c "$CONFIGURATION" --show-bin-path)
APP_DIR="$PROJECT_DIR/.build/ModelBar.app"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
install -m 755 "$BUILD_DIR/ModelBar" "$APP_DIR/Contents/MacOS/ModelBar"
install -m 644 "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"

printf '%s\n' "$APP_DIR"
