# Capture director for Mac: design

Status: draft for Derek's review, 2026-10-27, revised 2026-11-02 for a native SwiftUI app

## Why this exists

Capture director makes clips, and the library (`capture-director library`, merged in #2) already keeps track of them. But the library is a web page you open from the terminal. People who install capture-director should be able to click an icon in the Dock and get their captures in a real Mac window.

Derek's three jobs for the app, in his words: find a capture, organize captures "in folders like for a project," and share or upload them. He clarified that sharing means "an easy way to drag and drop the file from the app file picker into your platform. It's basically a way to display where they live on your device but within the app." The platforms he named are the WordPress media library, YouTube, X, LinkedIn, Spacefast, and GitHub.

He'll mostly drive capture-director through a chat in the Claude or Codex app. The app sits alongside that chat; it doesn't replace it.

## Goals

1. **A Mac app.** Capture director opens from the Dock, Launchpad, or Spotlight in its own window, with a proper icon and menu bar. No terminal and no browser tab.
2. **Find.** Search, recent captures first, grid and list views, and hover-scrubbing so you can tell takes apart without opening them.
3. **Organize.** Project folders you can make, rename, nest, and drag captures between. Select several at once to move, star, or remove them.
4. **Drag out real files.** Dragging a capture out of the window hands macOS the actual video file, exactly like dragging from Finder. Dropping it into an upload page in any browser (WordPress media library, YouTube, X, LinkedIn, GitHub) or into any app (Slack, Messages, Finder) just works.
5. **Show where each file lives.** Every capture shows its real location on disk, with Show in Finder and copy-path one click away.
6. **Smaller copies for the web.** Derek added this on 2026-11-03: make a web-optimized copy of a capture to cut its file size before dragging it into an upload page with a size limit. The original is never touched.
7. **Hand off to an agent.** "Copy for agent" puts a ready-to-paste block on the clipboard with the path, length, size, source site, and where the click data lives.

## Non-goals (this project)

- **Uploading from the app.** No built-in uploaders, no sign-ins, and no "shared at" link tracking. Derek was explicit: drag and drop is the sharing story.
- **The storyboard.** Reviewing and editing shots before recording is the next project. See "What comes next."
- **Recording from the app.** Recording stays with the CLI and agents. The app has no "New capture" button in this version.
- **Capturing native Mac apps.** It's parked as its own future project. Today everything records in headless Chrome.
- **Windows and Linux apps.** The browser library (`capture-director library`) keeps working there, as it does today.
- **A cloud space for capture drops.** Derek framed this as a possible "recipe we offer down the road," not something to build now.

## Anti-goals (failure even if it works)

- **The app moves, renames, or deletes video files.** Folders are library-only. "Remove from library" forgets an entry and never touches the file. This is the library's existing promise and the app keeps it.
- **Anything leaves the Mac without the user dragging it out.** No telemetry and no network calls beyond loopback.
- **Weakening the library server's security.** The browser library keeps its token, host check, origin check, CSP, and loopback binding from #1 and #2. The Mac app opens no ports at all.
- **Feeling heavy.** No Electron, no bundled Chromium, and no background process when the window is closed.

## How it's built (decided)

**A native SwiftUI app, built with BAMA's template and rules.** Derek chose native on 2026-11-02, after reviewing [BAMA](https://github.com/daveebbelaar/bama) (Build Any Mac App by Dave Ebbelaar, installed as the `bama@bama` Claude Code plugin). It replaces the earlier plan of a Swift shell around the web library.

Why native won:

- **Drag-out is the main job, and SwiftUI does it directly.** A drag test on 2026-10-27 showed a browser page can't hand a real file to an upload page:

  | Drag source in a Chrome app window | Desktop | Browser upload box | WordPress media library |
  |---|---|---|---|
  | `DownloadURL` (Chrome's file trick) | real file | nothing | nothing |
  | Plain link | `.webloc` shortcut | link only | nothing |
  | `file://` link | broken shortcut | link only | nothing |

  In SwiftUI, `.draggable` with the file's URL puts the actual file on the pasteboard, the same as dragging from Finder. No bridge between a web page and Swift is needed.
- **Share, copy, and preview come free.** `ShareLink` gives the macOS share sheet. Copying a file URL to the pasteboard lets ⌘V paste the video into Slack, Mail, or Finder. Quick Look previews with Space.
- **No server, no ports.** The app reads files on disk. Nothing listens on the network, so the library server's token and origin checks don't apply to it at all.
- **BAMA already solved the parts Derek hasn't built before:** project layout, a build script that needs no Xcode, ad hoc signing, install to `~/Applications`, light and dark snapshots for checking every screen, and Mac design rules.

**library.json stays the single shared source of truth.** The CLI, agents, the browser library, and the Mac app all use `~/.capture-director/library.json` (or `$CD_HOME`). The app doesn't use SwiftData, even though BAMA's template does; the template's model layer gets swapped for a small reader of `library.json`. *(My call.)*

**Reading and writing (my call):**

- **The app reads `library.json` directly** and watches it for changes, so clips an agent adds while the window is open just appear.
- **All writes go through the Node CLI**, using new `capture-director library` subcommands that print JSON (see "Data changes"). That keeps one implementation of the library's rules (folder renames, the renames map, relocate checks, id collisions) instead of two that drift apart. A write costs one short `node` run, which is fine for organizing.
- **Thumbnails and hover scrub use AVFoundation** (`AVAssetImageGenerator`, `AVPlayer`), so the app needs no ffmpeg for browsing. The CLI's thumbnail cache in `~/.capture-director/thumbs` can be reused when it's there.

**Install.** A new `capture-director install-app [--dir /Applications]` command runs the app's build script (`swift build` plus bundling, from BAMA's template), signs it ad hoc (`codesign -s -`), and installs `Capture Director.app` in `/Applications`, or in `~/Applications` when `/Applications` isn't writable (it takes an admin account). *(Derek changed the default from `~/Applications` on 2026-11-03.)* Command Line Tools are enough; full Xcode isn't needed. Because of that, the icon is made with `iconutil` from a PNG set instead of BAMA's Icon Composer and `actool` route, which needs Xcode. *(My call.)* An app launched from the Dock doesn't get your shell's `PATH`, so `install-app` records the absolute paths to `node` and `bin/capture-director.js`, plus `PATH` (for Homebrew's `ffprobe`, used by relocate) and `CD_HOME` if it's set. If Command Line Tools are missing, it says to run `xcode-select --install`. If the recorded paths stop working (Node upgraded, repo moved), the app shows a plain message telling you to run `install-app` again. Because the app is built on the user's own Mac, Gatekeeper doesn't quarantine it.

