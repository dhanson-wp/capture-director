# Recording Mac apps: design

Status: approved 2026-11-03; implemented on mac-app-recorder

## Why this exists

Capture director records websites in headless Chrome. Derek wants a polished video of the capture director Mac app itself, which Chrome can't film, and then wants to build a full launch video from it in Hyperframes. He isn't in a hurry, so this ships as a real feature in a public release, not a one-off script.

The good news: recording and polishing are already separate. `record` writes raw frames plus `capture.json` (clicks, hovers, cursor moves, presses, with times and positions), and `processShot` in `src/shots.js` turns those into zooms and a drawn cursor without knowing Chrome made them. So the feature is a second recorder that writes the same output for a Mac app. Everything after it (zoom, cursor, `render`, `sheet`, `stills`, the library) works unchanged.

## Goals

1. **Record any Mac app from a shot list.** A shot names an app instead of a URL. The same `capture-director record shots.yaml` command records it, and `process`, `render`, `sheet`, and the library work on the result as they do for web shots.
2. **Nothing but the app.** Only the target app's windows show up: its main window, plus its own sheets, popovers, and menus. No desktop, wallpaper, Dock, menu bar, notifications, or other apps.
3. **A plain background.** The app window sits centered on a solid color with its normal macOS shadow, in a 1920x1080 frame. Derek picked the brand's mulberry purple (`#4c1637` in `ui/app.css`) for the launch video; the color is a shot option, not hard-coded.
4. **Scripted like web shots.** Actions are the familiar ones (`click`, `hover`, `move`, `wait`, `key`, `type`, `scroll`) with `zoom` and `hold`, so a shot list for a Mac app reads like one for a site.
5. **The capture director tour.** A ready example, `examples/mac-app-tour/`, that records the app: the grid of videos, a few sidebar items (All captures, a folder, Starred), playing one capture in the app's player (`PlayerSheet`) for a few seconds, closing it, then zooming into the inspector panel for that capture (title, notes, web and small copies). Derek chose "play it, then inspector" on 2026-11-03, so the player sheet must record cleanly (goal 2 covers sheets). Quick Look is not part of the tour. It starts with the app already open; no Dock click.
6. **Shipped.** README section, tests, and a GitHub release (0.2.0).

## Non-goals

- **Clicking the Dock or Launchpad.** Derek chose to start with the app open. The launch moment, if he wants one, happens in Hyperframes.
- **Audio.** Music and sound come from `render` or Hyperframes, as today.
- **Running in the background or in CI.** Native recording drives the real screen. It runs on Derek's Mac while he steps away for a minute.
- **Windows and Linux.** macOS only. The command fails plainly elsewhere.
- **Full-screen apps, multiple displays, or multi-window choreography.** One main window on the main display.
- **The Hyperframes launch video itself.** That's the next project. This one delivers the clips it needs.

## Anti-goals (failure even if it works)

- **Anything outside the target app is ever captured.** No other window, no notification banner, no wallpaper, not even for one frame. This is a public video, and it's a privacy promise for anyone who uses the feature.
- **Derek's own captures show up in the tour.** The example records against a demo library, never `~/.capture-director`.
- **The user's Mac is left in a strange state.** If recording fails or is cancelled, the mouse is released, keys aren't stuck down, and the app's window goes back to where it was.
- **Opening a hole in the filter graph.** The background color and every new value from YAML or `capture.json` must be a finite number or a validated plain value (hex color) before it reaches ffmpeg, per the 2026-10-27 decision.
- **New npm dependencies or a heavy toolchain.** The native side is Swift in the existing `mac/` package, built by the same `build.sh`.

## How it's built (decided)

