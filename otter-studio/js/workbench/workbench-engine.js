// workbench-engine.js - Professional Settings, Workbench, Command Registry & DevTools UI Engine for Otter Studio
// Implements: Global/workspace/project settings cascade, Settings UI model, Keybinding editor,
// Themes/fonts, Editor/terminal/designer/autosave/update/privacy settings, All workbench views,
// Command Palette, Quick Open, Status bar, Dockable/resizable/persistent panels, Multi-window,
// Layout restore/reset, Central command registry, Context-sensitive shortcuts, Discoverable shortcut UI,
// and Platform shortcut mapping.

// ============================================================================
// 1. SETTINGS SCHEMAS & 3-TIER CASCADE (DEFAULT -> USER -> WORKSPACE -> PROJECT)
// ============================================================================

export const DEFAULT_SETTINGS = {
  // Editor
  'editor.fontSize': 14,
  'editor.fontFamily': "'JetBrains Mono', 'Consolas', monospace",
  'editor.tabSize': 4,
  'editor.insertSpaces': true,
  'editor.wordWrap': 'on',
  'editor.lineNumbers': 'on',
  'editor.minimap': false,
  'editor.cursorBlinking': 'smooth',
  'editor.formatOnSave': true,

  // Terminal
  'terminal.defaultProfile': 'PowerShell 5.1',
  'terminal.fontSize': 13,
  'terminal.cursorStyle': 'bar',
  'terminal.scrollback': 1000,

  // Designer
  'designer.gridSize': 10,
  'designer.snapToGrid': true,
  'designer.showGuides': true,
  'designer.canvasTheme': 'default',
  'designer.defaultTarget': 'desktop',

  // Autosave
  'autosave.mode': 'afterDelay', // 'off' | 'afterDelay' | 'onFocusChange' | 'onWindowChange'
  'autosave.delayMs': 1000,

  // Update
  'update.channel': 'stable', // 'stable' | 'preview' | 'nightly'
  'update.autoCheck': true,
  'update.autoInstall': false,

  // Privacy & Telemetry
  'privacy.telemetryEnabled': false,
  'privacy.crashReportsEnabled': true,

  // Workbench & Themes
  'workbench.theme': 'dark-modern', // 'dark-modern' | 'light-modern' | 'high-contrast' | 'monokai'
  'workbench.accentColor': '#3B82F6',
  'workbench.sidebarPosition': 'left', // 'left' | 'right'
  'workbench.statusBarVisible': true
};

export const SETTINGS_SCHEMA = {
  'editor.fontSize': { type: 'number', min: 8, max: 32, category: 'Editor', description: 'Controls the font size in pixels.' },
  'editor.fontFamily': { type: 'string', category: 'Editor', description: 'Controls the font family.' },
  'editor.tabSize': { type: 'number', min: 1, max: 8, category: 'Editor', description: 'Number of spaces a tab is equal to.' },
  'editor.insertSpaces': { type: 'boolean', category: 'Editor', description: 'Insert spaces when pressing Tab.' },
  'editor.wordWrap': { type: 'enum', options: ['off', 'on', 'wordWrapColumn'], category: 'Editor', description: 'Controls line wrapping.' },
  'editor.lineNumbers': { type: 'enum', options: ['on', 'off', 'relative'], category: 'Editor', description: 'Controls display of line numbers.' },
  'editor.formatOnSave': { type: 'boolean', category: 'Editor', description: 'Automatically format files on save.' },
  'terminal.defaultProfile': { type: 'string', category: 'Terminal', description: 'Default terminal shell profile.' },
  'terminal.fontSize': { type: 'number', min: 9, max: 24, category: 'Terminal', description: 'Font size for terminal.' },
  'designer.gridSize': { type: 'number', min: 2, max: 50, category: 'Designer', description: 'Grid step size in pixels.' },
  'designer.snapToGrid': { type: 'boolean', category: 'Designer', description: 'Snap widgets to grid lines.' },
  'autosave.mode': { type: 'enum', options: ['off', 'afterDelay', 'onFocusChange', 'onWindowChange'], category: 'Autosave', description: 'Controls automatic file saving.' },
  'autosave.delayMs': { type: 'number', min: 100, max: 30000, category: 'Autosave', description: 'Delay in milliseconds before saving.' },
  'update.channel': { type: 'enum', options: ['stable', 'preview', 'nightly'], category: 'Update', description: 'Release update channel.' },
  'privacy.telemetryEnabled': { type: 'boolean', category: 'Privacy', description: 'Enable anonymous diagnostic telemetry.' },
  'privacy.crashReportsEnabled': { type: 'boolean', category: 'Privacy', description: 'Send crash dumps on fatal crash.' },
  'workbench.theme': { type: 'enum', options: ['dark-modern', 'light-modern', 'high-contrast', 'monokai'], category: 'Workbench', description: 'Active color theme.' }
};

