# Capture director

I wanted Screen Studio-style demo clips of a website without sitting there driving Screen Studio myself. Capture director lets an agent (or me) write a shot list, record it in headless Chrome, and get back a crisp 1080p clip with eased zooms on every click and a clean cursor. A second file assembles clips, title cards, an end card, and a music bed into the final video.

It runs locally. Nothing gets uploaded anywhere.

## What you need

- macOS (it's only been tested there so far)
- Node 20 or newer
- Google Chrome (it drives the installed Chrome through Playwright, so there's no browser download)
- ffmpeg with libx264 (`brew install ffmpeg`)

```bash
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

## Shot list reference

Top level: `out` (folder for captures, relative to the YAML file), `defaults` (merged into every shot), and `shots`.

Per shot, or in `defaults`:

| Key | Default | What it does |
|---|---|---|
| `id` | `shot-N` | Folder and file name |
| `url` | | Page to record |
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
| `hideWpBars` | `true` | Hides the WordPress admin bar and the `#atomic-proxy-bar`, which some WordPress.com setups show even to logged-out visitors |

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
    caption: { text: "Writing, notes, and projects", start: 1.2, end: 8, plate: "rgba(20,19,18,0.72)" }
```

Caption fields: `text`, `start` and `end` (seconds into the item; defaults leave 0.6 s at each end), `fade`, `position` (`bottom-left`, `bottom-right`, `top-left`, or `top-right`), `size`, `opacity`, `color`, `margin`, `weight`, `shadow`, `plate` (a backing color for busy or light footage), and `font`. A plain string works too: `caption: Every post, in one place.`

Card fields: `kicker`, `title`, `subtitle`, `url`, `duration`, `align` (`center` or `left`), `background`, `color`, `muted`, `titleSize`, `subtitleSize`, `weight`, `stretch`, `font`, `fontFamily`, and `monoFont`.

Cards are drawn by headless Chrome from the font file, not by ffmpeg's `drawtext`. Many ffmpeg builds, Homebrew's included, ship without `drawtext`, and Chrome's text rendering is better anyway: real kerning, variable font weights and widths, and proper antialiasing.

## Commands

```bash
capture-director record <shots.yaml> [--only id,id]   # record, then add zoom and cursor
capture-director process <shots.yaml> [--only id,id]  # redo zoom and cursor without re-recording
capture-director render <timeline.yaml> [--out file]  # assemble the final video
capture-director sheet <video.mp4> [--every 1]        # contact sheet PNG
capture-director stills <video.mp4> 1.5,4,8           # full-size PNG stills
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

- **Everything runs on your machine.** There's no server, no account, and no telemetry. Nothing is uploaded.
- **The browser starts logged out every time.** Each shot gets a fresh, empty Chrome profile, with no cookies, saved passwords, or extensions from your own browser. You can't accidentally record your admin bar or inbox.
- **Network traffic goes only where you point it:** the URLs in your shot list, plus any font or music URLs in your timeline.
- **A shot list is a script.** The `eval` and `css` steps run code inside the page you're recording, and file paths read local files (fonts, music, clips). Read a shot list from someone else before you run it, the same way you'd read a shell script.
- **Two dependencies:** `playwright-core` (it drives your installed Chrome, with no browser download) and `yaml`. `npm audit` reports no known vulnerabilities.
- **Mind what's on the page.** It records exactly what a logged-out visitor sees. Don't record staging sites or pages with personal data you wouldn't publish.

## Accessibility

Videos made with it have no voiceover, so they read fine on mute. Captions are drawn into the picture rather than shipped as a caption track, so write a short text description wherever you post the video. Keep captions on screen for at least two seconds, and use `plate` when text sits on busy footage, so the contrast holds up.

## Tests

```bash
npm test
```

The tests cover the zoom planner, step parsing, and a check that the generated ffmpeg expressions parse.

## License

MIT. See `LICENSE`.
