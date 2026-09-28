// Editor extras (js/editor/editor-extras.js): whitespace dots, links in
// source, bookmarks and the TODO/FIXME scan; plus the command keymap.
import assert from 'node:assert/strict';

const { markWhitespace, findLinkAt, resolveSourcePath, createBookmarks, tasksFromSearch } = await import('../js/editor/editor-extras.js');
const { chordOf, displayChord, parseChord } = await import('../js/shell/keys.js');
const { changeHunks, markersFromHunks, revertHunk } = await import('../js/scm/gutter-changes.js');

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

// Git gutter: added, modified and deleted regions against the base text.
const base = 'a\nb\nc\nd\ne\n';
const edited = 'a\nB\nc\nnew\ne\nend\n'; // b changed, d replaced, "end" added
const hunks = changeHunks(base, edited);
assert.deepEqual(hunks.map(h => [h.kind, h.start, h.end]), [['modified', 2, 2], ['modified', 4, 4], ['added', 6, 6]]);
assert.deepEqual(changeHunks(base, 'a\nb\ne\n').map(h => [h.kind, h.start, h.original]), [['deleted', 2, ['c', 'd']]]);
assert.deepEqual(changeHunks(base, 'b\nc\nd\ne\n').map(h => [h.kind, h.start]), [['deleted', 0]], 'deleted at the top');
const markers = markersFromHunks(changeHunks(base, 'b\nc\nd\nx\n'));
assert.equal(markers.get(1), 'gutter-git-deleted-above');
assert.equal(markers.get(4), 'gutter-git-modified');
assert.equal(changeHunks(base, base).length, 0, 'unchanged');
// Reverting a hunk puts the base lines back, keeping CRLF.
assert.equal(revertHunk(edited, hunks[0]), 'a\nb\nc\nnew\ne\nend\n');
assert.equal(revertHunk(edited, hunks[2]), 'a\nB\nc\nnew\ne\n');
assert.equal(revertHunk('a\r\nb\r\ne\r\n', changeHunks(base, 'a\nb\ne\n')[0]), 'a\r\nb\r\nc\r\nd\r\ne\r\n');

// Inline blame: the buffer is matched to the blamed text, so edits above a
// line do not shift its answer, and new lines read "Uncommitted change".
const { mapBufferToBlame, annotationFor } = await import('../js/scm/inline-blame.js');
const blame = [
  { line: 1, text: 'say 1', hash: 'a'.repeat(40), author: 'Ana', date: '2026-01-01T10:00:00Z', summary: 'first' },
  { line: 2, text: 'say 2', hash: 'b'.repeat(40), author: 'Ben', date: '2026-01-05T10:00:00Z', summary: 'second' }
];
const map = mapBufferToBlame(blame, 'say 0\nsay 1\nsay 2\n');
assert.equal(map.get(1), undefined, 'a new line has no blame');
assert.equal(map.get(2).author, 'Ana');
assert.equal(map.get(3).author, 'Ben', 'shifted by the new line above');
assert.equal(annotationFor(null).text, 'Uncommitted change');
assert.equal(annotationFor(map.get(3), Date.parse('2026-01-07T10:00:00Z')).text, 'Ben, 2 days ago · second');
assert.equal(annotationFor({ ...blame[0], uncommitted: true }).text, 'Uncommitted change');

// Keys: chords from events, display and parsing.
assert.equal(chordOf({ ctrlKey: true, altKey: true, key: 'k', code: 'KeyK' }), 'ctrl+alt+k');
assert.equal(chordOf({ altKey: true, key: '˚', code: 'KeyK' }), 'alt+k', 'Alt letters use the key cap');
assert.equal(chordOf({ key: 'F11', code: 'F11' }), 'f11');
assert.equal(displayChord('ctrl+alt+k'), 'Ctrl+Alt+K');
assert.equal(parseChord('Ctrl + Shift + Up'), 'ctrl+shift+arrowup');
assert.equal(parseChord('Shift+Ctrl+G'), 'ctrl+shift+g', 'modifiers in a fixed order');
assert.equal(parseChord('Ctrl+'), null);

console.log('Editor extras tests passed (7 groups).');
