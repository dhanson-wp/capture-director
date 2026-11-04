# Onboarding and agent setup implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new person goes from "installed" to "first video in the app" without help: a `doctor` check, one-command skill installs, no lost videos, and a Mac app that shows them how to connect their AI.

**Architecture:** Nothing changes in how the pieces talk. The agent runs the CLI, the CLI writes `library.json`, and the app watches it. New CLI commands (`doctor`, `skill`) do the checking and installing; the app's setup window calls them through the existing `CLI` runner. Pure logic lives in `src/*.js` (Node tests) and `mac/Sources/CaptureDirectorKit` (Swift Testing); views stay thin.

**Tech stack:** Node 20+ ESM with `node:test`, `playwright-core` and `yaml` only. SwiftUI on macOS 26, built with Command Line Tools through `mac/build.sh`.

**Spec:** `docs/superpowers/specs/2026-11-03-onboarding-and-agent-setup-design.md`

## Before you start

- The Mac recorder merged into `main` in PR #11 and shipped in v0.2.0. Start onboarding from the reviewed baseline, including the November 4 core readiness fixes, on a new `codex/onboarding` branch in its own worktree. Read `docs/2026-11-04-core-readiness-review.md` first.
- `record()` and `processShot()` in `src/shots.js` now include the native recorder flow. Preserve its cancellation and validation behavior when adding library results.
- Mac work follows `mac/CLAUDE.md`: scratch builds use `--dir /tmp/CaptureDirector-test-app`, tests run through `mac/tools/test.sh`, and a UI change is done only after `tools/snap.sh`, `tools/grid-lint.sh`, and `check-layout.swift` pass and you've looked at the light and dark snapshots.

## Global constraints

- No new npm dependencies and no new Swift packages.
- Node 20 or newer; macOS 26 or newer.
- `doctor`, `skill`, and the setup window make no network calls. The only network action is the "Watch an example" link, opened in the person's browser.
- Finding Node never runs a login shell or the person's shell startup files.
- `skill install` writes one symlink in the agent's skills folder and never overwrites a file or a symlink that points somewhere else.
- A library problem or a temp folder warning never fails a recording or render.
- Every library change and every skill install from the app goes through `CLI`. The app never writes `library.json` or symlinks itself.
- Every command prints JSON on stdout, except `skill print`, which prints the plain text block a person pastes.
- Copy: sentence case, contractions, no em dashes. Mac UI follows `mac/CLAUDE.md` (system controls, `Theme` and `Grid` tokens, `.noInitialFocus()`, `.fitsContent()`, a menu item and shortcut for every action).
- The default projects folder is `~/Movies/Capture Director/<project>/`, set in the skill and the starter prompt only. `out` in the CLI stays relative to the shot list.

## Review focus

1. **Paths with spaces.** `~/Movies/Capture Director`, `Capture Director.app`, and a clone in a folder like `~/My Projects` must survive every command string the app shows and every path `skill print` writes. Tested in Task 3 and Task 7.
2. **A skills path that's already taken.** A dangling symlink, a symlink to an old clone, or a real folder at `~/.claude/skills/capture-director` reports `other` with what's there, and install refuses. Tested in Task 3.
3. **A fresh account with no skills folder.** `~/.claude/skills` or `~/.agents/skills` doesn't exist yet; install creates it. Tested in Task 3.
4. **macOS temp paths come in two spellings.** `/tmp` is `/private/tmp`, and `os.tmpdir()` returns `/var/folders/...` while real paths are `/private/var/folders/...`. Both forms warn; `~/Movies/...` doesn't. Tested in Task 2.
5. **Missing tools don't crash `doctor`.** No ffmpeg on the PATH (spawn fails with ENOENT) gives a failed check with its fix, JSON on stdout, and exit code 1. In the app, a config pointing at an nvm Node 18 is skipped. Tested in Task 4 and Task 6.

---

### Task 1: Library status in the JSON

**Files:**
- Modify: `src/library.js` (`remember`)
- Modify: `src/shots.js` (`processShot` result)
- Modify: `src/render.js` (`render` result)
- Test: `test/remember.test.js` (new)

**Interfaces:**
- Produces: `remember(file, meta) -> Promise<{ status: 'added'|'updated'|'skipped'|'failed', id?: string, home: string, error?: string }>`. `processShot` and `render` results gain `library` with that value. `processShot` sets it only when `shot.source` is set, as today.

- [ ] **Step 1: Write the failing tests** in `test/remember.test.js`. Set `CD_HOME` to a `mkdtemp` folder and `CD_QUIET=1` before importing, like `test/library.test.js`, and make a video with `makeVideo` from `test/helpers.js`.

