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
    this.projectRoot = options.projectRoot || this.repoRoot;
  }

  /**
   * Authoritatively checks Otter source code or file path using the real Otter compiler.
   * @param {string} sourceOrPath - Source code string or absolute/relative file path
   * @param {object} [options] - Optional execution options (projectRoot, workingDir)
   * @returns {Promise<{ ok: boolean, errors: Array<{ message: string, line?: number, column?: number, suggestion?: string, sourceLine?: string, raw?: string }> }>}
   */
  async checkSource(sourceOrPath, options = {}) {
    if (typeof sourceOrPath !== 'string') {
      return {
        ok: false,
        errors: [{ message: 'Source must be a non-null string' }]
      };
    }

    if (!sourceOrPath.trim()) {
      return { ok: true, errors: [] };
    }

    const workingDir = options.projectRoot || options.workingDir || this.projectRoot || this.repoRoot;
    let targetFile = sourceOrPath;
    let isTemp = false;

    // Treat as an existing file path only if single-line and exists on disk as a file
    const isSingleLine = !sourceOrPath.includes('\n') && !sourceOrPath.includes('\r');
    const isFilePath = isSingleLine && (sourceOrPath.endsWith('.ot') || fs.existsSync(sourceOrPath)) && fs.existsSync(sourceOrPath) && fs.statSync(sourceOrPath).isFile();

    if (!isFilePath) {
      // Write temporary file in the project working directory so relative module imports (use "module.ot") resolve cleanly
      const targetDir = fs.existsSync(workingDir) ? workingDir : path.join(this.repoRoot, 'scratch');
      if (!fs.existsSync(targetDir)) {
        fs.mkdirSync(targetDir, { recursive: true });
      }
      targetFile = path.join(targetDir, `.otter-check-temp-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.ot`);
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
      ], { cwd: fs.existsSync(workingDir) ? workingDir : this.repoRoot });

      const output = (stdout || '') + '\n' + (stderr || '');
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
    const blocks = rawOutput.split(/Otter\s+(?:Syntax|Runtime|Parser|Lexer)?\s*Error/i);

    for (const block of blocks) {
      const trimmed = block.trim();
      if (!trimmed || trimmed.startsWith('Found ') || trimmed.includes('is valid.')) continue;

      let line = 1;
      let column = 1;
      let message = '';
      let suggestion = '';
      let sourceLine = '';

      // Match Line <digits>:
      const lineMatch = trimmed.match(/Line\s+(\d+):/i);
      if (lineMatch) {
        line = parseInt(lineMatch[1], 10);
      }

      const rawLines = trimmed.split(/\r?\n/);
      let codeLineIdx = -1;
      let caretLineIdx = -1;
      let tryLineIdx = -1;

      for (let i = 0; i < rawLines.length; i++) {
        const l = rawLines[i];
        if (/Line\s+\d+:/i.test(l)) {
          codeLineIdx = i + 1;
        }
        if (l.includes('^') && caretLineIdx === -1 && codeLineIdx !== -1 && i >= codeLineIdx) {
          caretLineIdx = i;
        }
        if (/^Try:/i.test(l.trim())) {
          tryLineIdx = i;
        }
      }

      if (codeLineIdx !== -1 && codeLineIdx < rawLines.length) {
        sourceLine = rawLines[codeLineIdx].trim();
      }

      if (caretLineIdx !== -1) {
        const caretLine = rawLines[caretLineIdx];
        const caretIndex = caretLine.indexOf('^');
        const codeLine = (codeLineIdx !== -1 && codeLineIdx < rawLines.length) ? rawLines[codeLineIdx] : '';
        const leadingSpaces = codeLine.search(/\S/);
        column = Math.max(1, caretIndex - (leadingSpaces >= 0 ? leadingSpaces : 4) + 1);
      }

      if (tryLineIdx !== -1 && tryLineIdx + 1 < rawLines.length) {
        suggestion = rawLines[tryLineIdx + 1].trim();
      }

      const msgStart = caretLineIdx !== -1 ? caretLineIdx + 1 : (codeLineIdx !== -1 ? codeLineIdx + 1 : 0);
      const msgEnd = tryLineIdx !== -1 ? tryLineIdx : rawLines.length;

      const explanationLines = [];
      for (let i = msgStart; i < msgEnd; i++) {
        const t = rawLines[i].trim();
        if (t && !t.startsWith('Line') && !t.startsWith('Found ') && !t.startsWith('Try:')) {
          explanationLines.push(t);
        }
      }

      if (explanationLines.length > 0) {
        message = explanationLines.join(' ');
      } else if (sourceLine) {
        message = `Syntax error near '${sourceLine}'`;
      } else {
        message = trimmed.slice(0, 120);
      }

      if (message) {
        const isDuplicate = errors.some(e => e.line === line && e.column === column && e.message === message);
        if (!isDuplicate) {
          errors.push({
            line,
            column,
            message,
            suggestion,
            sourceLine
          });
        }
      }
    }

    return errors;
  }
}
