// project-settings.js - Interactive Project Settings Visual Inspector for Otter Studio
import { validateManifest, normalizeManifest, VALID_ARCHETYPES } from '../project/project-manifest.js';

export function renderProjectSettings(container, options = {}) {
  if (!container) return;

  const {
    manifest: initialManifest,
    filePath = 'project.json',
    projectFiles = [],
    onChange = () => {},
    onSwitchToJson = () => {},
    onSave = () => {}
  } = options;

  let manifest = normalizeManifest(initialManifest);

  function escapeAttr(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function escapeHtml(str) {
    return String(str || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function render() {
    const validation = validateManifest(manifest, projectFiles);
    const otFiles = (projectFiles || [])
      .map(f => typeof f === 'string' ? f : (f.name || f.path || ''))
      .filter(f => f.endsWith('.ot'))
      .map(f => f.replace(/\\/g, '/').split('/').pop());

    const uniqueOtFiles = [...new Set(otFiles)];

    container.innerHTML = `
      <div class="project-settings-container">
        <!-- Settings Header Bar -->
        <header class="project-settings-header">
          <div class="header-left">
            <div class="project-icon-badge">⚙</div>
            <div class="header-titles">
              <h1 class="project-title">${escapeHtml(manifest.name || 'Untitled Project')}</h1>
              <span class="project-meta-path">${escapeHtml(filePath)}</span>
            </div>
            <span class="archetype-badge archetype-${manifest.target || 'desktop'}">${escapeHtml((manifest.target || 'desktop').toUpperCase())}</span>
            <span class="version-badge">v${escapeHtml(manifest.version || '1.0.0')}</span>
          </div>
          <div class="header-actions">
            <button type="button" class="btn-settings-action secondary" id="btnManifestSwitchToJson" title="Switch to raw JSON text editor">
              <span class="btn-icon">📄</span> Raw JSON
            </button>
            <button type="button" class="btn-settings-action primary" id="btnManifestSave" title="Save changes to project.json (Ctrl+S)">
              <span class="btn-icon">💾</span> Save Settings
            </button>
          </div>
        </header>

        <!-- Real-Time Diagnostic Banner -->
        <div class="manifest-diagnostics ${validation.ok && validation.warnings.length === 0 ? 'is-valid' : (validation.ok ? 'has-warnings' : 'has-errors')}">
          ${renderDiagnostics(validation)}
        </div>

        <!-- Settings Cards Grid -->
        <div class="project-settings-grid">
          <!-- Card 1: General Info -->
          <section class="settings-card">
            <div class="settings-card-header">
              <span class="card-icon">🏷</span>
              <h2>General Settings</h2>
            </div>
            <div class="settings-card-body">
              <div class="form-row">
                <div class="form-group flex-2">
                  <label for="inputManifestName">Project Name <span class="required">*</span></label>
                  <input type="text" id="inputManifestName" class="settings-input" value="${escapeAttr(manifest.name)}" placeholder="my-app" autocomplete="off" spellcheck="false" />
                </div>
                <div class="form-group flex-1">
                  <label for="inputManifestVersion">Version (SemVer) <span class="required">*</span></label>
                  <input type="text" id="inputManifestVersion" class="settings-input" value="${escapeAttr(manifest.version)}" placeholder="1.0.0" autocomplete="off" spellcheck="false" />
                </div>
              </div>

              <div class="form-row">
                <div class="form-group flex-1">
                  <label for="selectManifestTarget">Target Archetype</label>
                  <select id="selectManifestTarget" class="settings-select">
                    <option value="console" ${manifest.target === 'console' ? 'selected' : ''}>Console (Command Line Tool)</option>
                    <option value="desktop" ${manifest.target === 'desktop' ? 'selected' : ''}>Desktop (Native Window App)</option>
                    <option value="web" ${manifest.target === 'web' ? 'selected' : ''}>Web (Modern Web Application)</option>
                    <option value="game" ${manifest.target === 'game' ? 'selected' : ''}>Game (2D Interactive Canvas Game)</option>
                  </select>
                </div>
                <div class="form-group flex-1">
                  <label for="inputManifestEntry">Entry Point File <span class="required">*</span></label>
                  <div class="input-with-datalist">
                    <input type="text" id="inputManifestEntry" class="settings-input" list="manifestOtFiles" value="${escapeAttr(manifest.entryPoint)}" placeholder="main.ot" autocomplete="off" spellcheck="false" />
                    <datalist id="manifestOtFiles">
                      ${uniqueOtFiles.map(f => `<option value="${escapeAttr(f)}"></option>`).join('')}
                    </datalist>
                  </div>
                </div>
              </div>

              <div class="form-group">
                <label for="inputManifestDesc">Description</label>
                <input type="text" id="inputManifestDesc" class="settings-input" value="${escapeAttr(manifest.description)}" placeholder="Brief summary of your Otter project" autocomplete="off" />
              </div>

              <div class="form-row">
                <div class="form-group flex-1">
                  <label for="inputManifestAuthor">Author</label>
                  <input type="text" id="inputManifestAuthor" class="settings-input" value="${escapeAttr(manifest.author)}" placeholder="Developer Name" autocomplete="off" />
                </div>
                <div class="form-group flex-1">
                  <label for="inputManifestLicense">License</label>
                  <input type="text" id="inputManifestLicense" class="settings-input" value="${escapeAttr(manifest.license)}" placeholder="MIT" autocomplete="off" />
                </div>
              </div>
            </div>
          </section>

          <!-- Card 2: Build Configuration -->
          <section class="settings-card">
            <div class="settings-card-header">
              <span class="card-icon">⚡</span>
              <h2>Build &amp; Distribution</h2>
            </div>
            <div class="settings-card-body">
              <div class="form-group">
                <label for="inputManifestOutputDir">Output Directory</label>
                <input type="text" id="inputManifestOutputDir" class="settings-input" value="${escapeAttr(manifest.build?.outputDir || 'dist')}" placeholder="dist" autocomplete="off" />
              </div>

              <div class="toggle-list">
                <!-- No "source maps" option: otter build makes none (build.sourceMaps
                     in project.json is accepted and has no effect). -->
                <label class="toggle-item">
                  <input type="checkbox" id="checkManifestMinify" ${manifest.build?.minify ? 'checked' : ''} />
                  <span class="toggle-switch"></span>
                  <div class="toggle-copy">
                    <strong>Minify pages</strong>
                    <span>Removes comments and indentation from each page's code, about a fifth smaller; it works the same</span>
                  </div>
                </label>

                <label class="toggle-item">
                  <input type="checkbox" id="checkManifestClean" ${manifest.build?.clean !== false ? 'checked' : ''} />
                  <span class="toggle-switch"></span>
                  <div class="toggle-copy">
                    <strong>Clean Before Build</strong>
                    <span>Empties the output directory before generating fresh artifacts</span>
                  </div>
                </label>
              </div>
            </div>
          </section>

          <!-- Card 3: Permissions -->
          <section class="settings-card">
            <div class="settings-card-header">
              <span class="card-icon">🔒</span>
              <h2>Security &amp; Permissions</h2>
            </div>
            <div class="settings-card-body">
              <div class="toggle-list">
                <label class="toggle-item">
                  <input type="checkbox" id="permFilesystem" ${manifest.permissions?.filesystem !== false ? 'checked' : ''} />
                  <span class="toggle-switch"></span>
                  <div class="toggle-copy">
                    <strong>Filesystem Access</strong>
                    <span>Allows reading and writing local files within workspace bounds</span>
                  </div>
                </label>

                <label class="toggle-item">
                  <input type="checkbox" id="permNetwork" ${manifest.permissions?.network ? 'checked' : ''} />
                  <span class="toggle-switch"></span>
                  <div class="toggle-copy">
                    <strong>Network Access</strong>
                    <span>Enables outbound HTTP requests, web sockets, and APIs</span>
                  </div>
                </label>

                <label class="toggle-item">
                  <input type="checkbox" id="permClipboard" ${manifest.permissions?.clipboard !== false ? 'checked' : ''} />
                  <span class="toggle-switch"></span>
                  <div class="toggle-copy">
                    <strong>System Clipboard</strong>
                    <span>Permits copying and pasting text through Otter clipboard APIs</span>
                  </div>
                </label>

                <label class="toggle-item">
                  <input type="checkbox" id="permProcess" ${manifest.permissions?.process ? 'checked' : ''} />
                  <span class="toggle-switch"></span>
                  <div class="toggle-copy">
                    <strong>Process Execution</strong>
                    <span>Permits launching child processes and external commands</span>
                  </div>
                </label>
              </div>
            </div>
          </section>

          <!-- Card 4: Dependencies -->
          <section class="settings-card">
            <div class="settings-card-header">
              <span class="card-icon">📦</span>
              <h2>Dependencies</h2>
            </div>
            <div class="settings-card-body">
              <div class="table-list" id="dependencyList">
                ${renderDependencies(manifest.dependencies)}
              </div>
              <div class="add-row">
                <input type="text" id="inputNewDepName" class="settings-input flex-2" placeholder="Package name (e.g. core)" />
                <input type="text" id="inputNewDepVersion" class="settings-input flex-1" placeholder="Version (e.g. ^1.0.0)" />
                <button type="button" class="btn-settings-small" id="btnAddDependency">+ Add</button>
              </div>
            </div>
          </section>

          <!-- Card 5: Assets -->
          <section class="settings-card">
            <div class="settings-card-header">
              <span class="card-icon">🎨</span>
              <h2>Assets &amp; Resources</h2>
            </div>
            <div class="settings-card-body">
              <div class="table-list" id="assetList">
                ${renderAssets(manifest.assets)}
              </div>
              <div class="add-row">
                <input type="text" id="inputNewAsset" class="settings-input flex-2" placeholder="Asset path or glob (e.g. styles.css)" />
                <button type="button" class="btn-settings-small" id="btnAddAsset">+ Add</button>
              </div>
            </div>
          </section>

          <!-- Card 6: Scripts -->
          <section class="settings-card">
            <div class="settings-card-header">
              <span class="card-icon">▶</span>
              <h2>Project Scripts</h2>
            </div>
            <div class="settings-card-body">
              <div class="table-list" id="scriptList">
                ${renderScripts(manifest.scripts)}
              </div>
              <div class="add-row">
                <input type="text" id="inputNewScriptName" class="settings-input flex-1" placeholder="Script (e.g. lint)" />
                <input type="text" id="inputNewScriptCommand" class="settings-input flex-2" placeholder="Command (e.g. otter lint)" />
                <button type="button" class="btn-settings-small" id="btnAddScript">+ Add</button>
              </div>
            </div>
          </section>
        </div>
      </div>
    `;

    attachListeners();
  }

  function renderDiagnostics(validation) {
    if (validation.ok && validation.warnings.length === 0) {
      return `
        <div class="diag-icon">✓</div>
        <div class="diag-message">
          <strong>Manifest Valid</strong>
          <span>Entry point <code>${escapeHtml(manifest.entryPoint)}</code> is configured. All metadata fields conform to Otter Project v1 specification.</span>
        </div>
      `;
    }

    let items = [];
    if (!validation.ok) {
      items.push(...validation.errors.map(e => `<li class="diag-error"><strong>Error:</strong> ${escapeHtml(e)}</li>`));
    }
    if (validation.warnings.length > 0) {
      items.push(...validation.warnings.map(w => `<li class="diag-warning"><strong>Notice:</strong> ${escapeHtml(w)}</li>`));
    }

    return `
      <div class="diag-icon">${validation.ok ? '⚠' : '✕'}</div>
      <div class="diag-message">
        <strong>${validation.ok ? 'Validation Warnings' : 'Manifest Errors'}</strong>
        <ul class="diag-list">${items.join('')}</ul>
      </div>
    `;
  }

  function renderDependencies(deps = {}) {
    const entries = Object.entries(deps || {});
    if (entries.length === 0) {
      return `<div class="empty-list-notice">No dependencies configured.</div>`;
    }
    return entries.map(([name, version]) => `
      <div class="list-item-row" data-dep-name="${escapeAttr(name)}">
        <span class="item-name"><code>${escapeHtml(name)}</code></span>
        <span class="item-value"><code>${escapeHtml(version)}</code></span>
        <button type="button" class="btn-item-remove" data-remove-dep="${escapeAttr(name)}" title="Remove dependency">✕</button>
      </div>
    `).join('');
  }

  function renderAssets(assets = []) {
    if (!assets || assets.length === 0) {
      return `<div class="empty-list-notice">No asset files bundled.</div>`;
    }
    return assets.map((asset, index) => `
      <div class="list-item-row" data-asset-index="${index}">
        <span class="item-name"><code>${escapeHtml(asset)}</code></span>
        <button type="button" class="btn-item-remove" data-remove-asset="${index}" title="Remove asset">✕</button>
      </div>
    `).join('');
  }

  function renderScripts(scripts = {}) {
    const entries = Object.entries(scripts || {});
    if (entries.length === 0) {
      return `<div class="empty-list-notice">No scripts defined.</div>`;
    }
    return entries.map(([name, cmd]) => `
      <div class="list-item-row" data-script-name="${escapeAttr(name)}">
        <span class="item-name"><code>${escapeHtml(name)}</code></span>
        <span class="item-value"><code>${escapeHtml(cmd)}</code></span>
        <button type="button" class="btn-item-remove" data-remove-script="${escapeAttr(name)}" title="Remove script">✕</button>
      </div>
    `).join('');
  }

  function notifyChange() {
    onChange(normalizeManifest(manifest));
    const diagEl = container.querySelector('.manifest-diagnostics');
    if (diagEl) {
      const validation = validateManifest(manifest, projectFiles);
      diagEl.className = `manifest-diagnostics ${validation.ok && validation.warnings.length === 0 ? 'is-valid' : (validation.ok ? 'has-warnings' : 'has-errors')}`;
      diagEl.innerHTML = renderDiagnostics(validation);
    }
    const titleEl = container.querySelector('.project-title');
    if (titleEl) titleEl.textContent = manifest.name || 'Untitled Project';
    const verEl = container.querySelector('.version-badge');
    if (verEl) verEl.textContent = `v${manifest.version || '1.0.0'}`;
    const badgeEl = container.querySelector('.archetype-badge');
    if (badgeEl) {
      badgeEl.className = `archetype-badge archetype-${manifest.target || 'desktop'}`;
      badgeEl.textContent = (manifest.target || 'desktop').toUpperCase();
    }
  }

  function attachListeners() {
    // Header actions
    container.querySelector('#btnManifestSwitchToJson')?.addEventListener('click', () => {
      onSwitchToJson();
    });

    container.querySelector('#btnManifestSave')?.addEventListener('click', () => {
      onSave();
    });

    // General inputs
    const inputName = container.querySelector('#inputManifestName');
    inputName?.addEventListener('input', () => {
      manifest.name = inputName.value.trim();
      notifyChange();
    });

    const inputVersion = container.querySelector('#inputManifestVersion');
    inputVersion?.addEventListener('input', () => {
      manifest.version = inputVersion.value.trim();
      notifyChange();
    });

    const selectTarget = container.querySelector('#selectManifestTarget');
    selectTarget?.addEventListener('change', () => {
      manifest.target = selectTarget.value;
      manifest.archetype = selectTarget.value;
      notifyChange();
    });

    const inputEntry = container.querySelector('#inputManifestEntry');
    inputEntry?.addEventListener('input', () => {
      manifest.entryPoint = inputEntry.value.trim();
      manifest.main = manifest.entryPoint;
      notifyChange();
    });

    const inputDesc = container.querySelector('#inputManifestDesc');
    inputDesc?.addEventListener('input', () => {
      manifest.description = inputDesc.value;
      notifyChange();
    });

    const inputAuthor = container.querySelector('#inputManifestAuthor');
    inputAuthor?.addEventListener('input', () => {
      manifest.author = inputAuthor.value;
      notifyChange();
    });

    const inputLicense = container.querySelector('#inputManifestLicense');
    inputLicense?.addEventListener('input', () => {
      manifest.license = inputLicense.value;
      notifyChange();
    });

    // Build inputs
    const inputOutputDir = container.querySelector('#inputManifestOutputDir');
    inputOutputDir?.addEventListener('input', () => {
      if (!manifest.build) manifest.build = {};
      manifest.build.outputDir = inputOutputDir.value.trim();
      notifyChange();
    });


    const checkMinify = container.querySelector('#checkManifestMinify');
    checkMinify?.addEventListener('change', () => {
      if (!manifest.build) manifest.build = {};
      manifest.build.minify = checkMinify.checked;
      notifyChange();
    });

    const checkClean = container.querySelector('#checkManifestClean');
    checkClean?.addEventListener('change', () => {
      if (!manifest.build) manifest.build = {};
      manifest.build.clean = checkClean.checked;
      notifyChange();
    });

    // Permissions
    const permFs = container.querySelector('#permFilesystem');
    permFs?.addEventListener('change', () => {
      if (!manifest.permissions) manifest.permissions = {};
      manifest.permissions.filesystem = permFs.checked;
      notifyChange();
    });

    const permNet = container.querySelector('#permNetwork');
    permNet?.addEventListener('change', () => {
      if (!manifest.permissions) manifest.permissions = {};
      manifest.permissions.network = permNet.checked;
      notifyChange();
    });

    const permClip = container.querySelector('#permClipboard');
    permClip?.addEventListener('change', () => {
      if (!manifest.permissions) manifest.permissions = {};
      manifest.permissions.clipboard = permClip.checked;
      notifyChange();
    });

    const permProc = container.querySelector('#permProcess');
    permProc?.addEventListener('change', () => {
      if (!manifest.permissions) manifest.permissions = {};
      manifest.permissions.process = permProc.checked;
      notifyChange();
    });

    // Add dependency
    container.querySelector('#btnAddDependency')?.addEventListener('click', () => {
      const nameInput = container.querySelector('#inputNewDepName');
      const verInput = container.querySelector('#inputNewDepVersion');
      const depName = (nameInput?.value || '').trim();
      const depVer = (verInput?.value || '').trim() || '^1.0.0';
      if (!depName) return;
      if (!manifest.dependencies) manifest.dependencies = {};
      manifest.dependencies[depName] = depVer;
      if (nameInput) nameInput.value = '';
      if (verInput) verInput.value = '';
      render();
      notifyChange();
    });

    // Remove dependency
    container.querySelectorAll('[data-remove-dep]').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const depName = btn.getAttribute('data-remove-dep');
        if (depName && manifest.dependencies) {
          delete manifest.dependencies[depName];
          render();
          notifyChange();
        }
      });
    });

    // Add asset
    container.querySelector('#btnAddAsset')?.addEventListener('click', () => {
      const input = container.querySelector('#inputNewAsset');
      const val = (input?.value || '').trim();
      if (!val) return;
      if (!Array.isArray(manifest.assets)) manifest.assets = [];
      manifest.assets.push(val);
      if (input) input.value = '';
      render();
      notifyChange();
    });

    // Remove asset
    container.querySelectorAll('[data-remove-asset]').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const idx = Number(btn.getAttribute('data-remove-asset'));
        if (!isNaN(idx) && Array.isArray(manifest.assets)) {
          manifest.assets.splice(idx, 1);
          render();
          notifyChange();
        }
      });
    });

    // Add script
    container.querySelector('#btnAddScript')?.addEventListener('click', () => {
      const nameInput = container.querySelector('#inputNewScriptName');
      const cmdInput = container.querySelector('#inputNewScriptCommand');
      const sName = (nameInput?.value || '').trim();
      const sCmd = (cmdInput?.value || '').trim();
      if (!sName || !sCmd) return;
      if (!manifest.scripts) manifest.scripts = {};
      manifest.scripts[sName] = sCmd;
      if (nameInput) nameInput.value = '';
      if (cmdInput) cmdInput.value = '';
      render();
      notifyChange();
    });

    // Remove script
    container.querySelectorAll('[data-remove-script]').forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.stopPropagation();
        const sName = btn.getAttribute('data-remove-script');
        if (sName && manifest.scripts) {
          delete manifest.scripts[sName];
          render();
          notifyChange();
        }
      });
    });
  }

  render();
}
