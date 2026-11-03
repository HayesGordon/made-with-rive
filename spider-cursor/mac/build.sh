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

swiftc -O -F "$FRAMEWORKS" -framework RiveRuntime -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    "$HERE/Sources/Overlay.swift" "$HERE/Sources/Palette.swift" "$HERE/Sources/SpiderView.swift" \
    "$HERE/Tests/main.swift" -o "$OUT/overlay_tests"
"$OUT/overlay_tests" "$HERE/../scene.rml"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
swiftc -O -F "$FRAMEWORKS" -framework RiveRuntime \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$HERE/Sources/"*.swift -o "$APP/Contents/MacOS/SpiderCursor"
cp -R "$FRAMEWORKS/RiveRuntime.framework" "$APP/Contents/Frameworks/"
cp "$HERE/Info.plist" "$APP/Contents/"
(cd "$HERE/.." && rive . --publish >/dev/null)
cp "$HERE/../build/spider.riv" "$APP/Contents/Resources/"
codesign --force --deep --sign - "$APP"
echo "built $APP"
