// studio-shell.js - The Studio chrome that sits around the editors: the
// Welcome page, the mode bar's project chip and actions, the command
// palette shortcut, and the service status dot. It only wires existing IDE
// capabilities to new places; nothing here changes how files or projects
// behave.

import { mountPackageDialog } from './package-dialog.js';
import { createSettings, applySettingsToDocument, mountSettingsDialog } from './settings.js';
import { installKeymap } from './commands.js';
import { mountDocsViewer, issueUrl } from '../docs/docs-viewer.js';
import { createCommandRegistry, defaultCommands } from './commands.js';
import { mountShortcutsDialog } from './shortcuts-dialog.js';

const ICONS = {
  newProject: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/><path d="M12 12v6M9 15h6"/></svg>',
  openFolder: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>',
  examples: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M8 10l-2 2 2 2M16 10l2 2-2 2M13 9l-2 6"/></svg>',
  learn: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M2 5h7a3 3 0 0 1 3 3v12a2 2 0 0 0-2-2H2z"/><path d="M22 5h-7a3 3 0 0 0-3 3v12a2 2 0 0 1 2-2h8z"/></svg>',
  folder: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>'
};

export function mountStudioShell({ ide, setMode, openNewProjectModal, showWelcome }) {
  const welcomeView = document.getElementById('welcomeView');
  const welcomeTab = document.getElementById('btnWelcomeTab');

  // --- Welcome page -----------------------------------------------------------

  function timeAgo(iso) {
    const then = Date.parse(iso);
    if (!then) return '';
    const minutes = Math.round((Date.now() - then) / 60000);
    if (minutes < 2) return 'just now';
    if (minutes < 60) return `${minutes} minutes ago`;
    const hours = Math.round(minutes / 60);
    if (hours < 24) return `${hours} hour${hours === 1 ? '' : 's'} ago`;
    const days = Math.round(hours / 24);
    return `${days} day${days === 1 ? '' : 's'} ago`;
  }

  function renderWelcome() {
    if (!welcomeView) return;
    const recents = ide.getRecentProjects();
    welcomeView.innerHTML = `
      <div class="welcome-inner">
        <section class="welcome-hero">
          <div>
            <div class="welcome-kicker">Welcome to</div>
            <h1 class="welcome-title">Otter<span class="accent">Studio</span></h1>
            <p class="welcome-lead">Readable like English. Precise like code. Build console tools, desktop apps and websites from one language.</p>
          </div>
        </section>

        <section class="welcome-cards">
          <button class="welcome-card is-primary" data-welcome="new">
            <span class="welcome-card-icon">${ICONS.newProject}</span>
            <span class="welcome-card-body">
              <span class="welcome-card-title">New Project</span>
              <span class="welcome-card-desc">Console, desktop, web or game starter</span>
              <kbd>Ctrl + Shift + N</kbd>
            </span>
          </button>
          <button class="welcome-card" data-welcome="open">
            <span class="welcome-card-icon">${ICONS.openFolder}</span>
            <span class="welcome-card-body">
              <span class="welcome-card-title">Open Folder</span>
              <span class="welcome-card-desc">Open an existing Otter project</span>
              <kbd>Ctrl + O</kbd>
            </span>
          </button>
          <button class="welcome-card" data-welcome="examples">
            <span class="welcome-card-icon">${ICONS.examples}</span>
            <span class="welcome-card-body">
              <span class="welcome-card-title">Browse Examples</span>
              <span class="welcome-card-desc">Real programs to read, run and change</span>
            </span>
          </button>
          <button class="welcome-card" data-welcome="learn">
            <span class="welcome-card-icon">${ICONS.learn}</span>
            <span class="welcome-card-body">
              <span class="welcome-card-title">Learn Otter</span>
              <span class="welcome-card-desc">The documentation, written in Otter itself</span>
            </span>
          </button>
        </section>

        <section>
          <div class="welcome-section-head">
            <h2>Recent Projects</h2>
            ${recents.length ? '<button class="welcome-link-btn" data-welcome="clear-recent">Clear Recent</button>' : ''}
          </div>
          ${recents.length ? `
            <div class="welcome-recents">
              ${recents.map(r => `
                <button class="recent-tile" data-welcome="recent" data-folder="${escapeAttr(r.folder)}" title="${escapeAttr(r.folder)}">
                  <span class="recent-thumb">${ICONS.folder}</span>
                  <span class="recent-meta">
                    <span class="recent-name">${escapeHtml(r.name || r.folder)}</span>
                    <span class="recent-when">${escapeHtml(timeAgo(r.lastOpened))}</span>
                  </span>
                </button>`).join('')}
            </div>` : '<div class="recent-empty">Projects you open will appear here.</div>'}
        </section>
      </div>
    `;

    welcomeView.querySelectorAll('[data-welcome]').forEach(el => el.addEventListener('click', () => {
      const action = el.getAttribute('data-welcome');
      if (action === 'new') openNewProjectModal();
      else if (action === 'open') ide.promptOpenFolder();
      else if (action === 'examples') ide.loadProjectTree('examples');
      else if (action === 'learn') ide.loadProjectTree('otter-docs');
      else if (action === 'recent') ide.loadProjectTree(el.getAttribute('data-folder'));
      else if (action === 'clear-recent') {
        try { localStorage.removeItem('otter_recent_projects'); } catch { /* storage unavailable */ }
        renderWelcome();
      }
    }));
  }

  function showWelcomePage() {
    if (!welcomeView) return;
    renderWelcome();
    welcomeView.hidden = false;
    welcomeTab?.classList.add('is-active');
  }

  function hideWelcomePage() {
    if (!welcomeView || welcomeView.hidden) return;
    welcomeView.hidden = true;
    welcomeTab?.classList.remove('is-active');
  }

  welcomeTab?.addEventListener('click', showWelcomePage);
  document.querySelectorAll('.mode-pill').forEach(pill => pill.addEventListener('click', hideWelcomePage));
  document.getElementById('editorTabsScroll')?.addEventListener('click', hideWelcomePage);
  window.addEventListener('otter:ensure-editor-visible', hideWelcomePage);

  // A project opening (any path in) leaves the Welcome page and names the chip.
  const originalLoadProjectTree = ide.loadProjectTree.bind(ide);
  ide.loadProjectTree = async function (folder) {
    const result = await originalLoadProjectTree(folder);
    if (ide.currentProjectFolder) {
      ide.saveRecentProject(ide.currentProjectFolder, ide.currentProjectName);
      hideWelcomePage();
    }
    updateProjectChip();
    return result;
  };
  const originalActivateTab = ide.activateTab.bind(ide);
  ide.activateTab = function (...args) {
    hideWelcomePage();
    return originalActivateTab(...args);
  };

  // --- Mode bar ---------------------------------------------------------------

  const chipName = document.getElementById('projectChipName');
  function updateProjectChip() {
    if (!chipName) return;
    chipName.textContent = ide.currentProjectName || ide.currentSolution?.name || 'Untitled';
  }
  updateProjectChip();
  document.getElementById('projectChipBtn')?.addEventListener('click', () => {
    if (ide.currentProjectFolder) ide.openProjectSettings();
    else openNewProjectModal();
  });
  // ide.js renders the project name into the Files panel; follow it.
  const cardTitle = document.getElementById('projectCardTitle');
  if (cardTitle && window.MutationObserver) {
    new MutationObserver(updateProjectChip).observe(cardTitle, { childList: true, characterData: true, subtree: true });
  }

  document.getElementById('btnModebarNew')?.addEventListener('click', openNewProjectModal);
  document.getElementById('btnModebarOpen')?.addEventListener('click', () => ide.promptOpenFolder());
  document.getElementById('btnModebarSave')?.addEventListener('click', () => ide.saveCurrentFile());
  document.getElementById('btnModebarRun')?.addEventListener('click', () => document.getElementById('mainRunBtn')?.click());

  // --- Command palette (Ctrl+K) -----------------------------------------------

  const searchWrap = document.querySelector('.header-search-wrap');
  const searchInput = document.querySelector('.header-search-input');
  const openPalette = () => {
    searchInput?.blur();
    ide.openNavigationPalette('files');
  };
  searchWrap?.addEventListener('click', openPalette);
  searchInput?.addEventListener('focus', openPalette);
  window.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      openPalette();
    }
  });

  // --- Service status ---------------------------------------------------------

  const engine = document.getElementById('statusEngine');
  async function checkService() {
    if (!engine) return;
    try {
      const res = await fetch('/api/project?folder=', { cache: 'no-store' });
      engine.classList.toggle('is-offline', !res.ok && res.status >= 500);
      engine.querySelector('.status-text').textContent = res.ok || res.status < 500 ? 'Studio service: connected' : 'Studio service: unavailable';
    } catch {
      engine.classList.add('is-offline');
      engine.querySelector('.status-text').textContent = 'Studio service: offline';
    }
  }
  checkService();
  setInterval(checkService, 30000);

  // --- Desktop app window ----------------------------------------------------------
  // In the Otter Studio desktop app (otter-studio/desktop) the window is
  // frameless: the header is the title bar and its buttons drive the window.
  // In a browser those buttons have nothing to control, so they are hidden.
  const nativeWindow = window.otterStudioWindow;
  document.body.classList.toggle('is-desktop-app', Boolean(nativeWindow));
  if (nativeWindow) {
    document.querySelector('.win-min')?.addEventListener('click', () => nativeWindow.minimize());
    document.querySelector('.win-max')?.addEventListener('click', () => nativeWindow.toggleMaximize());
    document.querySelector('.win-close')?.addEventListener('click', () => nativeWindow.close());
    document.querySelector('.studio-header')?.addEventListener('dblclick', (e) => {
      if (!e.target.closest('button, input, .menu-item, .header-search-wrap')) nativeWindow.toggleMaximize();
    });
    nativeWindow.onStateChange?.((state) => document.body.classList.toggle('is-window-maximized', Boolean(state.maximized)));
  }

  // --- Settings -----------------------------------------------------------------

  const settings = createSettings();
  window.otterSettings = settings;
  applySettingsToDocument(settings);
  // The editor rendered before the settings existed; draw it once with them.
  if (ide.currentCode !== undefined) ide.renderEditorCode(ide.currentCode);
  settings.subscribe((path) => {
    applySettingsToDocument(settings);
    if (path === '*' || path.startsWith('editor.')) ide.renderEditorCode(ide.currentCode);
  });
  const settingsDialog = mountSettingsDialog(settings);
  document.getElementById('menuItemSettings')?.addEventListener('click', () => {
    document.getElementById('menuFile')?.classList.remove('is-open');
    settingsDialog.open();
  });

  // --- Build menu -------------------------------------------------------------

  const packageDialog = mountPackageDialog({ ide, openNewProjectModal });
  const menuBuild = document.getElementById('menuBuild');
  menuBuild?.addEventListener('click', (e) => {
    e.stopPropagation();
    document.getElementById('menuFile')?.classList.remove('is-open');
    menuBuild.classList.toggle('is-open');
  });
  document.addEventListener('click', () => menuBuild?.classList.remove('is-open'));
  document.getElementById('menuItemBuildDesktop')?.addEventListener('click', () => {
    menuBuild?.classList.remove('is-open');
    packageDialog.open();
  });
  document.getElementById('menuItemBuildReveal')?.addEventListener('click', () => {
    menuBuild?.classList.remove('is-open');
    if (!ide.currentProjectFolder) { packageDialog.open(); return; }
    fetch('/api/reveal', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path: `${ide.currentProjectFolder}/packages` })
    }).then(res => { if (!res.ok) packageDialog.open(); }).catch(() => packageDialog.open());
  });

  // --- Commands, palette, Help menu ---------------------------------------------

  // Zen mode: only the editor or designer, no header, sidebars, drawer or
  // status bar. Esc or the same command brings them back.
  function toggleZen(force) {
    const on = typeof force === 'boolean' ? force : !document.body.classList.contains('zen-mode');
    document.body.classList.toggle('zen-mode', on);
    window.dispatchEvent(new Event('resize'));
  }
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && document.body.classList.contains('zen-mode') && !e.defaultPrevented) toggleZen(false);
  });

  // Full screen for the whole Studio window (browser or desktop app).
  function toggleFullScreen() {
    if (document.fullscreenElement) document.exitFullscreen?.();
    else document.documentElement.requestFullscreen?.().catch(() => {});
  }

  const docsViewer = mountDocsViewer({ ide });
  const commands = createCommandRegistry();
  const shortcutsDialog = mountShortcutsDialog(commands, settings);
  commands.registerAll(defaultCommands({
    ide,
    setMode,
    openNewProjectModal,
    openSettings: () => settingsDialog.open(),
    openPackageDialog: () => packageDialog.open(),
    openShortcuts: () => shortcutsDialog.open(),
    showWelcome: showWelcomePage,
    toggleTheme: () => document.getElementById('btnThemeToggle')?.click(),
    byId: (id) => document.getElementById(id),
    toggleZen,
    toggleFullScreen,
    toggleWhitespace: () => settings.set('editor.renderWhitespace', !settings.get('editor.renderWhitespace')),
    openDocs: (path) => docsViewer.open(path),
    reportIssue: () => window.open(issueUrl({ version: '1.0', platform: navigator.platform, userAgent: navigator.userAgent }), '_blank', 'noopener')
  }));
  window.otterCommands = commands;
  commands.setKeybindings(settings.get('keybindings'));
  installKeymap(commands);

  window.addEventListener('keydown', (e) => {
    const inField = /^(input|textarea|select)$/i.test(document.activeElement?.tagName || '') || document.activeElement?.isContentEditable;
    if (e.key === 'F1' || ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === 'p')) {
      e.preventDefault();
      ide.openNavigationPalette('commands');
    } else if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === 'f' && !inField) {
      e.preventDefault();
      commands.run('view.searchPane');
    }
  });

  const menuHelp = document.getElementById('menuHelp');
  menuHelp?.addEventListener('click', (e) => {
    e.stopPropagation();
    document.getElementById('menuFile')?.classList.remove('is-open');
    menuBuild?.classList.remove('is-open');
    menuHelp.classList.toggle('is-open');
  });
  document.addEventListener('click', () => menuHelp?.classList.remove('is-open'));
  for (const [id, commandId] of [['menuItemLocalHistory', 'file.localHistory'], ['menuItemHelpCommands', 'help.commands'], ['menuItemHelpShortcuts', 'help.shortcuts'], ['menuItemHelpWelcome', 'view.welcome'], ['menuItemHelpDocs', 'help.documentation'], ['menuItemHelpGuide', 'help.guide'], ['menuItemHelpReleaseNotes', 'help.releaseNotes'], ['menuItemHelpIssue', 'help.reportIssue']]) {
    document.getElementById(id)?.addEventListener('click', () => {
      menuHelp?.classList.remove('is-open');
      commands.run(commandId);
    });
  }

  if (showWelcome && settings.get('workbench.showWelcomeOnStart') !== false) showWelcomePage();

  return { showWelcomePage, hideWelcomePage, updateProjectChip, packageDialog, settingsDialog, settings, commands, shortcutsDialog };
}

function escapeHtml(str) {
  return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function escapeAttr(str) {
  return escapeHtml(str);
}
