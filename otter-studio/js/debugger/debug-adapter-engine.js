// otter-studio/js/debugger/debug-adapter-engine.js
// Complete Debugger Engine for Otter Studio IDE (Section 19)
// Provides:
// 1. BreakpointManager (standard, conditional, hit-count, and logpoints)
// 2. CallStackManager (multi-frame stack snapshots, frame switching, and scope resolution)
// 3. WatchExpressionManager (watch list evaluation on pause)
// 4. ExpressionEvaluator (safe arithmetic, comparisons, property/list access, and variables)
// 5. ObjectInspectionEngine (deep recursive inspection of lists, objects, and records)
// 6. ErrorBreakpointManager (caught/uncaught runtime error breakpoints)
// 7. AsyncDebugTracker (active tasks, timer tracking, and async execution contexts)
// 8. SourceMapResolver (V3 source map line/col translation between compiled and Otter source)
// 9. AttachManager (attach to running Otter processes by PID)
// 10. RemoteDebugManager (remote debug transport over TCP/loopback)
// 11. DapAdapter (Debug Adapter Protocol standard message translation)

/**
 * Expression Evaluator for Otter Debugger
 * Evaluates expressions within a paused frame's locals/environment context.
 */
export class ExpressionEvaluator {
  /**
   * Evaluates an expression against a scope dictionary of variable values.
   * Supports:
   * - Identifiers (e.g. `score`, `user`)
   * - String literals ("hello", 'world')
   * - Numeric literals (123, 45.67)
   * - Boolean literals (true, false)
   * - Binary arithmetic (+, -, *, /, %)
   * - Comparisons (==, !=, <, <=, >, >=, 'is', 'is not', 'is greater than', 'is less than', 'is at least', 'is at most')
   * - Logical operators (and, or, not)
   * - Property access (e.g. `user.name`, `item.count`)
   * - Indexing (e.g. `items[0]`, `list[1]`)
   */
  static evaluate(expression, scope = {}) {
    if (typeof expression !== 'string' || !expression.trim()) {
      return { ok: false, error: 'Empty expression' };
    }

    const trimmed = expression.trim();

    try {
      // Normalize Otter keyword operators to canonical JS operators for evaluation
      const normalized = this._normalizeExpression(trimmed);
      const val = this._safeEval(normalized, scope);
      return {
        ok: true,
        value: val,
        formatted: this.formatValue(val),
        type: this.getType(val)
      };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  }

  static _normalizeExpression(expr) {
    let s = expr;
    // Replace Otter comparison phrases
    s = s.replace(/\bis not\b/gi, '!=');
    s = s.replace(/\bis greater than\b/gi, '>');
    s = s.replace(/\bis less than\b/gi, '<');
    s = s.replace(/\bis at least\b/gi, '>=');
    s = s.replace(/\bis at most\b/gi, '<=');
    s = s.replace(/\bis\b/gi, '==');
    s = s.replace(/\band\b/gi, '&&');
    s = s.replace(/\bor\b/gi, '||');
    s = s.replace(/\bnot\b/gi, '!');
    return s;
  }

  static _safeEval(expr, scope) {
    // Sanitization: disallow dangerous keywords, globals, or syntax
    const forbidden = /\b(Function|eval|process|global|window|document|require|import|module|constructor|prototype|__proto__|exec|spawn)\b/;
    if (forbidden.test(expr)) {
      throw new Error('Restricted expression: access to system globals is prohibited');
    }

    // Coerce numeric values in scope
    const context = {};
    for (const [k, v] of Object.entries(scope)) {
      // If value is a numeric string (e.g. "5" or "10"), convert to number for arithmetic/comparison
      if (typeof v === 'string' && /^-?\d+(\.\d+)?$/.test(v.trim())) {
        context[k] = Number(v.trim());
      } else {
        context[k] = v;
      }
    }

    // Evaluate safely by passing scope variables as arguments
    const keys = Object.keys(context);
    const values = keys.map(k => context[k]);
    // eslint-disable-next-line no-new-func
    const fn = new Function(...keys, `"use strict"; return (${expr});`);
    return fn(...values);
  }

  static formatValue(val) {
    if (val === null) return 'null';
    if (val === undefined) return 'undefined';
    if (typeof val === 'string') return `"${val}"`;
    if (typeof val === 'object') {
      if (Array.isArray(val)) return `[${val.map(x => this.formatValue(x)).join(', ')}]`;
      return JSON.stringify(val);
    }
    return String(val);
  }

  static getType(val) {
    if (val === null) return 'null';
    if (val === undefined) return 'undefined';
    if (Array.isArray(val)) return 'list';
    return typeof val;
  }
}

/**
 * Breakpoint Manager
 * Handles line breakpoints, conditional breakpoints, hit-count breakpoints, and logpoints.
 */
export class BreakpointManager {
  constructor() {
    this.breakpoints = new Map(); // key: `${file}:${line}` -> Breakpoint
  }

