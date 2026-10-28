# Capture director

<!-- impeccable:product-schema 1 -->

## Platform
web

## Stack
The marketing website uses Astro and GSAP, as requested. The product itself is a local Node.js CLI using Playwright, Chrome, and ffmpeg.

## Users
Builders making website demo videos. Derek confirmed the primary audience is builders using Codex or Claude Code.

## Product purpose
Turn a YAML shot list into recorded website clips, then assemble clips, cards, captions, and music into a finished video.

## Capabilities and constraints
Runs locally without an account or telemetry. Each shot uses a fresh logged-out Chrome profile. macOS is the tested platform; requires Node 20+, installed Google Chrome, and ffmpeg with libx264. Output defaults to 1920×1080, 30 fps, H.264. MIT license. Source downloads from GitHub, not a packaged desktop app.

## Evidence on hand
README.md, source code, examples/blog-tour, docs/demo.mp4, docs/demo-poster-first.mp4, and docs/demo-poster.png. No customer counts, testimonials, or speed benchmarks supplied.

## Brand commitments
Use the product name and Derek's voice guide. Derek rejected warm paper and recording red in favor of a more unique visual identity, and approved direct Astro implementation. The current proposed identity is citron, pool blue, and mulberry. The website will live on Spacefast; Derek explicitly approved public access on October 27, 2026. The live website is public; older version previews remain governed by their existing access rules.
