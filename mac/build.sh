#!/bin/bash
# Builds Translator.app with the Swift compiler from Xcode or the Command Line Tools.
# Usage: ./build.sh            builds mac/build/Translator.app
#        ./build.sh --install  also copies it into ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Translator.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -parse-as-library -swift-version 5 -O \
  -target "$(uname -m)-apple-macos15.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Translator"

# App icon, drawn from the web app's icon.svg (skipped if it can't be rendered).
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
if qlmanage -t -s 1024 -o build ../public/icon.svg >/dev/null 2>&1 && [ -f build/icon.svg.png ]; then
  for size in 16 32 128 256 512; do
    sips -z $size $size build/icon.svg.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) build/icon.svg.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc signature so macOS will remember the microphone permission.
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Translator.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to $HOME/Applications/Translator.app"
fi
