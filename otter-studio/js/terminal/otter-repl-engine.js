// otter-repl-engine.js - Production Otter REPL Engine for Otter Studio
/**
 * Production Interactive REPL Engine for the Otter Programming Language
 */
export class OtterReplEngine {
  constructor(options = {}) {
    this.variables = new Map();
    this.functions = new Map();
    this.loadedModules = new Set();
    this.history = [];
    this.historyIndex = -1;
    this.currentInput = '';
    this.outputListeners = new Set();

    // Default built-ins
    this.initDefaultEnvironment();
  }

  initDefaultEnvironment() {
    this.variables.clear();
    this.functions.clear();
    this.loadedModules.clear();

    // Pre-populate core constants
    this.variables.set('true', true);
    this.variables.set('false', false);
    this.variables.set('gone', null);
  }

  reset() {
    this.initDefaultEnvironment();
    return { ok: true, message: 'REPL environment reset to clean state.' };
  }

  // --- Multiline Block Detection ---
  isComplete(code) {
    if (!code || !code.trim()) {
      return { complete: true, openBlocks: 0, prompt: 'otter> ' };
    }

    const lines = code.split(/\r?\n/);
    let openBlocks = 0;
    let inString = false;
    let quoteChar = '';

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line || line.startsWith('#')) continue;

      // Check block openings
      if (/^(to\s+[A-Za-z_]|if\b|while\b|repeat\b|try\b)/.test(line)) {
        openBlocks++;
      }

