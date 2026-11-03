#!/bin/zsh
# Runs the Kit unit tests with Command Line Tools only (no Xcode).
# Swift Testing lives in the Command Line Tools' Developer frameworks, so the
# compiler and linker need to be pointed at it.
set -euo pipefail
here=${0:A:h}
repo=${here:h}
dev=$(xcode-select -p)
F="$dev/Library/Developer/Frameworks"
L="$dev/Library/Developer/usr/lib"
swift test --package-path "$repo" \
  --scratch-path "$HOME/Library/Developer/CaptureDirector/test-build" \
  -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
