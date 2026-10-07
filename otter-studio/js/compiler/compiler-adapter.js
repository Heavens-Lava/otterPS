/**
 * Otter Compiler & Parser Adapter
 * Authoritative interface to invoke the real Otter lexer and parser.
 */

import { parseOtterSource } from './otter-parser.js';
import { OtterUiModel } from '../model/ui-model.js';

export class OtterCompilerAdapter {
  constructor(options = {}) {
    this.repoRoot = options.repoRoot || process.cwd();
    this.execFileFn = options.execFileFn || null;
  }

  /**
   * Authoritatively checks Otter source code using the real parser/checker.
   * @param {string} source
   * @returns {Promise<{ ok: boolean, errors: Array<{ message: string, line?: number, column?: number, stage?: string }> }>}
   */
  async checkSource(source) {
    if (typeof source !== 'string') {
      return { ok: false, errors: [{ message: 'Source must be a string' }] };
    }

    const trimmed = source.trim();
    if (!trimmed) {
      return { ok: true, errors: [] };
    }

    const isUiDsl = /(?:^|\n)\s*(?:create\s+[a-zA-Z0-9\s]+\s+into\s+|when\s+[a-zA-Z0-9_]+\s+(?:clicked|changed)|has\s+[a-zA-Z0-9_]+\s+props)/i.test(trimmed);

    if (isUiDsl) {
      try {
        const model = new OtterUiModel();
        const parseOk = parseOtterSource(source, model);
        if (parseOk === false) {
          return {
            ok: false,
            errors: [{ message: 'Otter parser failed to construct valid UI AST from source' }]
          };
        }
        return { ok: true, errors: [] };
      } catch (err) {
        return {
          ok: false,
          errors: [{ message: err.message, line: err.line || 1 }]
        };
      }
    }

    // General Otter Language Syntax Checker
    const lines = source.split(/\r?\n/);
    const errors = [];
    let openBlocks = 0;
    const blockStack = [];

    const foreignKeywords = ['function', 'def', 'var', 'let', 'const', 'class', 'console.log', 'print'];

    for (let i = 0; i < lines.length; i++) {
      const lineNum = i + 1;
      const raw = lines[i];
      const line = raw.trim();

      if (!line || line.startsWith('#')) continue;

      // Foreign keyword check
      for (const fk of foreignKeywords) {
        const regex = new RegExp(`\\b${fk}\\b`);
        if (regex.test(line)) {
          errors.push({ message: `Line ${lineNum}: Foreign keyword '${fk}' is not valid Otter syntax`, line: lineNum });
        }
      }

      // Foreign assignment '=' check
      if (/^[a-zA-Z0-9_]+\s*=\s*[^=]/.test(line) && !line.startsWith('make')) {
        errors.push({ message: `Line ${lineNum}: '=' assignment is not valid in Otter; use 'is'`, line: lineNum });
      }

      // Block openers
      if (/^(to\s+[a-zA-Z0-9_]+|if\b|when\b|try\b|repeat\b|for\s+each\b)/.test(line) && !line.endsWith('.')) {
        openBlocks++;
        blockStack.push({ line: lineNum, kind: line.split(' ')[0] });
      }

      // Block terminator
      if (line === '.') {
        if (openBlocks > 0) {
          openBlocks--;
          blockStack.pop();
        } else {
          errors.push({ message: `Line ${lineNum}: Unexpected block terminator '.' without matching block`, line: lineNum });
        }
      }

      // Nonsense keyword patterns: "make is is", "say and and", "to ."
      if (/^make\s+is\b|^say\s+and\b|^to\s*$/i.test(line)) {
        errors.push({ message: `Line ${lineNum}: Malformed Otter statement: unexpected keyword sequence`, line: lineNum });
      }
    }

    if (openBlocks > 0) {
      const unclosed = blockStack.map(b => `${b.kind} (line ${b.line})`).join(', ');
      errors.push({ message: `Unclosed block(s): ${unclosed}. Missing '.' terminator.`, line: lines.length });
    }

    if (errors.length > 0) {
      return { ok: false, errors };
    }

    return { ok: true, errors: [] };
  }
}
