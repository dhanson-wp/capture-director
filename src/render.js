// Timeline assembly: clips, text cards, crossfades, an end card, and a music bed.

import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { launch, renderCard, renderCaption } from './browser.js';
import { remember } from './library.js';
import { ffmpeg, finite, loadYaml, localFile, log, num, outputPath, parseSize, probe, resolveFrom } from './util.js';

const VIDEO = ['.mp4', '.mov', '.m4v'];

function transitionOf(spec, fallback) {
	if (spec === undefined || spec === null) return fallback;
	if (typeof spec === 'number') return { type: fallback.type, duration: spec };
	if (spec === false || spec === 'cut') return { type: 'cut', duration: 0 };
	const type = spec.type ?? fallback.type;
	// xfade names are plain words; anything else would be spliced into the filter graph.
	if (!/^[a-z]+$/.test(type)) throw new Error(`Bad transition type "${type}"`);
	return { type, duration: finite(spec.duration ?? fallback.duration, 'transition duration', { min: 0 }) };
}

export async function render(file, { output, captions = true } = {}) {
	const tl = await loadYaml(file);
	const [OW, OH] = parseSize(tl.size);
	const fps = finite(tl.fps ?? 30, 'fps', { min: 1, max: 120 });
	const out = outputPath(output ? path.resolve(output) : localFile(file, tl.output || 'out/final.mp4', 'output'), VIDEO, 'output');
	const work = path.join(path.dirname(out), `.${path.basename(out, '.mp4')}-work`);
	await mkdir(work, { recursive: true });
	const defTransition = transitionOf(tl.transition, { type: 'fade', duration: 0.6 });
	const cardDefaults = {
		...(tl.card || {}),
		font: resolveFrom(file, tl.card?.font ?? tl.font),
		monoFont: resolveFrom(file, tl.card?.monoFont ?? tl.monoFont),
	};

	const captionDefaults = { ...(tl.caption || {}), font: resolveFrom(file, tl.caption?.font ?? tl.monoFont) };

	// Normalize items into { kind, input args, duration, transition-in }.
	const items = [];
	let browser;
	try {
		for (const [i, raw] of (tl.items || []).entries()) {
			const isEnd = 'end' in raw;
			if ('card' in raw || isEnd) {
				browser ??= await launch();
				const spec = { ...cardDefaults, ...(isEnd ? tl.endCard || {} : {}), ...(raw.card || raw.end) };
				if (spec.font) spec.font = resolveFrom(file, spec.font);
				if (spec.monoFont) spec.monoFont = resolveFrom(file, spec.monoFont);
				const png = path.join(work, `card-${i}.png`);
				await renderCard(browser, png, spec, { width: OW, height: OH });
				const duration = finite(spec.duration ?? (isEnd ? 4 : 3), 'card duration', { min: 0.1 });
				items.push({ label: isEnd ? 'end card' : 'card', args: ['-loop', '1', '-framerate', String(fps), '-t', num(duration), '-i', png], trim: null, duration, raw });
			} else if ('clip' in raw) {
				const src = localFile(file, raw.clip, 'clip');
				const info = await probe(src);
				const [a, b] = raw.trim || [0, info.duration];
				const end = Math.min(b ?? info.duration, info.duration);
				items.push({ label: path.basename(src), args: ['-i', src], trim: [a, end], duration: end - a, raw });
			} else {
				throw new Error(`Timeline item ${i} needs clip, card, or end`);
			}
			const item = items[items.length - 1];
			if (captions && raw.caption) {
				browser ??= await launch();
				const spec = { ...captionDefaults, ...(typeof raw.caption === 'string' ? { text: raw.caption } : raw.caption) };
				if (spec.font) spec.font = resolveFrom(file, spec.font);
				item.caption = { ...spec, png: path.join(work, `caption-${i}.png`) };
				await renderCaption(browser, item.caption.png, spec, { width: OW, height: OH });
			}
		}
	} finally {
		await browser?.close();
	}
	if (!items.length) throw new Error('Timeline has no items');

	const inputs = [];
	const chain = [];
	items.forEach((it, i) => {
		inputs.push(...it.args);
		const trim = it.trim ? `trim=start=${num(it.trim[0])}:end=${num(it.trim[1])},setpts=PTS-STARTPTS,` : '';
		chain.push(
			`[${i}:v]${trim}scale=${OW}:${OH}:force_original_aspect_ratio=decrease:flags=lanczos,` +
				`pad=${OW}:${OH}:(ow-iw)/2:(oh-ih)/2:color=black,fps=${fps},format=yuv420p,setsar=1,settb=AVTB[${it.caption ? `b${i}` : `s${i}`}]`,
		);
	});
	// Captions fade in and out over their own item, after the item's inputs.
	let next = items.length;
	items.forEach((it, i) => {
		if (!it.caption) return;
		const c = it.caption;
		const idx = next++;
		const start = Math.max(0, finite(c.start ?? 0.6, 'caption start'));
		const end = Math.min(it.duration, c.end !== undefined ? finite(c.end, 'caption end') : it.duration - 0.6);
		const f = finite(c.fade ?? 0.6, 'caption fade', { min: 0 });
		inputs.push('-loop', '1', '-framerate', String(fps), '-t', num(it.duration), '-i', c.png);
		chain.push(
			`[${idx}:v]format=rgba,fade=t=in:st=${num(start)}:d=${num(f)}:alpha=1,fade=t=out:st=${num(Math.max(start, end - f))}:d=${num(f)}:alpha=1,settb=AVTB[c${i}]`,
			`[b${i}][c${i}]overlay=0:0:shortest=1:format=auto,format=yuv420p[s${i}]`,
		);
	});

	// Crossfade chain. The transition on item i blends it in over the end of i-1.
	let acc = 's0';
	let length = items[0].duration;
	for (let i = 1; i < items.length; i++) {
		const tr = transitionOf(items[i].raw.transition, defTransition);
		const d = Math.min(tr.duration, items[i - 1].duration / 2, items[i].duration / 2);
		const label = `x${i}`;
		if (tr.type === 'cut' || d <= 0) {
			chain.push(`[${acc}][s${i}]concat=n=2:v=1:a=0[${label}]`);
			length += items[i].duration;
		} else {
			chain.push(`[${acc}][s${i}]xfade=transition=${tr.type}:duration=${num(d)}:offset=${num(length - d)}[${label}]`);
			length += items[i].duration - d;
		}
		acc = label;
	}

	const fade = { in: 0.5, out: 1.0, ...(tl.fade || {}) };
	const vf = [];
	if (fade.in > 0) vf.push(`fade=t=in:st=0:d=${num(fade.in)}`);
	if (fade.out > 0) vf.push(`fade=t=out:st=${num(length - fade.out)}:d=${num(fade.out)}`);
	chain.push(`[${acc}]${vf.length ? vf.join(',') : 'null'}[vout]`);

	const maps = ['-map', '[vout]'];
	if (tl.music) {
		const m = typeof tl.music === 'string' ? { file: tl.music } : tl.music;
		const idx = next++;
		inputs.push('-stream_loop', '-1');
		if (m.start) inputs.push('-ss', num(m.start));
		inputs.push('-i', localFile(file, m.file, 'music'));
		const fi = m.fadeIn ?? 1.5;
		const fo = m.fadeOut ?? 3;
		chain.push(
			`[${idx}:a]atrim=0:${num(length)},asetpts=PTS-STARTPTS,volume=${num(m.volume ?? 0.8)},` +
				`afade=t=in:st=0:d=${num(fi)},afade=t=out:st=${num(Math.max(0, length - fo))}:d=${num(fo)}[aout]`,
		);
		maps.push('-map', '[aout]', '-c:a', 'aac', '-b:a', '192k');
	}

	const graph = path.join(work, 'filter.txt');
	await writeFile(graph, chain.join(';\n'));
	log(`render: ${items.length} items, ${length.toFixed(2)}s -> ${out}`);
	await ffmpeg([
		...inputs,
		'-/filter_complex', graph,
		...maps,
		'-t', num(length),
		'-r', String(fps), '-fps_mode', 'cfr',
		'-c:v', 'libx264', '-preset', preset(tl.preset ?? 'slow'), '-crf', String(finite(tl.crf ?? 16, 'crf', { min: 0, max: 51 })), '-pix_fmt', 'yuv420p',
		'-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-color_range', 'tv',
		'-movflags', '+faststart',
		out,
	]);
	const info = await probe(out);
	log(`render: wrote ${out} (${info.width}x${info.height}, ${info.duration.toFixed(2)}s${info.hasAudio ? ', with music' : ''})`);
	await remember(out, { kind: 'video', title: tl.title, project: tl.project || path.basename(path.dirname(path.resolve(file))), source: file });
	return { file: out, ...info, items: items.map((it) => ({ label: it.label, duration: Number(it.duration.toFixed(2)) })) };
}

