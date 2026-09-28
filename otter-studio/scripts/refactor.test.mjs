// Refactoring: Extract Function works on whole lines and keeps the program's
// meaning (js/language/otter-language-service.js prepareExtractLines).
import assert from 'node:assert/strict';
const { otterLanguageService: s } = await import('../js/language/otter-language-service.js');

const lines = (...l) => [...l, ''].join('\n');

// Nested blocks keep their structure; the definition goes before the call.
{
  const code = lines('say "one"', 'if ready', '    say "two"', '    if again', '        say "deep"', 'say "four"');
  const r = s.prepareExtractLines(code, 2, 5, 'middle');
  assert.equal(r.newCode, lines('say "one"', 'to middle', '    if ready', '        say "two"', '        if again', '            say "deep"', '.', '', 'middle', 'say "four"'));
}

// From inside a block: the call keeps the indentation; the definition goes
// before the enclosing top-level statement.
{
  const code = lines('if ready', '    say "two"', '    say "three"', 'say "four"');
  const r = s.prepareExtractLines(code, 2, 3, 'both');
  assert.equal(r.newCode, lines('to both', '    say "two"', '    say "three"', '.', '', 'if ready', '    both', 'say "four"'));
}

// Inside a function: parameters and earlier locals the lines use are passed.
{
  const code = lines('to greet name', '    greeting is "Hello"', '    say greeting name', '    say "done"', '.', 'greet "Jeff"');
  const r = s.prepareExtractLines(code, 3, 3, 'part');
  assert.deepEqual(r.parameters, ['name', 'greeting']);
  assert.match(r.newCode, /^to part name and greeting\n    say greeting name\n\.\n/);
  assert.match(r.newCode, /\n    part name and greeting\n/);
}

// Refused: partial blocks, the tail of a block, and changes that could not
// reach the code around the selection.
{
  const code = lines('if ready', '    say "two"', 'otherwise', '    say "no"', 'say "end"');
  assert.match(s.prepareExtractLines(code, 1, 1, 'x').error, /part of a block/);
  assert.match(s.prepareExtractLines(code, 3, 4, 'x').error, /end of an earlier block/);
  assert.match(s.prepareExtractLines(lines('to f n', '    n is 2', '.'), 2, 2, 'x').error, /changes 'n'/);
  assert.match(s.prepareExtractLines(lines('x is 5', 'say x'), 1, 1, 'f').error, /'x' is set in the selection and used after it/);
  assert.match(s.prepareExtractLines(lines('say 1'), 1, 1, '2bad').error, /not a valid Otter identifier/);
}

// CRLF files stay CRLF.
{
  const code = 'say "a"\r\nsay "b"\r\n';
  assert.equal(s.prepareExtractLines(code, 2, 2, 'b').newCode, 'say "a"\r\nto b\r\n    say "b"\r\n.\r\n\r\nb\r\n');
}

console.log('Refactoring tests passed (5 groups).');
