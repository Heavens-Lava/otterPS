// properties.js - The designer inspector: Otter identity/content plus a full
// visual CSS style panel.
//
// Every style control writes through the StyleController, which decides where
// the value lives (Otter source or a styles.css rule), which breakpoint and
// state it belongs to, and how edits group into undo steps. The panel itself
// never touches the stylesheet directly.

import { ComponentSchema } from '../model/schema.js';
import { BREAKPOINTS, STATES, StyleController } from '../designer/style-context.js';
import {
  parseLength, stepLength, normalizeLengthInput, formatNumber,
  readBoxSides, collapseBox, SIDES, readCorners, CORNERS, splitTopLevel, toHexColor
} from '../designer/css-values.js';

const SECTION_STORE_KEY = 'otter-studio-style-sections';

const FONT_FAMILIES = [
  ['', 'Default'],
  ["Inter, system-ui, sans-serif", 'Inter'],
  ["system-ui, -apple-system, 'Segoe UI', sans-serif", 'System UI'],
  ["'Segoe UI', Roboto, Helvetica, Arial, sans-serif", 'Segoe / Roboto'],
  ["Georgia, 'Times New Roman', serif", 'Serif'],
  ["'JetBrains Mono', Consolas, monospace", 'Monospace']
];

const SHADOW_PRESETS = [
  ['none', 'None'],
  ['0 1px 2px rgba(15, 23, 42, 0.08)', 'XS'],
  ['0 4px 12px rgba(15, 23, 42, 0.10)', 'S'],
  ['0 10px 25px rgba(15, 23, 42, 0.14)', 'M'],
  ['0 20px 45px rgba(15, 23, 42, 0.20)', 'L'],
  ['inset 0 2px 4px rgba(15, 23, 42, 0.12)', 'Inset'],
  ['0 0 0 3px rgba(37, 99, 235, 0.35)', 'Ring']
];

const TRANSITION_PRESETS = [
  ['', 'None'],
  ['all 0.15s ease', 'Fast'],
  ['all 0.3s ease', 'Smooth'],
  ['all 0.5s cubic-bezier(0.22, 1, 0.36, 1)', 'Springy']
];

const COMMON_CSS_PROPERTIES = [
  'align-content', 'align-items', 'align-self', 'animation', 'aspect-ratio', 'backdrop-filter',
  'background', 'background-color', 'background-image', 'background-position', 'background-size',
  'border', 'border-bottom', 'border-color', 'border-left', 'border-radius', 'border-right',
  'border-style', 'border-top', 'border-width', 'bottom', 'box-shadow', 'box-sizing', 'color',
  'column-gap', 'cursor', 'display', 'filter', 'flex', 'flex-basis', 'flex-direction', 'flex-grow',
  'flex-shrink', 'flex-wrap', 'font-family', 'font-size', 'font-style', 'font-weight', 'gap',
  'grid-area', 'grid-column', 'grid-row', 'grid-template-areas', 'grid-template-columns',
  'grid-template-rows', 'height', 'inset', 'justify-content', 'justify-items', 'justify-self',
  'left', 'letter-spacing', 'line-height', 'margin', 'max-height', 'max-width', 'min-height',
  'min-width', 'mix-blend-mode', 'object-fit', 'opacity', 'order', 'outline', 'overflow',
  'overflow-x', 'overflow-y', 'padding', 'pointer-events', 'position', 'right', 'row-gap',
  'text-align', 'text-decoration', 'text-overflow', 'text-shadow', 'text-transform', 'top',
  'transform', 'transition', 'user-select', 'visibility', 'white-space', 'width', 'word-break',
  'z-index'
];

