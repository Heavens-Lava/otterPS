// ide.js - Interactive Code Editor, Real Project Tree, Terminal, and Execution Engine for Otter Studio

export class OtterStudioIde {
  constructor() {
    this.currentFile = 'untitled.ot';
    this.currentCode = '# untitled.ot\n\nsay "Hello from Otter!"\n';
    this.currentProjectFolder = null;
    this.currentProjectName = null;
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

    // Multi-Tab & Quick Action Elements
    this.tabsScrollEl = document.getElementById('editorTabsScroll');
    this.btnAddNewTab = document.getElementById('btnAddNewTab');
    this.btnFormatDoc = document.getElementById('btnFormatDoc');
    this.btnFindDoc = document.getElementById('btnFindDoc');

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
    this.statusBarPos = document.querySelector('.statusbar-right span:first-child');
    this.mainRunBtn = document.getElementById('mainRunBtn');
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
      this.mainRunBtn.addEventListener('click', () => this.runCurrentProgram());
    }

    // Keyboard Shortcuts: F5 / Ctrl+Enter to Run
    window.addEventListener('keydown', (e) => {
      if (e.key === 'F5' || (e.ctrlKey && e.key === 'Enter')) {
        e.preventDefault();
        this.runCurrentProgram();
      }
      if (e.ctrlKey && e.key === 's') {
        e.preventDefault();
        this.saveCurrentFile();
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
  renderCleanProjectTree() {
    this.currentProjectFolder = null;
    this.currentProjectName = null;
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
        this.renderProjectTree(data.tree, this.currentProjectName, this.currentProjectFolder);
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

    const textarea = document.getElementById('hiddenEditorInput');
    if (textarea) {
      textarea.value = this.currentCode;
    }

    this.renderTabs();
    this.renderEditorCode(this.currentCode);
    this.lintCurrentCode();
    this.renderExternalChangeBanner();
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

  goToLine(lineNum) {
    const textarea = document.getElementById('hiddenEditorInput');
    if (!textarea) return;
    const lines = textarea.value.split('\n');
    const targetLine = Math.min(Math.max(1, lineNum), lines.length);
    let charOffset = 0;
    for (let i = 0; i < targetLine - 1; i++) {
      charOffset += lines[i].length + 1;
    }
    textarea.focus();
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

  // --- Interactive Code Editor & Syntax Highlighting ---
  renderEditorCode(codeText) {
    if (!this.codeAreaEl) return;

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

    // Attach inline editor handlers
    this.setupInlineEditor();
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
      textarea.style.opacity = '0';
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
        if (this.codeAreaEl) {
          this.codeAreaEl.scrollTop = textarea.scrollTop;
          this.codeAreaEl.scrollLeft = textarea.scrollLeft;
        }
        if (this.gutterEl) {
          this.gutterEl.scrollTop = textarea.scrollTop;
        }
      });

      textarea.addEventListener('input', () => {
        this.currentCode = textarea.value;
        this.markCurrentTabDirty(true);
        this.renderEditorCode(this.currentCode);
        this.updateCursorPos(textarea);
        this.saveSessionState();
        this.debouncedLint();
      });

      textarea.addEventListener('keydown', (e) => {
        // Keyboard shortcuts
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
  async runCurrentProgram() {
    if (!this.mainRunBtn) return;
    this.mainRunBtn.classList.add('is-running');
    this.mainRunBtn.querySelector('span:last-child').innerText = 'Running...';

    // Save first. A disk conflict must be resolved before execution so the
    // runner never receives a version the user has not chosen explicitly.
    const saved = await this.saveCurrentFile();
    if (!saved) {
      this.mainRunBtn.classList.remove('is-running');
      this.mainRunBtn.querySelector('span:last-child').innerText = 'Run';
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
      this.mainRunBtn.classList.remove('is-running');
      this.mainRunBtn.querySelector('span:last-child').innerText = 'Run';
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
      const res = await fetch('/api/lint', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ code: this.currentCode })
      });
      const data = await res.json();

      if (data.ok) {
        this.errorLine = null;
        this.setProblemsStatus(true, 'No problems found.', 'Your code looks good!', 'Great job!', 'Keep going! 🐾');
      } else {
        this.errorLine = (typeof data.line === 'number') ? data.line : null;
        const lineNote = data.line ? `Line ${data.line}: ` : '';
        const msg = lineNote + (data.message || 'Syntax issue detected');
        const sub = data.suggestion ? `Suggestion: ${data.suggestion}` : 'Check your grammar.';
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
