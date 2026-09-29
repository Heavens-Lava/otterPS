import { OtterUiModel } from './model/ui-model.js';
import { CssAstManager } from './compiler/css-ast.js';
import { StarterTemplates } from './templates/starter-templates.js';
import { generateOtterSource } from './compiler/otter-generator.js';
import { parseOtterSource } from './compiler/otter-parser.js';
import { snapshotDesign, spliceDesignIntoSource, designMatchesBaseline } from './compiler/source-splice.js';

import { renderToolbox } from './components/toolbox.js';
import { renderHierarchy } from './components/hierarchy.js';
import { renderCanvas } from './components/canvas.js';
import { renderProperties } from './components/properties.js';
import { renderEvents } from './components/events.js';
import { renderEditor } from './components/editor.js';
import { renderPreview } from './components/preview.js';
import { OtterStudioIde } from './ide.js';
import { StyleController } from './designer/style-context.js';
import { mountStudioShell } from './shell/studio-shell.js';
import { toRegistryCommands } from './designer/commands.js';
import { createViewState } from './designer/view-state.js';
import { TasksPanel } from './components/tasks-panel.js';
import { installExplorerActions } from './components/explorer-actions.js';
import { setWorkspaceTrust } from './project/workspace-solution.js';
import { SourceControlPanel } from './components/source-control.js';
import { TestExplorer } from './components/test-explorer.js';

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

  // The CSS model starts with the blank template's CSS and no file. Bind it
  // to the restored project's real stylesheet (ide.init ran before the
  // manager existed, so it could not do this itself).
  await ide.loadDesignerStylesheet();

  // Mount components
  const toolboxEl = document.getElementById('toolboxPanel');
  const hierarchyEl = document.getElementById('hierarchyPanel');
  const canvasEl = document.getElementById('canvasContainer');
  const centerWorkArea = document.getElementById('centerWorkArea');
  const propertiesEl = document.getElementById('propertiesContent');
  const eventsEl = document.getElementById('eventsContent');
  const editorEl = document.getElementById('editorContainer');
  const previewEl = document.getElementById('previewContainer');

  // One stylesheet belongs to the design: undo/redo snapshots include it, and
  // one StyleController routes every style edit (canvas and panel alike) to
  // the right place in the Otter source or styles.css.
  uiModel.attachStylesheet(cssAstManager);
  const styleController = new StyleController(uiModel, cssAstManager);
  window.otterStyles = styleController;

  // Designer-only hide/lock (Layers panel); never written to the program.
  const viewState = createViewState();
  window.otterViewState = viewState;
  uiModel.subscribe((type, detail) => {
    if (type === 'rename' && detail?.oldName) viewState.rename(detail.oldName, detail.newName);
  });

  // A project can define its own breakpoints in project.json:
  //   "designer": { "breakpoints": [ { "id": "base", "label": "Desktop", "media": "" },
  //     { "id": "dark", "label": "Dark", "media": "(prefers-color-scheme: dark)" }, ... ] }
  // Without them the designer uses Desktop / Tablet / Mobile.
  async function applyProjectBreakpoints() {
    let list = null;
    const folder = ide.currentProjectFolder;
    if (folder && !/\.(json|otter-workspace)$/i.test(folder)) {
      try {
        const res = await fetch(`/api/project-manifest?folder=${encodeURIComponent(folder)}`);
        if (res.ok) list = (await res.json()).manifest?.designer?.breakpoints || null;
      } catch { /* no manifest: defaults */ }
    }
    styleController.setBreakpoints(list);
  }
  const loadProjectTreeWithBreakpoints = ide.loadProjectTree.bind(ide);
  ide.loadProjectTree = async function (folder) {
    const result = await loadProjectTreeWithBreakpoints(folder);
    await applyProjectBreakpoints();
    return result;
  };
  // A restored session opened its project before this hook existed.
  if (ide.currentProjectFolder) applyProjectBreakpoints();

  renderToolbox(toolboxEl, uiModel);
  renderHierarchy(hierarchyEl, uiModel, cssAstManager, viewState);
  const designer = renderCanvas(canvasEl, uiModel, cssAstManager, styleController, viewState);
  renderProperties(propertiesEl, uiModel, cssAstManager, styleController);
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
  const btnPaneScm = document.getElementById('btnPaneScm');
  const paneScm = document.getElementById('paneScm');
  const paneFiles = document.getElementById('paneFiles');
  const paneToolbox = document.getElementById('paneToolbox');
  const paneHierarchy = document.getElementById('paneHierarchy');
  const paneSearch = document.getElementById('paneSearch');
  const sourceOutlinePanel = document.getElementById('sourceOutlinePanel');
  const designerHierarchyPanel = document.getElementById('hierarchyPanel');

  function setOutlineContext(mode) {
    const sourceMode = mode === 'code';
    // One sidebar tab: code symbols (Outline) in Code mode, the designer's
    // component tree (Layers) wherever the designer shows.
    const tabLabel = btnPaneHierarchy?.querySelector('span:last-child');
    if (tabLabel) tabLabel.textContent = sourceMode ? 'Outline' : 'Layers';
    if (btnPaneHierarchy) btnPaneHierarchy.title = sourceMode ? 'Outline (symbols in this file)' : 'Layers (components of the design)';
    if (sourceOutlinePanel) sourceOutlinePanel.style.display = sourceMode ? 'flex' : 'none';
    if (designerHierarchyPanel) designerHierarchyPanel.style.display = sourceMode ? 'none' : 'flex';
  }

  function switchSidebarPane(pane) {
    [btnPaneFiles, btnPaneToolbox, btnPaneHierarchy, btnPaneSearch, btnPaneScm].forEach(b => b?.classList.remove('is-active'));
    if (paneScm) paneScm.style.display = 'none';
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
    } else if (pane === 'scm') {
      btnPaneScm?.classList.add('is-active');
      if (paneScm) paneScm.style.display = 'flex';
      sourceControl.refresh();
    }
  }

  // Explorer: right-click menu, F2, Delete, drag to move (server/fs-ops.mjs).
  window.otterExplorer = installExplorerActions(ide);
  // A renamed or moved design file (or stylesheet) stays bound.
  window.addEventListener('otter:file-moved', (e) => {
    const { from, to } = e.detail || {};
    const follow = (p) => (p && (p === from || p.startsWith(`${from}/`)) ? to + p.slice(from.length) : p);
    designBinding.file = follow(designBinding.file);
    cssAstManager.sourcePath = follow(cssAstManager.sourcePath);
  });

  // Tasks tab: TODO / FIXME comments in the project.
  const tasksPanel = new TasksPanel(ide, document.getElementById('panelTasks'));
  tasksPanel.init();
  window.otterTasks = tasksPanel;

  // Tests tab in the bottom drawer, backed by `otter test`.
  const testExplorer = new TestExplorer(ide, document.getElementById('panelTests'));
  testExplorer.init();
  window.otterTestExplorer = testExplorer;
  window.addEventListener('otter:project-loaded', () => testExplorer.discover());
  // A project opened during ide.init() loaded before this listener existed.
  if (ide.currentProjectFolder) testExplorer.discover();

  // Source Control pane (Git), backed by the git command line.
  const sourceControl = new SourceControlPanel(ide, document.getElementById('scmRoot'));
  sourceControl.init();
  window.otterSourceControl = sourceControl;
  window.addEventListener('keydown', e => {
    // In the designer, Ctrl+Shift+G wraps the selection in a row (canvas.js
    // handles it first and marks the event); everywhere else it opens Git.
    if (e.defaultPrevented) return;
    if (e.ctrlKey && e.shiftKey && e.key.toLowerCase() === 'g') {
      e.preventDefault();
      switchSidebarPane('scm');
    }
  });

  btnPaneFiles?.addEventListener('click', () => switchSidebarPane('files'));
  btnPaneToolbox?.addEventListener('click', () => switchSidebarPane('toolbox'));
  btnPaneHierarchy?.addEventListener('click', () => switchSidebarPane('hierarchy'));
  btnPaneSearch?.addEventListener('click', () => switchSidebarPane('search'));
  btnPaneScm?.addEventListener('click', () => switchSidebarPane('scm'));
  window.addEventListener('otter:sidebar-pane', event => switchSidebarPane(event.detail));

  // ---------------------------------------------------------------
  // Designer <-> source binding
  // ---------------------------------------------------------------
  // The designer model always belongs to exactly one .ot file: the one it
  // was last read from. `baseline` is a snapshot of the model as that file
  // describes it. A designer change is written back by splicing the
  // difference (baseline -> model) into that file's text, so only the
  // statements the change affects are rewritten. See source-splice.js.
  //
  // Invariant: the designer never writes to any file except `designBinding.file`.
  const designBinding = { file: null, baseline: null };

  function bindDesign(file) {
    designBinding.file = file || null;
    viewState.setScope(designBinding.file);
    designBinding.baseline = uiModel.getRoot() ? snapshotDesign(uiModel) : null;
  }

  function writeDesignToSource() {
    const file = designBinding.file;
    if (!file || !file.endsWith('.ot')) return;
    if (designMatchesBaseline(designBinding.baseline, uiModel)) return;

    const isActive = ide.currentFile === file;
    const tab = ide.openTabs.find(t => t.path === file);
    if (!isActive && !tab) return; // the bound file was closed: nothing to write to

    const source = isActive ? ide.currentCode : tab.content;
    const next = spliceDesignIntoSource(source, designBinding.baseline, uiModel);
    designBinding.baseline = snapshotDesign(uiModel);
    if (next === source) return;

    if (isActive) {
      ide.currentCode = next;
      const textarea = document.getElementById('hiddenEditorInput');
      if (textarea) textarea.value = next;
      if (ide.codeAreaEl) ide.renderEditorCode(next);
      ide.markCurrentTabDirty(true);
    } else {
      tab.content = next;
      tab.isDirty = true;
      ide.renderTabs();
    }
    ide.saveSessionState();
    showLiveCode();
  }

  // The "Live Code" drawer shows the bound file's real text.
  // Numbered, highlighted lines; double-click one to open it in the editor.
  function showLiveCode() {
    const liveCodeArea = document.getElementById('drawerGeneratedCodeArea');
    if (!liveCodeArea) return;
    const file = designBinding.file;
    const tab = ide.openTabs.find(t => t.path === file);
    const text = file === ide.currentFile ? ide.currentCode : (tab ? tab.content : generateOtterSource(uiModel));
    liveCodeArea.dataset.source = text || '';
    liveCodeArea.innerHTML = String(text || '').replace(/\r\n/g, '\n').replace(/\n$/, '').split('\n').map((line, i) =>
      `<div class="lc-line" data-line="${i + 1}"><span class="lc-num">${i + 1}</span><span class="lc-text">${ide.syntaxHighlightLine(line) || ' '}</span></div>`
    ).join('');
    const fileLabel = document.getElementById('liveCodeFile');
    if (fileLabel) fileLabel.textContent = file ? file.split('/').pop() : 'Otter source';
  }

  function openLiveCodeInEditor(line = 1) {
    const file = designBinding.file;
    if (!file) return;
    setMode('code');
    ide.navigateToLocation({ path: file, line, column: 0 });
  }
  document.getElementById('btnLiveCodeOpen')?.addEventListener('click', () => openLiveCodeInEditor(1));
  document.getElementById('drawerGeneratedCodeArea')?.addEventListener('dblclick', (e) => {
    const row = e.target.closest('.lc-line');
    if (row) openLiveCodeInEditor(Number(row.dataset.line));
  });

  // Designer style edits (properties panel, canvas resize) change the CSS
  // model. When the project's stylesheet is open in a tab, hand the new text
  // to that tab as an unsaved edit; otherwise saveDesignerStylesheet writes
  // it (with its revision) on the next save.
  window.addEventListener('css-updated', event => {
    const origin = event.detail?.source;
    if (origin === 'editor' || origin === 'disk') return;
    const sheetPath = cssAstManager.sourcePath;
    if (!sheetPath || !cssAstManager.dirty) return;
    const tab = ide.openTabs.find(t => t.path === sheetPath);
    if (!tab) return;
    const css = cssAstManager.generateCss();
    if (ide.currentFile === sheetPath) {
      ide.currentCode = css;
      const textarea = document.getElementById('hiddenEditorInput');
      if (textarea) textarea.value = css;
      if (ide.codeAreaEl) ide.renderEditorCode(css);
      ide.markCurrentTabDirty(true);
    } else {
      tab.content = css;
      tab.isDirty = true;
      ide.renderTabs();
    }
    cssAstManager.dirty = false; // the tab owns the unsaved text now
    ide.saveSessionState();
  });

  let sourceSyncTimer = null;
  let sourceSyncRevision = 0;

  async function syncUiFromSource(source, immediate = false, file = ide.currentFile) {
    const revision = ++sourceSyncRevision;
    if (sourceSyncTimer) clearTimeout(sourceSyncTimer);

    const apply = async () => {
      if (revision !== sourceSyncRevision) return;

      // Empty source is a valid empty design, not a reason to retain stale UI.
      if (!source || !source.trim()) {
        parseOtterSource('', uiModel);
        bindDesign(file);
        return;
      }

      // Re-reading the source rebuilds every component with a new id; keep
      // the selection by name so typing in the code pane or switching files
      // does not throw the designer back to the window.
      const selectedNames = [...uiModel.selectedIds]
        .filter(id => id !== uiModel.selectedId)
        .concat(uiModel.selectedId ? [uiModel.selectedId] : [])
        .map(id => uiModel.getComponent(id)?.name)
        .filter(Boolean);

      // The browser-side UI reader only mutates the model after it has found
      // a complete window declaration, so incomplete edits keep the last
      // valid visual tree while the user is typing.
      if (parseOtterSource(source, uiModel)) {
        bindDesign(file);
        if (selectedNames.length) {
          const byName = new Map(uiModel.getAllComponents().map(c => [c.name, c.id]));
          const ids = selectedNames.map(n => byName.get(n)).filter(Boolean);
          if (ids.length && !(ids.length === 1 && ids[0] === uiModel.selectedId)) uiModel.selectMany(ids);
        }
        window.dispatchEvent(new CustomEvent('otter:source-synced', {
          detail: { source }
        }));
        return;
      }

      // Not (yet) a UI. If the model still shows a different file's design,
      // unbind it now so no designer click can write that design here.
      if (designBinding.file !== file) {
        uiModel.clearFromSource();
        bindDesign(file);
        return;
      }

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
          bindDesign(file);
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
    const source = event.detail?.source ?? '';
    const file = event.detail?.file ?? ide.currentFile;
    if (event.detail?.origin === 'component-editor') {
      // That editor only edits Otter source; never let it overwrite a
      // stylesheet or JSON file that happens to be the active tab.
      if (ide.currentFile && !ide.currentFile.endsWith('.ot')) return;
      ide.currentCode = source;
      const activeTab = ide.openTabs.find(tab => tab.path === ide.currentFile);
      if (activeTab) {
        activeTab.content = source;
        activeTab.isDirty = true;
      }
      ide.saveSessionState();
    }
    if (file && file.endsWith('.css')) {
      // Only the designer's own stylesheet may replace its CSS model.
      if (cssAstManager && file === cssAstManager.sourcePath) {
        try {
          cssAstManager.parse(source);
          const styleTag = document.getElementById('canvasUserCss');
          if (styleTag) {
            styleTag.textContent = cssAstManager.generateCss();
          }
        } catch (e) {
          console.warn('CSS AST manager parse failed:', e);
        }
      }
      window.dispatchEvent(new CustomEvent('otter:source-synced', { detail: { source, file } }));
    } else if (!file || file.endsWith('.ot')) {
      syncUiFromSource(source, false, file);
    }
  });

  // A different tab became active. A .ot tab becomes the designer's file;
  // for other files the designer stays bound to its .ot file.
  window.addEventListener('otter:active-file-changed', event => {
    const file = event.detail?.file;
    if (file && file.endsWith('.ot') && file !== designBinding.file) {
      syncUiFromSource(event.detail.source ?? '', true, file);
    }
  });

  // A style edit made in the designer is unsaved work: mark the active file
  // dirty, and keep any open styles.css tab in step so switching to it (which
  // re-reads the tab into the CSS engine) never discards designer edits.
  const DESIGNER_CSS_SOURCES = new Set(['style', 'properties', 'resize', 'drop', 'rename']);
  window.addEventListener('css-updated', (event) => {
    if (!DESIGNER_CSS_SOURCES.has(event.detail?.source)) return;
    const css = cssAstManager.generateCss();
    let touched = false;
    for (const tab of ide.openTabs) {
      if (tab.path && tab.path.endsWith('.css') && tab.path !== ide.currentFile && tab.content !== css) {
        tab.content = css;
        tab.isDirty = true;
        touched = true;
      }
    }
    const active = ide.openTabs.find(tab => tab.path === ide.currentFile);
    if (active && !active.isDirty) {
      active.isDirty = true;
      touched = true;
    }
    if (touched) ide.renderTabs();
  });

  // Style provenance "Go to source": open the .ot file at the component's
  // declaration, or styles.css at the rule (inside the right @media block),
  // with the cursor on the property when it can be found.
  window.addEventListener('otter:reveal-style-source', async (event) => {
    const { location, prop } = event.detail || {};
    if (!location) return;
    const escapeRe = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    // Show code beside the designer first; switching layout later would
    // reset the editor's scroll position.
    if (!centerWorkArea.classList.contains('is-split')) setMode('split');
    if (location.file === 'source') {
      const path = designBinding.file; // the one .ot file the designer shows
      if (!path) return;
      await ide.loadFile(path);
      const lines = ide.currentCode.split('\n');
      const decl = new RegExp(`^\\s*${escapeRe(location.component)}\\s+is\\s+an?\\s`);
      const index = lines.findIndex(l => decl.test(l));
      if (index < 0) return;
      const keyMatch = location.key ? lines[index].match(new RegExp(`\\b${escapeRe(location.key)}\\b`)) : null;
      await ide.navigateToLocation({ path, line: index + 1, column: keyMatch ? keyMatch.index : 0 });
    } else if (location.file === 'styles.css' && cssAstManager.sourcePath) {
      const path = cssAstManager.sourcePath;
      await ide.loadFile(path);
      const lines = ide.currentCode.split('\n');
      let start = 0;
      let end = lines.length;
      if (location.media) {
        const norm = (s) => s.replace(/\s+/g, '');
        const m = lines.findIndex(l => /^\s*@media\b/.test(l) && norm(l).includes(norm(location.media)));
        if (m >= 0) {
          start = m + 1;
          let depth = 0;
          for (let i = m; i < lines.length; i++) {
            depth += (lines[i].match(/\{/g) || []).length - (lines[i].match(/\}/g) || []).length;
            if (depth <= 0 && i > m) { end = i; break; }
          }
        }
      }
      const ruleRe = new RegExp(`(^|[\\s,])${escapeRe(location.selector)}\\s*(,|\\{|$)`);
      let line = -1;
      for (let i = start; i < end; i++) {
        if (ruleRe.test(lines[i])) { line = i; break; }
      }
      if (line < 0) return ide.navigateToLocation({ path, line: 1, column: 0 });
      let column = 0;
      if (prop) {
        const propRe = new RegExp(`(^|[\\s;{])${escapeRe(prop)}\\s*:`);
        for (let i = line; i < end; i++) {
          const hit = lines[i].match(propRe);
          if (hit) { line = i; column = hit.index + hit[1].length; break; }
          if (i > line && /\}/.test(lines[i])) break;
        }
      }
      await ide.navigateToLocation({ path, line: line + 1, column });
    }
  });

  uiModel.subscribe((changeType) => {
    if (changeType === 'parse' || changeType === 'source-clear') {
      showLiveCode();
      return;
    }
    // Selecting a control never changes the file. Everything else goes
    // through the splicer, which writes nothing if the design is unchanged.
    if (changeType === 'select') return;
    writeDesignToSource();
  });

  // Reconcile the file loaded during IDE initialization. This listener is
  // installed after init, so the initial source needs one explicit pass.
  syncUiFromSource(ide.currentCode, true, ide.currentFile);

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
      const panelTests = document.getElementById('panelTests');
      const panelTasks = document.getElementById('panelTasks');
      if (panelTasks) {
        panelTasks.style.display = tabName === 'tasks' ? 'flex' : 'none';
        if (tabName === 'tasks') tasksPanel.refresh();
      }

      if (panelTests) {
        panelTests.style.display = tabName === 'tests' ? 'flex' : 'none';
        if (tabName === 'tests' && testExplorer.tests.length === 0) testExplorer.discover();
      }
      if (panelProb) panelProb.style.display = tabName === 'problems' ? 'flex' : 'none';
      if (panelOut) panelOut.style.display = tabName === 'output' ? 'block' : 'none';
      if (panelTerm) panelTerm.style.display = tabName === 'terminal' ? 'flex' : 'none';
      if (panelLive) {
        panelLive.style.display = tabName === 'livecode' ? 'block' : 'none';
        if (tabName === 'livecode') {
          showLiveCode();
        }
      }
    });
  });

  document.getElementById('btnCopyLiveCode')?.addEventListener('click', () => {
    const code = document.getElementById('drawerGeneratedCodeArea')?.dataset.source || '';
    if (code) {
      navigator.clipboard.writeText(code);
      const btn = document.getElementById('btnCopyLiveCode');
      if (btn) {
        btn.textContent = 'Copied!';
        setTimeout(() => btn.textContent = 'Copy', 1500);
      }
    }
  });

  // Mode Switcher Pills: Code | UI Designer | Split | Live App
  const modePills = document.querySelectorAll('.mode-pill');

  function setMode(mode) {
    document.body.dataset.studioMode = mode;
    // Designer: the drawer's left half shows this source (css/polish.css).
    if (mode === 'designer') {
      showLiveCode();
      const active = document.querySelector('.drawer-tab.is-active');
      if (!active || active.getAttribute('data-drawer-tab') === 'livecode') {
        document.querySelector('.drawer-tab[data-drawer-tab="output"]')?.click();
      }
    }
    centerWorkArea.classList.toggle('is-split', mode === 'split');
    centerWorkArea.classList.toggle('is-workbench', mode === 'workbench');
    modePills.forEach(p => p.classList.remove('is-active'));
    const activePill = document.getElementById(`pill${capitalize(mode)}Mode`);
    if (activePill) activePill.classList.add('is-active');

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

      if (!ide.currentFile || ide.currentFile.endsWith('.ot')) {
        syncUiFromSource(ide.currentCode, true, ide.currentFile);
      }
    } else if (mode === 'split') {
      setOutlineContext('designer');
      codeEditorView.style.display = 'flex';
      canvasEl.style.display = 'flex';
      editorEl.style.display = 'none';
      previewEl.style.display = 'none';

      codeRightSidebar.style.display = 'none';
      designerRightSidebar.style.display = 'flex';
      bottomDrawer.style.display = 'none';

      if (!ide.currentFile || ide.currentFile.endsWith('.ot')) {
        syncUiFromSource(ide.currentCode, true, ide.currentFile);
      }
    } else if (mode === 'workbench') {
      setOutlineContext('designer');
      codeEditorView.style.display = 'flex';
      canvasEl.style.display = 'flex';
      editorEl.style.display = 'none';
      previewEl.style.display = 'none';

      codeRightSidebar.style.display = 'none';
      designerRightSidebar.style.display = 'flex';
      bottomDrawer.style.display = 'flex';

      if (!ide.currentFile || ide.currentFile.endsWith('.ot')) {
        syncUiFromSource(ide.currentCode, true, ide.currentFile);
      }
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

  // Ensure code editor is visible when opening/activating files
  window.addEventListener('otter:ensure-editor-visible', () => {
    const activePill = document.querySelector('.mode-pill.is-active');
    if (activePill && (activePill.id === 'pillDesignerMode' || activePill.id === 'pillPreviewMode')) {
      setMode('code');
    }
  });

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
  // The menu bar (js/shell/menu-bar.js) is mounted by the studio shell and
  // runs registered commands.

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
      showCreateError('');
      suggestProjectName(defaultNames[selectedArchetype] || inputProjectName?.value || 'my-app');
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
        showCreateError('');
        suggestProjectName(defaultNames[selectedArchetype]);
      }
    });
  });

  // Create Project action
  // Problems creating a project show inside the dialog, next to the name.
  function showCreateError(message, existingFolder = null) {
    let box = document.getElementById('newProjectError');
    if (!box) {
      box = document.createElement('div');
      box.id = 'newProjectError';
      box.className = 'new-project-error';
      box.setAttribute('role', 'alert');
      document.querySelector('.project-config-section')?.after(box);
    }
    box.hidden = !message;
    box.innerHTML = message
      ? `<span>${message.replace(/</g, '&lt;')}</span>${existingFolder ? ' <button type="button" class="btn-modal-link" id="btnOpenExistingProject">Open it instead</button>' : ''}`
      : '';
    box.querySelector('#btnOpenExistingProject')?.addEventListener('click', async () => {
      closeNewProjectModal();
      await ide.loadProjectTree(existingFolder);
    });
    if (message) inputProjectName?.focus();
  }

  // Offer a name that is not taken yet whenever the archetype changes.
  async function suggestProjectName(base) {
    const asked = inputProjectName?.value;
    try {
      const res = await fetch(`/api/suggest-project-name?name=${encodeURIComponent(base)}`);
      const data = await res.json();
      // Never replace a name the user typed while the answer was on its way.
      if (data.name && inputProjectName && inputProjectName.value === asked) inputProjectName.value = data.name;
    } catch { /* keep the typed name */ }
  }

  async function handleCreateProject() {
    try {
      const projName = (inputProjectName?.value || '').trim() || defaultNames[selectedArchetype] || 'my-app';
      const isMinimal = selectProjectTemplate?.value === 'minimal';
      const templateDef = StarterTemplates[selectedArchetype] || StarterTemplates['blank'];

      // Opening the new project replaces the open tabs; never drop unsaved
      // work without asking.
      const unsaved = ide.openTabs.filter(t => t.isDirty);
      if (unsaved.length > 0 && !confirm(`These tabs have unsaved changes and will be closed: ${unsaved.map(t => t.name).join(', ')}.\n\nDiscard the changes and create the project?`)) {
        return;
      }

      if (templateDef) {
        // Build the template in a throwaway model. Loading it into the live
        // model would notify the designer, which is still bound to the file
        // that is open now, and splice the template into that file. The live
        // model and CSS model are re-read from the new files below.
        const templateModel = new OtterUiModel();
        if (templateDef.load) {
          templateDef.load(templateModel);
        }

        const fileName = isMinimal ? 'main.ot' : (templateDef.defaultFileName || 'main.ot');
        let initialCode = isMinimal ? `# ${projName}\n\nsay "Hello from ${projName}!"\n` : templateDef.code;
        let initialCss = isMinimal ? '/* Otter Stylesheet */\n' : (templateDef.css || '');

        if (templateDef.load && templateModel.getRoot()) {
          initialCode = generateOtterSource(templateModel);
        }

        // Create the project on disk. A name that is taken is reported in the
        // dialog; nothing is overwritten, and nothing continues with an
        // in-memory copy whose first save could replace another project.
        showCreateError('');
        btnConfirmCreateProject.disabled = true;
        let created;
        try {
          const res = await fetch('/api/create-project', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              name: projName,
              archetype: selectedArchetype,
              fileName,
              code: initialCode,
              css: initialCss,
              gitignore: document.getElementById('chkProjectGitignore')?.checked !== false
            })
          });
          created = await res.json().catch(() => ({}));
          if (!res.ok || !created.ok) {
            showCreateError(created.error || `The project could not be created (HTTP ${res.status}).`, created.exists ? created.folder : null);
            return;
          }
        } catch (apiErr) {
          showCreateError(`The Studio service could not be reached: ${apiErr.message}`);
          return;
        } finally {
          btnConfirmCreateProject.disabled = false;
        }
        const data = created;
        // Studio wrote every file in it from its own template: nothing to distrust.
        setWorkspaceTrust(data.folder, true);

        const projectFolder = data.folder;
        const filePath = `${projectFolder}/${fileName}`;
        ide.currentProjectFolder = projectFolder;
        ide.currentProjectName = projName;
        ide.openTabs = [];
        ide.currentFile = null;

        // Render real project tree in sidebar explorer!
        ide.renderProjectTree(data.tree, projName, projectFolder);

        // Update header title in project card
        const projTitleEl = document.getElementById('projectCardTitle');
        if (projTitleEl) projTitleEl.textContent = `Project: ${projName}`;

        // Open the files through the normal path so each carries its disk
        // revision; loading the .ot also binds the designer to it.
        await ide.loadFile(filePath);
        await ide.loadDesignerStylesheet();

        closeNewProjectModal();

        // Open it exactly like File > Open: the tree, the project chip,
        // Recent Projects, and the Welcome page all follow from this path.
        await ide.loadProjectTree(projectFolder);
        await ide.navigateToLocation({ path: filePath, line: 1, column: 0 });

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

  // Opening Studio without a folder or file to open shows the Start window
  // (recent projects, New Project, Open Folder, Continue without code), as
  // Visual Studio does - unless Settings turn it off (then the last session
  // was restored).
  const hasSpecificTarget = urlParams.get('folder') || urlParams.get('project') || urlParams.get('file');
  mountStudioShell({
    ide,
    setMode,
    openNewProjectModal,
    showStart: !hasSpecificTarget && !ide.startupRestoresSession()
  });
  // Designer commands (keyboard, context menu) also appear in the command
  // palette and the Keyboard Shortcuts dialog while the designer is showing.
  window.otterCommands?.registerAll(toRegistryCommands(designer.commands, () => designer.isDesignerVisible()));
});

function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}
