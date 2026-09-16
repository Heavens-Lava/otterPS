import assert from 'node:assert/strict';
import { OtterStudioIde } from '../js/ide.js';

function displayNode() {
  return { style: {}, textContent: '' };
}

const ide = new OtterStudioIde();
const tab = {
  path: 'examples/demo.ot',
  name: 'demo.ot',
  content: 'say "local"\n',
  isDirty: true,
  diskRevision: 'original',
  externalRevision: null,
  externalContent: null,
  externalDeleted: false
};

ide.openTabs = [tab];
ide.currentFile = tab.path;
ide.externalChangeBanner = displayNode();
ide.externalChangeTitle = displayNode();
ide.externalChangeMessage = displayNode();
ide.btnKeepLocalChanges = displayNode();
ide.btnReloadExternalFile = displayNode();
ide.renderTabs = () => {};
ide.saveSessionState = () => {};

ide.setExternalConflict(tab, {
  revision: 'external',
  content: 'say "external"\n'
});

assert.equal(tab.content, 'say "local"\n', 'a dirty editor buffer must not be overwritten');
assert.equal(tab.externalRevision, 'external');
assert.equal(tab.externalContent, 'say "external"\n');
assert.equal(ide.externalChangeBanner.style.display, 'flex');
assert.match(ide.externalChangeTitle.textContent, /changed outside Otter Studio/);

ide.keepLocalChanges();
assert.equal(tab.diskRevision, 'external', 'keeping local changes acknowledges the observed disk revision');
assert.equal(tab.externalRevision, null);
assert.equal(tab.externalContent, null);
assert.equal(tab.isDirty, true);
assert.equal(ide.externalChangeBanner.style.display, 'none');

console.log('External-change state tests passed: dirty buffers are preserved and conflicts require a choice.');
