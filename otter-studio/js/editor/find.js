// find.js - Find and replace logic for the editor's find widget.
//
// Options (the toggles in the widget):
//   caseSensitive  Aa    match case
//   wholeWord      ab    only whole words
//   regex          .*    a regular expression; \n in the pattern matches
//                        across lines (multi-line search)
//   inSelection    ≡     only inside the range that was selected when the
//                        toggle was turned on
//   preserveCase   AB    on replace, follow the case of each match
//                        (UPPER, Capitalized, lower)

// A global RegExp for the query, or { error } for an invalid pattern.
export function buildFindRegex(query, { caseSensitive = false, wholeWord = false, regex = false } = {}) {
  if (!query) return { error: '' };
  let source = regex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (wholeWord) source = `(?<![A-Za-z0-9_])(?:${source})(?![A-Za-z0-9_])`;
  try {
    return new RegExp(source, caseSensitive ? 'gm' : 'gim');
  } catch (err) {
    return { error: `Invalid pattern: ${err.message}` };
  }
}

// Every match in `text`: [{ index, length, text, groups }]. With a range
// { start, end }, only matches that lie entirely inside it.
export function findAll(text, re, range = null) {
  if (!(re instanceof RegExp)) return [];
  const out = [];
  re.lastIndex = range ? range.start : 0;
  let m;
  while ((m = re.exec(text)) !== null) {
    if (m[0].length === 0) { re.lastIndex++; continue; } // never loop on empty matches
    if (range && m.index + m[0].length > range.end) break;
    out.push({ index: m.index, length: m[0].length, text: m[0], groups: m.slice(1) });
    if (out.length >= 10000) break;
  }
  return out;
}

// The replacement text for one match: $1..$9 and $& in regex mode, and the
// match's case pattern when preserveCase is on.
export function replacementFor(match, replacement, { regex = false, preserveCase = false } = {}) {
  let text = replacement;
  if (regex) {
    text = text.replace(/\$(\d|&)/g, (_, g) => (g === '&' ? match.text : (match.groups[Number(g) - 1] ?? '')));
  }
  return preserveCase ? applyCase(match.text, text) : text;
}

// "Hello" + "world" -> "World"; "HELLO" -> "WORLD"; "hello" -> "world".
export function applyCase(model, text) {
  const letters = model.replace(/[^A-Za-z]/g, '');
  if (!letters) return text;
  if (letters === letters.toUpperCase() && letters.length > 1) return text.toUpperCase();
  if (letters === letters.toLowerCase()) return text.toLowerCase();
  if (letters[0] === letters[0].toUpperCase() && letters.slice(1) === letters.slice(1).toLowerCase()) {
    return text.charAt(0).toUpperCase() + text.slice(1);
  }
  return text;
}

// Replace all `matches` in `text` (from the end, so indexes stay valid).
export function replaceMatches(text, matches, replacement, options = {}) {
  let out = text;
  for (const m of [...matches].sort((a, b) => b.index - a.index)) {
    out = out.slice(0, m.index) + replacementFor(m, replacement, options) + out.slice(m.index + m.length);
  }
  return out;
}
