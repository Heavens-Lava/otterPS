// lsp-server.js - Standard JSON-RPC 2.0 Language Server Protocol Implementation for Otter
import { IncrementalLexer, IncrementalAst } from './incremental-parser.js';

export class OtterLspServer {
  constructor() {
    this.documents = new Map(); // uri -> { text, version, lexer, ast }
    this.initialized = false;
  }

  /**
   * Dispatches an incoming LSP JSON-RPC message.
   * @param {{ jsonrpc: string, id?: number|string, method: string, params?: any }} message 
   * @returns {{ jsonrpc: '2.0', id?: number|string, result?: any, error?: any }}
   */
  handleMessage(message) {
    if (!message || message.jsonrpc !== '2.0') {
      return { jsonrpc: '2.0', id: message?.id ?? null, error: { code: -32600, message: 'Invalid Request: expected jsonrpc 2.0' } };
    }

    const { id, method, params } = message;

    try {
      switch (method) {
        case 'initialize':
          this.initialized = true;
          return {
            jsonrpc: '2.0',
            id,
            result: {
              capabilities: {
                textDocumentSync: 2, // Incremental
                hoverProvider: true,
                definitionProvider: true,
                referencesProvider: true,
                completionProvider: {
                  resolveProvider: false,
                  triggerCharacters: ['.', ' ', '"']
                },
                documentSymbolProvider: true,
                renameProvider: { prepareProvider: false },
                codeActionProvider: true
              },
              serverInfo: {
                name: 'otter-language-server',
                version: '1.0.0'
              }
            }
          };

        case 'initialized':
          return null; // notification

        case 'shutdown':
          this.initialized = false;
          return { jsonrpc: '2.0', id, result: null };

        case 'exit':
          this.documents.clear();
          return null;

        case 'textDocument/didOpen':
          this.onDidOpen(params);
          return null;

        case 'textDocument/didChange':
          this.onDidChange(params);
          return null;

        case 'textDocument/didClose':
          this.onDidClose(params);
          return null;

        case 'textDocument/hover':
          return { jsonrpc: '2.0', id, result: this.onHover(params) };

        case 'textDocument/definition':
          return { jsonrpc: '2.0', id, result: this.onDefinition(params) };

        case 'textDocument/references':
          return { jsonrpc: '2.0', id, result: this.onReferences(params) };

        case 'textDocument/completion':
          return { jsonrpc: '2.0', id, result: this.onCompletion(params) };

        case 'textDocument/documentSymbol':
          return { jsonrpc: '2.0', id, result: this.onDocumentSymbol(params) };

        case 'textDocument/rename':
          return { jsonrpc: '2.0', id, result: this.onRename(params) };

        case 'textDocument/codeAction':
          return { jsonrpc: '2.0', id, result: this.onCodeAction(params) };

        default:
          return {
            jsonrpc: '2.0',
            id,
            error: { code: -32601, message: `Method not found: ${method}` }
          };
      }
    } catch (err) {
      return {
        jsonrpc: '2.0',
        id,
        error: { code: -32603, message: `Internal error: ${err.message}` }
      };
    }
  }

  onDidOpen(params) {
    const { textDocument } = params;
    const uri = textDocument.uri;
    const lexer = new IncrementalLexer();
    const ast = new IncrementalAst();
    lexer.tokenize(textDocument.text);
    ast.parse(textDocument.text);

    this.documents.set(uri, {
      uri,
      version: textDocument.version,
      text: textDocument.text,
      lexer,
      ast
    });
  }

  onDidChange(params) {
    const { textDocument, contentChanges } = params;
    const doc = this.documents.get(textDocument.uri);
    if (!doc) return;

    doc.version = textDocument.version;
    for (const change of contentChanges) {
      if (!change.range) {
        // Full text replacement
        doc.text = change.text;
      } else {
        // Incremental text change
        const lines = doc.text.split('\n');
        const start = change.range.start;
        const end = change.range.end;

        const before = lines.slice(0, start.line).join('\n') + (start.line > 0 ? '\n' : '');
        const startLineText = (lines[start.line] || '').slice(0, start.character);
        const endLineText = (lines[end.line] || '').slice(end.character);
        const after = (end.line < lines.length - 1 ? '\n' : '') + lines.slice(end.line + 1).join('\n');

        doc.text = before + startLineText + change.text + endLineText + after;
      }
    }

    doc.lexer.tokenize(doc.text);
    doc.ast.parse(doc.text);
  }

  onDidClose(params) {
    this.documents.delete(params.textDocument.uri);
  }

  onHover(params) {
    const doc = this.documents.get(params.textDocument.uri);
    if (!doc) return null;

    const { position } = params;
    const lines = doc.text.split('\n');
    const line = lines[position.line] || '';
    const word = this.getWordAt(line, position.character);

    if (!word) return null;

    const KEYWORDS = {
      say: 'Prints values to standard output.',
      make: 'Initializes a variable.',
      is: 'Assigns a value to a variable or compares equality in conditions.',
      has: 'Declares properties inside a custom thing or object.',
      to: 'Defines a user function.',
      use: 'Imports another Otter module or file.',
      create: 'Instantiates a UI component or object.',
      when: 'Registers an event handler for a component.',
      if: 'Conditional branch statement.',
      while: 'Loop executing while condition holds true.',
      'for each': 'Iterates over elements in a list or collection.'
    };

    if (KEYWORDS[word]) {
      return {
        contents: {
          kind: 'markdown',
          value: `**Otter Keyword**: \`${word}\`\n\n${KEYWORDS[word]}`
        }
      };
    }

    // Check function declarations in AST
    for (const stmt of doc.ast.statements) {
      if (stmt.kind === 'to' && stmt.text.includes(word)) {
        return {
          contents: {
            kind: 'markdown',
            value: `**Otter Function**: \`${word}\`\n\nDeclared at line ${stmt.startLine}`
          }
        };
      }
    }

    return {
      contents: {
        kind: 'markdown',
        value: `**Identifier**: \`${word}\``
      }
    };
  }