**Targets.** macOS 26 or later and Swift 6.2 or later, matching BAMA. Derek's Mac has macOS 27 and Swift 6.3.2 from Command Line Tools.

**Where things live:**

- `mac/`: the Swift package from BAMA's `new-mac-app` template, its build script, and the icon PNGs (made once from `ui/icon.svg` and committed)
- `src/install-app.js`: the build and install command
- `src/library.js` and `bin/capture-director.js`: the new library subcommands
- `ui/`: the browser library, unchanged except for showing nested folder paths sensibly

**BAMA skills to lean on while building:** `new-mac-app` for the scaffold, `mac-design` and `design-system` for the look, `ux-design` for names and where each action opens, `build-and-verify` and `test-mac-app` for checking every screen in light and dark, and `improve-loop` to work through the stories one commit at a time.

## The app, screen by screen

Mockup 1 (in `.superpowers/brainstorm/`, not committed) shows the layout Derek reviewed. Ignore its "New capture" button, the "Upload with agent" idea, and the "used in" chips; those were cut.

**Window and menus.** A standard Mac window with a unified toolbar. The menus cover the usual keys: ⌘F to search, ⌘1 and ⌘2 for grid and list, ⌘⌫ to remove from library, and ⌘⇧N for a new folder. Closing the last window quits the app. Opening it again while it's running focuses the existing window.

