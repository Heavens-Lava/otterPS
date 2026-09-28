// Editing assistance certification: auto-closing pairs, Otter block closing
// on Enter, save-time cleanup and indent guides - the pure rules the editor
// applies while typing.
import assert from 'node:assert/strict';
import { autoClosePair, backspacePair, enterKey, prepareForSave, renderIndentGuides, splitLineEnding, withLineEnding } from '../js/editor/editing-assist.js';

// 1. Pairs.
let r = autoClosePair('say ', 4, 4, '"');
assert.equal(r.text, 'say ""');
assert.equal(r.start, 5, 'caret sits between the quotes');
r = autoClosePair('say ""', 5, 5, '"');
assert.equal(r.text, 'say ""', 'typing the closing quote steps over it');
assert.equal(r.start, 6);
r = autoClosePair('say "hello', 10, 10, '"');
assert.equal(r, null, 'inside a string the quote is typed as is');
r = autoClosePair('say hello', 4, 9, '"');
assert.equal(r.text, 'say "hello"', 'a selection is wrapped');
assert.equal(r.start, 5); assert.equal(r.end, 10);
r = autoClosePair('x is ', 5, 5, '(');
assert.equal(r.text, 'x is ()');
r = autoClosePair('x is ()', 6, 6, ')');
assert.equal(r.text, 'x is ()', 'a closer that is already there is stepped over');
assert.equal(r.start, 7);
r = autoClosePair('say word', 4, 4, '"');
assert.equal(r, null, 'no pairing right before a word');
r = backspacePair('say ""', 5, 5);
assert.equal(r.text, 'say ', 'backspace in an empty pair removes both');
assert.equal(backspacePair('say "a"', 6, 6), null);
console.log('  pass  auto-closing quotes and brackets: insert, step over, wrap, backspace');

// 2. Enter.
r = enterKey('if x is 1', 9, 9);
assert.equal(r.text, 'if x is 1\n    \n.', 'a new block gets its body line and closing period');
assert.equal(r.text.slice(r.start), '\n.', 'the caret is on the body line');
r = enterKey('if x is 1\n    say "yes"\n.', 9, 9);
assert.equal(r.text, 'if x is 1\n    \n    say "yes"\n.', 'a block that has a body only gets the indent');
r = enterKey('    if x is 1\n    .', 13, 13);
assert.equal(r.text, '    if x is 1\n        \n    .', 'a block that already has its period only gets the indent');
r = enterKey('if x is 1', 9, 9, { autoCloseBlocks: false });
assert.equal(r.text, 'if x is 1\n    ', 'the setting turns the closing period off');
r = enterKey('    say "hi"', 12, 12);
assert.equal(r.text, '    say "hi"\n    ', 'an ordinary line keeps its indentation');
r = enterKey('if x is 1 and', 4, 4);
assert.equal(r.text, 'if x\n is 1 and', 'Enter in the middle of a line never inserts a period');
r = enterKey('to greet name', 13, 13);
assert.equal(r.text, 'to greet name\n    \n.', '`to` opens a function block');
r = enterKey('try', 3, 3);
assert.equal(r.text, 'try\n    \n.', '`try` opens a block');
console.log('  pass  Enter after a block opener indents and writes the closing period when the block is new');

// 3. Save cleanup.
assert.equal(prepareForSave('say "a"   \n  \nsay "b"'), 'say "a"\n\nsay "b"\n');

// Line endings: the editor holds LF text; the file's EOL comes back on save.
assert.deepEqual(splitLineEnding('a\r\nb\r\n'), { text: 'a\nb\n', eol: 'CRLF' });
assert.deepEqual(splitLineEnding('a\nb\n'), { text: 'a\nb\n', eol: 'LF' });
assert.deepEqual(splitLineEnding('\n'), { text: '\n', eol: 'LF' });
assert.deepEqual(splitLineEnding(''), { text: '', eol: 'CRLF' }, 'new files default to CRLF');
assert.equal(withLineEnding('a\nb\n', 'CRLF'), 'a\r\nb\r\n');
assert.equal(withLineEnding('a\r\nb', 'LF'), 'a\nb');
assert.equal(withLineEnding(splitLineEnding('x\r\ny\r\n').text, 'CRLF'), 'x\r\ny\r\n', 'round trip');
assert.equal(prepareForSave('say "a"  ', { trimTrailingWhitespace: false, insertFinalNewline: false }), 'say "a"  ');
assert.equal(prepareForSave(''), '', 'an empty file stays empty');
console.log('  pass  save cleanup trims trailing whitespace and ends the file with a newline, per setting');

// 4. Indent guides keep every character in place.
const highlight = (s) => `<t>${s}</t>`;
assert.equal(renderIndentGuides('say "a"', highlight), '<t>say "a"</t>');
assert.equal(renderIndentGuides('        say "a"', highlight), '<span class="indent-guide">    </span><span class="indent-guide">    </span><t>say "a"</t>');
assert.equal(renderIndentGuides('      x', highlight), '<span class="indent-guide">    </span>  <t>x</t>', 'leftover spaces stay as spaces');
const textOf = (html) => html.replace(/<[^>]+>/g, '');
assert.equal(textOf(renderIndentGuides('        say "a"', highlight)), '        say "a"', 'the text content is unchanged');
assert.equal(renderIndentGuides('\tsay', highlight), '<t>\tsay</t>', 'tab-indented lines are left alone');
console.log('  pass  indent guides wrap whole indent levels without changing the text');

console.log('Editing assistance certification passed (4 checks).');
