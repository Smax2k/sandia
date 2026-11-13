#!/bin/bash
# Builds a universal release binary, wraps it in build/Sandia.app (ad-hoc codesigned)
# and packs build/Sandia-<version>.dmg with an Applications symlink for drag-install.
#
# For a release build, set:
#   DEVELOPER_ID    a "Developer ID Application" signing identity, to sign the app and DMG
#   NOTARY_PROFILE  a notarytool keychain profile, to also notarize and staple the app and DMG
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Sandia.app"
STAGING="build/dmg"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" AppInfo.plist)
DMG="build/Sandia-$VERSION.dmg"
IDENTITY="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -n "$NOTARY_PROFILE" && -z "$IDENTITY" ]]; then
    echo "NOTARY_PROFILE needs DEVELOPER_ID: only Developer ID signed builds can be notarized." >&2
    exit 1
fi

# Submits a file to Apple's notary service and fails with Apple's log unless it is accepted.
notarize() {
    echo "Notarizing $1 (usually a few minutes)..."
    local result status
    result=$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
    status=$(plutil -extract status raw - <<< "$result")
    if [[ "$status" != "Accepted" ]]; then
        echo "Notarization of $1 finished with status: $status" >&2
        xcrun notarytool log "$(plutil -extract id raw - <<< "$result")" --keychain-profile "$NOTARY_PROFILE" >&2
        exit 1
    fi
}

# Prefer a universal (arm64 + x86_64) build; fall back to the native arch.
ARCHS=(--arch arm64 --arch x86_64)
if ! swift build -c release "${ARCHS[@]}"; then
    echo "Universal build failed; falling back to native arch ($(uname -m))." >&2
    ARCHS=()
    swift build -c release
fi
# The output path differs between build systems, so ask SwiftPM for it.
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/Sandia"
echo "Binary archs: $(lipo -archs "$BIN")"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sandia"
cp AppInfo.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Localized strings live beside the icon; macOS picks by the user's language.
for locale in Resources/*.lproj; do
    cp -R "$locale" "$APP/Contents/Resources/"
done
if [[ -n "$IDENTITY" ]]; then
    # Notarization requires the hardened runtime and a secure timestamp.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
    codesign --force --deep --sign - "$APP"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    # Staple the app itself too, so it opens offline once dragged out of the DMG.
    ditto -c -k --keepParent "$APP" build/Sandia.zip
    notarize build/Sandia.zip
    rm build/Sandia.zip
    xcrun stapler staple "$APP"
fi

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Sandia" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [[ -n "$IDENTITY" ]]; then
    codesign --sign "$IDENTITY" --timestamp "$DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo "Built $APP"
echo "Built $DMG"
