/**
 * Otter Studio AI Provider Base Class
 * Defines the contract for all AI model providers (OpenAI, Anthropic, OpenAI-compatible, Offline).
 */
export class AiProvider {
  constructor(config = {}) {
    this.name = 'base';
    this.displayName = 'Base Provider';
    this.config = { ...config };
    this.capabilities = {
      chat: true,
      complete: true,
      explain: true,
      generateTests: true,
      diagnose: true,
      synthesizeCode: true,
      streaming: false,
    };
  }

  isConfigured() {
    return false;
  }

  getStatus() {
    if (!this.isConfigured()) {
      return { status: 'unconfigured', message: 'API key or endpoint not configured.' };
    }
    return { status: 'configured', message: 'Provider configured.' };
  }

  async testConnection() {
    throw new Error('testConnection() not implemented on base provider');
  }

  async chat(messages, options = {}) {
    throw new Error('chat() not implemented on base provider');
  }

  async complete(prompt, context = {}, options = {}) {
    throw new Error('complete() not implemented on base provider');
  }

  async explain(code, context = {}, options = {}) {
    throw new Error('explain() not implemented on base provider');
  }

  async generateTests(code, context = {}, options = {}) {
    throw new Error('generateTests() not implemented on base provider');
  }

  async diagnose(diagnostics, sourceCode, context = {}, options = {}) {
    throw new Error('diagnose() not implemented on base provider');
  }

  async synthesizeCode(goal, context = {}, options = {}) {
    throw new Error('synthesizeCode() not implemented on base provider');
  }
}
