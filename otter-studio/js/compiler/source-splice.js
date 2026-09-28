// source-splice.js - Write designer changes back into an .ot file surgically.
//
// Why this exists
// ---------------
// The designer used to call generateOtterSource(model) after every model
// notification (including a plain selection click) and replace the whole
// editor buffer with the result. The model only knows windows, controls,
// `put` statements and `when` handlers, so everything else in the file -
// functions, variables, comments, blank lines, the author's formatting, and
// properties the model cannot express - was silently deleted.
//
// How it works
// ------------
// 1. When source is read into the model, the caller takes a snapshot of the
//    model (snapshotDesign). That snapshot is the "baseline": the design the
//    current source text describes.
// 2. After a designer change, spliceDesignIntoSource(source, baseline, model)
//    diffs the baseline against the live model, by component id, and turns
//    each difference into the smallest text edit:
//      rename      -> the identifier is renamed where it is used as code
//      remove      -> its declaration, property lines, handlers and `put`
//                     entries are deleted
//      property    -> only that property's phrase is rewritten, added or
//                     removed; every other character of the line stays
//      add         -> one declaration is inserted next to its siblings
//      children    -> only the affected `put` statements are rewritten
//      handler     -> only that `when` block is rewritten, added or removed
//    Positions come from scanOtterSource, the same scanner that built the
//    model, so the splicer and the model agree on what each line means.
// 3. The caller takes a new baseline from the model after writing the result.
//
// Anything the diff does not touch is copied through byte for byte, including
// CRLF line endings.

import { scanOtterSource, splitTopLevelCommas, readPropertyPhrase } from './otter-parser.js';
import { generateOtterSource, declareComponent, formatProperties, formatProperty } from './otter-generator.js';

/**
 * Copy the parts of the model that correspond to source text. Selection and
 * undo history are deliberately left out: they never change the file.
 */
export function snapshotDesign(model) {
  const components = new Map();
  for (const [id, comp] of model.components.entries()) {
    components.set(id, {
      name: comp.name,
      kind: comp.kind,
      parentId: comp.parentId || null,
      children: [...(comp.children || [])],
      properties: { ...(comp.properties || {}) }
    });
  }
  const events = new Map();
  for (const [id, handlers] of model.events.entries()) events.set(id, { ...handlers });
  return { rootId: model.rootId || null, components, events };
}

/**
 * True when the model still describes exactly what `baseline` describes, so
 * there is nothing to write. Used to skip notifications such as 'select'.
 */
export function designMatchesBaseline(baseline, model) {
  if (!baseline) return !model.getRoot();
  return JSON.stringify(serializeForCompare(baseline)) === JSON.stringify(serializeForCompare(snapshotDesign(model)));
}

function serializeForCompare(snapshot) {
  return {
    rootId: snapshot.rootId,
    components: [...snapshot.components.entries()].sort(([a], [b]) => a.localeCompare(b)),
    events: [...snapshot.events.entries()]
      .map(([id, handlers]) => [id, Object.entries(handlers).filter(([, code]) => normalizeBody(code) !== '').sort()])
      .filter(([, handlers]) => handlers.length > 0)
      .sort(([a], [b]) => a.localeCompare(b))
  };
}

/**
 * Apply the difference between `baseline` and `model` to `source`.
 * Returns the new source text (unchanged when nothing differs).
 */
export function spliceDesignIntoSource(source, baseline, model) {
  source = String(source ?? '');
  const root = model.getRoot();

  // No design was read from this file (a new file, or a console program).
  // Never replace the author's program: add the new UI after it instead.
  if (!baseline || !baseline.rootId || !baseline.components.has(baseline.rootId)) {
    if (!root) return source;
    const generated = generateOtterSource(model);
    if (!source.trim()) return generated;
    const buf = new SourceBuffer(source);
    const separator = buf.lines[buf.lines.length - 1].trim() === '' ? [] : [''];
    buf.insert(buf.lines.length, [...separator, ...generated.replace(/\n$/, '').split('\n')]);
    return buf.text();
  }

  const buf = new SourceBuffer(source);
  const current = snapshotDesign(model);

  // Work on a copy of the baseline so it can follow the edits we make
  // (after a rename, later steps must look the component up by its new name).
  const base = {
    rootId: baseline.rootId,
    components: new Map([...baseline.components].map(([id, c]) => [id, { ...c, children: [...c.children], properties: { ...c.properties } }])),
    events: new Map([...baseline.events].map(([id, h]) => [id, { ...h }]))
  };

  applyRenames(buf, base, current);
  applyRemovals(buf, base, current);
  applyPropertyChanges(buf, base, current);
  applyAdditions(buf, base, current);
  applyChildren(buf, current);
  applyEvents(buf, base, current);

  return buf.text();
}

