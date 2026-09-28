// keys.js - Keyboard chords as strings: "ctrl+shift+g", "alt+arrowup", "f11".
// "ctrl" means Cmd on a Mac. Shared by the designer keyboard, Studio's
// command keymap and the keybinding editor.

// The chord for a keydown event. Digits come from the physical key, so
// Shift+1 is "shift+1", not "!".
export function chordOf(event, isMac = false) {
  const parts = [];
  if (isMac ? event.metaKey : event.ctrlKey) parts.push('ctrl');
  if (event.altKey) parts.push('alt');
  if (event.shiftKey) parts.push('shift');
  let key = String(event.key || '').toLowerCase();
  const digit = /^Digit(\d)$/.exec(event.code || '');
  if (digit) key = digit[1];
  const letter = /^Key([A-Z])$/.exec(event.code || '');
  // With Alt held, some layouts turn letters into symbols; use the key cap.
  if (letter && event.altKey) key = letter[1].toLowerCase();
  if (key === ' ') key = 'space';
  if (!['control', 'alt', 'shift', 'meta'].includes(key)) parts.push(key);
  return parts.join('+');
}

// "ctrl+shift+arrowup" -> "Ctrl+Shift+Up" for display.
export function displayChord(chord) {
  const names = { arrowup: 'Up', arrowdown: 'Down', arrowleft: 'Left', arrowright: 'Right', escape: 'Esc', delete: 'Del', backspace: 'Backspace', enter: 'Enter', tab: 'Tab', space: 'Space' };
  return String(chord || '').split('+').filter(Boolean)
    .map(p => names[p] || (p.length === 1 ? p.toUpperCase() : p.charAt(0).toUpperCase() + p.slice(1)))
    .join('+');
}

// "Ctrl+Shift+G" or "ctrl + shift + g" -> "ctrl+shift+g"; null if not a chord.
export function parseChord(text) {
  const names = { up: 'arrowup', down: 'arrowdown', left: 'arrowleft', right: 'arrowright', esc: 'escape', del: 'delete', cmd: 'ctrl', control: 'ctrl', option: 'alt' };
  const parts = String(text || '').toLowerCase().split('+').map(p => p.trim()).filter(Boolean).map(p => names[p] || p);
  if (!parts.length) return null;
  const mods = ['ctrl', 'alt', 'shift'].filter(m => parts.includes(m));
  const keys = parts.filter(p => !['ctrl', 'alt', 'shift'].includes(p));
  if (keys.length !== 1) return null;
  return [...mods, keys[0]].join('+');
}

export function isMacPlatform() {
  return typeof navigator !== 'undefined' && /mac/i.test(navigator.platform || '');
}
