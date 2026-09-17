// css.js - Dedicated CSS syntax highlighter for Otter Studio

function escapeHtml(text) {
  if (typeof text !== 'string') return '';
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function highlightCssLine(line) {
  const trimmed = line.trim();
  if (trimmed.startsWith('/*') && trimmed.endsWith('*/')) {
    return `<span class="tok-comment">${escapeHtml(line)}</span>`;
  }
  let l = escapeHtml(line);

  // Preserve comments
  const comments = [];
  l = l.replace(/\/\*[\s\S]*?\*\//g, m => {
    comments.push(m);
    return `___CSS_COMMENT_${comments.length - 1}___`;
  });

  // Preserve strings
  const strings = [];
  l = l.replace(/"([^"]*)"|'([^']*)'/g, m => {
    strings.push(m);
    return `___CSS_STR_${strings.length - 1}___`;
  });

  // Highlight selectors before {
  if (l.includes('{')) {
    const braceIdx = l.indexOf('{');
    let sel = l.substring(0, braceIdx);
    const rest = l.substring(braceIdx);

    sel = sel
      .replace(/([#][A-Za-z0-9_-]+)/g, '<span class="tok-ui">$1</span>')
      .replace(/([.][A-Za-z0-9_-]+)/g, '<span class="tok-fn">$1</span>')
      .replace(/(^|[\s,>+~])(window|button|label|textbox|canvas|body|div|span|h1|h2|h3|p|a|input|header|footer|main|section|aside)(?=[\s,{:>]|$)/g, '$1<span class="tok-kw">$2</span>');

    l = sel + rest;
  }

  // Highlight CSS properties before colon (e.g. `background:`, `color:`)
  l = l.replace(/([a-zA-Z-][a-zA-Z0-9-]*)(?=\s*:)/g, '<span class="tok-var">$1</span>');

  // Highlight hex color values after colon: `#0f172a`
  l = l.replace(/(:\s*[^;{}]*?)(#[0-9a-fA-F]{3,8}\b)/g, '$1<span class="tok-ui">$2</span>');

  // Highlight numbers with optional units
  l = l.replace(/(:\s*[^;{}]*?)(\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms)?\b)/g, '$1<span class="tok-num">$2</span>');

  // Highlight common CSS keyword values
  l = l.replace(/(:\s*[^;{}]*?)(\b(true|false|none|block|flex|grid|inline|inline-block|absolute|relative|fixed|auto|center|left|right|bold|normal|solid|dashed|hidden|visible|transparent|inherit|pointer)\b)/g, '$1<span class="tok-kw">$2</span>');

  // Restore strings
  l = l.replace(/___CSS_STR_(\d+)___/g, (_, idx) => `<span class="tok-str">${strings[Number(idx)]}</span>`);

  // Restore comments
  l = l.replace(/___CSS_COMMENT_(\d+)___/g, (_, idx) => `<span class="tok-comment">${comments[Number(idx)]}</span>`);

  return l;
}
