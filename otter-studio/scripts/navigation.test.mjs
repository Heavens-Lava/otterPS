import assert from 'node:assert/strict';
import {
  filterNavigationItems,
  flattenProjectFiles,
  NavigationHistory,
  symbolsForFile,
  definitionForWord,
  occurrencesForWord
} from '../js/navigation/symbol-index.js';
import { getHoverInfo, getWordAtOffset } from '../js/navigation/hover-provider.js';
import { getSignatureHelp } from '../js/navigation/signature-provider.js';

const files = flattenProjectFiles([
  { name: 'main.ot', path: 'main.ot', isDir: false },
  {
    name: 'lib',
    path: 'lib',
    isDir: true,
    children: [{ name: 'helpers.ot', path: 'lib/helpers.ot', isDir: false }]
  }
], 'projects/demo');

assert.deepEqual(files.map(file => file.path), [
  'projects/demo/main.ot',
  'projects/demo/lib/helpers.ot'
]);

const filtered = filterNavigationItems([
  { label: 'main.ot', detail: 'projects/demo/main.ot' },
  { label: 'helpers.ot', detail: 'projects/demo/lib/helpers.ot' }
], 'hlp');
assert.equal(filtered[0].label, 'helpers.ot', 'Quick Open must support compact fuzzy queries');

const symbols = symbolsForFile([
  { Name: 'later', File: 'projects/demo/main.ot', Line: 8, Column: 0 },
  { Name: 'earlier', File: 'projects/demo/main.ot', Line: 2, Column: 0 },
  { Name: 'other', File: 'projects/demo/lib/helpers.ot', Line: 1, Column: 0 }
], 'projects/demo/main.ot');
assert.deepEqual(symbols.map(symbol => symbol.Name), ['earlier', 'later']);

const definitions = [
  { Name: 'name', File: 'projects/demo/main.ot', Line: 2, Column: 0 },
  { Name: 'name', File: 'projects/demo/main.ot', Line: 12, Column: 4 },
  { Name: 'greet', File: 'projects/demo/main.ot', Line: 20, Column: 3 }
];
assert.equal(definitionForWord(definitions, 'projects/demo/main.ot', 'name', 14).Line, 12, 'nearest preceding declaration must win');
assert.equal(definitionForWord(definitions, 'projects/demo/main.ot', 'greet', 4).Line, 20, 'later declarations must resolve for forward function calls');
assert.equal(definitionForWord(definitions, 'projects/demo/main.ot', 'missing', 4), null, 'unknown words must not navigate arbitrarily');

const occurrences = occurrencesForWord('name is "name"\n# name is a comment\nsay name\n', 'name');
assert.deepEqual(occurrences.map(hit => [hit.line, hit.column]), [[1, 0], [3, 4]], 'occurrence search must ignore quoted strings and comments');

const history = new NavigationHistory(3);
history.record({ path: 'main.ot', line: 2, column: 0 });
history.record({ path: 'helper.ot', line: 5, column: 3 });
assert.deepEqual(history.back(), { path: 'main.ot', line: 2, column: 0 });
assert.deepEqual(history.forward(), { path: 'helper.ot', line: 5, column: 3 });
history.back();
history.record({ path: 'third.ot', line: 1, column: 0 });
assert.equal(history.canForward, false, 'new navigation must discard the old forward branch');

const sayDoc = getHoverInfo('say');
assert.equal(sayDoc?.kind, 'builtin', 'say keyword must resolve to builtin hover info');
assert.match(sayDoc?.description, /console/, 'say doc must explain console output');

const symbolDoc = getHoverInfo('greet', 'projects/demo/main.ot', [
  { name: 'greet', kind: 'function', line: 20, path: 'projects/demo/main.ot' }
]);
assert.equal(symbolDoc?.kind, 'function', 'user functions must resolve in hover info');
assert.equal(symbolDoc?.line, 20, 'symbol hover info must report the declaration line');

assert.equal(getWordAtOffset('say "hello"', 1), 'say', 'offset in single keyword must return keyword');
assert.equal(getWordAtOffset('for each file in files', 5), 'for each', 'offset in multi-word keyword must return full phrase');
assert.equal(getWordAtOffset('greet("world")', 2), 'greet', 'offset in function identifier must return identifier');

const addSig1 = getSignatureHelp('add 5 ');
assert.equal(addSig1?.label, 'add <value> to <collection>', 'add signature label matches');
assert.equal(addSig1?.activeParameter, 0, 'first param active before "to"');

const addSig2 = getSignatureHelp('add 5 to ');
assert.equal(addSig2?.activeParameter, 1, 'second param active after "to"');

const countSig = getSignatureHelp('count i from 1 to ');
assert.equal(countSig?.activeParameter, 2, 'third param active after "to" in count loop');

console.log('Studio navigation tests passed: project flattening, fuzzy Quick Open, ordered outlines, history, hover documentation, word extraction, and signature help.');



