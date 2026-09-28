// editing-assist.js - Pure text-editing helpers for the Otter editor:
// auto-closing pairs, closing an Otter block with `.` on Enter, save-time
// cleanup, and indent guides. No DOM here, so every rule is testable in Node.

export const INDENT = '    ';

// The line shapes that open a block in Otter (mirrors the formatter).
export const BLOCK_START = /^(?:when\s+\w+\s+(?:is\s+)?\w+|for\s+each\b|if\b|otherwise\b|repeat\b|while\b|\w+\s+has$|game\b|on\s+(?:tick|key)|function\b|to\s+\w+|try\b)/i;

const PAIRS = { '"': '"', '(': ')', '[': ']' };
const CLOSERS = new Set(Object.values(PAIRS));

function lineStartOf(text, position) {
  return text.lastIndexOf('\n', position - 1) + 1;
}

function lineEndOf(text, position) {
  const index = text.indexOf('\n', position);
  return index === -1 ? text.length : index;
}

function indentOf(line) {
  const match = line.match(/^[ \t]*/);
  return match ? match[0] : '';
}

// Count double quotes before `position` on its line; an odd count means the
// caret is inside a string.
function insideString(text, position) {
  const line = text.slice(lineStartOf(text, position), position);
  return (line.match(/"/g) || []).length % 2 === 1;
}

// Typed a pairing character. Returns { text, start, end } or null to let the
// editor insert the character normally.
export function autoClosePair(text, start, end, key) {
  if (key in PAIRS) {
    const closer = PAIRS[key];
    // Wrap a selection.
    if (start !== end) {
      const selected = text.slice(start, end);
      return { text: text.slice(0, start) + key + selected + closer + text.slice(end), start: start + 1, end: start + 1 + selected.length };
    }
    const next = text[start] || '';
    // Typing a quote right before its twin steps over it.
    if (key === '"' && next === '"') {
      return { text, start: start + 1, end: start + 1 };
    }
    // Only pair when nothing word-like follows (and, for quotes, when we are
    // not already inside a string).
    if (next && !/[\s\]\)\.,:;]/.test(next)) return null;
    if (key === '"' && insideString(text, start)) return null;
    return { text: text.slice(0, start) + key + closer + text.slice(start), start: start + 1, end: start + 1 };
  }
  if (CLOSERS.has(key) && start === end && text[start] === key) {
    // Typing a closer that is already there: step over it.
    return { text, start: start + 1, end: start + 1 };
  }
  return null;
}

// Backspace between the two halves of an empty pair removes both.
export function backspacePair(text, start, end) {
  if (start !== end || start === 0) return null;
  const before = text[start - 1];
  const after = text[start];
  if (before in PAIRS && PAIRS[before] === after) {
    return { text: text.slice(0, start - 1) + text.slice(start + 1), start: start - 1, end: start - 1 };
  }
  return null;
}

// Enter: keep the indentation; after a block opener indent one level and,
// when the block has no body yet, write its closing `.` on the line below
// with the caret in between. Returns { text, start, end }.
export function enterKey(text, start, end, { autoCloseBlocks = true } = {}) {
  const lineStart = lineStartOf(text, start);
  const current = text.slice(lineStart, start);
  const indent = indentOf(current);
  const trimmed = current.trim();
  const opensBlock = BLOCK_START.test(trimmed) && !/\.$/.test(trimmed);
  const restOfLine = text.slice(end, lineEndOf(text, end));

  if (!opensBlock || restOfLine.trim() !== '') {
    const insert = '\n' + indent;
    return { text: text.slice(0, start) + insert + text.slice(end), start: start + insert.length, end: start + insert.length };
  }

  const bodyIndent = indent + INDENT;
  let insert = '\n' + bodyIndent;
  if (autoCloseBlocks) {
    // Look at the next non-blank line: a body or a closer already there means
    // the block is being edited, not created.
    const after = text.slice(lineEndOf(text, end) + 1);
    const nextLine = after.split('\n').find(l => l.trim() !== '');
    const nextIndent = nextLine === undefined ? '' : indentOf(nextLine);
    const alreadyHasBody = nextLine !== undefined && (nextIndent.length > indent.length || (nextLine.trim() === '.' && nextIndent === indent));
    if (!alreadyHasBody) insert += '\n' + indent + '.';
  }
  const caret = start + 1 + bodyIndent.length;
  return { text: text.slice(0, start) + insert + text.slice(end), start: caret, end: caret };
}

// What is written to disk, according to the file settings.
export function prepareForSave(text, { trimTrailingWhitespace = true, insertFinalNewline = true } = {}) {
  let out = text;
  if (trimTrailingWhitespace) out = out.split('\n').map(l => l.replace(/[ \t]+$/, '')).join('\n');
  if (insertFinalNewline && out.length > 0 && !out.endsWith('\n')) out += '\n';
  return out;
}

// Indent guides: the leading indentation is wrapped in spans (one per four
// spaces) that draw a hairline via CSS. The spaces stay inside the spans so
// the highlighted layer keeps exactly the textarea's character positions.
export function renderIndentGuides(line, highlightRest) {
  const indent = indentOf(line);
  const spaces = indent.replace(/\t/g, INDENT);
  if (spaces.length < INDENT.length || indent !== spaces) return highlightRest(line);
  const levels = Math.floor(spaces.length / INDENT.length);
  const remainder = spaces.length - levels * INDENT.length;
  let html = '';
  for (let i = 0; i < levels; i++) html += `<span class="indent-guide">${INDENT}</span>`;
  html += ' '.repeat(remainder);
  return html + highlightRest(line.slice(indent.length));
}
