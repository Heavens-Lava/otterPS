// analyzer.test.mjs - the language analysis Studio's warnings, Find References
// and Rename rely on (tools/vscode-otter/scripts/analyze.ps1, the real Otter
// parser): a variable read only in a `return` or a `set ... to` is a read.
// (Its walk skipped every node's Value: `return result` was "never read".)
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const analyze = (source) => JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(repoRoot, 'tools', 'vscode-otter', 'scripts', 'analyze.ps1'), '-Root', repoRoot], { input: source, encoding: 'utf8' }));
const reads = (result, name) => result.References.filter(r => r.Name === name && !r.IsDeclaration).map(r => r.Line);

let passed = 0;
const test = (name, fn) => { fn(); passed++; console.log(`  ✓ ${name}`); };

const source = [
  'to double n',
  '    result is n times 2',
  '    return result',
  '.',
  'scores is a thing',
  '    best is 0',
  '.',
  'top is 9',
  'set "best" to top in scores',
  'double 4 make eight',
  'say eight',
  ''
].join('\n');
const result = analyze(source);

console.log('Analyzer:');
test('a variable read only by return is read', () => assert.deepEqual(reads(result, 'result'), [3]));
test('a variable read only by set ... to is read', () => assert.deepEqual(reads(result, 'top'), [9]));
test('an assignment is still a declaration, not a read', () => assert.deepEqual(reads(result, 'eight'), [11]));
console.log(`Analyzer tests passed: ${passed}.`);