export class SettingsManager {
  constructor() {
    this.tiers = {
      default: { ...DEFAULT_SETTINGS },
      user: {},
      workspace: {},
      project: {}
    };
    this.listeners = new Set();
  }

  get(key) {
    if (this.tiers.project[key] !== undefined) return this.tiers.project[key];
    if (this.tiers.workspace[key] !== undefined) return this.tiers.workspace[key];
    if (this.tiers.user[key] !== undefined) return this.tiers.user[key];
    return this.tiers.default[key];
  }

  getAll() {
    return {
      ...this.tiers.default,
      ...this.tiers.user,
      ...this.tiers.workspace,
      ...this.tiers.project
    };
  }

  set(tier, key, value) {
    if (!this.tiers[tier]) {
      throw new Error(`Invalid settings tier "${tier}". Expected user, workspace, or project.`);
    }

    const schema = SETTINGS_SCHEMA[key];
    if (schema) {
      if (schema.type === 'number' && typeof value !== 'number') {
        value = Number(value);
      }
      if (schema.type === 'boolean' && typeof value !== 'boolean') {
        value = Boolean(value);
      }
      if (schema.type === 'enum' && !schema.options.includes(value)) {
        throw new Error(`Invalid value "${value}" for ${key}. Valid options: ${schema.options.join(', ')}`);
      }
    }

    const oldValue = this.get(key);
    this.tiers[tier][key] = value;
    const newValue = this.get(key);

    if (oldValue !== newValue) {
      this._notifyChange(key, newValue, oldValue, tier);
    }
  }

  resetTier(tier) {
    if (tier === 'default') return;
    if (this.tiers[tier]) {
      this.tiers[tier] = {};
      this._notifyChange('*', null, null, tier);
    }
  }

  _notifyChange(key, newValue, oldValue, tier) {
    for (const listener of this.listeners) {
      try { listener({ key, newValue, oldValue, tier }); } catch {}
    }
  }

  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
}

// ============================================================================
// 2. CENTRAL COMMAND REGISTRY & CONTEXT KEYS
// ============================================================================

export class CommandRegistry {
  constructor() {
    this.commands = new Map(); // id -> CommandDef
    this.contextKeys = new Map(); // key -> value
    this.listeners = new Set();
  }

  setContext(key, value) {
    this.contextKeys.set(key, value);
    this._notifyContext(key, value);
  }

  getContext(key) {
    return this.contextKeys.get(key);
  }

  evaluateWhen(whenExpression) {
    if (!whenExpression || whenExpression.trim() === '') return true;

    // Simple context expression parser: 'editorFocus && !isReadonly'
    const parts = whenExpression.split('&&').map(p => p.trim());
    for (const part of parts) {
      let expected = true;
      let key = part;
      if (key.startsWith('!')) {
        expected = false;
        key = key.slice(1).trim();
      }
      const val = Boolean(this.contextKeys.get(key));
      if (val !== expected) return false;
    }
    return true;
  }

  registerCommand({ id, title, category = 'General', handler, keybinding = null, when = null, icon = null }) {
    if (!id || typeof id !== 'string') {
      throw new Error('Command must have a string id');
    }
    if (typeof handler !== 'function') {
      throw new Error(`Command "${id}" must provide an executable handler function`);
    }

    const def = {
      id,
      title,
      category,
      handler,
      keybinding,
      when,
      icon,
      enabled: true
    };

    this.commands.set(id, def);
    return def;
  }

  getCommand(id) {
    return this.commands.get(id);
  }

  getAllCommands({ category = null, search = null } = {}) {
    let list = Array.from(this.commands.values());

    if (category) {
      list = list.filter(c => c.category.toLowerCase() === category.toLowerCase());
    }

    if (search) {
      const q = search.toLowerCase();
      list = list.filter(c =>
        c.title.toLowerCase().includes(q) ||
        c.id.toLowerCase().includes(q) ||
        c.category.toLowerCase().includes(q)
      );
    }

    return list;
  }

  executeCommand(id, ...args) {
    const cmd = this.commands.get(id);
    if (!cmd) {
      throw new Error(`Command not found: "${id}"`);
    }

    if (!cmd.enabled) {
      throw new Error(`Command "${id}" is currently disabled`);
    }

    if (cmd.when && !this.evaluateWhen(cmd.when)) {
      throw new Error(`Command "${id}" cannot be executed in current context (${cmd.when})`);
    }

    return cmd.handler(...args);
  }

