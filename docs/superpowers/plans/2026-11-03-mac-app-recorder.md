# Mac app recorder implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `capture-director record` records a Mac app from a shot list (`app:` instead of `url:`), showing only that app's windows on a solid color, and the existing zoom, cursor, and render steps polish it.

**Architecture:** Node stays the front door. For an `app:` shot it writes a job file and launches `Capture Director.app` in a new record mode through LaunchServices (`open -n -W`), so macOS grants permissions to Capture Director. The app's record mode relaunches the target with the shot's environment, drives it through the Accessibility API and real mouse and key events, records the target's windows with ScreenCaptureKit into `raw.mov`, and writes `capture.json` in the same shape Chrome shots use. Node then runs the existing `processShot`, which gains one small branch to read a video instead of a frame list.

**Tech Stack:** Node 20+ (ESM, `node --test`), Swift 6.2 package in `mac/` (macOS 26), ScreenCaptureKit, AVFoundation (`AVAssetWriter`), ApplicationServices (AX, `CGEvent`), ffmpeg.

**Spec:** `docs/superpowers/specs/2026-11-03-mac-app-recorder-design.md`

One naming change from the spec's sketch: the key step is `press` (the existing web step name), not `key`, so one vocabulary covers both kinds of shot.

## Global constraints

- No new npm dependencies. Native work is Swift in the existing `mac/` package, built and signed by `mac/build.sh`.
- macOS only. On any other platform an `app:` shot fails with: `Recording Mac apps only works on macOS.`
- A shot has `url` or `app`, never both. Web-only options on an app shot (`scale`, `hideScrollbars`, `setup`, `viewport`, `css`, `hide`, `waitUntil`) are rejected by name.
- Anything from YAML, the job file, or `capture.json` that reaches an ffmpeg filter graph is a finite number or a validated plain value. `background` must match `/^#[0-9a-fA-F]{6}$/`.
- Only the target app's windows are ever captured: no wallpaper, Dock, menu bar, notifications, or other apps' windows, not for one frame.
- The composed frame is 3840x2160 with the target window at about 80% of the frame width, centered, with its macOS shadow; `capture.json` reports `viewport: { width: 1920, height: 1080 }` so `processShot` computes `k = 2`.
- Default window size is 1440x900 points. Default background is `#4c1637`.
- The example uses bundle ID `io.github.dhanson-wp.capture-director` and never touches `~/.capture-director`.
- Recording uses the main display only. The system cursor is hidden in the capture (`showsCursor = false`).
- Failures print one plain sentence and exit non-zero. Cancelled takes write no clip.
- Prose (README, errors, PR) follows Derek's voice: no em dashes, contractions, sentence case.
- Each Swift change builds with no warnings (`mac/CLAUDE.md`). Scratch builds go to `--dir /tmp/CaptureDirector-test-app`; never overwrite `/Applications` during development.

## Review focus

