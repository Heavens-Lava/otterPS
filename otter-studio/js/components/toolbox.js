// toolbox.js - Component palette for dragging into visual canvas

import { ComponentSchema, ComponentCategories } from '../model/schema.js';

export function renderToolbox(containerEl, uiModel) {
  containerEl.innerHTML = `
    <div class="toolbox-header">
      <span class="panel-title">Toolbox</span>
      <span class="badge">Drag to Canvas</span>
    </div>
    <div class="toolbox-search">
      <input type="text" id="toolboxSearch" placeholder="Search components..." />
    </div>
    <div class="toolbox-categories" id="toolboxCategories"></div>
  `;

  const categoriesEl = containerEl.querySelector('#toolboxCategories');
  const searchInput = containerEl.querySelector('#toolboxSearch');

  function buildCategories(filter = '') {
    categoriesEl.innerHTML = '';
    const grouped = {};

    for (const [kind, schema] of Object.entries(ComponentSchema)) {
      if (schema.isRoot) continue; // window cannot be dragged
      if (filter && !schema.label.toLowerCase().includes(filter.toLowerCase()) && !kind.includes(filter.toLowerCase())) {
        continue;
      }
      if (!grouped[schema.category]) grouped[schema.category] = [];
      grouped[schema.category].push({ kind, ...schema });
    }

    for (const [catName, items] of Object.entries(grouped)) {
      const catEl = document.createElement('div');
      catEl.className = 'toolbox-category';
      catEl.innerHTML = `
        <div class="category-header">
          <span class="category-name">${catName}</span>
          <span class="category-count">${items.length}</span>
        </div>
        <div class="category-items"></div>
      `;

      const itemsEl = catEl.querySelector('.category-items');
      for (const item of items) {
        const itemEl = document.createElement('div');
        itemEl.className = 'toolbox-item';
        itemEl.setAttribute('draggable', 'true');
        itemEl.setAttribute('data-kind', item.kind);
        itemEl.innerHTML = `
          <div class="item-icon">${item.icon}</div>
          <span class="item-label">${item.label}</span>
        `;

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

        // Click to add to currently selected container
        itemEl.addEventListener('click', () => {
          const selected = uiModel.getComponent(uiModel.selectedId);
          let targetParentId = uiModel.rootId;
          if (selected) {
            const schema = ComponentSchema[selected.kind];
            if (schema && schema.isContainer) {
              targetParentId = selected.id;
            } else if (selected.parentId) {
              targetParentId = selected.parentId;
            }
          }
          uiModel.addChild(targetParentId, item.kind);
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
