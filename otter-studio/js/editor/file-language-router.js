// file-language-router.js - Multi-language router for Otter Studio

import { highlightOtterLine } from './syntax/otter.js';
import { highlightCssLine } from './syntax/css.js';
import { highlightJsonLine } from './syntax/json.js';

export function getLanguageForFile(filePath = '') {
  const normalized = filePath.toLowerCase();
  if (normalized.endsWith('.ot')) return 'otter';
  if (normalized.endsWith('.css')) return 'css';
  if (normalized.endsWith('.json')) return 'json';
  if (normalized.endsWith('.md')) return 'markdown';
  if (normalized.endsWith('.html') || normalized.endsWith('.htm')) return 'html';
  if (normalized.endsWith('.js') || normalized.endsWith('.mjs')) return 'javascript';
  return 'plaintext';
}

export function isOtterFile(filePath = '') {
  return !filePath || filePath.toLowerCase().endsWith('.ot');
}

export function getFileIcon(filePath = '') {
  const lang = getLanguageForFile(filePath);
  switch (lang) {
    case 'otter': return '📄';
    case 'css': return '🎨';
    case 'json': return '⚙';
    case 'markdown': return '📝';
    case 'html': return '🌐';
    case 'javascript': return '⚡';
    default: return '📄';
  }
}

export function highlightSourceLine(line, filePath = '', workspaceSymbols = []) {
  const lang = getLanguageForFile(filePath);
  switch (lang) {
    case 'css':
      return highlightCssLine(line);
    case 'json':
      return highlightJsonLine(line);
    case 'otter':
    default:
      return highlightOtterLine(line, workspaceSymbols, filePath);
  }
}
