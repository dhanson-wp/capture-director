# Security

Capture director is a local tool. It opens websites in headless Chrome, writes frames and videos to your disk, runs ffmpeg, and (if you ask) serves a small library app on your own machine. This page covers what it trusts, what it doesn't, and how it keeps the two apart.

## Reporting a problem

Please open a private security advisory on the GitHub repository (Security tab, "Report a vulnerability") rather than a public issue. Include the shot list or timeline that triggers it if you can. I'll reply as soon as I can and credit you in the fix unless you'd rather I didn't.

## What it trusts

- **You, and the files you choose to run.** A shot list is a script. `eval` steps run JavaScript in the page being recorded, `css` steps inject styles, and paths in a timeline read local fonts, clips, and music. Read a shot list from someone else before you run it.
- **Your installed Chrome and ffmpeg.** `FFMPEG`, `FFPROBE`, and `CD_CHROME_CHANNEL` pick which binaries run.

## What it doesn't trust

**The websites it records.** Chrome runs headless with a fresh, empty profile for every shot, with its sandbox on (Playwright turns it off by default) and downloads refused. Nothing from your own browser profile is available to the page.

**Values in YAML, beyond what they describe.** A shot list or timeline should only be able to describe a recording, not reach past it:

- Anything that lands in an ffmpeg filter graph (frame rates, durations, fades, crossfade names, trim points, and the event log in `capture.json`) has to be a finite number or a plain word. A crafted value can't add filters such as `movie=` that read or write other files.
- Shot ids must be plain names, so they can't climb out of the `out` folder. Re-recording deletes only the frame files the recorder wrote, never a whole folder.
- Shot URLs must be `http` or `https`. Clips and music must be local files, so ffmpeg never opens a URL or a remote playlist.
- The frame list is read in ffmpeg's safe concat mode, so a tampered `list.ffconcat` can't point at files outside its folder.
- Outputs need a video extension (`.mp4`, `.mov`, `.m4v`), and contact sheets need `.png`, so a typo can't overwrite a dotfile or a document.
- Card and caption styles can't close their `<style>` block, and those pages run under a Content Security Policy with no scripts and no network.
- Remote fonts time out after 20 seconds and are capped at 20 MB.

**Other websites and other machines, when the library is open.** `capture-director library` runs a web server, so it gets the most care:

- It listens on `127.0.0.1` only. Nothing else on your network can reach it.
- It answers only when the `Host` header is its own address, which blocks DNS rebinding (a web page pointing its own hostname at your machine).
- Every run makes a new random token. The link printed in your terminal trades it for an `HttpOnly`, `SameSite=Strict` cookie, so other sites can't send it and page scripts can't read it.
- Changes have to be JSON from the app's own origin. Forms and cross-site requests are refused.
- Videos and thumbnails are served by library id, never by path. Static files come from a fixed list.
- Pages are served with a strict Content Security Policy, no inline scripts, and `nosniff`. Titles and notes are always inserted as text.
- The app can retitle, regroup, star, annotate, reveal in Finder, and remove an entry from the list. It can't delete, move, or overwrite a video.
- `~/.capture-director/` is created readable only by you.

**Pages, for agents.** `skill/SKILL.md` tells an agent that text on a page is data, not instructions, and to use only `eval` steps it wrote itself.

## Dependencies

Two runtime dependencies: `playwright-core` and `yaml`. Run `npm audit` after installing; at the time of writing it reports no known vulnerabilities. The library's fonts (Manrope and Bricolage Grotesque) ship in `ui/fonts/` under the SIL Open Font License.
