// first-run-manager.js - Otter Studio First-Run, Welcome Experience, Toolchain Detection, and File Associations
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

/**
 * 1. Curated Sample Projects Catalog
 */
export const SAMPLE_PROJECTS = [
  {
    id: 'sample-counter',
    name: 'Counter App',
    category: 'desktop',
    description: 'Interactive Desktop counter app demonstrating reactive button clicks, state mutation, and visual layout.',
    entryPoint: 'examples/counter.ot',
    tags: ['Desktop', 'UI', 'Events']
  },
  {
    id: 'sample-file-organizer',
    name: 'File Organizer CLI',
    category: 'console',
    description: 'Command line file organization tool demonstrating directory scanning, path parsing, and file sorting.',
    entryPoint: 'examples/file-organizer/main.ot',
    tags: ['Console', 'Filesystem', 'CLI']
  },
  {
    id: 'sample-game-2d',
    name: '2D Bouncing Otter',
    category: 'game',
    description: '2D canvas physics simulation showcasing high-FPS game loop, sprite motion, and collision detection.',
    entryPoint: 'examples/game-2d.ot',
    tags: ['Game', '2D', 'Canvas', '60 FPS']
  },
  {
    id: 'sample-web-portfolio',
    name: 'Portfolio Web Application',
    category: 'web',
    description: 'Responsive web application featuring declarative navigation, dark mode themes, and reactive components.',
    entryPoint: 'examples/web-portfolio.ot',
    tags: ['Web', 'Responsive', 'CSS']
  }
];

/**
 * 2. Welcome Experience Manager
 */
export class WelcomeManager {
  constructor(options = {}) {
    this.showOnStartupKey = options.showOnStartupKey || 'otter_studio_show_welcome';
    this.storage = options.storage || (typeof localStorage !== 'undefined' ? localStorage : new Map());
  }

  shouldShowOnStartup() {
    if (this.storage instanceof Map) {
      const val = this.storage.get(this.showOnStartupKey);
      return val !== 'false';
    }
    try {
      const val = this.storage.getItem(this.showOnStartupKey);
      return val !== 'false';
    } catch {
      return true;
    }
  }

  setShowOnStartup(show) {
    const strVal = show ? 'true' : 'false';
    if (this.storage instanceof Map) {
      this.storage.set(this.showOnStartupKey, strVal);
      return;
    }
    try {
      this.storage.setItem(this.showOnStartupKey, strVal);
    } catch {}
  }

  getWelcomeData(options = {}) {
    const recentProjects = options.recentProjects || [];
    return {
      version: '1.0.0',
      tagline: 'Professional visual IDE and compiler for the Otter programming language',
      showOnStartup: this.shouldShowOnStartup(),
      quickActions: [
        { id: 'new-project', title: 'New Project...', shortcut: 'Ctrl+Shift+N', icon: 'sparkle' },
        { id: 'open-folder', title: 'Open Folder / Project...', shortcut: 'Ctrl+O', icon: 'folder' },
        { id: 'clone-repo', title: 'Clone Git Repository...', shortcut: 'Ctrl+Shift+G', icon: 'git' },
        { id: 'open-terminal', title: 'Interactive REPL Terminal', shortcut: 'Ctrl+`', icon: 'terminal' }
      ],
      recentProjects: recentProjects.slice(0, 8),
      samples: SAMPLE_PROJECTS,
      documentationLinks: [
        { title: 'Interactive Language Tour', path: 'docs/TOUR.md', description: 'Step-by-step introduction to Otter syntax and features' },
        { title: 'Standard Library Reference', path: 'docs/STANDARD_LIBRARY.md', description: 'Core math, text, lists, time, and system APIs' },
        { title: 'Visual Designer Guide', path: 'docs/STUDIO.md', description: 'Using drag-and-drop UI and two-way code sync' },
        { title: 'Platform Compatibility', path: 'docs/COMPATIBILITY.md', description: 'Windows 11, macOS, and Linux behavior matrix' }
      ]
    };
  }

