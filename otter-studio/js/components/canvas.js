// canvas.js - Visual Designer Canvas.
//
// The canvas renders the Otter UI model as real DOM, styled by the real
// compiler's stylesheet (see real-style.js) plus the live styles.css. A
// separate overlay layer draws everything the designer adds on top: selection
// boxes, resize handles, spacing handles, drop markers, grid tracks, smart
// guides and the marquee. The application DOM never contains designer chrome.
//
// Layout is structural: dropping reorders or reparents in the model, and flow
// elements are never given hidden left/top. Free positioning happens only for
// elements whose CSS says position: absolute/fixed.

import { ComponentSchema } from '../model/schema.js';
import { generateOtterSource } from '../compiler/otter-generator.js';
import { fetchRealRender, applyRealRender, prepareUserCss } from './real-style.js';
import { StyleController } from '../designer/style-context.js';
import { collapseBox, SIDES, formatNumber } from '../designer/css-values.js';
import { createDesignerActions, FREE_DEFAULT_SIZES } from '../designer/actions.js';
import { designerCommands, installDesignerKeyboard } from '../designer/commands.js';
import { createDesignerContextMenu } from '../designer/context-menu.js';
import { snapMove, snapResize } from '../designer/snapping.js';

// --otter-layout: free marks a Free layout container. Custom properties
// inherit, so without this every row, column and card inside a Free window
// would read as Free too (and a button dropped into a column was placed at
// x / y instead of taking its place in the column). Registered as not
// inheriting, each container reports only its own layout. Compiled apps do
// not read the marker, so only Studio needs this.
try {
  if (typeof CSS !== 'undefined' && CSS.registerProperty) CSS.registerProperty({ name: '--otter-layout', syntax: '*', inherits: false });
} catch { /* already registered */ }

const ZOOM_STEPS = [0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 2, 3];
const DESKTOP_WIDTH = 1280;
const SNAP_PX = 6;

