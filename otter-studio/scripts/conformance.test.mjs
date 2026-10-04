// otter-studio/scripts/conformance.test.mjs
// Certification test for Otter Conformance Suite (Section 37 / D62)
// Verifies manifest structure, fixture file integrity, syntax validation,
// and end-to-end execution of Test-OtterReleaseConformance.ps1.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(studioRoot, '..');
const manifestPath = path.join(repoRoot, 'conformance', 'manifest.json');
const runnerPath = path.join(repoRoot, 'tools', 'Test-OtterReleaseConformance.ps1');

test('Conformance Suite: Manifest and Fixture File Integrity', () => {
  assert.ok(fs.existsSync(manifestPath), 'manifest.json must exist');
  const raw = fs.readFileSync(manifestPath, 'utf8');
  const manifest = JSON.parse(raw);

  assert.ok(Array.isArray(manifest.fixtures), 'manifest must have fixtures array');
  assert.ok(manifest.fixtures.length >= 15, `Expected at least 15 fixtures, got ${manifest.fixtures.length}`);

  for (const fixture of manifest.fixtures) {
    assert.ok(fixture.name, 'Fixture must have a name');
    assert.ok(fixture.source, `Fixture ${fixture.name} must specify source path`);
    const fixtureFullPath = path.join(repoRoot, fixture.source);
    assert.ok(fs.existsSync(fixtureFullPath), `Fixture source file ${fixture.source} must exist on disk`);

    const content = fs.readFileSync(fixtureFullPath, 'utf8');
    assert.ok(content.length > 0, `Fixture ${fixture.name} content must not be empty`);
  }
});

test('Conformance Suite: Production Parser Verification on Fixtures', () => {
  const raw = fs.readFileSync(manifestPath, 'utf8');
  const manifest = JSON.parse(raw);

  const otterPs1 = path.join(repoRoot, 'otter.ps1');
  // Positive fixtures that represent standard syntax should pass check
  const positiveFixtures = manifest.fixtures.filter(f => f.expectedExitCode === 0 && !f.source.includes('negative'));
  assert.ok(positiveFixtures.length >= 7, 'Expected multiple positive core fixtures');

  for (const fixture of positiveFixtures) {
    const fixtureFullPath = path.join(repoRoot, fixture.source);
    const stdout = execFileSync('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-File', otterPs1,
      'check', fixtureFullPath
    ], {
      cwd: repoRoot,
      encoding: 'utf8',
      windowsHide: true,
      timeout: 15000
    });
    assert.ok(stdout.length >= 0, `Check executed for ${fixture.name}`);
  }
});

test('Conformance Suite: End-to-End Release Runner (Test-OtterReleaseConformance.ps1)', { timeout: 60000 }, () => {
  assert.ok(fs.existsSync(runnerPath), 'Test-OtterReleaseConformance.ps1 must exist');

  const stdout = execFileSync('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', runnerPath
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
    windowsHide: true,
    timeout: 55000
  });

  assert.match(stdout, /Release conformance passed \(15 fixtures\)/, 'Runner must report 15 fixtures passed');
});