// ---------------------------------------------------------------------------
// Line buffer: edits lines and rescans so positions are always fresh.
// ---------------------------------------------------------------------------

class SourceBuffer {
  constructor(source) {
    this.lines = source.split('\n');
    // New lines copy the file's convention: CRLF files keep CRLF.
    this.cr = source.includes('\r\n') ? '\r' : '';
    this.rescan();
  }

  rescan() {
    this.scan = scanOtterSource(this.lines.join('\n'));
  }

  text() {
    return this.lines.join('\n');
  }

  // Line content without its '\r'.
  get(i) {
    return this.lines[i].replace(/\r$/, '');
  }

  set(i, content) {
    // Keep whether this particular line ended in '\r' (the last line of a
    // file without a final newline does not).
    const cr = this.lines[i].endsWith('\r') ? '\r' : '';
    this.lines[i] = content + cr;
  }

  insert(at, contents) {
    // A line inserted after the file's last line becomes the last line; the
    // old last line now needs the '\r' that the rest of the file uses.
    if (at >= this.lines.length && this.cr && this.lines.length > 0 && !this.lines[this.lines.length - 1].endsWith('\r')) {
      this.lines[this.lines.length - 1] += this.cr;
    }
    const isEnd = at >= this.lines.length;
    const added = contents.map((c, i) => (isEnd && i === contents.length - 1) ? c : c + this.cr);
    this.lines.splice(at, 0, ...added);
    this.rescan();
  }

  // Remove the given line indexes (any order, duplicates allowed).
  removeLines(indexes) {
    const unique = [...new Set(indexes)].filter(i => i >= 0 && i < this.lines.length).sort((a, b) => b - a);
    for (const i of unique) this.lines.splice(i, 1);
    this.rescan();
  }
}

function indentOf(line) {
  return (line.match(/^[ \t]*/) || [''])[0];
}

// ---------------------------------------------------------------------------
// Renames
// ---------------------------------------------------------------------------

function applyRenames(buf, base, current) {
  const renames = [];
  for (const [id, comp] of current.components) {
    const before = base.components.get(id);
    if (before && before.name !== comp.name) renames.push({ id, from: before.name, to: comp.name });
  }
  if (renames.length === 0) return;

  // Two phases through unique temporary names, so swapping two names
  // (a -> b, b -> a) cannot merge them.
  let text = buf.text();
  renames.forEach((r, i) => { r.temp = `__otterStudioRename${i}__`; text = renameIdentifier(text, r.from, r.temp); });
  renames.forEach(r => { text = renameIdentifier(text, r.temp, r.to); base.components.get(r.id).name = r.to; });

  buf.lines = text.split('\n');
  buf.rescan();
}

/**
 * Replace whole-word uses of identifier `from` with `to`, skipping string
 * literals and `#` comments. Renaming a control in the designer should rename
 * the code that uses it (`text of saveButton`), not just its declaration,
 * otherwise the program no longer runs.
 */
