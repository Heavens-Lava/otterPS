import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(scriptDir, '..');
const { OtterUiModel } = await import(pathToFileURL(path.join(studioRoot, 'js', 'model', 'ui-model.js')).href);
const { parseOtterSource } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'otter-parser.js')).href);

const model = new OtterUiModel();
const source = `create window into app
app has title "Source synced"

create button into saveButton
saveButton has text "Save"

put saveButton in app
show app
`;

assert.equal(parseOtterSource(source, model), true);
assert.equal(model.getRoot().name, 'app');
assert.equal(model.getRoot().children.length, 1);
assert.equal(model.getComponent(model.getRoot().children[0]).name, 'saveButton');

const currentOtterSource = await fs.readFile(path.resolve(studioRoot, '..', 'examples', 'hello-app.ot'), 'utf8');
assert.equal(parseOtterSource(currentOtterSource, model), true, 'current Otter UI source must drive the Studio designer');
assert.equal(model.getRoot().name, 'app');
assert.ok(model.getRoot().children.length >= 2, 'current source must preserve put relationships');

assert.equal(parseOtterSource('', model), true, 'empty source is a valid empty design');
assert.equal(model.getRoot(), null, 'deleting source clears the stale UI root');
assert.equal(model.components.size, 0, 'deleting source clears every stale UI component');

assert.equal(parseOtterSource('say "Console only"\n', model), false, 'a non-UI program does not fabricate a UI tree');
assert.equal(model.getRoot(), null);

console.log('Studio source synchronization tests passed: UI source creates a model and empty source clears it.');
