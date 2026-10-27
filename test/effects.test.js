import { test } from 'node:test';
import assert from 'node:assert/strict';
import { zoomPlan, piecewise } from '../src/effects.js';
import { normalizeStep } from '../src/record.js';
import { execFileSync } from 'node:child_process';

const frame = { W: 1920, H: 1080, duration: 12 };

test('clicks close together share one zoom group', () => {
	const ev = [2, 3.5, 5].map((t) => ({ type: 'click', t, x: 900, y: 500 }));
	const plan = zoomPlan(ev, frame, {});
	assert.equal(plan.groups.length, 1);
	assert.equal(plan.transitions.length, 2); // in and out, no pans for the same spot
});

test('distant clicks get separate zooms', () => {
	const ev = [{ type: 'click', t: 1.5, x: 200, y: 200 }, { type: 'click', t: 9, x: 1700, y: 900 }];
	assert.equal(zoomPlan(ev, frame, {}).groups.length, 2);
});

test('zoom rect stays inside the frame and respects max', () => {
	const plan = zoomPlan([{ type: 'click', t: 3, x: 10, y: 10, zoom: 5 }], frame, { max: 2 });
	const r = plan.transitions[0].to;
	assert.equal(r.z, 2);
	assert.equal(r.x, 0);
	assert.equal(r.y, 0);
});

test('zoomOn box backs the zoom off to fit', () => {
	const plan = zoomPlan([{ type: 'click', t: 3, x: 500, y: 300, focus: { x: 960, y: 540, w: 1200, h: 700 } }], frame, { level: 2 });
	assert.ok(plan.transitions[0].to.z < 1.6);
});

test('zoom can be disabled per action and per shot', () => {
	assert.equal(zoomPlan([{ type: 'click', t: 3, x: 1, y: 1, zoom: false }], frame, {}).transitions.length, 0);
	assert.equal(zoomPlan([{ type: 'click', t: 3, x: 1, y: 1 }], frame, { enabled: false }).transitions.length, 0);
});

test('piecewise expression evaluates in ffmpeg', () => {
	const expr = piecewise('t', [{ t0: 1, t1: 2, v0: 0, v1: 100 }], 0);
	// Draw a box whose x follows the expression; it must parse and run.
	execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'color=s=320x180:d=3', '-vf', `crop=w=100:h=100:x='${expr}':y=0`, '-f', 'null', '-']);
});

test('steps normalize from short and long forms', () => {
	assert.deepEqual(normalizeStep({ click: '#a', zoom: 2 }), { kind: 'click', target: '#a', zoom: 2 });
	assert.deepEqual(normalizeStep({ scroll: 400 }), { kind: 'scroll', by: 400 });
	assert.deepEqual(normalizeStep(500), { kind: 'wait', ms: 500 });
	assert.deepEqual(normalizeStep({ move: [10, 20], duration: 300 }), { kind: 'move', point: [10, 20], duration: 300 });
});

test('camera moves push in from when they are logged and hold to the end', () => {
	const plan = zoomPlan([{ type: 'camera', t: 3, x: 960, y: 540, zoom: 1.4, ramp: 4, hold: null }], frame, { enabled: false });
	assert.equal(plan.transitions.length, 1);
	assert.equal(plan.transitions[0].t0, 3);
	assert.equal(plan.transitions[0].t1, 7);
	assert.equal(plan.transitions[0].to.z, 1.4);
});
