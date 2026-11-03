#!/bin/zsh
# Snapshots of every main window page in light and dark, on the
# fixture library (tools/fixture.sh) in a scratch home.
# Usage: tools/snap.sh            every page
#        APP_SNAPSHOT_PAGES=all-grid,inspector tools/snap.sh
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
# A finished web copy for the "inspector-copy" page.
tour=$(CD_HOME=$store node -e 'const db = JSON.parse(require("fs").readFileSync(process.argv[1] + "/library.json", "utf8")); process.stdout.write(db.entries.find((e) => e.title === "Post formats tour").id);' $store)
CD_HOME=$store node "${here:h:h}/bin/capture-director.js" library export "$tour" >/dev/null || exit 1
rm -rf $shots
CD_HOME=$store APP_SNAPSHOT=$shots "$app"
