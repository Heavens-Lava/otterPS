// css-ast.js - Lossless CSS AST parser and surgical manipulator
//
// Keeps comments, rule order, custom properties (--var) and unknown rules.
// Understands the parts of CSS the designer writes:
//   - plain rules            #card { ... }
//   - state rules            #card:hover { ... }
//   - @media blocks          @media (max-width: 900px) { #card { ... } }
// Any other at-rule (@keyframes, @font-face, @supports, @import ...) is kept
// verbatim, so a hand-written stylesheet survives a designer edit unchanged.
//
// Every method takes an optional `media` argument: '' (or omitted) means the
// top level, otherwise the exact media condition text, e.g. '(max-width: 900px)'.

export class CssAstManager {
  constructor(cssText = '') {
    this.rawText = cssText;
    this.rules = [];
    this.parse(cssText);
  }

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  parse(cssText) {
    this.rawText = cssText || '';
    this.rules = parseBlockItems(this.rawText);
  }

  parseDeclarations(bodyText) {
    return parseDeclarations(bodyText);
  }

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  // The list of items a selector lives in: the top level or one @media block.
  itemsFor(media = '', create = false) {
    const query = normalizeMedia(media);
    if (!query) return this.rules;
    let block = this.rules.find(r => r.type === 'media' && normalizeMedia(r.query) === query);
    if (!block && create) {
      block = { type: 'media', query, rules: [] };
      // Keep max-width breakpoints widest first. When both match (a phone
      // matches 900px and 600px), the narrower one must come later to win.
      const width = maxWidthOf(query);
      const before = width === null ? -1 : this.rules.findIndex(r =>
        r.type === 'media' && maxWidthOf(r.query) !== null && maxWidthOf(r.query) < width);
      if (before === -1) this.rules.push(block);
      else this.rules.splice(before, 0, block);
    }
    return block ? block.rules : null;
  }

  findRule(selector, media = '') {
    const items = this.itemsFor(media);
    if (!items) return null;
    const wanted = normalizeSelector(selector);
    return items.find(r => r.type === 'rule' && normalizeSelector(r.selector) === wanted) || null;
  }

  getProperty(selector, property, media = '') {
    const rule = this.findRule(selector, media);
    if (!rule) return null;
    const wanted = property.toLowerCase();
    // The last declaration wins in CSS, so search from the end.
    for (let i = rule.declarations.length - 1; i >= 0; i--) {
      const d = rule.declarations[i];
      if (d.type === 'declaration' && d.property.toLowerCase() === wanted) return d.value;
    }
    return null;
  }

  getRuleDeclarations(selector, media = '') {
    const rule = this.findRule(selector, media);
    if (!rule) return {};
    const map = {};
    for (const d of rule.declarations) {
      if (d.type === 'declaration') map[d.property.toLowerCase()] = d.value;
    }
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
          for (const d of item.declarations) {
            if (d.type !== 'declaration') continue;
            for (const match of d.value.match(colorPattern) || []) {
              const key = match.replace(/\s+/g, ' ').toLowerCase();
              counts.set(key, (counts.get(key) || 0) + 1);
            }
          }
        } else if (item.type === 'media') {
          visit(item.rules);
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
    const items = this.itemsFor(media, !remove);
    if (!items) return;

    const wanted = normalizeSelector(selector);
    let rule = items.find(r => r.type === 'rule' && normalizeSelector(r.selector) === wanted);
    if (!rule) {
      if (remove) return;
      rule = { type: 'rule', selector: selector.trim(), declarations: [] };
      insertRule(items, rule);
    }

    const propLower = property.toLowerCase();
    const existing = rule.declarations.filter(d => d.type === 'declaration' && d.property.toLowerCase() === propLower);

    if (remove) {
      rule.declarations = rule.declarations.filter(d => !existing.includes(d));
    } else if (existing.length > 0) {
      // Keep the first occurrence in place, drop duplicates that would override it.
      existing[0].value = String(value);
      rule.declarations = rule.declarations.filter(d => d === existing[0] || !existing.includes(d));
    } else {
      rule.declarations.push({ type: 'declaration', property, value: String(value) });
    }

    this.pruneEmpty(items, rule, media);
  }

  removeProperty(selector, property, media = '') {
    this.setProperty(selector, property, null, media);
  }

