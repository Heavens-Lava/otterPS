// hierarchy.js - The Layers panel: the design's component tree, with
// drag-and-drop reordering, collapsible nodes, range selection, inline
// rename, and designer-only hide/lock (designer/view-state.js).

import { ComponentSchema } from '../model/schema.js';

// getActions: the designer's actions (designer/actions.js), so a control
// moved into another container takes on its layout (moveInto).
export function renderHierarchy(containerEl, uiModel, cssAstManager = null, viewState = null, getActions = () => null) {
  const collapsedNodes = new Set();
  let draggedTreeNodeId = null;
  // Where a Shift+click range starts.
  let anchorId = null;

  // Components in the order the tree shows them (expanded nodes only).
  function visibleOrder() {
    const out = [];
    const walk = (id) => {
      const comp = uiModel.getComponent(id);
      if (!comp) return;
      out.push(id);
      if (!collapsedNodes.has(id)) (comp.children || []).forEach(walk);
    };
    if (uiModel.rootId) walk(uiModel.rootId);
    return out;
  }

  function update() {
    containerEl.innerHTML = `
      <div class="hierarchy-header">
        <span class="panel-title">Layers</span>
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

      const hidden = Boolean(viewState?.isHidden(comp.name));
      const locked = Boolean(viewState?.isLocked(comp.name));
      const nodeEl = document.createElement('div');
      nodeEl.className = `tree-node ${isSelected ? 'is-selected' : ''} ${hidden ? 'is-layer-hidden' : ''} ${locked ? 'is-layer-locked' : ''}`;
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
          ${comp.id !== uiModel.rootId && viewState ? `
            <button class="node-action-btn node-eye-btn ${hidden ? 'is-on' : ''}" title="${hidden ? 'Show on canvas' : 'Hide on canvas'} (Ctrl+Shift+H). The app still shows it." aria-pressed="${hidden}">${hidden ? EYE_OFF : EYE}</button>
            <button class="node-action-btn node-lock-btn ${locked ? 'is-on' : ''}" title="${locked ? 'Unlock' : 'Lock'} on canvas (Ctrl+Shift+L)" aria-pressed="${locked}">${locked ? LOCK : UNLOCK}</button>
          ` : ''}
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

      // Click selects; Ctrl+click toggles; Shift+click selects the range
      // from the last clicked row (in the order the tree shows them).
      nodeEl.addEventListener('click', (e) => {
        e.stopPropagation();
        if (e.shiftKey && anchorId && uiModel.getComponent(anchorId)) {
          const order = visibleOrder();
          const [from, to] = [order.indexOf(anchorId), order.indexOf(comp.id)].sort((x, y) => x - y);
          if (from >= 0 && to >= 0) {
            const range = order.slice(from, to + 1).filter(id => id !== uiModel.rootId || from === to);
            uiModel.selectMany(range);
            return;
          }
        }
        anchorId = comp.id;
        uiModel.select(comp.id, e.ctrlKey || e.metaKey);
      });

      nodeEl.querySelector('.node-eye-btn')?.addEventListener('click', (e) => {
        e.stopPropagation();
        viewState.toggleHidden(comp.name);
      });
      nodeEl.querySelector('.node-lock-btn')?.addEventListener('click', (e) => {
        e.stopPropagation();
        viewState.toggleLocked(comp.name);
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

        const moving = uiModel.getComponent(movingId);
        const actions = getActions();
        if (schema.isContainer && ratio >= 0.25 && ratio <= 0.75) {
          // Drop inside this container at the end
          if (actions && moving.parentId !== comp.id) actions.moveInto(moving, comp, null);
          else uiModel.moveChild(movingId, comp.id);
          collapsedNodes.delete(comp.id); // auto-expand
        } else {
          // Drop before or after in parent container
          const parentComp = comp.parentId ? uiModel.getComponent(comp.parentId) : root;
          if (!parentComp) return;

          const siblings = parentComp.children || [];
          const targetIndex = siblings.indexOf(comp.id);
          let insertIndex = ratio < 0.5 ? Math.max(0, targetIndex) : targetIndex + 1;
          // moveChild removes the node first: a later position in the same
          // parent shifts down by one.
          const fromIndex = siblings.indexOf(movingId);
          if (fromIndex !== -1 && fromIndex < insertIndex) insertIndex--;

          // Into another container: it takes on that container's layout.
          if (actions && moving.parentId !== parentComp.id) actions.moveInto(moving, parentComp, insertIndex);
          else uiModel.moveChild(movingId, parentComp.id, insertIndex);
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
  uiModel.subscribe(() => {
    update();
  });
  window.addEventListener('otter:view-state', () => update());
}

const ICON = (d) => `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${d}</svg>`;
const EYE = ICON('<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>');
const EYE_OFF = ICON('<path d="M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.2M6.6 6.6C3.8 8.4 2 12 2 12s3.5 7 10 7a9.6 9.6 0 0 0 5.4-1.6"/>');
const LOCK = ICON('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>');
const UNLOCK = ICON('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.5-2"/>');

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