export function renderProperties(containerEl, uiModel, cssAstManager, styleController = null) {
  const styles = styleController || new StyleController(uiModel, cssAstManager);
  let searchText = '';
  let scrubbing = false;
  let refreshQueued = false;
  let collapsed = loadCollapsed();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  function targets() {
    const list = uiModel.getSelectedComponents();
    return list.length ? list : [uiModel.getComponent(uiModel.selectedId)].filter(Boolean);
  }

  function canvasElementFor(comp) {
    if (!comp) return null;
    if (comp.id === uiModel.rootId) return document.querySelector('#canvasContainer .window-content-area');
    return document.querySelector(`#canvasContainer [data-id="${cssEscape(comp.id)}"]`);
  }

  function parentLayoutOf(comp) {
    if (!comp || !comp.parentId) return '';
    const parent = uiModel.getComponent(comp.parentId);
    const el = canvasElementFor(parent);
    if (!el) return '';
    const display = getComputedStyle(el).display;
    if (display.includes('grid')) return 'grid';
    if (display.includes('flex')) return 'flex';
    return '';
  }

  function write(values, key) {
    styles.write(targets(), values, { key });
    queueRefresh();
  }

  function queueRefresh() {
    if (refreshQueued) return;
    refreshQueued = true;
    requestAnimationFrame(() => {
      refreshQueued = false;
      if (!scrubbing) update();
    });
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  function update() {
    const selected = uiModel.getComponent(uiModel.selectedId);
    const bodyBefore = containerEl.querySelector('#propertiesBody');
    const scrollTop = bodyBefore ? bodyBefore.scrollTop : 0;
    const focusKey = document.activeElement && containerEl.contains(document.activeElement)
      ? document.activeElement.getAttribute('data-focus-key') : null;

    if (!selected) {
      containerEl.innerHTML = `
        <div class="properties-header"><span class="panel-title">Properties</span></div>
        <div class="empty-state">Select something on the canvas to style it.</div>
      `;
      return;
    }

    const count = uiModel.selectedIds.size;
    const resolved = styles.resolve(selected);
    const computed = computedFor(selected);
    const ctx = { selected, resolved, computed, parentLayout: parentLayoutOf(selected) };

    containerEl.innerHTML = `
      <div class="properties-header">
        <span class="panel-title">Properties</span>
        <span class="badge badge-accent">${count > 1 ? `${count} selected` : escapeHtml(selected.kind)}</span>
      </div>
      ${renderContextBar(selected)}
      <div class="properties-body sp-body" id="propertiesBody">
        ${renderIdentityGroup(selected, count)}
        ${renderContentGroup(selected, selected.properties || {})}
        ${renderLayoutSection(ctx)}
        ${renderSpacingSection(ctx)}
        ${renderSizeSection(ctx)}
        ${renderPositionSection(ctx)}
        ${renderTypographySection(ctx)}
        ${renderBackgroundSection(ctx)}
        ${renderBorderSection(ctx)}
        ${renderEffectsSection(ctx)}
        ${renderRawSection(ctx)}
      </div>
    `;

    bindEvents(selected);
    applySearch();

    const bodyAfter = containerEl.querySelector('#propertiesBody');
    if (bodyAfter) bodyAfter.scrollTop = scrollTop;
    if (focusKey) {
      const again = containerEl.querySelector(`[data-focus-key="${cssEscape(focusKey)}"]`);
      if (again) again.focus();
    }
  }

  function computedFor(comp) {
    const el = canvasElementFor(comp);
    if (!el) return {};
    const cs = getComputedStyle(el);
    const read = (p) => cs.getPropertyValue(p);
    const out = {};
    for (const p of ['display', 'flex-direction', 'width', 'height', 'font-size', 'font-weight', 'line-height',
      'letter-spacing', 'color', 'background-color', 'border-radius', 'opacity', 'position', 'z-index',
      'min-width', 'min-height', 'max-width', 'max-height', 'gap', 'font-family', 'text-align']) {
      out[p] = read(p);
    }
    out.padding = SIDES.map(s => read(`padding-${s}`));
    out.margin = SIDES.map(s => read(`margin-${s}`));
    return out;
  }

  function renderContextBar(selected) {
    const bp = styles.breakpoint;
    return `
      <div class="sp-context">
        <div class="sp-bp-tabs" role="tablist" aria-label="Breakpoint">
          ${BREAKPOINTS.map(b => `
            <button class="sp-bp-btn ${b.id === bp.id ? 'is-active' : ''}" data-breakpoint="${b.id}"
              title="${escapeHtml(b.label)}: ${escapeHtml(b.hint)}" role="tab" aria-selected="${b.id === bp.id}">
              ${breakpointIcon(b.id)}<span>${escapeHtml(b.label)}</span>
            </button>`).join('')}
        </div>
        <div class="sp-context-row">
          <label class="sp-state-label" for="spStateSelect">State</label>
          <select class="sp-select sp-state-select" id="spStateSelect">
            ${STATES.map(s => `<option value="${s.id}" ${s.id === styles.context.state ? 'selected' : ''}>${escapeHtml(s.label)}</option>`).join('')}
          </select>
          <code class="sp-target" title="Styles you edit are written here">${escapeHtml(styles.describe(selected))}</code>
        </div>
        <input type="search" class="sp-search" id="spSearch" placeholder="Search styles (e.g. radius, shadow)" value="${escapeHtml(searchText)}" data-focus-key="search" />
      </div>
    `;
  }

  function renderIdentityGroup(selected, count) {
    return `
      <div class="prop-group sp-identity">
        <div class="prop-row">
          <label class="prop-label" for="propName">Name</label>
          <input type="text" class="prop-input" id="propName" value="${escapeHtml(selected.name)}" data-focus-key="name"
            ${count > 1 ? 'disabled title="Select one component to rename it"' : ''} spellcheck="false" />
        </div>
        <div class="sp-name-error" id="propNameError" hidden></div>
        ${count > 1 ? `<div class="sp-note">Style edits apply to all ${count} selected components.</div>` : ''}
      </div>
    `;
  }

  function renderContentGroup(selected, props) {
    const fields = [];
    if (selected.kind === 'window') {
      fields.push(contentRow('Window title', 'title', props.title));
    }
    if (props.text !== undefined || ['button', 'primary button', 'danger button', 'text', 'heading', 'checkbox'].includes(selected.kind)) {
      fields.push(contentRow('Text', 'text', props.text));
    }
    if (['text box', 'dropdown'].includes(selected.kind)) {
      fields.push(contentRow('Placeholder', 'placeholder', props.placeholder));
    }
    if (selected.kind === 'image') {
      fields.push(contentRow('Image source', 'source', props.source));
    }
    if (selected.kind === 'checkbox') {
      fields.push(`
        <div class="prop-row">
          <label class="prop-label">Checked</label>
          <input type="checkbox" class="prop-checkbox" data-otter-key="checked" ${props.checked ? 'checked' : ''} />
        </div>`);
    }
    if (fields.length === 0) return '';
    return `
      <div class="prop-group">
        <div class="prop-group-title">Content (Otter)</div>
        ${fields.join('')}
      </div>
    `;
  }

  function contentRow(label, key, value) {
    return `
      <div class="prop-row">
        <label class="prop-label">${escapeHtml(label)}</label>
        <input type="text" class="prop-input" data-otter-key="${key}" data-focus-key="otter-${key}" value="${escapeHtml(value || '')}" />
      </div>`;
  }

  // --- Section scaffolding ----------------------------------------------------

  function section(id, title, body, { setCount = 0, search = '' } = {}) {
    const isCollapsed = collapsed[id] === true;
    return `
      <section class="sp-section ${isCollapsed ? 'is-collapsed' : ''}" data-section="${id}" data-search="${escapeHtml((title + ' ' + search).toLowerCase())}">
        <button class="sp-section-head" data-toggle-section="${id}" aria-expanded="${!isCollapsed}">
          <span class="sp-chevron">▸</span>
          <span class="sp-section-title">${escapeHtml(title)}</span>
          ${setCount ? `<span class="sp-set-count" title="${setCount} set in this context">${setCount}</span>` : ''}
        </button>
        <div class="sp-section-body">${body}</div>
      </section>
    `;
  }

  function countSet(ctx, props) {
    return props.filter(p => ctx.resolved.own[p] !== undefined).length;
  }

  // Status dot + label for one property row.
  function dot(ctx, props) {
    const list = Array.isArray(props) ? props : [props];
    const own = list.find(p => ctx.resolved.own[p] !== undefined);
    const inherited = list.find(p => ctx.resolved.inherited[p] !== undefined);
    if (own) {
      const fromOtter = ctx.resolved.origin[own] === 'otter';
      return `<button class="sp-dot is-set ${fromOtter ? 'is-otter' : ''}" data-reset="${list.join(',')}"
        title="${fromOtter ? 'Set in the Otter source' : 'Set in styles.css'} for this context. Click to reset."></button>`;
    }
    if (inherited) {
      return `<span class="sp-dot is-inherited" title="Inherited from ${escapeHtml(ctx.resolved.inheritedFrom[inherited])}"></span>`;
    }
    return '<span class="sp-dot"></span>';
  }

  function valueOf(ctx, prop) {
    return ctx.resolved.own[prop] ?? '';
  }

  function placeholderOf(ctx, prop, fallback = '') {
    const inherited = ctx.resolved.inherited[prop];
    if (inherited !== undefined) return inherited;
    const computed = ctx.computed[prop];
    return computed || fallback;
  }

  function field(ctx, prop, label, control, { search = '', scrub = null, wide = false } = {}) {
    const scrubAttrs = scrub
      ? `data-scrub="${prop}" data-unit="${scrub.unit ?? 'px'}" data-step="${scrub.step ?? 1}" data-min="${scrub.min ?? ''}"`
      : '';
    return `
      <div class="sp-field ${wide ? 'is-wide' : ''}" data-search="${escapeHtml((prop + ' ' + label + ' ' + search).toLowerCase())}">
        ${dot(ctx, prop)}
        <label class="sp-label ${scrub ? 'sp-scrub' : ''}" ${scrubAttrs} title="${scrub ? 'Drag left/right to change. Shift = ×10' : escapeHtml(prop)}">${escapeHtml(label)}</label>
        <div class="sp-control">${control}</div>
      </div>
    `;
  }

  function lengthInput(ctx, prop, { unit = 'px', placeholder = '' } = {}) {
    return `<input type="text" class="sp-input sp-len" data-prop="${prop}" data-unit="${unit}" data-focus-key="p-${prop}"
      value="${escapeHtml(valueOf(ctx, prop))}" placeholder="${escapeHtml(placeholderOf(ctx, prop, placeholder))}" spellcheck="false" />`;
  }

  function textInput(ctx, prop, placeholder = '') {
    return `<input type="text" class="sp-input" data-prop="${prop}" data-focus-key="p-${prop}"
      value="${escapeHtml(valueOf(ctx, prop))}" placeholder="${escapeHtml(placeholderOf(ctx, prop, placeholder))}" spellcheck="false" />`;
  }

  function selectInput(ctx, prop, options) {
    const current = valueOf(ctx, prop);
    const inherited = placeholderOf(ctx, prop);
    const known = options.some(([v]) => v === current);
    return `
      <select class="sp-select" data-prop="${prop}" data-focus-key="p-${prop}">
        <option value="" ${current === '' ? 'selected' : ''}>${escapeHtml(inherited ? `(${shorten(inherited)})` : '—')}</option>
        ${!known && current ? `<option value="${escapeHtml(current)}" selected>${escapeHtml(current)}</option>` : ''}
        ${options.filter(([v]) => v !== '').map(([v, l]) => `<option value="${escapeHtml(v)}" ${v === current ? 'selected' : ''}>${escapeHtml(l)}</option>`).join('')}
      </select>`;
  }

  // Segmented buttons. Clicking the active one clears the value.
  function segmented(ctx, prop, options, { effective = null } = {}) {
    const current = valueOf(ctx, prop);
    const shown = current || effective || placeholderOf(ctx, prop);
    return `
      <div class="sp-seg" data-prop="${prop}">
        ${options.map(([v, label, title]) => `
          <button class="sp-seg-btn ${current === v ? 'is-active' : (!current && shown === v ? 'is-implied' : '')}"
            data-value="${escapeHtml(v)}" title="${escapeHtml(title || v)}">${label}</button>`).join('')}
      </div>`;
  }

  function colorInput(ctx, prop) {
    const value = valueOf(ctx, prop);
    const fallback = placeholderOf(ctx, prop, '');
    const swatch = value || fallback;
    return `
      <div class="sp-color">
        <label class="sp-swatch" style="--swatch: ${escapeHtml(swatch || 'transparent')}" title="Pick a color">
          <input type="color" data-color-for="${prop}" value="${toHexColor(swatch, '#000000')}" />
        </label>
        <input type="text" class="sp-input" data-prop="${prop}" data-focus-key="p-${prop}" value="${escapeHtml(value)}"
          placeholder="${escapeHtml(fallback || 'none')}" spellcheck="false" />
        <button class="sp-palette-btn" data-palette-for="${prop}" title="Project colors">◐</button>
      </div>`;
  }

  // --- Layout -------------------------------------------------------------------

  function renderLayoutSection(ctx) {
    const { selected } = ctx;
    const schema = ComponentSchema[selected.kind] || {};
    const isContainer = schema.isContainer || selected.kind === 'window';

    // The compiled window stacks its children in its own content column, so
    // only the spacing between them can be designed here.
    if (selected.kind === 'window') {
      return section('layout', 'Layout',
        field(ctx, 'gap', 'Spacing', lengthInput(ctx, 'gap'), { scrub: { min: 0 }, search: 'gap spacing between' }) +
        '<div class="sp-note">A window stacks its children top to bottom. To arrange them another way, select them and wrap them in a row or column (right-click, or Ctrl+G).</div>',
        { setCount: countSet(ctx, ['gap']), search: 'gap spacing' });
    }
    // Controls get a computed flex/grid display from the browser (a button is
    // inline-flex); only offer child-layout tools when the design asks for it.
    const declared = valueOf(ctx, 'display') || ctx.resolved.inherited.display || '';
    const display = isContainer ? (declared || placeholderOf(ctx, 'display')) : declared;
    const isFlex = display.includes('flex');
    const isGrid = display.includes('grid');

    let body = field(ctx, 'display', 'Display', segmented(ctx, 'display', [
      ['block', 'Block', 'display: block'],
      ['flex', 'Flex', 'display: flex'],
      ['grid', 'Grid', 'display: grid'],
      ['inline-block', 'Inline', 'display: inline-block'],
      ['none', '⊘', 'display: none (hidden)']
    ]), { wide: true, search: 'hide hidden' });

    if (isFlex) {
      const direction = valueOf(ctx, 'flex-direction') || placeholderOf(ctx, 'flex-direction') || 'row';
      body += field(ctx, 'flex-direction', 'Direction', segmented(ctx, 'flex-direction', [
        ['row', '→', 'Row (left to right)'],
        ['column', '↓', 'Column (top to bottom)'],
        ['row-reverse', '←', 'Row reversed'],
        ['column-reverse', '↑', 'Column reversed']
      ]), { search: 'flex row column' });
      body += renderAlignMatrix(ctx, direction);
      body += field(ctx, 'flex-wrap', 'Wrap', segmented(ctx, 'flex-wrap', [
        ['nowrap', 'No wrap'], ['wrap', 'Wrap']
      ]));
      body += field(ctx, 'gap', 'Gap', lengthInput(ctx, 'gap'), { scrub: { min: 0 }, search: 'spacing between' });
    }

    if (isGrid) {
      const columns = valueOf(ctx, 'grid-template-columns') || placeholderOf(ctx, 'grid-template-columns');
      const colCount = gridTrackCount(columns);
      body += `
        <div class="sp-field is-wide" data-search="grid columns template">
          ${dot(ctx, 'grid-template-columns')}
          <label class="sp-label">Columns</label>
          <div class="sp-control sp-stepper">
            <button class="sp-step-btn" data-grid-cols="-1" title="Remove a column">−</button>
            <span class="sp-step-value">${colCount || '—'}</span>
            <button class="sp-step-btn" data-grid-cols="1" title="Add a column">+</button>
          </div>
        </div>`;
      body += field(ctx, 'grid-template-columns', 'Col tracks', textInput(ctx, 'grid-template-columns', 'repeat(3, 1fr)'), { wide: true, search: 'grid' });
      body += field(ctx, 'grid-template-rows', 'Row tracks', textInput(ctx, 'grid-template-rows', 'auto'), { wide: true, search: 'grid' });
      body += field(ctx, 'gap', 'Gap', lengthInput(ctx, 'gap'), { scrub: { min: 0 }, search: 'spacing grid' });
      body += field(ctx, 'justify-items', 'Items X', segmented(ctx, 'justify-items', [
        ['start', 'Start'], ['center', 'Center'], ['end', 'End'], ['stretch', 'Fill']
      ]), { search: 'grid align horizontal' });
      body += field(ctx, 'align-items', 'Items Y', segmented(ctx, 'align-items', [
        ['start', 'Top'], ['center', 'Middle'], ['end', 'Bottom'], ['stretch', 'Fill']
      ]), { search: 'grid align vertical' });
    }

    if (!isContainer && !isFlex && !isGrid && display !== 'none') {
      body += '<div class="sp-note">Set Display to Flex or Grid to lay out children.</div>';
    }

    if (ctx.parentLayout === 'flex') {
      body += `<div class="sp-subhead">Inside a flex parent</div>`;
      body += field(ctx, 'flex', 'Sizing', segmented(ctx, 'flex', [
        ['0 0 auto', 'Fixed', "Don't grow or shrink"],
        ['0 1 auto', 'Fit', 'Shrink if needed'],
        ['1 1 0%', 'Fill', 'Grow to fill space']
      ]), { search: 'grow shrink flex child', wide: true });
      body += field(ctx, 'align-self', 'Align self', segmented(ctx, 'align-self', [
        ['flex-start', 'Start'], ['center', 'Center'], ['flex-end', 'End'], ['stretch', 'Fill']
      ]), { search: 'flex child' });
      body += field(ctx, 'order', 'Order', lengthInput(ctx, 'order', { unit: '' }), { scrub: { unit: '', step: 1 }, search: 'flex child' });
    }

    if (ctx.parentLayout === 'grid') {
      body += `<div class="sp-subhead">Inside a grid parent</div>`;
      body += field(ctx, 'grid-column', 'Column', textInput(ctx, 'grid-column', 'auto / span 1'), { search: 'grid child span', wide: true });
      body += field(ctx, 'grid-row', 'Row', textInput(ctx, 'grid-row', 'auto / span 1'), { search: 'grid child span', wide: true });
      body += `
        <div class="sp-field is-wide" data-search="grid span">
          <span class="sp-dot"></span>
          <label class="sp-label">Span</label>
          <div class="sp-control sp-span-btns">
            ${[1, 2, 3, 4].map(n => `<button class="sp-seg-btn" data-grid-span="${n}" title="Span ${n} columns">${n} col</button>`).join('')}
            <button class="sp-seg-btn" data-grid-span="full" title="Span every column">Full</button>
          </div>
        </div>`;
    }

    return section('layout', 'Layout', body, {
      setCount: countSet(ctx, ['display', 'flex-direction', 'justify-content', 'align-items', 'flex-wrap', 'gap',
        'grid-template-columns', 'grid-template-rows', 'justify-items', 'flex', 'align-self', 'order', 'grid-column', 'grid-row']),
      search: 'flex grid align justify'
    });
  }

  function renderAlignMatrix(ctx, direction) {
    const isColumn = direction.startsWith('column');
    const justify = valueOf(ctx, 'justify-content') || placeholderOf(ctx, 'justify-content') || 'flex-start';
    const align = valueOf(ctx, 'align-items') || placeholderOf(ctx, 'align-items') || 'stretch';
    const positions = ['flex-start', 'center', 'flex-end'];
    const norm = (v) => ({ start: 'flex-start', end: 'flex-end', normal: 'stretch', left: 'flex-start', right: 'flex-end' }[v] || v);
    const j = norm(justify);
    const a = norm(align);

    let cells = '';
    for (let y = 0; y < 3; y++) {
      for (let x = 0; x < 3; x++) {
        // On screen, x is horizontal. For a row, horizontal is the main axis
        // (justify-content); for a column it is the cross axis (align-items).
        const jv = isColumn ? positions[y] : positions[x];
        const av = isColumn ? positions[x] : positions[y];
        const active = j === jv && a === av;
        cells += `<button class="sp-align-cell ${active ? 'is-active' : ''}" data-justify="${jv}" data-align="${av}"
          title="justify-content: ${jv}; align-items: ${av}"><span></span></button>`;
      }
    }
    return `
      <div class="sp-field is-wide sp-align-field" data-search="align justify alignment center distribute">
        ${dot(ctx, ['justify-content', 'align-items'])}
        <label class="sp-label">Align</label>
        <div class="sp-control sp-align-wrap">
          <div class="sp-align-matrix ${isColumn ? 'is-column' : 'is-row'}">${cells}</div>
          <div class="sp-align-extras">
            <button class="sp-seg-btn ${j === 'space-between' ? 'is-active' : ''}" data-justify="space-between" title="Space between">Between</button>
            <button class="sp-seg-btn ${j === 'space-around' ? 'is-active' : ''}" data-justify="space-around" title="Space around">Around</button>
            <button class="sp-seg-btn ${j === 'space-evenly' ? 'is-active' : ''}" data-justify="space-evenly" title="Space evenly">Evenly</button>
            <button class="sp-seg-btn ${a === 'stretch' ? 'is-active' : ''}" data-align="stretch" title="Stretch children across">Stretch</button>
            <button class="sp-seg-btn ${a === 'baseline' ? 'is-active' : ''}" data-align="baseline" title="Align text baselines">Baseline</button>
          </div>
        </div>
      </div>`;
  }

  // --- Spacing (box model) ------------------------------------------------------

  function renderSpacingSection(ctx) {
    const ownPad = readBoxSides(ctx.resolved.own, 'padding');
    const ownMar = readBoxSides(ctx.resolved.own, 'margin');
    const inhPad = readBoxSides(ctx.resolved.inherited, 'padding');
    const inhMar = readBoxSides(ctx.resolved.inherited, 'margin');
    const compPad = ctx.computed.padding || ['', '', '', ''];
    const compMar = ctx.computed.margin || ['', '', '', ''];

    const box = (prop, i, own, inh, comp) => {
      const side = SIDES[i];
      const value = own[i] || '';
      const placeholder = inh[i] || shortPx(comp[i]) || '0';
      return `<input type="text" class="sp-box-input sp-box-${side}" data-box="${prop}" data-side="${i}"
        data-focus-key="box-${prop}-${i}" value="${escapeHtml(value)}" placeholder="${escapeHtml(placeholder)}"
        title="${prop}-${side}. Drag to change. Alt: both opposite sides. Shift: all sides." spellcheck="false" />`;
    };

    const body = `
      <div class="sp-boxmodel" data-search="padding margin spacing box">
        <div class="sp-box-margin">
          <span class="sp-box-tag">Margin ${dot(ctx, ['margin', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left'])}</span>
          ${[0, 1, 2, 3].map(i => box('margin', i, ownMar, inhMar, compMar)).join('')}
          <div class="sp-box-padding">
            <span class="sp-box-tag">Padding ${dot(ctx, ['padding', 'padding-top', 'padding-right', 'padding-bottom', 'padding-left'])}</span>
            ${[0, 1, 2, 3].map(i => box('padding', i, ownPad, inhPad, compPad)).join('')}
            <div class="sp-box-content" title="Content">${escapeHtml(shortPx(ctx.computed.width))} × ${escapeHtml(shortPx(ctx.computed.height))}</div>
          </div>
        </div>
      </div>
      <div class="sp-quick-row" data-search="padding margin spacing preset">
        <span class="sp-quick-label">Padding</span>
        ${['0', '8px', '12px', '16px', '24px', '32px'].map(v => `<button class="sp-chip" data-quick-padding="${v}">${v.replace('px', '')}</button>`).join('')}
      </div>
    `;
    return section('spacing', 'Spacing', body, {
      setCount: countSet(ctx, ['padding', 'margin', ...SIDES.map(s => `padding-${s}`), ...SIDES.map(s => `margin-${s}`)]),
      search: 'padding margin'
    });
  }

  // --- Size -----------------------------------------------------------------------

  function renderSizeSection(ctx) {
    const sizeButtons = (prop) => `
      <div class="sp-size-presets">
        <button class="sp-chip" data-set="${prop}" data-value="auto" title="${prop}: auto">Auto</button>
        <button class="sp-chip" data-set="${prop}" data-value="100%" title="${prop}: 100% (fill parent)">Fill</button>
        <button class="sp-chip" data-set="${prop}" data-value="fit-content" title="${prop}: fit-content">Fit</button>
      </div>`;
    let body = `
      <div class="sp-grid-2">
        ${field(ctx, 'width', 'W', lengthInput(ctx, 'width'), { scrub: { min: 0 }, search: 'width size' })}
        ${field(ctx, 'height', 'H', lengthInput(ctx, 'height'), { scrub: { min: 0 }, search: 'height size' })}
      </div>
      <div class="sp-grid-2 sp-preset-row">${sizeButtons('width')}${sizeButtons('height')}</div>
      <div class="sp-grid-2">
        ${field(ctx, 'min-width', 'Min W', lengthInput(ctx, 'min-width'), { scrub: { min: 0 } })}
        ${field(ctx, 'min-height', 'Min H', lengthInput(ctx, 'min-height'), { scrub: { min: 0 } })}
        ${field(ctx, 'max-width', 'Max W', lengthInput(ctx, 'max-width'), { scrub: { min: 0 } })}
        ${field(ctx, 'max-height', 'Max H', lengthInput(ctx, 'max-height'), { scrub: { min: 0 } })}
      </div>
      ${field(ctx, 'overflow', 'Overflow', segmented(ctx, 'overflow', [
        ['visible', 'Show'], ['hidden', 'Clip'], ['auto', 'Scroll'], ['scroll', 'Always']
      ]), { wide: true, search: 'scroll clip' })}
      ${field(ctx, 'aspect-ratio', 'Ratio', segmented(ctx, 'aspect-ratio', [
        ['1 / 1', '1:1'], ['4 / 3', '4:3'], ['16 / 9', '16:9'], ['3 / 4', '3:4']
      ]), { wide: true, search: 'aspect ratio' })}
    `;
    if (ctx.selected.kind === 'image') {
      body += field(ctx, 'object-fit', 'Image fit', segmented(ctx, 'object-fit', [
        ['cover', 'Cover'], ['contain', 'Contain'], ['fill', 'Stretch']
      ]), { wide: true, search: 'image object fit' });
    }
    return section('size', 'Size', body, {
      setCount: countSet(ctx, ['width', 'height', 'min-width', 'min-height', 'max-width', 'max-height', 'overflow', 'aspect-ratio', 'object-fit']),
      search: 'width height min max overflow'
    });
  }

  // --- Position -----------------------------------------------------------------

  function renderPositionSection(ctx) {
    // Declared values only: the canvas itself positions elements relatively.
    const position = valueOf(ctx, 'position') || ctx.resolved.inherited.position || 'static';
    let body = field(ctx, 'position', 'Position', segmented(ctx, 'position', [
      ['static', 'Flow', 'position: static (normal layout)'],
      ['relative', 'Rel', 'position: relative'],
      ['absolute', 'Abs', 'position: absolute (free placement, drag it on the canvas)'],
      ['fixed', 'Fixed', 'position: fixed'],
      ['sticky', 'Sticky', 'position: sticky']
    ], { effective: position }), { wide: true, search: 'absolute relative fixed sticky' });

    if (position !== 'static') {
      body += `
        <div class="sp-offsets" data-search="top right bottom left offset inset">
          ${['top', 'right', 'bottom', 'left'].map(side => `
            <div class="sp-offset sp-offset-${side}">
              ${dot(ctx, side)}
              <input type="text" class="sp-input sp-len" data-prop="${side}" data-unit="px" data-focus-key="p-${side}"
                value="${escapeHtml(valueOf(ctx, side))}" placeholder="${escapeHtml(placeholderOf(ctx, side, side))}" spellcheck="false" />
            </div>`).join('')}
          <div class="sp-offset-center">${escapeHtml(position)}</div>
        </div>
        ${position === 'absolute' ? '<div class="sp-note">Drag it on the canvas to move it freely. Arrow keys nudge (Shift = 10px).</div>' : ''}
      `;
    }
    body += field(ctx, 'z-index', 'Z-index', lengthInput(ctx, 'z-index', { unit: '' }), { scrub: { unit: '', step: 1 }, search: 'layer stack order' });
    return section('position', 'Position', body, {
      setCount: countSet(ctx, ['position', 'top', 'right', 'bottom', 'left', 'z-index']),
      search: 'position absolute'
    });
  }

  // --- Typography -----------------------------------------------------------------

  function renderTypographySection(ctx) {
    const body = `
      ${field(ctx, 'font-family', 'Font', selectInput(ctx, 'font-family', FONT_FAMILIES), { wide: true, search: 'font family typeface' })}
      <div class="sp-grid-2">
        ${field(ctx, 'font-size', 'Size', lengthInput(ctx, 'font-size'), { scrub: { min: 1 }, search: 'font text' })}
        ${field(ctx, 'font-weight', 'Weight', selectInput(ctx, 'font-weight', [
          ['300', 'Light'], ['400', 'Regular'], ['500', 'Medium'], ['600', 'Semibold'], ['700', 'Bold'], ['800', 'Extra bold']
        ]), { search: 'bold font' })}
        ${field(ctx, 'line-height', 'Line', lengthInput(ctx, 'line-height', { unit: '' }), { scrub: { unit: '', step: 0.05, min: 0 }, search: 'line height leading' })}
        ${field(ctx, 'letter-spacing', 'Tracking', lengthInput(ctx, 'letter-spacing'), { scrub: { step: 0.1 }, search: 'letter spacing' })}
      </div>
      ${field(ctx, 'color', 'Color', colorInput(ctx, 'color'), { wide: true, search: 'text color foreground' })}
      ${field(ctx, 'text-align', 'Align', segmented(ctx, 'text-align', [
        ['left', alignIcon('left'), 'Left'], ['center', alignIcon('center'), 'Center'],
        ['right', alignIcon('right'), 'Right'], ['justify', alignIcon('justify'), 'Justify']
      ]), { wide: true, search: 'text align' })}
      ${field(ctx, 'text-transform', 'Case', segmented(ctx, 'text-transform', [
        ['none', '—', 'As typed'], ['uppercase', 'AA', 'UPPERCASE'], ['capitalize', 'Aa', 'Capitalize'], ['lowercase', 'aa', 'lowercase']
      ]), { wide: true, search: 'uppercase capitalize' })}
      ${field(ctx, 'font-style', 'Style', segmented(ctx, 'font-style', [
        ['normal', 'Normal'], ['italic', '<i>Italic</i>']
      ]), { search: 'italic' })}
      ${field(ctx, 'text-decoration', 'Line', segmented(ctx, 'text-decoration', [
        ['none', '—', 'None'], ['underline', '<u>U</u>', 'Underline'], ['line-through', '<s>S</s>', 'Strikethrough']
      ]), { search: 'underline strikethrough decoration' })}
    `;
    return section('typography', 'Typography', body, {
      setCount: countSet(ctx, ['font-family', 'font-size', 'font-weight', 'line-height', 'letter-spacing', 'color', 'text-align', 'text-transform', 'font-style', 'text-decoration']),
      search: 'font text color'
    });
  }

  // --- Background -------------------------------------------------------------------

  function renderBackgroundSection(ctx) {
    const bg = valueOf(ctx, 'background') || valueOf(ctx, 'background-color');
    const gradient = parseLinearGradient(bg);
    const body = `
      ${field(ctx, 'background', 'Fill', segmented(ctx, '__bg-mode', [
        ['solid', 'Solid'], ['gradient', 'Gradient'], ['none', 'None']
      ], { effective: gradient ? 'gradient' : (bg === 'none' || bg === 'transparent' ? 'none' : 'solid') }), { wide: true, search: 'background fill gradient' })}
      ${gradient ? `
        <div class="sp-gradient" data-search="gradient background">
          <div class="sp-gradient-preview" style="background: ${escapeHtml(bg)}"></div>
          <div class="sp-grid-2">
            <div class="sp-field"><span class="sp-dot"></span><label class="sp-label sp-scrub" data-scrub="__gradient-angle" data-unit="deg" data-step="1">Angle</label>
              <div class="sp-control"><input type="text" class="sp-input" data-gradient="angle" value="${gradient.angle}" data-focus-key="grad-angle" /></div></div>
            <div class="sp-field"><span class="sp-dot"></span><label class="sp-label">From</label>
              <div class="sp-control"><label class="sp-swatch" style="--swatch:${escapeHtml(gradient.from)}"><input type="color" data-gradient="from" value="${toHexColor(gradient.from)}" /></label></div></div>
            <div class="sp-field"><span class="sp-dot"></span><label class="sp-label">To</label>
              <div class="sp-control"><label class="sp-swatch" style="--swatch:${escapeHtml(gradient.to)}"><input type="color" data-gradient="to" value="${toHexColor(gradient.to)}" /></label></div></div>
          </div>
        </div>` : field(ctx, 'background', 'Color', colorInput(ctx, 'background'), { wide: true, search: 'background color' })}
      ${field(ctx, 'background-image', 'Image', textInput(ctx, 'background-image', 'url(photo.jpg)'), { wide: true, search: 'background image url' })}
      ${valueOf(ctx, 'background-image') ? field(ctx, 'background-size', 'Size', segmented(ctx, 'background-size', [
        ['cover', 'Cover'], ['contain', 'Contain'], ['auto', 'Auto']
      ]), { wide: true }) : ''}
    `;
    return section('background', 'Background', body, {
      setCount: countSet(ctx, ['background', 'background-color', 'background-image', 'background-size']),
      search: 'background color gradient image'
    });
  }

  // --- Border -------------------------------------------------------------------

  function renderBorderSection(ctx) {
    const border = parseBorder(valueOf(ctx, 'border'));
    const inheritedBorder = parseBorder(placeholderOf(ctx, 'border'));
    const corners = readCorners(ctx.resolved.own);
    const uniform = corners.every(c => c === corners[0]);
    const radiusPlaceholder = ctx.resolved.inherited['border-radius'] || shortPx(ctx.computed['border-radius']) || '0';

    const body = `
      <div class="sp-field is-wide" data-search="border radius rounded corners">
        ${dot(ctx, ['border-radius', ...CORNERS.map(c => `border-${c}-radius`)])}
        <label class="sp-label sp-scrub" data-scrub="border-radius" data-unit="px" data-step="1" data-min="0" title="Drag to change">Radius</label>
        <div class="sp-control sp-radius">
          <input type="text" class="sp-input sp-len" data-prop="border-radius" data-unit="px" data-focus-key="p-border-radius"
            value="${escapeHtml(uniform ? corners[0] : '')}" placeholder="${escapeHtml(uniform ? radiusPlaceholder : 'mixed')}" spellcheck="false" />
          ${['0', '4px', '8px', '12px', '9999px'].map(v => `<button class="sp-chip" data-set="border-radius" data-value="${v}" title="${v}">${v === '9999px' ? 'Pill' : v.replace('px', '')}</button>`).join('')}
        </div>
      </div>
      <div class="sp-corners" data-search="radius corners">
        ${CORNERS.map((corner, i) => `
          <input type="text" class="sp-input sp-corner sp-corner-${corner}" data-corner="${i}" data-focus-key="corner-${i}"
            value="${escapeHtml(uniform ? '' : corners[i])}" placeholder="${escapeHtml(corners[i] || radiusPlaceholder)}" title="${corner} radius" spellcheck="false" />`).join('')}
      </div>
      <div class="sp-field is-wide" data-search="border stroke outline">
        ${dot(ctx, ['border', 'border-width', 'border-style', 'border-color'])}
        <label class="sp-label">Border</label>
        <div class="sp-control sp-border">
          <input type="text" class="sp-input sp-len" data-border-part="width" value="${escapeHtml(border.width)}" placeholder="${escapeHtml(inheritedBorder.width || '0')}" title="Width" data-focus-key="border-w" spellcheck="false" />
          <select class="sp-select" data-border-part="style" title="Style">
            ${['', 'solid', 'dashed', 'dotted', 'double', 'none'].map(s => `<option value="${s}" ${border.style === s ? 'selected' : ''}>${s || '—'}</option>`).join('')}
          </select>
          <label class="sp-swatch" style="--swatch:${escapeHtml(border.color || inheritedBorder.color || 'transparent')}" title="Border color">
            <input type="color" data-border-part="color" value="${toHexColor(border.color || inheritedBorder.color, '#94a3b8')}" />
          </label>
        </div>
      </div>
    `;
    return section('border', 'Border', body, {
      setCount: countSet(ctx, ['border', 'border-radius', 'border-width', 'border-style', 'border-color']),
      search: 'border radius corners'
    });
  }

  // --- Effects ------------------------------------------------------------------

  function renderEffectsSection(ctx) {
    const opacity = valueOf(ctx, 'opacity');
    const opacityShown = opacity !== '' ? opacity : (ctx.resolved.inherited.opacity ?? ctx.computed.opacity ?? '1');
    const shadow = valueOf(ctx, 'box-shadow');
    const transition = valueOf(ctx, 'transition');
    const body = `
      <div class="sp-field is-wide" data-search="opacity transparency fade">
        ${dot(ctx, 'opacity')}
        <label class="sp-label">Opacity</label>
        <div class="sp-control sp-slider-wrap">
          <input type="range" class="sp-range" data-range="opacity" min="0" max="1" step="0.01" value="${escapeHtml(String(opacityShown))}" />
          <span class="sp-range-val">${Math.round(Number(opacityShown) * 100)}%</span>
        </div>
      </div>
      <div class="sp-field is-wide" data-search="shadow elevation drop box-shadow">
        ${dot(ctx, 'box-shadow')}
        <label class="sp-label">Shadow</label>
        <div class="sp-control sp-chip-row">
          ${SHADOW_PRESETS.map(([v, label]) => `<button class="sp-chip ${shadow === v ? 'is-active' : ''}" data-set="box-shadow" data-value="${escapeHtml(v)}" title="${escapeHtml(v)}">${label}</button>`).join('')}
        </div>
      </div>
      ${field(ctx, 'box-shadow', 'Custom', textInput(ctx, 'box-shadow', '0 4px 12px rgba(0,0,0,.1)'), { wide: true, search: 'shadow' })}
      <div class="sp-field is-wide" data-search="transition animation hover motion">
        ${dot(ctx, 'transition')}
        <label class="sp-label">Transition</label>
        <div class="sp-control sp-chip-row">
          ${TRANSITION_PRESETS.map(([v, label]) => `<button class="sp-chip ${transition === v && v ? 'is-active' : ''}" data-set="transition" data-value="${escapeHtml(v)}" title="${escapeHtml(v || 'none')}">${label}</button>`).join('')}
        </div>
      </div>
      ${field(ctx, 'transform', 'Transform', textInput(ctx, 'transform', 'translateY(-2px) scale(1.02)'), { wide: true, search: 'rotate scale translate move' })}
      ${field(ctx, 'cursor', 'Cursor', selectInput(ctx, 'cursor', [
        ['default', 'Default'], ['pointer', 'Pointer (hand)'], ['text', 'Text'], ['move', 'Move'], ['not-allowed', 'Not allowed'], ['grab', 'Grab']
      ]), { wide: true, search: 'mouse pointer' })}
      ${field(ctx, 'backdrop-filter', 'Backdrop', segmented(ctx, 'backdrop-filter', [
        ['none', 'None'], ['blur(6px)', 'Blur S'], ['blur(12px)', 'Blur M'], ['blur(24px)', 'Blur L']
      ]), { wide: true, search: 'blur glass frosted backdrop filter' })}
    `;
    return section('effects', 'Effects', body, {
      setCount: countSet(ctx, ['opacity', 'box-shadow', 'transition', 'transform', 'cursor', 'backdrop-filter']),
      search: 'opacity shadow transition transform cursor'
    });
  }

  // --- All declarations ---------------------------------------------------------

  function renderRawSection(ctx) {
    const own = Object.entries(ctx.resolved.own);
    const body = `
      ${own.length === 0 ? '<div class="sp-note">Nothing set for this breakpoint and state yet.</div>' : ''}
      ${own.map(([k, v]) => `
        <div class="sp-raw-row" data-search="${escapeHtml(k)}">
          <code class="sp-raw-prop" title="${ctx.resolved.origin[k] === 'otter' ? 'Stored in the Otter source' : 'Stored in styles.css'}">${escapeHtml(k)}${ctx.resolved.origin[k] === 'otter' ? '<sup>otter</sup>' : ''}</code>
          <input type="text" class="sp-input" data-prop="${escapeHtml(k)}" data-focus-key="raw-${escapeHtml(k)}" value="${escapeHtml(v)}" spellcheck="false" />
          <button class="sp-raw-del" data-reset="${escapeHtml(k)}" title="Remove ${escapeHtml(k)}">×</button>
        </div>`).join('')}
      <div class="sp-raw-add">
        <input type="text" class="sp-input" id="spNewProp" list="spCssProps" placeholder="property" data-focus-key="new-prop" spellcheck="false" />
        <input type="text" class="sp-input" id="spNewValue" placeholder="value" data-focus-key="new-value" spellcheck="false" />
        <button class="sp-add-btn" id="spAddProp" title="Add declaration">+</button>
        <datalist id="spCssProps">${COMMON_CSS_PROPERTIES.map(p => `<option value="${p}"></option>`).join('')}</datalist>
      </div>
      ${own.length ? '<button class="sp-clear-btn" id="spClearContext">Clear all styles in this context</button>' : ''}
    `;
    return section('raw', `All CSS (${own.length})`, body, { search: 'css custom raw declarations advanced' });
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  function bindEvents(selected) {
    const q = (sel) => containerEl.querySelector(sel);
    const qa = (sel) => containerEl.querySelectorAll(sel);

    // Context: breakpoint, state, search
    qa('[data-breakpoint]').forEach(btn => btn.addEventListener('click', () => {
      styles.setContext({ breakpoint: btn.getAttribute('data-breakpoint') });
    }));
    q('#spStateSelect')?.addEventListener('change', (e) => styles.setContext({ state: e.target.value }));
    q('#spSearch')?.addEventListener('input', (e) => {
      searchText = e.target.value;
      applySearch();
    });

    // Rename (validated; the model renames the CSS rules too)
    const nameInput = q('#propName');
    nameInput?.addEventListener('change', (e) => {
      const newName = e.target.value.trim();
      const error = q('#propNameError');
      const problem = validateName(newName, selected);
      if (problem) {
        error.textContent = problem;
        error.hidden = false;
        e.target.value = selected.name;
        return;
      }
      error.hidden = true;
      if (newName !== selected.name) {
        uiModel.setName(selected.id, newName);
        window.dispatchEvent(new CustomEvent('css-updated', { detail: { source: 'rename' } }));
      }
    });

    // Otter content properties
    qa('.prop-input[data-otter-key]').forEach(input => input.addEventListener('change', (e) => {
      uiModel.setProperty(selected.id, e.target.getAttribute('data-otter-key'), e.target.value.trim() || undefined);
    }));
    qa('.prop-checkbox[data-otter-key]').forEach(chk => chk.addEventListener('change', (e) => {
      uiModel.setProperty(selected.id, e.target.getAttribute('data-otter-key'), e.target.checked);
    }));

    // Collapsible sections
    qa('[data-toggle-section]').forEach(head => head.addEventListener('click', () => {
      const id = head.getAttribute('data-toggle-section');
      collapsed[id] = !collapsed[id];
      saveCollapsed(collapsed);
      head.closest('.sp-section').classList.toggle('is-collapsed', collapsed[id]);
      head.setAttribute('aria-expanded', String(!collapsed[id]));
    }));

    // Reset dots and raw delete buttons
    qa('[data-reset]').forEach(btn => btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const values = {};
      for (const p of btn.getAttribute('data-reset').split(',')) values[p] = null;
      write(values, `reset:${btn.getAttribute('data-reset')}`);
    }));

    // Plain text / length inputs
    qa('.sp-input[data-prop]').forEach(input => {
      const prop = input.getAttribute('data-prop');
      const unit = input.getAttribute('data-unit');
      input.addEventListener('change', () => {
        const value = input.classList.contains('sp-len') ? normalizeLengthInput(input.value, unit ?? 'px') : input.value.trim();
        write({ [prop]: value }, `input:${prop}`);
      });
      if (input.classList.contains('sp-len')) {
        input.addEventListener('keydown', (e) => {
          if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
          e.preventDefault();
          const step = (e.shiftKey ? 10 : e.altKey ? 0.1 : 1) * (e.key === 'ArrowUp' ? 1 : -1);
          const next = stepLength(input.value || input.placeholder, step, unit ?? 'px');
          input.value = next;
          write({ [prop]: next }, `step:${prop}`);
        });
      }
    });

    // Selects
    qa('.sp-select[data-prop]').forEach(sel => sel.addEventListener('change', () => {
      write({ [sel.getAttribute('data-prop')]: sel.value }, `select:${sel.getAttribute('data-prop')}`);
    }));

    // Segmented controls. Clicking the active value clears it.
    qa('.sp-seg[data-prop]').forEach(seg => {
      const prop = seg.getAttribute('data-prop');
      seg.querySelectorAll('.sp-seg-btn').forEach(btn => btn.addEventListener('click', () => {
        const value = btn.getAttribute('data-value');
        if (prop === '__bg-mode') return setBackgroundMode(value);
        write({ [prop]: btn.classList.contains('is-active') ? null : value }, `seg:${prop}`);
      }));
    });

    // Chips that set a value
    qa('[data-set]').forEach(btn => btn.addEventListener('click', () => {
      write({ [btn.getAttribute('data-set')]: btn.getAttribute('data-value') || null }, `chip:${btn.getAttribute('data-set')}`);
    }));

    // Alignment matrix and extras
    qa('.sp-align-cell, .sp-align-extras [data-justify], .sp-align-extras [data-align]').forEach(btn => btn.addEventListener('click', () => {
      const values = {};
      if (btn.hasAttribute('data-justify')) values['justify-content'] = btn.getAttribute('data-justify');
      if (btn.hasAttribute('data-align')) values['align-items'] = btn.getAttribute('data-align');
      write(values, 'align');
    }));

    // Grid column stepper and child span
    qa('[data-grid-cols]').forEach(btn => btn.addEventListener('click', () => {
      const ctx = styles.resolve(selected);
      const current = gridTrackCount(ctx.own['grid-template-columns'] || ctx.inherited['grid-template-columns'] || '') || 1;
      const next = Math.max(1, current + Number(btn.getAttribute('data-grid-cols')));
      write({ 'grid-template-columns': `repeat(${next}, 1fr)` }, 'grid-cols');
    }));
    qa('[data-grid-span]').forEach(btn => btn.addEventListener('click', () => {
      const span = btn.getAttribute('data-grid-span');
      write({ 'grid-column': span === 'full' ? '1 / -1' : `span ${span}` }, 'grid-span');
    }));

    // Colors
    qa('input[type=color][data-color-for]').forEach(picker => {
      const prop = picker.getAttribute('data-color-for');
      picker.addEventListener('input', () => {
        const text = picker.closest('.sp-color')?.querySelector('.sp-input');
        if (text) text.value = picker.value;
        picker.closest('.sp-swatch')?.style.setProperty('--swatch', picker.value);
        scrubbing = true;
        styles.write(targets(), { [prop]: picker.value }, { key: `color:${prop}` });
      });
      picker.addEventListener('change', () => { scrubbing = false; queueRefresh(); });
    });
    qa('[data-palette-for]').forEach(btn => btn.addEventListener('click', (e) => {
      e.stopPropagation();
      openPalette(btn, btn.getAttribute('data-palette-for'));
    }));

    // Opacity slider
    qa('input[data-range="opacity"]').forEach(range => {
      range.addEventListener('input', () => {
        range.nextElementSibling.textContent = `${Math.round(Number(range.value) * 100)}%`;
        scrubbing = true;
        styles.write(targets(), { opacity: Number(range.value) === 1 ? null : range.value }, { key: 'opacity' });
      });
      range.addEventListener('change', () => { scrubbing = false; queueRefresh(); });
    });

    // Box model inputs: type, arrow keys, drag
    qa('.sp-box-input').forEach(input => bindBoxInput(input, selected));
    qa('[data-quick-padding]').forEach(btn => btn.addEventListener('click', () => {
      write(clearLonghands('padding', { padding: btn.getAttribute('data-quick-padding') }), 'quick-padding');
    }));

    // Individual corners
    qa('.sp-corner').forEach(input => input.addEventListener('change', () => {
      const ctx = styles.resolve(selected);
      const corners = readCorners(ctx.own).map((c, i) => c || readCorners(ctx.inherited)[i] || '0');
      corners[Number(input.getAttribute('data-corner'))] = normalizeLengthInput(input.value) || '0';
      const values = { 'border-radius': collapseBox(corners) };
      for (const c of CORNERS) values[`border-${c}-radius`] = null;
      write(values, 'corners');
    }));

    // Border parts are written as one shorthand
    qa('[data-border-part]').forEach(part => {
      const handler = () => {
        const ctx = styles.resolve(selected);
        const current = parseBorder(ctx.own.border || ctx.inherited.border || '');
        const kind = part.getAttribute('data-border-part');
        current[kind] = kind === 'width' ? normalizeLengthInput(part.value) : part.value;
        if (kind === 'color') part.closest('.sp-swatch')?.style.setProperty('--swatch', part.value);
        if (!current.style && (current.width || current.color)) current.style = 'solid';
        if (!current.width && (current.style || current.color)) current.width = '1px';
        const shorthand = [current.width, current.style, current.color].filter(Boolean).join(' ');
        styles.write(targets(), { border: shorthand || null }, { key: 'border' });
        if (kind !== 'color') queueRefresh();
      };
      part.addEventListener(part.type === 'color' ? 'input' : 'change', handler);
      if (part.type === 'color') part.addEventListener('change', () => queueRefresh());
    });

    // Gradient editor
    qa('[data-gradient]').forEach(input => {
      const handler = () => {
        const ctx = styles.resolve(selected);
        const g = parseLinearGradient(ctx.own.background || ctx.own['background-color'] || '') || { angle: '135deg', from: '#2563eb', to: '#7c3aed' };
        const part = input.getAttribute('data-gradient');
        g[part] = part === 'angle' ? normalizeLengthInput(input.value, 'deg') : input.value;
        input.closest('.sp-swatch')?.style.setProperty('--swatch', input.value);
        const css = `linear-gradient(${g.angle}, ${g.from}, ${g.to})`;
        const preview = containerEl.querySelector('.sp-gradient-preview');
        if (preview) preview.style.background = css;
        scrubbing = input.type === 'color';
        styles.write(targets(), { background: css, 'background-color': null }, { key: 'gradient' });
      };
      input.addEventListener(input.type === 'color' ? 'input' : 'change', handler);
      input.addEventListener('change', () => { scrubbing = false; queueRefresh(); });
    });

    // Scrub labels
    qa('.sp-scrub[data-scrub]').forEach(label => bindScrub(label, selected));

    // Raw add / clear
    q('#spAddProp')?.addEventListener('click', addRawDeclaration);
    q('#spNewValue')?.addEventListener('keydown', (e) => { if (e.key === 'Enter') addRawDeclaration(); });
    q('#spClearContext')?.addEventListener('click', () => { styles.clear(targets()); queueRefresh(); });
  }

  function addRawDeclaration() {
    const keyInput = containerEl.querySelector('#spNewProp');
    const valueInput = containerEl.querySelector('#spNewValue');
    const prop = keyInput.value.trim().toLowerCase();
    const value = valueInput.value.trim();
    if (!/^-{0,2}[a-z][a-z0-9-]*$/.test(prop) || !value) {
      keyInput.classList.toggle('is-invalid', !/^-{0,2}[a-z][a-z0-9-]*$/.test(prop));
      valueInput.classList.toggle('is-invalid', !value);
      return;
    }
    write({ [prop]: value }, `raw:${prop}`);
  }

  function setBackgroundMode(mode) {
    const selected = uiModel.getComponent(uiModel.selectedId);
    const ctx = styles.resolve(selected);
    const current = ctx.own.background || ctx.own['background-color'] || ctx.inherited.background || '';
    if (mode === 'gradient') {
      if (parseLinearGradient(current)) return;
      const base = current && !current.includes('gradient') ? toHexColor(current, '#2563eb') : '#2563eb';
      write({ background: `linear-gradient(135deg, ${base}, #7c3aed)`, 'background-color': null }, 'bg-mode');
    } else if (mode === 'none') {
      write({ background: 'transparent', 'background-color': null }, 'bg-mode');
    } else {
      const g = parseLinearGradient(current);
      write({ background: g ? g.from : (current && current !== 'transparent' ? current : '#ffffff'), 'background-color': null }, 'bg-mode');
    }
  }

  // Remove padding-top etc. whenever the shorthand is written, so the
  // stylesheet keeps one clear source of truth.
  function clearLonghands(prop, values) {
    for (const side of SIDES) values[`${prop}-${side}`] = null;
    return values;
  }

  function writeBoxSide(selected, prop, sideIndex, value, mode, key) {
    const ctx = styles.resolve(selected);
    const own = readBoxSides(ctx.own, prop);
    const inherited = readBoxSides(ctx.inherited, prop);
    const sides = own.map((v, i) => v || inherited[i] || '0');
    const indexes = mode === 'all' ? [0, 1, 2, 3] : mode === 'pair' ? [sideIndex, (sideIndex + 2) % 4] : [sideIndex];
    for (const i of indexes) sides[i] = value;
    styles.write(targets(), clearLonghands(prop, { [prop]: collapseBox(sides) }), { key });
  }

  function bindBoxInput(input, selected) {
    const prop = input.getAttribute('data-box');
    const side = Number(input.getAttribute('data-side'));
    input.addEventListener('change', () => {
      writeBoxSide(selected, prop, side, normalizeLengthInput(input.value) || '0', 'one', `box:${prop}`);
      queueRefresh();
    });
    input.addEventListener('keydown', (e) => {
      if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
      e.preventDefault();
      const next = stepLength(input.value || input.placeholder, (e.shiftKey ? 10 : 1) * (e.key === 'ArrowUp' ? 1 : -1));
      input.value = next;
      writeBoxSide(selected, prop, side, next, 'one', `box:${prop}`);
    });
    // Drag vertically or horizontally on the value to scrub it; a click
    // without movement just focuses the input for typing.
    input.addEventListener('pointerdown', (e) => {
      if (document.activeElement === input) return;
      const startX = e.clientX;
      const startY = e.clientY;
      const start = parseLength(input.value || input.placeholder) || { num: 0, unit: 'px' };
      let moved = false;
      const move = (ev) => {
        const delta = (ev.clientX - startX) - (ev.clientY - startY);
        if (!moved && Math.abs(delta) < 3) return;
        if (!moved) {
          moved = true;
          scrubbing = true;
          input.setPointerCapture?.(e.pointerId);
          document.body.classList.add('sp-is-scrubbing');
        }
        const factor = ev.shiftKey ? 10 : 1;
        let num = start.num + Math.round(delta / 2) * factor;
        if (prop === 'padding') num = Math.max(0, num);
        const value = `${formatNumber(num)}${num === 0 ? '' : (start.unit || 'px')}`;
        input.value = value;
        const mode = ev.shiftKey && ev.altKey ? 'all' : ev.altKey ? 'pair' : 'one';
        writeBoxSide(selected, prop, side, value, mode, `box-drag:${prop}`);
      };
      const up = () => {
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        document.body.classList.remove('sp-is-scrubbing');
        if (moved) {
          scrubbing = false;
          queueRefresh();
        }
      };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
      e.preventDefault();
      // No drag: behave like a click and focus for typing.
      const focusIfClick = () => {
        window.removeEventListener('pointerup', focusIfClick);
        if (!moved) { input.focus(); input.select(); }
      };
      window.addEventListener('pointerup', focusIfClick);
    });
  }

  // Figma-style scrubbing: drag a label left/right to change its value.
  function bindScrub(label, selected) {
    const prop = label.getAttribute('data-scrub');
    const unit = label.getAttribute('data-unit') ?? 'px';
    const step = Number(label.getAttribute('data-step') || 1);
    const min = label.getAttribute('data-min') === '' ? null : Number(label.getAttribute('data-min'));
    label.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      const row = label.closest('.sp-field');
      const input = row?.querySelector('.sp-input');
      const startX = e.clientX;
      const start = parseLength(input?.value || input?.placeholder || '') || { num: 0, unit };
      label.setPointerCapture?.(e.pointerId);
      scrubbing = true;
      document.body.classList.add('sp-is-scrubbing');
      const move = (ev) => {
        const factor = ev.shiftKey ? 10 : 1;
        let num = start.num + Math.round((ev.clientX - startX) / 2) * step * factor;
        if (min !== null) num = Math.max(min, num);
        const outUnit = start.unit || unit;
        const value = prop === '__gradient-angle' ? `${formatNumber(num)}deg` : (outUnit ? `${formatNumber(num)}${outUnit}` : formatNumber(num));
        if (input) input.value = value;
        if (prop === '__gradient-angle') {
          input?.dispatchEvent(new Event('change'));
          scrubbing = true;
          return;
        }
        styles.write(targets(), { [prop]: value }, { key: `scrub:${prop}` });
      };
      const up = () => {
        window.removeEventListener('pointermove', move);
        window.removeEventListener('pointerup', up);
        document.body.classList.remove('sp-is-scrubbing');
        scrubbing = false;
        queueRefresh();
      };
      window.addEventListener('pointermove', move);
      window.addEventListener('pointerup', up);
    });
  }

  // A small popover with the colors already used in styles.css.
  function openPalette(anchor, prop) {
    document.querySelector('.sp-palette-pop')?.remove();
    const colors = cssAstManager.getColorPalette(18);
    const defaults = ['#0f172a', '#334155', '#64748b', '#e2e8f0', '#ffffff', '#2563eb', '#7c3aed', '#16a34a', '#f59e0b', '#dc2626'];
    const pop = document.createElement('div');
    pop.className = 'sp-palette-pop';
    const swatches = (list) => list.map(c => `<button class="sp-pal-swatch" style="--swatch:${escapeHtml(c)}" data-color="${escapeHtml(c)}" title="${escapeHtml(c)}"></button>`).join('');
    pop.innerHTML = `
      ${colors.length ? `<div class="sp-pal-title">Used in this project</div><div class="sp-pal-grid">${swatches(colors)}</div>` : ''}
      <div class="sp-pal-title">Basics</div><div class="sp-pal-grid">${swatches(defaults)}</div>
      <button class="sp-pal-clear" data-color="">Clear</button>
    `;
    document.body.appendChild(pop);
    const rect = anchor.getBoundingClientRect();
    pop.style.top = `${Math.min(window.innerHeight - pop.offsetHeight - 8, rect.bottom + 6)}px`;
    pop.style.left = `${Math.max(8, rect.right - pop.offsetWidth)}px`;
    pop.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-color]');
      if (!btn) return;
      write({ [prop]: btn.getAttribute('data-color') || null }, `palette:${prop}`);
      pop.remove();
    });
    const close = (e) => {
      if (!pop.contains(e.target)) {
        pop.remove();
        document.removeEventListener('pointerdown', close, true);
      }
    };
    setTimeout(() => document.addEventListener('pointerdown', close, true), 0);
  }

  function applySearch() {
    const term = searchText.trim().toLowerCase();
    containerEl.querySelectorAll('.sp-section').forEach(sectionEl => {
      if (!term) {
        sectionEl.hidden = false;
        sectionEl.classList.remove('is-searching');
        sectionEl.querySelectorAll('[data-search]').forEach(el => { el.hidden = false; });
        return;
      }
      sectionEl.classList.add('is-searching');
      const sectionMatch = (sectionEl.getAttribute('data-search') || '').includes(term);
      let any = false;
      sectionEl.querySelectorAll('.sp-section-body [data-search]').forEach(el => {
        const match = (el.getAttribute('data-search') || '').includes(term);
        el.hidden = !match && !sectionMatch;
        if (match) any = true;
      });
      sectionEl.hidden = !any && !sectionMatch;
    });
  }

  function validateName(name, comp) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) return 'Use letters, digits and _ only, starting with a letter.';
    const clash = uiModel.getAllComponents().find(c => c.name === name && c.id !== comp.id);
    if (clash) return `"${name}" is already used by another ${clash.kind}.`;
    return null;
  }

  // ---------------------------------------------------------------------------
  // Wiring
  // ---------------------------------------------------------------------------

  update();

  uiModel.subscribe((type, detail) => {
    if (scrubbing) return;
    if (type === 'property' && detail?.source === 'style') return queueRefresh();
    if (['select', 'property', 'rename', 'template', 'undo', 'redo', 'add', 'remove', 'move', 'parse', 'source-clear'].includes(type)) {
      queueRefresh();
    }
  });

  window.addEventListener('css-updated', (e) => {
    if (scrubbing) return;
    // Style edits from this panel refresh through queueRefresh already.
    if (e.detail?.source !== 'style') queueRefresh();
  });
  window.addEventListener('otter:style-context', () => update());
  // The canvas re-renders asynchronously; computed placeholders follow it.
  window.addEventListener('otter:canvas-rendered', () => { if (!scrubbing && !containerEl.contains(document.activeElement)) queueRefresh(); });

  return { update, styles };
}

