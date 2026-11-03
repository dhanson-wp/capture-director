#!/bin/zsh
# Snapshots of every main window page and Settings in light and dark, on the
# fixture library (tools/fixture.sh) in a scratch home.
# Usage: tools/snap.sh            every page and Settings
#        APP_SNAPSHOT_PAGES=all-grid,settings tools/snap.sh
# Environment: CD_APP_DIR   folder with Capture Director.app (default /tmp/CaptureDirector-test-app,
#              made with: node bin/capture-director.js install-app --dir /tmp/CaptureDirector-test-app)
set -u
here=${0:A:h}
appdir="${CD_APP_DIR:-/tmp/CaptureDirector-test-app}"
app="$appdir/Capture Director.app/Contents/MacOS/CaptureDirector"
[[ -x "$app" ]] || { echo "no app at $appdir. Install one there: node bin/capture-director.js install-app --dir $appdir" >&2; exit 1; }
store=/tmp/CaptureDirector-test-home
shots=/tmp/CaptureDirector-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/io.github.dhanson-wp.capture-director.savedState
"$here/fixture.sh" $store >/dev/null || exit 1
rm -rf $shots
CD_HOME=$store APP_SNAPSHOT=$shots "$app"
