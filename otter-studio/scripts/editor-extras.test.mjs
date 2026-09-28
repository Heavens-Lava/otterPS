// Editor extras (js/editor/editor-extras.js): whitespace dots, links in
// source, bookmarks and the TODO/FIXME scan; plus the command keymap.
import assert from 'node:assert/strict';

const { markWhitespace, findLinkAt, resolveSourcePath, createBookmarks, tasksFromSearch } = await import('../js/editor/editor-extras.js');
const { chordOf, displayChord, parseChord } = await import('../js/shell/keys.js');

// Whitespace: spaces in text get a dot span; tags and attributes are untouched.
assert.equal(markWhitespace('<span class="k">say</span> "a b"'),
  '<span class="k">say</span><span class="ws-dot"> </span>"a<span class="ws-dot"> </span>b"');

// Links: URLs and quoted relative paths under the cursor.
const line = 'data is read file "data/customers.csv"  # see https://example.com/docs.';
assert.deepEqual(findLinkAt(line, 25), { type: 'path', target: 'data/customers.csv' });
assert.deepEqual(findLinkAt(line, line.indexOf('example') + 2), { type: 'url', target: 'https://example.com/docs' });
assert.equal(findLinkAt(line, 2), null);
assert.equal(findLinkAt('say "hello world"', 8), null, 'a plain string is not a path');
assert.equal(resolveSourcePath('projects/app/main.ot', 'data/x.csv'), 'projects/app/data/x.csv');
assert.equal(resolveSourcePath('projects/app/main.ot', '../shared/y.ot'), 'projects/shared/y.ot');
assert.equal(resolveSourcePath('main.ot', '../../x'), null, 'cannot climb out');

// Bookmarks: toggle, sorted, next/previous wrap around, kept in storage.
const store = new Map();
const storage = { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v), removeItem: k => store.delete(k) };
const marks = createBookmarks(storage);
marks.toggle('a.ot', 10); marks.toggle('a.ot', 3); marks.toggle('a.ot', 7);
assert.deepEqual(marks.lines('a.ot'), [3, 7, 10]);
assert.equal(marks.next('a.ot', 7, 1), 10);
assert.equal(marks.next('a.ot', 10, 1), 3, 'wraps to the first');
assert.equal(marks.next('a.ot', 3, -1), 10, 'wraps to the last');
marks.toggle('a.ot', 7);
assert.deepEqual(createBookmarks(storage).lines('a.ot'), [3, 10], 'persisted');
assert.equal(marks.next('b.ot', 1, 1), null);

// Tasks: only tags inside comments, most urgent first.
const tasks = tasksFromSearch([
  { path: 'p/main.ot', line: 4, column: 2, preview: '# TODO: load the real data' },
  { path: 'p/main.ot', line: 9, column: 2, preview: '# FIXME crashes on empty input' },
  { path: 'p/styles.css', line: 1, column: 3, preview: '/* NOTE: brand colors */' },
  { path: 'p/main.ot', line: 12, column: 5, preview: 'say "TODO list"' }
]);
assert.deepEqual(tasks.map(t => [t.tag, t.text]), [
  ['FIXME', 'crashes on empty input'], ['TODO', 'load the real data'], ['NOTE', 'brand colors']
]);

// Keys: chords from events, display and parsing.
assert.equal(chordOf({ ctrlKey: true, altKey: true, key: 'k', code: 'KeyK' }), 'ctrl+alt+k');
assert.equal(chordOf({ altKey: true, key: '˚', code: 'KeyK' }), 'alt+k', 'Alt letters use the key cap');
assert.equal(chordOf({ key: 'F11', code: 'F11' }), 'f11');
assert.equal(displayChord('ctrl+alt+k'), 'Ctrl+Alt+K');
assert.equal(parseChord('Ctrl + Shift + Up'), 'ctrl+shift+arrowup');
assert.equal(parseChord('Shift+Ctrl+G'), 'ctrl+shift+g', 'modifiers in a fixed order');
assert.equal(parseChord('Ctrl+'), null);

console.log('Editor extras tests passed (5 groups).');
