// export-legacy-pages.mjs - one-off migration helper. Reads the legacy Node
// documentation source (src/pages.mjs) and writes a JSON content list per page
// that scripts/new-docs-page.ps1 turns into Otter-authored pages. The legacy
// pages use a tiny HTML subset (p, h2, pre, aside.note, ul/li, inline code).
import { writeFile } from 'node:fs/promises';
import { pages, sections } from '../src/pages.mjs';

const skip = new Set(process.argv[2] ? process.argv[2].split(',') : []);
const named = { mdash: '—', ndash: '–', rarr: '→', larr: '←', hellip: '…', nbsp: ' ', rsquo: '’', lsquo: '‘', ldquo: '“', rdquo: '”' };
const unescape = (s) => s.replace(/&([a-z]+);/g, (m, n) => named[n] ?? m).replace(/&#(\d+);/g, (m, n) => String.fromCodePoint(Number(n))).replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&amp;', '&');
const plain = (html) => unescape(html.replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim();

function convert(body) {
  const items = [];
  const pattern = /<pre class="(otter-code|shell-code)"[^>]*><code>([\s\S]*?)<\/code><\/pre>|<aside class="note">[\s\S]*?<p>([\s\S]*?)<\/p>\s*<\/aside>|<h2>([\s\S]*?)<\/h2>|<p class="lead">([\s\S]*?)<\/p>|<p>([\s\S]*?)<\/p>|<li>([\s\S]*?)<\/li>/g;
  for (const m of body.matchAll(pattern)) {
    if (m[2] !== undefined) items.push({ k: 'code', t: unescape(m[2].replace(/<[^>]+>/g, '')).replace(/\n$/, ''), shell: m[1] === 'shell-code' });
    else if (m[3] !== undefined) items.push({ k: 'note', t: plain(m[3]) });
    else if (m[4] !== undefined) items.push({ k: 'h2', t: plain(m[4]) });
    else if (m[5] !== undefined) items.push({ k: 'lead', t: plain(m[5]) });
    else if (m[6] !== undefined) {
      items.push({ k: 'p', t: plain(m[6]) });
      for (const a of m[6].matchAll(/<a href="([^"]+)">([\s\S]*?)<\/a>/g)) items.push({ k: 'link', t: plain(a[2]), u: a[1] });
    } else if (m[7] !== undefined) items.push({ k: 'p', t: '- ' + plain(m[7]) });
  }
  // The first plain paragraph reads as the page's lead.
  const firstP = items.findIndex((i) => i.k === 'p' || i.k === 'lead');
  if (firstP >= 0) items[firstP].k = 'lead';
  return items;
}

const out = { sections, pages: {} };
for (const p of pages) {
  if (skip.has(p.slug)) continue;
  out.pages[p.slug] = { title: p.title, section: p.section, items: convert(p.body) };
}
await writeFile(new URL('./legacy-pages.json', import.meta.url), JSON.stringify(out, null, 1));
console.log(`Exported ${Object.keys(out.pages).length} pages`);
