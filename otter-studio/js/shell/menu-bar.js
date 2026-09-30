// menu-bar.js - The main menu bar (File, Edit, View, Go, Run, Build, Help),
// built from the command registry: every item runs a registered command,
// shows that command's current shortcut (so a rebound key shows up here
// too) and is greyed out when the command is not available right now.
//
// Before this, only File, Build and Help had menus; Edit, Run and View were
// labels that did nothing when clicked.
//
// Mouse: click a title to open it; while a menu is open, hovering another
// title switches to it. Keyboard: Enter/Space/Down open; Up/Down move;
// Left/Right switch menus; Home/End; Esc closes; Enter runs.

// A string is a command id; '-' a separator; { id, label } renames an item.
export const MENUS = [
  { id: 'file', label: 'File', items: [
    'file.newProject', 'file.newFile', 'file.newPage', 'file.openFolder', 'file.startWindow', '-',
    'file.save', 'file.saveAll', '-',
    'file.localHistory', { id: 'file.compareSaved', label: 'Compare with Saved' }, { id: 'file.compareHead', label: 'Compare with Last Commit' }, 'file.compareFile', '-',
    'file.projectSettings', 'file.newSolution', '-',
    'file.settings'
  ] },
  { id: 'edit', label: 'Edit', items: [
    'edit.undo', 'edit.redo', '-',
    'edit.find', 'edit.replace', 'view.searchPane', '-',
    'edit.toggleComment', 'edit.format', '-',
    { id: 'edit.rename', label: 'Rename Symbol...' }, { id: 'edit.extractFunction', label: 'Extract Function...' }, '-',
    'edit.toggleBookmark', 'edit.nextBookmark', 'edit.previousBookmark', '-',
    { id: 'edit.revertChange', label: 'Revert Change at Cursor' }
  ] },
  { id: 'view', label: 'View', items: [
    { id: 'view.code', label: 'Code' }, { id: 'view.designer', label: 'Designer' }, { id: 'view.split', label: 'Split' },
    { id: 'view.workbench', label: 'Designer Right' }, { id: 'view.preview', label: 'Live App' }, '-',
    { id: 'view.filesPane', label: 'Explorer' }, { id: 'view.searchPane', label: 'Search' }, { id: 'git.show', label: 'Source Control' },
    { id: 'view.toolboxPane', label: 'Toolbox' }, { id: 'view.tasks', label: 'Tasks' }, { id: 'run.tests', label: 'Tests' }, '-',
    { id: 'edit.wordWrap', label: 'Word Wrap' }, { id: 'view.renderWhitespace', label: 'Render Whitespace' }, '-',
    { id: 'view.zenMode', label: 'Zen Mode' }, { id: 'view.fullScreen', label: 'Full Screen' }, { id: 'view.toggleTheme', label: 'Toggle Light / Dark Theme' }
  ] },
  { id: 'go', label: 'Go', items: [
    'go.quickOpen', 'go.symbol', 'go.workspaceSymbol', 'go.line', '-',
    'go.definition', 'go.references', '-',
    'go.back', 'go.forward', '-',
    { id: 'edit.nextChange', label: 'Next Change' }, { id: 'edit.previousChange', label: 'Previous Change' }
  ] },
  { id: 'run', label: 'Run', items: [
    { id: 'run.run', label: 'Run Current File' }, 'run.project', { id: 'run.debug', label: 'Start Debugging' }, '-',
    'run.stop', 'run.restart', '-',
    'run.launchProfiles', { id: 'run.tests', label: 'Run Tests...' }
  ] },
  { id: 'build', label: 'Build', items: [
    'build.build', 'build.rebuild', 'build.clean', 'build.openWebsite', '-',
    'build.desktopApp', 'build.openPackagesFolder'
  ] },
  { id: 'help', label: 'Help', items: [
    'help.commands', 'help.shortcuts', '-',
    'view.welcome', { id: 'help.guide', label: 'Otter Guide' }, 'help.standardLibrary', 'help.releaseNotes', { id: 'help.documentation', label: 'Documentation Site Project' }, '-',
    'help.reportIssue'
  ] }
];

