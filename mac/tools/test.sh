#!/bin/zsh
# Runs the Kit unit tests. With Command Line Tools only (no Xcode), Swift
# Testing lives in the Developer frameworks there, so the compiler and linker
# need to be pointed at it. With Xcode selected, plain `swift test` works.
set -euo pipefail
here=${0:A:h}
repo=${here:h}
scratch="$HOME/Library/Developer/CaptureDirector/test-build"
dev=$(xcode-select -p)
flags=()
if [[ "$dev" == */CommandLineTools ]]; then
  F="$dev/Library/Developer/Frameworks"
  L="$dev/Library/Developer/usr/lib"
  flags=(-Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L)
fi
swift test --package-path "$repo" --scratch-path "$scratch" $flags "$@"