  onDefinition(params) {
    const doc = this.documents.get(params.textDocument.uri);
    if (!doc) return null;

    const { position } = params;
    const lines = doc.text.split('\n');
    const word = this.getWordAt(lines[position.line] || '', position.character);
    if (!word) return null;

    for (const stmt of doc.ast.statements) {
      if (stmt.text.includes(word)) {
        return {
          uri: doc.uri,
          range: {
            start: { line: stmt.startLine - 1, character: 0 },
            end: { line: stmt.endLine - 1, character: stmt.text.length }
          }
        };
      }
    }

    return null;
  }

  onReferences(params) {
    const doc = this.documents.get(params.textDocument.uri);
    if (!doc) return [];

    const { position } = params;
    const lines = doc.text.split('\n');
    const word = this.getWordAt(lines[position.line] || '', position.character);
    if (!word) return [];

    const refs = [];
    for (let i = 0; i < lines.length; i++) {
      let idx = lines[i].indexOf(word);
      while (idx >= 0) {
        refs.push({
          uri: doc.uri,
          range: {
            start: { line: i, character: idx },
            end: { line: i, character: idx + word.length }
          }
        });
        idx = lines[i].indexOf(word, idx + word.length);
      }
    }
    return refs;
  }

  onCompletion(params) {
    const doc = this.documents.get(params?.textDocument?.uri);
    const items = [
      { label: 'say', kind: 14 /* Keyword */, detail: 'say <expr>' },
      { label: 'is', kind: 14, detail: '<var> is <expr>' },
      { label: 'to', kind: 14, detail: 'to <function> <params>' },
      { label: 'has', kind: 14, detail: 'has <properties>' },
      { label: 'use', kind: 14, detail: 'use "<path>"' },
      { label: 'create', kind: 14, detail: 'create <kind> into <name>' },
      { label: 'when', kind: 14, detail: 'when <event> of <name>' },
      { label: 'if', kind: 14, detail: 'if <cond> ... .' },
      { label: 'for each', kind: 14, detail: 'for each <item> in <list>' }
    ];

    if (doc) {
      const seen = new Set(items.map(i => i.label));
      const tokens = doc.lexer.tokenize(doc.text);
      for (const tok of tokens) {
        if (tok.kind === 'Identifier' && !seen.has(tok.value)) {
          seen.add(tok.value);
          items.push({
            label: tok.value,
            kind: 6 /* Variable */,
            detail: `Identifier: ${tok.value}`
          });
        }
      }
    }

    return {
      isIncomplete: false,
      items
    };
  }

  onDocumentSymbol(params) {
    const doc = this.documents.get(params.textDocument.uri);
    if (!doc) return [];

    const symbols = [];
    for (const stmt of doc.ast.statements) {
      const matchTo = stmt.text.match(/^(?:to|function)\s+([a-zA-Z0-9_]+)/i);
      const matchMake = stmt.text.match(/^(?:make\s+|let\s+)?([a-zA-Z0-9_]+)\s+is\b/i);
      const name = matchTo ? matchTo[1] : (matchMake ? matchMake[1] : (stmt.metadata.header || `${stmt.kind} (Line ${stmt.startLine})`));
      symbols.push({
        name,
        kind: (stmt.kind === 'to' || matchTo) ? 12 /* Function */ : 13 /* Variable */,
        range: {
          start: { line: stmt.startLine - 1, character: 0 },
          end: { line: stmt.endLine - 1, character: 0 }
        },
        selectionRange: {
          start: { line: stmt.startLine - 1, character: 0 },
          end: { line: stmt.startLine - 1, character: name.length }
        }
      });
    }
    return symbols;
  }

  onRename(params) {
    const doc = this.documents.get(params.textDocument.uri);
    if (!doc) return null;

    const { position, newName } = params;
    const lines = doc.text.split('\n');
    const word = this.getWordAt(lines[position.line] || '', position.character);
    if (!word) return null;

    const edits = [];
    for (let i = 0; i < lines.length; i++) {
      let idx = lines[i].indexOf(word);
      while (idx >= 0) {
        edits.push({
          range: {
            start: { line: i, character: idx },
            end: { line: i, character: idx + word.length }
          },
          newText: newName
        });
        idx = lines[i].indexOf(word, idx + word.length);
      }
    }

    return {
      changes: {
        [doc.uri]: edits
      }
    };
  }

  onCodeAction(params) {
    const { range, context } = params;
    const actions = [];

    // Offer block termination fix if period is missing
    actions.push({
      title: "Add block terminator '.'",
      kind: 'quickfix',
      isPreferred: true,
      edit: {
        changes: {
          [params.textDocument.uri]: [
            {
              range: {
                start: { line: range.end.line, character: 0 },
                end: { line: range.end.line, character: 0 }
              },
              newText: '.\n'
            }
          ]
        }
      }
    });

    return actions;
  }

  getWordAt(line, col) {
    if (!line) return '';
    let start = col;
    while (start > 0 && /[a-zA-Z0-9_]/.test(line[start - 1])) start--;
    let end = col;
    while (end < line.length && /[a-zA-Z0-9_]/.test(line[end])) end++;
    return line.slice(start, end);
  }
}
