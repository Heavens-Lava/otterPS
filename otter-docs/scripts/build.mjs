import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pages, sections } from '../src/pages.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const dist = join(root, 'dist');
const esc = (value) => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const href = (slug) => slug === 'welcome' ? '/' : `/${slug}/`;
const nav = (active) => sections.map(([heading, items]) => `<section class="nav-section"><h2>${esc(heading)}</h2>${items.map(([slug, label]) => `<a class="${slug === active ? 'active' : ''}" href="${href(slug)}">${esc(label)}</a>`).join('')}</section>`).join('');

function shell(page, index) {
  const previous = pages[index - 1]; const next = pages[index + 1];
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="description" content="${esc(page.description || `Otter documentation: ${page.title}`)}"><title>${esc(page.title)} · Otter Documentation</title><link rel="stylesheet" href="/assets/site.css"><script defer src="/assets/site.js"></script></head><body><header class="topbar"><a class="brand" href="/">Otter <span>Documentation</span></a><nav class="primary-nav" aria-label="Primary navigation"><a href="/">Docs</a><a href="/download/">Download</a><a href="/example-hello/">Examples</a></nav><button class="menu" aria-label="Toggle navigation">Menu</button><label class="search"><span>Search</span><input type="search" placeholder="Search documentation" data-search></label></header><div class="site"><aside class="sidebar">${nav(page.slug)}</aside><main><nav class="crumb">${esc(page.section)} <span>/</span> ${esc(page.title)}</nav><article><h1>${esc(page.title)}</h1>${page.body}</article><nav class="pager">${previous ? `<a href="${href(previous.slug)}">← <span>Previous</span>${esc(previous.title)}</a>` : '<span></span>'}${next ? `<a class="next" href="${href(next.slug)}"><span>Next</span>${esc(next.title)} →</a>` : '<span></span>'}</nav></main></div><dialog data-results><button data-close>Close</button><div></div></dialog></body></html>`;
}

await rm(dist, { recursive: true, force: true });
await mkdir(join(dist, 'assets'), { recursive: true });
for (const [index, page] of pages.entries()) {
  const file = page.slug === 'welcome' ? join(dist, 'index.html') : join(dist, page.slug, 'index.html');
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, shell(page, index));
}
await writeFile(join(dist, 'search-index.json'), JSON.stringify(pages.map(({ slug, title, section, description }) => ({ title, section, description, url: href(slug) })), null, 2));
const baseCss = await readFile(new URL('../static/site.css', import.meta.url));
const highlightCss = await readFile(new URL('../static/highlight.css', import.meta.url));
await writeFile(join(dist, 'assets', 'site.css'), Buffer.concat([baseCss, Buffer.from('\n'), highlightCss]));
await writeFile(join(dist, 'assets', 'site.js'), await readFile(new URL('../static/site.js', import.meta.url)));
console.log(`Built ${pages.length} documentation pages in ${dist}`);
