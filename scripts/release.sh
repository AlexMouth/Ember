#!/bin/zsh
# Builds a universal Ember.app and packages dist/Ember-<version>.dmg and .zip.
# Usage: VERSION=0.2.0 ./scripts/release.sh
# The app is assembled and signed in a temp dir: iCloud/File Provider folders (e.g. ~/Documents)
# add xattrs that invalidate the code signature.
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION=${VERSION:-0.1.0}
WORK=$(mktemp -d)
export BUILD_DIR=$WORK/build
ARCHS="arm64 x86_64" ./scripts/build_app.sh
mkdir -p "$WORK/dmg" dist
ditto --norsrc --noextattr "$BUILD_DIR/Ember.app" "$WORK/dmg/Ember.app"
codesign --verify --deep --strict "$WORK/dmg/Ember.app"
ln -s /Applications "$WORK/dmg/Applications"
rm -f "dist/Ember-$VERSION.dmg" "dist/Ember-$VERSION.zip"
hdiutil create -volname "Ember" -srcfolder "$WORK/dmg" -fs APFS -ov -format UDZO "dist/Ember-$VERSION.dmg" >/dev/null
ditto -c -k --norsrc --noextattr --keepParent "$WORK/dmg/Ember.app" "dist/Ember-$VERSION.zip"
rm -rf "$WORK"
ls -la dist
