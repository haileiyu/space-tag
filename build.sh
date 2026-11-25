#!/bin/bash
# Build SpaceTag.app.   ./build.sh           -> build/SpaceTag.app
#                           ./build.sh install   -> also copy to ~/Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

NAME=SpaceTag
BUNDLE_ID=local.spacetag
APP="build/$NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 \
    -framework Cocoa -framework ApplicationServices -framework ServiceManagement \
    Sources/*.swift -o "$APP/Contents/MacOS/$NAME"

# Ad-hoc signature. macOS ties the Accessibility grant to this exact build,
# so each new build needs the grant again (install resets the old entry).
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    DEST="$HOME/Applications/$NAME.app"
    pkill -x "$NAME" 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    open "$DEST"
    echo "Installed and launched $DEST"
fi
