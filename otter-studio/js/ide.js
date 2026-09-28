// ide.js - Interactive Code Editor, Real Project Tree, Terminal, and Execution Engine for Otter Studio

import { openLaunchProfilesEditor } from './components/launch-profiles.js';
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
import { autoClosePair, backspacePair, enterKey, prepareForSave, renderIndentGuides } from './editor/editing-assist.js';
import { otterLanguageService } from './language/otter-language-service.js';
import {
  getLanguageForFile,
  getFileIcon,
  highlightSourceLine,
  isOtterFile
} from './editor/file-language-router.js';
import { highlightCssLine } from './editor/syntax/css.js';
import { highlightJsonLine } from './editor/syntax/json.js';
import { highlightOtterLine } from './editor/syntax/otter.js';
import { snapshotTabState, restoreTabState } from './editor/document-state.js';
import { renderProjectSettings } from './components/project-settings.js';
import { normalizeManifest, serializeManifest, validateManifest } from './project/project-manifest.js';
import {
  createDefaultSolution,
  normalizeSolution,
  validateSolution,
  serializeSolution,
  isWorkspaceTrusted,
  setWorkspaceTrust
} from './project/workspace-solution.js';
import { MultiCursorManager } from './editor/multi-cursor.js';
import {
  isLargeFile,
  computeVisibleRange,
  renderVirtualizedLines,
  renderVirtualizedGutter,
  DEFAULT_LINE_HEIGHT
} from './editor/large-file.js';
import {
  DiagnosticCodes,
  DiagnosticMetadata,
  resolveDiagnosticCode
} from './diagnostics/diagnostic-codes.js';
import {
  translateHostError,
  extractOtterStackFrames,
  formatOtterStackTrace
} from './diagnostics/host-translator.js';
import {
  computeExactRange,
  normalizeDiagnostic,
  getDiagnosticQuickFixes,
  DiagnosticCollection
} from './diagnostics/diagnostic-manager.js';

