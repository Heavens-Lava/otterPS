// commands.js - The designer's commands and their keyboard shortcuts.
//
// One list drives three things: the keyboard (installDesignerKeyboard), the
// command palette and the Keyboard Shortcuts dialog (registered into Studio's
// command registry, shell/commands.js). Each command calls an action from
// designer/actions.js.
//
// `keys` are chords as "ctrl+shift+g" ("ctrl" is Cmd on a Mac); the first one
// is shown as the shortcut. A command whose action returns false (nothing to
// do) leaves the key alone, so e.g. arrows still scroll when nothing moves.

import { chordOf, displayChord, isMacPlatform } from '../shell/keys.js';

export function designerCommands(actions) {
  const a = actions;
  return [
    // Edit
    { id: 'designer.undo', title: 'Undo', keys: ['ctrl+z'], run: a.undo },
    { id: 'designer.redo', title: 'Redo', keys: ['ctrl+y', 'ctrl+shift+z'], run: a.redo },
    { id: 'designer.duplicate', title: 'Duplicate', keys: ['ctrl+d'], run: a.duplicateSelection },
    { id: 'designer.delete', title: 'Delete', keys: ['delete', 'backspace'], run: a.deleteSelection },
    { id: 'designer.copyStyles', title: 'Copy Styles', keys: ['ctrl+alt+c'], run: a.copyStyles },
    { id: 'designer.pasteStyles', title: 'Paste Styles', keys: ['ctrl+alt+v'], run: a.pasteStyles },
    { id: 'designer.clearStyles', title: 'Clear Styles Here', keys: [], run: a.clearStyles },
    // Structure
    { id: 'designer.wrapColumn', title: 'Wrap in Column', keys: ['ctrl+g'], run: () => a.wrap('column') },
    { id: 'designer.wrapRow', title: 'Wrap in Row', keys: ['ctrl+shift+g'], run: () => a.wrap('row') },
    { id: 'designer.wrapCard', title: 'Wrap in Card', keys: [], run: () => a.wrap('card') },
    { id: 'designer.unwrap', title: 'Unwrap (Keep Children)', keys: ['ctrl+alt+g'], run: a.unwrap },
    { id: 'designer.moveUp', title: 'Move Before Previous Sibling', keys: ['ctrl+arrowup', 'alt+arrowup', 'alt+arrowleft'], run: () => a.moveAmongSiblings(-1) },
    { id: 'designer.moveDown', title: 'Move After Next Sibling', keys: ['ctrl+arrowdown', 'alt+arrowdown', 'alt+arrowright'], run: () => a.moveAmongSiblings(1) },
    { id: 'designer.moveOut', title: 'Move Out of Parent', keys: ['ctrl+arrowleft'], run: a.moveOutOfParent },
    { id: 'designer.moveIn', title: 'Move Into Previous Container', keys: ['ctrl+arrowright'], run: a.moveIntoPrevious },
    // Layers (designer only: never written to the program)
    { id: 'designer.toggleHidden', title: 'Hide / Show on Canvas', keys: ['ctrl+shift+h'], run: a.toggleHidden },
    { id: 'designer.toggleLocked', title: 'Lock / Unlock on Canvas', keys: ['ctrl+shift+l'], run: a.toggleLocked },
    { id: 'designer.showAll', title: 'Show All Hidden Components', keys: [], run: a.showAll },
    { id: 'designer.unlockAll', title: 'Unlock All Components', keys: [], run: a.unlockAll },
    // Selection
    { id: 'designer.selectAll', title: 'Select All Siblings', keys: ['ctrl+a'], run: a.selectAllSiblings },
    { id: 'designer.selectParent', title: 'Select Parent', keys: ['escape', 'shift+enter'], run: a.selectParent },
    { id: 'designer.selectChild', title: 'Select First Child', keys: ['enter'], run: a.selectFirstChild },
    { id: 'designer.selectNext', title: 'Select Next Sibling', keys: ['tab'], run: () => a.selectSibling(1) },
    { id: 'designer.selectPrevious', title: 'Select Previous Sibling', keys: ['shift+tab'], run: () => a.selectSibling(-1) },
    // Position (absolutely positioned elements)
    { id: 'designer.nudgeLeft', title: 'Nudge Left', keys: ['arrowleft'], run: () => a.nudge(-1, 0) },
    { id: 'designer.nudgeRight', title: 'Nudge Right', keys: ['arrowright'], run: () => a.nudge(1, 0) },
    { id: 'designer.nudgeUp', title: 'Nudge Up', keys: ['arrowup'], run: () => a.nudge(0, -1) },
    { id: 'designer.nudgeDown', title: 'Nudge Down', keys: ['arrowdown'], run: () => a.nudge(0, 1) },
    { id: 'designer.nudgeLeft10', title: 'Nudge Left 10px', keys: ['shift+arrowleft'], run: () => a.nudge(-10, 0) },
    { id: 'designer.nudgeRight10', title: 'Nudge Right 10px', keys: ['shift+arrowright'], run: () => a.nudge(10, 0) },
    { id: 'designer.nudgeUp10', title: 'Nudge Up 10px', keys: ['shift+arrowup'], run: () => a.nudge(0, -10) },
    { id: 'designer.nudgeDown10', title: 'Nudge Down 10px', keys: ['shift+arrowdown'], run: () => a.nudge(0, 10) },
    // View
    { id: 'designer.zoomIn', title: 'Zoom In', keys: ['ctrl+=', 'ctrl++'], run: a.zoomIn },
    { id: 'designer.zoomOut', title: 'Zoom Out', keys: ['ctrl+-'], run: a.zoomOut },
    { id: 'designer.zoomReset', title: 'Zoom to 100%', keys: ['ctrl+0'], run: a.zoomReset },
    { id: 'designer.zoomFit', title: 'Zoom to Fit', keys: ['shift+1'], run: a.zoomToFit },
    { id: 'designer.zoomSelection', title: 'Zoom to Selection', keys: ['shift+2'], run: a.zoomToSelection }
  ];
}

// Chords are shared with the rest of Studio (shell/keys.js).
export { chordOf, displayChord } from '../shell/keys.js';

// Route keydown events to designer commands. `isActive()` decides whether the
// designer owns the keyboard right now (visible, pointer or focus inside, not
// typing in a field).
export function installDesignerKeyboard(commands, { isActive, target = window, keysOf = null }) {
  const isMac = isMacPlatform();
  // Keys are looked up at key time, so the keybinding editor's changes
  // (Studio's command registry) apply at once.
  const liveKeys = keysOf || ((command) => (typeof window !== 'undefined' && window.otterCommands?.get(command.id)?.keys) || command.keys);
  const onKey = (event) => {
    if (event.defaultPrevented || !isActive(event)) return;
    const chord = chordOf(event, isMac);
    const command = commands.find(c => liveKeys(c).includes(chord));
    if (!command) return;
    if (command.run() !== false) event.preventDefault();
  };
  target.addEventListener('keydown', onKey);
  return () => target.removeEventListener('keydown', onKey);
}

// Designer commands in the shape Studio's command registry takes.
export function toRegistryCommands(commands, isAvailable) {
  return commands.map(command => ({
    id: command.id,
    title: command.title,
    category: 'Designer',
    keys: command.keys,
    scope: 'designer',
    rebindable: true,
    when: isAvailable,
    run: command.run
  }));
}
