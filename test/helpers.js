import path from 'node:path';
import { ffmpeg } from '../src/util.js';

// A tiny real video, so code that probes or stats files has something to read.
export async function makeVideo(dir, name = 'clip.mp4', seconds = 1) {
	const file = path.join(dir, name);
	await ffmpeg(['-f', 'lavfi', '-i', 'testsrc=size=320x180:rate=10', '-t', String(seconds), '-pix_fmt', 'yuv420p', file]);
	return file;
}
