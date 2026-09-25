// canvas.js - Visual Designer Canvas with GrapesJS-style decoupled interaction overlay, resize handles, and shortcuts
// Keeps Otter's structured UI model as single source of truth; relies on real browser CSS/Flex/Grid layout engine.

import { ComponentSchema } from '../model/schema.js';
import { generateOtterSource } from '../compiler/otter-generator.js';
import { fetchRealRender, applyRealRender } from './real-style.js';

export function renderCanvas(containerEl, uiModel, cssAstManager) {
  let currentDraggedComponentId = null;
  let currentHit = null;
  let isInteractMode = false;
  let realRender = null;
  let realRenderTimer = null;
  let realRenderSerial = 0;

  function update() {
    const root = uiModel.getRoot();
    if (!root) {
      containerEl.innerHTML = '<div class="empty-state">No active window</div>';
      return;
    }

    // Inject active user CSS stylesheet dynamically into the canvas container
    const userCss = cssAstManager ? cssAstManager.generateCss() : '';

    containerEl.innerHTML = `
      <style id="canvasUserCss">
        ${userCss}
      </style>
      <div class="canvas-topbar">
        <div class="canvas-breadcrumbs" id="canvasBreadcrumbs"></div>
        <div class="canvas-actions">
          <div class="canvas-mode-toggle">
            <button class="canvas-toggle-btn ${!isInteractMode ? 'is-active' : ''}" id="btnCanvasDesignMode" title="Visual Designer & Layout Manipulation Mode">🎨 Design</button>
            <button class="canvas-toggle-btn ${isInteractMode ? 'is-active' : ''}" id="btnCanvasInteractMode" title="Test User Interaction & Event Handlers directly on canvas">⚡ Live Interact</button>
          </div>
          <button class="icon-btn" id="canvasUndoBtn" title="Undo (Ctrl+Z)" ${!uiModel.canUndo() || isInteractMode ? 'disabled style="opacity:0.35;cursor:not-allowed;"' : ''}>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 7v6h6M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/></svg>
          </button>
          <button class="icon-btn" id="canvasRedoBtn" title="Redo (Ctrl+Y)" ${!uiModel.canRedo() || isInteractMode ? 'disabled style="opacity:0.35;cursor:not-allowed;"' : ''}>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 7v6h-6M3 17a9 9 0 0 1 9-9 9 9 0 0 1 6 2.3L21 13"/></svg>
          </button>
          <span class="canvas-zoom-label">100% (CSS/Flex Engine)</span>
        </div>
      </div>
      <div class="canvas-viewport" id="canvasViewport">
        <div class="canvas-window-wrapper otter-window ${uiModel.isSelected(root.id) && !isInteractMode ? 'is-selected-window' : ''}" id="canvasWindowWrapper">
          <div class="window-titlebar">
            <div class="window-dots">
              <span class="dot dot-red"></span>
              <span class="dot dot-yellow"></span>
              <span class="dot dot-green"></span>
            </div>
            <span class="window-title-text" id="canvasWindowTitleText">${escapeHtml(root.properties.title || 'Otter Application')}</span>
            <span class="window-dimension-badge">${cssAstManager ? (cssAstManager.getProperty('#' + root.name, 'width') || '740px') : '740px'}</span>
          </div>
          <div class="window-content-area" id="${root.name}" data-id="${root.id}"></div>
        </div>

        <!-- Decoupled Designer Overlay -->
        <div class="designer-canvas-overlay" id="designerOverlay" style="${isInteractMode ? 'display: none;' : ''}">
          <div id="designerSelectionContainer"></div>
          <div class="designer-hover-box" id="designerHoverBox" style="display: none;">
            <span class="designer-hover-badge" id="designerHoverBadge"></span>
          </div>
          <div class="designer-target-box" id="designerTargetBox" style="display: none;">
            <span class="designer-target-badge" id="designerTargetBadge"></span>
          </div>
          <div class="designer-insertion-line" id="designerInsertionLine" style="display: none;">
            <div class="line-dot dot-start"></div>
            <div class="line-dot dot-end"></div>
          </div>
        </div>
      </div>
    `;

    // Canvas Mode Switcher listeners
    containerEl.querySelector('#btnCanvasDesignMode')?.addEventListener('click', () => {
      if (isInteractMode) {
        isInteractMode = false;
        update();
      }
    });
    containerEl.querySelector('#btnCanvasInteractMode')?.addEventListener('click', () => {
      if (!isInteractMode) {
        isInteractMode = true;
        update();
      }
    });

    renderBreadcrumbs(containerEl.querySelector('#canvasBreadcrumbs'));
    const contentArea = containerEl.querySelector(`#${root.name}`);
    const viewportEl = containerEl.querySelector('#canvasViewport');
    const windowWrapper = containerEl.querySelector('#canvasWindowWrapper');

    // Undo / Redo button listeners
    const undoBtn = containerEl.querySelector('#canvasUndoBtn');
    if (undoBtn) {
      undoBtn.addEventListener('click', () => uiModel.undo());
    }
    const redoBtn = containerEl.querySelector('#canvasRedoBtn');
    if (redoBtn) {
      redoBtn.addEventListener('click', () => uiModel.redo());
    }

    // Root title inline edit
    const titleTextEl = containerEl.querySelector('#canvasWindowTitleText');
    if (titleTextEl && !isInteractMode) {
      titleTextEl.style.cursor = 'text';
      titleTextEl.title = 'Double-click to edit title';
      titleTextEl.addEventListener('dblclick', (e) => {
        e.stopPropagation();
        startInlineEdit(titleTextEl, root, 'title');
      });
    }

    // Viewport background click deselects
    viewportEl.addEventListener('click', (e) => {
      if (!isInteractMode && e.target === viewportEl) {
        uiModel.select(null);
      }
    });

    // Root click selects window if in design mode
    contentArea.addEventListener('click', (e) => {
      if (!isInteractMode && e.target === contentArea) {
        uiModel.select(root.id);
      }
    });

    const titlebarEl = containerEl.querySelector('.window-titlebar');
    if (titlebarEl) {
      titlebarEl.addEventListener('click', (e) => {
        if (!isInteractMode && e.target !== titleTextEl) {
          uiModel.select(root.id);
        }
      });
    }

    // Recursively render child components into contentArea
    if (root.children && root.children.length > 0) {
      for (let i = 0; i < root.children.length; i++) {
        const childId = root.children[i];
        const child = uiModel.getComponent(childId);
        if (child) {
          contentArea.appendChild(renderCanvasComponent(child, root.id, i));
        }
      }
    } else {
      const promptEl = document.createElement('div');
      promptEl.className = 'empty-canvas-prompt';
      promptEl.innerHTML = `
        <span class="prompt-icon">🎨</span>
        <span class="prompt-title">Drag components from the Toolbox</span>
        <span class="prompt-desc">Drop rows, columns, cards, buttons, or inputs here to start designing your application.</span>
      `;
      contentArea.appendChild(promptEl);
    }

    // Look like the real program: reuse the last real render right away so the
    // canvas never flashes its own approximation, then refresh it from the
    // production compiler for the current source.
    if (realRender) applyRealRender(contentArea, realRender);
    scheduleRealRender();

    // Attach designer interaction layer to viewport (only in Design mode)
    if (!isInteractMode) {
      setupDesignerInteraction(viewportEl, contentArea, root);
      updateOverlay();
    }
  }

  function scheduleRealRender() {
    clearTimeout(realRenderTimer);
    realRenderTimer = setTimeout(async () => {
      const serial = ++realRenderSerial;
      try {
        const code = generateOtterSource(uiModel);
        const css = cssAstManager ? cssAstManager.generateCss() : '';
        const real = await fetchRealRender(code, css);
        if (serial !== realRenderSerial) return;
        realRender = real;
        const root = uiModel.getRoot();
        const area = root && containerEl.querySelector(`#${root.name}`);
        if (area) {
          applyRealRender(area, realRender);
          updateOverlay();
        }
      } catch (err) {
        console.warn('Otter Studio: real render unavailable, showing approximate canvas.', err);
      }
    }, 300);
  }

  function updateOverlay() {
    if (isInteractMode) return;
    const viewportEl = containerEl.querySelector('#canvasViewport');
    const overlayEl = containerEl.querySelector('#designerOverlay');
    const selectionContainer = containerEl.querySelector('#designerSelectionContainer');
    const windowWrapper = containerEl.querySelector('#canvasWindowWrapper');
    const root = uiModel.getRoot();
    if (!viewportEl || !overlayEl || !selectionContainer || !root) return;

    selectionContainer.innerHTML = '';
    const vpRect = viewportEl.getBoundingClientRect();
    const scrollLeft = viewportEl.scrollLeft;
    const scrollTop = viewportEl.scrollTop;

    for (const selectedId of uiModel.selectedIds) {
      let targetEl = null;
      if (selectedId === root.id) {
        targetEl = windowWrapper;
      } else {
        targetEl = containerEl.querySelector(`[data-id="${selectedId}"]`);
      }
      if (!targetEl) continue;

      const comp = uiModel.getComponent(selectedId);
      if (!comp) continue;

      const elRect = targetEl.getBoundingClientRect();
      const left = elRect.left - vpRect.left + scrollLeft;
      const top = elRect.top - vpRect.top + scrollTop;
      const width = elRect.width;
      const height = elRect.height;

      const isPrimary = (selectedId === uiModel.selectedId);

      const box = document.createElement('div');
      box.className = `designer-selection-box ${isPrimary ? 'is-primary' : 'is-multi'}`;
      box.setAttribute('data-selection-id', selectedId);
      box.style.left = `${left}px`;
      box.style.top = `${top}px`;
      box.style.width = `${width}px`;
      box.style.height = `${height}px`;

      if (isPrimary) {
        // Floating Selection Badge on Overlay
        const badge = document.createElement('div');
        badge.className = 'designer-selection-badge';
        badge.innerHTML = `
          <span class="badge-name">${escapeHtml(comp.name)}</span>
          <span class="badge-kind">${escapeHtml(comp.kind)}</span>
          <div class="badge-actions">
            ${comp.id !== root.id ? `
              <button class="badge-btn badge-dup" title="Duplicate (Ctrl+D)">⎘</button>
              <button class="badge-btn badge-del" title="Delete (Del)">×</button>
            ` : ''}
          </div>
        `;
        badge.querySelector('.badge-dup')?.addEventListener('click', (e) => {
          e.stopPropagation();
          uiModel.duplicateComponent(comp.id, cssAstManager);
        });
        badge.querySelector('.badge-del')?.addEventListener('click', (e) => {
          e.stopPropagation();
          uiModel.removeComponent(comp.id);
        });
        box.appendChild(badge);

        // Attach Overlay Resize Handles (E, S, SE)
        ['handle-e', 'handle-s', 'handle-se'].forEach(handleClass => {
          const handle = document.createElement('div');
          handle.className = `designer-resize-handle ${handleClass}`;
          attachOverlayResize(handle, handleClass, targetEl, comp, viewportEl, box);
          box.appendChild(handle);
        });
      }

      selectionContainer.appendChild(box);
    }
  }

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
      const newText = input.value.trim();
      uiModel.setProperty(comp.id, propKey, newText);
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

    input.addEventListener('blur', () => {
      commit();
    });
  }

  function triggerOtterEvent(comp, eventKind) {
    const events = uiModel.getEvents(comp.id);
    const handler = events[eventKind];

    const logToStudio = (msg) => {
      const outBody = document.getElementById('programOutputBody');
      if (outBody) {
        const line = document.createElement('div');
        line.className = 'log-line';
        line.innerHTML = `<span style="color:#60a5fa">[${comp.name}.${eventKind}]</span> ${escapeHtml(msg)}`;
        outBody.appendChild(line);
        outBody.scrollTop = outBody.scrollHeight;
      }
      const previewLog = document.getElementById('previewLogEntries');
      if (previewLog) {
        const time = new Date().toLocaleTimeString();
        const entry = document.createElement('div');
        entry.className = 'log-entry';
        entry.innerHTML = `<span class="log-time">[${time}]</span> <span style="color:#60a5fa">[${comp.name}]</span> ${escapeHtml(msg)}`;
        previewLog.appendChild(entry);
        previewLog.scrollTop = previewLog.scrollHeight;
      }
      console.log(`[Otter Interact: ${comp.name}.${eventKind}] ${msg}`);
    };

    if (!handler || !handler.trim()) {
      logToStudio(`Triggered ${eventKind} (no handler registered)`);
      return;
    }

    const lines = handler.split('\n');
    for (const raw of lines) {
      const line = raw.trim();
      if (!line || line.startsWith('#')) continue;

      if (line.startsWith('say ')) {
        const expr = line.slice(4).trim().replace(/^"(.*)"$/, '$1');
        logToStudio(`say: ${expr}`);
        continue;
      }

      const addMatch = line.match(/^add\s+(\d+)\s+to\s+([a-zA-Z0-9_]+)$/i);
      if (addMatch) {
        const amt = parseInt(addMatch[1], 10);
        const targetName = addMatch[2];
        const allComps = uiModel.getAllComponents();
        const target = allComps.find(c => c.name === targetName);
        if (target) {
          if (typeof target.properties.value === 'number') {
            target.properties.value += amt;
            uiModel.notify('property', { id: target.id });
            logToStudio(`Added ${amt} to ${targetName}. New value: ${target.properties.value}`);
          } else {
            const num = parseInt(target.properties.text, 10);
            if (!isNaN(num)) {
              target.properties.text = String(num + amt);
              uiModel.notify('property', { id: target.id });
              logToStudio(`Added ${amt} to ${targetName}. New text: ${target.properties.text}`);
            }
          }
        }
        continue;
      }

      const subMatch = line.match(/^(?:remove|subtract)\s+(\d+)\s+from\s+([a-zA-Z0-9_]+)$/i);
      if (subMatch) {
        const amt = parseInt(subMatch[1], 10);
        const targetName = subMatch[2];
        const allComps = uiModel.getAllComponents();
        const target = allComps.find(c => c.name === targetName);
        if (target) {
          if (typeof target.properties.value === 'number') {
            target.properties.value = Math.max(0, target.properties.value - amt);
            uiModel.notify('property', { id: target.id });
            logToStudio(`Subtracted ${amt} from ${targetName}. New value: ${target.properties.value}`);
          } else {
            const num = parseInt(target.properties.text, 10);
            if (!isNaN(num)) {
              target.properties.text = String(num - amt);
              uiModel.notify('property', { id: target.id });
              logToStudio(`Subtracted ${amt} from ${targetName}. New text: ${target.properties.text}`);
            }
          }
        }
        continue;
      }

      const textMatch = line.match(/^([a-zA-Z0-9_]+)\s+has\s+text\s+(.+)$/i);
      if (textMatch) {
        const targetName = textMatch[1];
        const val = textMatch[2].trim().replace(/^"(.*)"$/, '$1');
        const target = uiModel.getAllComponents().find(c => c.name === targetName);
        if (target) {
          target.properties.text = val;
          uiModel.notify('property', { id: target.id });
          logToStudio(`${targetName} has text "${val}"`);
        }
        continue;
      }

      logToStudio(`Executed: ${line}`);
    }
  }

  function renderBreadcrumbs(crumbsEl) {
    if (!crumbsEl) return;
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
        sep.innerText = '›';
        crumbsEl.appendChild(sep);
      }
      const crumb = document.createElement('span');
      crumb.className = `crumb-item ${node.id === selected.id ? 'is-active' : ''}`;
      crumb.innerText = `${node.name} (${node.kind})`;
      crumb.addEventListener('click', () => uiModel.select(node.id));
      crumbsEl.appendChild(crumb);
    });
  }

  function renderCanvasComponent(comp, parentId, indexInParent) {
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

    // Component-specific content with canonical Otter runtime classes
    switch (comp.kind) {
      case 'row':
        el.classList.add('canvas-row', 'otter-row');
        break;
      case 'column':
        el.classList.add('canvas-column', 'otter-column');
        break;
      case 'card':
        el.classList.add('canvas-card', 'otter-card', 'task-item');
        break;
      case 'scroll':
        el.classList.add('canvas-scroll', 'otter-scroll');
        break;
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
        el.innerHTML = `
          <div class="slider-track"><div class="slider-thumb" style="left: ${props.value || 50}%;"></div></div>
        `;
        break;
      case 'dropdown':
        el.classList.add('canvas-dropdown', 'otter-dropdown', 'otter-select');
        el.innerHTML = `<span>${escapeHtml(props.placeholder || 'Select option...')}</span><span class="arrow">▾</span>`;
        break;
      case 'progress bar':
        el.classList.add('canvas-progress', 'otter-progress');
        const pct = Math.min(100, Math.max(0, ((props.value || 0) / (props.maximum || 100)) * 100));
        el.innerHTML = `<div class="progress-bar-fill" style="width:${pct}%;background:${props.foreground || '#3b82f6'};"></div>`;
        break;
      case 'image':
        el.classList.add('canvas-image', 'otter-image');
        el.innerHTML = `<img src="${escapeHtml(props.source || '')}" alt="" style="width:100%;height:100%;object-fit:cover;pointer-events:none;" />`;
        break;
    }

    // --- INTERACTIVE MODE BEHAVIORS ---
    if (isInteractMode) {
      if (['button', 'primary button', 'danger button'].includes(comp.kind)) {
        el.style.cursor = 'pointer';
        el.addEventListener('click', (e) => {
          e.stopPropagation();
          el.classList.add('btn-clicked');
          setTimeout(() => el.classList.remove('btn-clicked'), 150);
          triggerOtterEvent(comp, 'clicked');
        });
      } else if (comp.kind === 'checkbox') {
        const chk = el.querySelector('input[type="checkbox"]');
        if (chk) {
          chk.addEventListener('change', (e) => {
            e.stopPropagation();
            comp.properties.checked = chk.checked;
            triggerOtterEvent(comp, 'clicked');
          });
        }
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
    } else {
      // --- DESIGN MODE BEHAVIORS (Selection, Drag, Inline Edit) ---
      // Note: Application DOM remains pure. Zero designer badges or handles are inserted here.
      if (['heading', 'text', 'button', 'primary button', 'danger button'].includes(comp.kind)) {
        el.title = 'Double-click to edit text';
        el.addEventListener('dblclick', (e) => {
          e.stopPropagation();
          startInlineEdit(el, comp, 'text');
        });
      } else if (comp.kind === 'checkbox') {
        const span = el.querySelector('span');
        if (span) {
          span.title = 'Double-click to edit label';
          span.addEventListener('dblclick', (e) => {
            e.stopPropagation();
            startInlineEdit(span, comp, 'text');
          });
        }
      }

      // Draggable element handling
      if (comp.id !== uiModel.rootId) {
        el.draggable = true;
        el.addEventListener('dragstart', (e) => {
          e.stopPropagation();
          currentDraggedComponentId = comp.id;
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
          hideDropOverlay();
        });
      }

      // Click to select (Single click or Ctrl+Click multi-select)
      el.addEventListener('click', (e) => {
        e.stopPropagation();
        const multi = e.ctrlKey || e.metaKey;
        uiModel.select(comp.id, multi);
      });
    }

    // If it's a container, render children
    if (schema.isContainer && comp.children) {
      for (let i = 0; i < comp.children.length; i++) {
        const childId = comp.children[i];
        const child = uiModel.getComponent(childId);
        if (child) {
          el.appendChild(renderCanvasComponent(child, comp.id, i));
        }
      }
    }

    return el;
  }

  // =========================================================================
  // Decoupled Overlay Resize Handling (Mutates Supported Model/CSS Properties)
  // =========================================================================

  function attachOverlayResize(handleEl, handleClass, targetEl, comp, viewportEl, boxEl) {
    handleEl.addEventListener('mousedown', (e) => {
      e.stopPropagation();
      e.preventDefault();

      const startX = e.clientX;
      const startY = e.clientY;
      const startRect = targetEl.getBoundingClientRect();
      const selector = `#${comp.name}`;
      const initialWidth = comp.properties.width !== undefined ? comp.properties.width : (cssAstManager ? cssAstManager.getProperty(selector, 'width') : null);
      const initialHeight = comp.properties.height !== undefined ? comp.properties.height : (cssAstManager ? cssAstManager.getProperty(selector, 'height') : null);

      const tooltip = document.createElement('div');
      tooltip.className = 'resize-dimension-tooltip';
      viewportEl.appendChild(tooltip);

      let isCancelled = false;

      function onMouseMove(moveEvent) {
        if (isCancelled) return;
        moveEvent.preventDefault();
        const deltaX = moveEvent.clientX - startX;
        const deltaY = moveEvent.clientY - startY;

        const newW = Math.max(32, Math.round((startRect.width + deltaX) / 8) * 8);
        const newH = Math.max(28, Math.round((startRect.height + deltaY) / 8) * 8);

        if (handleClass === 'handle-e') {
          if (cssAstManager) cssAstManager.setProperty(selector, 'width', `${newW}px`);
          comp.properties.width = `${newW}px`;
          tooltip.textContent = `W: ${newW}px`;
          boxEl.style.width = `${newW}px`;
          targetEl.style.width = `${newW}px`;
        } else if (handleClass === 'handle-s') {
          if (cssAstManager) cssAstManager.setProperty(selector, 'height', `${newH}px`);
          comp.properties.height = `${newH}px`;
          tooltip.textContent = `H: ${newH}px`;
          boxEl.style.height = `${newH}px`;
          targetEl.style.height = `${newH}px`;
        } else {
          if (cssAstManager) {
            cssAstManager.setProperty(selector, 'width', `${newW}px`);
            cssAstManager.setProperty(selector, 'height', `${newH}px`);
          }
          comp.properties.width = `${newW}px`;
          comp.properties.height = `${newH}px`;
          tooltip.textContent = `${newW}px × ${newH}px`;
          boxEl.style.width = `${newW}px`;
          boxEl.style.height = `${newH}px`;
          targetEl.style.width = `${newW}px`;
          targetEl.style.height = `${newH}px`;
        }

        const vpRect = viewportEl.getBoundingClientRect();
        tooltip.style.left = `${moveEvent.clientX - vpRect.left + viewportEl.scrollLeft + 12}px`;
        tooltip.style.top = `${moveEvent.clientY - vpRect.top + viewportEl.scrollTop - 28}px`;

        window.dispatchEvent(new CustomEvent('css-updated', { detail: { selector, source: 'resize' } }));
      }

      function onKeyDown(keyEvent) {
        if (keyEvent.key === 'Escape') {
          keyEvent.preventDefault();
          keyEvent.stopPropagation();
          isCancelled = true;
          if (initialWidth !== null && initialWidth !== undefined) {
            if (cssAstManager) cssAstManager.setProperty(selector, 'width', initialWidth);
            comp.properties.width = initialWidth;
            targetEl.style.width = initialWidth;
          } else {
            if (cssAstManager) cssAstManager.removeProperty(selector, 'width');
            delete comp.properties.width;
            targetEl.style.width = '';
          }
          if (initialHeight !== null && initialHeight !== undefined) {
            if (cssAstManager) cssAstManager.setProperty(selector, 'height', initialHeight);
            comp.properties.height = initialHeight;
            targetEl.style.height = initialHeight;
          } else {
            if (cssAstManager) cssAstManager.removeProperty(selector, 'height');
            delete comp.properties.height;
            targetEl.style.height = '';
          }
          cleanup();
          updateOverlay();
        }
      }

      function cleanup() {
        window.removeEventListener('mousemove', onMouseMove);
        window.removeEventListener('mouseup', onMouseUp);
        window.removeEventListener('keydown', onKeyDown);
        if (tooltip.parentNode) {
          tooltip.parentNode.removeChild(tooltip);
        }
      }

      function onMouseUp() {
        cleanup();
        if (!isCancelled) {
          uiModel.saveSnapshot();
          uiModel.notify('property', { id: comp.id, prop: 'dimensions' });
          updateOverlay();
        }
      }

      window.addEventListener('mousemove', onMouseMove);
      window.addEventListener('mouseup', onMouseUp);
      window.addEventListener('keydown', onKeyDown);
    });
  }

  // =========================================================================
  // GrapesJS-Style Interaction Layer: Hit Testing & Decoupled Visual Overlay
  // =========================================================================

  function setupDesignerInteraction(viewportEl, contentArea, root) {
    const overlayEl = viewportEl.querySelector('#designerOverlay');
    const targetBoxEl = viewportEl.querySelector('#designerTargetBox');
    const targetBadgeEl = viewportEl.querySelector('#designerTargetBadge');
    const insertionLineEl = viewportEl.querySelector('#designerInsertionLine');

    function showOverlay(hit) {
      if (!overlayEl || !targetBoxEl || !insertionLineEl) return;

      const viewportRect = viewportEl.getBoundingClientRect();
      const scrollLeft = viewportEl.scrollLeft;
      const scrollTop = viewportEl.scrollTop;

      // Position container target box
      const cRect = hit.containerRect;
      targetBoxEl.style.left = `${cRect.left - viewportRect.left + scrollLeft}px`;
      targetBoxEl.style.top = `${cRect.top - viewportRect.top + scrollTop}px`;
      targetBoxEl.style.width = `${cRect.width}px`;
      targetBoxEl.style.height = `${cRect.height}px`;

      const kindName = hit.targetComp.kind || (hit.targetComp.id === root.id ? 'window' : 'container');
      targetBadgeEl.textContent = `${hit.targetComp.name} [${kindName}]`;

      // Position insertion line with endpoint dots
      const geo = hit.lineGeometry;
      if (hit.isRow) {
        insertionLineEl.className = 'designer-insertion-line is-vertical';
        insertionLineEl.style.left = `${geo.x - viewportRect.left + scrollLeft}px`;
        insertionLineEl.style.top = `${geo.y - viewportRect.top + scrollTop}px`;
        insertionLineEl.style.width = '3px';
        insertionLineEl.style.height = `${geo.height}px`;
      } else {
        insertionLineEl.className = 'designer-insertion-line is-horizontal';
        insertionLineEl.style.left = `${geo.x - viewportRect.left + scrollLeft}px`;
        insertionLineEl.style.top = `${geo.y - viewportRect.top + scrollTop}px`;
        insertionLineEl.style.width = `${geo.width}px`;
        insertionLineEl.style.height = '3px';
      }

      overlayEl.style.display = 'block';
    }

    function hideOverlay() {
      if (overlayEl) {
        overlayEl.style.display = 'none';
      }
    }

    viewportEl.addEventListener('dragover', (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = currentDraggedComponentId ? 'move' : 'copy';

      const hit = performHitTest(e.clientX, e.clientY, currentDraggedComponentId, contentArea, root);
      if (!hit) {
        hideOverlay();
        currentHit = null;
        return;
      }

      currentHit = hit;
      showOverlay(hit);
    });

    viewportEl.addEventListener('dragleave', (e) => {
      if (!viewportEl.contains(e.relatedTarget)) {
        hideOverlay();
        currentHit = null;
      }
    });

    viewportEl.addEventListener('drop', (e) => {
      e.preventDefault();
      hideOverlay();

      const hit = currentHit || performHitTest(e.clientX, e.clientY, currentDraggedComponentId, contentArea, root);
      currentHit = null;
      const draggedId = currentDraggedComponentId;
      currentDraggedComponentId = null;

      if (!hit) return;

      let dragData = null;
      try {
        const jsonStr = e.dataTransfer.getData('application/json');
        if (jsonStr) dragData = JSON.parse(jsonStr);
      } catch (err) {}

      if (!dragData) {
        const otterKind = e.dataTransfer.getData('text/otter-kind');
        if (otterKind) {
          dragData = { type: 'new-component', kind: otterKind };
        }
      }

      if (!dragData) return;

      if (dragData.type === 'new-component') {
        const child = uiModel.addChild(hit.targetComp.id, dragData.kind, {}, hit.insertIndex);
        if (child && cssAstManager) {
          if (child.kind === 'row' || child.kind === 'column' || child.kind === 'card') {
            cssAstManager.setProperty(`#${child.name}`, 'padding', '12px');
          }
        }
      } else if (dragData.type === 'move-component') {
        const compId = dragData.componentId || draggedId;
        if (compId) {
          uiModel.moveChild(compId, hit.targetComp.id, hit.insertIndex);
        }
      }
    });

    // Mouse hover tracking for decoupled overlay outline
    viewportEl.addEventListener('mousemove', (e) => {
      if (isInteractMode || currentDraggedComponentId) return;
      const hoverBox = containerEl.querySelector('#designerHoverBox');
      const hoverBadge = containerEl.querySelector('#designerHoverBadge');
      if (!hoverBox || !hoverBadge) return;

      const target = e.target.closest('[data-id]');
      if (!target || target === contentArea || target.getAttribute('data-id') === root.id) {
        hoverBox.style.display = 'none';
        return;
      }

      const hoverId = target.getAttribute('data-id');
      if (uiModel.isSelected(hoverId)) {
        hoverBox.style.display = 'none';
        return;
      }

      const comp = uiModel.getComponent(hoverId);
      if (!comp) {
        hoverBox.style.display = 'none';
        return;
      }

      const elRect = target.getBoundingClientRect();
      const vpRect = viewportEl.getBoundingClientRect();
      hoverBox.style.left = `${elRect.left - vpRect.left + viewportEl.scrollLeft}px`;
      hoverBox.style.top = `${elRect.top - vpRect.top + viewportEl.scrollTop}px`;
      hoverBox.style.width = `${elRect.width}px`;
      hoverBox.style.height = `${elRect.height}px`;
      hoverBadge.textContent = `${comp.name} (${comp.kind})`;
      hoverBox.style.display = 'block';
    });

    viewportEl.addEventListener('mouseleave', () => {
      const hoverBox = containerEl.querySelector('#designerHoverBox');
      if (hoverBox) hoverBox.style.display = 'none';
    });

    // Viewport scroll and window resize keep overlay aligned
    viewportEl.addEventListener('scroll', () => {
      updateOverlay();
    });
    window.addEventListener('resize', () => {
      updateOverlay();
    });

    // External hover events (e.g. from component tree)
    window.addEventListener('otter:highlight-component', (e) => {
      if (isInteractMode) return;
      const hoverBox = containerEl.querySelector('#designerHoverBox');
      const hoverBadge = containerEl.querySelector('#designerHoverBadge');
      if (!hoverBox || !hoverBadge) return;

      const compId = e.detail?.id;
      if (!compId) {
        hoverBox.style.display = 'none';
        return;
      }
      const target = containerEl.querySelector(`[data-id="${compId}"]`);
      if (!target || uiModel.isSelected(compId)) {
        hoverBox.style.display = 'none';
        return;
      }
      const comp = uiModel.getComponent(compId);
      if (!comp) {
        hoverBox.style.display = 'none';
        return;
      }
      const elRect = target.getBoundingClientRect();
      const vpRect = viewportEl.getBoundingClientRect();
      hoverBox.style.left = `${elRect.left - vpRect.left + viewportEl.scrollLeft}px`;
      hoverBox.style.top = `${elRect.top - vpRect.top + viewportEl.scrollTop}px`;
      hoverBox.style.width = `${elRect.width}px`;
      hoverBox.style.height = `${elRect.height}px`;
      hoverBadge.textContent = `${comp.name} (${comp.kind})`;
      hoverBox.style.display = 'block';
    });
  }

  function hideDropOverlay() {
    const overlay = containerEl.querySelector('#designerOverlay');
    if (overlay) overlay.style.display = 'none';
  }

  // Hit-testing algorithm based on real DOM bounding boxes and computed layout
  function performHitTest(clientX, clientY, draggedId, contentArea, root) {
    const elements = document.elementsFromPoint(clientX, clientY);
    if (!elements || elements.length === 0) return null;

    let targetEl = null;
    let targetComp = null;

    for (const el of elements) {
      if (el === contentArea || el.id === root.name || el.getAttribute('data-id') === root.id) {
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

    if (!targetEl || !targetComp) return null;

    // Prevent dropping onto self or descendants
    if (draggedId) {
      if (targetComp.id === draggedId || uiModel.isDescendantOf(targetComp.id, draggedId)) {
        let ancestor = targetComp.parentId ? uiModel.getComponent(targetComp.parentId) : null;
        while (ancestor && (ancestor.id === draggedId || uiModel.isDescendantOf(ancestor.id, draggedId))) {
          ancestor = ancestor.parentId ? uiModel.getComponent(ancestor.parentId) : null;
        }
        if (!ancestor) return null;
        targetComp = ancestor;
        targetEl = targetComp.id === root.id ? contentArea : containerEl.querySelector(`[data-id="${targetComp.id}"]`);
        if (!targetEl) return null;
      }
    }

    // If target is a leaf control, resolve to parent container and determine relative insertion
    const schema = ComponentSchema[targetComp.kind] || {};
    let dropBeforeEl = null;
    let dropAfterEl = null;

    if (!schema.isContainer && targetComp.id !== root.id) {
      const parentComp = targetComp.parentId ? uiModel.getComponent(targetComp.parentId) : root;
      const parentEl = parentComp.id === root.id ? contentArea : containerEl.querySelector(`[data-id="${parentComp.id}"]`);
      if (!parentEl) return null;

      const leafEl = targetEl;
      targetComp = parentComp;
      targetEl = parentEl;

      const leafRect = leafEl.getBoundingClientRect();
      const parentStyle = window.getComputedStyle(targetEl);
      const isParentRow = (targetComp.kind === 'row') || (parentStyle.display.includes('flex') && parentStyle.flexDirection.includes('row'));

      if (isParentRow) {
        const midX = leafRect.left + leafRect.width / 2;
        if (clientX < midX) {
          dropBeforeEl = leafEl;
        } else {
          dropAfterEl = leafEl;
        }
      } else {
        const midY = leafRect.top + leafRect.height / 2;
        if (clientY < midY) {
          dropBeforeEl = leafEl;
        } else {
          dropAfterEl = leafEl;
        }
      }
    }

    const computed = window.getComputedStyle(targetEl);
    const isRow = (targetComp.kind === 'row') || (computed.display.includes('flex') && computed.flexDirection.includes('row'));

    // Direct rendered children
    const directChildren = Array.from(targetEl.children).filter(c => {
      const cid = c.getAttribute('data-id');
      return cid && cid !== draggedId && !c.classList.contains('is-dragging');
    });

    let insertIndex = 0;
    let lineX = 0;
    let lineY = 0;
    let lineWidth = 0;
    let lineHeight = 0;

    const containerRect = targetEl.getBoundingClientRect();

    if (directChildren.length === 0) {
      insertIndex = 0;
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
      if (dropBeforeEl) {
        insertIndex = refIdx >= 0 ? refIdx : 0;
      } else {
        insertIndex = refIdx >= 0 ? refIdx + 1 : directChildren.length;
      }

      const refRect = refEl.getBoundingClientRect();
      if (isRow) {
        lineY = refRect.top;
        lineHeight = refRect.height;
        lineWidth = 3;
        lineX = dropBeforeEl ? (refRect.left - 2) : (refRect.right + 2);
      } else {
        lineX = containerRect.left + 8;
        lineWidth = Math.max(40, containerRect.width - 16);
        lineHeight = 3;
        lineY = dropBeforeEl ? (refRect.top - 2) : (refRect.bottom + 2);
      }
    } else {
      if (isRow) {
        insertIndex = directChildren.length;
        for (let i = 0; i < directChildren.length; i++) {
          const cRect = directChildren[i].getBoundingClientRect();
          const midX = cRect.left + cRect.width / 2;
          if (clientX < midX) {
            insertIndex = i;
            break;
          }
        }

        lineWidth = 3;
        if (insertIndex === 0) {
          const firstRect = directChildren[0].getBoundingClientRect();
          lineX = firstRect.left - 3;
          lineY = firstRect.top;
          lineHeight = firstRect.height;
        } else if (insertIndex === directChildren.length) {
          const lastRect = directChildren[directChildren.length - 1].getBoundingClientRect();
          lineX = lastRect.right + 3;
          lineY = lastRect.top;
          lineHeight = lastRect.height;
        } else {
          const prevRect = directChildren[insertIndex - 1].getBoundingClientRect();
          const nextRect = directChildren[insertIndex].getBoundingClientRect();
          lineX = (prevRect.right + nextRect.left) / 2;
          lineY = Math.min(prevRect.top, nextRect.top);
          lineHeight = Math.max(prevRect.height, nextRect.height);
        }
      } else {
        insertIndex = directChildren.length;
        for (let i = 0; i < directChildren.length; i++) {
          const cRect = directChildren[i].getBoundingClientRect();
          const midY = cRect.top + cRect.height / 2;
          if (clientY < midY) {
            insertIndex = i;
            break;
          }
        }

        lineX = containerRect.left + 8;
        lineWidth = Math.max(40, containerRect.width - 16);
        lineHeight = 3;

        if (insertIndex === 0) {
          const firstRect = directChildren[0].getBoundingClientRect();
          lineY = firstRect.top - 3;
        } else if (insertIndex === directChildren.length) {
          const lastRect = directChildren[directChildren.length - 1].getBoundingClientRect();
          lineY = lastRect.bottom + 3;
        } else {
          const prevRect = directChildren[insertIndex - 1].getBoundingClientRect();
          const nextRect = directChildren[insertIndex].getBoundingClientRect();
          lineY = (prevRect.bottom + nextRect.top) / 2;
        }
      }
    }

    return {
      targetEl,
      targetComp,
      containerRect,
      isRow,
      insertIndex,
      lineGeometry: {
        x: lineX,
        y: lineY,
        width: lineWidth,
        height: lineHeight
      }
    };
  }

  // =========================================================================
  // Global Studio Keyboard Shortcuts
  // =========================================================================

  function setupKeyboardShortcuts() {
    window.addEventListener('keydown', (e) => {
      const activeTag = document.activeElement ? document.activeElement.tagName.toLowerCase() : '';
      if (['input', 'textarea', 'select'].includes(activeTag) || document.activeElement?.isContentEditable) {
        return;
      }
      if (isInteractMode) {
        return;
      }

      const isMac = navigator.platform.toUpperCase().indexOf('MAC') >= 0;
      const mod = isMac ? e.metaKey : e.ctrlKey;

      // Undo: Ctrl+Z
      if (mod && !e.shiftKey && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        uiModel.undo();
        return;
      }

      // Redo: Ctrl+Y or Ctrl+Shift+Z
      if ((mod && e.key.toLowerCase() === 'y') || (mod && e.shiftKey && e.key.toLowerCase() === 'z')) {
        e.preventDefault();
        uiModel.redo();
        return;
      }

      // Duplicate: Ctrl+D
      if (mod && e.key.toLowerCase() === 'd') {
        e.preventDefault();
        if (uiModel.selectedId && uiModel.selectedId !== uiModel.rootId) {
          uiModel.duplicateComponent(uiModel.selectedId, cssAstManager);
        }
        return;
      }

      // Delete: Delete or Backspace
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (uiModel.selectedId && uiModel.selectedId !== uiModel.rootId) {
          e.preventDefault();
          uiModel.removeComponent(uiModel.selectedId);
        }
        return;
      }

      // Reorder with Alt+Arrow keys
      if (e.altKey && (e.key === 'ArrowUp' || e.key === 'ArrowDown' || e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
        const selected = uiModel.getComponent(uiModel.selectedId);
        if (selected && selected.parentId) {
          const parent = uiModel.getComponent(selected.parentId);
          if (parent && parent.children) {
            const idx = parent.children.indexOf(selected.id);
            if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') {
              if (idx > 0) {
                e.preventDefault();
                uiModel.moveChild(selected.id, parent.id, idx - 1);
              }
            } else {
              if (idx < parent.children.length - 1) {
                e.preventDefault();
                uiModel.moveChild(selected.id, parent.id, idx + 1);
              }
            }
          }
        }
      }
    });
  }

  setupKeyboardShortcuts();
  update();

  uiModel.subscribe((type) => {
    update();
  });

  window.addEventListener('css-updated', () => {
    update();
  });
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
