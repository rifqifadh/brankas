#!/bin/bash
set -euo pipefail

APP_NAME="Brankas"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/.build/$APP_NAME.app"

echo "Killing previous instance..."
pkill -9 -f "$APP_NAME.app" 2>/dev/null || true
sleep 0.3

echo "Building (debug)..."
swift build --product "$APP_NAME"

echo "Creating app bundle..."
BIN_PATH=$(swift build --show-bin-path 2>/dev/null)/$APP_NAME
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$PROJECT_DIR/Sources/Brankas/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "Opening $APP_NAME..."
open "$APP_BUNDLE"
