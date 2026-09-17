// large-file.js - Large File Threshold Detection, Viewport Virtualization, and Performance Optimization

export const LARGE_FILE_LINE_THRESHOLD = 3000;
export const LARGE_FILE_SIZE_THRESHOLD = 500000; // ~500KB
export const DEFAULT_LINE_HEIGHT = 22; // standard editor monospace line height in px

export function isLargeFile(codeText, byteSize = null) {
  if (byteSize && byteSize >= LARGE_FILE_SIZE_THRESHOLD) {
    return true;
  }
  if (!codeText) return false;
  if (codeText.length >= LARGE_FILE_SIZE_THRESHOLD) {
    return true;
  }

  // Fast newline counting without splitting huge string into memory array
  let lines = 1;
  for (let i = 0; i < codeText.length; i++) {
    if (codeText.charCodeAt(i) === 10) { // '\n'
      lines++;
      if (lines >= LARGE_FILE_LINE_THRESHOLD) {
        return true;
      }
    }
  }

  return false;
}

export function computeVisibleRange(scrollTop, viewportHeight, totalLines, lineHeight = DEFAULT_LINE_HEIGHT, overscan = 40) {
  const safeHeight = Math.max(viewportHeight || 400, 200);
  const safeScroll = Math.max(0, scrollTop || 0);

  const firstVisible = Math.floor(safeScroll / lineHeight);
  const visibleCount = Math.ceil(safeHeight / lineHeight);

  const startIndex = Math.max(0, firstVisible - overscan);
  const endIndex = Math.min(totalLines, firstVisible + visibleCount + overscan);

  const topSpacerHeight = startIndex * lineHeight;
  const bottomSpacerHeight = Math.max(0, (totalLines - endIndex) * lineHeight);

  return {
    startIndex,
    endIndex,
    topSpacerHeight,
    bottomSpacerHeight,
    totalLines,
    isVirtualized: true
  };
}

export function renderVirtualizedLines(lines, startIndex, endIndex, topSpacerHeight, bottomSpacerHeight, syntaxHighlightFn, errorLine = null) {
  let html = '';

  if (topSpacerHeight > 0) {
    html += `<div class="virtual-spacer top-spacer" style="height:${topSpacerHeight}px;"></div>`;
  }

  for (let idx = startIndex; idx < endIndex && idx < lines.length; idx++) {
    const line = lines[idx];
    const lineNum = idx + 1;
    let renderedLine = syntaxHighlightFn ? syntaxHighlightFn(line) : escapeHtml(line);
    const indentClass = line.startsWith('        ') ? ' ind-2' : (line.startsWith('    ') ? ' ind-1' : '');
    const errClass = (errorLine === lineNum) ? ' has-error' : '';

    html += `<div class="code-line${indentClass}${errClass}" data-line="${lineNum}">${renderedLine || '&nbsp;'}</div>`;
  }

  if (bottomSpacerHeight > 0) {
    html += `<div class="virtual-spacer bottom-spacer" style="height:${bottomSpacerHeight}px;"></div>`;
  }

  return html;
}

export function renderVirtualizedGutter(startIndex, endIndex, topSpacerHeight, bottomSpacerHeight, errorLine = null, warningLine = null) {
  let html = '';

  if (topSpacerHeight > 0) {
    html += `<div class="gutter-spacer top-spacer" style="height:${topSpacerHeight}px;"></div>`;
  }

  for (let idx = startIndex; idx < endIndex; idx++) {
    const i = idx + 1;
    let markerClass = '';
    if (errorLine === i) markerClass = ' class="gutter-err"';
    else if (warningLine === i) markerClass = ' class="gutter-warn"';
    html += `<span${markerClass}>${i}</span>`;
  }

  if (bottomSpacerHeight > 0) {
    html += `<div class="gutter-spacer bottom-spacer" style="height:${bottomSpacerHeight}px;"></div>`;
  }

  return html;
}

function escapeHtml(text) {
  return String(text || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
