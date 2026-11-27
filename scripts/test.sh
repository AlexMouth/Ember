#!/bin/zsh
# Runs the test suite. With only the Command Line Tools installed (no Xcode), SwiftPM
# does not find the swift-testing macro plugin or framework on its own, so point it there.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV=$(xcode-select -p)
PLUGINS=$DEV/usr/lib/swift/host/plugins/testing
FW=$DEV/Library/Developer/Frameworks
if [[ -d "$PLUGINS" && -d "$FW" && "$DEV" == *CommandLineTools* ]]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" -Xlinker -rpath -Xlinker "$FW" "$@"
fi
exec swift test "$@"
