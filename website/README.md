# Capture director website

Astro marketing page for Capture director, with GSAP ScrollTrigger and self-hosted Bricolage Grotesque and Manrope fonts.

```sh
npm ci
npm run dev
npm run build
npm run preview
```

Publish only `dist/` to Spacefast. The CLI source at the repository root is independent of this site.

## Demo asset

The website serves the existing `docs/demo.mp4` as `/demo.mp4` so playback doesn't depend on a GitHub attachment redirect. Video binaries stay ignored by Git. Before building from a fresh checkout, copy the approved finished demo to `public/demo.mp4` from your local media archive. `public/demo-poster.png` is the repository's existing poster. No original footage, render projects, or music beds are included.

## Design references

Mobbin references: [Tines](https://mobbin.com/sites/sections/c7058e8a-dd2e-4be9-a940-cf8bafb296a5), for a prominent product tour, and [Grain](https://mobbin.com/sites/sections/707379bd-de88-41d2-90b5-069e476a139c), for generous video spacing. The final citron, pool-blue, and mulberry identity is original to this page.

## Motion and accessibility

GSAP uses a scroll-linked write/record/render sequence on desktop. Mobile and reduced-motion preferences receive a static, readable workflow. The real demo always requires a click to play. Native video controls, keyboard focus styles, native FAQ disclosures, and a copy-status live region are provided.

## Search and answers

Static HTML contains descriptive copy, requirements, and six FAQs. JSON-LD describes the software and matches the visible FAQs. `llms.txt` supplies a compact source-linked overview. A private review deployment isn't indexable by public search engines. Configure the final public hostname and canonical/social URLs before public launch.

## Animation refinement

Motion follows Emil Kowalski's Animate guidance: explanation on the marketing sequence, fast CSS press/state feedback, strong documented easing, hover gating, and reduced-motion alternatives. GSAP handles the scroll orchestration. All 23 non-logo SVG icons are from `@lucide/astro`; the original site logo remains unchanged.

### Scroll-story media

`public/story.mp4` is a 1280px, silent, frequent-keyframe derivative of the existing finished demo for responsive scroll seeking. It remains Git-ignored. Four JPEGs in `public/story/` are real frame extractions at 2, 8, 15, and 24 seconds of `docs/demo.mp4`, used in the illustrative editing timeline. They are website assets, not original footage or a video-production project. The original site logo is unchanged.

The title no longer animates or changes transforms on load. Preloaded, self-hosted fonts avoid a visible fallback swap. Buttons and icons stay anchored, with surface feedback on hover and press. The four scroll chapters replace the earlier decorative sequence.

## Public launch metadata

Public viewing was explicitly approved on October 27, 2026. SEO title: “Capture director | Open-source website demo videos”. Description and Open Graph/Twitter metadata match. `/og-image.png` is a 1200 × 630 PNG rendered from `social-image.astro` using the unchanged approved icon, wordmark, palette, and self-hosted fonts. The template is development source, not a second published page.
