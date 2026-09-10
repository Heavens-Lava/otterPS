const vscode = require('vscode');

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
  const provider = {
    provideCompletionItems() {
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
      return items;
    }
  };
  context.subscriptions.push(
    vscode.languages.registerCompletionItemProvider({ language: 'otter', scheme: 'file' }, provider)
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