// 16 px line icons (stroke paths), in the style of the reference design.
const ICONS = {
  'file.newProject': 'M3 2.5h6l3.5 3.5v7.5h-9.5zM9 2.5V6h3.5M7.75 8v4M5.75 10h4',
  'file.newFile': 'M4 2.5h5l3 3v8H4zM9 2.5v3h3',
  'file.newPage': 'M2.5 3h11v10h-11zM2.5 5.5h11M8 7.5v4M6 9.5h4',
  'file.openFolder': 'M2 4.5v8h10.5l1.5-5.5H4.5L3 12.5M2 4.5h4l1.2 1.2H12v1.3',
  'file.startWindow': 'M2.5 3h11v10h-11zM2.5 6h11M6 8.5h5M6 10.5h3',
  'file.save': 'M3 2.5h8l2 2v9H3zM5.5 2.5v3h5v-3M5 13.5v-4h6v4',
  'file.saveAll': 'M4.5 4.5h7l1.5 1.5v7.5h-8.5zM2.5 11V2.5h7',
  'file.localHistory': 'M8 3a5 5 0 1 1-4.6 3M3 3v3h3M8 5.5V8l2 1.5',
  'file.compareSaved': 'M5.5 2.5v11M10.5 2.5v11M2.5 5h3M10.5 11h3M2.5 8h3M10.5 8h3',
  'file.projectSettings': 'M8 5.75a2.25 2.25 0 1 1 0 4.5 2.25 2.25 0 0 1 0-4.5zM8 1.5v2M8 12.5v2M14.5 8h-2M3.5 8h-2M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4M12.6 12.6l-1.4-1.4M4.8 4.8L3.4 3.4',
  'file.settings': 'M8 5.75a2.25 2.25 0 1 1 0 4.5 2.25 2.25 0 0 1 0-4.5zM8 1.5v2M8 12.5v2M14.5 8h-2M3.5 8h-2M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4M12.6 12.6l-1.4-1.4M4.8 4.8L3.4 3.4',
  'edit.undo': 'M5.5 4 2.5 7l3 3M2.5 7h7a3.5 3.5 0 0 1 0 7H8',
  'edit.redo': 'M10.5 4l3 3-3 3M13.5 7h-7a3.5 3.5 0 0 0 0 7H8',
  'edit.find': 'M7 2.75a4.25 4.25 0 1 1 0 8.5 4.25 4.25 0 0 1 0-8.5zM10.2 10.2l3.3 3.3',
  'edit.replace': 'M2.5 5.5h7l-2-2M13.5 10.5h-7l2 2',
  'view.searchPane': 'M7 2.75a4.25 4.25 0 1 1 0 8.5 4.25 4.25 0 0 1 0-8.5zM10.2 10.2l3.3 3.3',
  'edit.toggleComment': 'M5.5 3.5 3 12.5M9 3.5 6.5 12.5M10.5 8h3',
  'edit.format': 'M2.5 4h11M5 7h8.5M5 10h8.5M2.5 13h11',
  'edit.rename': 'M10.5 2.5l3 3-8 8h-3v-3zM9 4l3 3',
  'edit.extractFunction': 'M5 3.5c-1.5 0-2 .8-2 2v1.25c0 .7-.5 1.25-1 1.25.5 0 1 .55 1 1.25v1.25c0 1.2.5 2 2 2M11 3.5c1.5 0 2 .8 2 2v1.25c0 .7.5 1.25 1 1.25-.5 0-1 .55-1 1.25v1.25c0 1.2-.5 2-2 2',
  'edit.toggleBookmark': 'M4.5 2.5h7v11l-3.5-2.5-3.5 2.5z',
  'view.code': 'M5.5 4.5 2 8l3.5 3.5M10.5 4.5 14 8l-3.5 3.5',
  'view.designer': 'M2.5 2.5h11v11h-11zM2.5 6h11M6 6v7.5',
  'view.split': 'M2.5 2.5h11v11h-11zM2.5 8h11',
  'view.workbench': 'M2.5 2.5h11v11h-11zM9.5 2.5v11',
  'view.preview': 'M8 2.75a5.25 5.25 0 1 1 0 10.5 5.25 5.25 0 0 1 0-10.5zM6.75 5.75v4.5L10.5 8z',
  'view.filesPane': 'M4 2.5h5l3 3v8H4zM9 2.5v3h3',
  'git.show': 'M5 3.5v9M5 12.5a1.5 1.5 0 1 0 0 .01M5 3.5a1.5 1.5 0 1 0 0 .01M11 5a1.5 1.5 0 1 0 0 .01M11 6.5c0 3-6 2-6 4.5',
  'view.toolboxPane': 'M2.5 2.5h4.5v4.5H2.5zM9 2.5h4.5v4.5H9zM2.5 9h4.5v4.5H2.5zM9 9h4.5v4.5H9z',
  'view.tasks': 'M2.5 4l1.5 1.5L6.5 3M8.5 4.5h5M2.5 9.5 4 11l2.5-2.5M8.5 10h5',
  'view.zenMode': 'M2.5 6V2.5H6M10 2.5h3.5V6M13.5 10v3.5H10M6 13.5H2.5V10',
  'view.fullScreen': 'M2.5 6V2.5H6M10 2.5h3.5V6M13.5 10v3.5H10M6 13.5H2.5V10',
  'view.toggleTheme': 'M8 2.5a5.5 5.5 0 1 0 5.2 7.3A4.5 4.5 0 0 1 8 2.5z',
  'go.quickOpen': 'M4 2.5h5l3 3v8H4zM9 2.5v3h3',
  'go.symbol': 'M4.5 5.5 8 3l3.5 2.5v5L8 13l-3.5-2.5z',
  'go.workspaceSymbol': 'M4.5 5.5 8 3l3.5 2.5v5L8 13l-3.5-2.5z',
  'go.line': 'M3 4.5h10M3 8h6M3 11.5h10',
  'go.definition': 'M6 3.5h6.5V10M12.5 3.5 4 12',
  'go.references': 'M3 4.5h10M3 8h10M3 11.5h6',
  'go.back': 'M10 3 5 8l5 5',
  'go.forward': 'M6 3l5 5-5 5',
  'run.run': 'M5 3.5v9l7-4.5z',
  'run.project': 'M5 3.5v9l7-4.5z',
  'run.debug': 'M5.5 5.5a2.5 2.5 0 0 1 5 0M4.5 7h7v3.5a3.5 3.5 0 0 1-7 0zM8 7v7M2 8.5h2.5M11.5 8.5H14',
  'run.stop': 'M4 4h8v8H4z',
  'run.restart': 'M12.5 8A4.5 4.5 0 1 1 11 4.6M11.5 2v3h-3',
  'run.tests': 'M6 2.5h4M7 2.5v4L3.5 12.5a.8.8 0 0 0 .7 1.2h7.6a.8.8 0 0 0 .7-1.2L9 6.5v-4',
  'build.build': 'M9.5 3.5l3 3-7 7-3-3zM11 2l3 3',
  'build.openWebsite': 'M8 2.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11zM2.5 8h11M8 2.5c1.5 1.6 2.2 3.4 2.2 5.5S9.5 11.9 8 13.5M8 2.5C6.5 4.1 5.8 5.9 5.8 8s.7 3.9 2.2 5.5',
  'build.rebuild': 'M12.5 8A4.5 4.5 0 1 1 11 4.6M11.5 2v3h-3',
  'build.desktopApp': 'M2.5 3h11v8h-11zM6 13.5h4M8 11v2.5',
  'build.openPackagesFolder': 'M2 4.5v8h10.5l1.5-5.5H4.5L3 12.5M2 4.5h4l1.2 1.2H12v1.3',
  'help.commands': 'M4 5.5 7 8l-3 2.5M8.5 11h4',
  'help.shortcuts': 'M2 4.5h12v7H2zM4.5 7h1M7.5 7h1M10.5 7h1M5 9.5h6',
  'view.welcome': 'M2.5 7.5 8 3l5.5 4.5M4 6.5v7h8v-7',
  'help.guide': 'M8 4.5c-1.5-1-3.5-1.5-5.5-1.5v9.5c2 0 4 .5 5.5 1.5 1.5-1 3.5-1.5 5.5-1.5V3c-2 0-4 .5-5.5 1.5zM8 4.5v9',
  'help.standardLibrary': 'M3 2.5h3v11H3zM7 2.5h3v11H7zM11 3.5l2.5-.5 1.5 10-2.5.5z',
  'help.releaseNotes': 'M3.5 2.5h9v11h-9zM5.5 5.5h5M5.5 8h5M5.5 10.5h3',
  'help.documentation': 'M8 4.5c-1.5-1-3.5-1.5-5.5-1.5v9.5c2 0 4 .5 5.5 1.5 1.5-1 3.5-1.5 5.5-1.5V3c-2 0-4 .5-5.5 1.5zM8 4.5v9',
  'help.reportIssue': 'M8 2.5 14 13H2zM8 6.5v3M8 11.25v.25'
};
ICONS['file.compareHead'] = ICONS['file.compareSaved'];
ICONS['file.compareFile'] = ICONS['file.compareSaved'];
ICONS['file.newSolution'] = ICONS['file.newProject'];
ICONS['build.clean'] = 'M3 13.5h10M5 13.5l1-6h4l1 6M7 7.5V2.5h2v5';
ICONS['run.launchProfiles'] = ICONS['file.settings'];

