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

// The size a control gets when it is placed in a Free layout container, so
// nothing arrives stretched across the window or collapsed to nothing (like
// a new control on a Visual Studio form). Numbers are px; width / height go
// into the Otter source ("width 220"), minWidth into the stylesheet. Kinds
// not listed (text, heading, checkbox) keep their natural size.
export const FREE_DEFAULT_SIZES = {
  'button': { minWidth: 100 },
  'primary button': { minWidth: 100 },
  'danger button': { minWidth: 100 },
  'text box': { width: 220 },
  'dropdown': { width: 200 },
  'slider': { width: 200 },
  'progress bar': { width: 220 },
  'image': { width: 200, height: 140 },
  'card': { width: 300, height: 200 },
  'row': { width: 320, height: 120 },
  'column': { width: 240, height: 240 },
  'scroll': { width: 300, height: 240 }
};

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

  // A copy of a Free control would land exactly on the original (its left /
  // top are copied too): it goes 16 px down and right, as in Visual Studio.
  const COPY_OFFSET = 16;

  function duplicateSelection() {
    const comps = selection();
    if (comps.length === 0) return false;
    const boxes = new Map(comps.map(c => [c.id, freeBox(c)]));
    const copies = asOneStep(() => comps.map(c => {
      const copy = uiModel.duplicateComponent(c.id, cssAstManager);
      const box = boxes.get(c.id);
      if (copy && box) offsetCopy(copy, box, COPY_OFFSET);
      return copy;
    }).filter(Boolean));
    uiModel.selectMany(copies.map(c => c.id));
    return true;
  }

  function offsetCopy(copy, box, by) {
    inBaseState(() => styles.write(copy, { left: `${Math.round(box.left + by)}px`, top: `${Math.round(box.top + by)}px` }, { key: `copy:${copy.id}` }));
  }

  // --- Copy / paste controls (Ctrl+C / Ctrl+V on the canvas) -----------------
  //
  // Paste puts copies of the copied controls into the selected container (or
  // the selected control's container). Pasting again into the same place
  // offsets each new copy a further 16 px.
  let clipboard = [];
  let pasteRun = { key: '', count: 0 };

  function copySelection() {
    const comps = selection();
    if (!comps.length) return false;
    clipboard = comps.map(c => c.id);
    pasteRun = { key: '', count: 0 };
    return true;
  }

  function pasteTarget() {
    const comp = primary();
    if (!comp) return uiModel.getRoot();
    if (isContainer(comp) && !clipboard.includes(comp.id)) return comp;
    return uiModel.getComponent(comp.parentId) || uiModel.getRoot();
  }

  function pasteSelection() {
    const originals = clipboard.map(id => uiModel.getComponent(id)).filter(Boolean);
    if (!originals.length) return false;
    const target = pasteTarget();
    if (!target) return false;
    const runKey = `${target.id}:${clipboard.join(',')}`;
    pasteRun = pasteRun.key === runKey ? { key: runKey, count: pasteRun.count + 1 } : { key: runKey, count: 1 };
    const boxes = new Map(originals.map(o => [o.id, freeBox(o)]));
    const copies = asOneStep(() => originals.map(original => {
      if (uiModel.isDescendantOf(target.id, original.id) || target.id === original.id) return null;
      const copy = uiModel.duplicateComponent(original.id, cssAstManager);
      if (!copy) return null;
      if (copy.parentId !== target.id) uiModel.moveChild(copy.id, target.id);
      const box = boxes.get(original.id);
      if (box && isFreeLayout(target)) offsetCopy(copy, box, original.parentId === target.id ? COPY_OFFSET * pasteRun.count : 0);
      return copy;
    }).filter(Boolean));
    if (!copies.length) return false;
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
  // Arrow keys: every selected control placed at x / y moves by (dx, dy) from
  // where it is (it used to give them all the primary one's position).
  // Controls in a row or column are left alone.
  function nudge(dx, dy) {
    const boxes = selection().map(freeBox).filter(Boolean);
    if (!boxes.length) return false;
    const key = `nudge:${boxes.map(b => b.comp.id).join(',')}`;
    for (const b of boxes) {
      const values = {};
      if (dx) values.left = `${Math.round(b.left + dx)}px`;
      if (dy) values.top = `${Math.round(b.top + dy)}px`;
      styles.write(b.comp, values, { key });
    }
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
        // Absolute children take no room: keep the container's height.
        const values = { [FREE_MARK]: 'free', position: 'relative', 'min-height': `${Math.round(containerHeight)}px` };
        styles.write(container, values, { key });
        if (container.id === uiModel.rootId && cssAstManager) {
          // The window's title is its title bar (as the designer draws it); the
          // compiled window's own title header would otherwise sit on top of
          // the controls placed near the top, since #app is where they are
          // measured from.
          cssAstManager.setProperty(windowHeaderSelector(container), 'display', 'none');
        }
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
        if (container.id === uiModel.rootId && cssAstManager) cssAstManager.removeProperty(windowHeaderSelector(container), 'display');
      }
      return true;
    });
  }

  function windowHeaderSelector(win) {
    return `#${win.name} > .otter-window-header`;
  }

  function toggleFreeLayout(comp = primary()) {
    const target = isContainer(comp) ? comp : uiModel.getComponent(comp?.parentId);
    if (!target) return false;
    return setFreeLayout(target, !isFreeLayout(target));
  }

  // Put a child of a Free container at a point: its top-left corner goes
  // where the pointer is, minus where the pointer held it (grab, CSS px).
  // isNew: a control just created (dragged or clicked in from Components)
  // also gets its default size (FREE_DEFAULT_SIZES).
  // Where a drop at a point would put a control's top-left corner (left /
  // top in CSS px) - the same numbers the drop writes, for the drop preview.
  function positionFor(container, clientX, clientY, grab = { x: 0, y: 0 }) {
    const containerEl = container && canvas.elementFor(container.id);
    if (!containerEl) return null;
    const at = pointIn(containerEl, clientX, clientY);
    return { left: Math.max(0, Math.round(at.x - grab.x)), top: Math.max(0, Math.round(at.y - grab.y)) };
  }

  function placeAt(comp, container, clientX, clientY, grab = { x: 0, y: 0 }, { isNew = false } = {}) {
    const pos = comp && positionFor(container, clientX, clientY, grab);
    if (!pos) return false;
    const { left, top } = pos;
    const values = { position: 'absolute', left: `${left}px`, top: `${top}px`, right: null, bottom: null };
    const size = isNew ? FREE_DEFAULT_SIZES[comp.kind] : null;
    if (size?.width) values.width = `${size.width}px`;
    if (size?.height) values.height = `${size.height}px`;
    if (size?.minWidth) values['min-width'] = `${size.minWidth}px`;
    inBaseState(() => styles.write(comp, values, { key: `place:${comp.id}` }));
    return true;
  }

  // --- Align and distribute (Free controls) ----------------------------------
  //
  // For two or more selected controls in the same Free container: line them
  // up on the selection's left / centre / right / top / middle / bottom edge,
  // or (three or more) spread them so the gaps between them are equal. Each
  // is one undo step.

  // Where a Free control is in its container, in CSS px (null otherwise).
  function freeBox(comp) {
    const el = comp && canvas.elementFor(comp.id);
    if (!el) return null;
    const cs = getComputedStyle(el);
    if (cs.position !== 'absolute' && cs.position !== 'fixed') return null;
    const r = el.getBoundingClientRect();
    const zoom = canvas.getZoom();
    return { comp, left: parseFloat(cs.left) || 0, top: parseFloat(cs.top) || 0, width: r.width / zoom, height: r.height / zoom };
  }

  function freeSelection(min = 2) {
    const comps = selection();
    if (comps.length < min || !comps.every(c => c.parentId === comps[0].parentId)) return null;
    const boxes = comps.map(freeBox);
    return boxes.every(Boolean) ? boxes : null;
  }

  let arrangeCount = 0;
  function writeBoxes(boxes, name) {
    const key = `${name}:${++arrangeCount}`;
    inBaseState(() => {
      for (const b of boxes) styles.write(b.comp, { left: `${Math.round(b.left)}px`, top: `${Math.round(b.top)}px` }, { key });
    });
    return true;
  }

  function align(edge) {
    const boxes = freeSelection(2);
    if (!boxes) return false;
    const left = Math.min(...boxes.map(b => b.left));
    const right = Math.max(...boxes.map(b => b.left + b.width));
    const top = Math.min(...boxes.map(b => b.top));
    const bottom = Math.max(...boxes.map(b => b.top + b.height));
    for (const b of boxes) {
      if (edge === 'left') b.left = left;
      else if (edge === 'right') b.left = right - b.width;
      else if (edge === 'center') b.left = (left + right) / 2 - b.width / 2;
      else if (edge === 'top') b.top = top;
      else if (edge === 'bottom') b.top = bottom - b.height;
      else if (edge === 'middle') b.top = (top + bottom) / 2 - b.height / 2;
    }
    return writeBoxes(boxes, `align-${edge}`);
  }

  function distribute(axis) {
    const boxes = freeSelection(3);
    if (!boxes) return false;
    const pos = axis === 'horizontal' ? 'left' : 'top';
    const size = axis === 'horizontal' ? 'width' : 'height';
    boxes.sort((a, b) => a[pos] - b[pos]);
    const first = boxes[0];
    const last = boxes[boxes.length - 1];
    const span = last[pos] + last[size] - first[pos];
    const gap = (span - boxes.reduce((sum, b) => sum + b[size], 0)) / (boxes.length - 1);
    let at = first[pos];
    for (const b of boxes) {
      b[pos] = at;
      at += b[size] + gap;
    }
    return writeBoxes(boxes, `distribute-${axis}`);
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
    isFreeLayout, setFreeLayout, toggleFreeLayout, placeAt, positionFor,
    copySelection, pasteSelection, align, distribute,
    canArrange: (min = 2) => Boolean(freeSelection(min)),
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
