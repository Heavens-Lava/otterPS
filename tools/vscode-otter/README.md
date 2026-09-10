# Otter Language Support for VS Code

An intentionally small, standalone VS Code extension for editing `.ot` files.
It keeps syntax support and completion separate from the Otter parser so a
future language server can become the source of semantic information without
rewriting the editor integration.

## Local installation

1. Open this folder in VS Code: `tools/vscode-otter`.
2. Press `F5` and choose **Run Otter Extension** if VS Code asks for a
   configuration. The included `.vscode/launch.json` launches an Extension
   Development Host automatically.
3. In the new window, open an `.ot` file (for example,
   `examples/dates.ot` from the repository).

If the file is not colored, check the language indicator in the status bar and
select **Otter**. The extension must be opened as the development workspace,
not just installed as a folder in the first window.

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
- semantic completions for variables and functions discovered by the real Otter parser
- parser-backed diagnostics for syntax errors, plus basic hover text for known variables and functions

The semantic bridge currently invokes the PowerShell lexer/parser directly and
expects the Otter repository (with `Otter.Contract.psm1`) to be available in
the workspace or in the extension's development checkout. It is intentionally
small and synchronous; a future Otter Language Server should replace this
bridge and provide richer AST-aware navigation to both VS Code and Otter
Studio.
