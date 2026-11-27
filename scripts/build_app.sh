#!/bin/zsh
# Builds Ember.app from the Swift package. Needs only the Command Line Tools.
#
# Environment:
#   VERSION        marketing version (default: latest git tag without the "v", else 0.0.0)
#   BUILD_NUMBER   CFBundleVersion (default: number of commits on HEAD)
#   BUNDLE_ID      bundle identifier (default: local.ember.app — changing it resets
#                  preferences, notification permission and keychain access)
#   SIGN_IDENTITY  codesign identity, e.g. "Developer ID Application: Name (TEAMID)".
#                  When set, the app is signed with the hardened runtime and a secure
#                  timestamp, as notarization requires. Default: ad-hoc ("-").
#   ARCHS          e.g. "arm64 x86_64" for a universal build
#   BUILD_DIR      output folder (default: build)
set -euo pipefail
cd "$(dirname "$0")/.."
DEFAULT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
VERSION=${VERSION:-${DEFAULT_VERSION:-0.0.0}}
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
BUNDLE_ID=${BUNDLE_ID:-local.ember.app}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
ARCHS=(${=ARCHS:-})
FLAGS=(-c release -Xswiftc -Osize -Xlinker -dead_strip)
for a in $ARCHS; do FLAGS+=(--arch $a); done
swift build $FLAGS
BIN=$(swift build $FLAGS --show-bin-path)
BUILD_DIR=${BUILD_DIR:-build}
APP=$BUILD_DIR/Ember.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Ember" "$APP/Contents/MacOS/Ember"
strip -x "$APP/Contents/MacOS/Ember"
cp assets/Ember.icns "$APP/Contents/Resources/Ember.icns"
cp -R "$BIN/Ember_Ember.bundle" "$APP/Contents/Resources/"
PLIST=$APP/Contents/Info.plist
cat > "$PLIST" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Ember</string>
<key>CFBundleDisplayName</key><string>Ember</string>
<key>CFBundleExecutable</key><string>Ember</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Ember</string>
<key>CFBundleDevelopmentRegion</key><string>fr</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
XML
plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$PLIST"
plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -insert CFBundleVersion -string "$BUILD_NUMBER" "$PLIST"
plutil -lint "$PLIST" >/dev/null
xattr -cr "$APP"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built $APP ($BUNDLE_ID $VERSION build $BUILD_NUMBER)"