  // Drop a rule that has no declarations left, and an @media block with no
  // rules left, so the designer never leaves empty `#x { }` litter behind.
  pruneEmpty(items, rule, media) {
    if (rule && rule.declarations.length === 0) {
      const idx = items.indexOf(rule);
      if (idx >= 0) items.splice(idx, 1);
    }
    const query = normalizeMedia(media);
    if (query) {
      const block = this.rules.find(r => r.type === 'media' && normalizeMedia(r.query) === query);
      if (block && !block.rules.some(r => r.type === 'rule' || r.type === 'at')) {
        this.rules.splice(this.rules.indexOf(block), 1);
      }
    }
  }

  // Remove every rule (at any level) whose selector targets `#id`, including
  // its states (`#id:hover`). Used when a component is deleted.
  removeSelectorFamily(id) {
    const visit = (items) => {
      for (let i = items.length - 1; i >= 0; i--) {
        const item = items[i];
        if (item.type === 'rule' && selectorTargetsId(item.selector, id)) items.splice(i, 1);
        else if (item.type === 'media') {
          visit(item.rules);
          if (!item.rules.some(r => r.type === 'rule' || r.type === 'at')) items.splice(i, 1);
        }
      }
    };
    visit(this.rules);
  }

  // Copy every rule for `#fromId` (states and breakpoints included) onto `#toId`.
  copySelectorFamily(fromId, toId) {
    const copies = [];
    const visit = (items, media) => {
      for (const item of items) {
        if (item.type === 'rule' && selectorTargetsId(item.selector, fromId)) {
          copies.push({ media, selector: replaceId(item.selector, fromId, toId), declarations: item.declarations });
        } else if (item.type === 'media') {
          visit(item.rules, item.query);
        }
      }
    };
    visit(this.rules, '');
    for (const copy of copies) {
      for (const d of copy.declarations) {
        if (d.type === 'declaration') this.setProperty(copy.selector, d.property, d.value, copy.media);
      }
    }
  }

  // Rename `#oldId` to `#newId` in every selector, in place.
  renameSelectorFamily(oldId, newId) {
    const visit = (items) => {
      for (const item of items) {
        if (item.type === 'rule' && selectorTargetsId(item.selector, oldId)) {
          item.selector = replaceId(item.selector, oldId, newId);
        } else if (item.type === 'media') {
          visit(item.rules);
        }
      }
    };
    visit(this.rules);
  }

  // ---------------------------------------------------------------------------
  // Output
  // ---------------------------------------------------------------------------

  // One blank line between top-level items; comments and unknown rules kept.
  // The output is stable: parse(generateCss()) then generateCss() is identical.
  generateCss() {
    const out = emitItems(this.rules, '');
    return out.trim() ? out.trim() + '\n' : '';
  }
}

// -----------------------------------------------------------------------------
// Parser helpers
// -----------------------------------------------------------------------------

function parseBlockItems(text) {
  const items = [];
  let i = 0;
  const len = text.length;

  while (i < len) {
    const ch = text[i];

    if (/\s/.test(ch)) { i++; continue; }

    if (text.startsWith('/*', i)) {
      const end = text.indexOf('*/', i + 2);
      const stop = end === -1 ? len : end + 2;
      items.push({ type: 'comment', raw: text.slice(i, stop) });
      i = stop;
      continue;
    }

    // A statement at-rule with no block: @import url(x); @charset "utf-8";
    if (ch === '@') {
      const semi = findTopLevel(text, i, ';');
      const brace = findTopLevel(text, i, '{');
      if (semi !== -1 && (brace === -1 || semi < brace)) {
        items.push({ type: 'at', raw: text.slice(i, semi + 1).trim() });
        i = semi + 1;
        continue;
      }
    }

    const open = findTopLevel(text, i, '{');
    if (open === -1) {
      const remainder = text.slice(i).trim();
      if (remainder) items.push({ type: 'raw', raw: remainder });
      break;
    }
    const close = findMatchingBrace(text, open);
    if (close === -1) {
      items.push({ type: 'raw', raw: text.slice(i).trim() });
      break;
    }

    const prelude = text.slice(i, open).trim();
    const body = text.slice(open + 1, close);

    const mediaMatch = prelude.match(/^@media\s+([\s\S]+)$/i);
    if (mediaMatch) {
      items.push({ type: 'media', query: mediaMatch[1].trim(), rules: parseBlockItems(body) });
    } else if (prelude.startsWith('@')) {
      items.push({ type: 'at', raw: text.slice(i, close + 1).trim() });
    } else {
      items.push({ type: 'rule', selector: prelude, declarations: parseDeclarations(body) });
    }
    i = close + 1;
  }

  return items;
}

