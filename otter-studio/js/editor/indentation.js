// indentation.js - How a file is indented: from .editorconfig when one
// applies, otherwise detected from the file's own text, otherwise 4 spaces.
//
//   detectIndentation(text)            -> { insertSpaces, size } | null
//   parseEditorConfig(text)            -> { root, sections: [{ glob, props }] }
//   resolveEditorConfig(file, configs) -> { indentStyle, indentSize, tabWidth,
//                                           endOfLine, insertFinalNewline,
//                                           trimTrailingWhitespace } (only keys set)
//   indentUnit({ insertSpaces, size }) -> '\t' or that many spaces
//
// EditorConfig (https://editorconfig.org): files are found from the file's
// folder upward and stop at one with `root = true`; nearer files win, and
// later sections in a file win over earlier ones. A glob without a "/"
// matches the file name in any folder below the .editorconfig.

export const DEFAULT_INDENT = Object.freeze({ insertSpaces: true, size: 4 });

export function indentUnit(indent = DEFAULT_INDENT) {
  return indent.insertSpaces ? ' '.repeat(indent.size || 4) : '\t';
}

/**
 * Guess the indentation from the text: the lines indented with tabs versus
 * spaces, and for spaces the most common step between a line and the line
 * above it (2, 4, 8...). Null when the text has too little indentation to
 * tell (then a default applies).
 */
export function detectIndentation(text) {
  const lines = String(text || '').replace(/\r\n/g, '\n').split('\n');
  let tabLines = 0;
  let spaceLines = 0;
  const steps = new Map();
  let previous = 0;
  for (const line of lines) {
    if (!line.trim()) continue;
    const indent = line.match(/^[ \t]*/)[0];
    if (indent.startsWith('\t')) tabLines++;
    else if (indent.length > 0) spaceLines++;
    if (!indent.includes('\t')) {
      const step = Math.abs(indent.length - previous);
      if (step >= 2 && step <= 8) steps.set(step, (steps.get(step) || 0) + 1);
      previous = indent.length;
    }
  }
  if (tabLines === 0 && spaceLines === 0) return null;
  if (tabLines > spaceLines) return { insertSpaces: false, size: 4 };
  if (!steps.size) return null;
  // The most common step; a tie goes to the smaller one (a 2-space file
  // also has 4-space steps where two levels close at once).
  const [size] = [...steps.entries()].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0];
  return { insertSpaces: true, size };
}

