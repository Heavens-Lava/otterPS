// gutter-changes.js - Git change markers in the editor's line-number gutter.
//
// The editor's live text is compared with the file's staged copy (or the last
// commit when nothing is staged), the same base the Git pane's "Changes" list
// uses, so the markers move as you type:
//   added     a green bar  - lines that are not in the base
//   modified  a blue bar   - lines that replace base lines
//   deleted   a red wedge  - base lines were removed just below this line
//                            (just above line 1 when removed at the top)
// Untracked files and files outside a repository get no markers.
//
// changeHunks(base, current) is pure and tested (scripts/editor-extras.test.mjs).

import { diffLines, splitLines } from './line-diff.js';

/**
 * The changed regions, in order. Each hunk:
 *   { kind: 'added' | 'modified' | 'deleted',
 *     start, end,          // 1-based lines in the current text (end inclusive);
 *                          // for 'deleted' both are the line above the gap (0 = top)
 *     original: string[] } // the base lines this hunk replaced
 */
export function changeHunks(base, current) {
  const ops = diffLines(base ?? '', current ?? '');
  const hunks = [];
  let lastNewLine = 0;
  let i = 0;
  while (i < ops.length) {
    if (ops[i].type === 'equal') { lastNewLine = ops[i].newLine; i++; continue; }
    const deletes = [];
    const inserts = [];
    while (i < ops.length && ops[i].type !== 'equal') {
      if (ops[i].type === 'delete') deletes.push(ops[i]);
      else inserts.push(ops[i]);
      i++;
    }
    if (inserts.length) {
      hunks.push({
        kind: deletes.length ? 'modified' : 'added',
        start: inserts[0].newLine,
        end: inserts[inserts.length - 1].newLine,
        original: deletes.map(d => d.text)
      });
      lastNewLine = inserts[inserts.length - 1].newLine;
    } else {
      hunks.push({ kind: 'deleted', start: lastNewLine, end: lastNewLine, original: deletes.map(d => d.text) });
    }
  }
  return hunks;
}

/** line number -> gutter class (a deletion at the very top is marked on line 1). */
export function markersFromHunks(hunks) {
  const markers = new Map();
  for (const h of hunks) {
    if (h.kind === 'deleted') {
      const line = Math.max(h.start, 1);
      const cls = h.start === 0 ? 'gutter-git-deleted-above' : 'gutter-git-deleted';
      markers.set(line, markers.has(line) ? `${markers.get(line)} ${cls}` : cls);
    } else {
      for (let line = h.start; line <= h.end; line++) markers.set(line, `gutter-git-${h.kind}`);
    }
  }
  return markers;
}

/**
 * The text with one hunk put back to its base lines. Keeps the text's line
 * endings (CRLF stays CRLF) and its trailing newline.
 */
export function revertHunk(current, hunk) {
  const eol = /\r\n/.test(current) ? '\r\n' : '\n';
  const trailing = /\r?\n$/.test(current);
  const lines = splitLines(current);
  if (hunk.kind === 'deleted') lines.splice(hunk.start, 0, ...hunk.original);
  else lines.splice(hunk.start - 1, hunk.end - hunk.start + 1, ...hunk.original);
  return lines.join(eol) + (trailing || !lines.length ? eol : '');
}

/**
 * Where a workspace file sits in its Git repository: { folder, repoPath },
 * or null when it is not in one. (Also used by inline-blame.js.)
 */
export async function locateInRepo(path) {
  const folder = path.split('/').slice(0, -1).join('/') || '.';
  const status = await (await fetch(`/api/git/status?folder=${encodeURIComponent(folder)}`)).json();
  if (!status.isRepo) return null;
  const rootPrefix = status.root && status.root !== '.' ? `${status.root}/` : '';
  // file: the path as the workspace knows it; the server places it in the
  // repository (which may be outside the Otter install: a project's own).
  const repoPath = rootPrefix && path.startsWith(rootPrefix) ? path.slice(rootPrefix.length) : path;
  return { folder, repoPath, file: path };
}

/**
 * The editor side: fetches each file's base from /api/git/diff, keeps the
 * hunks current for the open file, and answers the gutter and the
 * next/previous/revert change commands.
 */
export function createGitGutter(ide) {
  const bases = new Map(); // path -> base text, or null (untracked / no repository)
  const pending = new Map();
  let computedFor = null; // { path, text, base }
  let hunks = [];
  let markers = new Map();

  async function fetchBase(path) {
    try {
      const where = await locateInRepo(path);
      if (!where) return null;
      const { folder, file } = where;
      const res = await fetch(`/api/git/diff?folder=${encodeURIComponent(folder)}&file=${encodeURIComponent(file)}`);
      if (!res.ok) return null;
      const data = await res.json();
      return data.tracked === false ? null : data.original;
    } catch {
      return null;
    }
  }

  // Fetch (again) the base of a file; redraws the gutter when it changed.
  function refresh(path = ide.currentFile) {
    if (!path) return Promise.resolve();
    if (pending.has(path)) return pending.get(path);
    const job = fetchBase(path).then(base => {
      pending.delete(path);
      const changed = !bases.has(path) || bases.get(path) !== base;
      bases.set(path, base);
      if (changed && path === ide.currentFile) {
        computedFor = null;
        ide.renderGutter?.((ide.currentCode || '').split('\n').length);
      }
    });
    pending.set(path, job);
    return job;
  }

  function compute() {
    const path = ide.currentFile;
    const text = ide.currentCode || '';
    const base = path ? bases.get(path) : undefined;
    if (computedFor && computedFor.path === path && computedFor.text === text && computedFor.base === base) return;
    computedFor = { path, text, base };
    hunks = typeof base === 'string' ? changeHunks(base, text) : [];
    markers = markersFromHunks(hunks);
  }

  const lineOf = () => ide.currentEditorLocation?.()?.line || 1;

  function goTo(direction) {
    compute();
    if (!hunks.length) return false;
    const here = lineOf();
    const starts = hunks.map(h => Math.max(h.start, 1));
    let target = direction > 0 ? starts.find(s => s > here) : [...starts].reverse().find(s => s < here);
    if (target === undefined) target = direction > 0 ? starts[0] : starts[starts.length - 1]; // wrap
    ide.goToLine?.(target);
    return true;
  }

  function hunkAt(line) {
    compute();
    return hunks.find(h => (h.kind === 'deleted' ? Math.max(h.start, 1) === line : line >= h.start && line <= h.end)) || null;
  }

  function revertAtCursor() {
    const hunk = hunkAt(lineOf());
    if (!hunk) return false;
    ide.replaceDocumentText(revertHunk(ide.currentCode || '', hunk));
    return true;
  }

  // Staging, committing, checking out or pulling changes the base: the Git
  // pane announces every status it reads (after its actions, on window
  // focus, and on its timer).
  // (Tests build the IDE under Node, where there is no window.)
  globalThis.addEventListener?.('otter:git-status', () => { if (ide.currentFile) refresh(ide.currentFile); });

  return {
    refresh,
    classFor(line) { compute(); return markers.get(line) || ''; },
    hunks() { compute(); return hunks; },
    nextChange: () => goTo(1),
    previousChange: () => goTo(-1),
    revertAtCursor,
    forget(path) { bases.delete(path); }
  };
}
