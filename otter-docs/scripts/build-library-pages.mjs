#!/usr/bin/env node
/**
 * scripts/build-library-pages.mjs
 * Generates static detail pages (/library/<slug>/index.html), enhances /library/index.html
 * with the library bundle, and merges all library items into static/docs-index.json so
 * site-wide Ctrl+K search discovers every component cleanly.
 *
 * Uses the exact Otter-compiled topBar and siteFooter from generated/library/index.html
 * so every /library/ and /library/<slug>/ page matches the Otter website shell.
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CATEGORY_META,
  buildSandboxSrcDoc,
  escapeHtml,
  highlightCode
} from '../static/library-filter.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DOCS_ROOT = resolve(__dirname, '..');

function parseArgs(argv) {
  const opts = { outputRoot: resolve(DOCS_ROOT, 'generated') };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--output-root' && argv[i + 1]) opts.outputRoot = resolve(argv[++i]);
  }
  return opts;
}

function extractDivById(html, id) {
  const startMatch = new RegExp(`<div\\b[^>]*\\bid="${id}"[^>]*>`).exec(html);
  if (!startMatch) return null;
  const startIdx = startMatch.index;
  const tagRe = /<\/?div\b[^>]*>/gi;
  tagRe.lastIndex = startIdx;
  let depth = 0;
  let match;
  while ((match = tagRe.exec(html)) !== null) {
    if (match[0].startsWith('</')) {
      depth--;
      if (depth === 0) {
        return html.slice(startIdx, match.index + match[0].length);
      }
    } else if (!match[0].endsWith('/>')) {
      depth++;
    }
  }
  return null;
}

function extractShellChrome(libraryHtml) {
  // Capture the exact Otter-compiled topBar and siteFooter markup + head styles.
  const topBar = extractDivById(libraryHtml, 'topBar');
  const siteFooter = extractDivById(libraryHtml, 'siteFooter');
  const styleMatch = libraryHtml.match(/<style>[\s\S]*?<\/style>/);
  if (!topBar || !siteFooter) {
    throw new Error('Could not extract Otter-compiled #topBar or #siteFooter from generated/library/index.html.');
  }
  return {
    topBar: topBar.trim(),
    siteFooter: siteFooter.trim(),
    otterBaseStyle: styleMatch ? styleMatch[0] : ''
  };
}

function verificationBadgeClass(status) {
  switch (status) {
    case 'contract-and-behavior-verified': return 'lib-badge-verified';
    case 'behaviorally-tested': return 'lib-badge-tested';
    case 'contract-validated': return 'lib-badge-contract';
    default: return 'lib-badge-reviewed';
  }
}

function renderPreviewSection(item) {
  const p = item.preview || {};
  if (p.type === 'iframe-sandbox') {
    const srcdoc = buildSandboxSrcDoc({ html: p.html || '', css: p.css || '', js: p.js || '' });
    const controlsHtml = (p.controls || []).length
      ? `<div class="lib-customizer" aria-label="Live customization controls">
          <div class="lib-customizer-title">Customize Preview</div>
          <div class="lib-customizer-grid">
            ${p.controls.map((c) => {
              const unit = c.unit || '';
              if (c.type === 'color') {
                return `<label class="lib-ctrl"><span>${escapeHtml(c.label)}</span><input type="color" data-css-var="${escapeHtml(c.cssVar)}" value="${escapeHtml(c.default)}"></label>`;
              }
              return `<label class="lib-ctrl"><span>${escapeHtml(c.label)} (<output data-var-out="${escapeHtml(c.cssVar)}">${escapeHtml(c.default)}${escapeHtml(unit)}</output>)</span><input type="range" data-css-var="${escapeHtml(c.cssVar)}" data-unit="${escapeHtml(unit)}" min="${escapeHtml(c.min ?? 0)}" max="${escapeHtml(c.max ?? 100)}" value="${escapeHtml(c.default)}"></label>`;
            }).join('')}
          </div>
        </div>`
      : '';

    return `<section class="lib-panel" aria-labelledby="preview-heading">
      <div class="lib-panel-head">
        <h2 id="preview-heading">Sandboxed Live Preview</h2>
        <span class="lib-pill">Isolated iframe (no same-origin access)</span>
      </div>
      <div class="lib-preview-box">
        <iframe class="lib-sandbox-frame" sandbox="allow-scripts" referrerpolicy="no-referrer" loading="lazy" style="height:${Number(p.height || 260)}px" title="Live sandboxed preview of ${escapeHtml(item.name)}" srcdoc="${escapeHtml(srcdoc)}"></iframe>
      </div>
      ${p.caption ? `<p class="lib-preview-caption">${escapeHtml(p.caption)}</p>` : ''}
      ${controlsHtml}
    </section>`;
  }

  if (p.type === 'contract-summary' && item.contract) {
    const ops = item.contract.operations || [];
    const rows = ops.map((op) => {
      const sig = `${op.name}(${(op.parameters || []).map((pr) => `${pr.name}: ${pr.type}`).join(', ')})`;
      const ret = op.returns?.type || 'any';
      const eff = (op.sideEffects || ['none']).join(', ');
      return `<tr>
        <td><code>${escapeHtml(sig)}</code></td>
        <td><code>${escapeHtml(ret)}</code></td>
        <td>${escapeHtml(eff)}</td>
        <td><code>${escapeHtml(op.errorMode || 'returns-fallback')}</code></td>
      </tr>`;
    }).join('');
    return `<section class="lib-panel" aria-labelledby="preview-heading">
      <div class="lib-panel-head">
        <h2 id="preview-heading">Schema v${escapeHtml(item.contract.schemaVersion)} Operation Contract (${ops.length} operations)</h2>
        ${item.contract.variablePrefix ? `<span class="lib-pill">Scoping Prefix: <code>${escapeHtml(item.contract.variablePrefix)}</code></span>` : ''}
      </div>
      <p class="lib-preview-caption">${escapeHtml(p.caption || '')}</p>
      <div class="lib-table-wrap">
        <table class="lib-contract-table">
          <thead><tr><th>Operation Signature</th><th>Returns</th><th>Side Effects</th><th>Error Mode</th></tr></thead>
          <tbody>${rows}</tbody>
        </table>
      </div>
    </section>`;
  }

  // Diagram / Native / Screenshot / Video / Project Reference preview (Desktop, Games, Otter Blueprints/Recipes/Workflows/Snippets)
  const steps = (p.architecture || []).map((s, idx) =>
    `<li class="lib-arch-step"><span class="lib-arch-num">${idx + 1}</span><span>${escapeHtml(s)}</span></li>`
  ).join('');
  const shots = (p.screenshots || []).map((src) =>
    `<img class="lib-preview-img" src="${escapeHtml(src)}" alt="Preview screenshot of ${escapeHtml(item.name)}" loading="lazy">`
  ).join('');
  const videoHtml = p.video
    ? `<video class="lib-preview-video" controls preload="metadata" src="${escapeHtml(p.video)}"></video>`
    : '';
  const projectRefHtml = p.projectRef
    ? `<div class="lib-project-ref"><strong>Example Project Integration:</strong> ${escapeHtml(p.projectRef)}</div>`
    : '';

  return `<section class="lib-panel" aria-labelledby="preview-heading">
    <div class="lib-panel-head">
      <h2 id="preview-heading">Architecture &amp; Runtime Preview</h2>
      <span class="lib-pill">${escapeHtml(item.framework)}</span>
    </div>
    ${p.caption ? `<p class="lib-preview-caption">${escapeHtml(p.caption)}</p>` : ''}
    ${shots}${videoHtml}
    ${steps ? `<ol class="lib-arch-list">${steps}</ol>` : ''}
    ${projectRefHtml}
  </section>`;
}

function renderSourceTabs(item) {
  const files = item.files || [];
  const tabs = files.map((f, idx) =>
    `<button type="button" role="tab" class="lib-tab${idx === 0 ? ' is-active' : ''}" id="tab-${idx}" aria-controls="panel-${idx}" aria-selected="${idx === 0 ? 'true' : 'false'}" tabindex="${idx === 0 ? '0' : '-1'}" data-file-index="${idx}">${escapeHtml(f.label)}</button>`
  ).join('');

  const panels = files.map((f, idx) =>
    `<div role="tabpanel" id="panel-${idx}" aria-labelledby="tab-${idx}" class="lib-code-panel${idx === 0 ? '' : ' is-hidden'}" data-file-panel="${idx}">
      <div class="lib-code-toolbar">
        <span class="lib-code-lang">${escapeHtml(f.label)} · ${escapeHtml(f.language)}</span>
        <div class="lib-code-actions">
          <button type="button" class="lib-btn-copy" data-copy-target="raw-code-${idx}">Copy file</button>
          ${files.length > 1 ? '<button type="button" class="lib-btn-copy lib-btn-copy-all" data-copy-all="true">Copy all files</button>' : ''}
        </div>
      </div>
      <pre class="lib-code-pre"><code data-lang="${escapeHtml(f.language)}">${highlightCode(f.content, f.language)}</code></pre>
      <textarea id="raw-code-${idx}" class="lib-raw-code" readonly aria-hidden="true" tabindex="-1">${escapeHtml(f.content)}</textarea>
    </div>`
  ).join('');

  return `<section class="lib-panel" aria-labelledby="source-heading">
    <div class="lib-panel-head">
      <h2 id="source-heading">Source Code (${files.length} ${files.length === 1 ? 'file' : 'files'})</h2>
      <span class="lib-copy-live" aria-live="polite"></span>
    </div>
    <div class="lib-tabs" role="tablist" aria-label="Component source files">${tabs}</div>
    ${panels}
  </section>`;
}

function renderDetailPage(item, bySlug, chrome, provenance) {
  const catMeta = CATEGORY_META[item.category] || { label: item.category };
  const depsHtml = (item.dependencies || []).length
    ? `<ul class="lib-meta-list">${item.dependencies.map((d) => `<li><code>${escapeHtml(d.name)}</code> <span>${escapeHtml(d.version)}</span></li>`).join('')}</ul>`
    : '<p class="lib-meta-muted">No external dependencies required.</p>';

  const relatedItems = (item.related || []).map((s) => bySlug.get(s)).filter(Boolean);
  const relatedHtml = relatedItems.length
    ? `<section class="lib-panel" aria-labelledby="related-heading">
        <h2 id="related-heading">Related Components</h2>
        <div class="lib-related-grid">
          ${relatedItems.map((rel) => `<a class="lib-related-card" href="/library/${escapeHtml(rel.slug)}/">
            <span class="lib-related-cat">${escapeHtml(CATEGORY_META[rel.category]?.label || rel.category)} · ${escapeHtml(rel.subcategory)}</span>
            <strong>${escapeHtml(rel.name)}</strong>
            <span>${escapeHtml(rel.description.slice(0, 110))}${rel.description.length > 110 ? '…' : ''}</span>
          </a>`).join('')}
        </div>
      </section>`
    : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(item.name)} - Otter Component Library</title>
<meta name="description" content="${escapeHtml(item.description)}">
${chrome.otterBaseStyle}
<link rel="icon" href="/static/images/otter-site-icon.png" type="image/png">
<link rel="apple-touch-icon" href="/static/images/otter-site-icon.png">
<link rel="stylesheet" href="/static/docs-enhancements.css">
<link rel="stylesheet" href="/static/library-app.css">
<script defer src="/static/docs-enhancements.js"></script>
<script type="module" src="/static/library-app.js"></script>
</head>
<body class="otter-has-page otter-doc-scroll lib-body">
<div class="otter-page" id="app" style="width:100%;max-width:100%;background:#f4f7fb;color:#0f1f36;padding:0px;gap:0px;">
  ${chrome.topBar}
  <main class="lib-detail-main" id="libraryDetailMain">
    <nav class="lib-crumbs" aria-label="Breadcrumb">
      <a href="/library/">Otter Library</a>
      <span aria-hidden="true">/</span>
      <a href="/library/?category=${encodeURIComponent(item.category)}">${escapeHtml(catMeta.label)}</a>
      <span aria-hidden="true">/</span>
      <span>${escapeHtml(item.name)}</span>
    </nav>

    <header class="lib-detail-hero">
      <div class="lib-detail-badges">
        <span class="lib-cat-chip lib-cat-${escapeHtml(item.category)}">${escapeHtml(catMeta.label)}</span>
        <span class="lib-sub-chip">${escapeHtml(item.subcategory)}</span>
        <span class="lib-lang-chip">${escapeHtml(item.language)}</span>
        <span class="lib-ver-chip ${verificationBadgeClass(item.verification?.status)}">${escapeHtml(item.verification?.label || 'Source Reviewed')}</span>
      </div>
      <h1>${escapeHtml(item.name)}</h1>
      <p class="lib-detail-desc">${escapeHtml(item.description)}</p>
      <div class="lib-detail-quickmeta">
        <span><strong>ID:</strong> <code>${escapeHtml(item.id)}</code></span>
        <span><strong>Version:</strong> ${escapeHtml(item.version)}</span>
        <span><strong>License:</strong> ${escapeHtml(item.license)}</span>
        <span><strong>Framework:</strong> ${escapeHtml(item.framework)}</span>
      </div>
    </header>

    <div class="lib-detail-layout">
      <div class="lib-detail-primary">
        ${renderPreviewSection(item)}
        ${renderSourceTabs(item)}

        <section class="lib-panel" aria-labelledby="install-heading">
          <div class="lib-panel-head">
            <h2 id="install-heading">Installation &amp; Usage</h2>
            <button type="button" class="lib-btn-copy" data-copy-target="raw-install">Copy command</button>
          </div>
          <pre class="lib-code-pre"><code data-lang="bash">${highlightCode(item.install, 'bash')}</code></pre>
          <textarea id="raw-install" class="lib-raw-code" readonly aria-hidden="true" tabindex="-1">${escapeHtml(item.install)}</textarea>
          <p class="lib-usage-text">${escapeHtml(item.usage)}</p>
        </section>

        ${relatedHtml}
      </div>

      <aside class="lib-detail-aside" aria-label="Component metadata">
        <section class="lib-aside-card">
          <h3>Verification Status</h3>
          <p class="lib-ver-badge-block ${verificationBadgeClass(item.verification?.status)}">${escapeHtml(item.verification?.label || 'Source Reviewed')}</p>
          <p class="lib-aside-copy">${escapeHtml(item.verification?.details || '')}</p>
        </section>

        <section class="lib-aside-card">
          <h3>Dependencies</h3>
          ${depsHtml}
        </section>

        <section class="lib-aside-card">
          <h3>Compatibility &amp; Platforms</h3>
          <ul class="lib-meta-list">
            ${(item.platforms || []).map((pl) => `<li>${escapeHtml(pl)}</li>`).join('')}
          </ul>
        </section>

        <section class="lib-aside-card">
          <h3>Tags</h3>
          <div class="lib-tags-wrap">
            ${(item.tags || []).map((t) => `<a class="lib-tag" href="/library/?q=${encodeURIComponent(t)}">#${escapeHtml(t)}</a>`).join('')}
          </div>
        </section>

        <section class="lib-aside-card">
          <h3>Catalog Provenance</h3>
          <p class="lib-aside-copy">Canonical Otter assets synced from <code>${escapeHtml(provenance.canonicalRepo)}</code> @ <code>${escapeHtml(String(provenance.sourceCommit || '').slice(0, 7))}</code> (tree <code>${escapeHtml(String(provenance.libraryTreeSha256 || '').slice(0, 12))}</code>).</p>
          <a class="lib-back-link" href="/library/">← Back to all ${escapeHtml(provenance.totalCount)} components</a>
        </section>
      </aside>
    </div>
  </main>
  ${chrome.siteFooter}
</div>
</body>
</html>
`;
}

export function buildLibraryPages(options = {}) {
  const outputRoot = resolve(options.outputRoot || resolve(DOCS_ROOT, 'generated'));
  const catalogPath = join(outputRoot, 'static', 'library-catalog.json');
  const libraryIndexPath = join(outputRoot, 'library', 'index.html');

  if (!existsSync(catalogPath)) {
    throw new Error(`Missing catalog JSON at ${catalogPath}. Run build-library-catalog.mjs first.`);
  }
  if (!existsSync(libraryIndexPath)) {
    throw new Error(`Missing Otter-compiled /library/index.html at ${libraryIndexPath}. Run build-otter-pages.ps1 first.`);
  }

  const catalog = JSON.parse(readFileSync(catalogPath, 'utf8'));
  const items = catalog.components || [];
  const bySlug = new Map(items.map((i) => [i.slug, i]));

  // 1. Enhance Otter-compiled /library/index.html with library-app assets + fallback static links
  let libIndexHtml = readFileSync(libraryIndexPath, 'utf8');
  const chrome = extractShellChrome(libIndexHtml);

  const libHeadAssets =
    '<link rel="stylesheet" href="/static/library-app.css">\n' +
    '<script type="module" src="/static/library-app.js"></script>\n';
  if (!libIndexHtml.includes('/static/library-app.css')) {
    libIndexHtml = libIndexHtml.replace(/<\/head>/i, `${libHeadAssets}</head>`);
  }

  // Provide semantic mount container & crawlable fallback list inside #libraryMount
  const staticFallbackLinks = items.map((it) =>
    `<a class="lib-noscript-link" href="/library/${escapeHtml(it.slug)}/">${escapeHtml(it.name)} (${escapeHtml(it.language)})</a>`
  ).join('');
  const mountMarkup = `<div id="libraryAppRoot" class="lib-app-root" data-catalog-url="/static/library-catalog.json">
    <noscript><div class="lib-panel"><h2>Browse all ${items.length} components</h2><div class="lib-noscript-grid">${staticFallbackLinks}</div></div></noscript>
  </div>`;

  if (!libIndexHtml.includes('id="libraryAppRoot"')) {
    libIndexHtml = libIndexHtml.replace(
      /(<div id="libraryMount"[^>]*>)([\s\S]*?)(<\/div>)/,
      `$1${mountMarkup}$3`
    );
  }
  writeFileSync(libraryIndexPath, libIndexHtml, 'utf8');

  // 2. Generate static /library/<slug>/index.html for every component
  let builtCount = 0;
  for (const item of items) {
    const destDir = join(outputRoot, 'library', item.slug);
    mkdirSync(destDir, { recursive: true });
    const html = renderDetailPage(item, bySlug, chrome, catalog.provenance);
    writeFileSync(join(destDir, 'index.html'), html, 'utf8');
    builtCount++;
  }

  // 3. Merge library entries into static/docs-index.json so site-wide Ctrl+K search finds them
  const docsIndexPath = join(outputRoot, 'static', 'docs-index.json');
  if (existsSync(docsIndexPath)) {
    const existing = JSON.parse(readFileSync(docsIndexPath, 'utf8'));
    const byUrl = new Map();
    for (const entry of Array.isArray(existing) ? existing : []) {
      byUrl.set(entry.url, entry);
    }
    for (const item of items) {
      const url = `/library/${item.slug}/`;
      byUrl.set(url, {
        title: `${item.name} (${CATEGORY_META[item.category]?.label || item.category} Library)`,
        url,
        text: `${item.description} ${(item.tags || []).join(' ')} ${item.language} ${item.framework}`
      });
    }
    const merged = [...byUrl.values()].sort((a, b) => a.url.localeCompare(b.url));
    writeFileSync(docsIndexPath, JSON.stringify(merged, null, 2) + '\n', 'utf8');
  }

  return { builtCount, totalComponents: items.length };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const opts = parseArgs(process.argv.slice(2));
  const res = buildLibraryPages(opts);
  console.log(`Generated ${res.builtCount} static component detail pages under ${join(opts.outputRoot, 'library')}`);
}
