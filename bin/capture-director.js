#!/usr/bin/env node
import path from 'node:path';
import { record, processAll } from '../src/shots.js';
import { render, contactSheet, stills } from '../src/render.js';
import { serve, importPath } from '../src/library.js';

const HELP = `capture-director: record polished website demo clips without a human at the wheel

Usage:
  capture-director record <shots.yaml> [--only id,id]   Record shots, then add zoom and cursor
  capture-director process <shots.yaml> [--only id,id]  Redo zoom and cursor on existing captures
  capture-director render <timeline.yaml> [--out file]  Assemble clips, cards, and music
  capture-director sheet <video.mp4> [--every 1]        Contact sheet PNG for a quick look
  capture-director stills <video.mp4> <t1,t2,...>       Full-size PNG stills at given seconds
  capture-director library [--port 7465] [--no-open]    Browse and organize everything you've made
  capture-director library add <folder or video>       Add videos made before the library existed

Every command prints a JSON summary on stdout. Progress goes to stderr.
`;

function flags(argv) {
	const out = { _: [] };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a.startsWith('--')) {
			const [k, v] = a.slice(2).split('=');
			out[k] = v ?? (argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : true);
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
			result = await render(target, { output: f.out });
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
			} else {
				const { url, port, library } = await serve({ port: f.port === undefined ? undefined : Number(f.port), open: !f['no-open'] });
				result = { url, port, library };
			}
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
