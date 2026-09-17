// otter.js - Dedicated Otter syntax and semantic token highlighter for Otter Studio

import { symbolsForFile } from '../../navigation/symbol-index.js';

function escapeHtml(text) {
  if (typeof text !== 'string') return '';
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

const multiWordKeywords = [
  'is at least', 'is at most', 'is greater than', 'is less than', 'is not',
  'get files in', 'get folders in', 'and subfolders into', 'copy file to',
  'for each', 'name of', 'extension of', 'create folder', 'divided by',
  'on tick', 'on key'
];

const singleKeywords = [
  'to', 'make', 'when', 'function', 'return', 'stop', 'if', 'otherwise',
  'while', 'count', 'repeat', 'has', 'is', 'add', 'remove', 'put',
  'ask', 'display', 'wait', 'say', 'get', 'into', 'not', 'and', 'or',
  'game'
];

const uiWidgets = new Set([
  'window', 'button', 'label', 'textbox', 'canvas', 'box', 'column',
  'row', 'stack', 'card', 'slider', 'checkbox'
]);

export function highlightOtterLine(line, workspaceSymbols = [], currentFile = '') {
  if (line.trim().startsWith('#')) {
    return `<span class="tok-comment">${escapeHtml(line)}</span>`;
  }

  const currentSymbols = symbolsForFile(workspaceSymbols, currentFile);
  const userFns = new Set(
    currentSymbols
      .filter(s => (s.Kind || s.kind) === 'function')
      .map(s => (s.Name || s.name || '').toLowerCase())
  );
  const userVars = new Set(
    currentSymbols
      .filter(s => ['variable', 'parameter', 'loop-variable'].includes((s.Kind || s.kind || '').toLowerCase()))
      .map(s => (s.Name || s.name || '').toLowerCase())
  );

  let l = escapeHtml(line);

  // Strings
  l = l.replace(/"([^"]*)"/g, '<span class="tok-str">"$1"</span>');

  // Numbers
  l = l.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');

  // Booleans & Special Values
  l = l.replace(/\b(true|false|gone)\b/g, '<span class="tok-bool">$1</span>');

  // Multi-word keywords & comparison operators
  for (const kw of multiWordKeywords) {
    const reg = new RegExp(`\\b(${kw})\\b`, 'gi');
    l = l.replace(reg, '<span class="tok-kw">$1</span>');
  }

  // Single keywords
  for (const kw of singleKeywords) {
    const reg = new RegExp(`\\b(${kw})\\b`, 'gi');
    l = l.replace(reg, '<span class="tok-kw">$1</span>');
  }

  // Period block terminator
  l = l.replace(/(^|\s)(\.)(\s|$)/g, '$1<span class="tok-kw">.</span>$3');

  // Semantic Highlighting for user functions, variables, and UI widgets (only outside existing HTML tags)
  l = l.replace(/(<[^>]+>)|(\b[A-Za-z_][A-Za-z0-9_]*\b)/g, (match, tag, word) => {
    if (tag) return tag;
    const lower = (word || '').toLowerCase();
    if (userFns.has(lower)) {
      return `<span class="tok-fn">${word}</span>`;
    }
    if (uiWidgets.has(lower)) {
      return `<span class="tok-ui">${word}</span>`;
    }
    if (userVars.has(lower)) {
      return `<span class="tok-var">${word}</span>`;
    }
    return word;
  });

  return l;
}
