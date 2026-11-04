import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { loadShots } from '../src/shots.js';

const BUNDLE = 'io.github.dhanson-wp.capture-director';

// Write a one-shot YAML file and load it. `body` is the shot's YAML, indented under "shots:".
async function load(body) {
	const dir = await mkdtemp(`${tmpdir()}/cd-app-shots-`);
	const file = path.join(dir, 'shots.yml');
	const indented = body.trim().split('\n').map((l, i) => (i === 0 ? `  - ${l}` : `    ${l}`)).join('\n');
	await writeFile(file, `shots:\n${indented}\n`);
	return { dir, ...(await loadShots(file)) };
}

test('an app shot loads with defaults', async () => {
	const { shots } = await load(`app: ${BUNDLE}`);
	const [s] = shots;
	assert.equal(s.kind, 'app');
	assert.deepEqual(s.app, { bundleId: BUNDLE });
	assert.deepEqual(s.window, { width: 1440, height: 900 });
	assert.equal(s.background, '#4c1637');
	assert.equal(s.countdown, 3);
	assert.equal(s.recordFps, 60);
	assert.equal(s.settle, 400);
	assert.equal(s.tail, 800);
	assert.deepEqual(s.env, {});
	assert.equal(s.cursor.enabled, true);
	assert.equal(s.zoom.enabled, true);
});

test('a web shot is kind web', async () => {
	const { shots } = await load('url: https://example.com');
	assert.equal(shots[0].kind, 'web');
});

test('an .app path is accepted', async () => {
	const { shots } = await load('app: /Applications/TextEdit.app');
	assert.deepEqual(shots[0].app, { path: '/Applications/TextEdit.app' });
});

test('url and app together are refused', async () => {
	await assert.rejects(load(`url: https://example.com\napp: ${BUNDLE}`), /url or app, not both/);
});

test('web-only options are refused on app shots', async () => {
	await assert.rejects(load(`app: ${BUNDLE}\nscale: 2`), /scale only works on web shots/);
	for (const [k, v] of [['hideScrollbars', 'true'], ['setup', '[]'], ['viewport', '{ width: 800, height: 600 }'], ['css', '"a{}"'], ['hide', '[a]'], ['waitUntil', 'load']]) {
		await assert.rejects(load(`app: ${BUNDLE}\n${k}: ${v}`), new RegExp(`${k} only works on web shots`));
	}
});

test('background must be a plain hex color', async () => {
	await assert.rejects(load(`app: ${BUNDLE}\nbackground: "red;movie=x"`), /must be a color like #4c1637/);
	await assert.rejects(load(`app: ${BUNDLE}\nbackground: "#4c16"`), /must be a color like #4c1637/);
	const { shots } = await load(`app: ${BUNDLE}\nbackground: "#0A1b2C"`);
	assert.equal(shots[0].background, '#0A1b2C');
});

test('env must be plain strings with plain names', async () => {
	await assert.rejects(load(`app: ${BUNDLE}\nenv: { CD_HOME: 5 }`), /env/);
	await assert.rejects(load(`app: ${BUNDLE}\nenv: { "A B": "x" }`), /env/);
	await assert.rejects(load(`app: ${BUNDLE}\nenv: [a]`), /env/);
	const { shots } = await load(`app: ${BUNDLE}\nenv: { CD_HOME: "/tmp/x" }`);
	assert.deepEqual(shots[0].env, { CD_HOME: '/tmp/x' });
});

test('relative env values resolve from the YAML file, others pass verbatim', async () => {
	const { dir, shots } = await load(`app: ${BUNDLE}\nenv: { A: ./data, B: ../up, C: plain, D: "~/x" }`);
	assert.deepEqual(shots[0].env, { A: path.join(dir, 'data'), B: path.resolve(dir, '../up'), C: 'plain', D: '~/x' });
});

test('app must be a bundle ID or an .app path', async () => {
	await assert.rejects(load('app: "../../bin/sh"'), /bundle ID or a path to an .app/);
	await assert.rejects(load('app: notabundle'), /bundle ID or a path to an .app/);
	await assert.rejects(load('app: "/Applications/Foo"'), /bundle ID or a path to an .app/);
});

test('a relative .app path resolves from the YAML file', async () => {
	const { dir, shots } = await load('app: ./build/Demo.app');
	assert.equal(shots[0].app.path, path.join(dir, 'build', 'Demo.app'));
});

test('window size is bounded', async () => {
	await assert.rejects(load(`app: ${BUNDLE}\nwindow: { width: 100, height: 900 }`), /window/);
	await assert.rejects(load(`app: ${BUNDLE}\nwindow: { width: 1440, height: 3000 }`), /window/);
	await assert.rejects(load(`app: ${BUNDLE}\nwindow: { width: 3001, height: 900 }`), /window/);
	const { shots } = await load(`app: ${BUNDLE}\nwindow: { width: 760, height: 480 }`);
	assert.deepEqual(shots[0].window, { width: 760, height: 480 });
});

test('app steps only use app actions', async () => {
	await assert.rejects(load(`app: ${BUNDLE}\nactions:\n  - eval: "1"`), /eval doesn't work in app shots/);
	await assert.rejects(load(`app: ${BUNDLE}\nactions:\n  - drag: [1, 2]`), /drag doesn't work in app shots/);
	await load(`app: ${BUNDLE}\nactions:\n  - 500\n  - wait: 200\n  - click: { id: grid.item.0 }\n  - hover: x\n  - move: [10, 20]\n  - press: cmd+o\n  - type: hi\n  - scroll: 100`);
});

test('countdown, recordFps, and settle are checked numbers', async () => {
	await assert.rejects(load(`app: ${BUNDLE}\ncountdown: abc`), /countdown/);
	await assert.rejects(load(`app: ${BUNDLE}\nrecordFps: 500`), /recordFps/);
	await assert.rejects(load(`app: ${BUNDLE}\nsettle: -1`), /settle/);
	const { shots } = await load(`app: ${BUNDLE}\ncountdown: 0\nrecordFps: 30\nsettle: 100`);
	assert.equal(shots[0].countdown, 0);
	assert.equal(shots[0].recordFps, 30);
	assert.equal(shots[0].settle, 100);
});
