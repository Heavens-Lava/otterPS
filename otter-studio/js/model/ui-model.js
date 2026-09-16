// ui-model.js - In-memory tree, reactive state, undo/redo history, and duplication for the Otter UI Designer

import { ComponentSchema } from './schema.js';

export class OtterUiModel {
  constructor() {
    this.components = new Map();
    this.rootId = null;
    this.selectedId = null;
    this.events = new Map(); // id -> { [eventKind]: handlerCode }
    this.listeners = new Set();
    this.nameCounters = {};

    this.undoStack = [];
    this.redoStack = [];
    this.maxHistory = 50;

    this.initDefault();
  }

  initDefault() {
    this.components.clear();
    this.events.clear();
    this.nameCounters = {};
    this.undoStack = [];
    this.redoStack = [];

    const root = this.createComponent('window', {
      name: 'app',
      properties: {
        title: 'Task Manager',
        width: 740,
        height: 520,
        background: '#0f172a',
        padding: 16,
        spacing: 12
      }
    });
    this.rootId = root.id;
    this.selectedId = root.id;
  }

  // --- Snapshot & History (Undo / Redo) ---

  serializeSnapshot() {
    return {
      components: Array.from(this.components.entries()).map(([k, v]) => [k, {
        ...v,
        children: [...v.children],
        properties: { ...v.properties }
      }]),
      rootId: this.rootId,
      selectedId: this.selectedId,
      events: Array.from(this.events.entries()).map(([k, v]) => [k, { ...v }]),
      nameCounters: { ...this.nameCounters }
    };
  }

  restoreSnapshot(snap) {
    this.components = new Map(snap.components.map(([k, v]) => [k, {
      ...v,
      children: [...v.children],
      properties: { ...v.properties }
    }]));
    this.rootId = snap.rootId;
    this.selectedId = snap.selectedId;
    this.events = new Map(snap.events.map(([k, v]) => [k, { ...v }]));
    this.nameCounters = { ...snap.nameCounters };
  }

  saveSnapshot() {
    this.undoStack.push(this.serializeSnapshot());
    if (this.undoStack.length > this.maxHistory) {
      this.undoStack.shift();
    }
    this.redoStack = []; // clear redo on new action
  }

  undo() {
    if (this.undoStack.length === 0) return false;
    const current = this.serializeSnapshot();
    this.redoStack.push(current);
    const prev = this.undoStack.pop();
    this.restoreSnapshot(prev);
    this.notify('undo');
    return true;
  }

  redo() {
    if (this.redoStack.length === 0) return false;
    const current = this.serializeSnapshot();
    this.undoStack.push(current);
    const next = this.redoStack.pop();
    this.restoreSnapshot(next);
    this.notify('redo');
    return true;
  }

  canUndo() {
    return this.undoStack.length > 0;
  }

  canRedo() {
    return this.redoStack.length > 0;
  }

  // --- Reactive Listeners ---

  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  notify(changeType = 'update', detail = null) {
    for (const listener of this.listeners) {
      listener(changeType, detail);
    }
  }

  clearFromSource() {
    this.components.clear();
    this.events.clear();
    this.rootId = null;
    this.selectedId = null;
    this.nameCounters = {};
    this.undoStack = [];
    this.redoStack = [];
    this.notify('source-clear');
  }

  // --- Identifier & Variable Generation ---

