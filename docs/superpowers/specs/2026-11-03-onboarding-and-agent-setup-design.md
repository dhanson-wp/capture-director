# Onboarding and agent setup: design

Status: approved by Derek, 2026-11-03

## Why this exists

Capture director works well on Derek's Mac because he built it there. Someone who finds it on GitHub hits a series of quiet gaps: the skill only has setup steps for two agents, nothing checks that Chrome and ffmpeg are ready, the Mac app opens to an empty window that assumes they know Terminal, and an agent can make a video that never shows up in the app because it was written to a temp folder or the library add failed without anyone noticing.

The way the pieces fit together doesn't need to change. The agent runs the CLI, the CLI writes `library.json`, and the app watches that file. There are no API keys, no accounts, and no connector protocol, and Derek wants to keep it that way. This project fills the gaps around that design so a new person gets from "installed" to "first video in the app" without help.

## Goals

1. **One check for everything.** `capture-director doctor` checks Node, Chrome, ffmpeg with libx264, the library home, the skill install, and the Mac app, and says how to fix each problem in one plain sentence.
2. **Every agent can be set up.** Claude Code and Codex each get a one-command skill install. Any other agent (Cursor, Gemini CLI, Copilot, and the rest) gets instructions it can paste in. The skill finds the CLI without guessing where the repo is.
3. **The app shows people how to connect their AI.** A "Set up your AI" window with a tab per agent, a status check for each, and a copy button for the one thing to run or paste. It also offers a starter prompt to copy.
4. **No lost videos.** Videos made by an agent land somewhere the person can find. The CLI's JSON says whether a capture made it into the library, and the skill tells the agent to report that.
5. **The app never opens to a dead end.** The empty state leads with "ask your AI," gives commands that actually run on this Mac, and shows what the tool makes.
6. **The app survives normal Mac changes.** Upgrading Node with nvm, asdf, Volta, fnm, or Homebrew doesn't break it.
7. **New captures are easy to spot.** A capture that arrives while the app is in the background is marked as new.

## Non-goals

