# Otter Language Support for VS Code

An intentionally small, standalone VS Code extension for editing `.ot` files.
It keeps syntax support and completion separate from the Otter parser so a
future language server can become the source of semantic information without
rewriting the editor integration.

## Local installation

1. Open this folder in VS Code: `tools/vscode-otter`.
2. Press `F5` to launch an Extension Development Host.
3. Open an `.ot` file in the new window.

For a local user install, package the folder as a VSIX with `@vscode/vsce`
when that tool is available, then use **Extensions: Install from VSIX...**.

Validate the extension without VS Code or downloaded dependencies:

```powershell
npm test
npm run check
```

## Current support

- `.ot` association and `otter` language ID
- `#` line comments, strings, escapes, numbers, booleans, and `gone`
- statement, structural, diagnostic, file/folder, and date/time vocabulary
- contextual multi-word forms such as `for each`, `starts with`, and `divided by`
- block-ending periods and indentation/folding hints
- completion for common keywords plus `if`, `each`, `thing has`, `to`, and `try` snippets

The grammar intentionally provides presentation-level highlighting only. It
does not attempt to duplicate parser decisions such as runtime name lookup or
all contextual keyword rules. Semantic diagnostics, symbol completion, and
AST-aware navigation belong in the future Otter Language Server.
