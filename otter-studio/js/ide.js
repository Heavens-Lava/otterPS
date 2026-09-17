// ide.js - Interactive Code Editor, Real Project Tree, Terminal, and Execution Engine for Otter Studio

import {
  filterNavigationItems,
  flattenProjectFiles,
  NavigationHistory,
  symbolsForFile,
  definitionForWord,
  occurrencesForWord
} from './navigation/symbol-index.js';
import { getHoverInfo, getWordAtOffset } from './navigation/hover-provider.js';
import { getSignatureHelp } from './navigation/signature-provider.js';
import { otterLanguageService } from './language/otter-language-service.js';

export class OtterStudioIde {
  constructor() {
    this.currentFile = 'untitled.ot';
    this.currentCode = '# untitled.ot\n\nsay "Hello from Otter!"\n';
    this.currentProjectFolder = null;
    this.currentProjectName = null;
    this.wordWrap = typeof localStorage !== 'undefined' && localStorage.getItem('otter-studio-word-wrap') === 'true';
    this.files = {};
    this.activeTab = 'problems'; // 'problems' | 'output' | 'terminal'
    this.autocompleteVisible = false;
    this.autocompleteIndex = 0;
    this.openTabs = []; // [{ path, name, content, isDirty, icon }]
    this.findMatches = [];
    this.currentMatchIndex = -1;
    this.errorLine = null;
    this.currentFilteredSuggestions = [];
    this.externalCheckTimer = null;
    this.externalCheckInFlight = false;
    this.externalCheckIntervalMs = 2000;
    this.workspaceFiles = [];
    this.workspaceSymbols = [];
    this.templatesCollapsed = false;
    this.navigationMode = null;
    this.navigationItems = [];
    this.filteredNavigationItems = [];
    this.navigationIndex = 0;
    this.navigationHistory = new NavigationHistory();
    this.suggestions = [
      {
        icon: '📝',
        title: 'make [name] is [value]',
        desc: 'Create or reassign variable',
        insert: 'make count is 0',
        example: 'make score is 100',
        docTitle: 'make ... is ...',
        docDesc: 'Declares or binds a variable with an initial value.'
      },
      {
        icon: '🔀',
        title: 'if [condition] ... .',
        desc: 'Conditional branch block',
        insert: 'if score is greater than 10\n    say "You won!"\n.',
        example: 'if count is 0\n    say "empty"\n.',
        docTitle: 'if ... .',
        docDesc: 'Executes a block of code if the boolean condition is true.'
      },
      {
        icon: '🔁',
        title: 'for each [item] in [list] ... .',
        desc: 'Iterate over a list',
        insert: 'for each item in items\n    say item\n.',
        example: 'for each file in files\n    say file\n.',
        docTitle: 'for each ... in ... .',
        docDesc: 'Iterates through each element in a collection.'
      },
      {
        icon: '⚙️',
        title: 'function [name] with [params] ... .',
        desc: 'Define a function',
        insert: 'function greet with name\n    say "Hello" name\n.',
        example: 'function add with a and b\n    return a + b\n.',
        docTitle: 'function ... with ... .',
        docDesc: 'Defines a reusable procedure or pure function.'
      },
      {
        icon: '💬',
        title: 'say [message]',
        desc: 'Print text or variable to output',
        insert: 'say "Hello, Otter!"',
        example: 'say "Score is" score',
        docTitle: 'say ...',
        docDesc: 'Outputs text or values to the console or log.'
      },
      {
        icon: '⏳',
        title: 'wait [seconds] seconds',
        desc: 'Pause execution',
        insert: 'wait 1 seconds',
        example: 'wait 0.5 seconds',
        docTitle: 'wait ... seconds',
        docDesc: 'Pauses execution for a specified duration.'
      },
      {
        icon: '🖱️',
        title: 'button [name] text "..."',
        desc: 'UI clickable button component',
        insert: 'button "actionBtn" text "Click Me"',
        example: 'button "submitBtn" text "Submit"',
        docTitle: 'button ...',
        docDesc: 'Declares an interactive UI button.'
      },
      {
        icon: '🔲',
        title: 'box with direction "..."',
        desc: 'UI container box (column / row)',
        insert: 'box with direction "column" and padding 16\n    .\n',
        example: 'box with direction "row" and padding 8',
        docTitle: 'box ...',
        docDesc: 'Flex container for organizing child widgets.'
      },
      {
        icon: '🏷️',
        title: 'heading [name] text "..."',
        desc: 'UI heading text element',
        insert: 'heading "titleText" text "Welcome to Otter"',
        example: 'heading "mainHeader" text "Dashboard"',
        docTitle: 'heading ...',
        docDesc: 'Renders prominent header typography.'
      },
      {
        icon: '🎮',
        title: 'game with width ... and height ...',
        desc: 'Interactive 2D game canvas',
        insert: 'game with width 640 and height 480\n    on tick\n        # game loop\n    .\n.',
        example: 'game with width 640 and height 480',
        docTitle: 'game ...',
        docDesc: 'Initializes a 2D game canvas with frame tick and keyboard events.'
      },
      {
        icon: '📄',
        title: 'get files in...',
        desc: 'Get files from a folder',
        insert: 'get files in "Pictures" into files',
        example: 'get files in "Pictures" into files',
        docTitle: 'get files in...',
        docDesc: 'Gets a list of files from a folder.'
      },
      {
        icon: '📁',
        title: 'get folders in...',
        desc: 'Get folders from a folder',
        insert: 'get folders in "Pictures" into folders',
        example: 'get folders in "Pictures" into folders',
        docTitle: 'get folders in...',
        docDesc: 'Gets a list of child folders from a directory.'
      },
      {
        icon: '💵',
        title: 'get environment variable...',
        desc: 'Read an environment variable',
        insert: 'get environment variable "PATH" into sysPath',
        example: 'get environment variable "USER" into currentUsr',
        docTitle: 'get environment variable...',
        docDesc: 'Reads a system or process environment variable.'
      },
      {
        icon: '🪟',
        title: 'get running processes',
        desc: 'Get a list of processes',
        insert: 'get running processes into procs',
        example: 'get running processes into procs',
        docTitle: 'get running processes',
        docDesc: 'Returns a list of currently active system processes.'
      }
    ];
    this.currentFilteredSuggestions = this.suggestions;
  }

  async init() {
    this.bindDomElements();
    this.bindEvents();

    // Check if a project or file was requested via URL
    const urlParams = new URLSearchParams(window.location.search);
    const folderParam = urlParams.get('folder') || urlParams.get('project');
    const fileParam = urlParams.get('file');

    if (folderParam) {
      await this.loadProjectTree(folderParam);
      if (fileParam) {
        await this.loadFile(fileParam);
      }
    } else if (fileParam) {
      this.renderCleanProjectTree();
      await this.loadFile(fileParam);
    } else {
      // Clean startup: fresh untitled file, no pre-opened folder
      this.renderCleanProjectTree();
      this.loadUntitledFile();
    }

    this.startExternalChangeMonitor();
  }

  loadUntitledFile() {
    this.currentFile = 'untitled.ot';
    this.currentCode = '# untitled.ot\n\nsay "Hello from Otter!"\n';
    this.openTabs = [{
      path: 'untitled.ot',
      name: 'untitled.ot',
      content: this.currentCode,
      isDirty: false,
      icon: '📄'
    }];
    this.renderTabs();
    this.renderEditorCode(this.currentCode);
    this.hideAutocomplete();
    this.lintCurrentCode();
  }

  bindDomElements() {
    // Left Sidebar Project Elements
    this.projectTreeEl = document.querySelector('.project-tree');
    this.newFileBtn = document.querySelector('.new-file-btn');
    this.btnOpenFolderHeader = document.getElementById('btnOpenFolderHeader');
    if (this.btnOpenFolderHeader) {
      this.btnOpenFolderHeader.addEventListener('click', () => this.promptOpenFolder());
    }
    this.btnNewProjectHeader = document.getElementById('btnNewProjectHeader');
    if (this.btnNewProjectHeader) {
      this.btnNewProjectHeader.addEventListener('click', () => {
        window.dispatchEvent(new CustomEvent('otter:open-new-project'));
      });
    }
    this.templatesCard = document.getElementById('templatesCard');
    this.btnToggleTemplates = document.getElementById('btnToggleTemplates');
    this.btnTemplatesNewProject = document.getElementById('btnTemplatesNewProject');
    this.btnToggleTemplates?.addEventListener('click', () => {
      this.setTemplatesCollapsed(!this.templatesCollapsed);
    });
    this.btnTemplatesNewProject?.addEventListener('click', () => {
      window.dispatchEvent(new CustomEvent('otter:open-new-project'));
    });

    // Editor Elements
    this.codeViewport = document.getElementById('codeViewport');
    this.gutterEl = document.getElementById('lineNumbersGutter');
    this.codeAreaEl = document.getElementById('codeTextArea');
    this.autocompletePopup = document.getElementById('autocompletePopup');
    this.externalChangeBanner = document.getElementById('externalChangeBanner');
    this.externalChangeTitle = document.getElementById('externalChangeTitle');
    this.externalChangeMessage = document.getElementById('externalChangeMessage');
    this.btnKeepLocalChanges = document.getElementById('btnKeepLocalChanges');
    this.btnReloadExternalFile = document.getElementById('btnReloadExternalFile');
    this.sourceOutlineBody = document.getElementById('sourceOutlineBody');
    this.btnRefreshOutline = document.getElementById('btnRefreshOutline');
    this.btnQuickOpen = document.getElementById('btnQuickOpen');
    this.btnGoToSymbol = document.getElementById('btnGoToSymbol');
    this.navigationPaletteBackdrop = document.getElementById('navigationPaletteBackdrop');
    this.navigationPaletteTitle = document.getElementById('navigationPaletteTitle');
    this.navigationPaletteInput = document.getElementById('navigationPaletteInput');
    this.navigationPaletteList = document.getElementById('navigationPaletteList');
    this.btnNavigateBack = document.getElementById('btnNavigateBack');
    this.btnNavigateForward = document.getElementById('btnNavigateForward');
    this.workspaceSearchForm = document.getElementById('workspaceSearchForm');
    this.workspaceSearchInput = document.getElementById('workspaceSearchInput');
    this.workspaceReplaceInput = document.getElementById('workspaceReplaceInput');
    this.workspaceSearchRegex = document.getElementById('workspaceSearchRegex');
    this.workspaceSearchCase = document.getElementById('workspaceSearchCase');
    this.btnWorkspaceReplaceAll = document.getElementById('btnWorkspaceReplaceAll');
    this.workspaceSearchSummary = document.getElementById('workspaceSearchSummary');
    this.workspaceSearchResults = document.getElementById('workspaceSearchResults');

    // Multi-Tab & Quick Action Elements
    this.tabsScrollEl = document.getElementById('editorTabsScroll');
    this.btnAddNewTab = document.getElementById('btnAddNewTab');
    this.btnFormatDoc = document.getElementById('btnFormatDoc');
    this.btnFindDoc = document.getElementById('btnFindDoc');
    this.btnGoToDefinition = document.getElementById('btnGoToDefinition');
    this.btnPeekDefinition = document.getElementById('btnPeekDefinition');
    this.btnFindOccurrences = document.getElementById('btnFindOccurrences');
    this.btnFindReferences = document.getElementById('btnFindReferences');
    this.btnRenameSymbol = document.getElementById('btnRenameSymbol');
    this.modalRenameSymbol = document.getElementById('modalRenameSymbol');
    this.inputRenameNewName = document.getElementById('inputRenameNewName');
    this.renameModalSummary = document.getElementById('renameModalSummary');
    this.renamePreviewList = document.getElementById('renamePreviewList');
    this.btnCancelRename = document.getElementById('btnCancelRename');
    this.btnCloseRenameModal = document.getElementById('btnCloseRenameModal');
    this.btnApplyRename = document.getElementById('btnApplyRename');
    this.currentRenameSymbol = null;
    this.currentRenamePlan = null;
    this.definitionPeekEl = document.getElementById('definitionPeek');
    this.editorHoverTooltipEl = document.getElementById('editorHoverTooltip');
    this.editorSignatureHelpEl = document.getElementById('editorSignatureHelp');
    this.hoverDebounceTimer = null;
    this.btnToggleWordWrap = document.getElementById('btnToggleWordWrap');
    this.breadcrumbsEl = document.getElementById('editorBreadcrumbs');
    this.btnEolSelector = document.getElementById('btnEolSelector');
    this.btnEncodingSelector = document.getElementById('btnEncodingSelector');
    this.fileEncoding = 'UTF-8';
    this.fileEol = 'CRLF';

    // Floating Find & Replace Widget Elements
    this.findReplaceWidget = document.getElementById('findReplaceWidget');
    this.findInput = document.getElementById('findInput');
    this.replaceInput = document.getElementById('replaceInput');
    this.replaceRow = document.getElementById('replaceRow');
    this.findCount = document.getElementById('findCount');
    this.btnToggleReplaceMode = document.getElementById('btnToggleReplaceMode');
    this.btnFindPrev = document.getElementById('btnFindPrev');
    this.btnFindNext = document.getElementById('btnFindNext');
    this.btnReplaceOne = document.getElementById('btnReplaceOne');
    this.btnReplaceAll = document.getElementById('btnReplaceAll');
    this.btnFindClose = document.getElementById('btnFindClose');

    // Status bar
    this.statusBarPos = document.getElementById('statusbarPos') || document.querySelector('.statusbar-right span:first-child');
    this.mainRunBtn = document.getElementById('mainRunBtn');
    this.btnStopProgram = document.getElementById('btnStopProgram');
    this.btnRunDropdown = document.getElementById('btnRunDropdown');
    this.launchProfileMenu = document.getElementById('launchProfileMenu');
    this.runBtnLabel = document.getElementById('runBtnLabel');
    this.launchProfile = typeof localStorage !== 'undefined' ? (localStorage.getItem('otter-studio-launch-profile') || 'current') : 'current';
    this.clearProgramBtn = document.getElementById('clearProgramBtn');

    // Right Sidebar
    this.programOutputBody = document.getElementById('programOutputBody');
    this.variablesBody = document.querySelector('.variables-body');

    // Bottom Drawer Tabs
    this.drawerTabs = document.querySelectorAll('.drawer-tab');
    this.panelProblems = document.getElementById('panelProblems') || document.querySelector('.problem-status-banner')?.parentElement;
    this.panelOutput = document.getElementById('panelOutput');
    this.panelTerminal = document.getElementById('panelTerminal');
    this.problemTitle = document.querySelector('.problem-title');
    this.problemSubtitle = document.querySelector('.problem-subtitle');
    this.statusCheckCircle = document.querySelector('.status-check-circle');
    this.cheerHeadline = document.querySelector('.cheer-headline');
    this.cheerTagline = document.querySelector('.cheer-tagline');

    // Terminal Elements
    this.terminalHistory = document.getElementById('terminalHistory');
    this.terminalForm = document.getElementById('terminalForm');
    this.terminalInput = document.getElementById('terminalInput');
  }

