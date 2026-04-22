#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="SmoothDial"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
RESOURCES="$CONTENTS/Resources"
SRC_RESOURCES="Sources/SmoothDial/Resources"

echo "==> Building release binary…"
swift build -c release

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$RESOURCES"

cp .build/release/"$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp Sources/SmoothDial/Info.plist "$CONTENTS/Info.plist"

echo "==> Generating app icon…"
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size "$SRC_RESOURCES/appicon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
done
cp "$ICONSET/icon_32x32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/icon_64x64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
rm "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

echo "==> Generating menu bar icon…"
sips -z 36 36 "$SRC_RESOURCES/MenuIcon.png" --out "$RESOURCES/MenuIcon.png" >/dev/null
sips -z 18 18 "$SRC_RESOURCES/MenuIcon.png" --out "$RESOURCES/MenuIcon@1x.png" >/dev/null

echo "==> Creating DMG…"
DMG_STAGING=$(mktemp -d)
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$BUILD_DIR/$APP_NAME.dmg" >/dev/null
rm -rf "$DMG_STAGING"

echo ""
echo "Done:"
echo "  $APP_BUNDLE"
echo "  $BUILD_DIR/$APP_NAME.dmg"
