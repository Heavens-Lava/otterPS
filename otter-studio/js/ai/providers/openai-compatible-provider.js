import { OpenAiProvider } from './openai-provider.js';

export class OpenAiCompatibleProvider extends OpenAiProvider {
  constructor(config = {}) {
    super(config);
    this.name = 'openai-compatible';
    this.displayName = 'OpenAI Compatible (Local/Custom)';
    this.endpoint = config.endpoint !== undefined ? config.endpoint : 'http://localhost:11434/v1';
    this.apiKey = config.apiKey || 'not-needed';
    this.model = config.model || 'llama3';
  }

  isConfigured() {
    return Boolean(this.endpoint && this.endpoint.trim().length > 0);
  }

  getStatus() {
    if (!this.isConfigured()) {
      return {
        status: 'unconfigured',
        provider: this.name,
        displayName: this.displayName,
        message: 'Endpoint is not configured.'
      };
    }
    return {
      status: 'configured',
      provider: this.name,
      displayName: this.displayName,
      endpoint: this.endpoint,
      model: this.model,
      message: `OpenAI-compatible endpoint configured at ${this.endpoint} (${this.model}).`
    };
  }
}
