#!/bin/bash
# Build "Gifford.app" from main.swift and install it to ~/Applications.
# Usage:
#   ./build.sh          build + install
#   ./build.sh --run    build + install + launch
#   INSTALL_DIR=/Applications ./build.sh   install somewhere else
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Gifford"
BINARY="Gifford"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"

echo "▶ Compiling…"
mkdir -p build
swiftc -O -swift-version 5 -o "build/$BINARY" main.swift

echo "▶ Quitting any running copy…"
pkill -f "/$BINARY$" 2>/dev/null || true

echo "▶ Assembling bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "build/$BINARY" "$APP_BUNDLE/Contents/MacOS/$BINARY"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "▶ Ad-hoc signing…"
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ Installed: $APP_BUNDLE"

if [[ "${1:-}" == "--run" ]]; then
    echo "▶ Launching…"
    open "$APP_BUNDLE"
fi
