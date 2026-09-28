// css-ast.js - Lossless CSS AST parser and surgical manipulator
//
// Understands the parts of CSS the designer writes:
//   - plain rules            #card { ... }
//   - state rules            #card:hover { ... }
//   - @media blocks          @media (max-width: 900px) { #card { ... } }
// Any other at-rule (@keyframes, @font-face, @supports, @import ...) is kept
// verbatim.
//
// Every lookup and edit method takes an optional `media` argument: '' (or
// omitted) means the top level, otherwise the media condition text, e.g.
// '(max-width: 900px)'.
//
// "Lossless" is a promise the save path depends on: generateCss() gives back
// the stylesheet exactly as it was read unless the designer changed
// something, and a change only touches the declaration it is about.
//
// How it stays lossless:
//   * Every item (whitespace, comment, rule, @media block, other at-rule)
//     keeps its original text in `raw`. An item is only regenerated when it
//     was edited (`modified`), and an edited @media block regenerates only
//     its edited rules.
//   * A rule's body is kept as its original `;`-separated segments. Editing
//     `color` rewrites only the `color` segment; the others keep their own
//     spacing, comments and formatting.
//   * Scanning skips strings, comments and parentheses, so a `;` or `}`
//     inside `url("data:...;base64,...")` or `content: "}"` is not mistaken
//     for the end of a declaration or rule.
//
// `dirty` becomes true on the first real edit and tells the IDE there is
// something to write back; the IDE clears it (markSaved) after a save.

const INDENT = '    ';

export class CssAstManager {
  constructor(cssText = '') {
    this.rawText = '';
    this.rules = [];
    this.dirty = false;
    // Where this stylesheet lives on disk and the revision it was read at.
    // Set by the IDE; a save sends the revision so a newer file on disk is
    // reported instead of overwritten.
    this.sourcePath = null;
    this.revision = null;
    this.parse(cssText);
  }

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  parse(cssText) {
    this.rawText = cssText || '';
    this.rules = parseItems(this.rawText);
    this.dirty = false;
  }

  parseDeclarations(bodyText) {
    return parseSegments(bodyText).filter(s => s.type === 'declaration')
      .map(s => ({ type: 'declaration', property: s.property, value: s.value }));
  }

  // The save path wrote this text to disk (at `revision`).
  markSaved(revision = null) {
    this.dirty = false;
    this.revision = revision;
  }

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  mediaBlock(media) {
    const query = normalizeMedia(media);
    if (!query) return null;
    return this.rules.find(r => r.type === 'media' && normalizeMedia(r.query) === query) || null;
  }

  // The list of items a selector lives in: the top level or one @media block.
  itemsFor(media = '', create = false) {
    const query = normalizeMedia(media);
    if (!query) return this.rules;
    let block = this.mediaBlock(query);
    if (!block && create) {
      block = newMediaBlock(String(media).trim().replace(/^@media\s+/i, ''));
      placeMediaBlock(this.rules, block);
    }
    return block ? block.items : null;
  }

  findRule(selector, media = '') {
    const items = this.itemsFor(media);
    if (!items) return null;
    const wanted = normalizeSelector(selector);
    // The last matching rule is the one that wins in the cascade.
    for (let i = items.length - 1; i >= 0; i--) {
      const r = items[i];
      if (r.type === 'rule' && normalizeSelector(r.selector) === wanted) return r;
    }
    return null;
  }

  getProperty(selector, property, media = '') {
    const rule = this.findRule(selector, media);
    if (!rule) return null;
    const wanted = property.toLowerCase();
    // The last declaration wins in CSS, so search from the end.
    const decls = declarationsOf(rule);
    for (let i = decls.length - 1; i >= 0; i--) {
      if (decls[i].property.toLowerCase() === wanted) return decls[i].value;
    }
    return null;
  }

  getRuleDeclarations(selector, media = '') {
    const rule = this.findRule(selector, media);
    if (!rule) return {};
    const map = {};
    for (const d of declarationsOf(rule)) map[d.property.toLowerCase()] = d.value;
    return map;
  }

  // Every media condition used in the stylesheet, in source order.
  getMediaQueries() {
    return this.rules.filter(r => r.type === 'media').map(r => r.query);
  }

  // Every rule selector, optionally only those inside `media`.
  getSelectors(media = '') {
    const items = this.itemsFor(media) || [];
    return items.filter(r => r.type === 'rule').map(r => r.selector);
  }

