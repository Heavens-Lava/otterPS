// more-menu.js - A button that opens a menu of actions (the editor's
// "More Actions" menu next to the tabs). The items are ordinary buttons with
// their own click handlers (bound elsewhere by id); this only opens, closes
// and moves focus: Enter/Space/Down open, Up/Down move, Esc closes, an item
// click runs it and closes.

export function installMoreMenu(button, menu) {
  if (!button || !menu) return null;
  const items = () => [...menu.querySelectorAll('[role="menuitem"]:not([disabled])')];

  function open() {
    menu.hidden = false;
    button.setAttribute('aria-expanded', 'true');
    button.classList.add('is-open');
    // Keep the menu on screen: right-aligned to the button.
    const r = button.getBoundingClientRect();
    menu.style.top = `${r.bottom + 4}px`;
    menu.style.left = `${Math.max(8, Math.min(r.right - menu.offsetWidth, window.innerWidth - menu.offsetWidth - 8))}px`;
    items()[0]?.focus();
    document.addEventListener('pointerdown', onOutside, true);
  }

  function close({ focusButton = false } = {}) {
    if (menu.hidden) return;
    menu.hidden = true;
    button.setAttribute('aria-expanded', 'false');
    button.classList.remove('is-open');
    document.removeEventListener('pointerdown', onOutside, true);
    if (focusButton) button.focus();
  }

  const onOutside = (e) => {
    if (!menu.contains(e.target) && !button.contains(e.target)) close();
  };

  button.addEventListener('click', () => (menu.hidden ? open() : close()));
  button.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' && menu.hidden) { e.preventDefault(); open(); }
  });
  menu.addEventListener('keydown', (e) => {
    const list = items();
    const at = list.indexOf(document.activeElement);
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close({ focusButton: true }); }
    else if (e.key === 'ArrowDown') { e.preventDefault(); list[(at + 1) % list.length]?.focus(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); list[(at - 1 + list.length) % list.length]?.focus(); }
    else if (e.key === 'Home') { e.preventDefault(); list[0]?.focus(); }
    else if (e.key === 'End') { e.preventDefault(); list[list.length - 1]?.focus(); }
    else if (e.key === 'Tab') close();
  });
  // Items run through their own handlers; the menu just gets out of the way
  // (after them, so the action sees the editor as it was).
  menu.addEventListener('click', (e) => {
    if (e.target.closest('[role="menuitem"]')) setTimeout(() => close(), 0);
  });
  window.addEventListener('resize', () => close());
  return { open, close };
}