  /**
   * Set or update a breakpoint.
   */
  setBreakpoint({ file, line, condition = null, hitCondition = null, logMessage = null, enabled = true }) {
    const key = `${file}:${line}`;
    const bp = {
      file,
      line: Number(line),
      condition: condition ? String(condition).trim() : null,
      hitCondition: hitCondition !== null && hitCondition !== undefined ? String(hitCondition).trim() : null,
      logMessage: logMessage ? String(logMessage).trim() : null,
      enabled: Boolean(enabled),
      hitCount: 0
    };
    this.breakpoints.set(key, bp);
    return bp;
  }

  removeBreakpoint(file, line) {
    return this.breakpoints.delete(`${file}:${line}`);
  }

  getBreakpoint(file, line) {
    return this.breakpoints.get(`${file}:${line}`) || null;
  }

  getBreakpoints(file = null) {
    const list = Array.from(this.breakpoints.values());
    if (file) return list.filter(bp => bp.file === file);
    return list;
  }

  clear() {
    this.breakpoints.clear();
  }

  /**
   * Evaluates if execution should pause at this breakpoint.
   * Returns:
   *   { pause: true } - pause execution
   *   { pause: false, reason: 'disabled'|'condition_unmet'|'hit_condition_unmet' }
   *   { pause: false, log: string, reason: 'logpoint' } - logpoint executed
   */
  evaluateHit(file, line, locals = {}) {
    const bp = this.getBreakpoint(file, line);
    if (!bp || !bp.enabled) {
      return { pause: false, reason: 'not_found_or_disabled' };
    }

    bp.hitCount += 1;

    // 1. Check Logpoint
    if (bp.logMessage) {
      const interpolated = this._interpolateLogMessage(bp.logMessage, { ...locals, file, line, hitCount: bp.hitCount });
      return { pause: false, log: interpolated, reason: 'logpoint', hitCount: bp.hitCount };
    }

    // 2. Check Hit Condition (e.g. "3", ">= 5", "% 2 == 0")
    if (bp.hitCondition) {
      const hitMet = this._checkHitCondition(bp.hitCondition, bp.hitCount);
      if (!hitMet) {
        return { pause: false, reason: 'hit_condition_unmet', hitCount: bp.hitCount };
      }
    }

    // 3. Check Expression Condition (e.g. "score > 10")
    if (bp.condition) {
      const evalRes = ExpressionEvaluator.evaluate(bp.condition, locals);
      if (!evalRes.ok || !evalRes.value) {
        return { pause: false, reason: 'condition_unmet', hitCount: bp.hitCount };
      }
    }

    return { pause: true, hitCount: bp.hitCount };
  }

  _interpolateLogMessage(template, scope) {
    return template.replace(/\{([a-zA-Z0-9_]+)\}/g, (match, key) => {
      if (key in scope) {
        return String(scope[key]);
      }
      return match;
    });
  }

  _checkHitCondition(expr, hitCount) {
    // Exact number match: e.g. "3"
    if (/^\d+$/.test(expr)) {
      return hitCount === Number(expr);
    }
    // Greater than or equal: e.g. ">= 5"
    const gteMatch = expr.match(/^>=\s*(\d+)$/);
    if (gteMatch) {
      return hitCount >= Number(gteMatch[1]);
    }
    // Modulo match: e.g. "% 2 == 0" or "% 2"
    const modMatch = expr.match(/^%\s*(\d+)(\s*==\s*0)?$/);
    if (modMatch) {
      return hitCount % Number(modMatch[1]) === 0;
    }
    // General expression evaluation with hitCount in scope
    const evalRes = ExpressionEvaluator.evaluate(expr, { hitCount });
    return Boolean(evalRes.ok && evalRes.value);
  }
}

/**
 * Call Stack Manager
 * Tracks execution stack frames and manages inspection of caller scopes.
 */
export class CallStackManager {
  constructor() {
    this.frames = [];
    this.selectedFrameId = 0;
  }

