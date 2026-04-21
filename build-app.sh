#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="SmoothDial"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

echo "==> Building release binary…"
swift build -c release

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS"

cp .build/release/"$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
cp Sources/SmoothDial/Info.plist "$CONTENTS/Info.plist"

echo ""
echo "Done: $APP_BUNDLE"
echo "Install with:  cp -R \"$APP_BUNDLE\" /Applications/"