export function renderCanvas(containerEl, uiModel, cssAstManager, styleController = null, viewState = null) {
  const styles = styleController || new StyleController(uiModel, cssAstManager);

  let currentDraggedComponentId = null;
  let currentHit = null;
  let isInteractMode = false;
  let realRender = null;
  let realRenderTimer = null;
  let realRenderSerial = 0;
  let zoom = 1;
  let spaceHeld = false;
  let gestureActive = false; // resize / spacing drag / free move in progress

  // Elements created once in mount().
  let viewportEl, stageEl, overlayEl, selectionLayer, guidesLayer, gridLayer, hoverBox, hoverBadge,
    targetBox, targetBadge, insertionLine, cellBox, marqueeEl, userStyleEl, topbarEl, freeGhost, freeGhostLabel;
  // The Components tile being dragged (its kind), for the Free drop preview.
  let draggingNewKind = null;

  // ---------------------------------------------------------------------------
  // Mounting (once)
  // ---------------------------------------------------------------------------

  function mount() {
    containerEl.innerHTML = `
      <style id="canvasUserCss"></style>
      <div class="canvas-topbar" id="canvasTopbar">
        <div class="canvas-breadcrumbs" id="canvasBreadcrumbs"></div>
        <div class="canvas-actions">
          <div class="canvas-device-toggle" role="group" aria-label="Breakpoint" id="canvasDeviceToggle">${deviceButtonsHtml()}</div>
          <div class="canvas-zoom" role="group" aria-label="Zoom">
            <button class="icon-btn" data-zoom="out" title="Zoom out (Ctrl -)">−</button>
            <button class="canvas-zoom-label" data-zoom="reset" id="canvasZoomLabel" title="Reset to 100% (Ctrl 0)">100%</button>
            <button class="icon-btn" data-zoom="in" title="Zoom in (Ctrl +)">+</button>
            <button class="canvas-zoom-fit" data-zoom="fit" title="Fit to view (Shift 1)">Fit</button>
          </div>
          <div class="canvas-mode-toggle">
            <button class="canvas-toggle-btn" id="btnCanvasDesignMode" title="Design: select, drag, resize and style">Design</button>
            <button class="canvas-toggle-btn" id="btnCanvasInteractMode" title="Interact: click buttons and type like a user">Interact</button>
          </div>
          <button class="icon-btn" id="canvasUndoBtn" title="Undo (Ctrl+Z)">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 7v6h6M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/></svg>
          </button>
          <button class="icon-btn" id="canvasRedoBtn" title="Redo (Ctrl+Y)">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 7v6h-6M3 17a9 9 0 0 1 9-9 9 9 0 0 1 6 2.3L21 13"/></svg>
          </button>
        </div>
      </div>
      <div class="canvas-viewport" id="canvasViewport" tabindex="-1">
        <div class="canvas-stage" id="canvasStage"></div>
        <div class="designer-canvas-overlay" id="designerOverlay">
          <div class="designer-grid-layer" id="designerGridLayer"></div>
          <div id="designerSelectionContainer"></div>
          <div class="designer-guides-layer" id="designerGuidesLayer"></div>
          <div class="designer-hover-box" id="designerHoverBox" hidden>
            <span class="designer-hover-badge" id="designerHoverBadge"></span>
          </div>
          <div class="designer-target-box" id="designerTargetBox" hidden>
            <span class="designer-target-badge" id="designerTargetBadge"></span>
          </div>
          <div class="designer-cell-box" id="designerCellBox" hidden></div>
          <div class="designer-insertion-line" id="designerInsertionLine" hidden>
            <div class="line-dot dot-start"></div>
            <div class="line-dot dot-end"></div>
          </div>
          <div class="designer-marquee" id="designerMarquee" hidden></div>
          <div class="designer-free-ghost" id="designerFreeGhost" hidden><span class="designer-free-ghost-label" id="designerFreeGhostLabel"></span></div>
        </div>
      </div>
    `;

    userStyleEl = containerEl.querySelector('#canvasUserCss');
    topbarEl = containerEl.querySelector('#canvasTopbar');
    viewportEl = containerEl.querySelector('#canvasViewport');
    stageEl = containerEl.querySelector('#canvasStage');
    overlayEl = containerEl.querySelector('#designerOverlay');
    selectionLayer = containerEl.querySelector('#designerSelectionContainer');
    guidesLayer = containerEl.querySelector('#designerGuidesLayer');
    gridLayer = containerEl.querySelector('#designerGridLayer');
    hoverBox = containerEl.querySelector('#designerHoverBox');
    hoverBadge = containerEl.querySelector('#designerHoverBadge');
    targetBox = containerEl.querySelector('#designerTargetBox');
    targetBadge = containerEl.querySelector('#designerTargetBadge');
    insertionLine = containerEl.querySelector('#designerInsertionLine');
    cellBox = containerEl.querySelector('#designerCellBox');
    marqueeEl = containerEl.querySelector('#designerMarquee');
    freeGhost = containerEl.querySelector('#designerFreeGhost');
    freeGhostLabel = containerEl.querySelector('#designerFreeGhostLabel');

    bindTopbar();
    bindViewport();
    bindKeyboard();
  }

  function bindTopbar() {
    // Delegated: the buttons are rebuilt when the project's breakpoints change.
    topbarEl.querySelector('#canvasDeviceToggle').addEventListener('click', (e) => {
      const btn = e.target.closest('[data-device]');
      if (btn) styles.setContext({ breakpoint: btn.getAttribute('data-device') });
    });
    window.addEventListener('otter:breakpoints', () => {
      topbarEl.querySelector('#canvasDeviceToggle').innerHTML = deviceButtonsHtml();
      renderTopbarState();
    });
    topbarEl.querySelectorAll('[data-zoom]').forEach(btn => btn.addEventListener('click', () => {
      const action = btn.getAttribute('data-zoom');
      if (action === 'in') zoomBy(1);
      else if (action === 'out') zoomBy(-1);
      else if (action === 'reset') setZoom(1);
      else zoomToFit();
    }));
    topbarEl.querySelector('#btnCanvasDesignMode').addEventListener('click', () => {
      if (isInteractMode) { isInteractMode = false; update(); }
    });
    topbarEl.querySelector('#btnCanvasInteractMode').addEventListener('click', () => {
      if (!isInteractMode) { isInteractMode = true; update(); }
    });
    topbarEl.querySelector('#canvasUndoBtn').addEventListener('click', () => uiModel.undo());
    topbarEl.querySelector('#canvasRedoBtn').addEventListener('click', () => uiModel.redo());
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  // One button per breakpoint (styles.breakpoints: the project's own or the defaults).
  function deviceButtonsHtml() {
    return styles.breakpoints.map(b => `<button class="canvas-device-btn" data-device="${escapeHtml(b.id)}" title="${escapeHtml(`${b.label} — ${b.hint}${b.width ? ` (previewed at ${b.width}px)` : ''}`)}">${escapeHtml(b.label)}</button>`).join('');
  }

  // The environment the canvas previews: width plus media features such as
  // a dark color scheme, so @media rules follow the design, not Studio's window.
  function deviceEnv() {
    styles.desktopWidth = DESKTOP_WIDTH;
    return styles.envFor(styles.breakpoint);
  }

  function update() {
    const root = uiModel.getRoot();
    importantCache = new Map();
    renderTopbarState();
    if (!root) {
      stageEl.innerHTML = '<div class="empty-state">No active window</div>';
      clearOverlay();
      return;
    }

    const bp = styles.breakpoint;
    stageEl.style.zoom = String(zoom);
    stageEl.innerHTML = `
      <div class="canvas-window-wrapper otter-window ${bp.width ? 'is-device' : ''} ${uiModel.isSelected(root.id) && !isInteractMode ? 'is-selected-window' : ''}"
        id="canvasWindowWrapper" ${bp.width ? `style="width:${bp.width}px"` : ''} data-device="${bp.id}">
        <div class="window-titlebar">
          <div class="window-dots">
            <span class="dot dot-red"></span>
            <span class="dot dot-yellow"></span>
            <span class="dot dot-green"></span>
          </div>
          <span class="window-title-text" id="canvasWindowTitleText">${escapeHtml(root.properties.title || 'Otter Application')}</span>
          <span class="window-dimension-badge" id="canvasDimensionBadge"></span>
        </div>
        <div class="window-content-area" id="${escapeHtml(root.name)}" data-id="${root.id}"></div>
      </div>
    `;

    const wrapper = stageEl.querySelector('#canvasWindowWrapper');
    const contentArea = wrapper.querySelector('.window-content-area');
    const titleTextEl = wrapper.querySelector('#canvasWindowTitleText');

    if (!isInteractMode) {
      titleTextEl.style.cursor = 'text';
      titleTextEl.title = 'Double-click to edit title';
      titleTextEl.addEventListener('dblclick', (e) => {
        e.stopPropagation();
        startInlineEdit(titleTextEl, root, 'title');
      });
      // A click anywhere on the title bar (the title too) selects the window;
      // a double-click on the title renames it. Selecting does not rebuild the
      // canvas, so the double-click still reaches the title.
      wrapper.querySelector('.window-titlebar').addEventListener('click', (e) => {
        uiModel.select(root.id, e.ctrlKey || e.metaKey || e.shiftKey);
      });
    }

    if (root.children && root.children.length > 0) {
      root.children.forEach((childId, i) => {
        const child = uiModel.getComponent(childId);
        if (child) contentArea.appendChild(renderCanvasComponent(child, root.id, i));
      });
    } else {
      const promptEl = document.createElement('div');
      promptEl.className = 'empty-canvas-prompt';
      // Whether the window is in Free layout shows once its styles are on.
      promptEl.innerHTML = `
        <span class="prompt-title">Drag controls here from Components</span>
        <span class="prompt-desc prompt-flow">They stack top to bottom. Rows and columns arrange things; cards group them.</span>
        <span class="prompt-desc prompt-free">Drop them where you want them; drag to move, pull the handles to resize. Rows, columns and cards arrange what you put inside them.</span>
      `;
      contentArea.appendChild(promptEl);
    }

    // Reuse the last real render right away so the canvas never flashes its
    // own approximation, then refresh it from the production compiler. Until
    // the first one arrives (starting the compiler can take seconds), the
    // source's own sizes apply, so a form is already the right shape.
    if (realRender) applyRealRenderNow(contentArea);
    else applySourceInline(contentArea);
    refreshUserStyles();
    applyForcedState();
    scheduleRealRender();
    applyViewState();
    renderBreadcrumbs();
    updateOverlay();
  }

  function renderTopbarState() {
    const bp = styles.breakpoint;
    topbarEl.querySelectorAll('[data-device]').forEach(btn => {
      btn.classList.toggle('is-active', btn.getAttribute('data-device') === bp.id);
    });
    topbarEl.querySelector('#canvasZoomLabel').textContent = `${Math.round(zoom * 100)}%`;
    topbarEl.querySelector('#btnCanvasDesignMode').classList.toggle('is-active', !isInteractMode);
    topbarEl.querySelector('#btnCanvasInteractMode').classList.toggle('is-active', isInteractMode);
    const undo = topbarEl.querySelector('#canvasUndoBtn');
    const redo = topbarEl.querySelector('#canvasRedoBtn');
    undo.disabled = !uiModel.canUndo() || isInteractMode;
    redo.disabled = !uiModel.canRedo() || isInteractMode;
    overlayEl.hidden = isInteractMode;
    viewportEl.classList.toggle('is-interact-mode', isInteractMode);
  }

  // The live styles.css, scoped to the canvas and evaluated for the device width.
  function refreshUserStyles() {
    const userCss = cssAstManager ? cssAstManager.generateCss() : '';
    userStyleEl.textContent = prepareUserCss(userCss, '#canvasWindowWrapper', deviceEnv());
    updateDimensionBadge();
  }

  function applyRealRenderNow(contentArea) {
    applyRealRender(contentArea, realRender, deviceEnv());
    applySourceInline(contentArea, realRender.sourceInline);
  }

  // Otter source values (width 300, padding 28, size 24) are applied inline by
  // the compiler. The real render reflects the source as it was when it was
  // compiled, so bring them up to date now instead of waiting for the next
  // render: set the current ones, and drop ones that have since left the
  // source (moved to styles.css), which would otherwise mask the new rule.
  function applySourceInline(contentArea, renderedWith = new Map()) {
    for (const comp of uiModel.getAllComponents()) {
      const el = comp.id === uiModel.rootId ? contentArea : contentArea.querySelector(`[data-id="${cssEscape(comp.id)}"]`);
      if (!el) continue;
      const now = styles.sourceInline(comp);
      for (const prop of renderedWith.get(comp.name) || []) {
        if (!(prop in now)) el.style.removeProperty(prop);
      }
      for (const [prop, value] of Object.entries(now)) el.style.setProperty(prop, value);
    }
    applyViewState();
  }

  // Layers panel hide/lock (designer/view-state.js): classes on canvas elements only.
  function isLocked(comp) {
    return Boolean(viewState && comp && viewState.isLocked(comp.name));
  }

  // A click on a locked component goes to its nearest unlocked ancestor.
  function unlockedAncestor(comp) {
    let current = comp;
    while (current && current.id !== uiModel.rootId && isLocked(current)) current = uiModel.getComponent(current.parentId);
    return current || uiModel.getRoot();
  }

  function applyViewState() {
    if (!viewState) return;
    for (const comp of uiModel.getAllComponents()) {
      if (comp.id === uiModel.rootId) continue;
      const el = elementFor(comp.id);
      if (!el) continue;
      el.classList.toggle('is-designer-hidden', viewState.isHidden(comp.name));
      el.classList.toggle('is-designer-locked', viewState.isLocked(comp.name));
      el.draggable = !viewState.isLocked(comp.name);
    }
  }

  // Does the compiler's own stylesheet set `cssProp` on this component with
  // !important? Then a styles.css rule needs !important too, or it would
  // never show in the compiled app (e.g. a primary button's background).
  const LONGHANDS = {
    background: ['background-color', 'background-image'],
    border: ['border-top-width', 'border-top-style', 'border-top-color'],
    'border-radius': ['border-top-left-radius'],
    padding: ['padding-top', 'padding-left'],
    margin: ['margin-top', 'margin-left'],
    gap: ['row-gap', 'column-gap']
  };
  let importantCache = new Map();
  function compilerForcesImportant(comp, cssProp) {
    const cacheKey = `${comp.id}|${cssProp}`;
    if (importantCache.has(cacheKey)) return importantCache.get(cacheKey);
    let result = false;
    const el = elementFor(comp.id);
    const sheet = document.getElementById('otterRealCanvasCss')?.sheet;
    if (el && sheet) {
      const props = [cssProp, ...(LONGHANDS[cssProp] || [])];
      const visit = (rules) => {
        for (const rule of rules) {
          if (result) return;
          if (rule.cssRules && !rule.selectorText) visit(rule.cssRules);
          else if (rule.selectorText && props.some(p => rule.style.getPropertyPriority(p) === 'important')) {
            // Ignore state pseudo-classes: test the element's own selector.
            const selector = rule.selectorText.replace(/::?(hover|active|focus|focus-visible|disabled|placeholder)\b/g, '');
            try { if (el.matches(selector)) result = true; } catch { /* unsupported selector */ }
          }
        }
      };
      try { visit(sheet.cssRules); } catch { /* sheet not readable yet */ }
    }
    importantCache.set(cacheKey, result);
    return result;
  }
  styles.importantProbe = compilerForcesImportant;

  // What the compiler itself applies to a component, for style provenance
  // (StyleController.explain): its inline value for `cssProp` when the Otter
  // source does not set it, and every rule in its stylesheet that sets the
  // property on this element in the current state.
  const SCOPE_RESET = /^#[\w-]+$/; // real-style.js's own reset rule on the canvas root
  const STATE_PSEUDO = /::?(hover|active|focus|focus-visible|disabled|placeholder)\b/g;
  function compilerStyleFor(comp, cssProp, state) {
    const el = elementFor(comp.id);
    const sheet = document.getElementById('otterRealCanvasCss')?.sheet;
    if (!el || !realRender) return null;
    const props = [cssProp, ...(LONGHANDS[cssProp] || [])];

    let inline = null;
    const info = realRender.elements.get(el.id);
    const renderedFromSource = (realRender.sourceInline?.get(comp.name) || []).includes(cssProp);
    if (info?.style && !renderedFromSource && styles.sourceValue(comp, cssProp) === null) {
      const probe = document.createElement('div');
      probe.style.cssText = info.style;
      for (const p of props) {
        const value = probe.style.getPropertyValue(p);
        if (value) { inline = value; break; }
      }
    }

    const rules = [];
    const wanted = (state || '').replace(/^:+/, '');
    const visit = (list) => {
      for (const rule of list) {
        if (rule.cssRules && !rule.selectorText) { visit(rule.cssRules); continue; }
        if (!rule.selectorText || !rule.style) continue;
        const prop = props.find(p => rule.style.getPropertyValue(p));
        if (!prop) continue;
        for (const part of rule.selectorText.split(',')) {
          const selector = part.trim();
          if (SCOPE_RESET.test(selector)) continue;
          const states = [...selector.matchAll(STATE_PSEUDO)].map(m => m[1]);
          if (states.length && !states.every(s => s === wanted || (wanted === 'focus' && s === 'focus-visible'))) continue;
          let matches = false;
          try { matches = el.matches(selector.replace(STATE_PSEUDO, '')); } catch { /* unsupported selector */ }
          if (!matches) continue;
          rules.push({
            // Show the selector as the compiler wrote it, without the canvas scope.
            selector: selector.replace(/^#[\w-]+\s+/, ''),
            value: rule.style.getPropertyValue(prop),
            important: rule.style.getPropertyPriority(prop) === 'important'
          });
          break;
        }
      }
    };
    try { if (sheet) visit(sheet.cssRules); } catch { /* sheet not readable yet */ }
    return inline || rules.length ? { inline, rules } : null;
  }
  styles.compilerProbe = compilerStyleFor;

  // Which inline source values each component has, for the render in flight.
  function snapshotSourceInline() {
    const map = new Map();
    for (const comp of uiModel.getAllComponents()) map.set(comp.name, Object.keys(styles.sourceInline(comp)));
    return map;
  }

  function scheduleRealRender() {
    clearTimeout(realRenderTimer);
    realRenderTimer = setTimeout(async () => {
      const serial = ++realRenderSerial;
      try {
        const code = generateOtterSource(uiModel);
        const css = cssAstManager ? cssAstManager.generateCss() : '';
        const sourceInline = snapshotSourceInline();
        const real = await fetchRealRender(code, css);
        if (serial !== realRenderSerial) return;
        real.sourceInline = sourceInline;
        realRender = real;
        importantCache = new Map();
        const area = contentAreaEl();
        if (area && !gestureActive) {
          applyRealRenderNow(area);
          applyForcedState();
          updateOverlay();
          window.dispatchEvent(new CustomEvent('otter:canvas-rendered'));
        }
      } catch (err) {
        console.warn('Otter Studio: real render unavailable, showing approximate canvas.', err);
      }
    }, 300);
  }

  // While designing :hover/:active/:focus, show that state on the selection.
  function applyForcedState() {
    // ::placeholder needs no forcing: an empty text box always shows it.
    const state = styles.context.state.replace(/^:+/, '');
    stageEl.querySelectorAll('[data-force-state]').forEach(el => el.removeAttribute('data-force-state'));
    if (!state || state === 'placeholder' || isInteractMode) return;
    for (const id of uiModel.selectedIds) {
      const el = elementFor(id);
      if (el) el.setAttribute('data-force-state', state);
    }
  }

  function updateDimensionBadge() {
    const badge = stageEl.querySelector('#canvasDimensionBadge');
    const area = contentAreaEl();
    if (!badge || !area) return;
    const bp = styles.breakpoint;
    const rect = area.getBoundingClientRect();
    badge.textContent = bp.width
      ? `${bp.label} · ${bp.width}px screen`
      : `${bp.label} · ${Math.round(rect.width / zoom)} × ${Math.round(rect.height / zoom)}`;
  }

  function contentAreaEl() {
    return stageEl.querySelector('.window-content-area');
  }

  function elementFor(id) {
    if (id === uiModel.rootId) return contentAreaEl();
    return stageEl.querySelector(`[data-id="${cssEscape(id)}"]`);
  }

  // ---------------------------------------------------------------------------
  // Overlay: selection, handles, spacing, grid tracks
  // ---------------------------------------------------------------------------

  function toOverlay(rect) {
    const vp = viewportEl.getBoundingClientRect();
    return {
      left: rect.left - vp.left + viewportEl.scrollLeft,
      top: rect.top - vp.top + viewportEl.scrollTop,
      width: rect.width,
      height: rect.height
    };
  }

  function place(el, rect) {
    el.style.left = `${rect.left}px`;
    el.style.top = `${rect.top}px`;
    el.style.width = `${rect.width}px`;
    el.style.height = `${rect.height}px`;
  }

  function clearOverlay() {
    selectionLayer.innerHTML = '';
    gridLayer.innerHTML = '';
    guidesLayer.innerHTML = '';
  }

  // Free layout containers carry is-free-layout on the canvas (the dot grid,
  // the empty-window hint); their layout comes from the stylesheet, so it is
  // read back from the computed style.
  function markLayoutModes() {
    for (const comp of uiModel.getAllComponents()) {
      const el = elementFor(comp.id);
      if (!el) continue;
      const cs = getComputedStyle(el);
      if (ComponentSchema[comp.kind]?.isContainer || comp.id === uiModel.rootId) {
        el.classList.toggle('is-free-layout', cs.getPropertyValue('--otter-layout').trim() === 'free');
      }
      // A control placed at x / y moves with the pointer (startFreeMove); the
      // browser's own drag-and-drop (reordering in a row or column) would
      // start instead and swallow the move.
      if (comp.id !== uiModel.rootId) {
        const placed = cs.position === 'absolute' || cs.position === 'fixed';
        el.draggable = !placed && !isLocked(comp);
      }
    }
  }

  function updateOverlay() {
    if (isInteractMode) return;
    const root = uiModel.getRoot();
    clearOverlay();
    if (!root) return;
    markLayoutModes();
    // Overlay covers the whole scrollable area.
    overlayEl.style.width = `${viewportEl.scrollWidth}px`;
    overlayEl.style.height = `${viewportEl.scrollHeight}px`;
    updateDimensionBadge();

    for (const selectedId of uiModel.selectedIds) {
      const comp = uiModel.getComponent(selectedId);
      const targetEl = selectedId === root.id ? stageEl.querySelector('#canvasWindowWrapper') : elementFor(selectedId);
      if (!comp || !targetEl) continue;

      const rect = toOverlay(targetEl.getBoundingClientRect());
      const isPrimary = selectedId === uiModel.selectedId;
      const box = document.createElement('div');
      box.className = `designer-selection-box ${isPrimary ? 'is-primary' : 'is-multi'}`;
      box.setAttribute('data-selection-id', selectedId);
      place(box, rect);
      selectionLayer.appendChild(box);

      if (!isPrimary) continue;

      box.appendChild(selectionBadge(comp, root));
      if (comp.id === root.id) {
        // Size the window like a Visual Studio form: drag its right edge,
        // bottom edge or corner. Its width / height go into the Otter source.
        for (const handle of ['e', 's', 'se']) {
          const h = document.createElement('div');
          h.className = `designer-resize-handle handle-${handle} is-window-handle`;
          h.title = 'Drag to resize the window. Alt turns off snapping to 8 px.';
          h.addEventListener('pointerdown', (e) => startResize(e, handle, comp));
          box.appendChild(h);
        }
        continue;
      }

      const el = elementFor(comp.id);
      const cs = getComputedStyle(el);
      const isFree = cs.position === 'absolute' || cs.position === 'fixed';
      box.classList.toggle('is-free', isFree);
      drawSpacing(box, comp, el, cs);
      for (const handle of ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw']) {
        const h = document.createElement('div');
        h.className = `designer-resize-handle handle-${handle}`;
        h.title = 'Drag to resize. Shift keeps proportions, Alt turns off snapping.';
        h.addEventListener('pointerdown', (e) => startResize(e, handle, comp));
        box.appendChild(h);
      }
      if (isFree) {
        box.classList.add('is-movable');
        box.addEventListener('pointerdown', (e) => {
          if (e.target === box) startFreeMove(e, comp);
        });
      }
    }

    // Grid tracks for a selected grid container.
    const primary = uiModel.getComponent(uiModel.selectedId);
    const primaryEl = primary && elementFor(primary.id);
    if (primaryEl && getComputedStyle(primaryEl).display.includes('grid')) {
      drawGridTracks(primaryEl);
    }
  }

  function selectionBadge(comp, root) {
    const badge = document.createElement('div');
    badge.className = 'designer-selection-badge';
    const context = styles.isBaseContext() ? '' : `<span class="badge-context">${escapeHtml(styles.breakpoint.id !== 'base' ? styles.breakpoint.label : '')}${escapeHtml(styles.state.id ? ' ' + styles.state.label : '')}</span>`;
    badge.innerHTML = `
      <span class="badge-name">${escapeHtml(comp.name)}</span>
      <span class="badge-kind">${escapeHtml(comp.kind)}</span>
      ${context}
      <div class="badge-actions">
        ${comp.parentId ? '<button class="badge-btn badge-parent" title="Select parent (Esc)">↑</button>' : ''}
        ${comp.id !== root.id ? `
          <button class="badge-btn badge-dup" title="Duplicate (Ctrl+D)">⎘</button>
          <button class="badge-btn badge-del" title="Delete (Del)">×</button>` : ''}
      </div>
    `;
    badge.addEventListener('pointerdown', (e) => e.stopPropagation());
    badge.querySelector('.badge-parent')?.addEventListener('click', (e) => { e.stopPropagation(); uiModel.select(comp.parentId); });
    badge.querySelector('.badge-dup')?.addEventListener('click', (e) => { e.stopPropagation(); uiModel.duplicateComponent(comp.id, cssAstManager); });
    badge.querySelector('.badge-del')?.addEventListener('click', (e) => { e.stopPropagation(); uiModel.removeComponent(comp.id); });
    return badge;
  }

  // Padding (inside), margin (outside) and gap (between children) are drawn as
  // bands that can be dragged to change the value.
  function drawSpacing(box, comp, el, cs) {
    const px = (v) => (parseFloat(v) || 0) * zoom;
    const pad = SIDES.map(s => px(cs.getPropertyValue(`padding-${s}`)));
    const mar = SIDES.map(s => px(cs.getPropertyValue(`margin-${s}`)));
    const border = SIDES.map(s => px(cs.getPropertyValue(`border-${s}-width`)));
    const w = parseFloat(box.style.width);
    const h = parseFloat(box.style.height);

    const band = (kind, sideIndex, rect, value) => {
      const b = document.createElement('div');
      b.className = `designer-space-band is-${kind} side-${SIDES[sideIndex]}`;
      place(b, rect);
      b.title = `${kind}-${SIDES[sideIndex]}: ${formatNumber(value / zoom)}px — drag to change (Alt: both sides, Shift: all sides)`;
      const label = document.createElement('span');
      label.className = 'designer-space-label';
      label.textContent = formatNumber(value / zoom);
      b.appendChild(label);
      // Only a small grip is interactive, so the rest of the padding area
      // still selects and drags the element itself.
      const grip = document.createElement('div');
      grip.className = 'designer-space-grip';
      grip.title = b.title;
      grip.addEventListener('pointerdown', (e) => startSpacingDrag(e, comp, kind, sideIndex));
      b.appendChild(grip);
      box.appendChild(b);
    };

    const MIN = 6; // keep zero-size bands grabbable
    // Padding bands sit inside the border.
    band('padding', 0, { left: border[3], top: border[0], width: w - border[1] - border[3], height: Math.max(MIN, pad[0]) }, pad[0]);
    band('padding', 2, { left: border[3], top: h - border[2] - Math.max(MIN, pad[2]), width: w - border[1] - border[3], height: Math.max(MIN, pad[2]) }, pad[2]);
    band('padding', 3, { left: border[3], top: border[0], width: Math.max(MIN, pad[3]), height: h - border[0] - border[2] }, pad[3]);
    band('padding', 1, { left: w - border[1] - Math.max(MIN, pad[1]), top: border[0], width: Math.max(MIN, pad[1]), height: h - border[0] - border[2] }, pad[1]);
    // Margin bands sit outside the box.
    if (mar[0] > 0) band('margin', 0, { left: 0, top: -mar[0], width: w, height: mar[0] }, mar[0]);
    if (mar[2] > 0) band('margin', 2, { left: 0, top: h, width: w, height: mar[2] }, mar[2]);
    if (mar[3] > 0) band('margin', 3, { left: -mar[3], top: 0, width: mar[3], height: h }, mar[3]);
    if (mar[1] > 0) band('margin', 1, { left: w, top: 0, width: mar[1], height: h }, mar[1]);

    // Gap bands between consecutive children of a flex/grid container.
    if (!/flex|grid/.test(cs.display)) return;
    const kids = Array.from(el.children).filter(k => k.hasAttribute('data-id') && getComputedStyle(k).display !== 'none');
    const boxRect = el.getBoundingClientRect();
    const isRow = cs.display.includes('flex') ? cs.flexDirection.startsWith('row') : true;
    for (let i = 0; i < kids.length - 1; i++) {
      const a = kids[i].getBoundingClientRect();
      const b = kids[i + 1].getBoundingClientRect();
      let rect;
      if (isRow && b.left >= a.right - 1) {
        rect = { left: a.right - boxRect.left, top: Math.min(a.top, b.top) - boxRect.top, width: Math.max(MIN, b.left - a.right), height: Math.max(a.height, b.height) };
      } else if (b.top >= a.bottom - 1) {
        rect = { left: Math.min(a.left, b.left) - boxRect.left, top: a.bottom - boxRect.top, width: Math.max(a.width, b.width), height: Math.max(MIN, b.top - a.bottom) };
      } else {
        continue;
      }
      const g = document.createElement('div');
      g.className = `designer-gap-band ${isRow && b.left >= a.right - 1 ? 'is-vertical' : 'is-horizontal'}`;
      place(g, rect);
      g.title = 'Gap between children — drag to change';
      const grip = document.createElement('div');
      grip.className = 'designer-space-grip';
      grip.title = g.title;
      grip.addEventListener('pointerdown', (e) => startGapDrag(e, comp, g.classList.contains('is-vertical')));
      g.appendChild(grip);
      box.appendChild(g);
    }
  }

  function drawGridTracks(el) {
    const tracks = gridTracks(el);
    if (!tracks) return;
    const frame = toOverlay(tracks.content);
    const layer = document.createElement('div');
    layer.className = 'designer-grid-tracks';
    place(layer, frame);
    tracks.columns.forEach((col, i) => {
      tracks.rows.forEach((row, j) => {
        const cell = document.createElement('div');
        cell.className = 'designer-grid-cell';
        place(cell, { left: col.start - tracks.content.left, top: row.start - tracks.content.top, width: col.end - col.start, height: row.end - row.start });
        cell.setAttribute('data-cell', `${i + 1},${j + 1}`);
        layer.appendChild(cell);
      });
    });
    gridLayer.appendChild(layer);
  }

  // Track boundaries of a grid container, in client coordinates.
  function gridTracks(el) {
    const cs = getComputedStyle(el);
    const colSizes = cs.gridTemplateColumns.split(/\s+/).map(parseFloat).filter(n => !Number.isNaN(n));
    const rowSizes = cs.gridTemplateRows.split(/\s+/).map(parseFloat).filter(n => !Number.isNaN(n));
    if (colSizes.length === 0) return null;
    const rect = el.getBoundingClientRect();
    const scale = zoom;
    const padL = (parseFloat(cs.paddingLeft) + parseFloat(cs.borderLeftWidth)) * scale;
    const padT = (parseFloat(cs.paddingTop) + parseFloat(cs.borderTopWidth)) * scale;
    const colGap = (parseFloat(cs.columnGap) || 0) * scale;
    const rowGap = (parseFloat(cs.rowGap) || 0) * scale;
    const build = (sizes, origin, gap) => {
      const out = [];
      let pos = origin;
      for (const size of sizes) {
        out.push({ start: pos, end: pos + size * scale });
        pos += size * scale + gap;
      }
      return out;
    };
    const columns = build(colSizes, rect.left + padL, colGap);
    const rows = rowSizes.length ? build(rowSizes, rect.top + padT, rowGap) : [{ start: rect.top + padT, end: rect.bottom }];
    const content = {
      left: columns[0].start, top: rows[0].start,
      right: columns[columns.length - 1].end, bottom: rows[rows.length - 1].end
    };
    content.width = content.right - content.left;
    content.height = content.bottom - content.top;
    return { columns, rows, content, colSizes };
  }

  // ---------------------------------------------------------------------------
  // Gestures: resize with smart guides, spacing drags, free move
  // ---------------------------------------------------------------------------

  // Common pointer-drag plumbing: pointer capture, Escape to cancel (undoes
  // the whole gesture), and a single undo step for the whole drag.
  // During a move or resize the selection box goes with the element (the
  // full overlay is redrawn when the gesture ends).
  function followSelection() {
    for (const box of selectionLayer.querySelectorAll('.designer-selection-box[data-selection-id]')) {
      const id = box.getAttribute('data-selection-id');
      const target = id === uiModel.rootId ? stageEl.querySelector('#canvasWindowWrapper') : elementFor(id);
      if (target) place(box, toOverlay(target.getBoundingClientRect()));
    }
  }

  function beginGesture(e, { onMove, onEnd, cursor }) {
    e.preventDefault();
    e.stopPropagation();
    gestureActive = true;
    // The hover outline would stay where the gesture began.
    if (hoverBox) hoverBox.hidden = true;
    const undoDepth = uiModel.undoStack.length;
    document.body.classList.add('designer-is-dragging');
    if (cursor) document.body.style.cursor = cursor;
    const tooltip = document.createElement('div');
    tooltip.className = 'resize-dimension-tooltip';
    overlayEl.appendChild(tooltip);
    let cancelled = false;

    const move = (ev) => {
      if (cancelled) return;
      const text = onMove(ev);
      followSelection();
      if (text) {
        tooltip.textContent = text;
        const vp = viewportEl.getBoundingClientRect();
        tooltip.style.left = `${ev.clientX - vp.left + viewportEl.scrollLeft + 14}px`;
        tooltip.style.top = `${ev.clientY - vp.top + viewportEl.scrollTop + 14}px`;
      }
    };
    const finish = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', finish);
      window.removeEventListener('keydown', key, true);
      document.body.classList.remove('designer-is-dragging');
      document.body.style.cursor = '';
      tooltip.remove();
      guidesLayer.innerHTML = '';
      gestureActive = false;
      onEnd?.(cancelled);
      update();
    };
    const key = (ev) => {
      if (ev.key !== 'Escape') return;
      ev.preventDefault();
      ev.stopPropagation();
      cancelled = true;
      // Roll back every snapshot this gesture made.
      while (uiModel.undoStack.length > undoDepth) uiModel.undo();
      uiModel.redoStack = [];
      finish();
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', finish);
    window.addEventListener('keydown', key, true);
  }

  function startResize(e, handle, comp) {
    const el = elementFor(comp.id);
    if (!el) return;
    const startRect = el.getBoundingClientRect();
    const startX = e.clientX;
    const startY = e.clientY;
    const cs = getComputedStyle(el);
    const isFree = cs.position === 'absolute' || cs.position === 'fixed';
    const startLeft = parseFloat(cs.left) || 0;
    const startTop = parseFloat(cs.top) || 0;
    const ratio = startRect.width / Math.max(1, startRect.height);
    const isWindow = comp.id === uiModel.rootId;
    const parentEl = isWindow ? null : el.parentElement;
    const parentCs = parentEl ? getComputedStyle(parentEl) : null;
    const parentInner = parentEl ? {
      width: (parentEl.clientWidth - parseFloat(parentCs.paddingLeft) - parseFloat(parentCs.paddingRight)),
      height: (parentEl.clientHeight - parseFloat(parentCs.paddingTop) - parseFloat(parentCs.paddingBottom))
    } : null;
    const siblings = parentEl ? Array.from(parentEl.children).filter(k => k !== el && k.hasAttribute('data-id')) : [];
    // A placed control's dragged edges snap to its neighbours' edges and
    // sizes (designer/snapping.js), measured once at the start.
    const freeSnap = isFree && !isWindow ? snapContext(el.offsetParent || el.parentElement, el) : null;
    const key = `resize:${comp.id}`;
    const cursor = getComputedStyle(e.target).cursor;
    // Its padding / margin bands stay hidden while it changes size.
    document.body.classList.add('designer-is-moving');

    beginGesture(e, {
      cursor,
      onMove: (ev) => {
        const dx = (ev.clientX - startX) / zoom;
        const dy = (ev.clientY - startY) / zoom;
        let w = startRect.width / zoom;
        let h = startRect.height / zoom;
        if (handle.includes('e')) w += dx;
        if (handle.includes('w')) w -= dx;
        if (handle.includes('s')) h += dy;
        if (handle.includes('n')) h -= dy;
        if (ev.shiftKey && handle.length === 2) h = w / ratio;
        w = Math.max(isWindow ? 160 : 8, w);
        h = Math.max(isWindow ? 120 : 8, h);

        // Smart snapping: parent width (becomes 100%), sibling sizes, 8px grid.
        const notes = [];
        let widthValue = null;
        let heightValue = null;
        const guides = [];
        let freeGuides = null;
        if (freeSnap) {
          const keepRatio = ev.shiftKey && handle.length === 2;
          const box = {
            left: startRect.left + (handle.includes('w') ? startRect.width - w * zoom : 0),
            top: startRect.top + (handle.includes('n') ? startRect.height - h * zoom : 0),
            width: w * zoom,
            height: h * zoom
          };
          // Keeping the proportions, the side edge snaps and the height follows.
          const snap = snapResize(box, keepRatio ? handle.replace(/[ns]/, '') : handle, freeSnap.siblings, freeSnap.parent, { threshold: ev.altKey ? 0 : SNAP_PX * zoom, zoom });
          w = Math.max(8, snap.box.width / zoom);
          h = keepRatio ? Math.max(8, w / ratio) : Math.max(8, snap.box.height / zoom);
          freeGuides = snap;
          for (const z of snap.sizes) {
            const other = z.index !== undefined && freeSnap.els[z.index];
            if (other) notes.push(`= ${other.id} ${z.axis === 'x' ? 'width' : 'height'}`);
          }
        } else if (!ev.altKey) {
          if (handle.includes('e') || handle.includes('w')) {
            if (parentInner && Math.abs(w - parentInner.width) <= SNAP_PX) {
              w = parentInner.width; widthValue = '100%'; notes.push('fills parent');
            } else {
              const match = siblings.find(s => Math.abs(s.getBoundingClientRect().width / zoom - w) <= SNAP_PX);
              if (match) {
                w = match.getBoundingClientRect().width / zoom;
                notes.push(`= ${match.id} width`);
                guides.push({ el: match, axis: 'x' });
              } else {
                w = Math.round(w / 8) * 8 || 8;
              }
            }
          }
          if (handle.includes('n') || handle.includes('s')) {
            const match = siblings.find(s => Math.abs(s.getBoundingClientRect().height / zoom - h) <= SNAP_PX);
            if (match) {
              h = match.getBoundingClientRect().height / zoom;
              notes.push(`= ${match.id} height`);
              guides.push({ el: match, axis: 'y' });
            } else {
              h = Math.round(h / 8) * 8 || 8;
            }
          }
        }

        const values = {};
        if (handle.includes('e') || handle.includes('w')) values.width = widthValue || `${Math.round(w)}px`;
        if (handle.includes('n') || handle.includes('s') || (ev.shiftKey && handle.length === 2)) values.height = heightValue || `${Math.round(h)}px`;
        if (values.height && el.classList.contains('is-free-layout')) values['min-height'] = values.height;
        if (isFree && handle.includes('w')) values.left = `${Math.round(startLeft + (startRect.width / zoom - w))}px`;
        if (isFree && handle.includes('n')) values.top = `${Math.round(startTop + (startRect.height / zoom - h))}px`;

        styles.write(comp, values, { key });
        // Drawn after the write: a source-backed write (width 240) redraws
        // the overlay, guides included.
        if (freeGuides) {
          guidesLayer.innerHTML = '';
          drawSnapLines(freeGuides.lines);
          drawSpacingGuides([], [], freeGuides.sizes);
        } else {
          drawSizeGuides(comp, guides);
        }
        return `${Math.round(w)} × ${Math.round(h)}${notes.length ? '  ·  ' + notes.join(', ') : ''}`;
      },
      onEnd: () => document.body.classList.remove('designer-is-moving')
    });
  }

  // Dashed lines from the resized element to the sibling it matches.
  function drawSizeGuides(comp, guides) {
    guidesLayer.innerHTML = '';
    const el = elementFor(comp.id);
    if (!el) return;
    const own = toOverlay(el.getBoundingClientRect());
    for (const g of guides) {
      const other = toOverlay(g.el.getBoundingClientRect());
      for (const r of [own, other]) {
        const line = document.createElement('div');
        line.className = `designer-guide ${g.axis === 'x' ? 'is-measure-x' : 'is-measure-y'}`;
        if (g.axis === 'x') place(line, { left: r.left, top: r.top + r.height + 3, width: r.width, height: 1 });
        else place(line, { left: r.left + r.width + 3, top: r.top, width: 1, height: r.height });
        guidesLayer.appendChild(line);
      }
    }
  }

  function startSpacingDrag(e, comp, kind, sideIndex) {
    const el = elementFor(comp.id);
    if (!el) return;
    const cs = getComputedStyle(el);
    const start = SIDES.map(s => parseFloat(cs.getPropertyValue(`${kind}-${s}`)) || 0);
    const startX = e.clientX;
    const startY = e.clientY;
    const key = `space:${comp.id}:${kind}`;
    // Dragging outward (away from the content) increases the value.
    const direction = { 0: [0, -1], 1: [1, 0], 2: [0, 1], 3: [-1, 0] }[sideIndex];
    const sign = kind === 'padding' ? -1 : 1;

    beginGesture(e, {
      cursor: sideIndex % 2 === 0 ? 'ns-resize' : 'ew-resize',
      onMove: (ev) => {
        const delta = (((ev.clientX - startX) * direction[0]) + ((ev.clientY - startY) * direction[1])) / zoom * sign;
        let value = start[sideIndex] + delta;
        if (kind === 'padding') value = Math.max(0, value);
        value = ev.altKey && ev.shiftKey ? value : Math.round(value / (ev.ctrlKey ? 1 : 4)) * (ev.ctrlKey ? 1 : 4);
        const sides = start.map(v => `${formatNumber(v)}px`);
        const indexes = ev.shiftKey ? [0, 1, 2, 3] : ev.altKey ? [sideIndex, (sideIndex + 2) % 4] : [sideIndex];
        for (const i of indexes) sides[i] = `${formatNumber(value)}px`;
        const values = { [kind]: collapseBox(sides.map(s => s === '0px' ? '0' : s)) };
        for (const s of SIDES) values[`${kind}-${s}`] = null;
        styles.write(comp, values, { key });
        return `${kind} ${indexes.length === 4 ? 'all' : indexes.map(i => SIDES[i]).join(' + ')}: ${formatNumber(value)}px`;
      }
    });
  }

  function startGapDrag(e, comp, vertical) {
    const el = elementFor(comp.id);
    if (!el) return;
    const cs = getComputedStyle(el);
    const start = parseFloat(vertical ? cs.columnGap : cs.rowGap) || 0;
    const startPos = vertical ? e.clientX : e.clientY;
    beginGesture(e, {
      cursor: vertical ? 'ew-resize' : 'ns-resize',
      onMove: (ev) => {
        let value = Math.max(0, start + ((vertical ? ev.clientX : ev.clientY) - startPos) / zoom);
        value = ev.ctrlKey ? Math.round(value) : Math.round(value / 4) * 4;
        styles.write(comp, { gap: `${value}px` }, { key: `gap:${comp.id}` });
        return `gap: ${value}px`;
      }
    });
  }

  // Drag a placed control - or, when it is one of several selected placed
  // controls in the same container, all of them together (the group snaps
  // as one box). Let go over another container (a card, a row, the window)
  // and they go into it (actions.moveInto): the container is outlined while
  // the pointer is over it. One undo step.
  function startFreeMove(e, comp) {
    const el = elementFor(comp.id);
    if (!el) return;
    const undoDepth = uiModel.undoStack.length;
    const isPlaced = (node) => ['absolute', 'fixed'].includes(getComputedStyle(node).position);
    let movers = [];
    if (uiModel.isSelected(comp.id) && uiModel.selectedIds.size > 1) {
      movers = uiModel.getSelectedComponents()
        .filter(c => c.id !== uiModel.rootId && c.parentId === comp.parentId)
        .map(c => ({ comp: c, el: elementFor(c.id) }))
        .filter(m => m.el && isPlaced(m.el));
    }
    if (!movers.some(m => m.comp.id === comp.id)) {
      movers = [{ comp, el }];
      uiModel.select(comp.id);
    }
    for (const m of movers) {
      const mcs = getComputedStyle(m.el);
      m.startLeft = parseFloat(mcs.left) || 0;
      m.startTop = parseFloat(mcs.top) || 0;
    }
    const startX = e.clientX;
    const startY = e.clientY;
    const parentEl = el.offsetParent || el.parentElement;
    const key = `move:${movers.map(m => m.comp.id).join(',')}`;
    // Measured once: the elements themselves move with every write.
    const rects = movers.map(m => m.el.getBoundingClientRect());
    const union = {
      left: Math.min(...rects.map(r => r.left)),
      top: Math.min(...rects.map(r => r.top)),
      right: Math.max(...rects.map(r => r.right)),
      bottom: Math.max(...rects.map(r => r.bottom))
    };
    const startRect = { left: union.left, top: union.top, width: union.right - union.left, height: union.bottom - union.top };
    const { siblings, parent } = snapContext(parentEl, movers.map(m => m.el));
    // The moving controls are under the pointer: look past them for a container.
    const isMoving = (node) => movers.some(m => elementFor(m.comp.id)?.contains(node));
    let into = null;

    // While it moves, its padding / margin bands stay out of the way.
    document.body.classList.add('designer-is-moving');
    beginGesture(e, {
      cursor: 'move',
      onEnd: (cancelled) => {
        document.body.classList.remove('designer-is-moving');
        hideDropMarkers();
        if (cancelled || !into) return;
        const target = uiModel.getComponent(into.targetComp.id);
        // Where they are on screen now is where they stay (in Free layout).
        const rects = movers.map(m => elementFor(m.comp.id)?.getBoundingClientRect() || null);
        const insertAt = actions.isFreeLayout(target) ? null : (into.insertIndex ?? null);
        actions.moveInto(movers.map(m => m.comp), target, insertAt, { rects });
        // The drag and the move are one undo step.
        uiModel.undoStack.length = Math.min(uiModel.undoStack.length, undoDepth + 1);
      },
      onMove: (ev) => {
        // How far it has moved, in CSS px.
        let dx = (ev.clientX - startX) / zoom;
        let dy = (ev.clientY - startY) / zoom;
        guidesLayer.innerHTML = '';
        // Over another container: it goes in there when let go.
        const hit = performHitTest(ev.clientX, ev.clientY, comp.id, contentAreaEl(), uiModel.getRoot(), isMoving);
        into = hit && hit.targetComp.id !== comp.parentId ? hit : null;
        if (into) {
          showMoveTarget(into);
        } else {
          hideDropMarkers();
          const box = { left: startRect.left + dx * zoom, top: startRect.top + dy * zoom, width: startRect.width, height: startRect.height };
          // Alt: no snapping (the distances still show).
          const snap = snapMove(box, siblings, parent, { threshold: ev.altKey ? 0 : SNAP_PX * zoom, zoom });
          dx += snap.dx / zoom;
          dy += snap.dy / zoom;
          drawSnapLines(snap.lines);
          drawSpacingGuides(snap.gaps, snap.measures);
        }
        const dxPx = Math.round(dx);
        const dyPx = Math.round(dy);
        for (const m of movers) {
          styles.write(m.comp, { left: `${m.startLeft + dxPx}px`, top: `${m.startTop + dyPx}px`, right: null, bottom: null }, { key });
        }
        if (into) return `Into ${into.targetComp.name}`;
        const lead = movers.find(m => m.comp.id === comp.id) || movers[0];
        return movers.length > 1
          ? `${movers.length} controls  ·  x ${lead.startLeft + dxPx}  y ${lead.startTop + dyPx}`
          : `x ${lead.startLeft + dxPx}  y ${lead.startTop + dyPx}`;
      }
    });
  }

  // Moving placed controls over another container: outline it; a row or
  // column also shows where in its order they would go.
  function showMoveTarget(hit) {
    const free = actions.isFreeLayout(hit.targetComp);
    showDropMarkers(hit);
    if (free || hit.gridCell) {
      insertionLine.hidden = true;
      cellBox.hidden = true;
    }
    targetBadge.textContent = `Into ${hit.targetComp.name}${free ? ' · Free layout' : ''}`;
  }

  // What a control moving in a container snaps to (designer/snapping.js):
  // its siblings' boxes and the container's padding box, in screen px.
  function snapContext(parentEl, exclude) {
    if (!parentEl) return { siblings: [], els: [], parent: null };
    const skip = new Set(Array.isArray(exclude) ? exclude : [exclude]);
    const box = (r) => ({ left: r.left, top: r.top, width: r.width, height: r.height });
    const els = Array.from(parentEl.children)
      .filter(k => !skip.has(k) && k.hasAttribute('data-id') && !k.classList.contains('is-designer-hidden'));
    const siblings = els.map(k => box(k.getBoundingClientRect()));
    const pr = parentEl.getBoundingClientRect();
    const pcs = getComputedStyle(parentEl);
    const bl = (parseFloat(pcs.borderLeftWidth) || 0) * zoom;
    const bt = (parseFloat(pcs.borderTopWidth) || 0) * zoom;
    const br = (parseFloat(pcs.borderRightWidth) || 0) * zoom;
    const bb = (parseFloat(pcs.borderBottomWidth) || 0) * zoom;
    return { siblings, els, parent: { left: pr.left + bl, top: pr.top + bt, width: pr.width - bl - br, height: pr.height - bt - bb } };
  }

  // Equal gaps (pink bars with their size), distances to the nearest
  // neighbours / container edge (red lines with their size) and, resizing,
  // equal sizes (bars beside both controls), in CSS px.
  function drawSpacingGuides(gaps, measures, sizes = []) {
    const vp = viewportEl.getBoundingClientRect();
    const toLayer = (x, y) => ({ x: x - vp.left + viewportEl.scrollLeft, y: y - vp.top + viewportEl.scrollTop });
    const draw = (g, cls) => {
      if (Math.abs(g.to - g.from) < 1) return;
      const line = document.createElement('div');
      line.className = `designer-guide ${cls}`;
      const a = g.axis === 'x' ? toLayer(g.from, g.at) : toLayer(g.at, g.from);
      if (g.axis === 'x') place(line, { left: a.x, top: a.y, width: g.to - g.from, height: 1 });
      else place(line, { left: a.x, top: a.y, width: 1, height: g.to - g.from });
      const label = document.createElement('span');
      label.className = 'designer-guide-label';
      label.textContent = String(g.px);
      line.appendChild(label);
      guidesLayer.appendChild(line);
    };
    for (const g of gaps) draw(g, 'is-gap');
    for (const m of measures) draw(m, m.toParent ? 'is-measure is-to-parent' : 'is-measure');
    for (const z of sizes) draw(z, 'is-size');
  }

  function drawSnapLines(lines) {
    const vp = viewportEl.getBoundingClientRect();
    for (const l of lines) {
      const line = document.createElement('div');
      line.className = 'designer-guide is-snap';
      if (l.axis === 'x') place(line, { left: l.at - vp.left + viewportEl.scrollLeft, top: l.from - vp.top + viewportEl.scrollTop, width: 1, height: l.to - l.from });
      else place(line, { left: l.from - vp.left + viewportEl.scrollLeft, top: l.at - vp.top + viewportEl.scrollTop, width: l.to - l.from, height: 1 });
      guidesLayer.appendChild(line);
    }
  }

  // ---------------------------------------------------------------------------
  // Components
  // ---------------------------------------------------------------------------

  function startInlineEdit(targetEl, comp, propKey = 'text') {
    if (isInteractMode) return;
    const initialText = comp.properties[propKey] || '';
    const input = document.createElement('input');
    input.type = 'text';
    input.className = 'canvas-inline-editor';
    input.value = initialText;
    targetEl.innerHTML = '';
    targetEl.appendChild(input);
    input.focus();
    input.select();

    let committed = false;
    function commit() {
      if (committed) return;
      committed = true;
      uiModel.setProperty(comp.id, propKey, input.value.trim());
    }
    input.addEventListener('keydown', (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') {
        e.preventDefault();
        commit();
      } else if (e.key === 'Escape') {
        e.preventDefault();
        committed = true;
        update();
      }
    });
    input.addEventListener('blur', commit);
  }

  function triggerOtterEvent(comp, eventKind) {
    const events = uiModel.getEvents(comp.id);
    const handler = events[eventKind];

    const logToStudio = (msg) => {
      const outBody = document.getElementById('programOutputBody');
      if (outBody) {
        const line = document.createElement('div');
        line.className = 'log-line';
        line.innerHTML = `<span style="color:#60a5fa">[${escapeHtml(comp.name)}.${eventKind}]</span> ${escapeHtml(msg)}`;
        outBody.appendChild(line);
        outBody.scrollTop = outBody.scrollHeight;
      }
      const previewLog = document.getElementById('previewLogEntries');
      if (previewLog) {
        const time = new Date().toLocaleTimeString();
        const entry = document.createElement('div');
        entry.className = 'log-entry';
        entry.innerHTML = `<span class="log-time">[${time}]</span> <span style="color:#60a5fa">[${escapeHtml(comp.name)}]</span> ${escapeHtml(msg)}`;
        previewLog.appendChild(entry);
        previewLog.scrollTop = previewLog.scrollHeight;
      }
      console.log(`[Otter Interact: ${comp.name}.${eventKind}] ${msg}`);
    };

    if (!handler || !handler.trim()) {
      logToStudio(`Triggered ${eventKind} (no handler registered)`);
      return;
    }

    for (const raw of handler.split('\n')) {
      const line = raw.trim();
      if (!line || line.startsWith('#')) continue;

      if (line.startsWith('say ')) {
        logToStudio(`say: ${line.slice(4).trim().replace(/^"(.*)"$/, '$1')}`);
        continue;
      }

      const addMatch = line.match(/^add\s+(\d+)\s+to\s+([a-zA-Z0-9_]+)$/i);
      const subMatch = line.match(/^(?:remove|subtract)\s+(\d+)\s+from\s+([a-zA-Z0-9_]+)$/i);
      if (addMatch || subMatch) {
        const amt = parseInt((addMatch || subMatch)[1], 10) * (addMatch ? 1 : -1);
        const targetName = (addMatch || subMatch)[2];
        const target = uiModel.getAllComponents().find(c => c.name === targetName);
        if (target) {
          if (typeof target.properties.value === 'number') {
            target.properties.value = Math.max(0, target.properties.value + amt);
            uiModel.notify('property', { id: target.id });
            logToStudio(`${targetName} is now ${target.properties.value}`);
          } else {
            const num = parseInt(target.properties.text, 10);
            if (!isNaN(num)) {
              target.properties.text = String(num + amt);
              uiModel.notify('property', { id: target.id });
              logToStudio(`${targetName} text is now ${target.properties.text}`);
            }
          }
        }
        continue;
      }

      const textMatch = line.match(/^([a-zA-Z0-9_]+)\s+has\s+text\s+(.+)$/i);
      if (textMatch) {
        const target = uiModel.getAllComponents().find(c => c.name === textMatch[1]);
        if (target) {
          target.properties.text = textMatch[2].trim().replace(/^"(.*)"$/, '$1');
          uiModel.notify('property', { id: target.id });
          logToStudio(`${textMatch[1]} has text "${target.properties.text}"`);
        }
        continue;
      }

      logToStudio(`Executed: ${line}`);
    }
  }

  function renderBreadcrumbs() {
    const crumbsEl = topbarEl.querySelector('#canvasBreadcrumbs');
    crumbsEl.innerHTML = '';
    const selected = uiModel.getComponent(uiModel.selectedId);
    if (!selected) return;
    const path = [];
    let curr = selected;
    while (curr) {
      path.unshift(curr);
      curr = curr.parentId ? uiModel.getComponent(curr.parentId) : null;
    }
    path.forEach((node, idx) => {
      if (idx > 0) {
        const sep = document.createElement('span');
        sep.className = 'crumb-sep';
        sep.textContent = '›';
        crumbsEl.appendChild(sep);
      }
      const crumb = document.createElement('span');
      crumb.className = `crumb-item ${node.id === selected.id ? 'is-active' : ''}`;
      crumb.textContent = `${node.name} (${node.kind})`;
      crumb.addEventListener('click', () => uiModel.select(node.id));
      crumb.addEventListener('mouseenter', () => showHover(node.id));
      crumb.addEventListener('mouseleave', () => { hoverBox.hidden = true; });
      crumbsEl.appendChild(crumb);
    });
    if (uiModel.selectedIds.size > 1) {
      const more = document.createElement('span');
      more.className = 'crumb-multi';
      more.textContent = `+${uiModel.selectedIds.size - 1} more`;
      crumbsEl.appendChild(more);
    }
  }

  function renderCanvasComponent(comp) {
    const schema = ComponentSchema[comp.kind] || {};
    const props = comp.properties || {};

    // Real programs render buttons as <button>, which has its own font, box
    // model and line-height; a <div> would measure differently.
    const isButtonKind = ['button', 'primary button', 'danger button'].includes(comp.kind);
    const el = document.createElement(isButtonKind ? 'button' : 'div');
    if (isButtonKind) el.type = 'button';
    el.id = comp.name; // ID matches CSS selector #compName
    el.className = `canvas-element ${schema.isContainer ? 'is-container' : 'is-control'} ${isInteractMode ? 'is-interactive-mode' : ''}`;
    el.setAttribute('data-id', comp.id);
    el.setAttribute('data-kind', comp.kind);

    switch (comp.kind) {
      case 'row': el.classList.add('canvas-row', 'otter-row'); break;
      case 'column': el.classList.add('canvas-column', 'otter-column'); break;
      case 'card': el.classList.add('canvas-card', 'otter-card', 'task-item'); break;
      case 'scroll': el.classList.add('canvas-scroll', 'otter-scroll'); break;
      case 'heading':
        el.classList.add('canvas-heading', 'otter-heading');
        el.innerText = props.text || 'Heading';
        break;
      case 'text':
        el.classList.add('canvas-text', 'otter-text');
        el.innerText = props.text || 'Text Label';
        break;
      case 'button':
      case 'primary button':
      case 'danger button':
        el.classList.add('canvas-button', 'otter-button', 'otter-btn');
        if (comp.kind === 'primary button') el.classList.add('otter-btn-primary');
        if (comp.kind === 'danger button') el.classList.add('otter-btn-danger');
        el.innerText = props.text || 'Button';
        break;
      case 'text box':
        el.classList.add('canvas-textbox', 'otter-textbox', 'otter-input');
        el.innerText = props.text || props.placeholder || 'Enter text...';
        if (!props.text && props.placeholder) el.classList.add('is-placeholder');
        break;
      case 'checkbox':
        el.classList.add('canvas-checkbox', 'otter-checkbox');
        el.innerHTML = `
          <input type="checkbox" ${props.checked ? 'checked' : ''} ${!isInteractMode ? 'disabled style="pointer-events:none;"' : ''} />
          <span>${escapeHtml(props.text || 'Checkbox')}</span>
        `;
        break;
      case 'slider':
        el.classList.add('canvas-slider', 'otter-slider');
        el.innerHTML = `<div class="slider-track"><div class="slider-thumb" style="left: ${Number(props.value) || 50}%;"></div></div>`;
        break;
      case 'dropdown':
        el.classList.add('canvas-dropdown', 'otter-dropdown', 'otter-select');
        el.innerHTML = `<span>${escapeHtml(props.placeholder || 'Select option...')}</span><span class="arrow">▾</span>`;
        break;
      case 'progress bar': {
        el.classList.add('canvas-progress', 'otter-progress');
        const pct = Math.min(100, Math.max(0, ((props.value || 0) / (props.maximum || 100)) * 100));
        el.innerHTML = `<div class="progress-bar-fill" style="width:${pct}%;background:${escapeHtml(props.foreground || '#3b82f6')};"></div>`;
        break;
      }
      case 'image':
        el.classList.add('canvas-image', 'otter-image');
        el.innerHTML = `<img src="${escapeHtml(props.source || '')}" alt="" style="width:100%;height:100%;object-fit:cover;pointer-events:none;" />`;
        break;
    }

    if (isInteractMode) {
      bindInteractBehaviors(el, comp);
    } else {
      bindDesignBehaviors(el, comp);
    }

    if (schema.isContainer && comp.children) {
      comp.children.forEach((childId, i) => {
        const child = uiModel.getComponent(childId);
        if (child) el.appendChild(renderCanvasComponent(child, comp.id, i));
      });
    }
    return el;
  }

  function bindInteractBehaviors(el, comp) {
    if (['button', 'primary button', 'danger button'].includes(comp.kind)) {
      el.style.cursor = 'pointer';
      el.addEventListener('click', (e) => {
        e.stopPropagation();
        el.classList.add('btn-clicked');
        setTimeout(() => el.classList.remove('btn-clicked'), 150);
        triggerOtterEvent(comp, 'clicked');
      });
    } else if (comp.kind === 'checkbox') {
      el.querySelector('input[type="checkbox"]')?.addEventListener('change', (e) => {
        e.stopPropagation();
        comp.properties.checked = e.target.checked;
        triggerOtterEvent(comp, 'clicked');
      });
    } else if (comp.kind === 'slider') {
      el.style.cursor = 'pointer';
      el.addEventListener('click', (e) => {
        e.stopPropagation();
        const rect = el.getBoundingClientRect();
        const clickPct = Math.max(0, Math.min(100, Math.round(((e.clientX - rect.left) / rect.width) * 100)));
        comp.properties.value = clickPct;
        const thumb = el.querySelector('.slider-thumb');
        if (thumb) thumb.style.left = `${clickPct}%`;
        triggerOtterEvent(comp, 'changed');
      });
    } else if (comp.kind === 'text box') {
      el.contentEditable = true;
      el.style.cursor = 'text';
      el.addEventListener('input', () => {
        comp.properties.text = el.innerText;
        triggerOtterEvent(comp, 'changed');
      });
    }
  }

  function bindDesignBehaviors(el, comp) {
    if (['heading', 'text', 'button', 'primary button', 'danger button'].includes(comp.kind)) {
      el.title = 'Double-click to edit text';
      el.addEventListener('dblclick', (e) => {
        if (isLocked(comp)) return;
        e.stopPropagation();
        startInlineEdit(el, comp, 'text');
      });
    } else if (comp.kind === 'checkbox') {
      const span = el.querySelector('span');
      span?.addEventListener('dblclick', (e) => {
        e.stopPropagation();
        startInlineEdit(span, comp, 'text');
      });
    }

    el.draggable = !isLocked(comp);
    el.addEventListener('dragstart', (e) => {
      e.stopPropagation();
      if (isLocked(comp)) { e.preventDefault(); return; }
      // Absolute elements move freely with the pointer instead.
      const pos = getComputedStyle(el).position;
      if (pos === 'absolute' || pos === 'fixed') {
        e.preventDefault();
        return;
      }
      currentDraggedComponentId = comp.id;
      const grabRect = el.getBoundingClientRect();
      dragGrab = { x: (e.clientX - grabRect.left) / zoom, y: (e.clientY - grabRect.top) / zoom };
      // Dragging one of several selected components moves just that one.
      el.classList.add('is-dragging');
      e.dataTransfer.effectAllowed = 'move';
      e.dataTransfer.setData('application/json', JSON.stringify({
        type: 'move-component',
        componentId: comp.id,
        parentId: comp.parentId
      }));
    });
    el.addEventListener('dragend', (e) => {
      e.stopPropagation();
      currentDraggedComponentId = null;
      el.classList.remove('is-dragging');
      hideDropMarkers();
    });

    el.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || isLocked(comp)) return;
      const pos = getComputedStyle(el).position;
      if ((pos === 'absolute' || pos === 'fixed') && !e.ctrlKey && !e.metaKey && !e.shiftKey) {
        e.stopPropagation();
        startFreeMove(e, comp);
      }
    });

    el.addEventListener('click', (e) => {
      e.stopPropagation();
      if (suppressClick) return;
      uiModel.select(unlockedAncestor(comp).id, e.ctrlKey || e.metaKey || e.shiftKey);
    });

    el.addEventListener('contextmenu', (e) => {
      e.preventDefault();
      e.stopPropagation();
      const target = unlockedAncestor(comp);
      if (!uiModel.isSelected(target.id)) uiModel.select(target.id);
      openContextMenu(e.clientX, e.clientY, target);
    });
  }

  // ---------------------------------------------------------------------------
  // Viewport: drop targets, hover, marquee, zoom, pan, auto-scroll
  // ---------------------------------------------------------------------------

  let suppressClick = false;
  // Where the pointer held the element being dragged (CSS px), so a drop into
  // a Free layout container puts it exactly where it was let go.
  let dragGrab = { x: 0, y: 0 };
  // How far the drop preview snapped (screen px); the drop applies it too.
  let freeDropNudge = { dx: 0, dy: 0 };
  document.addEventListener('dragstart', (e) => {
    draggingNewKind = e.target?.closest?.('.toolbox-item')?.getAttribute('data-kind') || null;
  }, true);
  document.addEventListener('dragend', () => { draggingNewKind = null; }, true);

  function bindViewport() {
    viewportEl.addEventListener('dragover', (e) => {
      e.preventDefault();
      if (isInteractMode) return;
      e.dataTransfer.dropEffect = currentDraggedComponentId ? 'move' : 'copy';
      autoScroll(e.clientX, e.clientY);
      const root = uiModel.getRoot();
      const hit = root && performHitTest(e.clientX, e.clientY, currentDraggedComponentId, contentAreaEl(), root);
      currentHit = hit || null;
      if (hit) showDropMarkers(hit); else hideDropMarkers();
      if (hit && !hit.gridCell && actions.isFreeLayout(hit.targetComp)) {
        insertionLine.hidden = true;
        showFreeGhost(hit.targetComp, e.clientX, e.clientY);
      } else if (freeGhost) {
        freeGhost.hidden = true;
      }
    });

    viewportEl.addEventListener('dragleave', (e) => {
      if (!viewportEl.contains(e.relatedTarget)) {
        hideDropMarkers();
        currentHit = null;
      }
    });

    viewportEl.addEventListener('drop', (e) => {
      e.preventDefault();
      const dropNudge = freeDropNudge; // hideDropMarkers resets it
      hideDropMarkers();
      if (isInteractMode) return;
      const root = uiModel.getRoot();
      const hit = currentHit || (root && performHitTest(e.clientX, e.clientY, currentDraggedComponentId, contentAreaEl(), root));
      currentHit = null;
      const draggedId = currentDraggedComponentId;
      currentDraggedComponentId = null;
      if (!hit) return;

      let dragData = null;
      try {
        const jsonStr = e.dataTransfer.getData('application/json');
        if (jsonStr) dragData = JSON.parse(jsonStr);
      } catch { /* not ours */ }
      if (!dragData) {
        const otterKind = e.dataTransfer.getData('text/otter-kind');
        if (otterKind) dragData = { type: 'new-component', kind: otterKind };
      }
      if (!dragData) return;

      let placedId = null;
      if (dragData.type === 'new-component') {
        const child = uiModel.addChild(hit.targetComp.id, dragData.kind, {}, hit.insertIndex);
        styleNewContainer(child);
        placedId = child?.id;
      } else if (dragData.type === 'move-component') {
        const compId = dragData.componentId || draggedId;
        if (compId && uiModel.moveChild(compId, hit.targetComp.id, hit.insertIndex)) placedId = compId;
      }

      // A drop into a Free layout container: exactly where it was let go.
      if (placedId && !hit.gridCell && actions.isFreeLayout(hit.targetComp)) {
        const grab = dragData.type === 'move-component' ? dragGrab : { x: 0, y: 0 };
        actions.placeAt(uiModel.getComponent(placedId), hit.targetComp, e.clientX + dropNudge.dx, e.clientY + dropNudge.dy, grab, { isNew: dragData.type === 'new-component' });
      }
      dragGrab = { x: 0, y: 0 };

      // A drop onto a grid cell places the component in that cell explicitly.
      if (placedId && hit.gridCell) {
        const placed = uiModel.getComponent(placedId);
        const saveContext = { ...styles.context };
        styles.context = { breakpoint: styles.context.breakpoint, state: '' };
        styles.write(placed, {
          'grid-column': `${hit.gridCell.col} / span 1`,
          'grid-row': `${hit.gridCell.row} / span 1`
        }, { key: `grid-drop:${placedId}` });
        styles.context = saveContext;
      }
      window.dispatchEvent(new CustomEvent('css-updated', { detail: { source: 'drop' } }));
    });

    // Hover outline
    viewportEl.addEventListener('mousemove', (e) => {
      if (isInteractMode || currentDraggedComponentId || gestureActive) return;
      // Reveal the spacing handles while the pointer is over the selection.
      const primaryBox = selectionLayer.querySelector('.designer-selection-box.is-primary');
      if (primaryBox) {
        const r = primaryBox.getBoundingClientRect();
        const pad = 12;
        const inside = e.clientX >= r.left - pad && e.clientX <= r.right + pad && e.clientY >= r.top - pad && e.clientY <= r.bottom + pad;
        primaryBox.classList.toggle('is-hovered', inside);
      }
      const target = e.target.closest?.('[data-id]');
      const root = uiModel.getRoot();
      if (!target || !root || target.getAttribute('data-id') === root.id || !stageEl.contains(target)) {
        hoverBox.hidden = true;
        return;
      }
      showHover(target.getAttribute('data-id'));
    });
    viewportEl.addEventListener('mouseleave', () => { hoverBox.hidden = true; });

    // Background click deselects; drag on background draws a marquee.
    viewportEl.addEventListener('pointerdown', (e) => {
      if (isInteractMode) return;
      if (spaceHeld || e.button === 1) return startPan(e);
      if (e.button !== 0) return;
      const root = uiModel.getRoot();
      const area = contentAreaEl();
      const onBackground = e.target === viewportEl || e.target === stageEl || e.target === overlayEl;
      const onRootArea = e.target === area;
      if (onBackground || onRootArea) startMarquee(e, onRootArea ? root : null);
    });

    // Ctrl + wheel zooms around the pointer.
    viewportEl.addEventListener('wheel', (e) => {
      if (!(e.ctrlKey || e.metaKey)) return;
      e.preventDefault();
      const factor = Math.exp(-e.deltaY * 0.0015);
      setZoom(zoom * factor, { clientX: e.clientX, clientY: e.clientY });
    }, { passive: false });

    viewportEl.addEventListener('scroll', () => {
      if (!gestureActive) updateOverlay();
    });
    new ResizeObserver(() => { if (!gestureActive) updateOverlay(); }).observe(viewportEl);

    window.addEventListener('otter:highlight-component', (e) => {
      if (isInteractMode) return;
      const compId = e.detail?.id;
      if (!compId || uiModel.isSelected(compId)) { hoverBox.hidden = true; return; }
      showHover(compId);
    });
  }

  function showHover(compId) {
    const el = elementFor(compId);
    const comp = uiModel.getComponent(compId);
    if (!el || !comp || uiModel.isSelected(compId)) {
      hoverBox.hidden = true;
      return;
    }
    place(hoverBox, toOverlay(el.getBoundingClientRect()));
    hoverBadge.textContent = `${comp.name} (${comp.kind})`;
    hoverBox.hidden = false;
  }

  function startMarquee(e, rootComp) {
    const startX = e.clientX;
    const startY = e.clientY;
    const additive = e.ctrlKey || e.metaKey || e.shiftKey;
    const before = additive ? Array.from(uiModel.selectedIds) : [];
    let active = false;

    const move = (ev) => {
      const dx = ev.clientX - startX;
      const dy = ev.clientY - startY;
      if (!active && Math.hypot(dx, dy) < 5) return;
      active = true;
      const box = {
        left: Math.min(startX, ev.clientX), top: Math.min(startY, ev.clientY),
        right: Math.max(startX, ev.clientX), bottom: Math.max(startY, ev.clientY)
      };
      place(marqueeEl, toOverlay({ left: box.left, top: box.top, width: box.right - box.left, height: box.bottom - box.top }));
      marqueeEl.hidden = false;
      const hits = [];
      for (const el of stageEl.querySelectorAll('.canvas-element[data-id]')) {
        // Locked and hidden layers are not picked up by a marquee.
        if (el.classList.contains('is-designer-locked') || el.classList.contains('is-designer-hidden')) continue;
        const r = el.getBoundingClientRect();
        if (r.left >= box.left && r.right <= box.right && r.top >= box.top && r.bottom <= box.bottom) {
          // Only the outermost contained components, not every descendant.
          const parentHit = el.parentElement?.closest('.canvas-element[data-id]');
          const pr = parentHit?.getBoundingClientRect();
          if (pr && pr.left >= box.left && pr.right <= box.right && pr.top >= box.top && pr.bottom <= box.bottom) continue;
          hits.push(el.getAttribute('data-id'));
        }
      }
      stageEl.querySelectorAll('.is-marquee-hit').forEach(el => el.classList.remove('is-marquee-hit'));
      hits.forEach(id => elementFor(id)?.classList.add('is-marquee-hit'));
      marqueeEl.dataset.hits = hits.join(',');
    };
    const up = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      marqueeEl.hidden = true;
      stageEl.querySelectorAll('.is-marquee-hit').forEach(el => el.classList.remove('is-marquee-hit'));
      if (active) {
        const hits = (marqueeEl.dataset.hits || '').split(',').filter(Boolean);
        uiModel.selectMany([...new Set([...before, ...hits])]);
        // The click that follows a marquee must not reselect the root.
        suppressClick = true;
        setTimeout(() => { suppressClick = false; }, 0);
      } else if (rootComp) {
        uiModel.select(rootComp.id, additive);
      } else if (!additive) {
        uiModel.select(null);
      }
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  }

  function startPan(e) {
    e.preventDefault();
    const startX = e.clientX;
    const startY = e.clientY;
    const startLeft = viewportEl.scrollLeft;
    const startTop = viewportEl.scrollTop;
    viewportEl.classList.add('is-panning');
    const move = (ev) => {
      viewportEl.scrollLeft = startLeft - (ev.clientX - startX);
      viewportEl.scrollTop = startTop - (ev.clientY - startY);
    };
    const up = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      viewportEl.classList.remove('is-panning');
    };
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', up);
  }

  let autoScrollFrame = null;
  function autoScroll(clientX, clientY) {
    const rect = viewportEl.getBoundingClientRect();
    const edge = 48;
    const speed = (d) => Math.ceil((edge - d) / 3);
    let dx = 0;
    let dy = 0;
    if (clientY - rect.top < edge) dy = -speed(clientY - rect.top);
    else if (rect.bottom - clientY < edge) dy = speed(rect.bottom - clientY);
    if (clientX - rect.left < edge) dx = -speed(clientX - rect.left);
    else if (rect.right - clientX < edge) dx = speed(rect.right - clientX);
    if (!dx && !dy) return;
    cancelAnimationFrame(autoScrollFrame);
    autoScrollFrame = requestAnimationFrame(() => {
      viewportEl.scrollLeft += dx;
      viewportEl.scrollTop += dy;
    });
  }

  function setZoom(next, anchor = null) {
    const clamped = Math.min(4, Math.max(0.2, next));
    if (Math.abs(clamped - zoom) < 0.001) return;
    const rect = viewportEl.getBoundingClientRect();
    const ax = anchor ? anchor.clientX - rect.left : rect.width / 2;
    const ay = anchor ? anchor.clientY - rect.top : rect.height / 2;
    const contentX = (viewportEl.scrollLeft + ax) / zoom;
    const contentY = (viewportEl.scrollTop + ay) / zoom;
    zoom = clamped;
    stageEl.style.zoom = String(zoom);
    viewportEl.scrollLeft = contentX * zoom - ax;
    viewportEl.scrollTop = contentY * zoom - ay;
    renderTopbarState();
    updateOverlay();
  }

  function zoomBy(direction) {
    const next = direction > 0
      ? ZOOM_STEPS.find(z => z > zoom + 0.001) ?? ZOOM_STEPS[ZOOM_STEPS.length - 1]
      : [...ZOOM_STEPS].reverse().find(z => z < zoom - 0.001) ?? ZOOM_STEPS[0];
    setZoom(next);
  }

  function zoomToFit() {
    const wrapper = stageEl.querySelector('#canvasWindowWrapper');
    if (!wrapper) return;
    const r = wrapper.getBoundingClientRect();
    const naturalW = r.width / zoom;
    const naturalH = r.height / zoom;
    const fit = Math.min((viewportEl.clientWidth - 80) / naturalW, (viewportEl.clientHeight - 80) / naturalH, 2);
    setZoom(fit);
    viewportEl.scrollTop = 0;
  }

  // Fit the selected components in view (Penpot's Shift+2).
  function zoomToSelection() {
    const els = uiModel.getSelectedComponents().map(c => elementFor(c.id)).filter(Boolean);
    if (els.length === 0) return false;
    const rects = els.map(el => el.getBoundingClientRect());
    const left = Math.min(...rects.map(r => r.left));
    const top = Math.min(...rects.map(r => r.top));
    const right = Math.max(...rects.map(r => r.right));
    const bottom = Math.max(...rects.map(r => r.bottom));
    const vp = viewportEl.getBoundingClientRect();
    // Content coordinates (unzoomed) of the selection box.
    const cx = (viewportEl.scrollLeft + (left + right) / 2 - vp.left) / zoom;
    const cy = (viewportEl.scrollTop + (top + bottom) / 2 - vp.top) / zoom;
    const w = Math.max(1, (right - left) / zoom);
    const h = Math.max(1, (bottom - top) / zoom);
    const next = Math.min(2, Math.max(0.2, Math.min((viewportEl.clientWidth - 120) / w, (viewportEl.clientHeight - 120) / h)));
    zoom = next;
    stageEl.style.zoom = String(zoom);
    viewportEl.scrollLeft = cx * zoom - viewportEl.clientWidth / 2;
    viewportEl.scrollTop = cy * zoom - viewportEl.clientHeight / 2;
    renderTopbarState();
    updateOverlay();
    return true;
  }

  // A new row, column or card gets room inside (12px padding) and a card
  // rounded corners - in the stylesheet, where they are easy to change.
  function styleNewContainer(child) {
    if (!child || !cssAstManager) return;
    if (['row', 'column', 'card'].includes(child.kind)) cssAstManager.setProperty(`#${child.name}`, 'padding', '12px');
    if (child.kind === 'card') cssAstManager.setProperty(`#${child.name}`, 'border-radius', '12px');
  }

  function showDropMarkers(hit) {
    place(targetBox, toOverlay(hit.containerRect));
    const kindName = hit.targetComp.kind || 'container';
    targetBadge.textContent = hit.gridCell
      ? `${hit.targetComp.name} · column ${hit.gridCell.col}, row ${hit.gridCell.row}`
      : `${hit.targetComp.name} [${kindName}]`;
    targetBox.hidden = false;

    if (hit.gridCell) {
      place(cellBox, toOverlay(hit.gridCell.rect));
      cellBox.hidden = false;
      insertionLine.hidden = true;
      return;
    }
    cellBox.hidden = true;
    const geo = hit.lineGeometry;
    const pos = toOverlay({ left: geo.x, top: geo.y, width: 0, height: 0 });
    insertionLine.className = `designer-insertion-line ${hit.isRow ? 'is-vertical' : 'is-horizontal'}`;
    place(insertionLine, { left: pos.left, top: pos.top, width: hit.isRow ? 3 : geo.width, height: hit.isRow ? geo.height : 3 });
    insertionLine.hidden = false;
  }

  function hideDropMarkers() {
    targetBox.hidden = true;
    insertionLine.hidden = true;
    cellBox.hidden = true;
    if (freeGhost) freeGhost.hidden = true;
    if (guidesLayer) guidesLayer.innerHTML = '';
    freeDropNudge = { dx: 0, dy: 0 };
  }

  // Dragging over a Free layout container: a dashed outline exactly where the
  // control will land, at the size it will have, with its x / y. A control
  // being moved keeps its size and where it is held; a new one gets its
  // default size (FREE_DEFAULT_SIZES; about 100 x 36 when it sizes itself).
  function showFreeGhost(container, clientX, clientY) {
    if (!freeGhost) return;
    let width = 100;
    let height = 36;
    let grab = { x: 0, y: 0 };
    const movingEl = currentDraggedComponentId && elementFor(currentDraggedComponentId);
    if (movingEl) {
      const r = movingEl.getBoundingClientRect();
      width = r.width / zoom;
      height = r.height / zoom;
      grab = dragGrab;
    } else if (draggingNewKind) {
      const size = FREE_DEFAULT_SIZES[draggingNewKind] || {};
      width = size.width || size.minWidth || (['text', 'heading', 'checkbox'].includes(draggingNewKind) ? 90 : 100);
      height = size.height || (['heading'].includes(draggingNewKind) ? 32 : ['text', 'checkbox'].includes(draggingNewKind) ? 22 : 36);
    }
    const containerEl = elementFor(container.id);
    // Snap the preview like a move (alignment and equal spacing), and let the
    // drop land exactly there.
    const { siblings, parent } = snapContext(containerEl, movingEl || null);
    const raw = { left: clientX - grab.x * zoom, top: clientY - grab.y * zoom, width: width * zoom, height: height * zoom };
    const snap = snapMove(raw, siblings, parent, { threshold: SNAP_PX * zoom, zoom });
    freeDropNudge = { dx: snap.dx, dy: snap.dy };
    guidesLayer.innerHTML = '';
    drawSnapLines(snap.lines);
    drawSpacingGuides(snap.gaps, snap.measures);
    const pos = actions.positionFor(container, clientX + snap.dx, clientY + snap.dy, grab);
    if (!pos) { freeGhost.hidden = true; return; }
    const cRect = containerEl.getBoundingClientRect();
    const cs = getComputedStyle(containerEl);
    const left = cRect.left + ((parseFloat(cs.borderLeftWidth) || 0) + pos.left) * zoom;
    const top = cRect.top + ((parseFloat(cs.borderTopWidth) || 0) + pos.top) * zoom;
    place(freeGhost, toOverlay({ left, top, width: width * zoom, height: height * zoom }));
    freeGhostLabel.textContent = `x ${pos.left}  ·  y ${pos.top}`;
    freeGhost.hidden = false;
    targetBadge.textContent = `${container.name} · Free layout`;
  }

  // Hit testing on real DOM bounding boxes and computed layout.
  // skipEl: elements to look past (the controls being moved, which are
  // under the pointer).
  function performHitTest(clientX, clientY, draggedId, contentArea, root, skipEl = null) {
    const elements = document.elementsFromPoint(clientX, clientY);
    if (!elements || elements.length === 0 || !contentArea) return null;

    let targetEl = null;
    let targetComp = null;
    for (const el of elements) {
      if (!stageEl.contains(el)) continue;
      if (skipEl && skipEl(el)) continue;
      if (el === contentArea || el.getAttribute('data-id') === root.id) {
        targetEl = contentArea;
        targetComp = root;
        break;
      }
      const compId = el.getAttribute('data-id');
      if (compId) {
        const comp = uiModel.getComponent(compId);
        if (comp) {
          targetEl = el;
          targetComp = comp;
          break;
        }
      }
    }
    if (!targetEl && elements.some(el => el.closest?.('#canvasWindowWrapper'))) {
      targetEl = contentArea;
      targetComp = root;
    }
    if (!targetEl || !targetComp) return null;

    // Never drop onto itself or into its own descendants.
    if (draggedId && (targetComp.id === draggedId || uiModel.isDescendantOf(targetComp.id, draggedId))) {
      let ancestor = targetComp.parentId ? uiModel.getComponent(targetComp.parentId) : null;
      while (ancestor && (ancestor.id === draggedId || uiModel.isDescendantOf(ancestor.id, draggedId))) {
        ancestor = ancestor.parentId ? uiModel.getComponent(ancestor.parentId) : null;
      }
      if (!ancestor) return null;
      targetComp = ancestor;
      targetEl = elementFor(targetComp.id);
      if (!targetEl) return null;
    }

    // A leaf control resolves to its parent container, before or after itself.
    const schema = ComponentSchema[targetComp.kind] || {};
    let dropBeforeEl = null;
    let dropAfterEl = null;
    if (!schema.isContainer && targetComp.id !== root.id) {
      const parentComp = targetComp.parentId ? uiModel.getComponent(targetComp.parentId) : root;
      const parentEl = elementFor(parentComp.id);
      if (!parentEl) return null;
      const leafEl = targetEl;
      targetComp = parentComp;
      targetEl = parentEl;
      const leafRect = leafEl.getBoundingClientRect();
      const parentStyle = getComputedStyle(targetEl);
      const isParentRow = targetComp.kind === 'row' || (parentStyle.display.includes('flex') && parentStyle.flexDirection.startsWith('row'));
      const before = isParentRow ? clientX < leafRect.left + leafRect.width / 2 : clientY < leafRect.top + leafRect.height / 2;
      if (before) dropBeforeEl = leafEl; else dropAfterEl = leafEl;
    }

    const computed = getComputedStyle(targetEl);
    const containerRect = targetEl.getBoundingClientRect();
    const directChildren = Array.from(targetEl.children).filter(c => {
      const cid = c.getAttribute('data-id');
      return cid && cid !== draggedId && !c.classList.contains('is-dragging');
    });

    // Grid containers: target a cell.
    if (computed.display.includes('grid')) {
      const tracks = gridTracks(targetEl);
      if (tracks) {
        const col = tracks.columns.findIndex(c => clientX >= c.start && clientX <= c.end + 1);
        const row = tracks.rows.findIndex(r => clientY >= r.start && clientY <= r.end + 1);
        const c = tracks.columns[col];
        const r = tracks.rows[row];
        // Only an empty cell is a placement target; over a child, fall back
        // to ordinary before/after insertion.
        const occupied = c && r && directChildren.some(child => {
          const cr = child.getBoundingClientRect();
          const cx = cr.left + cr.width / 2;
          const cy = cr.top + cr.height / 2;
          return cx >= c.start && cx <= c.end && cy >= r.start && cy <= r.end;
        });
        if (col >= 0 && row >= 0 && !occupied) {
          return {
            targetEl, targetComp, containerRect,
            isRow: true,
            insertIndex: directChildren.length,
            gridCell: { col: col + 1, row: row + 1, rect: { left: c.start, top: r.start, width: c.end - c.start, height: r.end - r.start } },
            lineGeometry: { x: 0, y: 0, width: 0, height: 0 }
          };
        }
      }
    }

    const isRow = targetComp.kind === 'row' || (computed.display.includes('flex') && computed.flexDirection.startsWith('row'));
    let insertIndex = 0;
    let lineX = 0;
    let lineY = 0;
    let lineWidth = 0;
    let lineHeight = 0;

    if (directChildren.length === 0) {
      if (isRow) {
        lineX = containerRect.left + 16;
        lineY = containerRect.top + 10;
        lineWidth = 3;
        lineHeight = Math.max(28, containerRect.height - 20);
      } else {
        lineX = containerRect.left + 14;
        lineY = containerRect.top + 14;
        lineWidth = Math.max(48, containerRect.width - 28);
        lineHeight = 3;
      }
    } else if (dropBeforeEl || dropAfterEl) {
      const refEl = dropBeforeEl || dropAfterEl;
      const refIdx = directChildren.indexOf(refEl);
      insertIndex = dropBeforeEl ? Math.max(0, refIdx) : (refIdx >= 0 ? refIdx + 1 : directChildren.length);
      const refRect = refEl.getBoundingClientRect();
      if (isRow) {
        lineY = refRect.top;
        lineHeight = refRect.height;
        lineWidth = 3;
        lineX = dropBeforeEl ? refRect.left - 2 : refRect.right + 2;
      } else {
        lineX = containerRect.left + 8;
        lineWidth = Math.max(40, containerRect.width - 16);
        lineHeight = 3;
        lineY = dropBeforeEl ? refRect.top - 2 : refRect.bottom + 2;
      }
    } else {
      insertIndex = directChildren.length;
      for (let i = 0; i < directChildren.length; i++) {
        const cRect = directChildren[i].getBoundingClientRect();
        if (isRow ? clientX < cRect.left + cRect.width / 2 : clientY < cRect.top + cRect.height / 2) {
          insertIndex = i;
          break;
        }
      }
      const first = directChildren[0].getBoundingClientRect();
      const last = directChildren[directChildren.length - 1].getBoundingClientRect();
      if (isRow) {
        lineWidth = 3;
        if (insertIndex === 0) {
          lineX = first.left - 3; lineY = first.top; lineHeight = first.height;
        } else if (insertIndex === directChildren.length) {
          lineX = last.right + 3; lineY = last.top; lineHeight = last.height;
        } else {
          const prev = directChildren[insertIndex - 1].getBoundingClientRect();
          const next = directChildren[insertIndex].getBoundingClientRect();
          lineX = (prev.right + next.left) / 2;
          lineY = Math.min(prev.top, next.top);
          lineHeight = Math.max(prev.height, next.height);
        }
      } else {
        lineX = containerRect.left + 8;
        lineWidth = Math.max(40, containerRect.width - 16);
        lineHeight = 3;
        if (insertIndex === 0) lineY = first.top - 3;
        else if (insertIndex === directChildren.length) lineY = last.bottom + 3;
        else {
          const prev = directChildren[insertIndex - 1].getBoundingClientRect();
          const next = directChildren[insertIndex].getBoundingClientRect();
          lineY = (prev.bottom + next.top) / 2;
        }
      }
    }

    return {
      targetEl, targetComp, containerRect, isRow, insertIndex,
      lineGeometry: { x: lineX, y: lineY, width: lineWidth, height: lineHeight }
    };
  }

  // ---------------------------------------------------------------------------
  // Commands, keyboard and context menu (designer/actions.js, commands.js,
  // context-menu.js). The canvas supplies the DOM-dependent parts.
  // ---------------------------------------------------------------------------

  const actions = createDesignerActions({
    uiModel, styles, cssAstManager, viewState,
    canvas: { elementFor, zoomBy, setZoom, zoomToFit, zoomToSelection, getZoom: () => zoom }
  });
  const commands = designerCommands(actions);
  const contextMenu = createDesignerContextMenu({ uiModel, styles, actions, commands });

  function openContextMenu(x, y, comp) {
    contextMenu.open(x, y, comp);
  }

  function isDesignerVisible() {
    return containerEl.offsetParent !== null && !isInteractMode;
  }

  // The designer owns the keyboard while it is visible and the pointer or
  // focus is in it - never while typing in a field or working in another panel.
  function designerHasKeyboard() {
    const active = document.activeElement;
    const tag = active ? active.tagName.toLowerCase() : '';
    if (['input', 'textarea', 'select'].includes(tag) || active?.isContentEditable) return false;
    if (!isDesignerVisible()) return false;
    return containerEl.matches(':hover') || containerEl.contains(active) || active === document.body;
  }

  function bindKeyboard() {
    // Space held: drag to pan.
    window.addEventListener('keyup', (e) => {
      if (e.code === 'Space') {
        spaceHeld = false;
        viewportEl.classList.remove('is-pan-ready');
      }
    });
    window.addEventListener('keydown', (e) => {
      if (e.code === 'Space' && !e.repeat && designerHasKeyboard()) {
        spaceHeld = true;
        viewportEl.classList.add('is-pan-ready');
        e.preventDefault();
      }
    });
    installDesignerKeyboard(commands, { isActive: designerHasKeyboard });
  }

  // ---------------------------------------------------------------------------
  // Wiring
  // ---------------------------------------------------------------------------

  mount();
  update();

  uiModel.subscribe((type) => {
    if (type === 'select') {
      // Selection does not change the DOM, so keep the elements (a rebuild
      // between the two clicks of a double-click would lose the double-click).
      const root = uiModel.getRoot();
      stageEl.querySelector('#canvasWindowWrapper')?.classList.toggle('is-selected-window', !!root && uiModel.isSelected(root.id) && !isInteractMode);
      renderTopbarState();
      renderBreadcrumbs();
      applyForcedState();
      updateOverlay();
      return;
    }
    if (gestureActive && type === 'property') {
      // During a drag, source-backed writes (width 240) are applied inline
      // immediately; a full rebuild would destroy the element being dragged.
      const area = contentAreaEl();
      if (area && realRender) applyRealRenderNow(area);
      else if (area) applySourceInline(area);
      updateOverlay();
      return;
    }
    update();
  });

  window.addEventListener('css-updated', (e) => {
    // Style changes do not change the component tree: refresh the styles and
    // the overlay only, and let the real render catch up in the background.
    if (e.detail?.source === 'rename') return update();
    refreshUserStyles();
    applyForcedState();
    if (!gestureActive) updateOverlay();
    scheduleRealRender();
  });

  window.addEventListener('otter:source-synced', (e) => {
    if (e.detail?.file && e.detail.file.endsWith('.css')) {
      refreshUserStyles();
      updateOverlay();
      scheduleRealRender();
    }
  });

  window.addEventListener('otter:style-context', () => update());
  // Added by clicking a Components tile: in a Free container it gets its own
  // spot, cascading down from the top-left so new ones do not stack.
  window.addEventListener('otter:component-added', (e) => {
    const parent = uiModel.getComponent(e.detail?.parentId);
    const child = uiModel.getComponent(e.detail?.id);
    styleNewContainer(child);
    if (!parent || !child || !actions.isFreeLayout(parent)) return;
    const parentEl = elementFor(parent.id);
    if (!parentEl) return;
    const step = ((parent.children || []).length - 1) % 10;
    const rect = parentEl.getBoundingClientRect();
    actions.placeAt(child, parent, rect.left + (24 + step * 20) * zoom, rect.top + (24 + step * 20) * zoom, { x: 0, y: 0 }, { isNew: true });
  });
  window.addEventListener('otter:free-layout', (e) => {
    const comp = uiModel.getComponent(e.detail?.id);
    if (comp) actions.setFreeLayout(comp, Boolean(e.detail.on));
  });
  window.addEventListener('otter:view-state', () => { applyViewState(); updateOverlay(); });

  return { actions, commands, isDesignerVisible };
}

function cssEscape(value) {
  return window.CSS && CSS.escape ? CSS.escape(value) : String(value).replace(/"/g, '\\"');
}

function escapeHtml(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
