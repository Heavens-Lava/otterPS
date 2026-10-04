// asset-resources.test.mjs - Comprehensive Verification Suite for Section 26: Assets/resources

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {
  toResourceId,
  fromResourceId,
  parsePlatformAndScale,
  AssetScanner,
  AssetOptimizer,
  AssetDiagnosticScanner,
  AssetBrowserCatalog,
  generateDesignerSnippet,
  AssetRefactoringEngine,
  resolvePlatformResource,
  AppIconGenerator,
  LocalizationResourceManager
} from '../js/project/asset-manager-engine.js';

console.log('--- RUNNING SECTION 26 ASSET & RESOURCE TESTS ---');

// Helper to create a temp test project
function createTempProject() {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-asset-test-'));
  fs.mkdirSync(path.join(tmp, 'assets', 'images'), { recursive: true });
  fs.mkdirSync(path.join(tmp, 'assets', 'audio'), { recursive: true });
  fs.mkdirSync(path.join(tmp, 'assets', 'fonts'), { recursive: true });
  fs.mkdirSync(path.join(tmp, 'assets', 'game'), { recursive: true });
  fs.mkdirSync(path.join(tmp, 'assets', 'locales'), { recursive: true });
  fs.mkdirSync(path.join(tmp, 'src'), { recursive: true });
  return tmp;
}

// Cleanup helper
function cleanupProject(tmp) {
  try {
    fs.rmSync(tmp, { recursive: true, force: true });
  } catch {}
}

const tmp = createTempProject();

