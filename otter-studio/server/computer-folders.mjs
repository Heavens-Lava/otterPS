// computer-folders.mjs - File > Open Folder > This computer: a project folder
// anywhere, not only inside the workspace.
//
// Browsing lists folder names only (never files or their contents). Opening
// a folder adds it to the workspace roots - the same trust as
// `otter studio <folder>` gives a folder on the command line, no more - and
// remembers it, so it is still open to Studio next time. A whole drive
// (C:\, /) is refused: choose the project folder itself.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const SKIP = new Set(['node_modules', '$recycle.bin', 'system volume information', 'windows', 'program files', 'program files (x86)', 'programdata']);

const isDir = (p) => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };

export function stateFile() {
  const dir = process.env.OTTER_STUDIO_STATE_DIR || path.join(os.homedir(), '.otter-studio');
  return path.join(dir, 'workspaces.json');
}

// Folders opened through "This computer" before, that still exist.
export function loadSavedRoots() {
  try {
    const saved = JSON.parse(fs.readFileSync(stateFile(), 'utf8'));
    return (Array.isArray(saved.folders) ? saved.folders : []).filter(p => typeof p === 'string' && isDir(p));
  } catch {
    return [];
  }
}

export function saveRoot(folder) {
  const file = stateFile();
  const folders = loadSavedRoots();
  if (!folders.some(p => p.toLowerCase() === folder.toLowerCase())) folders.push(folder);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ folders }, null, 2) + '\n');
}

export function isDriveRoot(abs) {
  const full = path.resolve(abs);
  return path.parse(full).root.replace(/[\\/]+$/, '') === full.replace(/[\\/]+$/, '');
}

// Where to start: your home folder and its usual places, then the drives.
export function computerPlaces() {
  const home = os.homedir();
  const places = [{ name: 'Home', path: home, kind: 'place' }];
  for (const name of ['Desktop', 'Documents', 'Downloads', path.join('OneDrive', 'Documents')]) {
    const p = path.join(home, name);
    if (isDir(p)) places.push({ name: name.replace(/\\/g, ' / '), path: p, kind: 'place' });
  }
  if (process.platform === 'win32') {
    for (const letter of 'CDEFGHIJKLMNOPQRSTUVWXYZ') {
      const root = `${letter}:\\`;
      if (isDir(root)) places.push({ name: `${letter}: drive`, path: root, kind: 'drive' });
    }
  } else {
    places.push({ name: 'Computer', path: '/', kind: 'drive' });
  }
  return places;
}

function describe(childAbs, name) {
  let names = [];
  try { names = fs.readdirSync(childAbs); } catch { return null; }
  return {
    name,
    path: childAbs,
    isProject: names.includes('project.json') || names.includes('otter.json'),
    hasOtter: names.some(n => n.toLowerCase().endsWith('.ot')),
    hasFolders: names.some(n => !n.startsWith('.') && !SKIP.has(n.toLowerCase()) && isDir(path.join(childAbs, n)))
  };
}

// The folders inside one folder. No path: the starting places.
export function listComputerFolder(folder) {
  if (!folder) return { path: '', parent: null, dirs: computerPlaces().map(p => ({ ...(describe(p.path, p.name) || { name: p.name, path: p.path }), kind: p.kind })) };
  const abs = path.resolve(folder);
  if (!isDir(abs)) {
    const err = new Error('That folder does not exist.');
    err.status = 404;
    throw err;
  }
  const dirs = [];
  let entries = [];
  try { entries = fs.readdirSync(abs, { withFileTypes: true }); } catch {
    const err = new Error('Studio cannot read that folder.');
    err.status = 403;
    throw err;
  }
  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith('.') || entry.name.startsWith('$') || SKIP.has(entry.name.toLowerCase())) continue;
    const d = describe(path.join(abs, entry.name), entry.name);
    if (d) dirs.push(d);
  }
  dirs.sort((a, b) => (b.isProject - a.isProject) || a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
  const parent = isDriveRoot(abs) ? '' : path.dirname(abs);
  return { path: abs, parent, dirs };
}
