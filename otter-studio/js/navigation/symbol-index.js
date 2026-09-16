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
// inventing module/hoisting semantics.  The nearest declaration before the
// cursor wins; a later declaration is used for forward-declared functions.
export function definitionForWord(symbols, filePath, name, line) {
  const candidates = symbolsForFile(symbols, filePath)
    .filter(symbol => symbol.Name === name);
  if (candidates.length === 0) return null;

  const beforeCursor = candidates
    .filter(symbol => Number(symbol.Line) <= Number(line))
    .sort((left, right) => Number(right.Line) - Number(left.Line));
  return beforeCursor[0] || candidates[0];
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
