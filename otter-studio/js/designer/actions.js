// actions.js - What the designer can do to the selection, as plain functions.
//
// The keyboard (designer/commands.js), the command palette, the context menu
// (designer/context-menu.js) and the Layers panel all call these, so a
// shortcut, a menu item and a palette entry can never behave differently.
// Every action works on the UI model and the StyleController; the canvas
// supplies only what needs the DOM (element lookup and zoom).
//
// Actions that may not apply (moving the first child up, nudging an element
// that is not absolutely positioned) return false, so a keyboard handler can
// leave the key alone for someone else.

import { ComponentSchema } from '../model/schema.js';

export function createDesignerActions({ uiModel, styles, cssAstManager, canvas, viewState = null }) {
  // The selection that edits apply to: never the window itself.
  function selection() {
    return uiModel.getSelectedComponents().filter(c => c.id !== uiModel.rootId);
  }

  function primary() {
    return uiModel.getComponent(uiModel.selectedId);
  }

  function isContainer(comp) {
    return Boolean(comp && (ComponentSchema[comp.kind]?.isContainer || comp.id === uiModel.rootId));
  }

  // Several model edits as one undo step.
  function asOneStep(fn) {
    uiModel.saveSnapshot();
    const depth = uiModel.undoStack.length;
    const result = fn();
    uiModel.undoStack.length = depth;
    return result;
  }

  function deleteSelection() {
    const comps = selection();
    if (comps.length === 0) return false;
    asOneStep(() => {
      for (const comp of comps) {
        if (uiModel.getComponent(comp.id)) uiModel.removeComponent(comp.id);
      }
    });
    return true;
  }

  function duplicateSelection() {
    const comps = selection();
    if (comps.length === 0) return false;
    const copies = asOneStep(() => comps.map(c => uiModel.duplicateComponent(c.id, cssAstManager)).filter(Boolean));
    uiModel.selectMany(copies.map(c => c.id));
    return true;
  }

  // Wrap the selected siblings in a new row / column / card.
  function wrap(kind) {
    const comps = selection();
    if (comps.length === 0 || !comps.every(c => c.parentId === comps[0].parentId)) return false;
    return Boolean(uiModel.wrapComponents(comps.map(c => c.id), kind));
  }

  function unwrap() {
    const comp = primary();
    if (!comp || comp.id === uiModel.rootId || !isContainer(comp)) return false;
    uiModel.unwrapComponent(comp.id);
    return true;
  }

  // --- Selection ---------------------------------------------------------

  function selectParent() {
    const comp = primary();
    if (!comp || !comp.parentId) return false;
    uiModel.select(comp.parentId);
    return true;
  }

  function selectFirstChild() {
    const comp = primary();
    if (!comp?.children?.length) return false;
    uiModel.select(comp.children[0]);
    return true;
  }

  // Next (+1) or previous (-1) sibling, wrapping around.
  function selectSibling(direction) {
    const comp = primary();
    const parent = comp?.parentId ? uiModel.getComponent(comp.parentId) : null;
    if (!parent || parent.children.length < 2) return false;
    const idx = parent.children.indexOf(comp.id);
    uiModel.select(parent.children[(idx + direction + parent.children.length) % parent.children.length]);
    return true;
  }

  function selectAllSiblings() {
    const comp = primary();
    const parent = comp && comp.parentId ? uiModel.getComponent(comp.parentId) : uiModel.getRoot();
    if (!parent || !parent.children.length) return false;
    uiModel.selectMany(parent.children);
    return true;
  }

  // --- Structure (Webstudio's Ctrl+arrows) ---------------------------------

  // Move the primary selection before (-1) or after (+1) its neighbour.
  function moveAmongSiblings(direction) {
    const comp = primary();
    const parent = comp?.parentId ? uiModel.getComponent(comp.parentId) : null;
    if (!parent) return false;
    const target = parent.children.indexOf(comp.id) + direction;
    if (target < 0 || target >= parent.children.length) return false;
    return uiModel.moveChild(comp.id, parent.id, target);
  }

  // Move the primary selection out of its parent, right after it.
  function moveOutOfParent() {
    const comp = primary();
    const parent = comp?.parentId ? uiModel.getComponent(comp.parentId) : null;
    const grandparent = parent?.parentId ? uiModel.getComponent(parent.parentId) : null;
    if (!grandparent) return false;
    const ok = uiModel.moveChild(comp.id, grandparent.id, grandparent.children.indexOf(parent.id) + 1);
    if (ok) uiModel.select(comp.id);
    return ok;
  }

  // Move the primary selection into the container just before it, at the end.
  function moveIntoPrevious() {
    const comp = primary();
    const parent = comp?.parentId ? uiModel.getComponent(comp.parentId) : null;
    if (!parent) return false;
    const previous = uiModel.getComponent(parent.children[parent.children.indexOf(comp.id) - 1]);
    if (!isContainer(previous)) return false;
    const ok = uiModel.moveChild(comp.id, previous.id, null);
    if (ok) uiModel.select(comp.id);
    return ok;
  }

  // --- Position -------------------------------------------------------------

  // Nudge absolutely positioned elements; flow elements are left to the
  // layout (return false so the key can do something else).
  function nudge(dx, dy) {
    const comp = primary();
    if (!comp || comp.id === uiModel.rootId) return false;
    const el = canvas.elementFor(comp.id);
    const cs = el ? getComputedStyle(el) : null;
    if (!cs || (cs.position !== 'absolute' && cs.position !== 'fixed')) return false;
    const values = {};
    if (dx) values.left = `${Math.round((parseFloat(cs.left) || 0) + dx)}px`;
    if (dy) values.top = `${Math.round((parseFloat(cs.top) || 0) + dy)}px`;
    styles.write(selection(), values, { key: `nudge:${comp.id}` });
    return true;
  }

  // --- Hide / lock (designer only, see view-state.js) -------------------------

  function toggleHidden() {
    const comps = selection();
    return Boolean(viewState && comps.length && viewState.toggleHidden(comps.map(c => c.name)));
  }

  function toggleLocked() {
    const comps = selection();
    return Boolean(viewState && comps.length && viewState.toggleLocked(comps.map(c => c.name)));
  }

  // --- Styles ---------------------------------------------------------------

  let copiedStyles = null;

  function copyStyles() {
    const comp = primary();
    if (!comp) return false;
    copiedStyles = { ...styles.resolve(comp).own };
    return true;
  }

  function pasteStyles() {
    if (!copiedStyles) return false;
    styles.write(uiModel.getSelectedComponents(), copiedStyles, { key: 'paste-styles' });
    return true;
  }

  // --- Free layout (place anywhere) -----------------------------------------
  //
  // A container in Free layout keeps each child exactly where it was dropped
  // or dragged, like a Visual Studio form: the container is position:
  // relative and every child is position: absolute with left / top. All of it
  // is ordinary CSS in the project's stylesheet, so the compiled app shows
  // the same layout. The container is marked with the custom property
  // --otter-layout: free (valid CSS, ignored by browsers).
  //
  // Positions are written for the current breakpoint (a different
  // arrangement on Mobile is possible), never for a :hover-style state.

  const FREE_MARK = '--otter-layout';

  function isFreeLayout(comp) {
    const el = comp && canvas.elementFor(comp.id);
    return Boolean(el) && getComputedStyle(el).getPropertyValue(FREE_MARK).trim() === 'free';
  }

  function inBaseState(fn) {
    const saved = { ...styles.context };
    styles.context = { breakpoint: saved.breakpoint, state: '' };
    try { return fn(); } finally { styles.context = saved; }
  }

  // Where a point (client px) falls inside a container's padding box, in CSS
  // px with the zoom taken out - what left / top of a child there would be.
  function pointIn(containerEl, clientX, clientY) {
    const rect = containerEl.getBoundingClientRect();
    const cs = getComputedStyle(containerEl);
    const zoom = canvas.getZoom();
    return {
      x: (clientX - rect.left) / zoom - (parseFloat(cs.borderLeftWidth) || 0),
      y: (clientY - rect.top) / zoom - (parseFloat(cs.borderTopWidth) || 0)
    };
  }

  // Turn Free layout on or off for a container. On: every child stays
  // exactly where it is now, at its current size (its position becomes its
  // left / top), so nothing jumps. Off: the children go back to flowing in
  // order; the widths stay, so the round trip changes nothing else.
  function setFreeLayout(container, on) {
    if (!isContainer(container)) return false;
    const containerEl = canvas.elementFor(container.id);
    if (!containerEl) return false;
    // On and off are separate undo steps (the same key would merge them).
    const key = `free-layout-${on ? 'on' : 'off'}:${container.id}`;
    const children = (container.children || []).map(id => uiModel.getComponent(id)).filter(Boolean);
    return inBaseState(() => {
      if (on) {
        // Measure everything before writing: each write re-renders.
        const zoom = canvas.getZoom();
        const placed = children.map(child => {
          const el = canvas.elementFor(child.id);
          if (!el) return null;
          const rect = el.getBoundingClientRect();
          const cs = getComputedStyle(el);
          const at = pointIn(containerEl, rect.left, rect.top);
          return {
            child,
            left: Math.round(at.x - (parseFloat(cs.marginLeft) || 0)),
            top: Math.round(at.y - (parseFloat(cs.marginTop) || 0)),
            width: rect.width / zoom
          };
        }).filter(Boolean);
        const containerHeight = containerEl.getBoundingClientRect().height / zoom;
        const values = { [FREE_MARK]: 'free', position: 'relative' };
        // Absolute children take no room: keep the container's height.
        if (container.id !== uiModel.rootId) values['min-height'] = `${Math.round(containerHeight)}px`;
        styles.write(container, values, { key });
        // An absolute element shrinks to its content; one that was stretched
        // across the container (a full-width button) keeps its width, so the
        // form looks exactly as it did.
        for (const p of placed) {
          styles.write(p.child, { position: 'absolute', left: `${p.left}px`, top: `${p.top}px`, right: null, bottom: null, width: `${Math.round(p.width)}px` }, { key });
        }
      } else {
        for (const child of children) {
          styles.write(child, { position: null, left: null, top: null, right: null, bottom: null }, { key });
        }
        styles.write(container, { [FREE_MARK]: null, position: null, 'min-height': null }, { key });
      }
      return true;
    });
  }

  function toggleFreeLayout(comp = primary()) {
    const target = isContainer(comp) ? comp : uiModel.getComponent(comp?.parentId);
    if (!target) return false;
    return setFreeLayout(target, !isFreeLayout(target));
  }

  // Put a child of a Free container at a point: its top-left corner goes
  // where the pointer is, minus where the pointer held it (grab, CSS px).
  function placeAt(comp, container, clientX, clientY, grab = { x: 0, y: 0 }) {
    const containerEl = canvas.elementFor(container.id);
    if (!comp || !containerEl) return false;
    const at = pointIn(containerEl, clientX, clientY);
    const left = Math.max(0, Math.round(at.x - grab.x));
    const top = Math.max(0, Math.round(at.y - grab.y));
    inBaseState(() => styles.write(comp, { position: 'absolute', left: `${left}px`, top: `${top}px`, right: null, bottom: null }, { key: `place:${comp.id}` }));
    return true;
  }

  function clearStyles() {
    const comps = uiModel.getSelectedComponents();
    if (!comps.length) return false;
    styles.clear(comps);
    return true;
  }

  return {
    selection, primary, isContainer,
    deleteSelection, duplicateSelection, wrap, unwrap,
    selectParent, selectFirstChild, selectSibling, selectAllSiblings,
    moveAmongSiblings, moveOutOfParent, moveIntoPrevious,
    nudge,
    isFreeLayout, setFreeLayout, toggleFreeLayout, placeAt,
    toggleHidden, toggleLocked,
    showAll: () => Boolean(viewState && viewState.showAll()),
    unlockAll: () => Boolean(viewState && viewState.unlockAll()),
    copyStyles, pasteStyles, clearStyles, copiedStyleCount: () => (copiedStyles ? Object.keys(copiedStyles).length : 0),
    undo: () => { uiModel.undo(); return true; },
    redo: () => { uiModel.redo(); return true; },
    zoomIn: () => { canvas.zoomBy(1); return true; },
    zoomOut: () => { canvas.zoomBy(-1); return true; },
    zoomReset: () => { canvas.setZoom(1); return true; },
    zoomToFit: () => { canvas.zoomToFit(); return true; },
    zoomToSelection: () => canvas.zoomToSelection()
  };
}
