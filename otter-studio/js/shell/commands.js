// commands.js - Studio's central command registry.
//
// Every user-facing action is a command: an id, a title, a category, an
// optional shortcut, and a function that runs it. The command palette
// (Ctrl+Shift+P / F1, or ">" in the header box) lists them, the Keyboard
// Shortcuts dialog documents them, and menus and buttons keep calling the
// same functions, so the three never disagree.

export function createCommandRegistry() {
  const commands = new Map();

  function register(command) {
    if (!command || !command.id || typeof command.run !== 'function') {
      throw new Error('A command needs an id and a run function.');
    }
    if (commands.has(command.id)) throw new Error(`Command "${command.id}" is registered twice.`);
    commands.set(command.id, {
      id: command.id,
      title: command.title || command.id,
      category: command.category || 'General',
      shortcut: command.shortcut || '',
      when: typeof command.when === 'function' ? command.when : null,
      run: command.run
    });
    return command.id;
  }

  function registerAll(list) {
    for (const command of list) register(command);
  }

  // Commands available right now, grouped for display.
  function list({ includeUnavailable = false } = {}) {
    return Array.from(commands.values())
      .filter(c => includeUnavailable || !c.when || c.when() !== false)
      .sort((a, b) => a.category.localeCompare(b.category) || a.title.localeCompare(b.title));
  }

  function get(id) {
    return commands.get(id) || null;
  }

  async function run(id, ...args) {
    const command = commands.get(id);
    if (!command) throw new Error(`Unknown command "${id}".`);
    if (command.when && command.when() === false) return false;
    await command.run(...args);
    return true;
  }

  // Items in the shape the navigation palette renders.
  function toPaletteItems() {
    return list().map(command => ({
      type: 'command',
      id: command.id,
      label: command.title,
      detail: command.category,
      icon: '›',
      shortcut: command.shortcut,
      run: () => run(command.id)
    }));
  }

  return { register, registerAll, list, get, run, toPaletteItems, size: () => commands.size };
}

// Normalise a shortcut for display: "ctrl+shift+p" -> "Ctrl+Shift+P".
export function formatShortcut(shortcut) {
  if (!shortcut) return '';
  return shortcut.split(' ').map(chord => chord.split('+').map(part => {
    const p = part.trim();
    if (!p) return '';
    if (p.length === 1) return p.toUpperCase();
    return p.charAt(0).toUpperCase() + p.slice(1);
  }).join('+')).join(' ');
}

