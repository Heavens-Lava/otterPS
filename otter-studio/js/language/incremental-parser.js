// incremental-parser.js - High-Performance Incremental Lexer & AST Engine for Otter Studio
// Re-lexes and re-parses only modified lines/blocks, reusing unchanged tokens and AST nodes.

/**
 * Lightweight token definition for fast in-browser lexing.
 */
export class TokenSpan {
  constructor(kind, value, line, col, endCol) {
    this.kind = kind;
    this.value = value;
    this.line = line;
    this.col = col;
    this.endCol = endCol;
  }
}

/**
 * Basic lexer that converts a single line into tokens.
 */
export function tokenizeLine(lineText, lineNumber) {
  const tokens = [];
  let col = 0;
  const len = lineText.length;

  while (col < len) {
    const ch = lineText[col];

    // Whitespace
    if (ch === ' ' || ch === '\t') {
      col++;
      continue;
    }

    // Comments
    if (ch === '#') {
      tokens.push(new TokenSpan('Comment', lineText.slice(col), lineNumber, col, len));
      break;
    }

    // Strings
    if (ch === '"') {
      let end = col + 1;
      while (end < len && lineText[end] !== '"') {
        if (lineText[end] === '\\') end++;
        end++;
      }
      if (end < len && lineText[end] === '"') end++;
      tokens.push(new TokenSpan('String', lineText.slice(col, end), lineNumber, col, end));
      col = end;
      continue;
    }

    // Numbers
    if (/\d/.test(ch)) {
      let end = col;
      while (end < len && /[\d.]/.test(lineText[end])) end++;
      tokens.push(new TokenSpan('Number', lineText.slice(col, end), lineNumber, col, end));
      col = end;
      continue;
    }

    // Identifiers and keywords
    if (/[a-zA-Z_]/.test(ch)) {
      let end = col;
      while (end < len && /[a-zA-Z0-9_]/.test(lineText[end])) end++;
      const val = lineText.slice(col, end);
      tokens.push(new TokenSpan('Identifier', val, lineNumber, col, end));
      col = end;
      continue;
    }

    // Symbols / punctuation
    tokens.push(new TokenSpan('Symbol', ch, lineNumber, col, col + 1));
    col++;
  }

  return tokens;
}

/**
 * Incremental Lexer with line-level caching.
 */
export class IncrementalLexer {
  constructor() {
    this.lineCache = new Map(); // lineIndex (0-based) -> { text, tokens }
    this.reusedCount = 0;
    this.relexedCount = 0;
  }

  /**
   * Tokenizes text incrementally. Reuses token arrays for lines that haven't changed.
   * @param {string} source 
   * @returns {TokenSpan[]} Full flat array of tokens
   */
  tokenize(source) {
    const lines = source.split(/\r?\n/);
    const newLineCache = new Map();
    const allTokens = [];
    this.reusedCount = 0;
    this.relexedCount = 0;

    for (let i = 0; i < lines.length; i++) {
      const lineText = lines[i];
      const cached = this.lineCache.get(i);

      if (cached && cached.text === lineText) {
        // Reuse line tokens directly
        newLineCache.set(i, cached);
        allTokens.push(...cached.tokens);
        this.reusedCount++;
      } else {
        // Line changed or new line: re-lex only this line
        const tokens = tokenizeLine(lineText, i + 1);
        const entry = { text: lineText, tokens };
        newLineCache.set(i, entry);
        allTokens.push(...tokens);
        this.relexedCount++;
      }
    }

    this.lineCache = newLineCache;
    return allTokens;
  }

  getStats() {
    return {
      totalLines: this.lineCache.size,
      reusedLines: this.reusedCount,
      relexedLines: this.relexedCount,
      reuseRate: this.lineCache.size > 0 ? (this.reusedCount / this.lineCache.size) : 0
    };
  }

  clear() {
    this.lineCache.clear();
  }
}

/**
 * AST Node wrapper with line span.
 */
export class AstStatementNode {
  constructor(kind, text, startLine, endLine, metadata = {}) {
    this.kind = kind;
    this.text = text;
    this.startLine = startLine;
    this.endLine = endLine;
    this.metadata = metadata;
  }
}

/**
 * Incremental AST parser that updates only modified statement blocks.
 */
export class IncrementalAst {
  constructor() {
    this.statements = []; // AstStatementNode[]
    this.lastSource = '';
    this.reusedNodes = 0;
    this.reparsedNodes = 0;
  }

  /**
   * Updates the AST given new source code.
   * Identifies top-level statements / blocks and preserves unchanged nodes.
   */
  parse(source) {
    if (source === this.lastSource && this.statements.length > 0) {
      return this.statements;
    }

    const lines = source.split(/\r?\n/);
    const newStatements = [];
    this.reusedNodes = 0;
    this.reparsedNodes = 0;

    let currentBlock = null;

    for (let i = 0; i < lines.length; i++) {
      const lineNum = i + 1;
      const rawLine = lines[i];
      const trimmed = rawLine.trim();

      if (!trimmed || trimmed.startsWith('#')) continue;

      // Check if we are inside a multi-line block
      if (currentBlock) {
        currentBlock.lines.push(rawLine);
        if (trimmed === '.') {
          // Block terminator
          currentBlock.endLine = lineNum;
          const blockText = currentBlock.lines.join('\n');

          // Match with existing statement
          const existing = this.findMatchingStatement(currentBlock.kind, blockText);
          if (existing) {
            existing.startLine = currentBlock.startLine;
            existing.endLine = currentBlock.endLine;
            newStatements.push(existing);
            this.reusedNodes++;
          } else {
            const node = new AstStatementNode(
              currentBlock.kind,
              blockText,
              currentBlock.startLine,
              currentBlock.endLine,
              currentBlock.metadata
            );
            newStatements.push(node);
            this.reparsedNodes++;
          }
          currentBlock = null;
        }
        continue;
      }

      // Check for block starter
      if (/^(to|has|create|on|when|if|while|for\s+each|try)\b/i.test(trimmed)) {
        const kind = trimmed.split(/\s+/)[0].toLowerCase();
        currentBlock = {
          kind,
          startLine: lineNum,
          endLine: lineNum,
          lines: [rawLine],
          metadata: { header: trimmed }
        };
        continue;
      }

      // Single-line statement
      const existing = this.findMatchingStatement('statement', rawLine);
      if (existing) {
        existing.startLine = lineNum;
        existing.endLine = lineNum;
        newStatements.push(existing);
        this.reusedNodes++;
      } else {
        const node = new AstStatementNode('statement', rawLine, lineNum, lineNum);
        newStatements.push(node);
        this.reparsedNodes++;
      }
    }

    // Handle unterminated block if any
    if (currentBlock) {
      currentBlock.endLine = lines.length;
      newStatements.push(new AstStatementNode(
        currentBlock.kind,
        currentBlock.lines.join('\n'),
        currentBlock.startLine,
        currentBlock.endLine,
        { ...currentBlock.metadata, unterminated: true }
      ));
      this.reparsedNodes++;
    }

    this.statements = newStatements;
    this.lastSource = source;
    return this.statements;
  }

  findMatchingStatement(kind, text) {
    return this.statements.find(s => s.kind === kind && s.text === text);
  }

  getStats() {
    return {
      totalStatements: this.statements.length,
      reusedNodes: this.reusedNodes,
      reparsedNodes: this.reparsedNodes
    };
  }
}
