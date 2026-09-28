// inline-blame.js - Who last changed the line the cursor is on, shown faintly
// at the end of that line: "Jeffrey Macy, 3 days ago · studio: fix undo".
// Settings > Editor > "Inline blame" turns it off.
//
// Blame comes from `git blame` of the file on disk (/api/git/blame), which
// includes each line's text. The editor's buffer is matched to it with a
// line diff, so unsaved edits above the cursor do not shift the answer, and
// a line that is new or changed reads "Uncommitted change".
//
// annotationFor(blameLines, bufferText, line) is pure and tested.

import { diffLines } from './line-diff.js';
import { locateInRepo } from './gutter-changes.js';
import { formatWhen } from '../components/local-history.js';

/** buffer line (1-based) -> blame entry, or null when the line is not in the blamed text. */
export function mapBufferToBlame(blameLines, bufferText) {
  const blamedText = blameLines.map(l => l.text).join('\n');
  const map = new Map();
  for (const op of diffLines(blamedText, bufferText)) {
    if (op.type === 'equal') map.set(op.newLine, blameLines[op.oldLine - 1]);
  }
  return map;
}

export function annotationFor(entry, now = Date.now()) {
  if (!entry || entry.uncommitted) return { text: 'Uncommitted change', title: 'This line is not committed yet.' };
  const when = entry.date ? formatWhen(Date.parse(entry.date), now) : '';
  const text = [entry.author, when].filter(Boolean).join(', ') + (entry.summary ? ` · ${entry.summary}` : '');
  const title = `${entry.hash.slice(0, 8)} ${entry.author}${entry.date ? `, ${new Date(entry.date).toLocaleString()}` : ''}\n${entry.summary || ''}`;
  return { text, title };
}

export function createInlineBlame(ide) {
  const cache = new Map(); // path -> blame lines, or null (untracked / not a repository)
  const pending = new Map();
  let mapped = { path: null, text: null, map: null };

  function load(path) {
    if (pending.has(path)) return pending.get(path);
    const job = (async () => {
      try {
        const where = await locateInRepo(path);
        if (!where) return null;
        const res = await fetch(`/api/git/blame?folder=${encodeURIComponent(where.folder)}&path=${encodeURIComponent(where.repoPath)}`);
        if (!res.ok) return null; // e.g. not committed yet
        return (await res.json()).lines || null;
      } catch {
        return null;
      }
    })().then(lines => {
      pending.delete(path);
      cache.set(path, lines);
      mapped = { path: null, text: null, map: null };
      if (path === ide.currentFile) decorate();
      return lines;
    });
    pending.set(path, job);
    return job;
  }

  // Draw the annotation on the cursor's line (and remove the old one).
  function decorate() {
    const area = ide.codeAreaEl;
    if (!area) return;
    area.querySelectorAll('.inline-blame').forEach(el => el.remove());
    const path = ide.currentFile;
    if (!path || !ide.setting?.('editor.inlineBlame', true)) return;
    if (!cache.has(path)) { load(path); return; }
    const lines = cache.get(path);
    if (!lines) return;
    const text = ide.currentCode || '';
    if (mapped.path !== path || mapped.text !== text) mapped = { path, text, map: mapBufferToBlame(lines, text) };
    const here = ide.currentEditorLocation?.();
    if (!here) return;
    const row = area.querySelector(`.code-line[data-line="${here.line}"]`);
    if (!row) return;
    const { text: label, title } = annotationFor(mapped.map.get(here.line) || null);
    const span = document.createElement('span');
    span.className = 'inline-blame';
    span.textContent = label;
    span.title = title;
    row.appendChild(span);
  }

  // Commits, checkouts and pulls change the blame: the Git pane announces
  // every status it reads. Saving changes it too (the blamed text is the
  // file on disk).
  const refresh = () => {
    cache.clear();
    if (ide.currentFile) load(ide.currentFile);
  };
  let head;
  globalThis.addEventListener?.('otter:git-status', (e) => {
    const oid = e.detail?.oid ?? null;
    if (head !== undefined && oid !== head) refresh(); // a commit, checkout or pull
    head = oid;
  });
  globalThis.addEventListener?.('otter:file-saved', (e) => {
    const path = e.detail?.path;
    if (path) cache.delete(path);
    if (path && path === ide.currentFile) load(path);
  });

  return { decorate, refresh, forget: (path) => cache.delete(path) };
}
