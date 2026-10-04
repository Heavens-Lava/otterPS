// devtools-profiler-advanced.test.mjs - Comprehensive Certification for Section 27 DevTools

import assert from 'node:assert/strict';
import {
  NetworkInspector,
  NETWORK_PROFILES,
  DomCssInspector,
  StorageConsoleManager,
  ResponsivePreviewManager,
  DEVICE_PRESETS,
  encodeVlq,
  decodeVlq,
  SourceMapV3Generator
} from '../js/profiler/devtools-engine.js';

console.log('--- RUNNING SECTION 27 DEVTOOLS & ADVANCED PROFILER TESTS ---');

// ============================================================================
// Test 1: Network Inspector, Throttling & HAR Export
// ============================================================================
console.log('Test 1: Network inspector, throttling and HAR export');
const net = new NetworkInspector();

// Set throttling
const prof = net.setThrottlingProfile('fast-3g');
assert.equal(prof.name, 'Fast 3G');
assert.equal(net.getThrottlingProfile().key, 'fast-3g');

// Start and complete requests
const req1 = net.startRequest({ url: 'http://127.0.0.1:4200/api/project', method: 'GET' });
assert.equal(req1.state, 'pending');

const resp1 = net.completeResponse(req1.id, {
  status: 200,
  statusText: 'OK',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ name: 'my-app' })
});
assert.equal(resp1.state, 'completed');
assert.equal(resp1.status, 200);

// Failed request
const req2 = net.startRequest({ url: 'http://127.0.0.1:4200/api/missing', method: 'POST' });
net.failRequest(req2.id, new Error('Connection refused'));

const failed = net.getEntries({ filter: 'failed' });
assert.equal(failed.length, 1);
assert.equal(failed[0].id, req2.id);

// HAR Export
const har = net.exportHar();
assert.equal(har.log.version, '1.2');
assert.equal(har.log.entries.length, 2);
assert.equal(har.log.entries[0].request.method, 'GET');
console.log('✓ Network inspector & HAR export verified');

// ============================================================================
// Test 2: DOM & CSS Inspector (Virtual DOM, Matched Rules, Box Model)
// ============================================================================
console.log('Test 2: DOM and CSS inspector with computed styles and box model');
const domInspector = new DomCssInspector();

const sampleDom = {
  tag: 'div',
  id: 'app-container',
  classList: ['layout', 'main'],
  children: [
    {
      tag: 'button',
      id: 'submit-btn',
      classList: ['primary-btn'],
      style: { width: '120px', height: '36px', backgroundColor: '#3B82F6' },
      children: []
    }
  ]
};

const foundBtn = domInspector.findNode(sampleDom, n => n.id === 'submit-btn');
assert.ok(foundBtn);
assert.equal(foundBtn.tag, 'button');

const rules = [
  { selector: '*', declarations: { margin: 0, padding: 0 } },
  { selector: '.primary-btn', declarations: { padding: '8px', borderTopWidth: '2px', color: '#ffffff' } }
];

const styles = domInspector.computeStyles(foundBtn, rules);
assert.equal(styles.matchedRules.length, 2);
assert.equal(styles.computed.width, '120px');
assert.equal(styles.computed.color, '#ffffff');

// Box model calculation
const box = styles.boxModel;
assert.equal(box.content.width, 120);
assert.equal(box.content.height, 36);
assert.equal(box.padding.top, 8);
assert.equal(box.border.top, 2);
assert.ok(box.totalWidth >= 120);
console.log('✓ DOM & CSS inspector and box model verified');

// ============================================================================
// Test 3: Storage & Browser Console Manager
// ============================================================================
console.log('Test 3: Storage and browser console logging');
const scm = new StorageConsoleManager();

scm.log('Application started');
scm.warn('Deprecated API used', { api: 'legacyFetch' });
scm.error('Failed to load asset', 404);

const logs = scm.getLogs();
assert.equal(logs.length, 3);
const errs = scm.getLogs({ level: 'error' });
assert.equal(errs.length, 1);
assert.ok(errs[0].message.includes('Failed to load asset'));

