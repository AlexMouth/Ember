#!/bin/zsh
# Builds Ember.app (ad-hoc signed) from the Swift package. Needs only the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=${VERSION:-0.1.0}
ARCHS=(${=ARCHS:-})   # e.g. ARCHS="arm64 x86_64" for a universal build
FLAGS=(-c release)
for a in $ARCHS; do FLAGS+=(--arch $a); done
swift build $FLAGS
BIN=$(swift build $FLAGS --show-bin-path)
APP=build/Ember.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Ember" "$APP/Contents/MacOS/Ember"
cp assets/Ember.icns "$APP/Contents/Resources/Ember.icns"
cp -R "$BIN/Ember_Ember.bundle" "$APP/Contents/Resources/" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.ember.app</string>
<key>CFBundleName</key><string>Ember</string>
<key>CFBundleExecutable</key><string>Ember</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Ember</string>
<key>CFBundleShortVersionString</key><string>__VERSION__</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
sed -i '' "s/__VERSION__/$VERSION/" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
