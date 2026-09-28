// Command registry certification: one list of commands feeds the palette
// and the shortcuts dialog; ids are unique; unavailable commands hide.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createCommandRegistry, defaultCommands, formatShortcut } from '../js/shell/commands.js';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// 1. Registry semantics.
const registry = createCommandRegistry();
const ran = [];
registry.register({ id: 'a.one', title: 'One', category: 'B', shortcut: 'Ctrl+1', run: () => ran.push('one') });
registry.register({ id: 'a.two', title: 'Two', category: 'A', run: () => ran.push('two') });
registry.register({ id: 'a.hidden', title: 'Hidden', category: 'A', when: () => false, run: () => ran.push('hidden') });
assert.throws(() => registry.register({ id: 'a.one', run() {} }), /twice/, 'duplicate ids are refused');
assert.throws(() => registry.register({ title: 'no id' }), /needs an id/);
assert.deepEqual(registry.list().map(c => c.id), ['a.two', 'a.one'], 'sorted by category then title; unavailable hidden');
assert.deepEqual(registry.list({ includeUnavailable: true }).map(c => c.id), ['a.hidden', 'a.two', 'a.one']);
await registry.run('a.one');
assert.equal(await registry.run('a.hidden'), false, 'an unavailable command does not run');
assert.deepEqual(ran, ['one']);
await assert.rejects(() => registry.run('nope'), /Unknown command/);
const items = registry.toPaletteItems();
assert.equal(items[1].type, 'command');
assert.equal(items[1].label, 'One');
assert.equal(items[1].shortcut, 'Ctrl+1');
await items[1].run();
assert.deepEqual(ran, ['one', 'one'], 'palette items run their command');
console.log('  pass  registry: unique ids, availability, sorted listing, palette items that run');

// 2. Shortcut formatting.
assert.equal(formatShortcut('ctrl+shift+p'), 'Ctrl+Shift+P');
assert.equal(formatShortcut('Ctrl+K Ctrl+S'), 'Ctrl+K Ctrl+S');
assert.equal(formatShortcut(''), '');
console.log('  pass  shortcuts format consistently');

// 3. The default command set is complete and consistent.
const calls = [];
const stub = new Proxy({}, { get: (_t, name) => (...args) => calls.push(String(name)) });
const commands = defaultCommands({
  ide: stub, setMode: (m) => calls.push('mode:' + m), openNewProjectModal: () => calls.push('newProject'),
  openSettings: () => calls.push('settings'), openPackageDialog: () => calls.push('package'), openShortcuts: () => calls.push('shortcuts'),
  showWelcome: () => calls.push('welcome'), toggleTheme: () => calls.push('theme'), byId: () => null
});
const all = createCommandRegistry();
all.registerAll(commands);
assert.ok(all.size() >= 35, `expected a rich default set, got ${all.size()}`);
const ids = commands.map(c => c.id);
assert.equal(new Set(ids).size, ids.length, 'default ids are unique');
for (const c of commands) {
  assert.match(c.id, /^[a-z]+\.[a-zA-Z]+$/, `id "${c.id}" follows category.name`);
  assert.ok(c.title && c.category, `${c.id} has a title and category`);
  if (c.shortcut) assert.equal(c.shortcut, formatShortcut(c.shortcut), `${c.id} shortcut "${c.shortcut}" is already in display form`);
}
const shortcuts = commands.filter(c => c.shortcut).map(c => c.shortcut);
assert.equal(new Set(shortcuts).size, shortcuts.length, 'no two commands claim the same shortcut');
for (const id of ['file.save', 'edit.format', 'view.designer', 'build.desktopApp', 'help.commands']) {
  await all.run(id);
}
assert.deepEqual(calls, ['saveCurrentFile', 'formatCurrentDocument', 'mode:designer', 'package', 'openNavigationPalette'], 'commands route to the existing IDE entry points');
console.log('  pass  default commands: unique ids and shortcuts, and they route to the existing entry points');

// 4. Shell wiring (checked once the palette is connected).
const ideJs = await fs.readFile(path.join(studioRoot, 'js', 'ide.js'), 'utf8');
const shellJs = await fs.readFile(path.join(studioRoot, 'js', 'shell', 'studio-shell.js'), 'utf8');
assert.match(ideJs, /mode === 'commands'/, 'the navigation palette must have a commands mode');
assert.match(ideJs, /rawVal\.startsWith\('>'\)/, '">" in the palette switches to commands');
assert.match(shellJs, /window\.otterCommands = /, 'the shell must publish the registry');
console.log('  pass  the palette lists commands and ">" reaches them');

console.log('Command registry certification passed (4 checks).');