```js
test('remember says it added a new capture', async () => {
	const r = await remember(file, { kind: 'clip' });
	assert.equal(r.status, 'added');
	assert.match(r.id, /^[0-9a-f]{16}$/);
	assert.equal(r.home, process.env.CD_HOME);
});
test('remember says it updated a capture it already had', async () => {
	assert.equal((await remember(file, { kind: 'clip' })).status, 'updated');
});
test('remember skips when CD_NO_LIBRARY is 1', async () => {
	process.env.CD_NO_LIBRARY = '1';
	try { assert.deepEqual(await remember(file, {}), { status: 'skipped', home: process.env.CD_HOME }); }
	finally { delete process.env.CD_NO_LIBRARY; }
});
test('remember reports a failure instead of throwing', async () => {
	const r = await remember(path.join(dir, 'missing.mp4'), {});
	assert.equal(r.status, 'failed');
	assert.ok(r.error.length > 0);
});
```

- [ ] **Step 2: Run them and see them fail.** `node --test test/remember.test.js` fails: `remember` returns undefined.
- [ ] **Step 3: Make `remember` return the status.** `add()` stays as it is. A new entry has `added === updated` (both are set to the same `now`), so `status = entry.added === entry.updated ? 'added' : 'updated'`. Keep the stderr log line on failure. `home` is `home()`.
- [ ] **Step 4: Put it in the results.** In `processShot`, keep the `remember` call's return value and add `library` to the returned object. In `render`, the same.
- [ ] **Step 5: Run `npm test`.** Everything passes.
- [ ] **Step 6: Commit.** `git commit -m "feat: record and render say whether the capture made it into the library"`

### Task 2: Temp folder warning

**Files:**
- Modify: `src/util.js`
- Modify: `src/shots.js` (`processShot` result), `src/render.js` (`render` result)
- Test: `test/temp-path.test.js` (new)

**Interfaces:**
- Produces: `isTempPath(p: string, { tmp = os.tmpdir() } = {}) -> boolean` and `TEMP_WARNING` (the exact string below), both exported from `src/util.js`. `processShot` and `render` results gain `warnings: string[]` only when there's a warning.

- [ ] **Step 1: Write the failing tests.**

```js
test('temp folders count in both spellings', () => {
	for (const p of ['/tmp/x/out', '/private/tmp/x/out', '/var/folders/ab/T/x', '/private/var/folders/ab/T/x'])
		assert.equal(isTempPath(p, { tmp: '/var/folders/ab/T' }), true, p);
});
test('a permanent folder does not', () => {
	assert.equal(isTempPath(path.join(os.homedir(), 'Movies/Capture Director/demo/out')), false);
	assert.equal(isTempPath('/tmpfiles/out'), false);
});
test('the warning says what to do', () => {
	assert.equal(TEMP_WARNING, 'This video is in a temporary folder that macOS clears. Move the shot list somewhere permanent, or the library will lose track of it.');
});
```

- [ ] **Step 2: Run them and see them fail.** `node --test test/temp-path.test.js`.
- [ ] **Step 3: Implement `isTempPath`.** Resolve `p`, strip a leading `/private`, and do the same to `tmp`. Return true when the result is `/tmp`, `/var/folders`, or the stripped `tmp`, or is inside one of them. Compare whole path segments, so `/tmpfiles` doesn't match.
- [ ] **Step 4: Warn.** When the clip's or render's output path is a temp path, `log(TEMP_WARNING)` and add `warnings: [TEMP_WARNING]` to the result. The run still finishes.
- [ ] **Step 5: Run `npm test`.** Everything passes.
- [ ] **Step 6: Commit.** `git commit -m "feat: warn when a video lands in a temporary folder"`

### Task 3: `skill install`, `skill status`, and `skill print`

**Files:**
- Create: `src/skill.js`
- Modify: `bin/capture-director.js` (a `skill` case and three help lines)
- Test: `test/skill.test.js` (new)

**Interfaces:**
- Produces, from `src/skill.js`:
  - `AGENTS = { claude: '.claude/skills', codex: '.agents/skills' }`
  - `skillPath(agent, { home = os.homedir() } = {}) -> string`, the `capture-director` path inside the agent's folder
  - `skillStatus({ home, repo }) -> Promise<{ claude: AgentSkill, codex: AgentSkill }>` where `AgentSkill = { path: string, status: 'installed'|'missing'|'other', detail?: string }`
  - `installSkill(agent, { home, repo }) -> Promise<{ agent, path, status: 'installed'|'already-installed' }>`; throws when the status is `other`, or the agent is unknown
  - `skillPrint({ repo, onPath }) -> string`
  - `repo` defaults to the checkout this file is in, and `home` to `os.homedir()`.