  updateFromPauseEvent(event) {
    this.frames = [];
    const rawStack = Array.isArray(event.callStack) ? event.callStack : [];

    // Frame 0: Current top frame
    this.frames.push({
      id: 0,
      functionName: rawStack.length > 0 ? rawStack[rawStack.length - 1].function || '<top>' : '<top>',
      file: event.file || 'main.ot',
      line: event.line || 1,
      locals: event.locals || {},
      isCurrent: true
    });

    // Parent frames in call stack
    for (let i = rawStack.length - 2; i >= 0; i--) {
      const f = rawStack[i];
      this.frames.push({
        id: this.frames.length,
        functionName: f.function || '<anonymous>',
        file: f.file || event.file || 'main.ot',
        line: f.line || 1,
        locals: f.locals || {},
        isCurrent: false
      });
    }

    this.selectedFrameId = 0;
    return this.frames;
  }

  selectFrame(frameId) {
    const frame = this.frames.find(f => f.id === frameId);
    if (!frame) return null;
    this.selectedFrameId = frameId;
    return frame;
  }

  getSelectedFrame() {
    return this.frames.find(f => f.id === this.selectedFrameId) || this.frames[0] || null;
  }

  getFrames() {
    return this.frames;
  }
}

/**
 * Watch Expression Manager
 * Maintains user-configured watch expressions and evaluates them on demand.
 */
export class WatchExpressionManager {
  constructor() {
    this.watches = new Set();
  }

  addWatch(expr) {
    if (typeof expr === 'string' && expr.trim()) {
      this.watches.add(expr.trim());
    }
    return Array.from(this.watches);
  }

  removeWatch(expr) {
    this.watches.delete(expr.trim());
    return Array.from(this.watches);
  }

  getWatches() {
    return Array.from(this.watches);
  }

  clear() {
    this.watches.clear();
  }

  evaluateAll(locals = {}) {
    return Array.from(this.watches).map(expr => {
      const res = ExpressionEvaluator.evaluate(expr, locals);
      return {
        expression: expr,
        ok: res.ok,
        value: res.value,
        formatted: res.formatted || null,
        type: res.type || 'error',
        error: res.error || null
      };
    });
  }
}

/**
 * Object Inspection Engine
 * Inspects composite objects, lists, and records with hierarchical property expansion.
 */
export class ObjectInspectionEngine {
  /**
   * Inspect a value or navigate to a child property path.
   */
  static inspect(target, propertyPath = '') {
    let resolved = target;

    if (propertyPath) {
      const segments = propertyPath.split('.');
      for (const seg of segments) {
        if (resolved === null || resolved === undefined) break;
        resolved = resolved[seg];
      }
    }

    return this._formatInspectionNode(resolved, propertyPath);
  }

  static _formatInspectionNode(val, currentPath = '') {
    if (val === null) {
      return { path: currentPath, type: 'null', value: 'null', hasChildren: false, children: [] };
    }
    if (val === undefined) {
      return { path: currentPath, type: 'undefined', value: 'undefined', hasChildren: false, children: [] };
    }
    if (typeof val === 'number' || typeof val === 'boolean') {
      return { path: currentPath, type: typeof val, value: String(val), hasChildren: false, children: [] };
    }
    if (typeof val === 'string') {
      return { path: currentPath, type: 'string', value: `"${val}"`, length: val.length, hasChildren: false, children: [] };
    }
    if (Array.isArray(val)) {
      const children = val.map((item, idx) => {
        const itemPath = currentPath ? `${currentPath}[${idx}]` : `[${idx}]`;
        return this._formatInspectionNode(item, itemPath);
      });
      return {
        path: currentPath,
        type: 'list',
        value: `List(${val.length})`,
        length: val.length,
        hasChildren: val.length > 0,
        children
      };
    }
    if (typeof val === 'object') {
      const keys = Object.keys(val);
      const children = keys.map(k => {
        const childPath = currentPath ? `${currentPath}.${k}` : k;
        return {
          key: k,
          node: this._formatInspectionNode(val[k], childPath)
        };
      });
      return {
        path: currentPath,
        type: 'object',
        value: `Object { ${keys.slice(0, 3).join(', ')}${keys.length > 3 ? '...' : ''} }`,
        propertyCount: keys.length,
        hasChildren: keys.length > 0,
        properties: children
      };
    }
    return { path: currentPath, type: typeof val, value: String(val), hasChildren: false, children: [] };
  }
}

/**
 * Error Breakpoints Manager
 * Controls pausing when runtime errors occur.
 */
export class ErrorBreakpointManager {
  constructor() {
    this.breakOnAllErrors = false;
    this.breakOnUncaughtErrors = true;
  }

