import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawn } from 'node:child_process';
import {
  cpSync,
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildCatalog } from '../scripts/build-library-catalog.mjs';
import {
  CATEGORY_META,
  buildSandboxSrcDoc,
  extractFacets,
  filterComponents,
  highlightCode
} from '../static/library-filter.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS_ROOT = resolve(__dirname, '..');
const GENERATED_ROOT = join(DOCS_ROOT, 'generated');
const SOURCE_CONFIG_PATH = join(DOCS_ROOT, 'library-source.json');
const SOURCE_CONFIG = JSON.parse(readFileSync(SOURCE_CONFIG_PATH, 'utf8'));
const OTTER_NET_LIBRARY = resolve(DOCS_ROOT, SOURCE_CONFIG.defaultRelativePath);

function sha256File(path) {
  return createHash('sha256').update(readFileSync(path)).digest('hex');
}

test('catalog ingestion imports all 55 canonical Otter assets + 10 curated components with provenance', () => {
  const tempOut = mkdtempSync(join(tmpdir(), 'otter-lib-cat-'));
  try {
    const res = buildCatalog({
      otterNetLibrary: OTTER_NET_LIBRARY,
      outputRoot: tempOut,
      sourceConfig: SOURCE_CONFIG_PATH
    });

    assert.equal(res.catalog.provenance.totalCount, 65);
    assert.equal(res.catalog.provenance.curatedCount, 10);
    assert.deepEqual(res.catalog.provenance.otterCounts, {
      packs: 5,
      snippets: 38,
      blueprints: 4,
      recipes: 4,
      workflows: 4
    });
    assert.equal(res.catalog.provenance.canonicalRepo, 'Heavens-Lava/otter-net');
    assert.equal(res.catalog.provenance.expectedCommit, SOURCE_CONFIG.expectedCommit);
    assert.equal(res.catalog.provenance.libraryTreeSha256, SOURCE_CONFIG.expectedLibraryTreeSha256);
    assert.equal(res.catalog.provenance.ancestorVerified, true);
    assert.match(res.catalog.provenance.sourceCommit, /^[0-9a-f]{40}$/);

    // Verify all 5 official Schema v2 packs expose 72 total operations
    const packs = res.catalog.components.filter((c) => c.subcategory === 'Packs');
    assert.equal(packs.length, 5);
    const totalOps = packs.reduce((sum, p) => sum + (p.contract?.operations?.length || 0), 0);
    assert.equal(totalOps, 72);
    for (const pack of packs) {
      assert.equal(pack.contract.schemaVersion, 2);
      assert.ok(pack.contract.variablePrefix, `Pack ${pack.id} must declare variablePrefix`);
    }
  } finally {
    rmSync(tempOut, { recursive: true, force: true });
  }
});

test('catalog generation is deterministic across independent runs', () => {
  const outA = mkdtempSync(join(tmpdir(), 'otter-lib-det-a-'));
  const outB = mkdtempSync(join(tmpdir(), 'otter-lib-det-b-'));
  try {
    const resA = buildCatalog({ otterNetLibrary: OTTER_NET_LIBRARY, outputRoot: outA, sourceConfig: SOURCE_CONFIG_PATH });
    const resB = buildCatalog({ otterNetLibrary: OTTER_NET_LIBRARY, outputRoot: outB, sourceConfig: SOURCE_CONFIG_PATH });
    assert.equal(sha256File(resA.outFile), sha256File(resB.outFile));
  } finally {
    rmSync(outA, { recursive: true, force: true });
    rmSync(outB, { recursive: true, force: true });
  }
});

test('catalog generator fails loudly on missing, drifted, or stale otter-net library input', () => {
  const tempBase = mkdtempSync(join(tmpdir(), 'otter-lib-stale-'));
  try {
    // 1. Missing directory
    assert.throws(
      () => buildCatalog({
        otterNetLibrary: join(tempBase, 'does-not-exist'),
        outputRoot: join(tempBase, 'out1'),
        sourceConfig: SOURCE_CONFIG_PATH
      }),
      /not found|Refusing to build with stale data/i
    );

    // 2. Modified/drifted library copy (fails tree sha256 verification)
    const driftedLib = join(tempBase, 'drifted-library');
    cpSync(OTTER_NET_LIBRARY, driftedLib, { recursive: true });
    writeFileSync(join(driftedLib, 'snippets', 'catalog.json'), readFileSync(join(driftedLib, 'snippets', 'catalog.json'), 'utf8') + '\n ', 'utf8');
    assert.throws(
      () => buildCatalog({
        otterNetLibrary: driftedLib,
        outputRoot: join(tempBase, 'out2'),
        sourceConfig: SOURCE_CONFIG_PATH
      }),
      /content hash mismatch/i
    );

    // 3. Mismatched expectedCommit in source config
    const badConfigPath = join(tempBase, 'bad-source.json');
    const badConfig = { ...SOURCE_CONFIG, expectedCommit: '0000000000000000000000000000000000000000' };
    writeFileSync(badConfigPath, JSON.stringify(badConfig, null, 2), 'utf8');
    assert.throws(
      () => buildCatalog({
        otterNetLibrary: OTTER_NET_LIBRARY,
        outputRoot: join(tempBase, 'out3'),
        sourceConfig: badConfigPath
      }),
      /does not include expected commit/i
    );
  } finally {
    rmSync(tempBase, { recursive: true, force: true });
  }
});

