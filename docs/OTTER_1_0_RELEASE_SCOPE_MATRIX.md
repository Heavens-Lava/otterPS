# Otter 1.0 — Authoritative Release Scope Matrix

## Classification Scheme
Every capability in the Otter platform is assigned exactly one status:
- **SUPPORTED**: Production-ready, fully implemented, reached by production CLI (`otter`), documented, and verified with automated test suites.
- **TARGET-SPECIFIC**: Functional and supported only on specific runtime targets (e.g. Web target with browser fetch, or Desktop target with OS shell).
- **EXPERIMENTAL**: Implemented for testing, research, or developer preview; not subject to 1.0 breaking change guarantees.
- **DEFERRED**: Intentionally excluded from Otter 1.0; scheduled for Otter 1.1 or later.
- **UNSUPPORTED**: Not planned, explicitly prohibited by language architecture, or obsolete.

---

## 1. Core Language & Runtimes

| Area / Subsystem | Status | Scope & Platform Details |
|---|---|---|
| **Console Interpreter (`otter run`)** | **SUPPORTED** | Runs on Windows PowerShell 5.1 (Windows) and PowerShell 7 (Windows, Linux, macOS; D120, D129). Features built on Windows itself are Windows-only and refuse clearly elsewhere (D129). Full syntax support for scripts, control flow, functions, collections, objects, file I/O, processes. |
| **JavaScript Compiler (`otter web`)** | **SUPPORTED** | Translates `.ot` programs into self-contained HTML/JS applications with reactive DOM binding, styles, and asset embedding. |
| **Distribution & Per-User Installer** | **SUPPORTED** | Certified non-admin ZIP packaging (`otter-<version>.zip`, one payload for Windows, Linux and macOS; D129), `otter.cmd` and `otter` launchers, `Install-Otter.ps1`, `Uninstall-Otter.ps1`, PATH registration (user PATH on Windows, `~/.local/bin` on Linux and macOS), upgrade path, and payload integrity checks. |
| **Otter CLI Contract (`otter`)** | **SUPPORTED** | Public CLI (`otter`, `run`, `web`, `check`, `help`, `--version`). Deterministic exit codes (0, 1, 2, 3), zero raw host stack traces, directory independence. |
| **Otter Studio (IDE)** | **EXPERIMENTAL** | Browser-based development environment and visual editor (`otter studio` / `studio.cmd`). Operates independently from core language 1.0 gate. |
| **Desktop Native Target (WPF/WebView2)** | **EXPERIMENTAL** | Host bridge runtime (`Otter.Desktop.psm1`) for desktop windows, controls, and local webviews. |
| **File modules (`use "math.ot"`)** | **TARGET-SPECIFIC** | Certified through the console production entry points (`otter run`, `otter check`, `otter debug`); file imports resolve relative to the importing file. The web compiler has a separate resolver path; web/desktop/serve parity remains a target certification item. |
| **Package modules / registry imports** | **DEFERRED** | Package names, registry lookup, and package distribution are outside the 1.0 file-import contract. |
| **Concurrency / Multithreading** | **DEFERRED** | `do at the same time`, background worker threads, and shared memory concurrency are deferred to 1.1+. |
| **Database / SQL Integration** | **DEFERRED** | `get ... from database`, table schemas, and SQL drivers are deferred to 1.2+. |

---

## 2. Standard Library & Domain Capabilities

