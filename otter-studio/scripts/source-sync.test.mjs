import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(scriptDir, '..');
const componentEditorSource = await fs.readFile(path.join(studioRoot, 'js', 'components', 'editor.js'), 'utf8');
const appSource = await fs.readFile(path.join(studioRoot, 'js', 'app.js'), 'utf8');
const { OtterUiModel } = await import(pathToFileURL(path.join(studioRoot, 'js', 'model', 'ui-model.js')).href);
const { parseOtterSource } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'otter-parser.js')).href);
const { generateOtterSource } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'otter-generator.js')).href);

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

const declarativeSource = `app is a page with title "Declarative Studio"

saveButton is a button with text "Save", padding 8, background "black", round, foreground "white"

put saveButton in app
show app
`;
assert.equal(parseOtterSource(declarativeSource, model), true, 'modern declarative UI source must drive the Studio designer');
assert.equal(model.getRoot().name, 'app');
assert.equal(model.getRoot().properties.title, 'Declarative Studio');
const declarativeButton = model.getComponent(model.getRoot().children[0]);
assert.equal(declarativeButton.name, 'saveButton');
assert.equal(declarativeButton.properties.padding, 8);
assert.equal(declarativeButton.properties.round, true, 'a bare round is a flag (a pill when compiled)');

const regeneratedDeclarativeSource = generateOtterSource(model);
// A page stays a page (it used to be regenerated as a window).
assert.match(regeneratedDeclarativeSource, /^app is a page with /m, 'Studio must emit modern declarative UI declarations, keeping a page a page');
assert.match(regeneratedDeclarativeSource, /^saveButton is a button with /m, 'Studio must emit modern declarative component declarations');
assert.doesNotMatch(regeneratedDeclarativeSource, /^create /m, 'Studio must not regenerate the legacy create-into UI form');

const currentOtterSource = await fs.readFile(path.resolve(studioRoot, '..', 'examples', 'hello-app.ot'), 'utf8');
assert.equal(parseOtterSource(currentOtterSource, model), true, 'current Otter UI source must drive the Studio designer');
assert.equal(model.getRoot().name, 'app');
assert.ok(model.getRoot().children.length >= 2, 'current source must preserve put relationships');

assert.equal(parseOtterSource('', model), true, 'empty source is a valid empty design');
assert.equal(model.getRoot(), null, 'deleting source clears the stale UI root');
assert.equal(model.components.size, 0, 'deleting source clears every stale UI component');

assert.equal(parseOtterSource('say "Console only"\n', model), false, 'a non-UI program does not fabricate a UI tree');
assert.equal(model.getRoot(), null);

assert.doesNotMatch(componentEditorSource, /Apply to Canvas/, 'the split editor must not require a manual apply action');
assert.match(componentEditorSource, /scheduleOtterSourceSync\(\)/, 'the split editor must synchronize source edits live');
assert.match(componentEditorSource, /otter:source-changed/, 'the split editor must update the primary source buffer too');
assert.match(componentEditorSource, /otter:source-synced/, 'the split editor must display source opened in the primary editor');
assert.match(appSource, /otter:source-synced/, 'the Studio shell must publish successful source reconciliation');

// Only the program's top level is the design: UI made inside a function
// (OtterBoard's `to makeProjectCard ... return card`) exists only when the
// program runs; and a `when` holding an `if ... .` keeps its whole body.
{
  const { scanOtterSource } = await import(pathToFileURL(path.join(studioRoot, 'js', 'compiler', 'otter-parser.js')).href);
  const scan = scanOtterSource([
    'app is a page with title "T"',
    'to makeCard name',
    '    card is a card with width 200',
    '    label is a text with text name',
    '    put label in card',
    '    return card',
    '.',
    'status is a text with text "off"',
    'agree is a checkbox with text "Hi"',
    'put status, agree in app',
    'when agree is changed',
    '    if checked of agree',
    '        text of status is "on"',
    '    otherwise',
    '        text of status is "off"',
    '    .',
    '.',
    'show app'
  ].join('\n'));
  assert.deepEqual([...scan.components.keys()], ['app', 'status', 'agree'], 'a function\'s controls are not page elements');
  assert.deepEqual(scan.puts.map(p => p.container), ['app'], 'a function\'s `put` is not the page\'s');
  assert.equal(scan.whens.length, 1);
  assert.equal(scan.whens[0].end, 16, 'the handler ends at its own `.`, not the if\'s');
  assert.match(scan.whens[0].body, /otherwise[\s\S]*"off"[\s\S]*\n\s+\./, 'the whole body, the if\'s `.` included');
}

console.log('Studio source synchronization tests passed: live split editor, UI source creation, and empty-source clearing.');
