// view-state.js - Designer-only visibility and locking (Layers panel).
//
// Hiding or locking a component is a way of working in the designer, not a
// change to the program: nothing here is ever written to the .ot file or to
// styles.css, and the running app shows everything. State is keyed by
// component name (ids change every time the source is re-read) and kept per
// design file in this browser.
//
//   hidden  the component is not drawn on the canvas (its space closes up,
//           as when a design tool hides a layer)
//   locked  clicks and drags on the canvas go to its parent instead, so a
//           background or a finished section cannot be moved by accident;
//           it can still be selected in the Layers panel

const STORE_PREFIX = 'otter-studio-view:';

export function createViewState() {
  let scope = null;
  let hidden = new Set();
  let locked = new Set();

  function load() {
    hidden = new Set();
    locked = new Set();
    if (!scope) return;
    try {
      const saved = JSON.parse(localStorage.getItem(STORE_PREFIX + scope) || '{}');
      hidden = new Set(saved.hidden || []);
      locked = new Set(saved.locked || []);
    } catch { /* storage unavailable: start clean */ }
  }

  function save() {
    if (!scope) return;
    try {
      if (hidden.size || locked.size) {
        localStorage.setItem(STORE_PREFIX + scope, JSON.stringify({ hidden: [...hidden], locked: [...locked] }));
      } else {
        localStorage.removeItem(STORE_PREFIX + scope);
      }
    } catch { /* storage unavailable: the state lasts for this session */ }
  }

  function changed() {
    save();
    if (typeof window !== 'undefined') window.dispatchEvent(new CustomEvent('otter:view-state'));
  }

  function toggle(set, names, force) {
    const list = (Array.isArray(names) ? names : [names]).filter(Boolean);
    if (!list.length) return false;
    // Several at once: if any is off, turn all on (like a design tool).
    const on = force ?? list.some(n => !set.has(n));
    for (const n of list) on ? set.add(n) : set.delete(n);
    changed();
    return true;
  }

  return {
    // Which design the state belongs to (the .ot path); loads its state.
    setScope(next) {
      if (next === scope) return;
      scope = next || null;
      load();
      changed();
    },
    isHidden: (name) => hidden.has(name),
    isLocked: (name) => locked.has(name),
    toggleHidden: (names, force) => toggle(hidden, names, force),
    toggleLocked: (names, force) => toggle(locked, names, force),
    // Keep the state when a component is renamed.
    rename(oldName, newName) {
      let touched = false;
      for (const set of [hidden, locked]) {
        if (set.delete(oldName)) { set.add(newName); touched = true; }
      }
      if (touched) changed();
    },
    showAll() {
      if (!hidden.size) return false;
      hidden.clear();
      changed();
      return true;
    },
    unlockAll() {
      if (!locked.size) return false;
      locked.clear();
      changed();
      return true;
    },
    counts: () => ({ hidden: hidden.size, locked: locked.size })
  };
}
