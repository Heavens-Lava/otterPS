// Indentation (js/editor/indentation.js): detection, .editorconfig parsing,
// globs and resolution.
import assert from 'node:assert/strict';
const {
  detectIndentation, parseEditorConfig, editorConfigGlob, resolveEditorConfig, indentationFor, indentUnit
} = await import('../js/editor/indentation.js');

// Detection.
assert.deepEqual(detectIndentation('if x\n  say 1\n  if y\n    say 2\n    .\n  .\n.'), { insertSpaces: true, size: 2 });
assert.deepEqual(detectIndentation('if x\n    say 1\n    if y\n        say 2\n.'), { insertSpaces: true, size: 4 });
assert.deepEqual(detectIndentation('if x\n\tsay 1\n\tif y\n\t\tsay 2\n.'), { insertSpaces: false, size: 4 });
assert.equal(detectIndentation('say 1\nsay 2\n'), null, 'no indentation: nothing to go on');
assert.deepEqual(detectIndentation('a\n  b\n    c\na\n  b\n'), { insertSpaces: true, size: 2 }, 'a two-level close is not a 4-step file');
assert.equal(indentUnit({ insertSpaces: true, size: 2 }), '  ');
assert.equal(indentUnit({ insertSpaces: false, size: 4 }), '\t');

// Parsing.
const cfg = parseEditorConfig('root = true\n# comment\n[*]\nindent_style = space\nindent_size = 4 ; trailing\n\n[*.{js,json}]\nindent_size=2\n');
assert.equal(cfg.root, true);
assert.deepEqual(cfg.sections.map(s => s.glob), ['*', '*.{js,json}']);
assert.equal(cfg.sections[0].props.indent_size, '4');

// Globs.
const m = (glob, p) => editorConfigGlob(glob).test(p);
assert.ok(m('*', 'main.ot') && m('*', 'src/deep/main.ot'), '* without a slash matches the name anywhere');
assert.ok(m('*.{js,json}', 'a/b.json') && !m('*.{js,json}', 'a/b.ot'));
assert.ok(m('lib/*.ot', 'lib/x.ot') && !m('lib/*.ot', 'src/lib/x.ot') && !m('lib/*.ot', 'lib/sub/x.ot'), 'a path glob is anchored');
assert.ok(m('lib/**.ot', 'lib/sub/x.ot'));
assert.ok(m('**/test/*.ot', 'test/a.ot') && m('**/test/*.ot', 'x/y/test/a.ot'));
assert.ok(m('[Mm]akefile', 'Makefile') && m('file?.txt', 'file1.txt') && !m('[!a]x', 'ax'));
assert.ok(m('v{1..3}.ot', 'v2.ot') && !m('v{1..3}.ot', 'v4.ot'));

// Resolution: nearer files win, later sections win, unset clears, root stops.
const configs = [
  { dir: 'projects/app', text: '[*.ot]\nindent_size = 2\n[legacy/*.ot]\nindent_style = tab\nindent_size = unset\n' },
  { dir: '.', text: 'root = true\n[*]\nindent_style = space\nindent_size = 4\nend_of_line = lf\ninsert_final_newline = true\ntrim_trailing_whitespace = false\n' }
];
assert.deepEqual(resolveEditorConfig('projects/app/main.ot', configs), {
  indentStyle: 'space', indentSize: 2, tabWidth: 2, endOfLine: 'lf', insertFinalNewline: true, trimTrailingWhitespace: false
});
const legacy = resolveEditorConfig('projects/app/legacy/old.ot', configs);
assert.equal(legacy.indentStyle, 'tab');
assert.equal(legacy.indentSize, undefined, 'unset removes the inherited size');
assert.equal(resolveEditorConfig('other/x.css', configs).indentSize, 4, 'the app folder config does not apply outside it');
assert.deepEqual(resolveEditorConfig('x.ot', []), {});
assert.equal(resolveEditorConfig('a.py', [{ dir: '.', text: '[*]\nindent_size = tab\ntab_width = 8\n' }]).indentSize, 8);

// What a file ends up with.
assert.deepEqual(indentationFor('if x\n  y\n.', {}), { insertSpaces: true, size: 2, tabWidth: 4, source: 'detected' });
assert.equal(indentationFor('if x\n  y\n.', { indentStyle: 'space', indentSize: 4 }).size, 4, '.editorconfig beats detection');
assert.equal(indentationFor('say 1', {}).source, 'default');
assert.equal(indentationFor('say 1', { indentStyle: 'tab' }).insertSpaces, false);

// Server: the .editorconfig files above a file, nearest first, stopping at
// root = true and never above the workspace.
{
  const fs = await import('node:fs');
  const os = await import('node:os');
  const path = await import('node:path');
  const { editorConfigChain } = await import('../server/editorconfig.mjs');
  const ws = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-ec-'));
  try {
    fs.mkdirSync(path.join(ws, 'a', 'b', 'c'), { recursive: true });
    fs.writeFileSync(path.join(ws, '.editorconfig'), '[*]\nindent_size = 8\n');
    fs.writeFileSync(path.join(ws, 'a', '.editorconfig'), 'root = true\n[*]\nindent_size = 4\n');
    fs.writeFileSync(path.join(ws, 'a', 'b', '.editorconfig'), '[*.ot]\nindent_size = 2\n');
    const chain = editorConfigChain(ws, path.join(ws, 'a', 'b', 'c', 'x.ot'));
    assert.deepEqual(chain.map(c => c.dir), ['a/b', 'a'], 'stops at root = true');
    assert.equal(resolveEditorConfig('a/b/c/x.ot', chain).indentSize, 2);
    assert.deepEqual(editorConfigChain(ws, path.join(ws, 'top.ot')).map(c => c.dir), ['.']);
    // "root = true" inside a section is a property, not the preamble.
    fs.writeFileSync(path.join(ws, 'a', '.editorconfig'), '[*]\nroot = true\n');
    assert.deepEqual(editorConfigChain(ws, path.join(ws, 'a', 'x.ot')).map(c => c.dir), ['a', '.']);
  } finally {
    fs.rmSync(ws, { recursive: true, force: true });
  }
}

console.log('Indentation tests passed (6 groups).');
