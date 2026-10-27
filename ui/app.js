// Capture director library. Plain DOM, no framework, no build step.
// Every value from the library goes in through textContent or properties, never innerHTML.

const $ = (s) => document.querySelector(s);
const state = { entries: [], platform: 'darwin', view: 'all', project: null, query: '', sort: 'new', open: null, stamp: '' };

const api = async (path, opts = {}) => {
	const res = await fetch(path, {
		...opts,
		headers: opts.body ? { 'Content-Type': 'application/json' } : undefined,
		credentials: 'same-origin',
	});
	if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `Request failed (${res.status})`);
	return res.json();
};

const clock = (s) => {
	s = Math.max(0, Math.round(s || 0));
	return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};
const day = (iso) => (iso ? new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: new Date(iso).getFullYear() === new Date().getFullYear() ? undefined : 'numeric' }) : '');
const when = (iso) => (iso ? new Date(iso).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '');

function toast(text) {
	const t = $('#toast');
	t.textContent = text;
	t.hidden = false;
	clearTimeout(toast.timer);
	toast.timer = setTimeout(() => (t.hidden = true), 2200);
}

// --- Data

async function refresh() {
	try {
		const data = await api('/api/library');
		const stamp = JSON.stringify(data.entries.map((e) => [e.id, e.updated, e.edited, e.missing]));
		state.platform = data.platform;
		if (stamp === state.stamp) return;
		state.stamp = stamp;
		state.entries = data.entries;
		render();
	} catch (err) {
		toast(err.message);
	}
}

async function patch(entry, changes) {
	const updated = await api(`/api/entries/${entry.id}`, { method: 'PATCH', body: JSON.stringify(changes) });
	Object.assign(entry, updated);
	state.stamp = '';
	render();
	return updated;
}

// --- Filtering

function visible() {
	const q = state.query.toLowerCase();
	let list = state.entries.filter((e) => {
		if (state.project !== null) return e.project === state.project;
		if (state.view === 'starred') return e.starred;
		if (state.view === 'video' || state.view === 'clip') return e.kind === state.view;
		return true;
	});
	if (q) list = list.filter((e) => [e.title, e.project, e.notes, e.file].some((v) => (v || '').toLowerCase().includes(q)));
	const by = {
		new: (a, b) => (b.updated || '').localeCompare(a.updated || ''),
		old: (a, b) => (a.updated || '').localeCompare(b.updated || ''),
		name: (a, b) => a.title.localeCompare(b.title, undefined, { numeric: true }),
		long: (a, b) => (b.duration || 0) - (a.duration || 0),
	}[state.sort];
	return list.sort(by);
}

// --- Rendering

function render() {
	const counts = {
		all: state.entries.length,
		starred: state.entries.filter((e) => e.starred).length,
		video: state.entries.filter((e) => e.kind === 'video').length,
		clip: state.entries.filter((e) => e.kind === 'clip').length,
	};
	for (const [k, n] of Object.entries(counts)) $(`[data-count="${k}"]`).textContent = n;
	for (const b of document.querySelectorAll('.views button')) b.setAttribute('aria-current', String(state.project === null && b.dataset.view === state.view));

	const projects = new Map();
	for (const e of state.entries) projects.set(e.project, (projects.get(e.project) || 0) + 1);
	const names = [...projects.keys()].sort((a, b) => a.localeCompare(b));
	const nav = $('#projects');
	nav.replaceChildren(
		...names.map((name) => {
			const b = document.createElement('button');
			b.type = 'button';
			b.setAttribute('aria-current', String(state.project === name));
			const label = document.createElement('span');
			label.textContent = name;
			const count = document.createElement('b');
			count.textContent = projects.get(name);
			b.append(label, count);
			b.addEventListener('click', () => {
				state.project = name;
				render();
			});
			return b;
		}),
	);
	$('#project-list').replaceChildren(...names.map((n) => Object.assign(document.createElement('option'), { value: n })));
	if (state.project !== null && !projects.has(state.project)) state.project = null;

	const headings = { all: 'All captures', starred: 'Starred', video: 'Final videos', clip: 'Clips' };
	$('#heading').textContent = state.project ?? headings[state.view];

	const list = visible();
	$('#empty').hidden = state.entries.length > 0;
	$('#no-match').hidden = !state.entries.length || list.length > 0;
	$('#grid').replaceChildren(...list.map(card));
	document.title = `${$('#heading').textContent} · Capture director`;
}

function card(entry) {
	const node = $('#card').content.firstElementChild.cloneNode(true);
	node.classList.toggle('missing', !!entry.missing);
	const img = node.querySelector('img');
	if (!entry.missing) {
		img.addEventListener('load', () => img.classList.add('loaded'), { once: true });
		img.src = `/thumb/${entry.id}?v=${encodeURIComponent(entry.updated || '')}`;
	}
	node.querySelector('.badge').textContent = entry.kind === 'video' ? 'Final' : '';
	node.querySelector('.length').textContent = clock(entry.duration);
	node.querySelector('.card-title').textContent = entry.title;
	node.querySelector('.card-meta').textContent = [entry.project, day(entry.updated)].filter(Boolean).join(' · ');
	node.querySelector('.card-open').setAttribute('aria-label', `${entry.title}, ${clock(entry.duration)}`);
	node.querySelector('.card-open').addEventListener('click', () => openDetail(entry));
	const star = node.querySelector('.card-star');
	star.setAttribute('aria-pressed', String(!!entry.starred));
	star.setAttribute('aria-label', entry.starred ? `Unstar ${entry.title}` : `Star ${entry.title}`);
	star.addEventListener('click', () => patch(entry, { starred: !entry.starred }).catch((err) => toast(err.message)));
	return node;
}

// --- Detail

