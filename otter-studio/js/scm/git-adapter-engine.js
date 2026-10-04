// git-adapter-engine.js - Professional Source Control & Git Adapter Engine for Otter Studio
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs';
import path from 'node:path';

const execFileAsync = promisify(execFile);

/**
 * Base abstract class for Source Control Providers (Extension API)
 */
export class SourceControlProvider {
  constructor(id, name, capabilities = {}) {
    this.id = id;
    this.name = name;
    this.capabilities = {
      staging: true,
      branches: true,
      remotes: true,
      stashing: true,
      tagging: true,
      blame: true,
      merge: true,
      conflictResolution: true,
      ...capabilities
    };
  }

  async isRepository(cwd) { throw new Error('Not implemented'); }
  async getStatus(cwd) { throw new Error('Not implemented'); }
  async getDiff(cwd, options) { throw new Error('Not implemented'); }
  async stage(cwd, files) { throw new Error('Not implemented'); }
  async unstage(cwd, files) { throw new Error('Not implemented'); }
  async commit(cwd, options) { throw new Error('Not implemented'); }
  async getBranches(cwd) { throw new Error('Not implemented'); }
}

/**
 * Conflict parser and resolution engine
 */
export class ConflictEditorManager {
  static parse(content) {
    const lines = content.split(/\r?\n/);
    const sections = [];
    let inConflict = false;
    let currentLines = [];
    let baseLines = [];
    let incomingLines = [];
    let currentMarker = '';
    let incomingMarker = '';
    let readingBase = false;
    let readingIncoming = false;
    let normalLines = [];

    const flushNormal = () => {
      if (normalLines.length > 0) {
        sections.push({ type: 'normal', text: normalLines.join('\n') });
        normalLines = [];
      }
    };

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      if (line.startsWith('<<<<<<<')) {
        flushNormal();
        inConflict = true;
        currentMarker = line.slice(7).trim();
        currentLines = [];
        baseLines = [];
        incomingLines = [];
        readingBase = false;
        readingIncoming = false;
      } else if (inConflict && line.startsWith('|||||||')) {
        readingBase = true;
      } else if (inConflict && line.startsWith('=======')) {
        readingBase = false;
        readingIncoming = true;
      } else if (inConflict && line.startsWith('>>>>>>>')) {
        incomingMarker = line.slice(7).trim();
        sections.push({
          type: 'conflict',
          current: currentLines.join('\n'),
          incoming: incomingLines.join('\n'),
          base: baseLines.length > 0 ? baseLines.join('\n') : null,
          currentMarker,
          incomingMarker
        });
        inConflict = false;
        readingBase = false;
        readingIncoming = false;
      } else if (inConflict) {
        if (readingIncoming) {
          incomingLines.push(line);
        } else if (readingBase) {
          baseLines.push(line);
        } else {
          currentLines.push(line);
        }
      } else {
        normalLines.push(line);
      }
    }

    flushNormal();
    return {
      hasConflicts: sections.some(s => s.type === 'conflict'),
      conflictCount: sections.filter(s => s.type === 'conflict').length,
      sections
    };
  }

  static resolve(content, choice, customContent = null) {
    const parsed = this.parse(content);
    if (!parsed.hasConflicts && !customContent) return content;

    if (customContent !== null && choice === 'custom') {
      return customContent;
    }

    const resolvedParts = [];
    for (const sec of parsed.sections) {
      if (sec.type === 'normal') {
        resolvedParts.push(sec.text);
      } else if (sec.type === 'conflict') {
        if (choice === 'current' || choice === 'ours') {
          if (sec.current) resolvedParts.push(sec.current);
        } else if (choice === 'incoming' || choice === 'theirs') {
          if (sec.incoming) resolvedParts.push(sec.incoming);
        } else if (choice === 'both') {
          const both = [sec.current, sec.incoming].filter(Boolean).join('\n');
          if (both) resolvedParts.push(both);
        }
      }
    }
    return resolvedParts.join('\n');
  }
}

/**
 * Remote & Authentication Manager
 */
export class RemoteAuthManager {
  constructor() {
    this.authTokens = new Map(); // host -> token
  }

  setToken(host, token) {
    this.authTokens.set(host.toLowerCase(), token);
  }

  getToken(host) {
    return this.authTokens.get(host.toLowerCase()) || null;
  }

  clearToken(host) {
    this.authTokens.delete(host.toLowerCase());
  }

  sanitizeUrl(url) {
    if (!url) return '';
    try {
      const u = new URL(url);
      if (u.password || u.username) {
        return `${u.protocol}//***:***@${u.host}${u.pathname}${u.search}`;
      }
      return url;
    } catch {
      return url.replace(/\/\/([^@]+)@/, '//***@');
    }
  }

