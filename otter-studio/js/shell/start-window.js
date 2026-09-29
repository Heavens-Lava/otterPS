// start-window.js - What Otter Studio shows when it opens, like Visual
// Studio's start window: recent projects on the left (with search), the ways
// to get started on the right, and "Continue without code" for an empty
// workbench. Nothing is loaded until you choose.
//
// File > Start Window brings it back. Settings > Workbench turns it off
// (Studio then reopens the last session on launch).

const ICONS = {
  newProject: 'M6 3h9l5 5v13H6zM15 3v5h5M13 11v6M10 14h6',
  openFolder: 'M3 7v11h15l3-8H7l-2 8M3 7h6l2 2h8v1',
  learn: 'M12 6.5c-2-1.3-4.7-2-7.5-2v13c2.8 0 5.5.7 7.5 2 2-1.3 4.7-2 7.5-2v-13c-2.8 0-5.5.7-7.5 2zM12 6.5v13',
  folder: 'M3 7v11h18V9h-9l-2-2z',
  search: 'M11 5a6 6 0 1 1 0 12 6 6 0 0 1 0-12zM20 20l-4.5-4.5',
  arrow: 'M5 12h14M13 6l6 6-6 6'
};
const svg = (d, cls = '') => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${d}" /></svg>`;
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

export function formatOpened(iso, now = Date.now()) {
  const then = Date.parse(iso);
  if (!then) return '';
  const days = Math.floor((new Date(now).setHours(0, 0, 0, 0) - new Date(then).setHours(0, 0, 0, 0)) / 86400000);
  const time = new Date(then).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  if (days <= 0) return `Today, ${time}`;
  if (days === 1) return `Yesterday, ${time}`;
  if (days < 7) return new Date(then).toLocaleDateString([], { weekday: 'long' });
  return new Date(then).toLocaleDateString();
}

export function mountStartWindow({ ide, openNewProjectModal, openLearn, version = '1.0' }) {
  let el = null;

  function close() {
    if (!el) return;
    el.remove();
    el = null;
    document.removeEventListener('keydown', onKey, true);
  }

  const onKey = (e) => {
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); }
  };

  function renderRecents(filter = '') {
    const list = el.querySelector('.start-recent-list');
    const needle = filter.trim().toLowerCase();
    const recents = ide.getRecentProjects().filter(r => !needle || `${r.name} ${r.folder}`.toLowerCase().includes(needle));
    if (!recents.length) {
      list.innerHTML = `<div class="start-recent-empty">${needle ? 'No recent project matches that.' : 'Projects you open will appear here, so you can get back to them in one click.'}</div>`;
      return;
    }
    list.innerHTML = recents.map(r => `
      <button type="button" class="start-recent" data-folder="${esc(r.folder)}" title="${esc(r.folder)}">
        ${svg(ICONS.folder, 'start-recent-icon')}
        <span class="start-recent-text">
          <span class="start-recent-name">${esc(r.name || r.folder.split('/').pop())}</span>
          <span class="start-recent-path">${esc(r.folder)}</span>
        </span>
        <span class="start-recent-when">${esc(formatOpened(r.lastOpened))}</span>
      </button>`).join('');
  }

  function show() {
    if (el) return;
    el = document.createElement('div');
    el.className = 'start-window';
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-modal', 'true');
    el.setAttribute('aria-labelledby', 'startWindowTitle');
    el.innerHTML = `
      <div class="start-card">
        <header class="start-head">
          <img class="start-logo" src="img/otter-avatar.svg" alt="" />
          <div>
            <h1 id="startWindowTitle">Otter Studio</h1>
            <p>Version ${esc(version)} · Readable like English. Precise like code.</p>
          </div>
        </header>
        <div class="start-body">
          <section class="start-recent-col" aria-label="Open recent">
            <h2>Open recent</h2>
            <label class="start-search">
              ${svg(ICONS.search)}
              <input type="search" placeholder="Search recent projects" aria-label="Search recent projects" />
            </label>
            <div class="start-recent-list"></div>
          </section>
          <section class="start-actions-col" aria-label="Get started">
            <h2>Get started</h2>
            <button type="button" class="start-action" data-start="new">
              ${svg(ICONS.newProject, 'start-action-icon')}
              <span><strong>Create a new project</strong><span>A console tool, desktop app, website or game, with its first file ready</span></span>
            </button>
            <button type="button" class="start-action" data-start="open">
              ${svg(ICONS.openFolder, 'start-action-icon')}
              <span><strong>Open a folder</strong><span>An Otter project or any folder of .ot files</span></span>
            </button>
            <button type="button" class="start-action" data-start="learn">
              ${svg(ICONS.learn, 'start-action-icon')}
              <span><strong>Learn Otter</strong><span>The guide, the standard library and every keyword</span></span>
            </button>
            <button type="button" class="start-continue" data-start="continue">Continue without code ${svg(ICONS.arrow)}</button>
          </section>
        </div>
      </div>`;
    document.body.appendChild(el);
    renderRecents();

    const search = el.querySelector('.start-search input');
    search.addEventListener('input', () => renderRecents(search.value));
    el.querySelector('.start-recent-list').addEventListener('click', async (e) => {
      const item = e.target.closest('[data-folder]');
      if (!item) return;
      close();
      await ide.openRecentProject(item.dataset.folder);
    });
    el.querySelectorAll('[data-start]').forEach(btn => btn.addEventListener('click', () => {
      const action = btn.dataset.start;
      close();
      if (action === 'new') openNewProjectModal();
      else if (action === 'open') ide.promptOpenFolder();
      else if (action === 'learn') openLearn();
    }));
    document.addEventListener('keydown', onKey, true);
    setTimeout(() => (el?.querySelector('.start-recent') || el?.querySelector('.start-action'))?.focus(), 30);
  }

  return { show, close, isOpen: () => Boolean(el) };
}