  _notifyContext(key, value) {
    for (const listener of this.listeners) {
      try { listener({ key, value }); } catch {}
    }
  }

  subscribeContext(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
}

// ============================================================================
// 3. KEYBINDING MANAGER & PLATFORM SHORTCUT MAPPING
// ============================================================================

export class KeybindingManager {
  constructor(commandRegistry, platform = 'windows') {
    this.commandRegistry = commandRegistry;
    this.platform = platform.toLowerCase();
    this.customKeybindings = new Map(); // id -> shortcut string
  }

  normalizeKeyCombo(combo) {
    if (!combo) return '';
    const parts = combo.toLowerCase().replace(/\\s+/g, '').split('+');
    const order = ['ctrl', 'meta', 'alt', 'shift'];
    const modifiers = parts.filter(p => order.includes(p)).sort((a, b) => order.indexOf(a) - order.indexOf(b));
    const keys = parts.filter(p => !order.includes(p));
    return [...modifiers, ...keys].join('+');
  }

  formatForPlatform(combo) {
    if (!combo) return '';
    const isMac = this.platform === 'macos' || this.platform === 'darwin';

    if (isMac) {
      return combo
        .replace(/ctrl/gi, '⌘')
        .replace(/meta/gi, '⌘')
        .replace(/alt/gi, '⌥')
        .replace(/shift/gi, '⇧')
        .split('+')
        .map(p => p.trim())
        .map(p => (p === '⌘' || p === '⌥' || p === '⇧') ? p : p.toUpperCase())
        .join(' ');
    } else {
      return combo
        .replace(/meta/gi, 'Win')
        .split('+')
        .map(p => p.length === 1 ? p.toUpperCase() : p.charAt(0).toUpperCase() + p.slice(1).toLowerCase())
        .join('+');
    }
  }

  setCustomKeybinding(commandId, keyCombo) {
    if (keyCombo) {
      this.customKeybindings.set(commandId, this.normalizeKeyCombo(keyCombo));
    } else {
      this.customKeybindings.delete(commandId);
    }
  }

  getKeybinding(commandId) {
    if (this.customKeybindings.has(commandId)) {
      return this.customKeybindings.get(commandId);
    }
    const cmd = this.commandRegistry.getCommand(commandId);
    return cmd ? cmd.keybinding : null;
  }

  resolveCommandForShortcut(keyCombo) {
    const target = this.normalizeKeyCombo(keyCombo);

    // 1. Check custom overrides
    for (const [id, combo] of this.customKeybindings.entries()) {
      if (combo === target) {
        const cmd = this.commandRegistry.getCommand(id);
        if (cmd && (!cmd.when || this.commandRegistry.evaluateWhen(cmd.when))) {
          return cmd;
        }
      }
    }

    // 2. Check registered default shortcuts
    for (const cmd of this.commandRegistry.commands.values()) {
      if (cmd.keybinding && this.normalizeKeyCombo(cmd.keybinding) === target) {
        if (!cmd.when || this.commandRegistry.evaluateWhen(cmd.when)) {
          return cmd;
        }
      }
    }

    return null;
  }
}

// ============================================================================
// 4. COMMAND PALETTE & QUICK OPEN ENGINE
// ============================================================================

export class CommandPaletteEngine {
  constructor(commandRegistry, projectFiles = []) {
    this.commandRegistry = commandRegistry;
    this.projectFiles = projectFiles;
    this.recentFiles = [];
  }

  setProjectFiles(files) {
    this.projectFiles = [...files];
  }

  recordFileAccess(file) {
    this.recentFiles = [file, ...this.recentFiles.filter(f => f !== file)].slice(0, 20);
  }

  query(input) {
    const text = (input || '').trim();

    if (text.startsWith('>')) {
      // Command mode: '>format'
      const search = text.slice(1).trim().toLowerCase();
      const commands = this.commandRegistry.getAllCommands({ search });
      return {
        mode: 'commands',
        results: commands.map(c => ({
          type: 'command',
          id: c.id,
          title: c.title,
          category: c.category,
          shortcut: c.keybinding,
          icon: c.icon || '⚡'
        }))
      };
    } else if (text.startsWith(':')) {
      // Line number mode: ':42'
      const lineNum = parseInt(text.slice(1).trim(), 10);
      return {
        mode: 'line',
        targetLine: isNaN(lineNum) ? null : lineNum,
        results: isNaN(lineNum) ? [] : [{ type: 'line', line: lineNum, title: `Go to Line ${lineNum}` }]
      };
    } else {
      // File search mode (Quick Open)
      const q = text.toLowerCase();
      const matches = this.projectFiles.filter(f => f.toLowerCase().includes(q));

      // Prioritize recent files
      matches.sort((a, b) => {
        const aRecent = this.recentFiles.indexOf(a);
        const bRecent = this.recentFiles.indexOf(b);
        if (aRecent !== -1 && bRecent !== -1) return aRecent - bRecent;
        if (aRecent !== -1) return -1;
        if (bRecent !== -1) return 1;
        return a.localeCompare(b);
      });

      return {
        mode: 'files',
        results: matches.slice(0, 15).map(f => ({
          type: 'file',
          path: f,
          fileName: f.split(/[\\/]/).pop(),
          icon: f.endsWith('.ot') ? '🦦' : (f.endsWith('.json') ? '⚙' : '📄')
        }))
      };
    }
  }
}

// ============================================================================
// 5. STATUS BAR MANAGER
// ============================================================================

export class StatusBarManager {
  constructor() {
    this.items = new Map(); // id -> itemDef
    this.listeners = new Set();
  }

