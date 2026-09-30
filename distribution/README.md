# Otter

**Readable like English. Precise like code.**

Otter is a programming language designed to make software development read naturally without giving up deterministic programming-language behavior.

```otter
name is "World"
say "Hello" name
```

Output:
```text
Hello World
```

Otter uses readable statements, minimal punctuation, and explicit language rules while providing familiar programming concepts such as variables, conditions, loops, functions, objects, files, CSV processing, command-line applications, and web applications.

---

## Why Otter?

Otter is designed around a simple idea:

> **Programming code should be understandable when read aloud.**

Instead of punctuation-heavy syntax:

```javascript
const age = 20;
if (age >= 18) {
    console.log("Adult");
}
```

Otter uses clear, everyday English words and structured indentation:

```otter
age is 20
if age is at least 18
    say "Adult"
.
```

In Otter:
- Words express meaning directly: `and`, `minus`, `times`, `divided by`, `is at least`, `is greater than`.
- Blocks are defined by natural indentation, finished with an explicit period (`.`).
- Properties are read using everyday prepositions: `name of developer`.
- The period `.` has exactly one structural meaning: **finish a block or process**. It is never overloaded for property access.

---

## Realistic Example

Here is a complete program demonstrating lists, traversal, functions, and output:

```otter
games are
    "Zelda"
    "Metroid"
    "Mario"
.

each game in games
    say "Game:" game
.

to greet person
    say "Hello" person
.

greet "Jeff"
```

Output:
```text
Game: Zelda
Game: Metroid
Game: Mario
Hello Jeff
```

---

## Otter 1.0 Features

- **Variables & Expressions**: Statement-level assignment with `is`, readable arithmetic (`and`, `minus`, `times`, `divided by`), and variable updates (`add`, `remove`).
- **Conditions & Branching**: Clean comparison phrases (`is`, `is not`, `is greater than`, `is at least`, `is less than`, `is at most`) with `if`, `otherwise if`, and `otherwise`.
- **Loops & Iteration**: Multi-line lists (`are`), collection traversal (`each ... in`), numeric ranges (`count from ... to ... as`), fixed repetition (`repeat`), and condition loops (`while`).
- **Functions & Closures**: Defined with `to`, taking readable arguments, with first-class `return` values.
- **Objects & Properties**: Structured objects declared canonically with `has`, properties accessed with `of`, and dynamic key access.
- **Native Filesystem**: File operations that are safe by default (`write ... to`, `write ... to ... atomically`, `read ... into`, `copy ... to`, `delete file`, `if file ... exists`): deleting a folder is never recursive and refuses a folder that still has things in it. This is not a sandbox: a program can read and write any path the user running it can.
- **RFC 4180 CSV**: Native conversion between CSV text, files, and structured objects (`convert ... from csv into`, `read csv`, `write csv`).
- **Command-Line Arguments**: Automatic parameter binding via the built-in `arguments` list.
- **Environment & Directory**: Working directory inspection (`get current directory into`) and environment variable management (`get/set environment variable`).
- **Process Execution**: Structured command execution (`run command ... into`) capturing stdout, stderr, and exit codes.
- **Safe Web Downloads**: Streaming, non-overwriting file downloads with atomic promotion and guaranteed cleanup (`download file from ... to`).
- **Web Application Target**: Direct compilation into standalone, reactive HTML/CSS/JavaScript web applications (`otter web`).
- **Interactive REPL**: Immediate feedback loop for learning and testing statements (`otter`).
- **Reserved Words**: Many words have a meaning in Otter and cannot be used as variable or function names; see the [Otter 1.0 reserved words](docs/OTTER_1_0_RESERVED_WORDS.md).

---

## Platform Support

Otter 1.0 is built and verified for:
- **Windows**: 64-bit Windows 10 and Windows 11, on Windows PowerShell 5.1 (`powershell.exe`, built into Windows). Zero external dependencies.
- **Linux and macOS**: PowerShell 7 (`pwsh`). The same release ZIP installs there with `pwsh -NoProfile -File ./Install-Otter.ps1 -AddToUserPath`, which adds an `otter` command to `~/.local/bin`. Console programs and web applications work; desktop windows and other features built on Windows itself (the registry, the event log, stored credentials, printing, notifications, file dialogs) stop with a clear message. See the [Installation Guide](INSTALL.md#linux-and-macos-powershell-7).

---

## Installation Quick Start

Download the latest Otter release archive (`otter-1.0.0-rc.6.zip`), extract the ZIP, open Windows PowerShell in the extracted directory, and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-Otter.ps1 -AddToUserPath
```

Open a new terminal and verify:

```powershell
otter --version
```

Output:
```text
Otter 1.0.0-rc.6
```

To run without modifying your system or user `PATH`, invoke the batch entry point directly:

```powershell
& "$env:LOCALAPPDATA\Otter\1.0.0-rc.6\otter.cmd" --version
```

On Linux and macOS, install PowerShell 7, then run this in the extracted directory and open a new terminal:

```sh
pwsh -NoProfile -File ./Install-Otter.ps1 -AddToUserPath
```

For complete prerequisites, manual installation steps, and uninstallation instructions, see the [Installation Guide](INSTALL.md).

---

## CLI Quick Reference

```powershell
# Show version information
otter --version

# Display usage instructions and options
otter --help

# Validate syntax without executing
otter check program.ot

# Execute an Otter program
otter run program.ot

# Execute an Otter program with arguments
# (flags Otter uses itself, such as -Port or --help, are not passed on; see INSTALL.md)
otter run program.ot arg1 arg2 arg3

# Shorthand execution
otter program.ot

# Compile an Otter script to a standalone web application
otter web app.ot

# Start an interactive REPL session
otter
```

---

## Status

Otter is currently preparing for the official 1.0 release.

Current release candidate:
```text
1.0.0-rc.6
```

The 1.0 language, compiler, and runtime are **feature frozen** while final verification and release candidate auditing are completed.

---

## Documentation

- [Installation Guide](INSTALL.md) — Detailed setup, prerequisites, PATH configuration, and troubleshooting
- [15-Minute Language Tour](TOUR.md) — Step-by-step tutorial covering Otter's complete core model
- [Examples](examples/) — Runnable Otter programs demonstrating language features
- [License](LICENSE) — Terms of use and redistribution rights
- [Third-Party Notices](THIRD-PARTY-NOTICES.md) — Dependency and third-party asset disclosures

---

## Author

Created by **Jeffrey Macy**.

---

## License

Otter is distributed under the **Otter Free Use License Version 1.0**.

Free to download, use, and build commercial applications with. See [LICENSE](LICENSE) for complete terms.
