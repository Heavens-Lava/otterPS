// The Designer's Assets tab: image paths relative to the design
// (js/designer/asset-url.js), the server's listing and import names
// (server/assets.mjs), and the size a dropped image gets.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
const { designDir, joinPath, assetUrl, withAssetBase, relativeToDesign } = await import('../js/designer/asset-url.js');
const { listAssets, freeImageName } = await import('../server/assets.mjs');
const { imageSize } = await import('../js/components/assets.js');

let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log(`  ✓ ${name}`);
}

console.log('Assets:');

test('the design folder is the bound .ot file\'s, kept while a stylesheet is open', () => {
  const ide = { currentFile: 'projects/app/styles.css', currentProjectFolder: 'projects/app' };
  assert.equal(designDir(ide, { file: 'projects/app/src/main.ot' }), 'projects/app/src');
  assert.equal(designDir(ide, null), 'projects/app/src', 'the last .ot folder, not the stylesheet\'s');
});

test('sources relative to the design load through /api/raw; absolute ones are left alone', () => {
  const dir = 'projects/my app';
  assert.equal(assetUrl('assets/images/logo.png', dir), '/api/raw/projects/my%20app/assets/images/logo.png');
  assert.equal(assetUrl('../shared/a.png', `${dir}/src`), '/api/raw/projects/my%20app/shared/a.png');
  assert.equal(assetUrl('https://example.com/a.png', dir), 'https://example.com/a.png');
  assert.equal(assetUrl('data:image/png;base64,xx', dir), 'data:image/png;base64,xx');
  assert.equal(joinPath('a/./b', '../c/d.png'), 'a/c/d.png');
});

test('a compiled page gets a <base> at the design folder', () => {
  const html = withAssetBase('<!DOCTYPE html><html><head><title>x</title></head><body></body></html>', 'projects/app');
  assert.match(html, /<head><base href="\/api\/raw\/projects\/app\/"><title>/);
});

test('a project file as a source, from the design\'s folder', () => {
  assert.equal(relativeToDesign('projects/app/assets/images/a.png', 'projects/app'), 'assets/images/a.png');
  assert.equal(relativeToDesign('projects/app/assets/a.png', 'projects/app/src'), '../assets/a.png');
});

test('a dropped image keeps its proportions, at most 320 wide', () => {
  assert.deepEqual(imageSize(64, 32), { width: 64, height: 32 });
  assert.deepEqual(imageSize(1280, 720), { width: 320, height: 180 });
  assert.deepEqual(imageSize(0, 0), { width: 200, height: 140 }, 'not loaded yet: the image default');
});

test('the server lists images, styles, fonts and data; skips tooling and build folders', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-assets-'));
  try {
    const put = (rel) => { fs.mkdirSync(path.dirname(path.join(dir, rel)), { recursive: true }); fs.writeFileSync(path.join(dir, rel), 'x'); };
    ['assets/images/logo.png', 'assets/icons/add.svg', 'styles.css', 'data/contacts.json', 'fonts/Inter.woff2',
      'main.ot', 'project.json', 'node_modules/x/y.png', 'dist/app.css', '.otter/cache.png'].forEach(put);
    const out = listAssets(dir);
    assert.deepEqual(out.images.map(f => f.path), ['assets/icons/add.svg', 'assets/images/logo.png']);
    assert.deepEqual(out.styles.map(f => f.path), ['styles.css']);
    assert.deepEqual(out.data.map(f => f.path), ['data/contacts.json'], 'project.json is Studio\'s, not an asset');
    assert.deepEqual(out.fonts.map(f => f.path), ['fonts/Inter.woff2']);
    // Published packages and a renamed build folder are output, not assets.
    ['publish/site-1.0.0/assets/images/logo.png', 'publish/otter.publish.json', 'site/app.css', 'otter.build.json'].forEach(put);
    fs.writeFileSync(path.join(dir, 'project.json'), JSON.stringify({ build: { outputDir: 'site' } }));
    const again = listAssets(dir);
    assert.deepEqual(again.images.map(f => f.path), ['assets/icons/add.svg', 'assets/images/logo.png'], 'publish/ skipped');
    assert.deepEqual(again.styles.map(f => f.path), ['styles.css'], 'build.outputDir skipped');
    assert.deepEqual(again.data.map(f => f.path), ['data/contacts.json'], 'build/publish records skipped');
    // An imported file never overwrites one already there.
    fs.mkdirSync(path.join(dir, 'imp'));
    fs.writeFileSync(path.join(dir, 'imp', 'my-photo.png'), 'x');
    assert.equal(freeImageName(path.join(dir, 'imp'), 'Team Photo.PNG'), 'Team-Photo.png', 'spaces become dashes');
    assert.equal(freeImageName(path.join(dir, 'imp'), 'my photo.png'), 'my-photo-2.png');
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

console.log(`\nAssets tests passed: ${passed}.`);