try {
  // ==========================================================================
  // Test 1: Resource IDs and Platform/Scale Parsing
  // ==========================================================================
  console.log('Test 1: Resource ID and Platform/Scale conventions');
  assert.equal(toResourceId('assets/images/logo.png'), '@asset/assets/images/logo.png');
  assert.equal(fromResourceId('@asset/assets/images/logo.png'), 'assets/images/logo.png');
  assert.equal(fromResourceId('res://assets/images/logo.png'), 'assets/images/logo.png');

  const platScale = parsePlatformAndScale('icon.win@2x.png');
  assert.equal(platScale.platform, 'windows');
  assert.equal(platScale.scale, '2x');
  console.log('✓ Resource IDs & scale parsing verified');

  // ==========================================================================
  // Test 2: Asset Scanning and Metadata Extraction
  // ==========================================================================
  console.log('Test 2: Scanning assets across categories');
  // Create sample assets
  fs.writeFileSync(path.join(tmp, 'assets', 'images', 'banner.svg'), '<svg width="200" height="100" viewBox="0 0 200 100"><circle cx="50" cy="50" r="40"/></svg>');
  fs.writeFileSync(path.join(tmp, 'assets', 'images', 'photo.png'), Buffer.from([1, 2, 3, 4]));
  fs.writeFileSync(path.join(tmp, 'assets', 'audio', 'click.mp3'), Buffer.from([5, 6, 7]));
  fs.writeFileSync(path.join(tmp, 'assets', 'fonts', 'Inter.woff2'), Buffer.from([8, 9]));
  fs.writeFileSync(path.join(tmp, 'assets', 'game', 'level.tmx'), '<map width="10" height="10"></map>');

  const scanner = new AssetScanner();
  const assets = scanner.scanProject(tmp);
  assert.equal(assets.length, 5, 'Should scan all 5 assets');

  const svgAsset = assets.find(a => a.extension === '.svg');
  assert.ok(svgAsset);
  assert.equal(svgAsset.category, 'image');
  assert.equal(svgAsset.metadata.width, 200);
  assert.equal(svgAsset.metadata.height, 100);

  const audioAsset = assets.find(a => a.extension === '.mp3');
  assert.ok(audioAsset);
  assert.equal(audioAsset.category, 'audio');
  assert.equal(audioAsset.mimeType, 'audio/mpeg');

  const gameAsset = assets.find(a => a.extension === '.tmx');
  assert.ok(gameAsset);
  assert.equal(gameAsset.category, 'game');
  console.log('✓ Asset scanning & metadata extraction verified');

  // ==========================================================================
  // Test 3: Optimization Pipeline, Deduplication & Build Copying
  // ==========================================================================
  console.log('Test 3: Build copying, SVG optimization, and deduplication');
  // Create duplicate file
  fs.writeFileSync(path.join(tmp, 'assets', 'images', 'photo-copy.png'), Buffer.from([1, 2, 3, 4]));
  // Create SVG with comments and whitespace
  fs.writeFileSync(path.join(tmp, 'assets', 'images', 'unopt.svg'), '<?xml version="1.0"?>\n<!-- comment -->\n<svg>\n  <g>\n  </g>\n</svg>');

  const optimizer = new AssetOptimizer();
  const buildResult = optimizer.buildAndCopy({
    projectDir: tmp,
    outputDir: 'dist/assets',
    optimize: true,
    deduplicate: true
  });

  assert.ok(fs.existsSync(buildResult.manifestPath));
  assert.ok(buildResult.manifest.stats.duplicatesDeduplicated >= 1);

  // Check optimized SVG
  const optSvgPath = path.join(tmp, 'dist', 'assets', 'assets', 'images', 'unopt.svg');
  assert.ok(fs.existsSync(optSvgPath));
  const optSvgContent = fs.readFileSync(optSvgPath, 'utf8');
  assert.ok(!optSvgContent.includes('<!-- comment -->'), 'SVG comment should be stripped');
  assert.ok(!optSvgContent.includes('<?xml'), 'XML declaration should be stripped');
  console.log('✓ Optimization & deduplication verified');

  // ==========================================================================
  // Test 4: Missing-Asset Diagnostics
  // ==========================================================================
  console.log('Test 4: Missing-asset diagnostics and fuzzy suggestions');
  const codeContent = `
    say "Loading game..."
    load image "@asset/assets/images/banner.svg"
    load image "@asset/assets/images/bannr.svg"
    play sound "@asset/assets/audio/missing-sound.mp3"
  `;
  const codePath = path.join(tmp, 'src', 'main.ot');
  fs.writeFileSync(codePath, codeContent, 'utf8');

  const diagScanner = new AssetDiagnosticScanner();
  const diagResult = diagScanner.diagnoseReferences(tmp, ['src/main.ot']);
  assert.equal(diagResult.ok, false);
  assert.equal(diagResult.diagnostics.length, 2);

  const typoDiag = diagResult.diagnostics.find(d => d.reference.includes('bannr'));
  assert.ok(typoDiag);
  assert.equal(typoDiag.code, 'ASSET_NOT_FOUND');
  assert.ok(typoDiag.suggestion.includes('banner.svg'), 'Should provide fuzzy match suggestion');
  console.log('✓ Missing-asset diagnostics & fuzzy matching verified');

  // ==========================================================================
  // Test 5: Asset Browser Catalog & Previews
  // ==========================================================================
  console.log('Test 5: Asset catalog browser and previews');
  const catalog = new AssetBrowserCatalog(tmp);
  const items = catalog.getCatalog({ category: 'image' });
  assert.ok(items.length >= 2);
  const svgItem = items.find(i => i.extension === '.svg');
  assert.ok(svgItem.preview);
  assert.equal(svgItem.preview.type, 'svg-data');
  assert.ok(svgItem.preview.dataUri.startsWith('data:image/svg+xml'));
  console.log('✓ Asset browser catalog and previews verified');

  // ==========================================================================
  // Test 6: Drag Asset onto Designer (Code Snippet Generation)
  // ==========================================================================
  console.log('Test 6: Drag asset snippet generation');
  const imgSnippet = generateDesignerSnippet(svgAsset, 'desktop');
  assert.ok(imgSnippet.includes('<Image source="@asset/assets/images/banner.svg"'));

  const gameSpriteSnippet = generateDesignerSnippet(svgAsset, 'game');
  assert.ok(gameSpriteSnippet.includes('create sprite "banner" from "@asset/assets/images/banner.svg"'));

  const audioSnippet = generateDesignerSnippet(audioAsset, 'web');
  assert.ok(audioSnippet.includes('<audio controls src="@asset/assets/audio/click.mp3">'));
  console.log('✓ Designer drag snippets verified');

  // ==========================================================================
  // Test 7: Rename/Move Asset with Source Reference Updates
  // ==========================================================================
  console.log('Test 7: Rename/move asset refactoring');
  const refactorEngine = new AssetRefactoringEngine(tmp);
  const plan = refactorEngine.planMoveOrRename({
    oldRelativePath: 'assets/images/banner.svg',
    newRelativePath: 'assets/images/header-logo.svg',
    sourceFiles: ['src/main.ot']
  });

  assert.equal(plan.fileEdits.length, 1);
  assert.ok(plan.fileEdits[0].updatedContent.includes('@asset/assets/images/header-logo.svg'));

  const execResult = refactorEngine.executeMoveOrRename(plan);
  assert.ok(execResult.ok);
  assert.ok(fs.existsSync(path.join(tmp, 'assets', 'images', 'header-logo.svg')));
  assert.ok(!fs.existsSync(path.join(tmp, 'assets', 'images', 'banner.svg')));

  const updatedSource = fs.readFileSync(codePath, 'utf8');
  assert.ok(updatedSource.includes('@asset/assets/images/header-logo.svg'));
  console.log('✓ Asset move/rename refactoring verified');

  // ==========================================================================
  // Test 8: Platform-Specific Resource Resolution
  // ==========================================================================
  console.log('Test 8: Platform-specific resource resolution');
  const mockAssets = [
    { fileName: 'app-icon.win.ico', platform: 'windows', extension: '.ico' },
    { fileName: 'app-icon.mac.icns', platform: 'macos', extension: '.icns' },
    { fileName: 'app-icon.png', platform: 'all', extension: '.png' }
  ];

  const winRes = resolvePlatformResource('app-icon', 'windows', mockAssets);
  assert.equal(winRes.fileName, 'app-icon.win.ico');

  const macRes = resolvePlatformResource('app-icon', 'macos', mockAssets);
  assert.equal(macRes.fileName, 'app-icon.mac.icns');

  const linuxRes = resolvePlatformResource('app-icon', 'linux', mockAssets);
  assert.equal(linuxRes.fileName, 'app-icon.png');
  console.log('✓ Platform-specific resource resolution verified');

  // ==========================================================================
  // Test 9: App Icon Generator (.ICO and multi-size PNGs)
  // ==========================================================================
  console.log('Test 9: App icon set generator');
  const iconGen = new AppIconGenerator({ sizes: [16, 32, 64, 128, 256] });
  const iconOutDir = path.join(tmp, 'dist', 'icons');
  const iconResult = iconGen.generateIconSet({
    masterSvgPath: path.join(tmp, 'assets', 'images', 'header-logo.svg'),
    outputDir: iconOutDir,
    baseName: 'otter-app'
  });

  assert.ok(iconResult.ok);
  assert.ok(fs.existsSync(path.join(iconOutDir, 'otter-app.ico')));
  assert.ok(fs.existsSync(path.join(iconOutDir, 'favicon.ico')));
  assert.ok(fs.existsSync(path.join(iconOutDir, 'otter-app-16x16.png')));
  assert.ok(fs.existsSync(path.join(iconOutDir, 'otter-app-256x256.png')));
  assert.ok(fs.existsSync(path.join(iconOutDir, 'icons.json')));

  // Verify valid ICO binary header: 0x0000 0x0001 <count>
  const icoHeader = fs.readFileSync(path.join(iconOutDir, 'otter-app.ico')).slice(0, 6);
  assert.equal(icoHeader.readUInt16LE(0), 0);
  assert.equal(icoHeader.readUInt16LE(2), 1);
  assert.equal(icoHeader.readUInt16LE(4), 5); // 5 sizes
  console.log('✓ App icon generator verified');

  // ==========================================================================
  // Test 10: Localization Resources
  // ==========================================================================
  console.log('Test 10: Localization resources & coverage validation');
  const localesDir = path.join(tmp, 'assets', 'locales');
  fs.writeFileSync(path.join(localesDir, 'en.json'), JSON.stringify({
    welcome: 'Hello, {name}!',
    itemsCount: { zero: 'No items', one: '1 item', other: '{count} items' },
    settings: 'Settings'
  }, null, 2));

  fs.writeFileSync(path.join(localesDir, 'es.json'), JSON.stringify({
    welcome: '¡Hola, {name}!',
    itemsCount: { zero: 'Sin elementos', one: '1 elemento', other: '{count} elementos' }
    // missing settings
  }, null, 2));

  const i18n = new LocalizationResourceManager(localesDir);
  i18n.loadAll();

  assert.equal(i18n.get('welcome', 'en', { name: 'Jeff' }), 'Hello, Jeff!');
  assert.equal(i18n.get('welcome', 'es', { name: 'Jeff' }), '¡Hola, Jeff!');

  assert.equal(i18n.get('itemsCount', 'en', { count: 0 }), 'No items');
  assert.equal(i18n.get('itemsCount', 'en', { count: 1 }), '1 item');
  assert.equal(i18n.get('itemsCount', 'en', { count: 5 }), '5 items');

  const coverage = i18n.validateCoverage('en');
  assert.equal(coverage.totalKeys, 3);
  assert.ok(coverage.missingKeys.es.includes('settings'));
  assert.equal(coverage.languages.es.coveragePercent, 67);
  console.log('✓ Localization resources & validation verified');

  console.log('\n--- ALL SECTION 26 ASSET/RESOURCE TESTS PASSED (10/10) ---');
} finally {
  cleanupProject(tmp);
}
