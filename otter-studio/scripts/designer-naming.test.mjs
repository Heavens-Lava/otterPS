// Designer naming certification: new controls get numbered, non-keyword,
// collision-free names (button1, button2, ...), never a bare keyword.
import assert from 'node:assert/strict';
import { OtterUiModel } from '../js/model/ui-model.js';

const model = new OtterUiModel();
const root = model.getRoot();

const first = model.addChild(root.id, 'button', {});
const second = model.addChild(root.id, 'button', {});
const primary = model.addChild(root.id, 'primary button', {});
const box = model.addChild(root.id, 'text box', {});
assert.equal(first.name, 'button1');
assert.equal(second.name, 'button2');
assert.equal(primary.name, 'primaryButton1');
assert.equal(box.name, 'textBox1');

// A name already in use (for example `button4`, typed in the source) is never
// handed out again - the generator skips over it.
const taken = model.addChild(root.id, 'button', {});
model.setName(taken.id, 'button4');
const next = model.addChild(root.id, 'button', {});
assert.equal(next.name, 'button5', 'skips button4, which is in use');
const later = model.addChild(root.id, 'button', {});
assert.equal(later.name, 'button6');

// Names are unique across the whole tree.
const names = Array.from(model.components.values()).map(c => c.name);
assert.equal(new Set(names).size, names.length);

console.log('Designer naming certification passed.');
