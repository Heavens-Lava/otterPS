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
assert.equal(definitionForWord(definitions, 'projects/demo/main.ot', 'greet', 25).Line, 20, 'function calls at or after declaration must resolve');
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

import { otterLanguageService } from '../js/language/otter-language-service.js';
import { getBuiltinMetadata } from '../js/language/otter-metadata.js';

// --- Authoritative Metadata Verification ---
const metadataSay = getBuiltinMetadata('say');
assert.equal(metadataSay?.category, 'statement');
assert.equal(metadataSay?.syntax, 'say <expression>');
const metadataIf = getBuiltinMetadata('if');
assert.match(metadataIf?.doc, /indented block/);

// --- User-defined function hover with parameters ---
const fnHover = getHoverInfo('calculateScore', 'projects/demo/main.ot', [
  {
    name: 'calculateScore',
    kind: 'function',
    line: 15,
    path: 'projects/demo/main.ot',
    parameters: ['base', 'bonus']
  }
]);
assert.equal(fnHover?.kind, 'function');
assert.equal(fnHover?.signature, 'to calculateScore base and bonus');
assert.match(fnHover?.description, /2 parameters/);
assert.deepEqual(fnHover?.parameters, ['base', 'bonus']);

// --- Known variable hover with declaration info (no speculative types) ---
const varHover = getHoverInfo('userCount', 'projects/demo/main.ot', [
  {
    name: 'userCount',
    kind: 'variable',
    line: 5,
    path: 'projects/demo/main.ot'
  }
]);
assert.equal(varHover?.kind, 'variable');
assert.equal(varHover?.signature, 'variable userCount');
assert.match(varHover?.description, /Declared at line 5/);

// --- Cross-File Go to Definition ---
const workspaceSymbolsPool = [
  { Name: 'helperFn', Kind: 'function', File: 'projects/demo/lib/helpers.ot', Line: 10, Column: 3 }
];
const crossDef = definitionForWord(
  [{ Name: 'localFn', Kind: 'function', File: 'projects/demo/main.ot', Line: 2, Column: 0 }],
  'projects/demo/main.ot',
  'helperFn',
  1,
  workspaceSymbolsPool
);
assert.equal(crossDef?.File, 'projects/demo/lib/helpers.ot', 'cross-file definition resolves from workspace pool');
assert.equal(crossDef?.Line, 10);

// --- Scope-Aware Find References ---
const sampleSource = `
score is 10
say "score in quotes is not a ref" # score in comment is not a ref
score is score plus 5
`;
const scoreRefs = otterLanguageService.findReferences('score', 'main.ot', sampleSource);
assert.equal(scoreRefs.length, 3, 'findReferences must find 3 variable references and skip strings/comments');
assert.equal(scoreRefs[0].line, 2);
assert.equal(scoreRefs[1].line, 4);
assert.equal(scoreRefs[2].line, 4);

// --- Safe Rename Symbol with Preview Diff ---
const renamePlan = otterLanguageService.prepareRename(
  'score',
  'totalPoints',
  'main.ot',
  sampleSource
);
assert.equal(renamePlan.ok, true);
assert.equal(renamePlan.oldName, 'score');
assert.equal(renamePlan.newName, 'totalPoints');
assert.equal(renamePlan.referencesCount, 3);
assert.equal(renamePlan.affectedLinesCount, 2);
assert.match(renamePlan.edits[0].modifiedLine, /totalPoints is 10/);
assert.match(renamePlan.edits[1].originalLine, /score is score plus 5/);

// Applying rename must transform source safely without touching strings/comments
const renamedSource = otterLanguageService.applyRenameToSource(
  sampleSource,
  'score',
  'totalPoints',
  renamePlan.edits
);
assert.match(renamedSource, /totalPoints is 10/);
assert.match(renamedSource, /"score in quotes is not a ref"/, 'strings must not be renamed');
assert.match(renamedSource, /# score in comment is not a ref/, 'comments must not be renamed');
assert.match(renamedSource, /totalPoints is totalPoints plus 5/);

// Invalid rename validation
const invalidRename = otterLanguageService.prepareRename('score', '123bad', 'main.ot', sampleSource);
assert.equal(invalidRename.ok, false);
assert.match(invalidRename.error, /not a valid Otter identifier/);

console.log('Studio navigation tests passed: project flattening, fuzzy Quick Open, ordered outlines, history, hover documentation, word extraction, signature help, function parameters, cross-file definition, safe references, and preview rename.');



