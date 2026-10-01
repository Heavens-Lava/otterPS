// test-archetypes.mjs - Automated certification test suite for all 4 Otter Studio project archetypes
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '../..');
const PORT = 4200;

function post(pathname, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const req = http.request({
      hostname: 'localhost',
      port: PORT,
      path: pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      }
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, json: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, text: data });
        }
      });
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function get(pathname) {
  return new Promise((resolve, reject) => {
    http.get(`http://localhost:${PORT}${pathname}`, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, json: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, text: data });
        }
      });
    }).on('error', reject);
  });
}

async function runTests() {
  console.log('🐾 Starting Otter Studio Archetype Certification Suite...\n');
  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`  ✓ ${message}`);
      passed++;
    } else {
      console.error(`  ✗ ${message}`);
      failed++;
    }
  }

  // 1. Test Console Archetype
  console.log('--- 1. Testing Console Archetype ---');
  const consoleCode = `# Console App
say "Otter CLI Test Executed"
score is 3
say "Score is" score
`;
  const consoleRes = await post('/api/create-project', {
    name: 'test-certified-console',
    archetype: 'console',
    fileName: 'main.ot',
    code: consoleCode
  });
  assert(consoleRes.status === 200 && consoleRes.json.ok, 'Console project created via /api/create-project');
  assert(consoleRes.json.folder === 'projects/test-certified-console', 'Project created in projects/ directory');

  // Verify files on disk
  const consoleDiskDir = path.join(REPO_ROOT, 'projects', 'test-certified-console');
  assert(fs.existsSync(path.join(consoleDiskDir, 'main.ot')), 'main.ot exists on disk');
  assert(fs.existsSync(path.join(consoleDiskDir, 'project.json')), 'project.json manifest exists on disk');

  // Run Console Program via Runner API
  const consoleRun = await post('/api/run', {
    path: 'projects/test-certified-console/main.ot',
    content: consoleCode
  });
  assert(consoleRun.status === 200, 'Runner API /api/run responded HTTP 200');
  assert(consoleRun.json.exitCode === 0, `Exit code is 0 (actual: ${consoleRun.json.exitCode})`);
  assert(consoleRun.json.stdout.includes('Otter CLI Test Executed'), 'Stdout contains expected output');
  assert(consoleRun.json.stdout.includes('Score is 3'), 'Stdout contains variable output');

  // 2. Test Desktop Archetype
  console.log('\n--- 2. Testing Desktop Archetype ---');
  const desktopRes = await post('/api/create-project', {
    name: 'test-certified-desktop',
    archetype: 'desktop',
    fileName: 'app.ot',
    code: `# Desktop App\nwindow "app" title "My Window"\n`,
    css: `/* Desktop styles */\n#app { width: 720px; }\n`
  });
  assert(desktopRes.status === 200 && desktopRes.json.ok, 'Desktop project created via /api/create-project');
  const desktopDiskDir = path.join(REPO_ROOT, 'projects', 'test-certified-desktop');
  assert(fs.existsSync(path.join(desktopDiskDir, 'app.ot')), 'app.ot exists on disk');
  assert(fs.existsSync(path.join(desktopDiskDir, 'app.css')), 'app.css exists on disk (D125: <entry>.css)');
  assert(fs.existsSync(path.join(desktopDiskDir, 'project.json')), 'project.json exists on disk');

  // 3. Test Web Archetype
  console.log('\n--- 3. Testing Web Archetype ---');
  const webRes = await post('/api/create-project', {
    name: 'test-certified-web',
    archetype: 'web',
    fileName: 'web-app.ot',
    code: `# Web App\npage "app"\n    card "hero"\n.\n`,
    css: `/* Web styles */\n#hero { padding: 24px; }\n`
  });
  assert(webRes.status === 200 && webRes.json.ok, 'Web project created via /api/create-project');
  const webDiskDir = path.join(REPO_ROOT, 'projects', 'test-certified-web');
  assert(fs.existsSync(path.join(webDiskDir, 'web-app.ot')), 'web-app.ot exists on disk');
  assert(fs.existsSync(path.join(webDiskDir, 'web-app.css')), 'web-app.css exists on disk (D125: <entry>.css)');
  assert(fs.existsSync(path.join(webDiskDir, 'project.json')), 'project.json exists on disk');

  // 4. Test 2D Game Archetype
  console.log('\n--- 4. Testing 2D Game Archetype ---');
  const gameRes = await post('/api/create-project', {
    name: 'test-certified-game',
    archetype: 'game',
    fileName: 'game.ot',
    code: `# 2D Game\ngame with width 640 and height 480\n    on tick\n    .\n.\n`,
    css: `/* Game styles */\n#gameCanvasBox { background: #000; }\n`
  });
  assert(gameRes.status === 200 && gameRes.json.ok, 'Game project created via /api/create-project');
  const gameDiskDir = path.join(REPO_ROOT, 'projects', 'test-certified-game');
  assert(fs.existsSync(path.join(gameDiskDir, 'game.ot')), 'game.ot exists on disk');
  assert(fs.existsSync(path.join(gameDiskDir, 'game.css')), 'game.css exists on disk (D125: <entry>.css)');
  assert(fs.existsSync(path.join(gameDiskDir, 'project.json')), 'project.json exists on disk');

  // 5. Test Project Reloading via /api/project
  console.log('\n--- 5. Testing Project Reopen & Tree Scanning ---');
  const reopenRes = await get('/api/project?folder=projects/test-certified-console');
  assert(reopenRes.status === 200, 'Reopen project responded HTTP 200');
  assert(reopenRes.json.name === 'test-certified-console', 'Project name correctly identified');
  assert(reopenRes.json.tree.length >= 2, `Project tree scanned ${reopenRes.json.tree.length} files`);

  // 6. Test Diagnostics Linter API
  console.log('\n--- 6. Testing Diagnostics Linter API ---');
  const validLint = await post('/api/lint', { code: 'say "Hello"' });
  assert(validLint.status === 200 && validLint.json.ok === true, 'Valid Otter code passes linter');

  console.log(`\n========================================`);
  console.log(`Certification Summary: ${passed} passed, ${failed} failed.`);
  if (failed > 0) {
    process.exit(1);
  }
}

runTests().catch(err => {
  console.error('Test runner fatal error:', err);
  process.exit(1);
});
