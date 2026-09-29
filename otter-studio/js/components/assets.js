// assets.js - The Designer's Assets tab (beside Components; see the
// reference design in docs/studio/reference): the project's images, fonts,
// stylesheets and data files (server/assets.mjs).
//
// Images show as thumbnails. Drag one onto the canvas, or click it, and it
// becomes an Otter image with `source` set to the file, relative to the
// design (js/designer/asset-url.js), at its own size (at most 320 wide).
// Import adds images to assets/images - from the button, or by dropping
// files from the desktop onto the tab. Stylesheets and data files open in
// the editor.

import { ComponentSchema } from '../model/schema.js';
import { assetUrl, relativeToDesign, designDir } from '../designer/asset-url.js';

const GROUPS = [
  { id: 'images', label: 'Images' },
  { id: 'styles', label: 'Styles' },
  { id: 'fonts', label: 'Fonts' },
  { id: 'data', label: 'Data' }
];
const MAX_WIDTH = 320;

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

// Its natural size, scaled down to MAX_WIDTH (or 200 x 140 when unknown).
export function imageSize(naturalWidth, naturalHeight) {
  if (!naturalWidth || !naturalHeight) return { width: 200, height: 140 };
  const scale = Math.min(1, MAX_WIDTH / naturalWidth);
  return { width: Math.round(naturalWidth * scale), height: Math.round(naturalHeight * scale) };
}

