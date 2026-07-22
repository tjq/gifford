#!/bin/bash
# Build, sign, notarize, and package Gifford for a GitHub release.
#
# One-time setup:
#   1. Install your "Developer ID Application" certificate in the login keychain
#      (Xcode → Settings → Accounts → Manage Certificates, or developer.apple.com).
#   2. xcrun notarytool store-credentials gifford-notary \
#        --apple-id <apple-id-email> --team-id <TEAMID>
#      (uses an app-specific password from appleid.apple.com)
#
# Usage: ./release.sh            → dist/Gifford-<version>.zip, signed + notarized + stapled
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Gifford"
BINARY="Gifford"
PROFILE="${NOTARY_PROFILE:-gifford-notary}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DIST="dist"
APP_BUNDLE="$DIST/$APP_NAME.app"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [[ -z "$IDENTITY" ]]; then
    echo "✗ No 'Developer ID Application' identity found in the keychain." >&2
    exit 1
fi
echo "▶ Signing identity: $IDENTITY"

echo "▶ Compiling universal binary…"
rm -rf "$DIST" build/release
mkdir -p "$DIST" build/release
swiftc -O -swift-version 5 -target arm64-apple-macos11  -o build/release/$BINARY-arm64  main.swift
swiftc -O -swift-version 5 -target x86_64-apple-macos11 -o build/release/$BINARY-x86_64 main.swift
lipo -create -output "build/release/$BINARY" "build/release/$BINARY-arm64" "build/release/$BINARY-x86_64"

echo "▶ Assembling bundle…"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "build/release/$BINARY" "$APP_BUNDLE/Contents/MacOS/$BINARY"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "▶ Signing…"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

echo "▶ Zipping…"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP"

echo "▶ Notarizing (profile: $PROFILE)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▶ Stapling…"
xcrun stapler staple "$APP_BUNDLE"

# Re-zip so the published archive contains the stapled app.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP"

echo "✓ Release artifact: $ZIP"
echo "  sha256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
