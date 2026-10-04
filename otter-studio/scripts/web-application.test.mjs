// web-application.test.mjs - Comprehensive Test Suite for Section 13: Web Application Target
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  SSR_STRATEGY_DECISION,
  BROWSER_MATRIX,
  DEPLOY_PRESETS,
  generateSeoMetaTags,
  generateRobotsTxt,
  generateSitemapXml,
  generatePwaManifest,
  generateServiceWorker,
  buildEnvironmentConfig,
  generateV3SourceMap,
  minifyHtml,
  minifyCss,
  minifyJs,
  generateClientRuntimeCode,
  generateResponsiveCss,
  compileSinglePageHtmlDocument,
  buildStaticSite,
  buildClientApp
} from '../js/compiler/web-target-engine.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const BASE_URL = `http://127.0.0.1:${PORT}`;

async function api(pathname, body, method = 'POST') {
  const res = await fetch(`${BASE_URL}${pathname}`, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await res.json().catch(() => ({}));
  return { status: res.status, data };
}

// ----------------------------------------------------------------------------
// 1. SSR Decision & Architecture Verification
// ----------------------------------------------------------------------------
test('Section 13.15: SSR Decision & Architecture', () => {
  assert.equal(SSR_STRATEGY_DECISION.strategy, 'static-prerender-with-client-hydration');
  assert.equal(SSR_STRATEGY_DECISION.architecture, 'SSG + CSH (Static Site Generation + Client-Side Hydration)');
  assert.ok(Array.isArray(SSR_STRATEGY_DECISION.rationale));
  assert.ok(SSR_STRATEGY_DECISION.rationale.length >= 4);
  assert.ok(SSR_STRATEGY_DECISION.rationale.some(r => r.includes('Zero-JS Crawlability')));
  assert.ok(SSR_STRATEGY_DECISION.rationale.some(r => r.includes('First Contentful Paint')));
});

// ----------------------------------------------------------------------------
// 2. Browser Matrix & Compatibility Shims
// ----------------------------------------------------------------------------
test('Section 13.17: Browser Matrix & ES2018 Shims', () => {
  assert.equal(BROWSER_MATRIX.baseline, 'ES2018 Modern Evergreen');
  assert.ok(BROWSER_MATRIX.targets.chrome);
  assert.ok(BROWSER_MATRIX.targets.firefox);
  assert.ok(BROWSER_MATRIX.targets.safari);
  assert.ok(BROWSER_MATRIX.targets.edge);
  assert.ok(BROWSER_MATRIX.shims.includes('Otter Browser Compatibility Shims'));
  assert.ok(BROWSER_MATRIX.shims.includes('ResizeObserver'));
});

// ----------------------------------------------------------------------------
// 3. SEO, OpenGraph, Twitter Cards, Sitemap & Robots.txt
// ----------------------------------------------------------------------------
test('Section 13.16: SEO / Meta, Robots & Sitemap Generation', () => {
  const meta = generateSeoMetaTags({
    title: 'Otter Web App Showcase',
    description: 'A brilliant demo web app built with Otter Studio',
    url: 'https://otter-lang.org/showcase',
    author: 'Otter Team'
  });

  assert.match(meta, /<title>Otter Web App Showcase<\/title>/);
  assert.match(meta, /<meta name="description" content="A brilliant demo web app/);
  assert.match(meta, /<meta property="og:title" content="Otter Web App Showcase"/);
  assert.match(meta, /<meta property="twitter:card"/);
  assert.match(meta, /<script type="application\/ld\+json">/);

  const robots = generateRobotsTxt({ sitemapUrl: 'https://otter-lang.org/sitemap.xml' });
  assert.match(robots, /User-agent: \*/);
  assert.match(robots, /Sitemap: https:\/\/otter-lang\.org\/sitemap\.xml/);

  const sitemap = generateSitemapXml(['/', '/about', '/contact'], 'https://otter-lang.org');
  assert.match(sitemap, /<loc>https:\/\/otter-lang\.org<\/loc>/);
  assert.match(sitemap, /<loc>https:\/\/otter-lang\.org\/about<\/loc>/);
  assert.match(sitemap, /<loc>https:\/\/otter-lang\.org\/contact<\/loc>/);
});

// ----------------------------------------------------------------------------
// 4. Responsive Layout Breakpoints & Media Queries
// ----------------------------------------------------------------------------
test('Section 13.7: Responsive Layout CSS System', () => {
  const css = generateResponsiveCss();
  assert.match(css, /@media \(max-width: 640px\)/);
  assert.match(css, /@media \(min-width: 641px\) and \(max-width: 1024px\)/);
  assert.match(css, /@media \(min-width: 1025px\)/);
  assert.match(css, /\.otter-hide-mobile/);
  assert.match(css, /\.otter-show-mobile/);
  assert.match(css, /\.otter-input-invalid/);
});

// ----------------------------------------------------------------------------
// 5. Client Runtime: Routing, Forms, State & Reusable Components
// ----------------------------------------------------------------------------
test('Section 13.3, 13.4, 13.5, 13.6: Client Runtime Engine', () => {
  const runtime = generateClientRuntimeCode({
    env: { NODE_ENV: 'production', OTTER_ENV: 'production', PUBLIC_API_URL: 'https://api.example.com' }
  });

  assert.match(runtime, /class OtterStore/);
  assert.match(runtime, /class OtterRouter/);
  assert.match(runtime, /class OtterForm/);
  assert.match(runtime, /class OtterComponentRegistry/);
  assert.match(runtime, /PUBLIC_API_URL/);

  // Evaluate runtime in mock sandbox to verify class behavior
  const mockWindow = {
    location: { hash: '#/users/42?tab=activity', pathname: '/', search: '', protocol: 'http:' },
    addEventListener: () => {},
    document: {
      querySelectorAll: () => [],
      getElementById: () => null
    }
  };

  const runtimeFn = new Function('window', runtime);
  runtimeFn(mockWindow);

  assert.ok(mockWindow.otter);
  assert.ok(mockWindow.otter.store);
  assert.ok(mockWindow.otter.router);
  assert.ok(mockWindow.otter.components);

  // Verify Reactive Store
  let storeFired = false;
  mockWindow.otter.store.subscribe((next, prev) => {
    storeFired = true;
    assert.equal(next.count, 10);
  });
  mockWindow.otter.store.setState({ count: 10 });
  assert.equal(storeFired, true);
  assert.equal(mockWindow.otter.store.getState().count, 10);

  // Verify Router Parameter & Query Parsing
  let routeMatched = false;
  mockWindow.otter.router.addRoute('/users/:id', (to) => {
    routeMatched = true;
    assert.equal(to.params.id, '42');
    assert.equal(to.query.tab, 'activity');
  });
  mockWindow.otter.router.resolveCurrentRoute();
  assert.equal(routeMatched, true);

  // Verify Reusable Component Registry with Slots
  mockWindow.otter.components.register('UserCard', {
    template: (props, slots) => `<div class="card"><h3>${props.name}</h3><div class="body"><slot></slot></div></div>`
  });
  const compHtml = mockWindow.otter.components.instantiate('UserCard', { name: 'Alice' }, { default: '<p>Admin User</p>' });
  assert.match(compHtml, /<h3>Alice<\/h3>/);
  assert.match(compHtml, /<p>Admin User<\/p>/);
});

// ----------------------------------------------------------------------------
// 6. Source Maps V3 Specification
// ----------------------------------------------------------------------------
test('Section 13.9: V3 Source Map Generation', () => {
  const map = generateV3SourceMap('bundle.js', 'main.ot', 'say "Hello Otter"');
  assert.equal(map.version, 3);
  assert.equal(map.file, 'bundle.js');
  assert.deepEqual(map.sources, ['main.ot']);
  assert.deepEqual(map.sourcesContent, ['say "Hello Otter"']);
  assert.ok(map.mappings);
});

// ----------------------------------------------------------------------------
// 7. Production Optimization: Minification
// ----------------------------------------------------------------------------
test('Section 13.12: Production Optimization Minifiers', () => {
  const rawHtml = `
    <!-- Comment -->
    <div class="card">
      <h2> Title </h2>
    </div>
  `;
  const minHtml = minifyHtml(rawHtml);
  assert.ok(!minHtml.includes('<!--'));
  assert.ok(!minHtml.includes('  '));

  const rawCss = `
    /* Comment */
    .btn {
      color: #ffffff;
      padding: 10px 20px;
    }
  `;
  const minCss = minifyCss(rawCss);
  assert.ok(!minCss.includes('/*'));
  assert.ok(minCss.includes('.btn{color:#ffffff;padding:10px 20px}'));

  const rawJs = `
    // Line comment
    /* Block comment */
    function greet() {
      return "Hello";
    }
  `;
  const minJs = minifyJs(rawJs);
  assert.ok(!minJs.includes('// Line comment'));
  assert.ok(!minJs.includes('/* Block comment */'));
});

// ----------------------------------------------------------------------------
// 8. PWA Manifest & Service Worker
// ----------------------------------------------------------------------------
test('Section 13.14: PWA Manifest & Service Worker', () => {
  const manifest = generatePwaManifest({ name: 'OtterPwaDemo', themeColor: '#10b981' });
  assert.equal(manifest.name, 'OtterPwaDemo');
  assert.equal(manifest.theme_color, '#10b981');
  assert.equal(manifest.display, 'standalone');
  assert.ok(Array.isArray(manifest.icons));

  const sw = generateServiceWorker('v1', ['/', '/index.html']);
  assert.match(sw, /self\.addEventListener\('install'/);
  assert.match(sw, /self\.addEventListener\('fetch'/);
  assert.match(sw, /caches\.match/);
});

// ----------------------------------------------------------------------------
// 9. Deploy Presets (GitHub Pages, Netlify, Vercel, Cloudflare, S3)
// ----------------------------------------------------------------------------
test('Section 13.18: Deploy Presets Catalog', () => {
  assert.ok(DEPLOY_PRESETS['github-pages']);
  assert.ok(DEPLOY_PRESETS['netlify']);
  assert.ok(DEPLOY_PRESETS['vercel']);
  assert.ok(DEPLOY_PRESETS['cloudflare-pages']);
  assert.ok(DEPLOY_PRESETS['s3-static']);

  assert.ok(DEPLOY_PRESETS['github-pages'].files['.github/workflows/deploy.yml']);
  assert.ok(DEPLOY_PRESETS['netlify'].files['netlify.toml']);
  assert.ok(DEPLOY_PRESETS['vercel'].files['vercel.json']);
  assert.ok(DEPLOY_PRESETS['cloudflare-pages'].files['_routes.json']);
});

// ----------------------------------------------------------------------------
// 10. End-to-End Static Site Build (Multi-Page Pre-Rendering)
// ----------------------------------------------------------------------------
test('Section 13.1, 13.8: Static Site Build Pipeline', () => {
  const testOutDir = path.join(REPO_ROOT, 'publish', 'test-static-site');

  try {
    const res = buildStaticSite({
      outputDir: testOutDir,
      name: 'Otter Multi-Page Showcase',
      baseUrl: 'https://showcase.otter-lang.org',
      preset: 'netlify',
      pwa: true,
      routes: [
        { path: '/', title: 'Home', content: '<h1>Welcome to Otter</h1>' },
        { path: '/features', title: 'Features', content: '<h2>Language Features</h2>' },
        { path: '/docs/getting-started', title: 'Getting Started', content: '<p>Install Otter easily</p>' }
      ]
    });

    assert.equal(res.ok, true);
    assert.ok(fs.existsSync(path.join(testOutDir, 'index.html')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'features', 'index.html')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'docs', 'getting-started', 'index.html')));
    assert.ok(fs.existsSync(path.join(testOutDir, '404.html')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'robots.txt')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'sitemap.xml')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'manifest.webmanifest')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'sw.js')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'netlify.toml')));

    const homeHtml = fs.readFileSync(path.join(testOutDir, 'index.html'), 'utf8');
    assert.match(homeHtml, /Welcome to Otter/);
    assert.match(homeHtml, /Otter Multi-Page Showcase/);

    const sitemapContent = fs.readFileSync(path.join(testOutDir, 'sitemap.xml'), 'utf8');
    assert.match(sitemapContent, /https:\/\/showcase\.otter-lang\.org\/features/);
    assert.match(sitemapContent, /https:\/\/showcase\.otter-lang\.org\/docs\/getting-started/);
  } finally {
    if (fs.existsSync(testOutDir)) {
      fs.rmSync(testOutDir, { recursive: true, force: true });
    }
  }
});