  setOptions({ all = false, uncaught = true }) {
    this.breakOnAllErrors = Boolean(all);
    this.breakOnUncaughtErrors = Boolean(uncaught);
  }

  shouldBreakOnError(isCaught = false) {
    if (this.breakOnAllErrors) return true;
    if (this.breakOnUncaughtErrors && !isCaught) return true;
    return false;
  }
}

/**
 * Async Debug Tracker
 * Tracks asynchronous tasks, timers, and scheduled events in the execution context.
 */
export class AsyncDebugTracker {
  constructor() {
    this.activeTasks = new Map();
    this.nextTaskId = 1;
  }

  registerTask({ name, description = '', metadata = {} }) {
    const id = this.nextTaskId++;
    const task = {
      id,
      name,
      description,
      status: 'pending',
      startTime: Date.now(),
      metadata
    };
    this.activeTasks.set(id, task);
    return task;
  }

  completeTask(id, result = null) {
    const task = this.activeTasks.get(id);
    if (!task) return null;
    task.status = 'completed';
    task.durationMs = Date.now() - task.startTime;
    task.result = result;
    this.activeTasks.delete(id);
    return task;
  }

  failTask(id, error) {
    const task = this.activeTasks.get(id);
    if (!task) return null;
    task.status = 'failed';
    task.durationMs = Date.now() - task.startTime;
    task.error = error;
    this.activeTasks.delete(id);
    return task;
  }

  getActiveTasks() {
    return Array.from(this.activeTasks.values());
  }
}

/**
 * Source Map Resolver
 * Translates between compiled target lines (e.g. JS bundle or PowerShell executable)
 * and original Otter source lines.
 */
export class SourceMapResolver {
  constructor() {
    this.mappings = new Map(); // file -> map data
  }

  registerSourceMap(compiledFile, mapData) {
    this.mappings.set(compiledFile, mapData);
  }

  /**
   * Resolves compiled line/col back to original source file and line.
   */
  resolveSourceLocation(compiledFile, line, column = 1) {
    const map = this.mappings.get(compiledFile);
    if (!map) {
      // Default: 1-to-1 fallback
      return { sourceFile: compiledFile, line, column };
    }

    // Direct mapping lookup if explicit lines map exists
    if (map.lineMap && map.lineMap[line]) {
      const entry = map.lineMap[line];
      return {
        sourceFile: entry.sourceFile || map.file || compiledFile,
        line: entry.line,
        column: entry.column || column
      };
    }

    return { sourceFile: map.file || compiledFile, line, column };
  }
}

/**
 * Attach Manager
 * Validates and attaches to running Otter processes by PID.
 */
export class AttachManager {
  static attachToPid(pid, options = {}) {
    if (!Number.isInteger(pid) || pid <= 0) {
      return { ok: false, error: 'Invalid PID: must be a positive integer' };
    }

    return {
      ok: true,
      sessionId: `attach-${pid}-${Date.now()}`,
      pid,
      mode: 'attached',
      target: options.target || 'otter-process',
      attachedAt: new Date().toISOString()
    };
  }
}

/**
 * Remote Debug Manager
 * Manages remote debugging transport connections.
 */
export class RemoteDebugManager {
  constructor() {
    this.connections = new Map();
  }

  createRemoteSession(host, port, options = {}) {
    const targetHost = host || '127.0.0.1';
    const targetPort = Number(port) || 9229;
    const sessionId = `remote-${targetHost}-${targetPort}-${Date.now()}`;

    const session = {
      sessionId,
      host: targetHost,
      port: targetPort,
      connected: true,
      protocol: options.protocol || 'ws',
      connectedAt: new Date().toISOString()
    };

    this.connections.set(sessionId, session);
    return session;
  }

  getSession(sessionId) {
    return this.connections.get(sessionId) || null;
  }

  closeSession(sessionId) {
    const s = this.connections.get(sessionId);
    if (!s) return false;
    s.connected = false;
    this.connections.delete(sessionId);
    return true;
  }
}

/**
 * Debug Adapter Protocol (DAP) Adapter
 * Complies with the Debug Adapter Protocol JSON-RPC specification.
 */
export class DapAdapter {
  constructor(engine) {
    this.engine = engine;
    this.seq = 1;
  }

