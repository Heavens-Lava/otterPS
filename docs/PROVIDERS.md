# Otter Programming Language — Runtime & Provider Specification

This document specifies the provider interfaces that bridge the core Otter semantics to host environments.

---

## 1. Provider Architecture

Otter decouples the pure language pipeline (Lexer, Parser, AST, Semantics) from host-specific capabilities through providers:

```text
    Otter AST / Semantics
              |
      Provider Interface
   +----------+----------+
   |          |          |
Desktop     Server      Web
 Host        Host       Host
 (Bridge)   (Socket)  (Browser)
```

---

## 2. Filesystem Provider

Exposes CRUD operations over hierarchical paths:
- `ReadText(path)`: Synchronously or asynchronously reads file content as UTF-8.
- `WriteText(path, content)`: Overwrites target with UTF-8 content.
- `AppendText(path, content)`: Appends content to existing file.
- `DeleteFile(path)`: Unlinks file.
- `Exists(path)`: Returns boolean indicating file existence.
- `ListFiles(folder, recurse)`: Returns list of files in folder.
- `ListFolders(folder, recurse)`: Returns list of subfolders.

---

## 3. Process & Terminal Bridge Provider (D60 / D62)

Manages external command execution and interactive sessions:
- **Loopback Bridge**: Binds strictly to `127.0.0.1` on an ephemeral port.
- **Security Requirements**:
  - Requires `X-Otter-Token` (256-bit cryptographic session secret) on every request.
  - Validates `Origin` header against loopback and configured trusted origins.
- **Endpoints**:
  - `POST /api/terminal/exec`: Executes shell commands and returns structured `{ stdout, stderr, exitCode, output }`.
  - `GET /api/terminal/profiles`: Enumerates detected shells (PowerShell, CMD, Git Bash, WSL).
  - `POST /api/session/heartbeat`: Heartbeat management for WebView process lifetimes.

---

## 4. UI & Graphics Provider

- **WPF Native Provider**: Directly hosts desktop controls (`Window`, `Button`, `TextBox`, `Text`, `Row`, `Column`, `Scroll`, `Canvas`).
- **Web / Canvas Provider**: Renders semantic elements as accessible HTML5 components and WebGL/2D animated canvases.

---

## 5. Terminal & REPL Provider

- **Interactive REPL**:
  - Activated by running `otter` without arguments.
  - Maintained across an unbroken `OtterEnvironment` session, allowing variables, types, and functions defined on earlier lines to persist.
  - Dynamic multiline block continuation: lines opening statements (`if`, `while`, `repeat`, `count`, `for`, `to`, `otherwise`, `are$`) switch the prompt to `..... ` until completed by a blank line or closing token.
  - Error isolation: syntax and runtime errors report concise messages and recover immediately without corrupting the session environment.
- **PTY & Shell Discovery**:
  - `Get-OtterAvailableShells` auto-detects installed system shells: PowerShell 7 (`pwsh`), Windows PowerShell (`powershell.exe`), Command Prompt (`cmd.exe`), Git Bash (`bash.exe`), and WSL (`wsl.exe`).
  - Real-time command execution captures `stdout`, `stderr`, and `exitCode` with UTF-8 stream decoding.

---

## 6. Console Application Provider

- **Standard I/O**:
  - `say`: Writes text to stdout with native newline termination.
  - `ask`: Reads lines from stdin into variables.
- **Process Exit Strategy**:
  - Exit code 0: Clean execution success.
  - Exit code 1: CLI usage error (unrecognized command, missing target, bad extension).
  - Exit code 2: Check error (lexical or syntactic parsing failure).
  - Exit code 3: Unhandled runtime error.
- **Argument Escaping**:
  - Native process invocations strictly avoid shell string concatenation.
  - Arguments are individually sanitized and escaped via `ConvertTo-OtterProcessArgument`, neutralizing argument injection vulnerabilities.

