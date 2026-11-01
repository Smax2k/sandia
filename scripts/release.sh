#!/bin/bash
# Construit Sandia.app signée Developer ID et la notarie, sans aucun secret à saisir.
#
#   ./scripts/release.sh          # build, signature, notarisation, agrafage, DMG
#   ./scripts/release.sh --sign   # build et signature seulement
#
# La notarisation utilise le profil `asc` déjà présent sur la machine
# (`asc auth status`) : aucune clé ni mot de passe n'est manipulé ici.
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY="${DEVELOPER_ID:-Developer ID Application: Jonathan Bahu (BG55CF653X)}"
TEAM="${TEAM_ID:-BG55CF653X}"
OUT=".build/dist"
APP="$OUT/Build/Products/Release/Sandia.app"
VERSION=$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml | tr -d '"')
VERSION="${VERSION:-dev}"
SIGN_ONLY="${1:-}"

echo "Sandia $VERSION — signature : $IDENTITY"

xcodebuild -project Sandia.xcodeproj -scheme Sandia -configuration Release \
    -derivedDataPath "$OUT" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ONLY_ACTIVE_ARCH=NO ARCHS=arm64 \
    build | grep -E "error:|warning: .*sign|BUILD" || true

test -d "$APP" || { echo "Build absent : $APP" >&2; exit 1; }

# La signature attendue, vérifiée plutôt que supposée.
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier|flags=.*runtime|Timestamp="

if [[ "$SIGN_ONLY" == "--sign" ]]; then
    echo "Signée seulement. App : $APP"
    exit 0
fi

asc auth status --validate >/dev/null || { echo "Profil asc indisponible : lancer asc auth login" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'find "$WORK" -depth -delete 2>/dev/null || true' EXIT

notarize() {
    local file="$1" result id status
    echo "Notarisation de $(basename "$file") (quelques minutes)…"
    result=$(asc notarization submit --file "$file" --wait --timeout 25m --output json)
    id=$(python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["id"])' <<< "$result")
    status=$(python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["attributes"]["status"])' <<< "$result")
    if [[ "$status" != "Accepted" ]]; then
        echo "Refusé : $status" >&2
        asc notarization log --id "$id" --pretty >&2
        exit 1
    fi
    echo "Accepté ($id)"
}

# Le bundle tel quel, pour que l'app agrafée s'ouvre aussi hors ligne.
ditto -c -k --keepParent "$APP" "$WORK/Sandia.zip"
notarize "$WORK/Sandia.zip"
asc notarization staple --file "$APP" --confirm
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
