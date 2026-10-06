/**
 * Otter Studio Semantic Inline Completion Engine
 * Handles debounced ghost-text suggestions in editor with abort cancellation.
 */

export class InlineCompletionEngine {
  constructor(options = {}) {
    this.enabled = options.enabled !== false;
    this.debounceMs = options.debounceMs || 300;
    this.activeController = null;
    this.lastCompletion = null;
    this.cache = new Map();
  }

  setEnabled(val) {
    this.enabled = Boolean(val);
  }

  cancelPending() {
    if (this.activeController) {
      this.activeController.abort();
      this.activeController = null;
    }
  }

  /**
   * Requests completion with debounce and cancellation
   */
  async requestCompletion(prefix, suffix, context = {}, provider = null) {
    if (!this.enabled || !prefix || !prefix.trim()) {
      return null;
    }

    // Cancel any previous in-flight request
    this.cancelPending();

    const cacheKey = `${prefix.slice(-80)}|${suffix.slice(0, 20)}`;
    if (this.cache.has(cacheKey)) {
      return this.cache.get(cacheKey);
    }

    this.activeController = new AbortController();
    const signal = this.activeController.signal;

    try {
      // Local debounce wait
      await new Promise((resolve, reject) => {
        const timer = setTimeout(resolve, this.debounceMs);
        signal.addEventListener('abort', () => {
          clearTimeout(timer);
          reject(new Error('Completion request superseded'));
        });
      });

      let code = '';
      if (provider) {
        const res = await provider.complete(prefix, context, { signal, maxTokens: 80 });
        code = res?.code || '';
      }

      if (code) {
        // Strip duplicate prefix if returned by model
        if (code.startsWith(prefix)) {
          code = code.slice(prefix.length);
        }
        this.cache.set(cacheKey, code);
        this.lastCompletion = code;
        return code;
      }
      return null;
    } catch (err) {
      if (err.message?.includes('superseded') || signal.aborted) {
        return null;
      }
      return null;
    } finally {
      this.activeController = null;
    }
  }
}