      // Check block closings: single dot "."
      if (line === '.' || line.startsWith('. ')) {
        openBlocks = Math.max(0, openBlocks - 1);
      }
    }

    // Check open quotes or brackets
    let openBrackets = 0;
    let openParens = 0;
    for (let i = 0; i < code.length; i++) {
      const ch = code[i];
      if (ch === '"' && (i === 0 || code[i - 1] !== '\\')) {
        inString = !inString;
      }
      if (!inString) {
        if (ch === '[') openBrackets++;
        if (ch === ']') openBrackets = Math.max(0, openBrackets - 1);
        if (ch === '(') openParens++;
        if (ch === ')') openParens = Math.max(0, openParens - 1);
      }
    }

    const complete = (openBlocks === 0 && !inString && openBrackets === 0 && openParens === 0);
    const prompt = complete ? 'otter> ' : '...   ';

    return {
      complete,
      openBlocks,
      openBrackets,
      inString,
      prompt
    };
  }

  // --- Command History Navigation ---
  addHistory(line) {
    const trimmed = (line || '').trim();
    if (!trimmed) return;
    if (this.history.length === 0 || this.history[this.history.length - 1] !== trimmed) {
      this.history.push(trimmed);
    }
    this.historyIndex = this.history.length;
  }

  historyUp(currentLine = '') {
    if (this.history.length === 0) return currentLine;
    if (this.historyIndex === this.history.length) {
      this.currentInput = currentLine;
    }
    if (this.historyIndex > 0) {
      this.historyIndex--;
      return this.history[this.historyIndex];
    }
    return this.history[0];
  }

  historyDown() {
    if (this.history.length === 0) return '';
    if (this.historyIndex < this.history.length - 1) {
      this.historyIndex++;
      return this.history[this.historyIndex];
    }
    this.historyIndex = this.history.length;
    return this.currentInput;
  }

  // --- Auto-Completion ---
  complete(line) {
    const keywords = [
      'make', 'is', 'to', 'say', 'if', 'otherwise', 'while', 'repeat',
      'use', 'return', 'stop', 'plus', 'minus', 'times', 'divided by',
      'and', 'or', 'not', 'true', 'false', 'gone', 'for', 'each', 'in'
    ];
    const stdModules = ['"math"', '"strings"', '"collections"', '"fs"', '"net"', '"json"', '"time"'];

    // Find the current token being typed
    const match = line.match(/([A-Za-z0-9_"]*)$/);
    const prefix = match ? match[1] : '';

    const candidates = new Set();

    // Keywords
    for (const kw of keywords) {
      if (kw.startsWith(prefix)) candidates.add(kw);
    }
    // REPL Variables
    for (const varName of this.variables.keys()) {
      if (varName.startsWith(prefix)) candidates.add(varName);
    }
    // REPL Functions
    for (const fnName of this.functions.keys()) {
      if (fnName.startsWith(prefix)) candidates.add(fnName);
    }
    // Module names if typing a string
    if (prefix.startsWith('"') || line.trim().startsWith('use')) {
      for (const mod of stdModules) {
        if (mod.startsWith(prefix)) candidates.add(mod);
      }
    }

    return {
      prefix,
      completions: Array.from(candidates)
    };
  }

  // --- Syntax Highlighting ---
  highlight(code, mode = 'ansi') {
    if (mode === 'ansi') {
      return this._highlightAnsi(code);
    }
    return this._highlightHtml(code);
  }

  _highlightAnsi(code) {
    const keywords = /\b(make|is|to|say|if|otherwise|while|repeat|use|return|stop|plus|minus|times|divided by|and|or|not|true|false|gone|for|each|in)\b/g;
    let res = code
      .replace(/(#.*$)/gm, '\x1b[90m$1\x1b[0m') // comment
      .replace(/(".*?")/g, '\x1b[32m$1\x1b[0m') // string
      .replace(/\b(\d+(?:\.\d+)?)\b/g, '\x1b[33m$1\x1b[0m') // number
      .replace(keywords, '\x1b[36m$1\x1b[0m') // keyword
      .replace(/\b(to\s+)([A-Za-z_][A-Za-z0-9_]*)/g, '$1\x1b[35m$2\x1b[0m'); // func name
    return res;
  }

  _highlightHtml(code) {
    const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    return esc(code)
      .replace(/(#.*$)/gm, '<span class="ot-comment">$1</span>')
      .replace(/(&quot;.*?&quot;)/g, '<span class="ot-string">$1</span>')
      .replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="ot-number">$1</span>')
      .replace(/\b(make|is|to|say|if|otherwise|while|repeat|use|return|stop|plus|minus|times|divided by|and|or|not|true|false|gone)\b/g, '<span class="ot-keyword">$1</span>');
  }

  // --- Pretty Value & Object Inspection ---
  prettyPrint(val, depth = 0) {
    if (val === null || val === undefined) {
      return '\x1b[90mgone\x1b[0m';
    }
    if (typeof val === 'boolean') {
      return `\x1b[36m${val ? 'true' : 'false'}\x1b[0m`;
    }
    if (typeof val === 'number') {
      return `\x1b[33m${val}\x1b[0m`;
    }
    if (typeof val === 'string') {
      return `\x1b[32m"${val}"\x1b[0m`;
    }
    if (typeof val === 'function') {
      return `\x1b[35m[Function: ${val.name || 'anonymous'}]\x1b[0m`;
    }
    if (Array.isArray(val)) {
      if (depth > 2) return '[...]';
      const items = val.map(item => this.prettyPrint(item, depth + 1)).join(', ');
      return `[${items}]`;
    }
    if (typeof val === 'object') {
      if (depth > 2) return '{...}';
      const pairs = Object.entries(val).map(([k, v]) => `${k}: ${this.prettyPrint(v, depth + 1)}`).join(', ');
      return `{ ${pairs} }`;
    }
    return String(val);
  }

  // --- REPL Statement / Expression Evaluation ---
  async eval(input) {
    const text = (input || '').trim();
    if (!text) return { ok: true, value: null };

    // Meta-commands
    if (text === '.reset' || text === '.clear') {
      return this.reset();
    }
    if (text === '.vars') {
      const varsObj = {};
      for (const [k, v] of this.variables.entries()) {
        varsObj[k] = v;
      }
      return { ok: true, type: 'meta', variables: varsObj };
    }
    if (text === '.funcs') {
      return { ok: true, type: 'meta', functions: Array.from(this.functions.keys()) };
    }

    this.addHistory(text);

    try {
      // 1. Module loading: use <module>
      const useMatch = text.match(/^use\s+(.+)$/);
      if (useMatch) {
        const modName = useMatch[1].replace(/["']/g, '').trim();
        this.loadedModules.add(modName);
        return {
          ok: true,
          type: 'module',
          value: `Module '${modName}' loaded.`,
          prettyValue: `\x1b[32mModule '${modName}' loaded.\x1b[0m`
        };
      }

      // 2. Function definition: to <name> [params] ... .
      const fnMatch = text.match(/^to\s+([A-Za-z_][A-Za-z0-9_]*)([\s\S]*)\.\s*$/);
      if (fnMatch) {
        const fnName = fnMatch[1];
        const fnBody = fnMatch[2].trim();
        this.functions.set(fnName, { name: fnName, body: fnBody });
        return {
          ok: true,
          type: 'function',
          value: `Function '${fnName}' defined.`,
          prettyValue: `\x1b[35m[Function: ${fnName}]\x1b[0m`
        };
      }

      // 3. Variable assignment: make <var> is <expr> or <var> is <expr>
      const assignMatch = text.match(/^(?:make\s+)?([A-Za-z_][A-Za-z0-9_]*)\s+is\s+([\s\S]+)$/);
      if (assignMatch && !text.startsWith('if ')) {
        const varName = assignMatch[1];
        const expr = assignMatch[2].trim();
        const evaluatedVal = this._evaluateExpression(expr);
        this.variables.set(varName, evaluatedVal);
        return {
          ok: true,
          type: 'assignment',
          name: varName,
          value: evaluatedVal,
          prettyValue: this.prettyPrint(evaluatedVal)
        };
      }

      // 4. Output statement: say <expr>
      if (text.startsWith('say ')) {
        const expr = text.slice(4).trim();
        const evaluatedVal = this._evaluateExpression(expr);
        const strVal = typeof evaluatedVal === 'object' ? JSON.stringify(evaluatedVal) : String(evaluatedVal ?? 'gone');
        return {
          ok: true,
          type: 'say',
          stdout: strVal + '\n',
          value: evaluatedVal,
          prettyValue: this.prettyPrint(evaluatedVal)
        };
      }

      // 5. Function call or general expression evaluation
      const evaluatedVal = this._evaluateExpression(text);
      return {
        ok: true,
        type: 'expression',
        value: evaluatedVal,
        prettyValue: this.prettyPrint(evaluatedVal)
      };

    } catch (err) {
      return {
        ok: false,
        error: err.message,
        suggestion: err.suggestion || 'Check syntax and ensure variables are defined before use.',
        stage: 'runtime'
      };
    }
  }

  _evaluateExpression(expr) {
    const trimmed = expr.trim();

    // Check literals
    if (trimmed === 'true') return true;
    if (trimmed === 'false') return false;
    if (trimmed === 'gone') return null;
    if (/^-?\d+(?:\.\d+)?$/.test(trimmed)) {
      return Number(trimmed);
    }
    if (/^"(?:[^"\\]|\\.)*"$/.test(trimmed)) {
      return trimmed.slice(1, -1).replace(/\\n/g, '\n').replace(/\\t/g, '\t');
    }

    // List literal [a, b, c]
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      const inner = trimmed.slice(1, -1).trim();
      if (!inner) return [];
      return inner.split(',').map(part => this._evaluateExpression(part.trim()));
    }

    // Object/Thing literal { a: 1, b: 2 }
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      const inner = trimmed.slice(1, -1).trim();
      if (!inner) return {};
      const obj = {};
      for (const pair of inner.split(',')) {
        const [k, v] = pair.split(':');
        if (k && v) {
          obj[k.trim()] = this._evaluateExpression(v.trim());
        }
      }
      return obj;
    }

    // Check variable lookup
    if (this.variables.has(trimmed)) {
      return this.variables.get(trimmed);
    }

    // Check function lookup
    if (this.functions.has(trimmed)) {
      return `[Function: ${trimmed}]`;
    }

    // Infix arithmetic and logical operators
    // "plus", "minus", "times", "divided by", "and", "or"
    if (trimmed.includes(' plus ')) {
      const [left, ...rest] = trimmed.split(' plus ');
      return this._evaluateExpression(left) + this._evaluateExpression(rest.join(' plus '));
    }
    if (trimmed.includes(' minus ')) {
      const [left, ...rest] = trimmed.split(' minus ');
      return this._evaluateExpression(left) - this._evaluateExpression(rest.join(' minus '));
    }
    if (trimmed.includes(' times ')) {
      const [left, ...rest] = trimmed.split(' times ');
      return this._evaluateExpression(left) * this._evaluateExpression(rest.join(' times '));
    }
    if (trimmed.includes(' divided by ')) {
      const [left, ...rest] = trimmed.split(' divided by ');
      const r = this._evaluateExpression(rest.join(' divided by '));
      if (r === 0) throw new Error('Division by zero');
      return this._evaluateExpression(left) / r;
    }
    if (trimmed.includes(' and ')) {
      const [left, ...rest] = trimmed.split(' and ');
      const lVal = this._evaluateExpression(left);
      const rVal = this._evaluateExpression(rest.join(' and '));
      if (typeof lVal === 'string' && typeof rVal === 'string') {
        return lVal + rVal; // Otter concatenation
      }
      return Boolean(lVal && rVal);
    }
    if (trimmed.includes(' or ')) {
      const [left, ...rest] = trimmed.split(' or ');
      return Boolean(this._evaluateExpression(left) || this._evaluateExpression(rest.join(' or ')));
    }

    // Unary "not"
    if (trimmed.startsWith('not ')) {
      return !this._evaluateExpression(trimmed.slice(4));
    }

    // Fallback error with suggestion
    const err = new Error(`Identifier or expression '${trimmed}' could not be evaluated.`);
    err.suggestion = `Define '${trimmed}' with 'make ${trimmed} is <value>' before referencing it.`;
    throw err;
  }
}

export const otterRepl = new OtterReplEngine();
