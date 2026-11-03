// The capture library: a list of every clip and video this machine has made,
// plus a small local web app for browsing and organizing it.
//
// The list lives in ~/.capture-director/library.json (or $CD_HOME). Videos stay
// wherever they were rendered; the library only points at them.

import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { mkdir, readFile, readdir, rename, rm, stat, writeFile } from 'node:fs/promises';
import http from 'node:http';
import { homedir } from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { ffmpeg, log, probe } from './util.js';

const UI = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'ui');
const VIDEO = /\.(mp4|mov|m4v)$/i;

export function home() {
	return process.env.CD_HOME ? path.resolve(process.env.CD_HOME) : path.join(homedir(), '.capture-director');
}
const dbFile = () => path.join(home(), 'library.json');
const thumbDir = () => path.join(home(), 'thumbs');

// Web copies live in <home>/exports as <id>-<preset>.mp4. They go when their capture goes or moves.
async function clearExports(id) {
	const dir = path.join(home(), 'exports');
	for (const name of await readdir(dir).catch(() => [])) if (name.startsWith(`${id}-`)) await rm(path.join(dir, name), { force: true });
}
export const idFor = (file) => createHash('sha256').update(file).digest('hex').slice(0, 16);

// "a / b/" becomes "a/b". The top level ("Unsorted") is the empty path.
export function normalizeFolder(p) {
	const out = String(p ?? '').split('/').map((s) => s.trim()).filter(Boolean).join('/');
	if (out.length > 300) throw new Error('Folder names can be at most 300 characters');
	return out === 'Unsorted' ? '' : out;
}

// Every folder the app should show: the ones made on purpose, plus each parent of a clip's folder.
export function folderPaths(db) {
	// A path that can't be normalized (too long, from a hand edit or a rename) is skipped, so one bad entry can't block every save.
	const tidy = (p) => {
		try {
			return normalizeFolder(p);
		} catch {
			return '';
		}
	};
	const all = new Set();
	// Each path also brings its parents, so "a/b" always has an "a".
	const withParents = (p) => {
		const parts = tidy(p).split('/').filter(Boolean);
		for (let i = 1; i <= parts.length; i++) all.add(parts.slice(0, i).join('/'));
	};
	for (const f of db.folders || []) withParents(f);
	for (const e of db.entries) withParents(e.project);
	return [...all].sort();
}

// Folders renamed in the Mac app. New clips follow the rename instead of recreating the old folder.
function renamed(project, renames) {
	for (const key of Object.keys(renames).sort((a, b) => b.length - a.length)) {
		if (project === key) return renames[key];
		if (project.startsWith(`${key}/`)) return renames[key] + project.slice(key.length);
	}
	return project;
}

// The folder a new clip starts in. A rename that makes the path too long is ignored for that clip.
function startFolder(project, renames) {
	const base = normalizeFolder(project);
	try {
		return normalizeFolder(renamed(base, renames));
	} catch {
		return base;
	}
}

export async function load() {
	try {
		const db = JSON.parse(await readFile(dbFile(), 'utf8'));
		return {
			entries: Array.isArray(db.entries) ? db.entries : [],
			folders: Array.isArray(db.folders) ? db.folders : [],
			renames: db.renames && typeof db.renames === 'object' && !Array.isArray(db.renames) ? db.renames : {},
		};
	} catch (err) {
		if (err.code === 'ENOENT') return { entries: [], folders: [], renames: {} };
		throw new Error(`Can't read ${dbFile()}: ${err.message}`);
	}
}

// Private to this user, and written atomically so a crash can't leave half a file.
async function save(db) {
	await mkdir(home(), { recursive: true, mode: 0o700 });
	const tmp = `${dbFile()}.${process.pid}.tmp`;
	await writeFile(tmp, JSON.stringify({ ...db, folders: folderPaths(db) }, null, 2), { mode: 0o600 });
	await rename(tmp, dbFile());
}

