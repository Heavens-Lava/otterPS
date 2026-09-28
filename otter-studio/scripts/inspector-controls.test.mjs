// Inspector value editors (js/components/properties.js): shadow layers and
// the transition editor read and write the same CSS text.
import assert from 'node:assert/strict';

globalThis.window = globalThis.window || new EventTarget();
const { parseShadowLayers, formatShadowLayers, parseTransition } = await import('../js/components/properties.js');
const { STATES } = await import('../js/designer/style-context.js');

// Shadows: every layer, inset, colors with commas inside.
const layers = parseShadowLayers('inset 0 4px 12px rgba(0, 0, 0, 0.1), 0 1px 2px #000');
assert.equal(layers.length, 2);
assert.deepEqual(layers[0], { inset: true, x: '0', y: '4px', blur: '12px', spread: '0', color: 'rgba(0, 0, 0, 0.1)' });
assert.equal(layers[1].color, '#000');
assert.deepEqual(parseShadowLayers('none'), []);
assert.deepEqual(parseShadowLayers(''), []);
assert.equal(parseShadowLayers('0 0 0 3px var(--ring) blue'), null, 'two colors: left to the text field');
assert.equal(formatShadowLayers(parseShadowLayers('0 4px 12px 2px #111')), '0 4px 12px 2px #111', 'round trip');
assert.equal(formatShadowLayers([{ inset: true, x: '0', y: '2', blur: '4', spread: '0', color: '#000' }]), 'inset 0 2px 4px 0 #000', 'bare numbers become px');

// Transitions: property, duration, easing (functions too), delay.
assert.deepEqual(parseTransition('opacity 0.3s cubic-bezier(0.22, 1, 0.36, 1) 100ms'),
  { property: 'opacity', duration: '0.3s', easing: 'cubic-bezier(0.22, 1, 0.36, 1)', delay: '100ms' });
assert.deepEqual(parseTransition(''), { property: 'all', duration: '0.2s', easing: 'ease', delay: '0s' });
assert.equal(parseTransition('all 0.15s ease').easing, 'ease');

// The designer can style the disabled state and a text box's placeholder.
assert.ok(STATES.some(s => s.id === ':disabled'));
assert.ok(STATES.some(s => s.id === '::placeholder'));

console.log('Inspector control tests passed (4 groups).');
