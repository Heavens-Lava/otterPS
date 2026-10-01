// otter-parser.js - In-browser parser for bidirectional sync (Code -> UI Model)
//
// The reader works in two steps:
//
//   scanOtterSource(source)  -> a description of the UI statements in the file
//                               AND the exact lines/characters each one occupies
//   parseOtterSource(source, model) -> scans, then rebuilds the designer model
//
// The positions matter. The designer used to regenerate the whole .ot file
// from the model after every click, which threw away everything the model does
// not represent (functions, variables, comments, formatting). The splicer in
// source-splice.js now uses these positions to rewrite only the statements a
// designer change actually affects. That only works if the splicer and the
// model agree on what each line means, so both are driven by this one scanner.

import { ComponentSchema, KindAliases } from '../model/schema.js';

// Each statement pattern the designer understands. `(?:the\s+)?` allows the
// optional article Otter permits in front of a name.
const CREATE_RE = /^create\s+(?:the\s+)?([a-zA-Z0-9\s]+?)\s+into\s+(?:the\s+)?([a-zA-Z0-9_]+)$/i;
const DECLARE_RE = /^(?:the\s+)?([a-zA-Z0-9_]+)\s+is\s+a\s+(.+)$/i;
const HAS_BLOCK_RE = /^(?:the\s+)?([a-zA-Z0-9_]+)\s+has$/i;
const HAS_INLINE_RE = /^(?:the\s+)?([a-zA-Z0-9_]+)\s+has\s+(.+)$/i;
const PROP_OF_RE = /^(?:the\s+)?([a-zA-Z0-9_]+)\s+of\s+(?:the\s+)?([a-zA-Z0-9_]+)\s+is\s+(.+)$/i;
const PUT_RE = /^put\s+(.+?)\s+in\s+(?:the\s+)?([a-zA-Z0-9_]+)$/i;
const WHEN_RE = /^when\s+(?:the\s+)?([a-zA-Z0-9_]+)\s+(?:is\s+)?([a-zA-Z0-9_]+)$/i;
const SHOW_RE = /^show\s+(?:the\s+)?([a-zA-Z0-9_]+)\s*$/i;

/**
 * Split `a 1, b "x, y", c` on the commas that are NOT inside a string.
 * The old reader used a plain split(','), which cut `customstyle "a, b"` in
 * half; once the designer wrote the model back, the file got the broken
 * halves as two bogus properties.
 * Returns [{ text, start }] where start is the part's offset in `list`.
 */
export function splitTopLevelCommas(list) {
  const parts = [];
  let inString = false;
  let partStart = 0;
  for (let i = 0; i < list.length; i++) {
    const ch = list[i];
    if (inString) {
      if (ch === '\\') i++;           // skip the escaped character
      else if (ch === '"') inString = false;
    } else if (ch === '"') {
      inString = true;
    } else if (ch === ',') {
      parts.push({ text: list.slice(partStart, i), start: partStart });
      partStart = i + 1;
    }
  }
  parts.push({ text: list.slice(partStart), start: partStart });
  return parts;
}

/**
 * Read one property phrase (`text "Save"`, `width is 400`, `spread`).
 * Returns { key, rawKey, value, usesIs } or null when the phrase is not a
 * property. `key` is the model's name for it; `rawKey` is the spelling in the
 * source, so a rewrite keeps `value` where the author wrote `value`.
 */
export function readPropertyPhrase(text, kind = '') {
  const trimmed = text.trim();
  const lower = trimmed.toLowerCase();
  if (lower === 'spread') return { key: 'spread', rawKey: trimmed, value: true, usesIs: false };
  // A bare `round` is a flag: ordinary 8px corners (a pill is `pill true`).
  if (lower === 'round') return { key: 'round', rawKey: trimmed, value: true, usesIs: false };

  const match = trimmed.match(/^([a-zA-Z0-9_]+)\s+(is\s+)?(.+)$/);
  if (!match) return null;
  const rawKey = match[1];
  let key = rawKey.toLowerCase();
  // Current Otter Web examples use both `value` and `text` for visible
  // text. Studio's internal text component uses `text`, so preserve the
  // visual result when reading a real declarative source file.
  if (key === 'value' && ['text', 'heading', 'badge'].includes(kind)) key = 'text';
  return { key, rawKey, value: parseValue(match[3].trim()), usesIs: Boolean(match[2]) };
}

/**
 * Scan source for the UI statements the designer understands.
 *
 * Returned shape (line numbers are 0-based indexes into `lines`):
 *   lines       the source split on '\n' (a '\r' stays on the end of its line)
 *   components  Map name -> { name, kind, rawKind, declLine, endLine, form,
 *                             sites, properties, listLine, listStart }
 *                 form: 'inline' (`x is a k with ...`), 'block' (`x is a k`,
 *                 property lines, `.`) or 'create' (legacy create ... into)
 *                 sites: every place a property is written for the
 *                 component: { key, rawKey, value, usesIs, line, type }
 *                 where type is 'segment' (one item of a comma list on
 *                 `listLine` starting at column `listStart`), 'line' (a whole
 *                 line inside a block) or 'propOf' (`k of x is v`)
 *                 hasRanges: legacy `x has ...` lines and blocks [{ start, end }]
 *   puts        [{ line, container, items: [name] }]
 *   whens       [{ name, eventKind, start, end, body }]  (end = its `.` line)
 *   showLines   [{ line, name }]
 */
