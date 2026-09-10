// check-examples.mjs
//
// Runs every Otter code sample in the documentation through the real Otter
// parser and fails if any of them no longer parses.
//
// Documentation that shows code which does not work is worse than
// documentation that shows less code, because a beginner cannot tell the
// difference between "I typed it wrong" and "the page is out of date". This
// makes that impossible to miss.
//
//     node scripts/check-examples.mjs
//
// It uses otter.ps1 -ParseOnly, so nothing in a sample is executed: no file
// is written, no folder is deleted, no program is launched. Samples are only
// checked for being well formed.
//
// Blocks written with shell() or transcript() are skipped - they are terminal
// commands and session transcripts, not Otter source.

import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

import { pages } from '../src/pages.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const otter = resolve(here, '..', '..', 'otter.ps1');

// Pull the source back out of a rendered block, undoing the highlighter.
const unhighlight = (html) =>
  html
    .replace(/<span class="[^"]*">/g, '')
    .replace(/<\/span>/g, '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

const otterBlocks = (body) => {
  const blocks = [];
  const pattern = /<pre class="otter-code" data-otter="1"><code>([\s\S]*?)<\/code><\/pre>/g;
  let match;
  while ((match = pattern.exec(body)) !== null) {
    blocks.push(unhighlight(match[1]));
  }
  return blocks;
};

const workspace = mkdtempSync(join(tmpdir(), 'otter-docs-check-'));
let checked = 0;
const failures = [];

for (const page of pages) {
  otterBlocks(page.body).forEach((source, index) => {
    checked += 1;
    const file = join(workspace, `${page.slug}-${index}.ot`);
    writeFileSync(file, source, 'utf8');

    const result = spawnSync(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', otter, file, '-ParseOnly'],
      { encoding: 'utf8' }
    );

    const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
    if (result.status !== 0 || /Syntax Error/.test(output)) {
      failures.push({ slug: page.slug, index, source, output: output.trim() });
    }
  });
}

rmSync(workspace, { recursive: true, force: true });

if (failures.length === 0) {
  console.log(`All ${checked} Otter examples parse.`);
  process.exit(0);
}

console.error(`${failures.length} of ${checked} Otter examples do not parse:\n`);
for (const failure of failures) {
  console.error(`  ${failure.slug} (block ${failure.index + 1})`);
  for (const line of failure.source.split('\n')) console.error(`    | ${line}`);
  for (const line of failure.output.split('\n')) {
    if (line.trim()) console.error(`    ${line.trim()}`);
  }
  console.error('');
}
process.exit(1);