// ----------------------------------------------------------------------------
// 11. End-to-End Client App Build (SPA Pipeline)
// ----------------------------------------------------------------------------
test('Section 13.2, 13.8, 13.9, 13.13: Client App Build Pipeline', () => {
  const testOutDir = path.join(REPO_ROOT, 'publish', 'test-client-app');

  try {
    const res = buildClientApp({
      outputDir: testOutDir,
      name: 'OtterTasksSPA',
      html: '<div class="otter-window" id="app"><h1>Task Dashboard</h1></div>',
      css: '.card { padding: 12px; }',
      js: 'otter.say("Tasks loaded successfully");',
      preset: 'vercel',
      pwa: true,
      env: {
        OTTER_ENV: 'staging',
        PUBLIC_API_URL: 'https://tasks.api.otter-lang.org'
      }
    });

    assert.equal(res.ok, true);
    assert.ok(fs.existsSync(path.join(testOutDir, 'index.html')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'app.js')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'app.js.map')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'app.css')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'app.css.map')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'manifest.webmanifest')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'sw.js')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'vercel.json')));

    const appJs = fs.readFileSync(path.join(testOutDir, 'app.js'), 'utf8');
    assert.match(appJs, /PUBLIC_API_URL/);
    assert.match(appJs, /sourceMappingURL=app\.js\.map/);

    const appCss = fs.readFileSync(path.join(testOutDir, 'app.css'), 'utf8');
    assert.match(appCss, /sourceMappingURL=app\.css\.map/);
  } finally {
    if (fs.existsSync(testOutDir)) {
      fs.rmSync(testOutDir, { recursive: true, force: true });
    }
  }
});

