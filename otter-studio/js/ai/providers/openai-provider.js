import { AiProvider } from '../provider-base.js';

export class OpenAiProvider extends AiProvider {
  constructor(config = {}) {
    super(config);
    this.name = 'openai';
    this.displayName = 'OpenAI';
    this.endpoint = config.endpoint || 'https://api.openai.com/v1';
    this.apiKey = config.apiKey || '';
    this.model = config.model || 'gpt-4o-mini';
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
        message: 'OpenAI API key is missing. Set it in Settings > AI.'
      };
    }
    return {
      status: 'configured',
      provider: this.name,
      displayName: this.displayName,
      model: this.model,
      message: `OpenAI configured with model ${this.model}.`
    };
  }

  async _request(path, body, signal) {
    if (!this.isConfigured()) {
      throw new Error('OpenAI provider is not configured: missing API key.');
    }

    const url = `${this.endpoint.replace(/\/+$/, '')}/${path.replace(/^\/+/, '')}`;
    const res = await this.fetchFn(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.apiKey}`
      },
      body: JSON.stringify(body),
      signal
    });

    if (res.status === 401) {
      const err = new Error('Authentication failed: Invalid OpenAI API key.');
      err.status = 401;
      err.code = 'AUTHENTICATION_FAILED';
      throw err;
    }

    if (res.status === 429) {
      const err = new Error('Rate limit exceeded: OpenAI rate limit or quota reached.');
      err.status = 429;
      err.code = 'RATE_LIMITED';
      throw err;
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      const err = new Error(`OpenAI API error (${res.status}): ${text.slice(0, 200)}`);
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
      const res = await this._request('chat/completions', {
        model: this.model,
        messages: [{ role: 'user', content: 'Ping' }],
        max_tokens: 5
      }, signal);
      return {
        ok: true,
        status: 'connected',
        provider: this.name,
        model: this.model,
        message: `Successfully connected to OpenAI (${this.model}).`
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
    const formattedMessages = [
      {
        role: 'system',
        content: 'You are Otter Studio Copilot, an expert pair programmer for the Otter programming language. Keep responses practical, concise, and accurate.'
      },
      ...messages
    ];

    if (options.contextFormatted) {
      formattedMessages.splice(1, 0, {
        role: 'system',
        content: `IDE Context:\n${options.contextFormatted}`
      });
    }

    const json = await this._request('chat/completions', {
      model: this.model,
      messages: formattedMessages,
      max_tokens: options.maxTokens || 1200,
      temperature: options.temperature ?? 0.2
    }, options.signal);

    const reply = json.choices?.[0]?.message?.content || '';
    return {
      provider: this.name,
      displayName: this.displayName,
      model: this.model,
      reply,
      usage: json.usage
    };
  }

  async complete(prompt, context = {}, options = {}) {
    const systemPrompt = 'You are an inline code completion engine for the Otter programming language. Produce only the raw code continuation without explanation.';
    const messages = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: `Context:\n${context.formatted || ''}\n\nCode before cursor:\n${prompt}` }
    ];
    const json = await this._request('chat/completions', {
      model: this.model,
      messages,
      max_tokens: options.maxTokens || 150,
      temperature: 0.1
    }, options.signal);
    return {
      provider: this.name,
      model: this.model,
      code: json.choices?.[0]?.message?.content || ''
    };
  }

  async explain(code, context = {}, options = {}) {
    const messages = [
      { role: 'system', content: 'Explain this Otter code clearly and provide a concise summary.' },
      { role: 'user', content: `Code:\n${code}\n\nContext:\n${context.formatted || 'None'}` }
    ];
    const res = await this.chat(messages, { ...options, maxTokens: 800 });
    return {
      provider: this.name,
      model: this.model,
      explanation: res.reply,
      summary: res.reply.split('\n\n')[0]
    };
  }

  async generateTests(code, context = {}, options = {}) {
    const messages = [
      {
        role: 'system',
        content: 'Generate Otter test cases using valid Otter syntax. Output Otter test code blocks.'
      },
      { role: 'user', content: `Generate tests for this code:\n${code}\n\nContext:\n${context.formatted || ''}` }
    ];
    const res = await this.chat(messages, { ...options, maxTokens: 1000 });
    return {
      provider: this.name,
      model: this.model,
      testCode: res.reply
    };
  }

  async diagnose(diagnostics, sourceCode, context = {}, options = {}) {
    const messages = [
      {
        role: 'system',
        content: 'You are diagnosing Otter code diagnostics. Propose exact, reviewable fixes with rationale and a unified diff or patch.'
      },
      {
        role: 'user',
        content: `Diagnostics:\n${JSON.stringify(diagnostics, null, 2)}\n\nSource Code:\n${sourceCode}`
      }
    ];
    const res = await this.chat(messages, { ...options, maxTokens: 1000 });
    return {
      provider: this.name,
      model: this.model,
      summary: res.reply,
      patches: [{ description: 'AI proposed fix', rationale: res.reply, patchedCode: res.reply }]
    };
  }

  async synthesizeCode(goal, context = {}, options = {}) {
    const messages = [
      {
        role: 'system',
        content: 'You synthesize valid Otter code matching user requirements. Output clear Otter code.'
      },
      { role: 'user', content: `Synthesize Otter code for goal: ${goal}\nContext: ${context.formatted || ''}` }
    ];
    const res = await this.chat(messages, { ...options, maxTokens: 1000 });
    return {
      provider: this.name,
      model: this.model,
      code: res.reply,
      explanation: `Generated for: ${goal}`
    };
  }
}