export function renameIdentifier(text, from, to) {
  const isWordChar = ch => /[A-Za-z0-9_]/.test(ch || '');
  let out = '';
  let i = 0;
  let inString = false;
  let inComment = false;
  while (i < text.length) {
    const ch = text[i];
    if (inComment) {
      out += ch;
      if (ch === '\n') inComment = false;
      i++;
      continue;
    }
    if (inString) {
      out += ch;
      if (ch === '\\' && i + 1 < text.length) { out += text[i + 1]; i += 2; continue; }
      if (ch === '"' || ch === '\n') inString = false;
      i++;
      continue;
    }
    if (ch === '"') { inString = true; out += ch; i++; continue; }
    if (ch === '#') { inComment = true; out += ch; i++; continue; }
    if (text.startsWith(from, i) && !isWordChar(text[i - 1]) && !isWordChar(text[i + from.length])) {
      out += to;
      i += from.length;
      continue;
    }
    out += ch;
    i++;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Removals
// ---------------------------------------------------------------------------

function applyRemovals(buf, base, current) {
  const removedNames = [];
  for (const [id, comp] of base.components) {
    if (!current.components.has(id)) removedNames.push(comp.name);
  }
  if (removedNames.length === 0) return;

  const removed = new Set(removedNames);
  const scan = buf.scan;
  const doomed = [];

  for (const name of removedNames) {
    const comp = scan.components.get(name);
    if (comp) {
      for (let l = comp.declLine; l <= comp.endLine; l++) doomed.push(l);
      for (const range of comp.hasRanges) for (let l = range.start; l <= range.end; l++) doomed.push(l);
      for (const site of comp.sites) if (site.type === 'propOf') doomed.push(site.line);
    }
    for (const when of scan.whens) {
      if (when.name === name) for (let l = when.start; l <= when.end; l++) doomed.push(l);
    }
  }

  // Take removed names out of `put` statements; drop a `put` left empty.
  for (const put of scan.puts) {
    if (removed.has(put.container)) { doomed.push(put.line); continue; }
    const kept = put.items.filter(item => !removed.has(item));
    if (kept.length === put.items.length) continue;
    if (kept.length === 0) doomed.push(put.line);
    else buf.set(put.line, `${indentOf(buf.get(put.line))}put ${kept.join(', ')} in ${put.container}`);
  }

  buf.removeLines(doomed);
}

// ---------------------------------------------------------------------------
// Property changes
// ---------------------------------------------------------------------------

function sameValue(a, b) {
  return a === b || (a == null && b == null);
}

function applyPropertyChanges(buf, base, current) {
  for (const [id, comp] of current.components) {
    const before = base.components.get(id);
    if (!before) continue;

    if (before.kind !== comp.kind) setComponentKind(buf, comp.name, comp.kind);

    const keys = new Set([...Object.keys(before.properties), ...Object.keys(comp.properties)]);
    for (const key of keys) {
      if (sameValue(before.properties[key], comp.properties[key])) continue;
      setComponentProperty(buf, comp.name, key, comp.properties[key]);
    }
  }
}

function setComponentKind(buf, name, kind) {
  const comp = buf.scan.components.get(name);
  if (!comp || comp.form === 'create') return;
  const line = buf.get(comp.declLine);
  const re = new RegExp(`(\\bis\\s+an?\\s+)${comp.rawKind.replace(/\s+/g, '\\s+')}\\b`, 'i');
  buf.set(comp.declLine, line.replace(re, `$1${kind}`));
  buf.rescan();
}

/**
 * The text a property site should hold after the change, in the site's own
 * style: its key spelling (`value` stays `value`) and its `is` if it had one.
 */
function phraseForSite(site, key, formatted) {
  if (formatted === key || !formatted.startsWith(key)) return formatted; // flags: `spread`, `round`
  const rest = formatted.slice(key.length); // e.g. ` "Save"`
  return `${site.rawKey}${site.usesIs ? ' is' : ''}${rest}`;
}

function valueTextOf(key, formatted) {
  if (formatted === key) return 'true';
  return formatted.startsWith(key) ? formatted.slice(key.length).trim() : formatted;
}

export function setComponentProperty(buf, name, key, value) {
  const comp = buf.scan.components.get(name);
  if (!comp) return;
  const formatted = formatProperty(key, value);
  const sites = comp.sites.filter(s => s.key === key);

  if (formatted === null) {
    // Remove every place the property is written, last first so earlier
    // positions stay valid; rescan between removals.
    for (let n = sites.length; n > 0; n--) {
      const fresh = buf.scan.components.get(name).sites.filter(s => s.key === key);
      removeSite(buf, name, fresh[fresh.length - 1]);
    }
    return;
  }

  if (sites.length > 0) {
    // The last site is the one that takes effect; rewrite just that one.
    replaceSite(buf, comp, sites[sites.length - 1], key, formatted);
    return;
  }
  addSite(buf, comp, key, formatted);
}

function replaceSite(buf, comp, site, key, formatted) {
  const line = buf.get(site.line);
  const indent = indentOf(line);
  if (site.type === 'line') {
    buf.set(site.line, indent + phraseForSite(site, key, formatted));
  } else if (site.type === 'propOf') {
    buf.set(site.line, `${indent}${site.rawKey} of ${comp.name} is ${valueTextOf(key, formatted)}`);
  } else {
    editSegments(buf, site.line, site.listStart, comp.kind, parts => {
      const j = lastIndexWhere(parts, p => p.key === key);
      if (j !== -1) parts[j].phrase = phraseForSite(site, key, formatted);
      return parts;
    });
  }
  buf.rescan();
}

function removeSite(buf, name, site) {
  if (!site) return;
  const comp = buf.scan.components.get(name);
  if (site.type === 'line' || site.type === 'propOf') {
    buf.removeLines([site.line]);
    return;
  }

  let emptied = false;
  editSegments(buf, site.line, site.listStart, comp.kind, parts => {
    const j = lastIndexWhere(parts, p => p.key === site.key);
    if (j !== -1) parts.splice(j, 1);
    emptied = parts.length === 0;
    return parts;
  });

  if (!emptied) { buf.rescan(); return; }

  if (site.line === comp.declLine) {
    // `x is a k with p` lost its last property. A bare `x is a k` opens a
    // block, so write the block form with its terminator instead.
    const line = buf.get(site.line);
    const withAt = line.search(/\s+with\s*$/i);
    const head = withAt === -1 ? line.replace(/\s+$/, '') : line.slice(0, withAt);
    buf.set(site.line, head);
    buf.insert(site.line + 1, [`${indentOf(line)}.`]);
  } else {
    // An inline `x has ...` line with nothing left.
    buf.removeLines([site.line]);
  }
}

/**
 * Rewrite the comma list on one line. `edit` receives the parts as
 * [{ key, phrase, lead, trail }] and returns the parts to keep; untouched
 * parts keep their exact original text and spacing.
 */
function editSegments(buf, lineIndex, listStart, kind, edit) {
  const line = buf.get(lineIndex);
  if (listStart < 0) return;

  const head = line.slice(0, listStart);
  const list = line.slice(listStart);
  const parts = splitTopLevelCommas(list).map(p => {
    const lead = (p.text.match(/^\s*/) || [''])[0];
    const trail = (p.text.match(/\s*$/) || [''])[0];
    const phrase = p.text.trim();
    const read = readPropertyPhrase(phrase, kind);
    return { key: read ? read.key : null, phrase, lead, trail };
  });

  const kept = edit(parts);
  const rebuilt = kept.map((p, i) => {
    // The first part never starts with the space that followed a comma.
    const lead = i === 0 ? '' : (p.lead || ' ');
    return lead + p.phrase + (i === kept.length - 1 ? p.trail : '');
  }).join(',');
  buf.set(lineIndex, head + rebuilt);
}

function lastIndexWhere(items, test) {
  for (let i = items.length - 1; i >= 0; i--) if (test(items[i])) return i;
  return -1;
}

function addSite(buf, comp, key, formatted) {
  // A comma list already exists (`x is a k with ...` or `x has ...`): append.
  if (comp.listLine >= 0) {
    editSegments(buf, comp.listLine, comp.listStart, comp.kind, parts => [...parts, { key, phrase: formatted, lead: ' ', trail: '' }]);
    buf.rescan();
    return;
  }

  if (comp.form === 'block' && comp.endLine > comp.declLine) {
    // Insert a property line just before the block's `.`, in the style of
    // the lines already there (`title is "x"` in Otter's documentation style).
    const lineSites = comp.sites.filter(s => s.type === 'line');
    const last = lineSites[lineSites.length - 1];
    const indent = last ? indentOf(buf.get(last.line)) : indentOf(buf.get(comp.declLine)) + '    ';
    const usesIs = last ? last.usesIs : true;
    const phrase = phraseForSite({ rawKey: key, usesIs }, key, formatted);
    buf.insert(comp.endLine, [indent + phrase]);
    return;
  }

  if (comp.form === 'block') {
    // An unterminated `x is a k`: give it an inline list.
    buf.set(comp.declLine, `${buf.get(comp.declLine).replace(/\s+$/, '')} with ${formatted}`);
    buf.rescan();
    return;
  }

  // Legacy `create k into x`: add `key of x is value` after its last line.
  const lastLine = Math.max(comp.declLine, ...comp.sites.map(s => s.line));
  const indent = indentOf(buf.get(comp.declLine));
  buf.insert(lastLine + 1, [`${indent}${key} of ${comp.name} is ${valueTextOf(key, formatted)}`]);
}

// ---------------------------------------------------------------------------
// Additions
// ---------------------------------------------------------------------------

function preOrder(snapshot) {
  const out = [];
  const visit = id => {
    const comp = snapshot.components.get(id);
    if (!comp) return;
    out.push(id);
    for (const child of comp.children) visit(child);
  };
  visit(snapshot.rootId);
  return out;
}

// Last line of `id`'s declaration or of any declared descendant's.
function lastDeclaredLine(buf, snapshot, id) {
  const comp = snapshot.components.get(id);
  if (!comp) return -1;
  const scanned = buf.scan.components.get(comp.name);
  let last = scanned ? scanned.endLine : -1;
  for (const child of comp.children) last = Math.max(last, lastDeclaredLine(buf, snapshot, child));
  return last;
}

function applyAdditions(buf, base, current) {
  for (const id of preOrder(current)) {
    if (base.components.has(id)) continue;
    const comp = current.components.get(id);
    if (buf.scan.components.has(comp.name)) continue; // already written

    // Place it after its previous sibling (and that sibling's children),
    // else after its parent, else after the last declaration in the file.
    const parent = current.components.get(comp.parentId);
    let anchor = -1;
    if (parent) {
      const siblings = parent.children;
      for (let i = siblings.indexOf(id) - 1; i >= 0 && anchor === -1; i--) {
        anchor = lastDeclaredLine(buf, current, siblings[i]);
      }
      if (anchor === -1) {
        const parentDecl = buf.scan.components.get(parent.name);
        if (parentDecl) anchor = parentDecl.endLine;
      }
    }
    if (anchor === -1) {
      for (const c of buf.scan.components.values()) anchor = Math.max(anchor, c.endLine);
    }

    // Match the neighbouring style: block declarations get a block.
    const neighbour = [...buf.scan.components.values()].find(c => c.endLine === anchor);
    const indent = neighbour ? indentOf(buf.get(neighbour.declLine)) : '';
    let text;
    if (neighbour && neighbour.form === 'block' && neighbour.endLine > neighbour.declLine) {
      const props = formatProperties(comp.properties).map(p => `${indent}    ${phraseForSite({ rawKey: p.split(' ')[0], usesIs: true }, p.split(' ')[0], p)}`);
      text = ['', `${indent}${comp.name} is a ${comp.kind}`, ...props, `${indent}.`];
    } else {
      text = [indent + declareComponent(comp.name, comp.kind, formatProperties(comp.properties))];
    }
    buf.insert(anchor === -1 ? buf.lines.length : anchor + 1, text);
    base.components.set(id, { ...comp, children: [...comp.children], properties: { ...comp.properties } });
  }
}

// ---------------------------------------------------------------------------
// Children (`put` statements)
// ---------------------------------------------------------------------------

function sameList(a, b) {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

function applyChildren(buf, current) {
  const modelNames = new Set([...current.components.values()].map(c => c.name));

  for (const id of preOrder(current)) {
    const container = current.components.get(id);
    const wanted = container.children.map(c => current.components.get(c)?.name).filter(Boolean);
    const puts = buf.scan.puts.filter(p => p.container === container.name);
    const written = puts.flatMap(p => p.items);
    const writtenKnown = written.filter(item => modelNames.has(item));
    if (sameList(writtenKnown, wanted)) continue;

    // Names the designer does not know about (a variable holding a control
    // built in code, say) stay where they were in the list.
    const merged = [...wanted];
    written.forEach((item, index) => {
      if (!modelNames.has(item)) merged.splice(Math.min(index, merged.length), 0, item);
    });

    // A `put` must come after the declarations of everything it places.
    const lastChildDecl = Math.max(-1, ...wanted.map(n => buf.scan.components.get(n)?.endLine ?? -1));

    if (puts.length === 0) {
      if (merged.length === 0) continue;
      const intoParent = buf.scan.puts.find(p => p.items.includes(container.name));
      const lastPut = buf.scan.puts[buf.scan.puts.length - 1];
      let at = intoParent ? intoParent.line : (lastPut ? lastPut.line + 1 : lastChildDecl + 1);
      if (at <= lastChildDecl) at = lastChildDecl + 1;
      const ref = intoParent || lastPut;
      const indent = ref ? indentOf(buf.get(ref.line)) : '';
      buf.insert(at, [`${indent}put ${merged.join(', ')} in ${container.name}`]);
      continue;
    }

    const keep = puts[puts.length - 1];
    const indent = indentOf(buf.get(keep.line));
    const others = puts.slice(0, -1).map(p => p.line);
    if (merged.length === 0) {
      buf.removeLines([...others, keep.line]);
    } else if (keep.line > lastChildDecl) {
      buf.set(keep.line, `${indent}put ${merged.join(', ')} in ${container.name}`);
      buf.removeLines(others);
    } else {
      // A child is now declared after this `put`: move the statement down.
      buf.removeLines([...others, keep.line]);
      const shift = [...others, keep.line].filter(l => l <= lastChildDecl).length;
      buf.insert(lastChildDecl - shift + 1, [`${indent}put ${merged.join(', ')} in ${container.name}`]);
    }
  }
}

// ---------------------------------------------------------------------------
// Event handlers (`when x is clicked` ... `.`)
// ---------------------------------------------------------------------------

function normalizeBody(code) {
  return typeof code === 'string' && code.trim() !== '' ? code.replace(/\r/g, '') : '';
}

function formatBody(code, indent) {
  const lines = normalizeBody(code).split('\n');
  while (lines.length && !lines[0].trim()) lines.shift();
  while (lines.length && !lines[lines.length - 1].trim()) lines.pop();
  const common = Math.min(...lines.filter(l => l.trim()).map(l => indentOf(l).length));
  return lines.map(l => (l.trim() ? indent + l.slice(common) : ''));
}

function applyEvents(buf, base, current) {
  for (const [id, comp] of current.components) {
    const before = base.events.get(id) || {};
    const after = current.events.get(id) || {};
    const kinds = new Set([...Object.keys(before), ...Object.keys(after)]);

    for (const kind of kinds) {
      const oldBody = normalizeBody(before[kind]);
      const newBody = normalizeBody(after[kind]);
      if (oldBody === newBody) continue;

      const blocks = buf.scan.whens.filter(w => w.name === comp.name && w.eventKind === kind);
      const block = blocks[blocks.length - 1];

      if (!newBody) {
        if (!block) continue;
        const doomed = [];
        for (let l = block.start; l <= block.end; l++) doomed.push(l);
        // Also drop the blank line that separated the block, if it leaves two.
        if (buf.get(block.end + 1)?.trim() === '' && buf.get(block.start - 1)?.trim() === '') doomed.push(block.end + 1);
        buf.removeLines(doomed);
        continue;
      }

      if (block) {
        const headerIndent = indentOf(buf.get(block.start));
        const body = formatBody(newBody, headerIndent + '    ');
        buf.lines.splice(block.start + 1, block.end - block.start - 1, ...body.map(l => l + buf.cr));
        buf.rescan();
        continue;
      }

      // New handler: before `show <window>` when there is one, else at the end.
      const show = buf.scan.showLines[0];
      const blockLines = [`when ${comp.name} is ${kind}`, ...formatBody(newBody, '    '), '.', ''];
      if (show) {
        buf.insert(show.line, blockLines);
      } else {
        const separator = buf.lines.length && buf.get(buf.lines.length - 1).trim() !== '' ? [''] : [];
        buf.insert(buf.lines.length, [...separator, ...blockLines.slice(0, -1)]);
      }
    }
  }
}
