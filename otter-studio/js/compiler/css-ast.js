// css-ast.js - Lossless CSS AST parser and surgical manipulator
// Preserves comments, whitespace, ordering, custom properties (--var), and unknown rules.
//
// "Lossless" is a promise the save path depends on: generateCss() must give
// back the stylesheet exactly as it was read unless the designer changed
// something, and a change must only touch the declaration it is about.
//
// How it stays lossless:
//   * Every top-level item keeps its original text in `raw`. Comments,
//     whitespace, @media/@supports/@keyframes blocks and anything else the
//     designer does not edit are only ever copied through.
//   * A style rule's body is kept as its original `;`-separated segments.
//     Editing `color` rewrites only the `color` segment; the others keep their
//     own spacing, comments and formatting.
//   * Scanning skips strings, comments and parentheses, so a `;` or `}`
//     inside `url("data:...;base64,...")` or `content: "}"` is not mistaken
//     for the end of a declaration or rule.
//
// `dirty` becomes true on the first real edit and tells the IDE there is
// something to write back; the IDE clears it after a successful save.

export class CssAstManager {
  constructor(cssText = '') {
    this.rawText = cssText;
    this.rules = [];
    this.dirty = false;
    // Where this stylesheet lives on disk and the revision it was read at.
    // Set by the IDE when it loads a project's stylesheet; the save path uses
    // them so a designer edit can never silently overwrite a newer file.
    this.sourcePath = null;
    this.revision = null;
    this.parse(cssText);
  }

  // Parse CSS into structured rules while preserving unknown properties and comment blocks
  parse(cssText) {
    this.rawText = cssText || '';
    this.rules = [];
    this.dirty = false;

    const text = this.rawText;
    const len = text.length;
    let i = 0;

    while (i < len) {
      // Comments
      if (text.startsWith('/*', i)) {
        const end = text.indexOf('*/', i + 2);
        const stop = end === -1 ? len : end + 2;
        this.pushItem({ type: 'comment', raw: text.slice(i, stop) });
        i = stop;
        continue;
      }

      // Whitespace / newlines outside rules
      if (/\s/.test(text[i])) {
        let j = i;
        while (j < len && /\s/.test(text[j])) j++;
        this.pushItem({ type: 'whitespace', raw: text.slice(i, j) });
        i = j;
        continue;
      }

      // A prelude runs to the first top-level `{` (a block) or `;` (a
      // statement such as `@import url(x);`).
      const stop = scanUntil(text, i, ch => ch === '{' || ch === ';');
      if (stop >= len) {
        this.pushItem({ type: 'raw', raw: text.slice(i) });
        break;
      }
      if (text[stop] === ';') {
        this.pushItem({ type: 'raw', raw: text.slice(i, stop + 1) });
        i = stop + 1;
        continue;
      }

      const close = matchingBrace(text, stop);
      if (close === -1) {
        // Malformed, store as raw
        this.pushItem({ type: 'raw', raw: text.slice(i) });
        break;
      }

      const selectorRaw = text.slice(i, stop);
      const selector = selectorRaw.trim();
      const raw = text.slice(i, close + 1);

      if (selector.startsWith('@')) {
        // @media, @supports, @keyframes, @font-face...: never rewritten.
        this.pushItem({ type: 'raw', raw });
      } else {
        this.pushItem({
          type: 'rule',
          selectorRaw,
          selector,
          raw,
          modified: false,
          segments: parseSegments(text.slice(stop + 1, close))
        });
      }
      i = close + 1;
    }
  }

  pushItem(item) {
    this.rules.push(item);
  }

  findRule(selector) {
    // The last matching rule is the one that wins in the cascade.
    for (let i = this.rules.length - 1; i >= 0; i--) {
      const r = this.rules[i];
      if (r.type === 'rule' && r.selector === selector) return r;
    }
    return null;
  }

  // Declarations of a rule, in order: [{ property, value, segment }]
  declarationsOf(rule) {
    return rule.segments.filter(s => s.type === 'declaration');
  }

  // Get declaration value for a given selector and property
  getProperty(selector, property) {
    const rule = this.findRule(selector);
    if (!rule) return null;

    const decls = this.declarationsOf(rule).filter(d => d.property.toLowerCase() === property.toLowerCase());
    return decls.length ? decls[decls.length - 1].value : null;
  }

  // Get all declarations for a selector as a key-value map
  getRuleDeclarations(selector) {
    const rule = this.findRule(selector);
    if (!rule) return {};

    const map = {};
    for (const d of this.declarationsOf(rule)) {
      map[d.property.toLowerCase()] = d.value;
    }
    return map;
  }

