// launch-profiles.js - The Launch Profiles editor (Run ▾ > Edit Launch Profiles…).
//
// A profile says how to start the program: the project or one .ot file, the
// arguments it receives, its working folder, extra environment variables and
// a timeout. Profiles are saved to <project>/.otter-studio/launch.json by
// the server (server/launch.mjs), which validates them again and never runs
// anything through a shell.
//
// Arguments are edited one per line, so an argument containing spaces or
// quotes needs no quoting rules at all: each line is exactly one argument.
// Environment variables are edited as NAME=value lines.

/** "a\n\nb c" -> ["a", "b c"]; blank lines are ignored. */
export function parseArgLines(text) {
  return String(text || '').split(/\r?\n/).filter(line => line.trim() !== '');
}

/**
 * "A=1\nB = two" -> { env: { A: '1', B: 'two' }, errors: [] }.
 * Only the first `=` splits, so values may contain `=`.
 */
export function parseEnvLines(text) {
  const env = {};
  const errors = [];
  String(text || '').split(/\r?\n/).forEach((line, i) => {
    if (!line.trim() || line.trim().startsWith('#')) return;
    const eq = line.indexOf('=');
    if (eq <= 0) { errors.push(`Line ${i + 1}: write NAME=value.`); return; }
    const name = line.slice(0, eq).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) { errors.push(`Line ${i + 1}: "${name}" is not a valid variable name.`); return; }
    env[name] = line.slice(eq + 1).trim();
  });
  return { env, errors };
}

export function formatEnvLines(env) {
  return Object.entries(env || {}).map(([k, v]) => `${k}=${v}`).join('\n');
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
}

/**
 * Open the editor for `ide`'s current project. Resolves when it closes.
 * The IDE provides: currentProjectFolder, launchConfig, launchConfigRevision,
 * and loadLaunchConfig() to refresh after saving.
 */