- CLI: `skill install --for claude|codex`, `skill status`, `skill print`.

- [ ] **Step 1: Write the failing tests** against a `mkdtemp` home and a fake repo folder whose path contains a space.

```js
test('install makes the skills folder and the link', async () => {
	const r = await installSkill('claude', { home, repo });
	assert.deepEqual(r, { agent: 'claude', path: path.join(home, '.claude/skills/capture-director'), status: 'installed' });
	assert.equal(await readlink(r.path), path.join(repo, 'skill'));
});
test('installing twice says so', async () => {
	assert.equal((await installSkill('claude', { home, repo })).status, 'already-installed');
});
test('install never replaces something else', async () => {
	await mkdir(path.join(home, '.agents/skills'), { recursive: true });
	await symlink('/old/clone/skill', path.join(home, '.agents/skills/capture-director')); // dangling
	await assert.rejects(installSkill('codex', { home, repo }), /already .*\/old\/clone\/skill/);
	assert.equal((await skillStatus({ home, repo })).codex.status, 'other');
});
test('a real folder in the way is other, too', async () => { /* mkdir the path, expect status 'other' and a rejected install */ });
test('status reports missing', async () => { /* fresh home: both 'missing' */ });
test('print names the CLI and the skill with full paths', () => {
	const text = skillPrint({ repo, onPath: false });
	assert.match(text, new RegExp(`node "${repo}/bin/capture-director.js"`));
	assert.ok(text.includes(path.join(repo, 'skill', 'SKILL.md')));
	assert.ok(skillPrint({ repo, onPath: true }).includes('capture-director doctor'));
});
test('an unknown agent is refused', async () => {
	await assert.rejects(installSkill('cursor', { home, repo }), /claude or codex/);
});
```

