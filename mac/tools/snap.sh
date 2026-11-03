#!/bin/zsh
# Snapshots of the main window and Settings in light and dark, on a scratch library home.
# Usage: tools/snap.sh            main window and Settings
#        APP_SNAPSHOT_PAGES=main,settings tools/snap.sh
set -u
app="$HOME/Applications/Capture Director.app/Contents/MacOS/CaptureDirector"
store=/tmp/CaptureDirector-test-home
shots=/tmp/CaptureDirector-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/io.github.dhanson-wp.capture-director.savedState
rm -rf $store; mkdir -p $store
rm -rf $shots
CD_HOME=$store APP_SNAPSHOT=$shots "$app"
