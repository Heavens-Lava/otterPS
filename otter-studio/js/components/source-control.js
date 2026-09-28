// source-control.js - The Source Control pane (sidebar "Git" tab).
//
// Everything shown here comes from the real `git` command line through
// /api/git/* (server/git.mjs). The pane shows:
//
//   branch + sync      current branch, commits ahead/behind, Fetch/Pull/Push,
//                      branch picker (switch, create, delete, merge)
//   commit box         message, Commit / Amend (Ctrl+Enter commits)
//   change lists       Merge conflicts, Staged, Changes; per file: open,
//                      diff, stage/unstage, discard; bulk stage/unstage
//   history            commits (all or current file); click for details
//   stashes, tags, remotes
//
// It also decorates Explorer entries with their status letter (M, A, U, D,
// R, !) and offers Blame and File History for the file in the editor.
//
// Diffs open in a side-by-side viewer (js/scm/line-diff.js, Myers diff).
// Conflicted files open in a conflict editor (js/scm/conflicts.js) that
// resolves each block with ours/theirs/both and saves through the normal,
// revision-checked file save before marking the file resolved.

import { diffLines, sideBySide, diffStats } from '../scm/line-diff.js';
import { parseConflicts, resolveConflict } from '../scm/conflicts.js';
import { askText } from '../shell/ask.js';

const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));

function statusLetter(file) {
  if (file.conflict) return '!';
  if (file.untracked) return 'U';
  const code = file.index !== '.' ? file.index : file.worktree;
  return { M: 'M', A: 'A', D: 'D', R: 'R', C: 'C', T: 'T' }[code] || 'M';
}

function relativeTime(iso) {
  if (!iso) return '';
  const seconds = Math.round((Date.now() - new Date(iso).getTime()) / 1000);
  const units = [['year', 31536000], ['month', 2592000], ['week', 604800], ['day', 86400], ['hour', 3600], ['minute', 60]];
  for (const [unit, size] of units) {
    if (seconds >= size) {
      const n = Math.floor(seconds / size);
      return `${n} ${unit}${n === 1 ? '' : 's'} ago`;
    }
  }
  return 'just now';
}

export class SourceControlPanel {
  constructor(ide, container) {
    this.ide = ide;
    this.container = container;
    this.status = null;
    this.bottomTab = 'history';
    this.historyForFile = null;
    this.busy = false;
    this.refreshTimer = null;
  }

  // Folder whose repository we show: the open project (or the workspace).
  get folder() {
    const f = this.ide.currentProjectFolder;
    return f && !/\.(json|otter-workspace)$/i.test(f) ? f : '.';
  }