- **A Swift helper does the native work.** A small command-line tool in the `mac/` Swift package (built and signed alongside the app) captures with ScreenCaptureKit and drives the app through the Accessibility API. Node stays the front door: `record` sees an `app:` shot, runs the helper with the shot as JSON, and then calls the existing `processShot`.
- **The helper writes what Chrome writes.** Raw frames and a `capture.json` with the same fields (`viewport`, `duration`, `events`, `moves`, `presses`, `cursorStart`), in the coordinate space of the composed 1920x1080 frame. The system cursor is hidden in the capture so the existing drawn cursor is the only one.
- **Elements are found through accessibility,** not pixel coordinates, so a shot keeps working when the layout shifts. Shots target an element by its accessibility identifier, or by role and label (for example, the sidebar row labelled "Starred"). Raw coordinates stay available as a fallback, like `move: [x, y]` today.
- **Capture director's own app gets accessibility identifiers** on the sidebar rows, grid items, and inspector controls it needs (it has none today). That also helps VoiceOver and the app's self-test.
- **A fixed window size.** The helper sizes and places the target window (default 1440x900 points) before recording, so every take frames the same, and restores it afterwards.
- **Permissions are explained, not hit.** Screen Recording and Accessibility are checked before anything happens. If either is missing, the command fails with one plain sentence on where to grant it, and exits non-zero.
- **A countdown and an escape.** Recording starts after a short countdown on stderr, and pressing Escape cancels cleanly. The output JSON says the shot was cancelled rather than writing a half clip.
- **The demo library.** The tour example points the app at a scratch `CD_HOME` filled with good-looking demo captures (made by capture director from public sites), built by a script in the example folder.

## Calls made after the builder review (Claude's, for Derek to check)

- **How the app ends up "already open" on the demo library.** An app shot can set `env` (for the tour, `CD_HOME`). Before the countdown, the helper quits the app if it's running, relaunches it with that environment, waits for its window, and sizes it. After the take it quits that copy and relaunches the app normally if it was running before. Recording starts only once the window is up, so the video still opens on the app.
- **Who holds the permissions.** The helper lives inside `Capture Director.app` and runs as the app, so macOS grants Screen Recording and Accessibility to Capture Director, not to Terminal or whichever app ran the CLI. `record` finds the helper through the installed app's location (the same `config.json` handshake `install-app` already writes) and tells you to run `capture-director install-app` if it isn't there.
- **Release packaging.** There's no Developer ID on this Mac, so 0.2.0 stays build-from-source like 0.1.0: the GitHub release has notes and source, no prebuilt binary. Ad-hoc signing means macOS may ask for permission again after a rebuild; the README says so. A notarized download is a later project if Derek gets a Developer ID.
- **Sharpness.** The helper captures at the display's Retina scale and composes a 3840x2160 frame, so 1.7x zooms stay crisp after `processShot` scales to 1080p. The window takes up about 80% of the frame width, leaving room for its shadow. `processShot` already derives size from the first frame; the builder checks the coordinate math holds.
- **Bundle ID.** The example uses the real one, `io.github.dhanson-wp.capture-director`.

## Shot list shape (sketch; details are the builder's)

```yaml
out: out
defaults:
  background: "#4c1637"
shots:
  - id: tour
    app: io.github.dhanson-wp.capture-director   # bundle ID; an .app path also works
    window: { width: 1440, height: 900 }
    actions:
      - wait: 800
      - click: { role: row, label: "Starred" }
        zoom: 1.3
      - click: { id: "grid.item.0" }
      - click: { id: "inspector" }
        zoom: 1.7
        hold: 2400
```

A shot has `url` or `app`, never both. Web-only options (`scale`, `hideScrollbars`, `setup` steps like `waitForImages`) are rejected on app shots with a clear message rather than silently ignored.

## Left to the builder

- Whether the helper composites the window onto the background itself, or hands ffmpeg a window-only capture to composite. Either is fine if goal 2's privacy promise holds.
- How sheets and popovers that extend past the main window are framed.
- Frame format and rate from the helper, as long as `processShot` reads it unchanged or with a small, tested branch.
- The exact selector syntax, the helper's name, and how its signature stays stable enough that macOS doesn't re-ask for permission after every rebuild.
- Which demo captures fill the tour library.

## Done means

- `capture-director record examples/mac-app-tour/shots.yaml` produces a 1080p clip of the app on mulberry, with smooth zooms and the drawn cursor, and nothing else on screen.
- Missing permissions, a missing app, and a bad selector each fail with one plain sentence.
- Node tests cover the new shot validation; Swift tests cover the coordinate math and selector matching. Existing tests and the Mac self-test still pass.
- README documents app shots and the permissions. Released as 0.2.0.
