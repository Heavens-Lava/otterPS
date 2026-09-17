// json.js - Dedicated JSON syntax highlighter for Otter Studio

function escapeHtml(text) {
  if (typeof text !== 'string') return '';
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function highlightJsonLine(line) {
  let l = escapeHtml(line);
  // Match property keys: `"name":`
  l = l.replace(/"([^"]+)"(?=\s*:)/g, '<span class="tok-var">"$1"</span>');
  // Match string values after colon:
  l = l.replace(/(:\s*)"([^"]*)"/g, '$1<span class="tok-str">"$2"</span>');
  // Match number values after colon:
  l = l.replace(/(:\s*)(\d+(?:\.\d+)?)/g, '$1<span class="tok-num">$2</span>');
  // Match boolean / null values after colon:
  l = l.replace(/(:\s*)(true|false|null)\b/g, '$1<span class="tok-bool">$2</span>');
  return l;
}
