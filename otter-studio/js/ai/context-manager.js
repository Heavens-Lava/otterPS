/**
 * Otter Studio Controlled Context Manager
 * Builds prioritized, bounded, sanitized IDE context for AI prompts.
 * Prioritization order:
 * 1. Selected code / cursor snippet (highest)
 * 2. Surrounding function/block
 * 3. Active diagnostics
 * 4. Active file
 * 5. Relevant symbols & project manifest
 * 6. Conversation history
 */
export class ContextManager {
  constructor(options = {}) {
    this.maxContextChars = options.maxContextChars || 12000;
  }

  setBudget(chars) {
    if (typeof chars === 'number' && chars > 500) {
      this.maxContextChars = chars;
    }
  }

  /**
   * Sanitizes text to redact potential API keys or tokens before sending to AI or logging
   */
  sanitizeSecrets(text) {
    if (typeof text !== 'string') return text;
    return text
      .replace(/sk-[a-zA-Z0-9_-]{20,}/g, '[REDACTED_API_KEY]')
      .replace(/ant-[a-zA-Z0-9_-]{20,}/g, '[REDACTED_API_KEY]')
      .replace(/bearer\s+[a-zA-Z0-9_.-]{20,}/gi, 'Bearer [REDACTED_TOKEN]')
      .replace(/api[_-]?key\s*[:=]\s*["'][^"']+["']/gi, 'apiKey: "[REDACTED]"');
  }

  /**
   * Builds bounded, prioritized context from provided IDE inputs
   */
  buildContext(input = {}, budgetOverride = null) {
    const budget = budgetOverride || this.maxContextChars;
    const {
      selectedCode = null,
      surroundingBlock = null,
      diagnostics = [],
      compilerErrors = [],
      testFailures = [],
      activeFile = null,
      sourceCode = null,
      symbols = [],
      projectManifest = null,
      openFiles = [],
      languageDocs = null,
      conversationHistory = []
    } = input;

    // Prioritized candidate list: [title, content, priorityWeight]
    const candidates = [];

    // Priority 1: Selected code or active cursor block
    if (selectedCode && selectedCode.trim()) {
      candidates.push({ title: 'Selected Code', content: selectedCode });
    }
    if (surroundingBlock && surroundingBlock.trim()) {
      candidates.push({ title: 'Surrounding Function / Block', content: surroundingBlock });
    }

    // Priority 2: Diagnostics & errors
    if (diagnostics && diagnostics.length > 0) {
      candidates.push({ title: 'Active Diagnostics', content: diagnostics.slice(0, 5) });
    }
    if (compilerErrors && compilerErrors.length > 0) {
      candidates.push({ title: 'Compiler / Build Errors', content: compilerErrors.slice(0, 3) });
    }
    if (testFailures && testFailures.length > 0) {
      candidates.push({ title: 'Test Failures', content: testFailures.slice(0, 3) });
    }

    // Priority 3: Active file and source
    if (activeFile) {
      candidates.push({ title: 'Active File Path', content: activeFile });
    }
    if (sourceCode && sourceCode.trim() && !selectedCode) {
      candidates.push({ title: 'Current Source Code', content: sourceCode });
    }

    // Priority 4: Symbols & Project manifest
    if (symbols && symbols.length > 0) {
      candidates.push({ title: 'Relevant Symbols', content: symbols.slice(0, 10).map(s => s.name || s).join(', ') });
    }
    if (projectManifest) {
      candidates.push({ title: 'Project Manifest', content: projectManifest });
    }
    if (openFiles && openFiles.length > 0) {
      candidates.push({ title: 'Open Files in Workspace', content: openFiles.map(f => typeof f === 'string' ? f : f.name || f.path).join(', ') });
    }
    if (languageDocs) {
      candidates.push({ title: 'Language Notes', content: languageDocs });
    }

    // Priority 5: Bounded recent conversation context
    if (conversationHistory && conversationHistory.length > 0) {
      const recent = conversationHistory.slice(-4).map(m => `[${m.role}]: ${m.content}`).join('\n');
      candidates.push({ title: 'Recent Conversation', content: recent });
    }

    const sections = [];
    let currentLength = 0;

    for (const item of candidates) {
      if (!item.content) continue;
      const rawText = typeof item.content === 'string' ? item.content : JSON.stringify(item.content, null, 2);
      const sanitized = this.sanitizeSecrets(rawText);
      const sectionText = `### ${item.title}\n${sanitized}\n`;

      if (currentLength + sectionText.length <= budget) {
        sections.push(sectionText);
        currentLength += sectionText.length;
      } else {
        const remaining = Math.max(0, budget - currentLength - item.title.length - 25);
        if (remaining > 60) {
          sections.push(`### ${item.title}\n${sanitized.slice(0, remaining)}\n... [truncated for context budget]\n`);
          currentLength += remaining;
        }
        break; // Stop adding lower priority sections once budget is exhausted
      }
    }

    return {
      formatted: sections.join('\n'),
      sectionCount: sections.length,
      characterCount: currentLength,
      budget
    };
  }
}
