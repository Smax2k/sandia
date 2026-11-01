#!/bin/bash
# Construit Sandia.app signée Developer ID, prête à être notariée.
#
#   ./scripts/release.sh                     # construit et signe seulement
#   NOTARY_PROFILE=sandia-notary ./scripts/release.sh
#                                            # notarie, agrafe et produit un DMG
#
# Le profil de notarisation se crée une fois :
#   xcrun notarytool store-credentials sandia-notary --apple-id <id> --team-id BG55CF653X
# (mot de passe spécifique à l'app, créé sur appleid.apple.com)
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="${DEVELOPER_ID:-Developer ID Application: Jonathan Bahu (BG55CF653X)}"
TEAM="${TEAM_ID:-BG55CF653X}"
PROFILE="${NOTARY_PROFILE:-}"
OUT=".build/dist"
APP="$OUT/Build/Products/Release/Sandia.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :MARKETING_VERSION" project.yml 2>/dev/null || echo "0.0.0")

echo "Sandia $VERSION — signature : $IDENTITY"

xcodebuild -project Sandia.xcodeproj -scheme Sandia -configuration Release \
    -derivedDataPath "$OUT" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM" \
    ONLY_ACTIVE_ARCH=NO ARCHS=arm64 \
    build | grep -E "error:|warning: .*sign|BUILD" || true

test -d "$APP" || { echo "Build absent : $APP" >&2; exit 1; }

# La signature attendue, vérifiée plutôt que supposée.
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier|flags=.*runtime"

if [[ -z "$PROFILE" ]]; then
    echo
    echo "Signée. Pour notarier : NOTARY_PROFILE=sandia-notary ./scripts/release.sh"
    echo "App : $APP"
    exit 0
fi

WORK=$(mktemp -d)
trap 'find "$WORK" -depth -delete 2>/dev/null || true' EXIT

notarize() {
    echo "Notarisation de $1 (quelques minutes)…"
    local result status
    result=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --output-format json)
    status=$(plutil -extract status raw - <<< "$result")
    if [[ "$status" != "Accepted" ]]; then
        echo "Refusé : $status" >&2
        xcrun notarytool log "$(plutil -extract id raw - <<< "$result")" --keychain-profile "$PROFILE" >&2
        exit 1
    fi
}

# Le bundle tel quel, pour que l'app agrafée s'ouvre aussi hors ligne.
ditto -c -k --keepParent "$APP" "$WORK/Sandia.zip"
notarize "$WORK/Sandia.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# DMG de distribution.
DMG="$OUT/Sandia-$VERSION.dmg"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Sandia.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Sandia" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo
echo "App : $APP"
echo "DMG : $DMG"
