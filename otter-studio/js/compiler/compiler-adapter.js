import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs';
import path from 'node:path';

const execFileAsync = promisify(execFile);

/**
 * Authoritative Otter Compiler Adapter
 * Delegates ALL language syntax, grammar, and semantic checking directly to the real Otter toolchain (otter.ps1 check).
 * Contains ZERO JavaScript grammar approximations or hand-written AST rules.
 */
export class OtterCompilerAdapter {
  constructor(options = {}) {
    this.repoRoot = options.repoRoot || path.resolve(process.cwd(), '..');
    this.otterCli = options.otterCli || path.join(this.repoRoot, 'otter.ps1');
  }

  /**
   * Authoritatively checks Otter source code or file path using the real Otter compiler.
   * @param {string} sourceOrPath - Source code string or absolute/relative file path
   * @returns {Promise<{ ok: boolean, errors: Array<{ message: string, line?: number, column?: number, suggestion?: string, raw?: string }> }>}
   */
  async checkSource(sourceOrPath) {
    if (typeof sourceOrPath !== 'string') {
      return {
        ok: false,
        errors: [{ message: 'Source must be a non-null string' }]
      };
    }

    if (!sourceOrPath.trim()) {
      return { ok: true, errors: [] };
    }

    let targetFile = sourceOrPath;
    let isTemp = false;

    // If sourceOrPath is raw source code rather than an existing file path, write to scratch temp file
    if (!fs.existsSync(sourceOrPath)) {
      const scratchDir = path.join(this.repoRoot, 'scratch');
      if (!fs.existsSync(scratchDir)) {
        fs.mkdirSync(scratchDir, { recursive: true });
      }
      targetFile = path.join(scratchDir, `check_${Date.now()}_${Math.random().toString(36).slice(2, 8)}.ot`);
      fs.writeFileSync(targetFile, sourceOrPath, 'utf8');
      isTemp = true;
    }

    try {
      const { stdout, stderr } = await execFileAsync('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        this.otterCli,
        'check',
        targetFile
      ], { cwd: this.repoRoot });

      const output = stdout + '\n' + stderr;
      if (output.includes('is valid.')) {
        return { ok: true, errors: [] };
      }

      const errors = this.parseCompilerDiagnostics(output);
      return {
        ok: errors.length === 0,
        errors: errors.length > 0 ? errors : [{ message: output.trim() || 'Compiler check failed' }]
      };
    } catch (err) {
      const output = (err.stdout || '') + '\n' + (err.stderr || '') + '\n' + (err.message || '');
      const errors = this.parseCompilerDiagnostics(output);
      return {
        ok: false,
        errors: errors.length > 0 ? errors : [{ message: output.trim() || 'Otter compiler check failed' }]
      };
    } finally {
      if (isTemp) {
        try { fs.unlinkSync(targetFile); } catch {}
      }
    }
  }

  /**
   * Normalizes real Otter compiler diagnostic output into structured diagnostic objects.
   * @param {string} rawOutput
   */
  parseCompilerDiagnostics(rawOutput) {
    const errors = [];
    const blocks = rawOutput.split(/Otter (?:Syntax|Runtime|Parser) Error/i);

    for (const block of blocks) {
      const trimmed = block.trim();
      if (!trimmed) continue;

      let line = 1;
      let column = 1;
      let message = '';
      let suggestion = '';

      const lineMatch = trimmed.match(/Line\s+(d+):/i);
      if (lineMatch) {
        line = parseInt(lineMatch[1], 10);
      }

      const colMatch = trimmed.match(/\n\s*(\^)/);
      if (colMatch) {
        const lines = trimmed.split('\n');
        for (let i = 0; i < lines.length; i++) {
          if (lines[i].includes('^')) {
            column = lines[i].indexOf('^') + 1;
            break;
          }
        }
      }

      const tryMatch = trimmed.match(/Try:\s*\n\s*(.+)/i);
      if (tryMatch) {
        suggestion = tryMatch[1].trim();
      }

      const lines = trimmed.split('\n').map(l => l.trim()).filter(Boolean);
      const descLines = lines.filter(l => !l.startsWith('Line') && !l.includes('^') && !l.startsWith('Try:') && l !== suggestion);
      if (descLines.length > 0) {
        message = descLines[0];
      } else {
        message = trimmed.slice(0, 120);
      }

      if (message) {
        errors.push({
          line,
          column,
          message,
          suggestion,
          raw: trimmed
        });
      }
    }

    return errors;
  }
}
