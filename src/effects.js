// Auto-zoom and cursor post-production, expressed as ffmpeg filter expressions.
//
// The recorder logs every click, hover, and cursor move with real timestamps.
// Here those logs become eased keyframes, and the keyframes become piecewise
// ffmpeg expressions. Zoom uses the perspective filter (sub-pixel, fixed output
// size, per-frame evaluation), which avoids the integer jitter zoompan has.

import { num } from './util.js';

export const ZOOM_DEFAULTS = {
	enabled: true,
	level: 1.6, // default zoom for an event
	max: 2.0, // cap for per-action overrides
	on: ['click', 'hover'], // which logged events trigger zooms
	lead: 0.25, // seconds before the event that the zoom is fully in
	ramp: 0.9, // zoom-in duration
	rampOut: 1.0, // zoom-out duration
	hold: 1.4, // seconds after the last event in a group before zooming out
	pan: 0.7, // pan duration between events inside one zoom group
	gap: 0.6, // zoom groups closer than this merge into one
	focus: [0.5, 0.5], // where the event sits inside the zoomed frame (0..1)
	padding: 0.12, // breathing room around a zoomOn box
};

const EASE = (p) => `if(lt(${p},0.5),4*pow(${p},3),1-pow(-2*${p}+2,3)/2)`;

// Build `value(T)` from sorted, non-overlapping eased segments.
// segs: [{ t0, t1, v0, v1 }], initial: value before the first segment.
export function piecewise(T, segs, initial, slot = 0) {
	let expr = num(segs.length ? segs[segs.length - 1].v1 : initial);
	for (let i = segs.length - 1; i >= 0; i--) {
		const s = segs[i];
		const before = i === 0 ? num(initial) : num(segs[i - 1].v1);
		const d = Math.max(1e-3, s.t1 - s.t0);
		const p = `ld(${slot})`;
		const lerp =
			s.v0 === s.v1
				? num(s.v1)
				: `(st(${slot},clip((${T}-${num(s.t0)})/${num(d)},0,1));${num(s.v0)}+(${num(s.v1 - s.v0)})*${EASE(p)})`;
		expr = `if(lt(${T},${num(s.t0)}),${before},if(lt(${T},${num(s.t1)}),${lerp},${expr}))`;
	}
	return expr;
}

// The zoomed view for one event. With a focus box (from `zoomOn`), the view
// centers on that box and backs off just enough to fit it with some padding.
function rectFor(ev, W, H, cfg) {
	let z = Math.min(cfg.max, Math.max(1, typeof ev.zoom === 'number' ? ev.zoom : cfg.level));
	let cx = ev.x;
	let cy = ev.y;
	let [fx, fy] = cfg.focus;
	if (ev.focus) {
		cx = ev.focus.x;
		cy = ev.focus.y;
		[fx, fy] = [0.5, 0.5];
		const pad = 1 + (cfg.padding ?? 0.12);
		if (ev.focus.w || ev.focus.h) z = Math.max(1, Math.min(z, W / (ev.focus.w * pad || 1), H / (ev.focus.h * pad || 1)));
	}
	const w = W / z;
	const h = H / z;
	const x = Math.min(W - w, Math.max(0, cx - w * fx));
	const y = Math.min(H - h, Math.max(0, cy - h * fy));
	return { x, y, w, z };
}

