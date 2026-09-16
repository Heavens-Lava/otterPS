// otter-parser.js - In-browser parser for bidirectional sync (Code -> UI Model)

import { ComponentSchema } from '../model/schema.js';

export function parseOtterSource(source, targetModel) {
  if (!source || !source.trim()) return false;

  const lines = source.split('\n');
  const createdComponents = new Map(); // name -> { kind, properties: {} }
  const parenting = new Map(); // containerName -> [childNames]
  const eventHandlers = new Map(); // name -> { [eventKind]: body }

  let currentBlock = null; // { type: 'has'|'when', name: '', eventKind: '', lines: [] }

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    const line = rawLine.trim();

    // Skip empty lines or top-level comments
    if (!line || (line.startsWith('#') && !currentBlock)) continue;

    // Check for block terminator
    if (line === '.') {
      if (currentBlock) {
        if (currentBlock.type === 'has') {
          processHasBlock(currentBlock, createdComponents);
        } else if (currentBlock.type === 'when') {
          if (!eventHandlers.has(currentBlock.name)) {
            eventHandlers.set(currentBlock.name, {});
          }
          eventHandlers.get(currentBlock.name)[currentBlock.eventKind] = currentBlock.lines.join('\n');
        }
        currentBlock = null;
      }
      continue;
    }

    if (currentBlock) {
      currentBlock.lines.push(rawLine);
      continue;
    }

    // 1. "create <kind> into <name>"
    const createMatch = line.match(/^create\s+(?:the\s+)?([a-zA-Z0-9\s]+?)\s+into\s+([a-zA-Z0-9_]+)$/i);
    if (createMatch) {
      const kind = createMatch[1].trim().toLowerCase();
      const name = createMatch[2].trim();
      if (ComponentSchema[kind]) {
        createdComponents.set(name, {
          name,
          kind,
          properties: { ...ComponentSchema[kind].defaultProperties }
        });
      }
      continue;
    }

    // 2. "<name> has" (starts block) or "<name> has <key> <val>, ..."
    const hasBlockMatch = line.match(/^([a-zA-Z0-9_]+)\s+has$/i);
    if (hasBlockMatch) {
      currentBlock = {
        type: 'has',
        name: hasBlockMatch[1],
        lines: []
      };
      continue;
    }

    const inlineHasMatch = line.match(/^([a-zA-Z0-9_]+)\s+has\s+(.+)$/i);
    if (inlineHasMatch) {
      const name = inlineHasMatch[1];
      const rest = inlineHasMatch[2];
      processHasProps(name, rest, createdComponents);
      continue;
    }

    // 3. "<prop> of <name> is <val>"
    const propOfMatch = line.match(/^([a-zA-Z0-9_]+)\s+of\s+([a-zA-Z0-9_]+)\s+is\s+(.+)$/i);
    if (propOfMatch) {
      const propKey = propOfMatch[1].toLowerCase();
      const name = propOfMatch[2];
      const valRaw = propOfMatch[3].trim();
      const val = parseValue(valRaw);
      if (createdComponents.has(name)) {
        createdComponents.get(name).properties[propKey] = val;
      }
      continue;
    }

    // 4. "put <items> in <container>"
    const putMatch = line.match(/^put\s+(.+?)\s+in\s+([a-zA-Z0-9_]+)$/i);
    if (putMatch) {
      const itemsRaw = putMatch[1];
      const containerName = putMatch[2];
      const items = itemsRaw.split(',').map(s => s.trim().replace(/^the\s+/i, ''));
      if (!parenting.has(containerName)) {
        parenting.set(containerName, []);
      }
      parenting.get(containerName).push(...items);
      continue;
    }

    // 5. "when <name> is <event>"
    const whenMatch = line.match(/^when\s+([a-zA-Z0-9_]+)\s+(?:is\s+)?([a-zA-Z0-9_]+)$/i);
    if (whenMatch) {
      currentBlock = {
        type: 'when',
        name: whenMatch[1],
        eventKind: whenMatch[2].toLowerCase(),
        lines: []
      };
      continue;
    }
  }

  // If no window was created, parsing failed to find UI structure
  let rootComp = null;
  for (const [name, comp] of createdComponents.entries()) {
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
    properties: rootComp.properties
  });
  targetModel.rootId = root.id;
  targetModel.selectedId = root.id;

  const nameToId = new Map();
  nameToId.set(rootComp.name, root.id);

  // Create all components
  for (const [name, comp] of createdComponents.entries()) {
    if (name === rootComp.name) continue;
    const newComp = targetModel.createComponent(comp.kind, {
      name: comp.name,
      properties: comp.properties
    });
    nameToId.set(name, newComp.id);
  }

  // Connect parenting relationships
  for (const [parentName, childNames] of parenting.entries()) {
    const parentId = nameToId.get(parentName);
    const parent = targetModel.getComponent(parentId);
    if (!parent) continue;

    for (const childName of childNames) {
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
  for (const [name, events] of eventHandlers.entries()) {
    const id = nameToId.get(name);
    if (id) {
      for (const [eventKind, body] of Object.entries(events)) {
        targetModel.setEvent(id, eventKind, body);
      }
    }
  }

  targetModel.notify('parse', { rootId: root.id });
  return true;
}

function processHasBlock(block, createdComponents) {
  const comp = createdComponents.get(block.name);
  if (!comp) return;

  for (const line of block.lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    parsePropertyLine(trimmed, comp.properties);
  }
}

function processHasProps(name, propsString, createdComponents) {
  const comp = createdComponents.get(name);
  if (!comp) return;

  // Split by comma
  const parts = propsString.split(',');
  for (const part of parts) {
    parsePropertyLine(part.trim(), comp.properties);
  }
}

function parsePropertyLine(text, properties) {
  if (text.toLowerCase() === 'spread') {
    properties['spread'] = true;
    return;
  }
  if (text.toLowerCase() === 'round') {
    properties['round'] = 8;
    return;
  }

  const match = text.match(/^([a-zA-Z0-9_]+)\s+(.+)$/);
  if (match) {
    const key = match[1].toLowerCase();
    const val = parseValue(match[2].trim());
    properties[key] = val;
  }
}

function parseValue(raw) {
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
