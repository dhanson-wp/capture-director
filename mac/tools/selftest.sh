#!/bin/zsh
# Runs the in-app self-test against the fixture library (tools/fixture.sh) in /tmp.
# Exit code 0 when every check passed.
# Environment: CD_APP_DIR   folder with Capture Director.app (default ~/Applications)
set -u
here=${0:A:h}
app="${CD_APP_DIR:-$HOME/Applications}/Capture Director.app/Contents/MacOS/CaptureDirector"
rm -rf ~/Library/Saved\ Application\ State/io.github.dhanson-wp.capture-director.savedState
store=/tmp/CaptureDirector-self-home
"$here/fixture.sh" $store >/dev/null || exit 1
CD_HOME=$store "$app" --selftest
