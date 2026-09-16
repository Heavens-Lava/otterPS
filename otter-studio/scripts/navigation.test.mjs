import assert from 'node:assert/strict';
import {
  filterNavigationItems,
  flattenProjectFiles,
  NavigationHistory,
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

const history = new NavigationHistory(3);
history.record({ path: 'main.ot', line: 2, column: 0 });
history.record({ path: 'helper.ot', line: 5, column: 3 });
assert.deepEqual(history.back(), { path: 'main.ot', line: 2, column: 0 });
assert.deepEqual(history.forward(), { path: 'helper.ot', line: 5, column: 3 });
history.back();
history.record({ path: 'third.ot', line: 1, column: 0 });
assert.equal(history.canForward, false, 'new navigation must discard the old forward branch');

console.log('Studio navigation tests passed: project flattening, fuzzy Quick Open, ordered outlines, and history.');
