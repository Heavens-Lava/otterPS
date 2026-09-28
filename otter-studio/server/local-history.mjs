// local-history.mjs - Local History: a copy of a file each time Studio
// saves it, independent of Git, so an earlier version can be compared and
// restored even when it was never committed.
//
// Stored outside the workspace (like VS Code's local history), so it never
// shows up in Git or in the project:
//   ~/.otter-studio/history/<key>/index.json   { path, entries: [...] }
//   ~/.otter-studio/history/<key>/<id>.txt     the file's text at that time
// <key> is a hash of the file's absolute path. OTTER_STUDIO_HISTORY_DIR
// moves the store (tests use a scratch folder).
//
// Kept per file: the newest MAX_ENTRIES versions; identical consecutive
// versions are stored once; files over MAX_BYTES are not recorded.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';

export const MAX_ENTRIES = 50;
export const MAX_BYTES = 2 * 1024 * 1024;

const historyRoot = () => process.env.OTTER_STUDIO_HISTORY_DIR || path.join(os.homedir(), '.otter-studio', 'history');

function keyFor(abs) {
  const normal = process.platform === 'win32' ? path.resolve(abs).toLowerCase() : path.resolve(abs);
  return crypto.createHash('sha1').update(normal).digest('hex').slice(0, 20);
}

const hashOf = (text) => crypto.createHash('sha1').update(text).digest('hex');

function readIndex(dir) {
  try {
    const index = JSON.parse(fs.readFileSync(path.join(dir, 'index.json'), 'utf8'));
    return Array.isArray(index.entries) ? index : { entries: [] };
  } catch {
    return { entries: [] };
  }
}

function writeIndex(dir, index) {
  fs.mkdirSync(dir, { recursive: true });
  const tmp = path.join(dir, `index.${process.pid}.tmp`);
  const text = JSON.stringify(index, null, 2);
  fs.writeFileSync(tmp, text, 'utf8');
  try {
    fs.renameSync(tmp, path.join(dir, 'index.json'));
  } catch {
    // Windows refuses to replace a file another process has open (a scan,
    // a concurrent read): write it in place instead.
    fs.writeFileSync(path.join(dir, 'index.json'), text, 'utf8');
    fs.rmSync(tmp, { force: true });
  }
}

/**
 * Record `content` as a version of the file. `reason` is shown in the list
 * ("save", "before save", ...). Never throws: history must not break a save.
 */
export function recordVersion(abs, relPath, content, reason = 'save') {
  try {
    if (typeof content !== 'string' || Buffer.byteLength(content, 'utf8') > MAX_BYTES) return null;
    const dir = path.join(historyRoot(), keyFor(abs));
    const index = readIndex(dir);
    const hash = hashOf(content);
    const last = index.entries[index.entries.length - 1];
    if (last && last.hash === hash) return last;
    let time = Date.now();
    if (last && time <= last.time) time = last.time + 1; // ids stay unique and ordered
    const entry = { id: String(time), time, size: Buffer.byteLength(content, 'utf8'), hash, reason };
    if (!fs.existsSync(dir)) pruneFiles();
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, `${entry.id}.txt`), content, 'utf8');
    index.path = relPath;
    index.entries.push(entry);
    if (index.entries.length > MAX_ENTRIES) index.entries.splice(0, index.entries.length - MAX_ENTRIES);
    writeIndex(dir, index);
    // Then drop every copy the index no longer lists. One at a time and best
    // effort: Windows can refuse to delete a file for a moment (an antivirus
    // scan); what is left now goes on a later save.
    const kept = new Set(index.entries.map(e => `${e.id}.txt`));
    for (const name of fs.readdirSync(dir)) {
      if (name.endsWith('.txt') && !kept.has(name)) {
        try { fs.rmSync(path.join(dir, name), { force: true }); } catch { /* next time */ }
      }
    }
    return entry;
  } catch {
    return null;
  }
}

// The store keeps at most MAX_FILES files' histories: before a new file's
// history starts, the least recently written ones beyond the limit go.
export const MAX_FILES = 500;
function pruneFiles() {
  const root = historyRoot();
  if (!fs.existsSync(root)) return;
  const dirs = fs.readdirSync(root, { withFileTypes: true }).filter(d => d.isDirectory())
    .map(d => {
      const full = path.join(root, d.name);
      let mtime = 0;
      try { mtime = fs.statSync(path.join(full, 'index.json')).mtimeMs; } catch { /* unreadable: oldest */ }
      return { full, mtime };
    });
  if (dirs.length < MAX_FILES) return;
  dirs.sort((a, b) => a.mtime - b.mtime);
  for (const d of dirs.slice(0, dirs.length - MAX_FILES + 1)) fs.rmSync(d.full, { recursive: true, force: true });
}

/** Versions of a file, newest first. */
export function listVersions(abs) {
  return readIndex(path.join(historyRoot(), keyFor(abs))).entries.slice().reverse()
    .map(({ id, time, size, reason }) => ({ id, time, size, reason }));
}

export function readVersion(abs, id) {
  if (!/^\d+$/.test(String(id))) return null;
  const file = path.join(historyRoot(), keyFor(abs), `${id}.txt`);
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
}

/** A renamed or moved file keeps its history (a folder: everything under it). */
export function moveHistory(fromAbs, toAbs, toRel) {
  try {
    const root = historyRoot();
    const move = (from, to, rel) => {
      const src = path.join(root, keyFor(from));
      const dst = path.join(root, keyFor(to));
      if (!fs.existsSync(src) || fs.existsSync(dst)) return;
      fs.renameSync(src, dst);
      const index = readIndex(dst);
      index.path = rel;
      writeIndex(dst, index);
    };
    if (fs.existsSync(toAbs) && fs.statSync(toAbs).isDirectory()) {
      const walk = (dir, relDir) => {
        for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
          const child = path.join(dir, e.name);
          const childRel = `${relDir}/${e.name}`;
          if (e.isDirectory()) walk(child, childRel);
          else move(path.join(fromAbs, path.relative(toAbs, child)), child, childRel);
        }
      };
      walk(toAbs, toRel);
    } else {
      move(fromAbs, toAbs, toRel);
    }
  } catch { /* history is best effort */ }
}

/**
 * GET /api/history/list?path=   -> { entries: [{ id, time, size, reason }] }
 * GET /api/history/entry?path=&id= -> { content }
 */
export function handleHistoryRoutes(req, res, pathname, urlObj, ctx) {
  if (!pathname.startsWith('/api/history/') || req.method !== 'GET') return false;
  const rel = urlObj.searchParams.get('path') || '';
  const abs = path.resolve(ctx.repoRoot, rel);
  if (!rel || !ctx.isInsideRepo(abs)) return ctx.sendJson(res, { error: 'Forbidden' }, 403), true;
  if (pathname === '/api/history/list') return ctx.sendJson(res, { path: rel, entries: listVersions(abs) }), true;
  if (pathname === '/api/history/entry') {
    const content = readVersion(abs, urlObj.searchParams.get('id'));
    if (content === null) return ctx.sendJson(res, { error: 'That version is no longer in the local history.' }, 404), true;
    return ctx.sendJson(res, { path: rel, content }), true;
  }
  return false;
}
