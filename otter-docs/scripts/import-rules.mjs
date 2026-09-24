// import-rules.mjs - one-off migration helper. Builds documentation page content
// from the language rules (rules.md and rules3.md), which already hold the
// explanations and examples. Output: scripts/rules-pages.json, consumed by
// build-docs-content.ps1. Code samples are parse-checked afterwards with
// check-otter-page-examples.ps1; anything that does not parse is reviewed by hand.
import { readFile, writeFile } from 'node:fs/promises';

const rules3 = (await readFile(new URL('../../rules3.md', import.meta.url), 'utf8')).replace(/\r\n/g, '\n');
const rules1 = (await readFile(new URL('../../rules.md', import.meta.url), 'utf8')).replace(/\r\n/g, '\n');

// "# 16. Try and Otherwise" -> { n: 16, title, body }
function sectionsOf(text, numbered) {
  const out = [];
  const parts = text.split(/\n(?=# )/);
  for (const part of parts) {
    const m = part.match(/^# (?:(\d+)\.\s+)?(.+)\n/);
    if (!m) continue;
    if (numbered && !m[1]) continue;
    out.push({ n: m[1] ? Number(m[1]) : null, title: m[2].trim(), body: part.slice(m[0].length) });
  }
  return out;
}

const strip = (s) => s.replace(/`([^`]+)`/g, '$1').replace(/\*\*([^*]+)\*\*/g, '$1').replace(/\*([^*]+)\*/g, '$1').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').replace(/\s+/g, ' ').trim();

function convert(body) {
  const items = [];
  const lines = body.split('\n');
  let i = 0;
  const para = [];
  const flush = () => { if (para.length) { items.push({ k: 'p', t: strip(para.join(' ')) }); para.length = 0; } };
  while (i < lines.length) {
    const line = lines[i];
    const fence = line.match(/^```(\w*)/);
    if (fence) {
      flush();
      const lang = fence[1];
      const buf = [];
      i++;
      while (i < lines.length && !lines[i].startsWith('```')) buf.push(lines[i++]);
      i++;
      const text = buf.join('\n').replace(/\s+$/, '');
      if (!text) continue;
      // Expression-only samples ("length of games") are not statements; show them as
      // `say <expression>` so every code block on the site is a real program line.
      const exprLine = /^(?!say )[a-z]+( [a-z]+)? of [a-z]+( of [a-z]+)*$/;
      const sampleLines = text.split('\n');
      if (lang === 'otter' && /^\w+$/.test(text)) items.push({ k: 'out', t: text });
      else if (lang === 'otter' && sampleLines.every((l) => exprLine.test(l))) items.push({ k: 'code', t: sampleLines.map((l) => 'say ' + l).join('\n') });
      else if (lang === 'otter' && /^\s*\.\.\.\s*$/m.test(text)) items.push({ k: 'out', t: text });   // a sketch with ... in it, not a program
      else items.push({ k: lang === 'otter' ? 'code' : 'out', t: text });
      continue;
    }
    if (/^---+\s*$/.test(line) || /^\s*$/.test(line)) { flush(); i++; continue; }
    if (/^#{2,4} /.test(line)) { flush(); items.push({ k: 'h2', t: strip(line.replace(/^#+\s*/, '')) }); i++; continue; }
    if (/^>/.test(line)) {
      flush();
      const buf = [];
      while (i < lines.length && /^>/.test(lines[i])) buf.push(lines[i++].replace(/^>\s?/, ''));
      items.push({ k: 'note', t: strip(buf.join(' ')) });
      continue;
    }
    if (/^\s*[*-] /.test(line)) {
      flush();
      while (i < lines.length && /^\s*[*-] /.test(lines[i])) items.push({ k: 'p', t: '- ' + strip(lines[i++].replace(/^\s*[*-] /, '')) });
      continue;
    }
    if (/^\|/.test(line)) {
      flush();
      const buf = [];
      while (i < lines.length && /^\|/.test(lines[i])) buf.push(lines[i++]);
      const rows = buf.filter((r) => !/^\|[\s:|-]+\|$/.test(r)).map((r) => r.split('|').slice(1, -1).map((c) => strip(c)));
      const widths = rows[0].map((_, c) => Math.max(...rows.map((r) => (r[c] ?? '').length)));
      items.push({ k: 'out', t: rows.map((r) => r.map((c, ci) => c.padEnd(widths[ci])).join('  ').trimEnd()).join('\n') });
      continue;
    }
    para.push(line.trim());
    i++;
  }
  flush();
  return items;
}

