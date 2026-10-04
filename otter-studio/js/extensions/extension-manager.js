// extension-manager.js - Extensible Plugin and Architecture Engine for Otter Studio
export class OtterExtensionManager {
  constructor() {
    this.extensions = new Map();
    this.commands = new Map();
    this.keybindings = new Map();
    this.themes = new Map();
    this.panels = new Map();
    this.providers = new Map();
  }

  // --- Extension Registration & Lifecycle ---

  registerExtension(manifest, activateFn = null, deactivateFn = null) {
    if (!manifest || typeof manifest !== 'object' || !manifest.id) {
      throw new Error('Extension manifest must be an object with a unique "id"');
    }

    const id = manifest.id;
    if (this.extensions.has(id)) {
      this.unregisterExtension(id);
    }

    const record = {
      manifest: {
        id,
        name: manifest.name || id,
        version: manifest.version || '1.0.0',
        author: manifest.author || 'Anonymous',
        description: manifest.description || '',
        contributes: manifest.contributes || {}
      },
      activateFn,
      deactivateFn,
      state: 'inactive',
      disposables: [],
      error: null
    };

    this.extensions.set(id, record);

    // Register declared static contributions
    this._processContributions(record);

    return {
      id,
      activate: () => this.activateExtension(id),
      deactivate: () => this.deactivateExtension(id)
    };
  }

  activateExtension(id) {
    const record = this.extensions.get(id);
    if (!record) throw new Error(`Extension "${id}" is not registered`);
    if (record.state === 'active') return true;

    record.state = 'activating';
    record.error = null;

    try {
      if (typeof record.activateFn === 'function') {
        const context = {
          extensionId: id,
          subscriptions: record.disposables,
          registerCommand: (cmdId, handler) => this.registerCommand(cmdId, handler, record),
          registerTheme: (themeId, theme) => this.registerTheme(themeId, theme, record),
          registerPanel: (panelId, panel) => this.registerPanel(panelId, panel, record),
          registerProvider: (type, provider) => this.registerProvider(type, provider, record)
        };
        record.activateFn(context);
      }
      record.state = 'active';
      return true;
    } catch (err) {
      record.state = 'error';
      record.error = err.message;
      console.error(`[Extension Error] Failed to activate extension "${id}":`, err);
      return false;
    }
  }

  deactivateExtension(id) {
    const record = this.extensions.get(id);
    if (!record) return false;
    if (record.state !== 'active') return true;

    try {
      if (typeof record.deactivateFn === 'function') {
        record.deactivateFn();
      }
    } catch (err) {
      console.error(`[Extension Error] Error in deactivate for "${id}":`, err);
    }

    // Dispose active subscriptions
    for (const dispose of record.disposables) {
      try {
        if (typeof dispose === 'function') dispose();
      } catch {}
    }
    record.disposables = [];
    record.state = 'inactive';
    return true;
  }

  unregisterExtension(id) {
    this.deactivateExtension(id);

    // Clean up static contributions owned by this extension
    for (const [cmdId, cmd] of this.commands.entries()) {
      if (cmd.extensionId === id) this.commands.delete(cmdId);
    }
    for (const [themeId, theme] of this.themes.entries()) {
      if (theme.extensionId === id) this.themes.delete(themeId);
    }
    for (const [key, kb] of this.keybindings.entries()) {
      if (kb.extensionId === id) this.keybindings.delete(key);
    }
    for (const [panelId, panel] of this.panels.entries()) {
      if (panel.extensionId === id) this.panels.delete(panelId);
    }
    for (const [type, list] of this.providers.entries()) {
      this.providers.set(type, list.filter(e => e.extensionId !== id));
    }

    this.extensions.delete(id);
  }

  // --- Contribution Processors ---