test('all 65 catalog entries pass metadata, source integrity, related links, and honest preview rules', () => {
  const catalogPath = join(GENERATED_ROOT, 'static', 'library-catalog.json');
  assert.ok(existsSync(catalogPath), `Expected built catalog at ${catalogPath}`);
  const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
  const items = catalog.components;
  assert.equal(items.length, 65);

  const slugs = new Set(items.map((i) => i.slug));
  assert.equal(slugs.size, 65, 'Every component slug must be unique');

  const allowedCategories = new Set(Object.keys(CATEGORY_META));
  const allowedVerification = new Set([
    'contract-and-behavior-verified',
    'behaviorally-tested',
    'contract-validated',
    'source-reviewed'
  ]);

  for (const item of items) {
    assert.ok(item.id && item.slug && item.name && item.description, `Missing core fields on ${item.id}`);
    assert.ok(allowedCategories.has(item.category), `Invalid category '${item.category}' on ${item.id}`);
    assert.ok(item.subcategory && item.language && item.framework && item.version && item.license, `Missing classification on ${item.id}`);
    assert.ok(item.install && item.usage, `Missing install/usage on ${item.id}`);
    assert.ok(Array.isArray(item.platforms) && item.platforms.length > 0, `Missing platforms on ${item.id}`);
    assert.ok(Array.isArray(item.tags) && item.tags.length > 0, `Missing tags on ${item.id}`);
    assert.ok(allowedVerification.has(item.verification?.status), `Invalid verification status on ${item.id}`);
    assert.ok(Array.isArray(item.files) && item.files.length > 0, `Component ${item.id} has no source files`);

    for (const file of item.files) {
      assert.ok(file.label && file.language && file.content && file.content.trim().length > 0, `Empty source file in ${item.id}`);
      assert.ok(!file.path.includes('..'), `Path traversal detected in ${item.id}: ${file.path}`);
    }

    for (const relSlug of item.related || []) {
      assert.ok(slugs.has(relSlug), `Component ${item.id} references unknown related slug '${relSlug}'`);
    }

    // Honest preview invariant: browser iframes only for safe static Web / Styles & Effects
    if (item.preview?.type === 'iframe-sandbox') {
      assert.ok(
        item.category === 'web' || item.category === 'effects',
        `Unsafe or fabricated browser iframe preview on non-web component ${item.id}`
      );
    } else if (item.category === 'desktop' || item.category === 'games') {
      assert.notEqual(item.preview?.type, 'iframe-sandbox');
      assert.ok(item.preview?.projectRef, `Desktop/game component ${item.id} should document runnable project integration`);
    }
  }
});

