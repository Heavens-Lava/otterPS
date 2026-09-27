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
| **Console Interpreter (`otter run`)** | **SUPPORTED** | Primary execution engine for Windows PowerShell 5.1 host. Full syntax support for scripts, control flow, functions, collections, objects, file I/O, processes. |
| **JavaScript Compiler (`otter web`)** | **SUPPORTED** | Translates `.ot` programs into self-contained HTML/JS applications with reactive DOM binding, styles, and asset embedding. |
| **Distribution & Per-User Installer** | **SUPPORTED** | Certified non-admin ZIP packaging, `Install-Otter.ps1`, `Uninstall-Otter.ps1`, PATH registration, upgrade path, and payload integrity checks. |
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
| **Variables & Primitives** (Number, Text, Boolean, `gone`) | **SUPPORTED** | Fully portable across Console and Web targets. |
| **Math & Arithmetic** (Basic, power, percent, round, sqrt, trig, log) | **SUPPORTED** | Fully portable across Console and Web targets. |
| **String Operations** (length, upper/lower, split, replace, contains, starts/ends) | **SUPPORTED** | Fully portable across Console and Web targets. |
| **Lists & Collections** (literals, add/remove, sort, reverse, for-each iteration) | **SUPPORTED** | Fully portable across Console and Web targets. |
| **Objects & Things** (`is a thing`, `property of`, dynamic keys `get`/`set`) | **SUPPORTED** | Fully portable across Console and Web targets. |
| **Custom Types** (`a Person has`, instantiation, field assignment) | **SUPPORTED** | Fully portable across Console and Web targets. |
| **JSON Serialization** (`convert to/from json`, `read json`) | **SUPPORTED** | Portable across Console and Web targets. |
| **Dates & Times** (`today`, `now`, part extraction, arithmetic, format) | **SUPPORTED** | Portable across Console and Web targets. |
| **Randomization** (`random number`, `random item`) | **SUPPORTED** | Portable across Console and Web targets. |
| **File I/O** (`read`, `write`, `append`, `delete file`, `file exists`) | **SUPPORTED** | Supported on Console runtime. Bridge-dependent on Web target. |
| **Folder Discovery** (`get files/folders in`, `and subfolders`, `create/delete folder`) | **SUPPORTED** | Supported on Console runtime. |
| **Process Management** (`run command`, output capture, exit code, `get processes`, `kill process`) | **SUPPORTED** | Supported on Console runtime. |
| **Diagnostics** (`log`, `warn`, `error`, line number tracking) | **SUPPORTED** | Portable across Console and Web targets. |
| **Error Model** (`try` / `otherwise`, `fail with`) | **SUPPORTED** | Portable across Console and Web targets. |
| **HTTP Client (`get`, `post`, `put`, `delete`)** | **TARGET-SPECIFIC** | Supported on Web target via standard browser `fetch`. Not supported on headless Console runtime. |
| **Clipboard Integration** (`copy "..." to clipboard`, `get clipboard`) | **TARGET-SPECIFIC** | Supported on Console (Windows API) and Web target (Clipboard API). |
| **System Info & Environment** (`get environment variable`, `get system info`) | **TARGET-SPECIFIC** | Supported on Console target. |
| **Windows Registry Integration** (`get/set/delete registry value`) | **TARGET-SPECIFIC** | Supported on Windows Console target only. |
| **Windows DPAPI Credentials** (`set/get/delete credential`) | **TARGET-SPECIFIC** | Supported on Windows Console target only. |
| **Print Spooler** (`print "..." to "Printer"`) | **TARGET-SPECIFIC** | Supported on Windows Console target only. |
| **Remote PowerShell / WinRM / SSH** (`run command on remote ...`) | **EXPERIMENTAL** | Windows remote execution subsystem. |
| **Zip / Unzip Compression** (`zip folder`, `unzip archive`) | **SUPPORTED** | Supported on Console runtime (.NET ZipArchive). |
| **Dot Member Access (`person.name`)** | **UNSUPPORTED** | Prohibited by language design. Must use `name of person`. Produces syntax error with suggestion. |
| **Implicit Variable Declaration** | **UNSUPPORTED** | Undefined variables produce clean runtime errors, not implicit null/false. |