  // Set or update a property on a selector
  setProperty(selector, property, value) {
    const remove = value === null || value === undefined || value === '';
    let rule = this.findRule(selector);

    if (!rule) {
      if (remove) return;
      // Create new rule at the end, separated from the text before it by one
      // blank line. New rules are written in the canonical format.
      const before = this.generateCss();
      const gap = before === '' ? '' : (before.endsWith('\n\n') ? '' : (before.endsWith('\n') ? '\n' : '\n\n'));
      if (gap) this.pushItem({ type: 'whitespace', raw: gap });
      rule = {
        type: 'rule',
        selectorRaw: `${selector} `,
        selector,
        raw: '',
        modified: true,
        created: true,
        segments: [{ type: 'other', raw: '\n' }]
      };
      this.pushItem(rule);
      this.pushItem({ type: 'whitespace', raw: '\n' });
    }

    const propLower = property.toLowerCase();
    const matches = rule.segments.filter(s => s.type === 'declaration' && s.property.toLowerCase() === propLower);

    if (remove) {
      if (matches.length === 0) return;
      rule.segments = rule.segments.filter(s => !matches.includes(s));
    } else if (matches.length > 0) {
      const target = matches[matches.length - 1];
      if (target.value === String(value)) return; // no change, stay clean
      target.value = String(value);
      target.modified = true;
    } else {
      insertDeclaration(rule, property, String(value));
    }

    rule.modified = true;
    this.dirty = true;
  }

  // Generate CSS string output preserving comments, rules, and ordering
  generateCss() {
    let out = '';
    for (const item of this.rules) {
      if (item.type !== 'rule' || !item.modified) {
        out += item.raw;
      } else {
        out += `${item.selectorRaw}{${item.segments.map(renderSegment).join(';')}}`;
      }
    }
    return out;
  }

  // The IDE calls this after the stylesheet was written to disk.
  markSaved(revision = null) {
    this.rawText = this.generateCss();
    this.parse(this.rawText);
    this.revision = revision;
  }
}

// ---------------------------------------------------------------------------
// Scanning helpers: skip strings, comments and parentheses.
// ---------------------------------------------------------------------------

// Index of the first character at or after `from` for which `isStop` is true,
// outside strings, comments and parentheses; text.length when there is none.
function scanUntil(text, from, isStop) {
  let depth = 0;
  for (let i = from; i < text.length; i++) {
    const ch = text[i];
    if (ch === '"' || ch === "'") { i = skipString(text, i); continue; }
    if (text.startsWith('/*', i)) { const end = text.indexOf('*/', i + 2); i = end === -1 ? text.length : end + 1; continue; }
    if (ch === '(') depth++;
    else if (ch === ')') depth = Math.max(0, depth - 1);
    else if (depth === 0 && isStop(ch)) return i;
  }
  return text.length;
}

function skipString(text, start) {
  const quote = text[start];
  for (let i = start + 1; i < text.length; i++) {
    if (text[i] === '\\') { i++; continue; }
    if (text[i] === quote || text[i] === '\n') return i;
  }
  return text.length;
}

// Index of the `}` that closes the `{` at `open`, or -1.
function matchingBrace(text, open) {
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    const ch = text[i];
    if (ch === '"' || ch === "'") { i = skipString(text, i); continue; }
    if (text.startsWith('/*', i)) { const end = text.indexOf('*/', i + 2); if (end === -1) return -1; i = end + 1; continue; }
    if (ch === '{') depth++;
    else if (ch === '}') { depth--; if (depth === 0) return i; }
  }
  return -1;
}

// Split a rule body on top-level `;`. Each segment keeps its raw text; the
// ones that are `property: value` also carry the parsed pair.
function parseSegments(body) {
  const segments = [];
  let start = 0;
  while (start <= body.length) {
    const stop = scanUntil(body, start, ch => ch === ';');
    const raw = body.slice(start, stop);
    segments.push(readSegment(raw));
    if (stop >= body.length) break;
    start = stop + 1;
  }
  return segments;
}

function readSegment(raw) {
  // Leading comments stay with the segment but are not part of the property.
  const withoutComments = raw.replace(/\/\*[\s\S]*?\*\//g, '');
  const colon = scanUntil(withoutComments, 0, ch => ch === ':');
  if (!withoutComments.trim() || colon >= withoutComments.length) return { type: 'other', raw };
  return {
    type: 'declaration',
    raw,
    property: withoutComments.slice(0, colon).trim(),
    value: withoutComments.slice(colon + 1).trim(),
    modified: false
  };
}

function renderSegment(segment) {
  if (segment.type !== 'declaration' || !segment.modified) return segment.raw;
  // Keep the whitespace that surrounded the original segment.
  const lead = (segment.raw.match(/^\s*/) || [''])[0];
  const trail = segment.raw.trim() ? (segment.raw.match(/\s*$/) || [''])[0] : '';
  return `${lead}${segment.property}: ${segment.value}${trail}`;
}

function insertDeclaration(rule, property, value) {
  const decls = rule.segments.filter(s => s.type === 'declaration');
  const last = decls[decls.length - 1];
  // Indent like the existing declarations; a new rule uses four spaces.
  const lead = last ? (last.raw.match(/^\s*/) || [''])[0] : '\n    ';
  const segment = { type: 'declaration', raw: lead, property, value, modified: true };

  const tail = rule.segments[rule.segments.length - 1];
  if (tail && tail.type === 'other' && !tail.raw.trim()) {
    // Body ends with `;` + whitespace (or is empty): insert before that tail
    // so the closing brace keeps its line.
    rule.segments.splice(rule.segments.length - 1, 0, segment);
    if (rule.created) tail.raw = '\n';
  } else {
    // Last declaration had no `;`: add ours after it, then a terminating `;`.
    rule.segments.push(segment, { type: 'other', raw: '' });
  }
}
