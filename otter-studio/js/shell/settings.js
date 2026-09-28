// settings.js - Studio settings: one persisted object with defaults, a tiny
// API (get / set / subscribe), and the Settings dialog (File -> Settings,
// Ctrl+,). Settings are per browser profile, in localStorage.

const STORAGE_KEY = 'otter-studio-settings';

export const DEFAULT_SETTINGS = {
  editor: {
    fontSize: 13,              // 12-15; the line height stays 22px so overlays keep aligning
    autoClosePairs: true,      // "" () []
    autoCloseBlocks: true,     // Enter after `if x` writes the closing period
    indentGuides: true,
    renderWhitespace: false     // a dot for every space
  },
  files: {
    formatOnSave: false,       // run the Otter formatter when saving .ot files
    trimTrailingWhitespace: true,
    insertFinalNewline: true
  },
  workbench: {
    showWelcomeOnStart: true
  }
};

// The dialog is generated from this description, so a new setting is one line.
const FIELDS = [
  { section: 'Editor', path: 'editor.fontSize', label: 'Font size', type: 'select', options: [[12, '12 px'], [13, '13 px'], [14, '14 px'], [15, '15 px']], hint: 'Code, gutter and terminal text' },
  { section: 'Editor', path: 'editor.autoClosePairs', label: 'Auto-close quotes and brackets', type: 'checkbox', hint: 'Typing " ( or [ inserts the closing character' },
  { section: 'Editor', path: 'editor.autoCloseBlocks', label: 'Close blocks with a period', type: 'checkbox', hint: 'Enter after "if x is 1" writes the body line and the closing "."' },
  { section: 'Editor', path: 'editor.indentGuides', label: 'Indent guides', type: 'checkbox', hint: 'A faint line for each indentation level' },
  { section: 'Editor', path: 'editor.renderWhitespace', label: 'Show whitespace', type: 'checkbox', hint: 'A faint dot for every space' },
  { section: 'Files', path: 'files.formatOnSave', label: 'Format on save', type: 'checkbox', hint: 'Re-indent .ot files with the Otter formatter when saving' },
  { section: 'Files', path: 'files.trimTrailingWhitespace', label: 'Trim trailing whitespace', type: 'checkbox', hint: 'Remove spaces at the end of lines when saving' },
  { section: 'Files', path: 'files.insertFinalNewline', label: 'End files with a newline', type: 'checkbox' },
  { section: 'Workbench', path: 'workbench.showWelcomeOnStart', label: 'Show the Welcome page on a fresh start', type: 'checkbox' }
];

function deepMerge(base, extra) {
  const out = { ...base };
  for (const [key, value] of Object.entries(extra || {})) {
    out[key] = value && typeof value === 'object' && !Array.isArray(value) ? deepMerge(base[key] || {}, value) : value;
  }
  return out;
}

function getPath(obj, path) {
  return path.split('.').reduce((o, k) => (o === undefined || o === null ? undefined : o[k]), obj);
}

function setPath(obj, path, value) {
  const keys = path.split('.');
  let cursor = obj;
  for (const key of keys.slice(0, -1)) {
    if (!cursor[key] || typeof cursor[key] !== 'object') cursor[key] = {};
    cursor = cursor[key];
  }
  cursor[keys[keys.length - 1]] = value;
}

const clone = (value) => JSON.parse(JSON.stringify(value));

export function createSettings(storage = safeStorage()) {
  // Always work on copies: the defaults object must never be written to.
  let data = clone(DEFAULT_SETTINGS);
  try {
    const raw = storage.getItem(STORAGE_KEY);
    if (raw) data = deepMerge(clone(DEFAULT_SETTINGS), JSON.parse(raw));
  } catch { /* unreadable settings: start from the defaults */ }
  const listeners = new Set();

  const api = {
    get(path) { return getPath(data, path); },
    set(path, value) {
      if (getPath(data, path) === value) return;
      data = clone(data);
      setPath(data, path, value);
      try { storage.setItem(STORAGE_KEY, JSON.stringify(data)); } catch { /* storage unavailable */ }
      for (const listener of listeners) listener(path, value);
    },
    reset() {
      data = clone(DEFAULT_SETTINGS);
      try { storage.removeItem(STORAGE_KEY); } catch { /* storage unavailable */ }
      for (const listener of listeners) listener('*', null);
    },
    subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener); },
    snapshot() { return JSON.parse(JSON.stringify(data)); }
  };
  return api;
}

