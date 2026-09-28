// shortcuts-dialog.js - Keyboard Shortcuts: every command and its key,
// generated from the command registry so it can never drift from what the
// keys actually do - and the keybinding editor.
//
// Click a key (or "Add key") and press the new chord; Esc cancels. Custom
// keys are stored in Settings (`keybindings`) and applied to the registry at
// once. A key used by another command in the same place is flagged. Keys
// the editor itself handles (Ctrl+S, Ctrl+F...) are shown but fixed.

import { formatShortcut } from './commands.js';
import { chordOf, displayChord, isMacPlatform } from './keys.js';

export function mountShortcutsDialog(registry, settings = null) {
  let backdrop = null;
  let recordingId = null;
  let filterText = '';

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
            <p class="modal-subtitle">Click a key to change it. Every command is also in the palette: press F1 or type &gt; in the search box.</p>
          </div>
          <button class="modal-close-btn" id="btnShortcutsClose" title="Close (Esc)">✕</button>
        </div>
        <div class="modal-body shortcuts-body">
          <input class="config-input shortcuts-filter" id="shortcutsFilter" placeholder="Filter by command or key..." spellcheck="false" />
          <div id="shortcutsList"></div>
        </div>
        <div class="modal-footer">
          <div class="modal-footer-left">${settings ? '<button class="btn-modal-link" id="btnShortcutsResetAll">Reset all keys</button>' : ''}</div>
          <div class="modal-footer-right"><button class="btn-modal-primary" id="btnShortcutsDone">Done</button></div>
        </div>
      </div>`;
    document.body.appendChild(backdrop);
    backdrop.querySelector('#btnShortcutsClose').addEventListener('click', close);
    backdrop.querySelector('#btnShortcutsDone').addEventListener('click', close);
    backdrop.querySelector('#btnShortcutsResetAll')?.addEventListener('click', () => save({}));
    backdrop.querySelector('#shortcutsFilter').addEventListener('input', (e) => { filterText = e.target.value; render(); });
    backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });
    backdrop.querySelector('#shortcutsList').addEventListener('click', onListClick);
    return backdrop;
  }

  function customKeys() {
    return { ...(settings?.get('keybindings') || {}) };
  }

  function save(map) {
    settings?.set('keybindings', map);
    registry.setKeybindings(map);
    recordingId = null;
    render();
  }

  // Other commands in the same place (global, or the designer) using a chord.
  function conflictsFor(command) {
    const out = [];
    for (const chord of command.keys) {
      for (const other of registry.commandsForChord(chord, command.scope)) {
        if (other.id !== command.id) out.push(other.title);
      }
    }
    return out;
  }

  function keyCell(c) {
    const rebindable = settings && registry.isRebindable(c);
    if (recordingId === c.id) {
      return '<span class="shortcuts-recording">Press the new keys… (Esc cancels)</span>';
    }
    const keys = c.shortcut
      ? formatShortcut(c.shortcut).split(' ').map(chord => `<kbd>${escapeHtml(chord)}</kbd>`).join(' ')
      : '<span class="shortcuts-none">—</span>';
    if (!rebindable) {
      return `<span class="shortcuts-fixed" title="Handled by the editor itself">${keys}</span>`;
    }
    const conflicts = conflictsFor(c);
    return `
      <button class="shortcuts-key-btn" data-record="${escapeHtml(c.id)}" title="Change the key">${c.shortcut ? keys : '<span class="shortcuts-add">Add key</span>'}</button>
      ${registry.isCustomized(c) ? `<button class="btn-modal-link shortcuts-reset" data-reset-key="${escapeHtml(c.id)}" title="Back to the default key">Reset</button>` : ''}
      ${c.keys.length ? `<button class="btn-modal-link shortcuts-remove" data-remove-key="${escapeHtml(c.id)}" title="Remove this key">Remove</button>` : ''}
      ${conflicts.length ? `<div class="shortcuts-conflict">Also used by: ${escapeHtml(conflicts.join(', '))}</div>` : ''}`;
  }

  function render() {
    if (!backdrop) return;
    const list = backdrop.querySelector('#shortcutsList');
    const term = filterText.trim().toLowerCase();
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
            <tr data-command="${escapeHtml(c.id)}" class="${registry.isCustomized(c) ? 'is-custom' : ''}">
              <td class="shortcuts-title">${escapeHtml(c.title)}</td>
              <td class="shortcuts-keys">${keyCell(c)}</td>
            </tr>`).join('')}
        </table>
      </section>`).join('');
    list.querySelectorAll('tr[data-command] .shortcuts-title').forEach(cell => cell.addEventListener('dblclick', () => {
      close();
      registry.run(cell.closest('tr').getAttribute('data-command'));
    }));
  }

  function onListClick(e) {
    const record = e.target.closest('[data-record]');
    if (record) {
      recordingId = record.getAttribute('data-record');
      render();
      return;
    }
    const reset = e.target.closest('[data-reset-key]');
    if (reset) {
      const map = customKeys();
      delete map[reset.getAttribute('data-reset-key')];
      save(map);
      return;
    }
    const remove = e.target.closest('[data-remove-key]');
    if (remove) {
      const map = customKeys();
      map[remove.getAttribute('data-remove-key')] = '';
      save(map);
    }
  }

  // While recording, the next chord (with at least one non-modifier key)
  // becomes the command's key; Esc cancels. Nothing else sees these keys.
  function onKeyCapture(e) {
    if (!recordingId || !backdrop || backdrop.style.display === 'none') return;
    if (['Control', 'Alt', 'Shift', 'Meta'].includes(e.key)) return;
    e.preventDefault();
    e.stopPropagation();
    if (e.key === 'Escape') {
      recordingId = null;
      render();
      return;
    }
    const chord = chordOf(e, isMacPlatform());
    const map = customKeys();
    const command = registry.get(recordingId);
    // Choosing the default again clears the customization.
    if (command && command.defaultKeys[0] === chord) delete map[recordingId];
    else map[recordingId] = chord;
    save(map);
  }

  function open(filter = '') {
    ensure();
    filterText = filter;
    backdrop.querySelector('#shortcutsFilter').value = filter;
    recordingId = null;
    render();
    backdrop.style.display = 'flex';
    setTimeout(() => backdrop.querySelector('#shortcutsFilter')?.focus(), 30);
  }

  function close() {
    recordingId = null;
    if (backdrop) backdrop.style.display = 'none';
  }

  window.addEventListener('keydown', onKeyCapture, true);
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !recordingId && backdrop && backdrop.style.display !== 'none') close();
  });

  return { open, close, displayChord };
}

function escapeHtml(str) {
  return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
