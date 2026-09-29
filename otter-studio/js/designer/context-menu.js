// context-menu.js - The designer's right-click menu.
//
// Built from the same actions and shortcuts as the keyboard and the command
// palette (designer/actions.js, designer/commands.js), so the hints shown here
// are the keys that really work.

import { ComponentSchema } from '../model/schema.js';
import { displayChord } from './commands.js';

export function createDesignerContextMenu({ uiModel, styles, actions, commands }) {
  const hint = (id) => {
    const command = commands.find(c => c.id === id);
    return command && command.keys.length ? displayChord(command.keys[0]) : '';
  };

  function open(x, y, comp) {
    close();
    const selected = actions.selection();
    const schema = ComponentSchema[comp.kind] || {};
    const sameParent = selected.length > 0 && selected.every(c => c.parentId === selected[0].parentId);
    const notRoot = comp.id !== uiModel.rootId;
    const pasteCount = actions.copiedStyleCount();
    const items = [
      comp.parentId && { label: 'Select parent', hint: hint('designer.selectParent'), run: actions.selectParent },
      comp.children?.length && { label: 'Select first child', hint: hint('designer.selectChild'), run: actions.selectFirstChild },
      '-',
      sameParent && { label: 'Wrap in row', hint: hint('designer.wrapRow'), run: () => actions.wrap('row') },
      sameParent && { label: 'Wrap in column', hint: hint('designer.wrapColumn'), run: () => actions.wrap('column') },
      sameParent && { label: 'Wrap in card', hint: '', run: () => actions.wrap('card') },
      schema.isContainer && notRoot && { label: 'Unwrap (keep children)', hint: hint('designer.unwrap'), run: actions.unwrap },
      (schema.isContainer || !notRoot) && { label: actions.isFreeLayout(comp) ? 'Flow Layout (in order)' : 'Free Layout (place anywhere)', run: () => actions.setFreeLayout(comp, !actions.isFreeLayout(comp)) },
      '-',
      notRoot && { label: 'Move before previous', hint: hint('designer.moveUp'), run: () => actions.moveAmongSiblings(-1) },
      notRoot && { label: 'Move after next', hint: hint('designer.moveDown'), run: () => actions.moveAmongSiblings(1) },
      notRoot && comp.parentId !== uiModel.rootId && { label: 'Move out of parent', hint: hint('designer.moveOut'), run: actions.moveOutOfParent },
      '-',
      { label: 'Copy styles', hint: hint('designer.copyStyles'), run: actions.copyStyles },
      pasteCount && { label: `Paste styles (${pasteCount})`, hint: hint('designer.pasteStyles'), run: actions.pasteStyles },
      { label: 'Clear styles here', hint: styles.isBaseContext() ? '' : styles.breakpoint.label, run: actions.clearStyles },
      '-',
      actions.canArrange(2) && { label: 'Align left edges', hint: hint('designer.alignLeft'), run: () => actions.align('left') },
      actions.canArrange(2) && { label: 'Align centres', hint: hint('designer.alignCenter'), run: () => actions.align('center') },
      actions.canArrange(2) && { label: 'Align top edges', hint: hint('designer.alignTop'), run: () => actions.align('top') },
      actions.canArrange(2) && { label: 'Align middles', hint: hint('designer.alignMiddle'), run: () => actions.align('middle') },
      actions.canArrange(3) && { label: 'Distribute horizontally', hint: hint('designer.distributeHorizontal'), run: () => actions.distribute('horizontal') },
      actions.canArrange(3) && { label: 'Distribute vertically', hint: hint('designer.distributeVertical'), run: () => actions.distribute('vertical') },
      '-',
      notRoot && { label: 'Copy', hint: hint('designer.copy'), run: actions.copySelection },
      { label: 'Paste', hint: hint('designer.paste'), run: actions.pasteSelection },
      notRoot && { label: 'Duplicate', hint: hint('designer.duplicate'), run: actions.duplicateSelection },
      notRoot && { label: 'Delete', hint: hint('designer.delete'), danger: true, run: actions.deleteSelection }
    ].filter(Boolean);

    // Drop leading, trailing and doubled separators.
    const cleaned = items.filter((item, i, arr) => item !== '-' || (i > 0 && i < arr.length - 1 && arr[i - 1] !== '-'));
    const menu = document.createElement('div');
    menu.className = 'designer-context-menu';
    menu.setAttribute('role', 'menu');
    for (const item of cleaned) {
      if (item === '-') {
        menu.appendChild(Object.assign(document.createElement('div'), { className: 'designer-menu-sep' }));
        continue;
      }
      const btn = document.createElement('button');
      btn.className = `designer-menu-item ${item.danger ? 'is-danger' : ''}`;
      btn.setAttribute('role', 'menuitem');
      btn.innerHTML = `<span>${escapeHtml(item.label)}</span><span class="designer-menu-hint">${escapeHtml(item.hint || '')}</span>`;
      btn.addEventListener('click', () => {
        close();
        item.run();
      });
      menu.appendChild(btn);
    }
    document.body.appendChild(menu);
    menu.style.left = `${Math.min(x, window.innerWidth - menu.offsetWidth - 8)}px`;
    menu.style.top = `${Math.min(y, window.innerHeight - menu.offsetHeight - 8)}px`;
    menu.querySelector('button')?.focus();
    setTimeout(() => {
      document.addEventListener('pointerdown', onOutside, true);
      document.addEventListener('keydown', onMenuKey, true);
    }, 0);
  }

  function onOutside(e) {
    if (!e.target.closest('.designer-context-menu')) close();
  }

  function onMenuKey(e) {
    const menu = document.querySelector('.designer-context-menu');
    if (!menu) return;
    const items = Array.from(menu.querySelectorAll('.designer-menu-item'));
    const idx = items.indexOf(document.activeElement);
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); }
    else if (e.key === 'ArrowDown') { e.preventDefault(); items[(idx + 1) % items.length]?.focus(); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); items[(idx - 1 + items.length) % items.length]?.focus(); }
  }

  function close() {
    document.querySelector('.designer-context-menu')?.remove();
    document.removeEventListener('pointerdown', onOutside, true);
    document.removeEventListener('keydown', onMenuKey, true);
  }

  return { open, close };
}

function escapeHtml(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
