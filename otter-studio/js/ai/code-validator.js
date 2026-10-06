/**
 * Otter Studio AI Code & Syntax Validator
 * Verifies that AI-generated Otter code conforms to valid Otter grammar and conventions.
 */

export class OtterCodeValidator {
  /**
   * Validates generated Otter source text
   * @param {string} source
   * @returns {{ isValid: boolean, errors: string[], suggestions: string[], normalized: string }}
   */
  static validate(source) {
    if (typeof source !== 'string' || !source.trim()) {
      return { isValid: false, errors: ['Generated code is empty.'], suggestions: [], normalized: '' };
    }

    const errors = [];
    const suggestions = [];

    // Strip markdown code fences if present (e.g. ```otter ... ```)
    let cleaned = source.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replace(/^```[a-zA-Z0-9_-]*\n?/, '').replace(/\n?```$/, '').trim();
    }

    const lines = cleaned.split(/\r?\n/);
    let openBlocks = 0;
    const blockStack = [];

    // Check for foreign keywords that indicate model hallucinated Python/JS/C#
    const forbiddenPatterns = [
      { regex: /\bfunction\s+[a-zA-Z0-9_]+\s*\(/, name: 'JavaScript function declaration' },
      { regex: /\bdef\s+[a-zA-Z0-9_]+\s*\(/, name: 'Python def declaration' },
      { regex: /\bclass\s+[a-zA-Z0-9_]+/, name: 'class keyword' },
      { regex: /\b(const|let|var)\s+[a-zA-Z0-9_]+\s*=/, name: 'JS variable declaration (use "name is value")' },
      { regex: /\bconsole\.log\s*\(/, name: 'console.log' },
      { regex: /\bprint\s*\(/, name: 'Python print() (use say in Otter)' }
    ];

    for (let idx = 0; idx < lines.length; idx++) {
      const lineNum = idx + 1;
      const rawLine = lines[idx];
      const trimmed = rawLine.trim();

      if (!trimmed || trimmed.startsWith('#')) continue;

      // Check forbidden patterns
      for (const pat of forbiddenPatterns) {
        if (pat.regex.test(trimmed)) {
          errors.push(`Line ${lineNum}: Contains non-Otter syntax: ${pat.name}`);
          suggestions.push(`Replace foreign syntax on line ${lineNum} with standard Otter keywords (e.g. "to", "is", "say").`);
        }
      }

      // Check equals assignment without 'is' (e.g., 'x = 10')
      if (/^[a-zA-Z0-9_]+\s*=\s*[^=]/.test(trimmed) && !trimmed.startsWith('make')) {
        errors.push(`Line ${lineNum}: Uses '=' for assignment instead of Otter 'is'.`);
        suggestions.push(`Change '=' to 'is' on line ${lineNum}.`);
      }

      // Check block openings
      if (/^(to|when|if|try|repeat|for\s+each)\b/.test(trimmed) && !trimmed.endsWith('.')) {
        openBlocks++;
        blockStack.push({ line: lineNum, kind: trimmed.split(' ')[0] });
      }

      // Check block terminators
      if (trimmed === '.') {
        if (openBlocks > 0) {
          openBlocks--;
          blockStack.pop();
        } else {
          errors.push(`Line ${lineNum}: Unexpected block terminator '.' without matching open block.`);
        }
      }
    }

    if (openBlocks > 0) {
      const unclosed = blockStack.map(b => `${b.kind} (line ${b.line})`).join(', ');
      errors.push(`Unclosed Otter block(s): ${unclosed}. Missing '.' terminator.`);
      suggestions.push('Add "." to close the open block(s).');
    }

    return {
      isValid: errors.length === 0,
      errors,
      suggestions,
      normalized: cleaned
    };
  }

  /**
   * Attempts a deterministic single-pass local repair on common minor syntax issues
   */
  static attemptLocalRepair(source) {
    const val = this.validate(source);
    if (val.isValid) return { repaired: true, source: val.normalized };

    let cleaned = val.normalized;
    const lines = cleaned.split(/\r?\n/);
    const repairedLines = [];
    let openBlocks = 0;

    for (let line of lines) {
      let trimmed = line.trim();
      // Auto-convert simple 'x = y' to 'x is y'
      if (/^[a-zA-Z0-9_]+\s*=\s*[^=]/.test(trimmed)) {
        line = line.replace(/=/, 'is');
        trimmed = line.trim();
      }
      if (/^(to|when|if|try|repeat|for\s+each)\b/.test(trimmed) && !trimmed.endsWith('.')) {
        openBlocks++;
      }
      if (trimmed === '.') {
        if (openBlocks > 0) openBlocks--;
      }
      repairedLines.push(line);
    }

    // Add missing block closures if needed
    while (openBlocks > 0) {
      repairedLines.push('.');
      openBlocks--;
    }

    const finalSource = repairedLines.join('\n');
    const finalVal = this.validate(finalSource);
    return {
      repaired: finalVal.isValid,
      source: finalSource,
      validation: finalVal
    };
  }
}
