# D119 Dogfooding Log: Otter 0.9 Production Workspace

This document is the authoritative engineering log for **D119 — Otter 0.9 Production Dogfood**.
Every meaningful friction point, language/runtime deficiency, successful area, and design decision discovered while building the **Otter Developer Workspace** is recorded here under the **No-Language-Workaround Rule**.

---

## Metric Dashboard

| Metric | Current Value | Target | Status |
|---|---|---|---|
| **Host-Language Application Workaround LOC** | **0** | **0** | **Enforced (Strict)** |
| **Otter Application LOC** | 11 | 10,000+ | Phase 1 Foundation |
| **Otter Modules (`.ot`)** | 1 (`main.ot`) | — | Growing organically |
| **Otter Unit/Integration Tests** | 0 | — | Phase 1 Test Suite |
| **Language/Tooling Refinements Identified** | 1 | — | In Progress |

---

## Log Entries

### Entry 001: Phase 1 Capability Audit & Project Scaffolding
- **Date**: 2026-09-25
- **Task**: Scaffold `OtterWorkspace` desktop project and audit existing Otter capabilities for User Story 1 (Open project -> view recent -> select -> inspect -> check).
- **Subsystem Audited**: Project System (D118), Process Execution, JSON, Filesystem, Desktop UI.
- **Successful Capabilities Confirmed**:
  1. **Project Scaffolding**: `otter new desktop OtterWorkspace` generated a valid project layout with clean `otter.json`, `main.ot`, and assets. `otter check .` immediately passed.
  2. **JSON Serialization & Deserialization**:
     - `read json from <path> into <var>`
     - `convert <value> to json into <var>`
     - `convert <text> from json into <var>`
     - Records and dynamic property access (`prop of thing`) work natively.
  3. **Filesystem Operations**:
     - `read <path> into <var>`, `write <text> to <path> [atomically]`
     - `file <path> exists` (boolean condition)
     - `choose folder into <path>` (native folder picker)
     - `get system folder "appdata"` / `"user"` / `"current"`
  4. **Desktop UI Composition**:
     - `create window`, `create heading`, `create text`, `create text box`, `create button`, `create row`, `create column`, `create scroll`, `create card`
     - `put <control> in <container>`
     - `when <button> is clicked:`, `when <textbox> is changed:`
     - `show <window>` (initiates native desktop window message pump)
- **Friction Points & Deficiencies Identified**:
  1. **Process Execution & Child Script Resolution (`run command`) [RESOLVED in D119-R1]**:
     - **First real application symptom**: Clicking "Check" cannot successfully invoke the Otter CLI from Otter Workspace when PATH resolves `otter` to `otter.ps1`.
     - **Problem**: When executing `run command "otter --version" into res`, `Invoke-OtterCommand` uses `Get-Command -Name "otter"`. On Windows with Otter installed in repo or PATH, this resolves to `otter.ps1` (`ExternalScript`) or `otter.cmd`.
     - `Process.Start` with `UseShellExecute = $false` fails immediately on `.ps1` files with:
       `"The specified executable is not a valid application for this OS platform."`
     - On `.cmd` or `.bat` files, launching without `cmd.exe /c` under redirected streams can hang or fail because Windows command scripts require the command processor.
     - **Severity**: **Critical Blocker** for running Otter CLI commands (`otter check`) from Otter programs.
     - **Refinement Implemented (D119-R1)**:
       - Structured script-aware process dispatch in `Invoke-OtterCommand` (`src/Otter.Library.psm1`).
       - Native executables launch directly without shell intermediaries.
       - `.ps1` targets dispatch via dynamic host detection (`Get-OtterPowerShellHost`) with `-NoProfile -File <script> <args...>` without forcing `-ExecutionPolicy Bypass`.
       - `.cmd` and `.bat` targets dispatch via `cmd.exe /d /s /c "<target> <args...>"` with argument boundaries preserved.
       - Hardened argument escaping in `ConvertTo-OtterProcessArgument` and `Split-OtterCommandLine` (supporting spaces, empty arguments, literal quotes via `\"` and `""`, Unicode, paths with spaces, and shell metacharacters `&`, `|`, `<`, `>`, `^`).
       - Deadlock safety hardened with asynchronous stdout and stderr stream reads (`ReadToEndAsync()`) before `WaitForExit()`.
     - **Refinement Commit**: `76fb44e` (`D119-R1: add script-aware command dispatch`)
     - **Regression Tests Added**: `tests/CommandDispatch.Tests.ps1` (10 test scenarios).
     - **Result**: All 10 tests passed; self-hosting `otter --version` reports `0.9.0` and `otter check` runs cleanly from within Otter. Full repository suite passed.
     - **Host-language application workaround LOC**: **0**.
  2. **Process Execution Model (Synchronous vs Asynchronous) [Known D119-R2 Candidate]**:
     - **First real application symptom**: When the user clicks "Check", "Build", or "Publish", the desktop window UI dispatcher freezes until the process finishes.
     - **Problem**: `run command` is entirely synchronous and blocking (`WaitForExit()`). Running a long check or build task inside a UI button click handler blocks the WPF dispatcher thread.
     - `run <target> into p` is asynchronous, but discards `stdout` and `stderr` completely (only yields `id` and `name`).
     - **Severity**: High for interactive UI responsiveness. Scheduled as D119-R2 after Phase 1 foundation vertical slice.
