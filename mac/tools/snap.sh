#!/bin/zsh
# Snapshots of the main window and Settings in light and dark, on a fresh test store.
# Usage: tools/snap.sh            main window and Settings
#        APP_SNAPSHOT_PAGES=main,settings tools/snap.sh
set -u
app="$HOME/Applications/Capture Director.app/Contents/MacOS/CaptureDirector"
store=/tmp/CaptureDirector-test.store
shots=/tmp/CaptureDirector-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/io.github.dhanson-wp.capture-director.savedState
rm -f $store $store-shm $store-wal
rm -rf $shots
APP_STORE=$store APP_SNAPSHOT=$shots "$app"
