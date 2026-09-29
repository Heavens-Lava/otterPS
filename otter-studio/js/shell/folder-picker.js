// folder-picker.js - File > Open Folder: browse the workspace's folders
// instead of typing a path. Otter projects (a project.json inside) are
// marked and listed first. Click selects, double-click (or Enter) goes in,
// Backspace / Up goes up, typing filters. Resolves to the chosen folder's
// workspace path, or null when cancelled. Server: GET /api/fs/dirs.

const FOLDER = 'M2 5.5v11h16V7.5h-7.5L8.8 5.5z';
const PROJECT = 'M10 3.5 3 7v6.5l7 3.5 7-3.5V7zM3 7l7 3.5L17 7M10 10.5V17';
const UP = 'M10 16V4M5 9l5-5 5 5';
const svg = (d, cls) => `<svg class="${cls}" viewBox="0 0 20 20" aria-hidden="true"><path d="${d}" /></svg>`;
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

async function fetchDirs(path) {
  const res = await fetch(`/api/fs/dirs?path=${encodeURIComponent(path)}`);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

export function pickFolder({ title = 'Open Folder', start = '.', okLabel = 'Open' } = {}) {
  return new Promise((resolve) => {
    let current = '.';
    let entries = [];
    let selected = null;
    let filter = '';

    const backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop folder-picker-backdrop';
    backdrop.style.display = 'flex';
    backdrop.innerHTML = `
      <div class="modal-dialog folder-picker" role="dialog" aria-modal="true" aria-labelledby="folderPickerTitle">
        <div class="modal-header">
          <div class="modal-title-wrap">
            <h2 class="modal-title" id="folderPickerTitle"></h2>
            <p class="modal-subtitle">Choose a project folder. Folders with a project.json are Otter projects.</p>
          </div>
          <button type="button" class="modal-close-btn" data-fp-cancel title="Cancel (Esc)">✕</button>
        </div>
        <div class="fp-bar">
          <button type="button" class="fp-up" title="Up one folder (Backspace)" aria-label="Up one folder">${svg(UP, 'fp-up-icon')}</button>
          <nav class="fp-crumbs" aria-label="Folder path"></nav>
          <input type="search" class="fp-filter" placeholder="Filter" aria-label="Filter folders" />
        </div>
        <div class="fp-list" role="listbox" aria-label="Folders" tabindex="0"></div>
        <div class="modal-footer">
          <div class="modal-footer-left fp-choice"></div>
          <div class="modal-footer-right">
            <button type="button" class="btn-modal-cancel" data-fp-cancel>Cancel</button>
            <button type="button" class="btn-modal-primary fp-open"></button>
          </div>
        </div>
      </div>`;
    backdrop.querySelector('#folderPickerTitle').textContent = title;
    backdrop.querySelector('.fp-open').textContent = okLabel;
    document.body.appendChild(backdrop);
    const list = backdrop.querySelector('.fp-list');
    const crumbs = backdrop.querySelector('.fp-crumbs');
    const filterInput = backdrop.querySelector('.fp-filter');
    const choice = backdrop.querySelector('.fp-choice');
    const upBtn = backdrop.querySelector('.fp-up');

    const chosen = () => selected || (current === '.' ? null : current);

    function renderChoice() {
      const c = chosen();
      choice.textContent = c ? `Opens ${c}` : 'Select a folder';
      backdrop.querySelector('.fp-open').disabled = !c;
    }

    function renderList() {
      const shown = entries.filter(e => !filter || e.name.toLowerCase().includes(filter));
      if (!shown.length) {
        list.innerHTML = `<div class="fp-empty">${filter ? 'No folder matches.' : 'No folders here. Open this one, or go up.'}</div>`;
      } else {
        list.innerHTML = shown.map(e => `
          <div class="fp-item${e.path === selected ? ' is-selected' : ''}" role="option" aria-selected="${e.path === selected}" data-path="${esc(e.path)}" tabindex="-1">
            ${svg(e.isProject ? PROJECT : FOLDER, e.isProject ? 'fp-icon is-project' : 'fp-icon')}
            <span class="fp-name">${esc(e.name)}</span>
            ${e.isProject ? '<span class="fp-badge">Otter project</span>' : (e.hasOtter ? '<span class="fp-badge is-muted">.ot files</span>' : '')}
            ${e.hasFolders ? '<span class="fp-chevron">›</span>' : ''}
          </div>`).join('');
      }
      renderChoice();
    }

    function renderCrumbs() {
      const parts = current === '.' ? [] : current.split('/');
      crumbs.innerHTML = ['<button type="button" data-crumb=".">Workspace</button>',
        ...parts.map((p, i) => `<span class="fp-sep">/</span><button type="button" data-crumb="${esc(parts.slice(0, i + 1).join('/'))}">${esc(p)}</button>`)].join('');
      upBtn.disabled = current === '.';
    }

    async function go(path) {
      try {
        const data = await fetchDirs(path);
        current = data.path || '.';
        entries = data.dirs || [];
        selected = null;
        filter = '';
        filterInput.value = '';
        renderCrumbs();
        renderList();
        list.focus();
      } catch (err) {
        list.innerHTML = `<div class="fp-empty is-error">${esc(err.message)}</div>`;
      }
    }

    const parentOf = (p) => (p.includes('/') ? p.split('/').slice(0, -1).join('/') : '.');

    function finish(result) {
      backdrop.remove();
      document.removeEventListener('keydown', onKey, true);
      resolve(result);
    }

    function moveSelection(delta) {
      const items = [...list.querySelectorAll('.fp-item')];
      if (!items.length) return;
      const at = items.findIndex(i => i.dataset.path === selected);
      const next = items[Math.max(0, Math.min(items.length - 1, at + delta))];
      selected = next.dataset.path;
      renderList();
      list.querySelector('.is-selected')?.scrollIntoView({ block: 'nearest' });
    }

    const onKey = (e) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); finish(null); return; }
      if (e.target === filterInput) {
        if (e.key === 'ArrowDown') { e.preventDefault(); list.focus(); moveSelection(1); }
        return;
      }
      if (e.key === 'ArrowDown') { e.preventDefault(); moveSelection(1); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); moveSelection(-1); }
      else if (e.key === 'Enter') {
        e.preventDefault();
        if (e.ctrlKey && chosen()) finish(chosen());
        else if (selected) go(selected);
        else if (chosen()) finish(chosen());
      } else if (e.key === 'Backspace' && current !== '.') { e.preventDefault(); go(parentOf(current)); }
    };

    // Selection changes classes in place: rebuilding the list between the two
    // clicks of a double-click would stop the browser firing dblclick.
    list.addEventListener('click', (e) => {
      const item = e.target.closest('.fp-item');
      if (!item) return;
      selected = item.dataset.path;
      list.querySelectorAll('.fp-item').forEach(el => {
        const on = el === item;
        el.classList.toggle('is-selected', on);
        el.setAttribute('aria-selected', String(on));
      });
      renderChoice();
    });
    list.addEventListener('dblclick', (e) => {
      const item = e.target.closest('.fp-item');
      if (!item) return;
      const entry = entries.find(x => x.path === item.dataset.path);
      // A project opens; a plain folder is entered.
      if (entry?.isProject && !entry.hasFolders) finish(entry.path);
      else go(item.dataset.path);
    });
    crumbs.addEventListener('click', (e) => {
      const b = e.target.closest('[data-crumb]');
      if (b) go(b.dataset.crumb);
    });
    upBtn.addEventListener('click', () => go(parentOf(current)));
    filterInput.addEventListener('input', () => { filter = filterInput.value.trim().toLowerCase(); renderList(); });
    backdrop.querySelector('.fp-open').addEventListener('click', () => { if (chosen()) finish(chosen()); });
    backdrop.querySelectorAll('[data-fp-cancel]').forEach(b => b.addEventListener('click', () => finish(null)));
    backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop) finish(null); });
    document.addEventListener('keydown', onKey, true);
    go(start || '.').catch(() => go('.'));
  });
}
