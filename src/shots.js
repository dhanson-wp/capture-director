// Shot lists: load, apply defaults, record, and post-process into clips.

import { mkdir, readFile, writeFile, access } from 'node:fs/promises';
import path from 'node:path';
import { recordShot, withBrowser } from './record.js';
import { remember } from './library.js';
import { renderCursor } from './browser.js';
import { zoomPlan, zoomFilter, cursorExprs, pressedEnable, ZOOM_DEFAULTS } from './effects.js';
import { ffmpeg, finite, loadYaml, log, merge, parseSize, probe, resolveFrom, safeId } from './util.js';

const PRESETS = ['ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow', 'placebo'];

export const SHOT_DEFAULTS = {
	viewport: { width: 1440, height: 810 },
	scale: 4 / 3, // deviceScaleFactor: 1440x810 CSS px becomes 1920x1080 device px
	output: '1920x1080',
	quality: 95,
	fps: 30,
	crf: 16,
	preset: 'slow',
	tail: 800,
	hideScrollbars: true,
	cursor: { enabled: true, size: 1 },
	zoom: ZOOM_DEFAULTS,
};

export async function loadShots(file) {
	const doc = await loadYaml(file);
	const defaults = merge(SHOT_DEFAULTS, doc.defaults || {});
	const outDir = resolveFrom(file, doc.out || 'out');
	const shots = (doc.shots || []).map((s, i) => {
		const shot = merge(defaults, s);
		shot.id = safeId(s.id || `shot-${i + 1}`);
		shot.source = file;
		shot.project = doc.project || path.basename(path.dirname(path.resolve(file)));
		if (typeof shot.zoom === 'boolean') shot.zoom = { ...defaults.zoom, enabled: shot.zoom };
		if (typeof shot.cursor === 'boolean') shot.cursor = { ...defaults.cursor, enabled: shot.cursor };
		if (!shot.url) throw new Error(`Shot ${shot.id} has no url`);
		// Web pages only. A file: URL would record whatever local file it names.
		if (!/^https?:\/\//i.test(shot.url)) throw new Error(`Shot ${shot.id}: url must start with http:// or https://`);
		shot.fps = finite(shot.fps, `${shot.id} fps`, { min: 1, max: 120 });
		shot.crf = finite(shot.crf, `${shot.id} crf`, { min: 0, max: 51 });
		shot.quality = finite(shot.quality, `${shot.id} quality`, { min: 1, max: 100 });
		shot.scale = finite(shot.scale, `${shot.id} scale`, { min: 0.5, max: 4 });
		if (!PRESETS.includes(shot.preset)) throw new Error(`Shot ${shot.id}: unknown preset "${shot.preset}"`);
		return shot;
	});
	return { file, outDir, shots };
}

function pick(shots, only) {
	if (!only) return shots;
	const ids = only.split(',');
	const picked = shots.filter((s) => ids.includes(s.id));
	if (!picked.length) throw new Error(`No shots match --only ${only}`);
	return picked;
}

export async function record(file, { only } = {}) {
	const { outDir, shots } = await loadShots(file);
	const results = [];
	for (const shot of pick(shots, only)) {
		const dir = path.join(outDir, shot.id);
		await mkdir(dir, { recursive: true });
		await withBrowser((browser) => recordShot(browser, shot, dir), { scale: shot.scale });
		results.push(await withBrowser((browser) => processShot(browser, shot, dir)));
	}
	return results;
}

// Re-run zoom and cursor on existing captures, without re-recording.
export async function processAll(file, { only } = {}) {
	const { outDir, shots } = await loadShots(file);
	const results = [];
	await withBrowser(async (browser) => {
		for (const shot of pick(shots, only)) results.push(await processShot(browser, shot, path.join(outDir, shot.id)));
	});
	return results;
}

export async function processShot(browser, shot, dir) {
	const capPath = path.join(dir, 'capture.json');
	await access(capPath).catch(() => {
		throw new Error(`${shot.id}: no capture at ${dir}; run record first`);
	});
	const cap = JSON.parse(await readFile(capPath, 'utf8'));
	// capture.json lands in the filter graph, so check it as carefully as the YAML.
	cap.duration = finite(cap.duration, `${shot.id} capture duration`, { min: 0 });
	const first = await probe(path.join(dir, 'frames', '000000.jpg'));
	const W = first.width;
	const H = first.height;
	const k = W / cap.viewport.width; // CSS px to device px
	const fps = shot.fps;
	const [OW, OH] = parseSize(shot.output);

	const scaleBox = (f) => f && { x: f.x * k, y: f.y * k, w: f.w * k, h: f.h * k };
	const events = cap.events.filter((e) => e.x !== undefined).map((e) => ({ ...e, x: e.x * k, y: e.y * k, focus: scaleBox(e.focus) }));
	const plan = zoomPlan(events, { W, H, duration: cap.duration }, shot.zoom);
	const zoom = zoomFilter(plan, { W, H, fps });

	// Safe mode (the default) only accepts plain relative names, which is all the recorder writes.
	const inputs = ['-f', 'concat', '-i', path.join(dir, 'frames', 'list.ffconcat')];
	// The concat demuxer can run long on the held last frame, so trim to the real length.
	const chain = [`[0:v]fps=${fps},trim=duration=${cap.duration},setpts=PTS-STARTPTS,format=yuv420p[b0]`];
	let last = 'b0';

	if (shot.cursor.enabled) {
		const size = shot.cursor.size ?? 1;
		const hot = await renderCursor(browser, path.join(dir, 'cursor.png'), { scale: k, size });
		await renderCursor(browser, path.join(dir, 'cursor-pressed.png'), { scale: k, size, pressed: true });
		inputs.push('-loop', '1', '-framerate', String(fps), '-i', path.join(dir, 'cursor.png'));
		inputs.push('-loop', '1', '-framerate', String(fps), '-i', path.join(dir, 'cursor-pressed.png'));
		const moves = cap.moves.map((m) => ({ ...m, x0: m.x0 * k, y0: m.y0 * k, x1: m.x1 * k, y1: m.y1 * k }));
		const pos = cursorExprs({ moves, start: cap.cursorStart.map((v) => v * k), hotspot: hot });
		const pressed = pressedEnable(cap.presses);
		const ov = (img, enable) => `overlay=x='${pos.x}':y='${pos.y}':shortest=1:format=auto${enable ? `:enable='${enable}'` : ''}`;
		if (pressed) {
			chain.push(`[b0][1:v]${ov(1, `not(${pressed})`)}[b1]`, `[b1][2:v]${ov(2, pressed)}[b2]`);
			last = 'b2';
		} else {
			chain.push(`[b0][1:v]${ov(1)}[b1]`);
			last = 'b1';
		}
	}

	const scale = `scale=${OW}:${OH}:flags=lanczos:out_color_matrix=bt709:out_range=tv,setsar=1,format=yuv420p`;
	chain.push(`[${last}]${zoom ? `${zoom},` : ''}${scale}[v]`);

	const graphFile = path.join(dir, 'filter.txt');
	await writeFile(graphFile, chain.join(';\n'));
	await writeFile(path.join(dir, 'zoom-plan.json'), JSON.stringify(plan, null, 2));

	const out = path.join(dir, `${shot.id}.mp4`);
	log(`${shot.id}: rendering ${plan.transitions.length} zoom moves, cursor ${shot.cursor.enabled ? 'on' : 'off'}`);
	await ffmpeg([
		...inputs,
		'-/filter_complex', graphFile,
		'-map', '[v]',
		'-r', String(fps), '-fps_mode', 'cfr',
		'-c:v', 'libx264', '-preset', shot.preset, '-crf', String(shot.crf), '-pix_fmt', 'yuv420p',
		'-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
		'-movflags', '+faststart',
		out,
	]);
	const info = await probe(out);
	log(`${shot.id}: wrote ${out} (${info.width}x${info.height}, ${info.duration.toFixed(2)}s)`);
	if (shot.source) await remember(out, { kind: 'clip', title: shot.id, project: shot.project, source: shot.source, shot: shot.id });
	return { id: shot.id, file: out, ...info, zooms: plan.groups.length };
}