// ----------------------------------------------------------------------------
// 12. Dev Server Live Endpoints & Hot Reload Broadcasting
// ----------------------------------------------------------------------------
test('Section 13.10, 13.11: Dev Server Web Target APIs & Hot Reload', async () => {
  // 1. SSR Strategy endpoint
  const ssrRes = await api('/api/web/ssr-strategy', null, 'GET');
  assert.equal(ssrRes.status, 200);
  assert.equal(ssrRes.data.strategy, 'static-prerender-with-client-hydration');

  // 2. Browser matrix endpoint
  const browserRes = await api('/api/web/browser-matrix', null, 'GET');
  assert.equal(browserRes.status, 200);
  assert.equal(browserRes.data.baseline, 'ES2018 Modern Evergreen');

  // 3. Deploy presets endpoint
  const presetRes = await api('/api/web/deploy-presets', null, 'GET');
  assert.equal(presetRes.status, 200);
  assert.ok(presetRes.data.presets.includes('github-pages'));
  assert.ok(presetRes.data.presets.includes('netlify'));
  assert.ok(presetRes.data.presets.includes('vercel'));

  // 4. Hot reload broadcast endpoint
  const broadcastRes = await api('/api/web/broadcast-reload', { type: 'css' });
  assert.equal(broadcastRes.status, 200);
  assert.equal(broadcastRes.data.ok, true);
  assert.equal(broadcastRes.data.type, 'css');

  // 5. Web build API endpoint
  const buildRes = await api('/api/web/build', {
    target: 'client',
    outputDir: 'publish/test-api-web-app',
    name: 'ApiWebAppTest',
    html: '<div id="api-root">API Web App</div>',
    css: 'body { margin: 0; }',
    js: 'otter.say("API App");',
    preset: 'github-pages'
  });

  const absOutDir = path.join(REPO_ROOT, 'publish', 'test-api-web-app');
  try {
    assert.equal(buildRes.status, 200);
    assert.equal(buildRes.data.ok, true);
    assert.equal(buildRes.data.target, 'client');
    assert.ok(fs.existsSync(path.join(absOutDir, 'index.html')));
    assert.ok(fs.existsSync(path.join(absOutDir, 'app.js')));
    assert.ok(fs.existsSync(path.join(absOutDir, '.github', 'workflows', 'deploy.yml')));
  } finally {
    if (fs.existsSync(absOutDir)) {
      fs.rmSync(absOutDir, { recursive: true, force: true });
    }
  }
});
