import { access, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { pages, sections } from '../src/pages.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const dist = join(root, 'dist');
const failures = [];
const bySlug = new Map();

for (const page of pages) {
  if (bySlug.has(page.slug)) failures.push(`Duplicate page slug: ${page.slug}`);
  bySlug.set(page.slug, page);
}

for (const [, items] of sections) {
  for (const [slug] of items) {
    if (!bySlug.has(slug)) failures.push(`Navigation link has no page: ${slug}`);
  }
}

for (const page of pages) {
  const file = page.slug === 'welcome'
    ? join(dist, 'index.html')
    : join(dist, page.slug, 'index.html');
  try {
    await access(file);
    const html = await readFile(file, 'utf8');
    for (const required of ['class="sidebar"', 'class="pager"', 'site.js']) {
      if (!html.includes(required)) failures.push(`${page.slug} is missing ${required}`);
    }
  } catch {
    failures.push(`Missing generated page: ${page.slug}`);
  }
}

try {
  const index = JSON.parse(await readFile(join(dist, 'search-index.json'), 'utf8'));
  if (index.length !== pages.length) failures.push('Search index page count does not match source pages.');
} catch {
  failures.push('Missing or invalid search index.');
}

if (failures.length) {
  console.error(`Site check failed:\n- ${failures.join('\n- ')}`);
  process.exit(1);
}

console.log(`Site structure verified: ${pages.length} pages and navigation/search metadata.`);
