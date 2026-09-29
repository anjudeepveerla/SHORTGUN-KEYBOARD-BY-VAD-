#!/bin/sh
set -eu

cd "$(dirname "$0")"
./build.sh
codesign --verify --deep --strict ShotgunKeyboard.app

mkdir -p dist
staging="$(mktemp -d "./.shotgun-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT

ditto ShotgunKeyboard.app "$staging/ShotgunKeyboard.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/Install.txt" <<'EOF'
Drag ShotgunKeyboard.app to Applications.

On first launch, right-click the app and choose Open if macOS blocks it.
Enable ShotgunKeyboard in System Settings > Privacy & Security >
Input Monitoring and Accessibility, then quit and reopen the app.

Click the menu bar speaker icon or the Dock icon to open the controls.
EOF

output="dist/ShotgunKeyboard-macOS-$(uname -m).dmg"
hdiutil create -ov -format UDZO -volname ShotgunKeyboard -srcfolder "$staging" "$output"
hdiutil verify "$output"
echo "Built $(pwd)/$output"