  _processContributions(record) {
    const contributes = record.manifest.contributes;
    if (contributes.commands && Array.isArray(contributes.commands)) {
      for (const cmd of contributes.commands) {
        if (cmd.id && cmd.title) {
          this.commands.set(cmd.id, {
            id: cmd.id,
            title: cmd.title,
            category: cmd.category || 'General',
            handler: null,
            extensionId: record.manifest.id
          });
        }
      }
    }

    if (contributes.themes && Array.isArray(contributes.themes)) {
      for (const theme of contributes.themes) {
        if (theme.id && theme.colors) {
          this.themes.set(theme.id, { ...theme, extensionId: record.manifest.id });
        }
      }
    }

    if (contributes.keybindings && Array.isArray(contributes.keybindings)) {
      for (const kb of contributes.keybindings) {
        if (kb.key && kb.command) {
          this.keybindings.set(kb.key, { command: kb.command, extensionId: record.manifest.id });
        }
      }
    }
  }

  // --- Dynamic API Registrations ---

  registerCommand(cmdId, handler, ownerRecord = null) {
    const existing = this.commands.get(cmdId);
    const entry = {
      id: cmdId,
      title: existing?.title || cmdId,
      category: existing?.category || 'General',
      handler,
      extensionId: ownerRecord?.manifest?.id || 'dynamic'
    };
    this.commands.set(cmdId, entry);

    const dispose = () => {
      this.commands.delete(cmdId);
    };
    if (ownerRecord) ownerRecord.disposables.push(dispose);
    return dispose;
  }

  executeCommand(cmdId, ...args) {
    let cmd = this.commands.get(cmdId);
    if (!cmd) throw new Error(`Command "${cmdId}" not found`);

    // On-demand activation if extension is inactive
    if (typeof cmd.handler !== 'function' && cmd.extensionId && this.extensions.has(cmd.extensionId)) {
      const ext = this.extensions.get(cmd.extensionId);
      if (ext.state !== 'active') {
        this.activateExtension(cmd.extensionId);
        cmd = this.commands.get(cmdId);
      }
    }

    if (typeof cmd.handler !== 'function') throw new Error(`Command "${cmdId}" has no executable handler registered`);
    try {
      return cmd.handler(...args);
    } catch (err) {
      console.error(`[Extension Error] Execution of command "${cmdId}" failed:`, err);
      throw err;
    }
  }

  executeKeybinding(key, ...args) {
    const kb = this.keybindings.get(key);
    if (!kb) return false;
    return this.executeCommand(kb.command, ...args);
  }

  registerTheme(themeId, theme, ownerRecord = null) {
    this.themes.set(themeId, { ...theme, id: themeId, extensionId: ownerRecord?.manifest?.id || 'dynamic' });
    const dispose = () => this.themes.delete(themeId);
    if (ownerRecord) ownerRecord.disposables.push(dispose);
    return dispose;
  }

  getTheme(themeId) {
    return this.themes.get(themeId) || null;
  }

  registerPanel(panelId, panelConfig, ownerRecord = null) {
    this.panels.set(panelId, { ...panelConfig, id: panelId, extensionId: ownerRecord?.manifest?.id || 'dynamic' });
    const dispose = () => this.panels.delete(panelId);
    if (ownerRecord) ownerRecord.disposables.push(dispose);
    return dispose;
  }

  getPanels() {
    return Array.from(this.panels.values());
  }

  getPanel(panelId) {
    return this.panels.get(panelId) || null;
  }

  registerProvider(type, provider, ownerRecord = null) {
    if (!this.providers.has(type)) {
      this.providers.set(type, []);
    }
    const list = this.providers.get(type);
    const entry = { provider, extensionId: ownerRecord?.manifest?.id || 'dynamic' };
    list.push(entry);

    const dispose = () => {
      const current = this.providers.get(type) || [];
      this.providers.set(type, current.filter(e => e !== entry));
    };
    if (ownerRecord) ownerRecord.disposables.push(dispose);
    return dispose;
  }

  getProviders(type) {
    return (this.providers.get(type) || []).map(e => e.provider);
  }

  getExtensions() {
    return Array.from(this.extensions.values()).map(r => ({
      ...r.manifest,
      state: r.state,
      error: r.error
    }));
  }

  getExtension(id) {
    const record = this.extensions.get(id);
    if (!record) return null;
    return {
      ...record.manifest,
      state: record.state,
      error: record.error
    };
  }
}

export const extensionManager = new OtterExtensionManager();