// Add or refresh a video. Edits made in the library (title, project, star, notes) are kept.
export async function add(file, { kind = 'video', title, project, source, shot, url } = {}) {
	file = path.resolve(file);
	const info = await probe(file);
	const { size } = await stat(file);
	const db = await load();
	const now = new Date().toISOString();
	let entry = db.entries.find((e) => e.file === file);
	if (!entry) {
		// Two paths hashing to one id is unlikely, but an id must never point at two files.
		let id = idFor(file);
		while (db.entries.some((e) => e.id === id)) id = randomBytes(8).toString('hex');
		entry = {
			id,
			file,
			title: title || path.basename(file).replace(VIDEO, ''),
			project: startFolder(project || path.basename(path.dirname(source || file)), db.renames) || 'Unsorted',
			kind,
			starred: false,
			notes: '',
			added: now,
		};
		db.entries.push(entry);
	}
	Object.assign(entry, { kind, source: source ? path.resolve(source) : entry.source, shot: shot ?? entry.shot, updated: now });
	Object.assign(entry, { duration: info.duration, width: info.width, height: info.height, hasAudio: info.hasAudio, size });
	if (url) entry.url = url;
	await save(db);
	await rm(path.join(thumbDir(), `${entry.id}.jpg`), { force: true });
	return entry;
}

// ---------------------------------------------------------------------------
// Changes the Mac app makes by calling `capture-director library ...`.
// Each loads the library, changes it, and saves once. Video files are never touched.

const inside = (p, folder) => p === folder || p.startsWith(`${folder}/`);

export async function addFolder(p) {
	const folder = normalizeFolder(p);
	if (!folder) throw new Error('Pick a folder name');
	const db = await load();
	db.folders.push(folder);
	await save(db);
	return { folders: folderPaths(db) };
}

export async function renameFolder(from, to) {
	from = normalizeFolder(from);
	to = normalizeFolder(to);
	if (!from || !to) throw new Error('Pick a folder name');
	if (inside(to, from)) throw new Error("Can't move a folder into itself");
	const db = await load();
	const known = folderPaths(db);
	if (!known.some((f) => inside(f, from))) throw new Error(`There's no folder called ${from}`);
	if (known.includes(to)) throw new Error(`There's already a folder called ${to}`);
	const move = (p) => (inside(p, from) ? to + p.slice(from.length) : p);
	// Check every new path before changing anything, so a refusal leaves the library as it was.
	const entries = db.entries.filter((x) => inside(normalizeFolder(x.project), from));
	for (const p of [...db.folders.map(normalizeFolder), ...entries.map((x) => normalizeFolder(x.project))]) {
		if (move(p).length > 300) throw new Error('That name makes a folder path longer than 300 characters');
	}
	for (const x of entries) x.project = move(normalizeFolder(x.project));
	db.folders = db.folders.map(normalizeFolder).filter(Boolean).map(move);
	// Earlier renames that pointed into the moved folder now point at its new home.
	for (const key of Object.keys(db.renames)) db.renames[key] = move(db.renames[key]);
	delete db.renames[to];
	db.renames[from] = to;
	await save(db);
	return { folders: folderPaths(db), moved: entries.length };
}

export async function removeFolder(p) {
	const folder = normalizeFolder(p);
	if (!folder) throw new Error('Pick a folder name');
	const db = await load();
	if (db.entries.some((x) => inside(normalizeFolder(x.project), folder))) throw new Error(`${folder} isn't empty`);
	db.folders = db.folders.map(normalizeFolder).filter((f) => f && !inside(f, folder));
	await save(db);
	return { folders: folderPaths(db) };
}

// Looks every id up before the first change, so one unknown id changes nothing.
function pick(db, ids) {
	if (!ids.length) throw new Error('Pick at least one capture');
	return [...new Set(ids)].map((id) => {
		const entry = db.entries.find((x) => x.id === id);
		if (!entry) throw new Error(`No capture with id ${id}`);
		return entry;
	});
}

export async function setEntries(ids, edits = {}) {
	const db = await load();
	const picked = pick(db, ids);
	const body = {};
	for (const k of ['project', 'starred', 'title', 'notes']) if (edits[k] !== undefined) body[k] = edits[k];
	const now = new Date().toISOString();
	for (const entry of picked) {
		applyEdits(entry, body);
		entry.edited = now;
	}
	await save(db);
	return picked;
}