  // Colors written anywhere in the stylesheet, most used first. The designer
  // offers these as a project palette so a design stays consistent.
  getColorPalette(limit = 16) {
    const counts = new Map();
    const colorPattern = /#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})\b|rgba?\([^)]*\)|hsla?\([^)]*\)/g;
    const visit = (items) => {
      for (const item of items) {
        if (item.type === 'rule') {
          for (const d of declarationsOf(item)) {
            for (const match of d.value.match(colorPattern) || []) {
              const key = match.replace(/\s+/g, ' ').toLowerCase();
              counts.set(key, (counts.get(key) || 0) + 1);
            }
          }
        } else if (item.type === 'media') {
          visit(item.items);
        }
      }
    };
    visit(this.rules);
    return Array.from(counts.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, limit)
      .map(([color]) => color);
  }

  // ---------------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------------

  // Set, update or (with null / undefined / '') remove a property.
  setProperty(selector, property, value, media = '') {
    const remove = value === null || value === undefined || value === '';
    const block = this.mediaBlock(media);
    const items = this.itemsFor(media, !remove);
    if (!items) return;

    let rule = this.findRule(selector, media);
    if (!rule) {
      if (remove) return;
      rule = newRule(selector.trim(), ruleIndentFor(items, block || this.mediaBlock(media)));
      insertRule(items, rule, !!normalizeMedia(media));
    }

    const propLower = property.toLowerCase();
    const matches = rule.segments.filter(s => s.type === 'declaration' && s.property.toLowerCase() === propLower);
    const text = remove ? null : String(value);

    if (remove) {
      if (matches.length === 0) return;
      rule.segments = rule.segments.filter(s => !matches.includes(s));
    } else if (matches.length > 0) {
      const keep = matches[matches.length - 1];
      if (matches.length === 1 && keep.value === text) return; // no change
      // Rewrite the winning occurrence in place; drop earlier duplicates.
      keep.value = text;
      keep.modified = true;
      rule.segments = rule.segments.filter(s => s === keep || !matches.includes(s));
    } else {
      addDeclaration(rule, property, text);
    }

    rule.modified = true;
    this.touch(media);
    this.pruneEmpty(items, rule, media);
  }

  removeProperty(selector, property, media = '') {
    this.setProperty(selector, property, null, media);
  }

  // Mark an edit: the @media block (if any) must regenerate its body.
  touch(media) {
    const block = this.mediaBlock(media);
    if (block) block.modified = true;
    this.dirty = true;
  }

  // Drop a rule that has no declarations left, and an @media block with no
  // rules left, so the designer never leaves empty `#x { }` litter behind.
  pruneEmpty(items, rule, media) {
    if (rule && !rule.segments.some(s => s.type === 'declaration' || s.type === 'comment' || /\S/.test(s.raw))) {
      removeItem(items, rule);
    }
    const block = this.mediaBlock(media);
    if (block && !block.items.some(r => r.type === 'rule' || r.type === 'at' || r.type === 'comment')) {
      removeItem(this.rules, block);
    }
  }

  // Remove every rule (at any level) whose selector targets `#id`, including
  // its states (`#id:hover`). Used when a component is deleted.
  removeSelectorFamily(id) {
    let changed = false;
    const visit = (items, block) => {
      for (let i = items.length - 1; i >= 0; i--) {
        const item = items[i];
        if (item.type === 'rule' && selectorTargetsId(item.selector, id)) {
          removeItem(items, item);
          changed = true;
          if (block) block.modified = true;
        } else if (item.type === 'media') {
          visit(item.items, item);
          if (!item.items.some(r => r.type === 'rule' || r.type === 'at' || r.type === 'comment')) removeItem(items, item);
        }
      }
    };
    visit(this.rules, null);
    if (changed) this.dirty = true;
  }

  // Copy every rule for `#fromId` (states and breakpoints included) onto `#toId`.
  copySelectorFamily(fromId, toId) {
    const copies = [];
    const visit = (items, media) => {
      for (const item of items) {
        if (item.type === 'rule' && selectorTargetsId(item.selector, fromId)) {
          copies.push({ media, selector: replaceId(item.selector, fromId, toId), declarations: declarationsOf(item) });
        } else if (item.type === 'media') {
          visit(item.items, item.query);
        }
      }
    };
    visit(this.rules, '');
    for (const copy of copies) {
      for (const d of copy.declarations) this.setProperty(copy.selector, d.property, d.value, copy.media);
    }
  }

  // Rename `#oldId` to `#newId` in every selector, in place.
  renameSelectorFamily(oldId, newId) {
    const visit = (items, block) => {
      for (const item of items) {
        if (item.type === 'rule' && selectorTargetsId(item.selector, oldId)) {
          const next = replaceId(item.selector, oldId, newId);
          item.selectorRaw = item.selectorRaw.replace(item.selector, next);
          item.selector = next;
          item.modified = true;
          if (block) block.modified = true;
          this.dirty = true;
        } else if (item.type === 'media') {
          visit(item.items, item);
        }
      }
    };
    visit(this.rules, null);
  }

