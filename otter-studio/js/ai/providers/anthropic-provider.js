import { AiProvider } from '../provider-base.js';

export class AnthropicProvider extends AiProvider {
  constructor(config = {}) {
    super(config);
    this.name = 'anthropic';
    this.displayName = 'Anthropic';
    this.endpoint = config.endpoint || 'https://api.anthropic.com/v1';
    this.apiKey = config.apiKey || '';
    this.model = config.model || 'claude-3-5-sonnet-20241022';
    this.fetchFn = config.fetchFn || globalThis.fetch;
  }

  isConfigured() {
    return Boolean(this.apiKey && this.apiKey.trim().length > 0);
  }

  getStatus() {
    if (!this.isConfigured()) {
      return {
        status: 'unconfigured',
        provider: this.name,
        displayName: this.displayName,
        message: 'Anthropic API key is missing. Set it in Settings > AI.'
      };
    }
    return {
      status: 'configured',
      provider: this.name,
      displayName: this.displayName,
      model: this.model,
      message: `Anthropic configured with model ${this.model}.`
    };
  }

  async _request(path, body, signal) {
    if (!this.isConfigured()) {
      throw new Error('Anthropic provider is not configured: missing API key.');
    }

    const url = `${this.endpoint.replace(/\/+$/, '')}/${path.replace(/^\/+/, '')}`;
    const res = await this.fetchFn(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': this.apiKey,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify(body),
      signal
    });

    if (res.status === 401) {
      const err = new Error('Authentication failed: Invalid Anthropic API key.');
      err.status = 401;
      err.code = 'AUTHENTICATION_FAILED';
      throw err;
    }

    if (res.status === 429) {
      const err = new Error('Rate limit exceeded: Anthropic rate limit or quota reached.');
      err.status = 429;
      err.code = 'RATE_LIMITED';
      throw err;
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      const err = new Error(`Anthropic API error (${res.status}): ${text.slice(0, 200)}`);
      err.status = res.status;
      err.code = 'PROVIDER_ERROR';
      throw err;
    }

    return await res.json();
  }

  async testConnection(signal) {
    if (!this.isConfigured()) {
      return { ok: false, status: 'unconfigured', message: 'No API key provided.' };
    }
    try {
      await this._request('messages', {
        model: this.model,
        messages: [{ role: 'user', content: 'Ping' }],
        max_tokens: 5
      }, signal);
      return {
        ok: true,
        status: 'connected',
        provider: this.name,
        model: this.model,
        message: `Successfully connected to Anthropic (${this.model}).`
      };
    } catch (err) {
      return {
        ok: false,
        status: err.code === 'AUTHENTICATION_FAILED' ? 'authentication_failed' :
                err.code === 'RATE_LIMITED' ? 'rate_limited' : 'connection_failed',
        message: err.message
      };
    }
  }

  async chat(messages, options = {}) {
    const anthropicMessages = messages.map(m => ({
      role: m.role === 'assistant' ? 'assistant' : 'user',
      content: m.content
    }));

    const body = {
      model: this.model,
      system: 'You are Otter Studio Copilot, an expert pair programmer for Otter. Provide clean, accurate solutions.',
      messages: anthropicMessages,
      max_tokens: options.maxTokens || 1200
    };

    const json = await this._request('messages', body, options.signal);
    const reply = json.content?.map(c => c.text || '').join('\n') || '';
    return {
      provider: this.name,
      displayName: this.displayName,
      model: this.model,
      reply,
      usage: json.usage
    };
  }

  async complete(prompt, context = {}, options = {}) {
    const body = {
      model: this.model,
      system: 'You are an inline code completion engine for Otter. Output only code completion text.',
      messages: [{ role: 'user', content: `Code:\n${prompt}` }],
      max_tokens: options.maxTokens || 150
    };
    const json = await this._request('messages', body, options.signal);
    const code = json.content?.map(c => c.text || '').join('\n') || '';
    return {
      provider: this.name,
      model: this.model,
      code
    };
  }

  async explain(code, context = {}, options = {}) {
    const res = await this.chat([{ role: 'user', content: `Explain this Otter code:\n${code}` }], options);
    return {
      provider: this.name,
      model: this.model,
      explanation: res.reply,
      summary: res.reply.split('\n\n')[0]
    };
  }

  async generateTests(code, context = {}, options = {}) {
    const res = await this.chat([{ role: 'user', content: `Generate Otter tests for:\n${code}` }], options);
    return {
      provider: this.name,
      model: this.model,
      testCode: res.reply
    };
  }

  async diagnose(diagnostics, sourceCode, context = {}, options = {}) {
    const res = await this.chat([{
      role: 'user',
      content: `Diagnose issues in code:\n${sourceCode}\nDiagnostics: ${JSON.stringify(diagnostics)}`
    }], options);
    return {
      provider: this.name,
      model: this.model,
      summary: res.reply,
      patches: [{ description: 'AI proposed fix', patchedCode: res.reply }]
    };
  }

  async synthesizeCode(goal, context = {}, options = {}) {
    const res = await this.chat([{ role: 'user', content: `Synthesize Otter code for: ${goal}` }], options);
    return {
      provider: this.name,
      model: this.model,
      code: res.reply,
      explanation: `Generated for: ${goal}`
    };
  }
}