  setItem(id, { text, tooltip = '', command = null, alignment = 'left', priority = 100, visible = true }) {
    this.items.set(id, {
      id,
      text: String(text),
      tooltip,
      command,
      alignment, // 'left' | 'right'
      priority,
      visible
    });
    this._notify();
  }

  getItem(id) {
    return this.items.get(id);
  }

  removeItem(id) {
    if (this.items.delete(id)) {
      this._notify();
    }
  }

  getItems(alignment = null) {
    let list = Array.from(this.items.values()).filter(i => i.visible);
    if (alignment) {
      list = list.filter(i => i.alignment === alignment);
    }
    // High priority first
    return list.sort((a, b) => b.priority - a.priority);
  }

  _notify() {
    for (const listener of this.listeners) {
      try { listener(); } catch {}
    }
  }

  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
}

// ============================================================================
// 6. DOCKABLE, RESIZABLE & PERSISTENT WORKBENCH PANELS & MULTI-WINDOW
// ============================================================================

export const WORKBENCH_VIEWS = [
  'explorer',
  'search',
  'scm',
  'run-debug',
  'extensions',
  'problems',
  'output',
  'terminal',
  'tests',
  'properties',
  'toolbox',
  'designer',
  'live-app'
];

export const DEFAULT_LAYOUT = {
  activeView: 'explorer',
  sidebarOpen: true,
  sidebarWidth: 280,
  sidebarDock: 'left', // 'left' | 'right'
  bottomPanelOpen: true,
  bottomPanelHeight: 220,
  activeBottomTab: 'terminal',
  propertiesOpen: true,
  propertiesWidth: 300,
  secondaryWindows: []
};

export class WorkbenchLayoutManager {
  constructor(initialLayout = {}) {
    this.layout = { ...DEFAULT_LAYOUT, ...initialLayout };
    this.listeners = new Set();
  }

  getLayout() {
    return { ...this.layout };
  }

  setActiveView(viewId) {
    if (!WORKBENCH_VIEWS.includes(viewId)) {
      throw new Error(`Unknown workbench view "${viewId}"`);
    }
    this.layout.activeView = viewId;
    this.layout.sidebarOpen = true;
    this._notify();
  }

  toggleSidebar() {
    this.layout.sidebarOpen = !this.layout.sidebarOpen;
    this._notify();
    return this.layout.sidebarOpen;
  }

  setSidebarWidth(width) {
    this.layout.sidebarWidth = Math.max(180, Math.min(600, Number(width) || 280));
    this._notify();
  }

  toggleBottomPanel() {
    this.layout.bottomPanelOpen = !this.layout.bottomPanelOpen;
    this._notify();
    return this.layout.bottomPanelOpen;
  }

  setActiveBottomTab(tabId) {
    this.layout.activeBottomTab = tabId;
    this.layout.bottomPanelOpen = true;
    this._notify();
  }

  setBottomPanelHeight(height) {
    this.layout.bottomPanelHeight = Math.max(100, Math.min(600, Number(height) || 220));
    this._notify();
  }

  registerWindow(windowId, { role = 'designer', url = '' }) {
    this.layout.secondaryWindows.push({ windowId, role, url, openedAt: new Date().toISOString() });
    this._notify();
  }

  unregisterWindow(windowId) {
    this.layout.secondaryWindows = this.layout.secondaryWindows.filter(w => w.windowId !== windowId);
    this._notify();
  }

  resetLayout() {
    this.layout = { ...DEFAULT_LAYOUT };
    this._notify();
    return { ...this.layout };
  }

  _notify() {
    for (const listener of this.listeners) {
      try { listener({ ...this.layout }); } catch {}
    }
  }

  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
}