export function scanOtterSource(source) {
  const lines = String(source ?? '').split('\n');
  const components = new Map();
  const puts = [];
  const whens = [];
  const showLines = [];

  let block = null; // the open `... .` block: { type, name, start, lines }

  // Record the properties written as a comma list on one line.
  const addSegments = (comp, lineIndex, listStart) => {
    const list = lines[lineIndex].replace(/\r$/, '').slice(listStart);
    comp.listLine = lineIndex;
    comp.listStart = listStart;
    for (const part of splitTopLevelCommas(list)) {
      const phrase = readPropertyPhrase(part.text, comp.kind);
      if (phrase) comp.sites.push({ ...phrase, line: lineIndex, type: 'segment', listStart });
    }
  };

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i].replace(/\r$/, '');
    const line = rawLine.trim();

    // Skip empty lines or top-level comments
    if (!line || (line.startsWith('#') && !block)) continue;

    // Only the program's own top level is the design: a line indented
    // outside a block the designer reads is inside a function (`to
    // makeCard ...`), an `if` or a loop - UI made there exists only when
    // the program runs, and a `.` there closes that body, not ours.
    const indent = rawLine.length - rawLine.trimStart().length;
    if (!block && indent > 0) continue;

    // Check for block terminator: the `.` at the block's own indentation
    // (a nested `if ... .` inside a `when` belongs to its body).
    if (line === '.' && block && indent > block.indent) {
      if (block.type === 'when') block.lines.push(lines[i]);
      continue;
    }
    if (line === '.') {
      if (block) {
        if (block.type === 'object') {
          const comp = components.get(block.name);
          if (comp && comp.declLine === block.start) comp.endLine = i;
        } else if (block.type === 'has') {
          const comp = components.get(block.name);
          if (comp) comp.hasRanges.push({ start: block.start, end: i });
        } else if (block.type === 'when') {
          whens.push({
            name: block.name,
            eventKind: block.eventKind,
            start: block.start,
            end: i,
            body: block.lines.join('\n')
          });
        }
        block = null;
      }
      continue;
    }

    if (block) {
      if (block.type === 'when') {
        block.lines.push(lines[i]);
      } else if (!line.startsWith('#')) {
        // A property line inside `x is a k` / `x has` ... `.`
        const comp = components.get(block.name);
        const phrase = comp ? readPropertyPhrase(line, comp.kind) : null;
        if (phrase) comp.sites.push({ ...phrase, line: i, type: 'line' });
      }
      continue;
    }

    // 1. "create <kind> into <name>"
    const createMatch = line.match(CREATE_RE);
    if (createMatch) {
      const rawCreateKind = createMatch[1].trim().toLowerCase();
      const kind = KindAliases[rawCreateKind] || rawCreateKind;
      const name = createMatch[2].trim();
      if (ComponentSchema[kind]) {
        components.set(name, newComponent(name, kind, kind, i, 'create'));
      }
      continue;
    }

    // 1b. Modern declarative UI: `saveButton is a button with text "Save"`.
    // The UI model calls its root a window; `page` is the equivalent Web
    // spelling and maps to that same design surface.
    const declarativeMatch = line.match(DECLARE_RE);
    if (declarativeMatch) {
      const name = declarativeMatch[1].trim();
      const declarationTail = declarativeMatch[2].trim();
      const withIndex = declarationTail.search(/\s+with\s+/i);
      const rawKind = (withIndex === -1 ? declarationTail : declarationTail.slice(0, withIndex)).trim().toLowerCase();
      // Other spellings the compiler accepts (check box, switch, textarea...)
      // map the same way; rawKind keeps what the author wrote.
      const kind = KindAliases[rawKind] || rawKind;
      if (ComponentSchema[kind]) {
        if (withIndex === -1) {
          // Block form: properties follow on their own lines until `.`.
          // endLine stays on declLine until the terminator is seen.
          components.set(name, newComponent(name, kind, rawKind, i, 'block'));
          block = { type: 'object', name, start: i, indent };
        } else {
          const comp = newComponent(name, kind, rawKind, i, 'inline');
          components.set(name, comp);
          // Column where the property list starts: just after ` with `.
          const tailAt = rawLine.indexOf(declarationTail);
          const withMatch = /\s+with\s+/i.exec(rawLine.slice(tailAt));
          addSegments(comp, i, tailAt + withMatch.index + withMatch[0].length);
        }
      }
      continue;
    }

    // 2. "<name> has" (starts block) or "<name> has <key> <val>, ..."
    const hasBlockMatch = line.match(HAS_BLOCK_RE);
    if (hasBlockMatch) {
      block = { type: 'has', name: hasBlockMatch[1], start: i, indent };
      continue;
    }

    const inlineHasMatch = line.match(HAS_INLINE_RE);
    if (inlineHasMatch) {
      const comp = components.get(inlineHasMatch[1]);
      if (comp) {
        const hasMatch = /\s+has\s+/i.exec(rawLine);
        comp.hasRanges.push({ start: i, end: i });
        addSegments(comp, i, hasMatch.index + hasMatch[0].length);
      }
      continue;
    }

    // 3. "<prop> of <name> is <val>"
    const propOfMatch = line.match(PROP_OF_RE);
    if (propOfMatch) {
      const comp = components.get(propOfMatch[2]);
      if (comp) {
        comp.sites.push({
          key: propOfMatch[1].toLowerCase(),
          rawKey: propOfMatch[1],
          value: parseValue(propOfMatch[3].trim()),
          usesIs: true,
          line: i,
          type: 'propOf'
        });
      }
      continue;
    }

    // 4. "put <items> in <container>"
    const putMatch = line.match(PUT_RE);
    if (putMatch) {
      const items = splitTopLevelCommas(putMatch[1])
        .map(p => p.text.trim().replace(/^the\s+/i, ''))
        .filter(Boolean);
      puts.push({ line: i, container: putMatch[2], items });
      continue;
    }

    // 5. "when <name> is <event>"
    const whenMatch = line.match(WHEN_RE);
    if (whenMatch) {
      block = {
        type: 'when',
        indent,
        name: whenMatch[1],
        eventKind: whenMatch[2].toLowerCase(),
        start: i,
        lines: []
      };
      continue;
    }

    // 6. "show <window>" - only recorded, as an anchor for new event blocks.
    const showMatch = line.match(SHOW_RE);
    if (showMatch) showLines.push({ line: i, name: showMatch[1] });
  }

  // Properties as the program has them: every written site in file order (a
  // later site wins, as it does when the program runs). No schema defaults:
  // the compiler never applies them, so a model holding them would show - and
  // attribute to the source - values the running app does not have.
  for (const comp of components.values()) {
    comp.properties = {};
    const inFileOrder = [...comp.sites].sort((a, b) => a.line - b.line);
    for (const site of inFileOrder) comp.properties[site.key] = site.value;
  }

  return { lines, components, puts, whens, showLines };
}

