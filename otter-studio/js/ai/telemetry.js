/**
 * Otter Studio AI Telemetry & Local Diagnostics
 * Transparent, local-only performance tracking without storing API keys, user source, or prompts.
 */

export class AiTelemetryManager {
  constructor(maxEntries = 100) {
    this.maxEntries = maxEntries;
    this.entries = [];
  }

  record(event = {}) {
    const entry = {
      timestamp: new Date().toISOString(),
      operation: event.operation || 'chat',
      provider: event.provider || 'unknown',
      model: event.model || 'none',
      durationMs: typeof event.durationMs === 'number' ? Math.round(event.durationMs) : 0,
      contextCharCount: event.contextCharCount || 0,
      responseCharCount: event.responseCharCount || 0,
      success: Boolean(event.success),
      errorCategory: event.errorCategory || null,
      wasCancelled: Boolean(event.wasCancelled)
    };

    this.entries.unshift(entry);
    if (this.entries.length > this.maxEntries) {
      this.entries.pop();
    }
    return entry;
  }

  getRecentEntries(limit = 20) {
    return this.entries.slice(0, limit);
  }

  getSummary() {
    const total = this.entries.length;
    if (total === 0) {
      return { totalRequests: 0, successRate: 1.0, avgDurationMs: 0, cancellations: 0, byProvider: {} };
    }

    const successful = this.entries.filter(e => e.success).length;
    const cancelled = this.entries.filter(e => e.wasCancelled).length;
    const totalDuration = this.entries.reduce((acc, e) => acc + e.durationMs, 0);

    const byProvider = {};
    for (const entry of this.entries) {
      byProvider[entry.provider] = (byProvider[entry.provider] || 0) + 1;
    }

    return {
      totalRequests: total,
      successRate: Math.round((successful / total) * 100) / 100,
      avgDurationMs: Math.round(totalDuration / total),
      cancellations: cancelled,
      byProvider
    };
  }

  clear() {
    this.entries = [];
  }
}
