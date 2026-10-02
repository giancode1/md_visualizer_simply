#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="VisualizadorGC.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/VisualizadorGC" "$APP/Contents/MacOS/VisualizadorGC"
mkdir -p "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_ID=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/' || true)
codesign --force --deep --sign "${SIGN_ID:--}" "$APP"

echo "Listo: $APP  (muévela a /Applications; 'open -a VisualizadorGC archivo.md' o arrastra un .md a su ícono)"
