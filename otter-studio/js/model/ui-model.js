// ui-model.js - In-memory tree, reactive state, undo/redo history, and duplication for the Otter UI Designer

import { ComponentSchema } from './schema.js';

export class OtterUiModel {
  constructor() {
    this.components = new Map();
    this.rootId = null;
    // 'page' for a web page (`app is a page`), else a desktop window.
    this.rootKind = 'window';
    this.selectedId = null;
    this.selectedIds = new Set();
    this.events = new Map(); // id -> { [eventKind]: handlerCode }
    this.listeners = new Set();
    this.nameCounters = {};

    this.undoStack = [];
    this.redoStack = [];
    this.maxHistory = 50;

    // The stylesheet (a CssAstManager) that belongs to this design. When one
    // is attached, undo/redo snapshots include the CSS text, so a style edit
    // is undone together with the structure it belongs to.
    this.stylesheet = null;

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
    this.rootKind = 'window';
    this.selectedId = root.id;
    this.selectedIds = new Set([root.id]);
  }

  // --- Snapshot & History (Undo / Redo) ---

  attachStylesheet(cssAstManager) {
    this.stylesheet = cssAstManager || null;
  }

  serializeSnapshot() {
    return {
      css: this.stylesheet ? this.stylesheet.generateCss() : null,
      components: Array.from(this.components.entries()).map(([k, v]) => [k, {
        ...v,
        children: [...v.children],
        properties: { ...v.properties }
      }]),
      rootId: this.rootId,
      selectedId: this.selectedId,
      selectedIds: Array.from(this.selectedIds),
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
    this.selectedIds = new Set(snap.selectedIds || (snap.selectedId ? [snap.selectedId] : []));
    this.events = new Map(snap.events.map(([k, v]) => [k, { ...v }]));
    this.nameCounters = { ...snap.nameCounters };
    if (this.stylesheet && typeof snap.css === 'string') {
      this.stylesheet.parse(snap.css);
    }
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
    this.rootKind = 'window';
    this.selectedId = null;
    this.selectedIds.clear();
    this.nameCounters = {};
    this.undoStack = [];
    this.redoStack = [];
    this.notify('source-clear');
  }

  // --- Identifier & Variable Generation ---

  // New controls get a numbered name (button1, button2, ...). A bare kind such
  // as `button` or `text` is a keyword in Otter, so it is a poor variable name,
  // and it could collide with a name already present in the source.
  generateVariableName(kind) {
    const words = kind.split(/\s+/);
    const camel = words.map((w, i) => i === 0 ? w.toLowerCase() : w.charAt(0).toUpperCase() + w.slice(1).toLowerCase()).join('');
    const taken = new Set(Array.from(this.components.values()).map(c => c.name));

    let n = this.nameCounters[camel] || 0;
    let candidate;
    do {
      n += 1;
      candidate = `${camel}${n}`;
    } while (taken.has(candidate));
    this.nameCounters[camel] = n;
    return candidate;
  }

  // --- Component Creation & Management ---

  createComponent(kind, overrides = {}) {
    const canonicalKind = {
      'input': 'text box',
      'textbox': 'text box',
      'label': 'text'
    }[kind] || kind;

    const schema = ComponentSchema[canonicalKind];
    if (!schema) throw new Error(`Unknown component kind: ${kind}`);

    const id = overrides.id || `node_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
    const name = overrides.name || this.generateVariableName(kind);
    // New components start from the schema defaults, which then become
    // part of their source. A component read from source (defaults: false)
    // has exactly the properties the source states.
    const properties = {
      ...(overrides.defaults === false ? {} : (schema.defaultProperties || {})),
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

  select(id, multi = false) {
    if (id === null) {
      this.selectedId = null;
      this.selectedIds.clear();
      this.notify('select', { id: null, selectedIds: [] });
      return;
    }

    if (multi) {
      if (this.selectedIds.has(id)) {
        this.selectedIds.delete(id);
        const arr = Array.from(this.selectedIds);
        this.selectedId = arr.length > 0 ? arr[arr.length - 1] : null;
      } else {
        this.selectedIds.add(id);
        this.selectedId = id;
      }
    } else {
      this.selectedIds.clear();
      this.selectedIds.add(id);
      this.selectedId = id;
    }

    this.notify('select', { id: this.selectedId, selectedIds: Array.from(this.selectedIds) });
  }

  // Replace the selection with `ids` (the last one becomes primary).
  selectMany(ids) {
    const valid = ids.filter(id => this.components.has(id));
    if (valid.length === 0) return this.select(null);
    this.selectedIds = new Set(valid);
    this.selectedId = valid[valid.length - 1];
    this.notify('select', { id: this.selectedId, selectedIds: valid });
  }

  // Put the given siblings into a new container of `kind`, at the position of
  // the first of them. Components with different parents are not wrapped.
  wrapComponents(ids, kind = 'column') {
    const comps = ids.map(id => this.components.get(id)).filter(c => c && c.id !== this.rootId);
    if (comps.length === 0) return null;
    const parentId = comps[0].parentId;
    if (!comps.every(c => c.parentId === parentId)) return null;
    const parent = this.components.get(parentId);
    if (!parent) return null;

    this.saveSnapshot();
    const ordered = comps.slice().sort((a, b) => parent.children.indexOf(a.id) - parent.children.indexOf(b.id));
    const at = parent.children.indexOf(ordered[0].id);
    const wrapper = this.createComponent(kind, { parentId });
    parent.children = parent.children.filter(id => !ordered.some(c => c.id === id));
    parent.children.splice(at, 0, wrapper.id);
    for (const comp of ordered) {
      comp.parentId = wrapper.id;
      wrapper.children.push(comp.id);
    }
    this.selectedIds = new Set([wrapper.id]);
    this.selectedId = wrapper.id;
    this.notify('add', { parentId, childId: wrapper.id });
    return wrapper;
  }

  // Replace a container with its children.
  unwrapComponent(id) {
    const comp = this.components.get(id);
    if (!comp || id === this.rootId || !comp.parentId) return false;
    const parent = this.components.get(comp.parentId);
    if (!parent) return false;

    this.saveSnapshot();
    const at = parent.children.indexOf(id);
    parent.children.splice(at, 1, ...comp.children);
    for (const childId of comp.children) {
      const child = this.components.get(childId);
      if (child) child.parentId = parent.id;
    }
    this.components.delete(id);
    this.events.delete(id);
    if (this.stylesheet) this.stylesheet.removeSelectorFamily(comp.name);
    const next = comp.children.length ? comp.children : [parent.id];
    this.selectedIds = new Set(next);
    this.selectedId = next[next.length - 1];
    this.notify('remove', { id });
    return true;
  }

  isSelected(id) {
    return this.selectedIds.has(id);
  }

  getSelectedComponents() {
    return Array.from(this.selectedIds).map(id => this.getComponent(id)).filter(Boolean);
  }

  // The schema's default colours suit a dark app. A control added onto a
  // light surface (the nearest background in the Otter source up the
  // container chain: a white page, a light card) gets the light-surface
  // colours instead - pale text on white was barely readable, and dark
  // navy fields looked out of place. Colours given explicitly are kept.
  fitDefaultsToSurface(child, parentId, given = {}) {
    let background = null;
    for (let id = parentId; id && !background; id = this.components.get(id)?.parentId) {
      const bg = this.components.get(id)?.properties?.background;
      if (typeof bg === 'string' && /^#[0-9a-f]{6}$/i.test(bg.trim())) background = bg.trim();
    }
    if (!background) return;
    const [r, g, b] = [1, 3, 5].map(i => parseInt(background.slice(i, i + 2), 16) / 255);
    if (0.2126 * r + 0.7152 * g + 0.0722 * b < 0.6) return; // a dark surface: the defaults suit it
    const LIGHT = {
      background: { '#1e293b': '#f1f5f9', '#0f172a': '#ffffff', '#334155': '#e2e8f0' },
      foreground: { '#cbd5e1': '#334155', '#f8fafc': '#0f172a' }
    };
    const defaults = ComponentSchema[child.kind]?.defaultProperties || {};
    for (const key of ['background', 'foreground']) {
      const value = child.properties[key];
      if (given[key] !== undefined || value === undefined || value !== defaults[key]) continue;
      let light = LIGHT[key][String(value).toLowerCase()];
      // A secondary button's white text on its new light grey would vanish.
      if (key === 'foreground' && value === '#ffffff' && child.properties.background === '#e2e8f0') light = '#0f172a';
      if (light) child.properties[key] = light;
    }
    if (child.properties.background === '#e2e8f0' && child.properties.foreground === '#ffffff') child.properties.foreground = '#0f172a';
  }

  addChild(parentId, kind, properties = {}, atIndex = null) {
    const parent = this.components.get(parentId);
    if (!parent) return null;

    this.saveSnapshot();

    const child = this.createComponent(kind, { parentId, properties });
    this.fitDefaultsToSurface(child, parentId, properties);
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

      // Clone the component's CSS, states and breakpoints included
      const sheet = cssAstManager || this.stylesheet;
      if (sheet) sheet.copySelectorFamily(comp.name, newName);

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
      const removed = this.components.get(removeId);
      if (removed && this.stylesheet) this.stylesheet.removeSelectorFamily(removed.name);
      this.components.delete(removeId);
      this.events.delete(removeId);
      this.selectedIds.delete(removeId);
    }

    if (this.selectedId === id || !this.selectedIds.has(this.selectedId)) {
      const nextId = comp.parentId || this.rootId;
      this.select(nextId);
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
    if (this.stylesheet) this.stylesheet.renameSelectorFamily(oldName, newName);
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
