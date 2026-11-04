#!/bin/zsh
# Fills a scratch library home with short demo captures, recorded with Capture Director
# itself against public pages of derekhanson.blog, for the Mac app tour (shots.yaml).
# Usage: make-demo-library.sh <home>      (a folder in /tmp; never ~/.capture-director)
#   Blog:   five captures      Launch: two captures (one starred in each folder)
set -euo pipefail
home=${1:?usage: make-demo-library.sh <home>}
[[ "$home" == "$HOME/.capture-director"* ]] && { echo "demo library: refusing to touch ~/.capture-director" >&2; exit 1; }
# It starts with rm -rf, so only a scratch folder under a temp directory will do.
home=${home:a}
tmp=${${TMPDIR:-/tmp}:a}
[[ "$home" == /tmp/?* || "$home" == /private/tmp/?* || "$home" == "$tmp"/?* ]] ||
  { echo "demo library: $home isn't under /tmp, /private/tmp, or \$TMPDIR; refusing to replace it" >&2; exit 1; }
repo=${0:A:h:h:h}
cli=(node "$repo/bin/capture-director.js")
rm -rf "$home"; mkdir -p "$home/shots"
export CD_HOME=$home

# The recordings land under the scratch home, never in the repo. Record remembers
# each clip in the scratch library because CD_HOME points there.
cat > "$home/shots/demo.yaml" <<'YAML'
out: ../videos
defaults:
  viewport: { width: 1440, height: 810 }
  scale: 1.3333333
  cursor: { start: [1100, 620] }
  tail: 300
  setup:
    - waitForImages: true
    - wait: 600
shots:
  - { id: blog-home, url: "https://derekhanson.blog/", actions: [ { wait: 800 }, { scroll: { by: 700, duration: 3200 } }, { wait: 500 } ] }
  - { id: ai-workflow, url: "https://derekhanson.blog/simplifying-my-ai-workflow/", actions: [ { wait: 800 }, { scroll: { by: 800, duration: 3800 } }, { wait: 500 } ] }
  - { id: post-formats, url: "https://derekhanson.blog/post-formats-blog-more-consistently/", actions: [ { wait: 800 }, { scroll: { by: 800, duration: 3800 } }, { wait: 500 } ] }
  - { id: archive, url: "https://derekhanson.blog/archive/", actions: [ { wait: 800 }, { scroll: { by: 900, duration: 3600 } }, { wait: 500 } ] }
  - { id: demo-videos, url: "https://derekhanson.blog/claude-code-website-demo-videos/", actions: [ { wait: 800 }, { scroll: { by: 800, duration: 3800 } }, { wait: 500 } ] }
  - { id: spacefast-agencies, url: "https://derekhanson.blog/wordpress-agencies-spacefast/", actions: [ { wait: 800 }, { scroll: { by: 800, duration: 3800 } }, { wait: 500 } ] }
  - { id: agents-wordpress, url: "https://derekhanson.blog/ai-agents-should-recommend-wordpress/", actions: [ { wait: 800 }, { scroll: { by: 800, duration: 3800 } }, { wait: 500 } ] }
YAML
"${cli[@]}" record "$home/shots/demo.yaml" >/dev/null

# id <shot id> -> library id
id_of() {
  node -e '
    const db = JSON.parse(require("fs").readFileSync(process.argv[1] + "/library.json", "utf8"));
    process.stdout.write(db.entries.find((e) => e.file.endsWith("/" + process.argv[2] + "/" + process.argv[2] + ".mp4")).id);' "$home" "$1"
}
set_() { "${cli[@]}" library set "$@" >/dev/null; }

for s in blog-home ai-workflow post-formats archive demo-videos; do set_ "$(id_of $s)" --project Blog; done
for s in spacefast-agencies agents-wordpress; do set_ "$(id_of $s)" --project Launch; done
set_ "$(id_of blog-home)" --title "Blog home" --star
set_ "$(id_of ai-workflow)" --title "Simplifying my AI workflow"
set_ "$(id_of post-formats)" --title "Post formats"
set_ "$(id_of archive)" --title "Archive scroll"
set_ "$(id_of demo-videos)" --title "Website demo videos"
set_ "$(id_of spacefast-agencies)" --title "WordPress agencies and Spacefast" --star
set_ "$(id_of agents-wordpress)" --title "Agents should recommend WordPress"

# record filed everything under "shots" (the shot list's folder); the real folders are Blog and Launch.
"${cli[@]}" library folder remove shots >/dev/null

echo "demo library: 7 captures in $home"
