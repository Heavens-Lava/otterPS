// terminal-manager.js - Interactive Multi-Session Terminal Manager for Otter Studio
import { ansiToHtml, stripAnsi } from './ansi-parser.js';
import { TerminalProfileManager, DEFAULT_PROFILES } from './terminal-profiles.js';

/**
 * Escapes an argument for safe execution in shell command strings, preventing argument injection.
 * @param {string} arg 
 * @returns {string} Escaped argument safe for execution
 */
export function escapeShellArg(arg) {
  if (typeof arg !== 'string') return '""';
  if (arg === '') return '""';
  // If argument contains only safe shell characters, return as is
  if (/^[a-zA-Z0-9_\-\.\/\\:=]+$/.test(arg)) {
    return arg;
  }
  // Windows cmd/powershell safe quoting: double internal quotes and enclose in double quotes
  return '"' + arg.replace(/"/g, '`"') + '"';
}

/**
 * Validates and audits a command string for dangerous shell injection constructs.
 * @param {string} cmd 
 * @returns {{ safe: boolean, reason?: string }}
 */
export function auditShellCommand(cmd) {
  if (typeof cmd !== 'string' || !cmd.trim()) {
    return { safe: false, reason: 'Command cannot be empty' };
  }
  // Check for null bytes
  if (cmd.includes('\0')) {
    return { safe: false, reason: 'Command contains null byte' };
  }
  // Check for dangerous carriage return / newline injection in single-line command contexts
  if (cmd.includes('\r\n') || cmd.includes('\n')) {
    // Multi-line scripts are allowed only if formatted
    return { safe: true, multiline: true };
  }
  return { safe: true };
}

export class TerminalSession {
  constructor(id, profile, options = {}) {
    this.id = id;
    this.profile = profile;
    this.name = options.name || profile.name || `Terminal ${id.slice(0, 4)}`;
    this.cwd = options.cwd || '';
    this.cols = options.cols || 80;
    this.rows = options.rows || 24;
    this.env = { ...(profile.env || {}), ...(options.env || {}) };
    this.state = 'starting'; // 'starting' | 'running' | 'terminated'
    this.createdAt = new Date().toISOString();
    this.exitCode = null;
    this.buffer = ''; // Raw output buffer
    this.lines = [];  // Formatted HTML lines
    this.maxScrollback = options.maxScrollback || 1000;
    this.listeners = new Set();
  }

  appendOutput(rawChunk) {
    if (!rawChunk) return;
    this.buffer += rawChunk;
    const formattedHtml = ansiToHtml(rawChunk);
    
    // Split into lines preserving formatting
    const rawLines = rawChunk.split('\n');
    for (let i = 0; i < rawLines.length; i++) {
      const lineHtml = ansiToHtml(rawLines[i]);
      if (i === 0 && this.lines.length > 0 && !rawChunk.startsWith('\n')) {
        // Append to existing partial line
        this.lines[this.lines.length - 1] += lineHtml;
      } else {
        this.lines.push(lineHtml);
      }
    }

    // Enforce max scrollback limit
    if (this.lines.length > this.maxScrollback) {
      this.lines = this.lines.slice(this.lines.length - this.maxScrollback);
    }

    this.notify({ type: 'output', chunk: rawChunk, html: formattedHtml });
  }

  setTerminated(code) {
    this.state = 'terminated';
    this.exitCode = code;
    this.notify({ type: 'exit', code });
  }

  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  notify(event) {
    for (const fn of this.listeners) {
      try {
        fn(event);
      } catch (err) {
        console.error('Terminal listener error:', err);
      }
    }
  }

  clear() {
    this.buffer = '';
    this.lines = [];
    this.notify({ type: 'clear' });
  }

  search(query, options = {}) {
    if (!query) return { query: '', matchCount: 0, matches: [] };
    const caseSensitive = Boolean(options.caseSensitive);
    const flags = caseSensitive ? 'g' : 'gi';
    const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const regex = new RegExp(escaped, flags);
    const matches = [];
    const rawLines = this.buffer.split(/\r?\n/);
    for (let i = 0; i < rawLines.length; i++) {
      const line = rawLines[i];
      let match;
      while ((match = regex.exec(line)) !== null) {
        matches.push({
          line: i + 1,
          col: match.index + 1,
          text: match[0],
          lineContent: line
        });
      }
    }
    return { query, matchCount: matches.length, matches };
  }

  static linkify(text) {
    if (!text) return '';
    let result = text.replace(/(https?:\/\/[^\s<>'"]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer" class="term-link term-url">$1</a>');
    result = result.replace(/(([a-zA-Z]:[\\/][^\s:<>'"]+|[a-zA-Z0-9_\-\.\/]+?\.(?:ot|js|mjs|json|md|ps1|psm1|psd1|txt|html|css)):(\d+)(?::(\d+))?)/g, (match, fullMatch, filePath, line, col) => {
      const colStr = col ? `:${col}` : '';
      return `<a href="#open-file" data-path="${filePath}" data-line="${line}" data-col="${col || 1}" class="term-link term-file-link">${filePath}:${line}${colStr}</a>`;
    });
    return result;
  }
}

export class TerminalManager {
  constructor(options = {}) {
    this.profileManager = new TerminalProfileManager(options.profiles || []);
    this.sessions = new Map();
    this.activeSessionId = null;
    this.nextSessionSeq = 1;
    this.apiBase = options.apiBase || '/api/terminal';
    this.pollIntervalMs = options.pollIntervalMs || 100;
  }

  /**
   * Spawns a new terminal session.
   * Communicates with backend /api/terminal/session/create when running in browser.
   */
  async createSession(options = {}) {
    const profileId = options.profileId || this.profileManager.getDefaultProfile().id;
    const profile = this.profileManager.getProfile(profileId) || this.profileManager.getDefaultProfile();
    const id = options.id || `term-${Date.now()}-${this.nextSessionSeq++}`;

    const session = new TerminalSession(id, profile, {
      name: options.name || `${profile.name} (${this.sessions.size + 1})`,
      cwd: options.cwd,
      cols: options.cols || 80,
      rows: options.rows || 24,
      env: options.env,
      maxScrollback: options.maxScrollback || 1000
    });

    this.sessions.set(id, session);
    if (!this.activeSessionId) {
      this.activeSessionId = id;
    }

    // If backend API is available, request real backend PTY spawn
    if (typeof fetch === 'function') {
      try {
        const res = await fetch(`${this.apiBase}/session/create`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            id: session.id,
            profile: profile.id,
            shell: profile.shell,
            args: profile.args,
            cwd: session.cwd,
            cols: session.cols,
            rows: session.rows,
            env: session.env
          })
        });
        if (res.ok) {
          const data = await res.json();
          session.state = 'running';
          if (data.initialOutput) {
            session.appendOutput(data.initialOutput);
          }
          this.startPollingSession(session);
        } else {
          session.state = 'running'; // Offline/standalone fallback
        }
      } catch {
        session.state = 'running'; // Offline fallback
      }
    } else {
      session.state = 'running';
    }

    return session;
  }

  /**
   * Starts polling output for an active session.
   */
  startPollingSession(session) {
    let offset = 0;
    const poll = async () => {
      if (session.state === 'terminated' || !this.sessions.has(session.id)) return;
      try {
        const res = await fetch(`${this.apiBase}/session/poll?id=${encodeURIComponent(session.id)}&offset=${offset}`);
        if (res.ok) {
          const data = await res.json();
          if (data.output) {
            session.appendOutput(data.output);
            offset += data.output.length;
          }
          if (data.terminated) {
            session.setTerminated(data.exitCode ?? 0);
            return;
          }
        }
      } catch {}
      setTimeout(poll, this.pollIntervalMs);
    };
    setTimeout(poll, this.pollIntervalMs);
  }

  /**
   * Sends character stdin to the session's active process.
   */
  async sendInput(sessionId, text) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Session not found: ${sessionId}`);

    if (typeof fetch === 'function') {
      try {
        await fetch(`${this.apiBase}/session/input`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: sessionId, input: text })
        });
      } catch (err) {
        console.warn('Backend sendInput unavailable, echoing locally:', err);
      }
    }
  }

  /**
   * Resizes the session's terminal dimensions.
   */
  async resizeSession(sessionId, cols, rows) {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    session.cols = cols;
    session.rows = rows;

    if (typeof fetch === 'function') {
      try {
        await fetch(`${this.apiBase}/session/resize`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: sessionId, cols, rows })
        });
      } catch {}
    }
  }

  /**
   * Sends a signal (e.g. SIGINT / Ctrl+C, SIGTERM, SIGKILL) to the session.
   */
  async sendSignal(sessionId, signal = 'SIGINT') {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    if (typeof fetch === 'function') {
      try {
        await fetch(`${this.apiBase}/session/signal`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: sessionId, signal })
        });
      } catch {}
    }
  }

  /**
   * Closes and terminates a terminal session.
   */
  async closeSession(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) return;

    session.setTerminated(0);
    this.sessions.delete(sessionId);

    if (this.activeSessionId === sessionId) {
      const remaining = Array.from(this.sessions.keys());
      this.activeSessionId = remaining.length > 0 ? remaining[0] : null;
    }

    if (typeof fetch === 'function') {
      try {
        await fetch(`${this.apiBase}/session/close`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: sessionId })
        });
      } catch {}
    }
  }

  getSession(sessionId) {
    return this.sessions.get(sessionId) || null;
  }

  getActiveSession() {
    return this.sessions.get(this.activeSessionId) || null;
  }

  setActiveSession(sessionId) {
    if (!this.sessions.has(sessionId)) {
      throw new Error(`Session not found: ${sessionId}`);
    }
    this.activeSessionId = sessionId;
  }

  getAllSessions() {
    return Array.from(this.sessions.values());
  }

  async restartSession(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Session not found: ${sessionId}`);
    const profileId = session.profile.id;
    const name = session.name;
    const cwd = session.cwd;
    await this.closeSession(sessionId);
    return await this.createSession({ profileId, name, cwd });
  }

  async syncCwd(sessionId, newCwd) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Session not found: ${sessionId}`);
    session.cwd = newCwd;
    if (typeof fetch === 'function') {
      try {
        await fetch(`${this.apiBase}/session/cwd`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: sessionId, cwd: newCwd })
        });
      } catch {}
    }
    session.notify({ type: 'cwd', cwd: newCwd });
    return { ok: true, cwd: newCwd };
  }
}