**Sidebar.**

- **Library section:** All captures, Recent (the last 7 days), Starred, Final videos, and Clips, each with a count.
- **Projects section:** a folder tree with a + button for new folders. Folders can be renamed in place, nested, and deleted only when empty. Captures with no folder show in Unsorted.
- **Drop targets:** dragging captures onto a folder moves them there in the library.
- **Footer:** "Local only. Your videos stay where they were rendered."

**Toolbar.** The current folder name and count, search, a grid or list toggle, and sort (Newest, Oldest, Name, Longest).

**Grid.** 16:9 thumbnails with a Final or Clip badge, the length, the title, and the date with the source site. Hovering scrubs through the clip: mouse position maps to time, using frames from AVFoundation loaded on hover. Click selects. Double-click opens the player, and Space opens Quick Look. ⌘-click and ⇧-click select more than one.

**List.** Rows showing title, project, kind, length, date, size, and location. It's sortable by column and is the faster view for big libraries.

**Inspector (right panel).** It shows the selected capture:

- A player
- Title (editable), kind, length, resolution, and file size
- Star
- **Primary actions:** Share (`ShareLink`), Copy video, Show in Finder, and a visible drag handle with the hint "Drag into any upload page." The thumbnail itself drags too, in the grid, the list, and the inspector.
- **Web copy:** "Make web copy" (up to 1080p) and "Make small copy" (up to 720p). While it works it says so; when it's done it shows the new size next to the original's, with its own drag handle, Copy, and Share
- **Copy for agent**
- Project picker, notes, source site, and the "Record again" command
- **Location:** the full path, with a copy button

With several captures selected, it shows the count and the bulk actions: move to folder, star, remove from library, Copy video, and drag all.

**Moved files.** A thumbnail whose file is gone shows "File moved," with **Locate…** (a native open panel) and **Remove from library**.

**Empty state.** The empty state the library has today (the record, render, and `library add` commands) stays.

