// diff-view.js - Side-by-side comparison of two texts (File > Compare...).
//
// Used for: the current file against its saved copy, against the last Git
// commit (HEAD), and against another file. The line diff is the same one the
// Git pane uses (js/scm/line-diff.js). Alt+Up / Alt+Down (or the arrows in
// the header) jump between changes; Esc closes.

import { diffLines, sideBySide, diffStats } from '../scm/line-diff.js';

export function showDiff({ title, leftLabel, rightLabel, left, right }) {
  document.querySelector('.diff-view-backdrop')?.remove();
  const ops = diffLines(left ?? '', right ?? '');
  const rows = sideBySide(ops);
  const stats = diffStats(ops);
  const changeStarts = rows.map((r, i) => (r.type !== 'equal' && (i === 0 || rows[i - 1].type === 'equal') ? i : -1)).filter(i => i >= 0);

  const cell = (side, row) => side
    ? `<span class="diff-ln">${side.line}</span><span class="diff-code">${escapeHtml(side.text) || ' '}</span>`
    : '<span class="diff-ln"></span><span class="diff-code diff-empty"></span>';
  const body = rows.length && (stats.added || stats.removed)
    ? rows.map((r, i) => `
        <div class="diff-row diff-${r.type}" data-row="${i}">
          <div class="diff-side diff-left">${cell(r.left, r)}</div>
          <div class="diff-side diff-right">${cell(r.right, r)}</div>
        </div>`).join('')
    : '<div class="diff-same">The two sides are identical.</div>';

  const backdrop = document.createElement('div');
  backdrop.className = 'modal-backdrop diff-view-backdrop';
  backdrop.style.display = 'flex';
  backdrop.innerHTML = `
    <div class="modal-dialog diff-view" role="dialog" aria-modal="true" aria-label="${escapeHtml(title)}">
      <div class="diff-view-header">
        <div class="diff-view-title">
          <strong>${escapeHtml(title)}</strong>
          <span class="diff-stat-add">+${stats.added}</span>
          <span class="diff-stat-del">−${stats.removed}</span>
          <span class="diff-view-changes">${changeStarts.length} change${changeStarts.length === 1 ? '' : 's'}</span>
        </div>
        <div class="diff-view-actions">
          <button class="find-action-btn" data-diff-prev title="Previous change (Alt+Up)" ${changeStarts.length ? '' : 'disabled'}>↑</button>
          <button class="find-action-btn" data-diff-next title="Next change (Alt+Down)" ${changeStarts.length ? '' : 'disabled'}>↓</button>
          <button class="modal-close-btn" data-diff-close title="Close (Esc)">✕</button>
        </div>
      </div>
      <div class="diff-view-labels"><div>${escapeHtml(leftLabel)}</div><div>${escapeHtml(rightLabel)}</div></div>
      <div class="diff-view-body">${body}</div>
    </div>`;
  document.body.appendChild(backdrop);

  const scroller = backdrop.querySelector('.diff-view-body');
  let current = -1;
  const goTo = (dir) => {
    if (!changeStarts.length) return;
    current = (current + dir + changeStarts.length) % changeStarts.length;
    const row = scroller.querySelector(`[data-row="${changeStarts[current]}"]`);
    scroller.querySelectorAll('.is-current').forEach(el => el.classList.remove('is-current'));
    row?.classList.add('is-current');
    row?.scrollIntoView({ block: 'center' });
  };
  const close = () => {
    backdrop.remove();
    document.removeEventListener('keydown', onKey, true);
  };
  const onKey = (e) => {
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); }
    else if (e.altKey && e.key === 'ArrowDown') { e.preventDefault(); goTo(1); }
    else if (e.altKey && e.key === 'ArrowUp') { e.preventDefault(); goTo(-1); }
  };
  backdrop.querySelector('[data-diff-close]').addEventListener('click', close);
  backdrop.querySelector('[data-diff-next]').addEventListener('click', () => goTo(1));
  backdrop.querySelector('[data-diff-prev]').addEventListener('click', () => goTo(-1));
  backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop) close(); });
  document.addEventListener('keydown', onKey, true);
  if (changeStarts.length) setTimeout(() => goTo(1), 0);
  return { close, stats, changes: changeStarts.length };
}

function escapeHtml(str) {
  return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
