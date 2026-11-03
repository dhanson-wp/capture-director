#!/bin/zsh
# Runs the in-app self-test against the fixture library (tools/fixture.sh) in /tmp.
# Exit code 0 when every check passed.
# Environment: CD_APP_DIR   folder with Capture Director.app (default /tmp/CaptureDirector-test-app,
#              made with: node bin/capture-director.js install-app --dir /tmp/CaptureDirector-test-app)
set -u
here=${0:A:h}
appdir="${CD_APP_DIR:-/tmp/CaptureDirector-test-app}"
app="$appdir/Capture Director.app/Contents/MacOS/CaptureDirector"
[[ -x "$app" ]] || { echo "no app at $appdir. Install one there: node bin/capture-director.js install-app --dir $appdir" >&2; exit 1; }
rm -rf ~/Library/Saved\ Application\ State/io.github.dhanson-wp.capture-director.savedState
store=/tmp/CaptureDirector-self-home
"$here/fixture.sh" $store >/dev/null || exit 1
CD_HOME=$store "$app" --selftest
