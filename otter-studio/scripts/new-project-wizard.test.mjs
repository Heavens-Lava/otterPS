// new-project-wizard.test.mjs - Production Certification Suite for New Project Wizard Archetypes
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createScratchFolder } from './test-scratch.mjs';

const execFileAsync = promisify(execFile);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const PORT = Number(process.env.OTTER_STUDIO_PORT || 4200);
const baseUrl = `http://127.0.0.1:${PORT}`;

const scratch = createScratchFolder(REPO_ROOT, 'new-project-wizard');

async function request(endpoint, options = {}) {
  const url = `${baseUrl}${endpoint}`;
  const res = await fetch(url, options);
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {}
  return { status: res.status, ok: res.ok, text, json };
}

async function verifyOtterSyntax(code) {
  const psScript = `
    $ErrorActionPreference = "Stop"
    Import-Module "${path.join(REPO_ROOT, 'Otter.Contract.psm1')}" -Force
    Import-Module "${path.join(REPO_ROOT, 'src', 'Otter.Lexer.psm1')}" -Force
    Import-Module "${path.join(REPO_ROOT, 'src', 'Otter.Parser.psm1')}" -Force

    $source = @'
${code}
'@

    $tokens = ConvertTo-OtterTokens -Source $source
    $ast = ConvertTo-OtterAst -Tokens $tokens
    if ($null -eq $ast) { throw "AST was null" }
    Write-Output "PARSER_VERIFIED: $($ast.GetType().Name)"
  `;
  try {
    const { stdout } = await execFileAsync('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', psScript], {
      windowsHide: true,
      timeout: 10000
    });
    return stdout.includes('PARSER_VERIFIED: ProgramNode');
  } catch (err) {
    console.error('Parser verification error:', err.message);
    return false;
  }
}

async function runTests() {
  console.log('=== Running New Project Wizard Archetype Certification Suite ===\n');

  const archetypes = [
    {
      name: 'test-console-tool',
      archetype: 'console',
      fileName: 'main.ot',
      code: '# test-console-tool\n\nsay "Hello from console tool!"\n',
      expectCss: false
    },
    {
      name: 'test-desktop-app',
      archetype: 'desktop',
      fileName: 'main.ot',
      code: 'app is a window with title "Desktop Demo"\n\nshow app\n',
      expectCss: true,
      css: '/* Desktop App Stylesheet */\n.otter-window { background: #0f172a; }\n'
    },
    {
      name: 'test-web-app',
      archetype: 'web',
      fileName: 'main.ot',
      code: 'app is a page with title "Web Demo"\n\nbtn is a button with text "Click me"\nput btn in app\nshow app\n',
      expectCss: true,
      css: '/* Web App Stylesheet */\n'
    },
    {
      name: 'test-game-app',
      archetype: 'game',
      fileName: 'main.ot',
      code: 'app is a window with title "Otter Game 2D"\n\nshow app\n',
      expectCss: true,
      css: '/* 2D Game Stylesheet */\n'
    }
  ];

  let passed = 0;
  let failed = 0;

  for (const arch of archetypes) {
    console.log(`--- Testing Archetype: ${arch.archetype} (${arch.name}) ---`);

    // 1. Create project via backend API
    const createRes = await request('/api/create-project', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: arch.name,
        baseDir: scratch.rel,
        archetype: arch.archetype,
        fileName: arch.fileName,
        code: arch.code,
        css: arch.css
      })
    });

    assert.equal(createRes.status, 200, `POST /api/create-project failed for ${arch.archetype}`);
    assert.equal(createRes.json.ok, true);
    console.log(`  ✓ API returned 200 OK for ${arch.archetype}`);

    // 2. Check disk layout
    const projDiskPath = path.join(scratch.abs, arch.name);
    assert.ok(fs.existsSync(projDiskPath), `Project directory must exist on disk: ${projDiskPath}`);

    const mainDiskPath = path.join(projDiskPath, arch.fileName);
    assert.ok(fs.existsSync(mainDiskPath), `Entry point ${arch.fileName} must exist on disk`);

    const mainContent = fs.readFileSync(mainDiskPath, 'utf8');
    assert.equal(mainContent, arch.code);
    console.log(`  ✓ Entry point ${arch.fileName} on disk matches expected code`);

    const manifestDiskPath = path.join(projDiskPath, 'project.json');
    assert.ok(fs.existsSync(manifestDiskPath), 'project.json must exist on disk');

    const manifest = JSON.parse(fs.readFileSync(manifestDiskPath, 'utf8'));
    assert.equal(manifest.name, arch.name);
    assert.equal(manifest.target, arch.archetype);
    assert.equal(manifest.entryPoint, arch.fileName);
    console.log(`  ✓ project.json verified on disk: name=${manifest.name}, target=${manifest.target}, entryPoint=${manifest.entryPoint}`);

    if (arch.expectCss) {
      const cssDiskPath = path.join(projDiskPath, 'styles.css');
      assert.ok(fs.existsSync(cssDiskPath), 'styles.css must exist for desktop/web/game archetype');
      console.log(`  ✓ styles.css verified on disk`);
    }

    // 3. Verify real Otter parser accepts the generated entry point
    const isValid = await verifyOtterSyntax(arch.code);
    assert.ok(isValid, `Real Otter parser must accept entry code for archetype ${arch.archetype}`);
    console.log(`  ✓ Real Otter parser verified valid ProgramNode for ${arch.archetype}`);

    // 4. Verify Studio read-back API path (/api/file and /api/project-manifest)
    const fileRes = await request(`/api/file?path=${scratch.rel}/${arch.name}/${arch.fileName}`);
    assert.equal(fileRes.status, 200);
    assert.equal(fileRes.json.content, arch.code);
    console.log(`  ✓ GET /api/file read-back verified`);

    const manifestRes = await request(`/api/project-manifest?folder=${scratch.rel}/${arch.name}`);
    assert.equal(manifestRes.status, 200);
    assert.equal(manifestRes.json.manifest.target, arch.archetype);
    console.log(`  ✓ GET /api/project-manifest read-back verified`);

    passed++;
    console.log(`  ✓ Archetype ${arch.archetype} certified successfully!\n`);
  }

  console.log(`========================================`);
  console.log(`Wizard Archetype Summary: ${passed} archetypes certified, ${failed} failed.`);
  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch(err => {
  console.error('Fatal error in wizard test suite:', err);
  process.exit(1);
});
