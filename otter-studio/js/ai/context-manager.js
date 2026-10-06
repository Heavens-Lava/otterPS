/**
 * Otter Studio Controlled Context Manager
 * Builds bounded, sanitized IDE context for AI prompts without dumping giant workspaces
 * or leaking credentials.
 */
export class ContextManager {
  constructor(options = {}) {
    this.maxContextChars = options.maxContextChars || 6000;
  }

  /**
   * Sanitizes text to redact potential API keys or tokens before sending to AI or logging
   */
  sanitizeSecrets(text) {
    if (typeof text !== 'string') return text;
    // Redact common API key patterns (OpenAI, Anthropic, generic bearer tokens)
    return text
      .replace(/sk-[a-zA-Z0-9_-]{20,}/g, '[REDACTED_API_KEY]')
      .replace(/ant-[a-zA-Z0-9_-]{20,}/g, '[REDACTED_API_KEY]')
      .replace(/bearer\s+[a-zA-Z0-9_.-]{20,}/gi, 'Bearer [REDACTED_TOKEN]')
      .replace(/api[_-]?key\s*[:=]\s*["'][^"']+["']/gi, 'apiKey: "[REDACTED]"');
  }

  /**
   * Builds bounded context from provided IDE inputs
   */
  buildContext(input = {}) {
    const {
      activeFile = null,
      selectedCode = null,
      sourceCode = null,
      diagnostics = [],
      openFiles = [],
      projectManifest = null,
      compilerErrors = [],
      testFailures = [],
      languageDocs = null,
    } = input;

    const sections = [];
    let currentLength = 0;

    const addSection = (title, content) => {
      if (!content) return;
      const sanitized = this.sanitizeSecrets(typeof content === 'string' ? content : JSON.stringify(content, null, 2));
      const sectionText = `### ${title}\n${sanitized}\n`;
      if (currentLength + sectionText.length <= this.maxContextChars) {
        sections.push(sectionText);
        currentLength += sectionText.length;
      } else {
        const remaining = Math.max(0, this.maxContextChars - currentLength - title.length - 20);
        if (remaining > 50) {
          sections.push(`### ${title}\n${sanitized.slice(0, remaining)}\n... [truncated for token budget]\n`);
          currentLength += remaining;
        }
      }
    };

    if (activeFile) {
      addSection('Active File', activeFile);
    }

    if (selectedCode) {
      addSection('Selected Code', selectedCode);
    } else if (sourceCode) {
      addSection('Current Source Code', sourceCode);
    }

    if (diagnostics && diagnostics.length > 0) {
      addSection('Active Diagnostics', diagnostics.slice(0, 5));
    }

    if (compilerErrors && compilerErrors.length > 0) {
      addSection('Compiler / Build Errors', compilerErrors.slice(0, 3));
    }

    if (testFailures && testFailures.length > 0) {
      addSection('Test Failures', testFailures.slice(0, 3));
    }

    if (projectManifest) {
      addSection('Project Manifest', projectManifest);
    }

    if (openFiles && openFiles.length > 0) {
      addSection('Open Files', openFiles.map(f => typeof f === 'string' ? f : f.name || f.path).join(', '));
    }

    if (languageDocs) {
      addSection('Relevant Language Notes', languageDocs);
    }

    return {
      formatted: sections.join('\n'),
      sectionCount: sections.length,
      characterCount: currentLength,
      budget: this.maxContextChars
    };
  }
}
