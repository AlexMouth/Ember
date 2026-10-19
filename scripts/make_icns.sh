#!/bin/zsh
# Builds assets/Ember.icns from assets/icon-1024.png.
set -euo pipefail
cd "$(dirname "$0")/.."
SET=$(mktemp -d)/Ember.iconset; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/icon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) assets/icon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o assets/Ember.icns
