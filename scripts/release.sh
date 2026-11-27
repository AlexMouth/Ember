#!/bin/zsh
# Builds a universal Ember.app and packages dist/Ember-<version>.dmg, .zip, .zip.sig and .zip.sha256.
# Usage: VERSION=0.5.0 ./scripts/release.sh
#
# Upload the four files to the GitHub release. The in-app updater refuses a ZIP whose
# Ember-<version>.zip.sig asset is missing or is not signed by the release key
# (scripts/sign_update.swift, key in ~/.config/ember/update-signing.key). The .sha256 is
# only for people checking a manual download.
#
# Optional notarization (needs a Developer ID): set SIGN_IDENTITY (see build_app.sh) and
# NOTARY_PROFILE, a keychain profile created once with
#   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team>
#
# The app is assembled and signed in a temp dir: iCloud/File Provider folders (e.g. ~/Documents)
# add xattrs that invalidate the code signature.
set -euo pipefail
cd "$(dirname "$0")/.."
DEFAULT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
export VERSION=${VERSION:-${DEFAULT_VERSION:-0.0.0}}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export BUILD_DIR=$WORK/build
ARCHS="arm64 x86_64" ./scripts/build_app.sh
APP=$WORK/dmg/Ember.app
mkdir -p "$WORK/dmg" dist
ditto --norsrc --noextattr "$BUILD_DIR/Ember.app" "$APP"
codesign --verify --deep --strict "$APP"
ZIP=dist/Ember-$VERSION.zip
DMG=dist/Ember-$VERSION.dmg
rm -f "$DMG" "$ZIP" "$ZIP.sha256" "$ZIP.sig"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ditto -c -k --keepParent "$APP" "$WORK/notarize.zip"
  xcrun notarytool submit "$WORK/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -volname "Ember" -srcfolder "$WORK/dmg" -fs APFS -ov -format UDZO "$DMG" >/dev/null
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
swiftc -O scripts/sign_update.swift -o "$WORK/sign_update"
"$WORK/sign_update" sign "$ZIP"
"$WORK/sign_update" verify "$ZIP"
(cd dist && shasum -a 256 "Ember-$VERSION.zip" > "Ember-$VERSION.zip.sha256" && shasum -a 256 -c "Ember-$VERSION.zip.sha256")
ls -la dist
