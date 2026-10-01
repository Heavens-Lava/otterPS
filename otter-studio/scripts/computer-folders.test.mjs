// Open Folder > This computer (server/computer-folders.mjs): folders anywhere
// are listed by name, a whole drive is never opened, and an opened folder is
// remembered (in OTTER_STUDIO_STATE_DIR, here a scratch folder).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'otter-computer-folders-'));
process.env.OTTER_STUDIO_STATE_DIR = path.join(scratch, 'state');
const { listComputerFolder, loadSavedRoots, saveRoot, isDriveRoot, computerPlaces } = await import('../server/computer-folders.mjs');

let passed = 0;
const test = (name, fn) => { fn(); passed++; console.log(`  ✓ ${name}`); };

try {
  const site = path.join(scratch, 'sites', 'my-site');
  fs.mkdirSync(path.join(site, 'assets'), { recursive: true });
  fs.writeFileSync(path.join(site, 'project.json'), '{}');
  fs.writeFileSync(path.join(site, 'main.ot'), 'say "hi"\n');
  fs.mkdirSync(path.join(scratch, 'sites', '.hidden'));
  fs.mkdirSync(path.join(scratch, 'sites', 'node_modules'));
  fs.mkdirSync(path.join(scratch, 'sites', 'notes'));

  test('the starting places: home first, then drives', () => {
    const places = computerPlaces();
    assert.equal(places[0].name, 'Home');
    assert.ok(places.some(p => p.kind === 'drive'));
  });
  test('a folder lists its folders - projects first, hidden and dependency folders left out - and its parent', () => {
    const listed = listComputerFolder(path.join(scratch, 'sites'));
    assert.deepEqual(listed.dirs.map(d => d.name), ['my-site', 'notes']);
    assert.equal(listed.dirs[0].isProject, true);
    assert.equal(listed.dirs[0].hasOtter, true);
    assert.equal(listed.dirs[0].hasFolders, true);
    assert.equal(listed.parent, scratch);
  });
  test('a folder that does not exist is a 404', () => {
    assert.throws(() => listComputerFolder(path.join(scratch, 'nope')), err => err.status === 404);
  });
  test('a whole drive is a drive root; a folder is not', () => {
    assert.equal(isDriveRoot(path.parse(scratch).root), true);
    assert.equal(isDriveRoot(scratch), false);
  });
  test('an opened folder is remembered once; a vanished one is forgotten', () => {
    saveRoot(site);
    saveRoot(site);
    assert.deepEqual(loadSavedRoots(), [site]);
    fs.rmSync(site, { recursive: true, force: true });
    assert.deepEqual(loadSavedRoots(), []);
  });
} finally {
  fs.rmSync(scratch, { recursive: true, force: true });
}
console.log(`Computer folder tests passed: ${passed}.`);
