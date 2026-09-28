// Find and replace (js/editor/find.js): options, in-selection, preserve case.
import assert from 'node:assert/strict';
const { buildFindRegex, findAll, replacementFor, replaceMatches, applyCase } = await import('../js/editor/find.js');

const text = 'Name is "x"\nsay name\nnameList is []\nsay NAME';
const count = (q, o, r) => findAll(text, buildFindRegex(q, o), r).length;
assert.equal(count('name', {}), 4, 'case-insensitive by default');
assert.equal(count('name', { caseSensitive: true }), 2);
assert.equal(count('name', { wholeWord: true }), 3, 'nameList is not a whole word');
assert.equal(count('n.me', {}), 0, 'plain text: the dot is literal');
assert.equal(count('n.me', { regex: true }), 4);
assert.equal(count('x"\nsay', { regex: true }), 1, 'multi-line search with \n');
assert.match(buildFindRegex('(', { regex: true }).error, /Invalid pattern/);
// In selection: only matches fully inside the range.
const second = text.indexOf('say name');
assert.equal(count('name', {}, { start: second, end: second + 'say name'.length }), 1);

// Replacement: groups and preserve case.
const m = findAll('say Name', buildFindRegex('(n)ame', { regex: true }))[0];
assert.equal(replacementFor(m, '$1ick', { regex: true }), 'Nick');
assert.equal(applyCase('HELLO', 'world'), 'WORLD');
assert.equal(applyCase('Hello', 'world'), 'World');
assert.equal(applyCase('hello', 'World'), 'world');
assert.equal(replaceMatches('Name name NAME', findAll('Name name NAME', buildFindRegex('name', {})), 'person', { preserveCase: true }), 'Person person PERSON');
assert.equal(findAll('aaa', buildFindRegex('x*', { regex: true })).length, 0, 'empty matches do not loop');

console.log('Find tests passed.');