export function parseEditorConfig(text) {
  const result = { root: false, sections: [] };
  let section = null;
  for (const raw of String(text || '').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#') || line.startsWith(';')) continue;
    const header = line.match(/^\[(.+)\]$/);
    if (header) {
      section = { glob: header[1], props: {} };
      result.sections.push(section);
      continue;
    }
    const pair = line.match(/^([^=:]+?)\s*[=:]\s*(.*)$/);
    if (!pair) continue;
    const key = pair[1].trim().toLowerCase();
    const value = pair[2].replace(/\s[#;].*$/, '').trim();
    if (!section) {
      if (key === 'root') result.root = value.toLowerCase() === 'true';
    } else {
      section.props[key] = value;
    }
  }
  return result;
}

// EditorConfig glob -> RegExp over a path relative to the .editorconfig's
// folder (forward slashes). * = within a folder, ** = across folders,
// ? = one character, [abc] / [!abc], {a,b,c}, {1..3}.
export function editorConfigGlob(glob) {
  let g = glob.trim();
  const anchored = g.includes('/');
  if (g.startsWith('/')) g = g.slice(1);
  let out = '';
  let braces = 0;
  for (let i = 0; i < g.length; i++) {
    const c = g[i];
    if (c === '\\' && i + 1 < g.length) { out += escapeRe(g[++i]); continue; }
    if (c === '*') {
      if (g[i + 1] === '*') {
        i++;
        if (g[i + 1] === '/') { i++; out += '(?:.*/)?'; } else out += '.*';
      } else {
        out += '[^/]*';
      }
    } else if (c === '?') {
      out += '[^/]';
    } else if (c === '[') {
      const close = g.indexOf(']', i + 1);
      if (close === -1) { out += '\\['; continue; }
      let set = g.slice(i + 1, close);
      if (set.startsWith('!')) set = `^${set.slice(1)}`;
      out += `[${set.replace(/\\/g, '\\\\')}]`;
      i = close;
    } else if (c === '{') {
      const close = g.indexOf('}', i + 1);
      const inner = close === -1 ? null : g.slice(i + 1, close);
      const range = inner && inner.match(/^(-?\d+)\.\.(-?\d+)$/);
      if (range) {
        const [lo, hi] = [Number(range[1]), Number(range[2])].sort((a, b) => a - b);
        const nums = [];
        for (let n = lo; n <= hi && nums.length < 1000; n++) nums.push(String(n));
        out += `(?:${nums.join('|')})`;
        i = close;
      } else if (inner !== null && inner.includes(',')) {
        out += '(?:';
        braces++;
      } else {
        out += '\\{';
      }
    } else if (c === ',' && braces > 0) {
      out += '|';
    } else if (c === '}' && braces > 0) {
      out += ')';
      braces--;
    } else {
      out += escapeRe(c);
    }
  }
  return new RegExp(`^${anchored ? '' : '(?:.*/)?'}${out}$`);
}

const escapeRe = (c) => c.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');

/**
 * The settings for `filePath` (workspace-relative, forward slashes) from
 * `configs`: [{ dir, text }] nearest folder first, as the server returns
 * them (it stops at a root = true file).
 */
export function resolveEditorConfig(filePath, configs = []) {
  const props = {};
  for (const { dir, text } of [...configs].reverse()) {
    const prefix = dir && dir !== '.' ? `${dir}/` : '';
    if (prefix && !filePath.startsWith(prefix)) continue;
    const rel = filePath.slice(prefix.length);
    for (const section of parseEditorConfig(text).sections) {
      let re;
      try { re = editorConfigGlob(section.glob); } catch { continue; }
      if (!re.test(rel)) continue;
      for (const [k, v] of Object.entries(section.props)) props[k] = v;
    }
  }
  for (const k of Object.keys(props)) if (String(props[k]).toLowerCase() === 'unset') delete props[k];

  const result = {};
  const style = String(props.indent_style || '').toLowerCase();
  if (style === 'space' || style === 'tab') result.indentStyle = style;
  const tabWidth = parseInt(props.tab_width, 10);
  const size = String(props.indent_size || '').toLowerCase();
  if (size === 'tab') result.indentSize = Number.isFinite(tabWidth) ? tabWidth : null;
  else if (/^\d+$/.test(size) && Number(size) > 0) result.indentSize = Number(size);
  if (Number.isFinite(tabWidth) && tabWidth > 0) result.tabWidth = tabWidth;
  else if (result.indentSize) result.tabWidth = result.indentSize;
  const eol = String(props.end_of_line || '').toLowerCase();
  if (eol === 'lf' || eol === 'crlf') result.endOfLine = eol;
  for (const [key, name] of [['insert_final_newline', 'insertFinalNewline'], ['trim_trailing_whitespace', 'trimTrailingWhitespace']]) {
    const v = String(props[key] || '').toLowerCase();
    if (v === 'true' || v === 'false') result[name] = v === 'true';
  }
  return result;
}

/**
 * The indentation a file uses: .editorconfig first, then what its text
 * shows, then the default. `source` says which, for the status bar.
 */
export function indentationFor(text, editorConfig = {}) {
  if (editorConfig.indentStyle || editorConfig.indentSize) {
    const detected = detectIndentation(text);
    const insertSpaces = editorConfig.indentStyle ? editorConfig.indentStyle === 'space' : (detected?.insertSpaces ?? true);
    const size = editorConfig.indentSize || editorConfig.tabWidth || detected?.size || 4;
    return { insertSpaces, size, tabWidth: editorConfig.tabWidth || size, source: 'editorconfig' };
  }
  const detected = detectIndentation(text);
  if (detected) return { ...detected, tabWidth: detected.insertSpaces ? 4 : detected.size, source: 'detected' };
  return { ...DEFAULT_INDENT, tabWidth: 4, source: 'default' };
}