  async api(method, action, data = {}) {
    let res;
    if (method === 'GET') {
      const params = new URLSearchParams({ folder: this.folder, ...data });
      res = await fetch(`/api/git/${action}?${params}`);
    } else {
      res = await fetch(`/api/git/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ folder: this.folder, ...data })
      });
    }
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `Source control request failed (${res.status}).`);
    return body;
  }

  // Workspace-relative path for a repository-relative one.
  toWorkspacePath(repoPath) {
    const root = this.status?.root;
    return !root || root === '.' ? repoPath : `${root}/${repoPath}`;
  }

  toRepoPath(workspacePath) {
    const root = this.status?.root;
    if (!root || root === '.') return workspacePath;
    return workspacePath.startsWith(`${root}/`) ? workspacePath.slice(root.length + 1) : null;
  }

  init() {
    this.container.addEventListener('click', e => this.onClick(e));
    this.container.addEventListener('keydown', e => {
      if (e.target.id === 'scmMessage' && e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        this.commit(false);
      }
    });
    // Keep the view current: after saves, when the window regains focus,
    // and on a slow timer while the pane is visible.
    window.addEventListener('focus', () => this.refresh());
    window.addEventListener('otter:file-saved', () => this.refresh());
    this.refreshTimer = setInterval(() => {
      if (this.container.offsetParent !== null && !document.hidden) this.refresh();
    }, 10000);
    // Re-apply Explorer decorations whenever the tree is redrawn.
    const originalRender = this.ide.renderProjectTree.bind(this.ide);
    this.ide.renderProjectTree = (...args) => {
      const result = originalRender(...args);
      this.decorateExplorer();
      return result;
    };
    this.render();
    this.refresh();
  }

  async refresh() {
    if (this.refreshing) return;
    this.refreshing = true;
    try {
      this.status = await this.api('GET', 'status');
      this.error = null;
    } catch (err) {
      this.status = null;
      this.error = err.message;
    } finally {
      this.refreshing = false;
    }
    this.render();
    this.decorateExplorer();
    if (this.status?.isRepo) this.loadBottomTab();
  }

  decorateExplorer() {
    const tree = this.ide.projectTreeEl;
    if (!tree) return;
    const byPath = new Map();
    for (const file of this.status?.isRepo ? this.status.files : []) {
      byPath.set(this.toWorkspacePath(file.path), file);
    }
    tree.querySelectorAll('.project-file-item[data-path]').forEach(el => {
      el.querySelector('.scm-decoration')?.remove();
      el.classList.remove('scm-modified', 'scm-added', 'scm-untracked', 'scm-deleted', 'scm-conflict');
      const file = byPath.get(el.dataset.path);
      if (!file) return;
      const letter = statusLetter(file);
      const cls = file.conflict ? 'scm-conflict' : file.untracked ? 'scm-untracked' : letter === 'A' ? 'scm-added' : letter === 'D' ? 'scm-deleted' : 'scm-modified';
      el.classList.add(cls);
      el.insertAdjacentHTML('beforeend', `<span class="scm-decoration" title="${esc(file.label)}" aria-label="Git: ${esc(file.label)}">${letter}</span>`);
    });
  }

  // -------------------------------------------------------------------------
  // Rendering
  // -------------------------------------------------------------------------

  render() {
    const s = this.status;
    if (this.error) {
      this.container.innerHTML = `<div class="scm-empty">${esc(this.error)}</div>`;
      return;
    }
    if (!s) {
      this.container.innerHTML = '<div class="scm-empty">Loading source control…</div>';
      return;
    }
    if (!s.isRepo) {
      this.container.innerHTML = `
        <div class="scm-empty">
          <p>This folder is not in a Git repository.</p>
          <button class="scm-btn scm-btn-primary" data-scm="init">Initialize Repository</button>
        </div>`;
      return;
    }

    const conflicts = s.files.filter(f => f.conflict);
    const staged = s.files.filter(f => !f.conflict && f.staged);
    const changes = s.files.filter(f => !f.conflict && (f.unstaged || f.untracked));
    const sync = s.upstream
      ? `<span title="Commits to push">↑${s.ahead}</span> <span title="Commits to pull">↓${s.behind}</span>`
      : '<span title="This branch is not published yet">not published</span>';

    // Keep what the user typed in the commit box across re-renders.
    const message = this.container.querySelector('#scmMessage')?.value ?? '';

    this.container.innerHTML = `
      <div class="scm-header">
        <button class="scm-branch" data-scm="branches" title="Switch, create, merge or delete branches">
          <span aria-hidden="true">⎇</span> ${esc(s.branch || `detached at ${(s.oid || '').slice(0, 7)}`)}
        </button>
        <span class="scm-sync">${sync}</span>
        <span class="scm-actions">
          <button class="scm-icon-btn" data-scm="fetch" title="Fetch from all remotes" aria-label="Fetch">⟳</button>
          <button class="scm-icon-btn" data-scm="pull" title="Pull" aria-label="Pull">↓</button>
          <button class="scm-icon-btn" data-scm="push" title="Push" aria-label="Push">↑</button>
          <button class="scm-icon-btn" data-scm="refresh" title="Refresh" aria-label="Refresh">↻</button>
        </span>
      </div>
      ${s.merging ? `
        <div class="scm-merge-banner" role="status">
          Merge in progress. Resolve the conflicts, then commit.
          <button class="scm-btn" data-scm="merge-abort">Abort Merge</button>
        </div>` : ''}
      <div class="scm-commit">
        <label for="scmMessage" class="scm-visually-hidden">Commit message</label>
        <textarea id="scmMessage" class="scm-message" rows="3" placeholder="Commit message (Ctrl+Enter to commit)">${esc(message)}</textarea>
        <div class="scm-commit-actions">
          <button class="scm-btn scm-btn-primary" data-scm="commit" ${conflicts.length ? 'disabled title="Resolve the conflicts first"' : ''}>✓ Commit${staged.length ? ` (${staged.length})` : ''}</button>
          <button class="scm-btn" data-scm="amend" title="Replace the last commit with the staged changes (and this message, if any)">Amend</button>
          <button class="scm-btn" data-scm="stash-push" title="Put all changes aside in a stash">Stash</button>
        </div>
      </div>
      <div class="scm-lists">
        ${conflicts.length ? this.renderGroup('Merge Conflicts', conflicts, 'conflict') : ''}
        ${this.renderGroup('Staged Changes', staged, 'staged')}
        ${this.renderGroup('Changes', changes, 'changes')}
      </div>
      <div class="scm-tools">
        <button class="scm-btn" data-scm="blame" title="Who last changed each line of the file in the editor">Blame current file</button>
        <button class="scm-btn" data-scm="file-history" title="Commits that changed the file in the editor">File history</button>
      </div>
      <div class="scm-tabs" role="tablist">
        ${['history', 'stashes', 'tags', 'remotes'].map(tab => `
          <button role="tab" aria-selected="${this.bottomTab === tab}" class="scm-tab${this.bottomTab === tab ? ' is-active' : ''}" data-scm-tab="${tab}">
            ${tab === 'history' ? 'History' : tab === 'stashes' ? `Stashes${s.stashCount ? ` (${s.stashCount})` : ''}` : tab === 'tags' ? 'Tags' : 'Remotes'}
          </button>`).join('')}
      </div>
      <div class="scm-tab-body" id="scmTabBody" role="tabpanel"><div class="scm-empty">Loading…</div></div>`;
  }

  renderGroup(title, files, kind) {
    const bulk = kind === 'staged'
      ? '<button class="scm-icon-btn" data-scm="unstage-all" title="Unstage all" aria-label="Unstage all">−</button>'
      : kind === 'changes'
        ? `<button class="scm-icon-btn" data-scm="discard-all" title="Discard all changes" aria-label="Discard all changes">⎌</button>
           <button class="scm-icon-btn" data-scm="stage-all" title="Stage all" aria-label="Stage all">+</button>`
        : '';
    const rows = files.map(f => {
      const name = f.path.split('/').pop();
      const dir = f.path.includes('/') ? f.path.slice(0, f.path.lastIndexOf('/')) : '';
      const letter = statusLetter(f);
      const actions = kind === 'staged'
        ? `<button class="scm-icon-btn" data-scm="unstage" title="Unstage" aria-label="Unstage ${esc(name)}">−</button>`
        : kind === 'changes'
          ? `<button class="scm-icon-btn" data-scm="discard" title="Discard changes" aria-label="Discard changes to ${esc(name)}">⎌</button>
             <button class="scm-icon-btn" data-scm="stage" title="Stage" aria-label="Stage ${esc(name)}">+</button>`
          : `<button class="scm-icon-btn" data-scm="resolve-editor" title="Resolve conflicts" aria-label="Resolve conflicts in ${esc(name)}">⚑</button>`;
      return `
        <li class="scm-file" data-path="${esc(f.path)}" data-kind="${kind}" tabindex="0" title="${esc(f.path)} — ${esc(f.label)}">
          <span class="scm-file-name${f.worktree === 'D' || f.index === 'D' ? ' is-deleted' : ''}">${esc(name)}</span>
          <span class="scm-file-dir">${esc(f.from ? `${f.from} → ` : '')}${esc(dir)}</span>
          <span class="scm-file-actions">
            <button class="scm-icon-btn" data-scm="open" title="Open file" aria-label="Open ${esc(name)}">↗</button>
            ${actions}
          </span>
          <span class="scm-letter scm-letter-${letter === '!' ? 'conflict' : letter}" aria-label="${esc(f.label)}">${letter}</span>
        </li>`;
    }).join('');
    return `
      <section class="scm-group" aria-label="${esc(title)}">
        <div class="scm-group-title"><span>${esc(title)} <span class="scm-count">${files.length}</span></span><span>${files.length ? bulk : ''}</span></div>
        <ul class="scm-file-list">${rows || '<li class="scm-none">None</li>'}</ul>
      </section>`;
  }

  async loadBottomTab() {
    const body = this.container.querySelector('#scmTabBody');
    if (!body) return;
    try {
      if (this.bottomTab === 'history') {
        const params = this.historyForFile ? { path: this.historyForFile, limit: 200 } : { limit: 100 };
        const { commits } = await this.api('GET', 'log', params);
        body.innerHTML = `
          ${this.historyForFile ? `<div class="scm-filter">History of <strong>${esc(this.historyForFile)}</strong> <button class="scm-btn" data-scm="history-all">Show all</button></div>` : ''}
          <ul class="scm-commit-list">${commits.map(c => `
            <li class="scm-commit-row" data-commit="${esc(c.hash)}" tabindex="0" title="${esc(c.hash)}">
              <span class="scm-commit-subject">${esc(c.subject)}</span>
              ${c.refs.length ? `<span class="scm-refs">${c.refs.map(r => `<span class="scm-ref">${esc(r)}</span>`).join('')}</span>` : ''}
              <span class="scm-commit-meta">${esc(c.short)} · ${esc(c.author)} · ${esc(relativeTime(c.date))}</span>
            </li>`).join('') || '<li class="scm-none">No commits yet.</li>'}</ul>`;
      } else if (this.bottomTab === 'stashes') {
        const { stashes } = await this.api('GET', 'stashes');
        body.innerHTML = `<ul class="scm-commit-list">${stashes.map(st => `
          <li class="scm-commit-row" data-stash="${esc(st.ref)}">
            <span class="scm-commit-subject">${esc(st.message)}</span>
            <span class="scm-commit-meta">${esc(st.ref)} · ${esc(relativeTime(st.date))}</span>
            <span class="scm-row-actions">
              <button class="scm-btn" data-scm="stash-pop">Pop</button>
              <button class="scm-btn" data-scm="stash-apply">Apply</button>
              <button class="scm-btn" data-scm="stash-drop">Drop</button>
            </span>
          </li>`).join('') || '<li class="scm-none">No stashes.</li>'}</ul>`;
      } else if (this.bottomTab === 'tags') {
        const { tags } = await this.api('GET', 'tags');
        body.innerHTML = `
          <div class="scm-inline-form"><button class="scm-btn" data-scm="tag-create">+ New tag on HEAD</button></div>
          <ul class="scm-commit-list">${tags.map(t => `
            <li class="scm-commit-row" data-tag="${esc(t.name)}">
              <span class="scm-commit-subject">${esc(t.name)}</span>
              <span class="scm-commit-meta">${esc(t.hash)} · ${esc(t.subject || '')} · ${esc(relativeTime(t.date))}</span>
              <span class="scm-row-actions"><button class="scm-btn" data-scm="tag-delete">Delete</button></span>
            </li>`).join('') || '<li class="scm-none">No tags.</li>'}</ul>`;
      } else {
        const { remotes } = await this.api('GET', 'remotes');
        body.innerHTML = `
          <div class="scm-inline-form"><button class="scm-btn" data-scm="remote-add">+ Add remote</button></div>
          <ul class="scm-commit-list">${remotes.map(r => `
            <li class="scm-commit-row" data-remote="${esc(r.name)}">
              <span class="scm-commit-subject">${esc(r.name)}</span>
              <span class="scm-commit-meta">${esc(r.fetchUrl || '')}</span>
              <span class="scm-row-actions"><button class="scm-btn" data-scm="remote-remove">Remove</button></span>
            </li>`).join('') || '<li class="scm-none">No remotes. Add one to push and pull.</li>'}</ul>
          <p class="scm-note">Sign-in uses your Git credential helper or SSH agent; Studio never asks for or stores passwords.</p>`;
      }
    } catch (err) {
      body.innerHTML = `<div class="scm-empty">${esc(err.message)}</div>`;
    }
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  async run(label, fn, { refresh = true } = {}) {
    if (this.busy) return;
    this.busy = true;
    this.container.classList.add('is-busy');
    try {
      const result = await fn();
      if (result?.output) this.log(label, result.output);
      return result;
    } catch (err) {
      this.log(`${label} failed`, err.message, false);
      alert(`${label} failed:\n\n${err.message}`);
      return null;
    } finally {
      this.busy = false;
      this.container.classList.remove('is-busy');
      if (refresh) await this.refresh();
    }
  }

  log(title, text, ok = true) {
    if (typeof this.ide.appendBuildLog === 'function') this.ide.appendBuildLog(`Git: ${title}`, text, ok);
  }

  async onClick(e) {
    const tabBtn = e.target.closest('[data-scm-tab]');
    if (tabBtn) {
      this.bottomTab = tabBtn.dataset.scmTab;
      this.render();
      this.loadBottomTab();
      return;
    }
    const actionEl = e.target.closest('[data-scm]');
    const fileEl = e.target.closest('.scm-file');
    const commitEl = e.target.closest('[data-commit]');
    if (!actionEl) {
      if (fileEl) this.openDiff(fileEl.dataset.path, fileEl.dataset.kind);
      else if (commitEl) this.showCommit(commitEl.dataset.commit);
      return;
    }
    e.stopPropagation();
    const action = actionEl.dataset.scm;
    const filePath = fileEl?.dataset.path;
    const s = this.status;

    // Git runs the repository's hooks on these (pre-commit, post-checkout,
    // post-merge...), which is running workspace code.
    const runsHooks = ['commit', 'amend', 'pull', 'push', 'branches', 'stash-pop', 'stash-apply'];
    if (runsHooks.includes(action) && typeof this.ide.ensureTrusted === 'function' && !(await this.ide.ensureTrusted('This Git action'))) return;

    switch (action) {
      case 'init': return this.run('Initialize repository', () => this.api('POST', 'init'));
      case 'refresh': return this.refresh();
      case 'fetch': return this.run('Fetch', () => this.api('POST', 'fetch'));
      case 'pull': return this.run('Pull', () => this.api('POST', 'pull'));
      case 'push': return this.run('Push', () => this.api('POST', 'push'));
      case 'open': return this.ide.loadFile(this.toWorkspacePath(filePath));
      case 'stage': return this.run('Stage', () => this.api('POST', 'stage', { paths: [filePath] }));
      case 'unstage': return this.run('Unstage', () => this.api('POST', 'unstage', { paths: [filePath] }));
      case 'stage-all': return this.run('Stage all', () => this.api('POST', 'stage', { paths: s.files.filter(f => f.unstaged || f.untracked).map(f => f.path) }));
      case 'unstage-all': return this.run('Unstage all', () => this.api('POST', 'unstage', { paths: s.files.filter(f => f.staged).map(f => f.path) }));
      case 'discard': return this.discard([s.files.find(f => f.path === filePath)]);
      case 'discard-all': return this.discard(s.files.filter(f => !f.conflict && (f.unstaged || f.untracked)));
      case 'commit': return this.commit(false);
      case 'amend': return this.commit(true);
      case 'merge-abort':
        if (confirm('Abort the merge and return to the state before it started?')) return this.run('Abort merge', () => this.api('POST', 'merge-abort'));
        return;
      case 'resolve-editor': return this.openConflictEditor(filePath);
      case 'branches': return this.openBranchPicker();
      case 'stash-push': {
        const message = await askText({ title: 'Stash Changes', message: 'An optional message to recognise this stash by.', okLabel: 'Stash' });
        if (message === null) return;
        return this.run('Stash', () => this.api('POST', 'stash', { op: 'push', message }));
      }
      case 'stash-pop':
      case 'stash-apply':
      case 'stash-drop': {
        const ref = e.target.closest('[data-stash]').dataset.stash;
        const op = action.slice('stash-'.length);
        if (op === 'drop' && !confirm(`Delete ${ref}? Its changes will be lost.`)) return;
        return this.run(`Stash ${op}`, () => this.api('POST', 'stash', { op, ref }));
      }
      case 'tag-create': {
        const name = await askText({ title: 'Create Tag', message: 'For example v1.0.0.', okLabel: 'Next',
          validate: (v) => (v.trim() && !/\s/.test(v.trim()) ? null : 'A tag name has no spaces.') });
        if (!name) return;
        const message = await askText({ title: `Tag ${name.trim()}`, message: 'A message makes an annotated tag; leave it empty for a lightweight one.', okLabel: 'Create tag' });
        if (message === null) return;
        return this.run('Create tag', () => this.api('POST', 'tag', { name: name.trim(), message }));
      }
      case 'tag-delete': {
        const name = e.target.closest('[data-tag]').dataset.tag;
        if (!confirm(`Delete tag ${name}?`)) return;
        return this.run('Delete tag', () => this.api('POST', 'tag', { name, delete: true }));
      }
      case 'remote-add': {
        const name = await askText({ title: 'Add Remote', message: 'A short name for the remote repository.', value: 'origin', okLabel: 'Next' });
        if (!name) return;
        const url = await askText({ title: `Remote ${name.trim()}`, message: 'https://, ssh:// or git@host:owner/repo.git', okLabel: 'Add remote' });
        if (!url) return;
        return this.run('Add remote', () => this.api('POST', 'remote', { name: name.trim(), url }));
      }
      case 'remote-remove': {
        const name = e.target.closest('[data-remote]').dataset.remote;
        if (!confirm(`Remove remote ${name}? Its remote-tracking branches are removed too.`)) return;
        return this.run('Remove remote', () => this.api('POST', 'remote', { name, remove: true }));
      }
      case 'blame': return this.showBlame();
      case 'file-history': {
        const repoPath = this.ide.currentFile ? this.toRepoPath(this.ide.currentFile) : null;
        if (!repoPath) { alert('Open a file from this repository first.'); return; }
        this.historyForFile = repoPath;
        this.bottomTab = 'history';
        this.render();
        return this.loadBottomTab();
      }
      case 'history-all':
        this.historyForFile = null;
        return this.loadBottomTab();
      default:
        return undefined;
    }
  }

  async discard(files) {
    files = files.filter(Boolean);
    if (!files.length) return;
    const untracked = files.filter(f => f.untracked);
    const names = files.map(f => f.path).slice(0, 10).join('\n');
    const more = files.length > 10 ? `\n…and ${files.length - 10} more` : '';
    const warning = untracked.length ? `\n\n${untracked.length} new file(s) will be DELETED.` : '';
    if (!confirm(`Discard changes? This cannot be undone.\n\n${names}${more}${warning}`)) return;
    await this.run('Discard', () => this.api('POST', 'discard', { paths: files.map(f => f.path), deleteUntracked: untracked.length > 0 }));
    // Open tabs showing those files must not keep (and later save) the old text.
    for (const f of files) await this.ide.reloadTabFromDisk?.(this.toWorkspacePath(f.path));
  }

  async commit(amend) {
    const box = this.container.querySelector('#scmMessage');
    const message = box?.value.trim() || '';
    const s = this.status;
    const staged = s.files.filter(f => f.staged && !f.conflict);
    if (!amend && !message) { alert('Write a commit message first.'); box?.focus(); return; }

    // Unsaved editor changes are not part of the commit; say so.
    const dirty = this.ide.openTabs.filter(t => t.isDirty).map(t => t.name);
    if (dirty.length && !confirm(`These files have unsaved changes that will not be in the commit: ${dirty.join(', ')}.\n\nCommit anyway?`)) return;

    let all = false;
    if (!amend && staged.length === 0) {
      const changed = s.files.filter(f => f.unstaged && !f.untracked).length;
      if (!changed) { alert('There are no changes to commit. Stage new files with + first.'); return; }
      if (!confirm('Nothing is staged. Commit all changed tracked files?')) return;
      all = true;
    }
    if (amend && !confirm('Amend replaces the last commit. Do not amend a commit you have already pushed.\n\nAmend the last commit?')) return;
    const result = await this.run(amend ? 'Amend' : 'Commit', () => this.api('POST', 'commit', { message, amend, all }));
    if (result && box) box.value = '';
  }

  // -------------------------------------------------------------------------
  // Dialogs
  // -------------------------------------------------------------------------

  openDialog(title, bodyHtml, { wide = true } = {}) {
    const backdrop = document.createElement('div');
    backdrop.className = 'modal-backdrop scm-dialog';
    backdrop.style.display = 'flex';
    backdrop.innerHTML = `
      <div class="modal-dialog" role="dialog" aria-modal="true" aria-label="${esc(title)}" style="max-width: ${wide ? '1100px' : '560px'}; width: 96vw; max-height: 90vh; display: flex; flex-direction: column;">
        <div class="modal-header">
          <h2 class="modal-title">${esc(title)}</h2>
          <button class="modal-close-btn" data-close title="Close (Esc)" aria-label="Close">✕</button>
        </div>
        <div class="modal-body scm-dialog-body" style="overflow: auto; flex: 1;">${bodyHtml}</div>
      </div>`;
    const close = () => { backdrop.remove(); document.removeEventListener('keydown', onKey, true); };
    const onKey = e => { if (e.key === 'Escape') { e.preventDefault(); close(); } };
    document.addEventListener('keydown', onKey, true);
    backdrop.addEventListener('click', e => { if (e.target === backdrop || e.target.closest('[data-close]')) close(); });
    document.body.appendChild(backdrop);
    backdrop.querySelector('.modal-close-btn')?.focus();
    return { el: backdrop, close };
  }

  renderDiffTable(original, modified, leftLabel, rightLabel) {
    const ops = diffLines(original, modified);
    const stats = diffStats(ops);
    const rows = sideBySide(ops);
    // Collapse long unchanged stretches, keeping 3 lines of context.
    const keep = new Set();
    rows.forEach((row, i) => {
      if (row.type !== 'equal') for (let j = Math.max(0, i - 3); j <= Math.min(rows.length - 1, i + 3); j++) keep.add(j);
    });
    let html = '';
    let skipped = 0;
    rows.forEach((row, i) => {
      if (!keep.has(i) && rows.length > 40) { skipped++; return; }
      if (skipped) { html += `<tr class="scm-diff-skip"><td colspan="4">⋯ ${skipped} unchanged line${skipped === 1 ? '' : 's'}</td></tr>`; skipped = 0; }
      const cell = (side, cls) => side
        ? `<td class="scm-ln">${side.line}</td><td class="scm-code ${cls}">${esc(side.text) || ' '}</td>`
        : '<td class="scm-ln"></td><td class="scm-code scm-blank"></td>';
      html += `<tr>${cell(row.left, row.type === 'equal' ? '' : 'scm-del')}${cell(row.right, row.type === 'equal' ? '' : 'scm-add')}</tr>`;
    });
    if (skipped) html += `<tr class="scm-diff-skip"><td colspan="4">⋯ ${skipped} unchanged line${skipped === 1 ? '' : 's'}</td></tr>`;
    return `
      <div class="scm-diff-summary"><span class="scm-add-text">+${stats.added}</span> <span class="scm-del-text">−${stats.removed}</span></div>
      <table class="scm-diff" aria-label="Side-by-side diff">
        <colgroup><col style="width: 48px"><col><col style="width: 48px"><col></colgroup>
        <thead><tr><th colspan="2">${esc(leftLabel)}</th><th colspan="2">${esc(rightLabel)}</th></tr></thead>
        <tbody>${html || '<tr><td colspan="4" class="scm-none">No differences.</td></tr>'}</tbody>
      </table>`;
  }

  async openDiff(repoPath, kind) {
    if (kind === 'conflict') return this.openConflictEditor(repoPath);
    try {
      const d = await this.api('GET', 'diff', { path: repoPath, staged: kind === 'staged' ? '1' : '0' });
      this.openDialog(`${repoPath} — ${d.originalLabel} ↔ ${d.modifiedLabel}`, this.renderDiffTable(d.original, d.modified, d.originalLabel, d.modifiedLabel));
    } catch (err) {
      alert(err.message);
    }
  }

  async showCommit(hash) {
    try {
      const c = await this.api('GET', 'show', { commit: hash });
      const files = c.files.map(f => `<li><span class="scm-letter scm-letter-${esc(f.status[0])}">${esc(f.status[0])}</span> ${esc(f.from ? `${f.from} → ${f.path}` : f.path)}</li>`).join('');
      this.openDialog(`${c.short} ${c.subject}`, `
        <p class="scm-commit-meta">${esc(c.hash)}<br>${esc(c.author)} &lt;${esc(c.email)}&gt; · ${esc(new Date(c.date).toLocaleString())}</p>
        ${c.body ? `<pre class="scm-commit-body">${esc(c.body)}</pre>` : ''}
        <h3 class="scm-h3">Files changed (${c.files.length})</h3>
        <ul class="scm-plain-list">${files}</ul>
        <h3 class="scm-h3">Patch</h3>
        <pre class="scm-patch">${esc(c.patch).replace(/^(\+(?!\+\+).*)$/gm, '<span class="scm-add-text">$1</span>').replace(/^(-(?!--).*)$/gm, '<span class="scm-del-text">$1</span>')}</pre>`);
    } catch (err) {
      alert(err.message);
    }
  }

  async showBlame() {
    const file = this.ide.currentFile;
    const repoPath = file ? this.toRepoPath(file) : null;
    if (!repoPath) { alert('Open a file from this repository first.'); return; }
    try {
      const { lines } = await this.api('GET', 'blame', { path: repoPath });
      let previous = null;
      const rows = lines.map(l => {
        const same = l.hash === previous;
        previous = l.hash;
        const who = l.uncommitted ? 'Not committed yet' : `${l.hash.slice(0, 7)} ${l.author} · ${relativeTime(l.date)}`;
        return `<tr${same ? '' : ' class="scm-blame-start"'}>
          <td class="scm-blame-who" title="${esc(l.summary || '')}">${same ? '' : esc(who)}</td>
          <td class="scm-ln">${l.line}</td><td class="scm-code">${esc(l.text) || ' '}</td></tr>`;
      }).join('');
      const dialog = this.openDialog(`Blame: ${repoPath}`, `<table class="scm-diff scm-blame"><colgroup><col style="width: 280px"><col style="width: 48px"><col></colgroup><tbody>${rows}</tbody></table>`);
      dialog.el.addEventListener('dblclick', e => {
        const row = e.target.closest('tr');
        const index = [...row.parentElement.children].indexOf(row);
        const hash = lines[index]?.hash;
        if (hash && !lines[index].uncommitted) this.showCommit(hash);
      });
    } catch (err) {
      alert(err.message);
    }
  }

  async openBranchPicker() {
    let branches;
    try {
      ({ branches } = await this.api('GET', 'branches'));
    } catch (err) {
      alert(err.message);
      return;
    }
    const row = b => `
      <li class="scm-branch-row${b.current ? ' is-current' : ''}" data-branch="${esc(b.name)}">
        <span class="scm-commit-subject">${b.current ? '● ' : ''}${esc(b.name)}</span>
        <span class="scm-commit-meta">${esc(b.hash)}${b.upstream ? ` · tracks ${esc(b.upstream)}` : ''} · ${esc(relativeTime(b.date))}</span>
        <span class="scm-row-actions">
          ${b.current ? '' : '<button class="scm-btn" data-branch-action="switch">Switch</button>'}
          ${b.current ? '' : '<button class="scm-btn" data-branch-action="merge">Merge into current</button>'}
          ${b.current || b.remote ? '' : '<button class="scm-btn" data-branch-action="delete">Delete</button>'}
        </span>
      </li>`;
    const dialog = this.openDialog('Branches', `
      <div class="scm-inline-form">
        <label for="scmNewBranch" class="scm-visually-hidden">New branch name</label>
        <input id="scmNewBranch" class="config-input" placeholder="new-branch-name" />
        <button class="scm-btn scm-btn-primary" data-branch-action="create">Create and switch</button>
      </div>
      <h3 class="scm-h3">Local</h3>
      <ul class="scm-commit-list">${branches.filter(b => !b.remote).map(row).join('') || '<li class="scm-none">No branches yet (make the first commit).</li>'}</ul>
      <h3 class="scm-h3">Remote</h3>
      <ul class="scm-commit-list">${branches.filter(b => b.remote).map(row).join('') || '<li class="scm-none">No remote branches. Fetch to update.</li>'}</ul>`, { wide: false });
    dialog.el.addEventListener('click', async e => {
      const btn = e.target.closest('[data-branch-action]');
      if (!btn) return;
      const action = btn.dataset.branchAction;
      const name = btn.closest('[data-branch]')?.dataset.branch;
      if (action === 'create') {
        const newName = dialog.el.querySelector('#scmNewBranch').value.trim();
        if (!newName) return;
        dialog.close();
        await this.run('Create branch', () => this.api('POST', 'checkout', { branch: newName, create: true }));
      } else if (action === 'switch') {
        if (this.ide.openTabs.some(t => t.isDirty) && !confirm('Some tabs have unsaved changes. Switching branches may change those files on disk. Continue?')) return;
        dialog.close();
        await this.run('Switch branch', () => this.api('POST', 'checkout', { branch: name }));
        await this.ide.reloadCleanTabsFromDisk?.();
      } else if (action === 'merge') {
        if (!confirm(`Merge ${name} into ${this.status.branch}?`)) return;
        dialog.close();
        const result = await this.run('Merge', () => this.api('POST', 'merge', { branch: name }));
        if (result?.conflicts?.length) alert(`The merge has conflicts in:\n\n${result.conflicts.join('\n')}\n\nOpen each one from Merge Conflicts to resolve it.`);
        await this.ide.reloadCleanTabsFromDisk?.();
      } else if (action === 'delete') {
        if (!confirm(`Delete branch ${name}?`)) return;
        dialog.close();
        const ok = await this.run('Delete branch', () => this.api('POST', 'delete-branch', { branch: name }));
        if (!ok && confirm(`${name} has commits that are not merged anywhere. Delete it anyway? Those commits will be lost.`)) {
          await this.run('Delete branch', () => this.api('POST', 'delete-branch', { branch: name, force: true }));
        }
      }
    });
    dialog.el.querySelector('#scmNewBranch')?.focus();
  }

  async openConflictEditor(repoPath) {
    const workspacePath = this.toWorkspacePath(repoPath);
    const res = await fetch(`/api/file?path=${encodeURIComponent(workspacePath)}`);
    const file = await res.json();
    if (!res.ok) { alert(file.error || 'Could not open the file.'); return; }
    let text = file.content;
    let revision = file.revision;

    const dialog = this.openDialog(`Resolve conflicts: ${repoPath}`, '<div class="scm-conflicts"></div>');
    const host = dialog.el.querySelector('.scm-conflicts');
    const draw = () => {
      const { blocks } = parseConflicts(text);
      host.innerHTML = `
        <p class="scm-note">${blocks.length ? `${blocks.length} conflict${blocks.length === 1 ? '' : 's'} left. Choose a side for each, or edit the file by hand.` : 'All conflicts are resolved.'}</p>
        ${blocks.map(b => `
          <div class="scm-conflict" data-index="${b.index}">
            <div class="scm-conflict-cols">
              <div><div class="scm-conflict-label">Ours (${esc(b.oursLabel)})</div><pre class="scm-add">${esc(b.ours.join('\n')) || ' '}</pre></div>
              <div><div class="scm-conflict-label">Theirs (${esc(b.theirsLabel)})</div><pre class="scm-del">${esc(b.theirs.join('\n')) || ' '}</pre></div>
            </div>
            <div class="scm-row-actions">
              <button class="scm-btn" data-choice="ours">Accept ours</button>
              <button class="scm-btn" data-choice="theirs">Accept theirs</button>
              <button class="scm-btn" data-choice="both">Accept both</button>
            </div>
          </div>`).join('')}
        <div class="scm-commit-actions">
          <button class="scm-btn" data-conflict-action="open">Edit in editor</button>
          <button class="scm-btn scm-btn-primary" data-conflict-action="save" ${blocks.length ? 'disabled' : ''}>Save and mark resolved</button>
        </div>`;
    };
    draw();
    host.addEventListener('click', async e => {
      const choice = e.target.closest('[data-choice]')?.dataset.choice;
      if (choice) {
        const index = Number(e.target.closest('[data-index]').dataset.index);
        text = resolveConflict(text, index, choice);
        draw();
        return;
      }
      const action = e.target.closest('[data-conflict-action]')?.dataset.conflictAction;
      if (action === 'open') {
        dialog.close();
        await this.ide.loadFile(workspacePath);
      } else if (action === 'save') {
        const save = await fetch('/api/file', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ path: workspacePath, content: text, expectedRevision: revision })
        });
        const saved = await save.json();
        if (!save.ok) { alert(saved.error || 'Could not save.'); return; }
        revision = saved.revision;
        dialog.close();
        await this.run('Mark resolved', () => this.api('POST', 'resolve', { paths: [repoPath] }));
        await this.ide.reloadTabFromDisk?.(workspacePath);
      }
    });
  }
}
