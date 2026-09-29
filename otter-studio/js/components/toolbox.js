// toolbox.js - Component palette for dragging into visual canvas.
//
// Laid out like the reference design's Components tab
// (docs/studio/reference): a search box, then collapsible groups of tiles -
// an icon over a label. Drag a tile onto the canvas, or click it (or focus
// it and press Enter) to add it to the selected container.

import { ComponentSchema } from '../model/schema.js';

const COLLAPSED_KEY = 'otter-studio-toolbox-collapsed';

function loadCollapsed() {
  try { return new Set(JSON.parse(localStorage.getItem(COLLAPSED_KEY) || '[]')); } catch { return new Set(); }
}

function saveCollapsed(set) {
  try { localStorage.setItem(COLLAPSED_KEY, JSON.stringify([...set])); } catch { /* private mode */ }
}

export function renderToolbox(containerEl, uiModel) {
  containerEl.innerHTML = `
    <div class="toolbox-header">
      <span class="panel-title">Components</span>
      <span class="toolbox-hint">Drag onto the canvas</span>
    </div>
    <div class="toolbox-search">
      <svg class="toolbox-search-icon" viewBox="0 0 16 16" aria-hidden="true"><circle cx="7" cy="7" r="4.25" /><path d="m10.2 10.2 3.3 3.3" /></svg>
      <input type="text" id="toolboxSearch" placeholder="Search components..." aria-label="Search components" />
    </div>
    <div class="toolbox-categories" id="toolboxCategories"></div>
  `;

  const categoriesEl = containerEl.querySelector('#toolboxCategories');
  const searchInput = containerEl.querySelector('#toolboxSearch');
  const collapsed = loadCollapsed();

  function addToCanvas(kind) {
    const selected = uiModel.getComponent(uiModel.selectedId);
    let targetParentId = uiModel.rootId;
    if (selected) {
      const schema = ComponentSchema[selected.kind];
      if (schema && schema.isContainer) targetParentId = selected.id;
      else if (selected.parentId) targetParentId = selected.parentId;
    }
    uiModel.addChild(targetParentId, kind);
  }

  function buildCategories(filter = '') {
    categoriesEl.innerHTML = '';
    const grouped = {};
    const needle = filter.toLowerCase();

    for (const [kind, schema] of Object.entries(ComponentSchema)) {
      if (schema.isRoot) continue; // window cannot be dragged
      if (needle && !schema.label.toLowerCase().includes(needle) && !kind.includes(needle)) continue;
      if (!grouped[schema.category]) grouped[schema.category] = [];
      grouped[schema.category].push({ kind, ...schema });
    }

    if (!Object.keys(grouped).length) {
      categoriesEl.innerHTML = '<div class="toolbox-empty">No component matches that name.</div>';
      return;
    }

    for (const [catName, items] of Object.entries(grouped)) {
      // While searching every group is open, so matches are never hidden.
      const isCollapsed = !needle && collapsed.has(catName);
      const catEl = document.createElement('section');
      catEl.className = `toolbox-category${isCollapsed ? ' is-collapsed' : ''}`;
      catEl.innerHTML = `
        <button type="button" class="category-header" aria-expanded="${!isCollapsed}">
          <svg class="category-chevron" viewBox="0 0 16 16" aria-hidden="true"><path d="M4.5 6.5 8 10l3.5-3.5" /></svg>
          <span class="category-name"></span>
          <span class="category-count">${items.length}</span>
        </button>
        <div class="category-items" role="list"></div>
      `;
      catEl.querySelector('.category-name').textContent = catName;
      catEl.querySelector('.category-header').addEventListener('click', () => {
        const nowCollapsed = !catEl.classList.contains('is-collapsed');
        catEl.classList.toggle('is-collapsed', nowCollapsed);
        catEl.querySelector('.category-header').setAttribute('aria-expanded', String(!nowCollapsed));
        if (!needle) {
          if (nowCollapsed) collapsed.add(catName); else collapsed.delete(catName);
          saveCollapsed(collapsed);
        }
      });

      const itemsEl = catEl.querySelector('.category-items');
      for (const item of items) {
        const itemEl = document.createElement('div');
        itemEl.className = 'toolbox-item';
        itemEl.setAttribute('role', 'listitem');
        itemEl.setAttribute('draggable', 'true');
        itemEl.setAttribute('tabindex', '0');
        itemEl.setAttribute('data-kind', item.kind);
        itemEl.title = `${item.label}: drag onto the canvas, or click to add it to the selected container`;
        itemEl.innerHTML = `
          <div class="item-icon">${item.icon}</div>
          <span class="item-label"></span>
        `;
        itemEl.querySelector('.item-label').textContent = item.label;

        itemEl.addEventListener('dragstart', (e) => {
          e.dataTransfer.setData('text/otter-kind', item.kind);
          e.dataTransfer.setData('application/json', JSON.stringify({
            type: 'new-component',
            kind: item.kind
          }));
          e.dataTransfer.effectAllowed = 'copy';
          itemEl.classList.add('is-dragging');
        });

        itemEl.addEventListener('dragend', () => {
          itemEl.classList.remove('is-dragging');
        });

        // Click (or Enter / Space) adds it to the selected container.
        itemEl.addEventListener('click', () => addToCanvas(item.kind));
        itemEl.addEventListener('keydown', (e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            addToCanvas(item.kind);
          }
        });

        itemsEl.appendChild(itemEl);
      }

      categoriesEl.appendChild(catEl);
    }
  }

  buildCategories();

  searchInput.addEventListener('input', (e) => {
    buildCategories(e.target.value.trim());
  });
}