// -----------------------------------------------------------------------------
// Pure helpers
// -----------------------------------------------------------------------------

function loadCollapsed() {
  try { return JSON.parse(localStorage.getItem(SECTION_STORE_KEY) || '{}') || {}; } catch { return {}; }
}

function saveCollapsed(state) {
  try { localStorage.setItem(SECTION_STORE_KEY, JSON.stringify(state)); } catch { /* storage unavailable */ }
}

function gridTrackCount(template) {
  const text = String(template || '').trim();
  if (!text || text === 'none') return 0;
  const repeat = text.match(/^repeat\(\s*(\d+)\s*,/);
  if (repeat) return Number(repeat[1]);
  return splitTopLevel(text).length;
}

function parseBorder(value) {
  const out = { width: '', style: '', color: '' };
  for (const part of splitTopLevel(value || '')) {
    if (/^(none|solid|dashed|dotted|double|groove|ridge|inset|outset|hidden)$/.test(part)) out.style = part;
    else if (parseLength(part) || /^(thin|medium|thick)$/.test(part)) out.width = part;
    else out.color = part;
  }
  return out;
}

function parseLinearGradient(value) {
  const m = String(value || '').match(/^linear-gradient\(\s*([^,]+?)\s*,\s*(.+?)\s*,\s*([^,]+?)\s*\)$/);
  if (!m) return null;
  let angle = m[1];
  if (!/deg$|^to /.test(angle)) return null;
  return { angle, from: m[2], to: m[3] };
}

function shortPx(value) {
  if (!value) return '';
  const n = parseFloat(value);
  if (Number.isNaN(n)) return value;
  return `${Math.round(n * 10) / 10}`;
}

function shorten(text) {
  const s = String(text);
  return s.length > 22 ? s.slice(0, 21) + '…' : s;
}

function breakpointIcon(id) {
  if (id === 'mobile') return '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/></svg>';
  if (id === 'tablet') return '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="4" y="2" width="16" height="20" rx="2"/><path d="M11 18h2"/></svg>';
  return '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/></svg>';
}

function alignIcon(kind) {
  const lines = {
    left: 'M4 6h16M4 10h10M4 14h16M4 18h10',
    center: 'M4 6h16M7 10h10M4 14h16M7 18h10',
    right: 'M4 6h16M10 10h10M4 14h16M10 18h10',
    justify: 'M4 6h16M4 10h16M4 14h16M4 18h16'
  }[kind];
  return `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="${lines}"/></svg>`;
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