  renderWelcomeHtml(options = {}) {
    const data = this.getWelcomeData(options);
    const recentsHtml = data.recentProjects.length > 0
      ? data.recentProjects.map(p => `
          <div class="welcome-recent-item" data-path="${p.path}">
            <div class="recent-title">${p.name || path.basename(p.path)}</div>
            <div class="recent-path">${p.path}</div>
          </div>
        `).join('')
      : '<div class="welcome-empty-recents">No recent projects. Start by creating or opening one.</div>';

    const samplesHtml = data.samples.map(s => `
      <div class="welcome-sample-card" data-sample-id="${s.id}" data-entry="${s.entryPoint}">
        <div class="sample-badge">${s.category.toUpperCase()}</div>
        <h4>${s.name}</h4>
        <p>${s.description}</p>
        <div class="sample-tags">${s.tags.map(t => `<span class="tag">${t}</span>`).join('')}</div>
      </div>
    `).join('');

    return `
      <div class="otter-welcome-screen" role="region" aria-label="Welcome to Otter Studio">
        <header class="welcome-header">
          <div class="welcome-logo-container">
            <span class="welcome-logo-icon">🦦</span>
            <h1>Otter Studio</h1>
            <span class="welcome-version-pill">v${data.version}</span>
          </div>
          <p class="welcome-tagline">${data.tagline}</p>
        </header>

        <div class="welcome-grid">
          <section class="welcome-column">
            <h3>Start</h3>
            <div class="welcome-actions">
              ${data.quickActions.map(a => `
                <button class="welcome-action-btn" data-action="${a.id}">
                  <span class="action-title">${a.title}</span>
                  <span class="action-shortcut">${a.shortcut}</span>
                </button>
              `).join('')}
            </div>

            <h3>Recent Workspaces</h3>
            <div class="welcome-recents-list">${recentsHtml}</div>
          </section>

          <section class="welcome-column">
            <h3>Sample Projects</h3>
            <div class="welcome-samples-grid">${samplesHtml}</div>

            <h3>Help & Learning</h3>
            <ul class="welcome-help-links">
              ${data.documentationLinks.map(d => `
                <li>
                  <a href="#" data-doc="${d.path}">${d.title}</a>
                  <span>${d.description}</span>
                </li>
              `).join('')}
            </ul>
          </section>
        </div>

        <footer class="welcome-footer">
          <label>
            <input type="checkbox" id="chkShowWelcome" ${data.showOnStartup ? 'checked' : ''} />
            Show Welcome page on startup
          </label>
        </footer>
      </div>
    `;
  }
}

/**
 * 3. Host Toolchain Detector
 */
export class ToolchainDetector {
  static detect() {
    const results = {
      timestamp: Date.now(),
      platform: process.platform,
      arch: process.arch,
      tools: {},
      readyForDevelopment: true,
      warnings: []
    };

    // 1. Node.js
    results.tools.node = {
      installed: true,
      version: process.version,
      path: process.execPath
    };

    // 2. PowerShell (Windows PowerShell 5.1 & PowerShell 7)
    results.tools.powershell5 = ToolchainDetector.checkCommand('powershell.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()"');
    results.tools.powershell7 = ToolchainDetector.checkCommand('pwsh -NoProfile -Command "$PSVersionTable.PSVersion.ToString()"');

    // On Windows, PS 5.1 is the baseline; on POSIX, pwsh is required
    if (process.platform === 'win32' && !results.tools.powershell5.installed) {
      results.readyForDevelopment = false;
      results.warnings.push('Windows PowerShell 5.1 was not detected. Required for core language execution on Windows.');
    } else if (process.platform !== 'win32' && !results.tools.powershell7.installed) {
      results.readyForDevelopment = false;
      results.warnings.push('PowerShell 7 (pwsh) was not detected. Required on macOS/Linux hosts.');
    }

    // 3. Git
    results.tools.git = ToolchainDetector.checkCommand('git --version');
    if (!results.tools.git.installed) {
      results.warnings.push('Git is not installed or not in PATH. Version control features will be disabled.');
    }

    // 4. Code Signing Tool (signtool on Windows, codesign on macOS, gpg on Linux)
    if (process.platform === 'win32') {
      results.tools.signtool = ToolchainDetector.checkCommand('signtool.exe /?');
    } else if (process.platform === 'darwin') {
      results.tools.codesign = ToolchainDetector.checkCommand('codesign --version');
    } else {
      results.tools.gpg = ToolchainDetector.checkCommand('gpg --version');
    }

    // 5. C# / .NET Toolchain (optional for native interop)
    results.tools.dotnet = ToolchainDetector.checkCommand('dotnet --version');

    return results;
  }

  static checkCommand(command) {
    try {
      const output = execSync(command, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], timeout: 3000 });
      return {
        installed: true,
        version: output.trim().split('\n')[0]
      };
    } catch {
      return {
        installed: false,
        version: null
      };
    }
  }
}

/**
 * 4. File Associations Manager
 */
