// hierarchy.js - Tree view with drag-and-drop reordering, collapsible nodes, and inline actions

import { ComponentSchema } from '../model/schema.js';

export function renderHierarchy(containerEl, uiModel, cssAstManager = null) {
  const collapsedNodes = new Set();
  let draggedTreeNodeId = null;

  function update() {
    containerEl.innerHTML = `
      <div class="hierarchy-header">
        <span class="panel-title">Component Tree</span>
        <div class="hierarchy-actions">
          <button class="icon-btn" id="treeCollapseAllBtn" title="Collapse All">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="4 14 12 6 20 14"/></svg>
          </button>
          <button class="icon-btn" id="treeExpandAllBtn" title="Expand All">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="4 6 12 14 20 6"/></svg>
          </button>
        </div>
      </div>
      <div class="hierarchy-tree" id="hierarchyTree"></div>
    `;

    const treeEl = containerEl.querySelector('#hierarchyTree');
    const root = uiModel.getRoot();
    if (!root) {
      treeEl.innerHTML = '<div class="empty-state">No components</div>';
      return;
    }

    containerEl.querySelector('#treeCollapseAllBtn').addEventListener('click', () => {
      uiModel.getAllComponents().forEach(c => {
        if (c.children && c.children.length > 0) collapsedNodes.add(c.id);
      });
      update();
    });

    containerEl.querySelector('#treeExpandAllBtn').addEventListener('click', () => {
      collapsedNodes.clear();
      update();
    });

    function renderNode(comp, depth = 0) {
      const schema = ComponentSchema[comp.kind] || {};
      const isSelected = uiModel.isSelected(comp.id);
      const hasChildren = comp.children && comp.children.length > 0;
      const isCollapsed = collapsedNodes.has(comp.id);

      const nodeEl = document.createElement('div');
      nodeEl.className = `tree-node ${isSelected ? 'is-selected' : ''}`;
      nodeEl.style.paddingLeft = `${depth * 16 + 8}px`;
      nodeEl.setAttribute('data-id', comp.id);

      nodeEl.innerHTML = `
        <div class="node-arrow ${isCollapsed ? 'is-collapsed' : ''}">
          ${hasChildren ? '▾' : ''}
        </div>
        <div class="node-icon">${schema.icon || ''}</div>
        <span class="node-name" title="Double click to rename">${escapeHtml(comp.name)}</span>
        <span class="node-kind">${comp.kind}</span>
        <div class="node-actions">
          ${comp.id !== uiModel.rootId ? `
            <button class="node-action-btn node-dup-btn" title="Duplicate (Ctrl+D)">⎘</button>
            <button class="node-action-btn node-del-btn" title="Delete">×</button>
          ` : ''}
        </div>
      `;

      // Toggle collapse/expand on arrow click
      const arrowEl = nodeEl.querySelector('.node-arrow');
      if (hasChildren) {
        arrowEl.addEventListener('click', (e) => {
          e.stopPropagation();
          if (collapsedNodes.has(comp.id)) {
            collapsedNodes.delete(comp.id);
          } else {
            collapsedNodes.add(comp.id);
          }
          update();
        });
      }

      // Selection (Single select or Ctrl+Click multi-select)
      nodeEl.addEventListener('click', (e) => {
        e.stopPropagation();
        const multi = e.ctrlKey || e.metaKey;
        uiModel.select(comp.id, multi);
      });

      // Hover canvas highlight on overlay
      nodeEl.addEventListener('mouseenter', () => {
        window.dispatchEvent(new CustomEvent('otter:highlight-component', { detail: { id: comp.id } }));
      });
      nodeEl.addEventListener('mouseleave', () => {
        window.dispatchEvent(new CustomEvent('otter:highlight-component', { detail: { id: null } }));
      });

      // Action buttons
      const dupBtn = nodeEl.querySelector('.node-dup-btn');
      if (dupBtn) {
        dupBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          uiModel.duplicateComponent(comp.id, cssAstManager);
        });
      }

      const delBtn = nodeEl.querySelector('.node-del-btn');
      if (delBtn) {
        delBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          uiModel.removeComponent(comp.id);
        });
      }

      // Inline rename on double click
      const nameEl = nodeEl.querySelector('.node-name');
      nameEl.addEventListener('dblclick', (e) => {
        e.stopPropagation();
        const currentName = comp.name;
        const input = document.createElement('input');
        input.type = 'text';
        input.className = 'node-inline-input';
        input.value = currentName;

        nameEl.replaceWith(input);
        input.focus();
        input.select();

        function finishRename() {
          const newName = input.value.trim();
          if (newName && newName !== currentName) {
            uiModel.setName(comp.id, newName);
          } else {
            update();
          }
        }

        input.addEventListener('keydown', (ke) => {
          if (ke.key === 'Enter') finishRename();
          if (ke.key === 'Escape') update();
        });
        input.addEventListener('blur', finishRename);
      });

      // --- Tree Drag-and-Drop ---
      if (comp.id !== uiModel.rootId) {
        nodeEl.draggable = true;

        nodeEl.addEventListener('dragstart', (e) => {
          e.stopPropagation();
          draggedTreeNodeId = comp.id;
          nodeEl.classList.add('is-dragging');
          e.dataTransfer.effectAllowed = 'move';
          e.dataTransfer.setData('text/otter-tree-node', comp.id);
        });

        nodeEl.addEventListener('dragend', (e) => {
          e.stopPropagation();
          draggedTreeNodeId = null;
          nodeEl.classList.remove('is-dragging');
          clearDropClasses();
        });
      }

      // Drop target on tree node
      nodeEl.addEventListener('dragover', (e) => {
        e.preventDefault();
        e.stopPropagation();

        if (!draggedTreeNodeId || draggedTreeNodeId === comp.id) return;
        if (uiModel.isDescendantOf(comp.id, draggedTreeNodeId)) return;

        clearDropClasses();

        const rect = nodeEl.getBoundingClientRect();
        const offsetY = e.clientY - rect.top;
        const ratio = offsetY / rect.height;

        if (schema.isContainer) {
          if (ratio < 0.25) {
            nodeEl.classList.add('drop-before');
          } else if (ratio > 0.75) {
            nodeEl.classList.add('drop-after');
          } else {
            nodeEl.classList.add('drop-inside');
          }
        } else {
          if (ratio < 0.5) {
            nodeEl.classList.add('drop-before');
          } else {
            nodeEl.classList.add('drop-after');
          }
        }
      });

      nodeEl.addEventListener('dragleave', (e) => {
        if (!nodeEl.contains(e.relatedTarget)) {
          nodeEl.classList.remove('drop-before', 'drop-after', 'drop-inside');
        }
      });

      nodeEl.addEventListener('drop', (e) => {
        e.preventDefault();
        e.stopPropagation();

        const movingId = draggedTreeNodeId || e.dataTransfer.getData('text/otter-tree-node');
        clearDropClasses();
        draggedTreeNodeId = null;

        if (!movingId || movingId === comp.id) return;
        if (uiModel.isDescendantOf(comp.id, movingId)) return;

        const rect = nodeEl.getBoundingClientRect();
        const offsetY = e.clientY - rect.top;
        const ratio = offsetY / rect.height;

        if (schema.isContainer && ratio >= 0.25 && ratio <= 0.75) {
          // Drop inside this container at the end
          uiModel.moveChild(movingId, comp.id);
          collapsedNodes.delete(comp.id); // auto-expand
        } else {
          // Drop before or after in parent container
          const parentComp = comp.parentId ? uiModel.getComponent(comp.parentId) : root;
          if (!parentComp) return;

          const siblings = parentComp.children || [];
          const targetIndex = siblings.indexOf(comp.id);
          const insertIndex = ratio < 0.5 ? Math.max(0, targetIndex) : targetIndex + 1;

          uiModel.moveChild(movingId, parentComp.id, insertIndex);
        }
      });

      treeEl.appendChild(nodeEl);

      // Render children if expanded
      if (hasChildren && !isCollapsed) {
        for (const childId of comp.children) {
          const child = uiModel.getComponent(childId);
          if (child) renderNode(child, depth + 1);
        }
      }
    }

    function clearDropClasses() {
      treeEl.querySelectorAll('.drop-before, .drop-after, .drop-inside').forEach(el => {
        el.classList.remove('drop-before', 'drop-after', 'drop-inside');
      });
    }

    renderNode(root, 0);
  }

  update();
  uiModel.subscribe((type) => {
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
