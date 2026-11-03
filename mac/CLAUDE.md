# CaptureDirector

A native macOS app in SwiftUI. It drives the capture-director CLI. Command Line Tools only; no Xcode. Its only record is the CLI's `library.json`.

## Layout

- `Sources/CaptureDirector/` the app. `App.swift` has the window and menus.
- `Sources/CaptureDirectorKit/` rules and data logic with no SwiftUI. Tests in `Tests/CaptureDirectorKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `$CD_APP_DIR/Capture Director.app` (default `/Applications`, or `~/Applications` when that isn't writable); `capture-director install-app` runs it.
- `Icon/AppIcon.iconset` the app icon: ten PNG sizes rendered from `ui/icon.svg`. `tools/make_icon.sh` turns it into `Resources/AppIcon.icns` with `iconutil`. To redraw the PNGs (transparent corners, artwork at 824 of 1024 points), run `swift mac/tools/render_icon.swift` from the repo root.
- `docs/` the brief, the screen index, and the user stories, when they exist.

## Build and check

- Build and install: `node bin/capture-director.js install-app` from the repo root (builds and writes the app's `config.json`, which says where node and the CLI are; without it every change fails). For scratch builds and tests, always add `--dir /tmp/CaptureDirector-test-app` so the installed app is never overwritten. `build.sh` alone keeps the installed copy's config.json and warns when there's none; `--open` restarts the app with the new build. The build shows warnings; fix them.
- Unit tests: `tools/test.sh` (adds the Command Line Tools flags Swift Testing needs).
- Self-test (the app's real functions on a scratch library): `tools/selftest.sh` (runs the app in `/tmp/CaptureDirector-test-app`; set `CD_APP_DIR` to use another). Exit 0 when every check passes. Add a check for every story with logic in `SelfTest.swift`.
- After every UI change, take snapshots with sample data and look at them: `tools/snap.sh` (fills a scratch home with `tools/fixture.sh`; set `CD_APP_DIR` to snapshot an app installed elsewhere; it defaults to `/tmp/CaptureDirector-test-app`).
  It writes `/tmp/CaptureDirector-shots/<page>-light.png` and `-dark.png` for every page in `Snapshot.pages`, then quits. `APP_SNAPSHOT_PAGES=all-grid,inspector tools/snap.sh` limits the pages (all-grid, all-list, folder, starred, empty, inspector, inspector-moved, and the rest in `Snapshot.swift`).
  For a panel, sheet, or popover, add a page to `Snapshot.pages`.
- Snapshots and the self-test run with `CD_HOME` pointing at a folder in /tmp. The app only reads `library.json`; never point tests at `~/.capture-director`.
- Then check the grid: `tools/grid-lint.sh` and `swift tools/check-layout.swift /tmp/CaptureDirector-shots/*-layout.json`. Both print PASS.
- A change is done when the build has no errors, the grid checks pass, and you looked at the light and dark snapshots.

## Design rules

- Use Apple's controls and system styles, in the system accent color. There's no custom `.tint`: the app is built with Command Line Tools, which can't compile an asset-catalog accent, so AppKit draws the sidebar in the system accent and a custom tint would mix two accents in one window. A committed Xcode-built `Assets.car` with `NSAccentColorName` could bring mulberry back later. Light and dark mode follow the Mac.
- Brand colors are fixed tokens in `UI/Theme.swift` for brand things only: `Palette.star` (mulberry), `Palette.final` with `Palette.onFinal` (citron, the Final badge), and `Palette.highlight` (pool, quiet highlights). `Palette.accent` is the system accent, for selection rings and drop targets. Never hard-code colors, radii, or durations in views.
- Spacing comes from `Space` in `UI/Grid.swift`, on a 4 pt grid. Mark custom pages and cards with `.gridArea` and `.gridProbe`.
- Windows open calm: `.noInitialFocus()` on every window and sheet (no focus ring or selected text on open), `.fitsContent()` on sheets (no scroll bar with nothing to scroll). System scroll bars. Both in `UI/WindowBehavior.swift`.
- There's no Settings window; nothing needs one yet. If a setting comes along, add a `Settings` scene with one grouped Form per tab.
- Window chrome (title bar, toolbar, sidebar, menus, sheets) stays system. Buttons use system styles, like `.borderedProminent`.
- Colors: `.primary`, `.secondary`, `.tint` (the system accent), and system colors. Never fixed grays or white for text.
- Every action has a menu bar item and a keyboard shortcut.
- `Label` for icon and text pairs. SF Symbols for icons.
- `ContentUnavailableView` for empty states.
- Liquid Glass belongs to floating controls only, never to content.

## Skills

The bama plugin has a skill for each step: `mac-design` (design rules),
`design-system` (accent and tokens), `layout-grid`, `ux-design`,
`swift-swiftui`, `os-integrations`, `performance`, `build-and-verify`,
`test-mac-app`, `app-icon`, `user-stories`, and `improve-loop`. Use them.

## Git

- Commit after each working change, with a message that says what the user can now do.
