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
