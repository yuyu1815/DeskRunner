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
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$app/Contents/Info.plist"
fi
cp "$bin/DeskRunner" "$app/Contents/MacOS/DeskRunner"
cp Sources/DeskRunner/Resources/*.png "$app/Contents/Resources/"
cp LICENSE* "$app/Contents/Resources/"
cp Packaging/AppIcon.icns "$app/Contents/Resources/"

# ビルドした Mac では欠けた画像を .build から読めてしまい気付けないので、ここで確かめる
for png in Sources/DeskRunner/Resources/*.png; do
    test -f "$app/Contents/Resources/$(basename "$png")" || { echo "missing $(basename "$png") in $app" >&2; exit 1; }
done

codesign --force --sign - "$app"

echo "$app"
