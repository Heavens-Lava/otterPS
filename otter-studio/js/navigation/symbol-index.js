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
