#!/bin/zsh
# Builds a universal Ember.app and packages dist/Ember-<version>.dmg and .zip.
# Usage: VERSION=0.2.0 ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export VERSION=${VERSION:-0.1.0}
ARCHS="arm64 x86_64" ./scripts/build_app.sh
rm -rf dist && mkdir -p dist/dmg
cp -R build/Ember.app dist/dmg/
ln -s /Applications dist/dmg/Applications
hdiutil create -volname "Ember" -srcfolder dist/dmg -ov -format UDZO "dist/Ember-$VERSION.dmg" >/dev/null
ditto -c -k --keepParent build/Ember.app "dist/Ember-$VERSION.zip"
rm -rf dist/dmg
ls -la dist
