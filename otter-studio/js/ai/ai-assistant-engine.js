/**
 * Otter Studio AI Assistant & Copilot Engine (Prototype / Section 39)
 *
 * NOTE (Review 2026-10-06): This engine operates as an offline
 * heuristic / template-matching prototype. It provides AST-aware assistance,
 * standard diagnostic fix recommendations, test skeleton generation, and
 * syntax-aware completions without requiring an external cloud service.
 * An optional external provider (e.g., local Ollama instance or custom
 * LLM endpoint) can be configured via constructor options.
 */

export class OtterAIAssistant {
  constructor(options = {}) {
    this.isPrototype = true;
    this.provider = options.provider || 'offline-heuristic-prototype';
    this.modelName = options.modelName || 'otter-copilot-template-v1';
    this.endpoint = options.endpoint || null;
    this.apiKey = options.apiKey || null;
    this.temperature = options.temperature ?? 0.2;
    this.conversationHistory = [];
  }

  /**
   * 1. In-IDE conversational pair programmer with workspace context
   */
  buildWorkspaceContext({
    workspaceRoot = '',
    activeFile = '',
    cursorPosition = { line: 1, column: 1 },
    selectedText = '',
    diagnostics = [],
    terminalHistory = [],
    symbols = []
  } = {}) {
    return {
      timestamp: new Date().toISOString(),
      workspaceRoot,
      activeFile,
      cursorPosition,
      selectedText,
      diagnosticsCount: diagnostics.length,
      diagnostics: diagnostics.slice(0, 5),
      recentTerminalLines: terminalHistory.slice(-10),
      availableSymbols: symbols.map(s => s.name || s)
    };
  }

  chat(userMessage, context = {}) {
    const fullContext = this.buildWorkspaceContext(context);
    const entry = {
      role: 'user',
      message: userMessage,
      context: fullContext,
      timestamp: new Date().toISOString()
    };
    this.conversationHistory.push(entry);

    let reply = '';
    const lower = userMessage.toLowerCase();

    if (lower.includes('fix') && fullContext.diagnostics.length > 0) {
      const fixes = this.analyzeDiagnosticsAndSuggestFixes(fullContext.diagnostics, context.source || '');
      reply = `I analyzed your diagnostics. Here is the suggested fix:\n\n${fixes.map(f => f.explanation).join('\n')}`;
    } else if (lower.includes('test') && context.source) {
      reply = this.generateTestSuites(context.source, context.activeFile || 'module');
    } else if (lower.includes('explain') && (context.selectedText || context.source)) {
      reply = this.explainCode(context.selectedText || context.source);
    } else if (lower.includes('create') || lower.includes('generate')) {
      reply = this.generateOtterCode(userMessage, fullContext);
    } else {
      reply = `I am your Otter AI Copilot (offline prototype). I understand Otter syntax, reactive events, UI layouts, and test suites. How can I assist you in ${context.activeFile || 'your workspace'}?`;
    }

    const assistantEntry = {
      role: 'assistant',
      message: reply,
      timestamp: new Date().toISOString()
    };
    this.conversationHistory.push(assistantEntry);

    return {
      reply,
      historyLength: this.conversationHistory.length,
      isPrototype: this.isPrototype,
      provider: this.provider
    };
  }

  /**
   * 2. Natural language to Otter code synthesis
   */
  generateOtterCode(prompt, context = {}) {
    const p = prompt.toLowerCase();

    if (p.includes('counter') || (p.includes('click') && p.includes('button'))) {
      return [
        'count is 0',
        '',
        'label is a text label with text "Count: 0"',
        'btn is a primary button with text "Increment"',
        '',
        'when btn is clicked',
        '    add 1 to count',
        '    set text of label to "Count: " + count',
        '.'
      ].join('\n');
    }

    if (p.includes('http') || p.includes('fetch') || p.includes('api')) {
      return [
        '# Fetch JSON data from API',
        'get json from "https://api.example.com/items" into response',
        'for each item in response',
        '    say name of item',
        '.'
      ].join('\n');
    }

    if (p.includes('file') || p.includes('disk') || p.includes('read') || p.includes('write')) {
      return [
        '# File read and write operations',
        'write content to "output.txt"',
        'read text from "input.txt" into data',
        'say data'
      ].join('\n');
    }

    if (p.includes('loop') || p.includes('repeat') || p.includes('times')) {
      return [
        'repeat 5 times',
        '    say "Iteration"',
        '.'
      ].join('\n');
    }

    if (p.includes('function') || p.includes('add') || p.includes('math')) {
      return [
        'to calculateTotal base and tax',
        '    total is base plus tax',
        '    return total',
        '.'
      ].join('\n');
    }

    // Default template
    return [
      '# Generated Otter source',
      'name is "Otter Application"',
      'say "Starting " + name'
    ].join('\n');
  }

