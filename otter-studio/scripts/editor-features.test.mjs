// editor-features.test.mjs - Automated Certification Suite for Multiple Cursors & Large-File Viewport Virtualization
import assert from 'node:assert/strict';
import { MultiCursorManager } from '../js/editor/multi-cursor.js';
import {
  isLargeFile,
  computeVisibleRange,
  renderVirtualizedLines,
  renderVirtualizedGutter,
  LARGE_FILE_LINE_THRESHOLD,
  LARGE_FILE_SIZE_THRESHOLD,
  DEFAULT_LINE_HEIGHT
} from '../js/editor/large-file.js';

async function runTests() {
  console.log('=== Running Otter Studio Editor Features (Multiple Cursors & Large-File Virtualization) Suite ===\n');
  let passed = 0;
  let failed = 0;

  function test(name, fn) {
    try {
      fn();
      console.log(`  ✓ ${name}`);
      passed++;
    } catch (err) {
      console.error(`  ✗ ${name}:`, err.message);
      failed++;
    }
  }

  // --- 1. MultiCursorManager Core Mechanics ---
  console.log('--- 1. MultiCursorManager Core Mechanics ---');

  test('Initializes with single primary cursor at offset 0', () => {
    const mgr = new MultiCursorManager();
    assert.equal(mgr.cursors.length, 1);
    assert.deepEqual(mgr.primary, { start: 0, end: 0 });
    assert.equal(mgr.hasMultipleCursors(), false);
    assert.equal(mgr.secondaries.length, 0);
  });

  test('Adds and normalizes secondary cursors', () => {
    const mgr = new MultiCursorManager();
    mgr.setPrimaryCursor(10, 10);
    mgr.addCursor(25, 25);
    mgr.addCursor(5, 5);

    assert.equal(mgr.hasMultipleCursors(), true);
    assert.equal(mgr.cursors.length, 3);
    // After normalize, cursors should be sorted ascending by offset: 5, 10, 25
    assert.equal(mgr.cursors[0].start, 5);
    assert.equal(mgr.cursors[1].start, 10);
    assert.equal(mgr.cursors[2].start, 25);
  });

  test('Merges overlapping and adjacent cursor selections', () => {
    const mgr = new MultiCursorManager();
    mgr.setPrimaryCursor(5, 12);
    mgr.addCursor(10, 18); // overlaps with [5, 12]

    assert.equal(mgr.cursors.length, 1);
    assert.deepEqual(mgr.cursors[0], { start: 5, end: 18 });
  });

  test('Clears secondary cursors restoring single primary cursor', () => {
    const mgr = new MultiCursorManager();
    mgr.setPrimaryCursor(20, 20);
    mgr.addCursor(50, 50);
    assert.equal(mgr.cursors.length, 2);

    mgr.clearSecondaryCursors();
    assert.equal(mgr.cursors.length, 1);
    assert.deepEqual(mgr.primary, { start: 20, end: 20 });
    assert.equal(mgr.hasMultipleCursors(), false);
  });

  // --- 2. Select Next Occurrence (Ctrl+D) ---
  console.log('\n--- 2. Select Next Occurrence (Ctrl+D) ---');

  test('Automatically expands word under primary cursor and selects next occurrence', () => {
    const code = 'make score is 10\nadd 5 to score\nsay score';
    const mgr = new MultiCursorManager();
    // Cursor initially at offset 7 (inside "score")
    mgr.setPrimaryCursor(7, 7);

    const addedFirst = mgr.selectNextOccurrence(code);
    assert.equal(addedFirst, true);
    assert.equal(mgr.cursors.length, 2);
    // First cursor should be expanded to first "score" [5, 10]
    assert.deepEqual(mgr.cursors[0], { start: 5, end: 10 });
    // Second cursor should select second "score" [26, 31]
    assert.deepEqual(mgr.cursors[1], { start: 26, end: 31 });

    // Press Ctrl+D again to select third "score"
    const addedSecond = mgr.selectNextOccurrence(code);
    assert.equal(addedSecond, true);
    assert.equal(mgr.cursors.length, 3);
    assert.deepEqual(mgr.cursors[2], { start: 36, end: 41 });
  });

  test('Wraps around document when finding next occurrence', () => {
    const code = 'item = 1\nother = 2\nitem = 3';
    const mgr = new MultiCursorManager();
    // Primary cursor at last occurrence [19, 23]
    mgr.setPrimaryCursor(19, 23);

    const added = mgr.selectNextOccurrence(code);
    assert.equal(added, true);
    assert.equal(mgr.cursors.length, 2);
    // Cursors should now include the first occurrence [0, 4]
    assert.equal(mgr.cursors[0].start, 0);
    assert.equal(mgr.cursors[0].end, 4);
    assert.equal(mgr.cursors[1].start, 19);
    assert.equal(mgr.cursors[1].end, 23);
  });

  // --- 3. Column Cursors (Ctrl+Alt+Up / Down) ---
  console.log('\n--- 3. Column Cursors (Ctrl+Alt+Up / Down) ---');

  test('Adds column cursor to line below preserving column position', () => {
    const code = 'alpha = 10\nbeta  = 20\ngamma = 30';
    const mgr = new MultiCursorManager();
    // Cursor at col 6 on line 1 ("alpha ")
    mgr.setPrimaryCursor(6, 6);

    const addedDown = mgr.addColumnCursor(code, 1);
    assert.equal(addedDown, true);
    assert.equal(mgr.cursors.length, 2);

    // Line 2 at col 6 offset: line 1 length is 10 + 1 = 11. 11 + 6 = 17
    assert.equal(mgr.cursors[1].start, 17);
  });

  test('Adds column cursor to line above clamped to line length', () => {
    const code = 'hi\nlongline = 100';
    const mgr = new MultiCursorManager();
    // Cursor at col 8 on line 2
    mgr.setPrimaryCursor(11, 11);

    const addedUp = mgr.addColumnCursor(code, -1);
    assert.equal(addedUp, true);
    assert.equal(mgr.cursors.length, 2);
    // Line 1 only has length 2, cursor should be clamped to 2
    assert.equal(mgr.cursors[0].start, 2);
  });

  // --- 4. Synchronized Multi-Cursor Editing ---
  console.log('\n--- 4. Synchronized Multi-Cursor Editing ---');

  test('Simultaneously inserts text at all cursor positions without offset distortion', () => {
    const code = 'let a = 1\nlet b = 2\nlet c = 3';
    const mgr = new MultiCursorManager();
    // Place cursors after 'let ' on lines 1, 2, 3
    mgr.setPrimaryCursor(4, 4); // after 'let ' line 1
    mgr.addCursor(14, 14);     // after 'let ' line 2
    mgr.addCursor(24, 24);     // after 'let ' line 3

    const result = mgr.applyEdit(code, 'mut_', false, false);
    assert.equal(result.code, 'let mut_a = 1\nlet mut_b = 2\nlet mut_c = 3');
    assert.equal(mgr.cursors.length, 3);
    assert.equal(mgr.cursors[0].start, 8);
    assert.equal(mgr.cursors[1].start, 22);
    assert.equal(mgr.cursors[2].start, 36);
  });

  test('Simultaneously backspaces at all cursor positions', () => {
    const code = 'var x = 1\nvar y = 2';
    const mgr = new MultiCursorManager();
    mgr.setPrimaryCursor(3, 3); // after 'var' line 1
    mgr.addCursor(13, 13);     // after 'var' line 2

    const result = mgr.applyEdit(code, '', true, false);
    assert.equal(result.code, 'va x = 1\nva y = 2');
    assert.equal(mgr.cursors[0].start, 2);
    assert.equal(mgr.cursors[1].start, 11);
  });

  test('Simultaneously deletes forward at all cursor positions', () => {
    const code = 'a1 = 1\nb1 = 2';
    const mgr = new MultiCursorManager();
    mgr.setPrimaryCursor(1, 1); // before '1' line 1
    mgr.addCursor(8, 8);       // before '1' line 2

    const result = mgr.applyEdit(code, '', false, true);
    assert.equal(result.code, 'a = 1\nb = 2');
  });

  test('Simultaneously replaces non-empty selections across multiple cursors', () => {
    const code = 'make foo is 1\nmake foo is 2';
    const mgr = new MultiCursorManager();
    mgr.setPrimaryCursor(5, 8);  // 'foo' line 1
    mgr.addCursor(19, 22);       // 'foo' line 2

    const result = mgr.applyEdit(code, 'target', false, false);
    assert.equal(result.code, 'make target is 1\nmake target is 2');
    assert.equal(mgr.cursors[0].start, 11);
    assert.equal(mgr.cursors[1].start, 28);
  });

  test('Simultaneously inserts newlines across multiple cursors', () => {
    const code = 'fn1()\nfn2()';
    const mgr = new MultiCursorManager();
    mgr.setPrimaryCursor(5, 5);  // after fn1()
    mgr.addCursor(11, 11);       // after fn2()

    const result = mgr.applyEdit(code, '\n    # note', false, false);
    assert.equal(result.code, 'fn1()\n    # note\nfn2()\n    # note');
  });

  // --- 5. Large-File Detection ---
  console.log('\n--- 5. Large-File Detection ---');

  test('Detects small file (< 3,000 lines, < 500KB) as standard mode', () => {
    const smallCode = 'say "hello"\n'.repeat(500);
    assert.equal(isLargeFile(smallCode), false);
  });

  test('Detects large file based on line threshold (>= 3,000 lines)', () => {
    const largeLineCode = 'line\n'.repeat(3050);
    assert.equal(isLargeFile(largeLineCode), true);
  });

  test('Detects large file based on byte size (>= 500KB)', () => {
    const largeByteCode = 'x'.repeat(500001);
    assert.equal(isLargeFile(largeByteCode), true);
    assert.equal(isLargeFile('', 500005), true);
  });

  // --- 6. Viewport Virtualization Calculation ---
  console.log('\n--- 6. Viewport Virtualization Calculation ---');

  test('Computes visible window and spacers at document top', () => {
    const totalLines = 10000;
    const scrollTop = 0;
    const viewportHeight = 600; // ~27 lines at 22px
    const range = computeVisibleRange(scrollTop, viewportHeight, totalLines, DEFAULT_LINE_HEIGHT, 40);

    assert.equal(range.isVirtualized, true);
    assert.equal(range.startIndex, 0);
    assert.equal(range.topSpacerHeight, 0);
    assert.ok(range.endIndex > 60);
    assert.ok(range.bottomSpacerHeight > 0);
    // Total vertical span (top spacer + visible lines + bottom spacer) must equal total lines * lineHeight
    const visibleCount = range.endIndex - range.startIndex;
    const totalCalculatedHeight = range.topSpacerHeight + (visibleCount * DEFAULT_LINE_HEIGHT) + range.bottomSpacerHeight;
    assert.equal(totalCalculatedHeight, totalLines * DEFAULT_LINE_HEIGHT);
  });

  test('Computes visible window and spacers after scrolling down', () => {
    const totalLines = 10000;
    const scrollTop = 22000; // line 1000 at 22px
    const viewportHeight = 600;
    const range = computeVisibleRange(scrollTop, viewportHeight, totalLines, DEFAULT_LINE_HEIGHT, 40);

    assert.ok(range.startIndex > 900);
    assert.ok(range.topSpacerHeight > 0);
    assert.ok(range.bottomSpacerHeight > 0);

    const visibleCount = range.endIndex - range.startIndex;
    const totalCalculatedHeight = range.topSpacerHeight + (visibleCount * DEFAULT_LINE_HEIGHT) + range.bottomSpacerHeight;
    assert.equal(totalCalculatedHeight, totalLines * DEFAULT_LINE_HEIGHT);
  });

  // --- 7. Virtualized DOM HTML Generation ---
  console.log('\n--- 7. Virtualized DOM HTML Generation ---');

  test('Renders virtualized gutter with top and bottom spacers', () => {
    const gutterHtml = renderVirtualizedGutter(100, 150, 2200, 44000, 125, null);
    assert.ok(gutterHtml.includes('gutter-spacer top-spacer'));
    assert.ok(gutterHtml.includes('style="height:2200px;"'));
    assert.ok(gutterHtml.includes('gutter-spacer bottom-spacer'));
    assert.ok(gutterHtml.includes('style="height:44000px;"'));
    // Line 101 to 150 rendered
    assert.ok(gutterHtml.includes('<span>101</span>'));
    assert.ok(gutterHtml.includes('class="gutter-err">125</span>'));
  });

  test('Renders virtualized code lines with top and bottom spacers and syntax highlighting', () => {
    const lines = [];
    for (let i = 1; i <= 500; i++) {
      lines.push(`say "line ${i}"`);
    }

    const linesHtml = renderVirtualizedLines(
      lines,
      50,
      100,
      1100,
      8800,
      (line) => `<span class="highlighted">${line}</span>`,
      75
    );

    assert.ok(linesHtml.includes('virtual-spacer top-spacer'));
    assert.ok(linesHtml.includes('style="height:1100px;"'));
    assert.ok(linesHtml.includes('virtual-spacer bottom-spacer'));
    assert.ok(linesHtml.includes('style="height:8800px;"'));
    assert.ok(linesHtml.includes('data-line="51"'));
    assert.ok(linesHtml.includes('data-line="75"'));
    assert.ok(linesHtml.includes('has-error'));
  });

  console.log(`\nResults: ${passed} passed, ${failed} failed`);
  if (failed > 0) {
    process.exit(1);
  }
}

runTests();