  getEnvWithAuth(host = null) {
    const env = { ...process.env, GIT_TERMINAL_PROMPT: '0' };
    if (host && this.authTokens.has(host.toLowerCase())) {
      env.OTTER_SCM_TOKEN = this.authTokens.get(host.toLowerCase());
    }
    return env;
  }
}

/**
 * Standard Production Git Provider
 */
export class GitProvider extends SourceControlProvider {
  constructor(options = {}) {
    super('git', 'Git Source Control', {
      staging: true,
      branches: true,
      remotes: true,
      stashing: true,
      tagging: true,
      blame: true,
      merge: true,
      conflictResolution: true
    });
    this.authManager = options.authManager || new RemoteAuthManager();
  }

  async _exec(args, cwd, customEnv = {}) {
    const env = { ...process.env, GIT_TERMINAL_PROMPT: '0', ...customEnv };
    try {
      const { stdout, stderr } = await execFileAsync('git', args, { cwd, env });
      return { ok: true, stdout: stdout || '', stderr: stderr || '' };
    } catch (err) {
      return {
        ok: false,
        code: err.code,
        error: err.stderr || err.stdout || err.message,
        stdout: err.stdout || '',
        stderr: err.stderr || ''
      };
    }
  }

  async isRepository(cwd) {
    const res = await this._exec(['rev-parse', '--is-inside-work-tree'], cwd);
    return res.ok && res.stdout.trim() === 'true';
  }

  async getStatus(cwd) {
    const isRepo = await this.isRepository(cwd);
    if (!isRepo) {
      return { isRepo: false };
    }

    const branchRes = await this._exec(['rev-parse', '--abbrev-ref', 'HEAD'], cwd);
    const branch = branchRes.ok ? branchRes.stdout.trim() : 'HEAD';

    const trackingRes = await this._exec(['rev-list', '--left-right', '--count', `${branch}...@{upstream}`], cwd);
    let ahead = 0;
    let behind = 0;
    if (trackingRes.ok) {
      const parts = trackingRes.stdout.trim().split(/\s+/);
      if (parts.length >= 2) {
        ahead = parseInt(parts[0], 10) || 0;
        behind = parseInt(parts[1], 10) || 0;
      }
    }

    const statusRes = await this._exec(['status', '--porcelain=v1', '-uall'], cwd);
    const lines = (statusRes.stdout || '').split(/\r?\n/).filter(Boolean);

    const staged = [];
    const unstaged = [];
    const untracked = [];
    const conflicted = [];

    const conflictCodes = new Set(['DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU']);

    for (const line of lines) {
      const x = line[0];
      const y = line[1];
      const file = line.slice(3).trim();
      const code = x + y;

      if (x === '?' && y === '?') {
        untracked.push(file);
      } else if (conflictCodes.has(code)) {
        conflicted.push({ file, code });
      } else {
        if (x !== ' ' && x !== '?') {
          staged.push({ file, status: x });
        }
        if (y !== ' ' && y !== '?') {
          unstaged.push({ file, status: y });
        }
      }
    }

    return {
      isRepo: true,
      branch,
      ahead,
      behind,
      clean: lines.length === 0,
      staged,
      unstaged,
      untracked,
      conflicted
    };
  }

  async getDiff(cwd, { path: filePath, staged = false, commit = null } = {}) {
    const args = ['diff'];
    if (staged) args.push('--cached');
    if (commit) args.push(commit);
    if (filePath) args.push('--', filePath);

    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return res.stdout;
  }

  async stage(cwd, files) {
    const targetFiles = Array.isArray(files) ? files : [files];
    const args = ['add', '--', ...targetFiles];
    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return true;
  }

  async unstage(cwd, files) {
    const targetFiles = Array.isArray(files) ? files : [files];
    const args = ['reset', 'HEAD', '--', ...targetFiles];
    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return true;
  }

  async commit(cwd, { message, amend = false } = {}) {
    if (!message && !amend) throw new Error('Commit message is required');
    const args = ['commit'];
    if (amend) args.push('--amend');
    if (message) args.push('-m', message);

    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);

