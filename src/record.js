// Recorder: drives system Chrome with Playwright, captures every compositor
// frame with the CDP screencast, and logs cursor moves, clicks, and hovers
// with real timestamps for post-production.

import { mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { launch } from './browser.js';
import { ease, log, sleep } from './util.js';

const PRIMARY = ['wait', 'waitFor', 'click', 'hover', 'move', 'camera', 'press', 'type', 'scroll', 'scrollTo', 'eval', 'hide', 'css', 'waitForImages'];

// `- click: "#a"` and `- click: { target: "#a", zoom: 2 }` both become
// { kind: 'click', target: '#a', zoom: 2 }.
export function normalizeStep(step) {
	if (typeof step === 'number') return { kind: 'wait', ms: step };
	const kind = PRIMARY.find((k) => k in step);
	if (!kind) throw new Error(`Unknown step: ${JSON.stringify(step)}`);
	const { [kind]: value, ...rest } = step;
	const out = { kind, ...rest };
	if (value && typeof value === 'object' && !Array.isArray(value)) Object.assign(out, value);
	else if (kind === 'wait') out.ms = Number(value);
	else if (kind === 'press') out.key = value;
	else if (kind === 'eval' || kind === 'css') out.code = value;
	else if (kind === 'hide') out.selectors = [].concat(value);
	else if (kind === 'move' && Array.isArray(value)) out.point = value;
	else if (kind === 'type') out.text = value;
	else if (kind === 'scroll' && typeof value === 'number') out.by = value;
	else out.target = value;
	return out;
}

class Session {
	constructor(page, shot) {
		this.page = page;
		this.shot = shot;
		this.mouse = shot.cursor.start ? [...shot.cursor.start] : [shot.viewport.width * 0.62, shot.viewport.height * 0.72];
		this.events = [];
		this.moves = [];
		this.presses = [];
	}

	now() {
		return Date.now() / 1000;
	}

	async point(step) {
		if (step.point) return step.point;
		const target = step.target ?? step.to;
		if (Array.isArray(target)) return target;
		let loc = this.page.locator(target).first();
		if (step.inView) {
			// The first match that sits fully inside the viewport, wherever the page has scrolled.
			const { width, height } = this.shot.viewport;
			const index = await this.page.locator(target).evaluateAll(
				(els, [w, h, skip]) =>
					els.map((e) => e.getBoundingClientRect()).findIndex((r, i) => r.width > 0 && r.top >= 0 && r.left >= 0 && r.bottom <= h && r.right <= w && i >= 0 && (skip-- <= 0)),
				[width, height, step.skip ?? 0],
			);
			if (index < 0) throw new Error(`No ${target} fully in view`);
			loc = this.page.locator(target).nth(index);
		}
		await loc.waitFor({ state: 'visible', timeout: step.timeout ?? 10000 });
		const box = await loc.boundingBox();
		if (!box) throw new Error(`No box for ${target}`);
		const [ox, oy] = step.offset || [0, 0];
		const p = [box.x + box.width / 2 + ox, box.y + box.height / 2 + oy];
		const { width, height } = this.shot.viewport;
		if (p[0] < 0 || p[1] < 0 || p[0] > width || p[1] > height) {
			log(`warning: ${target} is outside the viewport at ${p.map(Math.round)}; scroll to it first`);
		}
		return p;
	}

	// Optional zoom framing: one or more selectors (their union box) or a point.
	async focus(step) {
		const z = step.zoomOn;
		if (!z) return undefined;
		if (Array.isArray(z) && typeof z[0] === 'number') return { x: z[0], y: z[1], w: 0, h: 0 };
		const boxes = [];
		for (const sel of [].concat(z)) {
			const box = await this.page.locator(sel).first().boundingBox();
			if (box) boxes.push(box);
		}
		if (!boxes.length) return undefined;
		const x0 = Math.min(...boxes.map((b) => b.x));
		const y0 = Math.min(...boxes.map((b) => b.y));
		const x1 = Math.max(...boxes.map((b) => b.x + b.width));
		const y1 = Math.max(...boxes.map((b) => b.y + b.height));
		return { x: (x0 + x1) / 2, y: (y0 + y1) / 2, w: x1 - x0, h: y1 - y0 };
	}

	// Eased, frame-paced mouse move; logged as one segment for the cursor overlay.
	async moveTo([x, y], duration) {
		const [x0, y0] = this.mouse;
		if (Math.hypot(x - x0, y - y0) < 0.5) return;
		const ms = duration ?? Math.min(900, 380 + Math.hypot(x - x0, y - y0) * 0.45);
		const t0 = this.now();
		for (;;) {
			const p = Math.min(1, (this.now() - t0) / (ms / 1000));
			const e = ease(p);
			await this.page.mouse.move(x0 + (x - x0) * e, y0 + (y - y0) * e);
			if (p >= 1) break;
			await sleep(12);
		}
		this.moves.push({ t0, t1: t0 + ms / 1000, x0, y0, x1: x, y1: y });
		this.mouse = [x, y];
	}

	async smoothScroll(step) {
		const duration = step.duration ?? 1200;
		// Resolve the target with Playwright, so `text=...` and other selectors work here too.
		const sel = step.to ?? step.target;
		let target = null;
		if (sel) {
			const box = await this.page.locator(sel).first().boundingBox();
			if (!box) throw new Error(`scroll: no box for ${sel}`);
			target = { top: box.y, height: box.height };
		}
		await this.page.evaluate(
			async ({ by, target, block, offset, duration }) => {
				const start = window.scrollY;
				let end = start + (by || 0);
				if (target) {
					const r = target;
					const top = r.top + start;
					end = block === 'start' ? top : block === 'end' ? top + r.height - innerHeight : top + r.height / 2 - innerHeight / 2;
				}
				end = Math.max(0, Math.min(end + (offset || 0), document.documentElement.scrollHeight - innerHeight));
				const ease = (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
				const t0 = performance.now();
				await new Promise((done) => {
					const tick = (now) => {
						const p = Math.min(1, (now - t0) / duration);
						window.scrollTo(0, start + (end - start) * ease(p));
						p < 1 ? requestAnimationFrame(tick) : done();
					};
					requestAnimationFrame(tick);
				});
			},
			{ by: step.by, target, block: step.block ?? 'center', offset: step.offset, duration },
		);
	}

	// Steps that work the same in setup and in the recorded action list.
	async common(step) {
		const { page } = this;
		switch (step.kind) {
			case 'wait':
				return sleep(step.ms);
			case 'waitFor':
				return page.locator(step.target).first().waitFor({ state: step.state ?? 'visible', timeout: step.timeout ?? 15000 });
			case 'eval':
				return page.evaluate(step.code);
			case 'css':
				return page.addStyleTag({ content: step.code });
			case 'hide':
				return page.addStyleTag({ content: `${step.selectors.join(',')}{display:none!important}` });
			case 'waitForImages':
				return page.evaluate(async (timeout) => {
					const visible = [...document.images].filter((img) => {
						const r = img.getBoundingClientRect();
						return r.bottom > -200 && r.top < innerHeight + 200 && r.width > 0;
					});
					const ready = (img) =>
						img.complete
							? img.decode().catch(() => {})
							: new Promise((r) => {
									img.addEventListener('load', r, { once: true });
									img.addEventListener('error', r, { once: true });
								});
					await Promise.race([Promise.all(visible.map(ready)), new Promise((r) => setTimeout(r, timeout))]);
				}, step.timeout ?? 10000);
			default:
				return undefined;
		}
	}

	async setup(step) {
		const { page } = this;
		switch (step.kind) {
			case 'scrollTo':
			case 'scroll':
				if (step.by && !step.target && !step.to) return page.evaluate((y) => window.scrollBy(0, y), step.by);
				return this.smoothScroll({ ...step, duration: 1 });
			case 'click':
				return page.locator(step.target).first().click({ timeout: step.timeout ?? 10000 });
			case 'hover':
				return page.locator(step.target).first().hover();
			case 'press':
				return page.keyboard.press(step.key);
			case 'type':
				return page.locator(step.target).first().fill(step.text);
			default:
				return this.common(step);
		}
	}

	async action(step) {
		const { page } = this;
		switch (step.kind) {
			case 'move':
				return this.moveTo(await this.point(step), step.duration);
			case 'hover': {
				const p = await this.point(step);
				const focus = await this.focus(step);
				await this.moveTo(p, step.duration);
				this.events.push({ type: 'hover', t: this.now(), x: p[0], y: p[1], zoom: step.zoom, focus, target: step.target });
				if (step.hold) await sleep(step.hold);
				return;
			}
			case 'click': {
				const p = await this.point(step);
				const focus = await this.focus(step);
				await this.moveTo(p, step.duration);
				await sleep(step.settle ?? 140);
				const t0 = this.now();
				await page.mouse.down();
				this.events.push({ type: 'click', t: t0, x: p[0], y: p[1], zoom: step.zoom, focus, target: step.target });
				await sleep(90);
				await page.mouse.up();
				this.presses.push({ t0, t1: this.now() + 0.06 });
				if (step.hold) await sleep(step.hold);
				return;
			}
			case 'camera': {
				// A camera move with no cursor: push in on a target and (by default) stay there.
				const target = step.target ?? step.on;
				const focus = await this.focus({ zoomOn: target });
				if (!focus) throw new Error(`camera: no box for ${JSON.stringify(target)}`);
				this.events.push({
					type: 'camera',
					t: this.now(),
					x: focus.x,
					y: focus.y,
					focus: step.fit === false ? undefined : focus,
					zoom: step.zoom,
					ramp: (step.duration ?? 3000) / 1000,
					hold: step.hold === undefined ? null : step.hold / 1000,
					target,
				});
				return undefined;
			}
			case 'press':
				this.events.push({ type: 'key', t: this.now(), key: step.key });
				return page.keyboard.press(step.key);
			case 'type':
				if (step.target) await page.locator(step.target).first().focus();
				return page.keyboard.type(step.text, { delay: step.delay ?? 70 });
			case 'scroll':
			case 'scrollTo':
				this.events.push({ type: 'scroll', t: this.now() });
				return this.smoothScroll(step);
			default:
				return this.common(step);
		}
	}
}

// CSS applied to every page a shot loads, including pages reached by clicking.
export function pageStyles(shot) {
	let css = '';
	// WordPress.com sites can show these bars to logged-out visitors on Automattic's proxy.
	if (shot.hideWpBars !== false) css += '#wpadminbar,#atomic-proxy-bar{display:none!important}html,body{margin-top:0!important}';
	if (shot.hideScrollbars !== false) css += '::-webkit-scrollbar{display:none!important}html{scrollbar-width:none!important}';
	return css;
}

export async function recordShot(browser, shot, dir) {
	const frameDir = path.join(dir, 'frames');
	await rm(frameDir, { recursive: true, force: true });
	await mkdir(frameDir, { recursive: true });

	const context = await browser.newContext({
		viewport: shot.viewport,
		deviceScaleFactor: shot.scale,
		colorScheme: shot.colorScheme,
		reducedMotion: shot.reducedMotion,
	});
	// An init script rather than addStyleTag, so the styles survive navigation. A bar that
	// appears late on a second page would otherwise shift the layout under the next click.
	// Client-side routers (WordPress's Interactivity API router, for one) swap pages in place
	// and disable stylesheets the next page doesn't list, so the style re-enables itself.
	const css = pageStyles(shot);
	if (css) {
		await context.addInitScript((text) => {
			const style = document.createElement('style');
			style.textContent = text;
			const keep = () => {
				if (!document.documentElement) return;
				if (!style.isConnected) document.documentElement.appendChild(style);
				if (style.disabled) style.disabled = false;
			};
			keep();
			new MutationObserver(keep).observe(document, { childList: true, subtree: true });
		}, css);
	}
	const page = await context.newPage();
	const s = new Session(page, shot);

	log(`${shot.id}: loading ${shot.url}`);
	await page.goto(shot.url, { waitUntil: shot.waitUntil ?? 'networkidle', timeout: 60000 });
	for (const raw of shot.setup || []) await s.setup(normalizeStep(raw));
	// Park the pointer only when the shot uses it. A pointer resting on the page
	// can trigger hover states, such as a carousel that pauses under the pointer.
	if (shot.cursor.enabled || shot.cursor.start) await page.mouse.move(...s.mouse);
	await sleep(shot.settle ?? 400);

	// Capture.
	const cdp = await context.newCDPSession(page);
	const frames = [];
	const writes = [];
	let firstFrame;
	const gotFirst = new Promise((r) => (firstFrame = r));
	cdp.on('Page.screencastFrame', (f) => {
		cdp.send('Page.screencastFrameAck', { sessionId: f.sessionId }).catch(() => {});
		const i = frames.length;
		const file = path.join(frameDir, `${String(i).padStart(6, '0')}.jpg`);
		frames.push({ file, ts: f.metadata.timestamp });
		writes.push(writeFile(file, Buffer.from(f.data, 'base64')));
		if (i === 0) firstFrame();
	});
	// Without maxWidth/maxHeight the screencast arrives at CSS size, not device pixels.
	await cdp.send('Page.startScreencast', {
		format: 'jpeg',
		quality: shot.quality,
		everyNthFrame: 1,
		maxWidth: Math.round(shot.viewport.width * shot.scale),
		maxHeight: Math.round(shot.viewport.height * shot.scale),
	});
	// A static page may not emit a frame on its own; nudge the compositor.
	const nudge = setTimeout(() => page.evaluate(() => (document.body.style.outline = '0 solid transparent')).catch(() => {}), 300);
	await Promise.race([gotFirst, sleep(3000)]);
	clearTimeout(nudge);
	if (!frames.length) throw new Error(`${shot.id}: screencast produced no frames`);
	// Guard against short or CSS-size frames, which would stretch when scaled to the output.
	const want = [Math.round(shot.viewport.width * shot.scale), Math.round(shot.viewport.height * shot.scale)];
	const got = await frameSize(frames[0], writes[0]);
	if (got[0] !== want[0] || got[1] !== want[1]) {
		await cdp.send('Page.stopScreencast').catch(() => {});
		throw new Error(`${shot.id}: screencast frames are ${got.join('x')}, expected ${want.join('x')}. Try CD_CHROME_CHANNEL=bundled`);
	}

	log(`${shot.id}: recording ${shot.actions?.length ?? 0} actions`);
	for (const raw of shot.actions || []) await s.action(normalizeStep(raw));
	await sleep(shot.tail ?? 800);
	const end = Date.now() / 1000;
	await cdp.send('Page.stopScreencast');
	await Promise.all(writes);
	await context.close();

	// Real frame durations from compositor timestamps.
	const t0 = frames[0].ts;
	const duration = end - t0;
	const lines = ['ffconcat version 1.0'];
	frames.forEach((f, i) => {
		const next = i + 1 < frames.length ? frames[i + 1].ts : end;
		lines.push(`file '${path.basename(f.file)}'`, `duration ${Math.max(0.001, next - f.ts).toFixed(6)}`);
	});
	lines.push(`file '${path.basename(frames[frames.length - 1].file)}'`);
	await writeFile(path.join(frameDir, 'list.ffconcat'), lines.join('\n') + '\n');

	const rel = (t) => Number((t - t0).toFixed(4));
	const meta = {
		id: shot.id,
		url: shot.url,
		viewport: shot.viewport,
		scale: shot.scale,
		frames: frames.length,
		duration: Number(duration.toFixed(4)),
		avgFps: Number((frames.length / duration).toFixed(2)),
		cursorStart: shot.cursor.start || [shot.viewport.width * 0.62, shot.viewport.height * 0.72],
		events: s.events.map((e) => ({ ...e, t: rel(e.t) })),
		moves: s.moves.map((m) => ({ ...m, t0: rel(m.t0), t1: rel(m.t1) })),
		presses: s.presses.map((p) => ({ t0: rel(p.t0), t1: rel(p.t1) })),
	};
	await writeFile(path.join(dir, 'capture.json'), JSON.stringify(meta, null, 2));
	log(`${shot.id}: ${frames.length} frames over ${meta.duration}s (${meta.avgFps} fps average, frames are held while the page is still)`);
	return meta;
}

// Width and height from a JPEG's SOF marker.
async function frameSize(frame, written) {
	await written;
	const buf = await readFile(frame.file);
	let i = 2;
	while (i < buf.length) {
		const marker = buf[i + 1];
		const len = buf.readUInt16BE(i + 2);
		if (marker >= 0xc0 && marker <= 0xc2) return [buf.readUInt16BE(i + 7), buf.readUInt16BE(i + 5)];
		i += 2 + len;
	}
	return [0, 0];
}

export async function withBrowser(fn, opts) {
	const browser = await launch(opts);
	try {
		return await fn(browser);
	} finally {
		await browser.close();
	}
}