test('search, facets, syntax highlighting, and sandbox srcdoc work across all categories and languages', () => {
  const catalog = JSON.parse(readFileSync(join(GENERATED_ROOT, 'static', 'library-catalog.json'), 'utf8'));
  const items = catalog.components;

  const facets = extractFacets(items);
  assert.equal(facets.categoryCounts.all, 65);
  assert.equal(
    facets.categoryCounts.web + facets.categoryCounts.desktop + facets.categoryCounts.games + facets.categoryCounts.effects + facets.categoryCounts.otter,
    65
  );
  const langNames = facets.languages.map(([name]) => name);
  assert.ok(langNames.includes('Otter'));
  assert.ok(langNames.includes('C#'));
  assert.ok(langNames.includes('XAML'));
  assert.ok(langNames.includes('GDScript'));
  assert.ok(langNames.includes('Luau'));

  // Category filtering
  assert.equal(filterComponents(items, { category: 'web' }).length, 3);
  assert.equal(filterComponents(items, { category: 'desktop' }).length, 2);
  assert.equal(filterComponents(items, { category: 'games' }).length, 3);
  assert.equal(filterComponents(items, { category: 'effects' }).length, 2);
  assert.equal(filterComponents(items, { category: 'otter' }).length, 55);

  // Language & subcategory filtering
  assert.equal(filterComponents(items, { language: 'XAML' }).length, 2);
  assert.equal(filterComponents(items, { language: 'GDScript' }).length, 1);
  assert.equal(filterComponents(items, { language: 'Luau' }).length, 1);
  assert.equal(filterComponents(items, { subcategory: 'Packs' }).length, 5);

  // Query search across names, tags, frameworks, and Otter Schema v2 operation names
  const applyDmg = filterComponents(items, { query: 'applyDamage' });
  assert.ok(applyDmg.some((c) => c.slug === 'pack-otter-official-game-entity'));
  const wpfGrid = filterComponents(items, { query: 'WPF DataGrid' });
  assert.ok(wpfGrid.some((c) => c.slug === 'desktop-wpf-data-grid'));
  const unityInv = filterComponents(items, { query: 'Unity' });
  assert.ok(unityInv.some((c) => c.slug === 'games-unity-inventory-system'));
  const glass = filterComponents(items, { query: 'glassmorphism' });
  assert.ok(glass.some((c) => c.slug === 'effects-glassmorphism-card'));
  assert.equal(filterComponents(items, { query: 'zzznonexistentcomponent999' }).length, 0);

  // Syntax highlighter XSS escaping & tokens
  const xss = highlightCode('<script>alert("x")</script>', 'html');
  assert.ok(!xss.includes('<script>'), 'Highlighter must escape raw HTML tags');
  assert.ok(xss.includes('&lt;'), 'Highlighter must HTML-escape angle brackets');
  const otterHl = highlightCode('# comment\nto clamp value min_val max_val\n    return value\n.', 'otter');
  assert.ok(otterHl.includes('tok-com'));
  assert.ok(otterHl.includes('tok-kw'));

  // Sandbox srcdoc builder
  const doc = buildSandboxSrcDoc({ html: '<button>Hi</button>', css: ':root{--a:#fff}', js: 'console.log(1)' });
  assert.ok(doc.includes('otter-lib-vars'));
  assert.ok(doc.includes('<button>Hi</button>'));
});

test('generated /library/ and all 65 /library/<slug>/ pages enforce shell, tabs, copy controls, and iframe sandboxing', () => {
  const catalog = JSON.parse(readFileSync(join(GENERATED_ROOT, 'static', 'library-catalog.json'), 'utf8'));
  const libIndexPath = join(GENERATED_ROOT, 'library', 'index.html');
  assert.ok(existsSync(libIndexPath));
  const libIndex = readFileSync(libIndexPath, 'utf8');
  assert.ok(libIndex.includes('id="topBar"'));
  assert.ok(libIndex.includes('id="siteFooter"'));
  assert.ok(libIndex.includes('/static/library-app.css'));
  assert.ok(libIndex.includes('/static/library-app.js'));
  assert.ok(libIndex.includes('id="libraryAppRoot"'));

  const docsIndex = JSON.parse(readFileSync(join(GENERATED_ROOT, 'static', 'docs-index.json'), 'utf8'));
  const docsUrls = new Set(docsIndex.map((e) => e.url));

  for (const item of catalog.components) {
    const pagePath = join(GENERATED_ROOT, 'library', item.slug, 'index.html');
    assert.ok(existsSync(pagePath), `Missing generated detail page: ${pagePath}`);
    const html = readFileSync(pagePath, 'utf8');

    // Shell consistency + navigation + noscript discovery
    assert.ok(html.includes('id="topBar"'), `${item.slug} missing #topBar`);
    assert.ok(html.includes('id="siteFooter"'), `${item.slug} missing #siteFooter`);
    assert.ok(libIndex.includes(`/library/${item.slug}/`), `/library/index.html missing noscript link to ${item.slug}`);
    assert.ok(docsUrls.has(`/library/${item.slug}/`), `docs-index.json missing /library/${item.slug}/`);

    // Multi-file tabs + copy controls + install/license/verification/provenance
    assert.ok(html.includes('role="tablist"'), `${item.slug} missing tablist`);
    assert.ok(html.includes('data-copy-target="raw-code-0"'), `${item.slug} missing source copy control`);
    assert.ok(html.includes('data-copy-target="raw-install"'), `${item.slug} missing install copy control`);
    assert.ok(html.includes('Verification Status'), `${item.slug} missing verification section`);
    assert.ok(html.includes('Catalog Provenance'), `${item.slug} missing provenance section`);

    // Strict iframe sandboxing security checks
    if (item.preview?.type === 'iframe-sandbox') {
      assert.ok(html.includes('sandbox="allow-scripts"'), `${item.slug} iframe must use sandbox="allow-scripts"`);
      assert.ok(!html.includes('allow-same-origin'), `${item.slug} iframe MUST NOT include allow-same-origin`);
    } else {
      assert.ok(!html.includes('<iframe'), `Non-web component ${item.slug} must not render an iframe`);
    }
  }
});