export class OtterStudioIde {
  constructor() {
    this.currentFile = 'untitled.ot';
    this.currentCode = '# untitled.ot\n\nsay "Hello from Otter!"\n';
    this.multiCursor = new MultiCursorManager();
    this.isLargeFileMode = false;
    this.currentVirtualRange = null;
    this.currentProjectFolder = null;
    this.currentProjectName = null;
    this.wordWrap = typeof localStorage !== 'undefined' && localStorage.getItem('otter-studio-word-wrap') === 'true';
    // Debugger (first slice): breakpoints are Otter source line numbers the
    // user armed by clicking the gutter; debugSessionId identifies the real
    // production otter.ps1 debug process on Studio's backend.
    this.debugBreakpoints = new Set();
    this.debugSessionId = null;
    this.debugPausedLine = null;
    this.debugCallStack = null;
    this.debugPollTimer = null;
    this.files = {};
    this.activeTab = 'problems'; // 'problems' | 'output' | 'terminal'
    this.autocompleteVisible = false;
    this.autocompleteIndex = 0;
    this.openTabs = []; // [{ path, name, content, isDirty, icon }]
    this.findMatches = [];
    this.currentMatchIndex = -1;
    this.errorLine = null;
    this.warningLine = null;
    this.diagnosticCollection = new DiagnosticCollection();
    this.activeDiagnostics = [];
    this.currentDiagnostic = null;
    this.currentFilteredSuggestions = [];
    this.manifestViewMode = 'form'; // 'form' | 'json'
    this.currentSolutionPath = null;
    this.currentSolution = null;
    this.isMultiRoot = false;
    this.isTrusted = true;
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
        title: '[name] is [value]',
        desc: 'Assign variable',
        insert: 'count is 0',
        example: 'score is 100',
        docTitle: '[name] is [value]',
        docDesc: 'Assigns a value to a variable (canonical Otter assignment).'
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
    window.__otterIde = this;
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
      const restored = await this.restoreSessionState();
      if (!restored) {
        this.renderCleanProjectTree();
        this.loadUntitledFile();
      }
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
    this.btnProjectSettingsHeader = document.getElementById('btnProjectSettingsHeader');
    if (this.btnProjectSettingsHeader) {
      this.btnProjectSettingsHeader.addEventListener('click', () => {
        this.openProjectSettings();
      });
    }
    this.projectSettingsContainer = document.getElementById('projectSettingsContainer');
    this.manifestToggleBar = document.getElementById('manifestToggleBar');
    this.btnToggleSettingsForm = document.getElementById('btnToggleSettingsForm');
    this.btnToggleSettingsJson = document.getElementById('btnToggleSettingsJson');

    this.btnToggleSettingsForm?.addEventListener('click', () => {
      if (this.manifestViewMode === 'form') return;
      try {
        JSON.parse(this.currentCode);
        this.manifestViewMode = 'form';
        this.activateTab(this.currentFile);
      } catch (err) {
        alert('Cannot switch to Visual Settings: project.json contains invalid JSON syntax:\n' + err.message);
      }
    });

    this.btnToggleSettingsJson?.addEventListener('click', () => {
      if (this.manifestViewMode === 'json') return;
      this.manifestViewMode = 'json';
      this.activateTab(this.currentFile);
    });

    // Workspace Trust & Multi-Root Solution Elements
    this.workspaceTrustBanner = document.getElementById('workspaceTrustBanner');
    this.btnTrustWorkspace = document.getElementById('btnTrustWorkspace');
    this.btnDismissTrustBanner = document.getElementById('btnDismissTrustBanner');
    this.btnWorkspaceTrustStatus = document.getElementById('btnWorkspaceTrustStatus');

    this.btnTrustWorkspace?.addEventListener('click', () => this.grantWorkspaceTrust());
    this.btnDismissTrustBanner?.addEventListener('click', () => this.hideTrustBanner());
    this.btnWorkspaceTrustStatus?.addEventListener('click', () => this.toggleWorkspaceTrust());
    document.getElementById('menuItemNewSolution')?.addEventListener('click', () => this.promptNewSolution());

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
    this.outlineFilterInput = document.getElementById('outlineFilterInput');
    this.btnRefreshOutline = document.getElementById('btnRefreshOutline');
    this.btnQuickOpen = document.getElementById('btnQuickOpen');
    this.btnGoToSymbol = document.getElementById('btnGoToSymbol');
    this.btnWorkspaceSymbols = document.getElementById('btnWorkspaceSymbols');
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
    this.btnExtractFunction = document.getElementById('btnExtractFunction');
    this.btnProblemQuickFix = document.getElementById('btnProblemQuickFix');
    this.availableQuickFixes = [];
    this.warningLine = null;

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
    this.statusLargeFile = document.getElementById('statusLargeFile');
    this.statusBarPos = document.getElementById('statusbarPos') || document.querySelector('.statusbar-right span:first-child');
    this.mainRunBtn = document.getElementById('mainRunBtn');
    this.btnStopProgram = document.getElementById('btnStopProgram');
    this.btnDebugProgram = document.getElementById('btnDebugProgram');
    this.btnDebugContinue = document.getElementById('btnDebugContinue');
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
    this.outlineFilterInput?.addEventListener('input', () => this.renderSourceOutline());
    this.btnQuickOpen?.addEventListener('click', () => this.openNavigationPalette('files'));
    this.btnGoToSymbol?.addEventListener('click', () => this.openNavigationPalette('symbols'));
    this.btnWorkspaceSymbols?.addEventListener('click', () => this.openNavigationPalette('workspace-symbols'));
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
    this.btnExtractFunction?.addEventListener('click', () => this.extractFunction());
    this.btnProblemQuickFix?.addEventListener('click', (e) => {
      e.stopPropagation();
      this.applyCurrentQuickFix();
    });
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
    this.problemStatusBanner?.addEventListener('click', (e) => {
      if (e.target === this.btnProblemQuickFix || this.btnProblemQuickFix?.contains(e.target)) return;
      if (this.currentDiagnostic) {
        this.navigateToDiagnostic(this.currentDiagnostic);
        return;
      }
      const target = this.errorLine || this.warningLine;
      if (target) this.goToLine(target);
    });
    this.problemStatusBanner?.addEventListener('keydown', event => {
      if (event.target === this.btnProblemQuickFix || this.btnProblemQuickFix?.contains(event.target)) return;
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        if (this.currentDiagnostic) {
          this.navigateToDiagnostic(this.currentDiagnostic);
          return;
        }
        const target = this.errorLine || this.warningLine;
        if (target) {
          this.goToLine(target);
        }
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
    this.btnDebugProgram?.addEventListener('click', () => this.startDebugSession());
    this.btnDebugContinue?.addEventListener('click', () => this.continueDebugSession());
    this.btnRunDropdown?.addEventListener('click', (e) => {
      e.stopPropagation();
      this.toggleLaunchProfileMenu();
    });
    document.addEventListener('click', () => this.closeLaunchProfileMenu());

    // The menu is rebuilt from the project's launch.json (renderLaunchMenu),
    // so one delegated listener handles every item.
    this.launchProfileMenu?.addEventListener('click', (e) => {
      const item = e.target.closest('[data-profile], [data-launch-action]');
      if (!item) return;
      e.stopPropagation();
      if (item.dataset.profile) this.setLaunchProfile(item.dataset.profile);
      else this.runLaunchAction(item.dataset.launchAction);
    });
    this.renderLaunchMenu();

    // Keyboard Shortcuts: F5 / Ctrl+Enter to Run
    window.addEventListener('keydown', (e) => {
      if (e.key === 'F5' && e.ctrlKey && e.shiftKey) {
        e.preventDefault();
        this.restartProgram();
        return;
      }
      if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'b') {
        e.preventDefault();
        this.buildProject();
        return;
      }
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
      if (e.ctrlKey && !e.shiftKey && e.key.toLowerCase() === 't') {
        e.preventDefault();
        this.openNavigationPalette('workspace-symbols');
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

    if (folder.endsWith('.solution.json') || folder.endsWith('solution.json') || folder.endsWith('.otter-workspace')) {
      await this.loadSolution(folder);
      return;
    }

    try {
      const res = await fetch(`/api/project?folder=${encodeURIComponent(folder)}`);
      const data = await res.json();
      if (data && data.tree && data.tree.length > 0) {
        this.isMultiRoot = false;
        this.currentSolutionPath = null;
        this.currentSolution = null;
        this.currentProjectFolder = data.rootPath || folder;
        this.currentProjectName = data.name || folder;
        this.setTemplatesCollapsed(true);
        this.workspaceFiles = flattenProjectFiles(data.tree, this.currentProjectFolder);
        this.renderProjectTree(data.tree, this.currentProjectName, this.currentProjectFolder);
        this.checkWorkspaceTrust();
        this.refreshWorkspaceSymbols();
        await this.loadDesignerStylesheet();
        await this.loadLaunchConfig();
      } else {
        alert(data.error || 'Folder is empty or could not be loaded.');
      }
    } catch (err) {
      console.warn('Could not fetch project tree from server:', err);
    }
  }

  async loadSolution(solutionPath) {
    try {
      const res = await fetch(`/api/workspace?path=${encodeURIComponent(solutionPath)}`);
      const data = await res.json();
      if (!res.ok || !data.ok) {
        throw new Error(data.error || 'Could not load solution.');
      }
      this.currentSolutionPath = data.path;
      this.currentSolution = data.solution;
      this.isMultiRoot = true;
      this.currentProjectName = data.solution.name;
      this.currentProjectFolder = data.path;

      // Flatten files across all project roots
      const allFiles = [];
      for (const root of data.roots || []) {
        const rootFiles = flattenProjectFiles(root.tree, root.path);
        allFiles.push(...rootFiles);
      }
      this.workspaceFiles = allFiles;

      this.setTemplatesCollapsed(true);
      this.renderMultiRootProjectTree(data.solution, data.roots);
      this.checkWorkspaceTrust();
      this.refreshWorkspaceSymbols();
      await this.loadDesignerStylesheet();
      this.saveSessionState();
    } catch (err) {
      console.warn('Error loading solution:', err);
      alert('Error loading solution: ' + err.message);
    }
  }

  renderMultiRootProjectTree(solution, roots = []) {
    if (!this.projectTreeEl) return;

    let html = `
      <div class="solution-header" title="${this.escapeHtml(this.currentSolutionPath || '')}">
        <div class="solution-title">
          <span class="solution-icon">📦</span>
          <span>${this.escapeHtml(solution.name || 'Solution')}</span>
        </div>
        <span class="solution-badge">${roots.length} PROJECTS</span>
      </div>
      <div class="multi-root-container">
    `;

    const renderNodes = (nodes, parentFolder) => {
      let out = '';
      for (const item of nodes) {
        const fullPath = parentFolder ? `${parentFolder}/${item.path}` : item.path;
        const isSelected = (this.currentFile === fullPath) ? ' is-active' : '';
        if (item.isDir) {
          out += `
            <div class="project-folder-item" data-folder="${fullPath}">
              <span class="folder-arrow">▾</span>
              <span class="folder-icon">📁</span>
              <span class="folder-name">${this.escapeHtml(item.name)}</span>
            </div>
            <div class="folder-children-wrap" data-parent-folder="${fullPath}">
              ${item.children ? renderNodes(item.children, parentFolder) : ''}
            </div>
          `;
        } else {
          const icon = item.name.endsWith('.ot') ? '📄' : (item.name.endsWith('.css') ? '🎨' : (item.name.endsWith('.json') ? '⚙' : '📝'));
          out += `
            <div class="project-file-item${isSelected}" data-path="${fullPath}" title="${fullPath}">
              <span class="file-icon">${icon}</span>
              <span class="file-name">${this.escapeHtml(item.name)}</span>
            </div>
          `;
        }
      }
      return out;
    };

    for (const root of roots) {
      html += `
        <div class="multi-root-folder" data-root-path="${root.path}">
          <div class="multi-root-header">
            <span class="root-arrow">▾</span>
            <span class="root-icon">📁</span>
            <span class="root-name">${this.escapeHtml(root.name)}</span>
          </div>
          <div class="root-children-wrap">
            ${renderNodes(root.tree, root.path)}
          </div>
        </div>
      `;
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

    this.projectTreeEl.querySelectorAll('.multi-root-header').forEach(header => {
      header.addEventListener('click', () => {
        const wrap = header.nextElementSibling;
        const arrow = header.querySelector('.root-arrow');
        if (wrap) {
          const isCollapsed = wrap.style.display === 'none';
          wrap.style.display = isCollapsed ? 'block' : 'none';
          if (arrow) arrow.textContent = isCollapsed ? '▾' : '›';
        }
      });
    });

    this.projectTreeEl.querySelectorAll('.project-folder-item').forEach(el => {
      el.addEventListener('click', () => {
        const folder = el.getAttribute('data-folder');
        const wrap = this.projectTreeEl.querySelector(`.folder-children-wrap[data-parent-folder="${folder}"]`);
        const arrow = el.querySelector('.folder-arrow');
        if (wrap) {
          const isCollapsed = wrap.style.display === 'none';
          wrap.style.display = isCollapsed ? 'block' : 'none';
          if (arrow) arrow.textContent = isCollapsed ? '▾' : '›';
        }
      });
    });
  }

  async promptNewSolution() {
    const name = prompt('Enter solution name (e.g. MySuite):', 'MySuite');
    if (!name) return;
    const folders = [];
    if (this.currentProjectFolder && !this.isMultiRoot) {
      folders.push({ name: this.currentProjectName || 'App', path: this.currentProjectFolder });
    }
    try {
      const res = await fetch('/api/create-solution', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, folders })
      });
      const data = await res.json();
      if (data.ok) {
        await this.loadSolution(data.path);
      }
    } catch (e) {
      alert('Error creating solution: ' + e.message);
    }
  }

  checkWorkspaceTrust() {
    const target = this.currentSolutionPath || this.currentProjectFolder;
    this.isTrusted = isWorkspaceTrusted(target, this.currentSolution);

    if (this.workspaceTrustBanner) {
      this.workspaceTrustBanner.style.display = this.isTrusted ? 'none' : 'flex';
    }

    if (this.btnWorkspaceTrustStatus) {
      this.btnWorkspaceTrustStatus.textContent = this.isTrusted ? '🛡️ Trusted' : '🛡️ Restricted';
      this.btnWorkspaceTrustStatus.className = `statusbar-btn trust-status-btn ${this.isTrusted ? 'is-trusted' : 'is-untrusted'}`;
      this.btnWorkspaceTrustStatus.title = this.isTrusted ? 'Workspace is trusted. Execution permitted.' : 'Workspace is in Restricted Mode. Click to manage trust.';
    }
  }

  grantWorkspaceTrust() {
    const target = this.currentSolutionPath || this.currentProjectFolder;
    setWorkspaceTrust(target, true);
    if (this.currentSolution?.trust) {
      this.currentSolution.trust.isTrusted = true;
    }
    this.isTrusted = true;
    this.checkWorkspaceTrust();
  }

  hideTrustBanner() {
    if (this.workspaceTrustBanner) {
      this.workspaceTrustBanner.style.display = 'none';
    }
  }

  toggleWorkspaceTrust() {
    const target = this.currentSolutionPath || this.currentProjectFolder;
    const next = !this.isTrusted;
    setWorkspaceTrust(target, next);
    if (this.currentSolution?.trust) {
      this.currentSolution.trust.isTrusted = next;
    }
    this.isTrusted = next;
    this.checkWorkspaceTrust();
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

    const renderNodes = (nodes, parentFolder) => {
      let out = '';
      for (const item of nodes) {
        const fullPath = parentFolder ? `${parentFolder}/${item.path}` : item.path;
        const isSelected = (this.currentFile === fullPath) ? ' is-active' : '';
        if (item.isDir) {
          out += `
            <div class="project-folder-item" data-folder="${fullPath}">
              <span class="folder-arrow">▾</span>
              <span class="folder-icon">📁</span>
              <span class="folder-name">${this.escapeHtml(item.name)}</span>
            </div>
            <div class="folder-children-wrap" data-parent-folder="${fullPath}">
              ${item.children ? renderNodes(item.children, parentFolder) : ''}
            </div>
          `;
        } else {
          const icon = item.name.endsWith('.ot') ? '📄' : (item.name.endsWith('.css') ? '🎨' : (item.name.endsWith('.json') ? '⚙' : '📝'));
          out += `
            <div class="project-file-item${isSelected}" data-path="${fullPath}" title="${fullPath}">
              <span class="file-icon">${icon}</span>
              <span class="file-name">${this.escapeHtml(item.name)}</span>
            </div>
          `;
        }
      }
      return out;
    };

    html += renderNodes(items, rootFolder);
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

    this.projectTreeEl.querySelectorAll('.project-folder-item').forEach(el => {
      el.addEventListener('click', () => {
        const folder = el.getAttribute('data-folder');
        const wrap = this.projectTreeEl.querySelector(`.folder-children-wrap[data-parent-folder="${folder}"]`);
        const arrow = el.querySelector('.folder-arrow');
        if (wrap) {
          const isCollapsed = wrap.style.display === 'none';
          wrap.style.display = isCollapsed ? 'block' : 'none';
          if (arrow) arrow.textContent = isCollapsed ? '▾' : '›';
        }
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
    const allSymbols = symbolsForFile(this.workspaceSymbols, this.currentFile)
      .filter(symbol => Number(symbol.ScopeId) === 0);
    const filterQuery = (this.outlineFilterInput?.value || '').trim().toLowerCase();
    const symbols = filterQuery
      ? allSymbols.filter(s => (s.Name || '').toLowerCase().includes(filterQuery) || (s.Kind || '').toLowerCase().includes(filterQuery))
      : allSymbols;

    if (symbols.length === 0) {
      this.sourceOutlineBody.innerHTML = `<div class="outline-empty">${filterQuery ? 'No matching symbols found.' : 'No declarations found in this file.'}</div>`;
      return;
    }
    this.sourceOutlineBody.innerHTML = symbols.map((symbol, index) => {
      const kind = (symbol.Kind || 'variable').toLowerCase();
      const kindClass = kind === 'function' ? 'kind-fn' : (kind === 'ui' ? 'kind-ui' : (kind === 'object' ? 'kind-obj' : 'kind-var'));
      const icon = kind === 'function' ? 'ƒ' : (kind === 'ui' ? '⊞' : (kind === 'object' ? '◇' : 'v'));
      return `
      <button class="outline-symbol" type="button" data-outline-index="${index}" title="Go to line ${Number(symbol.Line) || 1}">
        <span class="outline-symbol-icon ${kindClass}">${icon}</span>
        <span class="outline-symbol-name">${this.escapeHtml(symbol.Name)}</span>
        <span class="outline-symbol-line">${Number(symbol.Line) || 1}</span>
      </button>
    `;
    }).join('');
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
        .map(symbol => {
          const kind = (symbol.Kind || 'variable').toLowerCase();
          return {
            type: 'symbol',
            label: symbol.Name,
            detail: kind,
            line: Number(symbol.Line) || 1,
            column: Number(symbol.Column) || 0,
            icon: kind === 'function' ? 'ƒ' : (kind === 'ui' ? '⊞' : (kind === 'object' ? '◇' : 'v'))
          };
        });
    } else if (mode === 'workspace-symbols') {
      this.navigationPaletteTitle.textContent = 'Workspace Symbols';
      this.navigationPaletteInput.placeholder = 'Type a symbol name across workspace…';
      this.navigationItems = otterLanguageService.searchWorkspaceSymbols(this.workspaceSymbols, '');
    } else if (mode === 'commands') {
      // Every Studio action, from the shared registry (js/shell/commands.js).
      this.navigationPaletteTitle.textContent = 'Commands';
      this.navigationPaletteInput.placeholder = 'Type a command…';
      this.navigationItems = window.otterCommands ? window.otterCommands.toPaletteItems() : [];
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
    const rawVal = this.navigationPaletteInput?.value || '';
    if (rawVal.startsWith('>')) {
      // ">" turns any palette into the command palette, as in most editors.
      this.navigationMode = 'commands';
      this.navigationPaletteTitle.textContent = 'Commands';
      const query = rawVal.slice(1).trim();
      const commands = window.otterCommands ? window.otterCommands.toPaletteItems() : [];
      this.filteredNavigationItems = query ? filterNavigationItems(commands, query) : commands;
    } else if (this.navigationMode === 'commands') {
      const commands = window.otterCommands ? window.otterCommands.toPaletteItems() : [];
      this.filteredNavigationItems = rawVal.trim() ? filterNavigationItems(commands, rawVal) : commands;
    } else if (rawVal.startsWith('#')) {
      this.navigationMode = 'workspace-symbols';
      this.navigationPaletteTitle.textContent = 'Workspace Symbols';
      const query = rawVal.slice(1).trim();
      this.filteredNavigationItems = otterLanguageService.searchWorkspaceSymbols(this.workspaceSymbols, query);
    } else if (this.navigationMode === 'workspace-symbols') {
      this.filteredNavigationItems = otterLanguageService.searchWorkspaceSymbols(this.workspaceSymbols, rawVal);
    } else {
      this.filteredNavigationItems = filterNavigationItems(this.navigationItems, rawVal);
    }
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
        <span class="navigation-item-meta">${item.type === 'command' ? this.escapeHtml(item.shortcut || '') : (item.type === 'symbol' || item.type === 'occurrence' ? `Line ${item.line}` : '')}</span>
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
    if (item.type === 'command') {
      await item.run();
      return;
    }
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

  applyCurrentQuickFix() {
    if (!this.availableQuickFixes || this.availableQuickFixes.length === 0) return;
    const fix = this.availableQuickFixes[0];
    const newCode = fix.apply();
    if (typeof newCode === 'string' && newCode !== this.currentCode) {
      this.currentCode = newCode;
      this.markCurrentTabDirty(true);
      this.renderEditorCode(this.currentCode);
      const textarea = document.getElementById('hiddenEditorInput');
      if (textarea) textarea.value = this.currentCode;
      this.debouncedLint();
    }
  }

  extractFunction() {
    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea) return;
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const selectedText = (start !== end) ? textarea.value.substring(start, end) : '';
    if (!selectedText.trim()) {
      alert('Please select the code statements you wish to extract into a function.');
      return;
    }

    const fnName = prompt('Enter new function name for extracted code:', 'extractedAction');
    if (!fnName) return;

    const beforeSel = textarea.value.substring(0, start);
    const cursorLine = beforeSel.split('\n').length;
    const result = otterLanguageService.prepareExtractFunction(selectedText, fnName, this.currentCode, cursorLine);
    if (!result.ok) {
      alert(result.error);
      return;
    }

    this.currentCode = result.newCode;
    this.markCurrentTabDirty(true);
    this.renderEditorCode(this.currentCode);
    if (textarea) textarea.value = this.currentCode;
    this.debouncedLint();
    this.setProblemsStatus(true, `Extracted function '${result.fnName}'.`, 'Code refactored successfully.');
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

    if (this.openTabs.length === 1 && this.openTabs[0].path === 'untitled.ot' && !this.openTabs[0].isDirty) {
      this.openTabs = [];
    }

    // A file that cannot be read must not open. This used to fall back to
    // the "Hello from Otter" starter text with no disk revision, so pressing
    // Save replaced the real file with the starter program.
    let fileContent;
    let fileRevision;
    try {
      const res = await fetch(`/api/file?path=${encodeURIComponent(filePath)}`);
      const data = await res.json();
      if (!res.ok || !data || typeof data.content !== 'string') {
        throw new Error(data?.error || `The server returned ${res.status}.`);
      }
      fileContent = data.content;
      fileRevision = data.revision || null;
    } catch (err) {
      alert(`Could not open ${filePath}: ${err.message}`);
      return;
    }

    const fileName = filePath.split('/').pop();
    const icon = getFileIcon(filePath);
    const newTab = {
      path: filePath,
      name: fileName,
      content: fileContent,
      isDirty: false,
      icon,
      diskRevision: fileRevision,
      externalRevision: null,
      externalContent: null,
      externalDeleted: false,
      selectionStart: 0,
      selectionEnd: 0,
      scrollTop: 0,
      scrollLeft: 0
    };
    this.openTabs.push(newTab);
    this.activateTab(filePath);
  }

  activateTab(filePath) {
    const tab = this.openTabs.find(t => t.path === filePath);
    if (!tab) return;

    // Snapshot departing tab's unsaved text, caret selection, and scroll offsets
    if (this.currentFile && this.currentFile !== filePath) {
      const prevTab = this.openTabs.find(t => t.path === this.currentFile);
      if (prevTab) {
        const textarea = document.getElementById('hiddenEditorInput');
        snapshotTabState(prevTab, textarea);
      }
    }

    this.currentFile = tab.path;
    this.currentCode = tab.content;
    this.detectFileEol(this.currentCode);

    if (this.multiCursor) {
      this.multiCursor.setPrimaryCursor(0, 0);
      this.multiCursor.clearSecondaryCursors();
    }

    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea) {
      textarea.value = this.currentCode;
    }

    this.renderTabs();
    this.renderEditorCode(this.currentCode);
    this.lintCurrentCode();
    this.renderExternalChangeBanner();
    this.renderSourceOutline();

    if (this.projectTreeEl) {
      this.projectTreeEl.querySelectorAll('.project-file-item').forEach(el => {
        if (el.getAttribute('data-path') === filePath) {
          el.classList.add('is-active');
        } else {
          el.classList.remove('is-active');
        }
      });
    }

    // Only the stylesheet the designer writes to may replace its CSS model.
    // Opening any other .css file used to load that file's text into the
    // model, and the next save wrote it over styles.css.
    if (filePath.endsWith('.css') && window.otterCssAstManager && filePath === window.otterCssAstManager.sourcePath) {
      try {
        const css = window.otterCssAstManager;
        if (css.dirty && !tab.isDirty) {
          // Designer style edits not saved yet: the tab takes them over as
          // unsaved text instead of the disk copy silently discarding them.
          this.currentCode = css.generateCss();
          if (textarea) textarea.value = this.currentCode;
          this.renderEditorCode(this.currentCode);
          this.markCurrentTabDirty(true);
          css.dirty = false;
        }
        css.parse(this.currentCode);
        const styleTag = document.getElementById('canvasUserCss');
        if (styleTag) {
          styleTag.textContent = window.otterCssAstManager.generateCss();
        }
        // Let the designer re-scope the stylesheet for its canvas.
        window.dispatchEvent(new CustomEvent('css-updated', { detail: { source: 'css-file' } }));
      } catch (err) {
        console.warn('CSS AST sync on tab activate:', err);
      }
    }

    // Restore caret position and scroll offset for newly activated tab
    restoreTabState(tab, textarea, this.codeAreaEl, this.gutterEl);
    if (textarea && this.multiCursor) {
      this.multiCursor.setPrimaryCursor(textarea.selectionStart, textarea.selectionEnd);
    }
    this.renderCursorOverlays();

    // Project Manifest Mode Handling (Visual Form vs Raw JSON)
    const isManifest = filePath.endsWith('project.json');
    if (this.manifestToggleBar) {
      this.manifestToggleBar.style.display = isManifest ? 'flex' : 'none';
    }

    if (isManifest && this.manifestViewMode === 'form') {
      if (this.projectSettingsContainer) {
        this.projectSettingsContainer.style.display = 'block';
      }
      if (this.codeViewport) {
        this.codeViewport.style.display = 'none';
      }
      this.btnToggleSettingsForm?.classList.add('is-active');
      this.btnToggleSettingsJson?.classList.remove('is-active');
      this.renderProjectSettingsView();
    } else {
      if (this.projectSettingsContainer) {
        this.projectSettingsContainer.style.display = 'none';
      }
      if (this.codeViewport) {
        this.codeViewport.style.display = 'flex';
      }
      if (isManifest) {
        this.btnToggleSettingsForm?.classList.remove('is-active');
        this.btnToggleSettingsJson?.classList.add('is-active');
      }
    }

    this.saveSessionState();
    window.dispatchEvent(new CustomEvent('otter:ensure-editor-visible', { detail: { path: filePath } }));
    // The designer re-reads its model from the newly active .ot file. Before
    // this, the model kept the previous file's UI, and the next designer
    // click wrote that UI into this file.
    window.dispatchEvent(new CustomEvent('otter:active-file-changed', {
      detail: { file: filePath, source: this.currentCode }
    }));
  }

  async openProjectSettings() {
    let manifestPath = 'project.json';
    if (this.currentProjectFolder) {
      manifestPath = `${this.currentProjectFolder}/project.json`;
    }
    this.manifestViewMode = 'form';
    await this.loadFile(manifestPath);
  }

  renderProjectSettingsView() {
    if (!this.projectSettingsContainer) return;
    let manifestObj = null;
    try {
      manifestObj = JSON.parse(this.currentCode);
    } catch {
      manifestObj = normalizeManifest(null);
    }

    renderProjectSettings(this.projectSettingsContainer, {
      manifest: manifestObj,
      filePath: this.currentFile,
      projectFiles: this.workspaceFiles,
      onChange: (updatedManifest) => {
        const serialized = serializeManifest(updatedManifest);
        this.currentCode = serialized;
        const currentTab = this.openTabs.find(t => t.path === this.currentFile);
        if (currentTab) {
          currentTab.content = serialized;
          currentTab.isDirty = true;
        }
        const textarea = document.getElementById('hiddenEditorInput');
        if (textarea) {
          textarea.value = serialized;
        }
        this.renderTabs();

        if (updatedManifest.name) {
          this.currentProjectName = updatedManifest.name;
          const projTitleEl = document.getElementById('projectCardTitle');
          if (projTitleEl) {
            projTitleEl.textContent = `Project: ${updatedManifest.name}`;
          }
        }
      },
      onSwitchToJson: () => {
        this.manifestViewMode = 'json';
        this.activateTab(this.currentFile);
      },
      onSave: () => {
        this.saveCurrentFile();
      }
    });
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
        this.applySaveSettings();
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

        if (this.currentFile && this.currentFile.endsWith('project.json')) {
          try {
            const parsed = JSON.parse(this.currentCode);
            if (parsed.name) {
              this.currentProjectName = parsed.name;
              const projTitleEl = document.getElementById('projectCardTitle');
              if (projTitleEl) {
                projTitleEl.textContent = `Project: ${parsed.name}`;
              }
            }
          } catch {}
        }
      }

      // Designer style edits are written only when there are some, and
      // with the revision they were based on (see saveDesignerStylesheet).
      await this.saveDesignerStylesheet();

      // Clear dirty state on tab
      if (tab) {
        tab.isDirty = false;
        tab.content = this.currentCode;
        this.renderTabs();
      }
      window.dispatchEvent(new CustomEvent('otter:file-saved', { detail: { path: this.currentFile } }));
      this.renderExternalChangeBanner();
      this.saveSessionState();
      return true;
    } catch (err) {
      console.warn('Save file error:', err);
      return false;
    }
  }

  // The stylesheet the designer's style edits belong to.
  // Seam with the language release: Otter 1.0 (D-3) makes `<entry>.css`
  // the rule for a program's stylesheet. When Studio adopts it, this is the
  // one place to change.
  projectStylesheetPath() {
    const folder = this.currentProjectFolder;
    if (!folder || /\.(json|otter-workspace)$/i.test(folder)) return null; // solutions have no single stylesheet
    return `${folder}/styles.css`;
  }

  // Read the project's stylesheet into the designer's CSS model, remembering
  // its path and revision. Until this has run, the model is not bound to a
  // file and nothing is ever written for it.
  async loadDesignerStylesheet() {
    const css = window.otterCssAstManager;
    if (!css) return;
    const sheetPath = this.projectStylesheetPath();
    css.sourcePath = null;
    css.revision = null;
    if (!sheetPath) return;

    // An open, edited tab is newer than the disk copy.
    const tab = this.openTabs.find(t => t.path === sheetPath);
    try {
      if (tab) {
        css.parse(tab.content);
        css.revision = tab.diskRevision || null;
      } else {
        const res = await fetch(`/api/file?path=${encodeURIComponent(sheetPath)}`);
        if (res.status === 404) {
          css.parse('');
        } else {
          const data = await res.json();
          if (!res.ok || typeof data.content !== 'string') throw new Error(data.error || `status ${res.status}`);
          css.parse(data.content);
          css.revision = data.revision || null;
        }
      }
      css.sourcePath = sheetPath;
    } catch (err) {
      // Unknown state: leave the model unbound so it can never be written.
      console.warn('Could not read the project stylesheet:', err);
      return;
    }

    const styleTag = document.getElementById('canvasUserCss');
    if (styleTag) styleTag.textContent = css.generateCss();
    window.dispatchEvent(new CustomEvent('css-updated', { detail: { source: 'disk' } }));
  }

  // Write designer style edits to the project's stylesheet, if there are any
  // and the stylesheet is not open in a tab (an open tab receives the edits
  // as unsaved text and is saved like any other file). The save carries the
  // revision the edits were based on, so a newer file on disk is reported as
  // a conflict instead of being overwritten.
  async saveDesignerStylesheet() {
    const css = window.otterCssAstManager;
    if (!css || !css.dirty || !css.sourcePath) return true;
    if (this.openTabs.some(t => t.path === css.sourcePath)) return true;

    const res = await fetch('/api/file', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        path: css.sourcePath,
        content: css.generateCss(),
        expectedRevision: css.revision || undefined
      })
    });
    const data = await res.json().catch(() => ({}));
    if (res.status === 409 && data.conflict) {
      alert(`${css.sourcePath} changed on disk, so your designer style changes were not saved over it. Open the stylesheet to compare and merge.`);
      return false;
    }
    if (!res.ok) {
      alert(`Could not save ${css.sourcePath}: ${data.error || res.status}`);
      return false;
    }
    css.markSaved(data.revision || null);
    return true;
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
      // The designer re-reads the new text too, so it never shows (or
      // writes back) the design of the old version.
      this.emitSourceChanged();
    }
    this.saveSessionState();
  }

  // Re-read one open tab from disk after something outside the editor
  // changed the file (Git discard, merge, branch switch, conflict editor).
  // A tab with unsaved edits is not overwritten: it gets the usual
  // "changed on disk" conflict banner so the user chooses.
  async reloadTabFromDisk(filePath) {
    const tab = this.openTabs.find(t => t.path === filePath);
    if (!tab) return;
    try {
      const res = await fetch(`/api/file?path=${encodeURIComponent(filePath)}`);
      if (res.status === 404) {
        tab.externalDeleted = true;
      } else {
        const snapshot = await res.json();
        if (!res.ok || typeof snapshot.content !== 'string') return;
        if (snapshot.revision === tab.diskRevision) return;
        if (tab.isDirty) this.setExternalConflict(tab, snapshot);
        else this.applyExternalSnapshot(tab, snapshot);
      }
    } catch (err) {
      console.warn('Could not reload from disk:', err);
    }
    this.renderTabs();
    if (tab.path === this.currentFile) this.renderExternalChangeBanner();
  }

  async reloadCleanTabsFromDisk() {
    for (const tab of this.openTabs.filter(t => t.path !== 'untitled.ot')) {
      await this.reloadTabFromDisk(tab.path);
    }
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
  // A Studio setting, read through the shared store when it is mounted.
  setting(path, fallback) {
    const value = window.otterSettings ? window.otterSettings.get(path) : undefined;
    return value === undefined ? fallback : value;
  }

  isOtterFile() {
    return !this.currentFile || this.currentFile.endsWith('.ot');
  }

  // Apply an edit produced by js/editor/editing-assist.js and refresh
  // everything that follows a keystroke.
  applyAssistedEdit(textarea, edit) {
    textarea.value = edit.text;
    textarea.selectionStart = edit.start;
    textarea.selectionEnd = edit.end;
    this.currentCode = textarea.value;
    this.markCurrentTabDirty(true);
    this.renderEditorCode(this.currentCode);
    this.updateCursorPos(textarea);
    this.saveSessionState();
    this.debouncedLint();
    this.emitSourceChanged();
  }

  // What the file settings do to a buffer before it is written.
  applySaveSettings() {
    let content = this.currentCode;
    if (this.isOtterFile() && this.setting('files.formatOnSave', false)) {
      content = this.formatOtterCode(content);
    }
    content = prepareForSave(content, {
      trimTrailingWhitespace: this.setting('files.trimTrailingWhitespace', true),
      insertFinalNewline: this.setting('files.insertFinalNewline', true)
    });
    if (content !== this.currentCode) {
      this.currentCode = content;
      const textarea = document.getElementById('hiddenEditorInput');
      if (textarea) {
        const at = Math.min(textarea.selectionStart, content.length);
        textarea.value = content;
        textarea.selectionStart = textarea.selectionEnd = at;
      }
      this.renderEditorCode(this.currentCode);
    }
  }

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
    this.caretMoves = (this.caretMoves || 0) + 1;
    textarea.dataset.caretMoves = String(this.caretMoves);
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

    // The textarea owns the scroll position (the code view and gutter mirror
    // it), so scroll it and let the mirrors follow; scrolling the code view
    // alone was undone by the next sync. Center the line.
    const lineHeight = DEFAULT_LINE_HEIGHT || 22;
    const targetScrollTop = Math.max(0, (targetLine - 1) * lineHeight - textarea.clientHeight / 2 + lineHeight / 2);
    textarea.scrollTop = targetScrollTop;
    if (this.codeAreaEl) this.codeAreaEl.scrollTop = textarea.scrollTop;
    if (this.gutterEl) this.gutterEl.scrollTop = textarea.scrollTop;
    if (this.isLargeFileMode) this.handleVirtualizedScroll(textarea);
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
      const activeTextarea = document.getElementById('hiddenEditorInput');
      if (activeTextarea && this.currentFile) {
        const curTab = this.openTabs.find(t => t.path === this.currentFile);
        if (curTab) {
          snapshotTabState(curTab, activeTextarea);
        }
      }
      const session = {
        currentFile: this.currentFile,
        currentFolder: this.currentProjectFolder,
        currentSolutionPath: this.currentSolutionPath,
        isMultiRoot: this.isMultiRoot,
        openTabs: this.openTabs.map(t => ({
          path: t.path,
          name: t.name,
          content: t.content,
          isDirty: t.isDirty,
          icon: t.icon,
          diskRevision: t.diskRevision || null,
          selectionStart: t.selectionStart,
          selectionEnd: t.selectionEnd,
          scrollTop: t.scrollTop,
          scrollLeft: t.scrollLeft
        }))
      };
      localStorage.setItem('otter_studio_session', JSON.stringify(session));
    } catch (e) {}
  }

  async restoreSessionState() {
    try {
      const saved = localStorage.getItem('otter_studio_session');
      if (!saved) return false;
      const session = JSON.parse(saved);
      if (session && session.openTabs && session.openTabs.length > 0) {
        this.openTabs = session.openTabs;
        this.currentProjectFolder = session.currentFolder || null;
        this.currentSolutionPath = session.currentSolutionPath || null;
        this.isMultiRoot = Boolean(session.isMultiRoot);
        this.currentFile = session.currentFile || session.openTabs[0].path;
        const curTab = this.openTabs.find(t => t.path === this.currentFile) || this.openTabs[0];
        this.currentCode = curTab.content;
        this.renderTabs();
        this.renderEditorCode(this.currentCode);
        this.lintCurrentCode();
        if (session.currentSolutionPath) {
          await this.loadSolution(session.currentSolutionPath);
        } else if (this.currentProjectFolder) {
          await this.loadProjectTree(this.currentProjectFolder);
        }
        const textarea = document.getElementById('hiddenEditorInput');
        restoreTabState(curTab, textarea, this.codeAreaEl, this.gutterEl);
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
    this.isLargeFileMode = isLargeFile(codeText);
    if (this.statusLargeFile) {
      this.statusLargeFile.style.display = this.isLargeFileMode ? 'inline-block' : 'none';
    }

    if (this.isLargeFileMode) {
      const viewportHeight = this.codeAreaEl.parentElement?.clientHeight || 600;
      const scrollTop = existingTextarea ? existingTextarea.scrollTop : (this.codeAreaEl.parentElement?.scrollTop || 0);
      const range = computeVisibleRange(scrollTop, viewportHeight, lines.length, DEFAULT_LINE_HEIGHT, 40);
      this.currentVirtualRange = range;

      const gutterHtml = renderVirtualizedGutter(range.startIndex, range.endIndex, range.topSpacerHeight, range.bottomSpacerHeight, this.errorLine, this.warningLine);
      if (this.gutterEl) this.gutterEl.innerHTML = gutterHtml;

      const linesHtml = renderVirtualizedLines(
        lines,
        range.startIndex,
        range.endIndex,
        range.topSpacerHeight,
        range.bottomSpacerHeight,
        (line) => this.renderLineHtml(line),
        this.errorLine
      );
      this.codeAreaEl.innerHTML = linesHtml;
    } else {
      this.renderGutter(lines.length);

      let html = '';
      lines.forEach((line, idx) => {
        const lineNum = idx + 1;
        let renderedLine = this.renderLineHtml(line);
        const indentClass = line.startsWith('        ') ? ' ind-2' : (line.startsWith('    ') ? ' ind-1' : '');
        const errClass = (this.errorLine === lineNum) ? ' has-error' : ((this.warningLine === lineNum) ? ' has-warning' : '');
        const pauseClass = (this.debugPausedLine === lineNum) ? ' has-debug-pause' : '';

        const lineDiags = (this.activeDiagnostics || []).filter(d => d.startLine === lineNum);
        if (lineDiags.length > 0) {
          renderedLine = this.applyExactSquigglesToLine(renderedLine, lineNum, line, lineDiags);
        }

        html += `<div class="code-line${indentClass}${errClass}${pauseClass}" data-line="${lineNum}">${renderedLine || '&nbsp;'}</div>`;
      });

      this.codeAreaEl.innerHTML = html;
    }

    this.renderCursorOverlays();
    this.updateEditorChrome();

    // Attach inline editor handlers
    this.setupInlineEditor();

    if (editorState) {
      const textarea = document.getElementById('hiddenEditorInput');
      if (textarea) {
        const limit = this.currentCode.length;
        const start = Math.min(editorState.start, limit);
        const end = Math.min(editorState.end, limit);
        const caretMoves = this.caretMoves || 0;
        requestAnimationFrame(() => {
          // A deliberate move since the redraw (goToLine: definitions,
          // problems, style provenance) wins over the stale saved position.
          if ((this.caretMoves || 0) !== caretMoves) return;
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

  // Shared word-wrap-aware pixel<->offset conversion for the hidden editor textarea.
  // A single logical line can render as multiple visual rows when word-wrap is on, so
  // callers must not assume `\n`-split index === visual row. This mirrors the textarea's
  // box/typography into an off-screen element and reads real layout, matching whatever
  // wrapping the browser actually performed.
  _getEditorPositionMirror(textarea) {
    let div = this._editorPositionMirrorEl;
    if (!div) {
      div = document.createElement('div');
      div.style.position = 'absolute';
      div.style.visibility = 'hidden';
      div.style.top = '-9999px';
      div.style.left = '-9999px';
      div.style.pointerEvents = 'none';
      document.body.appendChild(div);
      this._editorPositionMirrorEl = div;
    }
    const style = window.getComputedStyle(textarea);
    const mirrorProps = [
      'boxSizing', 'width', 'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
      'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth', 'borderStyle',
      'fontStyle', 'fontVariant', 'fontWeight', 'fontSize', 'lineHeight', 'fontFamily',
      'letterSpacing', 'wordSpacing', 'whiteSpace', 'wordBreak', 'overflowWrap', 'tabSize'
    ];
    mirrorProps.forEach((prop) => { div.style[prop] = style[prop]; });
    return div;
  }

  _getEditorCharWidth(textarea) {
    if (!this._editorCharWidthCache) this._editorCharWidthCache = new Map();
    const style = window.getComputedStyle(textarea);
    const key = `${style.fontSize}|${style.fontFamily}|${style.letterSpacing}`;
    if (this._editorCharWidthCache.has(key)) return this._editorCharWidthCache.get(key);
    if (!this._editorMeasureCanvas) this._editorMeasureCanvas = document.createElement('canvas');
    const ctx = this._editorMeasureCanvas.getContext('2d');
    ctx.font = `${style.fontStyle} ${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
    const width = ctx.measureText('MMMMMMMMMM').width / 10 || 7.8;
    this._editorCharWidthCache.set(key, width);
    return width;
  }

  // offset -> {left, top} in textarea-local pixels, valid whether or not the line wraps.
  _offsetToEditorCoords(textarea, offset) {
    const div = this._getEditorPositionMirror(textarea);
    const value = textarea.value;
    const clamped = Math.max(0, Math.min(offset, value.length));
    div.textContent = value.slice(0, clamped);
    const marker = document.createElement('span');
    marker.textContent = value.slice(clamped, clamped + 1) || '.';
    div.appendChild(marker);
    const coords = { left: marker.offsetLeft, top: marker.offsetTop };
    div.removeChild(marker);
    return coords;
  }

  // {x, y} textarea-local pixels -> nearest string offset, wrap-aware.
  _editorCoordsToOffset(textarea, targetX, targetY) {
    const value = textarea.value;
    const len = value.length;
    if (len === 0) return 0;
    if (!this.wordWrap) {
      // Fast path: no visual wrapping, so `\n`-split index is exactly the visual row.
      const computedStyle = window.getComputedStyle(textarea);
      const lineHeight = parseFloat(computedStyle.lineHeight) || DEFAULT_LINE_HEIGHT;
      const padTop = parseFloat(computedStyle.paddingTop) || 16;
      const padLeft = parseFloat(computedStyle.paddingLeft) || 20;
      const charWidth = this._getEditorCharWidth(textarea);
      const lines = value.split('\n');
      const lineIdx = Math.floor((targetY - padTop) / lineHeight);
      if (lineIdx < 0 || lineIdx >= lines.length) return -1;
      const colIdx = Math.max(0, Math.floor((targetX - padLeft) / charWidth));
      let lineStart = 0;
      for (let i = 0; i < lineIdx; i++) lineStart += lines[i].length + 1;
      return Math.min(lineStart + lines[lineIdx].length, lineStart + colIdx);
    }
    // Word-wrap path: binary search for the visual row (top is monotonic in offset),
    // then linear-scan within that single row for the closest column.
    let lo = 0, hi = len;
    while (lo < hi) {
      const mid = Math.ceil((lo + hi) / 2);
      if (this._offsetToEditorCoords(textarea, mid).top <= targetY) lo = mid; else hi = mid - 1;
    }
    const rowTop = this._offsetToEditorCoords(textarea, lo).top;
    let best = lo;
    let bestDist = Math.abs(this._offsetToEditorCoords(textarea, lo).left - targetX);
    for (let o = lo + 1; o <= len; o++) {
      const c = this._offsetToEditorCoords(textarea, o);
      if (c.top !== rowTop) break;
      const dist = Math.abs(c.left - targetX);
      if (dist <= bestDist) { bestDist = dist; best = o; }
    }
    for (let o = lo - 1; o >= 0; o--) {
      const c = this._offsetToEditorCoords(textarea, o);
      if (c.top !== rowTop) break;
      const dist = Math.abs(c.left - targetX);
      if (dist <= bestDist) { bestDist = dist; best = o; }
    }
    return best;
  }

  renderCursorOverlays() {
    if (!this.codeAreaEl) return;
    let layer = document.getElementById('multiCursorLayer');
    if (!layer) {
      layer = document.createElement('div');
      layer.id = 'multiCursorLayer';
      layer.className = 'multi-cursor-layer';
      this.codeAreaEl.appendChild(layer);
    }
    layer.innerHTML = '';

    if (!this.multiCursor || !this.multiCursor.hasMultipleCursors()) {
      return;
    }

    const textarea = document.getElementById('hiddenEditorInput');
    const lineHeight = DEFAULT_LINE_HEIGHT;
    const charWidth = textarea ? this._getEditorCharWidth(textarea) : 7.8;
    const paddingTop = 16;
    const paddingLeft = 20;

    for (const cursor of this.multiCursor.secondaries) {
      let top, left;
      if (this.wordWrap && textarea) {
        const coords = this._offsetToEditorCoords(textarea, cursor.start);
        top = coords.top;
        left = coords.left;
      } else {
        const { line, column } = this.multiCursor.getLineAndCol(this.currentCode, cursor.start);
        top = (line - 1) * lineHeight + paddingTop;
        left = column * charWidth + paddingLeft;
      }

      const caretEl = document.createElement('div');
      caretEl.className = 'secondary-cursor-caret';
      caretEl.style.top = `${top}px`;
      caretEl.style.left = `${left}px`;
      layer.appendChild(caretEl);

      if (cursor.start !== cursor.end) {
        let width;
        if (this.wordWrap && textarea) {
          const endCoords = this._offsetToEditorCoords(textarea, cursor.end);
          width = Math.max(2, endCoords.top === top ? endCoords.left - left : charWidth);
        } else {
          const { column } = this.multiCursor.getLineAndCol(this.currentCode, cursor.start);
          const { column: endCol } = this.multiCursor.getLineAndCol(this.currentCode, cursor.end);
          width = Math.max(2, (endCol - column) * charWidth);
        }
        const selEl = document.createElement('div');
        selEl.className = 'secondary-cursor-selection';
        selEl.style.top = `${top}px`;
        selEl.style.left = `${left}px`;
        selEl.style.width = `${width}px`;
        selEl.style.height = `${lineHeight}px`;
        layer.appendChild(selEl);
      }
    }
  }

  handleVirtualizedScroll(textarea) {
    if (!this.isLargeFileMode || !textarea) return;
    const lines = this.currentCode.split('\n');
    const viewportHeight = textarea.clientHeight || 600;
    const range = computeVisibleRange(textarea.scrollTop, viewportHeight, lines.length, DEFAULT_LINE_HEIGHT, 40);

    if (this.currentVirtualRange &&
        Math.abs(range.startIndex - this.currentVirtualRange.startIndex) < 10 &&
        Math.abs(range.endIndex - this.currentVirtualRange.endIndex) < 10) {
      return;
    }

    this.currentVirtualRange = range;
    if (this.gutterEl) {
      this.gutterEl.innerHTML = renderVirtualizedGutter(range.startIndex, range.endIndex, range.topSpacerHeight, range.bottomSpacerHeight, this.errorLine, this.warningLine);
    }
    if (this.codeAreaEl) {
      const linesHtml = renderVirtualizedLines(
        lines,
        range.startIndex,
        range.endIndex,
        range.topSpacerHeight,
        range.bottomSpacerHeight,
        (line) => this.syntaxHighlightLine(line),
        this.errorLine
      );
      this.codeAreaEl.innerHTML = linesHtml;
      this.renderCursorOverlays();
    }
  }

  setWordWrap(enabled) {
    this.wordWrap = Boolean(enabled);
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem('otter-studio-word-wrap', String(this.wordWrap));
    }
    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea) {
      textarea.style.whiteSpace = this.wordWrap ? 'pre-wrap' : 'pre';
      textarea.style.wordBreak = this.wordWrap ? 'break-all' : 'normal';
      textarea.style.overflowWrap = this.wordWrap ? 'anywhere' : 'normal';
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
      const classes = [];
      if (this.errorLine === i) classes.push('gutter-err');
      else if (this.warningLine === i) classes.push('gutter-warn');
      if (this.debugBreakpoints && this.debugBreakpoints.has(i)) classes.push('gutter-breakpoint');
      if (this.debugPausedLine === i) classes.push('gutter-debug-pause');
      const classAttr = classes.length ? ` class="${classes.join(' ')}"` : '';
      spans += `<span${classAttr} data-line="${i}">${i}</span>`;
    }
    this.gutterEl.innerHTML = spans;
  }

  // Debugger (first slice): click a gutter line number to arm/disarm a
  // breakpoint on that exact Otter source line. Otter Studio never decides
  // WHERE execution pauses - it only tells the real interpreter which lines
  // to stop on (src/Otter.Debugger.psm1 does the actual pausing).
  toggleBreakpoint(lineNumber) {
    if (!this.debugBreakpoints) this.debugBreakpoints = new Set();
    if (this.debugBreakpoints.has(lineNumber)) {
      this.debugBreakpoints.delete(lineNumber);
    } else {
      this.debugBreakpoints.add(lineNumber);
    }
    this.renderGutter((this.currentCode || '').split('\n').length);
  }

  syntaxHighlightCssLine(line) {
    return highlightCssLine(line);
  }

  syntaxHighlightJsonLine(line) {
    return highlightJsonLine(line);
  }

  // One line of the highlighted layer: syntax colours plus indent guides
  // when the setting is on (the text content is identical either way).
  renderLineHtml(line) {
    if (this.setting('editor.indentGuides', true) && this.isOtterFile()) {
      return renderIndentGuides(line, (rest) => this.syntaxHighlightLine(rest));
    }
    return this.syntaxHighlightLine(line);
  }

  syntaxHighlightLine(line) {
    if (this.currentFile?.endsWith('.css')) {
      return this.syntaxHighlightCssLine(line);
    }
    if (this.currentFile?.endsWith('.json')) {
      return this.syntaxHighlightJsonLine(line);
    }
    return highlightOtterLine(line, this.workspaceSymbols, this.currentFile);
  }

  setupInlineEditor() {
    let textarea = document.getElementById('hiddenEditorInput');
    const container = document.getElementById('codeEditorContainer') || this.codeAreaEl?.parentElement;
    if (!textarea && container) {
      textarea = document.createElement('textarea');
      textarea.id = 'hiddenEditorInput';
      textarea.className = 'code-editor-input';
      textarea.spellcheck = false;
      container.appendChild(textarea);
    }
    if (!textarea) return;

    // Strict typography and geometry synchronization with syntax highlight layer
    textarea.style.position = 'absolute';
    textarea.style.top = '0';
    textarea.style.left = '0';
    textarea.style.width = '100%';
    textarea.style.height = '100%';
    textarea.style.boxSizing = 'border-box';
    textarea.style.padding = '16px 20px';
    textarea.style.margin = '0';
    textarea.style.border = '0';
    textarea.style.outline = 'none';
    textarea.style.resize = 'none';
    textarea.style.fontFamily = 'var(--font-code, "JetBrains Mono", Consolas, monospace)';
    textarea.style.fontSize = 'var(--editor-font-size, 13px)'; // Settings > Editor > Font size
    textarea.style.lineHeight = '22px';
    textarea.style.letterSpacing = '0px';
    textarea.style.tabSize = '4';
    textarea.style.fontVariantLigatures = 'none';
    textarea.style.whiteSpace = this.wordWrap ? 'pre-wrap' : 'pre';
    textarea.style.wordBreak = this.wordWrap ? 'break-all' : 'normal';
    textarea.style.overflowWrap = this.wordWrap ? 'anywhere' : 'normal';
    textarea.style.overflow = 'auto';
    textarea.style.opacity = '1';
    textarea.style.color = 'transparent';
    textarea.style.caretColor = '#2563eb';
    textarea.style.background = 'transparent';
    textarea.style.zIndex = '5';
    textarea.spellcheck = false;

    if (container) {
      container.style.position = 'relative';
    }

    if (!textarea.dataset.editorBound) {
      textarea.dataset.editorBound = 'true';

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
        if (this.isLargeFileMode) {
          this.handleVirtualizedScroll(textarea);
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
        } else if (e.altKey) {
          const clickPos = textarea.selectionStart;
          this.multiCursor.addCursor(clickPos, clickPos);
          this.renderCursorOverlays();
          this.updateCursorPos(textarea);
        } else {
          this.multiCursor.setPrimaryCursor(textarea.selectionStart, textarea.selectionEnd);
          this.multiCursor.clearSecondaryCursors();
          this.renderCursorOverlays();
          this.updateCursorPos(textarea);
        }
      });

      textarea.addEventListener('input', () => {
        this.hideHoverTooltip();
        this.checkSignatureHelp();
        this.currentCode = textarea.value;
        this.multiCursor.setPrimaryCursor(textarea.selectionStart, textarea.selectionEnd);
        this.renderCursorOverlays();
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
          if (this.multiCursor && this.multiCursor.hasMultipleCursors()) {
            this.multiCursor.clearSecondaryCursors();
            this.renderCursorOverlays();
            this.updateCursorPos(textarea);
            return;
          }
        }
        // Multi-cursor next occurrence (Ctrl+D)
        if (e.ctrlKey && !e.shiftKey && (e.key === 'd' || e.key === 'D')) {
          e.preventDefault();
          this.multiCursor.setPrimaryCursor(textarea.selectionStart, textarea.selectionEnd);
          const added = this.multiCursor.selectNextOccurrence(this.currentCode);
          if (added) {
            this.renderCursorOverlays();
            this.updateCursorPos(textarea);
          }
          return;
        }
        // Multi-cursor column carets (Ctrl+Alt+Up / Down)
        if (e.ctrlKey && e.altKey && (e.key === 'ArrowUp' || e.key === 'ArrowDown')) {
          e.preventDefault();
          this.multiCursor.setPrimaryCursor(textarea.selectionStart, textarea.selectionEnd);
          const dir = e.key === 'ArrowUp' ? -1 : 1;
          const added = this.multiCursor.addColumnCursor(this.currentCode, dir);
          if (added) {
            this.renderCursorOverlays();
            this.updateCursorPos(textarea);
          }
          return;
        }

        // Multi-cursor simultaneous typing / deleting
        if (this.multiCursor && this.multiCursor.hasMultipleCursors()) {
          if (e.key === 'Backspace') {
            e.preventDefault();
            const res = this.multiCursor.applyEdit(this.currentCode, '', true, false);
            if (res) {
              this.currentCode = res.code;
              textarea.value = res.code;
              textarea.selectionStart = this.multiCursor.primary.start;
              textarea.selectionEnd = this.multiCursor.primary.end;
              this.markCurrentTabDirty(true);
              this.renderEditorCode(this.currentCode);
              this.updateCursorPos(textarea);
              this.saveSessionState();
              this.debouncedLint();
              this.emitSourceChanged();
            }
            return;
          }
          if (e.key === 'Delete') {
            e.preventDefault();
            const res = this.multiCursor.applyEdit(this.currentCode, '', false, true);
            if (res) {
              this.currentCode = res.code;
              textarea.value = res.code;
              textarea.selectionStart = this.multiCursor.primary.start;
              textarea.selectionEnd = this.multiCursor.primary.end;
              this.markCurrentTabDirty(true);
              this.renderEditorCode(this.currentCode);
              this.updateCursorPos(textarea);
              this.saveSessionState();
              this.debouncedLint();
              this.emitSourceChanged();
            }
            return;
          }
          if (e.key === 'Enter') {
            e.preventDefault();
            const res = this.multiCursor.applyEdit(this.currentCode, '\n', false, false);
            if (res) {
              this.currentCode = res.code;
              textarea.value = res.code;
              textarea.selectionStart = this.multiCursor.primary.start;
              textarea.selectionEnd = this.multiCursor.primary.end;
              this.markCurrentTabDirty(true);
              this.renderEditorCode(this.currentCode);
              this.updateCursorPos(textarea);
              this.saveSessionState();
              this.debouncedLint();
              this.emitSourceChanged();
            }
            return;
          }
          if (e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) {
            e.preventDefault();
            const res = this.multiCursor.applyEdit(this.currentCode, e.key, false, false);
            if (res) {
              this.currentCode = res.code;
              textarea.value = res.code;
              textarea.selectionStart = this.multiCursor.primary.start;
              textarea.selectionEnd = this.multiCursor.primary.end;
              this.markCurrentTabDirty(true);
              this.renderEditorCode(this.currentCode);
              this.updateCursorPos(textarea);
              this.saveSessionState();
              this.debouncedLint();
              this.emitSourceChanged();
            }
            return;
          }
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
        if (e.altKey && e.key === 'Enter') {
          if (this.availableQuickFixes && this.availableQuickFixes.length > 0) {
            e.preventDefault();
            this.applyCurrentQuickFix();
            return;
          }
        }
        if (e.ctrlKey && e.shiftKey && (e.key === 'r' || e.key === 'R')) {
          e.preventDefault();
          this.extractFunction();
          return;
        }
        if (e.ctrlKey && !e.shiftKey && (e.key === 't' || e.key === 'T')) {
          e.preventDefault();
          this.openNavigationPalette('workspace-symbols');
          return;
        }
        if (e.ctrlKey && e.key === 's') {
          e.preventDefault();
          this.saveCurrentFile();
          return;
        }

        // Smart Enter: keep the indentation, open a block's body and, when the
        // block is new, write its closing period (editor.autoCloseBlocks).
        if (e.key === 'Enter') {
          e.preventDefault();
          const edit = enterKey(textarea.value, textarea.selectionStart, textarea.selectionEnd, {
            autoCloseBlocks: this.isOtterFile() && this.setting('editor.autoCloseBlocks', true)
          });
          this.applyAssistedEdit(textarea, edit);
          return;
        }

        // Auto-closing quotes and brackets (editor.autoClosePairs).
        if (this.setting('editor.autoClosePairs', true) && !e.ctrlKey && !e.metaKey && !e.altKey) {
          if (e.key === 'Backspace') {
            const edit = backspacePair(textarea.value, textarea.selectionStart, textarea.selectionEnd);
            if (edit) { e.preventDefault(); this.applyAssistedEdit(textarea, edit); return; }
          } else if (e.key.length === 1) {
            const edit = autoClosePair(textarea.value, textarea.selectionStart, textarea.selectionEnd, e.key);
            if (edit) { e.preventDefault(); this.applyAssistedEdit(textarea, edit); return; }
          }
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
        if (this.multiCursor) {
          this.multiCursor.setPrimaryCursor(textarea.selectionStart, textarea.selectionEnd);
          this.renderCursorOverlays();
        }
      });
    }

    if (this.gutterEl && !this.gutterEl.dataset.wheelBound) {
      this.gutterEl.dataset.wheelBound = 'true';
      this.gutterEl.addEventListener('wheel', (e) => {
        if (textarea) {
          textarea.scrollTop += e.deltaY;
          textarea.scrollLeft += e.deltaX;
          e.preventDefault();
        }
      }, { passive: false });
    }

    if (this.gutterEl && !this.gutterEl.dataset.breakpointBound) {
      this.gutterEl.dataset.breakpointBound = 'true';
      this.gutterEl.addEventListener('click', (e) => {
        const target = e.target.closest('[data-line]');
        if (!target) return;
        const lineNumber = parseInt(target.dataset.line, 10);
        if (Number.isFinite(lineNumber)) this.toggleBreakpoint(lineNumber);
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
      if (this.multiCursor && this.multiCursor.hasMultipleCursors()) {
        this.statusBarPos.innerText = `Ln ${lineNum}, Col ${colNum} (${this.multiCursor.cursors.length} cursors)`;
      } else {
        this.statusBarPos.innerText = `Ln ${lineNum}, Col ${colNum}`;
      }
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
  //
  // What Run does is chosen in the Run ▾ menu:
  //   current            otter run <current file>
  //   project            otter run <project folder>   (uses otter.json)
  //   terminal           types the run command into the integrated terminal
  //   custom:<name>      a profile from <project>/.otter-studio/launch.json
  // The choice is remembered per project; a project's "startup" profile is
  // the default. The server (server/launch.mjs) turns a profile into the
  // exact otter.ps1 invocation.

  builtInProfile(id) {
    if (id === 'project') return { name: 'Run Project', kind: 'project', args: [], cwd: '.', env: {}, timeoutSeconds: 30 };
    return { name: 'Run Current File', kind: 'file', program: '${currentFile}', args: [], cwd: '${fileDir}', env: {}, timeoutSeconds: 30 };
  }

  resolveLaunchProfile(id = this.launchProfile) {
    if (id && id.startsWith('custom:')) {
      const name = id.slice('custom:'.length);
      const found = this.launchConfig?.profiles?.find(p => p.name === name);
      if (found) return found;
    }
    return this.builtInProfile(id === 'project' ? 'project' : 'current');
  }

  launchProfileLabel(id = this.launchProfile) {
    if (id === 'project') return 'Run Project';
    if (id === 'terminal') return 'Run (Term)';
    if (id && id.startsWith('custom:')) return `Run: ${id.slice('custom:'.length)}`;
    return 'Run';
  }

  updateRunButtonLabel() {
    if (this.runBtnLabel) this.runBtnLabel.innerText = this.launchProfileLabel();
  }

  async runActiveProfile() {
    if (this.launchProfile === 'terminal') {
      await this.runInTerminal();
    } else {
      await this.runCurrentProgram(this.resolveLaunchProfile());
    }
  }

  async runProject() {
    await this.runCurrentProgram(this.builtInProfile('project'));
  }

  // Stop whatever is running, then run the same profile again.
  async restartProgram() {
    try { await fetch('/api/stop', { method: 'POST' }); } catch {}
    await this.runActiveProfile();
  }

  // Read <project>/.otter-studio/launch.json (or the defaults) and rebuild
  // the Run menu from it.
  async loadLaunchConfig() {
    this.launchConfig = null;
    this.launchConfigRevision = null;
    this.launchConfigErrors = [];
    const folder = this.projectStylesheetPath() ? this.currentProjectFolder : null;
    if (folder) {
      try {
        const res = await fetch(`/api/launch-config?folder=${encodeURIComponent(folder)}`);
        const data = await res.json();
        if (res.ok) {
          this.launchConfig = data.config;
          this.launchConfigRevision = data.revision;
          this.launchConfigErrors = data.errors || [];
        }
      } catch (err) {
        console.warn('Could not read launch profiles:', err);
      }
    }
    // Per-project remembered choice, else the project's startup profile.
    let remembered = null;
    try { remembered = localStorage.getItem(`otter-studio-launch-profile:${folder || ''}`); } catch {}
    const exists = id => !id?.startsWith('custom:') || this.launchConfig?.profiles?.some(p => `custom:${p.name}` === id);
    if (remembered && exists(remembered)) {
      this.launchProfile = remembered;
    } else if (this.launchConfig?.startup) {
      const startup = this.launchConfig.startup;
      this.launchProfile = startup === 'Run Project' ? 'project' : (startup === 'Run Current File' ? 'current' : `custom:${startup}`);
      if (!exists(this.launchProfile)) this.launchProfile = 'current';
    }
    this.renderLaunchMenu();
    this.updateRunButtonLabel();
  }

  renderLaunchMenu() {
    if (!this.launchProfileMenu) return;
    const esc = v => this.escapeHtml(String(v));
    const item = (id, icon, title, shortcut = '') => `
      <button type="button" class="launch-profile-item${this.launchProfile === id ? ' is-active' : ''}" data-profile="${esc(id)}" role="menuitemradio" aria-checked="${this.launchProfile === id}">
        <span class="profile-icon">${icon}</span><span class="profile-title">${esc(title)}</span><span class="profile-shortcut">${shortcut}</span>
      </button>`;
    const action = (id, icon, title, shortcut = '') => `
      <button type="button" class="launch-profile-item" data-launch-action="${id}" role="menuitem">
        <span class="profile-icon">${icon}</span><span class="profile-title">${title}</span><span class="profile-shortcut">${shortcut}</span>
      </button>`;
    // Built-in profiles are the defaults; a launch.json profile with the same
    // name is shown only once (as the built-in).
    const custom = (this.launchConfig?.profiles || []).filter(p => p.name !== 'Run Project' && p.name !== 'Run Current File');
    this.launchProfileMenu.setAttribute('role', 'menu');
    this.launchProfileMenu.innerHTML = `
      <div class="launch-profile-header">Launch Profiles</div>
      ${item('current', '▶', 'Run Current File', 'F5')}
      ${item('project', '🚀', 'Run Project', 'Ctrl+F5')}
      ${item('terminal', '💻', 'Run in Terminal', 'Alt+F5')}
      ${custom.map(p => item(`custom:${p.name}`, '⚙', p.name)).join('')}
      ${this.launchConfigErrors?.length ? `<div class="launch-profile-header" style="color: #ef4444;">launch.json: ${esc(this.launchConfigErrors[0])}</div>` : ''}
      <div class="launch-profile-header">Actions</div>
      ${action('restart', '↻', 'Restart', 'Ctrl+Shift+F5')}
      ${action('edit', '✎', 'Edit Launch Profiles…')}
      ${action('build', '🔨', 'Build Project', 'Ctrl+Shift+B')}
      ${action('rebuild', '♻', 'Rebuild Project')}
      ${action('clean', '🧹', 'Clean Build Output')}`;
  }

  runLaunchAction(action) {
    this.closeLaunchProfileMenu();
    if (action === 'edit') openLaunchProfilesEditor(this);
    else if (action === 'restart') this.restartProgram();
    else if (action === 'build') this.buildProject();
    else if (action === 'rebuild') this.buildProject({ clean: true });
    else if (action === 'clean') this.cleanProject();
  }

  // Save every edited tab (each with its own disk revision). Returns false
  // if any save failed or hit a conflict, so Run/Build can stop.
  async saveAllFiles() {
    let ok = true;
    for (const tab of this.openTabs.filter(t => t.isDirty && t.path !== 'untitled.ot')) {
      if (tab.path === this.currentFile) {
        ok = (await this.saveCurrentFile()) && ok;
        continue;
      }
      try {
        const res = await fetch('/api/file', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ path: tab.path, content: tab.content, expectedRevision: tab.diskRevision || undefined })
        });
        const data = await res.json();
        if (res.status === 409 && data.conflict) { this.setExternalConflict(tab, data); ok = false; continue; }
        if (!res.ok) { ok = false; continue; }
        tab.diskRevision = data.revision || null;
        tab.isDirty = false;
      } catch {
        ok = false;
      }
    }
    if (!this.currentFile || !this.openTabs.some(t => t.path === this.currentFile && t.isDirty)) {
      ok = (await this.saveDesignerStylesheet()) && ok;
    }
    this.renderTabs();
    this.saveSessionState();
    return ok;
  }

  showOutputDrawer() {
    const tab = Array.from(this.drawerTabs || []).find(t => t.getAttribute('data-drawer-tab') === 'output');
    tab?.click();
  }

  appendBuildLog(title, text, ok) {
    const outputTabLog = document.getElementById('outputTabLog');
    if (!outputTabLog) return;
    const timestamp = new Date().toLocaleTimeString();
    outputTabLog.innerHTML += `
      <div class="log-run-entry">
        <div class="log-run-meta" style="color: ${ok ? 'inherit' : '#ef4444'};">[${timestamp}] ${this.escapeHtml(title)}</div>
        <pre class="log-run-text">${this.escapeHtml(text || '')}</pre>
      </div>`;
    outputTabLog.scrollTop = outputTabLog.scrollHeight;
  }

  // otter build <project>. `clean: true` first deletes the previous output
  // (only a folder otter build created). Output goes to the Output tab;
  // a failure is also shown in Problems.
  async buildProject({ clean = false } = {}) {
    const folder = this.projectStylesheetPath() ? this.currentProjectFolder : null;
    if (!folder) { alert('Open a project folder to build it.'); return null; }
    if (!(await this.saveAllFiles())) {
      this.appendBuildLog('Build cancelled: some files could not be saved.', '', false);
      return null;
    }
    this.showOutputDrawer();
    this.appendBuildLog(`${clean ? 'Rebuilding' : 'Building'} ${folder}…`, '', true);
    let data;
    try {
      const res = await fetch('/api/build', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder, clean })
      });
      data = await res.json();
      if (!res.ok && !('exitCode' in data)) throw new Error(data.error || `status ${res.status}`);
    } catch (err) {
      this.appendBuildLog(`Build could not start: ${err.message}`, '', false);
      return null;
    }
    const cleanNote = data.cleaned ? (data.cleaned.removed ? `Cleaned ${data.cleaned.outputDir}/.\n` : `${data.cleaned.reason}\n`) : '';
    const artifacts = (data.artifacts || []).map(a => `  ${data.outputDir}/${a.path}  (${a.size} bytes)`).join('\n');
    this.appendBuildLog(
      data.ok ? `Build succeeded in ${data.durationMs} ms` : `Build failed (exit code ${data.exitCode}) after ${data.durationMs} ms`,
      `${cleanNote}${data.output || ''}${artifacts ? `\nArtifacts:\n${artifacts}` : ''}`,
      data.ok
    );
    if (data.ok) {
      this.setProblemsStatus(true, 'Build succeeded.', `Output: ${data.outputDir}/`, 'Build', 'Ready to publish. 📦');
    } else {
      const firstError = (data.output || '').split('\n').map(l => l.trim()).filter(l => l && !/^(Building|Target:|Checking project|Build failed\.)/.test(l))[0] || 'Build failed.';
      this.setProblemsStatus(false, firstError, `Build of ${folder} failed with exit code ${data.exitCode}. See the Output tab.`, 'Build Error', 'Check the build output! 🔍');
    }
    await this.loadProjectTree(this.currentProjectFolder);
    return data;
  }

  async cleanProject() {
    const folder = this.projectStylesheetPath() ? this.currentProjectFolder : null;
    if (!folder) { alert('Open a project folder first.'); return null; }
    const res = await fetch('/api/clean', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ folder })
    });
    const data = await res.json().catch(() => ({}));
    this.showOutputDrawer();
    this.appendBuildLog(data.removed ? `Cleaned ${data.outputDir}/` : 'Nothing cleaned', data.reason || data.error || '', res.ok);
    await this.loadProjectTree(this.currentProjectFolder);
    return data;
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
    if (this.debugSessionId) {
      try {
        await fetch('/api/debug/stop', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sessionId: this.debugSessionId })
        });
        this.appendProgramOutputLine('Debug session stopped by user.');
      } catch {}
      this.endDebugSession();
      return;
    }
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
      this.updateRunButtonLabel();
    }
  }

  setLaunchProfile(profile) {
    this.launchProfile = profile;
    try {
      localStorage.setItem('otter-studio-launch-profile', profile);
      localStorage.setItem(`otter-studio-launch-profile:${this.currentProjectFolder || ''}`, profile);
    } catch {}
    this.renderLaunchMenu();
    this.updateRunButtonLabel();
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

  async runCurrentProgram(profile = this.builtInProfile('current')) {
    if (!this.mainRunBtn) return;

    if (!this.isTrusted) {
      const proceed = confirm('Restricted Mode: This workspace is untrusted. Running code in an untrusted workspace may be unsafe.\n\nDo you want to trust this workspace and run the program?');
      if (!proceed) return;
      this.grantWorkspaceTrust();
    }

    this.mainRunBtn.classList.add('is-running');
    if (this.runBtnLabel) this.runBtnLabel.innerText = 'Running...';
    if (this.btnStopProgram) this.btnStopProgram.style.display = 'inline-flex';
    this.mainRunBtn.style.display = 'none';

    // Save first. A disk conflict must be resolved before execution so the
    // runner never receives a version the user has not chosen explicitly.
    // A project run may use any file, so every edited tab is saved.
    const saved = profile.kind === 'project' ? await this.saveAllFiles() : await this.saveCurrentFile();
    if (!saved) {
      if (this.btnStopProgram) this.btnStopProgram.style.display = 'none';
      this.mainRunBtn.style.display = 'inline-flex';
      this.mainRunBtn.classList.remove('is-running');
      this.updateRunButtonLabel();
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
        // The file was saved above; the server runs what is on disk.
        body: JSON.stringify({
          path: this.currentFile,
          folder: this.projectStylesheetPath() ? this.currentProjectFolder : undefined,
          profile
        })
      });
      const data = await res.json();
      if (!res.ok && !('exitCode' in data)) {
        throw new Error(data.error || `The run could not start (${res.status}).`);
      }
      if (data.timedOut) data.stderr = `${data.stderr || ''}\nStopped: the program ran longer than ${profile.timeoutSeconds || 30} seconds (the profile's timeout).`.trim();

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
            <div class="log-run-meta">[${timestamp}] ${this.escapeHtml(data.command || '')} — finished in ${data.durationMs}ms with exit code ${data.exitCode}${data.stopped ? ' (stopped)' : ''}</div>
            <pre class="log-run-text">${this.escapeHtml(data.stdout || data.stderr || 'No output')}</pre>
          </div>
        `;
        outputTabLog.scrollTop = outputTabLog.scrollHeight;
      }

      // Update Variables Inspector
      this.updateVariablesInspector(data.exitCode === 0);

      // Update Problems / Mascot banner
      if (data.exitCode === 0) {
        this.activeDiagnostics = [];
        this.diagnosticCollection.clear(this.currentFile);
        this.currentDiagnostic = null;
        this.errorLine = null;
        this.warningLine = null;
        this.setProblemsStatus(true, 'No problems found.', 'Your code looks good!', 'Great job!', 'Keep going! 🐾');
        this.updateErrorSquiggles();
      } else {
        const rawErr = data.stderr || data.error || 'Execution failed.';
        const translated = translateHostError(rawErr, { file: this.currentFile, line: 1 });
        const diag = normalizeDiagnostic({
          ...(translated || {}),
          stage: 'runtime',
          hostDetails: translated?.hostDetails || rawErr
        }, this.currentCode, this.currentFile);

        this.activeDiagnostics = [diag];
        this.diagnosticCollection.set(this.currentFile, [diag]);
        this.currentDiagnostic = diag;
        this.errorLine = diag.startLine;
        this.availableQuickFixes = diag.fixes;
        this.setProblemsStatus(
          false,
          `${diag.code}  ${diag.message}`,
          `Line ${diag.startLine}, Col ${diag.startColumn} (${this.currentFile}) — Runtime Execution`,
          'Execution Error',
          'Check the error message! 🔍',
          false,
          diag
        );
        this.updateErrorSquiggles();
      }

    } catch (err) {
      if (this.programOutputBody) {
        this.programOutputBody.innerHTML = `<div class="log-line log-error">${this.escapeHtml(err.message)}</div>`;
      }
    } finally {
      if (this.btnStopProgram) this.btnStopProgram.style.display = 'none';
      this.mainRunBtn.style.display = 'inline-flex';
      this.mainRunBtn.classList.remove('is-running');
      this.updateRunButtonLabel();
    }
  }

  // --- Debugger (first slice) ---
  //
  // breakpoint -> pause -> exact source location -> locals -> continue,
  // through the real production otter.ps1 debug subcommand
  // (src/Otter.Debugger.psm1), never a second interpreter inside Studio.
  // Studio's backend (serve.mjs /api/debug/*) spawns that real process and
  // relays its line-oriented protocol; this is the client side of that
  // relay: start a session, poll it, show what it reports, let the user
  // continue.

  async startDebugSession() {
    if (!this.btnDebugProgram) return;
    if (this.debugSessionId) return; // a session is already running

    if (!this.isTrusted) {
      const proceed = confirm('Restricted Mode: This workspace is untrusted. Running code in an untrusted workspace may be unsafe.\n\nDo you want to trust this workspace and debug the program?');
      if (!proceed) return;
      this.grantWorkspaceTrust();
    }

    const saved = await this.saveCurrentFile();
    if (!saved) return;

    this.clearDebugPauseState();
    this.btnDebugProgram.style.display = 'none';
    if (this.mainRunBtn) this.mainRunBtn.style.display = 'none';
    if (this.btnStopProgram) this.btnStopProgram.style.display = 'inline-flex';
    if (this.programOutputBody) {
      this.programOutputBody.innerHTML = '<div class="log-line">Starting Otter debug session...</div>';
    }
    if (this.variablesBody) {
      this.variablesBody.innerHTML = '<div class="empty-state-text" style="padding: 16px 12px; font-size: 12px; color: var(--text-faint); text-align: center;">Waiting for a breakpoint...</div>';
    }

    try {
      const res = await fetch('/api/debug/start', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          path: this.currentFile,
          content: this.currentCode,
          breakpoints: Array.from(this.debugBreakpoints)
        })
      });
      const data = await res.json();
      if (!data.sessionId) throw new Error(data.error || 'Otter debug session could not be started.');

      this.debugSessionId = data.sessionId;
      this.debugPollTimer = setInterval(() => this.pollDebugSession(), 250);
    } catch (err) {
      if (this.programOutputBody) {
        this.programOutputBody.innerHTML = `<div class="log-line log-error">${this.escapeHtml(err.message)}</div>`;
      }
      this.endDebugSession();
    }
  }

  async pollDebugSession() {
    if (!this.debugSessionId) return;
    let data;
    try {
      const res = await fetch(`/api/debug/poll?sessionId=${encodeURIComponent(this.debugSessionId)}`);
      data = await res.json();
    } catch {
      return; // a transient poll failure is not the same as the session ending
    }

    for (const line of (data.output || [])) {
      this.appendProgramOutputLine(line);
    }

    for (const event of (data.events || [])) {
      if (event.event === 'paused') {
        this.handleDebugPaused(event);
      } else if (event.event === 'finished') {
        this.appendProgramOutputLine('Program finished.', true);
      }
    }

    if (data.finished) {
      this.endDebugSession();
    }
  }

  appendProgramOutputLine(text, success = false) {
    if (!this.programOutputBody) return;
    if (this.programOutputBody.querySelector('.log-empty, .log-line')?.textContent?.includes('Starting Otter debug session')) {
      this.programOutputBody.innerHTML = '';
    }
    const cls = success ? 'log-line log-success' : 'log-line';
    const rendered = success ? `<strong>${this.escapeHtml(text)}</strong>` : this.escapeHtml(text);
    this.programOutputBody.innerHTML += `<div class="${cls}">${rendered}</div>`;
    this.programOutputBody.scrollTop = this.programOutputBody.scrollHeight;
  }

  // A real Otter call frame paused execution: exact file/line, and the
  // Otter locals that frame actually owns - straight from
  // Get-OtterDebugLocals in src/Otter.Debugger.psm1, never derived by
  // Studio itself from source text (contrast updateVariablesInspector's
  // post-run best-effort regex scan above, which this session intentionally
  // does not use while paused).
  handleDebugPaused(event) {
    this.debugPausedLine = event.line;
    this.debugCallStack = event.callStack || [];
    this.renderGutter((this.currentCode || '').split('\n').length);
    const lineEl = this.codeAreaEl?.querySelector(`.code-line[data-line="${event.line}"]`);
    if (lineEl) {
      lineEl.classList.add('has-debug-pause');
      lineEl.scrollIntoView({ block: 'center', behavior: 'smooth' });
    }
    this.renderDebugLocals(event.locals || {}, event.callStack || []);
    if (this.btnDebugContinue) this.btnDebugContinue.style.display = 'inline-flex';
    this.appendProgramOutputLine(`Paused at ${event.file}:${event.line}`);
  }

  renderDebugLocals(locals, callStack) {
    if (!this.variablesBody) return;
    const names = Object.keys(locals);
    let html = '';
    if (callStack.length > 0) {
      html += `<div style="padding: 4px 8px; font-size: 11px; color: var(--text-faint);">in ${this.escapeHtml(callStack[callStack.length - 1].function)}()</div>`;
    }
    if (names.length === 0) {
      html += '<div class="var-empty-state" style="color: #94a3b8; font-style: italic; font-size: 11px; padding: 6px 4px;">No variables in this scope yet.</div>';
    } else {
      html += names.map(name => `
        <div class="var-row" style="display: flex; justify-content: space-between; gap: 8px; padding: 3px 8px; font-family: var(--font-code); font-size: 12px;">
          <span style="color: #0891b2;">${this.escapeHtml(name)}</span>
          <span style="color: var(--text-main); font-weight: 600;">${this.escapeHtml(String(locals[name]))}</span>
        </div>
      `).join('');
    }
    this.variablesBody.innerHTML = html;
  }

  async continueDebugSession() {
    if (!this.debugSessionId) return;
    this.clearDebugPauseState(true);
    try {
      await fetch('/api/debug/continue', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sessionId: this.debugSessionId })
      });
    } catch {}
  }

  // Clears the visual "paused here" state. keepSession=true is used by
  // "Continue" (the session itself is still running, just no longer
  // stopped); the default (session start/end) also drops debugCallStack.
  clearDebugPauseState(keepSession = false) {
    if (this.debugPausedLine !== null && this.codeAreaEl) {
      const lineEl = this.codeAreaEl.querySelector(`.code-line[data-line="${this.debugPausedLine}"]`);
      lineEl?.classList.remove('has-debug-pause');
    }
    this.debugPausedLine = null;
    this.renderGutter((this.currentCode || '').split('\n').length);
    if (this.btnDebugContinue) this.btnDebugContinue.style.display = 'none';
    if (!keepSession) this.debugCallStack = null;
  }

  endDebugSession() {
    if (this.debugPollTimer) clearInterval(this.debugPollTimer);
    this.debugPollTimer = null;
    this.debugSessionId = null;
    this.clearDebugPauseState();
    if (this.btnDebugProgram) this.btnDebugProgram.style.display = 'inline-flex';
    if (this.mainRunBtn) this.mainRunBtn.style.display = 'inline-flex';
    if (this.btnStopProgram) this.btnStopProgram.style.display = 'none';
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
    if (!cmdText || !this.terminalHistory) return;

    if (!this.isTrusted) {
      const proceed = confirm('Restricted Mode: This workspace is untrusted. Executing terminal commands in an untrusted workspace may be unsafe.\n\nDo you want to trust this workspace and proceed?');
      if (!proceed) return;
      this.grantWorkspaceTrust();
    }

    // Append Command entry to history
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
    if (this.isLargeFileMode) {
      this.errorLine = null;
      this.warningLine = null;
      this.activeDiagnostics = [];
      this.diagnosticCollection.clear(this.currentFile);
      this.currentDiagnostic = null;
      this.availableQuickFixes = [];
      if (this.btnProblemQuickFix) this.btnProblemQuickFix.style.display = 'none';
      const diag = normalizeDiagnostic({
        code: DiagnosticCodes.LARGE_FILE_ANALYSIS_BYPASS,
        severity: 'info',
        source: 'studio',
        category: 'studio',
        message: 'AST analysis bypassed for high performance.'
      }, this.currentCode, this.currentFile);
      this.setProblemsStatus(true, 'Large File Mode Active', 'AST analysis bypassed for high performance.', 'Large File', 'Virtualization active. ⚡', false, diag);
      this.updateErrorSquiggles();
      return;
    }

    if (this.currentFile && !this.currentFile.endsWith('.ot')) {
      this.errorLine = null;
      this.warningLine = null;
      this.activeDiagnostics = [];
      this.diagnosticCollection.clear(this.currentFile);
      this.currentDiagnostic = null;
      this.availableQuickFixes = [];
      if (this.btnProblemQuickFix) this.btnProblemQuickFix.style.display = 'none';

      if (this.currentFile.endsWith('.css')) {
        this.setProblemsStatus(true, 'CSS Stylesheet', 'Lossless CSS styles.', 'CSS 3.0', 'Styling active. 🎨', false);
      } else if (this.currentFile.endsWith('.json')) {
        try {
          const parsed = JSON.parse(this.currentCode);
          if (this.currentFile.endsWith('project.json')) {
            const validation = validateManifest(parsed, this.workspaceFiles);
            if (!validation.ok) {
              const diag = normalizeDiagnostic({
                code: DiagnosticCodes.MANIFEST_VALIDATION_ERROR,
                severity: 'error',
                source: 'build',
                category: 'build',
                message: `Manifest Error: ${validation.errors[0]}`
              }, this.currentCode, this.currentFile);
              this.activeDiagnostics = [diag];
              this.currentDiagnostic = diag;
              this.setProblemsStatus(false, `${diag.code}  ${diag.message}`, 'Check project.json', 'Manifest', 'Invalid manifest configuration.', false, diag);
            } else if (validation.warnings.length > 0) {
              this.setProblemsStatus(true, `Notice: ${validation.warnings[0]}`, 'Advisory', 'Manifest', 'Manifest has advisory warnings.', false);
            } else {
              this.setProblemsStatus(true, `Project Manifest (${parsed.name || 'app'})`, 'Ready', 'Manifest', 'Manifest valid. ⚙', false);
            }
          } else {
            this.setProblemsStatus(true, 'Valid JSON Configuration', 'Ready', 'JSON', 'Config valid. ⚙', false);
          }
        } catch (err) {
          const diag = normalizeDiagnostic({
            code: DiagnosticCodes.MANIFEST_VALIDATION_ERROR,
            severity: 'error',
            source: 'studio',
            category: 'syntax',
            message: `JSON Error: ${err.message}`
          }, this.currentCode, this.currentFile);
          this.activeDiagnostics = [diag];
          this.currentDiagnostic = diag;
          this.setProblemsStatus(false, `${diag.code}  ${diag.message}`, 'Check JSON formatting', 'JSON Syntax', 'Invalid JSON syntax.', false, diag);
        }
      } else {
        this.setProblemsStatus(true, 'Ready', 'Text file', 'Text', '', false);
      }
      this.updateErrorSquiggles();
      return;
    }

    try {
      const res = await fetch('/api/analyze', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: this.currentCode })
      });
      const data = await res.json();

      if (data.Ok !== false && data.ok !== false) {
        this.errorLine = null;
        this.updateCurrentDocumentSymbols(data);

        // Compute semantic diagnostics (unused variables and unreachable code)
        const semanticDiags = otterLanguageService.computeSemanticDiagnostics(
          this.currentCode,
          data.Symbols || [],
          data.References || data.AstReferences || []
        );

        if (semanticDiags.length > 0) {
          const normalizedSemantics = semanticDiags.map(sd => normalizeDiagnostic({
            ...sd,
            stage: 'analyzer',
            severity: 'warning',
            isWarning: true
          }, this.currentCode, this.currentFile));

          this.activeDiagnostics = normalizedSemantics;
          this.diagnosticCollection.set(this.currentFile, normalizedSemantics);
          const first = normalizedSemantics[0];
          this.currentDiagnostic = first;
          this.warningLine = first.startLine;
          this.availableQuickFixes = first.fixes;

          this.setProblemsStatus(
            false,
            `${first.code}  ${first.message}`,
            `Line ${first.startLine}, Col ${first.startColumn} (${this.currentFile}) — Semantic Advisory`,
            'Code Advisory',
            'Review variables and execution flow. 🐾',
            true,
            first
          );
        } else {
          this.activeDiagnostics = [];
          this.diagnosticCollection.set(this.currentFile, []);
          this.currentDiagnostic = null;
          this.warningLine = null;
          this.availableQuickFixes = [];
          if (this.btnProblemQuickFix) this.btnProblemQuickFix.style.display = 'none';
          this.setProblemsStatus(true, 'No problems found.', 'Your code looks good!', 'Great job!', 'Keep going! 🐾', false);
        }
      } else {
        this.warningLine = null;
        const diag = normalizeDiagnostic({
          Line: data.Line ?? data.line,
          Column: data.Column ?? data.column,
          Message: data.Message ?? data.message,
          Suggestion: data.Suggestion ?? data.suggestion,
          SourceLine: data.SourceLine ?? data.sourceLine,
          stage: data.stage || 'parser',
          source: 'otter'
        }, this.currentCode, this.currentFile);

        this.activeDiagnostics = [diag];
        this.diagnosticCollection.set(this.currentFile, [diag]);
        this.currentDiagnostic = diag;
        this.errorLine = diag.startLine;
        this.availableQuickFixes = diag.fixes;

        const lineNote = diag.startLine ? `Line ${diag.startLine}, Col ${diag.startColumn} (${this.currentFile}) — ` : '';
        const sub = diag.suggestion ? `Suggestion: ${diag.suggestion}` : 'Check your grammar.';

        this.setProblemsStatus(
          false,
          `${diag.code}  ${diag.message}`,
          lineNote + sub,
          'Syntax Check',
          'Keep checking your code! 🐾',
          false,
          diag
        );
      }
      this.updateErrorSquiggles();
    } catch {
      // Offline fallback: assume ok
    }
  }

  updateErrorSquiggles() {
    if (!this.codeAreaEl) return;
    this.codeAreaEl.querySelectorAll('.code-line.has-error').forEach(el => el.classList.remove('has-error'));
    this.codeAreaEl.querySelectorAll('.code-line.has-warning').forEach(el => el.classList.remove('has-warning'));
    if (this.gutterEl) {
      this.gutterEl.querySelectorAll('.gutter-err').forEach(el => el.classList.remove('gutter-err'));
      this.gutterEl.querySelectorAll('.gutter-warn').forEach(el => el.classList.remove('gutter-warn'));
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
    } else if (this.warningLine) {
      const warnLineEl = this.codeAreaEl.querySelector(`[data-line="${this.warningLine}"]`);
      if (warnLineEl) warnLineEl.classList.add('has-warning');
      if (this.gutterEl) {
        const gutterSpans = this.gutterEl.querySelectorAll('span');
        if (gutterSpans[this.warningLine - 1]) {
          gutterSpans[this.warningLine - 1].classList.add('gutter-warn');
        }
      }
    }
  }

  setProblemsStatus(ok, title, subtitle, cheerH, cheerT, isWarning = false, diagnostic = null) {
    if (this.problemTitle) {
      if (diagnostic?.code) {
        const severityClass = diagnostic.severity === 'warning' ? 'severity-warning' : (diagnostic.severity === 'info' ? 'severity-info' : 'severity-error');
        const cleanTitle = title.replace(new RegExp(`^${diagnostic.code}\\s*`), '');
        this.problemTitle.innerHTML = `<span class="problem-code-badge ${severityClass}">${this.escapeHtml(diagnostic.code)}</span><span>${this.escapeHtml(cleanTitle)}</span>`;
      } else {
        this.problemTitle.innerText = title;
      }
    }

    if (this.problemSubtitle) {
      let subHtml = `<span>${this.escapeHtml(subtitle)}</span>`;
      if (diagnostic?.hostDetails) {
        subHtml += `
          <details class="host-error-details">
            <summary>Technical Details (${this.escapeHtml(diagnostic.source || 'host')})</summary>
            <pre>${this.escapeHtml(diagnostic.hostDetails)}</pre>
          </details>
        `;
      }
      if (diagnostic?.stack && diagnostic.stack.length > 0) {
        subHtml += `
          <div class="stack-frames-list">
            ${diagnostic.stack.map(f => `<div class="stack-frame-item" title="Click to navigate" data-file="${this.escapeHtml(f.file)}" data-line="${f.line}" data-col="${f.column}">at ${f.functionName && f.functionName !== '<script>' ? `in ${this.escapeHtml(f.functionName)} ` : ''}${this.escapeHtml(f.file)}:${f.line}${f.column > 1 ? `:${f.column}` : ''}</div>`).join('')}
          </div>
        `;
      }
      this.problemSubtitle.innerHTML = subHtml;
    }

    if (this.cheerHeadline) this.cheerHeadline.innerText = cheerH;
    if (this.cheerTagline) this.cheerTagline.innerText = cheerT;

    if (this.statusCheckCircle) {
      if (ok) {
        this.statusCheckCircle.style.background = '#22c55e';
        this.statusCheckCircle.innerText = '✓';
      } else if (isWarning) {
        this.statusCheckCircle.style.background = '#f59e0b';
        this.statusCheckCircle.innerText = '▲';
      } else {
        this.statusCheckCircle.style.background = '#ef4444';
        this.statusCheckCircle.innerText = '!';
      }
    }

    if (this.btnProblemQuickFix) {
      if (!ok && diagnostic?.fixes && diagnostic.fixes.length > 0) {
        this.btnProblemQuickFix.style.display = 'inline-flex';
        this.btnProblemQuickFix.textContent = `💡 ${diagnostic.fixes[0].title}`;
        this.btnProblemQuickFix.title = diagnostic.fixes[0].title;
      } else {
        this.btnProblemQuickFix.style.display = 'none';
      }
    }

    if (this.problemStatusBanner) {
      const target = diagnostic?.startLine || this.errorLine || this.warningLine;
      if (!ok && target) {
        this.problemStatusBanner.classList.add('has-error-clickable');
        this.problemStatusBanner.title = `Click to navigate to ${diagnostic?.file || this.currentFile}:${diagnostic?.startLine || target}:${diagnostic?.startColumn || 1} in source`;
      } else {
        this.problemStatusBanner.classList.remove('has-error-clickable');
        this.problemStatusBanner.title = 'No problems detected';
      }
    }
  }

  handleEditorHover(event) {
    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea || !this.editorHoverTooltipEl) return;

    const rect = textarea.getBoundingClientRect();
    const x = event.clientX - rect.left + textarea.scrollLeft;
    const y = event.clientY - rect.top + textarea.scrollTop;
    const offset = this._editorCoordsToOffset(textarea, x, y);

    if (offset < 0 || offset > textarea.value.length) {
      this.hideHoverTooltip();
      return;
    }

    const word = getWordAtOffset(textarea.value, offset);
    if (!word) {
      this.hideHoverTooltip();
      return;
    }

    const lineForHover = textarea.value.slice(0, offset).split('\n').length;
    const info = getHoverInfo(word, this.currentFile, this.workspaceSymbols, lineForHover);
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

    const coords = this._offsetToEditorCoords(textarea, textarea.selectionStart);
    const lineHeight = parseFloat(window.getComputedStyle(textarea).lineHeight) || 20;

    let left = Math.max(10, coords.left - textarea.scrollLeft + 20);
    let top = Math.max(10, coords.top + lineHeight - textarea.scrollTop + 10);
    const viewportRect = this.codeAreaEl?.parentElement?.getBoundingClientRect() || { width: 600, height: 400 };
    if (left + 360 > viewportRect.width) left = Math.max(10, viewportRect.width - 370);
    if (top + 100 > viewportRect.height) top = Math.max(10, coords.top - textarea.scrollTop - 70);

    this.editorSignatureHelpEl.style.left = `${left}px`;
    this.editorSignatureHelpEl.style.top = `${top}px`;
    this.editorSignatureHelpEl.style.display = 'block';
  }

  hideSignatureHelp() {
    if (this.editorSignatureHelpEl) {
      this.editorSignatureHelpEl.style.display = 'none';
    }
  }

  applyExactSquigglesToLine(renderedHtml, lineNum, rawLineText, diags = []) {
    if (!diags || diags.length === 0) return renderedHtml;

    let resultHtml = renderedHtml;
    for (const diag of diags) {
      const startCol = diag.startColumn || 1;
      const endCol = diag.endColumn || (startCol + 1);
      const severityClass = diag.severity === 'warning' ? 'squiggle-warning' : (diag.severity === 'info' ? 'squiggle-info' : 'squiggle-error');
      const title = this.escapeHtml(`${diag.code}: ${diag.message}`);

      // If diagnostic points past line text (e.g. missing block terminator at EOF or line end)
      if (startCol > rawLineText.length) {
        resultHtml += `<span class="exact-squiggle ${severityClass}" title="${title}">&nbsp;</span>`;
        continue;
      }

      // Wrap exact character slice in renderedHtml
      resultHtml = this.wrapExactRangeInHtml(resultHtml, startCol, endCol, `exact-squiggle ${severityClass}`, title);
    }
    return resultHtml;
  }

  wrapExactRangeInHtml(html, startCol, endCol, className, title) {
    let output = '';
    let visIdx = 0;
    let inTag = false;
    let tagBuffer = '';
    let isUnderlining = false;

    for (let i = 0; i < html.length; i++) {
      const c = html[i];
      if (c === '<') {
        inTag = true;
        tagBuffer = '<';
        continue;
      }
      if (inTag) {
        tagBuffer += c;
        if (c === '>') {
          inTag = false;
          output += tagBuffer;
          tagBuffer = '';
        }
        continue;
      }

      // Handle HTML entities (e.g. &amp;, &lt;, &gt;, &quot;, &#039;)
      let textChunk = c;
      if (c === '&') {
        const semiIdx = html.indexOf(';', i);
        if (semiIdx > i && semiIdx - i <= 8) {
          textChunk = html.slice(i, semiIdx + 1);
          i = semiIdx;
        }
      }

      const shouldUnderline = (visIdx >= startCol - 1 && visIdx < endCol - 1);
      if (shouldUnderline && !isUnderlining) {
        output += `<span class="${className}" title="${title}">`;
        isUnderlining = true;
      } else if (!shouldUnderline && isUnderlining) {
        output += '</span>';
        isUnderlining = false;
      }

      output += textChunk;
      visIdx++;
    }

    if (isUnderlining) {
      output += '</span>';
    }

    return output;
  }

  navigateToDiagnostic(diag) {
    if (!diag) return;
    if (diag.file && diag.file !== this.currentFile) {
      const tab = this.openTabs.find(t => t.path === diag.file);
      if (tab) {
        this.switchTab(diag.file);
      }
    }

    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea) return;

    const startOffset = this.getOffsetFromPosition(this.currentCode, diag.startLine, diag.startColumn);
    const endOffset = this.getOffsetFromPosition(this.currentCode, diag.endLine, diag.endColumn);

    textarea.focus();
    textarea.setSelectionRange(startOffset, Math.max(startOffset, endOffset));

    const lineHeight = DEFAULT_LINE_HEIGHT || 22;
    const targetScrollTop = Math.max(0, (diag.startLine - 3) * lineHeight);
    textarea.scrollTop = targetScrollTop;
    if (this.codeAreaEl) this.codeAreaEl.scrollTop = targetScrollTop;
    if (this.gutterEl) this.gutterEl.scrollTop = targetScrollTop;

    this.updateCursorPos(textarea);
    this.renderCursorOverlays();
  }

  navigateToPosition(file, line, column = 1) {
    if (file && file !== this.currentFile) {
      this.switchTab(file);
    }
    const diag = {
      file: file || this.currentFile,
      startLine: line,
      startColumn: column,
      endLine: line,
      endColumn: column + 1
    };
    this.navigateToDiagnostic(diag);
  }

  checkDiagnosticAtCursor(textarea) {
    if (!textarea || !this.activeDiagnostics || this.activeDiagnostics.length === 0) return;
    const offset = textarea.selectionStart;
    const { line, column } = this.multiCursor.getLineAndCol(this.currentCode, offset);
    const found = this.activeDiagnostics.find(d => {
      if (line < d.startLine || line > d.endLine) return false;
      if (line === d.startLine && column < d.startColumn) return false;
      if (line === d.endLine && column > d.endColumn) return false;
      return true;
    });
    if (found && found !== this.currentDiagnostic) {
      this.currentDiagnostic = found;
      this.setProblemsStatus(
        false,
        `${found.code}  ${found.message}`,
        `Line ${found.startLine}, Col ${found.startColumn} (${found.file})`,
        'Syntax Check',
        'Keep checking your code! 🐾',
        found.severity === 'warning',
        found
      );
    }
  }

  applyCurrentQuickFix() {
    if (!this.availableQuickFixes || this.availableQuickFixes.length === 0) return;
    this.applyQuickFix(this.availableQuickFixes[0]);
  }

  applyQuickFix(fix) {
    if (!fix) return;
    if (Array.isArray(fix.edits) && fix.edits.length > 0) {
      for (const edit of fix.edits) {
        if (edit.file && edit.file !== this.currentFile) {
          const targetTab = this.openTabs.find(t => t.path === edit.file);
          if (targetTab) {
            targetTab.content = this.applyEditToText(targetTab.content, edit);
            targetTab.isDirty = true;
          }
        } else {
          this.currentCode = this.applyEditToText(this.currentCode, edit);
          this.markCurrentTabDirty(true);
        }
      }
    } else if (typeof fix.apply === 'function') {
      const updated = fix.apply(this.currentCode);
      if (typeof updated === 'string') {
        this.currentCode = updated;
        this.markCurrentTabDirty(true);
      }
    }

    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea) {
      textarea.value = this.currentCode;
    }
    this.renderEditorCode(this.currentCode);
    this.saveSessionState();
    this.debouncedLint();
    this.emitSourceChanged();
  }

  applyEditToText(text, edit) {
    const startOffset = this.getOffsetFromPosition(text, edit.startLine, edit.startColumn);
    const endOffset = this.getOffsetFromPosition(text, edit.endLine, edit.endColumn);
    return text.slice(0, startOffset) + (edit.newText ?? '') + text.slice(endOffset);
  }

  getOffsetFromPosition(text, line = 1, column = 1) {
    const raw = text || '';
    const lines = raw.split('\n');
    if (line > lines.length) {
      return raw.length;
    }
    let offset = 0;
    const safeLine = Math.max(1, line);
    for (let i = 0; i < safeLine - 1; i++) {
      offset += lines[i].length + 1; // +1 for newline
    }
    const lineLen = lines[safeLine - 1] ? lines[safeLine - 1].length : 0;
    offset += Math.min(Math.max(0, (column || 1) - 1), lineLen);
    return offset;
  }

  populateBuildDiagnostics(target, buildResult) {
    if (!buildResult) return;
    const isOk = buildResult.ok !== false && !buildResult.error;
    if (isOk) {
      this.diagnosticCollection.clear(`build-${target}`);
      this.setProblemsStatus(true, `Build Succeeded (${target})`, `Target ${target} compiled cleanly.`, 'Build Ready', 'Ready to run or deploy! 🚀');
      return;
    }

    const rawError = buildResult.error || buildResult.stderr || 'Build failed';
    const translated = translateHostError(rawError, { file: this.currentFile, isBuild: true, target });
    const diag = normalizeDiagnostic({
      ...(translated || {}),
      code: DiagnosticCodes.TARGET_COMPILATION_ERROR,
      message: translated?.message || `Target compilation failed for ${target}`,
      target,
      source: 'build',
      category: 'build',
      hostDetails: buildResult.stderr || buildResult.stdout || rawError
    }, this.currentCode, this.currentFile);

    this.diagnosticCollection.set(`build-${target}`, [diag]);
    this.activeDiagnostics = [diag];
    this.currentDiagnostic = diag;
    this.setProblemsStatus(
      false,
      `[${target.toUpperCase()} Build] ${diag.code}  ${diag.message}`,
      `Build target: ${target} — Target Compiler Check`,
      'Build Issue',
      'Review build error details. ⚙',
      false,
      diag
    );
    this.updateErrorSquiggles();
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

