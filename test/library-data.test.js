import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { makeVideo } from './helpers.js';

process.env.CD_QUIET = '1';
const { add, addFolder, forget, idFor, load, normalizeFolder, relocate, removeFolder, renameFolder, setEntries } = await import('../src/library.js');
const run = promisify(execFile);
const CLI = path.join(import.meta.dirname, '..', 'bin', 'capture-director.js');

// Each test gets its own library folder; the module reads CD_HOME on every call.
async function fresh() {
	const dir = await mkdtemp(`${tmpdir()}/cd-data-`);
	process.env.CD_HOME = path.join(dir, 'home');
	return dir;
}
const dbPath = () => path.join(process.env.CD_HOME, 'library.json');

test('normalizeFolder tidies paths', () => {
	assert.equal(normalizeFolder(' a / /b '), 'a/b');
	assert.equal(normalizeFolder('Unsorted'), '');
	assert.equal(normalizeFolder('a/'), 'a');
	assert.equal(normalizeFolder('🎬 Demos'), '🎬 Demos');
	assert.throws(() => normalizeFolder('x'.repeat(301)), /Folder names can be at most 300 characters/);
});

test('old library.json loads unchanged', async () => {
	await fresh();
	const { mkdir } = await import('node:fs/promises');
	await mkdir(process.env.CD_HOME, { recursive: true });
	const oldEntry = { id: '0123456789abcdef', file: '/x/y.mp4', title: 'y', project: 'x', kind: 'video', starred: false, notes: '', added: '2026-01-01T00:00:00.000Z' };
	const raw = JSON.stringify({ entries: [oldEntry] }, null, 2);
	await writeFile(dbPath(), raw);
	assert.deepEqual(await load(), { entries: [oldEntry], folders: [], renames: {} });
	assert.equal(await readFile(dbPath(), 'utf8'), raw);
});

test('folders fill in on first save', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	await add(video, { project: 'blog/Post formats' });
	const saved = JSON.parse(await readFile(dbPath(), 'utf8'));
	assert.deepEqual(saved.folders, ['blog', 'blog/Post formats']);
});

test('add records size and url', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	const entry = await add(video, { url: 'https://example.com/' });
	assert.equal(entry.size, (await stat(video)).size);
	assert.equal(entry.url, 'https://example.com/');
});

test('renames send a new entry to the renamed folder', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	const { mkdir } = await import('node:fs/promises');
	await mkdir(process.env.CD_HOME, { recursive: true });
	await writeFile(dbPath(), JSON.stringify({ entries: [], renames: { blog: 'Website' } }));
	const entry = await add(video, { project: 'blog/Post formats' });
	assert.equal(entry.project, 'Website/Post formats');
	// Re-adding an existing entry keeps whatever project it has.
	const again = await add(video, { project: 'blog/Other' });
	assert.equal(again.project, 'Website/Post formats');
});

test('id collision gets a fresh id', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	const { mkdir } = await import('node:fs/promises');
	await mkdir(process.env.CD_HOME, { recursive: true });
	const clash = idFor(path.resolve(video));
	await writeFile(dbPath(), JSON.stringify({ entries: [{ id: clash, file: '/elsewhere.mp4', title: 'e', project: 'p', kind: 'video' }] }));
	const entry = await add(video);
	assert.match(entry.id, /^[0-9a-f]{16}$/);
	assert.notEqual(entry.id, clash);
});

// Write a library.json by hand, as an older version or a person editing it would.
async function seed(db) {
	await mkdir(process.env.CD_HOME, { recursive: true });
	await writeFile(dbPath(), JSON.stringify(db, null, 2));
}
const e = (id, project, file = `/x/${id}.mp4`) => ({ id, file, title: id, project, kind: 'video', starred: false, notes: '', added: '2026-01-01T00:00:00.000Z' });

test('folderPaths skips a path that is too long instead of breaking every save', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	await seed({ entries: [e('0000000000000001', 'x'.repeat(301))], folders: ['y'.repeat(301), 'ok'] });
	await add(video, { project: 'fine' });
	const saved = JSON.parse(await readFile(dbPath(), 'utf8'));
	assert.deepEqual(saved.folders, ['fine', 'ok']);
});