  bindEvents() {
    this.btnKeepLocalChanges?.addEventListener('click', () => this.keepLocalChanges());
    this.btnReloadExternalFile?.addEventListener('click', () => this.reloadExternalFile());
    this.btnRefreshOutline?.addEventListener('click', () => this.refreshWorkspaceSymbols());
    this.btnQuickOpen?.addEventListener('click', () => this.openNavigationPalette('files'));
    this.btnGoToSymbol?.addEventListener('click', () => this.openNavigationPalette('symbols'));
    this.navigationPaletteBackdrop?.addEventListener('click', event => {
      if (event.target === this.navigationPaletteBackdrop) this.closeNavigationPalette();
    });
    this.navigationPaletteInput?.addEventListener('input', () => this.filterNavigationPalette());
    this.navigationPaletteInput?.addEventListener('keydown', event => this.handleNavigationKeydown(event));
    this.btnNavigateBack?.addEventListener('click', () => this.navigateHistoryBack());
    this.btnNavigateForward?.addEventListener('click', () => this.navigateHistoryForward());
    this.btnToggleWordWrap?.addEventListener('click', () => this.setWordWrap(!this.wordWrap));
    this.btnGoToDefinition?.addEventListener('click', () => this.goToDefinition());
    this.btnPeekDefinition?.addEventListener('click', () => this.peekDefinition());
    this.btnFindOccurrences?.addEventListener('click', () => this.findOccurrences());
    this.btnFindReferences?.addEventListener('click', () => this.findReferences());
    this.btnRenameSymbol?.addEventListener('click', () => this.promptRename());
    this.btnCloseRenameModal?.addEventListener('click', () => this.closeRenameModal());
    this.btnCancelRename?.addEventListener('click', () => this.closeRenameModal());
    this.btnApplyRename?.addEventListener('click', () => this.applyRename());
    this.inputRenameNewName?.addEventListener('input', () => this.updateRenamePreview());
    this.inputRenameNewName?.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        this.applyRename();
      } else if (e.key === 'Escape') {
        this.closeRenameModal();
      }
    });
    this.modalRenameSymbol?.addEventListener('click', (e) => {
      if (e.target === this.modalRenameSymbol) this.closeRenameModal();
    });
    this.workspaceSearchForm?.addEventListener('submit', event => {
      event.preventDefault();
      this.searchWorkspace();
    });
    this.btnWorkspaceReplaceAll?.addEventListener('click', () => this.replaceWorkspace());

    this.problemStatusBanner = document.getElementById('problemStatusBanner');
    this.problemStatusBanner?.addEventListener('click', () => {
      if (this.errorLine) this.goToLine(this.errorLine);
    });
    this.problemStatusBanner?.addEventListener('keydown', event => {
      if ((event.key === 'Enter' || event.key === ' ') && this.errorLine) {
        event.preventDefault();
        this.goToLine(this.errorLine);
      }
    });

    this.btnEolSelector?.addEventListener('click', () => this.toggleEol());
    this.btnEncodingSelector?.addEventListener('click', () => this.toggleEncoding());

    // Bottom Drawer Tab switching
    this.drawerTabs.forEach((tab, index) => {
      tab.addEventListener('click', () => {
        this.drawerTabs.forEach(t => t.classList.remove('is-active'));
        tab.classList.add('is-active');

        const tabName = tab.innerText.toLowerCase().trim();
        this.switchBottomTab(tabName);
      });
    });

    // Run Buttons
    if (this.mainRunBtn) {
      this.mainRunBtn.addEventListener('click', () => this.runActiveProfile());
    }

    this.btnStopProgram?.addEventListener('click', () => this.stopCurrentProgram());
    this.btnRunDropdown?.addEventListener('click', (e) => {
      e.stopPropagation();
      this.toggleLaunchProfileMenu();
    });
    document.addEventListener('click', () => this.closeLaunchProfileMenu());

    this.launchProfileMenu?.querySelectorAll('.launch-profile-item').forEach(item => {
      item.addEventListener('click', (e) => {
        e.stopPropagation();
        const profile = item.dataset.profile;
        if (profile) this.setLaunchProfile(profile);
      });
    });

    // Keyboard Shortcuts: F5 / Ctrl+Enter to Run
    window.addEventListener('keydown', (e) => {
      if (e.key === 'F5' || (e.ctrlKey && e.key === 'Enter')) {
        e.preventDefault();
        if (e.shiftKey) {
          this.stopCurrentProgram();
        } else if (e.ctrlKey && e.key === 'F5') {
          this.runProject();
        } else if (e.altKey) {
          this.runInTerminal();
        } else {
          this.runActiveProfile();
        }
        return;
      }
      if (e.ctrlKey && e.key === 's') {
        e.preventDefault();
        this.saveCurrentFile();
      }
      if (e.ctrlKey && !e.shiftKey && e.key.toLowerCase() === 'p') {
        e.preventDefault();
        this.openNavigationPalette('files');
      }
      if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'o') {
        e.preventDefault();
        this.openNavigationPalette('symbols');
      }
      if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'f') {
        e.preventDefault();
        window.dispatchEvent(new CustomEvent('otter:sidebar-pane', { detail: 'search' }));
      }
      if (e.altKey && e.key === 'ArrowLeft') {
        e.preventDefault();
        this.navigateHistoryBack();
      }
      if (e.altKey && e.key === 'ArrowRight') {
        e.preventDefault();
        this.navigateHistoryForward();
      }
    });

    // Terminal Form Submission
    if (this.terminalForm) {
      this.terminalForm.addEventListener('submit', (e) => {
        e.preventDefault();
        const cmd = this.terminalInput.value.trim();
        if (cmd) {
          this.executeTerminalCommand(cmd);
          this.terminalInput.value = '';
        }
      });
    }

    // New File Button
    if (this.newFileBtn) {
      this.newFileBtn.addEventListener('click', () => this.promptNewFile());
    }

    // Clear Program Button
    if (this.clearProgramBtn) {
      this.clearProgramBtn.addEventListener('click', () => {
        if (this.programOutputBody) {
          this.programOutputBody.innerHTML = '<div class="log-line log-empty">Output cleared.</div>';
        }
      });
    }
  }

  switchBottomTab(tabName) {
    this.activeTab = tabName;
    if (this.panelProblems) this.panelProblems.style.display = (tabName === 'problems') ? 'flex' : 'none';
    if (this.panelOutput) this.panelOutput.style.display = (tabName === 'output') ? 'block' : 'none';
    if (this.panelTerminal) {
      this.panelTerminal.style.display = (tabName === 'terminal') ? 'flex' : 'none';
      if (tabName === 'terminal' && this.terminalInput) {
        setTimeout(() => this.terminalInput.focus(), 50);
      }
    }
  }

  // --- Project Tree & Workspace Management ---
  setTemplatesCollapsed(collapsed) {
    this.templatesCollapsed = Boolean(collapsed);
    if (!this.templatesCard) return;

    this.templatesCard.classList.toggle('is-collapsed', this.templatesCollapsed);
    if (this.btnToggleTemplates) {
      this.btnToggleTemplates.textContent = this.templatesCollapsed ? '⌄' : '⌃';
      this.btnToggleTemplates.title = this.templatesCollapsed ? 'Expand templates' : 'Collapse templates';
      this.btnToggleTemplates.setAttribute('aria-label', this.btnToggleTemplates.title);
      this.btnToggleTemplates.setAttribute('aria-expanded', String(!this.templatesCollapsed));
    }
  }

  renderCleanProjectTree() {
    this.currentProjectFolder = null;
    this.currentProjectName = null;
    this.setTemplatesCollapsed(false);
    if (!this.projectTreeEl) return;
    this.projectTreeEl.innerHTML = `
      <div class="no-project-box">
        <div class="no-project-icon">📂</div>
        <div class="no-project-title">No Folder Opened</div>
        <div class="no-project-subtitle">Create a project or open a folder to start.</div>
        <div class="no-project-actions">
          <button class="btn-clean-action" id="btnNewProjectAction">✨ New Project...</button>
          <button class="btn-clean-action-sec" id="btnOpenFolderAction">Open Folder</button>
        </div>
      </div>
    `;

    const newProjBtn = document.getElementById('btnNewProjectAction');
    if (newProjBtn) {
      newProjBtn.addEventListener('click', () => {
        window.dispatchEvent(new CustomEvent('otter:open-new-project'));
      });
    }

    const openBtn = document.getElementById('btnOpenFolderAction');
    if (openBtn) {
      openBtn.addEventListener('click', () => this.promptOpenFolder());
    }
  }

  async promptOpenFolder() {
    const folder = prompt('Enter folder path to open in workspace (e.g. examples/file-organizer or examples):', 'examples/file-organizer');
    if (!folder) return;
    await this.loadProjectTree(folder);
  }

  async loadProjectTree(folder) {
    if (!folder) {
      this.renderCleanProjectTree();
      return;
    }
    try {
      const res = await fetch(`/api/project?folder=${encodeURIComponent(folder)}`);
      const data = await res.json();
      if (data && data.tree && data.tree.length > 0) {
        this.currentProjectFolder = data.rootPath || folder;
        this.currentProjectName = data.name || folder;
        this.setTemplatesCollapsed(true);
        this.workspaceFiles = flattenProjectFiles(data.tree, this.currentProjectFolder);
        this.renderProjectTree(data.tree, this.currentProjectName, this.currentProjectFolder);
        this.refreshWorkspaceSymbols();
      } else {
        alert(data.error || 'Folder is empty or could not be loaded.');
      }
    } catch (err) {
      console.warn('Could not fetch project tree from server:', err);
    }
  }

  renderProjectTree(items, rootName, rootFolder) {
    if (!this.projectTreeEl) return;

    let html = `
      <div class="project-folder-root" title="${rootFolder}">
        <span class="folder-icon">📁</span>
        <span class="folder-name">${rootName}</span>
      </div>
      <div class="project-folder-children">
    `;

    for (const item of items) {
      const fullPath = rootFolder ? `${rootFolder}/${item.path}` : item.path;
      const isSelected = (this.currentFile === fullPath) ? ' is-active' : '';
      if (item.isDir) {
        html += `
          <div class="project-folder-item" data-folder="${fullPath}">
            <span class="folder-arrow">›</span>
            <span class="folder-icon">📁</span>
            <span class="folder-name">${item.name}</span>
          </div>
        `;
      } else {
        const icon = item.name.endsWith('.ot') ? '📄' : (item.name.endsWith('.css') ? '🎨' : '📄');
        html += `
          <div class="project-file-item${isSelected}" data-path="${fullPath}">
            <span class="file-icon">${icon}</span>
            <span class="file-name">${item.name}</span>
          </div>
        `;
      }
    }

    html += `</div>`;
    this.projectTreeEl.innerHTML = html;

    // Attach click events
    this.projectTreeEl.querySelectorAll('.project-file-item').forEach(el => {
      el.addEventListener('click', () => {
        this.projectTreeEl.querySelectorAll('.project-file-item').forEach(f => f.classList.remove('is-active'));
        el.classList.add('is-active');
        const p = el.getAttribute('data-path');
        if (p) this.loadFile(p);
      });
    });
  }

  async refreshWorkspaceSymbols() {
    if (!this.currentProjectFolder) {
      this.renderSourceOutline();
      return;
    }
    if (this.sourceOutlineBody) {
      this.sourceOutlineBody.innerHTML = '<div class="outline-loading">Indexing Otter symbols…</div>';
    }
    try {
      const res = await fetch(`/api/workspace-symbols?folder=${encodeURIComponent(this.currentProjectFolder)}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Could not index the workspace.');
      this.workspaceSymbols = data.symbols || [];
      if (Array.isArray(data.files) && data.files.length > 0) {
        const known = new Map(this.workspaceFiles.map(file => [file.path, file]));
        for (const filePath of data.files) {
          if (!known.has(filePath)) {
            known.set(filePath, { name: filePath.split('/').pop(), path: filePath });
          }
        }
        this.workspaceFiles = [...known.values()];
      }
      this.renderSourceOutline();
    } catch (error) {
      if (this.sourceOutlineBody) {
        this.sourceOutlineBody.innerHTML = `<div class="outline-empty">${this.escapeHtml(error.message)}</div>`;
      }
    }
  }

  updateCurrentDocumentSymbols(analysis) {
    if (!analysis || analysis.Ok === false || !this.currentFile) return;
    this.workspaceSymbols = this.workspaceSymbols.filter(symbol => symbol.File !== this.currentFile);
    for (const symbol of analysis.Symbols || []) {
      this.workspaceSymbols.push({ ...symbol, File: this.currentFile });
    }
    this.renderSourceOutline();
  }

  renderSourceOutline() {
    if (!this.sourceOutlineBody) return;
    const symbols = symbolsForFile(this.workspaceSymbols, this.currentFile)
      .filter(symbol => Number(symbol.ScopeId) === 0);
    if (symbols.length === 0) {
      this.sourceOutlineBody.innerHTML = '<div class="outline-empty">No declarations found in this file.</div>';
      return;
    }
    this.sourceOutlineBody.innerHTML = symbols.map((symbol, index) => `
      <button class="outline-symbol" type="button" data-outline-index="${index}" title="Go to line ${Number(symbol.Line) || 1}">
        <span class="outline-symbol-icon">${symbol.Kind === 'function' ? 'ƒ' : symbol.Kind === 'object' ? '◇' : 'v'}</span>
        <span class="outline-symbol-name">${this.escapeHtml(symbol.Name)}</span>
        <span class="outline-symbol-line">${Number(symbol.Line) || 1}</span>
      </button>
    `).join('');
    this.sourceOutlineBody.querySelectorAll('[data-outline-index]').forEach(button => {
      button.addEventListener('click', () => {
        const symbol = symbols[Number(button.dataset.outlineIndex)];
        if (symbol) this.navigateToLocation({
          path: this.currentFile,
          line: Number(symbol.Line),
          column: Number(symbol.Column)
        });
      });
    });
  }

  openNavigationPalette(mode) {
    if (!this.navigationPaletteBackdrop || !this.navigationPaletteInput) return;
    this.navigationMode = mode;
    this.navigationIndex = 0;
    if (mode === 'files') {
      this.navigationPaletteTitle.textContent = 'Quick Open';
      this.navigationPaletteInput.placeholder = 'Type a file name…';
      const files = this.workspaceFiles.length > 0
        ? this.workspaceFiles
        : this.openTabs.map(tab => ({ name: tab.name, path: tab.path }));
      this.navigationItems = files.map(file => ({
        type: 'file',
        label: file.name,
        detail: file.path,
        path: file.path,
        icon: file.name.toLowerCase().endsWith('.ot') ? 'OT' : '•'
      }));
    } else if (mode === 'symbols') {
      this.navigationPaletteTitle.textContent = 'Go to Symbol';
      this.navigationPaletteInput.placeholder = 'Type a symbol name…';
      this.navigationItems = symbolsForFile(this.workspaceSymbols, this.currentFile)
        .filter(symbol => Number(symbol.ScopeId) === 0)
        .map(symbol => ({
          type: 'symbol',
          label: symbol.Name,
          detail: symbol.Kind,
          line: Number(symbol.Line) || 1,
          column: Number(symbol.Column) || 0,
          icon: symbol.Kind === 'function' ? 'ƒ' : symbol.Kind === 'object' ? '◇' : 'v'
        }));
    }
    this.navigationPaletteInput.value = '';
    this.filteredNavigationItems = this.navigationItems;
    this.renderNavigationPalette();
    this.navigationPaletteBackdrop.style.display = 'flex';
    setTimeout(() => this.navigationPaletteInput.focus(), 0);
  }

  closeNavigationPalette() {
    if (this.navigationPaletteBackdrop) this.navigationPaletteBackdrop.style.display = 'none';
    this.navigationMode = null;
  }

  filterNavigationPalette() {
    this.filteredNavigationItems = filterNavigationItems(this.navigationItems, this.navigationPaletteInput?.value || '');
    this.navigationIndex = 0;
    this.renderNavigationPalette();
  }

  renderNavigationPalette() {
    if (!this.navigationPaletteList) return;
    if (this.filteredNavigationItems.length === 0) {
      this.navigationPaletteList.innerHTML = '<div class="navigation-palette-empty">No matching items.</div>';
      return;
    }
    this.navigationPaletteList.innerHTML = this.filteredNavigationItems.map((item, index) => `
      <button class="navigation-palette-item${index === this.navigationIndex ? ' is-selected' : ''}" type="button" role="option" aria-selected="${index === this.navigationIndex}" data-navigation-index="${index}">
        <span class="navigation-item-icon">${this.escapeHtml(item.icon)}</span>
        <span class="navigation-item-copy">
          <span class="navigation-item-label">${this.escapeHtml(item.label)}</span>
          <span class="navigation-item-detail">${this.escapeHtml(item.detail)}</span>
        </span>
        <span class="navigation-item-meta">${item.type === 'symbol' || item.type === 'occurrence' ? `Line ${item.line}` : ''}</span>
      </button>
    `).join('');
    this.navigationPaletteList.querySelectorAll('[data-navigation-index]').forEach(button => {
      button.addEventListener('click', () => this.activateNavigationItem(Number(button.dataset.navigationIndex)));
    });
    this.navigationPaletteList.querySelector('.is-selected')?.scrollIntoView({ block: 'nearest' });
  }

  handleNavigationKeydown(event) {
    if (event.key === 'Escape') {
      event.preventDefault();
      this.closeNavigationPalette();
      return;
    }
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      const direction = event.key === 'ArrowDown' ? 1 : -1;
      const count = this.filteredNavigationItems.length;
      if (count > 0) this.navigationIndex = (this.navigationIndex + direction + count) % count;
      this.renderNavigationPalette();
      return;
    }
    if (event.key === 'Enter') {
      event.preventDefault();
      this.activateNavigationItem(this.navigationIndex);
    }
  }

  async activateNavigationItem(index) {
    const item = this.filteredNavigationItems[index];
    if (!item) return;
    this.closeNavigationPalette();
    if (item.type === 'file') {
      await this.navigateToLocation({ path: item.path, line: 1, column: 0 });
      return;
    }
    await this.navigateToLocation({ path: item.path || this.currentFile, line: item.line, column: item.column });
  }

  currentEditorLocation() {
    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea || !this.currentFile) return null;
    const before = textarea.value.substring(0, textarea.selectionStart);
    const lines = before.split('\n');
    return {
      path: this.currentFile,
      line: lines.length,
      column: lines[lines.length - 1].length
    };
  }

  async navigateToLocation(location, record = true) {
    if (!location?.path) return;
    if (record) {
      this.navigationHistory.record(this.currentEditorLocation());
      this.navigationHistory.record(location);
    }
    await this.loadFile(location.path);
    this.goToLine(location.line || 1, location.column || 0);
    this.updateNavigationButtons();
  }

  async navigateHistoryBack() {
    const location = this.navigationHistory.back();
    if (location) await this.navigateToLocation(location, false);
  }

  async navigateHistoryForward() {
    const location = this.navigationHistory.forward();
    if (location) await this.navigateToLocation(location, false);
  }

  wordAtCursor() {
    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea) return null;
    const source = textarea.value;
    const cursor = textarea.selectionStart;
    const isWordChar = character => /[A-Za-z0-9_]/.test(character || '');
    let start = cursor;
    let end = cursor;
    while (start > 0 && isWordChar(source[start - 1])) start--;
    while (end < source.length && isWordChar(source[end])) end++;
    return start === end ? null : source.slice(start, end);
  }

  async goToDefinition() {
    const word = this.wordAtCursor();
    const location = this.currentEditorLocation();
    if (!word || !location) return;
    const definition = definitionForWord(this.workspaceSymbols, location.path, word, location.line, this.workspaceSymbols);
    if (!definition) {
      this.setProblemsStatus(false, `No definition found for '${word}'.`, 'Only declarations in this Otter file or workspace are currently resolved.', 'Go to Definition', 'Try a declared variable or function.');
      return;
    }
    this.navigationHistory.record(location);
    this.updateNavigationButtons();
    await this.navigateToLocation({
      path: definition.File || definition.path || location.path,
      line: Number(definition.Line || definition.line) || 1,
      column: Number(definition.Column || definition.column) || 0
    });
  }

  peekDefinition() {
    const word = this.wordAtCursor();
    const location = this.currentEditorLocation();
    if (!word || !location || !this.definitionPeekEl) return;
    const definition = definitionForWord(this.workspaceSymbols, location.path, word, location.line, this.workspaceSymbols);
    if (!definition) {
      this.definitionPeekEl.style.display = 'none';
      this.setProblemsStatus(false, `No definition found for '${word}'.`, 'Only declarations in this Otter file or workspace are currently resolved.', 'Peek Definition', 'Try a declared variable or function.');
      return;
    }
    const sourceLine = (this.currentCode.split(/\r?\n/)[Math.max(0, Number(definition.Line || definition.line) - 1)] || '').trim();
    this.definitionPeekEl.innerHTML = `
      <div class="definition-peek-header">
        <span><strong>${this.escapeHtml(definition.Name || definition.name)}</strong> · ${this.escapeHtml(definition.Kind || definition.kind || 'declaration')} · Line ${Number(definition.Line || definition.line) || 1}</span>
        <button type="button" class="definition-peek-close" aria-label="Close definition preview">×</button>
      </div>
      <pre>${this.escapeHtml(sourceLine)}</pre>
      <button type="button" class="definition-peek-open">Go to definition</button>`;
    this.definitionPeekEl.style.display = 'block';
    this.definitionPeekEl.querySelector('.definition-peek-close')?.addEventListener('click', () => {
      this.definitionPeekEl.style.display = 'none';
    });
    this.definitionPeekEl.querySelector('.definition-peek-open')?.addEventListener('click', () => {
      this.definitionPeekEl.style.display = 'none';
      this.navigateToLocation({ path: definition.File || definition.path || location.path, line: Number(definition.Line || definition.line) || 1, column: Number(definition.Column || definition.column) || 0 });
    });
  }

  findOccurrences() {
    const word = this.wordAtCursor();
    if (!word || !this.navigationPaletteBackdrop || !this.navigationPaletteInput) return;
    const occurrences = occurrencesForWord(this.currentCode, word);
    this.navigationMode = 'occurrences';
    this.navigationIndex = 0;
    this.navigationPaletteTitle.textContent = `Occurrences of ${word}`;
    this.navigationPaletteInput.placeholder = 'Occurrences in the active file';
    this.navigationPaletteInput.value = '';
    this.navigationItems = occurrences.map(hit => ({
      type: 'occurrence',
      label: word,
      detail: `Line ${hit.line}: ${hit.text}`,
      path: this.currentFile,
      line: hit.line,
      column: hit.column,
      icon: '•'
    }));
    this.filteredNavigationItems = this.navigationItems;
    this.renderNavigationPalette();
    this.navigationPaletteBackdrop.style.display = 'flex';
    setTimeout(() => this.navigationPaletteInput.focus(), 0);
  }

  findReferences() {
    const word = this.wordAtCursor();
    const location = this.currentEditorLocation();
    if (!word || !location) {
      this.setProblemsStatus(false, 'No symbol selected for Find References.', 'Place cursor on a variable or function.', 'Find References');
      return;
    }

    const references = otterLanguageService.findReferences(
      word,
      location.path,
      this.currentCode,
      this.workspaceSymbols
    );

    // Switch sidebar tab to Search pane
    const btnSearch = document.getElementById('btnPaneSearch');
    if (btnSearch) btnSearch.click();

    if (this.workspaceSearchSummary) {
      this.workspaceSearchSummary.textContent = references.length === 0
        ? `No references found for '${word}'.`
        : `Found ${references.length} reference${references.length === 1 ? '' : 's'} for '${word}':`;
    }

    if (this.workspaceSearchResults) {
      if (references.length === 0) {
        this.workspaceSearchResults.innerHTML = `<div class="outline-empty">No references found for '${this.escapeHtml(word)}'.</div>`;
        return;
      }
      this.workspaceSearchResults.innerHTML = references.map(ref => `
        <button type="button" class="workspace-search-result" data-path="${this.escapeHtml(ref.file)}" data-line="${ref.line}" data-column="${ref.column}">
          <span class="search-result-location">${this.escapeHtml(ref.file)}:${ref.line}:${ref.column + 1}</span>
          <span class="search-result-preview">${this.escapeHtml(ref.text || word)}</span>
        </button>
      `).join('');

      this.workspaceSearchResults.querySelectorAll('.workspace-search-result').forEach(btn => {
        btn.addEventListener('click', () => {
          const path = btn.dataset.path;
          const line = Number(btn.dataset.line) || 1;
          const column = Number(btn.dataset.column) || 0;
          this.navigateToLocation({ path, line, column });
        });
      });
    }
  }

  promptRename() {
    const word = this.wordAtCursor();
    const location = this.currentEditorLocation();
    if (!word || !location) {
      this.setProblemsStatus(false, 'No symbol selected for rename.', 'Place the cursor on a variable or function identifier.', 'Rename Symbol', 'Place cursor on a valid symbol.');
      return;
    }
    this.currentRenameSymbol = word;
    if (this.modalRenameSymbol && this.inputRenameNewName) {
      this.modalRenameSymbol.style.display = 'flex';
      this.inputRenameNewName.value = word;
      this.inputRenameNewName.focus();
      this.inputRenameNewName.select();
      this.updateRenamePreview();
    }
  }

  closeRenameModal() {
    if (this.modalRenameSymbol) {
      this.modalRenameSymbol.style.display = 'none';
      this.currentRenamePlan = null;
    }
  }

  updateRenamePreview() {
    if (!this.inputRenameNewName || !this.currentRenameSymbol) return;
    const newName = this.inputRenameNewName.value;
    const plan = otterLanguageService.prepareRename(
      this.currentRenameSymbol,
      newName,
      this.currentFile,
      this.currentCode,
      this.workspaceSymbols
    );
    this.currentRenamePlan = plan;

    if (!plan.ok) {
      if (this.renameModalSummary) {
        this.renameModalSummary.textContent = plan.error;
        this.renameModalSummary.style.color = '#ef4444';
      }
      if (this.renamePreviewList) this.renamePreviewList.innerHTML = '';
      if (this.btnApplyRename) this.btnApplyRename.disabled = true;
      return;
    }

    if (this.renameModalSummary) {
      this.renameModalSummary.textContent = `Found ${plan.referencesCount} occurrence${plan.referencesCount === 1 ? '' : 's'} across ${plan.affectedLinesCount} line${plan.affectedLinesCount === 1 ? '' : 's'}.`;
      this.renameModalSummary.style.color = '';
    }
    if (this.btnApplyRename) this.btnApplyRename.disabled = false;

    if (this.renamePreviewList) {
      this.renamePreviewList.innerHTML = plan.edits.map(edit => `
        <div class="rename-preview-item">
          <div class="rename-preview-loc">${this.escapeHtml(edit.file)}: Line ${edit.line}</div>
          <div class="rename-preview-diff">
            <span class="rename-diff-old">- ${this.escapeHtml(edit.originalLine)}</span>
            <span class="rename-diff-new">+ ${this.escapeHtml(edit.modifiedLine)}</span>
          </div>
        </div>
      `).join('');
    }
  }

  async applyRename() {
    if (!this.currentRenamePlan || !this.currentRenamePlan.ok) return;
    const plan = this.currentRenamePlan;
    const newCode = otterLanguageService.applyRenameToSource(
      this.currentCode,
      plan.oldName,
      plan.newName,
      plan.edits
    );

    this.currentCode = newCode;
    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea) textarea.value = newCode;
    this.markCurrentTabDirty(true);
    this.renderEditorCode(this.currentCode);
    this.closeRenameModal();
    await this.refreshWorkspaceSymbols();
    this.debouncedLint();
    this.setProblemsStatus(true, `Renamed '${plan.oldName}' to '${plan.newName}' across ${plan.referencesCount} location${plan.referencesCount === 1 ? '' : 's'}.`, 'Symbol rename complete.');
  }

  updateNavigationButtons() {
    if (this.btnNavigateBack) this.btnNavigateBack.disabled = !this.navigationHistory.canBack;
    if (this.btnNavigateForward) this.btnNavigateForward.disabled = !this.navigationHistory.canForward;
  }

  async searchWorkspace() {
    const query = this.workspaceSearchInput?.value || '';
    if (!query.trim()) {
      this.workspaceSearchSummary.textContent = 'Enter text to search the current workspace.';
      this.workspaceSearchResults.innerHTML = '';
      return;
    }
    if (!this.currentProjectFolder) {
      this.workspaceSearchSummary.textContent = 'Open a project folder before searching.';
      return;
    }
    this.workspaceSearchSummary.textContent = 'Searching…';
    this.workspaceSearchResults.innerHTML = '';
    try {
      const res = await fetch('/api/search', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          folder: this.currentProjectFolder,
          query,
          regex: this.workspaceSearchRegex?.checked === true,
          caseSensitive: this.workspaceSearchCase?.checked === true
        })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Workspace search failed.');
      const suffix = data.truncated ? ' (first 500 shown)' : '';
      this.workspaceSearchSummary.textContent = `${data.results.length} result${data.results.length === 1 ? '' : 's'} in ${data.filesSearched} files${suffix}.`;
      this.renderWorkspaceSearchResults(data.results);
    } catch (error) {
      this.workspaceSearchSummary.textContent = error.message;
    }
  }

  renderWorkspaceSearchResults(results) {
    if (!this.workspaceSearchResults) return;
    if (!results?.length) {
      this.workspaceSearchResults.innerHTML = '<div class="outline-empty">No matches found.</div>';
      return;
    }
    this.workspaceSearchResults.innerHTML = results.map((result, index) => `
      <button class="workspace-search-result" type="button" data-search-index="${index}">
        <span class="search-result-location">${this.escapeHtml(result.path)}:${Number(result.line)}:${Number(result.column) + 1}</span>
        <span class="search-result-preview">${this.escapeHtml(result.preview)}</span>
      </button>
    `).join('');
    this.workspaceSearchResults.querySelectorAll('[data-search-index]').forEach(button => {
      button.addEventListener('click', () => {
        const result = results[Number(button.dataset.searchIndex)];
        if (result) this.navigateToLocation({
          path: result.path,
          line: Number(result.line),
          column: Number(result.column)
        });
      });
    });
  }

  async replaceWorkspace() {
    const query = this.workspaceSearchInput?.value || '';
    const replaceWith = this.workspaceReplaceInput?.value ?? '';
    if (!query.trim()) {
      this.workspaceSearchSummary.textContent = 'Enter text to search for before replacing.';
      return;
    }
    if (!this.currentProjectFolder) {
      this.workspaceSearchSummary.textContent = 'Open a project folder before replacing.';
      return;
    }
    this.workspaceSearchSummary.textContent = 'Replacing across files…';
    try {
      const res = await fetch('/api/replace', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          folder: this.currentProjectFolder,
          query,
          replace: replaceWith,
          regex: this.workspaceSearchRegex?.checked === true,
          caseSensitive: this.workspaceSearchCase?.checked === true
        })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Workspace replacement failed.');
      this.workspaceSearchSummary.textContent = `Replaced ${data.totalReplacements} occurrence${data.totalReplacements === 1 ? '' : 's'} across ${data.filesModified} file${data.filesModified === 1 ? '' : 's'}.`;
      if (this.currentFile) {
        await this.reloadExternalFile();
      }
      this.searchWorkspace();
    } catch (error) {
      this.workspaceSearchSummary.textContent = error.message;
    }
  }

  async promptNewFile() {
    const name = prompt('Enter new Otter file name (e.g. main.ot or script.ot):', 'script.ot');
    if (!name) return;

    const initialContent = `# ${name}\n\nsay "Hello from ${name}!"\n`;
    if (!this.currentProjectFolder) {
      // Local in-memory session new file
      this.currentFile = name;
      this.currentCode = initialContent;
      const tabTitle = document.querySelector('.editor-tab.is-active .tab-title');
      if (tabTitle) tabTitle.innerText = name;
      this.renderEditorCode(this.currentCode);
      this.lintCurrentCode();
      return;
    }

    try {
      const res = await fetch('/api/create-file', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, folder: this.currentProjectFolder, content: initialContent })
      });
      const data = await res.json();
      if (data.ok) {
        await this.loadProjectTree(this.currentProjectFolder);
        await this.loadFile(data.path);
      } else {
        alert(data.error || 'Failed to create file.');
      }
    } catch (e) {
      alert('Error creating file: ' + e.message);
    }
  }

  // --- Real Multi-Tab File Load & Save ---
  async loadFile(filePath) {
    const existing = this.openTabs.find(t => t.path === filePath);
    if (existing) {
      this.activateTab(filePath);
      return;
    }

    let fileContent = this.getDefaultCode();
    let fileRevision = null;
    try {
      const res = await fetch(`/api/file?path=${encodeURIComponent(filePath)}`);
      const data = await res.json();
      if (data && typeof data.content === 'string') {
        fileContent = data.content;
        fileRevision = data.revision || null;
      }
    } catch {
      fileContent = this.getDefaultCode();
    }

    const fileName = filePath.split('/').pop();
    const icon = fileName.endsWith('.ot') ? '📄' : (fileName.endsWith('.css') ? '🎨' : (fileName.endsWith('.json') ? '⚙' : '📝'));
    const newTab = {
      path: filePath,
      name: fileName,
      content: fileContent,
      isDirty: false,
      icon,
      diskRevision: fileRevision,
      externalRevision: null,
      externalContent: null,
      externalDeleted: false
    };
    this.openTabs.push(newTab);
    this.activateTab(filePath);
  }

  activateTab(filePath) {
    const tab = this.openTabs.find(t => t.path === filePath);
    if (!tab) return;

    this.currentFile = tab.path;
    this.currentCode = tab.content;
    this.detectFileEol(this.currentCode);

    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea) {
      textarea.value = this.currentCode;
    }

    this.renderTabs();
    this.renderEditorCode(this.currentCode);
    this.lintCurrentCode();
    this.renderExternalChangeBanner();
    this.renderSourceOutline();
  }

  renderTabs() {
    if (!this.tabsScrollEl) return;
    this.tabsScrollEl.innerHTML = '';

    this.openTabs.forEach(tab => {
      const tabEl = document.createElement('div');
      tabEl.className = `editor-tab ${tab.path === this.currentFile ? 'is-active' : ''}${tab.externalRevision || tab.externalDeleted ? ' has-external-change' : ''}`;
      tabEl.setAttribute('data-path', tab.path);
      tabEl.innerHTML = `
        <span class="tab-icon">${tab.icon}</span>
        <span class="tab-title">${this.escapeHtml(tab.name)}</span>
        <span class="tab-dirty-dot" style="${tab.isDirty ? '' : 'display:none;'}">●</span>
        <span class="tab-external-dot" title="Changed outside Otter Studio" style="${tab.externalRevision || tab.externalDeleted ? '' : 'display:none;'}">!</span>
        <span class="tab-close" title="Close Tab">×</span>
      `;

      tabEl.addEventListener('click', (e) => {
        if (e.target.classList.contains('tab-close')) {
          e.stopPropagation();
          this.closeTab(tab.path);
        } else {
          this.activateTab(tab.path);
        }
      });

      this.tabsScrollEl.appendChild(tabEl);
    });
  }

  closeTab(filePath) {
    const idx = this.openTabs.findIndex(t => t.path === filePath);
    if (idx < 0) return;

    const closingTab = this.openTabs[idx];
    if (closingTab.isDirty) {
      const confirmClose = confirm(`File "${closingTab.name}" has unsaved changes. Close anyway?`);
      if (!confirmClose) return;
    }

    this.openTabs.splice(idx, 1);

    if (this.currentFile === filePath) {
      if (this.openTabs.length > 0) {
        const nextTab = this.openTabs[Math.max(0, idx - 1)];
        this.activateTab(nextTab.path);
      } else {
        this.loadUntitledFile();
      }
    } else {
      this.renderTabs();
    }
  }

  markCurrentTabDirty(isDirty = true) {
    const tab = this.openTabs.find(t => t.path === this.currentFile);
    if (tab) {
      tab.isDirty = isDirty;
      tab.content = this.currentCode;
      this.renderTabs();
    }
  }

  async saveCurrentFile() {
    try {
      const tab = this.openTabs.find(t => t.path === this.currentFile);
      if (this.currentFile) {
        const res = await fetch('/api/file', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            path: this.currentFile,
            content: this.currentCode,
            expectedRevision: tab?.diskRevision || undefined
          })
        });
        const data = await res.json();
        if (res.status === 409 && data.conflict) {
          this.setExternalConflict(tab, data);
          return false;
        }
        if (!res.ok) throw new Error(data.error || 'Could not save the file.');
        if (tab) {
          tab.diskRevision = data.revision || null;
          tab.externalRevision = null;
          tab.externalContent = null;
          tab.externalDeleted = false;
        }
      }

      if (this.currentProjectFolder && window.otterCssAstManager) {
        const cssPath = `${this.currentProjectFolder}/styles.css`;
        const cssContent = window.otterCssAstManager.generateCss();
        await fetch('/api/file', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ path: cssPath, content: cssContent })
        });
      }

      // Clear dirty state on tab
      if (tab) {
        tab.isDirty = false;
        tab.content = this.currentCode;
        this.renderTabs();
      }
      this.renderExternalChangeBanner();
      this.saveSessionState();
      return true;
    } catch (err) {
      console.warn('Save file error:', err);
      return false;
    }
  }

  startExternalChangeMonitor() {
    if (this.externalCheckTimer) clearInterval(this.externalCheckTimer);
    this.externalCheckTimer = setInterval(() => this.checkExternalChanges(), this.externalCheckIntervalMs);
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) this.checkExternalChanges();
    });
  }

  async checkExternalChanges() {
    if (this.externalCheckInFlight || document.hidden) return;
    const tabs = this.openTabs.filter(tab => tab.diskRevision && tab.path !== 'untitled.ot');
    if (tabs.length === 0) return;

    this.externalCheckInFlight = true;
    try {
      for (const tab of tabs) {
        const res = await fetch(`/api/file-status?path=${encodeURIComponent(tab.path)}`);
        if (!res.ok) continue;
        const status = await res.json();
        if (!status.exists) {
          tab.externalDeleted = true;
          if (tab.path === this.currentFile) this.renderExternalChangeBanner();
          continue;
        }
        if (status.revision === tab.diskRevision || status.revision === tab.externalRevision) continue;

        const latestRes = await fetch(`/api/file?path=${encodeURIComponent(tab.path)}`);
        if (!latestRes.ok) continue;
        const latest = await latestRes.json();
        if (tab.isDirty) {
          this.setExternalConflict(tab, latest);
        } else {
          this.applyExternalSnapshot(tab, latest);
        }
      }
    } finally {
      this.externalCheckInFlight = false;
      this.renderTabs();
    }
  }

  setExternalConflict(tab, snapshot) {
    if (!tab) return;
    tab.externalRevision = snapshot.revision || null;
    tab.externalContent = typeof snapshot.content === 'string' ? snapshot.content : null;
    tab.externalDeleted = snapshot.exists === false;
    this.renderTabs();
    if (tab.path === this.currentFile) this.renderExternalChangeBanner();
  }

  applyExternalSnapshot(tab, snapshot) {
    tab.content = snapshot.content;
    tab.diskRevision = snapshot.revision;
    tab.externalRevision = null;
    tab.externalContent = null;
    tab.externalDeleted = false;
    if (tab.path === this.currentFile) {
      this.currentCode = tab.content;
      const textarea = document.getElementById('hiddenEditorInput');
      if (textarea) textarea.value = this.currentCode;
      this.renderEditorCode(this.currentCode);
      this.lintCurrentCode();
      this.renderExternalChangeBanner('Reloaded the latest version from disk.');
    }
    this.saveSessionState();
  }

  reloadExternalFile() {
    const tab = this.openTabs.find(t => t.path === this.currentFile);
    if (!tab || tab.externalDeleted || typeof tab.externalContent !== 'string') return;
    this.applyExternalSnapshot(tab, {
      content: tab.externalContent,
      revision: tab.externalRevision
    });
    tab.isDirty = false;
    this.renderTabs();
    this.renderExternalChangeBanner();
  }

  keepLocalChanges() {
    const tab = this.openTabs.find(t => t.path === this.currentFile);
    if (!tab) return;
    if (tab.externalDeleted) {
      tab.diskRevision = null;
    } else if (tab.externalRevision) {
      tab.diskRevision = tab.externalRevision;
    }
    tab.externalRevision = null;
    tab.externalContent = null;
    tab.externalDeleted = false;
    tab.isDirty = true;
    this.renderTabs();
    this.renderExternalChangeBanner();
    this.saveSessionState();
  }

  renderExternalChangeBanner(transientMessage = null) {
    if (!this.externalChangeBanner) return;
    const tab = this.openTabs.find(t => t.path === this.currentFile);
    if (transientMessage) {
      this.externalChangeTitle.textContent = transientMessage;
      this.externalChangeMessage.textContent = tab?.name || '';
      this.externalChangeBanner.style.display = 'flex';
      this.btnKeepLocalChanges.style.display = 'none';
      this.btnReloadExternalFile.style.display = 'none';
      clearTimeout(this.externalBannerTimer);
      this.externalBannerTimer = setTimeout(() => this.renderExternalChangeBanner(), 2500);
      return;
    }
    const hasConflict = Boolean(tab && (tab.externalRevision || tab.externalDeleted));
    this.externalChangeBanner.style.display = hasConflict ? 'flex' : 'none';
    this.btnKeepLocalChanges.style.display = '';
    this.btnReloadExternalFile.style.display = tab?.externalDeleted ? 'none' : '';
    if (!hasConflict) return;
    this.externalChangeTitle.textContent = tab.externalDeleted
      ? `${tab.name} was deleted outside Otter Studio.`
      : `${tab.name} changed outside Otter Studio.`;
    this.externalChangeMessage.textContent = tab.externalDeleted
      ? 'Keep editing to recreate it when you save.'
      : 'Reload the disk version or keep your unsaved editor version.';
  }

  // --- Document Formatter Engine ---
  formatCurrentDocument() {
    const formatted = this.formatOtterCode(this.currentCode);
    if (formatted !== this.currentCode) {
      this.currentCode = formatted;
      const textarea = document.getElementById('hiddenEditorInput');
      if (textarea) textarea.value = this.currentCode;
      this.markCurrentTabDirty(true);
      this.renderEditorCode(this.currentCode);
      this.debouncedLint();
    }
  }

  formatOtterCode(code) {
    const lines = code.split('\n');
    let indentLevel = 0;
    const formatted = [];

    for (let raw of lines) {
      let line = raw.trim();
      if (!line) {
        if (formatted.length > 0 && formatted[formatted.length - 1] !== '') {
          formatted.push('');
        }
        continue;
      }

      if (line === '.') {
        indentLevel = Math.max(0, indentLevel - 1);
        formatted.push('    '.repeat(indentLevel) + '.');
        continue;
      }

      const startsBlock = /^(?:when\s+\w+\s+(?:is\s+)?\w+|for\s+each\b|if\b|otherwise\b|repeat\b|while\b|\w+\s+has$|game\b|on\s+(?:tick|key)|function\b)/i.test(line);

      if (/^otherwise\b/i.test(line)) {
        const tempIndent = Math.max(0, indentLevel - 1);
        formatted.push('    '.repeat(tempIndent) + line);
        continue;
      }

      formatted.push('    '.repeat(indentLevel) + line);

      if (startsBlock) {
        indentLevel++;
      }
    }

    return formatted.join('\n') + '\n';
  }

  // --- In-Editor Find & Replace Controller ---
  bindFindReplace() {
    this.btnFindDoc?.addEventListener('click', () => this.openFind(false));
    this.btnFormatDoc?.addEventListener('click', () => this.formatCurrentDocument());
    this.btnAddNewTab?.addEventListener('click', () => this.promptNewFile());

    this.btnToggleReplaceMode?.addEventListener('click', () => {
      if (!this.replaceRow) return;
      const isVisible = this.replaceRow.style.display !== 'none';
      this.replaceRow.style.display = isVisible ? 'none' : 'flex';
      this.btnToggleReplaceMode.classList.toggle('is-open', !isVisible);
    });

    this.findInput?.addEventListener('input', () => {
      this.performFind(this.findInput.value);
    });

    this.findInput?.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        if (e.shiftKey) this.findPrev();
        else this.findNext();
      } else if (e.key === 'Escape') {
        this.closeFind();
      }
    });

    this.replaceInput?.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        this.replaceOne();
      } else if (e.key === 'Escape') {
        this.closeFind();
      }
    });

    this.btnFindNext?.addEventListener('click', () => this.findNext());
    this.btnFindPrev?.addEventListener('click', () => this.findPrev());
    this.btnReplaceOne?.addEventListener('click', () => this.replaceOne());
    this.btnReplaceAll?.addEventListener('click', () => this.replaceAll());
    this.btnFindClose?.addEventListener('click', () => this.closeFind());
  }

  openFind(replaceMode = false) {
    if (!this.findReplaceWidget) return;
    this.findReplaceWidget.style.display = 'flex';
    if (replaceMode && this.replaceRow) {
      this.replaceRow.style.display = 'flex';
      this.btnToggleReplaceMode?.classList.add('is-open');
    }
    setTimeout(() => {
      this.findInput?.focus();
      this.findInput?.select();
    }, 50);
  }

  closeFind() {
    if (!this.findReplaceWidget) return;
    this.findReplaceWidget.style.display = 'none';
    this.findMatches = [];
    this.currentMatchIndex = -1;
    this.renderEditorCode(this.currentCode);
    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea) textarea.focus();
  }

  performFind(query) {
    if (!query) {
      this.findMatches = [];
      this.currentMatchIndex = -1;
      if (this.findCount) this.findCount.textContent = 'No results';
      this.renderEditorCode(this.currentCode);
      return;
    }

    const regex = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
    const matches = [];
    let match;
    while ((match = regex.exec(this.currentCode)) !== null) {
      matches.push({
        index: match.index,
        length: match[0].length
      });
    }

    this.findMatches = matches;
    this.currentMatchIndex = matches.length > 0 ? 0 : -1;
    if (this.findCount) {
      this.findCount.textContent = matches.length > 0
        ? `${this.currentMatchIndex + 1} of ${matches.length}`
        : 'No results';
    }

    this.highlightMatchesInEditor(query);
  }

  findNext() {
    if (this.findMatches.length === 0) return;
    this.currentMatchIndex = (this.currentMatchIndex + 1) % this.findMatches.length;
    if (this.findCount) {
      this.findCount.textContent = `${this.currentMatchIndex + 1} of ${this.findMatches.length}`;
    }
    this.highlightMatchesInEditor(this.findInput?.value || '');
  }

  findPrev() {
    if (this.findMatches.length === 0) return;
    this.currentMatchIndex = (this.currentMatchIndex - 1 + this.findMatches.length) % this.findMatches.length;
    if (this.findCount) {
      this.findCount.textContent = `${this.currentMatchIndex + 1} of ${this.findMatches.length}`;
    }
    this.highlightMatchesInEditor(this.findInput?.value || '');
  }

  replaceOne() {
    if (this.currentMatchIndex < 0 || this.findMatches.length === 0) return;
    const match = this.findMatches[this.currentMatchIndex];
    const replacement = this.replaceInput?.value || '';

    this.currentCode = this.currentCode.substring(0, match.index) + replacement + this.currentCode.substring(match.index + match.length);
    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea) textarea.value = this.currentCode;
    this.markCurrentTabDirty(true);
    this.performFind(this.findInput?.value || '');
  }

  replaceAll() {
    const query = this.findInput?.value;
    if (!query || this.findMatches.length === 0) return;
    const replacement = this.replaceInput?.value || '';

    const regex = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
    this.currentCode = this.currentCode.replace(regex, replacement);

    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea) textarea.value = this.currentCode;
    this.markCurrentTabDirty(true);
    this.performFind(query);
  }

  highlightMatchesInEditor(query) {
    if (!this.codeAreaEl) return;
    this.renderEditorCode(this.currentCode);
    if (!query || this.findMatches.length === 0) return;

    if (this.currentMatchIndex >= 0 && this.currentMatchIndex < this.findMatches.length) {
      const matchPos = this.findMatches[this.currentMatchIndex].index;
      const linesBefore = this.currentCode.substring(0, matchPos).split('\n').length;
      const targetLineEl = this.codeAreaEl.querySelector(`[data-line="${linesBefore}"]`);
      if (targetLineEl) {
        targetLineEl.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      }
    }
  }

  // --- Editor Navigation, Smart Actions & Session State ---
  toggleComment() {
    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea) return;
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const val = textarea.value;
    const lineStart = val.lastIndexOf('\n', start - 1) + 1;
    let lineEnd = val.indexOf('\n', end);
    if (lineEnd === -1) lineEnd = val.length;
    const block = val.substring(lineStart, lineEnd);
    const lines = block.split('\n');
    const allCommented = lines.every(l => l.trim().startsWith('#') || !l.trim());

    const modifiedLines = lines.map(l => {
      if (allCommented) {
        return l.replace(/^(\s*)# ?/, '$1');
      } else {
        return l.replace(/^(\s*)(.*)/, '$1# $2');
      }
    });
    const modified = modifiedLines.join('\n');
    textarea.value = val.substring(0, lineStart) + modified + val.substring(lineEnd);
    textarea.selectionStart = lineStart;
    textarea.selectionEnd = lineStart + modified.length;
    this.currentCode = textarea.value;
    this.markCurrentTabDirty(true);
    this.renderEditorCode(this.currentCode);
    this.debouncedLint();
    this.saveSessionState();
  }

  promptGoToLine() {
    const input = prompt('Go to Line number:');
    if (!input) return;
    const lineNum = parseInt(input, 10);
    if (!isNaN(lineNum) && lineNum > 0) {
      this.goToLine(lineNum);
    }
  }

  goToLine(lineNum, column = 0) {
    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea) return;
    const lines = textarea.value.split('\n');
    const targetLine = Math.min(Math.max(1, lineNum), lines.length);
    let charOffset = 0;
    for (let i = 0; i < targetLine - 1; i++) {
      charOffset += lines[i].length + 1;
    }
    textarea.focus();
    charOffset += Math.min(Math.max(0, column), lines[targetLine - 1].length);
    textarea.selectionStart = textarea.selectionEnd = charOffset;
    this.updateCursorPos(textarea);

    const targetLineEl = this.codeAreaEl?.querySelector(`[data-line="${targetLine}"]`);
    if (targetLineEl) {
      targetLineEl.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
  }

  checkBlockMatching(lineNum) {
    if (!this.codeAreaEl) return;
    this.codeAreaEl.querySelectorAll('.code-line.block-match').forEach(el => el.classList.remove('block-match'));

    const lines = this.currentCode.split('\n');
    if (lineNum < 1 || lineNum > lines.length) return;
    const curLine = lines[lineNum - 1].trim();

    if (curLine === '.') {
      let depth = 0;
      for (let i = lineNum - 2; i >= 0; i--) {
        const line = lines[i].trim();
        if (line === '.') {
          depth++;
        } else if (/^(?:when\s+\w+\s+(?:is\s+)?\w+|for\s+each\b|if\b|otherwise\b|repeat\b|while\b|\w+\s+has$|game\b|on\s+(?:tick|key)|function\b)/i.test(line)) {
          if (depth === 0) {
            const matchEl = this.codeAreaEl.querySelector(`[data-line="${i + 1}"]`);
            const dotEl = this.codeAreaEl.querySelector(`[data-line="${lineNum}"]`);
            if (matchEl) matchEl.classList.add('block-match');
            if (dotEl) dotEl.classList.add('block-match');
            break;
          } else {
            depth--;
          }
        }
      }
    } else if (/^(?:when\s+\w+\s+(?:is\s+)?\w+|for\s+each\b|if\b|otherwise\b|repeat\b|while\b|\w+\s+has$|game\b|on\s+(?:tick|key)|function\b)/i.test(curLine)) {
      let depth = 0;
      for (let i = lineNum; i < lines.length; i++) {
        const line = lines[i].trim();
        if (/^(?:when\s+\w+\s+(?:is\s+)?\w+|for\s+each\b|if\b|otherwise\b|repeat\b|while\b|\w+\s+has$|game\b|on\s+(?:tick|key)|function\b)/i.test(line)) {
          depth++;
        } else if (line === '.') {
          if (depth === 0) {
            const matchEl = this.codeAreaEl.querySelector(`[data-line="${lineNum}"]`);
            const dotEl = this.codeAreaEl.querySelector(`[data-line="${i + 1}"]`);
            if (matchEl) matchEl.classList.add('block-match');
            if (dotEl) dotEl.classList.add('block-match');
            break;
          } else {
            depth--;
          }
        }
      }
    }
  }

  saveSessionState() {
    try {
      const session = {
        currentFile: this.currentFile,
        currentFolder: this.currentProjectFolder,
        openTabs: this.openTabs.map(t => ({
          path: t.path,
          name: t.name,
          content: t.content,
          isDirty: t.isDirty,
          icon: t.icon,
          diskRevision: t.diskRevision || null
        }))
      };
      localStorage.setItem('otter_studio_session', JSON.stringify(session));
    } catch (e) {}
  }

  restoreSessionState() {
    try {
      const saved = localStorage.getItem('otter_studio_session');
      if (!saved) return false;
      const session = JSON.parse(saved);
      if (session && session.openTabs && session.openTabs.length > 0) {
        this.openTabs = session.openTabs;
        this.currentProjectFolder = session.currentFolder || null;
        this.currentFile = session.currentFile || session.openTabs[0].path;
        const curTab = this.openTabs.find(t => t.path === this.currentFile) || this.openTabs[0];
        this.currentCode = curTab.content;
        this.renderTabs();
        this.renderEditorCode(this.currentCode);
        this.lintCurrentCode();
        if (this.currentProjectFolder) {
          this.loadProjectTree(this.currentProjectFolder);
        }
        return true;
      }
    } catch {
      return false;
    }
    return false;
  }

  saveRecentProject(folder, name) {
    if (!folder) return;
    try {
      let recents = JSON.parse(localStorage.getItem('otter_recent_projects') || '[]');
      recents = recents.filter(r => r.folder !== folder);
      recents.unshift({ folder, name: name || folder, lastOpened: new Date().toISOString() });
      if (recents.length > 8) recents.pop();
      localStorage.setItem('otter_recent_projects', JSON.stringify(recents));
    } catch (e) {}
  }

  getRecentProjects() {
    try {
      return JSON.parse(localStorage.getItem('otter_recent_projects') || '[]');
    } catch {
      return [];
    }
  }

  getDefaultCode() {
    return `# untitled.ot\n\nsay "Hello from Otter!"\n`;
  }

  emitSourceChanged() {
    window.dispatchEvent(new CustomEvent('otter:source-changed', {
      detail: {
        source: this.currentCode,
        file: this.currentFile
      }
    }));
  }

  // --- Interactive Code Editor & Syntax Highlighting ---
  renderEditorCode(codeText) {
    if (!this.codeAreaEl) return;

    // Redrawing syntax-highlighted markup must not behave like navigating to
    // a new document. Keep the native editor's caret, selection, and scroll
    // viewport stable while the highlighted layer refreshes beneath it.
    const existingTextarea = document.getElementById('hiddenEditorInput');
    const editorState = existingTextarea && document.activeElement === existingTextarea
      ? {
          start: existingTextarea.selectionStart,
          end: existingTextarea.selectionEnd,
          scrollTop: existingTextarea.scrollTop,
          scrollLeft: existingTextarea.scrollLeft
        }
      : null;

    const lines = codeText.split('\n');
    this.renderGutter(lines.length);

    let html = '';
    lines.forEach((line, idx) => {
      const lineNum = idx + 1;
      let renderedLine = this.syntaxHighlightLine(line);
      const indentClass = line.startsWith('        ') ? ' ind-2' : (line.startsWith('    ') ? ' ind-1' : '');
      const errClass = (this.errorLine === lineNum) ? ' has-error' : '';

      html += `<div class="code-line${indentClass}${errClass}" data-line="${lineNum}">${renderedLine || '&nbsp;'}</div>`;
    });

    this.codeAreaEl.innerHTML = html;
    this.updateEditorChrome();

    // Attach inline editor handlers
    this.setupInlineEditor();

    if (editorState) {
      const textarea = document.getElementById('hiddenEditorInput');
      if (textarea) {
        const limit = this.currentCode.length;
        const start = Math.min(editorState.start, limit);
        const end = Math.min(editorState.end, limit);
        requestAnimationFrame(() => {
          textarea.focus({ preventScroll: true });
          textarea.setSelectionRange(start, end);
          textarea.scrollTop = editorState.scrollTop;
          textarea.scrollLeft = editorState.scrollLeft;
          if (this.codeAreaEl) {
            this.codeAreaEl.scrollTop = editorState.scrollTop;
            this.codeAreaEl.scrollLeft = editorState.scrollLeft;
          }
          if (this.gutterEl) this.gutterEl.scrollTop = editorState.scrollTop;
        });
      }
    }
  }

  setWordWrap(enabled) {
    this.wordWrap = Boolean(enabled);
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem('otter-studio-word-wrap', String(this.wordWrap));
    }
    this.updateEditorChrome();
  }

  updateEditorChrome() {
    this.codeViewport?.classList.toggle('is-word-wrapped', this.wordWrap);
    if (this.btnToggleWordWrap) {
      this.btnToggleWordWrap.classList.toggle('is-active', this.wordWrap);
      this.btnToggleWordWrap.setAttribute('aria-pressed', String(this.wordWrap));
      this.btnToggleWordWrap.title = `${this.wordWrap ? 'Disable' : 'Enable'} Word Wrap (Alt+Z)`;
    }
    this.renderBreadcrumbs();
  }

  renderBreadcrumbs() {
    if (!this.breadcrumbsEl) return;
    const path = (this.currentFile || 'untitled.ot').replace(/\\/g, '/');
    const fileParts = path.split('/').filter(Boolean);
    const project = this.currentProjectName || (this.currentProjectFolder ? this.currentProjectFolder.split(/[\\/]/).filter(Boolean).pop() : 'Otter Studio');
    const parts = project && fileParts[0] !== project ? [project, ...fileParts] : fileParts;
    this.breadcrumbsEl.innerHTML = parts.map((part, index) => {
      const separator = index ? '<span class="breadcrumb-separator">›</span>' : '';
      const current = index === parts.length - 1;
      return `${separator}<button type="button" class="breadcrumb-part${current ? ' is-current' : ''}" ${current ? 'aria-current="page"' : ''}>${this.escapeHtml(part)}</button>`;
    }).join('');
  }

  renderGutter(count) {
    if (!this.gutterEl) return;
    let spans = '';
    const maxLines = Math.max(count, 1);
    for (let i = 1; i <= maxLines; i++) {
      const errMarker = (this.errorLine === i) ? ' class="gutter-err"' : '';
      spans += `<span${errMarker}>${i}</span>`;
    }
    this.gutterEl.innerHTML = spans;
  }

  syntaxHighlightLine(line) {
    if (line.trim().startsWith('#')) {
      return `<span class="tok-comment">${this.escapeHtml(line)}</span>`;
    }

    let l = this.escapeHtml(line);

    // Strings
    l = l.replace(/"([^"]*)"/g, '<span class="tok-str">"$1"</span>');

    // Numbers
    l = l.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="tok-num">$1</span>');

    // Booleans & Special Values
    l = l.replace(/\b(true|false|gone)\b/g, '<span class="tok-bool">$1</span>');

    // Multi-word keywords & comparison operators
    const multiWordKeywords = [
      'is at least', 'is at most', 'is greater than', 'is less than', 'is not',
      'get files in', 'get folders in', 'and subfolders into', 'copy file to',
      'for each', 'name of', 'extension of', 'create folder', 'divided by',
      'on tick', 'on key'
    ];

    for (const kw of multiWordKeywords) {
      const reg = new RegExp(`\\b(${kw})\\b`, 'gi');
      l = l.replace(reg, '<span class="tok-kw">$1</span>');
    }

    // Single keywords
    const singleKeywords = [
      'make', 'when', 'function', 'return', 'stop', 'if', 'otherwise',
      'while', 'count', 'repeat', 'has', 'is', 'add', 'remove', 'put',
      'ask', 'display', 'wait', 'say', 'get', 'into', 'not', 'and', 'or',
      'game'
    ];

    for (const kw of singleKeywords) {
      const reg = new RegExp(`\\b(${kw})\\b`, 'gi');
      l = l.replace(reg, '<span class="tok-kw">$1</span>');
    }

    // Period block terminator
    l = l.replace(/(^|\s)(\.)(\s|$)/g, '$1<span class="tok-kw">.</span>$3');

    return l;
  }

  setupInlineEditor() {
    let textarea = document.getElementById('hiddenEditorInput');
    if (!textarea) {
      textarea = document.createElement('textarea');
      textarea.id = 'hiddenEditorInput';
      textarea.style.position = 'absolute';
      textarea.style.top = '0';
      textarea.style.left = '0';
      textarea.style.width = '100%';
      textarea.style.height = '100%';
      // Keep the native textarea present so its caret and selection remain
      // visible, but let the highlighted code layer provide the glyph colors.
      textarea.style.opacity = '1';
      textarea.style.color = 'transparent';
      textarea.style.caretColor = '#2563eb';
      textarea.style.background = 'transparent';
      textarea.style.border = '0';
      textarea.style.outline = 'none';
      textarea.style.zIndex = '5';
      textarea.style.fontFamily = 'inherit';
      textarea.style.fontSize = 'inherit';
      textarea.style.lineHeight = 'inherit';
      textarea.style.resize = 'none';
      textarea.spellcheck = false;
      this.codeAreaEl.parentElement.style.position = 'relative';
      this.codeAreaEl.parentElement.appendChild(textarea);

      // Pixel-perfect synchronized scrolling
      textarea.addEventListener('scroll', () => {
        this.hideHoverTooltip();
        this.hideSignatureHelp();
        if (this.codeAreaEl) {
          this.codeAreaEl.scrollTop = textarea.scrollTop;
          this.codeAreaEl.scrollLeft = textarea.scrollLeft;
        }
        if (this.gutterEl) {
          this.gutterEl.scrollTop = textarea.scrollTop;
        }
      });

      textarea.addEventListener('mousemove', (e) => {
        clearTimeout(this.hoverDebounceTimer);
        this.hoverDebounceTimer = setTimeout(() => {
          this.handleEditorHover(e);
        }, 250);
      });

      textarea.addEventListener('mouseleave', () => {
        clearTimeout(this.hoverDebounceTimer);
        this.hideHoverTooltip();
      });

      textarea.addEventListener('click', (e) => {
        if (e.ctrlKey || e.metaKey) {
          e.preventDefault();
          this.updateCursorPos(textarea);
          this.goToDefinition();
        }
      });

      textarea.addEventListener('input', () => {
        this.hideHoverTooltip();
        this.checkSignatureHelp();
        this.currentCode = textarea.value;
        this.markCurrentTabDirty(true);
        this.renderEditorCode(this.currentCode);
        this.updateCursorPos(textarea);
        this.saveSessionState();
        this.debouncedLint();
        this.emitSourceChanged();
      });

      textarea.addEventListener('keydown', (e) => {
        this.hideHoverTooltip();
        if (e.ctrlKey && e.shiftKey && e.key === ' ') {
          e.preventDefault();
          this.checkSignatureHelp();
          return;
        }
        if (e.key === 'Escape') {
          this.hideSignatureHelp();
          this.hideHoverTooltip();
        }
        // Keyboard shortcuts
        if (e.altKey && !e.ctrlKey && !e.shiftKey && e.key.toLowerCase() === 'z') {
          e.preventDefault();
          this.setWordWrap(!this.wordWrap);
          return;
        }
        if (e.key === 'F12') {
          e.preventDefault();
          if (e.shiftKey && e.altKey) this.findReferences();
          else if (e.shiftKey) this.findOccurrences();
          else if (e.altKey) this.peekDefinition();
          else this.goToDefinition();
          return;
        }
        if (e.key === 'F2') {
          e.preventDefault();
          this.promptRename();
          return;
        }
        if (e.ctrlKey && e.key === 'f') {
          e.preventDefault();
          this.openFind(false);
          return;
        }
        if (e.ctrlKey && e.key === 'h') {
          e.preventDefault();
          this.openFind(true);
          return;
        }
        if (e.ctrlKey && e.key === 'g') {
          e.preventDefault();
          this.promptGoToLine();
          return;
        }
        if (e.ctrlKey && e.key === '/') {
          e.preventDefault();
          this.toggleComment();
          return;
        }
        if ((e.shiftKey && e.altKey && (e.key === 'f' || e.key === 'F')) || (e.ctrlKey && e.shiftKey && (e.key === 'i' || e.key === 'I'))) {
          e.preventDefault();
          this.formatCurrentDocument();
          return;
        }
        if (e.ctrlKey && e.key === 's') {
          e.preventDefault();
          this.saveCurrentFile();
          return;
        }

        // Smart Auto-indent on Enter
        if (e.key === 'Enter') {
          e.preventDefault();
          const start = textarea.selectionStart;
          const end = textarea.selectionEnd;
          const val = textarea.value;
          const lineStart = val.lastIndexOf('\n', start - 1) + 1;
          const curLine = val.substring(lineStart, start);
          const indentMatch = curLine.match(/^(\s*)/);
          let indent = indentMatch ? indentMatch[1] : '';

          const trimmed = curLine.trim();
          const startsBlock = /^(?:when\s+\w+\s+(?:is\s+)?\w+|for\s+each\b|if\b|otherwise\b|repeat\b|while\b|\w+\s+has$|game\b|on\s+(?:tick|key)|function\b)/i.test(trimmed);
          if (startsBlock) {
            indent += '    ';
          }

          const insertText = '\n' + indent;
          textarea.value = val.substring(0, start) + insertText + val.substring(end);
          textarea.selectionStart = textarea.selectionEnd = start + insertText.length;
          this.currentCode = textarea.value;
          this.markCurrentTabDirty(true);
          this.renderEditorCode(this.currentCode);
          this.updateCursorPos(textarea);
          this.saveSessionState();
          this.debouncedLint();
          this.emitSourceChanged();
          return;
        }

        // Tab and Shift+Tab multi-line indent/un-indent
        if (e.key === 'Tab') {
          e.preventDefault();
          const start = textarea.selectionStart;
          const end = textarea.selectionEnd;
          const val = textarea.value;

          if (start !== end && val.substring(start, end).includes('\n')) {
            const lineStart = val.lastIndexOf('\n', start - 1) + 1;
            const lineEnd = val.indexOf('\n', end);
            const fullBlockEnd = lineEnd === -1 ? val.length : lineEnd;
            const block = val.substring(lineStart, fullBlockEnd);
            const lines = block.split('\n');
            let modified;
            if (e.shiftKey) {
              modified = lines.map(l => l.startsWith('    ') ? l.substring(4) : (l.startsWith('\t') ? l.substring(1) : l)).join('\n');
            } else {
              modified = lines.map(l => '    ' + l).join('\n');
            }
            textarea.value = val.substring(0, lineStart) + modified + val.substring(fullBlockEnd);
            textarea.selectionStart = lineStart;
            textarea.selectionEnd = lineStart + modified.length;
          } else {
            if (e.shiftKey) {
              const lineStart = val.lastIndexOf('\n', start - 1) + 1;
              if (val.substring(lineStart, lineStart + 4) === '    ') {
                textarea.value = val.substring(0, lineStart) + val.substring(lineStart + 4);
                textarea.selectionStart = textarea.selectionEnd = Math.max(lineStart, start - 4);
              }
            } else {
              textarea.value = val.substring(0, start) + '    ' + val.substring(end);
              textarea.selectionStart = textarea.selectionEnd = start + 4;
            }
          }
          this.currentCode = textarea.value;
          this.markCurrentTabDirty(true);
          this.renderEditorCode(this.currentCode);
          this.saveSessionState();
          this.debouncedLint();
          this.emitSourceChanged();
          return;
        }

        // Autocomplete keyboard handling
        if (this.autocompleteVisible) {
          const listLen = this.currentFilteredSuggestions.length;
          if (listLen > 0) {
            if (e.key === 'ArrowDown') {
              e.preventDefault();
              this.autocompleteIndex = (this.autocompleteIndex + 1) % listLen;
              this.updateAutocompleteSelection();
              return;
            } else if (e.key === 'ArrowUp') {
              e.preventDefault();
              this.autocompleteIndex = (this.autocompleteIndex - 1 + listLen) % listLen;
              this.updateAutocompleteSelection();
              return;
            } else if (e.key === 'Enter' || e.key === 'Tab') {
              e.preventDefault();
              this.insertAutocomplete(this.currentFilteredSuggestions[this.autocompleteIndex]);
              return;
            } else if (e.key === 'Escape') {
              this.hideAutocomplete();
              return;
            }
          }
        }
      });

      textarea.addEventListener('click', () => this.updateCursorPos(textarea));
      textarea.addEventListener('keyup', (e) => {
        if (!['ArrowUp', 'ArrowDown', 'Enter', 'Tab', 'Escape'].includes(e.key)) {
          this.updateCursorPos(textarea);
        }
      });
    }

    if (textarea.value !== this.currentCode) {
      textarea.value = this.currentCode;
    }
  }

  updateCursorPos(textarea) {
    if (!textarea) return;
    const textBefore = textarea.value.substring(0, textarea.selectionStart);
    const lines = textBefore.split('\n');
    const lineNum = lines.length;
    const colNum = lines[lines.length - 1].length + 1;
    if (this.statusBarPos) {
      this.statusBarPos.innerText = `Ln ${lineNum}, Col ${colNum}`;
    }

    // Dynamic Block matching
    this.checkBlockMatching(lineNum);

    // Context-aware Autocomplete popup
    const curLine = lines[lines.length - 1];
    const wordMatch = curLine.match(/[\w\-]+$/);
    if (wordMatch) {
      const word = wordMatch[0].toLowerCase();
      const matched = this.suggestions.filter(s =>
        s.title.toLowerCase().includes(word) || s.insert.toLowerCase().startsWith(word)
      );
      if (matched.length > 0 && word.length >= 2) {
        this.currentFilteredSuggestions = matched;
        this.autocompleteIndex = 0;
        this.renderAutocomplete();
        this.showAutocomplete();
        return;
      }
    }
    this.hideAutocomplete();
  }

  // --- Autocomplete Engine ---
  renderAutocomplete() {
    if (!this.autocompletePopup) return;

    const list = this.currentFilteredSuggestions.length > 0 ? this.currentFilteredSuggestions : this.suggestions;
    let itemsHtml = '';
    list.forEach((item, idx) => {
      const isSelected = (idx === this.autocompleteIndex) ? ' is-selected' : '';
      itemsHtml += `
        <div class="ac-item${isSelected}" data-index="${idx}">
          <span class="ac-icon">${item.icon}</span>
          <div class="ac-text-wrap">
            <span class="ac-title"><strong>${this.escapeHtml(item.title)}</strong></span>
            <span class="ac-desc">${this.escapeHtml(item.desc)}</span>
          </div>
        </div>
      `;
    });

    const activeItem = list[this.autocompleteIndex] || list[0] || this.suggestions[0];
    const docHtml = `
      <div class="autocomplete-doc-card">
        <div class="doc-card-title">
          <span class="doc-icon">${activeItem.icon}</span>
          <strong>${this.escapeHtml(activeItem.docTitle)}</strong>
        </div>
        <div class="doc-card-desc">${this.escapeHtml(activeItem.docDesc)}</div>
        <div class="doc-card-example-title">Example:</div>
        <div class="doc-card-example">
          ${this.escapeHtml(activeItem.example || activeItem.insert)}
        </div>
      </div>
    `;

    this.autocompletePopup.innerHTML = `
      <div class="autocomplete-list">${itemsHtml}</div>
      ${docHtml}
    `;

    // Click handlers on autocomplete items
    this.autocompletePopup.querySelectorAll('.ac-item').forEach(el => {
      el.addEventListener('click', () => {
        const idx = parseInt(el.getAttribute('data-index'), 10);
        this.autocompleteIndex = idx;
        this.insertAutocomplete(list[idx]);
      });
    });
  }

  updateAutocompleteSelection() {
    this.renderAutocomplete();
  }

  showAutocomplete() {
    if (this.autocompletePopup) {
      this.autocompletePopup.style.display = 'flex';
      this.autocompleteVisible = true;
    }
  }

  hideAutocomplete() {
    if (this.autocompletePopup) {
      this.autocompletePopup.style.display = 'none';
      this.autocompleteVisible = false;
    }
  }

  insertAutocomplete(suggestion) {
    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea && suggestion) {
      const val = textarea.value;
      const pos = textarea.selectionStart;
      const lineStart = val.lastIndexOf('\n', pos - 1) + 1;
      const curLine = val.substring(lineStart, pos);
      const lastWordMatch = curLine.match(/[\w\-]+$/);
      const prefix = lastWordMatch ? lastWordMatch[0] : '';
      const replaceStart = pos - prefix.length;

      textarea.value = val.substring(0, replaceStart) + suggestion.insert + val.substring(pos);
      textarea.selectionStart = textarea.selectionEnd = replaceStart + suggestion.insert.length;
      this.currentCode = textarea.value;
      this.markCurrentTabDirty(true);
      this.renderEditorCode(this.currentCode);
      this.updateCursorPos(textarea);
      this.saveSessionState();
      this.debouncedLint();
    }
    this.hideAutocomplete();
  }

  // --- Real Program Execution ---
  async runActiveProfile() {
    if (this.launchProfile === 'project') {
      await this.runProject();
    } else if (this.launchProfile === 'terminal') {
      await this.runInTerminal();
    } else {
      await this.runCurrentProgram();
    }
  }

  async runProject() {
    let entry = 'main.ot';
    if (this.currentProjectFolder) {
      const openMain = this.openTabs.find(t => t.path.endsWith('main.ot') || t.path.endsWith('organizer.ot'));
      if (openMain) {
        entry = openMain.path;
      } else {
        entry = `${this.currentProjectFolder}/main.ot`;
      }
    }
    await this.loadFile(entry);
    await this.runCurrentProgram();
  }

  async runInTerminal() {
    const filename = this.currentFile || 'main.ot';
    if (this.terminalInput && this.terminalForm) {
      this.terminalInput.value = `otter run "${filename}"`;
      this.terminalForm.dispatchEvent(new Event('submit'));
      const termTab = Array.from(this.drawerTabs).find(t => t.innerText.toLowerCase().includes('terminal'));
      if (termTab) termTab.click();
    }
  }

  async stopCurrentProgram() {
    try {
      await fetch('/api/stop', { method: 'POST' });
      if (this.programOutputBody) {
        this.programOutputBody.innerHTML += '<div class="log-line log-error" style="color: #f97316;">Execution stopped by user.</div>';
      }
    } catch {}
    if (this.btnStopProgram) this.btnStopProgram.style.display = 'none';
    if (this.mainRunBtn) {
      this.mainRunBtn.style.display = 'inline-flex';
      this.mainRunBtn.classList.remove('is-running');
      if (this.runBtnLabel) this.runBtnLabel.innerText = this.launchProfile === 'project' ? 'Run Project' : (this.launchProfile === 'terminal' ? 'Run (Term)' : 'Run');
    }
  }

  setLaunchProfile(profile) {
    this.launchProfile = profile;
    try {
      localStorage.setItem('otter-studio-launch-profile', profile);
    } catch {}
    if (this.launchProfileMenu) {
      this.launchProfileMenu.querySelectorAll('.launch-profile-item').forEach(item => {
        item.classList.toggle('is-active', item.dataset.profile === profile);
      });
    }
    if (this.runBtnLabel) {
      if (profile === 'project') this.runBtnLabel.innerText = 'Run Project';
      else if (profile === 'terminal') this.runBtnLabel.innerText = 'Run (Term)';
      else this.runBtnLabel.innerText = 'Run';
    }
    this.closeLaunchProfileMenu();
  }

  toggleLaunchProfileMenu() {
    if (!this.launchProfileMenu) return;
    const isVisible = this.launchProfileMenu.style.display !== 'none';
    if (isVisible) {
      this.closeLaunchProfileMenu();
    } else {
      this.launchProfileMenu.style.display = 'flex';
    }
  }

  closeLaunchProfileMenu() {
    if (this.launchProfileMenu) {
      this.launchProfileMenu.style.display = 'none';
    }
  }

  async runCurrentProgram() {
    if (!this.mainRunBtn) return;
    this.mainRunBtn.classList.add('is-running');
    if (this.runBtnLabel) this.runBtnLabel.innerText = 'Running...';
    if (this.btnStopProgram) this.btnStopProgram.style.display = 'inline-flex';
    this.mainRunBtn.style.display = 'none';

    // Save first. A disk conflict must be resolved before execution so the
    // runner never receives a version the user has not chosen explicitly.
    const saved = await this.saveCurrentFile();
    if (!saved) {
      if (this.btnStopProgram) this.btnStopProgram.style.display = 'none';
      this.mainRunBtn.style.display = 'inline-flex';
      this.mainRunBtn.classList.remove('is-running');
      if (this.runBtnLabel) this.runBtnLabel.innerText = 'Run';
      return;
    }

    // Clear output first
    if (this.programOutputBody) {
      this.programOutputBody.innerHTML = '<div class="log-line">Starting Otter execution...</div>';
    }

    try {
      const res = await fetch('/api/run', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: this.currentFile, content: this.currentCode })
      });
      const data = await res.json();

      // Render into Program Sidebar
      if (this.programOutputBody) {
        if (data.stdout) {
          const lines = data.stdout.split('\n').filter(l => l.trim().length > 0);
          let linesHtml = lines.map(line => {
            if (line.includes('All done!') || line.includes('Finished')) {
              return `<div class="log-line log-success"><strong>${this.escapeHtml(line)}</strong></div>`;
            }
            return `<div class="log-line">${this.escapeHtml(line)}</div>`;
          }).join('');
          this.programOutputBody.innerHTML = linesHtml;
        } else if (data.stderr || data.error) {
          this.programOutputBody.innerHTML = `<div class="log-line log-error" style="color: #ef4444;">${this.escapeHtml(data.stderr || data.error)}</div>`;
        }
      }

      // Render into Bottom Drawer Output Tab
      const outputTabLog = document.getElementById('outputTabLog');
      if (outputTabLog) {
        const timestamp = new Date().toLocaleTimeString();
        outputTabLog.innerHTML += `
          <div class="log-run-entry">
            <div class="log-run-meta">[${timestamp}] Finished in ${data.durationMs}ms with exit code ${data.exitCode}</div>
            <pre class="log-run-text">${this.escapeHtml(data.stdout || data.stderr || 'No output')}</pre>
          </div>
        `;
        outputTabLog.scrollTop = outputTabLog.scrollHeight;
      }

      // Update Variables Inspector
      this.updateVariablesInspector(data.exitCode === 0);

      // Update Problems / Mascot banner
      if (data.exitCode === 0) {
        this.setProblemsStatus(true, 'No problems found.', 'Your code looks good!', 'Great job!', 'Keep going! 🐾');
      } else {
        this.setProblemsStatus(false, 'Runtime Error encountered.', data.stderr || 'Execution failed. Check details in Output.', 'Need a hand?', 'Check the error message! 🔍');
      }

    } catch (err) {
      if (this.programOutputBody) {
        this.programOutputBody.innerHTML = `<div class="log-line log-error">${this.escapeHtml(err.message)}</div>`;
      }
    } finally {
      if (this.btnStopProgram) this.btnStopProgram.style.display = 'none';
      this.mainRunBtn.style.display = 'inline-flex';
      this.mainRunBtn.classList.remove('is-running');
      if (this.runBtnLabel) {
        this.runBtnLabel.innerText = this.launchProfile === 'project' ? 'Run Project' : (this.launchProfile === 'terminal' ? 'Run (Term)' : 'Run');
      }
    }
  }

  updateVariablesInspector(success) {
    if (!this.variablesBody) return;
    if (!success) {
      this.variablesBody.innerHTML = '<div class="empty-state-text" style="padding: 16px 12px; font-size: 12px; color: var(--text-faint); text-align: center;">Variables will appear here while running.</div>';
      return;
    }

    const varMap = new Map();
    const lines = (this.currentCode || '').split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.startsWith('#')) continue;
      const isMatch = trimmed.match(/^([a-zA-Z_][a-zA-Z0-9_]*)\s+is\s+(.+)$/);
      if (isMatch) {
        varMap.set(isMatch[1], isMatch[2]);
      }
      const intoMatch = trimmed.match(/into\s+([a-zA-Z_][a-zA-Z0-9_]*)$/);
      if (intoMatch) {
        varMap.set(intoMatch[1], '[ result ]');
      }
    }

    if (varMap.size === 0) {
      this.variablesBody.innerHTML = '<div class="empty-state-text" style="padding: 16px 12px; font-size: 12px; color: var(--text-faint); text-align: center;">No variables in current scope.</div>';
      return;
    }

    let html = '';
    for (const [name, val] of varMap.entries()) {
      const isStr = val.startsWith('"') && val.endsWith('"');
      html += `
        <div class="var-entry">
          <span class="var-name">${this.escapeHtml(name)}</span>
          <span class="var-value ${isStr ? 'tok-str' : ''}">${this.escapeHtml(val)}</span>
        </div>
      `;
    }
    this.variablesBody.innerHTML = html;
  }

  // --- Real Interactive Terminal ---
  async executeTerminalCommand(cmdText) {
    if (!this.terminalHistory) return;

    // Append Command Row
    const cmdEl = document.createElement('div');
    cmdEl.className = 'terminal-cmd-row';
    cmdEl.innerHTML = `<span class="prompt-text">PS C:\\projects\\otterPS&gt;</span> <span class="cmd-text">${this.escapeHtml(cmdText)}</span>`;
    this.terminalHistory.appendChild(cmdEl);

    // Append Loading indicator
    const runningEl = document.createElement('div');
    runningEl.className = 'terminal-output-loading';
    runningEl.innerText = 'Running...';
    this.terminalHistory.appendChild(runningEl);
    this.terminalHistory.scrollTop = this.terminalHistory.scrollHeight;

    try {
      const bridge = window.__OTTER_DESKTOP_BRIDGE__;
      let data;
      if (bridge && typeof bridge.exec === 'function') {
        data = await bridge.exec(cmdText);
      } else {
        const res = await fetch('/api/terminal', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ command: cmdText })
        });
        data = await res.json();
      }
      runningEl.remove();

      const outEl = document.createElement('pre');
      outEl.className = 'terminal-output-text';
      outEl.innerText = (data.stdout || data.stderr || `Command completed with exit code ${data.exitCode}`).trim();
      this.terminalHistory.appendChild(outEl);
    } catch (e) {
      runningEl.remove();
      const errEl = document.createElement('pre');
      errEl.className = 'terminal-output-text terminal-error';
      errEl.innerText = 'Execution error: ' + e.message;
      this.terminalHistory.appendChild(errEl);
    }

    this.terminalHistory.scrollTop = this.terminalHistory.scrollHeight;
  }

  // --- Real-time Syntax Checking / Diagnostics ---
  debouncedLint() {
    clearTimeout(this.lintTimer);
    this.lintTimer = setTimeout(() => this.lintCurrentCode(), 600);
  }

  async lintCurrentCode() {
    try {
      const res = await fetch('/api/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: this.currentCode })
      });
      const data = await res.json();

      if (data.Ok !== false) {
        this.errorLine = null;
        this.updateCurrentDocumentSymbols(data);
        this.setProblemsStatus(true, 'No problems found.', 'Your code looks good!', 'Great job!', 'Keep going! 🐾');
      } else {
        const errorLine = data.Line ?? data.line;
        const message = data.Message ?? data.message;
        const suggestion = data.Suggestion ?? data.suggestion;
        this.errorLine = (typeof errorLine === 'number') ? errorLine : null;
        const lineNote = errorLine ? `Line ${errorLine}: ` : '';
        const msg = lineNote + (message || 'Syntax issue detected');
        const sub = suggestion ? `Suggestion: ${suggestion}` : 'Check your grammar.';
        this.setProblemsStatus(false, msg, sub, 'Syntax Check', 'Keep checking your code! 🐾');
      }
      this.updateErrorSquiggles();
    } catch {
      // Offline fallback: assume ok
    }
  }

  updateErrorSquiggles() {
    if (!this.codeAreaEl) return;
    this.codeAreaEl.querySelectorAll('.code-line.has-error').forEach(el => el.classList.remove('has-error'));
    if (this.gutterEl) {
      this.gutterEl.querySelectorAll('.gutter-err').forEach(el => el.classList.remove('gutter-err'));
    }

    if (this.errorLine) {
      const errLineEl = this.codeAreaEl.querySelector(`[data-line="${this.errorLine}"]`);
      if (errLineEl) errLineEl.classList.add('has-error');
      if (this.gutterEl) {
        const gutterSpans = this.gutterEl.querySelectorAll('span');
        if (gutterSpans[this.errorLine - 1]) {
          gutterSpans[this.errorLine - 1].classList.add('gutter-err');
        }
      }
    }
  }

  setProblemsStatus(ok, title, subtitle, cheerH, cheerT) {
    if (this.problemTitle) this.problemTitle.innerText = title;
    if (this.problemSubtitle) this.problemSubtitle.innerText = subtitle;
    if (this.cheerHeadline) this.cheerHeadline.innerText = cheerH;
    if (this.cheerTagline) this.cheerTagline.innerText = cheerT;

    if (this.statusCheckCircle) {
      if (ok) {
        this.statusCheckCircle.style.background = '#22c55e';
        this.statusCheckCircle.innerText = '✓';
      } else {
        this.statusCheckCircle.style.background = '#ef4444';
        this.statusCheckCircle.innerText = '!';
      }
    }

    if (this.problemStatusBanner) {
      if (!ok && this.errorLine) {
        this.problemStatusBanner.classList.add('has-error-clickable');
        this.problemStatusBanner.title = `Click to navigate to line ${this.errorLine} in source`;
      } else {
        this.problemStatusBanner.classList.remove('has-error-clickable');
        this.problemStatusBanner.title = 'No problems detected';
      }
    }
  }

  handleEditorHover(event) {
    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea || !this.editorHoverTooltipEl) return;

    let offset = -1;
    const rect = textarea.getBoundingClientRect();
    const x = event.clientX - rect.left + textarea.scrollLeft;
    const y = event.clientY - rect.top + textarea.scrollTop;
    const computedStyle = window.getComputedStyle ? window.getComputedStyle(textarea) : null;
    const lineHeight = computedStyle ? (parseFloat(computedStyle.lineHeight) || 20) : 20;
    const lineIdx = Math.floor(y / lineHeight);
    const lines = textarea.value.split('\n');

    if (lineIdx >= 0 && lineIdx < lines.length) {
      const charWidth = 7.8;
      const colIdx = Math.max(0, Math.floor(x / charWidth));
      let lineStart = 0;
      for (let i = 0; i < lineIdx; i++) lineStart += lines[i].length + 1;
      offset = Math.min(lineStart + lines[lineIdx].length, lineStart + colIdx);
    }

    if (offset < 0 || offset > textarea.value.length) {
      this.hideHoverTooltip();
      return;
    }

    const word = getWordAtOffset(textarea.value, offset);
    if (!word) {
      this.hideHoverTooltip();
      return;
    }

    const info = getHoverInfo(word, this.currentFile, this.workspaceSymbols, lineIdx + 1);
    if (!info) {
      this.hideHoverTooltip();
      return;
    }

    this.showHoverTooltip(info, event.clientX, event.clientY);
  }

  showHoverTooltip(info, clientX, clientY) {
    if (!this.editorHoverTooltipEl) return;
    let html = `<div class="editor-hover-signature">${this.escapeHtml(info.signature || info.title)}</div>`;
    if (info.description) {
      html += `<div class="editor-hover-desc">${this.escapeHtml(info.description)}</div>`;
    }
    if (info.example) {
      html += `<div class="editor-hover-example"><strong>Example:</strong><br><code>${this.escapeHtml(info.example)}</code></div>`;
    }
    this.editorHoverTooltipEl.innerHTML = html;

    const viewportRect = this.codeAreaEl?.parentElement?.getBoundingClientRect() || { top: 0, left: 0, width: 600, height: 400 };
    let left = clientX - viewportRect.left + 12;
    let top = clientY - viewportRect.top + 16;
    if (left + 340 > viewportRect.width) left = Math.max(10, viewportRect.width - 350);
    if (top + 140 > viewportRect.height) top = Math.max(10, clientY - viewportRect.top - 130);

    this.editorHoverTooltipEl.style.left = `${Math.max(10, left)}px`;
    this.editorHoverTooltipEl.style.top = `${Math.max(10, top)}px`;
    this.editorHoverTooltipEl.style.display = 'block';
  }

  hideHoverTooltip() {
    if (this.editorHoverTooltipEl) {
      this.editorHoverTooltipEl.style.display = 'none';
    }
  }

  detectFileEol(content) {
    if (!content) return 'CRLF';
    const crlfCount = (content.match(/\r\n/g) || []).length;
    const lfCount = (content.match(/[^\r]\n/g) || []).length;
    this.fileEol = (lfCount > crlfCount) ? 'LF' : 'CRLF';
    this.updateEolIndicator();
    return this.fileEol;
  }

  toggleEol() {
    this.fileEol = (this.fileEol === 'CRLF') ? 'LF' : 'CRLF';
    if (this.currentCode) {
      if (this.fileEol === 'CRLF') {
        this.currentCode = this.currentCode.replace(/\r?\n/g, '\r\n');
      } else {
        this.currentCode = this.currentCode.replace(/\r\n/g, '\n');
      }
      const textarea = document.getElementById('hiddenEditorInput');
      if (textarea) textarea.value = this.currentCode;
      this.markCurrentTabDirty(true);
    }
    this.updateEolIndicator();
  }

  updateEolIndicator() {
    if (this.btnEolSelector) {
      this.btnEolSelector.textContent = this.fileEol;
    }
  }

  toggleEncoding() {
    const encodings = ['UTF-8', 'UTF-8 with BOM', 'ASCII', 'UTF-16LE'];
    const nextIdx = (encodings.indexOf(this.fileEncoding) + 1) % encodings.length;
    this.fileEncoding = encodings[nextIdx];
    if (this.btnEncodingSelector) {
      this.btnEncodingSelector.textContent = this.fileEncoding;
    }
  }

  checkSignatureHelp() {
    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea || !this.editorSignatureHelpEl) return;
    const text = textarea.value;
    const cursor = textarea.selectionStart;
    const lineStart = text.lastIndexOf('\n', cursor - 1) + 1;
    const lineUntilCursor = text.slice(lineStart, cursor);

    const help = getSignatureHelp(lineUntilCursor, this.workspaceSymbols);
    if (!help) {
      this.hideSignatureHelp();
      return;
    }
    this.showSignatureHelp(help, textarea);
  }

  showSignatureHelp(help, textarea) {
    if (!this.editorSignatureHelpEl) return;
    let labelHtml = '';
    help.parameters.forEach((param, idx) => {
      if (idx > 0) labelHtml += ' ';
      if (idx === help.activeParameter) {
        labelHtml += `<span class="editor-signature-active-param">${this.escapeHtml(param.label)}</span>`;
      } else {
        labelHtml += `<span>${this.escapeHtml(param.label)}</span>`;
      }
    });

    let html = `<div class="editor-signature-label">${this.escapeHtml(help.label)}</div>`;
    if (help.doc) {
      html += `<div class="editor-signature-doc">${this.escapeHtml(help.doc)}</div>`;
    }
    const activeDoc = help.parameters[help.activeParameter]?.doc;
    if (activeDoc) {
      html += `<div class="editor-signature-doc" style="margin-top: 4px; font-weight: 500; color: #2563eb;">${this.escapeHtml(help.parameters[help.activeParameter].label)}: ${this.escapeHtml(activeDoc)}</div>`;
    }

    this.editorSignatureHelpEl.innerHTML = html;

    const lines = textarea.value.slice(0, textarea.selectionStart).split('\n');
    const lineIdx = lines.length - 1;
    const colIdx = lines[lineIdx].length;
    const lineHeight = 20;
    const charWidth = 7.8;

    let left = Math.max(10, colIdx * charWidth - textarea.scrollLeft + 40);
    let top = Math.max(10, (lineIdx + 1) * lineHeight - textarea.scrollTop + 10);
    const viewportRect = this.codeAreaEl?.parentElement?.getBoundingClientRect() || { width: 600, height: 400 };
    if (left + 360 > viewportRect.width) left = Math.max(10, viewportRect.width - 370);
    if (top + 100 > viewportRect.height) top = Math.max(10, lineIdx * lineHeight - textarea.scrollTop - 70);

    this.editorSignatureHelpEl.style.left = `${left}px`;
    this.editorSignatureHelpEl.style.top = `${top}px`;
    this.editorSignatureHelpEl.style.display = 'block';
  }

  hideSignatureHelp() {
    if (this.editorSignatureHelpEl) {
      this.editorSignatureHelpEl.style.display = 'none';
    }
  }

  escapeHtml(str) {
    if (!str) return '';
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
}

