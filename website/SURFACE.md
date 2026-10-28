# Marketing homepage

Mode: Persuade. Goal: watch the real result, understand the local workflow, and download the source from GitHub. Primary audience: builders using Codex or Claude Code. No invented social proof.

## Direction contract

THESIS: A working film treatment turns a short set of directions into a polished website demo. The real video owns the opening.

OWN-WORLD: Citron #e5d935, pool blue #d4e9ed, and mulberry #4c1637. Bricolage Grotesque display with Manrope body, oversized titles, broad color fields, viewfinder corners, and editing rules. Derek explicitly rejected the initial warm neutral/red palette.

STORY: See the 31-second example, scroll through write/record/render, then follow the exact installation steps. Technical constraints stay explicit.

FIRST VIEWPORT: Oversized “You built it. Now roll.” title on citron at left, short explanation and GitHub action at right, then a large inset video on mulberry. A thin timeline links footage and shot list. Signature: a pinned sequence moves a synthetic cursor and reframes actual footage as the shot list advances.

FORM: Film treatment, candidate 7; seed:b6eea4233bde2780. Derek approved code-first Astro implementation.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Motion refinement

Derek approved the brand, colors, and existing logo on October 27, 2026. Preserve the logo file. All other icons come from Lucide's Astro package.

The rare-visit marketing sequence uses motion for explanation and delight: clipped film-title lines, a converging viewfinder, shot-list emphasis, cursor press, and export confirmation. Supporting rules draw as their content arrives; the terminal settles into place. Controls use CSS feedback at 160–200ms with Emil Kowalski's strong ease-out. GSAP retains the scroll timeline. Mobile gets a short unpinned version; reduced motion restores static content and keeps state feedback. No looping animation, autoplay, or sound.

Reference: local Emil Animate skill in the Worth a Fork source archive, originally https://github.com/emilkowalski/skills/tree/main/skills/animate.

## Motion correction and scroll narrative

Derek rejected the font jump, bouncing controls, and decorative feel of the prior refinement. Title lettering is now static. Fonts preload and block a fallback swap; GSAP initializes after font readiness. Controls and their icons have no independent transforms. Hover/press use surface feedback only.

The four-part scroll story is the motion focus: illustrative shot list, actual scroll-scrubbed demo footage, an illustrative editing timeline assembled from four real extracted frames, then export. Scrubbing is reversible. Video uses frequent keyframes, seeks only when ready, and loads near the section. Mobile has no pin; reduced motion keeps readable steps and static source. Short laptop viewports use a compact composition.