test('add falls back to the old project when the renamed one is too long', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	await seed({ entries: [], renames: { a: 'x'.repeat(299) } });
	const entry = await add(video, { project: 'a/bb' });
	assert.equal(entry.project, 'a/bb');
});

test('renameFolder moves entries and remembers the rename', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	await seed({ entries: [e('0000000000000001', 'blog'), e('0000000000000002', 'blog/x')], folders: ['blog/empty'], renames: { old: 'blog/sub' } });
	const out = await renameFolder('blog', 'Website');
	assert.equal(out.moved, 2);
	assert.deepEqual(out.folders, ['Website', 'Website/empty', 'Website/x']);
	const db = await load();
	assert.deepEqual(db.entries.map((x) => x.project), ['Website', 'Website/x']);
	assert.equal(db.renames.blog, 'Website');
	assert.equal(db.renames.old, 'Website/sub');
	const entry = await add(video, { project: 'blog' });
	assert.equal(entry.project, 'Website');
});

test('renameFolder refuses its own descendant and an existing path', async () => {
	await fresh();
	await seed({ entries: [e('0000000000000001', 'a'), e('0000000000000002', 'c')] });
	await load();
	await removeFolder('nothing').catch(() => {});
	const before = await readFile(dbPath(), 'utf8');
	await assert.rejects(renameFolder('a', 'a/b'), /Can't move a folder into itself/);
	await assert.rejects(renameFolder('a', 'a'), /Can't move a folder into itself/);
	await assert.rejects(renameFolder('a', 'c'), /There's already a folder called c/);
	assert.equal(await readFile(dbPath(), 'utf8'), before);
});

test('renameFolder refuses a rename that makes a path too long', async () => {
	await fresh();
	await seed({ entries: [e('0000000000000001', 'a/bbbbb')] });
	const before = await readFile(dbPath(), 'utf8');
	await assert.rejects(renameFolder('a', 'x'.repeat(298)), /That name makes a folder path longer than 300 characters/);
	assert.equal(await readFile(dbPath(), 'utf8'), before);
});

test('addFolder makes a folder and refuses an empty name', async () => {
	await fresh();
	assert.deepEqual((await addFolder(' a / b ')).folders, ['a', 'a/b']);
	await assert.rejects(addFolder('  '), /Pick a folder name/);
	await assert.rejects(addFolder('Unsorted'), /Pick a folder name/);
});

test('removeFolder only removes empty folders', async () => {
	await fresh();
	await seed({ entries: [e('0000000000000001', 'full/inside')], folders: ['empty', 'empty/child', 'full'] });
	await assert.rejects(removeFolder('full'), /full isn't empty/);
	await assert.rejects(removeFolder('full/inside'), /full\/inside isn't empty/);
	assert.deepEqual((await removeFolder('empty')).folders, ['full', 'full/inside']);
});

test('setEntries edits several at once', async () => {
	await fresh();
	await seed({ entries: [e('0000000000000001', 'a'), e('0000000000000002', 'a')] });
	const out = await setEntries(['0000000000000001', '0000000000000002'], { project: 'x', starred: true });
	assert.deepEqual(out.map((x) => [x.project, x.starred]), [['x', true], ['x', true]]);
	const before = await readFile(dbPath(), 'utf8');
	await assert.rejects(setEntries(['0000000000000001', 'nope'], { starred: false }), /No capture with id nope/);
	assert.equal(await readFile(dbPath(), 'utf8'), before);
});

test('setEntries moves captures into a deep folder up to 300 characters', async () => {
	await fresh();
	await seed({ entries: [e('0000000000000001', 'a')] });
	// Ten levels of 14 characters plus slashes: 149 characters, past the old 100 cap.
	const deep = Array.from({ length: 10 }, (_, i) => `Level ${String(i).padStart(2, '0')} folder`).join('/').slice(0, 150);
	assert.ok(deep.length > 100 && deep.length <= 300);
	const [out] = await setEntries(['0000000000000001'], { project: deep });
	assert.equal(out.project, normalizeFolder(deep));
	const before = await readFile(dbPath(), 'utf8');
	await assert.rejects(setEntries(['0000000000000001'], { project: 'x'.repeat(301) }), /at most 300 characters/);
	assert.equal(await readFile(dbPath(), 'utf8'), before);
});

test('forget keeps the file', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	const entry = await add(video);
	assert.deepEqual(await forget([entry.id]), { forgotten: [entry.id] });
	assert.equal((await load()).entries.length, 0);
	assert.ok((await stat(video)).isFile());
});

test('relocate rejects a missing or non-video file', async () => {
	const dir = await fresh();
	const video = await makeVideo(dir);
	const moved = await makeVideo(dir, 'moved.mp4', 2);
	const entry = await add(video);
	const other = await add(await makeVideo(dir, 'other.mp4'));
	await writeFile(path.join(dir, 'a.txt'), 'hi');
	await assert.rejects(relocate(entry.id, path.join(dir, 'a.txt')), /Only .mp4, .mov, and .m4v videos/);
	await assert.rejects(relocate(entry.id, path.join(dir, 'gone.mp4')));
	await assert.rejects(relocate(entry.id, other.file), /That video is already in the library/);
	const out = await relocate(entry.id, moved);
	assert.equal(out.id, entry.id);
	assert.equal(out.file, moved);
	assert.equal(out.size, (await stat(moved)).size);
	assert.ok(out.duration > entry.duration);
});

test('the CLI prints JSON and fails plainly', async () => {
	await fresh();
	const env = { ...process.env, CD_QUIET: '1' };
	const ok = await run(process.execPath, [CLI, 'library', 'folder', 'add', 'Demos'], { env });
	assert.ok(JSON.parse(ok.stdout).folders.includes('Demos'));
	await assert.rejects(run(process.execPath, [CLI, 'library', 'set', 'nope', '--star'], { env }), (err) => {
		assert.equal(err.code, 1);
		assert.equal(err.stderr.trim(), '[capture-director] No capture with id nope');
		return true;
	});
});

test('the CLI keeps flag values that start with -- or hold =', async () => {
	const dir = await fresh();
	const entry = await add(await makeVideo(dir));
	const env = { ...process.env, CD_QUIET: '1' };
	const set = async (...args) => JSON.parse((await run(process.execPath, [CLI, 'library', 'set', entry.id, ...args], { env })).stdout);
	await set('--notes=-- todo: reshoot', '--title=--star');
	let saved = (await load()).entries[0];
	assert.equal(saved.notes, '-- todo: reshoot');
	assert.equal(saved.title, '--star');
	assert.equal(saved.starred, false);
	await set('--notes=a=b');
	assert.equal((await load()).entries[0].notes, 'a=b');
	await set('--notes=');
	assert.equal((await load()).entries[0].notes, '');
	// The older forms still work.
	await set('--project', 'Demos', '--star');
	saved = (await load()).entries[0];
	assert.equal(saved.project, 'Demos');
	assert.equal(saved.starred, true);
});

test('the CLI reads everything after -- as names, even ones starting with --', async () => {
	await fresh();
	const env = { ...process.env, CD_QUIET: '1' };
	const out = JSON.parse((await run(process.execPath, [CLI, 'library', 'folder', 'add', '--', '--draft'], { env })).stdout);
	assert.ok(out.folders.includes('--draft'));
});

test('the CLI refuses an unknown library command instead of serving', async () => {
	await fresh();
	const env = { ...process.env, CD_QUIET: '1' };
	await assert.rejects(run(process.execPath, [CLI, 'library', 'frobnicate'], { env, timeout: 10000 }), (err) => {
		assert.equal(err.code, 1);
		assert.equal(err.stderr.trim(), '[capture-director] Unknown library command frobnicate. Run capture-director help.');
		return true;
	});
});
