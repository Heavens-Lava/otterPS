// shortcuts-dialog.js - Keyboard Shortcuts, generated from the command
// registry so it can never drift from what the keys actually do.

import { formatShortcut } from './commands.js';

export function mountShortcutsDialog(registry) {
  let backdrop = null;

  function ensure() {
    if (backdrop) return backdrop;
    backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop shortcuts-backdrop';
    backdrop.id = 'shortcutsDialog';
    backdrop.style.display = 'none';
    backdrop.innerHTML = `
      <div class="modal-dialog shortcuts-dialog" role="dialog" aria-modal="true" aria-labelledby="shortcutsTitle">
        <div class="modal-header">
          <div class="modal-title-wrap">
            <h2 class="modal-title" id="shortcutsTitle">Keyboard Shortcuts</h2>
            <p class="modal-subtitle">Every command is also in the palette: press F1 or type &gt; in the search box.</p>
          </div>
          <button class="modal-close-btn" id="btnShortcutsClose" title="Close (Esc)">✕</button>
        </div>
        <div class="modal-body shortcuts-body">
          <input class="config-input shortcuts-filter" id="shortcutsFilter" placeholder="Filter commands..." spellcheck="false" />
          <div id="shortcutsList"></div>
        </div>
        <div class="modal-footer">
          <div class="modal-footer-left"></div>
          <div class="modal-footer-right"><button class="btn-modal-primary" id="btnShortcutsDone">Done</button></div>
        </div>
      </div>`;
    document.body.appendChild(backdrop);
    backdrop.querySelector('#btnShortcutsClose').addEventListener('click', close);
    backdrop.querySelector('#btnShortcutsDone').addEventListener('click', close);
    backdrop.querySelector('#shortcutsFilter').addEventListener('input', (e) => render(e.target.value));
    backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });
    return backdrop;
  }

  function render(filter = '') {
    const list = backdrop.querySelector('#shortcutsList');
    const term = filter.trim().toLowerCase();
    const commands = registry.list({ includeUnavailable: true })
      .filter(c => !term || `${c.category} ${c.title} ${c.shortcut}`.toLowerCase().includes(term));
    const categories = [...new Set(commands.map(c => c.category))];
    if (commands.length === 0) {
      list.innerHTML = '<div class="shortcuts-empty">No commands match.</div>';
      return;
    }
    list.innerHTML = categories.map(category => `
      <section class="shortcuts-section">
        <h3 class="shortcuts-category">${escapeHtml(category)}</h3>
        <table class="shortcuts-table">
          ${commands.filter(c => c.category === category).map(c => `
            <tr data-command="${escapeHtml(c.id)}">
              <td class="shortcuts-title">${escapeHtml(c.title)}</td>
              <td class="shortcuts-keys">${c.shortcut ? formatShortcut(c.shortcut).split(' ').map(chord => `<kbd>${escapeHtml(chord)}</kbd>`).join(' ') : '<span class="shortcuts-none">—</span>'}</td>
            </tr>`).join('')}
        </table>
      </section>`).join('');
    list.querySelectorAll('tr[data-command]').forEach(row => row.addEventListener('dblclick', () => {
      close();
      registry.run(row.getAttribute('data-command'));
    }));
  }

  function open() {
    ensure();
    render('');
    backdrop.style.display = 'flex';
    setTimeout(() => backdrop.querySelector('#shortcutsFilter')?.focus(), 30);
  }

  function close() {
    if (backdrop) backdrop.style.display = 'none';
  }

  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && backdrop && backdrop.style.display !== 'none') close();
  });

  return { open, close };
}

function escapeHtml(str) {
  return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
