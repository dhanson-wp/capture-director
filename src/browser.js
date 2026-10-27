import { chromium } from 'playwright-core';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

// System Chrome, headless, no profile: every run is logged out.
// For recording, pass the shot's scale. The CDP screencast only delivers
// device pixels when Chrome itself runs at that scale factor; Playwright's
// deviceScaleFactor emulation alone yields frames at CSS size (1440x810).
export async function launch({ scale } = {}) {
	const args = ['--hide-scrollbars', '--force-color-profile=srgb', '--font-render-hinting=none'];
	if (scale) args.push(`--force-device-scale-factor=${scale}`);
	// CD_CHROME_CHANNEL=bundled uses Playwright's cached chromium-headless-shell instead.
	const channel = process.env.CD_CHROME_CHANNEL || 'chrome';
	return chromium.launch({ ...(channel === 'bundled' ? {} : { channel }), headless: true, args });
}

// A clean macOS-style arrow. The tip (hotspot) sits at (4, 3) in CSS px.
const CURSOR_SVG = (pressed) => `
<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
  <defs>
    <filter id="s" x="-50%" y="-50%" width="200%" height="200%">
      <feDropShadow dx="0" dy="1.2" stdDeviation="1.3" flood-color="#000" flood-opacity="0.45"/>
    </filter>
  </defs>
  <g filter="url(#s)" transform="${pressed ? 'translate(4 3) scale(0.86) translate(-4 -3)' : ''}">
    <path d="M4 3 L4 23.5 L9.2 18.6 L12.6 26.4 L16.2 24.9 L12.8 17.2 L19.8 17.2 Z"
      fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/>
  </g>
</svg>`;

export const CURSOR_HOTSPOT = [4, 3];

export async function renderCursor(browser, file, { scale = 1, pressed = false, size = 1 } = {}) {
	const page = await browser.newPage({ viewport: { width: 32, height: 32 }, deviceScaleFactor: scale * size });
	await page.setContent(`<style>html,body{margin:0;background:transparent}</style>${CURSOR_SVG(pressed)}`);
	await page.screenshot({ path: file, omitBackground: true });
	await page.close();
	return [CURSOR_HOTSPOT[0] * scale * size, CURSOR_HOTSPOT[1] * scale * size];
}

// Fonts are embedded as data URLs, so a local file or a URL both work.
async function fontFace(font) {
	if (!font) return '';
	let buf;
	if (/^https?:\/\//.test(font)) {
		const res = await fetch(font);
		if (!res.ok) throw new Error(`Font fetch failed: ${font} (${res.status})`);
		buf = Buffer.from(await res.arrayBuffer());
	} else {
		buf = await readFile(font);
	}
	const ext = path.extname(font.split('?')[0]).slice(1).toLowerCase();
	const fmt = { ttf: 'truetype', otf: 'opentype', woff: 'woff', woff2: 'woff2' }[ext] || 'truetype';
	const mime = { ttf: 'font/ttf', otf: 'font/otf', woff: 'font/woff', woff2: 'font/woff2' }[ext] || 'font/ttf';
	return `@font-face{font-family:"CardFont";src:url(data:${mime};base64,${buf.toString('base64')}) format("${fmt}");font-weight:100 900;font-stretch:50% 200%;}`;
}

const esc = (s = '') => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

