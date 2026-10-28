---
name: Capture director website
description: A working film treatment for a local website demo tool.
colors:
  citron: "#e5d935"
  pool: "#d4e9ed"
  mulberry: "#4c1637"
  mulberry-deep: "#321025"
  muted: "#695164"
  line: "#b6cdd2"
  white: "#fbf9ef"
  citron-hover: "#f2e966"
  citron-copy: "#654154"
  dark-copy: "#dfc7d6"
  code: "#f3e8ed"
typography:
  display:
    fontFamily: "Bricolage Grotesque Variable, sans-serif"
    fontSize: "clamp(5rem, 8.6vw, 8rem)"
    fontWeight: 650
    lineHeight: 0.92
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Bricolage Grotesque Variable, sans-serif"
    fontSize: "clamp(2.7rem, 4.6vw, 4.1rem)"
    fontWeight: 550
    lineHeight: 1.12
    letterSpacing: "-0.04em"
  title:
    fontFamily: "Manrope Variable, sans-serif"
    fontSize: "1.35rem"
    fontWeight: 650
    lineHeight: 1.3
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Manrope Variable, sans-serif"
  button:
    fontFamily: "Manrope Variable, sans-serif"
    fontSize: "0.9rem"
    fontWeight: 650
  mono:
    fontFamily: "ui-monospace, SFMono-Regular, Consolas, monospace"
    fontSize: "0.75rem"
rounded:
  film: "3px"
  panel: "4px"
  control: "5px"
  button: "8px"
spacing:
  inset: "22px"
  small: "16px"
  medium: "26px"
  large: "40px"
components:
  button-primary:
    backgroundColor: "{colors.mulberry}"
    textColor: "{colors.white}"
    rounded: "{rounded.button}"
    padding: "18px 23px"
    typography: "{typography.button}"
  button-primary-hover:
    backgroundColor: "{colors.mulberry-deep}"
  button-hero:
    backgroundColor: "{colors.mulberry}"
    textColor: "{colors.citron}"
    rounded: "{rounded.button}"
  button-light:
    backgroundColor: "{colors.citron}"
    textColor: "{colors.mulberry}"
    rounded: "{rounded.button}"
    padding: "18px 23px"
  button-light-hover:
    backgroundColor: "{colors.citron-hover}"
  process-panel:
    backgroundColor: "{colors.mulberry}"
    textColor: "{colors.pool}"
    rounded: "{rounded.panel}"
---

# Design System: Capture director website

## Overview

**Creative North Star: "Working film treatment"**

The implemented website uses a working film treatment: oversized titles, broad color fields, viewfinder corners, and a compact editing timeline. It's a marketing surface for builders using Codex or Claude Code, implemented directly in Astro with GSAP. This system belongs to the website; it doesn't prescribe the CLI's interface.

The final cascade in `src/styles/global.css` is authoritative. Earlier declarations include superseded radius, palette, and hero measurements; don't restore them when extending the page. `SURFACE.md` records the approved first surface, and `../PRODUCT.md` carries product facts.

**Key Characteristics:**

- Citron, pool, and mulberry color fields
- Self-hosted Bricolage Grotesque and Manrope
- Real footage and an illustrated write, record, edit, export sequence
- Readable static content before animation

## Colors

Three distinct inks organize the page through large fields and readable contrast.

### Primary

- **Citron:** Hero, feature field, playback control, setup action, and selected step numerals.
- **Mulberry:** Main text, dark demo and setup fields, process stage, and primary actions.

### Secondary

- **Pool:** Reading surfaces, footer, and text on dark panels.

### Neutral

- **Muted:** Supporting copy on pool.
- **Citron copy:** Supporting copy on citron.
- **Dark copy and code:** Supporting text and code inside mulberry fields.
- **Line:** Dividers on pool. Dark fields use translucent white or the source's mauve divider.
- **White:** Video control text and general primary action text. Hero and closing actions override it with citron.

**The Three Inks Rule.** Keep the broad fields citron, pool, and mulberry; supporting colors serve copy, dividers, and footage chrome.

## Typography

**Display Font:** Bricolage Grotesque Variable, sans-serif fallback.
**Body Font:** Manrope Variable, sans-serif fallback.
**Label/Mono Font:** Native monospace stack for commands, timestamps, and step indices.

Both branded families are self-hosted as two Latin WOFF2 files, explicitly preloaded with `font-display: block`. Motion initializes after `document.fonts.ready` so its measurements use the final type. The title stays static, including its rotated final phrase; it has no entrance animation. Body type keeps explanations compact and practical. Headings balance, and paragraphs use pretty wrapping.

The frontmatter records the base ramp. Clipped title-line wrappers use a line height of 1.08 around the display phrases. The hero resolves to `clamp(4rem, 8.5vw, 6rem)` at 1100px and below, then `clamp(3.25rem, 17vw, 6rem)` at 600px and below. Supporting copy varies by component, commonly using line heights from 1.7 to 1.85. Don't impose a fabricated uniform body size on these existing roles.

## Layout

The centered container caps at 1240px, with 56px side margins on the default desktop. Margins become 36px at 1100px and below, then 20px at 600px and below. Large color fields extend to the viewport edges. Hero and supporting sections use asymmetric two-column grids; mobile stacks them. The hero's final desktop split is 1.55fr to 1fr, with a 54px gap.