  // ---------------------------------------------------------------------------
  // Output
  // ---------------------------------------------------------------------------

  // The stylesheet text: unedited items exactly as they were read.
  generateCss() {
    return emitItems(this.rules);
  }
}

// -----------------------------------------------------------------------------
// Parsing
// -----------------------------------------------------------------------------

// Items of one level (the stylesheet, or an @media body), with whitespace kept
// as items so that joining every `raw` gives the text back.
function parseItems(text) {
  const items = [];
  const len = text.length;
  let i = 0;

  while (i < len) {
    if (/\s/.test(text[i])) {
      let j = i;
      while (j < len && /\s/.test(text[j])) j++;
      items.push({ type: 'whitespace', raw: text.slice(i, j) });
      i = j;
      continue;
    }

    if (text.startsWith('/*', i)) {
      const end = text.indexOf('*/', i + 2);
      const stop = end === -1 ? len : end + 2;
      items.push({ type: 'comment', raw: text.slice(i, stop) });
      i = stop;
      continue;
    }

    // A prelude runs to the first top-level `{` (a block) or `;` (a
    // statement such as `@import url(x);`).
    const stop = scanUntil(text, i, ch => ch === '{' || ch === ';');
    if (stop >= len) {
      items.push({ type: 'raw', raw: text.slice(i) });
      break;
    }
    if (text[stop] === ';') {
      items.push({ type: 'at', raw: text.slice(i, stop + 1) });
      i = stop + 1;
      continue;
    }

    const close = matchingBrace(text, stop);
    if (close === -1) {
      items.push({ type: 'raw', raw: text.slice(i) });
      break;
    }

    const preludeRaw = text.slice(i, stop);
    const prelude = preludeRaw.trim();
    const raw = text.slice(i, close + 1);
    const body = text.slice(stop + 1, close);

    const mediaMatch = prelude.match(/^@media\s+([\s\S]+)$/i);
    if (mediaMatch) {
      items.push({ type: 'media', raw, preludeRaw, query: mediaMatch[1].trim(), items: parseItems(body), modified: false });
    } else if (prelude.startsWith('@')) {
      items.push({ type: 'at', raw });
    } else {
      items.push({ type: 'rule', raw, selectorRaw: preludeRaw, selector: prelude, segments: parseSegments(body), modified: false });
    }
    i = close + 1;
  }

  return items;
}

// A rule body as its `;`-separated segments. Joining every segment's `raw`
// with ';' gives the body back exactly.
function parseSegments(body) {
  const text = body || '';
  const segments = [];
  let start = 0;
  let i = 0;
  const push = (end) => segments.push(makeSegment(text.slice(start, end)));
  while (i < text.length) {
    const next = scanUntil(text, i, ch => ch === ';');
    if (next >= text.length) break;
    push(next);
    start = next + 1;
    i = start;
  }
  push(text.length);
  return segments;
}

function makeSegment(raw) {
  // Leading comments stay part of the segment's raw text; the declaration is
  // what follows them.
  let rest = raw;
  let lead = '';
  for (;;) {
    const m = rest.match(/^(\s*\/\*[\s\S]*?\*\/)/);
    if (!m) break;
    lead += m[1];
    rest = rest.slice(m[1].length);
  }
  const colon = scanUntil(rest, 0, ch => ch === ':');
  if (!rest.trim() || colon >= rest.length) {
    return { type: lead && !rest.trim() ? 'comment' : 'other', raw };
  }
  const property = rest.slice(0, colon).trim();
  const value = rest.slice(colon + 1).trim();
  if (!property || /\s/.test(property)) return { type: 'other', raw };
  return { type: 'declaration', raw, property, value, modified: false };
}

// Index of the first top-level character matching `test`, skipping strings,
// comments and parentheses; text.length when there is none.
function scanUntil(text, from, test) {
  let quote = null;
  let depth = 0;
  for (let i = from; i < text.length; i++) {
    const ch = text[i];
    if (quote) {
      if (ch === '\\') { i++; continue; }
      if (ch === quote) quote = null;
      continue;
    }
    if (text.startsWith('/*', i)) {
      const end = text.indexOf('*/', i + 2);
      if (end === -1) return text.length;
      i = end + 1;
      continue;
    }
    if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '(') depth++;
    else if (ch === ')') depth = Math.max(0, depth - 1);
    else if (depth === 0 && test(ch)) return i;
  }
  return text.length;
}

