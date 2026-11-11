// library-explorer.js - Reusable Snippets & Package Explorer Component for Otter Studio
// Implements RFC Phase 2: Search, Preview, Insert, Pack Installation & Dependency Viewer

export class LibraryExplorer {
  constructor(options = {}) {
    this.snippets = options.snippets || [];
    this.packs = options.packs || [];
    this.blueprints = options.blueprints || [];
    this.installedPackages = options.installedPackages || {};
    this.activeTab = 'snippets'; // 'snippets' | 'packs' | 'installed' | 'blueprints'
    this.searchQuery = '';
    this.selectedCategory = 'all';
    this.selectedItem = null;
    this.onInsertSnippet = options.onInsertSnippet || (() => {});
    this.onInstallPack = options.onInstallPack || (() => {});
    this.onUninstallPack = options.onUninstallPack || (() => {});
    this.onViewExample = options.onViewExample || (() => {});
    this.onOpenBlueprint = options.onOpenBlueprint || (() => {});
  }

  setCatalog(catalog) {
    if (catalog.snippets) this.snippets = catalog.snippets;
    if (catalog.packs) this.packs = catalog.packs;
    if (catalog.blueprints) this.blueprints = catalog.blueprints;
    if (catalog.installed) this.installedPackages = catalog.installed;
  }

  getCategories() {
    const cats = new Set(['all']);
    for (const s of this.snippets) {
      if (s.category) cats.add(s.category);
    }
    return Array.from(cats);
  }

  getFilteredSnippets() {
    const q = this.searchQuery.trim().toLowerCase();
    return this.snippets.filter(s => {
      if (this.selectedCategory !== 'all' && s.category !== this.selectedCategory) {
        return false;
      }
      if (!q) return true;
      const haystack = `${s.id} ${s.title} ${s.category} ${s.description} ${(s.tags || []).join(' ')}`.toLowerCase();
      const tokens = q.split(/\s+/);
      return tokens.every(token => haystack.includes(token));
    });
  }

  getFilteredPacks() {
    const q = this.searchQuery.trim().toLowerCase();
    return this.packs.filter(p => {
      if (!q) return true;
      const haystack = `${p.name} ${p.publisher} ${p.description} ${(p.tags || []).join(' ')}`.toLowerCase();
      const tokens = q.split(/\s+/);
      return tokens.every(token => haystack.includes(token));
    });
  }

  getFilteredBlueprints() {
    const q = this.searchQuery.trim().toLowerCase();
    return this.blueprints.filter(bp => {
      if (!q) return true;
      const haystack = `${bp.id} ${bp.title} ${bp.summary} ${(bp.targets || []).join(' ')}`.toLowerCase();
      const tokens = q.split(/\s+/);
      return tokens.every(token => haystack.includes(token));
    });
  }

  getInstalledList() {
    return Object.entries(this.installedPackages).map(([pkgName, meta]) => ({
      name: pkgName,
      ...meta
    }));
  }

  selectItem(item, type) {
    this.selectedItem = item ? { ...item, _type: type } : null;
  }

  render(containerEl) {
    if (!containerEl) return;
    this.container = containerEl;
    containerEl.className = 'library-explorer-panel';
    containerEl.innerHTML = `
      <div class="library-header">
        <div class="library-title-row">
          <span class="panel-title">Library Explorer</span>
          <span class="badge">Otter Reusable Hub</span>
        </div>
        <div class="library-nav-tabs">
          <button class="lib-tab-btn ${this.activeTab === 'snippets' ? 'is-active' : ''}" data-tab="snippets">Snippets (${this.snippets.length})</button>
          <button class="lib-tab-btn ${this.activeTab === 'packs' ? 'is-active' : ''}" data-tab="packs">Packs (${this.packs.length})</button>
          <button class="lib-tab-btn ${this.activeTab === 'blueprints' ? 'is-active' : ''}" data-tab="blueprints">Blueprints (${this.blueprints.length})</button>
          <button class="lib-tab-btn ${this.activeTab === 'installed' ? 'is-active' : ''}" data-tab="installed">Installed (${Object.keys(this.installedPackages).length})</button>
        </div>
        <div class="library-search-box">
          <input type="text" id="librarySearchInput" placeholder="Search (e.g. 'for loop', 'enemy damage', 'clamp')..." value="${this.escapeHtml(this.searchQuery)}" />
        </div>
        ${this.activeTab === 'snippets' ? `
          <div class="library-category-bar">
            ${this.getCategories().map(cat => `
              <button class="lib-cat-pill ${this.selectedCategory === cat ? 'is-active' : ''}" data-category="${this.escapeAttr(cat)}">${this.escapeHtml(cat)}</button>
            `).join('')}
          </div>
        ` : ''}
      </div>
      <div class="library-body">
        <div class="library-list-col" id="libraryListCol"></div>
        <div class="library-preview-col" id="libraryPreviewCol"></div>
      </div>
    `;

    this._bindEvents();
    this._renderList();
    this._renderPreview();
  }

