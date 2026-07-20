#!/bin/bash
# Emballe build/JuiceFlow.app dans un .dmg de release — hdiutil uniquement,
# aucune dépendance. Usage : scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh --no-open

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/JuiceFlow.app/Contents/Info.plist)
STAGE="build/dmg-stage"
DMG="build/JuiceFlow-$VERSION.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/JuiceFlow.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "JuiceFlow $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGE"
echo "✅ $DMG"
