#!/bin/zsh
# Builds Resources/AppIcon.icns from Icon/AppIcon.iconset with iconutil, which
# ships with macOS. build.sh runs this when the iconset changed.
# The iconset holds the ten PNG sizes (16 to 512 at 1x and 2x), rendered from ui/icon.svg.
set -euo pipefail
here=${0:A:h}
repo=${here:h}
mkdir -p "$repo/Resources"
iconutil -c icns "$repo/Icon/AppIcon.iconset" -o "$repo/Resources/AppIcon.icns"
echo "wrote Resources/AppIcon.icns"