  /**
   * 3. Natural language to visual UI layout generation
   */
  generateUILayout(prompt) {
    const p = prompt.toLowerCase();
    const components = [];

    if (p.includes('login') || p.includes('auth') || p.includes('sign in')) {
      components.push(
        { id: 'titleLabel', type: 'Label', properties: { text: 'Welcome Back', fontSize: '24px' } },
        { id: 'userRow', type: 'Row', properties: {}, children: [
          { id: 'userInput', type: 'TextInput', properties: { placeholder: 'Enter username' } }
        ]},
        { id: 'passRow', type: 'Row', properties: {}, children: [
          { id: 'passInput', type: 'TextInput', properties: { placeholder: 'Enter password', isPassword: true } }
        ]},
        { id: 'submitBtn', type: 'Button', properties: { text: 'Sign In', variant: 'primary' } }
      );
    } else if (p.includes('settings') || p.includes('preferences')) {
      components.push(
        { id: 'settingsTitle', type: 'Label', properties: { text: 'Settings', fontSize: '22px' } },
        { id: 'themeRow', type: 'Row', properties: {}, children: [
          { id: 'themeLabel', type: 'Label', properties: { text: 'Dark Theme' } },
          { id: 'themeCheck', type: 'Checkbox', properties: { checked: true } }
        ]},
        { id: 'saveBtn', type: 'Button', properties: { text: 'Save Settings', variant: 'primary' } }
      );
    } else {
      // General form layout
      components.push(
        { id: 'titleLabel', type: 'Label', properties: { text: 'Otter Application', fontSize: '20px' } },
        { id: 'contentBox', type: 'TextInput', properties: { placeholder: 'Type here...' } },
        { id: 'actionButton', type: 'Button', properties: { text: 'Submit', variant: 'primary' } }
      );
    }

    const otterCodeLines = [];
    const flatten = (items) => {
      for (const c of items) {
        if (c.type === 'Label') {
          otterCodeLines.push(`${c.id} is a text label with text "${c.properties.text}"`);
        } else if (c.type === 'Button') {
          otterCodeLines.push(`${c.id} is a ${c.properties.variant || 'primary'} button with text "${c.properties.text}"`);
        } else if (c.type === 'TextInput') {
          otterCodeLines.push(`${c.id} is a text input with placeholder "${c.properties.placeholder || ''}"`);
        } else if (c.type === 'Checkbox') {
          otterCodeLines.push(`${c.id} is a checkbox`);
        }
        if (c.children && Array.isArray(c.children)) {
          flatten(c.children);
        }
      }
    };
    flatten(components);

    return {
      components,
      otterCode: otterCodeLines.join('\n')
    };
  }

  /**
   * 4. Automated diagnostic analysis and one-click code fixes
   */
  analyzeDiagnosticsAndSuggestFixes(diagnostics = [], source = '') {
    const lines = source.split('\n');
    const suggestions = [];

    for (const diag of diagnostics) {
      const lineNum = diag.line || 1;
      const originalLine = lines[lineNum - 1] || '';
      let fixedLine = originalLine;
      let explanation = '';

      if (diag.message && diag.message.includes('greater') && !originalLine.includes('than')) {
        fixedLine = originalLine.replace(/is greater\b/g, 'is greater than');
        explanation = 'Otter requires "than" after "greater". Replaced "is greater" with "is greater than".';
      } else if (diag.message && diag.message.includes('less') && !originalLine.includes('than')) {
        fixedLine = originalLine.replace(/is less\b/g, 'is less than');
        explanation = 'Otter requires "than" after "less". Replaced "is less" with "is less than".';
      } else if (diag.message && diag.message.includes('unclosed string')) {
        if (!originalLine.endsWith('"')) {
          fixedLine = originalLine + '"';
          explanation = 'Closed unclosed string literal with closing quote.';
        }
      } else if (diag.message && diag.message.includes('indentation')) {
        fixedLine = '    ' + originalLine.trimStart();
        explanation = 'Fixed block indentation to standard 4 spaces.';
      } else {
        explanation = `Suggested review for: ${diag.message || 'Diagnostic at line ' + lineNum}`;
      }

      suggestions.push({
        line: lineNum,
        originalLine,
        fixedLine,
        explanation,
        canApplyAutomatically: fixedLine !== originalLine
      });
    }

    return suggestions;
  }