function newComponent(name, kind, rawKind, declLine, form) {
  return {
    name, kind, rawKind, declLine, endLine: declLine, form,
    sites: [], hasRanges: [], listLine: -1, listStart: -1, properties: {}
  };
}

export function parseOtterSource(source, targetModel) {
  if (!source || !source.trim()) {
    targetModel.clearFromSource();
    return true;
  }

  const scan = scanOtterSource(source);

  // If no window was created, parsing failed to find UI structure
  let rootComp = null;
  for (const comp of scan.components.values()) {
    if (comp.kind === 'window') {
      rootComp = comp;
      break;
    }
  }

  if (!rootComp) return false;

  // Reconstruct targetModel from parsed data
  targetModel.components.clear();
  targetModel.events.clear();

  // Create root window
  const root = targetModel.createComponent('window', {
    name: rootComp.name,
    properties: rootComp.properties,
    // The model mirrors the source: no schema defaults it does not state.
    defaults: false
  });
  targetModel.rootId = root.id;
  targetModel.selectedId = root.id;
  // A web page (`app is a page`) or a desktop window: labels, the canvas
  // frame and generated source follow it.
  targetModel.rootKind = rootComp.rawKind === 'page' ? 'page' : 'window';

  const nameToId = new Map();
  nameToId.set(rootComp.name, root.id);

  // Create all components
  for (const [name, comp] of scan.components.entries()) {
    if (name === rootComp.name) continue;
    const newComp = targetModel.createComponent(comp.kind, {
      name: comp.name,
      properties: comp.properties,
      defaults: false
    });
    nameToId.set(name, newComp.id);
  }

  // Connect parenting relationships
  for (const put of scan.puts) {
    const parentId = nameToId.get(put.container);
    const parent = targetModel.getComponent(parentId);
    if (!parent) continue;

    for (const childName of put.items) {
      const childId = nameToId.get(childName);
      const child = targetModel.getComponent(childId);
      if (child) {
        child.parentId = parentId;
        if (!parent.children.includes(childId)) {
          parent.children.push(childId);
        }
      }
    }
  }

  // Connect events
  for (const when of scan.whens) {
    const id = nameToId.get(when.name);
    if (!id) continue;
    if (!targetModel.events.has(id)) targetModel.events.set(id, {});
    targetModel.events.get(id)[when.eventKind] = when.body;
  }

  targetModel.notify('parse', { rootId: root.id });
  return true;
}

export function parseValue(raw) {
  if (raw.startsWith('"') && raw.endsWith('"')) {
    return raw.slice(1, -1);
  }
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  if (raw === 'full') return 'full';
  const num = Number(raw);
  if (!isNaN(num)) return num;
  return raw;
}