function preset(p) {
	if (!/^[a-z]+$/.test(p)) throw new Error(`Bad preset "${p}"`);
	return p;
}

// Contact sheet so an agent can eyeball a clip without playing it.
export async function contactSheet(video, { every = 1, cols = 4, width = 480, output } = {}) {
	every = finite(every, 'every', { min: 0.05 });
	cols = Math.round(finite(cols, 'cols', { min: 1, max: 20 }));
	if (output) outputPath(output, ['.png'], 'sheet output');
	const info = await probe(video);
	const n = Math.ceil(info.duration / every);
	const rows = Math.ceil(n / cols);
	const out = output || video.replace(/\.mp4$/, '') + '-sheet.png';
	await ffmpeg([
		'-i', video,
		'-vf', `fps=1/${num(every)},scale=${width}:-1:flags=lanczos,tile=${cols}x${rows}:padding=6:margin=6:color=0x222222`,
		'-frames:v', '1', '-update', '1',
		out,
	]);
	return { file: out, frames: n, every };
}

// Single full-size stills at given times, for checking sharpness up close.
export async function stills(video, times, dir) {
	await mkdir(dir, { recursive: true });
	const files = [];
	for (const raw of times) {
		const t = finite(raw, 'still time', { min: 0 });
		const f = path.join(dir, `still-${num(t).replace('.', '_')}s.png`);
		await ffmpeg(['-ss', num(t), '-i', video, '-frames:v', '1', '-update', '1', f]);
		files.push(f);
	}
	return files;
}
