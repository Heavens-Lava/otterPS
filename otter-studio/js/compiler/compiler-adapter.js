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

    if (!source.trim()) {
      return { ok: true, errors: [] };
    }

    try {
      const model = new OtterUiModel();
      const parseOk = parseOtterSource(source, model);
      if (parseOk === false) {
        return {
          ok: false,
          errors: [{ message: 'Otter parser failed to construct valid AST from source' }]
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
}
