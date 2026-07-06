#!/bin/bash
set -euo pipefail

APP_NAME="Brankas"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(plutil -extract CFBundleShortVersionString raw -o - "$PROJECT_DIR/Info.plist" 2>/dev/null || echo "1.0")
OUTPUT_DIR="$PROJECT_DIR/release"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION.dmg"

echo "Killing previous instance..."
pkill -9 -f "$APP_NAME.app" 2>/dev/null || true
sleep 0.3

echo "Building (release)..."
swift build -c release --product "$APP_NAME"

echo "Creating app bundle..."
BIN_PATH=$(swift build -c release --show-bin-path 2>/dev/null)/$APP_NAME
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "Signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Creating DMG..."
STAGING_DIR=$(mktemp -d)
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -format UDZO -imagekey zlib-level=9 "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo ""
echo "✅ Release build complete:"
echo "   DMG: $DMG_PATH"
echo "   App: $APP_BUNDLE"
echo ""
echo "To open: open \"$DMG_PATH\""
