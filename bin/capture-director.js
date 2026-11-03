#!/usr/bin/env node
import path from 'node:path';
import { record, processAll } from '../src/shots.js';
import { render, contactSheet, stills } from '../src/render.js';
import { serve, importPath, addFolder, renameFolder, removeFolder, setEntries, forget, relocate } from '../src/library.js';
import { exportEntry } from '../src/export.js';
import { installApp } from '../src/install-app.js';

const HELP = `capture-director: record polished website demo clips without a human at the wheel

Usage:
  capture-director record <shots.yaml> [--only id,id]   Record shots, then add zoom and cursor
  capture-director process <shots.yaml> [--only id,id]  Redo zoom and cursor on existing captures
  capture-director render <timeline.yaml> [--out file]  Assemble clips, cards, and music
                    [--no-captions]                      Leave out every caption in the timeline
  capture-director sheet <video.mp4> [--every 1]        Contact sheet PNG for a quick look
  capture-director stills <video.mp4> <t1,t2,...>       Full-size PNG stills at given seconds
  capture-director library [--port 7465] [--no-open]    Browse and organize everything you've made
  capture-director library add <folder or video>       Add videos made before the library existed
  capture-director library folder add <path>            Make a folder (nested with /)
  capture-director library folder rename <from> <to>    Rename or move a folder and everything in it (also: move)
  capture-director library folder remove <path>         Remove an empty folder
  capture-director library set <id>... [--project <path>] [--star|--unstar] [--title <text>] [--notes <text>]
                                                        Change one or more captures
  capture-director library forget <id>...               Drop captures from the library; the videos stay on disk
  capture-director library export <id> [--preset web|small]  Make a smaller copy for size-limited uploads
  capture-director library relocate <id> <new path>     Point a capture at its video's new location
  capture-director install-app [--dir ~/Applications]   Build and install the Mac app

Every command prints a JSON summary on stdout. Progress goes to stderr.
`;

// --key=value splits on the first = only, so a value can hold = or start with --.
// A bare -- ends the flags: everything after it is positional, even names starting with --.
function flags(argv) {
	const out = { _: [] };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === '--') {
			out._.push(...argv.slice(i + 1));
			break;
		}
		if (a.startsWith('--')) {
			const eq = a.indexOf('=');
			if (eq !== -1) out[a.slice(2, eq)] = a.slice(eq + 1);
			else out[a.slice(2)] = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true;
		} else out._.push(a);
	}
	return out;
}

async function main() {
	const [cmd, ...rest] = process.argv.slice(2);
	const f = flags(rest);
	const target = cmd !== 'library' && f._[0] && path.resolve(f._[0]);
	let result;
	switch (cmd) {
		case 'record':
			result = await record(target, { only: f.only });
			break;
		case 'process':
			result = await processAll(target, { only: f.only });
			break;
		case 'render':
			result = await render(target, { output: f.out, captions: !f['no-captions'] });
			break;
		case 'sheet':
			result = await contactSheet(target, { every: Number(f.every ?? 1), cols: Number(f.cols ?? 4), output: f.out });
			break;
		case 'stills':
			result = await stills(target, String(f._[1] ?? '1').split(','), f.out ?? path.join(path.dirname(target), 'stills'));
			break;
		case 'library':
			if (f._[0] === 'add') {
				if (!f._[1]) throw new Error('library add needs a folder or video');
				result = await importPath(f._[1]);
			} else if (f._[0] === 'folder') {
				const [, op, a, b] = f._;
				if (op === 'add') result = await addFolder(a);
				else if (op === 'rename' || op === 'move') result = await renameFolder(a, b);
				else if (op === 'remove') result = await removeFolder(a);
				else throw new Error('library folder needs add, rename, or remove');
			} else if (f._[0] === 'set') {
				const edits = {};
				for (const k of ['project', 'title', 'notes']) if (f[k] !== undefined) edits[k] = f[k] === true ? '' : f[k];
				if (f.star) edits.starred = true;
				if (f.unstar) edits.starred = false;
				result = await setEntries(f._.slice(1), edits);
			} else if (f._[0] === 'forget') {
				result = await forget(f._.slice(1));
			} else if (f._[0] === 'relocate') {
				if (!f._[1] || !f._[2]) throw new Error('library relocate needs an id and a new path');
				result = await relocate(f._[1], f._[2]);
			} else if (f._[0] === 'export') {
				if (!f._[1]) throw new Error('library export needs an id');
				result = await exportEntry(f._[1], { preset: f.preset === undefined ? 'web' : f.preset });
			} else if (f._[0] !== undefined) {
				throw new Error(`Unknown library command ${f._[0]}. Run capture-director help.`);
			} else {
				const { url, port, library } = await serve({ port: f.port === undefined ? undefined : Number(f.port), open: !f['no-open'] });
				result = { url, port, library };
			}
			break;
		case 'install-app':
			result = await installApp({ dir: typeof f.dir === 'string' ? path.resolve(f.dir) : undefined });
			break;
		default:
			process.stdout.write(HELP);
			process.exit(cmd && cmd !== 'help' && cmd !== '--help' ? 1 : 0);
	}
	process.stdout.write(JSON.stringify(result, null, 2) + '\n');
}

main().catch((err) => {
	console.error(`[capture-director] ${err.message}`);
	process.exit(1);
});
