#!/bin/bash
# Builds and tests SpiderCursor.app against the public RiveRuntime.
#
#   ./build.sh
#
# Needs Xcode's command line tools, the Rive CLI (`rive`) on PATH and a Rive
# sign-in (`rive login`): a released runtime only runs signed scripts, and
# `rive --publish` signs them.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_VERSION=6.29.0
OUT="$HERE/build"
# CADisplayLink on NSView is macOS 14.
TARGET="$(uname -m)-apple-macos14.0"
FRAMEWORKS="$OUT/RiveRuntime.xcframework/macos-arm64_x86_64"
APP="$OUT/SpiderCursor.app"

if [[ "$(cat "$OUT/runtime-version" 2>/dev/null)" != "$RUNTIME_VERSION" ]]; then
    rm -rf "$OUT/RiveRuntime.xcframework"
    mkdir -p "$OUT"
    curl -fsSL -o "$OUT/runtime.zip" \
        "https://github.com/rive-app/rive-ios/releases/download/$RUNTIME_VERSION/RiveRuntime.xcframework.zip"
    unzip -q -o "$OUT/runtime.zip" -d "$OUT"
    rm "$OUT/runtime.zip"
    echo "$RUNTIME_VERSION" > "$OUT/runtime-version"
fi
test -d "$FRAMEWORKS/RiveRuntime.framework"

swiftc -O -target "$TARGET" -F "$FRAMEWORKS" -framework RiveRuntime -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    "$HERE/Sources/Overlay.swift" "$HERE/Sources/Palette.swift" \
    "$HERE/Tests/main.swift" -o "$OUT/overlay_tests"
"$OUT/overlay_tests" "$HERE/../scene.rml"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
swiftc -O -target "$TARGET" -F "$FRAMEWORKS" -framework RiveRuntime \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$HERE/Sources/"*.swift -o "$APP/Contents/MacOS/SpiderCursor"
cp -R "$FRAMEWORKS/RiveRuntime.framework" "$APP/Contents/Frameworks/"
cp "$HERE/Info.plist" "$APP/Contents/"
(cd "$HERE/.." && rive . --publish >/dev/null)
cp "$HERE/../build/spider.riv" "$APP/Contents/Resources/"
# The plist's minimum macOS must be the one the binary was built for.
MINOS=$(vtool -show-build "$APP/Contents/MacOS/SpiderCursor" | awk '/minos/ {print $2}')
PLIST_MINOS=$(plutil -extract LSMinimumSystemVersion raw "$HERE/Info.plist")
if [[ "$MINOS" != "$PLIST_MINOS" ]]; then
    echo "the app needs macOS $MINOS but Info.plist says $PLIST_MINOS" >&2
    exit 1
fi
codesign --force --deep --sign - "$APP"
echo "built $APP"
