// console-automation.test.mjs - Comprehensive Test Suite for Section 15: Console / Automation Target
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  CliOptionsHelper,
  EnvironmentManager,
  StandardStreamsManager,
  ExitCodeContract,
  EXIT_CODES,
  SignalManager,
  CrossPlatformShell,
  publishStandaloneCli
} from '../js/project/console-target-engine.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');

// ----------------------------------------------------------------------------
// 1. CLI Arguments & Positional Parsing (Section 15.5)
// ----------------------------------------------------------------------------
test('Section 15.5: CLI Positional Arguments Parsing', () => {
  const cli = new CliOptionsHelper({ name: 'otter-copy', description: 'Copy files' });
  cli.addPositional({ name: 'source', required: true, description: 'Source file' });
  cli.addPositional({ name: 'dest', required: true, description: 'Destination file' });

  const res = cli.parse(['input.txt', 'output.txt']);
  assert.equal(res.ok, true);
  assert.equal(res.positionals[0], 'input.txt');
  assert.equal(res.positionals[1], 'output.txt');

  // Missing required positional
  const badRes = cli.parse(['only-source.txt']);
  assert.equal(badRes.ok, false);
  assert.ok(badRes.errors.some(e => e.includes('Missing required argument: <dest>')));
});

// ----------------------------------------------------------------------------
// 2. Options / Flags Helper (Section 15.6)
// ----------------------------------------------------------------------------
test('Section 15.6: CLI Options and Flags Parsing', () => {
  const cli = new CliOptionsHelper({ name: 'otter-build', version: '2.1.0' });
  cli.addFlag({ name: 'verbose', short: 'v', type: 'boolean', description: 'Verbose logging' });
  cli.addFlag({ name: 'port', short: 'p', type: 'number', default: 3000, description: 'Port number' });
  cli.addFlag({ name: 'config', short: 'c', type: 'string', required: true, description: 'Config file path' });

  // Parsing long and short flags
  const parsed = cli.parse(['-v', '-p', '8080', '--config=settings.json', 'extra-arg']);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.flags.verbose, true);
  assert.equal(parsed.flags.port, 8080);
  assert.equal(parsed.flags.config, 'settings.json');
  assert.equal(parsed.positionals[0], 'extra-arg');

  // Help output generation
  const help = cli.generateHelpText();
  assert.match(help, /otter-build v2\.1\.0/);
  assert.match(help, /-v, --verbose/);
  assert.match(help, /-p, --port/);
  assert.match(help, /--help/);
});

// ----------------------------------------------------------------------------
// 3. Environment API (Section 15.7)
// ----------------------------------------------------------------------------
test('Section 15.7: Environment Variables API', () => {
  const env = new EnvironmentManager({
    OTTER_HOME: '/opt/otter',
    DEBUG: '1',
    PATH: '/usr/bin:/bin'
  });

  assert.equal(env.has('OTTER_HOME'), true);
  assert.equal(env.get('OTTER_HOME'), '/opt/otter');
  assert.equal(env.get('NON_EXISTENT', 'default_val'), 'default_val');

  env.set('CUSTOM_VAR', '42');
  assert.equal(env.get('CUSTOM_VAR'), '42');

  env.delete('DEBUG');
  assert.equal(env.has('DEBUG'), false);
  assert.equal(env.getPath(), '/usr/bin:/bin');
});

// ----------------------------------------------------------------------------
// 4. Stdin / Stdout / Stderr Piping (Section 15.8)
// ----------------------------------------------------------------------------
test('Section 15.8: Standard Streams Buffering and Piping', () => {
  const streams = new StandardStreamsManager();
  streams.writeOut('Hello Otter Output\n');
  streams.writeError('Warning: Low memory\n');

  assert.equal(streams.getStdout(), 'Hello Otter Output\n');
  assert.equal(streams.getStderr(), 'Warning: Low memory\n');

  streams.clear();
  assert.equal(streams.getStdout(), '');
  assert.equal(streams.getStderr(), '');
});

// ----------------------------------------------------------------------------
// 5. Whole-Program Exit Code Contract (Section 15.9)
// ----------------------------------------------------------------------------
test('Section 15.9: Whole-Program Exit Code Contract', () => {
  const exitContract = new ExitCodeContract();
  assert.equal(exitContract.isSuccess(), true);
  assert.equal(exitContract.exitCode, EXIT_CODES.SUCCESS);

  exitContract.setExitCode(EXIT_CODES.INVALID_ARGUMENTS);
  assert.equal(exitContract.exitCode, 64);
  assert.equal(exitContract.isSuccess(), false);

  exitContract.exit(EXIT_CODES.GENERAL_ERROR);
  assert.equal(exitContract.exitCode, 1);
  assert.equal(exitContract.terminated, true);
});

// ----------------------------------------------------------------------------
// 6. Signals Engine (SIGINT, SIGTERM, SIGHUP) (Section 15.10)
// ----------------------------------------------------------------------------
test('Section 15.10: Process Signal Handling and Dispatch', () => {
  const sig = new SignalManager();
  let intFired = false;
  let termFired = false;

  const unsubscribe = sig.on('SIGINT', (s) => {
    intFired = true;
    assert.equal(s, 'SIGINT');
  });

  sig.on('SIGTERM', () => {
    termFired = true;
  });

  const handled = sig.emit('SIGINT');
  assert.equal(handled, true);
  assert.equal(intFired, true);
  assert.equal(termFired, false);

  unsubscribe();
  intFired = false;
  sig.emit('SIGINT');
  assert.equal(intFired, false); // handler was unsubscribed
});

// ----------------------------------------------------------------------------
// 7. Cross-Platform Shell Behavior (Section 15.11)
// ----------------------------------------------------------------------------
test('Section 15.11: Cross-Platform Shell Formatting and Escaping', () => {
  const safeCmd = CrossPlatformShell.formatCommand('otter', ['run', 'path with spaces/main.ot', '--flag']);
  assert.match(safeCmd, /otter run/);
  assert.match(safeCmd, /path with spaces/);

  const shellCmd = CrossPlatformShell.getShellCommand('echo 123');
  assert.ok(shellCmd.shell);
  assert.ok(Array.isArray(shellCmd.args));
});

// ----------------------------------------------------------------------------
// 8. Standalone CLI Publishing Pipeline (Section 15.12)
// ----------------------------------------------------------------------------
test('Section 15.12: Standalone CLI Distribution Packaging', () => {
  const testOutDir = path.join(REPO_ROOT, 'publish', 'test-console-cli');

  try {
    const res = publishStandaloneCli({
      outputDir: testOutDir,
      name: 'my-cli-tool',
      version: '1.2.0',
      entryPoint: 'cli.ot',
      code: 'say "CLI Test Execution"\n'
    });

    assert.equal(res.ok, true);
    assert.ok(fs.existsSync(path.join(testOutDir, 'cli.ot')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'run.cmd')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'run')));
    assert.ok(fs.existsSync(path.join(testOutDir, 'otter.cli.json')));

    const runCmdContent = fs.readFileSync(path.join(testOutDir, 'run.cmd'), 'utf8');
    assert.match(runCmdContent, /%ERRORLEVEL%/);
    assert.match(runCmdContent, /cli\.ot/);

    const runShContent = fs.readFileSync(path.join(testOutDir, 'run'), 'utf8');
    assert.match(runShContent, /#!\/bin\/sh/);
    assert.match(runShContent, /cli\.ot/);
  } finally {
    if (fs.existsSync(testOutDir)) {
      fs.rmSync(testOutDir, { recursive: true, force: true });
    }
  }
});