// The end of a path is the part that tells files apart.
const shortPath = (p) => {
	const parts = p.split('/');
	return parts.length > 4 ? `…/${parts.slice(-3).join('/')}` : p;
};

function redoCommand(e) {
	if (!e.source) return '';
	const q = (s) => (/^[\w./~-]+$/.test(s) ? s : `'${s.replace(/'/g, `'\\''`)}'`);
	return e.kind === 'clip' && e.shot ? `capture-director record ${q(e.source)} --only ${q(e.shot)}` : `capture-director render ${q(e.source)}`;
}

function openDetail(entry) {
	state.open = entry;
	const d = $('#detail');
	const video = $('#d-video');
	video.hidden = !!entry.missing;
	$('#d-missing').hidden = !entry.missing;
	if (!entry.missing) {
		video.src = `/media/${entry.id}`;
		video.poster = `/thumb/${entry.id}?v=${encodeURIComponent(entry.updated || '')}`;
	} else video.removeAttribute('src');
	$('#d-kind').textContent = entry.kind === 'video' ? 'Final video' : 'Clip';
	$('#d-title').value = entry.title;
	$('#d-project').value = entry.project;
	$('#d-notes').value = entry.notes || '';
	setStar(entry.starred);
	const facts = [
		['Length', clock(entry.duration)],
		['Size', entry.width ? `${entry.width}×${entry.height}` : '-'],
		['Audio', entry.hasAudio ? 'Music bed' : 'None'],
		['Updated', when(entry.updated)],
		['Added', when(entry.added)],
	];
	$('#d-facts').replaceChildren(
		...facts.flatMap(([k, v]) => [Object.assign(document.createElement('dt'), { textContent: k }), Object.assign(document.createElement('dd'), { textContent: v })]),
	);
	$('#d-file').textContent = shortPath(entry.file);
	$('#d-file').title = entry.file;
	const redo = redoCommand(entry);
	$('#d-redo-row').hidden = !redo;
	$('#d-redo').textContent = redo.replace(entry.source || '', shortPath(entry.source || ''));
	$('#d-redo').title = redo;
	$('#d-reveal').textContent = state.platform === 'darwin' ? 'Show in Finder' : 'Show in folder';
	$('#d-reveal').disabled = !!entry.missing;
	$('#d-status').textContent = '';
	if (!d.open) d.showModal();
}

function setStar(on) {
	const b = $('#d-star');
	b.setAttribute('aria-pressed', String(!!on));
	b.querySelector('span').textContent = on ? 'Starred' : 'Star';
}

function closeDetail() {
	const video = $('#d-video');
	video.pause();
	video.removeAttribute('src');
	video.load();
	state.open = null;
	if ($('#detail').open) $('#detail').close();
}

async function saveField(field, value) {
	const entry = state.open;
	if (!entry || entry[field] === value) return;
	try {
		await patch(entry, { [field]: value });
		$('#d-status').textContent = 'Saved';
	} catch (err) {
		$('#d-status').textContent = err.message;
	}
}

async function copy(text) {
	try {
		await navigator.clipboard.writeText(text);
		toast('Copied');
	} catch {
		toast("Couldn't copy. Select the text instead.");
	}
}

// --- Wiring

for (const b of document.querySelectorAll('.views button')) {
	b.addEventListener('click', () => {
		state.view = b.dataset.view;
		state.project = null;
		render();
	});
}
$('#search').addEventListener('input', (e) => {
	state.query = e.target.value;
	render();
});
$('#sort').addEventListener('change', (e) => {
	state.sort = e.target.value;
	render();
});
document.addEventListener('keydown', (e) => {
	if (e.key === '/' && !e.metaKey && !e.ctrlKey && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)) {
		e.preventDefault();
		$('#search').focus();
	}
});

$('#d-close').addEventListener('click', closeDetail);
$('#detail').addEventListener('close', closeDetail);
$('#detail').addEventListener('click', (e) => {
	if (e.target === e.currentTarget) closeDetail();
});
$('#d-form').addEventListener('submit', (e) => e.preventDefault());
$('#d-title').addEventListener('change', (e) => saveField('title', e.target.value.trim()));
$('#d-project').addEventListener('change', (e) => saveField('project', e.target.value.trim()));
$('#d-notes').addEventListener('change', (e) => saveField('notes', e.target.value.trim()));
for (const id of ['#d-title', '#d-project']) {
	$(id).addEventListener('keydown', (e) => {
		if (e.key === 'Enter') e.target.blur();
	});
}
$('#d-star').addEventListener('click', async () => {
	const entry = state.open;
	await saveField('starred', !entry.starred);
	setStar(entry.starred);
});
for (const b of document.querySelectorAll('[data-copy]')) {
	b.addEventListener('click', () => copy(b.dataset.copy === 'file' ? state.open.file : redoCommand(state.open)));
}
$('#d-reveal').addEventListener('click', () => api(`/api/entries/${state.open.id}/reveal`, { method: 'POST', body: '{}' }).catch((err) => toast(err.message)));
$('#d-forget').addEventListener('click', async () => {
	const entry = state.open;
	if (!confirm(`Remove “${entry.title}” from the library? The video file stays where it is.`)) return;
	try {
		await api(`/api/entries/${entry.id}/forget`, { method: 'POST', body: '{}' });
		closeDetail();
		state.entries = state.entries.filter((e) => e.id !== entry.id);
		state.stamp = '';
		render();
		toast('Removed from the library');
	} catch (err) {
		toast(err.message);
	}
});

// New recordings show up on their own while the library is open.
refresh();
setInterval(() => {
	if (!document.hidden && !state.open) refresh();
}, 4000);
document.addEventListener('visibilitychange', () => !document.hidden && refresh());