// Render a title or end card to a PNG at the output size.
export async function renderCard(browser, file, card, { width, height }) {
	const c = {
		background: '#141312',
		color: '#f2efe9',
		muted: 'rgba(242,239,233,0.62)',
		align: 'center',
		titleSize: 112,
		subtitleSize: 34,
		kickerSize: 22,
		weight: 500,
		stretch: '100%',
		...card,
	};
	const family = `${c.font ? '"CardFont",' : ''}${c.fontFamily ? `${c.fontFamily},` : ''}"Helvetica Neue",Helvetica,Arial,sans-serif`;
	const monoFamily = `${c.monoFont ? '"CardMono",' : ''}${c.monoFamily ? `${c.monoFamily},` : ''}ui-monospace,Menlo,monospace`;
	const face = await fontFace(c.font);
	const mono = c.monoFont ? (await fontFace(c.monoFont)).replace('"CardFont"', '"CardMono"') : '';
	const html = `<!doctype html><meta charset="utf-8"><style>
${face}${mono}
html,body{margin:0;width:${width}px;height:${height}px;background:${c.background};color:${c.color};overflow:hidden}
body{display:flex;flex-direction:column;justify-content:center;align-items:${c.align === 'left' ? 'flex-start' : 'center'};
  text-align:${c.align};padding:0 ${Math.round(width * 0.1)}px;box-sizing:border-box;font-family:${family};
  -webkit-font-smoothing:antialiased;text-rendering:geometricPrecision}
.kicker{font-family:${monoFamily};font-size:${c.kickerSize}px;letter-spacing:.08em;text-transform:uppercase;color:${c.muted};margin:0 0 28px}
h1{font-size:${c.titleSize}px;line-height:1.02;font-weight:${c.weight};font-stretch:${c.stretch};letter-spacing:-0.02em;margin:0;max-width:16em}
p{font-size:${c.subtitleSize}px;line-height:1.35;color:${c.muted};margin:32px 0 0;max-width:30em}
.url{font-family:${monoFamily};font-size:${c.subtitleSize * 0.9}px;color:${c.color};margin-top:44px;letter-spacing:.01em}
</style>
${c.kicker ? `<div class="kicker">${esc(c.kicker)}</div>` : ''}
${c.title ? `<h1>${esc(c.title)}</h1>` : ''}
${c.subtitle ? `<p>${esc(c.subtitle)}</p>` : ''}
${c.url ? `<div class="url">${esc(c.url)}</div>` : ''}`;
	const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
	await page.setContent(html);
	await page.evaluate(() => document.fonts.ready);
	await page.screenshot({ path: file });
	await page.close();
}

// A caption overlay: transparent full-frame PNG with one or two short lines,
// placed in a corner like a lower-third label.
export async function renderCaption(browser, file, cap, { width, height }) {
	const c = {
		position: 'bottom-left',
		color: '#ffffff',
		opacity: 0.7,
		size: 30,
		margin: 72,
		weight: 400,
		shadow: true,
		plate: null, // e.g. "rgba(0,0,0,0.55)" for a backing behind busy footage
		...cap,
	};
	const family = `${c.font ? '"CardFont",' : ''}${c.fontFamily ? `${c.fontFamily},` : ''}ui-monospace,Menlo,monospace`;
	const plate = c.plate ? `background:${c.plate};padding:${Math.round(c.size * 0.45)}px ${Math.round(c.size * 0.7)}px;border-radius:${Math.round(c.size * 0.25)}px;` : '';
	const face = await fontFace(c.font);
	const [v, h] = c.position.split('-');
	const html = `<!doctype html><meta charset="utf-8"><style>
${face}
html,body{margin:0;width:${width}px;height:${height}px;background:transparent;overflow:hidden}
.cap{position:absolute;${v === 'top' ? 'top' : 'bottom'}:${c.margin}px;${h === 'right' ? 'right' : 'left'}:${c.margin}px;
  max-width:${Math.round(width * 0.6)}px;font-family:${family};font-size:${c.size}px;line-height:1.4;font-weight:${c.weight};
  color:${c.color};opacity:${c.opacity};text-align:${h === 'right' ? 'right' : 'left'};letter-spacing:.01em;${plate}
  -webkit-font-smoothing:antialiased;${c.shadow && !c.plate ? 'text-shadow:0 1px 12px rgba(0,0,0,.35)' : ''}}
</style><div class="cap">${esc(c.text).replace(/\n/g, '<br>')}</div>`;
	const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
	await page.setContent(html);
	await page.evaluate(() => document.fonts.ready);
	await page.screenshot({ path: file, omitBackground: true });
	await page.close();
}
