// editor-extras.js - Small editor features with their logic kept out of ide.js:
// rendered whitespace, links in source, bookmarks and the TODO/FIXME scan.

// --- Render whitespace ----------------------------------------------------------

// Mark every space in highlighted line HTML so CSS can draw a dot over it.
// The space character itself stays, so column widths (and the textarea caret
// that sits on top) are unchanged. Only text between tags is touched.
export function markWhitespace(html) {
  return String(html).split(/(<[^>]*>)/).map(part => {
    if (part.startsWith('<')) return part;
    return part.replace(/ /g, '<span class="ws-dot"> </span>').replace(/&nbsp;/g, '<span class="ws-dot">&nbsp;</span>');
  }).join('');
}

// --- Links in source ---------------------------------------------------------------

const URL_RE = /\bhttps?:\/\/[^\s"'<>)]+/gi;
// A quoted relative path with a file extension: "data/customers.csv", "main.ot".
const PATH_RE = /"((?:\.{1,2}\/)?[\w.-]+(?:\/[\w.-]+)*\.[A-Za-z0-9]{1,8})"/g;

// What is under `column` on `line`: { type: 'url', target } or
// { type: 'path', target } (as written), or null.
export function findLinkAt(line, column) {
  for (const re of [URL_RE, PATH_RE]) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(line)) !== null) {
      const start = m.index;
      const end = m.index + m[0].length;
      if (column >= start && column <= end) {
        return re === URL_RE
          ? { type: 'url', target: m[0].replace(/[.,;:]+$/, '') }
          : { type: 'path', target: m[1] };
      }
    }
  }
  return null;
}

// A path written in `fromFile` ("projects/app/main.ot"), resolved to a
// workspace path, or null when it climbs out of the workspace.
export function resolveSourcePath(fromFile, written) {
  const baseParts = String(fromFile || '').split('/').slice(0, -1);
  for (const part of written.split('/')) {
    if (part === '.' || part === '') continue;
    if (part === '..') {
      if (!baseParts.length) return null;
      baseParts.pop();
    } else {
      baseParts.push(part);
    }
  }
  return baseParts.join('/');
}

// --- Bookmarks ---------------------------------------------------------------------

const BOOKMARK_KEY = 'otter-studio-bookmarks';

// Line bookmarks per file, kept in this browser.
export function createBookmarks(storage = safeStorage()) {
  let data = {};
  try { data = JSON.parse(storage?.getItem(BOOKMARK_KEY) || '{}') || {}; } catch { data = {}; }
  const save = () => { try { storage?.setItem(BOOKMARK_KEY, JSON.stringify(data)); } catch { /* storage unavailable */ } };

  return {
    lines(path) {
      return [...(data[path] || [])].sort((a, b) => a - b);
    },
    has(path, line) {
      return (data[path] || []).includes(line);
    },
    toggle(path, line) {
      const set = new Set(data[path] || []);
      if (set.has(line)) set.delete(line); else set.add(line);
      if (set.size) data[path] = [...set]; else delete data[path];
      save();
      return set.has(line);
    },
    // The next (+1) or previous (-1) bookmark from `line`, wrapping; null if none.
    next(path, line, direction = 1) {
      const list = this.lines(path);
      if (!list.length) return null;
      if (direction > 0) return list.find(l => l > line) ?? list[0];
      return [...list].reverse().find(l => l < line) ?? list[list.length - 1];
    },
    clear(path) {
      delete data[path];
      save();
    }
  };
}

// --- TODO / FIXME scan -------------------------------------------------------------

// The comment markers the Tasks panel lists, most urgent first.
export const TASK_TAGS = ['FIXME', 'BUG', 'TODO', 'HACK', 'NOTE'];
export const TASK_SEARCH = `\\b(${TASK_TAGS.join('|')})\\b`;

// Keep only real comment tasks from /api/search results and sort them:
// by tag urgency, then file, then line. A task is a tag inside a comment
// (Otter `#`, CSS `/* */`, JS `//`) followed by text.
export function tasksFromSearch(results) {
  const tasks = [];
  for (const r of results || []) {
    const text = String(r.preview || '');
    const m = text.match(new RegExp(`(?:^|#|\\/\\/|\\/\\*|\\*)\\s*(${TASK_TAGS.join('|')})\\b[:\\s-]*(.*)$`));
    if (!m) continue;
    tasks.push({
      tag: m[1],
      text: m[2].replace(/\*\/\s*$/, '').trim() || '(no description)',
      path: r.path,
      line: r.line,
      column: r.column
    });
  }
  const rank = (t) => TASK_TAGS.indexOf(t.tag);
  return tasks.sort((a, b) => rank(a) - rank(b) || a.path.localeCompare(b.path) || a.line - b.line);
}

function safeStorage() {
  try { return typeof localStorage === 'undefined' ? null : localStorage; } catch { return null; }
}
