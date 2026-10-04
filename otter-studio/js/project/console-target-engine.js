// console-target-engine.js - Complete Console & Automation Target Engine for Otter
// Implements: CLI arguments, Options/flags helper, Environment API,
// stdin/stdout/stderr piping, Whole-program exit code contract, Signals,
// Cross-platform shell behavior, and Standalone CLI publishing.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';

// ============================================================================
// 1. & 2. CLI ARGUMENTS & OPTIONS/FLAGS HELPER
// ============================================================================
export class CliOptionsHelper {
  constructor(options = {}) {
    this.programName = options.name || 'otter-cli';
    this.description = options.description || 'Command Line Application built with Otter';
    this.version = options.version || '1.0.0';
    this.flagDefs = new Map();
    this.positionalDefs = [];
    this.examples = [];

    // Register built-in flags
    this.addFlag({ name: 'help', short: 'h', type: 'boolean', description: 'Display this help message' });
    this.addFlag({ name: 'version', short: 'V', type: 'boolean', description: 'Show version information' });
  }

  addFlag(def) {
    const name = def.name.toLowerCase();
    const short = def.short ? def.short.toLowerCase() : null;

    if (short) {
      for (const existing of this.flagDefs.values()) {
        if (existing.short === short) {
          existing.short = null;
        }
      }
    }

    this.flagDefs.set(name, {
      name,
      short,
      type: def.type || 'boolean', // 'boolean', 'string', 'number'
      default: def.default !== undefined ? def.default : (def.type === 'boolean' ? false : null),
      description: def.description || '',
      required: def.required === true
    });
    return this;
  }

  addPositional(def) {
    this.positionalDefs.push({
      name: def.name,
      description: def.description || '',
      required: def.required === true,
      default: def.default || null
    });
    return this;
  }

  addExample(cmd, description) {
    this.examples.push({ cmd, description });
    return this;
  }

  parse(rawArgs = []) {
    const args = Array.isArray(rawArgs) ? [...rawArgs] : [];
    const flags = {};
    const positionals = [];
    const errors = [];

    // Initialize defaults
    for (const [name, def] of this.flagDefs.entries()) {
      flags[name] = def.default;
    }

    let i = 0;
    let stopFlags = false;

    while (i < args.length) {
      const arg = args[i];

      if (stopFlags) {
        positionals.push(arg);
        i++;
        continue;
      }

      if (arg === '--') {
        stopFlags = true;
        i++;
        continue;
      }

      if (arg.startsWith('--')) {
        const eqIdx = arg.indexOf('=');
        let flagName = eqIdx > 0 ? arg.slice(2, eqIdx) : arg.slice(2);
        let flagVal = eqIdx > 0 ? arg.slice(eqIdx + 1) : null;
        flagName = flagName.toLowerCase();

        const def = this.flagDefs.get(flagName);
        if (!def) {
          errors.push(`Unknown option: "--${flagName}"`);
          i++;
          continue;
        }

        if (def.type === 'boolean') {
          flags[flagName] = flagVal !== null ? (flagVal === 'true' || flagVal === '1') : true;
        } else {
          if (flagVal === null) {
            i++;
            if (i >= args.length || args[i].startsWith('-')) {
              errors.push(`Option "--${flagName}" requires a value`);
              continue;
            }
            flagVal = args[i];
          }
          flags[flagName] = def.type === 'number' ? Number(flagVal) : flagVal;
        }
        i++;
        continue;
      }

      if (arg.startsWith('-') && arg.length > 1) {
        const shortChars = arg.slice(1).split('');
        for (let j = 0; j < shortChars.length; j++) {
          const char = shortChars[j].toLowerCase();
          const def = Array.from(this.flagDefs.values()).find(d => d.short === char);
          if (!def) {
            errors.push(`Unknown short option: "-${char}"`);
            continue;
          }

          if (def.type === 'boolean') {
            flags[def.name] = true;
          } else {
            // Option takes value
            const remainder = shortChars.slice(j + 1).join('');
            if (remainder.length > 0) {
              flags[def.name] = def.type === 'number' ? Number(remainder) : remainder;
              break;
            } else {
              i++;
              if (i >= args.length || args[i].startsWith('-')) {
                errors.push(`Option "-${char}" requires a value`);
                break;
              }
              const val = args[i];
              flags[def.name] = def.type === 'number' ? Number(val) : val;
              break;
            }
          }
        }
        i++;
        continue;
      }

      // Positional argument
      positionals.push(arg);
      i++;
    }

    // Required flags check
    for (const [name, def] of this.flagDefs.entries()) {
      if (def.required && (flags[name] === null || flags[name] === undefined)) {
        errors.push(`Missing required option: "--${name}"`);
      }
    }

    // Required positional check
    this.positionalDefs.forEach((def, idx) => {
      if (def.required && positionals[idx] === undefined) {
        errors.push(`Missing required argument: <${def.name}>`);
      }
    });

    return {
      flags,
      positionals,
      errors,
      ok: errors.length === 0,
      helpRequested: Boolean(flags.help),
      versionRequested: Boolean(flags.version)
    };
  }

