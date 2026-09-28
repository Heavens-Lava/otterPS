// package-dialog.js - Build -> Desktop App.
//
// A dialog that packages the open project as a Windows desktop application
// through the same `otter package` command the CLI offers, and shows its
// progress step by step. Application metadata (version, description, icon)
// is edited here and saved into the project's manifest before the build, so
// the CLI and Studio always agree on what the app is called.

const STEPS = [
  ['check', 'Check project and settings'],
  ['export', 'Compile Otter source and create the Electron application'],
  ['styles', 'Embed the project stylesheet'],
  ['configure', 'Write the packaging configuration'],
  ['runtime', 'Prepare the Electron runtime'],
  ['portable', 'Build the portable executable'],
  ['installer', 'Build the Windows installer']
];

const ICON_TYPES = /\.(png|ico)$/i;

export function mountPackageDialog({ ide, openNewProjectModal }) {
  let backdrop = null;
  let state = null; // { folder, manifestPath, manifestRevision, manifest }

  function ensureDialog() {
    if (backdrop) return backdrop;
    backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop package-backdrop';
    backdrop.id = 'packageDialog';
    backdrop.style.display = 'none';
    backdrop.innerHTML = `
      <div class="modal-dialog package-dialog" role="dialog" aria-modal="true" aria-labelledby="packageDialogTitle">
        <div class="modal-header">
          <div class="modal-title-wrap">
            <h2 class="modal-title" id="packageDialogTitle">Build Desktop Application</h2>
            <p class="modal-subtitle" id="packageDialogSubtitle">Package this project as a Windows application that runs without Otter installed.</p>
          </div>
          <button class="modal-close-btn" id="btnPackageClose" title="Close (Esc)">✕</button>
        </div>
        <div class="modal-body package-body" id="packageBody"></div>
        <div class="modal-footer">
          <div class="modal-footer-left" id="packageFooterLeft"></div>
          <div class="modal-footer-right">
            <button class="btn-modal-cancel" id="btnPackageCancel">Cancel</button>
            <button class="btn-modal-primary" id="btnPackageBuild">Build</button>
          </div>
        </div>
      </div>
    `;
    document.body.appendChild(backdrop);
    backdrop.querySelector('#btnPackageClose').addEventListener('click', close);
    backdrop.querySelector('#btnPackageCancel').addEventListener('click', close);
    backdrop.querySelector('#btnPackageBuild').addEventListener('click', build);
    backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });
    return backdrop;
  }

  function close() {
    if (backdrop) backdrop.style.display = 'none';
  }

  function isOpen() {
    return backdrop && backdrop.style.display !== 'none';
  }

  // --- Manifest ---------------------------------------------------------------

  async function readManifest(folder) {
    for (const name of ['otter.json', 'project.json']) {
      const res = await fetch(`/api/file?path=${encodeURIComponent(`${folder}/${name}`)}`);
      if (!res.ok) continue;
      const data = await res.json();
      let parsed;
      try { parsed = JSON.parse(data.content); } catch { continue; }
      return { path: `${folder}/${name}`, revision: data.revision, manifest: parsed, raw: data.content };
    }
    return null;
  }

  async function saveManifestChanges(values) {
    const m = state.manifest;
    const changed = (m.version || '') !== values.version || (m.description || '') !== values.description || (m.icon || '') !== values.icon;
    if (!changed) return true;
    const next = { ...m };
    if (values.version) next.version = values.version; else delete next.version;
    if (values.description) next.description = values.description; else delete next.description;
    if (values.icon) next.icon = values.icon; else delete next.icon;
    const res = await fetch('/api/file', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path: state.manifestPath, content: JSON.stringify(next, null, 2) + '\n', expectedRevision: state.manifestRevision, force: true })
    });
    if (!res.ok) throw new Error('The project manifest could not be saved.');
    const data = await res.json();
    state.manifest = next;
    state.manifestRevision = data.revision || state.manifestRevision;
    return true;
  }

  // --- Form -------------------------------------------------------------------

  function projectImages() {
    const files = Array.isArray(ide.workspaceFiles) ? ide.workspaceFiles : [];
    const folder = String(state.folder).replace(/\\/g, '/').replace(/\/$/, '');
    return files
      .map(f => (typeof f === 'string' ? f : (f.path || f.relativePath || '')).replace(/\\/g, '/'))
      .filter(p => ICON_TYPES.test(p))
      .map(p => p.startsWith(folder + '/') ? p.slice(folder.length + 1) : p);
  }

  function renderForm() {
    const m = state.manifest;
    const body = backdrop.querySelector('#packageBody');
    const images = projectImages();
    const currentIcon = m.icon || '';
    const iconOptions = [...new Set([currentIcon, ...images].filter(Boolean))];
    body.innerHTML = `
      <div class="package-grid">
        <label class="config-label" for="pkgName">Application</label>
        <input class="config-input" id="pkgName" value="${escapeAttr(m.name || state.folder)}" readonly title="Change the name in the project manifest" />

        <label class="config-label" for="pkgVersion">Version</label>
        <input class="config-input" id="pkgVersion" value="${escapeAttr(m.version || '1.0.0')}" placeholder="1.0.0" spellcheck="false" />

        <label class="config-label" for="pkgDescription">Description</label>
        <input class="config-input" id="pkgDescription" value="${escapeAttr(m.description || '')}" placeholder="Shown in the installer and in the app's file properties" />

        <label class="config-label" for="pkgOutput">Output</label>
        <input class="config-input" id="pkgOutput" value="${escapeAttr(state.folder.replace(/\\/g, '/') + '/packages')}" spellcheck="false" />

        <span class="config-label">Package</span>
        <div class="package-kinds">
          <label><input type="checkbox" id="pkgKindInstaller" checked /> Windows installer (Setup.exe)</label>
          <label><input type="checkbox" id="pkgKindPortable" checked /> Portable executable</label>
        </div>

        <label class="config-label" for="pkgIcon">Icon</label>
        <div class="package-icon-row">
          <select class="config-select" id="pkgIcon">
            <option value="">Default Electron icon</option>
            ${iconOptions.map(p => `<option value="${escapeAttr(p)}" ${p === currentIcon ? 'selected' : ''}>${escapeHtml(p)}</option>`).join('')}
          </select>
          <span class="package-hint">A .png of at least 256×256, or a .ico, inside the project</span>
        </div>
      </div>
      <div class="package-note">
        The result runs on other Windows PCs without Otter, PowerShell or Node.js installed. It is not code-signed, so Windows SmartScreen shows a warning the first time it runs elsewhere.
      </div>
    `;
    backdrop.querySelector('#btnPackageBuild').hidden = false;
    backdrop.querySelector('#btnPackageBuild').disabled = false;
    backdrop.querySelector('#btnPackageCancel').textContent = 'Cancel';
    backdrop.querySelector('#packageFooterLeft').innerHTML = '';
  }

  function renderNoProject() {
    const body = backdrop.querySelector('#packageBody');
    body.innerHTML = `
      <div class="package-empty">
        <p>Open a project first. A desktop application is built from a project folder with an <code>otter.json</code> (or <code>project.json</code>) manifest.</p>
      </div>`;
    backdrop.querySelector('#btnPackageBuild').hidden = true;
    backdrop.querySelector('#packageFooterLeft').innerHTML = '<button class="btn-modal-link" id="btnPackageNewProject">✨ New Project...</button>';
    backdrop.querySelector('#btnPackageNewProject').addEventListener('click', () => { close(); openNewProjectModal(); });
  }

  // Packaging compiles the project and runs electron-builder, so it follows
  // the same rule as Run and Terminal: not in a workspace you have not trusted.
  function renderRestricted() {
    const body = backdrop.querySelector('#packageBody');
    body.innerHTML = `
      <div class="package-empty">
        <p><strong>Restricted Mode.</strong> This workspace is not trusted yet, so Studio will not build or run code from it. Trust the workspace if you know where it came from.</p>
      </div>`;
    backdrop.querySelector('#btnPackageBuild').hidden = true;
    backdrop.querySelector('#packageFooterLeft').innerHTML = '<button class="btn-modal-link" id="btnPackageTrust">🛡️ Trust Workspace</button>';
    backdrop.querySelector('#btnPackageTrust').addEventListener('click', () => {
      ide.grantWorkspaceTrust?.();
      open();
    });
  }

  function renderConsoleProject(target) {
    const body = backdrop.querySelector('#packageBody');
    body.innerHTML = `<div class="package-empty"><p>This is a <strong>${escapeHtml(target)}</strong> project, which has no window to package. Desktop packaging is for desktop, web and game projects.</p></div>`;
    backdrop.querySelector('#btnPackageBuild').hidden = true;
    backdrop.querySelector('#packageFooterLeft').innerHTML = '';
  }

  // --- Progress ---------------------------------------------------------------

  function renderProgress(kinds) {
    const body = backdrop.querySelector('#packageBody');
    const visible = STEPS.filter(([id]) => (id !== 'portable' || kinds.includes('portable')) && (id !== 'installer' || kinds.includes('installer')));
    body.innerHTML = `
      <div class="package-progress">
        <div class="package-progress-title" id="pkgProgressTitle">Building ${escapeHtml(state.manifest.name || state.folder)}...</div>
        <ul class="package-steps" id="pkgSteps">
          ${visible.map(([id, label]) => `<li class="package-step is-pending" data-step="${id}"><span class="package-step-icon"></span><span class="package-step-label">${escapeHtml(label)}</span></li>`).join('')}
        </ul>
        <div class="package-result" id="pkgResult" hidden></div>
        <details class="package-log-wrap" id="pkgLogWrap"><summary>Output</summary><pre class="package-log" id="pkgLog"></pre></details>
      </div>
    `;
    backdrop.querySelector('#btnPackageBuild').hidden = true;
    backdrop.querySelector('#btnPackageCancel').textContent = 'Close';
    backdrop.querySelector('#packageFooterLeft').innerHTML = '';
  }

  function setStep(id, status, label) {
    const li = backdrop.querySelector(`.package-step[data-step="${id}"]`);
    if (!li) return;
    li.className = `package-step is-${status}`;
    if (label) li.querySelector('.package-step-label').textContent = label;
  }

  function appendLog(text) {
    const log = backdrop.querySelector('#pkgLog');
    if (!log) return;
    log.textContent += text + '\n';
    log.scrollTop = log.scrollHeight;
  }

  function formatSize(bytes) {
    return `${(bytes / 1048576).toFixed(1)} MB`;
  }

  function showResult(done, code, logLines) {
    const result = backdrop.querySelector('#pkgResult');
    const title = backdrop.querySelector('#pkgProgressTitle');
    if (!result) return;
    result.hidden = false;
    if (done && done.status === 'done' && code === 0) {
      title.textContent = done.dryRun ? 'Dry run complete' : 'Build complete';
      const rows = (done.artifacts || []).map(a => `<tr><td>${escapeHtml(a.name)}</td><td class="package-size">${formatSize(a.sizeBytes)}</td></tr>`).join('');
      result.innerHTML = `
        ${rows ? `<table class="package-artifacts">${rows}</table>` : '<p class="package-hint">No files were produced.</p>'}
        <div class="package-result-actions">
          <button class="btn-modal-primary" id="btnPackageOpenFolder">Open Folder</button>
          <span class="package-hint">${escapeHtml(done.outputDir || '')}</span>
        </div>`;
      result.querySelector('#btnPackageOpenFolder').addEventListener('click', () => {
        fetch('/api/reveal', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: done.outputDir }) }).catch(() => {});
      });
      backdrop.querySelector('.package-steps').querySelectorAll('.is-running, .is-pending').forEach(li => { li.className = 'package-step is-done'; });
    } else {
      title.textContent = 'Build failed';
      const detail = (done && done.detail) || logLines.filter(l => /error|failed|Otter:|otter package:/i.test(l)).slice(-6).join('\n') || logLines.slice(-6).join('\n');
      result.innerHTML = `<pre class="package-error">${escapeHtml(detail || 'The build stopped without a message. See the output below.')}</pre>`;
      backdrop.querySelector('.package-steps').querySelectorAll('.is-running').forEach(li => { li.className = 'package-step is-failed'; });
      backdrop.querySelector('#pkgLogWrap').open = true;
    }
  }

  async function build() {
    const values = {
      version: backdrop.querySelector('#pkgVersion').value.trim(),
      description: backdrop.querySelector('#pkgDescription').value.trim(),
      icon: backdrop.querySelector('#pkgIcon').value.trim(),
      output: backdrop.querySelector('#pkgOutput').value.trim()
    };
    const kinds = [];
    if (backdrop.querySelector('#pkgKindInstaller').checked) kinds.push('installer');
    if (backdrop.querySelector('#pkgKindPortable').checked) kinds.push('portable');
    if (kinds.length === 0) {
      backdrop.querySelector('#pkgKindPortable').focus();
      return;
    }
    if (values.version && !/^\d+\.\d+\.\d+/.test(values.version)) {
      backdrop.querySelector('#pkgVersion').focus();
      backdrop.querySelector('#pkgVersion').classList.add('is-invalid');
      return;
    }

    backdrop.querySelector('#btnPackageBuild').disabled = true;
    renderProgress(kinds);
    const logLines = [];
    let done = null;
    let code = null;
    try {
      await saveManifestChanges(values);
      const res = await fetch('/api/package', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder: state.folder, kinds, output: values.output || undefined, target: 'windows' })
      });
      if (!res.ok || !res.body) throw new Error(`The Studio service refused the build (HTTP ${res.status}).`);
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let pending = '';
      for (;;) {
        const { value, done: finished } = await reader.read();
        if (finished) break;
        pending += decoder.decode(value, { stream: true });
        let index;
        while ((index = pending.indexOf('\n')) >= 0) {
          const line = pending.slice(0, index);
          pending = pending.slice(index + 1);
          if (!line.trim()) continue;
          let event;
          try { event = JSON.parse(line); } catch { continue; }
          if (event.type === 'progress') {
            if (event.step === 'done' || event.step === 'failed') done = event;
            else setStep(event.step, event.status, event.label);
          } else if (event.type === 'log') {
            logLines.push(event.text);
            appendLog(event.text);
          } else if (event.type === 'exit') {
            code = event.code;
          }
        }
      }
    } catch (err) {
      logLines.push(String(err.message || err));
      appendLog(String(err.message || err));
      code = code ?? 1;
    }
    showResult(done, code ?? 1, logLines);
    ide.loadProjectTree?.(state.folder); // packages/ and dist/ now exist
  }

  // --- Open ---------------------------------------------------------------------

  async function open() {
    ensureDialog();
    backdrop.style.display = 'flex';
    const body = backdrop.querySelector('#packageBody');
    const folder = ide.currentProjectFolder;
    if (!folder) {
      state = null;
      renderNoProject();
      return;
    }
    if (ide.isTrusted === false) {
      state = null;
      renderRestricted();
      return;
    }
    body.innerHTML = '<div class="package-empty"><p>Reading the project manifest...</p></div>';
    const info = await readManifest(folder);
    if (!info) {
      state = null;
      renderNoProject();
      return;
    }
    state = { folder, manifestPath: info.path, manifestRevision: info.revision, manifest: info.manifest };
    const target = String(info.manifest.target || info.manifest.archetype || 'console').toLowerCase();
    if (['console', 'automation', 'server'].includes(target)) {
      renderConsoleProject(target);
      return;
    }
    renderForm();
    setTimeout(() => backdrop.querySelector('#pkgVersion')?.focus(), 40);
  }

  window.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === 'b') {
      e.preventDefault();
      open();
    } else if (e.key === 'Escape' && isOpen()) {
      close();
    }
  });

  return { open, close };
}

function escapeHtml(str) {
  return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function escapeAttr(str) {
  return escapeHtml(str);
}
