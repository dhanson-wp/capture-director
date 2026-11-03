#!/bin/zsh
# Fills a scratch library home with six short test videos, for snapshots and the self-test.
# Usage: tools/fixture.sh <home>      (a folder in /tmp; never ~/.capture-director)
#   blog/Post formats: Post formats tour (final, starred), Gallery scroll (clip), Quote block (clip, file deleted)
#   Spacefast:         Spacefast launch (final), Publish flow (clip, older than 7 days)
#   Unsorted:          Pricing toggle (clip)
set -euo pipefail
home=${1:?usage: tools/fixture.sh <home>}
[[ "$home" == "$HOME/.capture-director"* ]] && { echo "fixture: refusing to touch ~/.capture-director" >&2; exit 1; }
repo=${0:A:h:h:h}
cli=(node "$repo/bin/capture-director.js")
videos="$home/videos"
rm -rf "$home"; mkdir -p "$videos"

# make <path> <seconds>
make() {
  mkdir -p "${1:h}"
  ffmpeg -loglevel error -y -f lavfi -i "testsrc=size=640x360:rate=10" -t "$2" -pix_fmt yuv420p "$1"
}
# add <path> -> id
add() {
  CD_HOME=$home "${cli[@]}" library add "$1" >/dev/null 2>&1
  CD_HOME=$home node -e '
    const db = JSON.parse(require("fs").readFileSync(process.argv[1] + "/library.json", "utf8"));
    process.stdout.write(db.entries.find((e) => e.file === process.argv[2]).id);' "$home" "$1"
}
set_() { CD_HOME=$home "${cli[@]}" library set "$@" >/dev/null; }

# A clip sits in <out>/<id>/<id>.mp4; anything else is a final video.
make "$videos/post-formats-tour.mp4" 24
make "$videos/blog/gallery-scroll/gallery-scroll.mp4" 6
make "$videos/blog/quote-block/quote-block.mp4" 4
make "$videos/spacefast-launch.mp4" 45
make "$videos/spacefast/publish-flow/publish-flow.mp4" 9
make "$videos/misc/pricing-toggle/pricing-toggle.mp4" 3

tour=$(add "$videos/post-formats-tour.mp4")
gallery=$(add "$videos/blog/gallery-scroll/gallery-scroll.mp4")
quote=$(add "$videos/blog/quote-block/quote-block.mp4")
launch=$(add "$videos/spacefast-launch.mp4")
publish=$(add "$videos/spacefast/publish-flow/publish-flow.mp4")
pricing=$(add "$videos/misc/pricing-toggle/pricing-toggle.mp4")

set_ "$tour" "$gallery" "$quote" --project "blog/Post formats"
set_ "$launch" "$publish" --project "Spacefast"
set_ "$pricing" --project "Unsorted"
set_ "$tour" --star
set_ "$tour" --title "Post formats tour"
set_ "$gallery" --title "Gallery scroll"
set_ "$quote" --title "Quote block"
set_ "$launch" --title "Spacefast launch"
set_ "$publish" --title "Publish flow"
set_ "$pricing" --title "Pricing toggle"

# Source sites, and one capture from two weeks ago. library add has no flags for these.
node -e '
  const fs = require("fs");
  const file = process.argv[1] + "/library.json";
  const [tour, launch, publish, pricing, quote] = process.argv.slice(2);
  const db = JSON.parse(fs.readFileSync(file, "utf8"));
  const urls = { [tour]: "https://www.derekhanson.blog/post-formats/", [launch]: "https://spacefast.com/",
                 [publish]: "https://spacefast.com/docs/publish", [pricing]: "https://spacefast.com/pricing",
                 [quote]: "https://www.derekhanson.blog/quotes/" };
  const old = new Date(Date.now() - 14 * 86400000).toISOString();
  for (const e of db.entries) {
    if (urls[e.id]) e.url = urls[e.id];
    if (e.id === publish) { e.added = old; e.updated = old; }
  }
  // library add first files each video under its folder name; keep only the real folders.
  db.folders = ["Spacefast", "blog", "blog/Post formats"];
  fs.writeFileSync(file, JSON.stringify(db, null, 2));' "$home" "$tour" "$launch" "$publish" "$pricing" "$quote"

rm "$videos/blog/quote-block/quote-block.mp4"
echo "fixture: 6 captures in $home"