- **API keys, accounts, or a hosted service.** Nothing here signs in to anything.
- **Recording from the app.** Recording stays with the CLI and agents. The native recorder spec (`2026-11-03-mac-app-recorder-design.md`) is separate.
- **An MCP server.** Chat-only apps (the Claude app's chat tab, ChatGPT) can't run the CLI. A local stdio MCP server would fix that, but it's its own project. See "What comes later."
- **Cloud and remote agents.** Codex cloud, Claude Code on the web, and other remote sandboxes record on someone else's machine. The skill tells the agent to say so; it doesn't try to sync files back.
- **A notarized download or a Claude Code plugin package.** Both are later projects. Installing stays clone plus `npm install`.
- **Changing where `record` writes by default.** `out` stays relative to the shot list, so existing shot lists and the examples keep working.

## Anti-goals (failure even if it works)

- **The app or CLI writes somewhere the person didn't ask for.** Installing a skill writes one symlink into the agent's own skills folder and nothing else. It never overwrites a file or a symlink that points somewhere else.
- **Setup runs the person's shell startup files.** Finding Node must not run `.zshrc` or `.bash_profile`; those can do anything and can take seconds.
- **Anything leaves the Mac.** `doctor` and the setup window make no network calls. The one exception is a link the person clicks to watch the example video, which opens in their browser.
- **A capture fails because of onboarding.** A library problem or a temp-folder warning never fails a recording. They're reported, not enforced.
- **Breaking the library's existing promises.** The app still never moves, renames, or deletes a video, and every library change still goes through the CLI.

## How it's built (decided)

### `capture-director doctor`

A new CLI command that prints the usual JSON summary: a list of checks, each with `name`, `ok`, `detail`, and `fix` (a single sentence, or null). It exits 0 when every required check passes and 1 otherwise, so an agent can branch on it.

Required checks:

- **Node** is 20 or newer.
- **Chrome** is found on the channel `record` will use (`CD_CHROME_CHANNEL` respected).
- **ffmpeg and ffprobe** are on the PATH, and ffmpeg lists `libx264` among its encoders.
- **Library home** (`CD_HOME` or `~/.capture-director`) exists or can be created, and is writable. Its path is in the output.

Informational checks (reported, never fail the exit code):

- **Skill installs:** whether `~/.claude/skills/capture-director` and `~/.agents/skills/capture-director` exist and point at this checkout.
- **Mac app:** whether `Capture Director.app` is in `/Applications` or `~/Applications`, and whether its `config.json` points at this checkout's CLI and a Node that still exists.
- **`npm link`:** whether `capture-director` on the PATH resolves to this checkout.

`doctor` runs no network calls and launches no browser. It finds Chrome the same way `record` does, without starting it.

### Skill install for each agent

A new CLI command: `capture-director skill install --for claude|codex` and `capture-director skill status`. Install makes the same symlink the README shows today (`~/.claude/skills/capture-director` or `~/.agents/skills/capture-director` pointing at `<repo>/skill`), creating the parent folder if needed. If the path already exists and points here, it reports "already installed." If it exists and is anything else, it stops and says what's there; it never overwrites. The README replaces the raw `ln -s` lines with these commands.

For other agents, `capture-director skill print` writes a short block to stdout that a person pastes into their agent's rules file (Cursor rules, `GEMINI.md`, a project `AGENTS.md`, and so on). The block says what capture director is, gives the absolute path to the CLI and to `SKILL.md`, and tells the agent to read `SKILL.md` before recording. It's generated, so the paths are always right for this machine.

A root `AGENTS.md` goes in the repo for contributors' agents. It says how to run the tests and points at `skill/SKILL.md` and `mac/CLAUDE.md`. It's not how users connect their agent; `skill print` is.

### Skill changes

`skill/SKILL.md` gets four changes:

- **Finding the CLI.** "Use `capture-director` if it's on the PATH. Otherwise the CLI is `../bin/capture-director.js` from this skill's folder; run it with `node`." No more `<repo>`.
- **Run `doctor` first** in a new session, and stop with its `fix` sentences if a required check fails.
- **Where to put the work.** "Unless the user names a place, make a folder for the project in `~/Movies/Capture Director/<project>/` and put the shot list and timeline there. Never use a temp or scratch folder; the person needs to find these files later."
- **Reporting.** After `record` or `render`, report the output path and the `library` field (see below). If the library add failed, say so and give the error. If you're running in a sandbox or on a remote machine, say that the video is there and not on the person's Mac.

### Library status in the JSON

`remember()` returns what happened instead of only logging. `record` adds `library: { status, id?, home, error? }` to each shot's result, and `render` adds it to its result. `status` is `added`, `updated`, `skipped` (when `CD_NO_LIBRARY=1`), or `failed`. A failure still doesn't fail the capture.

### Temp folder warning

When a shot list's `outDir` or a timeline's output is inside a temporary folder (`/tmp`, `/private/tmp`, `/private/var/folders`, or `os.tmpdir()`), `record` and `render` print a warning to stderr and add `warnings: ["..."]` to the JSON: "This video is in a temporary folder that macOS clears. Move the shot list somewhere permanent, or the library will lose track of it." The recording still runs.

### Finding Node in the app

`InstallConfig` keeps the Node path from install time, but the app no longer gives up when that path is gone. A new `NodeLocator` in `CaptureDirectorKit` tries, in order, and takes the first Node 20 or newer:

1. The path in `config.json`.
2. Each folder in the config's saved `PATH`.
3. `/opt/homebrew/bin/node` and `/usr/local/bin/node`.
4. The newest installed version under `~/.nvm/versions/node`, `~/.asdf/installs/nodejs`, `~/.volta/tools/image/node`, and `~/.local/share/fnm/node-versions`.

It checks versions by running `node --version`, never a login shell. The result is cached for the session. `NodeLocator` takes the file system and process runner as parameters so it's tested without a real Node.

If the CLI itself is gone (the clone was moved or deleted), the app shows the setup window's "Your Mac" section with one sentence: "Capture Director can't find the capture-director folder. Run `capture-director install-app` from wherever you keep it now."

### "Set up your AI" window

A new window, opened from **Help > Set up your AI…** (⌘⇧A, or whatever doesn't collide; the builder checks), from the empty state, and automatically on first launch when the library is empty. It's a window, not Settings, because it's a guide and not a preference. It follows `mac/CLAUDE.md`: system controls, `.noInitialFocus()`, `.fitsContent()`, tokens from `Theme` and `Grid`.

Three sections:

- **Your Mac.** The required checks from `doctor`, each with a check mark or a warning and its `fix` sentence, plus a Check Again button. The app runs `doctor` through `CLI` like every other command.
- **Your AI.** A segmented control or picker: Claude Code, Codex, Other.
  - Claude Code and Codex each show their install status from `skill status` and an **Install** button that runs `skill install --for …`. When it's installed, the button becomes a check mark and a line: "Ask Claude Code to record a website and it'll use capture director."
  - Other shows the `skill print` block with a Copy button and a line on where to paste it.
  - A small line under all three: "Using the Claude app? Open its Code tab; the chat tab can't run tools on your Mac yet."
- **Try it.** A **Copy starter prompt** button. The prompt, with the library home filled in:

  > Use capture director to record a 10 second clip of https://example.com, hovering the main navigation and clicking one link. Put the project in ~/Movies/Capture Director/first-capture/. When it's done, tell me where the video is and whether it made it into the library.

  The person swaps in their own URL. Nothing is sent anywhere; it's the clipboard.

The window also shows the library home the app is reading, so a mismatch with an agent's `CD_HOME` is visible.

### Empty state

`EmptyLibrary` changes order and content:

1. Title stays "Nothing on the reel yet." The description becomes: "Ask your AI to record a website, and the video shows up here."
2. Primary button: **Set up your AI**, which opens the window above. Secondary: **Copy starter prompt**.
3. A disclosure, "Or run it yourself," with the existing three commands. Each command uses `capture-director` when `doctor` reports it's on the PATH, and the full `node <cli>` form from `config.json` when it isn't, so every command shown actually runs.
4. A link, **Watch an example**, that opens the README demo video on GitHub in the browser.

### New captures

Captures that appear in `library.json` while the app isn't frontmost get a small "New" mark (in `Palette.highlight`) on their grid item and list row until they've been selected or the window has been frontmost for a few seconds with them visible. The Dock icon shows the count of unseen captures. Both use no notification permission. "New" is app state only; nothing is written to `library.json`.

## Calls made (Claude's, confirmed by Derek on 2026-11-03)

- **The default home is `~/Movies/Capture Director/`**, and it lives in the skill and the starter prompt, not in the CLI. It's where Mac people look for video, and it keeps old shot lists working. The alternative was making `out` default to it in the CLI, which would quietly move the examples' output.
- **Skill install is a CLI command, and the app's Install button calls it.** That keeps the app's rule that every change goes through the CLI, and it gives agents the same command.
- **The setup window opens on its own once,** on first launch with an empty library, then only when asked. Remembered with `@AppStorage`.
- **No MCP server yet.** Most of Derek's audience will use Claude Code, Codex, or the Claude app's Code tab, which all run the CLI already. The window says so plainly.
- **"Watch an example" links to GitHub** instead of bundling a sample video, so the repo and app don't grow by megabytes. The alternative was a bundled 5 second clip imported as a sample on first launch.

## Testing

- Node tests for `doctor` with an injected environment (missing ffmpeg, ffmpeg without libx264, old Node, unwritable home), `skill install` and `skill status` against a temp `HOME` (fresh install, already installed, something else in the way), `skill print` output, the `library` field for each status, and the temp folder warning.
- Swift Testing for `NodeLocator` (each source in order, versions below 20 skipped, nothing found) and for the starter prompt and command text.
- Snapshot pages for the setup window (all checks passing, a failing check, each agent tab) and the new empty state, in light and dark, with the grid checks passing.
- Self-test checks for the Install button's round trip and for "New" marks on captures added while the app is in the background.

## Done means

- On a Mac with nothing set up, `capture-director doctor` names every missing piece and how to fix it.
- `capture-director skill install --for claude` and `--for codex` work, refuse to overwrite, and the README uses them.
- A fresh agent session with the skill finds the CLI without help, runs `doctor`, puts its project in `~/Movies/Capture Director/`, and reports the library status.
- The Mac app opens to the setup window on first launch, installs the skill for Claude Code and Codex, copies the starter prompt, and keeps working after a Node upgrade.
- A capture recorded by an agent while the app is in the background shows up marked as new, with a Dock badge.
- README sections updated: "Using it from Claude Code or Codex" becomes "Connecting your AI," with the three paths and a line on the `git pull` update model (pulling the repo changes the skill your agent reads, so read the diff like you'd read any script).

## What comes later

- **A local MCP server** (stdio, no keys) so chat-only apps can record. It would expose `record`, `render`, `sheet`, and `library` as tools and reuse everything here.
- **A Claude Code plugin manifest** so people can add it with `/plugin`, once the CLI install story is simple enough for a plugin to carry.
- **A notarized download** if Derek gets a Developer ID, so people can skip the clone.
- **The native recorder** brings Screen Recording and Accessibility permissions, and those belong in the "Your Mac" section of this window.
