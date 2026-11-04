# Capture director

I wanted Screen Studio-style demo clips of a website without sitting there driving Screen Studio myself. Capture director lets an agent (or me) write a shot list, record it in headless Chrome, and get back a crisp 1080p clip with eased zooms on every click and a clean cursor. A second file assembles clips, title cards, an end card, and a music bed into the final video.

It runs locally. Nothing gets uploaded anywhere.

https://github.com/user-attachments/assets/9b76dea2-7330-4a5d-ae31-57a5bec42116

Here's what it made from one shot list and one timeline: a 31 second tour of the new post formats on my blog, with eased zooms, a synthetic cursor, captions, and cards.

## What you need

- macOS (it's only been tested there so far)
- Node 20 or newer
- Google Chrome (it drives the installed Chrome through Playwright, so there's no browser download)
- To record a Mac app, the Mac app installed (see below) and macOS 26 or later
- ffmpeg with libx264 (`brew install ffmpeg`)

```bash
git clone https://github.com/dhanson-wp/capture-director.git
cd capture-director
npm install
npm link   # optional, puts capture-director on your PATH
```

## How it works

1. **Record.** Playwright opens a fresh, logged-out Chrome at your viewport (1440x810 by default) with Chrome itself running at a 4/3 scale factor, so every frame is 1920x1080 device pixels. The CDP screencast saves every compositor frame as a JPEG (quality 95) with its real timestamp, which comes out at 60 fps while anything on the page is moving. Playwright's `recordVideo` is softer, so it isn't used.
2. **Log.** Every cursor move, click, and hover is logged with its time and position. Headless Chrome has no cursor, so the log is what drives the synthetic one.
3. **Process.** ffmpeg turns the frames into a constant 30 fps stream using the true frame durations, draws the cursor (with a little press on clicks), and applies eased zoom-ins and zoom-outs around the logged clicks. The zoom uses the `perspective` filter, which works in sub-pixel steps, so it doesn't wobble the way `zoompan` does.
4. **Render.** A timeline file orders clips and cards, crossfades between them, fades in and out of black, and lays a looped, faded music bed underneath. Exports are H.264 at CRF 16.

## Worked example: a blog tour

The example lives in `examples/blog-tour/`. It opens a WordPress blog, hovers the Writing menu, scrolls to Recent posts, clicks into a post, then reads down the post in a second shot. Swap the URLs and selectors for any site.

```bash
cd examples/blog-tour
capture-director record shots.yaml
capture-director render timeline.yaml
capture-director sheet out/blog-tour.mp4
```

The first command writes one clip per shot to `out/home/home.mp4` and `out/post/post.mp4`. The second wraps them with a title card, captions, and an end card, and writes `out/blog-tour.mp4` (about 24 seconds, 1920x1080). The third makes a contact sheet so you can check the result at a glance.

Here's the first shot:

```yaml
out: out

shots:
  - id: home
    url: https://derekhanson.blog/
    cursor: { start: [1100, 620] }
    setup:                       # runs before recording starts
      - waitForImages: true
      - wait: 1000
    actions:                     # recorded
      - wait: 1200
      - hover: "text=Writing"
        zoom: 1.5
        hold: 1800
      - move: [1100, 560]
        duration: 900
      - scroll: { to: "text=Recent posts", block: start, duration: 2200 }
      - wait: 700
      - click: "text=Why I’m simplifying my AI workflow"
        zoom: 1.6
        hold: 2600
```

Selectors are Playwright selectors, so CSS (`.menu a`), text (`text=Writing`), and attributes (`[data-next]`) all work.

When a click changes something far from the button, add `zoomOn: [buttonSelector, changedSelector]`. The zoom then frames the box around both, instead of cropping out the thing that changed.

## Recording a Mac app

Websites aren't the only thing I want to film. Capture director can also record a native Mac app: it opens the app, drives it with the real mouse and keyboard, and hands back the same polished clip. It records only the app's windows, centered on a solid color, so the Dock, menu bar, wallpaper, and your other apps never show up.

It needs the Mac app (`capture-director install-app`), because the recorder lives inside it. Use `app:` in place of `url:`, with a bundle ID or the path to a `.app`:

```yaml
out: out

shots:
  - id: tour
    app: io.github.dhanson-wp.capture-director
    env:
      CD_HOME: /tmp/capture-director-tour-home   # environment for the app
    window: { width: 1440, height: 900 }         # the default; shrinks to fit your display
    background: "#4c1637"                        # the default
    countdown: 3                                 # seconds before the take starts; the default
    zoom: { on: [hover] }
    actions:
      - wait: 1200
      - hover: { id: sidebar.folder.Blog, zoom: 1.5, hold: 700 }
      - click: { id: sidebar.starred, hold: 900 }
      - click: { id: grid.item.0, hold: 500 }
      - press: cmd+o
      - wait: 3000
      - press: ctrl+cmd+i
```

The full tour is in `examples/mac-app-tour/`. `make-demo-library.sh` fills a scratch library so the app has something to show, and `env` points the app at it, so the tour never touches `~/.capture-director`. The inspector starts hidden, so the tour presses Control-Command-I to show it. Relative `env` values that start with `./` or `../` resolve from the YAML file's folder.

The app is recorded at 3840x2160 on the solid color, and then the usual zoom and cursor step turns that into a 1080p clip. The window is about 80 percent of the frame width, with its macOS shadow.

### Steps and targets

The steps that work on an app shot are `wait`, `click`, `hover`, `move`, `press`, `type`, and `scroll`. `press` takes a key with modifiers, like `cmd+o` or `ctrl+cmd+i`. `move` takes a point in the 1920x1080 frame (the same space as the coordinates in `capture.json`) or a target.

A target is how a step finds a control through the app's accessibility tree. Use whichever fits:

```yaml
- click: { id: sidebar.starred }                 # accessibility identifier
- click: { role: button, label: "New folder" }   # role plus label
- click: "New folder"                            # a bare label, any role
```

An `id` is the sturdiest, since it doesn't change with the app's wording. If you build the app yourself, set the accessibility identifier on the controls you plan to film.

Shot options that only make sense for a web page (`scale`, `hideScrollbars`, `setup`, `viewport`, `css`, `hide`, and `waitUntil`) are rejected on an app shot, by name. Per-step `zoom: false` isn't supported on app shots yet. To zoom only on hovers and leave clicks at full frame, set `zoom: { on: [hover] }` on the shot, as the tour does.

### Permissions

macOS asks for two permissions, and both go to Capture Director, not to Terminal or your agent:

- **Screen Recording**, to capture the app's windows.
- **Accessibility**, to find controls and to move the mouse and press keys.

The first take asks for Screen Recording, and the next asks for Accessibility. Allow each in System Settings, then record again.

The app is ad-hoc signed, so every rebuild or reinstall changes its signature. macOS then quietly stops honoring the old grant, even though the switch still looks on. If a take stalls on a permission you already gave, reset both and allow the prompts again:

```bash
tccutil reset ScreenCapture io.github.dhanson-wp.capture-director
tccutil reset Accessibility io.github.dhanson-wp.capture-director
```

Keep one copy of the app installed. Two copies with the same app ID confuse the permission list. `CD_APP` points the CLI at a specific copy if you need to.

### During a take

The take drives your real mouse and keyboard, so keep your hands off. Moving the mouse or pressing Escape cancels it cleanly, and no clip is written. Each shot folder gets a `recorder.log` that says what stopped a take, which is the first place to look when one ends early.

If the app is already open with unsaved work, the take asks you to quit it first. It won't force-quit anything.

Agents running in a sandboxed shell are fine: the CLI starts the recorder through LaunchServices (`open`), which works from a sandbox. Launching the app's binary directly from a sandboxed shell can hang, so don't.

Recording Mac apps only works on macOS, and it records the main display.

## Shot list reference

Top level: `out` (folder for captures, relative to the YAML file), `project` (the library project; defaults to the YAML file's folder name), `defaults` (merged into every shot), and `shots`.

Per shot, or in `defaults`:

| Key | Default | What it does |
|---|---|---|
| `id` | `shot-N` | Folder and file name. Letters, numbers, dots, dashes, and underscores |
| `url` | | Page to record (`http` or `https`). A shot has `url` or `app`, never both |
| `app` | | Mac app to record instead; see [Recording a Mac app](#recording-a-mac-app) |
| `viewport` | `{ width: 1440, height: 810 }` | CSS viewport |
| `scale` | `1.3333333` | Device scale factor; output is viewport x scale. Use `2` for crisper zooms |
| `output` | `1920x1080` | Final clip size |
| `fps` | `30` | Output frame rate (60 works too) |
| `crf` | `16` | x264 quality |
| `quality` | `95` | Screencast JPEG quality |
| `tail` | `800` | Milliseconds to keep recording after the last action |
| `cursor` | `{ enabled: true, size: 1, start: [x, y] }` | Synthetic cursor; `false` turns it off and keeps the real pointer off the page, so it can't trigger hover effects |
| `zoom` | see below | Auto-zoom settings; `false` turns it off |
| `colorScheme` | | `light` or `dark` |
| `waitUntil` | `networkidle` | Page load condition |
| `hideWpBars` | `true` | Hides the WordPress admin bar and the `#atomic-proxy-bar`, which some WordPress.com setups show even to logged-out visitors, on every page the shot visits |

Mac app shots also take `env`, `window`, `background`, and `countdown`, described in the section above.

Zoom settings: `level` (1.6), `max` (2.0), `on` (`[click, hover]`), `lead` (0.25 s; how early the zoom finishes before the click), `ramp` (0.9 s in), `rampOut` (1.0 s out), `hold` (1.4 s after the last click before zooming out), `pan` (0.7 s between clicks in one zoom), `gap` (0.6 s; zooms closer than this merge into one), and `padding` (0.12, around a `zoomOn` box). Clicks that land close together stay zoomed in and pan between targets, which is how Screen Studio feels.

### Steps

Each step has one main key. A bare value is the target; extra keys are options.

| Step | Example | Notes |
|---|---|---|
| `wait` | `- wait: 1000` | Milliseconds. A bare number works too |
| `waitFor` | `- waitFor: ".hero"` | Waits until visible |
| `click` | `- click: "#buy"` | Eased cursor move, then a click. Options: `zoom` (number or `false`), `zoomOn`, `duration` (move ms), `offset: [x, y]`, `hold` (ms after), `inView` (use the first match fully on screen) and `skip` (pass over that many on-screen matches first) |
| `hover` | `- hover: ".card"` | Same options as `click` |
| `move` | `- move: [800, 400]` | Cursor only, no zoom. Takes a selector too |
| `drag` | `- drag: [-400, 30]` | Press, move with the button held, release, from wherever the cursor is. Orbits 3D scenes, pans maps, drags sliders. Or `{ from, to }` with points or selectors. Options: `duration` (ms), `hold`. No zoom |
| `camera` | `- camera: "#hero"` | A push-in with no cursor. Options: `zoom`, `duration` (ms), `hold` (ms; stays to the end by default), `fit: false` to zoom past the box size |
| `scroll` | `- scroll: { by: 600, duration: 1400 }` | Eased in-page scroll. Or `to: selector` with `block: center`, `start`, or `end` |
| `press` | `- press: ArrowRight` | Any Playwright key name |
| `type` | `- type: { target: "#q", text: "hello", delay: 80 }` | Types with a per-key delay |
| `eval` | `- eval: "document.body.classList.add('x')"` | Runs in the page |
| `css` | `- css: ".cookie { display: none }"` | Injects a style tag |
| `hide` | `- hide: [".cookie", "#wpadminbar"]` | Hides elements |
| `scrollTo` | `- scrollTo: "#pricing"` | Setup only; jumps there instantly |
| `waitForImages` | `- waitForImages: true` | Waits for images near the viewport to load |

In `setup`, `click`, `hover`, and `type` act instantly with no cursor or zoom, since nobody sees setup.

## Timeline reference

```yaml
output: out/final.mp4
size: 1920x1080
fps: 30
crf: 16
font: path/or/url/to/font.woff2       # cards: .ttf, .otf, .woff, or .woff2
monoFont: path/or/url/to/mono.woff2   # kicker and URL lines
card: { background: "#151515", color: "#f2efe9", weight: 450 }
transition: { type: fade, duration: 0.7 }   # any ffmpeg xfade name
fade: { in: 0.6, out: 1.2 }                 # from and to black
music: { file: bed.m4a, volume: 0.7, fadeIn: 1.5, fadeOut: 3, start: 0 }
items:
  - card: { kicker: "example.com", title: "A short product tour", duration: 3 }
  - clip: out/home/home.mp4
    trim: [0.4, 10]
    transition: { type: smoothleft, duration: 0.8 }   # into this item; false for a hard cut
  - end: { title: "example.com", url: "Made with capture-director", duration: 4 }
```

Any clip or card can carry a `caption`: a short line drawn over the footage, which fades in and out with the item. Set the shared look with a top-level `caption` block and override it per item.

```yaml
caption: { position: bottom-left, opacity: 0.7, size: 28, margin: 72 }   # font defaults to monoFont
items:
  - clip: out/home/home.mp4
    caption: { text: "Writing, notes, and projects", start: 1.2, end: 8, opacity: 1, plate: "rgba(20,19,18,0.72)" }
```

Caption fields: `text`, `start` and `end` (seconds into the item; defaults leave 0.6 s at each end), `fade`, `position` (`bottom-left`, `bottom-right`, `top-left`, or `top-right`), `size`, `opacity`, `color`, `margin`, `weight`, `shadow`, `plate` (a backing color for busy or light footage), and `font`. `opacity` (0.7 by default) fades the plate along with the text, so set it to 1 when you use a plate, and pick a plate color that contrasts with the page rather than one that matches its background. A plain string works too: `caption: Every post, in one place.`

To make a clean version of the same video, run `render` with `--no-captions` and an `--out` of its own, such as `capture-director render timeline.yaml --no-captions --out out/clean.mp4`. Cards, transitions, and music stay the same.

Card fields: `kicker`, `title`, `subtitle`, `url`, `duration`, `align` (`center` or `left`), `background`, `color`, `muted`, `titleSize`, `subtitleSize`, `weight`, `stretch`, `font`, `fontFamily`, and `monoFont`.

Cards are drawn by headless Chrome from the font file, not by ffmpeg's `drawtext`. Many ffmpeg builds, Homebrew's included, ship without `drawtext`, and Chrome's text rendering is better anyway: real kerning, variable font weights and widths, and proper antialiasing.

## Commands

```bash
capture-director record <shots.yaml> [--only id,id]   # record, then add zoom and cursor
capture-director process <shots.yaml> [--only id,id]  # redo zoom and cursor without re-recording
capture-director render <timeline.yaml> [--out file]  # assemble the final video
                  [--no-captions]                    # same video, with every caption left out
capture-director sheet <video.mp4> [--every 1]        # contact sheet PNG
capture-director stills <video.mp4> 1.5,4,8           # full-size PNG stills
capture-director library                              # browse and organize everything you've made
capture-director library add <folder or video>        # bring in videos made before the library
capture-director library folder add clients/acme      # make a folder (nest with /)
capture-director library folder rename acme acme-2026 # rename or move a folder and everything in it
capture-director library folder remove clients/acme   # remove an empty folder
capture-director library set <id>... --project clients/acme --star   # retitle, move, star, or add notes
capture-director library forget <id>...               # drop captures from the library; videos stay on disk
capture-director library export <id> [--preset web|small]   # make a smaller copy for size-limited uploads
capture-director library relocate <id> <new path>     # point a capture at its video's new location
capture-director install-app [--dir /Applications]    # build and install the Mac app
```

If a shot's frames ever come back the wrong size, the recorder stops with an error instead of stretching them. Setting `CD_CHROME_CHANNEL=bundled` switches to Playwright's cached headless shell.

Every command prints a JSON summary on stdout and progress on stderr, so an agent can read the result without scraping logs.

`process` is the one to reach for when you're tuning zooms. Change `zoom` settings in the shot list and rerun it; the raw frames stay on disk in `out/<id>/frames/`.

## What's in a shot folder

- `frames/`: the raw JPEGs and `list.ffconcat` with their real durations
- `capture.json`: the event log (clicks, hovers, moves, presses), in CSS pixels and seconds
- `zoom-plan.json`: the zoom keyframes it chose
- `filter.txt`: the exact ffmpeg filter graph, handy when something looks off
- `<id>.mp4`: the finished clip

## Keeping captures organized

Clips end up wherever each shot list lives, which gets scattered fast. So every clip from `record` and every video from `render` also lands in a library, and `capture-director library` opens it in your browser.

It works a bit like Screen Studio's or Loom's library. Captures show as a grid of thumbnails you can search, sort, and filter to starred, final videos, or clips. Each one belongs to a project (the folder its shot list sits in, until you rename it). Open one to play it, retitle it, move it to another project, star it, jot a note, show it in Finder, or copy the command that records it again. New recordings show up while the library is open.

The library is a list of pointers, kept in `~/.capture-director/library.json`. Your videos stay where they were rendered. "Remove from library" forgets an entry and never touches the file; deleting a video is something you do in Finder.

Already have videos? `capture-director library add ~/Projects/demos` walks a folder and adds every `.mp4`, `.mov`, and `.m4v` it finds. Set `CD_HOME` to keep the library somewhere else, or `CD_NO_LIBRARY=1` to stop `record` and `render` from adding to it.

### Mac app

I also built a native Mac app on top of the same library. It's the quickest way to find a clip, sort it into folders, and get the real file into whatever upload page you're staring at: drag a capture straight out of the grid and drop it on the page. If a site caps upload size, the app can make a web or small copy first, and you drag that instead.

```bash
capture-director install-app                     # installs to /Applications
capture-director install-app --dir ~/Applications   # or just for you
```

If you can't write to /Applications (it takes an admin account), it goes in ~/Applications instead. You don't need Xcode; the Command Line Tools are enough to build it. It needs macOS 26 or later.

It's local only, like everything else here. It reads and writes the same `library.json`, so the browser library and the app always agree, and it never moves or deletes your videos.

Agents get the same powers from the command line. `library export` makes the smaller copy, `library set` takes ids before flags, and `library relocate` fixes an entry after you've moved a file.

## Using it from Claude Code or Codex

`skill/SKILL.md` teaches an agent the whole workflow: scout the page, write the shot list, record, check its own contact sheets, and fix what it finds. Link it into your agent's skills folder:

```bash
ln -s "$PWD/skill" ~/.claude/skills/capture-director   # Claude Code
ln -s "$PWD/skill" ~/.agents/skills/capture-director   # Codex
```

Then ask for something like "record a 10 second clip of the pricing page, hovering each plan."

## Where it fits

Capture director makes the footage: real, crisp recordings of a live site with Screen Studio-style polish. Its `render` command is a simple assembler for straightforward videos (clips, cards, captions, music).

For a more designed piece, such as kinetic type, animated end cards, or motion graphics, use the clips as footage in a motion tool like HyperFrames, Resolve, or Premiere. Capture director records, and the other tool edits.

## Safety and privacy

- **Everything runs on your machine.** There's no server you don't run, no account, and no telemetry. Nothing is uploaded.
- **Recording a Mac app is the one time it drives your real mouse and keyboard.** That's why macOS makes you grant Screen Recording and Accessibility to Capture Director. It captures only the target app's windows, never the rest of your screen, and moving the mouse or pressing Escape stops it.
- **The browser starts logged out every time.** Each shot gets a fresh, empty Chrome profile, with no cookies, saved passwords, or extensions from your own browser. You can't accidentally record your admin bar or inbox.
- **Chrome keeps its sandbox on.** Playwright turns Chrome's sandbox off by default; capture director turns it back on, since it's visiting websites you don't control. Downloads are refused. (`CD_NO_SANDBOX=1` is there for containers that can't run it.)
- **Network traffic goes only where you point it:** the URLs in your shot list, plus any font URLs in your timeline. Shot URLs must be `http` or `https`, and clips and music must be local files, so ffmpeg never fetches anything.
- **A shot list is a script.** The `eval` and `css` steps run code inside the page you're recording, an `app` shot launches an app and presses keys in it, and file paths read local files (fonts, music, clips). Read a shot list from someone else before you run it, the same way you'd read a shell script. Within that, the YAML can't reach outside what it describes: values that end up in ffmpeg filter graphs must be plain numbers or known names, shot ids must be plain names, outputs need a video extension, and re-recording only clears the frame files it wrote.
- **The library stays on your machine.** `capture-director library` listens on `127.0.0.1` only, answers only to its own address, and needs the one-time link printed in your terminal. It can't be reached from your network or driven by other websites, and it never deletes a file.
- **Two dependencies:** `playwright-core` (it drives your installed Chrome, with no browser download) and `yaml`. `npm audit` reports no known vulnerabilities.
- **Mind what's on the page.** It records exactly what a logged-out visitor sees. Don't record staging sites or pages with personal data you wouldn't publish.

See [SECURITY.md](SECURITY.md) for the details and how to report a problem.

## Accessibility

Videos made with it have no voiceover, so they read fine on mute. Captions are drawn into the picture rather than shipped as a caption track, so write a short text description wherever you post the video. Keep captions on screen for at least two seconds, and use `plate` when text sits on busy footage, so the contrast holds up.

## Tests

```bash
npm test            # the CLI
mac/tools/test.sh   # the Mac app's unit tests
```

The tests cover the zoom planner, app shot parsing, step parsing, a check that the generated ffmpeg expressions parse, the input checks that keep YAML out of the filter graph, and the library server's access rules. The Mac app has its own Swift tests. GitHub Actions runs them on Node 20 and 22 for every pull request and every push to `main`.

## License

MIT. See `LICENSE`.