function safeStorage() {
  try {
    if (typeof localStorage !== 'undefined') return localStorage;
  } catch { /* sandboxed */ }
  const memory = new Map();
  return { getItem: (k) => (memory.has(k) ? memory.get(k) : null), setItem: (k, v) => memory.set(k, v), removeItem: (k) => memory.delete(k) };
}

// Apply settings that are pure presentation (font size, guides) to the page.
export function applySettingsToDocument(settings) {
  const root = document.documentElement;
  root.style.setProperty('--editor-font-size', `${settings.get('editor.fontSize')}px`);
  document.body.classList.toggle('editor-indent-guides', Boolean(settings.get('editor.indentGuides')));
}

export function mountSettingsDialog(settings) {
  let backdrop = null;

  function ensure() {
    if (backdrop) return backdrop;
    backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop settings-backdrop';
    backdrop.id = 'settingsDialog';
    backdrop.style.display = 'none';
    backdrop.innerHTML = `
      <div class="modal-dialog settings-dialog" role="dialog" aria-modal="true" aria-labelledby="settingsTitle">
        <div class="modal-header">
          <div class="modal-title-wrap">
            <h2 class="modal-title" id="settingsTitle">Settings</h2>
            <p class="modal-subtitle">Saved in this browser. Changes apply immediately.</p>
          </div>
          <button class="modal-close-btn" id="btnSettingsClose" title="Close (Esc)">✕</button>
        </div>
        <div class="modal-body settings-body" id="settingsBody"></div>
        <div class="modal-footer">
          <div class="modal-footer-left"><button class="btn-modal-link" id="btnSettingsReset">Restore defaults</button></div>
          <div class="modal-footer-right"><button class="btn-modal-primary" id="btnSettingsDone">Done</button></div>
        </div>
      </div>`;
    document.body.appendChild(backdrop);
    backdrop.querySelector('#btnSettingsClose').addEventListener('click', close);
    backdrop.querySelector('#btnSettingsDone').addEventListener('click', close);
    backdrop.querySelector('#btnSettingsReset').addEventListener('click', () => { settings.reset(); render(); });
    backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });
    return backdrop;
  }

  function render() {
    const body = backdrop.querySelector('#settingsBody');
    const sections = [...new Set(FIELDS.map(f => f.section))];
    body.innerHTML = sections.map(section => `
      <section class="settings-section">
        <h3 class="settings-section-title">${escapeHtml(section)}</h3>
        ${FIELDS.filter(f => f.section === section).map(renderField).join('')}
      </section>`).join('');
    body.querySelectorAll('[data-setting]').forEach(input => {
      input.addEventListener('change', () => {
        const path = input.getAttribute('data-setting');
        const value = input.type === 'checkbox' ? input.checked : (Number.isFinite(Number(input.value)) && input.value !== '' ? Number(input.value) : input.value);
        settings.set(path, value);
      });
    });
  }

  function renderField(field) {
    const value = settings.get(field.path);
    const id = 'setting-' + field.path.replace(/\./g, '-');
    if (field.type === 'checkbox') {
      return `
        <label class="settings-row" for="${id}">
          <input type="checkbox" id="${id}" data-setting="${field.path}" ${value ? 'checked' : ''} />
          <span class="settings-row-text">
            <span class="settings-row-label">${escapeHtml(field.label)}</span>
            ${field.hint ? `<span class="settings-row-hint">${escapeHtml(field.hint)}</span>` : ''}
          </span>
        </label>`;
    }
    return `
      <div class="settings-row is-select">
        <span class="settings-row-text">
          <label class="settings-row-label" for="${id}">${escapeHtml(field.label)}</label>
          ${field.hint ? `<span class="settings-row-hint">${escapeHtml(field.hint)}</span>` : ''}
        </span>
        <select class="config-select settings-select" id="${id}" data-setting="${field.path}">
          ${field.options.map(([v, label]) => `<option value="${escapeHtml(String(v))}" ${String(v) === String(value) ? 'selected' : ''}>${escapeHtml(label)}</option>`).join('')}
        </select>
      </div>`;
  }

  function open() {
    ensure();
    render();
    backdrop.style.display = 'flex';
  }

  function close() {
    if (backdrop) backdrop.style.display = 'none';
  }

  window.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && !e.shiftKey && e.key === ',') {
      e.preventDefault();
      open();
    } else if (e.key === 'Escape' && backdrop && backdrop.style.display !== 'none') {
      close();
    }
  });

  return { open, close };
}

function escapeHtml(str) {
  return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
