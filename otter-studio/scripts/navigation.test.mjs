import assert from 'node:assert/strict';
import {
  filterNavigationItems,
  flattenProjectFiles,
  symbolsForFile
} from '../js/navigation/symbol-index.js';

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

console.log('Studio navigation tests passed: project flattening, fuzzy Quick Open, and ordered outlines.');
