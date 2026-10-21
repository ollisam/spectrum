#!/bin/bash
# Builds build/Spectrum.app.   ./build.sh install  → also installs to /Applications and launches.
set -euo pipefail
cd "$(dirname "$0")"

ID=com.olivermani.spectrum
APP=build/Spectrum.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Spectrum"

if [ ! -f build/AppIcon.icns ] || [ Resources/icon-source.png -nt build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
    mkdir -p build/AppIcon.iconset
    swift scripts/make-icon.swift Resources/icon-source.png build/icon-1024.png
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
        sips -z $((s*2)) $((s*2)) build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
    done
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Spectrum"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign with a stable designated requirement so the Screen Recording
# permission survives rebuilds.
codesign --force --sign - --identifier "$ID" \
    --requirements "=designated => identifier \"$ID\"" "$APP"

echo "Built $APP"

if [ "${1:-}" = "install" ]; then
    pkill -x Spectrum 2>/dev/null || true
    rm -rf /Applications/Spectrum.app
    cp -R "$APP" /Applications/
    open /Applications/Spectrum.app
    echo "Installed to /Applications/Spectrum.app"
fi
