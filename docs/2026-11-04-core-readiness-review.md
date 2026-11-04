# Core readiness review

I checked the public repo, installed dependencies in a clean scratch checkout, ran the core website example, and cleaned the local library before the next feature build.

## GitHub status

Verified November 4, 2026:

- Public repo: https://github.com/dhanson-wp/capture-director
- Local HEAD and remote HEAD: `3776301b7f42cd57b7f6dfbb1eb7c96d5270dcd4`.
- Latest release: v0.2.0. Source only; no downloadable app assets.
- Latest main CI run passed: https://github.com/dhanson-wp/capture-director/actions/runs/41778376542
- No open pull requests or issues returned by GitHub.
- The November 3 onboarding plan and design spec haven't been implemented. They're included with this review's commit so the next build has a recorded starting point.

## Fixes in this working tree

- Isolated `test/app-shots.test.js` with a temporary `CD_HOME`. Its synthetic video processing test previously registered recordings in the person's real library. The test now verifies registration in the isolated library.
- Fixed the Mac build script to honor Swift's exit code and print the full build log on failure. It previously swallowed the exit code and used source/binary timestamps as a substitute, which rejected a successful cached build here.
- Synchronized the lockfile's version, license, and executable metadata with package.json. Dependency versions are unchanged.
- Added README commands for recording, rendering, and inspecting the example without requiring `npm link`.
- Added selection-state diagnostics to the Mac self-test.

## Verification

- Clean source archive: `npm ci` succeeded from inside its folder.
- Node suite: 75 passed, zero failures or skips.
- Swift suite: 107 passed.
- Mac app installed and signed ad hoc in `/tmp/CaptureDirector-review-app`, without replacing the installed app.
- Final Mac app self-test: `SELFTEST PASS 109 checks`, using a temporary fixture library through LaunchServices. An earlier cached build reported four selection checks failing; the rebuilt app passed all checks.
- Documented blog example: both website shots recorded, timeline rendered to a 23.7-second 1920x1080 MP4, and contact sheet generated and visually inspected. Cards, captions, cursor, page interaction, and scrolling appeared in the output.
- Example output and review logs are under `/tmp/capture-director-review` and `/tmp/capture-director-*.log`; these are temporary evidence, not committed media.
- `git diff --check` passed.

## Local library cleanup

Removed 17 entries whose videos lived in temporary test directories, along with their empty library folders. Used the library's `forget` and `removeFolder` functions. All original videos stay on disk.

Four project captures remain: editor, find-seat, weddings-seating-map, and explore. All four files exist. The only remaining folders are dynamic-shapes and weddings-seating-map-video. The installed app reads this default library.

Backup: `~/.capture-director/library.before-test-cleanup-1793805606687.json`.

The repo's example YAML and test fixture generators remain available for users and automated checks. They aren't preloaded into a new user's library.

## Limits and handoff

The core website flow works on this Mac with Chrome and ffmpeg installed. This review doesn't establish compatibility across every macOS version or Node installation. Native app recording permissions and a live mouse-and-keyboard take weren't retested. Automated native recording logic and cancellation tests passed.

The planned doctor command, agent setup window, Node discovery fallback, library result reporting, and new-capture badges remain future work. Installation still requires a source clone, Node 20+, Chrome, and ffmpeg 7+; the Mac app also needs macOS 26+ and Command Line Tools.

These review fixes and the onboarding documents are committed together on a local review branch. GitHub main and v0.2.0 haven't changed. Keep every future recording test on an isolated `CD_HOME`.