export function openLaunchProfilesEditor(ide) {
  const folder = ide.currentProjectFolder;
  if (!folder) {
    alert('Open a project folder first. Launch profiles are saved inside the project.');
    return;
  }

  // Work on a copy; nothing changes until Save succeeds.
  const draft = JSON.parse(JSON.stringify(ide.launchConfig || { version: 1, startup: null, profiles: [] }));
  let selected = 0;

  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop';
  backdrop.style.display = 'flex';
  backdrop.innerHTML = `
    <div class="modal-dialog launch-profiles-dialog" role="dialog" aria-modal="true" aria-labelledby="launchProfilesTitle" style="max-width: 760px; width: 94vw;">
      <div class="modal-header">
        <h2 class="modal-title" id="launchProfilesTitle">Launch Profiles</h2>
        <button class="modal-close-btn" data-action="close" title="Close (Esc)" aria-label="Close">✕</button>
      </div>
      <div class="modal-body" style="display: grid; grid-template-columns: 200px 1fr; gap: 16px; min-height: 320px;">
        <div>
          <ul class="launch-profile-list" role="listbox" aria-label="Profiles" style="list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 4px;"></ul>
          <div style="display: flex; gap: 6px; margin-top: 8px;">
            <button class="btn-modal-link" data-action="add">+ Add</button>
            <button class="btn-modal-link" data-action="duplicate">Duplicate</button>
            <button class="btn-modal-link" data-action="remove">Remove</button>
          </div>
        </div>
        <form class="launch-profile-form" style="display: flex; flex-direction: column; gap: 10px;" autocomplete="off"></form>
      </div>
      <div class="launch-profile-errors" role="alert" style="color: #ef4444; font-size: 12px; padding: 0 20px;"></div>
      <div class="modal-footer">
        <div class="modal-footer-left" style="font-size: 12px; opacity: .75;">Saved to ${escapeHtml(folder)}/.otter-studio/launch.json</div>
        <div class="modal-footer-right">
          <button class="btn-modal-cancel" data-action="close">Cancel</button>
          <button class="btn-modal-primary" data-action="save">Save Profiles</button>
        </div>
      </div>
    </div>`;
  document.body.appendChild(backdrop);

  const list = backdrop.querySelector('.launch-profile-list');
  const form = backdrop.querySelector('.launch-profile-form');
  const errorsEl = backdrop.querySelector('.launch-profile-errors');

  const field = (label, id, inner, hint = '') => `
    <label class="config-field" for="${id}" style="display: flex; flex-direction: column; gap: 4px;">
      <span class="config-label">${label}</span>
      ${inner}
      ${hint ? `<span style="font-size: 11px; opacity: .7;">${hint}</span>` : ''}
    </label>`;

  function renderList() {
    list.innerHTML = draft.profiles.map((p, i) => `
      <li><button type="button" role="option" aria-selected="${i === selected}" data-index="${i}"
        class="launch-profile-item${i === selected ? ' is-active' : ''}" style="width: 100%; text-align: left;">
        <span class="profile-title">${escapeHtml(p.name || '(unnamed)')}</span>
        ${draft.startup === p.name ? '<span class="profile-shortcut">startup</span>' : ''}
      </button></li>`).join('');
  }

  function renderForm() {
    const p = draft.profiles[selected];
    if (!p) { form.innerHTML = '<p style="opacity: .7;">No profiles. Add one to start.</p>'; return; }
    form.innerHTML = `
      ${field('Name', 'lpName', `<input id="lpName" class="config-input" value="${escapeHtml(p.name)}" />`)}
      ${field('Runs', 'lpKind', `<select id="lpKind" class="config-select">
          <option value="project"${p.kind === 'project' ? ' selected' : ''}>The project (otter run &lt;project folder&gt;)</option>
          <option value="file"${p.kind === 'file' ? ' selected' : ''}>One .ot file</option>
        </select>`)}
      ${p.kind === 'file' ? field('Program', 'lpProgram', `<input id="lpProgram" class="config-input" value="${escapeHtml(p.program || '')}" />`,
        'A path inside the project, or ${currentFile} for the file open in the editor.') : ''}
      ${field('Arguments (one per line)', 'lpArgs', `<textarea id="lpArgs" class="config-input" rows="3" style="font-family: var(--font-code);">${escapeHtml((p.args || []).join('\n'))}</textarea>`,
        'Each line is passed as exactly one argument; no quoting needed.')}
      ${field('Working folder', 'lpCwd', `<input id="lpCwd" class="config-input" value="${escapeHtml(p.cwd || '.')}" />`,
        'Relative to the project folder. ${fileDir} is the current file\'s folder.')}
      ${field('Environment variables (NAME=value per line)', 'lpEnv', `<textarea id="lpEnv" class="config-input" rows="3" style="font-family: var(--font-code);">${escapeHtml(formatEnvLines(p.env))}</textarea>`)}
      ${field('Timeout (seconds)', 'lpTimeout', `<input id="lpTimeout" type="number" min="1" max="3600" class="config-input" value="${escapeHtml(p.timeoutSeconds ?? 30)}" />`)}
      <label style="display: flex; gap: 8px; align-items: center; font-size: 13px;">
        <input id="lpStartup" type="checkbox"${draft.startup === p.name ? ' checked' : ''} />
        Startup profile (what the Run button uses in this project)
      </label>`;
  }

  // Copy the form back into the draft; returns the problems found.
  function readForm() {
    const p = draft.profiles[selected];
    if (!p || !form.querySelector('#lpName')) return [];
    const oldName = p.name;
    p.name = form.querySelector('#lpName').value.trim();
    p.kind = form.querySelector('#lpKind').value;
    if (p.kind === 'file') p.program = (form.querySelector('#lpProgram')?.value ?? p.program ?? '${currentFile}').trim() || '${currentFile}';
    else delete p.program;
    p.args = parseArgLines(form.querySelector('#lpArgs').value);
    p.cwd = form.querySelector('#lpCwd').value.trim() || '.';
    const { env, errors } = parseEnvLines(form.querySelector('#lpEnv').value);
    p.env = env;
    p.timeoutSeconds = Number(form.querySelector('#lpTimeout').value);
    if (form.querySelector('#lpStartup').checked) draft.startup = p.name;
    else if (draft.startup === oldName) draft.startup = null;
    return errors.map(e => `${p.name || 'Profile'}: ${e}`);
  }

  function select(index) {
    const problems = readForm();
    errorsEl.textContent = problems.join(' ');
    selected = Math.max(0, Math.min(index, draft.profiles.length - 1));
    renderList();
    renderForm();
  }

  function uniqueName(base) {
    const names = new Set(draft.profiles.map(p => p.name.toLowerCase()));
    let name = base;
    for (let n = 2; names.has(name.toLowerCase()); n++) name = `${base} ${n}`;
    return name;
  }

  function close() {
    backdrop.remove();
    document.removeEventListener('keydown', onKey, true);
  }

  async function save() {
    const problems = readForm();
    if (problems.length) { errorsEl.textContent = problems.join(' '); return; }
    const res = await fetch('/api/launch-config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ folder, config: draft, expectedRevision: ide.launchConfigRevision || undefined })
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      errorsEl.textContent = (data.errors || [data.error || `Could not save (${res.status}).`]).join(' ');
      return;
    }
    await ide.loadLaunchConfig();
    close();
  }

  function onKey(e) {
    if (e.key === 'Escape') { e.preventDefault(); close(); }
  }
  document.addEventListener('keydown', onKey, true);

  backdrop.addEventListener('click', e => {
    const action = e.target.closest('[data-action]')?.dataset.action;
    const item = e.target.closest('[data-index]');
    if (item) { select(Number(item.dataset.index)); return; }
    if (e.target === backdrop || action === 'close') { close(); return; }
    if (action === 'add') {
      readForm();
      draft.profiles.push({ name: uniqueName('New Profile'), kind: 'project', args: [], cwd: '.', env: {}, timeoutSeconds: 30 });
      select(draft.profiles.length - 1);
    } else if (action === 'duplicate' && draft.profiles[selected]) {
      readForm();
      const copy = JSON.parse(JSON.stringify(draft.profiles[selected]));
      copy.name = uniqueName(`${copy.name} copy`);
      draft.profiles.splice(selected + 1, 0, copy);
      select(selected + 1);
    } else if (action === 'remove' && draft.profiles[selected]) {
      if (draft.startup === draft.profiles[selected].name) draft.startup = null;
      draft.profiles.splice(selected, 1);
      selected = Math.max(0, selected - 1);
      renderList();
      renderForm();
    } else if (action === 'save') {
      save();
    }
  });
  // Re-render when switching kind, so the Program field appears/disappears.
  form.addEventListener('change', e => {
    if (e.target.id === 'lpKind') { readForm(); renderForm(); }
  });

  renderList();
  renderForm();
  form.querySelector('#lpName')?.focus();
}
