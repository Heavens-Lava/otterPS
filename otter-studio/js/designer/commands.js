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

// "ctrl+shift+arrowup" for a keydown event. Digits come from the physical key
// so Shift+1 is "shift+1", not "!".
export function chordOf(event, isMac = false) {
  const parts = [];
  if (isMac ? event.metaKey : event.ctrlKey) parts.push('ctrl');
  if (event.altKey) parts.push('alt');
  if (event.shiftKey) parts.push('shift');
  let key = String(event.key || '').toLowerCase();
  const digit = /^Digit(\d)$/.exec(event.code || '');
  if (digit) key = digit[1];
  if (key === ' ') key = 'space';
  if (!['control', 'alt', 'shift', 'meta'].includes(key)) parts.push(key);
  return parts.join('+');
}

// "ctrl+shift+arrowup" -> "Ctrl+Shift+Up" for display.
export function displayChord(chord) {
  const names = { arrowup: 'Up', arrowdown: 'Down', arrowleft: 'Left', arrowright: 'Right', escape: 'Esc', delete: 'Del', backspace: 'Backspace', enter: 'Enter', tab: 'Tab', '=': '=', '-': '-', '+': '+' };
  return chord.split('+').filter(Boolean).map(p => names[p] || (p.length === 1 ? p.toUpperCase() : p.charAt(0).toUpperCase() + p.slice(1))).join('+');
}

// Route keydown events to designer commands. `isActive()` decides whether the
// designer owns the keyboard right now (visible, pointer or focus inside, not
// typing in a field).
export function installDesignerKeyboard(commands, { isActive, target = window }) {
  const isMac = typeof navigator !== 'undefined' && /mac/i.test(navigator.platform || '');
  const byChord = new Map();
  for (const command of commands) {
    for (const key of command.keys) byChord.set(key, command);
  }
  const onKey = (event) => {
    if (event.defaultPrevented || !isActive(event)) return;
    const command = byChord.get(chordOf(event, isMac));
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
    shortcut: command.keys.length ? displayChord(command.keys[0]) : '',
    when: isAvailable,
    run: command.run
  }));
}
