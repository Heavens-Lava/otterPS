// Docs viewer Markdown (js/docs/markdown.js): the constructs the docs use,
// and nothing unsafe gets through.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const { renderMarkdown } = await import('../js/docs/markdown.js');

const md = [
  '# Otter Guide',
  '',
  'Say **hello** with `say` and *style*. See [rules](rules.md#functions) or [site](https://example.com).',
  '',
  '```otter',
  'say "<b>hi</b>"',
  '```',
  '',
  '- one',
  '- two',
  '  - nested',
  '1. first',
  '',
  '| Name | Kind |',
  '| --- | --- |',
  '| say | statement |',
  '',
  '> a quote',
  '',
  '## Otter Guide',
  '<script>alert(1)</script>',
  '[bad](javascript:alert(1))'
].join('\n');
const { html, headings } = renderMarkdown(md);
assert.match(html, /<h1 id="otter-guide">Otter Guide<\/h1>/);
assert.match(html, /<h2 id="otter-guide-1">/, 'repeated headings get unique ids');
assert.deepEqual(headings.map(h => h.level), [1, 2]);
assert.match(html, /<strong>hello<\/strong>/);
assert.match(html, /<code>say<\/code>/);
assert.match(html, /<em>style<\/em>/);
assert.match(html, /<a href="rules\.md#functions" data-doc-link>rules<\/a>/);
assert.match(html, /<a href="https:\/\/example\.com" target="_blank" rel="noopener">site<\/a>/);
assert.match(html, /<pre class="md-code" data-lang="otter"><code>say &quot;&lt;b&gt;hi&lt;\/b&gt;&quot;<\/code><\/pre>/);
assert.match(html, /<ul><li>one<\/li><li>two<ul><li>nested<\/li><\/ul><\/li><\/ul>/);
assert.match(html, /<ol><li>first<\/li><\/ol>/);
assert.match(html, /<th>Name<\/th><th>Kind<\/th>/);
assert.match(html, /<td>say<\/td><td>statement<\/td>/);
assert.match(html, /<blockquote><p>a quote<\/p><\/blockquote>/);
assert.ok(!html.includes('<script>'), 'raw HTML is escaped');
assert.match(html, /&lt;script&gt;/);
assert.match(html, /<a href="#" data-doc-link>bad<\/a>/, 'unsafe link targets are dropped');

// The real guide renders without throwing and has an outline.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const rules = renderMarkdown(fs.readFileSync(path.join(root, 'rules.md'), 'utf8'));
assert.ok(rules.headings.length > 10);

console.log('Markdown tests passed.');
