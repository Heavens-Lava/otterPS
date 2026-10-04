export function flattenProjectFiles(items, rootFolder = '') {
  const files = [];
  for (const item of items || []) {
    if (item.isDir) {
      files.push(...flattenProjectFiles(item.children || [], rootFolder));
      continue;
    }
    const relativePath = String(item.path || item.name || '').replace(/\\/g, '/');
    files.push({
      name: item.name || relativePath.split('/').pop(),
      path: rootFolder ? `${rootFolder}/${relativePath}` : relativePath
    });
  }
  return files;
}

function fuzzyScore(label, query) {
  const haystack = label.toLowerCase();
  const needle = query.trim().toLowerCase();
  if (!needle) return 0;
  const exact = haystack.indexOf(needle);
  if (exact >= 0) return exact;

  let cursor = 0;
  let score = 100;
  for (const character of needle) {
    const found = haystack.indexOf(character, cursor);
    if (found < 0) return Number.POSITIVE_INFINITY;
    score += found - cursor;
    cursor = found + 1;
  }
  return score;
}

export function filterNavigationItems(items, query, limit = 80) {
  return (items || [])
    .map(item => ({ item, score: fuzzyScore(`${item.label} ${item.detail || ''}`, query) }))
    .filter(entry => Number.isFinite(entry.score))
    .sort((left, right) => left.score - right.score || left.item.label.localeCompare(right.item.label))
    .slice(0, limit)
    .map(entry => entry.item);
}

export function symbolsForFile(symbols, filePath) {
  return (symbols || [])
    .filter(symbol => symbol.File === filePath)
    .sort((left, right) => Number(left.Line) - Number(right.Line) || Number(left.Column) - Number(right.Column));
}

// Resolve only declarations that the current document can legally see without
// inventing module/hoisting semantics. The nearest declaration before the
// cursor wins; a later declaration is used for forward-declared functions.
// If not found in the current file, cross-file workspace symbols are checked.
export function definitionForWord(symbols, filePath, name, line, workspaceSymbols = [], workspaceFiles = [], source = '') {
  const allSymbols = symbols || [];

  // Check if cursor/word is on a `use "..."` line or module reference
  if (source && line) {
    const lines = source.split(/\r?\n/);
    const lineText = lines[line - 1] || '';
    const useMatch = lineText.match(/^\s*use\s+["']([^"']+)["']/);
    if (useMatch && (useMatch[1].includes(name) || name === 'use' || lineText.includes(name))) {
      const cleanPath = useMatch[1];
      const dir = filePath ? filePath.replace(/\\/g, '/').split('/').slice(0, -1).join('/') : '';
      const resolved = dir ? `${dir}/${cleanPath}` : cleanPath;
      return { Name: cleanPath, Kind: 'module', File: resolved, Line: 1, Column: 0 };
    }
  }

  const candidates = symbolsForFile(allSymbols, filePath)
    .filter(symbol => symbol.Name === name);
  if (candidates.length > 0) {
    const beforeCursor = candidates
      .filter(symbol => Number(symbol.Line) <= Number(line))
      .sort((left, right) => Number(right.Line) - Number(left.Line));
    return beforeCursor[0] || candidates[0];
  }

  // Cross-file fallback: if not found in current file, search workspace symbols
  const pool = [...allSymbols, ...(workspaceSymbols || [])];
  const remoteCandidates = pool.filter(s => s.File !== filePath && s.Name === name);
  if (remoteCandidates.length > 0) {
    const remoteFn = remoteCandidates.find(s => (s.Kind || s.kind) === 'function');
    return remoteFn || remoteCandidates[0];
  }

  return null;
}

// A safe lexical occurrence scan for the active document. It is intentionally
// not called semantic Find References: full scope-aware references need richer
// parser metadata. Comments and quoted strings cannot produce false matches.
export function occurrencesForWord(source, name) {
  if (!name) return [];
  const occurrences = [];
  const isWordChar = character => /[A-Za-z0-9_]/.test(character || '');
  for (const [index, line] of String(source || '').split(/\r?\n/).entries()) {
    let inString = false;
    for (let column = 0; column < line.length;) {
      const character = line[column];
      if (character === '"') {
        inString = !inString;
        column++;
        continue;
      }
      if (!inString && character === '#') break;
      if (!inString && line.startsWith(name, column) && !isWordChar(line[column - 1]) && !isWordChar(line[column + name.length])) {
        occurrences.push({ line: index + 1, column, text: line.trim() });
        column += name.length;
        continue;
      }
      column++;
    }
  }
  return occurrences;
}

export class NavigationHistory {
  constructor(limit = 100) {
    this.limit = limit;
    this.entries = [];
    this.index = -1;
  }

  record(location) {
    if (!location?.path) return;
    const normalized = {
      path: location.path,
      line: Math.max(1, Number(location.line) || 1),
      column: Math.max(0, Number(location.column) || 0)
    };
    const current = this.entries[this.index];
    if (current && current.path === normalized.path && current.line === normalized.line && current.column === normalized.column) return;
    this.entries = this.entries.slice(0, this.index + 1);
    this.entries.push(normalized);
    if (this.entries.length > this.limit) this.entries.shift();
    this.index = this.entries.length - 1;
  }

  back() {
    if (this.index <= 0) return null;
    this.index -= 1;
    return this.entries[this.index];
  }

  forward() {
    if (this.index < 0 || this.index >= this.entries.length - 1) return null;
    this.index += 1;
    return this.entries[this.index];
  }

  get canBack() { return this.index > 0; }
  get canForward() { return this.index >= 0 && this.index < this.entries.length - 1; }
}
