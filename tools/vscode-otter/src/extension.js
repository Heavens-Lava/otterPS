const vscode = require('vscode');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const keywords = [
  'say', 'ask', 'if', 'otherwise', 'while', 'repeat', 'each', 'for each',
  'to', 'return', 'stop', 'try', 'get', 'set', 'create', 'increase',
  'decrease', 'has'
];

const snippets = [
  ['if', 'if ${1:condition}\n\t$0\n.', 'Conditional block'],
  ['each', 'each ${1:item} in ${2:items}\n\t$0\n.', 'Collection loop'],
  ['thing has', 'thing has\n\t$0\n.', 'Object with properties'],
  ['to', 'to ${1:functionName}\n\t$0\n.', 'Function definition'],
  ['try', 'try\n\t$0\notherwise\n\t\n.', 'Error-handling block']
];

function activate(context) {
  const diagnostics = vscode.languages.createDiagnosticCollection('otter');
  context.subscriptions.push(diagnostics);
  function languageRoot() {
    const candidates = [];
    const bundled = path.join(context.extensionPath, 'bundled-frontend');
    if (fs.existsSync(path.join(bundled, 'Otter.Contract.psm1'))) candidates.push(bundled);
    for (const folder of vscode.workspace.workspaceFolders || []) candidates.push(folder.uri.fsPath);
    candidates.push(path.resolve(context.extensionPath, '..', '..'));
    return candidates.find((candidate) => fs.existsSync(path.join(candidate, 'Otter.Contract.psm1'))) || null;
  }
  function analyze(document) {
    const root = languageRoot();
    if (!root) return { Ok: false, Message: 'Otter language source was not found. Set up the Otter repository or configure the extension root.', Line: 1, Column: 0 };
    const script = path.join(context.extensionPath, 'scripts', 'analyze.ps1');
    const result = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, '-Root', root], { input: document.getText(), encoding: 'utf8', windowsHide: true });
    try { return JSON.parse(result.stdout.trim()); }
    catch { return { Ok: false, Message: result.stderr.trim() || 'Otter analysis failed.', Line: 1, Column: 0 }; }
  }
  function updateDiagnostics(document) {
    if (document.languageId !== 'otter') return;
    const result = analyze(document);
    if (result.Ok) { diagnostics.delete(document.uri); return; }
    const line = Math.max(0, (Number(result.Line) || 1) - 1);
    const column = Math.max(0, Number(result.Column) || 0);
    const range = new vscode.Range(line, column, line, Math.max(column + 1, document.lineAt(line).text.length));
    const message = result.Suggestion ? `${result.Message}\n${result.Suggestion}` : result.Message;
    diagnostics.set(document.uri, [new vscode.Diagnostic(range, message, vscode.DiagnosticSeverity.Error)]);
  }
  function visibleSymbols(result, line) {
    const scopes = result.Scopes || [];
    const active = scopes.filter((scope) => Number(scope.StartLine) <= line + 1 && Number(scope.EndLine) >= line + 1)
      .sort((a, b) => Number(b.StartLine) - Number(a.StartLine));
    const ids = new Set(active.map((scope) => Number(scope.Id)));
    const ordered = (result.Symbols || []).filter((symbol) => ids.has(Number(symbol.ScopeId)))
      .sort((a, b) => Number(b.ScopeId) - Number(a.ScopeId));
    const seen = new Set();
    return ordered.filter((symbol) => !seen.has(symbol.Name) && seen.add(symbol.Name));
  }
  const refresh = (document) => updateDiagnostics(document);
  context.subscriptions.push(vscode.workspace.onDidOpenTextDocument(refresh), vscode.workspace.onDidSaveTextDocument(refresh), vscode.workspace.onDidChangeTextDocument((event) => refresh(event.document)));
  for (const document of vscode.workspace.textDocuments) refresh(document);
  const provider = {
    provideCompletionItems(document, position) {
      const items = keywords.map((word) => {
        const item = new vscode.CompletionItem(word, vscode.CompletionItemKind.Keyword);
        item.detail = 'Otter keyword';
        return item;
      });
      for (const [label, body, detail] of snippets) {
        const item = new vscode.CompletionItem(label, vscode.CompletionItemKind.Snippet);
        item.detail = detail;
        item.insertText = new vscode.SnippetString(body);
        items.push(item);
      }
      const result = analyze(document);
      for (const symbol of visibleSymbols(result, position.line)) {
        const kind = symbol.Kind === 'function' ? vscode.CompletionItemKind.Function : vscode.CompletionItemKind.Variable;
        const item = new vscode.CompletionItem(symbol.Name, kind); item.detail = `Otter ${symbol.Kind}`; items.push(item);
      }
      const currentLine = document.lineAt(position.line).text.slice(0, position.character);
      const propertyMatch = currentLine.match(/\bof\s+([A-Za-z_][A-Za-z0-9_]*)?$/);
      if (propertyMatch && propertyMatch[1] && result.ObjectProperties?.[propertyMatch[1]]) {
        for (const property of result.ObjectProperties[propertyMatch[1]]) { const item = new vscode.CompletionItem(property, vscode.CompletionItemKind.Field); item.detail = `Property of ${propertyMatch[1]}`; items.push(item); }
      }
      return items;
    }
  };
  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider({ language: 'otter', scheme: 'file' }, provider)
  );
  context.subscriptions.push(vscode.languages.registerHoverProvider({ language: 'otter', scheme: 'file' }, {
    provideHover(document, position) {
      const range = document.getWordRangeAtPosition(position);
      if (!range) return undefined;
      const word = document.getText(range);
      const result = analyze(document);
      const symbol = visibleSymbols(result, position.line).find((entry) => entry.Name === word);
      if (symbol) return new vscode.Hover(`Otter ${symbol.Kind} **${word}**`);
      return undefined;
    }
  }));
  context.subscriptions.push(vscode.languages.registerDefinitionProvider({ language: 'otter', scheme: 'file' }, {
    provideDefinition(document, position) {
      const range = document.getWordRangeAtPosition(position);
      if (!range) return undefined;
      const word = document.getText(range);
      const result = analyze(document);
      const symbol = visibleSymbols(result, position.line).find((entry) => entry.Name === word);
      if (!symbol) return undefined;
      return new vscode.Location(document.uri, new vscode.Position(Math.max(0, Number(symbol.Line) - 1), Number(symbol.Column) || 0));
    }
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