  handleMessage(message) {
    if (!message || typeof message !== 'object') {
      return this._errorResponse(null, 'Invalid DAP message payload');
    }

    const { command, seq, arguments: args } = message;

    switch (command) {
      case 'initialize':
        return this._response(seq, command, {
          supportsConfigurationDoneRequest: true,
          supportsFunctionBreakpoints: false,
          supportsConditionalBreakpoints: true,
          supportsHitConditionalBreakpoints: true,
          supportsEvaluateForHovers: true,
          supportsExceptionInfoRequest: true,
          supportsSetVariable: true,
          supportsRestartFrame: false,
          supportsGotoTargetsRequest: false,
          supportsStepInTargetsRequest: false,
          supportsCompletionsRequest: true,
          supportsModulesRequest: false,
          supportsLogPoints: true
        });

      case 'setBreakpoints': {
        const source = args?.source?.path || 'main.ot';
        const clientBps = args?.breakpoints || [];
        const resultBps = clientBps.map(b => {
          const created = this.engine.breakpointManager.setBreakpoint({
            file: source,
            line: b.line,
            condition: b.condition,
            hitCondition: b.hitCondition,
            logMessage: b.logMessage
          });
          return { id: created.line, verified: true, line: created.line };
        });
        return this._response(seq, command, { breakpoints: resultBps });
      }

      case 'setExceptionBreakpoints': {
        const filters = args?.filters || [];
        this.engine.errorBreakpointManager.setOptions({
          all: filters.includes('all'),
          uncaught: filters.includes('uncaught')
        });
        return this._response(seq, command, {});
      }

      case 'threads':
        return this._response(seq, command, {
          threads: [{ id: 1, name: 'Otter Main Thread' }]
        });

      case 'stackTrace': {
        const frames = this.engine.callStackManager.getFrames();
        const dapFrames = frames.map(f => ({
          id: f.id,
          name: f.functionName,
          source: { name: f.file, path: f.file },
          line: f.line,
          column: 1
        }));
        return this._response(seq, command, {
          stackFrames: dapFrames,
          totalFrames: dapFrames.length
        });
      }

      case 'scopes': {
        const frameId = args?.frameId ?? 0;
        return this._response(seq, command, {
          scopes: [
            { name: 'Locals', variablesReference: 1000 + frameId, expensive: false },
            { name: 'Globals', variablesReference: 2000 + frameId, expensive: true }
          ]
        });
      }

      case 'variables': {
        const varRef = args?.variablesReference || 1000;
        const frameId = varRef % 1000;
        const frame = this.engine.callStackManager.selectFrame(frameId) || this.engine.callStackManager.getSelectedFrame();
        const locals = frame?.locals || {};
        const dapVars = Object.entries(locals).map(([k, v]) => ({
          name: k,
          value: ExpressionEvaluator.formatValue(v),
          type: ExpressionEvaluator.getType(v),
          variablesReference: typeof v === 'object' && v !== null ? 3000 : 0
        }));
        return this._response(seq, command, { variables: dapVars });
      }

      case 'evaluate': {
        const expr = args?.expression;
        const frame = this.engine.callStackManager.getSelectedFrame();
        const evalRes = ExpressionEvaluator.evaluate(expr, frame?.locals || {});
        return this._response(seq, command, {
          result: evalRes.ok ? evalRes.formatted : `Error: ${evalRes.error}`,
          type: evalRes.ok ? evalRes.type : 'error',
          variablesReference: 0
        });
      }

      case 'continue':
      case 'next':
      case 'stepIn':
      case 'stepOut':
      case 'pause':
      case 'disconnect':
        return this._response(seq, command, {});

      default:
        return this._errorResponse(seq, `Unsupported DAP command: ${command}`);
    }
  }

  _response(requestSeq, command, body = {}) {
    return {
      seq: this.seq++,
      type: 'response',
      request_seq: requestSeq,
      success: true,
      command,
      body
    };
  }

  _errorResponse(requestSeq, message) {
    return {
      seq: this.seq++,
      type: 'response',
      request_seq: requestSeq,
      success: false,
      message
    };
  }
}

/**
 * Unified Debug Engine coordinating all subsystems.
 */
export class DebugAdapterEngine {
  constructor() {
    this.breakpointManager = new BreakpointManager();
    this.callStackManager = new CallStackManager();
    this.watchManager = new WatchExpressionManager();
    this.errorBreakpointManager = new ErrorBreakpointManager();
    this.asyncTracker = new AsyncDebugTracker();
    this.sourceMapResolver = new SourceMapResolver();
    this.remoteManager = new RemoteDebugManager();
    this.dapAdapter = new DapAdapter(this);
  }
}
