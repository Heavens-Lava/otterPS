// local-history.js - File > Local History: every version Studio saved of a
// file (server/local-history.mjs), newest first. Pick one to compare it with
// the editor; Restore puts its text in the editor as one undo step (the file
// is not written until you save).

import { showDiff } from './diff-view.js';

export function formatWhen(time, now = Date.now()) {
  const s = Math.round((now - time) / 1000);
  if (s < 45) return 'just now';
  const m = Math.round(s / 60);
  if (m < 60) return `${m} minute${m === 1 ? '' : 's'} ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h} hour${h === 1 ? '' : 's'} ago`;
  const d = Math.round(h / 24);
  if (d < 30) return `${d} day${d === 1 ? '' : 's'} ago`;
  return new Date(time).toLocaleDateString();
}

const formatSize = (n) => (n < 1024 ? `${n} B` : `${(n / 1024).toFixed(1)} KB`);
const REASONS = { save: 'Saved', 'before save': 'Before save', 'before delete': 'Before delete' };

async function getJson(url) {
  const res = await fetch(url);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

export async function openLocalHistory(ide, filePath = ide.currentFile) {
  if (!filePath) return false;
  let entries;
  try {
    entries = (await getJson(`/api/history/list?path=${encodeURIComponent(filePath)}`)).entries;
  } catch (err) {
    ide.setProblemsStatus(false, `Local History: ${err.message}`, 'Local History');
    return false;
  }

  document.querySelector('.local-history-backdrop')?.remove();
  const name = filePath.split('/').pop();
  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop local-history-backdrop';
  backdrop.style.display = 'flex';
  backdrop.innerHTML = `
    <div class="modal-dialog local-history" role="dialog" aria-modal="true" aria-labelledby="localHistoryTitle">
      <div class="modal-header">
        <div class="modal-title-wrap">
          <h2 class="modal-title" id="localHistoryTitle"></h2>
          <p class="modal-subtitle">Every version Studio saved, kept outside the project. Pick one to compare it with the editor.</p>
        </div>
        <button type="button" class="modal-close-btn" data-history-close title="Close (Esc)">✕</button>
      </div>
      <div class="modal-body local-history-list" role="listbox" aria-label="Versions"></div>
    </div>`;
  backdrop.querySelector('#localHistoryTitle').textContent = `Local History: ${name}`;
  const list = backdrop.querySelector('.local-history-list');
  if (!entries.length) {
    list.innerHTML = '<div class="local-history-empty">No saved versions yet. A version is kept each time you save this file in Studio.</div>';
  }
  entries.forEach((entry, i) => {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'local-history-row';
    row.setAttribute('role', 'option');
    row.dataset.index = String(i);
    row.title = new Date(entry.time).toLocaleString();
    row.innerHTML = '<span class="local-history-when"></span><span class="local-history-reason"></span><span class="local-history-size"></span>';
    // "just now · 2:14:05 PM": the clock time tells close versions apart.
    const date = new Date(entry.time);
    const clock = Date.now() - entry.time < 86400_000
      ? date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', second: '2-digit' })
      : date.toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
    row.children[0].textContent = `${formatWhen(entry.time)} · ${clock}`;
    row.children[1].textContent = REASONS[entry.reason] || entry.reason;
    row.children[2].textContent = formatSize(entry.size);
    list.appendChild(row);
  });
  document.body.appendChild(backdrop);

  const close = () => {
    backdrop.remove();
    document.removeEventListener('keydown', onKey, true);
  };
  const onKey = (e) => {
    if (document.querySelector('.diff-view-backdrop')) return; // the diff has the keys
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); return; }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      const rows = [...list.querySelectorAll('.local-history-row')];
      const at = rows.indexOf(document.activeElement);
      const next = rows[Math.max(0, Math.min(rows.length - 1, at + (e.key === 'ArrowDown' ? 1 : -1)))];
      if (next) { e.preventDefault(); next.focus(); }
    }
  };

  async function compare(entry) {
    let content;
    try {
      content = (await getJson(`/api/history/entry?path=${encodeURIComponent(filePath)}&id=${entry.id}`)).content;
    } catch (err) {
      ide.setProblemsStatus(false, `Local History: ${err.message}`, 'Local History');
      return;
    }
    // Compare against what is in the editor for this file (the open tab, or
    // the file on disk when it is not open).
    const tab = ide.openTabs.find(t => t.path === filePath);
    const current = tab ? (tab.path === ide.currentFile ? ide.currentCode : tab.content) : null;
    const right = current ?? (await getJson(`/api/file?path=${encodeURIComponent(filePath)}`).catch(() => ({ content: '' }))).content;
    const when = `${formatWhen(entry.time)}, ${new Date(entry.time).toLocaleString()}`;
    // One dialog at a time: the list steps aside and comes back (on the
    // same row) when the comparison closes without a restore.
    const row = list.querySelector(`[data-index="${entries.indexOf(entry)}"]`);
    backdrop.style.display = 'none';
    showDiff({
      onClose: () => {
        if (!backdrop.isConnected) return;
        backdrop.style.display = 'flex';
        row?.focus();
      },
      title: `${name}: ${formatWhen(entry.time)} ↔ ${tab ? 'editor' : 'on disk'}`,
      leftLabel: `${name} (${when})`,
      rightLabel: `${name} (${tab ? 'editor' : 'on disk'})`,
      left: content,
      right,
      actions: [{
        label: 'Restore',
        primary: true,
        title: 'Put this version in the editor (Ctrl+Z undoes it; save to keep it)',
        run: async () => {
          if (ide.currentFile !== filePath) await ide.loadFile(filePath);
          ide.replaceDocumentText(content.replace(/\r\n/g, '\n'));
          ide.setProblemsStatus(true, `Restored ${name} from ${when}. Save to keep it.`, 'Local History');
          close();
          return true;
        }
      }]
    });
  }

  list.addEventListener('click', (e) => {
    const row = e.target.closest('.local-history-row');
    if (row) compare(entries[Number(row.dataset.index)]);
  });
  backdrop.querySelector('[data-history-close]').addEventListener('click', close);
  backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop) close(); });
  document.addEventListener('keydown', onKey, true);
  setTimeout(() => list.querySelector('.local-history-row')?.focus(), 20);
  return true;
}
