import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const files = ['package.json', 'language-configuration.json', 'syntaxes/otter.tmLanguage.json'];
const parsed = {};
for (const file of files) {
  try {
    parsed[file] = JSON.parse(await readFile(join(root, file), 'utf8'));
  } catch (error) {
    console.error(`Invalid or missing ${file}: ${error.message}`);
    process.exit(1);
  }
}

const pkg = parsed['package.json'];
const grammar = parsed['syntaxes/otter.tmLanguage.json'];
const language = parsed['language-configuration.json'];
const checks = [
  [pkg.contributes.languages?.some((entry) => entry.id === 'otter' && entry.extensions?.includes('.ot')), 'Otter language registration'],
  [pkg.contributes.grammars?.some((entry) => entry.scopeName === 'source.otter'), 'TextMate grammar registration'],
  [grammar.scopeName === 'source.otter' && grammar.repository?.comments, 'TextMate grammar structure'],
  [/\bput\b/.test(String(grammar.repository?.['statement-heads']?.patterns?.[0]?.match || '')) && /\bwhen\b/.test(String(grammar.repository?.['statement-heads']?.patterns?.[0]?.match || '')) && /\bshow\b/.test(String(grammar.repository?.['statement-heads']?.patterns?.[0]?.match || '')), 'structural UI statement keywords'],
  [!String(grammar.repository?.domain?.patterns?.[0]?.match || '').includes('clicked'), 'contextual event words remain unreserved'],
  [language.comments?.lineComment === '#', 'line comment configuration'],
  [language.indentationRules?.increaseIndentPattern && language.indentationRules?.decreaseIndentPattern, 'indentation configuration'],
  [pkg.main === 'src/extension.js', 'completion provider entry point']
];
const failed = checks.filter(([ok]) => !ok).map(([, label]) => label);
if (failed.length) {
  console.error(`Extension validation failed: ${failed.join(', ')}`);
  process.exit(1);
}
console.log('Otter VS Code extension metadata and grammar validated.');
