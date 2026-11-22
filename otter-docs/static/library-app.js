import {
  CATEGORY_META,
  escapeHtml,
  extractFacets,
  filterComponents
} from './library-filter.mjs';

const VERIFICATION_LABELS = {
  all: 'All verification levels',
  'contract-and-behavior-verified': 'Contract-Validated & Behaviorally Tested',
  'behaviorally-tested': 'Behaviorally Tested',
  'contract-validated': 'Contract-Validated / Compile-Checked',
  'source-reviewed': 'Source Reviewed'
};

function badgeClass(status) {
  if (status === 'contract-and-behavior-verified') return 'lib-badge-verified';
  if (status === 'behaviorally-tested') return 'lib-badge-tested';
  if (status === 'contract-validated') return 'lib-badge-contract';
  return 'lib-badge-reviewed';
}

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      // Fall through to execCommand fallback if clipboard permission is unavailable
    }
  }
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  const ok = document.execCommand('copy');
  ta.remove();
  if (!ok) throw new Error('Copy command failed');
}

function initGallery(mount) {
  const catalogUrl = mount.dataset.catalogUrl || '/static/library-catalog.json';
  const params = new URLSearchParams(window.location.search);
  const state = {
    query: params.get('q') || '',
    category: params.get('category') || 'all',
    subcategory: params.get('sub') || 'all',
    language: params.get('lang') || 'all',
    verification: params.get('ver') || 'all'
  };

  let catalog = null;
  let lastCategoryForSubs = null;

  function syncUrl() {
    const next = new URLSearchParams();
    if (state.query) next.set('q', state.query);
    if (state.category !== 'all') next.set('category', state.category);
    if (state.subcategory !== 'all') next.set('sub', state.subcategory);
    if (state.language !== 'all') next.set('lang', state.language);
    if (state.verification !== 'all') next.set('ver', state.verification);
    const qs = next.toString();
    const target = qs ? `${window.location.pathname}?${qs}` : window.location.pathname;
    window.history.replaceState(null, '', target);
  }

  function buildShellOnce() {
    const allItems = catalog.components || [];
    const facets = extractFacets(allItems);
    const prov = catalog.provenance || {};

    const catOrder = ['all', 'web', 'desktop', 'games', 'effects', 'otter'];
    const catTabsHtml = catOrder.map((key) => {
      const label = key === 'all' ? 'All Components' : CATEGORY_META[key].label;
      const count = facets.categoryCounts[key] || 0;
      return `<button type="button" class="lib-cat-tab" data-cat="${key}" aria-pressed="${state.category === key}">${escapeHtml(label)} <span class="lib-tab-count">${count}</span></button>`;
    }).join('');

    const langPillsHtml = [
      `<button type="button" class="lib-lang-pill" data-lang="all" aria-pressed="${state.language === 'all'}">All Languages</button>`,
      ...facets.languages.map(([lang, cnt]) =>
        `<button type="button" class="lib-lang-pill" data-lang="${escapeHtml(lang)}" aria-pressed="${state.language.toLowerCase() === lang.toLowerCase()}">${escapeHtml(lang)} (${cnt})</button>`
      )
    ].join('');

    const verOptions = Object.entries(VERIFICATION_LABELS).map(([k, lbl]) =>
      `<option value="${k}"${state.verification === k ? ' selected' : ''}>${escapeHtml(lbl)}</option>`
    ).join('');

    mount.innerHTML = `
      <section class="lib-controls-bar" aria-label="Filter component library">
        <div class="lib-search-row">
          <input id="libSearchInput" class="lib-search-input" type="search" placeholder="Search components, Otter packs, operations, tags, or frameworks..." aria-label="Search component library" autocomplete="off" spellcheck="false">
          <select id="libSubSelect" class="lib-select" aria-label="Filter by subcategory"></select>
          <select id="libVerSelect" class="lib-select" aria-label="Filter by verification status">${verOptions}</select>
          <button id="libResetBtn" type="button" class="lib-reset-btn">Reset filters</button>
        </div>
        <div class="lib-cat-tabs" role="group" aria-label="Categories">${catTabsHtml}</div>
        <div class="lib-lang-row" role="group" aria-label="Languages and frameworks"><span class="lib-lang-label">Language:</span>${langPillsHtml}</div>
      </section>
      <div id="libSummaryBar" class="lib-summary-bar" aria-live="polite"></div>
      <div id="libResultsHost"></div>
      <footer class="lib-provenance-bar">
        <span>Canonical Otter source: <code>${escapeHtml(prov.canonicalRepo || 'Heavens-Lava/otter-net')}@${escapeHtml(String(prov.sourceCommit || '').slice(0, 7))}</code></span>
        <span>Library SHA-256: <code>${escapeHtml(String(prov.libraryTreeSha256 || '').slice(0, 16))}</code> · Runtime target: Otter ${escapeHtml(prov.expectedOtterVersion || '1.0.1')}</span>
      </footer>
    `;

    const searchInput = mount.querySelector('#libSearchInput');
    const subSelect = mount.querySelector('#libSubSelect');
    const verSelect = mount.querySelector('#libVerSelect');
    const resetBtn = mount.querySelector('#libResetBtn');

    searchInput.value = state.query;

    // Persistent DOM listeners: #libSearchInput never unmounts, preserving focus, caret, selection, and IME.
    searchInput.addEventListener('input', (e) => {
      state.query = e.target.value;
      syncUrl();
      updateResults();
    });
    subSelect.addEventListener('change', (e) => {
      state.subcategory = e.target.value;
      syncUrl();
      updateResults();
    });
    verSelect.addEventListener('change', (e) => {
      state.verification = e.target.value;
      syncUrl();
      updateResults();
    });
    resetBtn.addEventListener('click', () => {
      state.query = '';
      state.category = 'all';
      state.subcategory = 'all';
      state.language = 'all';
      state.verification = 'all';
      searchInput.value = '';
      verSelect.value = 'all';
      syncUrl();
      updateResults();
    });
    mount.querySelectorAll('.lib-cat-tab').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.category = btn.dataset.cat;
        state.subcategory = 'all';
        syncUrl();
        updateResults();
      });
    });
    mount.querySelectorAll('.lib-lang-pill').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.language = btn.dataset.lang;
        syncUrl();
        updateResults();
      });
    });
  }

  function updateResults() {
    if (!catalog) return;
    const allItems = catalog.components || [];
    const prov = catalog.provenance || {};

    // Update category & language button pressed states in-place (preserving keyboard focus)
    mount.querySelectorAll('.lib-cat-tab').forEach((btn) => {
      btn.setAttribute('aria-pressed', String(state.category === btn.dataset.cat));
    });
    mount.querySelectorAll('.lib-lang-pill').forEach((btn) => {
      const pressed = btn.dataset.lang === 'all'
        ? state.language === 'all'
        : state.language.toLowerCase() === btn.dataset.lang.toLowerCase();
      btn.setAttribute('aria-pressed', String(pressed));
    });

    // Rebuild subcategory options only when the selected category changes
    const subSelect = mount.querySelector('#libSubSelect');
    if (lastCategoryForSubs !== state.category) {
      const catPool = state.category === 'all' ? allItems : allItems.filter((i) => i.category === state.category);
      const subFacets = extractFacets(catPool).subcategories;
      subSelect.innerHTML = [
        `<option value="all">All subcategories</option>`,
        ...subFacets.map(([sub, cnt]) =>
          `<option value="${escapeHtml(sub)}">${escapeHtml(sub)} (${cnt})</option>`
        )
      ].join('');
      lastCategoryForSubs = state.category;
    }
    subSelect.value = state.subcategory;
    if (subSelect.value !== state.subcategory) {
      state.subcategory = 'all';
      subSelect.value = 'all';
    }

    const filtered = filterComponents(allItems, state);

    const summaryBar = mount.querySelector('#libSummaryBar');
    summaryBar.innerHTML = `
      <span>Showing <strong>${filtered.length}</strong> of <strong>${allItems.length}</strong> reusable components</span>
      <span>Otter canonical assets: ${prov.otterCounts?.packs || 0} Packs · ${prov.otterCounts?.workflows || 0} Workflows · ${prov.otterCounts?.blueprints || 0} Blueprints · ${prov.otterCounts?.recipes || 0} Recipes · ${prov.otterCounts?.snippets || 0} Snippets</span>
    `;

    const resultsHost = mount.querySelector('#libResultsHost');
    resultsHost.innerHTML = filtered.length
      ? `<div class="lib-grid" role="list">${filtered.map((item) => {
          const previewTag = item.preview?.type === 'iframe-sandbox'
            ? 'Live Preview'
            : (item.preview?.type === 'contract-summary' ? `${item.contract?.operationsCount || 0} Ops Contract` : 'Source & Architecture');
          const firstLine = ((item.files?.[0]?.content || '').split('\n').find((l) => l.trim() && !l.trim().startsWith('#')) || item.id).trim();
          return `<a class="lib-card" role="listitem" href="/library/${escapeHtml(item.slug)}/">
            <div class="lib-card-thumb lib-card-thumb-${escapeHtml(item.category)}">
              <div class="lib-thumb-top">
                <span class="lib-thumb-badge">${escapeHtml(CATEGORY_META[item.category]?.label || item.category)} · ${escapeHtml(item.subcategory)}</span>
                <span class="lib-thumb-preview-type">${escapeHtml(previewTag)}</span>
              </div>
              <div class="lib-thumb-code">${escapeHtml(firstLine.slice(0, 56))}</div>
            </div>
            <div class="lib-card-body">
              <h3 class="lib-card-title">${escapeHtml(item.name)}</h3>
              <p class="lib-card-desc">${escapeHtml(item.description)}</p>
              <div class="lib-card-meta">
                <span class="lib-lang-chip">${escapeHtml(item.language)}</span>
                <span class="lib-ver-chip ${badgeClass(item.verification?.status)}">${escapeHtml(item.verification?.label || 'Source Reviewed')}</span>
              </div>
            </div>
          </a>`;
        }).join('')}</div>`
      : `<div class="lib-empty" role="status"><strong>No components match your filters.</strong><p>Try clearing the search query or switching category filters.</p></div>`;
  }

  fetch(catalogUrl)
    .then((r) => {
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return r.json();
    })
    .then((data) => {
      catalog = data;
      buildShellOnce();
      updateResults();
    })
    .catch((err) => {
      mount.innerHTML = `<div class="lib-empty"><strong>Could not load library catalog.</strong><p>${escapeHtml(err.message)}</p></div>`;
    });
}

