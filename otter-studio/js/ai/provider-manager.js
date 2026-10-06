import { OfflineHeuristicProvider } from './providers/offline-provider.js';
import { OpenAiProvider } from './providers/openai-provider.js';
import { AnthropicProvider } from './providers/anthropic-provider.js';
import { OpenAiCompatibleProvider } from './providers/openai-compatible-provider.js';
import { ContextManager } from './context-manager.js';
import { AiTelemetryManager } from './telemetry.js';
import { InlineCompletionEngine } from './inline-completion.js';
import { OtterCodeValidator } from './code-validator.js';

export class AiProviderManager {
  constructor(initialSettings = {}) {
    this.contextManager = new ContextManager();
    this.telemetry = new AiTelemetryManager();
    this.inlineCompletion = new InlineCompletionEngine();
    this.validator = OtterCodeValidator;

    this.activeProviderName = initialSettings.activeProvider || 'offline-heuristic';
    this.settings = {
      activeProvider: this.activeProviderName,
      includeCurrentFile: initialSettings.includeCurrentFile !== false,
      includeDiagnostics: initialSettings.includeDiagnostics !== false,
      includeWorkspaceContext: Boolean(initialSettings.includeWorkspaceContext),
      inlineCompletionsEnabled: initialSettings.inlineCompletionsEnabled !== false,
      providers: {
        'offline-heuristic': {},
        'openai': { endpoint: 'https://api.openai.com/v1', model: 'gpt-4o-mini', apiKey: '' },
        'anthropic': { endpoint: 'https://api.anthropic.com/v1', model: 'claude-3-5-sonnet-20241022', apiKey: '' },
        'openai-compatible': { endpoint: 'http://localhost:11434/v1', model: 'llama3', apiKey: '' },
        ...(initialSettings.providers || {})
      }
    };

    this.providers = new Map();
    this._initProviders();
  }

  _initProviders() {
    this.providers.set('offline-heuristic', new OfflineHeuristicProvider(this.settings.providers['offline-heuristic']));
    this.providers.set('openai', new OpenAiProvider(this.settings.providers['openai']));
    this.providers.set('anthropic', new AnthropicProvider(this.settings.providers['anthropic']));
    this.providers.set('openai-compatible', new OpenAiCompatibleProvider(this.settings.providers['openai-compatible']));
  }

  getActiveProvider() {
    const p = this.providers.get(this.activeProviderName);
    return p || this.providers.get('offline-heuristic');
  }

  setProviderConfig(name, config) {
    if (!this.settings.providers[name]) {
      this.settings.providers[name] = {};
    }
    // Only update apiKey if a non-masked string was sent
    if (config.apiKey !== undefined) {
      if (config.apiKey.startsWith('••••') || config.apiKey === '') {
        if (config.apiKey === '') {
          this.settings.providers[name].apiKey = '';
        }
      } else {
        this.settings.providers[name].apiKey = config.apiKey;
      }
    }
    if (config.endpoint !== undefined) this.settings.providers[name].endpoint = config.endpoint;
    if (config.model !== undefined) this.settings.providers[name].model = config.model;

    // Reinstantiate provider
    if (name === 'openai') {
      this.providers.set('openai', new OpenAiProvider(this.settings.providers['openai']));
    } else if (name === 'anthropic') {
      this.providers.set('anthropic', new AnthropicProvider(this.settings.providers['anthropic']));
    } else if (name === 'openai-compatible') {
      this.providers.set('openai-compatible', new OpenAiCompatibleProvider(this.settings.providers['openai-compatible']));
    }
  }

  setActiveProvider(name) {
    if (this.providers.has(name)) {
      this.activeProviderName = name;
      this.settings.activeProvider = name;
      return true;
    }
    return false;
  }

  getPublicSettings() {
    const maskKey = (key) => {
      if (!key) return '';
      if (key.length <= 4) return '••••';
      return '••••••••' + key.slice(-4);
    };

    const publicProviders = {};
    for (const [key, val] of Object.entries(this.settings.providers)) {
      publicProviders[key] = {
        endpoint: val.endpoint,
        model: val.model,
        hasKey: Boolean(val.apiKey && val.apiKey.length > 0),
        maskedKey: maskKey(val.apiKey)
      };
    }

    const active = this.getActiveProvider();
    return {
      activeProvider: this.activeProviderName,
      activeStatus: active.getStatus(),
      includeCurrentFile: this.settings.includeCurrentFile,
      includeDiagnostics: this.settings.includeDiagnostics,
      includeWorkspaceContext: this.settings.includeWorkspaceContext,
      inlineCompletionsEnabled: this.settings.inlineCompletionsEnabled,
      providers: publicProviders
    };
  }

  async testConnection(providerName) {
    const p = this.providers.get(providerName || this.activeProviderName);
    if (!p) {
      return { ok: false, status: 'unknown_provider', message: `Provider ${providerName} not found.` };
    }
    return await p.testConnection();
  }
}