**Look.** A native Mac look, following BAMA's `mac-design` rules: the standard sidebar, toolbar, and inspector, system type, SF Symbols, and proper light and dark modes. Selection and buttons use the Mac's own accent color. The app is built with Command Line Tools, which can't compile an asset-catalog accent, and without one AppKit draws the sidebar in the system accent no matter what SwiftUI's tint says, so a custom tint would mix two accents in one window; a committed Xcode-built `Assets.car` with `NSAccentColorName` could bring mulberry back later. The brand stays in fixed colors where it marks brand things: mulberry (#4c1637, #b04a80 in dark mode) for the star, citron (#e5d935) for the Final badge with dark text, pool (#d4e9ed) for quiet highlights, and the app icon. Manrope and Bricolage Grotesque stay with the website and the browser library; the app uses the system font. The shadcn-style mockups still show the layout and the actions, just not the final styling. *(My call.)*

## Data changes

`library.json` today holds `entries`, each with a `project` string. The changes are:

- **Nested folders as paths.** `project` stays a string, and `/` separates levels: `derekhanson.blog/Post formats`. Agents and the CLI keep setting a project by name, and nothing existing breaks. A top-level `folders` array stores folder paths, so empty folders persist. Renaming or moving a folder rewrites the prefix on every entry under it.
- **Existing libraries.** Every existing `project` value shows up as a top-level folder on first launch, just as it shows as a project today. Unsorted holds entries whose project is empty, missing, or the literal `Unsorted`. Old `library.json` files load without a rewrite; `folders` gets filled in on the first save. *(My call.)*
- **Renames stick.** Renaming or moving a folder also records `renames: { "old path": "new path" }`. `add()` applies that map to a new entry's default project, so the next `process` or `render` from the same shot list lands in the renamed folder instead of bringing back the old name. *(My call.)*
- **`url`** on each clip: the page it was recorded from. `processShot` (`src/shots.js:147`) reads it from the shot's `capture.json` when it adds the clip to the library. Finished videos from `render` can mix several pages, so they get no `url`. It powers the "source site" line and search. Entries without it simply don't show a site. *(My call.)*
- **`size`** in bytes, read on `add`.

**New CLI subcommands** that the app calls and agents can use too. Each prints JSON and exits non-zero with a plain message on failure:

- `capture-director library folder add|rename|move|remove <path> [<new path>]` creates, renames, moves, or deletes a folder (delete only when empty).
- `capture-director library set <id>... [--project <path>] [--star|--unstar] [--title <text>] [--notes <text>]` edits one or several entries.
- `capture-director library forget <id>...` removes entries from the library and never touches the files.
- `capture-director library relocate <id> <new path>` accepts only `.mp4`, `.mov`, and `.m4v` files that `ffprobe` can read. The entry keeps its id. Because ids are hashed from the original path, `add()` must check for an id that's already taken by a different file and give the new entry a fresh random id instead. *(My call.)*

- `capture-director library export <id> [--preset web|small]` makes a smaller H.264 copy in `<CD_HOME>/exports/<id>-<preset>.mp4` and prints `{ id, preset, file, size, reused }`. It reuses the copy while it's newer than the original. Exports aren't library entries; `forget` and `relocate` clear an entry's exports. *(Derek chose the hidden cache over writing next to the original, 2026-11-03.)*

The browser library's server gets no new endpoints in this project.

The app watches `library.json` and reloads when it changes. Writes from the CLI and the app aren't locked against each other; that's true of the CLI and browser library today too, and `save()` already writes atomically. If two writes ever collide in practice, a lock file is the follow-up.

## Testing

- **Unit tests** in `test/library.test.js` for folder paths, renaming a folder with entries under it, the new subcommands, the relocate checks, and that old `library.json` files load unchanged.
- **Swift tests** with Swift Testing for reading `library.json` (including old files and entries with missing fields) and building the folder tree, following BAMA's `test-mac-app`.
- **The first build milestone is the drag proof.** Before the rest of the UI is built, a bare app made by `install-app` with Command Line Tools only must drag a real library clip into the WordPress media library (Media → Add New on derekhanson.blog), YouTube's upload dialog, a GitHub comment box, Slack, and Finder. Derek runs this test himself, since it needs his signed-in accounts. If any of these fails, stop and report back before going further.
- **Snapshots** of every screen in light and dark, using BAMA's snapshot mode, checked before each commit.
- **A manual checklist** in the PR: install from a clean clone, launch from Spotlight, relaunch focuses the existing window, an agent's new clip appears without a reload, and the moved-file Locate flow works.

## Left to the builder

- How the Swift code is split up, within BAMA's template
- How the file watcher debounces reloads
- The exact menu layout and toolbar spacing
- The hover-scrub implementation details
- Whether the README's install section gets a short "Mac app" subsection or its own heading

## What comes next (separate projects)

1. **Storyboard (next).** You talk in the Claude or Codex chat while the app shows the storyboard alongside it. Shot cards come with scout pictures, a length bar against a target length, and a choice of captioned cut, clean cut (`--no-captions`, #7), or both. Derek edits captions, order, zoom point, and length directly, and leaves comments on shots for anything else. The agent handles comments when asked. Stages: draft, then recorded (check zooms), then rendered. BAMA's `agent-cli` skill (a command line and MCP server for the app) is the likely way for the chat agent and the storyboard window to talk.

   Derek's biggest worry is a zoom landing on the wrong spot after recording. The engine already supports the fix: zoom is planned after recording from saved frames and logged events (`src/shots.js:98`), so a misplaced zoom can be dragged and the shot rebuilt without recording again. The agent should flag shots where the planned and actual zoom drift apart. Mockup 2 shows the layout.

2. **Native Mac app capture.** Parked.

3. **A drops space.** A cloud home for capture drops with shared links, possibly a Spacefast recipe. It's being explored in the "Self-hosted Capture Director workflow" session as a Space template: opt-in, per clip, holding copies of published clips plus their title, notes, and folder path. Agents would publish first, through the Spacefast MCP, with a Mac app action later. This version only needs to keep entry ids stable and folders as paths, which it already does.
