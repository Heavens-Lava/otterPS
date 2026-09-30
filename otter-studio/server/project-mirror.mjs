// project-mirror.mjs - A private copy of a project's program files, so a
// render can use the text open in the editor (not yet saved) for one file
// while every other file comes from disk - without writing anything into
// the user's project.
//
// Rendering a page of a multi-file project (OtterBoard's shell.ot) alone
// fails: its functions and data live in other files that only the entry
// (app.ot) brings together. So the Designer and Live App compile the
// project's entry from this mirror, with the open document's text in place.
//
//   syncMirror(projectRoot, overrides) -> mirrorRoot
//     overrides: { <absolute path in the project>: text }
//
// Only the files a compile reads are mirrored (.ot, .css, .json, .svg); images
// are served from the real project (the page's <base> points there).
// Unchanged files are not copied again; files gone from the project go
// from the mirror too.

import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const SKIP_DIRS = new Set(['node_modules', 'dist', 'dist-electron', '.git', '.otter', 'publish', 'out', 'bin', 'obj']);
// What a compile reads: the program, its stylesheets and data, and SVG icon
// sprites (Otter 1.1 embeds a page's `icons` sprite at compile time).
const MIRRORED = /\.(ot|css|json|svg)$/i;
const MAX_FILES = 2000;

export function mirrorRootFor(projectRoot) {
  const id = crypto.createHash('sha256').update(path.resolve(projectRoot).toLowerCase()).digest('hex').slice(0, 16);
  return path.join(os.tmpdir(), 'otter-studio-mirror', id);
}

// The folder holding the project manifest above `file`, or null.
export function projectRootFor(file, isInside = () => true) {
  let dir = path.dirname(file);
  while (isInside(dir)) {
    if (fs.existsSync(path.join(dir, 'otter.json')) || fs.existsSync(path.join(dir, 'project.json'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

function listProgramFiles(root) {
  const out = [];
  const walk = (dir, depth) => {
    if (depth > 8 || out.length >= MAX_FILES) return;
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const abs = path.join(dir, entry.name);
      if (entry.isDirectory()) { if (!SKIP_DIRS.has(entry.name) && !entry.name.startsWith('.')) walk(abs, depth + 1); }
      else if (entry.isFile() && MIRRORED.test(entry.name)) out.push(abs);
    }
  };
  walk(root, 0);
  return out;
}

export function syncMirror(projectRoot, overrides = {}) {
  const root = path.resolve(projectRoot);
  const mirror = mirrorRootFor(root);
  const wanted = new Set();
  const byPath = new Map(Object.entries(overrides).map(([p, text]) => [path.resolve(p).toLowerCase(), text]));
  for (const src of listProgramFiles(root)) {
    const rel = path.relative(root, src);
    const dest = path.join(mirror, rel);
    wanted.add(dest.toLowerCase());
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    const override = byPath.get(src.toLowerCase());
    if (override !== undefined) {
      // Only rewritten when different, so the compile cache (keyed on the
      // mirror's modification times) stays valid while nothing changes.
      let current = null;
      try { current = fs.readFileSync(dest, 'utf8'); } catch { /* new */ }
      if (current !== override) fs.writeFileSync(dest, override, 'utf8');
      continue;
    }
    let same = false;
    try {
      const a = fs.statSync(src);
      const b = fs.statSync(dest);
      same = a.size === b.size && Math.floor(a.mtimeMs) === Math.floor(b.mtimeMs);
    } catch { /* not copied yet */ }
    if (!same) {
      fs.copyFileSync(src, dest);
      const a = fs.statSync(src);
      fs.utimesSync(dest, a.atime, a.mtime);
    }
  }
  // Unsaved files not on disk yet (a stylesheet the designer made): into
  // the mirror as well, when they belong to the project.
  for (const [lowerPath, text] of byPath) {
    const rel = path.relative(root.toLowerCase(), lowerPath);
    if (!rel || rel.startsWith('..') || path.isAbsolute(rel) || !MIRRORED.test(lowerPath)) continue;
    const original = Object.keys(overrides).find(p => path.resolve(p).toLowerCase() === lowerPath);
    const dest = path.join(mirror, path.relative(root, path.resolve(original)));
    if (wanted.has(dest.toLowerCase())) continue;
    wanted.add(dest.toLowerCase());
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    let current = null;
    try { current = fs.readFileSync(dest, 'utf8'); } catch { /* new */ }
    if (current !== text) fs.writeFileSync(dest, text, 'utf8');
  }
  // Files removed from the project leave the mirror.
  for (const dest of listProgramFiles(mirror)) {
    if (!wanted.has(dest.toLowerCase())) fs.rmSync(dest, { force: true });
  }
  return mirror;
}