test('local static server serves /library/, ES modules, catalog JSON, and detail pages cleanly', async () => {
  const port = 4390 + Math.floor(Math.random() * 400);
  const proc = spawn(process.execPath, [join(DOCS_ROOT, 'scripts', 'serve-otter-pages.mjs')], {
    env: { ...process.env, PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe']
  });

  try {
    await new Promise((resolveReady, rejectReady) => {
      const timer = setTimeout(() => rejectReady(new Error('Server failed to start within 5s')), 5000);
      proc.stdout.on('data', (chunk) => {
        if (chunk.toString('utf8').includes(`http://localhost:${port}`)) {
          clearTimeout(timer);
          resolveReady();
        }
      });
      proc.on('exit', (code) => {
        clearTimeout(timer);
        rejectReady(new Error(`Server exited early with code ${code}`));
      });
    });

    const checks = [
      ['/library/', 200, 'text/html'],
      ['/static/library-catalog.json', 200, 'application/json'],
      ['/static/library-filter.mjs', 200, 'text/javascript'],
      ['/static/library-app.js', 200, 'text/javascript'],
      ['/static/library-app.css', 200, 'text/css'],
      ['/library/web-animated-gradient-button/', 200, 'text/html'],
      ['/library/desktop-wpf-data-grid/', 200, 'text/html'],
      ['/library/games-godot-health-combat/', 200, 'text/html'],
      ['/library/effects-glassmorphism-card/', 200, 'text/html'],
      ['/library/pack-otter-official-game-entity/', 200, 'text/html']
    ];

    for (const [route, expectedStatus, expectedType] of checks) {
      const res = await fetch(`http://localhost:${port}${route}`);
      assert.equal(res.status, expectedStatus, `Unexpected status for ${route}`);
      assert.ok(
        (res.headers.get('content-type') || '').includes(expectedType),
        `Unexpected content-type for ${route}: ${res.headers.get('content-type')}`
      );
      if (route.endsWith('.json')) {
        const json = await res.json();
        assert.equal(json.components.length, 65);
      }
    }

    // Verify canonical trailing-slash redirect
    const redir = await fetch(`http://localhost:${port}/library`, { redirect: 'manual' });
    assert.equal(redir.status, 308);
    assert.equal(redir.headers.get('location'), '/library/');
  } finally {
    proc.kill('SIGTERM');
  }
});

test('publish-site.ps1 stages /library/ and preserves it across repeated publishes without touching Pages repo files', () => {
  const tempPublish = mkdtempSync(join(tmpdir(), 'otter-publish-test-'));
  try {
    execFileSync('git', ['init', '-q'], { cwd: tempPublish });
    writeFileSync(join(tempPublish, 'CNAME'), 'otterprogramming.com\n', 'utf8');
    writeFileSync(join(tempPublish, 'README.md'), '# Publish Test\n', 'utf8');
    writeFileSync(join(tempPublish, '.nojekyll'), '', 'utf8');

    const publishScript = join(DOCS_ROOT, 'scripts', 'publish-site.ps1');
    // Run twice to verify subsequent publishes never erase /library/
    for (let run = 1; run <= 2; run++) {
      execFileSync('pwsh', ['-NoProfile', '-File', publishScript, '-SkipBuild', '-PublishRepo', tempPublish], {
        stdio: 'pipe'
      });
    }

    assert.ok(existsSync(join(tempPublish, 'index.html')), 'Missing root index.html');
    assert.ok(existsSync(join(tempPublish, 'docs', 'index.html')), 'Missing existing /docs/ route');
    assert.ok(existsSync(join(tempPublish, 'library', 'index.html')), 'Missing /library/ route');
    assert.ok(existsSync(join(tempPublish, 'library', 'web-animated-gradient-button', 'index.html')), 'Missing detail page');
    assert.ok(existsSync(join(tempPublish, 'library', 'pack-otter-official-game-entity', 'index.html')), 'Missing Otter pack detail page');
    assert.ok(existsSync(join(tempPublish, 'static', 'library-catalog.json')), 'Missing catalog JSON');
    assert.equal(readFileSync(join(tempPublish, 'CNAME'), 'utf8'), 'otterprogramming.com\n');
    assert.equal(readFileSync(join(tempPublish, 'README.md'), 'utf8'), '# Publish Test\n');
    assert.ok(existsSync(join(tempPublish, '.nojekyll')));
  } finally {
    rmSync(tempPublish, { recursive: true, force: true });
  }
});