// The commands Studio ships with. `deps` are the existing IDE entry points;
// nothing here implements behaviour, it only names and routes it.
export function defaultCommands(deps) {
  const { ide, setMode, openNewProjectModal, openSettings, openPackageDialog, openShortcuts, showWelcome, toggleTheme, byId } = deps;
  const click = (id) => () => byId(id)?.click();
  const hasProject = () => Boolean(ide.currentProjectFolder);
  return [
    // File
    { id: 'file.newProject', title: 'New Project...', category: 'File', shortcut: 'Ctrl+Shift+N', run: openNewProjectModal },
    { id: 'file.newFile', title: 'New File', category: 'File', shortcut: 'Ctrl+N', run: () => ide.promptNewFile() },
    { id: 'file.openFolder', title: 'Open Folder...', category: 'File', shortcut: 'Ctrl+O', run: () => ide.promptOpenFolder() },
    { id: 'file.save', title: 'Save', category: 'File', shortcut: 'Ctrl+S', run: () => ide.saveCurrentFile() },
    { id: 'file.projectSettings', title: 'Project Settings...', category: 'File', when: hasProject, run: () => ide.openProjectSettings() },
    { id: 'file.settings', title: 'Settings...', category: 'File', shortcut: 'Ctrl+,', run: openSettings },
    // Go
    { id: 'go.quickOpen', title: 'Go to File...', category: 'Go', shortcut: 'Ctrl+P', run: () => ide.openNavigationPalette('files') },
    { id: 'go.symbol', title: 'Go to Symbol in File...', category: 'Go', shortcut: 'Ctrl+Shift+O', run: () => ide.openNavigationPalette('symbols') },
    { id: 'go.workspaceSymbol', title: 'Go to Symbol in Workspace...', category: 'Go', shortcut: 'Ctrl+T', run: () => ide.openNavigationPalette('workspace-symbols') },
    { id: 'go.line', title: 'Go to Line...', category: 'Go', shortcut: 'Ctrl+G', run: () => ide.promptGoToLine() },
    { id: 'go.definition', title: 'Go to Definition', category: 'Go', shortcut: 'F12', run: () => ide.goToDefinition() },
    { id: 'go.references', title: 'Find References', category: 'Go', shortcut: 'Shift+Alt+F12', run: () => ide.findReferences() },
    { id: 'go.back', title: 'Go Back', category: 'Go', shortcut: 'Alt+Left', run: click('btnNavigateBack') },
    { id: 'go.forward', title: 'Go Forward', category: 'Go', shortcut: 'Alt+Right', run: click('btnNavigateForward') },
    // Edit
    { id: 'edit.find', title: 'Find', category: 'Edit', shortcut: 'Ctrl+F', run: () => ide.openFind(false) },
    { id: 'edit.replace', title: 'Replace', category: 'Edit', shortcut: 'Ctrl+H', run: () => ide.openFind(true) },
    { id: 'edit.format', title: 'Format Document', category: 'Edit', shortcut: 'Shift+Alt+F', run: () => ide.formatCurrentDocument() },
    { id: 'edit.toggleComment', title: 'Toggle Line Comment', category: 'Edit', shortcut: 'Ctrl+/', run: () => ide.toggleComment() },
    { id: 'edit.rename', title: 'Rename Symbol', category: 'Edit', shortcut: 'F2', run: () => ide.promptRename() },
    { id: 'edit.extractFunction', title: 'Extract Function', category: 'Edit', shortcut: 'Ctrl+Shift+R', run: () => ide.extractFunction() },
    { id: 'edit.wordWrap', title: 'Toggle Word Wrap', category: 'Edit', shortcut: 'Alt+Z', run: () => ide.setWordWrap(!ide.wordWrap) },
    // View
    { id: 'view.code', title: 'Show Code', category: 'View', run: () => setMode('code') },
    { id: 'view.designer', title: 'Show Designer', category: 'View', run: () => setMode('designer') },
    { id: 'view.split', title: 'Show Split (Designer over Code)', category: 'View', run: () => setMode('split') },
    { id: 'view.workbench', title: 'Show Designer Right', category: 'View', run: () => setMode('workbench') },
    { id: 'view.preview', title: 'Show Live App', category: 'View', run: () => setMode('preview') },
    { id: 'view.welcome', title: 'Welcome', category: 'View', run: showWelcome },
    { id: 'view.toggleTheme', title: 'Toggle Light/Dark Theme', category: 'View', run: toggleTheme },
    { id: 'view.filesPane', title: 'Show Files', category: 'View', run: click('btnPaneFiles') },
    { id: 'view.toolboxPane', title: 'Show Toolbox', category: 'View', run: click('btnPaneToolbox') },
    { id: 'view.searchPane', title: 'Search in Files', category: 'View', shortcut: 'Ctrl+Shift+F', run: click('btnPaneSearch') },
    // Run
    { id: 'run.run', title: 'Run', category: 'Run', shortcut: 'F5', run: click('mainRunBtn') },
    { id: 'run.debug', title: 'Debug', category: 'Run', run: click('btnDebugProgram') },
    { id: 'run.stop', title: 'Stop', category: 'Run', shortcut: 'Shift+F5', run: click('btnStopProgram') },
    // Build
    { id: 'build.desktopApp', title: 'Build Desktop App (Windows)...', category: 'Build', run: openPackageDialog },
    // Help
    { id: 'help.shortcuts', title: 'Keyboard Shortcuts', category: 'Help', run: openShortcuts },
    { id: 'help.commands', title: 'Show All Commands', category: 'Help', shortcut: 'F1', run: () => ide.openNavigationPalette('commands') },
    { id: 'help.documentation', title: 'Otter Documentation (open the docs project)', category: 'Help', run: () => ide.loadProjectTree('otter-docs') }
  ];
}
