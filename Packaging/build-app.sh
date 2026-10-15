#!/bin/bash
# リリースビルドして dist/DeskRunner.app を作る (署名はアドホック)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)"

app=dist/DeskRunner.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Packaging/Info.plist "$app/Contents/Info.plist"
cp "$bin/DeskRunner" "$app/Contents/MacOS/DeskRunner"
cp Sources/DeskRunner/Resources/*.png "$app/Contents/Resources/"
cp LICENSE-* "$app/Contents/Resources/"
codesign --force --sign - "$app"

echo "$app"
