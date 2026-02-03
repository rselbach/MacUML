#!/bin/bash
# Assembles MacUML.app bundle from SwiftPM build output

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/.build/arm64-apple-macosx/debug"
APP_BUNDLE="$BUILD_DIR/MacUML.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$PROJECT_ROOT/Sources/Info.plist" "$APP_BUNDLE/Contents/"
cp "$BUILD_DIR/MacUML" "$APP_BUNDLE/Contents/MacOS/"
cp "$BUILD_DIR/MacUML_MacUML.bundle/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "Built: $APP_BUNDLE"
