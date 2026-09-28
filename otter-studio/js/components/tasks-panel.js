// tasks-panel.js - The Tasks tab in the bottom drawer: every TODO, FIXME,
// BUG, HACK and NOTE comment in the project, most urgent first. Uses the
// workspace search API; clicking a task opens the file at that line.

import { TASK_SEARCH, TASK_TAGS, tasksFromSearch } from '../editor/editor-extras.js';

export class TasksPanel {
  constructor(ide, rootEl) {
    this.ide = ide;
    this.root = rootEl;
    this.tasks = [];
    this.filter = '';
    this.loading = false;
    this.error = '';
  }

  init() {
    if (!this.root) return;
    this.root.addEventListener('click', (e) => {
      const row = e.target.closest('[data-task-index]');
      if (row) {
        const task = this.tasks[Number(row.getAttribute('data-task-index'))];
        if (task) this.ide.navigateToLocation({ path: task.path, line: task.line, column: task.column });
        return;
      }
      if (e.target.closest('[data-tasks-refresh]')) this.refresh();
      const tagBtn = e.target.closest('[data-task-filter]');
      if (tagBtn) {
        this.filter = this.filter === tagBtn.getAttribute('data-task-filter') ? '' : tagBtn.getAttribute('data-task-filter');
        this.render();
      }
    });
    this.render();
  }

  async refresh() {
    const folder = this.ide.currentProjectFolder;
    if (!folder || /\.(json|otter-workspace)$/i.test(folder)) {
      this.tasks = [];
      this.error = 'Open a project to list its tasks.';
      this.render();
      return;
    }
    this.loading = true;
    this.error = '';
    this.render();
    try {
      const res = await fetch('/api/search', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ query: TASK_SEARCH, folder, regex: true, caseSensitive: true })
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
      this.tasks = tasksFromSearch(data.results);
    } catch (err) {
      this.error = `Could not scan the project: ${err.message}`;
      this.tasks = [];
    } finally {
      this.loading = false;
      this.render();
    }
  }

  render() {
    if (!this.root) return;
    const counts = Object.fromEntries(TASK_TAGS.map(t => [t, this.tasks.filter(x => x.tag === t).length]));
    const shown = this.tasks.map((task, index) => ({ task, index })).filter(({ task }) => !this.filter || task.tag === this.filter);
    const rows = shown.map(({ task, index }) => `
      <button class="task-row" data-task-index="${index}" title="${escapeHtml(task.path)}:${task.line}">
        <span class="task-tag task-tag-${task.tag.toLowerCase()}">${task.tag}</span>
        <span class="task-text">${escapeHtml(task.text)}</span>
        <span class="task-where">${escapeHtml(task.path.split('/').pop())}:${task.line}</span>
      </button>`).join('');
    this.root.innerHTML = `
      <div class="tasks-toolbar">
        ${TASK_TAGS.filter(t => counts[t]).map(t => `<button class="task-filter ${this.filter === t ? 'is-active' : ''}" data-task-filter="${t}">${t} <b>${counts[t]}</b></button>`).join('')}
        <span class="tasks-spacer"></span>
        <button class="task-filter" data-tasks-refresh title="Scan the project again">↻ Refresh</button>
      </div>
      <div class="tasks-list">
        ${this.loading ? '<div class="tasks-empty">Scanning…</div>'
          : this.error ? `<div class="tasks-empty">${escapeHtml(this.error)}</div>`
          : rows || '<div class="tasks-empty">No TODO, FIXME, BUG, HACK or NOTE comments in this project.</div>'}
      </div>`;
  }
}

function escapeHtml(str) {
  return String(str ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
