#!/bin/bash
# Dancing Totem.app 을 build/ 폴더에 만든다.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Dancing Totem.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
    Sources/main.swift -o "$APP/Contents/MacOS/DancingTotem"

cp Info.plist "$APP/Contents/Info.plist"
# 기본 GIF는 저장소에 넣지 않는다. Resources/dancer.gif 가 있으면 앱에 같이 넣는다.
if [ -f Resources/dancer.gif ]; then
    cp Resources/dancer.gif "$APP/Contents/Resources/dancer.gif"
fi
codesign --force --sign - "$APP"

echo "완료: $APP"
