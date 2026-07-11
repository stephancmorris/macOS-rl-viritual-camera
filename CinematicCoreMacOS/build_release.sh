#!/bin/bash
#
# build_release.sh — Build, sign (Developer ID), notarize, and package Alfie as a
# distributable .dmg for other Macs.
#
# One-time prerequisites (see distribution notes):
#   1. A "Developer ID Application" certificate in your keychain.
#   2. A stored notary profile named "alfie-notary":
#        xcrun notarytool store-credentials "alfie-notary" \
#          --apple-id "stephancmorris@gmail.com" --team-id "EPZDEPSV69" \
#          --password "<app-specific-password>"
#
# Usage:  ./build_release.sh
# Output: build_out/Alfie.dmg  (notarized + stapled, ready to share)

set -euo pipefail

# --- Config -----------------------------------------------------------------
PROJECT="CinematicCoreMacOS.xcodeproj"
SCHEME="CinematicCoreMacOS"
APP_NAME="Alfie"
NOTARY_PROFILE="alfie-notary"
DEV_ID="Developer ID Application: Stephan Morris (EPZDEPSV69)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUT="build_out"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT_DIR="$OUT/export"
APP="$EXPORT_DIR/$APP_NAME.app"
ZIP="$OUT/$APP_NAME.zip"
DMG="$OUT/$APP_NAME.dmg"

mkdir -p "$OUT"

# --- Step 4: Archive --------------------------------------------------------
echo "==> [1/6] Archiving…"
rm -rf "$ARCHIVE"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    archive

# --- Step 5: Export with Developer ID (signs app + embedded extension) ------
echo "==> [2/6] Exporting Developer ID build…"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -allowProvisioningUpdates

# --- Step 6: Notarize the app ----------------------------------------------
echo "==> [3/6] Notarizing app (uploading to Apple, waiting)…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

# --- Step 7: Staple + verify ------------------------------------------------
echo "==> [4/6] Stapling + verifying…"
xcrun stapler staple "$APP"
spctl -a -vvv --type execute "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- Step 8: Build the DMG --------------------------------------------------
echo "==> [5/6] Building + signing DMG…"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP" -ov -format UDZO "$DMG"
codesign --force --sign "$DEV_ID" "$DMG"

# --- Step 9: Notarize + staple the DMG -------------------------------------
echo "==> [6/6] Notarizing DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo ""
echo "✅ Done. Share this file: $SCRIPT_DIR/$DMG"