// Turn logged events into rectangle keyframe transitions.
// events: [{ type, t, x, y, zoom }] in source pixels and seconds from clip start.
export function zoomPlan(events, { W, H, duration }, cfg) {
	cfg = { ...ZOOM_DEFAULTS, ...cfg };
	const full = { x: 0, y: 0, w: W, z: 1 };
	// Explicit camera moves always apply; click and hover zooms follow `enabled` and `on`.
	const evs = events
		.filter((e) => e.type === 'camera' || (cfg.enabled && cfg.on.includes(e.type) && e.zoom !== false))
		.sort((a, b) => a.t - b.t)
		.map((e) => ({ ...e, rect: rectFor(e, W, H, cfg) }));

	const groups = [];
	for (const ev of evs) {
		const g = groups[groups.length - 1];
		const wouldStart = ev.t - cfg.lead - cfg.ramp;
		const camera = ev.type === 'camera' || g?.[0].type === 'camera';
		if (g && !camera && wouldStart < g[g.length - 1].t + cfg.hold + cfg.rampOut + cfg.gap) g.push(ev);
		else groups.push([ev]);
	}

	const transitions = [];
	let lastEnd = 0;
	for (const g of groups) {
		const first = g[0];
		const isCamera = first.type === 'camera';
		// Clicks are zoomed into ahead of time; a camera move starts when it's logged.
		const inStart = isCamera ? Math.max(lastEnd, first.t) : Math.max(lastEnd, first.t - cfg.lead - cfg.ramp);
		const inEnd = isCamera ? inStart + first.ramp : Math.max(inStart + 0.3, first.t - cfg.lead);
		transitions.push({ t0: inStart, t1: inEnd, from: full, to: first.rect });
		let cur = first.rect;
		lastEnd = inEnd;
		for (const ev of g.slice(1)) {
			const r = ev.rect;
			const moved = Math.hypot(r.x + r.w / 2 - (cur.x + cur.w / 2), r.y - cur.y) > W * 0.03 || Math.abs(r.w - cur.w) > 1;
			if (!moved) continue;
			let t1 = ev.t - cfg.lead;
			let t0 = Math.max(lastEnd, t1 - cfg.pan);
			if (t1 - t0 < 0.2) t1 = t0 + 0.2;
			transitions.push({ t0, t1, from: cur, to: r });
			cur = r;
			lastEnd = t1;
		}
		const last = g[g.length - 1];
		// A camera move holds to the end of the clip unless it sets its own hold.
		const hold = isCamera ? (first.hold ?? Infinity) : cfg.hold;
		const outStart = Math.max(lastEnd, (isCamera ? inEnd : last.t) + hold);
		if (outStart < duration - 0.1) {
			const outEnd = Math.min(duration, outStart + cfg.rampOut);
			transitions.push({ t0: outStart, t1: outEnd, from: cur, to: full });
			lastEnd = outEnd;
		} else {
			lastEnd = duration;
		}
	}
	return { transitions, groups };
}

// Filter that applies the zoom plan to a W x H stream whose frame count is `in`.
export function zoomFilter(plan, { W, H, fps }) {
	if (!plan.transitions.length) return null;
	const T = `(in/${fps})`;
	const seg = (k) => plan.transitions.map((s) => ({ t0: s.t0, t1: s.t1, v0: s.from[k], v1: s.to[k] }));
	const X = piecewise(T, seg('x'), 0, 0);
	const Y = piecewise(T, seg('y'), 0, 1);
	const Wd = piecewise(T, seg('w'), W, 2);
	const Hd = `(${Wd})*${num(H / W)}`;
	const q = (e) => `'${e}'`;
	return [
		'perspective=',
		`x0=${q(X)}:y0=${q(Y)}:`,
		`x1=${q(`${X}+${Wd}`)}:y1=${q(Y)}:`,
		`x2=${q(X)}:y2=${q(`${Y}+${Hd}`)}:`,
		`x3=${q(`${X}+${Wd}`)}:y3=${q(`${Y}+${Hd}`)}:`,
		'interpolation=cubic:eval=frame',
	].join('');
}

// Cursor position expressions over overlay's `t`, minus the image hotspot.
export function cursorExprs({ moves, start, hotspot }) {
	const sx = moves.map((m) => ({ t0: m.t0, t1: m.t1, v0: m.x0, v1: m.x1 }));
	const sy = moves.map((m) => ({ t0: m.t0, t1: m.t1, v0: m.y0, v1: m.y1 }));
	return {
		x: `${piecewise('t', sx, start[0], 0)}-${num(hotspot[0])}`,
		y: `${piecewise('t', sy, start[1], 1)}-${num(hotspot[1])}`,
	};
}

export function pressedEnable(clicks) {
	if (!clicks.length) return null;
	return clicks.map((c) => `between(t,${num(c.t0)},${num(c.t1)})`).join('+');
}
