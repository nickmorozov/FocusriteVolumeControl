#!/bin/bash
#
# build-dmg.sh — Build a distributable DMG for Focusrite Volume Control
#
# Usage:
#   bash scripts/build-dmg.sh
#
# Optional environment variables for notarization:
#   APPLE_ID       — Apple ID email for notarization
#   TEAM_ID        — Developer Team ID
#   APP_PASSWORD   — App-specific password for notarization
#
# Without a Developer ID certificate, the app will be built unsigned.
# Users can add code signing later by setting CODE_SIGN_IDENTITY.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
SCHEME="FocusriteVolumeControl"
APP_NAME="FocusriteVolumeControl"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Build Release archive
echo "==> Building Release archive..."
xcodebuild archive \
    -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    -quiet

# Step 2: Export the archive to a .app
echo "==> Exporting archive..."
xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
    -exportPath "$BUILD_DIR/export" \
    -exportOptionsPlist "$PROJECT_DIR/ExportOptions.plist" \
    -quiet

# Verify the .app was exported
if [ ! -d "$BUILD_DIR/export/$APP_NAME.app" ]; then
    echo "ERROR: Export failed — $APP_NAME.app not found in $BUILD_DIR/export/"
    echo "This usually means you don't have a Developer ID certificate installed."
    echo ""
    echo "Falling back to direct build..."
    # Fallback: just build and copy from DerivedData
    xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        build \
        -quiet
    # Find the built app
    BUILT_APP=$(find ~/Library/Developer/Xcode/DerivedData/${APP_NAME}-* \
        -path "*/Build/Products/Release/${APP_NAME}.app" -maxdepth 5 2>/dev/null | head -1)
    if [ -z "$BUILT_APP" ]; then
        echo "ERROR: Could not find built app in DerivedData"
        exit 1
    fi
    mkdir -p "$BUILD_DIR/export"
    cp -R "$BUILT_APP" "$BUILD_DIR/export/"
fi

# Step 3: Create DMG with drag-to-Applications layout
echo "==> Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

cp -R "$BUILD_DIR/export/$APP_NAME.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$APP_NAME.dmg"

echo "==> DMG created: $BUILD_DIR/$APP_NAME.dmg"

# Step 4: Optional notarization
if [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APP_PASSWORD:-}" ]; then
    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$BUILD_DIR/$APP_NAME.dmg" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$BUILD_DIR/$APP_NAME.dmg"
    echo "==> Notarization complete!"
else
    echo ""
    echo "Skipping notarization (set APPLE_ID, TEAM_ID, APP_PASSWORD to enable)."
fi

echo ""
echo "Done! DMG is at: $BUILD_DIR/$APP_NAME.dmg"
echo "Size: $(du -h "$BUILD_DIR/$APP_NAME.dmg" | cut -f1)"
