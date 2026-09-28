// Settings certification: the store merges saved values over the defaults,
// persists changes, notifies listeners, resets; and the shell exposes the
// dialog and applies the editor settings.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createSettings, DEFAULT_SETTINGS } from '../js/shell/settings.js';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

function fakeStorage(initial = {}) {
  const map = new Map(Object.entries(initial));
  return { getItem: (k) => (map.has(k) ? map.get(k) : null), setItem: (k, v) => map.set(k, v), removeItem: (k) => map.delete(k), map };
}

// 1. Defaults and merge.
let storage = fakeStorage();
let settings = createSettings(storage);
assert.equal(settings.get('editor.fontSize'), 13);
assert.equal(settings.get('files.trimTrailingWhitespace'), true);
storage = fakeStorage({ 'otter-studio-settings': JSON.stringify({ editor: { fontSize: 15 }, files: { formatOnSave: true } }) });
settings = createSettings(storage);
assert.equal(settings.get('editor.fontSize'), 15, 'saved values win');
assert.equal(settings.get('editor.autoClosePairs'), true, 'unsaved keys keep their defaults');
assert.equal(settings.get('files.formatOnSave'), true);
storage = fakeStorage({ 'otter-studio-settings': '{not json' });
settings = createSettings(storage);
assert.equal(settings.get('editor.fontSize'), DEFAULT_SETTINGS.editor.fontSize, 'corrupt settings fall back to the defaults');
console.log('  pass  defaults, saved values merged over them, corrupt storage tolerated');

// 2. Set, persist, notify, reset.
storage = fakeStorage();
settings = createSettings(storage);
const seen = [];
settings.subscribe((p, v) => seen.push([p, v]));
settings.set('editor.indentGuides', false);
assert.equal(settings.get('editor.indentGuides'), false);
assert.deepEqual(JSON.parse(storage.map.get('otter-studio-settings')).editor.indentGuides, false, 'change persisted');
settings.set('editor.indentGuides', false);
assert.equal(seen.length, 1, 'setting the same value again does not notify');
assert.deepEqual(DEFAULT_SETTINGS.editor.indentGuides, true, 'the defaults object is never mutated');
settings.reset();
assert.equal(settings.get('editor.indentGuides'), true);
assert.equal(storage.map.has('otter-studio-settings'), false);
assert.deepEqual(seen[seen.length - 1], ['*', null]);
console.log('  pass  set persists and notifies once; reset restores defaults and clears storage');

// 3. Shell wiring.
const [indexHtml, shellJs, ideJs] = await Promise.all([
  fs.readFile(path.join(studioRoot, 'index.html'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'js', 'shell', 'studio-shell.js'), 'utf8'),
  fs.readFile(path.join(studioRoot, 'js', 'ide.js'), 'utf8')
]);
assert.match(indexHtml, /id="menuItemSettings"/, 'File menu must offer Settings...');
assert.match(indexHtml, /css\/settings\.css/, 'the settings stylesheet must be linked');
assert.match(shellJs, /window\.otterSettings = settings/, 'the shell must publish the settings store');
assert.match(ideJs, /this\.setting\('editor\.autoClosePairs'/, 'the editor must consult the auto-close setting');
assert.match(ideJs, /this\.setting\('files\.formatOnSave'/, 'saving must consult format-on-save');
assert.match(ideJs, /this\.setting\('editor\.indentGuides'/, 'rendering must consult indent guides');
assert.match(ideJs, /this\.applySaveSettings\(\);[^]{0,600}?res = await fetch\('\/api\/file'/, 'save settings must be applied before the file is written');
console.log('  pass  Settings dialog is reachable from File and the editor reads the settings it exposes');

console.log('Settings certification passed (3 checks).');
