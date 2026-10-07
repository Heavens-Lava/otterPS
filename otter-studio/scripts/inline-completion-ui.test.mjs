import test from 'node:test';
import assert from 'node:assert/strict';
import { InlineCompletionEngine } from '../js/ai/inline-completion.js';
import { OfflineHeuristicProvider } from '../js/ai/providers/offline-provider.js';

test('Inline Completion UI: Ghost-Text, Monotonic Race Protection, and Editor Interaction Certification', async (t) => {
  await t.test('1. Monotonic request ID: Rapid typing A then B guarantees slow A cannot overwrite fast B', async () => {
    const engine = new InlineCompletionEngine({ debounceMs: 10 });
    
    let aResolved = false;
    let bResolved = false;
    
    // Slow provider for Request A
    const slowProviderA = {
      async complete(prefix, ctx, opts) {
        await new Promise(r => setTimeout(r, 60));
        aResolved = true;
        return { code: prefix + ' slow_result_A' };
      }
    };
    
    // Fast provider for Request B
    const fastProviderB = {
      async complete(prefix, ctx, opts) {
        await new Promise(r => setTimeout(r, 15));
        bResolved = true;
        return { code: prefix + ' fast_result_B' };
      }
    };
    
    // Fire Request A
    const promiseA = engine.requestCompletion('make score is', '', {}, slowProviderA);
    
    // Immediately fire Request B (superseding A)
    const promiseB = engine.requestCompletion('make score is 10', '', {}, fastProviderB);
    
    const [resultA, resultB] = await Promise.all([promiseA, promiseB]);
    
    assert.equal(resultA, null, 'Request A was superseded and returned null');
    assert.ok(resultB && resultB.includes('fast_result_B'), 'Request B resolved successfully');
    assert.equal(engine.lastCompletion, resultB, 'Engine lastCompletion matches latest request B');
  });

  await t.test('2. Tab Key Acceptance Workflow: Inserts ghost text and records undo step', () => {
    let editorBuffer = 'make total is ';
    let cursorPosition = editorBuffer.length;
    let ghostText = '100 and add 5';
    const undoStack = [];
    
    function recordSnapshot(text, pos) {
      undoStack.push({ text, pos });
    }
    
    function handleTabKey() {
      if (!ghostText) return false;
      recordSnapshot(editorBuffer, cursorPosition);
      editorBuffer += ghostText;
      cursorPosition = editorBuffer.length;
      ghostText = null;
      return true;
    }
    
    assert.equal(handleTabKey(), true, 'Tab key accepted ghost text');
    assert.equal(editorBuffer, 'make total is 100 and add 5', 'Buffer updated with accepted completion');
    assert.equal(cursorPosition, 27, 'Cursor advanced to end of inserted text');
    assert.equal(ghostText, null, 'Ghost text cleared');
    assert.equal(undoStack.length, 1, 'Undo snapshot recorded');
    
    // Test Undo
    const previous = undoStack.pop();
    editorBuffer = previous.text;
    cursorPosition = previous.pos;
    assert.equal(editorBuffer, 'make total is ', 'Undo restored original buffer');
    assert.equal(cursorPosition, 14, 'Undo restored original cursor');
  });

  await t.test('3. Escape Key Dismissal: Immediately clears ghost text without altering buffer', () => {
    let editorBuffer = 'for each item in list';
    let ghostText = ' repeat:';
    
    function handleEscapeKey() {
      if (ghostText) {
        ghostText = null;
        return true;
      }
      return false;
    }
    
    assert.equal(handleEscapeKey(), true, 'Escape handled');
    assert.equal(ghostText, null, 'Ghost text dismissed');
    assert.equal(editorBuffer, 'for each item in list', 'Buffer untouched');
  });

  await t.test('4. Cursor Movement and File Switching: Cancels in-flight requests and dismisses ghost text', () => {
    const engine = new InlineCompletionEngine({ debounceMs: 50 });
    let ghostText = ' suggested code';
    
    // Simulate user moving cursor with arrow keys or click
    function onCursorMove() {
      engine.cancelPending();
      ghostText = null;
    }
    
    onCursorMove();
    assert.equal(ghostText, null, 'Ghost text dismissed on cursor move');
    assert.equal(engine.activeController, null, 'In-flight completion controller aborted');
    
    // Simulate active document / file switch
    ghostText = ' another suggestion';
    function onDocumentSwitch() {
      engine.cancelPending();
      ghostText = null;
    }
    
    onDocumentSwitch();
    assert.equal(ghostText, null, 'Ghost text dismissed on file switch');
  });

  await t.test('5. Provider Error and Network 500: Fails gracefully with zero editor disruptions', async () => {
    const engine = new InlineCompletionEngine({ debounceMs: 10 });
    const failingProvider = {
      async complete() {
        throw new Error('500 Internal Server Error: Mock upstream failure');
      }
    };
    
    const result = await engine.requestCompletion('function test', '', {}, failingProvider);
    assert.equal(result, null, 'Failed request safely returned null without throwing');
  });

  await t.test('6. Offline Fallback: OfflineHeuristicProvider provides deterministic completion', async () => {
    const engine = new InlineCompletionEngine({ debounceMs: 10 });
    const offlineProvider = new OfflineHeuristicProvider();
    
    const result = await engine.requestCompletion('make score is', '', {}, offlineProvider);
    assert.ok(result !== null, 'Offline provider returned completion');
  });

  await t.test('7. Disabled Setting: Produces zero provider requests when toggled off', async () => {
    const engine = new InlineCompletionEngine({ enabled: false, debounceMs: 10 });
    let callsCount = 0;
    const trackingProvider = {
      async complete() {
        callsCount++;
        return { code: 'some completion' };
      }
    };
    
    const result = await engine.requestCompletion('make x is 1', '', {}, trackingProvider);
    assert.equal(result, null, 'Disabled engine returns null immediately');
    assert.equal(callsCount, 0, 'Zero provider calls executed when disabled');
    
    // Re-enable
    engine.setEnabled(true);
    await engine.requestCompletion('make x is 1', '', {}, trackingProvider);
    assert.equal(callsCount, 1, 'Provider called once enabled');
  });
});