  /**
   * 5. Automated unit-test suite generation for Otter modules
   */
  generateTestSuites(source = '', moduleName = 'module') {
    const testCases = [];
    const fnRegex = /to\s+([a-zA-Z0-9_]+)(?:\s+([^.\n]+))?/g;
    let match;

    while ((match = fnRegex.exec(source)) !== null) {
      const fnName = match[1];
      const params = match[2] ? match[2].trim().split(/\s+/) : [];
      testCases.push({ fnName, params });
    }

    const testLines = [
      `# Test suite for ${moduleName}`,
      `use "${moduleName}.ot"`,
      '',
      `say "Running tests for ${moduleName}..."`
    ];

    if (testCases.length === 0) {
      testLines.push(
        'say "Test 1: Module loads cleanly"',
        'if not true',
        '    fail with "assertion failed"',
        '.'
      );
    } else {
      testCases.forEach((tc, idx) => {
        const dummyArgs = tc.params.map(() => '10').join(' ');
        testLines.push('');
        testLines.push(`say "Test ${idx + 1}: ${tc.fnName} execution"`);
        if (tc.params.length > 0) {
          testLines.push(`result${idx + 1} is ${tc.fnName} ${dummyArgs}`);
        } else {
          testLines.push(`result${idx + 1} is ${tc.fnName}`);
        }
        testLines.push(`if result${idx + 1} is gone`);
        testLines.push(`    fail with "${tc.fnName} returned gone"`);
        testLines.push('.');
      });
    }

    testLines.push('', `say "All tests for ${moduleName} passed!"`);
    return testLines.join('\n');
  }

  /**
   * 6. Intelligent code explanation and docstring generator
   */
  explainCode(source = '') {
    const explanations = [];
    if (source.includes('when') && source.includes('clicked')) {
      explanations.push('This code attaches an interactive click event handler to a button.');
    }
    if (source.includes('for each')) {
      explanations.push('This code iterates over a collection using an idiomatic Otter for-each loop.');
    }
    if (source.includes('try') && source.includes('otherwise')) {
      explanations.push('This code uses Otter structured error handling (try/otherwise) to safely catch and handle runtime exceptions.');
    }
    if (source.includes('to ')) {
      explanations.push('This code defines one or more reusable Otter functions.');
    }

    if (explanations.length === 0) {
      explanations.push('This Otter code declares variables and executes sequential procedural statements.');
    }

    return explanations.join(' ');
  }

  generateDocstring(functionName, params = [], returnDescription = 'Result') {
    const docLines = [
      `# Function: ${functionName}`
    ];
    if (params.length > 0) {
      params.forEach(p => docLines.push(`#   ${p}: Parameter description`));
    }
    docLines.push(`# Gives back: ${returnDescription}`);
    return docLines.join('\n');
  }

  /**
   * 7. Context-aware semantic inline completions
   */
  semanticInlineCompletions(prefix = '', suffix = '', context = {}) {
    const completions = [];
    const trimmed = prefix.trim();

    if (trimmed.endsWith('is')) {
      completions.push({ text: ' ""', displayText: '"" (empty string)' });
      completions.push({ text: ' 0', displayText: '0 (number)' });
      completions.push({ text: ' a primary button with text "Submit"', displayText: 'a primary button' });
      completions.push({ text: ' a text label with text ""', displayText: 'a text label' });
    } else if (trimmed.endsWith('when')) {
      completions.push({ text: ' button is clicked\n    say "Clicked!"\n.', displayText: 'button is clicked ... .' });
    } else if (trimmed.endsWith('for each')) {
      completions.push({ text: ' item in list\n    say item\n.', displayText: 'item in list ... .' });
    } else if (trimmed.endsWith('if')) {
      completions.push({ text: ' score is greater than 0\n    say "Winner"\n.', displayText: 'score is greater than 0 ... .' });
    } else if (trimmed.endsWith('try')) {
      completions.push({ text: '\n    say "Action"\notherwise error\n    say error\n.', displayText: 'try / otherwise error ... .' });
    } else {
      completions.push({ text: 'say "Hello, Otter!"', displayText: 'say "Hello, Otter!"' });
    }

    return completions;
  }
}
