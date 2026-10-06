import { AiProvider } from '../provider-base.js';
import { OtterAIAssistant } from '../ai-assistant-engine.js';

export class OfflineHeuristicProvider extends AiProvider {
  constructor(config = {}) {
    super(config);
    this.name = 'offline-heuristic';
    this.displayName = 'Offline Assistant (Templates)';
    this.engine = new OtterAIAssistant();
  }

  isConfigured() {
    return true; // Always available offline
  }

  getStatus() {
    return {
      status: 'offline',
      message: 'Offline template engine active. Fast heuristic fallback; does not use external models.',
      provider: this.name,
      displayName: this.displayName
    };
  }

  async testConnection() {
    return {
      ok: true,
      provider: this.name,
      status: 'offline',
      message: 'Offline heuristic engine is operational.'
    };
  }

  async chat(messages, options = {}) {
    const lastUserMsg = [...messages].reverse().find(m => m.role === 'user')?.content || '';
    const response = this.engine.chat(lastUserMsg, options.context || {});
    return {
      provider: this.name,
      displayName: this.displayName,
      reply: response.reply,
      suggestedActions: response.suggestedActions || [],
      contextUsed: response.contextUsed || {}
    };
  }

  async complete(prompt, context = {}, options = {}) {
    const code = this.engine.generateOtterCode(prompt, context);
    return {
      provider: this.name,
      displayName: this.displayName,
      code,
      explanation: 'Generated via template heuristic'
    };
  }

  async explain(code, context = {}, options = {}) {
    const explanation = this.engine.explainCode(code);
    return {
      provider: this.name,
      displayName: this.displayName,
      explanation,
      summary: explanation.split('\n\n')[0]
    };
  }

  async generateTests(code, context = {}, options = {}) {
    const moduleName = context.moduleName || 'module';
    const testCode = this.engine.generateTestSuites(code, moduleName);
    return {
      provider: this.name,
      displayName: this.displayName,
      testCode
    };
  }

  async diagnose(diagnostics, sourceCode, context = {}, options = {}) {
    const fixes = this.engine.analyzeDiagnosticsAndSuggestFixes(diagnostics, sourceCode);
    return {
      provider: this.name,
      displayName: this.displayName,
      patches: fixes.map(f => ({
        line: f.line,
        explanation: f.explanation,
        fixedLine: f.fixedLine,
        canApplyAutomatically: f.canApplyAutomatically
      })),
      summary: fixes.length > 0 ? `Found ${fixes.length} potential fix(es).` : 'No automatic fixes found.'
    };
  }

  async synthesizeCode(goal, context = {}, options = {}) {
    const code = this.engine.generateOtterCode(goal, context);
    return {
      provider: this.name,
      displayName: this.displayName,
      code,
      explanation: `Generated for: ${goal}`
    };
  }
}