  generateVariableName(kind) {
    const words = kind.split(/\s+/);
    const camel = words.map((w, i) => i === 0 ? w.toLowerCase() : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join('');

    if (!this.nameCounters[camel]) {
      this.nameCounters[camel] = 1;
      return camel;
    }
    this.nameCounters[camel]++;
    return `${camel}${this.nameCounters[camel]}`;
  }

  // --- Component Creation & Management ---

  createComponent(kind, overrides = {}) {
    const canonicalKind = {
      'input': 'text box',
      'textbox': 'text box',
      'badge': 'text',
      'label': 'text'
    }[kind] || kind;

    const schema = ComponentSchema[canonicalKind];
    if (!schema) throw new Error(`Unknown component kind: ${kind}`);

    const id = overrides.id || `node_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
    const name = overrides.name || this.generateVariableName(kind);
    const properties = {
      ...(schema.defaultProperties || {}),
      ...(overrides.properties || {})
    };

    const component = {
      id,
      name,
      kind,
      parentId: overrides.parentId || null,
      children: overrides.children || [],
      properties
    };

    this.components.set(id, component);
    return component;
  }

  getComponent(id) {
    return this.components.get(id) || null;
  }

  getRoot() {
    return this.components.get(this.rootId) || null;
  }

  select(id) {
    if (this.selectedId !== id) {
      this.selectedId = id;
      this.notify('select', { id });
    }
  }

  addChild(parentId, kind, properties = {}, atIndex = null) {
    const parent = this.components.get(parentId);
    if (!parent) return null;

    this.saveSnapshot();

    const child = this.createComponent(kind, { parentId, properties });
    if (atIndex !== null && atIndex >= 0 && atIndex <= parent.children.length) {
      parent.children.splice(atIndex, 0, child.id);
    } else {
      parent.children.push(child.id);
    }

    this.select(child.id);
    this.notify('add', { parentId, childId: child.id });
    return child;
  }

  moveChild(childId, newParentId, atIndex = null) {
    const child = this.components.get(childId);
    const newParent = this.components.get(newParentId);
    if (!child || !newParent || childId === this.rootId) return false;

    // Prevent dropping into self or descendants
    if (this.isDescendantOf(newParentId, childId)) return false;

    this.saveSnapshot();

    // Remove from old parent
    if (child.parentId) {
      const oldParent = this.components.get(child.parentId);
      if (oldParent) {
        oldParent.children = oldParent.children.filter(id => id !== childId);
      }
    }

    // Insert into new parent
    child.parentId = newParentId;
    if (atIndex !== null && atIndex >= 0 && atIndex <= newParent.children.length) {
      newParent.children.splice(atIndex, 0, childId);
    } else {
      newParent.children.push(childId);
    }

    this.notify('move', { childId, newParentId, atIndex });
    return true;
  }

  duplicateComponent(id, cssAstManager = null) {
    const original = this.components.get(id);
    if (!original || id === this.rootId) return null;

    this.saveSnapshot();

    const parent = original.parentId ? this.components.get(original.parentId) : this.getRoot();
    if (!parent) return null;

    // Recursive subtree clone
    const cloneSubtree = (comp, parentId) => {
      const newName = this.generateVariableName(comp.kind);
      const newId = `node_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
      const clonedComp = {
        id: newId,
        name: newName,
        kind: comp.kind,
        parentId: parentId,
        children: [],
        properties: JSON.parse(JSON.stringify(comp.properties || {}))
      };
      this.components.set(newId, clonedComp);

      // Clone events
      if (this.events.has(comp.id)) {
        this.events.set(newId, JSON.parse(JSON.stringify(this.events.get(comp.id))));
      }

      // Clone CSS AST rules if available
      if (cssAstManager) {
        const decls = cssAstManager.getRuleDeclarations(`#${comp.name}`);
        for (const [prop, val] of Object.entries(decls)) {
          cssAstManager.setProperty(`#${newName}`, prop, val);
        }
      }

      // Recurse children
      if (comp.children && comp.children.length > 0) {
        for (const childId of comp.children) {
          const child = this.components.get(childId);
          if (child) {
            const childClone = cloneSubtree(child, newId);
            clonedComp.children.push(childClone.id);
          }
        }
      }

      return clonedComp;
    };

    const clonedRoot = cloneSubtree(original, parent.id);

    // Insert immediately after original in parent's children
    const origIndex = parent.children.indexOf(id);
    if (origIndex >= 0) {
      parent.children.splice(origIndex + 1, 0, clonedRoot.id);
    } else {
      parent.children.push(clonedRoot.id);
    }

    this.select(clonedRoot.id);
    this.notify('add', { parentId: parent.id, childId: clonedRoot.id });
    return clonedRoot;
  }

  isDescendantOf(checkId, ancestorId) {
    let curr = this.components.get(checkId);
    while (curr && curr.parentId) {
      if (curr.parentId === ancestorId) return true;
      curr = this.components.get(curr.parentId);
    }
    return false;
  }

  removeComponent(id) {
    if (id === this.rootId) return false; // cannot remove root window
    const comp = this.components.get(id);
    if (!comp) return false;

    this.saveSnapshot();

    // Remove from parent
    if (comp.parentId) {
      const parent = this.components.get(comp.parentId);
      if (parent) {
        parent.children = parent.children.filter(cId => cId !== id);
      }
    }

    // Recursively remove children
    const toRemove = [id];
    let idx = 0;
    while (idx < toRemove.length) {
      const curr = this.components.get(toRemove[idx]);
      if (curr && curr.children) {
        toRemove.push(...curr.children);
      }
      idx++;
    }

    for (const removeId of toRemove) {
      this.components.delete(removeId);
      this.events.delete(removeId);
    }

    if (this.selectedId === id) {
      this.select(comp.parentId || this.rootId);
    }

    this.notify('remove', { id });
    return true;
  }

  setProperty(id, key, value) {
    const comp = this.components.get(id);
    if (!comp) return;

    this.saveSnapshot();

    comp.properties[key] = value;
    this.notify('property', { id, key, value });
  }

  updateProperties(id, props) {
    const comp = this.components.get(id);
    if (!comp || !props) return;

    this.saveSnapshot();
    Object.assign(comp.properties, props);
    this.notify('property', { id, properties: props });
  }

  setName(id, newName) {
    const comp = this.components.get(id);
    if (!comp || !newName || comp.name === newName) return;

    this.saveSnapshot();

    const oldName = comp.name;
    comp.name = newName;
    this.notify('rename', { id, oldName, newName });
  }

  getEvents(id) {
    return this.events.get(id) || {};
  }

  setEvent(id, eventKind, handlerCode) {
    this.saveSnapshot();

    if (!this.events.has(id)) {
      this.events.set(id, {});
    }
    const compEvents = this.events.get(id);
    compEvents[eventKind] = handlerCode;
    this.notify('event', { id, eventKind, handlerCode });
  }

  removeEvent(id, eventKind) {
    if (this.events.has(id)) {
      this.saveSnapshot();

      const compEvents = this.events.get(id);
      delete compEvents[eventKind];
      this.notify('event', { id, eventKind, handlerCode: null });
    }
  }

  getAllComponents() {
    return Array.from(this.components.values());
  }
}
