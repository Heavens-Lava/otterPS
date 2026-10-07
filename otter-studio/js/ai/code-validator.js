/**
 * Otter Studio AI Code & Syntax Validator
 * Uses lightweight preflight heuristics while strictly deferring to the real Otter compiler
 * as the ultimate authority for language correctness.
 */

import { OtterCompilerAdapter } from '../compiler/compiler-adapter.js';

export class OtterCodeValidator {
  /**
   * Lightweight preflight heuristic lint
   * @param {string} source
   */
  static preflightLint(source) {
    if (typeof source !== 'string' || !source.trim()) {
      return { isValid: false, errors: ['Generated code is empty.'], suggestions: [], normalized: '' };
    }

    const errors = [];
    const suggestions = [];

    let cleaned = source.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replace(/^```[a-zA-Z0-9_-]*\n?/, '').replace(/\n?```$/, '').trim();
    }

    const lines = cleaned.split(/\r?\n/);
    let openBlocks = 0;
    const blockStack = [];

    const forbiddenPatterns = [
      { regex: /\bfunction\s+[a-zA-Z0-9_]+\s*\(/, name: 'JavaScript function declaration' },
      { regex: /\bdef\s+[a-zA-Z0-9_]+\s*\(/, name: 'Python def declaration' },
      { regex: /\bclass\s+[a-zA-Z0-9_]+/, name: 'class keyword' },
      { regex: /\b(const|let|var)\s+[a-zA-Z0-9_]+\s*=/, name: 'JS variable declaration' },
      { regex: /\bconsole\.log\s*\(/, name: 'console.log' },
      { regex: /\bprint\s*\(/, name: 'Python print()' }
    ];

    for (let idx = 0; idx < lines.length; idx++) {
      const lineNum = idx + 1;
      const rawLine = lines[idx];
      const trimmed = rawLine.trim();

      if (!trimmed || trimmed.startsWith('#')) continue;

      for (const pat of forbiddenPatterns) {
        if (pat.regex.test(trimmed)) {
          errors.push(`Line ${lineNum}: Contains non-Otter syntax: ${pat.name}`);
          suggestions.push(`Replace foreign syntax on line ${lineNum} with standard Otter keywords.`);
        }
      }

      if (/^[a-zA-Z0-9_]+\s*=\s*[^=]/.test(trimmed) && !trimmed.startsWith('make')) {
        errors.push(`Line ${lineNum}: Uses '=' for assignment instead of Otter 'is'.`);
        suggestions.push(`Change '=' to 'is' on line ${lineNum}.`);
      }

      if (/^(to|when|if|try|repeat|for\s+each)\b/.test(trimmed) && !trimmed.endsWith('.')) {
        openBlocks++;
        blockStack.push({ line: lineNum, kind: trimmed.split(' ')[0] });
      }

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
   * Authoritative validation: runs preflight followed by real compiler check.
   * If the real compiler certifies the code, compiler authority supersedes any preflight warning.
   * @param {string} source
   * @param {OtterCompilerAdapter} [compilerAdapter]
   * @param {object} [options]
   */
  static async validate(source, compilerAdapter = null, options = {}) {
    const preflight = this.preflightLint(source);
    const adapter = compilerAdapter || new OtterCompilerAdapter({ projectRoot: options.projectRoot });

    // Check with the real compiler
    const compilerResult = await adapter.checkSource(preflight.normalized || source, options);

    if (compilerResult.ok) {
      // Real compiler accepted the source - authoritative PASS
      return {
        isValid: true,
        errors: [],
        diagnostics: [],
        suggestions: preflight.suggestions,
        normalized: preflight.normalized,
        compilerValidated: true
      };
    } else {
      // Real compiler rejected the source - authoritative FAIL
      const compilerErrors = compilerResult.errors.map(e => `Line ${e.line || 1}: ${e.message}`);
      return {
        isValid: false,
        errors: compilerErrors.length > 0 ? compilerErrors : preflight.errors,
        diagnostics: compilerResult.errors,
        suggestions: compilerResult.errors.map(e => e.suggestion).filter(Boolean).concat(preflight.suggestions),
        normalized: preflight.normalized,
        compilerValidated: true
      };
    }
  }

  /**
   * Attempts single-pass local repair
   */
  static attemptLocalRepair(source) {
    const pre = this.preflightLint(source);
    if (pre.isValid) return { repaired: true, source: pre.normalized };

    let cleaned = pre.normalized;
    const lines = cleaned.split(/\r?\n/);
    const repairedLines = [];
    let openBlocks = 0;

    for (let line of lines) {
      let trimmed = line.trim();
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

    while (openBlocks > 0) {
      repairedLines.push('.');
      openBlocks--;
    }

    const finalSource = repairedLines.join('\n');
    const finalPre = this.preflightLint(finalSource);
    return {
      repaired: finalPre.isValid,
      source: finalSource,
      validation: finalPre
    };
  }
}
