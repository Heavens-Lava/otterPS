// devtools-engine.js - Complete DevTools Platform for Otter Studio
// Implements: Network inspector, DOM/CSS inspector, Console & storage inspector,
// Responsive device preview emulator, and Source Map v3 generator (JS to Otter).

// ============================================================================
// 1. NETWORK INSPECTOR & HAR EXPORTER
// ============================================================================

export const NETWORK_PROFILES = {
  none: { name: 'No Throttling', downloadBps: Infinity, latencyMs: 0 },
  'fast-3g': { name: 'Fast 3G', downloadBps: 1.5 * 1024 * 1024, latencyMs: 40 },
  'slow-3g': { name: 'Slow 3G', downloadBps: 500 * 1024, latencyMs: 200 },
  offline: { name: 'Offline', downloadBps: 0, latencyMs: 0 }
};

export class NetworkInspector {
  constructor(options = {}) {
    this.maxEntries = options.maxEntries || 200;
    this.entries = [];
    this.activeProfile = 'none';
    this.listeners = new Set();
  }

  setThrottlingProfile(profileKey) {
    if (!NETWORK_PROFILES[profileKey]) {
      throw new Error(`Unknown network profile "${profileKey}"`);
    }
    this.activeProfile = profileKey;
    return NETWORK_PROFILES[profileKey];
  }

  getThrottlingProfile() {
    return { key: this.activeProfile, ...NETWORK_PROFILES[this.activeProfile] };
  }

