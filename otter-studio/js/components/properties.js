// properties.js - Visual Property Inspector binding directly to lossless CSS AST

import { ComponentSchema } from '../model/schema.js';

export function renderProperties(containerEl, uiModel, cssAstManager) {
  function update() {
    const selected = uiModel.getComponent(uiModel.selectedId);
    if (!selected) {
      containerEl.innerHTML = `
        <div class="properties-header"><span class="panel-title">Properties</span></div>
        <div class="empty-state">No component selected</div>
      `;
      return;
    }

    const selector = `#${selected.name}`;
    const cssDecls = cssAstManager ? cssAstManager.getRuleDeclarations(selector) : {};
    const props = selected.properties || {};

    const count = uiModel.selectedIds.size;
    const badgeText = count > 1 ? `${selected.kind} (${count} selected)` : selected.kind;

    containerEl.innerHTML = `
      <div class="properties-header">
        <span class="panel-title">Properties</span>
        <span class="badge badge-accent">${badgeText}</span>
      </div>
      <div class="properties-body" id="propertiesBody">
        <!-- Identity Group -->
        <div class="prop-group">
          <div class="prop-group-title">Otter Identity</div>
          ${count > 1 ? `
            <div class="prop-row" style="color: #93c5fd; font-size: 11px; margin-bottom: 6px;">
              <span>Multi-select active (${count} components). Showing primary:</span>
            </div>
          ` : ''}
          <div class="prop-row">
            <label class="prop-label">Selector</label>
            <div class="selector-badge">${selector}</div>
          </div>
          <div class="prop-row">
            <label class="prop-label">Variable</label>
            <input type="text" class="prop-input" id="propName" value="${selected.name}" />
          </div>
        </div>

        <!-- Otter Content & Structure -->
        ${renderContentGroup(selected, props)}

        <!-- Authoritative Flexbox & Alignment (for containers or flex items) -->
        ${renderCssFlexLayoutGroup(selected, selector, cssDecls)}

        <!-- Authoritative CSS Sizing & Box Model -->
        ${renderCssBoxModelGroup(selector, cssDecls)}

        <!-- Authoritative CSS Visual Styles -->
        ${renderCssVisualStylesGroup(selector, cssDecls)}

        <!-- Direct CSS Editor / Custom Properties -->
        ${renderCssCustomProperties(selector, cssDecls)}
      </div>
    `;

    bindEvents(containerEl, selected, selector);
  }

  function renderContentGroup(selected, props) {
    const fields = [];

    if (selected.kind === 'window') {
      fields.push(`
        <div class="prop-row">
          <label class="prop-label">Window Title</label>
          <input type="text" class="prop-input" data-otter-key="title" value="${escapeHtml(props.title || '')}" />
        </div>
      `);
    }

    if (props.text !== undefined || ['button', 'primary button', 'danger button', 'text', 'heading', 'checkbox'].includes(selected.kind)) {
      fields.push(`
        <div class="prop-row">
          <label class="prop-label">Text</label>
          <input type="text" class="prop-input" data-otter-key="text" value="${escapeHtml(props.text || '')}" />
        </div>
      `);
    }

    if (['text box', 'dropdown'].includes(selected.kind)) {
      fields.push(`
        <div class="prop-row">
          <label class="prop-label">Placeholder</label>
          <input type="text" class="prop-input" data-otter-key="placeholder" value="${escapeHtml(props.placeholder || '')}" />
        </div>
      `);
    }

    if (selected.kind === 'checkbox') {
      fields.push(`
        <div class="prop-row">
          <label class="prop-label">Checked</label>
          <input type="checkbox" class="prop-checkbox" data-otter-key="checked" ${props.checked ? 'checked' : ''} />
        </div>
      `);
    }

    if (fields.length === 0) return '';
    return `
      <div class="prop-group">
        <div class="prop-group-title">Content (Otter)</div>
        ${fields.join('')}
      </div>
    `;
  }

  function renderCssFlexLayoutGroup(selected, selector, cssDecls) {
    const schema = ComponentSchema[selected.kind] || {};
    // Only display for containers or window
    if (!schema.isContainer && selected.kind !== 'window') return '';

    const dir = cssDecls['flex-direction'] || (selected.kind === 'row' ? 'row' : 'column');
    const justify = cssDecls['justify-content'] || 'flex-start';
    const align = cssDecls['align-items'] || 'stretch';
    const wrap = cssDecls['flex-wrap'] || 'nowrap';
    const gap = cssDecls['gap'] || '';

    return `
      <div class="prop-group">
        <div class="prop-group-title">Layout & Flexbox</div>

        <!-- Direction -->
        <div class="prop-row">
          <label class="prop-label">Direction</label>
          <div class="prop-segmented-control" data-css-prop="flex-direction">
            <button class="prop-segment-btn ${dir === 'row' ? 'is-active' : ''}" data-css-val="row" title="Horizontal Row">Row →</button>
            <button class="prop-segment-btn ${dir === 'column' ? 'is-active' : ''}" data-css-val="column" title="Vertical Column">Col ↓</button>
          </div>
        </div>

        <!-- Justify Content (Distribution) -->
        <div class="prop-row">
          <label class="prop-label">Justify</label>
          <div class="prop-segmented-control" data-css-prop="justify-content">
            <button class="prop-segment-btn ${justify === 'flex-start' ? 'is-active' : ''}" data-css-val="flex-start" title="Start">Start</button>
            <button class="prop-segment-btn ${justify === 'center' ? 'is-active' : ''}" data-css-val="center" title="Center">Center</button>
            <button class="prop-segment-btn ${justify === 'flex-end' ? 'is-active' : ''}" data-css-val="flex-end" title="End">End</button>
            <button class="prop-segment-btn ${justify === 'space-between' ? 'is-active' : ''}" data-css-val="space-between" title="Space Between">Between</button>
          </div>
        </div>

        <!-- Align Items (Cross-axis) -->
        <div class="prop-row">
          <label class="prop-label">Align</label>
          <div class="prop-segmented-control" data-css-prop="align-items">
            <button class="prop-segment-btn ${align === 'stretch' ? 'is-active' : ''}" data-css-val="stretch" title="Stretch">Stretch</button>
            <button class="prop-segment-btn ${align === 'flex-start' ? 'is-active' : ''}" data-css-val="flex-start" title="Start">Start</button>
            <button class="prop-segment-btn ${align === 'center' ? 'is-active' : ''}" data-css-val="center" title="Center">Center</button>
            <button class="prop-segment-btn ${align === 'flex-end' ? 'is-active' : ''}" data-css-val="flex-end" title="End">End</button>
          </div>
        </div>

        <!-- Flex Wrap -->
        <div class="prop-row">
          <label class="prop-label">Wrap</label>
          <div class="prop-segmented-control" data-css-prop="flex-wrap">
            <button class="prop-segment-btn ${wrap === 'nowrap' ? 'is-active' : ''}" data-css-val="nowrap" title="No Wrap">No Wrap</button>
            <button class="prop-segment-btn ${wrap === 'wrap' ? 'is-active' : ''}" data-css-val="wrap" title="Wrap Items">Wrap</button>
          </div>
        </div>

        <!-- Quick Gap Presets -->
        <div class="prop-row">
          <label class="prop-label">Quick Gap</label>
          <div class="prop-quick-gaps">
            <button class="prop-gap-btn ${gap === '0px' || gap === '0' ? 'is-active' : ''}" data-gap="0px">0</button>
            <button class="prop-gap-btn ${gap === '8px' ? 'is-active' : ''}" data-gap="8px">8px</button>
            <button class="prop-gap-btn ${gap === '12px' ? 'is-active' : ''}" data-gap="12px">12px</button>
            <button class="prop-gap-btn ${gap === '16px' ? 'is-active' : ''}" data-gap="16px">16px</button>
            <button class="prop-gap-btn ${gap === '24px' ? 'is-active' : ''}" data-gap="24px">24px</button>
          </div>
        </div>
      </div>
    `;
  }

  function renderCssBoxModelGroup(selector, cssDecls) {
    const width = cssDecls['width'] || '';
    const height = cssDecls['height'] || '';
    const padding = cssDecls['padding'] || '';
    const margin = cssDecls['margin'] || '';
    const gap = cssDecls['gap'] || '';

    return `
      <div class="prop-group">
        <div class="prop-group-title">CSS Dimensions & Spacing</div>
        <div class="prop-row">
          <label class="prop-label">width</label>
          <div class="input-with-btn">
            <input type="text" class="prop-input" data-css-prop="width" value="${width}" placeholder="140px / 100%" />
            <button class="prop-toggle-btn ${width === '100%' ? 'is-active' : ''}" data-css-prop="width" data-css-val="100%">100%</button>
          </div>
        </div>
        <div class="prop-row">
          <label class="prop-label">height</label>
          <div class="input-with-btn">
            <input type="text" class="prop-input" data-css-prop="height" value="${height}" placeholder="42px / auto" />
            <button class="prop-toggle-btn ${height === '100%' ? 'is-active' : ''}" data-css-prop="height" data-css-val="100%">100%</button>
          </div>
        </div>
        <div class="prop-row">
          <label class="prop-label">padding</label>
          <input type="text" class="prop-input" data-css-prop="padding" value="${padding}" placeholder="8px 16px" />
        </div>
        <div class="prop-row">
          <label class="prop-label">margin</label>
          <input type="text" class="prop-input" data-css-prop="margin" value="${margin}" placeholder="4px" />
        </div>
        <div class="prop-row">
          <label class="prop-label">gap</label>
          <input type="text" class="prop-input" data-css-prop="gap" value="${gap}" placeholder="12px" />
        </div>
      </div>
    `;
  }

  function renderCssVisualStylesGroup(selector, cssDecls) {
    const bg = cssDecls['background'] || cssDecls['background-color'] || '';
    const color = cssDecls['color'] || '';
    const radius = cssDecls['border-radius'] || '';
    const opacity = cssDecls['opacity'] !== undefined ? cssDecls['opacity'] : '1';
    const border = cssDecls['border'] || '';

    return `
      <div class="prop-group">
        <div class="prop-group-title">CSS Visual Styling</div>
        <div class="prop-row">
          <label class="prop-label">background</label>
          <div class="color-picker-wrap">
            <input type="color" class="prop-color-swatch" value="${toHexColor(bg || '#1e293b')}" />
            <input type="text" class="prop-input" data-css-prop="background" value="${bg}" placeholder="#2563eb" />
          </div>
        </div>
        <div class="prop-row">
          <label class="prop-label">color</label>
          <div class="color-picker-wrap">
            <input type="color" class="prop-color-swatch" value="${toHexColor(color || '#f8fafc')}" />
            <input type="text" class="prop-input" data-css-prop="color" value="${color}" placeholder="white" />
          </div>
        </div>
        <div class="prop-row">
          <label class="prop-label">border-radius</label>
          <input type="text" class="prop-input" data-css-prop="border-radius" value="${radius}" placeholder="12px" />
        </div>
        <div class="prop-row">
          <label class="prop-label">border</label>
          <input type="text" class="prop-input" data-css-prop="border" value="${border}" placeholder="1px solid #334155" />
        </div>
        <div class="prop-row">
          <label class="prop-label">opacity</label>
          <div class="input-with-slider">
            <input type="range" class="prop-slider" min="0" max="1" step="0.05" value="${opacity || 1}" />
            <span class="slider-val">${Math.round((parseFloat(opacity) || 1) * 100)}%</span>
          </div>
        </div>
      </div>
    `;
  }

  function renderCssCustomProperties(selector, cssDecls) {
    const standard = [
      'width', 'height', 'padding', 'margin', 'gap', 'background', 'background-color',
      'color', 'border-radius', 'border', 'opacity', 'flex-direction', 'justify-content',
      'align-items', 'flex-wrap', 'display'
    ];
    const customList = Object.entries(cssDecls).filter(([k]) => !standard.includes(k.toLowerCase()));

    return `
      <div class="prop-group">
        <div class="prop-group-title">Advanced CSS Properties</div>
        ${customList.map(([k, v]) => `
          <div class="prop-row">
            <label class="prop-label code-label">${k}</label>
            <input type="text" class="prop-input" data-css-prop="${k}" value="${v}" />
          </div>
        `).join('')}
        <div class="add-css-prop-row">
          <input type="text" class="prop-input" id="newCssKey" placeholder="e.g. backdrop-filter" />
          <input type="text" class="prop-input" id="newCssVal" placeholder="blur(8px)" />
          <button class="editor-btn editor-btn-primary" id="addCssBtn">+</button>
        </div>
      </div>
    `;
  }

  function bindEvents(containerEl, selected, selector) {
    // Variable rename
    const nameInput = containerEl.querySelector('#propName');
    if (nameInput) {
      nameInput.addEventListener('change', (e) => {
        const newName = e.target.value.trim();
        if (newName && newName !== selected.name) {
          const oldSelector = `#${selected.name}`;
          const newSelector = `#${newName}`;
          const decls = cssAstManager.getRuleDeclarations(oldSelector);
          for (const [k, v] of Object.entries(decls)) {
            cssAstManager.setProperty(newSelector, k, v);
          }
          uiModel.setName(selected.id, newName);
          window.dispatchEvent(new CustomEvent('css-updated', { detail: { source: 'properties' } }));
        }
      });
    }

    // Segmented controls (Flexbox & Layout)
    const segmentControls = containerEl.querySelectorAll('.prop-segmented-control');
    segmentControls.forEach(ctrl => {
      const prop = ctrl.getAttribute('data-css-prop');
      ctrl.querySelectorAll('.prop-segment-btn').forEach(btn => {
        btn.addEventListener('click', () => {
          const val = btn.getAttribute('data-css-val');
          cssAstManager.setProperty(selector, prop, val);
          window.dispatchEvent(new CustomEvent('css-updated', { detail: { selector, prop, val, source: 'properties' } }));
          update();
        });
      });
    });

    // Quick Gap buttons
    const gapBtns = containerEl.querySelectorAll('.prop-gap-btn');
    gapBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        const gapVal = btn.getAttribute('data-gap');
        cssAstManager.setProperty(selector, 'gap', gapVal);
        window.dispatchEvent(new CustomEvent('css-updated', { detail: { selector, prop: 'gap', val: gapVal, source: 'properties' } }));
        update();
      });
    });

    // Otter Content properties
    const otterInputs = containerEl.querySelectorAll('.prop-input[data-otter-key]');
    otterInputs.forEach(input => {
      input.addEventListener('change', (e) => {
        const key = e.target.getAttribute('data-otter-key');
        uiModel.setProperty(selected.id, key, e.target.value.trim() || undefined);
      });
    });

    const otterCheckboxes = containerEl.querySelectorAll('.prop-checkbox[data-otter-key]');
    otterCheckboxes.forEach(chk => {
      chk.addEventListener('change', (e) => {
        const key = e.target.getAttribute('data-otter-key');
        uiModel.setProperty(selected.id, key, e.target.checked);
      });
    });

    // Authoritative CSS properties
    const cssInputs = containerEl.querySelectorAll('.prop-input[data-css-prop]');
    cssInputs.forEach(input => {
      input.addEventListener('change', (e) => {
        const prop = e.target.getAttribute('data-css-prop');
        const val = e.target.value.trim();
        cssAstManager.setProperty(selector, prop, val || null);
        window.dispatchEvent(new CustomEvent('css-updated', { detail: { selector, prop, val, source: 'properties' } }));
      });
    });

    // Swatches
    const swatches = containerEl.querySelectorAll('.prop-color-swatch');
    swatches.forEach(swatch => {
      const textInput = swatch.nextElementSibling;
      swatch.addEventListener('input', (e) => {
        const color = e.target.value;
        textInput.value = color;
        const prop = textInput.getAttribute('data-css-prop');
        cssAstManager.setProperty(selector, prop, color);
        window.dispatchEvent(new CustomEvent('css-updated', { detail: { selector, prop, val: color, source: 'properties' } }));
      });
    });

    // Opacity slider
    const slider = containerEl.querySelector('.prop-slider');
    if (slider) {
      const valLabel = slider.nextElementSibling;
      slider.addEventListener('input', (e) => {
        const num = parseFloat(e.target.value);
        valLabel.innerText = `${Math.round(num * 100)}%`;
        const val = num === 1 ? null : String(num);
        cssAstManager.setProperty(selector, 'opacity', val);
        window.dispatchEvent(new CustomEvent('css-updated', { detail: { selector, prop: 'opacity', val, source: 'properties' } }));
      });
    }

    // Toggle full width/height
    const toggleBtns = containerEl.querySelectorAll('.prop-toggle-btn[data-css-prop]');
    toggleBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        const prop = btn.getAttribute('data-css-prop');
        const val = btn.getAttribute('data-css-val');
        const current = cssAstManager.getProperty(selector, prop);
        const next = current === val ? null : val;
        cssAstManager.setProperty(selector, prop, next);
        window.dispatchEvent(new CustomEvent('css-updated', { detail: { selector, prop, val: next, source: 'properties' } }));
        update();
      });
    });

    // Add arbitrary custom CSS property
    const addCssBtn = containerEl.querySelector('#addCssBtn');
    const newKeyInput = containerEl.querySelector('#newCssKey');
    const newValInput = containerEl.querySelector('#newCssVal');
    if (addCssBtn && newKeyInput && newValInput) {
      addCssBtn.addEventListener('click', () => {
        const k = newKeyInput.value.trim();
        const v = newValInput.value.trim();
        if (k && v) {
          cssAstManager.setProperty(selector, k, v);
          window.dispatchEvent(new CustomEvent('css-updated', { detail: { selector, prop: k, val: v, source: 'properties' } }));
          update();
        }
      });
    }
  }

  update();

  uiModel.subscribe((type) => {
    if (type === 'select' || type === 'property' || type === 'rename' || type === 'template' || type === 'undo' || type === 'redo' || type === 'add' || type === 'remove' || type === 'move') {
      update();
    }
  });

  window.addEventListener('css-updated', (e) => {
    if (e.detail?.source !== 'properties') {
      update();
    }
  });
}

function toHexColor(colorStr) {
  if (!colorStr) return '#1e293b';
  if (colorStr.startsWith('#')) return colorStr;
  const names = {
    white: '#ffffff', black: '#000000', red: '#ef4444', blue: '#3b82f6',
    green: '#10b981', gray: '#6b7280', navy: '#0f172a'
  };
  return names[colorStr.toLowerCase()] || '#1e293b';
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