function initDetailPage(main) {
  // 1. Accessible file tabs with Left/Right/Home/End keyboard navigation
  const tabs = [...main.querySelectorAll('[role="tab"][data-file-index]')];
  const panels = [...main.querySelectorAll('[role="tabpanel"][data-file-panel]')];

  function activateTab(idx) {
    tabs.forEach((t, i) => {
      const selected = i === idx;
      t.classList.toggle('is-active', selected);
      t.setAttribute('aria-selected', String(selected));
      t.tabIndex = selected ? 0 : -1;
    });
    panels.forEach((p, i) => p.classList.toggle('is-hidden', i !== idx));
  }

  tabs.forEach((tab, idx) => {
    tab.addEventListener('click', () => activateTab(idx));
    tab.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight') { e.preventDefault(); const n = (idx + 1) % tabs.length; activateTab(n); tabs[n].focus(); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); const n = (idx - 1 + tabs.length) % tabs.length; activateTab(n); tabs[n].focus(); }
      else if (e.key === 'Home') { e.preventDefault(); activateTab(0); tabs[0].focus(); }
      else if (e.key === 'End') { e.preventDefault(); activateTab(tabs.length - 1); tabs[tabs.length - 1].focus(); }
    });
  });

  // 2. Copy single file / Copy all files / Copy install command
  const liveStatus = main.querySelector('.lib-copy-live');
  main.querySelectorAll('.lib-btn-copy').forEach((btn) => {
    btn.addEventListener('click', async () => {
      let text = '';
      if (btn.dataset.copyAll === 'true') {
        const allRaws = [...main.querySelectorAll('textarea[id^="raw-code-"]')];
        text = allRaws.map((ta, i) => {
          const label = tabs[i]?.textContent?.trim() || `file-${i + 1}`;
          return `/* ===== ${label} ===== */\n${ta.value}`;
        }).join('\n\n');
      } else if (btn.dataset.copyTarget) {
        const ta = document.getElementById(btn.dataset.copyTarget);
        text = ta ? ta.value : '';
      }
      if (!text) return;
      try {
        await copyText(text);
        const orig = btn.dataset.origLabel || btn.textContent;
        btn.dataset.origLabel = orig;
        btn.textContent = 'Copied!';
        if (liveStatus) liveStatus.textContent = 'Copied to clipboard.';
        clearTimeout(btn._copyTimer);
        btn._copyTimer = setTimeout(() => {
          btn.textContent = orig;
          if (liveStatus) liveStatus.textContent = '';
        }, 1800);
      } catch {
        if (liveStatus) liveStatus.textContent = 'Clipboard unavailable.';
      }
    });
  });

  // 3. Live CSS custom property bridge for opaque-origin sandboxed iframe previews
  const frame = main.querySelector('.lib-sandbox-frame');
  const controls = [...main.querySelectorAll('[data-css-var]')];
  if (frame && controls.length) {
    const channel = frame.dataset.previewChannel || '';
    const pushVars = () => {
      const vars = {};
      controls.forEach((ctrl) => {
        const unit = ctrl.dataset.unit || '';
        const val = `${ctrl.value}${unit}`;
        vars[ctrl.dataset.cssVar] = val;
        const out = main.querySelector(`output[data-var-out="${ctrl.dataset.cssVar}"]`);
        if (out) out.textContent = val;
      });
      // Opaque-origin sandboxed iframes (without allow-same-origin) have origin 'null',
      // so '*' is required when posting from parent to child. Only non-sensitive whitelisted
      // CSS custom property values and the preview channel token are ever transmitted.
      frame.contentWindow?.postMessage({ type: 'otter-lib-vars', channel, vars }, '*');
    };
    controls.forEach((ctrl) => ctrl.addEventListener('input', pushVars));
    frame.addEventListener('load', pushVars);
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const galleryRoot = document.getElementById('libraryAppRoot');
  if (galleryRoot) initGallery(galleryRoot);
  const detailMain = document.getElementById('libraryDetailMain');
  if (detailMain) initDetailPage(detailMain);
});
