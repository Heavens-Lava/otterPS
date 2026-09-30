// A website's pictures reach its build: the project's own images its pages
// show are listed in the manifest's assets (server/manifest-assets.mjs).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const studioRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { addManifestAssets, referencedImages } = await import(pathToFileURL(path.join(studioRoot, 'server', 'manifest-assets.mjs')).href);

let passed = 0;
const test = (name, fn) => { fn(); passed++; console.log(`  ✓ ${name}`); };
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-manifest-assets-'));

try {
  fs.mkdirSync(path.join(dir, 'assets', 'images'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'assets', 'images', 'team.png'), 'png');
  fs.writeFileSync(path.join(dir, 'logo.svg'), '<svg/>');
  fs.writeFileSync(path.join(dir, 'favicon.png'), 'png');
  fs.writeFileSync(path.join(dir, 'project.json'), '{\r\n  "name": "site",\r\n  "entryPoint": "main.ot",\r\n  "assets": ["logo.svg"]\r\n}\r\n');
  fs.writeFileSync(path.join(dir, 'main.ot'), [
    'home is a page with icon "favicon.png"',
    'team is a image with source "assets/images/team.png"',
    'logo is a image with source "./logo.svg"',
    'remote is a image with source "https://example.com/x.png"',
    'missing is a image with source "assets/images/gone.png"',
    'show home', ''
  ].join('\n'));

  test('the images a page shows (and its icon) that exist in the project', () => {
    assert.deepEqual(referencedImages(dir), ['assets/images/team.png', 'favicon.png', 'logo.svg']);
  });
  test('are added to the manifest once, keeping what it lists and its line endings', () => {
    assert.deepEqual(addManifestAssets(dir, referencedImages(dir)), ['assets/images/team.png', 'favicon.png']);
    const raw = fs.readFileSync(path.join(dir, 'project.json'), 'utf8');
    assert.deepEqual(JSON.parse(raw).assets, ['logo.svg', 'assets/images/team.png', 'favicon.png']);
    assert.ok(raw.includes('\r\n'), 'CRLF kept');
    assert.deepEqual(addManifestAssets(dir, referencedImages(dir)), [], 'nothing twice');
  });
  test('a folder without a manifest is left alone', () => {
    const bare = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-manifest-bare-'));
    assert.deepEqual(addManifestAssets(bare, ['a.png']), []);
    fs.rmSync(bare, { recursive: true, force: true });
  });
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
console.log(`Manifest asset tests passed: ${passed}.`);