// Removes entries and thumbnails only. The video files stay where they are.
export async function forget(ids) {
	const db = await load();
	const picked = pick(db, ids);
	const gone = new Set(picked.map((x) => x.id));
	db.entries = db.entries.filter((x) => !gone.has(x.id));
	await save(db);
	for (const id of gone) {
		await rm(path.join(thumbDir(), `${id}.jpg`), { force: true });
		await clearExports(id);
	}
	return { forgotten: [...gone] };
}

// Point an entry at a moved file. The id stays, so folders, stars, and notes stay with it.
export async function relocate(id, file) {
	if (!VIDEO.test(String(file))) throw new Error('Only .mp4, .mov, and .m4v videos');
	file = path.resolve(file);
	const info = await probe(file);
	const { size } = await stat(file);
	const db = await load();
	const [entry] = pick(db, [id]);
	if (db.entries.some((x) => x.id !== id && x.file === file)) throw new Error('That video is already in the library');
	Object.assign(entry, { file, size, duration: info.duration, width: info.width, height: info.height, hasAudio: info.hasAudio, updated: new Date().toISOString() });
	await save(db);
	await rm(path.join(thumbDir(), `${id}.jpg`), { force: true });
	await clearExports(id);
	return entry;
}

// Called after record and render. A library problem should never fail the capture itself.
export async function remember(file, meta) {
	if (process.env.CD_NO_LIBRARY === '1') return;
	try {
		await add(file, meta);
	} catch (err) {
		log(`library: couldn't add ${file}: ${err.message}`);
	}
}

// Bring in videos made before the library existed. Skips raw frame folders.
export async function importPath(target) {
	target = path.resolve(target);
	const found = [];
	const walk = async (dir, depth) => {
		for (const d of await readdir(dir, { withFileTypes: true })) {
			if (d.name.startsWith('.') || d.name === 'node_modules' || d.name === 'frames') continue;
			const p = path.join(dir, d.name);
			if (d.isDirectory() && depth < 6) await walk(p, depth + 1);
			else if (d.isFile() && VIDEO.test(d.name)) found.push(p);
		}
	};
	if ((await stat(target)).isDirectory()) await walk(target, 0);
	else found.push(target);
	const added = [];
	for (const file of found) {
		// A clip sits in <out>/<id>/<id>.mp4; anything else is treated as a finished video.
		const base = path.basename(file).replace(VIDEO, '');
		const isClip = path.basename(path.dirname(file)) === base;
		const project = path.basename(path.dirname(isClip ? path.dirname(path.dirname(file)) : path.dirname(file)));
		try {
			added.push(await add(file, { kind: isClip ? 'clip' : 'video', project, shot: isClip ? base : undefined }));
		} catch (err) {
			log(`library: skipped ${file}: ${err.message}`);
		}
	}
	return added.map((e) => ({ id: e.id, file: e.file, kind: e.kind, project: e.project }));
}

// ---------------------------------------------------------------------------
// Local web app

const TYPES = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml', '.woff2': 'font/woff2' };
const STATIC = new Set(['/index.html', '/app.css', '/app.js', '/icon.svg', '/fonts/manrope-latin-wght-normal.woff2', '/fonts/bricolage-grotesque-latin-wght-normal.woff2']);
const HEADERS = {
	'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self'; media-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
	'X-Content-Type-Options': 'nosniff',
	'Referrer-Policy': 'no-referrer',
	'Cross-Origin-Resource-Policy': 'same-origin',
	'Cross-Origin-Opener-Policy': 'same-origin',
	'Cache-Control': 'no-store',
};

function send(res, status, body, type = 'application/json; charset=utf-8') {
	const data = typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body);
	res.writeHead(status, { ...HEADERS, 'Content-Type': type, 'Content-Length': Buffer.byteLength(data) });
	res.end(data);
}

async function readJson(req) {
	let size = 0;
	const chunks = [];
	for await (const c of req) {
		size += c.length;
		if (size > 64 * 1024) throw Object.assign(new Error('Request too large'), { status: 413 });
		chunks.push(c);
	}
	try {
		return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
	} catch {
		throw Object.assign(new Error('Bad JSON'), { status: 400 });
	}
}

function cookie(req, name) {
	for (const part of (req.headers.cookie || '').split(';')) {
		const [k, ...v] = part.trim().split('=');
		if (k === name) return v.join('=');
	}
	return null;
}

