// explorer-actions.js - File management in the Explorer (Files pane):
// right-click menu, F2 (rename), Delete (to the Recycle Bin), and drag and
// drop to move. Server side: server/fs-ops.mjs.
//
// Open tabs follow a rename or move (their path changes, unsaved text is
// kept); a deleted file's tab closes. Studio announces
// `otter:file-moved` { from, to } so the designer and CSS model can follow.

import { askText, askConfirm } from '../shell/ask.js';

export function installExplorerActions(ide) {
  const tree = ide.projectTreeEl;
  if (!tree) return;
  let selected = null; // { path, isDir }

  const post = async (route, body) => {
    const res = await fetch(`/api/fs/${route}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
    return data;
  };

  const refresh = () => ide.loadProjectTree(ide.currentProjectFolder);
  const report = (err, what) => ide.setProblemsStatus(false, `${what}: ${err.message}`, 'Explorer');
  const baseName = (p) => p.split('/').pop();
  const parentOf = (p) => p.split('/').slice(0, -1).join('/');

  // What a tree row stands for.
  function targetOf(el) {
    const file = el.closest('.project-file-item[data-path]');
    if (file) return { path: file.getAttribute('data-path'), isDir: false, el: file };
    const folder = el.closest('.project-folder-item[data-folder]');
    if (folder) return { path: folder.getAttribute('data-folder'), isDir: true, el: folder };
    const root = el.closest('.project-folder-root');
    if (root && ide.currentProjectFolder && !/\.(json|otter-workspace)$/i.test(ide.currentProjectFolder)) {
      return { path: ide.currentProjectFolder, isDir: true, isRoot: true, el: root };
    }
    return null;
  }

  // Tabs whose path is `from` or inside it now live at `to`.
  function remapTabs(from, to) {
    let changed = false;
    for (const tab of ide.openTabs) {
      if (tab.path === from || tab.path.startsWith(`${from}/`)) {
        tab.path = to + tab.path.slice(from.length);
        tab.name = baseName(tab.path);
        changed = true;
      }
    }
    if (ide.currentFile && (ide.currentFile === from || ide.currentFile.startsWith(`${from}/`))) {
      ide.currentFile = to + ide.currentFile.slice(from.length);
    }
    if (changed) {
      ide.renderTabs();
      ide.saveSessionState?.();
    }
    window.dispatchEvent(new CustomEvent('otter:file-moved', { detail: { from, to } }));
  }

  async function newItem(kind, folder) {
    const name = await askText({
      title: kind === 'folder' ? 'New Folder' : 'New File',
      message: `In ${folder}`,
      value: kind === 'folder' ? 'new-folder' : 'untitled.ot',
      okLabel: 'Create',
      validate: (v) => (/^[^<>:"|?*\\/]+$/.test(v.trim()) && !/[. ]$/.test(v.trim()) ? null : 'Use a plain name without / \\ : * ? " < > |.')
    });
    if (!name) return;
    try {
      const data = await post(kind === 'folder' ? 'new-folder' : 'new-file', { folder, name: name.trim() });
      await refresh();
      if (kind === 'file') await ide.navigateToLocation({ path: data.path, line: 1, column: 0 });
    } catch (err) { report(err, `Could not create ${name}`); }
  }

  async function rename(target) {
    if (target.isRoot) return;
    const current = baseName(target.path);
    const name = await askText({
      title: `Rename ${target.isDir ? 'Folder' : 'File'}`, value: current, okLabel: 'Rename',
      validate: (v) => (/^[^<>:"|?*\\/]+$/.test(v.trim()) && !/[. ]$/.test(v.trim()) ? null : 'Use a plain name without / \\ : * ? " < > |.')
    });
    if (!name || name.trim() === current) return;
    try {
      const data = await post('rename', { path: target.path, name: name.trim() });
      remapTabs(data.from, data.path);
      await refresh();
    } catch (err) { report(err, `Could not rename ${current}`); }
  }

  async function remove(target) {
    if (target.isRoot) return;
    const affected = ide.openTabs.filter(t => t.path === target.path || t.path.startsWith(`${target.path}/`));
    const unsaved = affected.filter(t => t.isDirty).map(t => t.name);
    const ok = await askConfirm({
      title: `Delete ${baseName(target.path)}?`,
      message: `${target.isDir ? 'The folder and everything in it' : 'The file'} will go to the ${navigator.platform.startsWith('Win') ? 'Recycle Bin' : 'Trash'}, where you can restore it.${unsaved.length ? ` Unsaved changes in ${unsaved.join(', ')} will be lost.` : ''}`,
      okLabel: 'Delete', danger: true
    });
    if (!ok) return;
    try {
      await post('delete', { path: target.path });
      for (const tab of affected) tab.isDirty = false;
      for (const tab of affected) ide.closeTab(tab.path);
      await refresh();
    } catch (err) { report(err, `Could not delete ${baseName(target.path)}`); }
  }

  async function move(fromPath, folder) {
    if (!fromPath || !folder || parentOf(fromPath) === folder || fromPath === folder) return;
    try {
      const data = await post('move', { path: fromPath, folder });
      remapTabs(data.from, data.path);
      await refresh();
    } catch (err) { report(err, `Could not move ${baseName(fromPath)}`); }
  }

  async function copyText(text) {
    try { await navigator.clipboard.writeText(text); ide.setProblemsStatus(true, `Copied ${text}`, 'Explorer'); }
    catch { ide.setProblemsStatus(false, 'The clipboard is not available here.', 'Explorer'); }
  }

  // --- Context menu --------------------------------------------------------------

  function openMenu(x, y, target) {
    closeMenu();
    const folder = target.isDir ? target.path : parentOf(target.path);
    const projectRoot = ide.currentProjectFolder || '';
    const relative = projectRoot && target.path.startsWith(`${projectRoot}/`) ? target.path.slice(projectRoot.length + 1) : target.path;
    const items = [
      { label: 'New File...', run: () => newItem('file', folder) },
      { label: 'New Folder...', run: () => newItem('folder', folder) },
      '-',
      !target.isDir && { label: 'Open', run: () => ide.navigateToLocation({ path: target.path, line: 1, column: 0 }) },
      { label: 'Reveal in File Explorer', run: () => post('reveal', { path: target.path }).catch(err => report(err, 'Could not reveal')) },
      { label: 'Copy Path', run: () => copyText(target.path) },
      { label: 'Copy Relative Path', run: () => copyText(relative) },
      '-',
      !target.isRoot && { label: 'Rename...', hint: 'F2', run: () => rename(target) },
      !target.isRoot && { label: 'Delete', hint: 'Del', danger: true, run: () => remove(target) }
    ].filter(Boolean).filter((item, i, arr) => item !== '-' || (i > 0 && i < arr.length - 1 && arr[i - 1] !== '-'));
    const menu = document.createElement('div');
    menu.className = 'designer-context-menu explorer-context-menu';
    menu.setAttribute('role', 'menu');
    for (const item of items) {
      if (item === '-') { menu.appendChild(Object.assign(document.createElement('div'), { className: 'designer-menu-sep' })); continue; }
      const btn = document.createElement('button');
      btn.className = `designer-menu-item${item.danger ? ' is-danger' : ''}`;
      btn.setAttribute('role', 'menuitem');
      btn.innerHTML = '<span></span><span class="designer-menu-hint"></span>';
      btn.firstChild.textContent = item.label;
      btn.lastChild.textContent = item.hint || '';
      btn.addEventListener('click', () => { closeMenu(); item.run(); });
      menu.appendChild(btn);
    }
    document.body.appendChild(menu);
    menu.style.left = `${Math.min(x, window.innerWidth - menu.offsetWidth - 8)}px`;
    menu.style.top = `${Math.min(y, window.innerHeight - menu.offsetHeight - 8)}px`;
    menu.querySelector('button')?.focus();
    setTimeout(() => document.addEventListener('pointerdown', onOutside, true), 0);
  }
  const onOutside = (e) => { if (!e.target.closest('.explorer-context-menu')) closeMenu(); };
  function closeMenu() {
    document.querySelector('.explorer-context-menu')?.remove();
    document.removeEventListener('pointerdown', onOutside, true);
  }

  tree.addEventListener('contextmenu', (e) => {
    const target = targetOf(e.target);
    if (!target) return;
    e.preventDefault();
    select(target);
    openMenu(e.clientX, e.clientY, target);
  });

  // --- Selection and keys ---------------------------------------------------------

  function select(target) {
    selected = { path: target.path, isDir: target.isDir, isRoot: target.isRoot };
    tree.querySelectorAll('.is-explorer-selected').forEach(el => el.classList.remove('is-explorer-selected'));
    target.el?.classList.add('is-explorer-selected');
  }
  tree.setAttribute('tabindex', '0');
  tree.addEventListener('mousedown', (e) => {
    const target = targetOf(e.target);
    if (target) select(target);
  });
  tree.addEventListener('keydown', (e) => {
    if (!selected || e.target.closest('input, textarea')) return;
    if (e.key === 'F2') { e.preventDefault(); rename(selected); }
    else if (e.key === 'Delete') { e.preventDefault(); remove(selected); }
    else if (e.key === 'Escape') closeMenu();
  });

  // --- Drag and drop to move --------------------------------------------------------

  tree.addEventListener('dragstart', (e) => {
    const target = targetOf(e.target);
    if (!target || target.isRoot) return;
    e.dataTransfer.setData('text/otter-explorer-path', target.path);
    e.dataTransfer.effectAllowed = 'move';
  });
  const dropFolderOf = (el) => {
    const t = targetOf(el);
    if (!t) return null;
    return t.isDir ? t.path : parentOf(t.path);
  };
  tree.addEventListener('dragover', (e) => {
    if (!e.dataTransfer.types.includes('text/otter-explorer-path')) return;
    const folder = dropFolderOf(e.target);
    if (!folder) return;
    e.preventDefault();
    tree.querySelectorAll('.is-drop-target').forEach(el => el.classList.remove('is-drop-target'));
    (e.target.closest('.project-folder-item, .project-folder-root') || e.target.closest('.project-file-item'))?.classList.add('is-drop-target');
  });
  tree.addEventListener('dragleave', (e) => {
    if (!tree.contains(e.relatedTarget)) tree.querySelectorAll('.is-drop-target').forEach(el => el.classList.remove('is-drop-target'));
  });
  tree.addEventListener('drop', (e) => {
    const from = e.dataTransfer.getData('text/otter-explorer-path');
    tree.querySelectorAll('.is-drop-target').forEach(el => el.classList.remove('is-drop-target'));
    if (!from) return;
    e.preventDefault();
    move(from, dropFolderOf(e.target));
  });

  // Rows are re-rendered on every refresh; make them draggable each time.
  const markDraggable = () => tree.querySelectorAll('.project-file-item, .project-folder-item').forEach(el => { el.draggable = true; });
  new MutationObserver(markDraggable).observe(tree, { childList: true, subtree: true });
  markDraggable();

  return { newItem, rename, remove, move, selected: () => selected };
}