// Split a declaration block on top-level `;`, ignoring semicolons inside
// strings, parentheses (url(data:...;base64,...)) and comments.
function parseDeclarations(bodyText) {
  const decls = [];
  const text = bodyText || '';
  let start = 0;
  let i = 0;
  let depth = 0;
  let quote = null;

  const flush = (end) => {
    const part = text.slice(start, end).trim();
    start = end + 1;
    if (!part) return;
    // Standalone comments become their own entries; a comment glued to a
    // declaration stays with it.
    let rest = part;
    while (rest.startsWith('/*')) {
      const endComment = rest.indexOf('*/');
      if (endComment === -1) break;
      decls.push({ type: 'comment', raw: rest.slice(0, endComment + 2) });
      rest = rest.slice(endComment + 2).trim();
    }
    if (!rest) return;
    const colon = rest.indexOf(':');
    if (colon === -1) {
      decls.push({ type: 'raw', raw: rest });
      return;
    }
    decls.push({
      type: 'declaration',
      property: rest.slice(0, colon).trim(),
      value: rest.slice(colon + 1).trim()
    });
  };

  while (i < text.length) {
    const ch = text[i];
    if (quote) {
      if (ch === '\\') { i += 2; continue; }
      if (ch === quote) quote = null;
    } else if (text.startsWith('/*', i)) {
      const end = text.indexOf('*/', i + 2);
      i = end === -1 ? text.length : end + 2;
      continue;
    } else if (ch === '"' || ch === "'") {
      quote = ch;
    } else if (ch === '(') {
      depth++;
    } else if (ch === ')') {
      depth = Math.max(0, depth - 1);
    } else if (ch === ';' && depth === 0) {
      flush(i);
    }
    i++;
  }
  flush(text.length);
  return decls;
}

function findTopLevel(text, from, target) {
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
      if (end === -1) return -1;
      i = end + 1;
      continue;
    }
    if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '(') depth++;
    else if (ch === ')') depth = Math.max(0, depth - 1);
    else if (ch === target && depth === 0) return i;
  }
  return -1;
}

function findMatchingBrace(text, open) {
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
// Output and selector helpers
// -----------------------------------------------------------------------------

function emitItems(items, indent) {
  const blocks = [];
  for (const item of items) {
    if (item.type === 'comment' || item.type === 'raw' || item.type === 'at') {
      blocks.push(indentText(item.raw, indent));
    } else if (item.type === 'rule') {
      const inner = indent + '    ';
      const lines = [`${indent}${item.selector} {`];
      for (const d of item.declarations) {
        if (d.type === 'declaration') lines.push(`${inner}${d.property}: ${d.value};`);
        else if (d.type === 'comment') lines.push(`${inner}${d.raw}`);
        else if (d.type === 'raw') lines.push(`${inner}${d.raw};`);
      }
      lines.push(`${indent}}`);
      blocks.push(lines.join('\n'));
    } else if (item.type === 'media') {
      const body = emitItems(item.rules, indent + '    ').replace(/\n+$/, '');
      blocks.push(`${indent}@media ${item.query} {\n${body}\n${indent}}`);
    }
  }
  return blocks.join('\n\n') + (blocks.length ? '\n' : '');
}

function indentText(text, indent) {
  if (!indent) return text;
  return text.split('\n').map(line => indent + line.replace(/^\s+/, '')).join('\n');
}

// New rules go after the last existing rule, keeping trailing comments last.
// At the top level they go before the first @media block: a plain rule that
// came after a breakpoint would override it (same specificity, later wins).
function insertRule(items, rule) {
  const firstMedia = items.findIndex(r => r.type === 'media');
  let idx = firstMedia === -1 ? items.length : firstMedia;
  while (idx > 0 && items[idx - 1].type === 'comment') idx--;
  // A leading file comment (idx 0) should stay above rules.
  if (idx === 0 && items.length > 0 && firstMedia === -1) idx = items.length;
  items.splice(idx, 0, rule);
}

function normalizeSelector(selector) {
  return String(selector || '').trim().replace(/\s+/g, ' ').replace(/\s*([>+~,])\s*/g, '$1');
}

function normalizeMedia(media) {
  return String(media || '').trim().replace(/^@media\s+/i, '').replace(/\s+/g, ' ').replace(/\(\s+/g, '(').replace(/\s+\)/g, ')').replace(/\s*:\s*/g, ': ');
}

// The px value of a plain `(max-width: N)` condition, else null.
function maxWidthOf(query) {
  const m = String(query).match(/^\(\s*max-width\s*:\s*(\d*\.?\d+)(px|em|rem)?\s*\)$/i);
  if (!m) return null;
  return Number(m[1]) * (m[2] && m[2].toLowerCase() !== 'px' ? 16 : 1);
}

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
