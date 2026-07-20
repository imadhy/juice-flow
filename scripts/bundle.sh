#!/bin/bash
# Assemble JuiceFlow.app à partir du build SPM (pas besoin de Xcode).
# Usage : scripts/bundle.sh [--no-open]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
swift build -c "$CONFIG"

APP="build/JuiceFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/JuiceFlow" "$APP/Contents/MacOS/JuiceFlow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Signature ad-hoc : suffisante pour un usage local, pas de compte développeur requis.
codesign --force --sign - "$APP"

echo "✅ Bundle prêt : $APP"
if [[ "${1:-}" != "--no-open" ]]; then
  open "$APP"
fi