- [ ] **Step 2: Run them and see them fail.** `node --test test/skill.test.js`.
- [ ] **Step 3: Implement `src/skill.js`.** Status uses `lstat`: no entry is `missing`; a symlink whose `readlink` resolves to `<repo>/skill` is `installed`; anything else is `other`, with `detail` saying what's there ("a link to /old/clone/skill" or "a folder"). The install error reads: `There's already something at <path> (<detail>). Move it, then try again.` Install creates the parent with `mkdir({ recursive: true })` and uses `symlink`.
- [ ] **Step 4: Write the `skillPrint` text.** The exact block, where `<cli>` is `capture-director` when `onPath`, else `node "<repo>/bin/capture-director.js"`:

```
Capture director records polished demo videos of websites on this Mac.
Before recording, read <repo>/skill/SKILL.md and follow it.
Run the CLI as: <cli>
Start with: <cli> doctor
```

- [ ] **Step 5: Wire up the CLI.** `skill install` needs `--for`; with none it throws `skill install needs --for claude or --for codex`. `skill print` writes the text to stdout and doesn't print JSON. Its `onPath` comes from `onPath()` in Task 4, so until then pass `false`. Add the three lines to `HELP`.
- [ ] **Step 6: Run `npm test`.** Everything passes.
- [ ] **Step 7: Commit.** `git commit -m "feat: install the skill for Claude Code or Codex with one command"`

### Task 4: `capture-director doctor`

**Files:**
- Create: `src/doctor.js`
- Modify: `bin/capture-director.js` (a `doctor` case, a help line, and `onPath()` for `skill print`)
- Test: `test/doctor.test.js` (new)

**Interfaces:**
- Consumes: `skillStatus` from Task 3; `defaultAppDir` logic from `src/install-app.js` for app locations; `FFMPEG` and `FFPROBE` from `src/util.js`.
- Produces:
  - `doctor(deps = defaultDeps()) -> Promise<{ ok: boolean, home: string, checks: Check[] }>`, with `Check = { name, required: boolean, ok: boolean, detail: string, fix: string|null }`. `ok` is true when every required check passes.
  - `deps = { nodeVersion: string, run(cmd, args) -> Promise<string>, exists(p) -> Promise<boolean>, chromeChannel: string, libraryHome: string, home: string, repo: string, ffmpeg: string, ffprobe: string, which(name) -> Promise<string|null> }`
  - `onPath(deps) -> Promise<boolean>`: `which('capture-director')`, with symlinks resolved, is this repo's `bin/capture-director.js`.
  - The Mac app (Task 7) decodes this JSON. Check names are fixed: `node`, `chrome`, `ffmpeg`, `ffprobe`, `library-home` (required), then `skill-claude`, `skill-codex`, `mac-app`, `on-path` (informational).

- [ ] **Step 1: Write the failing tests** with fake `deps`.

```js
test('everything ready', async () => {
	const r = await doctor(fakeDeps());
	assert.equal(r.ok, true);
	assert.deepEqual(r.checks.map((c) => c.name), ['node', 'chrome', 'ffmpeg', 'ffprobe', 'library-home', 'skill-claude', 'skill-codex', 'mac-app', 'on-path']);
});
test('old Node fails with its fix', async () => {
	const c = (await doctor(fakeDeps({ nodeVersion: 'v18.19.0' }))).checks.find((c) => c.name === 'node');
	assert.equal(c.ok, false);
	assert.equal(c.fix, 'Install Node 20 or newer from nodejs.org or with `brew install node`, then run this again.');
});
test('missing ffmpeg is a failed check, not a crash', async () => {
	const deps = fakeDeps({ run: async (cmd) => { if (cmd === 'ffmpeg') throw Object.assign(new Error('spawn ffmpeg ENOENT'), { code: 'ENOENT' }); return ''; } });
	const r = await doctor(deps);
	assert.equal(r.ok, false);
	assert.equal(r.checks.find((c) => c.name === 'ffmpeg').fix, 'Install ffmpeg with `brew install ffmpeg`.');
});
test('ffmpeg without libx264', async () => { /* encoders output without " libx264 ": fix is the x264 sentence */ });
test('an unwritable library home fails', async () => { /* libraryHome under a chmod 500 folder */ });
test('informational checks never change ok', async () => { /* skills missing, no app, not on PATH: ok stays true */ });
test('the CLI exits 1 and still prints JSON when a required check fails', () => {
	const r = spawnSync(process.execPath, ['bin/capture-director.js', 'doctor'], { env: { ...process.env, FFMPEG: '/nonexistent/ffmpeg' }, encoding: 'utf8' });
	assert.equal(r.status, 1);
	assert.equal(JSON.parse(r.stdout).checks.find((c) => c.name === 'ffmpeg').ok, false);
});
```

- [ ] **Step 2: Run them and see them fail.** `node --test test/doctor.test.js`.
- [ ] **Step 3: Implement the checks.** Any thrown error in a check becomes a failed check with the error message as `detail`; the function itself never throws.
  - **node:** major from `nodeVersion` is 20 or more.
  - **chrome:** don't launch it. Channel `bundled` uses `chromium.executablePath()` from `playwright-core`. Otherwise map the channel to an app name (`chrome` is "Google Chrome", `chrome-beta` is "Google Chrome Beta", `chrome-dev` is "Google Chrome Dev", `chrome-canary` is "Google Chrome Canary", `msedge` is "Microsoft Edge") and look for `<name>.app/Contents/MacOS/<name>` in `/Applications` and `~/Applications`. Off macOS, pass with `detail: 'not checked on this platform'`.
  - **ffmpeg:** `run(ffmpeg, ['-hide_banner', '-encoders'])`. It fails when the spawn fails, and fails with the x264 fix when the output lacks ` libx264 `. **ffprobe:** `run(ffprobe, ['-version'])`.
  - **library-home:** `mkdir({ recursive: true })`, then `access(W_OK)`.
  - **skill-claude, skill-codex:** from `skillStatus`. **mac-app:** find `Capture Director.app` in `/Applications` or `~/Applications`, read `Contents/Resources/config.json`, and pass when its `cli` is this repo's CLI and its `node` exists. **on-path:** `onPath(deps)`.
- [ ] **Step 4: Use the exact fix copy.**

| Check | `fix` |
|---|---|
| node | Install Node 20 or newer from nodejs.org or with `brew install node`, then run this again. |
| chrome | Install Google Chrome from google.com/chrome, or set CD_CHROME_CHANNEL to a Chrome you have. |
| ffmpeg, ffprobe | Install ffmpeg with `brew install ffmpeg`. |
| ffmpeg (no x264) | This ffmpeg can't encode H.264. Install Homebrew's build with `brew install ffmpeg`. |
| library-home | Capture director can't write to `<home>`. Check its permissions, or set CD_HOME to a folder you own. |
| skill-claude | Run `capture-director skill install --for claude`. |
| skill-codex | Run `capture-director skill install --for codex`. |
| mac-app | Run `capture-director install-app` from this folder. |
| on-path | Run `npm link` in this folder to put capture-director on your PATH. |

- [ ] **Step 5: Wire up the CLI.** Print the JSON, then set `process.exitCode = 1` when `!result.ok`. Switch `skill print` to the real `onPath()`. Add `doctor` to `HELP`: `capture-director doctor    Check that Chrome, ffmpeg, Node, and the library are ready`.
- [ ] **Step 6: Run `npm test`.** Everything passes.
- [ ] **Step 7: Commit.** `git commit -m "feat: doctor checks everything a capture needs and says how to fix it"`

### Task 5: Skill, README, and AGENTS.md

**Files:**
- Modify: `skill/SKILL.md`, `README.md`
- Create: `AGENTS.md`

**Interfaces:**
- Consumes: the commands from Tasks 1 through 4, and the JSON fields `library` and `warnings`.

- [ ] **Step 1: Update `skill/SKILL.md`.** Replace the `node <repo>/bin/capture-director.js` paragraph with: use `capture-director` if it's on the PATH, otherwise run `node` on `../bin/capture-director.js` from this skill's folder. Add a workflow step 0: run `doctor` once per session and stop with its `fix` sentences if `ok` is false. Change step 2's location rule to: unless the user names a place, make `~/Movies/Capture Director/<project>/` and put the shot list and timeline there, never a temp or scratch folder. Add to step 7: report each result's `library.status` (and `error` when it's `failed`), pass on any `warnings`, and if you're in a sandbox or on a remote machine, say the video is there and not on the person's Mac.
- [ ] **Step 2: Update `README.md`.** Rename "Using it from Claude Code or Codex" to "Connecting your AI." It covers three paths: `skill install --for claude`, `skill install --for codex`, and `skill print` for any other agent. Add one line: the Claude app's chat tab can't run tools on your Mac, so use its Code tab. Add one line on updates: pulling the repo changes the skill your agent reads, so read the diff the way you'd read any script. Add `doctor` and `skill` to the Commands block, and `doctor` to "What you need" as the way to check.
- [ ] **Step 3: Write `AGENTS.md`** for contributors' agents: run tests with `npm test` and `mac/tools/test.sh`; the user-facing skill is `skill/SKILL.md`; Mac app rules are in `mac/CLAUDE.md`; the repo is public, so never commit secrets or personal paths.
- [ ] **Step 4: Check copy.** `grep -n "—" skill/SKILL.md README.md AGENTS.md` prints nothing.
- [ ] **Step 5: Commit.** `git commit -m "docs: connecting your AI, and where agents should put projects"`

### Task 6: The app finds Node after an upgrade

**Files:**
- Create: `mac/Sources/CaptureDirectorKit/NodeLocator.swift`
- Modify: `mac/Sources/CaptureDirectorKit/CLI.swift` (a `cliMissing` error), `mac/Sources/CaptureDirector/AppModel.swift` (resolve Node at launch, keep `cli` as a property)
- Test: `mac/Tests/CaptureDirectorKitTests/NodeLocatorTests.swift`

**Interfaces:**
- Produces:
  - `NodeLocator.find(config: InstallConfig, home: String, isExecutable: (String) -> Bool, listDir: (String) -> [String], version: (String) -> String?) -> String?`
  - `NodeLocator.major(_ version: String) -> Int?`, so `"v22.3.0"` is 22
  - `CLIError.cliMissing`, with the message: "Capture Director can't find the capture-director folder. Run `capture-director install-app` from wherever you keep it now."
  - `AppModel.cli: CLI?`, the runner with the resolved Node, for Tasks 7 and 8

- [ ] **Step 1: Write the failing tests** with fake closures.

```swift
@Test func configNodeWinsWhenItWorks() { /* config.node executable at v22: returns it */ }
@Test func savedPathIsNext() { /* config.node gone; "/x/bin:/y/bin" with /y/bin/node v20: returns /y/bin/node */ }
@Test func homebrewBeforeVersionManagers() { /* /opt/homebrew/bin/node and an nvm v24: returns homebrew */ }
@Test func newestVersionManagerNode() {
    // ~/.nvm/versions/node has v18.20.0, v20.11.1, v22.3.0; fnm has v21.0.0 under installation/bin
    #expect(NodeLocator.find(...) == "/Users/me/.nvm/versions/node/v22.3.0/bin/node")
}
@Test func nodeBelow20IsSkipped() { /* only an nvm v18 and a config node at v18: nil */ }
@Test func nothingFound() { /* nil */ }
@Test func majorParses() { #expect(NodeLocator.major("v22.3.0") == 22); #expect(NodeLocator.major("garbage") == nil) }
```

- [ ] **Step 2: Run `mac/tools/test.sh` and see them fail.**
- [ ] **Step 3: Implement `find`.** Try in order and return the first executable whose `version` has a major of 20 or more: `config.node`, `<dir>/node` for each `config.path` entry, `/opt/homebrew/bin/node`, `/usr/local/bin/node`. Then gather the version-manager installs and return the newest by semantic version: `~/.nvm/versions/node/<v>/bin/node`, `~/.asdf/installs/nodejs/<v>/bin/node`, `~/.volta/tools/image/node/<v>/bin/node`, and `~/.local/share/fnm/node-versions/<v>/installation/bin/node`.
- [ ] **Step 4: Wire it into the app.** In `AppModel.init`, the real `version` closure runs `<node> --version` with `Process` directly (no shell), with a 2 second limit. When `find` returns a different path, copy the config with that `node`. When it returns nil, keep the config so `CLI` reports `notInstalled` as today. In `CLI.runBlocking`, throw `cliMissing` when `config.cli` doesn't exist (before checking Node). Keep `cli` on `AppModel`.
- [ ] **Step 5: Run `mac/tools/test.sh` and `mac/tools/selftest.sh`.** Both pass.
- [ ] **Step 6: Commit.** `git commit -m "feat(mac): keep working after a Node upgrade"`

### Task 7: Setup logic in the kit

**Files:**
- Create: `mac/Sources/CaptureDirectorKit/Setup.swift`
- Test: `mac/Tests/CaptureDirectorKitTests/SetupTests.swift`

**Interfaces:**
- Produces:
  - `DoctorReport: Decodable { ok: Bool; home: String; checks: [Check] }` and `Check: Decodable, Identifiable { name, required: Bool, ok: Bool, detail: String, fix: String? }`, with `id` being `name`. `report.required` is the required checks; `report.check(_ name: String) -> Check?`.
  - `SkillStatus: Decodable { claude: AgentSkill; codex: AgentSkill }` and `AgentSkill { path: String; status: String; detail: String? }`, with `var installed: Bool { status == "installed" }`.
  - `StarterPrompt.text: String`, the exact prompt from the spec.
  - `RunCommand.prefix(onPath: Bool, config: InstallConfig?) -> String`: `capture-director` when `onPath` or there's no config, else `'<node>' '<cli>'` with each part in single quotes (an inner `'` becomes `'\''`).

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func decodesDoctorJSON() { /* a doctor JSON sample with one failed required check: ok false, required.count 5, check("ffmpeg")?.fix set */ }
@Test func decodesSkillStatus() { /* claude installed, codex other with detail */ }
@Test func starterPromptIsExact() {
    #expect(StarterPrompt.text == "Use capture director to record a 10 second clip of https://example.com, hovering the main navigation and clicking one link. Put the project in ~/Movies/Capture Director/first-capture/. When it's done, tell me where the video is and whether it made it into the library.")
}
@Test func commandOnPath() { #expect(RunCommand.prefix(onPath: true, config: cfg) == "capture-director") }
@Test func commandQuotesPathsWithSpaces() {
    let c = InstallConfig(node: "/opt/homebrew/bin/node", cli: "/Users/me/My Projects/capture-director/bin/capture-director.js", path: "", cdHome: nil)
    #expect(RunCommand.prefix(onPath: false, config: c) == "'/opt/homebrew/bin/node' '/Users/me/My Projects/capture-director/bin/capture-director.js'")
}
@Test func commandQuotesAnApostrophe() { /* "/Users/me/Derek's/cli.js" becomes '/Users/me/Derek'\''s/cli.js' */ }
```

- [ ] **Step 2: Run `mac/tools/test.sh` and see them fail.**
- [ ] **Step 3: Implement `Setup.swift`.**
- [ ] **Step 4: Run `mac/tools/test.sh`.** Everything passes.
- [ ] **Step 5: Commit.** `git commit -m "feat(mac): read doctor and skill status, and build the starter prompt"`

### Task 8: The "Set up your AI" window

**Files:**
- Create: `mac/Sources/CaptureDirector/SetupWindow.swift` (the view and a `SetupModel`)
- Modify: `mac/Sources/CaptureDirector/App.swift` (the scene and the Help menu item), `mac/Sources/CaptureDirector/AppModel.swift` (owns `setup: SetupModel`), `mac/Sources/CaptureDirector/ContentView.swift` (opens it once on first launch), `mac/Sources/CaptureDirector/Snapshot.swift` (pages that capture this window), `mac/Sources/CaptureDirector/SelfTest.swift`

**Interfaces:**
- Consumes: `AppModel.cli` (Task 6); `DoctorReport`, `SkillStatus`, `StarterPrompt` (Task 7); the CLI commands `doctor`, `skill status`, `skill install --for`, `skill print` (Tasks 3 and 4).
- Produces: `@Observable final class SetupModel { var report: DoctorReport?; var skills: SkillStatus?; var otherText: String?; var problem: String?; func refresh() async; func install(_ agent: String) async }`. The window id is `"setup"`, which Task 9's button opens with `openWindow(id: "setup")`.

- [ ] **Step 1: Write the self-test check first.** In `SelfTest.swift`, against the scratch home: `refresh()` fills `report` and `skills`. With `HOME` pointed at a scratch folder for the CLI, `install("claude")` leaves `skills.claude.installed == true`. Skip with the existing "no config.json" message when there's no CLI.
- [ ] **Step 2: Run `mac/tools/selftest.sh` and see the new check fail.**
- [ ] **Step 3: Build `SetupModel`.** `refresh` runs `doctor` (a non-zero exit still has the JSON on stdout, so `CLI.run` needs an `allowFailure: Bool = false` parameter that returns stdout on exit 1), `skill status`, and `skill print`. `install` runs `skill install --for <agent>`, then `refresh`. CLI errors go in `problem`.
- [ ] **Step 4: Build the window.** `Window("Set Up Your AI", id: "setup")` with `.windowResizability(.contentSize)`, `.noInitialFocus()`, and `.fitsContent()`. Use a grouped `Form` with three sections:
  - **Your Mac:** one row for each required check, a `checkmark.circle.fill` or `exclamationmark.triangle.fill` symbol, and `fix` below in `.secondary`. Then the library home ("Library: <home>"), and a Check Again button.
  - **Your AI:** a segmented `Picker` with Claude Code, Codex, and Other. Claude Code and Codex show `.borderedProminent` Install, or a check mark and "Ask Claude Code to record a website and it'll use capture director." (with "Codex" in place of "Claude Code" on the Codex tab). Other shows `otherText` in a monospaced box with a Copy button, plus "Paste this into your agent's rules, like a Cursor rule, GEMINI.md, or AGENTS.md." Under all three: "Using the Claude app? Open its Code tab; the chat tab can't run tools on your Mac yet."
  - **Try it:** a Copy Starter Prompt button that puts `StarterPrompt.text` on the clipboard and briefly shows "Copied," like `CommandRow`.

  `refresh()` runs when the window appears. When the CLI fails with `CLIError.cliMissing`, Your Mac shows that error's message in place of the checks, since `doctor` can't run.
- [ ] **Step 5: Add the menu item.** Add `CommandGroup(before: .help)` with "Set Up Your AI…" and ⌘⇧A, after checking that no existing command uses that shortcut (`grep -n keyboardShortcut mac/Sources`).
- [ ] **Step 6: Open it once on first launch.** In `ContentView`, `@AppStorage("setupShown")`. When the store has loaded, the library is empty, and `setupShown` is false, call `openWindow(id: "setup")` and set it true.
- [ ] **Step 7: Snapshot it.** Give `Snapshot.Page` an optional `window: String?`. When it's set, the snapshot opens that window and captures it instead of the main window. Add `setup-ready` (every check passing, Claude Code installed), `setup-failing` (ffmpeg failing), and `setup-other` (Other tab). Each page fills `model.setup` with fixture values and doesn't run the CLI.
- [ ] **Step 8: Build and verify.** `node bin/capture-director.js install-app --dir /tmp/CaptureDirector-test-app`, `mac/tools/selftest.sh`, `APP_SNAPSHOT_PAGES=setup-ready,setup-failing,setup-other mac/tools/snap.sh`, `mac/tools/grid-lint.sh`, and `swift mac/tools/check-layout.swift /tmp/CaptureDirector-shots/*-layout.json`. All pass. Look at all six PNGs.
- [ ] **Step 9: Commit.** `git commit -m "feat(mac): set up your AI from the app"`

### Task 9: Empty state that points at your AI

**Files:**
- Modify: `mac/Sources/CaptureDirector/ContentView.swift` (`EmptyLibrary`, `CommandRow`)

**Interfaces:**
- Consumes: `StarterPrompt.text`, `RunCommand.prefix` (Task 7); `model.setup.report?.check("on-path")?.ok` and `AppModel.cli?.config` for the prefix; the `"setup"` window (Task 8).

- [ ] **Step 1: Rework `EmptyLibrary`.**
  - Title "Nothing on the reel yet." Description: "Ask your AI to record a website, and the video shows up here."
  - Actions: a `.borderedProminent` Set Up Your AI button that opens the window, and a Copy Starter Prompt button.
  - A `DisclosureGroup("Or run it yourself")` with the three existing `CommandRow`s. Each command starts with `RunCommand.prefix(...)` in place of `capture-director`.
  - A `Link("Watch an example", destination: URL(string: "https://github.com/dhanson-wp/capture-director#readme")!)`.
- [ ] **Step 2: Snapshot it.** The existing `empty` page, plus `empty-open` with the disclosure expanded and the config prefix (not on PATH, a clone path with a space).
- [ ] **Step 3: Build and verify.** As in Task 8 Step 8, with `APP_SNAPSHOT_PAGES=empty,empty-open`. Check that the long command fits on one line at `.minimumScaleFactor(0.8)`; if it doesn't, let it wrap to two lines with `.lineLimit(2)` rather than truncating.
- [ ] **Step 4: Commit.** `git commit -m "feat(mac): the empty library points you at your AI"`

### Task 10: New captures get a mark and a Dock badge

**Files:**
- Create: `mac/Sources/CaptureDirectorKit/Arrivals.swift`
- Modify: `mac/Sources/CaptureDirector/LibraryStore.swift`, `GridView.swift`, `ListView.swift`, `AppModel.swift` (clears on selection and activation), `Snapshot.swift`, `SelfTest.swift`
- Test: `mac/Tests/CaptureDirectorKitTests/ArrivalsTests.swift`

**Interfaces:**
- Produces: `Arrivals.new(known: Set<String>, current: [String]) -> Set<String>` (ids in `current` not in `known`), and `Arrivals.badge(_ count: Int) -> String?` (nil for 0, `"99+"` above 99). `LibraryStore.unseen: Set<String>` and `LibraryStore.markSeen(_ ids: Set<String>)`. The store's init takes `isActive: @MainActor () -> Bool = { NSApp.isActive }`.

- [ ] **Step 1: Write the failing tests.**

```swift
@Test func newIdsOnly() { #expect(Arrivals.new(known: ["a", "b"], current: ["a", "b", "c"]) == ["c"]) }
@Test func badgeText() { #expect(Arrivals.badge(0) == nil); #expect(Arrivals.badge(3) == "3"); #expect(Arrivals.badge(140) == "99+") }
```

- [ ] **Step 2: Run `mac/tools/test.sh` and see them fail.**
- [ ] **Step 3: Track arrivals in the store.** After the first successful read, each reload that happens while `isActive()` is false adds `Arrivals.new` to `unseen`. Entries that leave the library leave `unseen`. Set `NSApp.dockTile.badgeLabel = Arrivals.badge(unseen.count)` whenever `unseen` changes. Nothing is written to `library.json`.
- [ ] **Step 4: Clear them.** Selecting a capture calls `markSeen` for it. Three seconds after `NSApplication.didBecomeActiveNotification`, if the app is still active, `markSeen` the unseen captures in the current `Browse.apply` result.
- [ ] **Step 5: Show the mark.** A "New" capsule on grid items and list rows in `unseen`, with `Palette.highlight` behind `.primary` text in `.caption`, positioned with `Space` tokens.
- [ ] **Step 6: Self-test and snapshot it.** Self-test: start the store with `isActive` returning false, add an entry through the CLI, and check that `unseen` holds its id and the badge reads "1". Then `markSeen` and check that it's empty. Also check that the first read of a library that already has entries leaves `unseen` empty. Snapshot page `new-marks` puts two fixture ids in `unseen`.
- [ ] **Step 7: Build and verify.** As in Task 8 Step 8, with `APP_SNAPSHOT_PAGES=new-marks,all-grid,all-list`.
- [ ] **Step 8: Commit.** `git commit -m "feat(mac): captures that arrive in the background are marked new"`

### Task 11: Whole-branch check

- [ ] **Step 1: Run everything.** `npm test`, `mac/tools/test.sh`, `mac/tools/selftest.sh`, a full `mac/tools/snap.sh`, `mac/tools/grid-lint.sh`, and `check-layout.swift`. All pass.
- [ ] **Step 2: Walk through the spec's "Done means" by hand.**
  - With `PATH` holding nothing but node, `doctor` names the missing ffmpeg and exits 1.
  - With `HOME` pointed at a scratch folder, `skill install` works for both agents and refuses the second time.
  - Point a scratch app's config at a Node path that doesn't exist; the app still makes changes.
  - Record into the scratch home with the app in the background; the capture shows "New" and the Dock shows 1.
- [ ] **Step 3: Scan for secrets and personal paths** before pushing (the repo is public): `git diff main --stat` and `git diff main | grep -n "/Users/derekhanson\|token\|secret"` print nothing unexpected.