  _bindEvents() {
    const searchInput = this.container.querySelector('#librarySearchInput');
    if (searchInput) {
      searchInput.addEventListener('input', (e) => {
        this.searchQuery = e.target.value;
        this._renderList();
      });
    }

    const tabBtns = this.container.querySelectorAll('.lib-tab-btn');
    tabBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        this.activeTab = btn.getAttribute('data-tab');
        this.selectedItem = null;
        this.render(this.container);
      });
    });

    const catBtns = this.container.querySelectorAll('.lib-cat-pill');
    catBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        this.selectedCategory = btn.getAttribute('data-category');
        this._renderList();
        catBtns.forEach(b => b.classList.toggle('is-active', b === btn));
      });
    });
  }

  _renderList() {
    const listCol = this.container.querySelector('#libraryListCol');
    if (!listCol) return;

    if (this.activeTab === 'snippets') {
      const items = this.getFilteredSnippets();
      if (items.length === 0) {
        listCol.innerHTML = `<div class="library-empty">No snippets match "${this.escapeHtml(this.searchQuery)}"</div>`;
        return;
      }
      listCol.innerHTML = items.map(s => `
        <div class="library-item-card ${this.selectedItem && this.selectedItem.id === s.id ? 'is-selected' : ''}" data-id="${this.escapeAttr(s.id)}" data-type="snippet">
          <div class="item-title-row">
            <span class="item-name">${this.escapeHtml(s.title)}</span>
            <span class="item-cat-badge">${this.escapeHtml(s.category)}</span>
          </div>
          <div class="item-desc">${this.escapeHtml(s.description)}</div>
          <div class="item-tags">
            ${(s.tags || []).slice(0, 4).map(t => `<span class="tag-chip">${this.escapeHtml(t)}</span>`).join('')}
          </div>
        </div>
      `).join('');
    } else if (this.activeTab === 'packs') {
      const items = this.getFilteredPacks();
      if (items.length === 0) {
        listCol.innerHTML = `<div class="library-empty">No packs match "${this.escapeHtml(this.searchQuery)}"</div>`;
        return;
      }
      listCol.innerHTML = items.map(p => `
        <div class="library-item-card ${this.selectedItem && this.selectedItem.name === p.name ? 'is-selected' : ''}" data-id="${this.escapeAttr(p.name)}" data-type="pack">
          <div class="item-title-row">
            <span class="item-name">${this.escapeHtml(p.publisher)}/${this.escapeHtml(p.name)}</span>
            <span class="item-ver-badge">v${this.escapeHtml(p.version)}</span>
          </div>
          <div class="item-desc">${this.escapeHtml(p.description)}</div>
          <div class="item-meta-row">
            <span>License: ${this.escapeHtml(p.license || 'MIT')}</span>
            <span>Platforms: ${(p.platforms || ['console']).join(', ')}</span>
          </div>
        </div>
      `).join('');
    } else if (this.activeTab === 'blueprints') {
      const items = this.getFilteredBlueprints();
      if (items.length === 0) {
        listCol.innerHTML = `<div class="library-empty">No blueprints match "${this.escapeHtml(this.searchQuery)}"</div>`;
        return;
      }
      listCol.innerHTML = items.map(bp => `
        <div class="library-item-card ${this.selectedItem && this.selectedItem.id === bp.id ? 'is-selected' : ''}" data-id="${this.escapeAttr(bp.id)}" data-type="blueprint">
          <div class="item-title-row">
            <span class="item-name">${this.escapeHtml(bp.title)}</span>
            <span class="item-ver-badge">v${this.escapeHtml(bp.version)}</span>
          </div>
          <div class="item-desc">${this.escapeHtml(bp.summary || '')}</div>
          <div class="item-meta-row">
            <span>Targets: ${(bp.targets || ['console']).join(', ')}</span>
            <span>Nodes: ${(bp.nodes || []).length}</span>
          </div>
        </div>
      `).join('');
    } else if (this.activeTab === 'installed') {
      const items = this.getInstalledList();
      if (items.length === 0) {
        listCol.innerHTML = `<div class="library-empty">No packages currently installed in project.</div>`;
        return;
      }
      listCol.innerHTML = items.map(p => `
        <div class="library-item-card ${this.selectedItem && this.selectedItem.name === p.name ? 'is-selected' : ''}" data-id="${this.escapeAttr(p.name)}" data-type="installed">
          <div class="item-title-row">
            <span class="item-name">${this.escapeHtml(p.name)}</span>
            <span class="item-ver-badge">v${this.escapeHtml(p.version)}</span>
          </div>
          <div class="item-desc">Entry point: <code>${this.escapeHtml(p.entry)}</code></div>
          <div class="item-hash">SHA-256: <code>${(p.sha256 || '').substring(0, 16)}...</code></div>
        </div>
      `).join('');
    }

    listCol.querySelectorAll('.library-item-card').forEach(card => {
      card.addEventListener('click', () => {
        const id = card.getAttribute('data-id');
        const type = card.getAttribute('data-type');
        let item = null;
        if (type === 'snippet') item = this.snippets.find(s => s.id === id);
        else if (type === 'pack') item = this.packs.find(p => p.name === id || `${p.publisher}/${p.name}` === id);
        else if (type === 'blueprint') item = this.blueprints.find(b => b.id === id);
        else if (type === 'installed') item = this.getInstalledList().find(p => p.name === id);
        this.selectItem(item, type);
        listCol.querySelectorAll('.library-item-card').forEach(c => c.classList.toggle('is-selected', c === card));
        this._renderPreview();
      });
    });
  }

  _renderPreview() {
    const previewCol = this.container.querySelector('#libraryPreviewCol');
    if (!previewCol) return;

    if (!this.selectedItem) {
      previewCol.innerHTML = `
        <div class="preview-placeholder">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18"/><path d="m14 9 3 3-3 3"/></svg>
          <p>Select a snippet or package to inspect documentation, template, and examples.</p>
        </div>
      `;
      return;
    }

    const item = this.selectedItem;
    if (item._type === 'snippet') {
      previewCol.innerHTML = `
        <div class="preview-header">
          <div class="preview-title-row">
            <h3 class="preview-title">${this.escapeHtml(item.title)}</h3>
            <button class="lib-action-btn primary" id="btnInsertSnippet">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>
              Insert Snippet
            </button>
          </div>
          <div class="preview-badges">
            <span class="preview-badge category">${this.escapeHtml(item.category)}</span>
            <span class="preview-badge cap">${(item.capabilities && item.capabilities.length) ? 'Requires: ' + item.capabilities.join(', ') : 'Pure Language'}</span>
            <span class="preview-badge target">${(item.platforms || ['console']).join(', ')}</span>
          </div>
          <p class="preview-desc">${this.escapeHtml(item.description)}</p>
        </div>
        <div class="preview-section">
          <div class="section-title">Insertable Template</div>
          <pre class="code-preview-block"><code>${this.escapeHtml(item.template)}</code></pre>
        </div>
        <div class="preview-section">
          <div class="section-title">Executable Demonstration</div>
          <pre class="code-preview-block"><code>${this.escapeHtml(item.example)}</code></pre>
        </div>
      `;

      previewCol.querySelector('#btnInsertSnippet').addEventListener('click', () => {
        this.onInsertSnippet(item);
      });
    } else if (item._type === 'pack') {
      const isInstalled = Boolean(this.installedPackages[`${item.publisher}/${item.name}`] || this.installedPackages[item.name]);
      previewCol.innerHTML = `
        <div class="preview-header">
          <div class="preview-title-row">
            <h3 class="preview-title">${this.escapeHtml(item.publisher)}/${this.escapeHtml(item.name)} <span class="ver">v${this.escapeHtml(item.version)}</span></h3>
            <button class="lib-action-btn ${isInstalled ? 'secondary' : 'primary'}" id="btnInstallPack">
              ${isInstalled ? 'Reinstall Pack' : 'Install Pack'}
            </button>
          </div>
          <div class="preview-badges">
            <span class="preview-badge license">License: ${this.escapeHtml(item.license || 'MIT')}</span>
            <span class="preview-badge cap">${(item.capabilities && item.capabilities.length) ? 'Capabilities: ' + item.capabilities.join(', ') : 'No external capabilities'}</span>
            <span class="preview-badge target">Platforms: ${(item.platforms || ['console']).join(', ')}</span>
          </div>
          <p class="preview-desc">${this.escapeHtml(item.description)}</p>
        </div>
        <div class="preview-section">
          <div class="section-title">Import Usage</div>
          <pre class="code-preview-block"><code>use ".otter/packages/${this.escapeHtml(item.publisher)}/${this.escapeHtml(item.name)}/${this.escapeHtml(item.version)}/${this.escapeHtml(item.entry)}"</code></pre>
        </div>
        ${item.examples && item.examples.length ? `
          <div class="preview-section">
            <div class="section-title">Examples</div>
            <div class="examples-list">
              ${item.examples.map(ex => `
                <div class="example-row">
                  <span>${this.escapeHtml(ex)}</span>
                  <button class="lib-small-btn" data-example="${this.escapeAttr(ex)}">Open</button>
                </div>
              `).join('')}
            </div>
          </div>
        ` : ''}
      `;

      previewCol.querySelector('#btnInstallPack').addEventListener('click', () => {
        this.onInstallPack(item);
      });

      previewCol.querySelectorAll('[data-example]').forEach(b => {
        b.addEventListener('click', () => {
          this.onViewExample(item, b.getAttribute('data-example'));
        });
      });
    } else if (item._type === 'installed') {
      previewCol.innerHTML = `
        <div class="preview-header">
          <div class="preview-title-row">
            <h3 class="preview-title">${this.escapeHtml(item.name)} <span class="ver">v${this.escapeHtml(item.version)}</span></h3>
            <button class="lib-action-btn danger" id="btnUninstallPack">Uninstall</button>
          </div>
          <p class="preview-desc">Installed in project lockfile. Ready to use via <code>use ".otter/packages/${this.escapeHtml(item.name)}/${this.escapeHtml(item.version)}/${this.escapeHtml(item.entry)}"</code>.</p>
        </div>
        <div class="preview-section">
          <div class="section-title">Package Integrity</div>
          <div class="integrity-card">
            <div><strong>Algorithm:</strong> SHA-256</div>
            <div><strong>Digest:</strong> <code>${this.escapeHtml(item.sha256)}</code></div>
            <div><strong>Installed At:</strong> ${this.escapeHtml(item.installedAt || 'N/A')}</div>
          </div>
        </div>
      `;

      previewCol.querySelector('#btnUninstallPack').addEventListener('click', () => {
        this.onUninstallPack(item);
      });
    } else if (item._type === 'blueprint') {
      previewCol.innerHTML = `
        <div class="preview-header">
          <div class="preview-title-row">
            <h3 class="preview-title">${this.escapeHtml(item.title)} <span class="ver">v${this.escapeHtml(item.version)}</span></h3>
            <button class="lib-action-btn primary" id="btnOpenBlueprint">Open in Workspace</button>
          </div>
          <div class="preview-badges">
            <span class="preview-badge license">ID: ${this.escapeHtml(item.id)}</span>
            <span class="preview-badge cap">Targets: ${(item.targets || ['console']).join(', ')}</span>
            <span class="preview-badge target">${(item.nodes || []).length} nodes, ${(item.edges || []).length} connections</span>
          </div>
          <p class="preview-desc">${this.escapeHtml(item.summary || '')}</p>
        </div>
        <div class="preview-section">
          <div class="section-title">Required Packs</div>
          <div class="examples-list">
            ${(item.packs || []).map(p => `
              <div class="example-row">
                <span><strong>${this.escapeHtml(p.id)}</strong> (v${this.escapeHtml(p.version)})</span>
              </div>
            `).join('')}
          </div>
        </div>
        <div class="preview-section">
          <div class="section-title">Architecture Explanation</div>
          <p class="preview-desc">${this.escapeHtml(item.explanations && item.explanations.intermediate ? item.explanations.intermediate : item.summary || '')}</p>
        </div>
      `;

      const btnOpen = previewCol.querySelector('#btnOpenBlueprint');
      if (btnOpen) {
        btnOpen.addEventListener('click', () => {
          this.onOpenBlueprint(item);
        });
      }
    }
  }

  escapeHtml(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  escapeAttr(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }
}