export class FileAssociationManager {
  /**
   * Generates Windows .reg file content to associate .ot files with Otter and Otter Studio.
   */
  static generateWindowsRegistry(options = {}) {
    const launcherPath = (options.launcherPath || '%LOCALAPPDATA%\\Otter\\1.0.0\\otter.cmd').replace(/\\/g, '\\\\');
    const studioUrl = options.studioUrl || 'http://127.0.0.1:4200';
    const iconPath = (options.iconPath || '%LOCALAPPDATA%\\Otter\\1.0.0\\assets\\otter.ico').replace(/\\/g, '\\\\');

    return [
      'Windows Registry Editor Version 5.00',
      '',
      '; Associate .ot extension with Otter source code',
      '[HKEY_CURRENT_USER\\Software\\Classes\\.ot]',
      '@="OtterScriptFile"',
      '"Content Type"="text/plain"',
      '"PerceivedType"="text"',
      '',
      '[HKEY_CURRENT_USER\\Software\\Classes\\OtterScriptFile]',
      '@="Otter Source Code"',
      '',
      '[HKEY_CURRENT_USER\\Software\\Classes\\OtterScriptFile\\DefaultIcon]',
      `@="${iconPath},0"`,
      '',
      '; Open in Otter Studio or Run in Otter CLI',
      '[HKEY_CURRENT_USER\\Software\\Classes\\OtterScriptFile\\shell]',
      '@="edit"',
      '',
      '[HKEY_CURRENT_USER\\Software\\Classes\\OtterScriptFile\\shell\\edit]',
      '@="Edit with Otter Studio"',
      '',
      '[HKEY_CURRENT_USER\\Software\\Classes\\OtterScriptFile\\shell\\edit\\command]',
      `@="cmd.exe /c start ${studioUrl}?file=\\"%1\\""`,
      '',
      '[HKEY_CURRENT_USER\\Software\\Classes\\OtterScriptFile\\shell\\run]',
      '@="Run with Otter"',
      '',
      '[HKEY_CURRENT_USER\\Software\\Classes\\OtterScriptFile\\shell\\run\\command]',
      `@="cmd.exe /c \\"${launcherPath}\\" run \\"%1\\" & pause"`
    ].join('\r\n');
  }

  /**
   * Generates Linux FreeDesktop XML MIME specification and .desktop associations.
   */
  static generateLinuxMimeAndDesktop(options = {}) {
    const execPath = options.execPath || '/usr/local/bin/otter';
    const icon = options.icon || 'otter';

    const mimeXml = [
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">',
      '  <mime-type type="text/x-otter">',
      '    <comment>Otter Source Code</comment>',
      '    <glob pattern="*.ot"/>',
      '    <icon name="text-x-generic"/>',
      '  </mime-type>',
      '</mime-info>'
    ].join('\n');

    const desktopEntry = [
      '[Desktop Entry]',
      'Type=Application',
      'Name=Otter Studio',
      'Comment=Visual IDE for the Otter Programming Language',
      `Exec=${execPath} studio %f`,
      `Icon=${icon}`,
      'Terminal=false',
      'Categories=Development;IDE;',
      'MimeType=text/x-otter;'
    ].join('\n');

    return { mimeXml, desktopEntry };
  }

  /**
   * Generates macOS Info.plist document type dictionary for .ot files.
   */
  static generateMacOsDocumentType(options = {}) {
    return {
      CFBundleTypeName: 'Otter Source Code',
      CFBundleTypeRole: 'Editor',
      CFBundleTypeIconFile: 'OtterDocumentIcon',
      LSHandlerRank: 'Owner',
      LSItemContentTypes: ['org.otterlang.otter-source'],
      CFBundleTypeExtensions: ['ot']
    };
  }
}

/**
 * 5. Offline Install Verifier
 */
export class OfflineInstallVerifier {
  static verifyPackage(packageDir) {
    const requiredFiles = [
      'VERSION',
      'otter.ps1',
      'Otter.Contract.psm1',
      'README.md',
      'INSTALL.md',
      'LICENSE',
      'THIRD-PARTY-NOTICES.md'
    ];

    const results = {
      packageDir,
      complete: true,
      missingFiles: [],
      verifiedFiles: []
    };

    for (const rel of requiredFiles) {
      const full = path.join(packageDir, rel);
      if (fs.existsSync(full)) {
        results.verifiedFiles.push(rel);
      } else {
        results.missingFiles.push(rel);
        results.complete = false;
      }
    }

    return results;
  }
}