  startRequest({ id, url, method = 'GET', headers = {}, body = null }) {
    const entry = {
      id: id || `req-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      url,
      method: method.toUpperCase(),
      requestHeaders: { ...headers },
      requestBody: body,
      startTime: Date.now(),
      status: null,
      statusText: null,
      responseHeaders: {},
      responseBody: null,
      durationMs: null,
      sizeBytes: body ? (typeof body === 'string' ? Buffer.byteLength(body) : JSON.stringify(body).length) : 0,
      state: 'pending'
    };

    this.entries.push(entry);
    if (this.entries.length > this.maxEntries) {
      this.entries.shift();
    }

    this._notify('request-started', entry);
    return entry;
  }

  completeResponse(id, { status = 200, statusText = 'OK', headers = {}, body = null }) {
    const entry = this.entries.find(e => e.id === id);
    if (!entry) return null;

    const now = Date.now();
    entry.status = status;
    entry.statusText = statusText;
    entry.responseHeaders = { ...headers };
    entry.responseBody = body;
    entry.durationMs = now - entry.startTime;
    entry.state = status >= 400 ? 'failed' : 'completed';

    const respSize = body ? (typeof body === 'string' ? Buffer.byteLength(body) : JSON.stringify(body).length) : 0;
    entry.sizeBytes += respSize;

    this._notify('response-completed', entry);
    return entry;
  }

  failRequest(id, error) {
    const entry = this.entries.find(e => e.id === id);
    if (!entry) return null;

    entry.status = 0;
    entry.statusText = error?.message || 'Network Error';
    entry.durationMs = Date.now() - entry.startTime;
    entry.state = 'failed';

    this._notify('request-failed', entry);
    return entry;
  }

  getEntries({ filter = null, method = null, status = null, search = null } = {}) {
    let result = [...this.entries];

    if (method) {
      result = result.filter(e => e.method.toLowerCase() === method.toLowerCase());
    }

    if (status !== null && status !== undefined) {
      result = result.filter(e => e.status === status);
    }

    if (filter === 'failed') {
      result = result.filter(e => e.state === 'failed');
    } else if (filter === 'xhr') {
      result = result.filter(e => e.url.includes('/api/'));
    }

    if (search) {
      const q = search.toLowerCase();
      result = result.filter(e => e.url.toLowerCase().includes(q) || (e.statusText && e.statusText.toLowerCase().includes(q)));
    }

    return result;
  }

  clear() {
    this.entries = [];
    this._notify('cleared', {});
  }

  exportHar() {
    return {
      log: {
        version: '1.2',
        creator: { name: 'Otter Studio DevTools', version: '1.0.0' },
        entries: this.entries.map(e => ({
          startedDateTime: new Date(e.startTime).toISOString(),
          time: e.durationMs || 0,
          request: {
            method: e.method,
            url: e.url,
            httpVersion: 'HTTP/1.1',
            headers: Object.entries(e.requestHeaders).map(([name, value]) => ({ name, value: String(value) })),
            queryString: [],
            bodySize: e.requestBody ? String(e.requestBody).length : 0
          },
          response: {
            status: e.status || 0,
            statusText: e.statusText || '',
            httpVersion: 'HTTP/1.1',
            headers: Object.entries(e.responseHeaders).map(([name, value]) => ({ name, value: String(value) })),
            content: {
              size: e.responseBody ? String(e.responseBody).length : 0,
              mimeType: e.responseHeaders['content-type'] || 'text/plain',
              text: typeof e.responseBody === 'string' ? e.responseBody : JSON.stringify(e.responseBody)
            }
          }
        }))
      }
    };
  }

  _notify(event, data) {
    for (const listener of this.listeners) {
      try { listener(event, data); } catch {}
    }
  }

  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }
}

// ============================================================================
// 2. DOM & CSS INSPECTOR (TREE, COMPUTED STYLES, BOX MODEL)
// ============================================================================

export class DomCssInspector {
  constructor() {}

  // Parse or walk virtual DOM node
  findNode(root, predicate) {
    if (!root) return null;
    if (predicate(root)) return root;

    if (Array.isArray(root.children)) {
      for (const child of root.children) {
        const found = this.findNode(child, predicate);
        if (found) return found;
      }
    }

    return null;
  }

  computeBoxModel(styles = {}) {
    const parseDim = (val, defaultVal = 0) => {
      if (typeof val === 'number') return val;
      if (!val) return defaultVal;
      const num = parseFloat(val);
      return isNaN(num) ? defaultVal : num;
    };

    const width = parseDim(styles.width, 100);
    const height = parseDim(styles.height, 40);

    const marginTop = parseDim(styles.marginTop || styles.margin, 0);
    const marginRight = parseDim(styles.marginRight || styles.margin, 0);
    const marginBottom = parseDim(styles.marginBottom || styles.margin, 0);
    const marginLeft = parseDim(styles.marginLeft || styles.margin, 0);

    const paddingTop = parseDim(styles.paddingTop || styles.padding, 0);
    const paddingRight = parseDim(styles.paddingRight || styles.padding, 0);
    const paddingBottom = parseDim(styles.paddingBottom || styles.padding, 0);
    const paddingLeft = parseDim(styles.paddingLeft || styles.padding, 0);

    const borderTop = parseDim(styles.borderTopWidth || styles.borderWidth, 0);
    const borderRight = parseDim(styles.borderRightWidth || styles.borderWidth, 0);
    const borderBottom = parseDim(styles.borderBottomWidth || styles.borderWidth, 0);
    const borderLeft = parseDim(styles.borderLeftWidth || styles.borderWidth, 0);

    return {
      margin: { top: marginTop, right: marginRight, bottom: marginBottom, left: marginLeft },
      border: { top: borderTop, right: borderRight, bottom: borderBottom, left: borderLeft },
      padding: { top: paddingTop, right: paddingRight, bottom: paddingBottom, left: paddingLeft },
      content: { width, height },
      totalWidth: width + marginLeft + paddingLeft + borderLeft + borderRight + paddingRight + marginRight,
      totalHeight: height + marginTop + paddingTop + borderTop + borderBottom + paddingBottom + marginBottom
    };
  }

  computeStyles(node, styleRules = []) {
    const computed = {};
    const matchedRules = [];

    // Apply matched rules
    for (const rule of styleRules) {
      if (this._matchesSelector(node, rule.selector)) {
        matchedRules.push(rule);
        Object.assign(computed, rule.declarations);
      }
    }

    // Apply inline style overrides
    if (node.style && typeof node.style === 'object') {
      Object.assign(computed, node.style);
    }

    return {
      computed,
      matchedRules,
      boxModel: this.computeBoxModel(computed)
    };
  }

  _matchesSelector(node, selector) {
    if (!node || !selector) return false;
    const sel = selector.trim();
    if (sel === '*') return true;
    if (sel.startsWith('#') && node.id === sel.slice(1)) return true;
    if (sel.startsWith('.') && Array.isArray(node.classList) && node.classList.includes(sel.slice(1))) return true;
    if (sel.toLowerCase() === (node.tag || node.type || '').toLowerCase()) return true;
    return false;
  }
}

// ============================================================================
// 3. STORAGE & BROWSER CONSOLE MANAGER
// ============================================================================

export class StorageConsoleManager {
  constructor() {
    this.logs = [];
    this.localStorage = new Map();
    this.sessionStorage = new Map();
    this.cookies = new Map();
  }

  // Console methods
  log(message, ...args) { this._recordLog('log', message, args); }
  info(message, ...args) { this._recordLog('info', message, args); }
  warn(message, ...args) { this._recordLog('warn', message, args); }
  error(message, ...args) { this._recordLog('error', message, args); }

  _recordLog(level, message, args = []) {
    this.logs.push({
      id: `log-${this.logs.length + 1}`,
      level,
      message: String(message),
      args,
      timestamp: new Date().toISOString()
    });
  }

  getLogs({ level = null, search = null } = {}) {
    let res = [...this.logs];
    if (level) res = res.filter(l => l.level === level);
    if (search) {
      const q = search.toLowerCase();
      res = res.filter(l => l.message.toLowerCase().includes(q));
    }
    return res;
  }

  clearLogs() {
    this.logs = [];
  }

  // Storage methods
  setItem(type, key, value) {
    const store = this._getStore(type);
    store.set(String(key), String(value));
  }

  getItem(type, key) {
    const store = this._getStore(type);
    return store.has(String(key)) ? store.get(String(key)) : null;
  }

  removeItem(type, key) {
    const store = this._getStore(type);
    store.delete(String(key));
  }

  clearStorage(type) {
    const store = this._getStore(type);
    store.clear();
  }

  listStorage(type) {
    const store = this._getStore(type);
    return Object.fromEntries(store.entries());
  }

  _getStore(type) {
    if (type === 'session') return this.sessionStorage;
    if (type === 'cookies') return this.cookies;
    return this.localStorage;
  }
}

// ============================================================================
// 4. RESPONSIVE DEVICE PREVIEW EMULATOR
// ============================================================================

export const DEVICE_PRESETS = {
  'iPhone 14': { width: 390, height: 844, dpr: 3.0, category: 'mobile', userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)' },
  'Pixel 7': { width: 412, height: 915, dpr: 2.625, category: 'mobile', userAgent: 'Mozilla/5.0 (Linux; Android 13; Pixel 7)' },
  'iPad Pro': { width: 1024, height: 1366, dpr: 2.0, category: 'tablet', userAgent: 'Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X)' },
  'Laptop 13': { width: 1280, height: 800, dpr: 1.0, category: 'desktop', userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' },
  'Desktop 1080p': { width: 1920, height: 1080, dpr: 1.0, category: 'desktop', userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }
};

export class ResponsivePreviewManager {
  constructor(defaultDevice = 'iPhone 14') {
    this.currentDevice = defaultDevice;
    this.orientation = 'portrait'; // 'portrait' | 'landscape'
    this.zoom = 1.0;
  }

  getAvailableDevices() {
    return Object.keys(DEVICE_PRESETS).map(name => ({
      name,
      ...DEVICE_PRESETS[name]
    }));
  }

  setDevice(name) {
    if (!DEVICE_PRESETS[name]) {
      throw new Error(`Unknown device preset "${name}"`);
    }
    this.currentDevice = name;
    return this.getViewport();
  }

  setOrientation(orientation) {
    if (orientation !== 'portrait' && orientation !== 'landscape') {
      throw new Error(`Invalid orientation "${orientation}". Expected portrait or landscape.`);
    }
    this.orientation = orientation;
    return this.getViewport();
  }

  toggleOrientation() {
    this.orientation = this.orientation === 'portrait' ? 'landscape' : 'portrait';
    return this.getViewport();
  }

  setZoom(zoomFactor) {
    this.zoom = Math.max(0.25, Math.min(3.0, Number(zoomFactor) || 1.0));
    return this.zoom;
  }

  getViewport() {
    const preset = DEVICE_PRESETS[this.currentDevice] || DEVICE_PRESETS['iPhone 14'];
    const isPortrait = this.orientation === 'portrait';

    const width = isPortrait ? preset.width : preset.height;
    const height = isPortrait ? preset.height : preset.width;

    return {
      deviceName: this.currentDevice,
      category: preset.category,
      width,
      height,
      dpr: preset.dpr,
      orientation: this.orientation,
      zoom: this.zoom,
      scaledWidth: Math.round(width * this.zoom),
      scaledHeight: Math.round(height * this.zoom),
      userAgent: preset.userAgent,
      mediaQuery: `(max-width: ${width}px) and (orientation: ${this.orientation})`
    };
  }
}

// ============================================================================
// 5. SOURCE MAP V3 GENERATOR (MAPPING JS BACK TO OTTER)
// ============================================================================

export const BASE64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export function encodeVlq(val) {
  let vlq = val < 0 ? ((-val) << 1) | 1 : (val << 1);
  let encoded = '';
  do {
    let digit = vlq & 31;
    vlq >>>= 5;
    if (vlq > 0) digit |= 32;
    encoded += BASE64_CHARS[digit];
  } while (vlq > 0);
  return encoded;
}

export function decodeVlq(str, index = 0) {
  let result = 0;
  let shift = 0;
  let continuation = true;
  let i = index;

  while (continuation && i < str.length) {
    const char = str[i++];
    const digit = BASE64_CHARS.indexOf(char);
    if (digit === -1) break;

    continuation = (digit & 32) !== 0;
    result += (digit & 31) << shift;
    shift += 5;
  }

  const isNeg = (result & 1) === 1;
  const value = (result >>> 1) * (isNeg ? -1 : 1);
  return { value, nextIndex: i };
}

export class SourceMapV3Generator {
  constructor({ file = 'output.js', sourceRoot = '' } = {}) {
    this.file = file;
    this.sourceRoot = sourceRoot;
    this.sources = [];
    this.sourcesContent = [];
    this.names = [];
    this.mappings = []; // list of { genLine, genCol, origLine, origCol, sourceIndex, nameIndex }
  }

  addSource(sourcePath, content = null) {
    let idx = this.sources.indexOf(sourcePath);
    if (idx === -1) {
      idx = this.sources.length;
      this.sources.push(sourcePath);
      this.sourcesContent.push(content);
    }
    return idx;
  }

  addMapping({ generated, original, source = null, name = null }) {
    const sourceIndex = source ? this.addSource(source) : 0;
    let nameIndex = null;
    if (name) {
      nameIndex = this.names.indexOf(name);
      if (nameIndex === -1) {
        nameIndex = this.names.length;
        this.names.push(name);
      }
    }

    this.mappings.push({
      genLine: generated.line,
      genCol: generated.column,
      origLine: original ? original.line : null,
      origCol: original ? original.column : null,
      sourceIndex,
      nameIndex
    });
  }

  generate() {
    // Sort mappings by generated line, then generated col
    this.mappings.sort((a, b) => {
      if (a.genLine !== b.genLine) return a.genLine - b.genLine;
      return a.genCol - b.genCol;
    });

    const lines = [];
    let prevGenCol = 0;
    let prevSourceIdx = 0;
    let prevOrigLine = 0;
    let prevOrigCol = 0;
    let currentLine = 1;
    let currentSegments = [];

    for (const m of this.mappings) {
      while (currentLine < m.genLine) {
        lines.push(currentSegments.join(','));
        currentSegments = [];
        currentLine++;
        prevGenCol = 0;
      }

      let segment = encodeVlq(m.genCol - prevGenCol);
      prevGenCol = m.genCol;

      if (m.origLine !== null && m.origCol !== null) {
        segment += encodeVlq(m.sourceIndex - prevSourceIdx);
        prevSourceIdx = m.sourceIndex;

        segment += encodeVlq(m.origLine - prevOrigLine);
        prevOrigLine = m.origLine;

        segment += encodeVlq(m.origCol - prevOrigCol);
        prevOrigCol = m.origCol;
      }

      currentSegments.push(segment);
    }

    lines.push(currentSegments.join(','));

    return {
      version: 3,
      file: this.file,
      sourceRoot: this.sourceRoot,
      sources: this.sources,
      sourcesContent: this.sourcesContent.filter(c => c !== null),
      names: this.names,
      mappings: lines.join(';')
    };
  }

  originalPositionFor({ line, column }) {
    // Search for closest mapping matching or before genLine and genCol
    const candidates = this.mappings.filter(m => m.genLine === line && m.genCol <= column);
    if (candidates.length > 0) {
      const match = candidates[candidates.length - 1];
      return {
        source: this.sources[match.sourceIndex] || null,
        line: match.origLine,
        column: match.origCol,
        name: match.nameIndex !== null ? this.names[match.nameIndex] : null
      };
    }

    const prevLineMatch = this.mappings.filter(m => m.genLine < line);
    if (prevLineMatch.length > 0) {
      const match = prevLineMatch[prevLineMatch.length - 1];
      return {
        source: this.sources[match.sourceIndex] || null,
        line: match.origLine,
        column: match.origCol,
        name: null
      };
    }

    return { source: null, line: null, column: null, name: null };
  }
}