Workflow pinning runs at 900px and above only when the viewport is at least 720px tall and motion is allowed. The full-width workflow section pins with `pin: true` for 2400px of scroll, leaving its centered inner wrap unchanged. Its four phases are shot list, actual capture footage, illustrative edit assembly, and export receipt. Desktop scrub is 0.35. Below either desktop dimension, the process stage runs without pinning, from its top at 85% of the viewport to its bottom at 10%, with scrub 0.25. Reduced motion keeps all four written steps and the code scene static and readable. Step copy stays full opacity; the selected numeral supplies emphasis.

The workflow grid uses 0.68fr and 1.32fr columns with a 50px gap on wide desktop. At widths of at least 900px and heights up to 900px, a compact composition reduces padding, type, and gaps and uses a 1.85 stage aspect ratio. Tablet steps use two columns, while phone steps stack. These dimensions keep the pinned story within the viewport.

## Elevation & Depth

Color fields and fine rules provide most separation. Footage and the process stage use soft shadows, while the playback and export controls sit above footage. These shadows belong to the media framing, not every content section.

### Shadow Vocabulary

- **Film:** `0 30px 50px -30px #481005aa`.
- **Process stage:** `0 24px 48px -30px #151c1d77`.
- **Playback:** `0 8px 35px #0005`.
- **Export:** `0 8px 30px #0006`.

## Shapes

Footage uses nearly square corners, the process and terminal panels use small corners, and download actions use a softer radius. Viewfinder corners and fine timeline tracks provide the film vocabulary. Use the existing Lucide library through `@lucide/astro` for interface icons. Interface SVGs use Lucide, including feature icons, arrows, playback, copy confirmation, and FAQ Plus. The approved product logo stays unchanged. Standalone component previews inline the library SVG geometry; they don't require a framework runtime. These shapes are evidence from the product interface, not decorative raster artwork.

## Components

### Buttons

Primary actions use mulberry with white or citron text, with a deeper mulberry hover. The setup action reverses to citron on mulberry. Controls and their directional icons stay anchored; feedback comes from background, color, and inset borders rather than bouncing, lifting, or scaling. Button and copy-control surface changes use 160ms, with a 120ms inset-shadow transition. Keyboard focus uses a 3px outline offset by 6px; setup controls switch the outline to citron for dark-field contrast.

### Navigation

The horizontal header shares the citron field, with a linked icon and name. On mobile, the first two section links hide while GitHub stays available. Keep the skip link usable at keyboard focus.

### Film player

Native video controls, inline playback, a poster, and an explicit overlay play action present the real demo. It doesn't autoplay. The poster originates at `../docs/demo-poster.png`; the existing finished `demo.mp4` is approximately 31.3 seconds and is an ignored binary. These are existing product evidence, with no generated raster artwork. Keep the error fallback and descriptive track.

### Process panel

A mulberry panel stages four phases. Illustrative YAML wipes away to actual scroll-seeked footage. Real frame thumbnails then assemble into an explicitly illustrative editing timeline with title and music tracks, followed by an export receipt. The timeline, caption, and waveform are explanatory UI, not a claim that the site is an editing application.

GSAP owns orchestration in `src/scripts/motion.ts`. Emil Kowalski's strong ease-out becomes `ui-out` (`0.23,1,0.32,1`); the movement curve becomes `ui-move` (`0.77,0,0.175,1`). Wipes and phase changes use these curves. The timeline reverses with scrolling. Statement and detail rules draw with `scaleX` on real spans. The hero, viewfinder corners, terminal, closing title, and controls have no entrance, convergence, tilt, or hover-travel animation.

The silent 1280px, frequent-keyframe `/story.mp4` is an approximately 28-second local derivative of `../docs/demo.mp4`, distinct from the finished demo player. It loads only when the workflow comes within 1000px of the viewport and motion is allowed. A queued target time seeks only when media is ready and not already seeking; completion applies the latest target, including reverse scrolling. Four JPEG thumbnails are genuine frame extractions at 2, 8, 15, and 24 seconds from the same finished demo. `README.md` records their origin. No generated raster artwork is introduced. Reduced motion keeps the first code scene, full rules, and all four instructions visible without loading the scroll video.

### Terminal and disclosure rows

Installation commands remain selectable and scroll horizontally as needed. The copy control reports success or fallback through a status region; Lucide Copy crossfades to Check on success. Reduced motion retains a short opacity-only confirmation (160ms), with no icon scale movement. FAQ rows use native details and summary with a Lucide Plus rotating 45 degrees when open, fine dividers, and no card shadow. Supporting browsers progressively animate disclosure height through `interpolate-size: allow-keywords`; browsers without it keep native disclosure behavior. Reduced motion removes the rotation transition. No text input or chip system exists on this surface.

## Do's and Don'ts

### Do:

- **Do** retain the citron, pool, and mulberry identity.
- **Do** use the existing real demo and its poster as product evidence.
- **Do** keep all workflow instructions readable without animation.
- **Do** preserve visible keyboard focus and native video controls.

### Don't:

- **Don't** return to the rejected warm paper and recording red palette.
- **Don't** add generated raster artwork or invented social proof.
- **Don't** require pinned scrolling on mobile or with reduced motion.
- **Don't** extend website styling into the CLI without a separate decision.