const same = (a, b) => typeof a === 'string' && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));

async function exists(file) {
	return stat(file).then((s) => s.isFile(), () => false);
}

async function listing() {
	const { entries } = await load();
	const out = await Promise.all(entries.map(async (e) => ({ ...e, missing: !(await exists(e.file)) })));
	out.sort((a, b) => (b.updated || '').localeCompare(a.updated || ''));
	return { entries: out, platform: process.platform };
}

async function thumbnail(entry) {
	const file = path.join(thumbDir(), `${entry.id}.jpg`);
	if (!(await exists(file))) {
		await mkdir(thumbDir(), { recursive: true, mode: 0o700 });
		const at = Math.min(Math.max(0, (entry.duration || 0) * 0.35), 4);
		await ffmpeg(['-ss', at.toFixed(2), '-i', entry.file, '-frames:v', '1', '-vf', 'scale=640:-2:flags=lanczos', '-q:v', '4', '-update', '1', file]);
	}
	return file;
}

// Stream a video with Range support, so the player can seek.
async function stream(req, res, file) {
	const { size } = await stat(file);
	const type = file.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4';
	const m = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
	if (!m || (!m[1] && !m[2])) {
		res.writeHead(200, { ...HEADERS, 'Content-Type': type, 'Content-Length': size, 'Accept-Ranges': 'bytes' });
		return pipe(createReadStream(file), res);
	}
	let start = m[1] ? Number(m[1]) : size - Number(m[2]);
	let end = m[1] && m[2] ? Number(m[2]) : size - 1;
	start = Math.max(0, start);
	end = Math.min(end, size - 1);
	if (start > end) {
		res.writeHead(416, { ...HEADERS, 'Content-Range': `bytes */${size}` });
		return res.end();
	}
	res.writeHead(206, { ...HEADERS, 'Content-Type': type, 'Content-Length': end - start + 1, 'Content-Range': `bytes ${start}-${end}/${size}`, 'Accept-Ranges': 'bytes' });
	pipe(createReadStream(file, { start, end }), res);
}

function pipe(from, res) {
	from.on('error', () => res.destroy());
	from.pipe(res);
}

function reveal(file) {
	const [cmd, args] =
		process.platform === 'darwin' ? ['open', ['-R', file]] : process.platform === 'win32' ? ['explorer.exe', [`/select,${file}`]] : ['xdg-open', [path.dirname(file)]];
	spawn(cmd, args, { stdio: 'ignore', detached: true }).on('error', () => {}).unref();
}

function openBrowser(url) {
	const [cmd, args] = process.platform === 'darwin' ? ['open', [url]] : process.platform === 'win32' ? ['cmd', ['/c', 'start', '', url]] : ['xdg-open', [url]];
	spawn(cmd, args, { stdio: 'ignore', detached: true }).on('error', () => {}).unref();
}

// Edits the app may make. Everything else about an entry comes from the file itself.
function applyEdits(entry, body) {
	const text = (v, max, what) => {
		if (typeof v !== 'string' || v.length > max) throw Object.assign(new Error(`Bad ${what}`), { status: 400 });
		return v.trim();
	};
	if ('title' in body) entry.title = text(body.title, 200, 'title') || entry.title;
	if ('project' in body) {
		if (typeof body.project !== 'string') throw Object.assign(new Error('Bad project'), { status: 400 });
		// Folder paths may be as long as normalizeFolder allows (300), so deep folders can take captures.
		try {
			entry.project = normalizeFolder(body.project) || 'Unsorted';
		} catch (err) {
			throw Object.assign(err, { status: 400 });
		}
	}
	if ('notes' in body) entry.notes = text(body.notes, 5000, 'notes');
	if ('starred' in body) entry.starred = body.starred === true;
}

