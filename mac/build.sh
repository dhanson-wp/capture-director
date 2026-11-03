#!/bin/zsh
# Builds Capture Director and installs it to $CD_APP_DIR/Capture Director.app
# (default ~/Applications).
# Build products live in ~/Library/Developer/CaptureDirector, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
# Environment: CD_APP_DIR       install folder (default ~/Applications)
#              CD_CONFIG_JSON   JSON written to Contents/Resources/config.json:
#                               { "node", "cli", "path", "cdHome" }. Unset, the installed
#                               copy's config.json is kept. Prefer
#                               node bin/capture-director.js install-app [--dir <folder>],
#                               which sets it.
set -euo pipefail
here=${0:A:h}
name="CaptureDirector"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

appdir="${CD_APP_DIR:-$HOME/Applications}"
app="$appdir/Capture Director.app"
mkdir -p "$appdir"
# The app's config.json (where node and the CLI are) isn't ours to lose: without
# CD_CONFIG_JSON, keep the installed copy's so a plain rebuild doesn't break writes.
kept=""
if [[ -z "${CD_CONFIG_JSON:-}" ]]; then
  if [[ -f "$app/Contents/Resources/config.json" ]]; then
    kept=$(mktemp)
    cp "$app/Contents/Resources/config.json" "$kept"
  else
    echo "warning: no config.json to keep, so this build can't run the CLI and every change will fail. Install with: node bin/capture-director.js install-app" >&2
  fi
fi
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The icon: Icon/AppIcon.iconset -> Resources/AppIcon.icns, rebuilt when it changed.
icns="$here/Resources/AppIcon.icns"
if [[ ! -f "$icns" || -n "$(find "$here/Icon/AppIcon.iconset" -newer "$icns" | head -1)" ]]; then
  "$here/tools/make_icon.sh" >&2
fi
cp -X "$icns" "$app/Contents/Resources/"
# Where the app finds node and the CLI. Written before codesign, which seals Resources.
if [[ -n "${CD_CONFIG_JSON:-}" ]]; then
  print -r -- "$CD_CONFIG_JSON" > "$app/Contents/Resources/config.json"
elif [[ -n "$kept" ]]; then
  mv "$kept" "$app/Contents/Resources/config.json"
fi
xattr -cr "$app"
sign_log=$(codesign --force --sign "$identity" "$app" 2>&1) || {
  echo "$sign_log" >&2
  echo "build failed: could not sign the app" >&2
  exit 1
}
print -r -- "$sign_log" | grep -v "replacing existing signature" >&2 || true
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"Capture Director\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
