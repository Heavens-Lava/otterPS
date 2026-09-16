import { OtterUiModel } from './model/ui-model.js';
import { CssAstManager } from './compiler/css-ast.js';
import { StarterTemplates } from './templates/starter-templates.js';
import { generateOtterSource } from './compiler/otter-generator.js';
import { parseOtterSource } from './compiler/otter-parser.js';

import { renderToolbox } from './components/toolbox.js';
import { renderHierarchy } from './components/hierarchy.js';
import { renderCanvas } from './components/canvas.js';
import { renderProperties } from './components/properties.js';
import { renderEvents } from './components/events.js';
import { renderEditor } from './components/editor.js';
import { renderPreview } from './components/preview.js';
import { OtterStudioIde } from './ide.js';

document.addEventListener('DOMContentLoaded', async () => {
  const themeToggle = document.getElementById('btnThemeToggle');
  const storedTheme = localStorage.getItem('otter-studio-theme');
  const initialTheme = storedTheme === 'light' || storedTheme === 'dark' ? storedTheme : 'dark';

  function applyTheme(theme) {
    const dark = theme === 'dark';
    document.body.classList.toggle('theme-dark', dark);
    document.body.classList.toggle('theme-light', !dark);
    if (themeToggle) {
      const nextTheme = dark ? 'light' : 'dark';
      const label = dark ? 'Light' : 'Dark';
      themeToggle.querySelector('.theme-toggle-icon').textContent = dark ? '☀' : '☾';
      themeToggle.querySelector('.theme-toggle-label').textContent = label;
      themeToggle.title = `Switch to ${nextTheme} theme`;
      themeToggle.setAttribute('aria-label', themeToggle.title);
      themeToggle.setAttribute('aria-pressed', String(dark));
    }
  }

  applyTheme(initialTheme);
  themeToggle?.addEventListener('click', () => {
    const nextTheme = document.body.classList.contains('theme-dark') ? 'light' : 'dark';
    localStorage.setItem('otter-studio-theme', nextTheme);
    applyTheme(nextTheme);
  });

  // Initialize Core In-Memory Model & CSS AST Engine
  const defaultTpl = StarterTemplates['blank'];
  const uiModel = new OtterUiModel();
  const cssAstManager = new CssAstManager(defaultTpl.css || '');

  // Load default template: Clean Blank Application
  defaultTpl.load(uiModel);

  // Initialize Interactive IDE & Execution Engine
  const ide = new OtterStudioIde();
  await ide.init();

  // Expose authoritative engines to window for cross-module access
  window.otterUiModel = uiModel;
  window.otterCssAstManager = cssAstManager;
  window.otterIde = ide;

  // Mount components
  const toolboxEl = document.getElementById('toolboxPanel');
  const hierarchyEl = document.getElementById('hierarchyPanel');
  const canvasEl = document.getElementById('canvasContainer');
  const centerWorkArea = document.getElementById('centerWorkArea');
  const propertiesEl = document.getElementById('propertiesContent');
  const eventsEl = document.getElementById('eventsContent');
  const editorEl = document.getElementById('editorContainer');
  const previewEl = document.getElementById('previewContainer');

  renderToolbox(toolboxEl, uiModel);
  renderHierarchy(hierarchyEl, uiModel, cssAstManager);
  renderCanvas(canvasEl, uiModel, cssAstManager);
  renderProperties(propertiesEl, uiModel, cssAstManager);
  renderEvents(eventsEl, uiModel);
  renderEditor(editorEl, uiModel, cssAstManager);
  renderPreview(previewEl, uiModel, cssAstManager);

  // View Elements
  const codeEditorView = document.getElementById('codeEditorView');
  const codeRightSidebar = document.getElementById('codeRightSidebar');
  const designerRightSidebar = document.getElementById('designerRightSidebar');
  const bottomDrawer = document.getElementById('bottomDrawer');

  // Sidebar Pane Tabs: Files, Toolbox, Outline
  const btnPaneFiles = document.getElementById('btnPaneFiles');
  const btnPaneToolbox = document.getElementById('btnPaneToolbox');
  const btnPaneHierarchy = document.getElementById('btnPaneHierarchy');
  const btnPaneSearch = document.getElementById('btnPaneSearch');
  const paneFiles = document.getElementById('paneFiles');
  const paneToolbox = document.getElementById('paneToolbox');
  const paneHierarchy = document.getElementById('paneHierarchy');
  const paneSearch = document.getElementById('paneSearch');
  const sourceOutlinePanel = document.getElementById('sourceOutlinePanel');
  const designerHierarchyPanel = document.getElementById('hierarchyPanel');

  function setOutlineContext(mode) {
    const sourceMode = mode === 'code';
    if (sourceOutlinePanel) sourceOutlinePanel.style.display = sourceMode ? 'flex' : 'none';
    if (designerHierarchyPanel) designerHierarchyPanel.style.display = sourceMode ? 'none' : 'flex';
  }

  function switchSidebarPane(pane) {
    [btnPaneFiles, btnPaneToolbox, btnPaneHierarchy, btnPaneSearch].forEach(b => b?.classList.remove('is-active'));
    if (paneFiles) paneFiles.style.display = 'none';
    if (paneToolbox) paneToolbox.style.display = 'none';
    if (paneHierarchy) paneHierarchy.style.display = 'none';
    if (paneSearch) paneSearch.style.display = 'none';

    if (pane === 'files') {
      btnPaneFiles?.classList.add('is-active');
      if (paneFiles) paneFiles.style.display = 'flex';
    } else if (pane === 'toolbox') {
      btnPaneToolbox?.classList.add('is-active');
      if (paneToolbox) paneToolbox.style.display = 'flex';
    } else if (pane === 'hierarchy') {
      btnPaneHierarchy?.classList.add('is-active');
      if (paneHierarchy) paneHierarchy.style.display = 'flex';
    } else if (pane === 'search') {
      btnPaneSearch?.classList.add('is-active');
      if (paneSearch) paneSearch.style.display = 'flex';
      setTimeout(() => document.getElementById('workspaceSearchInput')?.focus(), 0);
    }
  }

  btnPaneFiles?.addEventListener('click', () => switchSidebarPane('files'));
  btnPaneToolbox?.addEventListener('click', () => switchSidebarPane('toolbox'));
  btnPaneHierarchy?.addEventListener('click', () => switchSidebarPane('hierarchy'));
  btnPaneSearch?.addEventListener('click', () => switchSidebarPane('search'));
  window.addEventListener('otter:sidebar-pane', event => switchSidebarPane(event.detail));

  // Live Code Synchronizer from UI Model -> Code Editors
  function syncCodeFromUiModel() {
    if (!uiModel.getRoot()) return;
    const generatedCode = generateOtterSource(uiModel);
    ide.currentCode = generatedCode;
    if (ide.codeAreaEl) {
      ide.renderEditorCode(generatedCode);
    }
    const liveCodeArea = document.getElementById('drawerGeneratedCodeArea');
    if (liveCodeArea) {
      liveCodeArea.textContent = generatedCode;
    }
  }

  let sourceSyncTimer = null;
  let sourceSyncRevision = 0;

  async function syncUiFromSource(source, immediate = false) {
    const revision = ++sourceSyncRevision;
    if (sourceSyncTimer) clearTimeout(sourceSyncTimer);

    const apply = async () => {
      if (revision !== sourceSyncRevision) return;

      // Empty source is a valid empty design, not a reason to retain stale UI.
      if (!source || !source.trim()) {
        parseOtterSource('', uiModel);
        return;
      }

      // The browser-side UI reader only mutates the model after it has found
      // a complete window declaration, so incomplete edits keep the last
      // valid visual tree while the user is typing.
      if (parseOtterSource(source, uiModel)) return;

      // A valid non-UI Otter program intentionally has no visual tree. Use
      // the real parser to distinguish that from temporarily invalid source.
      try {
        const response = await fetch('/api/lint', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ code: source })
        });
        const result = await response.json();
        if (revision === sourceSyncRevision && result.ok) {
          uiModel.clearFromSource();
        }
      } catch (error) {
        console.warn('Could not validate source for visual synchronization:', error);
      }
    };

    if (immediate) {
      await apply();
    } else {
      sourceSyncTimer = setTimeout(apply, 180);
    }
  }

  window.addEventListener('otter:source-changed', event => {
    syncUiFromSource(event.detail?.source ?? '');
  });

  uiModel.subscribe((changeType) => {
    if (changeType === 'parse' || changeType === 'source-clear') {
      const liveCodeArea = document.getElementById('drawerGeneratedCodeArea');
      if (liveCodeArea) liveCodeArea.textContent = ide.currentCode;
      return;
    }
    syncCodeFromUiModel();
  });

  // Reconcile the file loaded during IDE initialization. This listener is
  // installed after init, so the initial source needs one explicit pass.
  syncUiFromSource(ide.currentCode, true);

  // Bottom Drawer Tabs
  const drawerTabs = document.querySelectorAll('.drawer-tab');
  drawerTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      drawerTabs.forEach(t => t.classList.remove('is-active'));
      tab.classList.add('is-active');
      const tabName = tab.getAttribute('data-drawer-tab');
      const panelProb = document.getElementById('panelProblems');
      const panelOut = document.getElementById('panelOutput');
      const panelTerm = document.getElementById('panelTerminal');
      const panelLive = document.getElementById('panelLiveCode');

      if (panelProb) panelProb.style.display = tabName === 'problems' ? 'flex' : 'none';
      if (panelOut) panelOut.style.display = tabName === 'output' ? 'block' : 'none';
      if (panelTerm) panelTerm.style.display = tabName === 'terminal' ? 'flex' : 'none';
      if (panelLive) {
        panelLive.style.display = tabName === 'livecode' ? 'block' : 'none';
        if (tabName === 'livecode') {
          syncCodeFromUiModel();
        }
      }
    });
  });

  document.getElementById('btnCopyLiveCode')?.addEventListener('click', () => {
    const code = document.getElementById('drawerGeneratedCodeArea')?.textContent || '';
    if (code) {
      navigator.clipboard.writeText(code);
      const btn = document.getElementById('btnCopyLiveCode');
      if (btn) {
        btn.textContent = 'Copied!';
        setTimeout(() => btn.textContent = 'Copy Code', 1500);
      }
    }
  });

  // Mode Switcher Pills: Code | UI Designer | Split | Live App
  const modePills = document.querySelectorAll('.mode-pill');

  function setMode(mode) {
    centerWorkArea.classList.toggle('is-workbench', mode === 'workbench');
    modePills.forEach(p => p.classList.remove('is-active'));
    const activePill = document.getElementById(`pill${capitalize(mode)}Mode`);
    if (activePill) activePill.classList.add('is-active');

    const tabMainOt = document.getElementById('tabMainOt');
    if (tabMainOt) {
      if (mode === 'designer') {
        tabMainOt.innerHTML = '<span class="tab-icon">🎨</span><span class="tab-title">UI Designer (app)</span>';
      } else if (mode === 'split') {
        tabMainOt.innerHTML = '<span class="tab-icon">⚡</span><span class="tab-title">Split View (Designer + Code)</span>';
      } else if (mode === 'preview') {
        tabMainOt.innerHTML = '<span class="tab-icon">▶</span><span class="tab-title">Live Preview</span>';
      } else {
        const curName = ide.currentFile ? ide.currentFile.split('/').pop() : 'main.ot';
        tabMainOt.innerHTML = `<span class="tab-icon">📄</span><span class="tab-title">${curName}</span><span class="tab-close">×</span>`;
      }
    }

    if (mode === 'code') {
      setOutlineContext('code');
      codeEditorView.style.display = 'flex';
      canvasEl.style.display = 'none';
      editorEl.style.display = 'none';
      previewEl.style.display = 'none';

      codeRightSidebar.style.display = 'flex';
      designerRightSidebar.style.display = 'none';
      bottomDrawer.style.display = 'flex';

      switchSidebarPane('files');
    } else if (mode === 'designer') {
      setOutlineContext('designer');
      codeEditorView.style.display = 'none';
      canvasEl.style.display = 'flex';
      editorEl.style.display = 'none';
      previewEl.style.display = 'none';

      codeRightSidebar.style.display = 'none';
      designerRightSidebar.style.display = 'flex';
      bottomDrawer.style.display = 'flex';

      // Attempt reverse-sync from code editor if user typed custom Otter code
      syncUiFromSource(ide.currentCode, true);
    } else if (mode === 'split') {
      setOutlineContext('designer');
      codeEditorView.style.display = 'none';
      canvasEl.style.display = 'flex';
      editorEl.style.display = 'flex';
      previewEl.style.display = 'none';

      codeRightSidebar.style.display = 'none';
      designerRightSidebar.style.display = 'flex';
      bottomDrawer.style.display = 'none';

      syncUiFromSource(ide.currentCode, true);
    } else if (mode === 'workbench') {
      setOutlineContext('designer');
      codeEditorView.style.display = 'flex';
      canvasEl.style.display = 'flex';
      editorEl.style.display = 'none';
      previewEl.style.display = 'none';

      codeRightSidebar.style.display = 'none';
      designerRightSidebar.style.display = 'flex';
      bottomDrawer.style.display = 'flex';

      syncUiFromSource(ide.currentCode, true);
    } else if (mode === 'preview') {
      setOutlineContext('designer');
      codeEditorView.style.display = 'none';
      canvasEl.style.display = 'none';
      editorEl.style.display = 'none';
      previewEl.style.display = 'flex';

      codeRightSidebar.style.display = 'none';
      designerRightSidebar.style.display = 'none';
      bottomDrawer.style.display = 'none';
    }
  }

  // Pill click handlers
  document.getElementById('pillCodeMode')?.addEventListener('click', () => setMode('code'));
  document.getElementById('pillDesignerMode')?.addEventListener('click', () => setMode('designer'));
  document.getElementById('pillSplitMode')?.addEventListener('click', () => setMode('split'));
  document.getElementById('pillWorkbenchMode')?.addEventListener('click', () => setMode('workbench'));
  document.getElementById('pillPreviewMode')?.addEventListener('click', () => setMode('preview'));

  // Check URL parameters for initial mode (e.g. ?mode=designer)
  const urlParams = new URLSearchParams(window.location.search);
  const initialMode = urlParams.get('mode');
  if (initialMode && ['code', 'designer', 'split', 'workbench', 'preview'].includes(initialMode)) {
    setMode(initialMode);
  }

  // Project Explorer File Clicks
  document.getElementById('projectFileMain')?.addEventListener('click', () => {
    setMode('code');
  });

  document.getElementById('projectFileCss')?.addEventListener('click', () => {
    setMode('split');
    const tabCss = document.getElementById('tabCss');
    if (tabCss) tabCss.click();
  });

  // Template clicks
  const templateItems = document.querySelectorAll('.template-item');
  templateItems.forEach(item => {
    item.addEventListener('click', () => {
      templateItems.forEach(t => t.classList.remove('is-active'));
      item.classList.add('is-active');

      const tpl = item.getAttribute('data-template');
      if (tpl === 'desktop') {
        setMode('split');
      } else if (tpl === 'simple' || tpl === 'automation') {
        setMode('code');
      }
    });
  });

  // Right sidebar tab toggle (Properties vs Events)
  const rightTabBtns = document.querySelectorAll('.right-tab-btn');
  const propertiesTab = document.getElementById('propertiesTab');
  const eventsTab = document.getElementById('eventsTab');

  rightTabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      rightTabBtns.forEach(b => b.classList.remove('is-active'));
      btn.classList.add('is-active');

      const target = btn.getAttribute('data-tab');
      if (target === 'properties') {
        propertiesTab.style.display = 'block';
        eventsTab.style.display = 'none';
      } else {
        propertiesTab.style.display = 'none';
        eventsTab.style.display = 'block';
      }
    });
  });

  // Main Run Button: in code mode, ide.js handles program execution
  const mainRunBtn = document.getElementById('mainRunBtn');
  if (mainRunBtn) {
    mainRunBtn.addEventListener('click', () => {
      const activePill = document.querySelector('.mode-pill.is-active');
      if (activePill && activePill.id !== 'pillCodeMode') {
        setMode('preview');
      }
    });
  }

  // Clear program output
  const clearProgramBtn = document.getElementById('clearProgramBtn');
  const programOutputBody = document.getElementById('programOutputBody');
  if (clearProgramBtn && programOutputBody) {
    clearProgramBtn.addEventListener('click', () => {
      programOutputBody.innerHTML = '<div class="log-line log-empty">Output cleared.</div>';
    });
  }

  // Interactive Autocomplete selection from Reference Image
  const acItems = document.querySelectorAll('.ac-item');
  const docTitle = document.querySelector('.doc-card-title strong');
  acItems.forEach(item => {
    item.addEventListener('click', () => {
      acItems.forEach(a => a.classList.remove('is-selected'));
      item.classList.add('is-selected');
      const title = item.querySelector('.ac-title strong') || item.querySelector('.ac-title');
      if (title && docTitle) {
        docTitle.innerText = title.innerText;
      }
    });
  });

  // ===============================================================
  // HEADER DROPDOWN MENUS & ACTIONS
  // ===============================================================
  const menuFile = document.getElementById('menuFile');
  if (menuFile) {
    menuFile.addEventListener('click', (e) => {
      e.stopPropagation();
      menuFile.classList.toggle('is-open');
    });
  }
  document.addEventListener('click', () => {
    menuFile?.classList.remove('is-open');
  });

  document.getElementById('menuItemNewProject')?.addEventListener('click', () => {
    menuFile?.classList.remove('is-open');
    openNewProjectModal();
  });
  document.getElementById('menuItemOpenFolder')?.addEventListener('click', () => {
    menuFile?.classList.remove('is-open');
    ide.promptOpenFolder();
  });
  document.getElementById('menuItemNewFile')?.addEventListener('click', () => {
    menuFile?.classList.remove('is-open');
    ide.promptNewFile();
  });
  document.getElementById('menuItemSave')?.addEventListener('click', () => {
    menuFile?.classList.remove('is-open');
    ide.saveCurrentFile();
  });

  // ===============================================================
  // NEW PROJECT / STARTUP WIZARD MODAL (Console, App, Web, Game)
  // ===============================================================
  const newProjectModal = document.getElementById('newProjectModal');
  const btnCloseModal = document.getElementById('btnCloseNewProjectModal');
  const btnCancelNewProject = document.getElementById('btnCancelNewProject');
  const btnModalStartBlank = document.getElementById('btnModalStartBlank');
  const btnModalOpenFolder = document.getElementById('btnModalOpenFolder');
  const btnConfirmCreateProject = document.getElementById('btnConfirmCreateProject');
  const inputProjectName = document.getElementById('inputProjectName');
  const selectProjectTemplate = document.getElementById('selectProjectTemplate');
  const archetypeCards = document.querySelectorAll('.archetype-card');

  let selectedArchetype = 'console';

  function openNewProjectModal() {
    if (newProjectModal) {
      newProjectModal.style.display = 'flex';
      setTimeout(() => inputProjectName?.focus(), 60);
    }
  }

  function closeNewProjectModal() {
    if (newProjectModal) {
      newProjectModal.style.display = 'none';
    }
  }

  // Archetype selection
  const defaultNames = {
    'console': 'my-cli-tool',
    'desktop': 'my-desktop-app',
    'web': 'my-web-app',
    'game': 'otter-game'
  };

  archetypeCards.forEach(card => {
    card.addEventListener('click', () => {
      archetypeCards.forEach(c => c.classList.remove('is-selected'));
      card.classList.add('is-selected');
      selectedArchetype = card.getAttribute('data-archetype') || 'console';
      if (inputProjectName && defaultNames[selectedArchetype]) {
        inputProjectName.value = defaultNames[selectedArchetype];
      }
    });
  });

  // Create Project action
  async function handleCreateProject() {
    try {
      const projName = (inputProjectName?.value || '').trim() || defaultNames[selectedArchetype] || 'my-app';
      const isMinimal = selectProjectTemplate?.value === 'minimal';
      const templateDef = StarterTemplates[selectedArchetype] || StarterTemplates['blank'];

      if (templateDef) {
        if (templateDef.load) {
          templateDef.load(uiModel);
        }
        if (cssAstManager && templateDef.css !== undefined) {
          cssAstManager.parse(templateDef.css);
        }

        const fileName = isMinimal ? 'main.ot' : (templateDef.defaultFileName || 'main.ot');
        let initialCode = isMinimal ? `# ${projName}\n\nsay "Hello from ${projName}!"\n` : templateDef.code;
        let initialCss = isMinimal ? '/* Otter Stylesheet */\n' : (templateDef.css || '');

        if (templateDef.load && uiModel.getRoot()) {
          initialCode = generateOtterSource(uiModel);
        }

        let projectFolder = `projects/${projName}`;
        let projectTree = [
          { name: fileName, path: fileName, isDir: false },
          { name: 'styles.css', path: 'styles.css', isDir: false },
          { name: 'project.json', path: 'project.json', isDir: false }
        ];

        // Call backend API to create real project directory and files on disk!
        try {
          const res = await fetch('/api/create-project', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              name: projName,
              archetype: selectedArchetype,
              fileName,
              code: initialCode,
              css: initialCss
            })
          });
          const data = await res.json();
          if (data.ok) {
            projectFolder = data.folder;
            projectTree = data.tree;
          }
        } catch (apiErr) {
          console.warn('Backend create-project failed, using local in-memory:', apiErr);
        }

        ide.currentProjectFolder = projectFolder;
        ide.currentProjectName = projName;
        ide.currentFile = `${projectFolder}/${fileName}`;
        ide.currentCode = initialCode;

        // Render real project tree in sidebar explorer!
        ide.renderProjectTree(projectTree, projName, projectFolder);

        // Update header title in project card
        const projTitleEl = document.getElementById('projectCardTitle');
        if (projTitleEl) projTitleEl.textContent = `Project: ${projName}`;

        const tabTitle = document.querySelector('.editor-tab.is-active .tab-title');
        if (tabTitle) tabTitle.innerText = fileName;

        ide.renderEditorCode(initialCode);
        ide.lintCurrentCode();
        syncCodeFromUiModel();

        // Ensure left sidebar shows the Files tab so project files are immediately visible!
        switchSidebarPane('files');

        // Route to optimal mode: 'split' lets user see BOTH designer and code!
        setMode(selectedArchetype === 'console' ? 'code' : 'split');
      }

      closeNewProjectModal();
    } catch (err) {
      console.error('Error creating project:', err);
      alert('Error creating project: ' + err.message);
    }
  }

  btnConfirmCreateProject?.addEventListener('click', handleCreateProject);
  btnCloseModal?.addEventListener('click', closeNewProjectModal);
  btnCancelNewProject?.addEventListener('click', closeNewProjectModal);
  btnModalStartBlank?.addEventListener('click', closeNewProjectModal);
  btnModalOpenFolder?.addEventListener('click', () => {
    closeNewProjectModal();
    ide.promptOpenFolder();
  });

  // Listen for custom trigger from ide or sidebar buttons
  window.addEventListener('otter:open-new-project', openNewProjectModal);

  // Keyboard Shortcuts: Ctrl+Shift+N for New Project, Escape to dismiss
  window.addEventListener('keydown', (e) => {
    if (e.ctrlKey && e.shiftKey && (e.key === 'N' || e.key === 'n')) {
      e.preventDefault();
      openNewProjectModal();
    } else if (e.key === 'Escape' && newProjectModal && newProjectModal.style.display === 'flex') {
      closeNewProjectModal();
    }
  });

  // Auto-open modal on fresh startup if no folder/project/file is set
  const hasSpecificTarget = urlParams.get('folder') || urlParams.get('project') || urlParams.get('file');
  if (!hasSpecificTarget) {
    openNewProjectModal();
  }
});

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}