const svg = (d) => `<svg viewBox="0 0 16 16" aria-hidden="true"><path d="${d}" /></svg>`;
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

export function mountMenuBar(nav, commands) {
  if (!nav) return null;
  let openIndex = -1;

  nav.innerHTML = MENUS.map((menu, i) => `
    <div class="menu-item mb-menu" data-menu="${menu.id}">
      <button type="button" class="mb-trigger" id="menu-${menu.id}" aria-haspopup="menu" aria-expanded="false" data-index="${i}">${esc(menu.label)}</button>
      <div class="mb-dropdown" role="menu" aria-labelledby="menu-${menu.id}" hidden></div>
    </div>`).join('');
  const triggers = [...nav.querySelectorAll('.mb-trigger')];
  const dropdowns = [...nav.querySelectorAll('.mb-dropdown')];

  // Built on each open: availability and shortcuts are read at that moment.
  function fill(i) {
    dropdowns[i].innerHTML = MENUS[i].items.map((entry) => {
      if (entry === '-') return '<div class="mb-sep" role="separator"></div>';
      const id = typeof entry === 'string' ? entry : entry.id;
      const command = commands.get(id);
      if (!command) return '';
      const label = (typeof entry === 'object' && entry.label) || command.title;
      const enabled = !command.when || command.when() !== false;
      return `<button type="button" class="mb-item" role="menuitem" data-command="${esc(id)}"${enabled ? '' : ' aria-disabled="true"'}>
        <span class="mb-icon">${ICONS[id] ? svg(ICONS[id]) : ''}</span>
        <span class="mb-label">${esc(label)}</span>
        <kbd class="mb-key">${esc(command.shortcut || '')}</kbd>
      </button>`;
    }).join('')
      // No separator first, last or twice in a row (after unknown ids).
      .replace(/^(\s*<div class="mb-sep"[^>]*><\/div>)+/, '')
      .replace(/(<div class="mb-sep"[^>]*><\/div>\s*)+$/, '')
      .replace(/(<div class="mb-sep"[^>]*><\/div>\s*){2,}/g, '<div class="mb-sep" role="separator"></div>');
  }

  const items = (i) => [...dropdowns[i].querySelectorAll('.mb-item:not([aria-disabled])')];

  function open(i, { focus = 'none' } = {}) {
    if (openIndex !== -1 && openIndex !== i) close({ keepListener: true });
    openIndex = i;
    fill(i);
    dropdowns[i].hidden = false;
    triggers[i].setAttribute('aria-expanded', 'true');
    triggers[i].parentElement.classList.add('is-open');
    // Keep the menu inside the window.
    const d = dropdowns[i];
    d.style.left = '0px';
    const overflow = d.getBoundingClientRect().right - (window.innerWidth - 8);
    if (overflow > 0) d.style.left = `${-overflow}px`;
    if (focus === 'first') items(i)[0]?.focus();
    else if (focus === 'last') items(i).at(-1)?.focus();
    document.addEventListener('pointerdown', onOutside, true);
    document.addEventListener('keydown', onEscape, true);
  }

  function close({ keepListener = false, focusTrigger = false } = {}) {
    if (openIndex === -1) return;
    const i = openIndex;
    dropdowns[i].hidden = true;
    triggers[i].setAttribute('aria-expanded', 'false');
    triggers[i].parentElement.classList.remove('is-open');
    openIndex = -1;
    if (!keepListener) {
      document.removeEventListener('pointerdown', onOutside, true);
      document.removeEventListener('keydown', onEscape, true);
    }
    if (focusTrigger) triggers[i].focus();
  }

  const onOutside = (e) => { if (!nav.contains(e.target)) close(); };
  // Esc closes a menu opened with the mouse too (focus is not inside it).
  const onEscape = (e) => {
    if (e.key !== 'Escape' || openIndex === -1) return;
    e.preventDefault();
    e.stopPropagation();
    close({ focusTrigger: nav.contains(document.activeElement) });
  };

  async function runItem(button) {
    if (!button || button.getAttribute('aria-disabled') === 'true') return;
    close();
    try {
      await commands.run(button.dataset.command);
    } catch (err) {
      console.error(err);
    }
  }

  triggers.forEach((trigger, i) => {
    trigger.addEventListener('click', (e) => {
      e.stopPropagation();
      if (openIndex === i) close(); else open(i);
    });
    // Moving across the bar while a menu is open switches menus.
    trigger.addEventListener('pointerenter', () => { if (openIndex !== -1 && openIndex !== i) open(i); });
    trigger.addEventListener('keydown', (e) => {
      if (['ArrowDown', 'Enter', ' '].includes(e.key)) { e.preventDefault(); open(i, { focus: 'first' }); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); open(i, { focus: 'last' }); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); triggers[(i + 1) % triggers.length].focus(); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); triggers[(i - 1 + triggers.length) % triggers.length].focus(); }
    });
  });

  dropdowns.forEach((dropdown, i) => {
    dropdown.addEventListener('click', (e) => runItem(e.target.closest('.mb-item')));
    dropdown.addEventListener('pointermove', (e) => {
      const item = e.target.closest('.mb-item:not([aria-disabled])');
      if (item && document.activeElement !== item) item.focus({ preventScroll: true });
    });
    dropdown.addEventListener('keydown', (e) => {
      const list = items(i);
      const at = list.indexOf(document.activeElement);
      const move = (to) => { e.preventDefault(); list[(to + list.length) % list.length]?.focus(); };
      if (e.key === 'ArrowDown') move(at + 1);
      else if (e.key === 'ArrowUp') move(at - 1);
      else if (e.key === 'Home') move(0);
      else if (e.key === 'End') move(list.length - 1);
      else if (e.key === 'ArrowRight') { e.preventDefault(); open((i + 1) % MENUS.length, { focus: 'first' }); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); open((i - 1 + MENUS.length) % MENUS.length, { focus: 'first' }); }
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close({ focusTrigger: true }); }
      else if (e.key === 'Tab') close();
      else if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); runItem(document.activeElement.closest('.mb-item')); }
    });
  });

  window.addEventListener('resize', () => close());
  window.addEventListener('blur', () => close());
  return { open, close, isOpen: () => openIndex !== -1 };
}