    const headRes = await this._exec(['rev-parse', 'HEAD'], cwd);
    const commitHash = headRes.ok ? headRes.stdout.trim() : '';
    return { commitHash, stdout: res.stdout.trim() };
  }

  async getBranches(cwd) {
    const res = await this._exec(['branch', '-a'], cwd);
    if (!res.ok) return { current: null, branches: [] };

    const branches = [];
    let current = null;
    for (const rawLine of res.stdout.split(/\r?\n/).filter(Boolean)) {
      const isCurrent = rawLine.startsWith('*');
      const name = rawLine.replace(/^\*?\s*/, '').trim();
      const isRemote = name.startsWith('remotes/');
      if (isCurrent) current = name;
      branches.push({ name, isCurrent, isRemote });
    }
    return { current, branches };
  }

  async createBranch(cwd, name, checkout = false) {
    if (!name) throw new Error('Branch name required');
    const args = checkout ? ['checkout', '-b', name] : ['branch', name];
    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, branch: name };
  }

  async checkoutBranch(cwd, name) {
    if (!name) throw new Error('Branch name required');
    const res = await this._exec(['checkout', name], cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, branch: name };
  }

  async deleteBranch(cwd, name, force = false) {
    if (!name) throw new Error('Branch name required');
    const args = ['branch', force ? '-D' : '-d', name];
    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true };
  }

  async fetch(cwd, { remote = 'origin', prune = false } = {}) {
    const args = ['fetch'];
    if (prune) args.push('--prune');
    if (remote) args.push(remote);

    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, stdout: res.stdout.trim() };
  }

  async pull(cwd, { remote = 'origin', branch = '', rebase = false } = {}) {
    const args = ['pull'];
    if (rebase) args.push('--rebase');
    if (remote) args.push(remote);
    if (branch) args.push(branch);

    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, stdout: res.stdout.trim() };
  }

  async push(cwd, { remote = 'origin', branch = '', force = false, setUpstream = false } = {}) {
    const args = ['push'];
    if (force) args.push('--force');
    if (setUpstream) args.push('-u');
    if (remote) args.push(remote);
    if (branch) args.push(branch);

    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, stdout: res.stdout.trim() };
  }

  async merge(cwd, { branch, abort = false, message = '' } = {}) {
    if (abort) {
      const res = await this._exec(['merge', '--abort'], cwd);
      if (!res.ok) throw new Error(res.error);
      return { ok: true, aborted: true };
    }
    if (!branch) throw new Error('Branch to merge is required');
    const args = ['merge', branch];
    if (message) args.push('-m', message);

    const res = await this._exec(args, cwd);
    if (!res.ok) {
      // Check if merge resulted in conflicts
      const status = await this.getStatus(cwd);
      if (status.conflicted && status.conflicted.length > 0) {
        return { ok: false, conflict: true, conflictedFiles: status.conflicted, error: res.error };
      }
      throw new Error(res.error);
    }
    return { ok: true, stdout: res.stdout.trim() };
  }

  async getBlame(cwd, { file: filePath, startLine, endLine } = {}) {
    if (!filePath) throw new Error('File path is required for blame');
    const args = ['blame', '--porcelain'];
    if (startLine && endLine) {
      args.push(`-L${startLine},${endLine}`);
    }
    args.push('--', filePath);

    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);

    const lines = res.stdout.split(/\r?\n/);
    const blameEntries = [];
    let currentCommit = {};

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (/^[0-9a-f]{40}\s+\d+\s+\d+/.test(line)) {
        const parts = line.split(/\s+/);
        currentCommit = {
          hash: parts[0],
          origLine: parseInt(parts[1], 10),
          finalLine: parseInt(parts[2], 10)
        };
      } else if (line.startsWith('author ')) {
        currentCommit.author = line.slice(7).trim();
      } else if (line.startsWith('author-mail ')) {
        currentCommit.authorMail = line.slice(12).replace(/[<>]/g, '').trim();
      } else if (line.startsWith('author-time ')) {
        currentCommit.authorTime = new Date(parseInt(line.slice(12).trim(), 10) * 1000).toISOString();
      } else if (line.startsWith('summary ')) {
        currentCommit.summary = line.slice(8).trim();
      } else if (line.startsWith('\t')) {
        blameEntries.push({
          ...currentCommit,
          line: currentCommit.finalLine,
          content: line.slice(1)
        });
      }
    }

    return blameEntries;
  }

  async getStashes(cwd) {
    const res = await this._exec(['stash', 'list', '--pretty=format:%gd|%h|%ad|%s'], cwd);
    if (!res.ok) return [];

    return res.stdout.split(/\r?\n/).filter(Boolean).map(line => {
      const [ref, hash, date, ...rest] = line.split('|');
      const idxMatch = (ref || '').match(/\{(\d+)\}/);
      const index = idxMatch ? parseInt(idxMatch[1], 10) : 0;
      return { index, ref, hash, date, message: rest.join('|') };
    });
  }

  async stashPush(cwd, { message = '', includeUntracked = true } = {}) {
    const args = ['stash', 'push'];
    if (includeUntracked) args.push('-u');
    if (message) args.push('-m', message);

    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, stdout: res.stdout.trim() };
  }

  async stashPop(cwd, { index = 0 } = {}) {
    const args = ['stash', 'pop', `stash@{${index}}`];
    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, stdout: res.stdout.trim() };
  }

  async stashApply(cwd, { index = 0 } = {}) {
    const args = ['stash', 'apply', `stash@{${index}}`];
    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, stdout: res.stdout.trim() };
  }

  async stashDrop(cwd, { index = 0 } = {}) {
    const args = ['stash', 'drop', `stash@{${index}}`];
    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, stdout: res.stdout.trim() };
  }

  async getTags(cwd) {
    const res = await this._exec(['tag', '-l', '--format=%(refname:short)|%(objectname:short)|%(creator)|%(contents:subject)'], cwd);
    if (!res.ok) return [];

    return res.stdout.split(/\r?\n/).filter(Boolean).map(line => {
      const [name, commitHash, tagger, ...rest] = line.split('|');
      return { name, commitHash, tagger, subject: rest.join('|') };
    });
  }

  async createTag(cwd, { name, message = '', commit = null } = {}) {
    if (!name) throw new Error('Tag name is required');
    const args = ['tag'];
    if (message) args.push('-a', '-m', message);
    args.push(name);
    if (commit) args.push(commit);

    const res = await this._exec(args, cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, tag: name };
  }

  async deleteTag(cwd, { name } = {}) {
    if (!name) throw new Error('Tag name is required');
    const res = await this._exec(['tag', '-d', name], cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true };
  }

  async getRemotes(cwd) {
    const res = await this._exec(['remote', '-v'], cwd);
    if (!res.ok) return [];

    const map = new Map();
    for (const line of res.stdout.split(/\r?\n/).filter(Boolean)) {
      const parts = line.split(/\s+/);
      if (parts.length >= 3) {
        const name = parts[0];
        const rawUrl = parts[1];
        const type = parts[2].replace(/[()]/g, '');
        if (!map.has(name)) {
          map.set(name, {
            name,
            url: this.authManager.sanitizeUrl(rawUrl),
            fetchUrl: null,
            pushUrl: null
          });
        }
        const entry = map.get(name);
        if (type === 'fetch') entry.fetchUrl = rawUrl;
        if (type === 'push') entry.pushUrl = rawUrl;
      }
    }
    return Array.from(map.values());
  }

  async addRemote(cwd, { name, url } = {}) {
    if (!name || !url) throw new Error('Remote name and url required');
    const res = await this._exec(['remote', 'add', name, url], cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, name, url: this.authManager.sanitizeUrl(url) };
  }

  async removeRemote(cwd, { name } = {}) {
    if (!name) throw new Error('Remote name required');
    const res = await this._exec(['remote', 'remove', name], cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true };
  }

  async setRemoteUrl(cwd, { name, url } = {}) {
    if (!name || !url) throw new Error('Remote name and url required');
    const res = await this._exec(['remote', 'set-url', name, url], cwd);
    if (!res.ok) throw new Error(res.error);
    return { ok: true, name, url: this.authManager.sanitizeUrl(url) };
  }

  async resolveConflict(cwd, { file: filePath, strategy = 'ours', customContent = null }) {
    if (!filePath) throw new Error('File path required');
    const fullPath = path.isAbsolute(filePath) ? filePath : path.join(cwd, filePath);
    if (!fs.existsSync(fullPath)) throw new Error(`File not found: ${filePath}`);

    const content = fs.readFileSync(fullPath, 'utf8');
    const resolved = ConflictEditorManager.resolve(content, strategy, customContent);
    fs.writeFileSync(fullPath, resolved, 'utf8');

    // Stage resolved file
    await this.stage(cwd, [filePath]);
    return { ok: true, file: filePath, resolved: true };
  }
}

/**
 * Registry for Source Control Extension API
 */
export class SourceControlRegistry {
  constructor() {
    this.providers = new Map();
    this.defaultProvider = new GitProvider();
    this.registerProvider(this.defaultProvider);
  }

  registerProvider(provider) {
    if (!(provider instanceof SourceControlProvider)) {
      throw new Error('Provider must inherit from SourceControlProvider');
    }
    this.providers.set(provider.id, provider);
  }

  getProvider(id) {
    return this.providers.get(id) || null;
  }

  listProviders() {
    return Array.from(this.providers.values()).map(p => ({
      id: p.id,
      name: p.name,
      capabilities: p.capabilities
    }));
  }

  async getActiveProvider(cwd) {
    for (const provider of this.providers.values()) {
      if (await provider.isRepository(cwd)) {
        return provider;
      }
    }
    return this.defaultProvider;
  }
}

export const sourceControlRegistry = new SourceControlRegistry();