export function renderAssets(containerEl, uiModel, ide = window.otterIde) {
  containerEl.innerHTML = `
    <div class="assets-toolbar">
      <div class="toolbox-search">
        <svg class="toolbox-search-icon" viewBox="0 0 16 16" aria-hidden="true"><circle cx="7" cy="7" r="4.25" /><path d="m10.2 10.2 3.3 3.3" /></svg>
        <input type="text" id="assetsSearch" placeholder="Search assets..." aria-label="Search assets" />
      </div>
      <input type="file" id="assetsFileInput" accept="image/*,.svg,.ico" multiple hidden />
    </div>
    <div class="assets-body" id="assetsBody"></div>
  `;
  const bodyEl = containerEl.querySelector('#assetsBody');
  const searchEl = containerEl.querySelector('#assetsSearch');
  const fileInput = containerEl.querySelector('#assetsFileInput');
  let assets = null;
  let folder = null;
  let message = '';

  async function load() {
    folder = ide?.currentProjectFolder || null;
    if (!folder || /\.(json|otter-workspace)$/i.test(folder)) {
      assets = null;
      render();
      return;
    }
    try {
      const res = await fetch(`/api/assets?folder=${encodeURIComponent(folder)}`);
      assets = res.ok ? (await res.json()).assets : null;
    } catch { assets = null; }
    render();
  }

  // Add an image control for `file` (a path in the project) to the selected
  // container, or to where it was dropped (the canvas does that part).
  function imageProperties(file, size) {
    return { source: relativeToDesign(`${folder}/${file.path}`, designDir(ide)), width: size.width, height: size.height };
  }

  function addImage(file, size) {
    const selected = uiModel.getComponent(uiModel.selectedId);
    let parentId = uiModel.rootId;
    if (selected) {
      if (ComponentSchema[selected.kind]?.isContainer) parentId = selected.id;
      else if (selected.parentId) parentId = selected.parentId;
    }
    const child = uiModel.addChild(parentId, 'image', imageProperties(file, size));
    if (child) window.dispatchEvent(new CustomEvent('otter:component-added', { detail: { id: child.id, parentId } }));
  }

  function render() {
    const needle = searchEl.value.trim().toLowerCase();
    if (!assets) {
      bodyEl.innerHTML = `<div class="assets-empty">Open a project to see its images, styles and fonts.</div>`;
      return;
    }
    const parts = [];
    if (message) parts.push(`<div class="assets-message">${escapeHtml(message)}</div>`);
    for (const group of GROUPS) {
      const files = (assets[group.id] || []).filter(f => !needle || f.path.toLowerCase().includes(needle));
      if (group.id !== 'images' && !files.length) continue;
      const tools = group.id === 'images'
        ? `<span class="assets-group-tools">
            <button class="assets-btn" data-assets-action="import" title="Import images into assets/images">+ Import</button>
            <button class="assets-btn icon" data-assets-action="refresh" title="Refresh">↻</button>
          </span>`
        : '';
      parts.push(`<section class="assets-group" data-group="${group.id}">
        <div class="assets-group-header">${group.label}<span class="assets-count">${files.length}</span>${tools}</div>`);
      if (group.id === 'images') {
        parts.push(files.length
          ? `<div class="assets-grid">${files.map(f => `
              <button class="asset-tile" draggable="true" data-path="${escapeHtml(f.path)}" title="${escapeHtml(`${f.path} · ${formatSize(f.size)}\nDrag onto the canvas, or click to add`)}">
                <span class="asset-thumb"><img src="${escapeHtml(assetUrl(f.path, folder))}" alt="" loading="lazy" draggable="false" /></span>
                <span class="asset-name">${escapeHtml(f.name)}</span>
              </button>`).join('')}</div>`
          : `<div class="assets-empty">${needle ? 'No image matches.' : 'No images yet. Import some, or drop image files here.'}</div>`);
      } else {
        parts.push(`<div class="assets-list">${files.map(f => `
          <button class="asset-row" data-open="${escapeHtml(f.path)}" title="Open ${escapeHtml(f.path)}">
            <span class="asset-row-name">${escapeHtml(f.name)}</span>
            <span class="asset-row-path">${escapeHtml(f.path.includes('/') ? f.path.slice(0, f.path.lastIndexOf('/')) : '')}</span>
          </button>`).join('')}</div>`);
      }
      parts.push('</section>');
    }
    bodyEl.innerHTML = parts.join('');
  }

  const fileFor = (tile) => assets?.images.find(f => f.path === tile.dataset.path);
  const sizeFor = (tile) => {
    const img = tile.querySelector('img');
    return imageSize(img?.naturalWidth, img?.naturalHeight);
  };

  bodyEl.addEventListener('click', (e) => {
    const action = e.target.closest('[data-assets-action]')?.dataset.assetsAction;
    if (action === 'import') return fileInput.click();
    if (action === 'refresh') { message = ''; return load(); }
    const tile = e.target.closest('.asset-tile');
    if (tile && fileFor(tile)) return addImage(fileFor(tile), sizeFor(tile));
    const row = e.target.closest('[data-open]');
    if (row && folder) ide?.navigateToLocation?.({ path: `${folder}/${row.dataset.open}`, line: 1, column: 0 });
  });

  // Dragged onto the canvas: a new image with its source (canvas.js drop).
  bodyEl.addEventListener('dragstart', (e) => {
    const tile = e.target.closest('.asset-tile');
    const file = tile && fileFor(tile);
    if (!file) return;
    const payload = { type: 'new-component', kind: 'image', properties: imageProperties(file, sizeFor(tile)) };
    e.dataTransfer.effectAllowed = 'copy';
    e.dataTransfer.setData('application/json', JSON.stringify(payload));
    e.dataTransfer.setData('text/otter-kind', 'image');
    window.dispatchEvent(new CustomEvent('otter:asset-drag', { detail: payload }));
  });

  async function importFiles(files) {
    if (!folder) return;
    const saved = [];
    for (const file of files) {
      const data = await new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result).split(',')[1] || '');
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(file);
      });
      const res = await fetch('/api/assets/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder, name: file.name, data })
      });
      const result = await res.json().catch(() => ({}));
      if (res.ok) saved.push(result.path);
      else message = result.error || `Could not import ${file.name}.`;
    }
    if (saved.length) message = `Imported ${saved.join(', ')}`;
    await load();
    window.dispatchEvent(new CustomEvent('otter:files-changed'));
  }

  fileInput.addEventListener('change', () => {
    importFiles([...fileInput.files]);
    fileInput.value = '';
  });
  searchEl.addEventListener('input', render);
  containerEl.addEventListener('dragover', (e) => {
    if ([...(e.dataTransfer?.types || [])].includes('Files')) { e.preventDefault(); containerEl.classList.add('is-drop-target'); }
  });
  containerEl.addEventListener('dragleave', (e) => {
    if (!containerEl.contains(e.relatedTarget)) containerEl.classList.remove('is-drop-target');
  });
  containerEl.addEventListener('drop', (e) => {
    containerEl.classList.remove('is-drop-target');
    const files = [...(e.dataTransfer?.files || [])];
    if (!files.length) return;
    e.preventDefault();
    importFiles(files);
  });

  return { refresh: load };
}