| Capability | Status | Target Details & Reachability |
|---|---|---|
| **Variables & Primitives** (Number, Text, Boolean, `gone`) | **SUPPORTED** | Portable across Console and Web targets (see the known differences below). |
| **Math & Arithmetic** (Basic, power, percent, round, sqrt, trig, log) | **SUPPORTED** | Portable across Console and Web targets (see the known differences below). |
| **String Operations** (length, upper/lower, split, replace, contains, starts/ends) | **SUPPORTED** | Portable across Console and Web targets (see the known differences below). |
| **Lists & Collections** (literals, add/remove, sort, reverse, for-each iteration) | **SUPPORTED** | Portable across Console and Web targets (see the known differences below). |
| **Objects & Things** (`is a thing`, `property of`, dynamic keys `get`/`set`) | **SUPPORTED** | Portable across Console and Web targets (see the known differences below). |
| **Custom Types** (`a Person has`, instantiation, field assignment) | **SUPPORTED** | Portable across Console and Web targets (see the known differences below). |
| **JSON Serialization** (`convert to/from json`, `read json`) | **SUPPORTED** | Portable across Console and Web targets. |
| **Dates & Times** (`today`, `now`, part extraction, arithmetic, format) | **SUPPORTED** | Portable across Console and Web targets. |
| **Randomization** (`random number`, `random item`) | **SUPPORTED** | Portable across Console and Web targets. |
| **File I/O** (`read`, `write`, `append`, `delete file`, `file exists`) | **SUPPORTED** | Supported on Console runtime. Bridge-dependent on Web target. |
| **Folder Discovery** (`get files/folders in`, `and subfolders`, `create/delete folder`) | **SUPPORTED** | Supported on Console runtime. |
| **Process Management** (`run command`, output capture, exit code, `get processes`, `kill process`) | **SUPPORTED** | Supported on Console runtime. |
| **Diagnostics** (`log`, `warn`, `error`, line number tracking) | **SUPPORTED** | Portable across Console and Web targets. |
| **Error Model** (`try` / `otherwise`, `fail with`) | **SUPPORTED** | Portable across Console and Web targets. |
| **HTTP Client (`get`, `post`, `put`, `delete`, request handles)** | **SUPPORTED** | Console (.NET `HttpClient`) and Web (browser `fetch`), per D116A/D116B (affirmed 2026-09-27). Console certified on the four D120 hosts by `tests/Http.Tests.ps1`. |
| **Clipboard Integration** (`copy "..." to clipboard`, `get clipboard`) | **TARGET-SPECIFIC** | Supported on Console (Windows API; on Linux and macOS where a clipboard program and desktop session exist, otherwise a clear error, D129) and Web target (Clipboard API). |
| **System Info & Environment** (`get environment variable`, `get system info`) | **TARGET-SPECIFIC** | Supported on Console target. |
| **Windows Registry Integration** (`get/set/delete registry value`) | **TARGET-SPECIFIC** | Supported on Windows Console target only; a clear error on Linux and macOS (D129). The same applies to the event log, notifications, file dialogs, file owners and power actions. |
| **Windows DPAPI Credentials** (`set/get/delete credential`) | **TARGET-SPECIFIC** | Supported on Windows Console target only; a clear error on Linux and macOS (D129). |
| **Print Spooler** (`print "..." to "Printer"`) | **TARGET-SPECIFIC** | Supported on Windows Console target only; a clear error on Linux and macOS (D129). |
| **Remote PowerShell / WinRM / SSH** (`run command on remote ...`) | **EXPERIMENTAL** | Windows remote execution subsystem. |
| **Zip / Unzip Compression** (`zip folder`, `unzip archive`) | **SUPPORTED** | Supported on Console runtime (.NET ZipArchive). |
| **Dot Member Access (`person.name`)** | **UNSUPPORTED** | Prohibited by language design. Must use `name of person`. Produces syntax error with suggestion. |
| **Implicit Variable Declaration** | **UNSUPPORTED** | Undefined variables produce clean runtime errors, not implicit null/false. |

### Known Console/Web differences

Console and web share the same semantics for the portable core, and from RC3
`say` formats values the same way on both targets (D8: lists joined with
`, `, `gone`, things and numbers). These known differences remain in Otter 1.0:

| Case | Console (`otter run`) | Web (`otter web`) |
|---|---|---|
| Comparing two lists with `is` | Equal when they hold the same items | Equal only when they are the same list |
| `convert ... to json` text | 2-space indentation; some whole numbers written as `36.0` | 4-space indentation; `36` |
| A list of numbers `contains` the same digits as text (`contains "2"`) | true | false |
| Ordering text (`"b" is greater than "a"`) | Runtime error | Compares the text |
| `repeat` with a fractional count (`repeat 2.7 times`) | Runs 2 times | Runs 3 times |
| `when x changes` | Runs only when the value actually changes | Also runs when the same value is assigned again, and does not run for a plain (non-`state`) variable |
| `if x is empty` (outside `xs are empty`) | Runtime error: no variable called `empty` | Works for text; always false for a list |
| `stop` at the top level of a program | Runtime error | Program stops silently |
| Error text for some mistakes (wrong number of arguments, runaway recursion, calling a function above its definition) | Readable Otter error | A different, less specific message |

Statements that exist only on one target are listed as TARGET-SPECIFIC in the
table above; they are not differences in shared semantics.