// Samples that are design targets, not implemented syntax (they fail the real
// parser). A section containing one is left out entirely rather than shown half-true.
const notImplemented = new Set([
  'sort files by name',
  'get files from files where extension of file is ".pdf" into pdfs',
  'jeff is a Person\nname of jeff is "Jeff"\nage of jeff is 29\nsay "Hello" name of jeff',
  'if ready and connected',
  'port is environment value "PORT"',
  'port is environment value "PORT" or 8080',
  'measure folder "Pictures" into size',
  'measure folder folder into size',
  'copy folder to "Backup"',
  'move folder to "Archive"',
  'delete folder "Backup" and everything in it',
  'body of request as json becomes user',
  'if the age is at least 18\n    say "Adult"\n.',
  'add the value 5 to score',
  'replace "Jeff" with "Jeffrey" in name into updatedName'
]);
const usable = (items) => !items.some((i) => i.k === 'code' && notImplemented.has(i.t));

const r3 = sectionsOf(rules3, true);
const byN = (n) => r3.find((s) => s.n === n);

// slug -> { title, parts: [rules3 section numbers] } - the page groupings.
const plan = {
  gone: { title: 'gone: the absence of a value', lead: 'gone means no value exists. It is not the same as empty text, zero, an empty list, or false.', from: [1, 2, 3] },
  discovery: { title: 'Finding files and folders', lead: 'Discover the files and folders inside a folder, with explicit control over whether subfolders are included.', from: [4, 5, 6, 7] },
  'file-objects': { title: 'File and folder objects', lead: 'A discovered file or folder is an object with properties you read with of.', from: [8, 9, 10] },
  try: { title: 'try and otherwise', lead: 'try runs a block; if something in it fails, otherwise handles it.', from: [16, 17, 18] },
  strings: { title: 'Working with text', lead: 'Measure, change, search, split, and join text with plain words.', from: [19, 22, 23, 24, 25, 26, 27, 28] },
  collections: { title: 'Working with collections', lead: 'Measure, order, search, and pick items from lists.', from: [20, 21, 29, 30, 31, 32, 33, 34] },
  json: { title: 'JSON', lead: 'JSON converts to ordinary Otter objects and lists, read with the same of you use everywhere else.', from: [35, 36] },
  scope: { title: 'Scope', lead: 'Where a variable can be seen: everywhere, inside one function, or inside one block.', from: [37, 38, 39] },
  modules: { title: 'Modules', lead: 'Split a program across files and reuse them with use.', from: [40] },
  random: { title: 'Random values', lead: 'Random numbers and random items from a collection.', from: [47, 48] },
  'logging-debugging': { title: 'Logging and debugging', lead: 'Write diagnostic output that is separate from what your program says.', from: [49, 50] },
  environment: { title: 'Arguments and environment', lead: 'Read command-line arguments and environment values.', from: [54, 55] }
};

const pages = {};
for (const [slug, def] of Object.entries(plan)) {
  const items = [];
  let firstLead = true;
  for (const n of def.from) {
    const s = byN(n);
    if (!s) continue;
    const converted = convert(s.body);
    if (!usable(converted)) continue;
    items.push({ k: 'h2', t: s.title });
    items.push(...converted);
  }
  pages[slug] = { title: def.title, lead: def.lead, items };
}

// rules.md: the plainer, older topics that deserve their own page.
const r1 = sectionsOf(rules1, false);
const r1By = (t) => r1.find((s) => s.title === t);
const fromR1 = {
  math: { title: 'Math', lead: 'Arithmetic in everyday words: and, minus, times, divided by, and make.', titles: ['Math'] },
  'nested-conditions': { title: 'Nested conditions', lead: 'Conditions inside conditions, and how the period keeps them unambiguous.', titles: ['Period Block Ending', 'Nested Conditions'] },
  'running-programs': { title: 'Running programs', lead: 'Run other programs and capture what they print.', titles: ['Running Programs'] }
};
for (const [slug, def] of Object.entries(fromR1)) {
  const items = [];
  for (const t of def.titles) {
    const s = r1By(t);
    if (!s) continue;
    const converted = convert(s.body);
    if (!usable(converted)) continue;
    if (def.titles.length > 1) items.push({ k: 'h2', t: s.title });
    items.push(...converted);
  }
  pages[slug] = { title: def.title, lead: def.lead, items };
}

await writeFile(new URL('./rules-pages.json', import.meta.url), JSON.stringify(pages, null, 1));
console.log(`Imported ${Object.keys(pages).length} pages: ${Object.entries(pages).map(([s, p]) => `${s}(${p.items.length})`).join(' ')}`);
