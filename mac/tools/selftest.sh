#!/bin/zsh
# Runs the in-app self-test against a scratch library home in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/io.github.dhanson-wp.capture-director.savedState
store=/tmp/CaptureDirector-self-home
rm -rf $store; mkdir -p $store
CD_HOME=$store "$HOME/Applications/Capture Director.app/Contents/MacOS/CaptureDirector" --selftest
