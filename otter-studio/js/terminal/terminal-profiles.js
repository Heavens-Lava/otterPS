// terminal-profiles.js - Terminal Profiles and Shell Configuration for Otter Studio

/**
 * Standard built-in terminal profiles.
 */
export const DEFAULT_PROFILES = [
  {
    id: 'powershell-5',
    name: 'PowerShell 5.1 (Windows)',
    shell: 'powershell.exe',
    args: ['-NoLogo', '-NoProfile'],
    icon: 'terminal-ps',
    isDefault: true,
    env: {}
  },
  {
    id: 'powershell-7',
    name: 'PowerShell 7 (Core)',
    shell: 'pwsh.exe',
    args: ['-NoLogo'],
    icon: 'terminal-pwsh',
    isDefault: false,
    env: {}
  },
  {
    id: 'cmd',
    name: 'Command Prompt',
    shell: 'cmd.exe',
    args: ['/Q'],
    icon: 'terminal-cmd',
    isDefault: false,
    env: {}
  },
  {
    id: 'bash',
    name: 'Bash / Git Bash',
    shell: 'bash.exe',
    args: ['--login', '-i'],
    icon: 'terminal-bash',
    isDefault: false,
    env: {}
  },
  {
    id: 'wsl',
    name: 'WSL (Windows Subsystem for Linux)',
    shell: 'wsl.exe',
    args: ['--cd', '~'],
    icon: 'terminal-linux',
    isDefault: false,
    env: {}
  },
  {
    id: 'otter-repl',
    name: 'Otter REPL',
    shell: 'powershell.exe',
    args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'otter.ps1', 'repl'],
    icon: 'otter-icon',
    isDefault: false,
    env: {}
  }
];

export class TerminalProfileManager {
  constructor(customProfiles = []) {
    this.profiles = new Map();
    for (const p of DEFAULT_PROFILES) {
      this.profiles.set(p.id, { ...p });
    }
    for (const cp of customProfiles) {
      if (cp && cp.id) {
        this.profiles.set(cp.id, { ...cp });
      }
    }
    this.defaultProfileId = 'powershell-5';
  }

  /**
   * Retrieves all available profiles as an array.
   */
  getAllProfiles() {
    return Array.from(this.profiles.values());
  }

  /**
   * Gets a specific profile by ID.
   */
  getProfile(id) {
    return this.profiles.get(id) || null;
  }

  /**
   * Gets the active default profile.
   */
  getDefaultProfile() {
    return this.profiles.get(this.defaultProfileId) || this.profiles.get('powershell-5') || DEFAULT_PROFILES[0];
  }

  /**
   * Sets the default profile.
   */
  setDefaultProfile(id) {
    if (!this.profiles.has(id)) {
      throw new Error(`Terminal profile not found: ${id}`);
    }
    this.defaultProfileId = id;
    for (const p of this.profiles.values()) {
      p.isDefault = (p.id === id);
    }
  }

  /**
   * Adds or updates a custom profile.
   */
  addProfile(profile) {
    if (!profile || !profile.id || !profile.shell) {
      throw new Error('Profile must specify id and shell path');
    }
    const validated = {
      id: String(profile.id).trim(),
      name: String(profile.name || profile.id).trim(),
      shell: String(profile.shell).trim(),
      args: Array.isArray(profile.args) ? profile.args.map(String) : [],
      icon: profile.icon || 'terminal',
      isDefault: Boolean(profile.isDefault),
      env: profile.env && typeof profile.env === 'object' ? { ...profile.env } : {}
    };
    this.profiles.set(validated.id, validated);
    if (validated.isDefault) {
      this.setDefaultProfile(validated.id);
    }
    return validated;
  }

  /**
   * Removes a custom profile by ID. Built-in default cannot be deleted.
   */
  removeProfile(id) {
    if (id === 'powershell-5') {
      throw new Error('Cannot remove primary built-in profile: powershell-5');
    }
    if (this.defaultProfileId === id) {
      this.defaultProfileId = 'powershell-5';
    }
    return this.profiles.delete(id);
  }
}