export async function serve({ port = 7465, open = true } = {}) {
	const token = randomBytes(24).toString('base64url');
	let origin;
	let session;

	const server = http.createServer(async (req, res) => {
		try {
			// Only answer to our own address. This stops DNS rebinding, where a web page
			// points its own hostname at 127.0.0.1 to reach local servers.
			const host = req.headers.host || '';
			if (host !== origin.host && host !== origin.host.replace('127.0.0.1', 'localhost')) return send(res, 421, { error: 'Wrong host' });
			const url = new URL(req.url, origin);

			// The link printed in the terminal carries a one-run token. Trade it for a
			// cookie that no other site can send, then drop it from the address bar.
			if (url.pathname === '/open') {
				if (!same(url.searchParams.get('token'), token)) return send(res, 403, 'This link has expired. Use the one printed in your terminal.', 'text/plain; charset=utf-8');
				res.writeHead(303, { ...HEADERS, Location: '/', 'Set-Cookie': `${session}=${token}; HttpOnly; SameSite=Strict; Path=/` });
				return res.end();
			}
			if (!same(cookie(req, session), token)) return send(res, 403, 'Open the library with the link printed in your terminal.', 'text/plain; charset=utf-8');

			// Changes must come from the app itself, as JSON.
			if (req.method !== 'GET' && req.method !== 'HEAD') {
				const from = req.headers.origin;
				if (from && from !== origin.origin && from !== origin.origin.replace('127.0.0.1', 'localhost')) return send(res, 403, { error: 'Cross-origin request' });
				if (!(req.headers['content-type'] || '').startsWith('application/json')) return send(res, 415, { error: 'Expected JSON' });
			}

			const p = url.pathname;
			if (req.method === 'GET' && (p === '/' || STATIC.has(p))) {
				const file = path.join(UI, p === '/' ? 'index.html' : p);
				return send(res, 200, await readFile(file), TYPES[path.extname(file)]);
			}
			if (req.method === 'GET' && p === '/api/library') return send(res, 200, await listing());

			const m = /^\/(media|thumb|api\/entries)\/([0-9a-f]{16})(?:\/(reveal|forget))?$/.exec(p);
			if (!m) return send(res, 404, { error: 'Not found' });
			const db = await load();
			const entry = db.entries.find((e) => e.id === m[2]);
			if (!entry) return send(res, 404, { error: 'Not in the library' });
			const [, area, , action] = m;

			if (req.method === 'GET' && area === 'media') return await stream(req, res, entry.file);
			if (req.method === 'GET' && area === 'thumb') {
				// Thumbnail URLs carry the entry's update time, so a cached copy is never stale.
				const data = await readFile(await thumbnail(entry));
				res.writeHead(200, { ...HEADERS, 'Cache-Control': 'private, max-age=86400', 'Content-Type': 'image/jpeg', 'Content-Length': data.length });
				return res.end(data);
			}
			if (area === 'api/entries' && req.method === 'PATCH' && !action) {
				applyEdits(entry, await readJson(req));
				entry.edited = new Date().toISOString();
				await save(db);
				return send(res, 200, entry);
			}
			if (area === 'api/entries' && req.method === 'POST' && action === 'reveal') {
				await readJson(req);
				reveal(entry.file);
				return send(res, 200, { ok: true });
			}
			if (area === 'api/entries' && req.method === 'POST' && action === 'forget') {
				// Removes the entry only. The video file stays where it is.
				await readJson(req);
				db.entries = db.entries.filter((e) => e.id !== entry.id);
				await save(db);
				await rm(path.join(thumbDir(), `${entry.id}.jpg`), { force: true });
				return send(res, 200, { ok: true });
			}
			return send(res, 405, { error: 'Not allowed' });
		} catch (err) {
			if (err.code === 'ENOENT') return send(res, 404, { error: 'File not found' });
			if (!err.status) log(`library: ${err.message}`);
			if (!res.headersSent) send(res, err.status || 500, { error: err.status ? err.message : 'Something went wrong' });
		}
	});

	// Loopback only, so nothing else on the network can reach it.
	const listen = (p) =>
		new Promise((resolve, reject) => {
			server.once('error', reject);
			server.listen(p, '127.0.0.1', () => resolve(server.address().port));
		});
	const actual = await listen(port).catch((err) => (err.code === 'EADDRINUSE' ? listen(0) : Promise.reject(err)));
	origin = new URL(`http://127.0.0.1:${actual}`);
	session = `cd_library_${actual}`;
	const link = `${origin.origin}/open?token=${token}`;
	log(`library: open ${link}`);
	log('library: press Ctrl-C to stop');
	if (open) openBrowser(link);
	return { url: link, port: actual, library: dbFile(), server };
}
