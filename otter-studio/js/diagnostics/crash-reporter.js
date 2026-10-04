// crash-reporter.js - Automated Crash Reporting & Diagnostic Snapshot Engine
// Captures unhandled crashes, async call stacks, redacted reproduction context, and environment telemetry.

import { extractOtterAsyncStackTrace, formatOtterAsyncStackTrace } from './host-translator.js';

const SECRET_PATTERNS = [
  /bearer\s+[a-zA-Z0-9_\-\.]+/gi,
  /(?:password|passwd|secret|token|api_key|apikey)\s*[:=]\s*["']?([^\s"']+)["']?/gi,
  /ghp_[a-zA-Z0-9]{36}/g,
  /isk_[a-zA-Z0-9_\-]+/g
];

/**
 * Redacts secrets, tokens, and passwords from sensitive crash dumps.
 */
export function sanitizeText(text) {
  if (typeof text !== 'string') return text;
  let sanitized = text;
  for (const pattern of SECRET_PATTERNS) {
    sanitized = sanitized.replace(pattern, (match) => {
      if (match.toLowerCase().startsWith('bearer ')) return 'Bearer [REDACTED]';
      return '[REDACTED_SECRET]';
    });
  }
  return sanitized;
}

export class CrashReportManager {
  constructor(options = {}) {
    this.maxBreadcrumbs = options.maxBreadcrumbs || 50;
    this.breadcrumbs = [];
    this.reports = new Map(); // id -> report
    this.storage = options.storage || (typeof localStorage !== 'undefined' ? localStorage : new Map());
    this.storageKey = options.storageKey || 'otter_studio_crash_reports';
    this.loadFromStorage();
  }

  loadFromStorage() {
    try {
      const raw = this.storage instanceof Map ? this.storage.get(this.storageKey) : this.storage.getItem(this.storageKey);
      if (raw) {
        const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
        if (Array.isArray(parsed)) {
          for (const rep of parsed) {
            this.reports.set(rep.id, rep);
          }
        }
      }
    } catch {
      // Safe fallback on corrupted local storage
    }
  }

  saveToStorage() {
    try {
      const arr = Array.from(this.reports.values());
      const data = JSON.stringify(arr);
      if (this.storage instanceof Map) {
        this.storage.set(this.storageKey, data);
      } else if (this.storage.setItem) {
        this.storage.setItem(this.storageKey, data);
      }
    } catch {
      // Ignore storage quota errors
    }
  }

  /**
   * Records a user/editor breadcrumb for crash reproduction.
   */
  recordBreadcrumb(category, message, metadata = {}) {
    const entry = {
      timestamp: new Date().toISOString(),
      category: String(category || 'action'),
      message: sanitizeText(String(message || '')),
      metadata: JSON.parse(JSON.stringify(metadata))
    };

    this.breadcrumbs.push(entry);
    if (this.breadcrumbs.length > this.maxBreadcrumbs) {
      this.breadcrumbs.shift();
    }
    return entry;
  }

  /**
   * Generates a complete, structured crash report.
   */
  generateReport(error, options = {}) {
    const id = `crash_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    const timestamp = new Date().toISOString();
    const rawMessage = error instanceof Error ? error.message : String(error || 'Unknown fatal error');
    const message = sanitizeText(rawMessage);

    const rawStack = error instanceof Error ? (error.stack || '') : String(error || '');
    const asyncChain = options.asyncChain || [];
    const asyncFrames = extractOtterAsyncStackTrace(rawStack, asyncChain, options.activeFile || 'main.ot', options.line || 1);
    const formattedStack = formatOtterAsyncStackTrace(asyncFrames);

    const report = {
      id,
      timestamp,
      error: {
        message,
        code: options.code || (error && error.code) || 'OT8001',
        category: options.category || 'runtime-crash',
        suggestion: options.suggestion || 'Review the crash stack trace and recent breadcrumbs.'
      },
      stack: {
        raw: sanitizeText(rawStack),
        frames: asyncFrames,
        formatted: formattedStack
      },
      environment: {
        platform: typeof process !== 'undefined' ? process.platform : 'browser',
        nodeVersion: typeof process !== 'undefined' ? process.version : null,
        studioVersion: '1.0.0',
        memory: typeof process !== 'undefined' && process.memoryUsage ? process.memoryUsage() : null
      },
      context: {
        activeFile: options.activeFile || null,
        cursor: options.cursor || null,
        dirtyFiles: options.dirtyFiles || []
      },
      breadcrumbs: [...this.breadcrumbs]
    };

    this.reports.set(id, report);
    this.saveToStorage();
    return report;
  }

  getReport(id) {
    return this.reports.get(id) || null;
  }

  listReports() {
    return Array.from(this.reports.values()).sort((a, b) => b.timestamp.localeCompare(a.timestamp));
  }

  clearReports() {
    this.reports.clear();
    this.saveToStorage();
  }
}

export const defaultCrashReporter = new CrashReportManager();
