// document-state.js - Tab state management & viewport preservation for Otter Studio

export function snapshotTabState(tab, textarea) {
  if (!tab) return;
  if (textarea) {
    tab.content = textarea.value;
    tab.selectionStart = textarea.selectionStart;
    tab.selectionEnd = textarea.selectionEnd;
    tab.scrollTop = textarea.scrollTop;
    tab.scrollLeft = textarea.scrollLeft;
  }
}

export function restoreTabState(tab, textarea, codeAreaEl = null, gutterEl = null) {
  if (!tab || !textarea) return;
  const len = typeof tab.content === 'string' ? tab.content.length : textarea.value.length;
  const start = typeof tab.selectionStart === 'number' ? Math.min(tab.selectionStart, len) : len;
  const end = typeof tab.selectionEnd === 'number' ? Math.min(tab.selectionEnd, len) : len;

  requestAnimationFrame(() => {
    try {
      textarea.focus({ preventScroll: true });
      textarea.setSelectionRange(start, end);
      if (typeof tab.scrollTop === 'number') {
        textarea.scrollTop = tab.scrollTop;
        textarea.scrollLeft = tab.scrollLeft || 0;
        if (codeAreaEl) {
          codeAreaEl.scrollTop = tab.scrollTop;
          codeAreaEl.scrollLeft = tab.scrollLeft || 0;
        }
        if (gutterEl) {
          gutterEl.scrollTop = tab.scrollTop;
        }
      }
    } catch {
      // Best-effort viewport restore
    }
  });
}
