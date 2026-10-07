/**
 * Otter Studio Semantic Inline Completion Engine
 * Handles debounced ghost-text suggestions in editor with abort cancellation
 * and strict monotonic sequence protection against out-of-order race conditions.
 */

export class InlineCompletionEngine {
  constructor(options = {}) {
    this.enabled = options.enabled !== false;
    this.debounceMs = options.debounceMs || 300;
    this.activeController = null;
    this.lastCompletion = null;
    this.cache = new Map();
    this.currentRequestId = 0;
  }

  setEnabled(val) {
    this.enabled = Boolean(val);
  }

  cancelPending() {
    this.currentRequestId++;
    if (this.activeController) {
      this.activeController.abort();
      this.activeController = null;
    }
  }

  async requestCompletion(prefix, suffix, context = {}, provider = null) {
    if (!this.enabled || !prefix || !prefix.trim()) {
      return null;
    }

    this.cancelPending();
    const reqId = this.currentRequestId;

    const cacheKey = `${prefix.slice(-80)}|${suffix.slice(0, 20)}`;
    if (this.cache.has(cacheKey)) {
      return this.cache.get(cacheKey);
    }

    this.activeController = new AbortController();
    const signal = this.activeController.signal;

    try {
      await new Promise((resolve, reject) => {
        const timer = setTimeout(resolve, this.debounceMs);
        signal.addEventListener('abort', () => {
          clearTimeout(timer);
          reject(new Error('Completion request superseded'));
        });
      });

      // Verify not superseded during debounce
      if (reqId !== this.currentRequestId || signal.aborted) {
        return null;
      }

      let code = '';
      if (provider) {
        const res = await provider.complete(prefix, context, { signal, maxTokens: 80 });
        code = res?.code || '';
      }

      // Verify not superseded while waiting for provider response
      if (reqId !== this.currentRequestId || signal.aborted) {
        return null;
      }

      if (code) {
        if (code.startsWith(prefix)) {
          code = code.slice(prefix.length);
        }
        this.cache.set(cacheKey, code);
        this.lastCompletion = code;
        return code;
      }
      return null;
    } catch (err) {
      return null;
    } finally {
      if (reqId === this.currentRequestId) {
        this.activeController = null;
      }
    }
  }
}