// Storage verification
scm.setItem('local', 'theme', 'dark');
scm.setItem('local', 'fontSize', '14');
assert.equal(scm.getItem('local', 'theme'), 'dark');

scm.setItem('session', 'sessionId', 'sess_123');
assert.equal(scm.getItem('session', 'sessionId'), 'sess_123');
assert.equal(scm.getItem('local', 'sessionId'), null);

const allLocal = scm.listStorage('local');
assert.equal(allLocal.theme, 'dark');
assert.equal(allLocal.fontSize, '14');
console.log('✓ Console logs & storage inspection verified');

// ============================================================================
// Test 4: Responsive Device Preview Emulator
// ============================================================================
console.log('Test 4: Responsive device preview emulator');
const preview = new ResponsivePreviewManager('iPhone 14');
const v1 = preview.getViewport();
assert.equal(v1.deviceName, 'iPhone 14');
assert.equal(v1.width, 390);
assert.equal(v1.height, 844);
assert.equal(v1.orientation, 'portrait');

// Toggle orientation to landscape
const v2 = preview.toggleOrientation();
assert.equal(v2.orientation, 'landscape');
assert.equal(v2.width, 844);
assert.equal(v2.height, 390);

// Switch device to iPad Pro
preview.setDevice('iPad Pro');
preview.setOrientation('portrait');
preview.setZoom(1.5);
const v3 = preview.getViewport();
assert.equal(v3.deviceName, 'iPad Pro');
assert.equal(v3.width, 1024);
assert.equal(v3.height, 1366);
assert.equal(v3.scaledWidth, Math.round(1024 * 1.5));
console.log('✓ Responsive device emulator verified');

// ============================================================================
// Test 5: Base64 VLQ & Source Map v3 Generator (JS back to Otter)
// ============================================================================
console.log('Test 5: Source Map v3 generator and VLQ mapping');
// Test VLQ encoder/decoder roundtrip
for (const val of [0, 1, -1, 15, -15, 128, -128, 1000]) {
  const enc = encodeVlq(val);
  const dec = decodeVlq(enc);
  assert.equal(dec.value, val, `VLQ roundtrip failed for ${val}`);
}

const smGen = new SourceMapV3Generator({ file: 'app.js' });
smGen.addSource('main.ot', 'say "hello world"\nlet x = 42\nsay x');

// Mapping 1: JS line 1, col 0 -> Otter line 1, col 0
smGen.addMapping({
  generated: { line: 1, column: 0 },
  original: { line: 1, column: 0 },
  source: 'main.ot'
});

// Mapping 2: JS line 2, col 4 -> Otter line 2, col 4
smGen.addMapping({
  generated: { line: 2, column: 4 },
  original: { line: 2, column: 4 },
  source: 'main.ot'
});

// Mapping 3: JS line 3, col 2 -> Otter line 3, col 0
smGen.addMapping({
  generated: { line: 3, column: 2 },
  original: { line: 3, column: 0 },
  source: 'main.ot'
});

const sourceMap = smGen.generate();
assert.equal(sourceMap.version, 3);
assert.equal(sourceMap.file, 'app.js');
assert.ok(sourceMap.mappings.length > 0);
assert.ok(sourceMap.sources.includes('main.ot'));

// Test position resolution back to Otter
const pos1 = smGen.originalPositionFor({ line: 1, column: 0 });
assert.equal(pos1.source, 'main.ot');
assert.equal(pos1.line, 1);
assert.equal(pos1.column, 0);

const pos2 = smGen.originalPositionFor({ line: 2, column: 10 });
assert.equal(pos2.source, 'main.ot');
assert.equal(pos2.line, 2);
assert.equal(pos2.column, 4);

console.log('✓ Source Map v3 generator and back-to-Otter resolution verified');

console.log('\n--- ALL SECTION 27 DEVTOOLS TESTS PASSED (5/5) ---');