  generateHelpText() {
    const posUsage = this.positionalDefs.map(p => p.required ? `<${p.name}>` : `[${p.name}]`).join(' ');
    let out = `${this.programName} v${this.version}\n${this.description}\n\n`;
    out += `USAGE:\n  ${this.programName} [OPTIONS] ${posUsage}\n\n`;

    if (this.positionalDefs.length > 0) {
      out += `ARGUMENTS:\n`;
      for (const pos of this.positionalDefs) {
        const req = pos.required ? '(required)' : '(optional)';
        out += `  <${pos.name.padEnd(16)}> ${pos.description} ${req}\n`;
      }
      out += `\n`;
    }

    out += `OPTIONS:\n`;
    for (const [name, def] of this.flagDefs.entries()) {
      const shortStr = def.short ? `-${def.short}, ` : '    ';
      const typeStr = def.type === 'boolean' ? '' : `<${def.type}>`;
      const flagFull = `${shortStr}--${name} ${typeStr}`.padEnd(28);
      out += `  ${flagFull} ${def.description}\n`;
    }

    if (this.examples.length > 0) {
      out += `\nEXAMPLES:\n`;
      for (const ex of this.examples) {
        out += `  # ${ex.description}\n  $ ${ex.cmd}\n\n`;
      }
    }

    return out;
  }
}

// ============================================================================
// 3. ENVIRONMENT API
// ============================================================================
export class EnvironmentManager {
  constructor(customEnv = null) {
    this.env = customEnv ? Object.assign({}, customEnv) : process.env;
  }

  get(key, defaultValue = null) {
    return this.env[key] !== undefined ? this.env[key] : defaultValue;
  }

  set(key, value) {
    this.env[key] = String(value);
    return this;
  }

  has(key) {
    return this.env[key] !== undefined;
  }

  delete(key) {
    delete this.env[key];
    return this;
  }

  list() {
    return Object.assign({}, this.env);
  }

  getPath() {
    return this.get('PATH') || this.get('Path') || '';
  }

  getHomeDir() {
    return this.get('USERPROFILE') || this.get('HOME') || '';
  }

  getTempDir() {
    return this.get('TEMP') || this.get('TMP') || '/tmp';
  }
}

// ============================================================================
// 4. STDIN / STDOUT / STDERR PIPING
// ============================================================================
export class StandardStreamsManager {
  constructor() {
    this.stdoutBuffer = [];
    this.stderrBuffer = [];
  }

  writeOut(text) {
    this.stdoutBuffer.push(String(text));
  }

  writeError(text) {
    this.stderrBuffer.push(String(text));
  }

  getStdout() {
    return this.stdoutBuffer.join('');
  }

  getStderr() {
    return this.stderrBuffer.join('');
  }

  clear() {
    this.stdoutBuffer = [];
    this.stderrBuffer = [];
  }
}

// ============================================================================
// 5. WHOLE-PROGRAM EXIT CODE CONTRACT
// ============================================================================
export const EXIT_CODES = {
  SUCCESS: 0,
  GENERAL_ERROR: 1,
  SYNTAX_ERROR: 2,
  INVALID_ARGUMENTS: 64, // sysexits.h EX_USAGE
  FILE_NOT_FOUND: 66,    // EX_NOINPUT
  UNAUTHORIZED: 77,      // EX_NOPERM
  INTERRUPTED: 130       // 128 + SIGINT (2)
};

export class ExitCodeContract {
  constructor() {
    this.exitCode = EXIT_CODES.SUCCESS;
    this.terminated = false;
  }

  setExitCode(code) {
    this.exitCode = Number(code) || 0;
  }

  exit(code = EXIT_CODES.SUCCESS) {
    this.exitCode = Number(code) || 0;
    this.terminated = true;
    return this.exitCode;
  }

  isSuccess() {
    return this.exitCode === EXIT_CODES.SUCCESS;
  }
}