1. **Another app's window overlaps the target, or a notification arrives mid-take.** Expected: neither appears in `raw.mov`. Pinned by the privacy check in Task 9.
2. **The target is Capture Director itself, and the recorder is also a Capture Director process.** Expected: quitting the target never quits the recorder, and the user's own copy comes back afterwards. Pinned by `TargetPlanTests` in Task 5.
3. **The display is too small for the window plus margin.** Expected: the window shrinks to fit with its aspect kept, or the job fails plainly when it would be under 760x480 (the app's minimum). Pinned by `FrameMathTests` in Task 4.
4. **The user moves the mouse, presses Escape, or a step fails mid-take.** Expected: no stuck mouse button, window restored, target relaunched normally, `result.json` says `cancelled` or `error`, and Node reports it without running `processShot`. Pinned in Tasks 6 and 7.
5. **A hostile or sloppy shot list.** `background: "red;movie=x"`, `env` with non-string values or odd keys, `app: "../../bin/sh"`. Expected: rejected while loading, before anything launches. Pinned in Task 1.

---

### Task 1: App shots in the shot list

**Files:**
- Modify: `src/shots.js` (`loadShots`), `src/util.js`
- Test: `test/app-shots.test.js`

**Interfaces:**
- Produces: `hexColor(v: unknown, what: string): string` in `src/util.js` (returns the value, throws `"<what> must be a color like #4c1637"`).
- Produces: loaded app shots have `shot.kind = 'app'` (web shots get `'web'`), `shot.app: { bundleId?: string, path?: string }`, `shot.env: Record<string,string>`, `shot.window: { width, height }`, `shot.background: string`, `shot.countdown: number` (seconds, default 3), `shot.recordFps: number` (default 60).

- [ ] **Step 1: Write the failing tests** in `test/app-shots.test.js`, writing YAML to a temp dir and calling `loadShots`:
  - `an app shot loads with defaults`: `app: io.github.dhanson-wp.capture-director` gives `kind === 'app'`, `app.bundleId` set, `window` `{1440, 900}`, `background === '#4c1637'`, `countdown === 3`.
  - `an .app path is accepted`: `app: /Applications/TextEdit.app` gives `app.path`.
  - `url and app together are refused`: throws `/url or app, not both/`.
  - `web-only options are refused on app shots`: `scale: 2` throws `/scale only works on web shots/`.
  - `background must be a plain hex color`: `"red;movie=x"` and `"#4c16"` throw `/must be a color like #4c1637/`.
  - `env must be plain strings with plain names`: `{ CD_HOME: 5 }` and `{ "A B": "x" }` throw; `{ CD_HOME: "/tmp/x" }` loads (relative paths resolve from the YAML file).
  - `app must be a bundle ID or an .app path`: `"../../bin/sh"` throws `/bundle ID or a path to an .app/`.
  - `window size is bounded`: `{ width: 100, height: 900 }` throws (min 760x480, max 3000x2000).
  - `app steps only use app actions`: an `eval` step throws `/eval doesn't work in app shots/`. Allowed: `wait`, `click`, `hover`, `move`, `press`, `type`, `scroll`.

- [ ] **Step 2: Run** `node --test test/app-shots.test.js`. Expected: all fail.

- [ ] **Step 3: Implement.** In `loadShots`, branch on `s.app` before the existing `url` checks. Bundle ID regex `/^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/`; a path must be absolute (after `resolveFrom`) and end in `.app`. Env key regex `/^[A-Z_][A-Z0-9_]*$/`. Validate step kinds with the existing `normalizeStep` from `src/record.js`. Keep every web shot's behavior exactly as it is.

- [ ] **Step 4: Run** `npm test`. Expected: all pass, including the 44 existing tests.

- [ ] **Step 5: Commit** `feat: app shots in the shot list`.

### Task 2: processShot reads a recorded video

**Files:**
- Modify: `src/shots.js` (`processShot`)
- Test: `test/app-shots.test.js`

**Interfaces:**
- Consumes: `capture.json` with optional `source: "raw.mov"` (a plain file name in the shot folder).
- Produces: when `cap.source` is set, ffmpeg's first input is `-i <dir>/<source>` and the frame size comes from probing that file; otherwise behavior is unchanged.

- [ ] **Step 1: Write the failing test** `processShot reads a video source`: make a 3840x2160, 3-second `raw.mov` with `ffmpeg -f lavfi -i testsrc=size=3840x2160:rate=60`, write `capture.json` with `source: 'raw.mov'`, `viewport: {width:1920,height:1080}`, `duration: 3`, one `click` event at `(960,540)` with `zoom: 1.5`, and empty `moves` and `presses`. Call `processShot(null, shot, dir)` with `cursor.enabled = false`. Assert the output probes as 1920x1080 and about 3 seconds long.
- [ ] **Step 2: Add** `source must be a plain file name`: `source: '../x.mov'` throws before ffmpeg runs.
- [ ] **Step 3: Run.** Expected: fail.
- [ ] **Step 4: Implement** the branch. Check `source` with `/^[\w.-]+$/`. Skip the `fps,trim` concat workaround only where it doesn't apply.
- [ ] **Step 5: Run** `npm test`. Expected: pass.
- [ ] **Step 6: Commit** `feat: process a shot from a recorded video`.

### Task 3: The job and capture log in Swift

**Files:**
- Create: `mac/Sources/CaptureDirectorKit/RecordJob.swift`, `mac/Sources/CaptureDirectorKit/CaptureLog.swift`
- Test: `mac/Tests/CaptureDirectorKitTests/RecordJobTests.swift`, `CaptureLogTests.swift`

**Interfaces:**
- Produces: `public struct RecordJob: Codable, Sendable` with fields `version: Int` (must be 1), `id: String`, `app: AppRef` (`bundleId: String?`, `path: String?`), `env: [String: String]`, `window: Size`, `background: String`, `fps: Int`, `countdown: Double`, `settle: Int` (ms), `tail: Int` (ms), `cursorStart: [Double]?`, `steps: [Step]`, `out: String`. `static func load(from url: URL) throws -> RecordJob` validates the same rules as Task 1 (defense in depth).
- Produces: `public enum Step: Codable, Sendable` with cases `wait(ms)`, `click(Target, zoom: Double?, hold: Int?, duration: Int?)`, `hover(...)` (same fields), `move(to: MoveTo, duration: Int?)`, `press(key: String)`, `type(text: String)`, `scroll(by: Double, duration: Int?)`. Decoded from Node's `normalizeStep` output (`{ kind, ... }`).
- Produces: `public enum Target: Codable, Sendable { case id(String), roleLabel(role: String?, label: String) }`. A bare string target means `roleLabel(nil, label)`.
- Produces: `public struct CaptureLog` with `mutating func click/hover/move/press(...)` taking times in seconds since capture start and points in 1920x1080 space, and `func json(duration: Double, source: String) -> Data`, which writes the keys `processShot` reads: `viewport`, `duration`, `source`, `events` (`type, t, x, y, zoom?, focus?`), `moves` (`t0, t1, x0, y0, x1, y1`), `presses` (`t0, t1`, with `t1 = t0 + 0.06` after release), `cursorStart`, `kind: "app"`.
- Produces: `public func ease(_ p: Double) -> Double`, the same easeInOutCubic as `src/util.js`.

- [ ] **Step 1: Write the failing tests.** Decode a job JSON fixture with every step kind; reject `version: 2`, `background: "red"`, and an empty `steps`. `ease(0.25) == 0.0625`, `ease(0.75) == 0.9375`, and inputs are clamped. A log with one click encodes `events[0].type == "click"` and a `presses` entry 0.06 s past release.
- [ ] **Step 2: Run** `mac/tools/test.sh`. Expected: fail to compile.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `mac/tools/test.sh`. Expected: all pass, including the 72 existing tests.
- [ ] **Step 5: Commit** `feat(mac): record job and capture log`.

### Task 4: Frame math

**Files:**
- Create: `mac/Sources/CaptureDirectorKit/FrameMath.swift`
- Test: `mac/Tests/CaptureDirectorKitTests/FrameMathTests.swift`

**Interfaces:**
- Produces: `public struct FrameLayout: Equatable { windowSize: CGSize; windowOrigin: CGPoint; sourceRect: CGRect }`, all in global screen points (top-left origin).
- Produces: `public func layout(requested: CGSize, visible: CGRect) throws -> FrameLayout`. The source rect is 16:9 with width `window.width / 0.8`, centered in `visible`. If it doesn't fit, scale the window down keeping its aspect, and throw `FrameError.displayTooSmall` below 760x480.
- Produces: `public func toFrame(_ p: CGPoint, in layout: FrameLayout) -> CGPoint` maps screen points to 1920x1080 space, and `toFrame(_ r: CGRect, in:) -> CGRect` maps focus boxes.

- [ ] **Step 1: Write the failing tests.** On a 1728x1079-point visible area (Derek's 3456x2234 display at 2x, minus the menu bar), 1440x900 doesn't fit as 1800x1012.5, so the window shrinks to 1382.4x864 (source rect 1728x972, ratio 1.6 kept). On a 2560x1415 area, 1440x900 is kept and the source rect is 1800x1012.5, centered. The window's center maps to (960, 540). On a 900x600 area it throws `displayTooSmall`.
- [ ] **Step 2: Run** and confirm it fails. **Step 3: Implement.** **Step 4: Run** and confirm it passes.
- [ ] **Step 5: Commit** `feat(mac): frame layout for app recordings`.

### Task 5: Choosing targets and selector matching

**Files:**
- Create: `mac/Sources/CaptureDirectorKit/TargetPlan.swift`, `mac/Sources/CaptureDirectorKit/ElementMatch.swift`
- Test: `mac/Tests/CaptureDirectorKitTests/TargetPlanTests.swift`, `ElementMatchTests.swift`

**Interfaces:**
- Produces: `public struct RunningApp { pid: Int32; bundleId: String? }` and `public func instancesToQuit(running: [RunningApp], bundleId: String, selfPid: Int32) -> [Int32]`, which never includes `selfPid`. Also `public func shouldRelaunchAfter(running: [RunningApp], bundleId: String, selfPid: Int32) -> Bool`.
- Produces: `public protocol ElementNode { var role: String? { get }; var identifier: String? { get }; var title: String? { get }; var label: String? { get }; var value: String? { get }; var children: [Self] { get } }` and `public func firstMatch<N: ElementNode>(_ target: Target, in root: N) -> N?`. This is a breadth-first search. `id` matches `identifier` exactly. `roleLabel` matches `role` case-insensitively with or without the `AX` prefix (`row` matches `AXRow`) when given, and `label` exactly against `title`, `label` (AX description), or `value`.

- [ ] **Step 1: Write the failing tests.** `instancesToQuit` with the recorder (pid 10) and the target (pid 20) sharing a bundle ID returns `[20]`. `shouldRelaunchAfter` is false when only the recorder runs. Matching uses a hand-built tree: `{ id: "inspector" }`, `{ role: "row", label: "Starred" }`, a bare `"Starred"`, and a miss returning nil. With two matches, the shallower one wins.
- [ ] **Step 2: Run** and confirm it fails. **Step 3: Implement.** **Step 4: Run** and confirm it passes.
- [ ] **Step 5: Commit** `feat(mac): target selection and element matching`.

### Task 6: Record mode in the app

**Files:**
- Create: `mac/Sources/CaptureDirector/Recorder/RecordMode.swift` (entry and orchestration), `Recorder/TargetApp.swift` (quit, relaunch with env, size, restore), `Recorder/AXDriver.swift` (`ElementNode` over `AXUIElement`, eased `CGEvent` mouse moves, clicks, keys, typing, scroll), `Recorder/ScreenRecorder.swift` (`SCStream` to `AVAssetWriter`), `Recorder/Permissions.swift`
- Modify: `mac/Sources/CaptureDirector/App.swift` (route `--record <job.json>` the way `--selftest` is routed, before any window opens)

**Interfaces:**
- Consumes: `RecordJob`, `Step`, `Target`, `CaptureLog`, `ease`, `layout`, `toFrame`, `instancesToQuit`, `shouldRelaunchAfter`, `firstMatch`.
- Produces: `CaptureDirector --record /abs/job.json` writes into `job.out`: `raw.mov` (3840x2160, H.264 at least 60 Mbps or HEVC, `job.fps`), `capture.json`, `recorder.log` (progress lines, `[capture-director] <id>: ...`), and always `result.json`: `{ "status": "ok" | "cancelled" | "error", "message"?: String }`. The exit code is 0 only for `ok`. It never shows a window or Dock icon (`.accessory` activation policy).

Behavior that matters:
- Check permissions first with `CGPreflightScreenCaptureAccess()` and `AXIsProcessTrusted()`. When missing, request once, then fail with exactly one of these: `Capture Director needs Screen Recording permission. Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording, then record again.` or `Capture Director needs Accessibility permission. Turn it on in System Settings > Privacy & Security > Accessibility, then record again.`
- If no app matches the bundle ID or path, fail with `Can't find the app <bundleId or path>.`
- Quit `instancesToQuit` politely, then force-quit after 5 s. Launch with `NSWorkspace.OpenConfiguration` (`environment = job.env`, `createsNewApplicationInstance = true`). Wait up to 15 s for a main window, then set its position and size through AX to `layout(...)`.
- Capture filter: `SCContentFilter(display: main, including: [target SCRunningApplication], exceptingWindows: [])`. Set `sourceRect = layout.sourceRect`, `width/height = 3840/2160`, `showsCursor = false`, and `backgroundColor` from `job.background`. Re-check after every step that the target is still frontmost and owns the key window; if not, fail with `Another window took focus during the take.`
- Countdown: `job.countdown` seconds of `starting in N` lines in the log. Then a global `NSEvent` monitor: Escape cancels, and any mouse movement the recorder didn't make cancels with `You moved the mouse, so the take stopped.`
- Steps: find targets with `firstMatch`, polling every 100 ms for up to 5 s. A miss fails with `<id>: nothing matches <target> in <app name>.` Move the real mouse with eased `CGEvent`s at 120 Hz along the same curve `CaptureLog` records. Clicks press and release with an 80 ms hold. Each hover or click event's `focus` is the element's frame mapped by `toFrame`.
- On any exit path (ok, cancel, error, or thrown), release held buttons and modifiers, stop the stream, quit the instance we launched, put the target's original window frame back if it was running before, and relaunch it normally if `shouldRelaunchAfter` said so. Partial `raw.mov` files are deleted when the take wasn't `ok`.

- [ ] **Step 1: Build** with `node bin/capture-director.js install-app --dir /tmp/CaptureDirector-test-app`. Expected: no errors or warnings.
- [ ] **Step 2: Smoke-test against TextEdit by hand.** Write `/tmp/cd-job.json` with `app.bundleId: com.apple.TextEdit`, a click on `{ role: "textarea" }` (or the role AX reports), a `type: "hello"`, and a 1 s wait. Run `open -n -W -a "/tmp/CaptureDirector-test-app/Capture Director.app" --args --record /tmp/cd-job.json`. Expected: on first run, `result.json` reports the permission message. After granting, `status: ok`, `raw.mov` is 3840x2160, and `capture.json` has one click event near the text area's center.
- [ ] **Step 3: Check cancelling.** Run again and press Escape during the countdown. Expected: `status: cancelled`, no `raw.mov`, and TextEdit back as it was.
- [ ] **Step 4: Run** `mac/tools/test.sh` and `mac/tools/selftest.sh`. Expected: everything still passes.
- [ ] **Step 5: Commit** `feat(mac): record mode drives and films a Mac app`.

### Task 7: Node runs the recorder

**Files:**
- Create: `src/native.js`
- Modify: `src/shots.js` (`record`)
- Test: `test/native.test.js`

**Interfaces:**
- Consumes: Task 1's shot fields and Task 6's file contract.
- Produces: `findRecorderApp({ env = process.env } = {}): Promise<string>`. It checks `CD_APP` (a path to `Capture Director.app`), then `/Applications`, then `~/Applications`, and fails with `Recording a Mac app needs the Capture Director app. Install it with: capture-director install-app`.
- Produces: `buildJob(shot, dir): object`, the JSON from Task 3, with `steps` from `normalizeStep` and `out = dir`.
- Produces: `recordAppShot(shot, dir, { run = spawnOpen } = {}): Promise<{ status, message? }>`. It writes `job.json` and runs `open -n -W -a <app> --args --record <job.json>`, forwarding `recorder.log` lines to stderr as they appear (poll every 250 ms). Then it reads `result.json`, and fails with `The recorder stopped without saying why.` if that file is missing.
- `record()`: for `shot.kind === 'app'`, call `recordAppShot`. On `ok`, run `processShot` and remember the clip in the library as web shots do. On `cancelled`, push `{ id, cancelled: true }` and skip processing. On `error`, throw the message. Off macOS, throw before writing anything.

- [ ] **Step 1: Write the failing tests** with an injected `run` that writes files instead of launching anything:
  - `buildJob carries the shot`: background, env, window, steps, and `version: 1`.
  - `a cancelled take is reported, not processed`: the fake writes `{status:"cancelled"}`; `record` resolves with `cancelled: true` and no `.mp4` exists.
  - `a recorder error becomes the command's error`.
  - `a missing result.json fails plainly`.
  - `findRecorderApp prefers CD_APP`, and a bad `CD_APP` fails with the install message.
- [ ] **Step 2: Run** and confirm it fails. **Step 3: Implement.** **Step 4: Run** `npm test` and confirm it passes.
- [ ] **Step 5: Commit** `feat: record Mac app shots from the CLI`.

### Task 8: Accessibility identifiers in Capture Director

**Files:**
- Modify: `mac/Sources/CaptureDirector/Sidebar.swift`, `GridView.swift`, `PlayerSheet.swift`, `Inspector.swift`

**Interfaces:**
- Produces these identifiers for the tour: sidebar rows `sidebar.all`, `sidebar.starred`, `sidebar.folder.<path>`; grid cells `grid.item.<index>` in display order; player `player`, `player.close`; inspector `inspector`, `inspector.title`, `inspector.notes`, `inspector.copy.web`, `inspector.copy.small`.

- [ ] **Step 1: Add** `.accessibilityIdentifier(...)` without changing labels, so VoiceOver reads the same as before.
- [ ] **Step 2: Build, then run the self-test, `tools/snap.sh`, `tools/grid-lint.sh`, and `check-layout.swift`.** Expected: PASS everywhere, and the snapshots are unchanged.
- [ ] **Step 3: Commit** `feat(mac): accessibility identifiers for scripted tours`.

### Task 9: The tour example and the privacy check

**Files:**
- Create: `examples/mac-app-tour/shots.yaml`, `examples/mac-app-tour/timeline.yaml`, `examples/mac-app-tour/make-demo-library.sh`

**Interfaces:**
- Consumes: everything above.
- Produces: `make-demo-library.sh <home>`, which refuses anything outside `/tmp`, `/private/tmp`, or `$TMPDIR` with the same guard as `mac/tools/fixture.sh`. It records 6 to 8 short demo captures of public sites with capture director itself (reusing `examples/blog-tour` plus a few more pages of derekhanson.blog), files them into folders `Blog` and `Launch`, stars two, and gives them readable titles.
- `shots.yaml`: one shot `tour`, `app: io.github.dhanson-wp.capture-director`, `env: { CD_HOME: /tmp/capture-director-tour-home }`, `background: "#4c1637"`. Steps: wait, then the grid, `sidebar.folder.Blog`, `sidebar.starred`, `sidebar.all`, double-click or `press: cmd+o` on `grid.item.0` to play for 3 s, `player.close`, then click `grid.item.0` and hover `inspector` at `zoom: 1.7` with `hold: 2400`.

- [ ] **Step 1: Write the files, build the demo library, and run** `node bin/capture-director.js record examples/mac-app-tour/shots.yaml`. Expected: `out/tour/tour.mp4` at 1920x1080.
- [ ] **Step 2: Look at it.** Run `capture-director sheet out/tour/tour.mp4 --every 1` and read the PNG. Expected: mulberry background, the app with its shadow, the player sheet in frame, the inspector zoom sharp, and one drawn cursor.
- [ ] **Step 3: Privacy check (Review focus 1).** Open a TextEdit window overlapping where the app will sit, and post a notification during the take (`osascript -e 'display notification "privacy check"'`). Record again. Expected: neither appears in any frame of the sheet or in `stills` at the notification's second.
- [ ] **Step 4: Check that Derek's library is untouched.** `~/.capture-director/library.json` has the same contents before and after, apart from the new tour clip if `record` remembers it.
- [ ] **Step 5: Commit** `docs: Mac app tour example` (commit the YAML and script only; recordings stay ignored).

### Task 10: Docs and release prep

**Files:**
- Modify: `README.md`, `package.json` (`"version": "0.2.0"`), `mac/Info.plist.in` (`CFBundleShortVersionString` `0.2`), `mac/CLAUDE.md` (record mode and `Recorder/`), `skill/` (the capture-director skill's docs on app shots)

- [ ] **Step 1: Write a README section, "Recording a Mac app".** Cover the YAML shape, targets (`id`, `role` plus `label`, a bare label), the two permissions and why they go to Capture Director, that the take drives your real mouse, Escape to cancel, and that ad-hoc builds may ask for permission again after a rebuild.
- [ ] **Step 2: Update the skill docs** so agents know `app:` shots exist and need the app installed.
- [ ] **Step 3: Run** `npm test`, `mac/tools/test.sh`, and `mac/tools/selftest.sh`. Expected: all pass.
- [ ] **Step 4: Commit** `docs: recording Mac apps, 0.2.0`. Then push the branch and open a PR. Create the GitHub release `v0.2.0` only after Derek approves it, after the merge.
