#!/bin/sh
set -eu

cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc is missing. Run: xcode-select --install" >&2
    exit 1
fi

python3 generate_sound.py

app="ShotgunKeyboard.app"
staging="$(mktemp -d "./.shotgun-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle="$staging/$app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"

swiftc -O -target "$(uname -m)-apple-macosx12.0" \
    -framework Cocoa \
    -framework AVFoundation \
    -framework ApplicationServices \
    -framework CoreGraphics \
    main.swift -o "$bundle/Contents/MacOS/ShotgunKeyboard"

cp Info.plist "$bundle/Contents/Info.plist"
cp generated-sounds/*.wav "$bundle/Contents/Resources/"
codesign --force --deep -s - "$bundle"
rm -rf "$app"
mv "$bundle" "$app"

echo "Built $(pwd)/$app"