// ============================================================================
// 6. PROCESS SIGNALS (SIGINT, SIGTERM, SIGHUP)
// ============================================================================
export class SignalManager {
  constructor() {
    this.handlers = new Map();
  }

  on(signal, handler) {
    const sig = signal.toUpperCase();
    if (!this.handlers.has(sig)) this.handlers.set(sig, []);
    this.handlers.get(sig).push(handler);
    return () => this.off(sig, handler);
  }

  off(signal, handler) {
    const sig = signal.toUpperCase();
    if (this.handlers.has(sig)) {
      const list = this.handlers.get(sig).filter(h => h !== handler);
      this.handlers.set(sig, list);
    }
  }

  emit(signal) {
    const sig = signal.toUpperCase();
    const list = this.handlers.get(sig) || [];
    let handled = false;
    for (const h of list) {
      try {
        h(sig);
        handled = true;
      } catch (err) {
        console.error(`[SignalManager]: Error in signal handler for ${sig}:`, err);
      }
    }
    return handled;
  }
}

// ============================================================================
// 7. CROSS-PLATFORM SHELL BEHAVIOR
// ============================================================================
export class CrossPlatformShell {
  static quoteArg(arg) {
    const str = String(arg);
    if (/^[A-Za-z0-9_\-\.\/\\:=]+$/.test(str)) {
      return str;
    }
    if (process.platform === 'win32') {
      return `"${str.replace(/"/g, '""')}"`;
    }
    return `'${str.replace(/'/g, "'\\''")}'`;
  }

  static formatCommand(cmd, args = []) {
    const quotedArgs = args.map(a => this.quoteArg(a));
    return [cmd, ...quotedArgs].join(' ');
  }

  static getShellCommand(commandString) {
    if (process.platform === 'win32') {
      return {
        shell: 'powershell.exe',
        args: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', commandString]
      };
    }
    return {
      shell: '/bin/sh',
      args: ['-c', commandString]
    };
  }
}

// ============================================================================
// 8. STANDALONE CLI PUBLISHING
// ============================================================================
export function publishStandaloneCli(options = {}) {
  const outputDir = options.outputDir;
  if (!outputDir) throw new Error('publishStandaloneCli requires an outputDir');

  const name = options.name || 'otter-cli-tool';
  const version = options.version || '1.0.0';
  const entryPoint = options.entryPoint || 'cli.ot';
  const scriptContent = options.code || `say "Hello from ${name} v${version}"\n`;

  fs.mkdirSync(outputDir, { recursive: true });
  const generatedFiles = [];

  // Write entry script
  fs.writeFileSync(path.join(outputDir, entryPoint), scriptContent, 'utf8');
  generatedFiles.push(entryPoint);

  // Write Windows launcher: run.cmd
  const runCmd = `@echo off
setlocal
set "DIR=%~dp0"
if exist "%DIR%..\\otter.cmd" (
    call "%DIR%..\\otter.cmd" run "%DIR%${entryPoint}" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DIR%otter.ps1" run "%DIR%${entryPoint}" %*
)
exit /b %ERRORLEVEL%
`;
  fs.writeFileSync(path.join(outputDir, 'run.cmd'), runCmd, 'utf8');
  generatedFiles.push('run.cmd');

  // Write POSIX launcher: run
  const runSh = `#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
if command -v otter >/dev/null 2>&1; then
    exec otter run "$DIR/${entryPoint}" "$@"
elif command -v pwsh >/dev/null 2>&1; then
    exec pwsh -NoProfile -File "$DIR/otter.ps1" run "$DIR/${entryPoint}" "$@"
else
    echo "Error: Otter runtime (otter or pwsh) required to run ${name}." >&2
    exit 1
fi
`;
  fs.writeFileSync(path.join(outputDir, 'run'), runSh, { encoding: 'utf8', mode: 0o755 });
  generatedFiles.push('run');

  // Package manifest: package.json / otter.cli.json
  const manifest = {
    name,
    version,
    target: 'console',
    bin: {
      [name]: './run'
    },
    scripts: {
      start: './run'
    },
    publishedAt: new Date().toISOString()
  };
  fs.writeFileSync(path.join(outputDir, 'otter.cli.json'), JSON.stringify(manifest, null, 2), 'utf8');
  generatedFiles.push('otter.cli.json');

  return {
    ok: true,
    name,
    version,
    outputDir,
    generatedFiles,
    totalFiles: generatedFiles.length
  };
}