function matchingBrace(text, open) {
  let depth = 0;
  let quote = null;
  for (let i = open; i < text.length; i++) {
    const ch = text[i];
    if (quote) {
      if (ch === '\\') { i++; continue; }
      if (ch === quote) quote = null;
      continue;
    }
    if (text.startsWith('/*', i)) {
      const end = text.indexOf('*/', i + 2);
      if (end === -1) return -1;
      i = end + 1;
      continue;
    }
    if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

// -----------------------------------------------------------------------------
// Editing helpers
// -----------------------------------------------------------------------------

function declarationsOf(rule) {
  return rule.segments.filter(s => s.type === 'declaration');
}

function newRule(selector, indent) {
  return {
    type: 'rule',
    raw: '',
    selectorRaw: `${indent}${selector} `,
    selector,
    // Body "\n<indent>    " + declarations + "\n<indent>": the trailing
    // segment carries the closing line's indentation.
    segments: [{ type: 'other', raw: `\n${indent}` }],
    indent,
    modified: true,
    fresh: true
  };
}

function newMediaBlock(query) {
  return { type: 'media', raw: '', preludeRaw: `@media ${query} `, query, items: [{ type: 'whitespace', raw: '\n' }], modified: true, fresh: true };
}

// Append a declaration, in the rule's own style: one per line with the
// indentation of its existing declarations, or inline for one-line rules.
function addDeclaration(rule, property, value) {
  const segs = rule.segments;
  const lastDecl = [...segs].reverse().find(s => s.type === 'declaration');
  const tail = segs[segs.length - 1];
  const tailIsTrailing = tail && tail.type !== 'declaration' && !/\S/.test(tail.raw);
  const multiLine = segs.some(s => s.raw.includes('\n')) || rule.fresh;

  let lead;
  if (lastDecl) {
    // A declaration added in this session has no raw text yet: reuse its lead.
    lead = lastDecl.raw ? lastDecl.raw.match(/^\s*/)[0] : (lastDecl.lead ?? ' ');
    if (!multiLine) lead = ' ';
  } else if (multiLine) {
    lead = `\n${(rule.indent ?? (tail ? tail.raw.replace(/^[\s\S]*\n/, '') : '')) + INDENT}`;
  } else {
    lead = ' ';
  }
  const decl = { type: 'declaration', raw: '', property, value, modified: true, lead };

  if (tailIsTrailing) {
    segs.splice(segs.length - 1, 0, decl);
  } else {
    // The body did not end with `;` (e.g. `color:white}`): the new
    // declaration follows the last one, and closes the same way.
    segs.push(decl);
  }
}

// Where a new rule goes: at the end, so existing text is untouched - except
// at the top level when an @media block already styles the same selector.
// Then it goes before that block: a plain rule after a breakpoint would
// override it (same specificity, later wins).
function insertRule(items, rule, inMedia) {
  let at = items.length;
  if (!inMedia) {
    const wanted = normalizeSelector(rule.selector);
    const firstOverride = items.findIndex(r => r.type === 'media' &&
      r.items.some(x => x.type === 'rule' && normalizeSelector(x.selector) === wanted));
    if (firstOverride !== -1) at = firstOverride;
  }
  // Keep trailing whitespace after the new rule.
  while (at > 0 && items[at - 1].type === 'whitespace') at--;
  const before = at === 0 ? (inMedia ? '\n' : '') : '\n\n';
  const hasFollowing = at < items.length;
  const insert = [];
  if (before) insert.push({ type: 'whitespace', raw: before });
  insert.push(rule);
  if (hasFollowing && items[at].type !== 'whitespace') insert.push({ type: 'whitespace', raw: '\n\n' });
  if (!hasFollowing) insert.push({ type: 'whitespace', raw: '\n' });
  items.splice(at, 0, ...insert);
}

// New @media blocks keep max-width breakpoints widest first and min-width
// breakpoints narrowest first: when two match, the more specific one must
// come later to win. Anything else goes at the end.
function placeMediaBlock(items, block) {
  const max = maxWidthOf(block.query);
  const min = minWidthOf(block.query);
  let at = items.length;
  if (max !== null) {
    const i = items.findIndex(r => r.type === 'media' && maxWidthOf(r.query) !== null && maxWidthOf(r.query) < max);
    if (i !== -1) at = i;
  } else if (min !== null) {
    const i = items.findIndex(r => r.type === 'media' && minWidthOf(r.query) !== null && minWidthOf(r.query) > min);
    if (i !== -1) at = i;
  }
  while (at > 0 && at === items.length && items[at - 1].type === 'whitespace') at--;
  const insert = [];
  if (at > 0) insert.push({ type: 'whitespace', raw: '\n\n' });
  insert.push(block);
  if (at < items.length && items[at].type !== 'whitespace') insert.push({ type: 'whitespace', raw: '\n\n' });
  if (at >= items.length) insert.push({ type: 'whitespace', raw: '\n' });
  items.splice(at, 0, ...insert);
}

// Remove an item and the separator in front of it, so no blank-line litter
// is left behind.
function removeItem(items, item) {
  const i = items.indexOf(item);
  if (i === -1) return;
  const prev = items[i - 1];
  const next = items[i + 1];
  if (prev && prev.type === 'whitespace' && (!next || next.type === 'whitespace')) items.splice(i - 1, 2);
  else items.splice(i, 1);
}

// Indentation for a new rule at this level: that of an existing rule, else
// one level inside an @media block.
function ruleIndentFor(items, block) {
  for (let i = 0; i < items.length; i++) {
    if (items[i].type === 'rule') {
      // Indentation is the end of the whitespace before the rule plus any
      // spaces at the start of its own selector text.
      const own = items[i].selectorRaw.match(/^[ \t]*/)[0];
      const prev = items[i - 1];
      const fromWhitespace = prev && prev.type === 'whitespace' && prev.raw.includes('\n')
        ? prev.raw.replace(/^[\s\S]*\n/, '') : '';
      return fromWhitespace + own;
    }
  }
  return block ? INDENT : '';
}

// -----------------------------------------------------------------------------
// Output
// -----------------------------------------------------------------------------

function emitItems(items) {
  let out = '';
  for (const item of items) {
    if (item.type === 'rule') out += item.modified ? emitRule(item) : item.raw;
    else if (item.type === 'media') out += item.modified ? `${item.preludeRaw}{${emitItems(item.items)}}` : item.raw;
    else out += item.raw;
  }
  return out;
}

function emitRule(rule) {
  const body = rule.segments.map(seg => {
    if (seg.type !== 'declaration' || !seg.modified) return seg.raw;
    // Rewritten declaration: keep the original leading whitespace (and any
    // leading comment) and trailing whitespace.
    if (seg.raw) {
      const lead = seg.raw.match(/^(\s*(?:\/\*[\s\S]*?\*\/\s*)*)/)[1];
      const trail = seg.raw.match(/\s*$/)[0];
      return `${lead}${seg.property}: ${seg.value}${trail}`;
    }
    return `${seg.lead ?? ' '}${seg.property}: ${seg.value}`;
  });
  // New declarations are always followed by `;`: join adds it between
  // segments; a new last declaration (body had no trailing `;`) gets none,
  // matching how the rule was written.
  let text = body.join(';');
  if (rule.fresh) {
    // A new rule: "{\n    a: b;\n}" - the trailing segment is "\n<indent>".
    text = rule.segments.length > 1 ? body.slice(0, -1).join(';') + ';' + body[body.length - 1] : body.join(';');
  }
  return `${rule.selectorRaw}{${text}}`;
}

// -----------------------------------------------------------------------------
// Selector and media helpers
// -----------------------------------------------------------------------------

function normalizeSelector(selector) {
  return String(selector || '').trim().replace(/\s+/g, ' ').replace(/\s*([>+~,])\s*/g, '$1');
}

function normalizeMedia(media) {
  return String(media || '').trim().replace(/^@media\s+/i, '').replace(/\s+/g, ' ').replace(/\(\s+/g, '(').replace(/\s+\)/g, ')').replace(/\s*:\s*/g, ': ');
}

function widthOf(query, kind) {
  const m = String(query).match(new RegExp(`^\\(\\s*${kind}-width\\s*:\\s*(\\d*\\.?\\d+)(px|em|rem)?\\s*\\)$`, 'i'));
  if (!m) return null;
  return Number(m[1]) * (m[2] && m[2].toLowerCase() !== 'px' ? 16 : 1);
}

// The px value of a plain `(max-width: N)` / `(min-width: N)` condition, else null.
function maxWidthOf(query) { return widthOf(query, 'max'); }
function minWidthOf(query) { return widthOf(query, 'min'); }

function escapeRegex(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// True when the selector starts with `#id` and the id ends there
// (`#card`, `#card:hover`, `#card .x` - but not `#cardTitle`).
function selectorTargetsId(selector, id) {
  return new RegExp(`^#${escapeRegex(id)}(?![A-Za-z0-9_-])`).test(selector.trim());
}

function replaceId(selector, fromId, toId) {
  return selector.trim().replace(new RegExp(`^#${escapeRegex(fromId)}(?![A-Za-z0-9_-])`), `#${toId}`);
}
