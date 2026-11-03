#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/io.github.dhanson-wp.capture-director.savedState
store=/tmp/CaptureDirector-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store "$HOME/Applications/Capture Director.app/Contents/MacOS/CaptureDirector" --selftest
