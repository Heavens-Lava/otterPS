# D119 Dogfooding Log: Otter 0.9 Production Workspace

This document is the authoritative engineering log for **D119 — Otter 0.9 Production Dogfood**.
Every meaningful friction point, language/runtime deficiency, successful area, and design decision discovered while building the **Otter Developer Workspace** is recorded here under the **No-Language-Workaround Rule**.

---

## Metric Dashboard

| Metric | Current Value | Target | Status |
|---|---|---|---|
| **Host-Language Application Workaround LOC** | **0** | **0** | **Enforced (Strict)** |
| **D119 Refinements Discovered** | **2** | — | D119-R1 & D119-R2 |
| **D119 Refinements Completed** | **2** | — | 100% Delivered & Certified |
| **Otter Application LOC** | 880+ | 10,000+ | Phase 4 (Project Explorer Active) |
| **Otter Test LOC** | 650+ | — | 6 Suites (Passing) |
| **Documentation & Dogfood Log LOC** | 400+ | — | Actively Maintained |
| **Otter Modules (`.ot`)** | 8 | — | Growing organically |
| **Otter Test Suites** | 6 suites (all passing) | — | Phase 4 Certified |

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

---

### Entry 002: Phase 1 First Vertical Slice Implementation
- **Date**: 2026-09-25
- **Task**: Implement the first complete, usable Otter Workspace vertical slice in pure Otter under the No-Language-Workaround Rule (`Host-language application workaround LOC = 0`).
- **Files Created**:
  - `OtterWorkspace/main.ot` (Application entry point)
  - `OtterWorkspace/src/workspace/project.ot` (`Project` type, `createProject`, `loadProjectManifest`)
  - `OtterWorkspace/src/workspace/project_store.ot` (`getRecentProjects`, `saveRecentProjects`, `addRecentProject` with deduplication)
  - `OtterWorkspace/src/workspace/project_service.ot` (`CheckResult` type, `runProjectCheck` capturing exit code, stdout, stderr)
  - `OtterWorkspace/src/ui/project_list.ot` (`formatProjectSummary`, `formatProjectDetails`, `formatRecentList`)
  - `OtterWorkspace/src/ui/shell.ot` (Complete window layout: header, Open Project button, Check Project button, status text, selected project details card, recent projects scroll, output scroll area, and event handlers)
  - `OtterWorkspace/tests/project_store_test.ot` (Store roundtrip, deduplication, missing store handling)
  - `OtterWorkspace/tests/project_service_test.ot` (Manifest loading, missing manifest rejection, check success, check failure exit codes, UI formatting helpers)
- **Toolchain Acceptance**:
  - `otter check .` -> **PASSED** (exit code 0)
  - `otter test .` -> **PASSED** (3/3 test suites passed: `app_test.ot`, `project_service_test.ot`, `project_store_test.ot`)
  - `otter build .` -> **PASSED** (output `dist/`, exit code 0)
  - `otter publish .` -> **PASSED** (artifact `publish/OtterWorkspace-0.1.0.zip`, SHA-256 computed, exit code 0)
- **Workaround Audit**:
  - Host-Language Application Workaround LOC: **0**
  - All workspace application code and tests are 100% written in Otter (`.ot`). No helper PowerShell/CMD scripts or native C# bridges were added to the application.

---

### Entry 003: D119-R2 Asynchronous Process Execution & Workspace Migration
- **Date**: 2026-09-25
- **Task**: Implement **D119-R2 — Asynchronous Process Execution** across the Otter grammar, parser, runtime, and interpreter, and migrate `OtterWorkspace/` from synchronous `run command` to non-blocking async process execution.
- **Language Grammar & AST Additions**:
  - `start command <expr> and call it <target>` (`StartCommandStmt`)
  - `on output from <job>` (`WhenStmt` with event `'output'`) -> reads line via `received output` (`JobContextExpr`)
  - `on error output from <job>` (`WhenStmt` with event `'error output'`) -> reads line via `received error output` (`JobContextExpr`)
  - `on exit of <job>` / `on complete of <job>` / `on cancel of <job>` (`WhenStmt` with terminal event dispatch)
  - `<job> is running` / `completed` / `failed` / `cancelled` (and `is not`) (`HttpRequestIsState`)
  - `cancel <job>` (`HttpCancel` statement handler for command jobs)
  - Dynamic properties: `exit code of <job>`, `state of <job>`, `output of <job>`, `error output of <job>`, `id of <job>`, `command of <job>`
- **Runtime Architecture & Runspace Safety**:
  - Implemented pure C# `OtterProcessTracker` (compiled via `Add-Type`) with `ConcurrentQueue<OtterJobEventItem>`. .NET `OutputDataReceived`, `ErrorDataReceived`, and `Exited` handlers write directly into thread-safe concurrent queues without executing PowerShell scriptblocks across thread boundaries (preventing `PSInvalidOperationException: There is no Runspace available on this thread` on Windows PowerShell 5.1).
  - Main interpreter single-threaded event loop (`Invoke-OtterEventLoop` / `Invoke-OtterJobEventLoopStep`) non-blockingly drains events and dispatches to registered Otter handlers.
  - Retained terminal events ensure handlers attached after a fast-exiting command still receive the exit/complete/cancel notification immediately.
  - Process tree kill (`Stop-OtterProcess -IncludeChildren $true`) ensures cancellation cleanly terminates child processes.
  - Double-cancel is strictly idempotent and safe.
- **Backward Compatibility**:
  - `run command "..." into result` remains 100% synchronous and unaltered.
- **Workspace UI Migration (`OtterWorkspace/src/ui/shell.ot`)**:
  - Migrated Check Project action to async execution (`start command cmd and call it checkJob`).
  - Added dedicated action buttons for **Check**, **Test**, **Build**, **Publish**, and **Cancel**.
  - Output box streams real-time stdout and stderr as lines arrive from child process.
  - Status label reflects live state (`"Running: otter check..."`, `"Completed successfully."`, `"Failed with exit code 1."`, `"Cancelled."`).
  - Desktop WPF message pump remains completely responsive during long-running builds and tests.
- **Verification & Acceptance**:
  - `tests/AsyncCommand.Tests.ps1`: **13/13 passing**.
  - `otter check .\OtterWorkspace`: **PASSED**.
  - `otter test .\OtterWorkspace`: **3/3 test suites passing** (`app_test.ot`, `project_service_test.ot`, `project_store_test.ot`).
  - `otter build .\OtterWorkspace`: **PASSED** (`dist/`).
  - `otter publish .\OtterWorkspace`: **PASSED** (`publish/OtterWorkspace-0.1.0.zip`).
  - Full repo test harness `tests/Run-Tests.ps1`: **All 54 test suites passing**.
- **Host-Language Application Workaround LOC**: **0** (Strictly maintained).

---

### Entry 004: Phase 2 Project Task Runner Implementation & Dogfooding Observations
- **Date**: 2026-09-25
- **Task**: Turn the existing Check workflow into a full-featured, reusable **Project Task Runner** covering `Run`, `Check`, `Test`, `Build`, `Publish`, `Cancel`, and `Clear Output` without blocking the UI.
- **Files Created / Updated**:
  - `OtterWorkspace/src/workspace/project_task.ot` (`ProjectTask` type, `createProjectTask`, `formatTaskCommand`, `startTask`, `recordTaskOutput`, `recordTaskError`, `finishTask`, `cancelTask`, `isTaskRunning`, `formatTaskStatus`).
  - `OtterWorkspace/src/workspace/project_service.ot` (Integrated `project_task.ot` while maintaining backward compatibility).
  - `OtterWorkspace/src/ui/shell.ot` (Extended toolbar with `Run`, `Check`, `Test`, `Build`, `Publish`, `Cancel`, and `Clear Output` buttons; live line-by-line output streaming with `[stderr]` distinction; single-task concurrency guards; preserved output history).
  - `OtterWorkspace/tests/task_runner_test.ot` (Comprehensive test suite covering command construction across all 5 actions, state transitions `idle` -> `running` -> `succeeded` / `failed` / `cancelled`, stdout/stderr accumulation, nonzero exit handling, simultaneous task prevention, and real async process execution).
- **Dogfooding Observations**:
  1. **Reusable Event-Driven Application Model**: Creating an Otter domain type (`ProjectTask`) to manage application-level state and mapping process streaming events (`on output from`, `on error output from`, `on exit of`, `on cancel of`) directly to model methods proved natural, clean, and concise in pure Otter.
  2. **Single-Task Concurrency Control**: Gating action triggers with `isTaskRunning activeTask` easily prevents duplicate or overlapping jobs without needing low-level lock primitives or complex thread synchronizers.
  3. **Output Accumulation & Stream Separation**: Distinguishing stdout and stderr in both the domain object (`output`, `errorOutput`) and live UI text (`[stderr] ...`) was straightforward using string concatenation.
  4. **Identifier Disambiguation**: In record types (`a ProjectTask has`), field names avoid keywords (`status` instead of `state`, `commandText` instead of `command`), keeping property definitions clean and collision-free.
- **Toolchain Acceptance**:
  - `otter check .\OtterWorkspace` -> **PASSED** (exit code 0)
  - `otter test .\OtterWorkspace` -> **PASSED** (4/4 test suites passed: `app_test.ot`, `project_service_test.ot`, `project_store_test.ot`, `task_runner_test.ot`)
  - `otter build .\OtterWorkspace` -> **PASSED** (output `dist/`, exit code 0)
  - `otter publish .\OtterWorkspace` -> **PASSED** (artifact `publish/OtterWorkspace-0.1.0.zip`, SHA-256 computed, exit code 0)
  - `tests/AsyncCommand.Tests.ps1` -> **PASSED** (13/13 passing)
- **Workaround Audit**:
  - Host-Language Application Workaround LOC: **0** (Strictly maintained).

---

### Entry 005: Phase 3 Project Management Experience & Dogfooding Observations
- **Date**: 2026-09-25
- **Task**: Implement full **Project Management Experience** in Otter Workspace: interactive recent-project card selection, project creation workflow with form validation, settings inspection/editing, and atomic manifest persistence with preservation of unknown fields.
- **Files Created / Updated**:
  - `OtterWorkspace/src/workspace/project.ot` (Added `entryPoint` and `rawManifest` fields to `Project`, implemented `saveProjectSettings` preserving unknown manifest properties with atomic disk writes).
  - `OtterWorkspace/src/workspace/project_service.ot` (Added `validateNewProjectForm` validating names, locations, and supported archetypes `console`, `desktop`, `web`, `automation`, `game`; added `formatNewProjectCommand`).
  - `OtterWorkspace/src/ui/shell.ot` (Added interactive Project Settings card with editable form fields and atomic Save button; added New Project creation form; added interactive recent-project cards).
  - `OtterWorkspace/tests/project_management_test.ot` (Automated test suite covering manifest loading, settings editing, preservation of arbitrary unknown JSON properties, atomic write verification, form validation, and command construction).
- **Dogfooding Observations**:
  1. **Dynamic Collection & Control Creation**: Iterating over `recentProjects` with `for each p in recents` to create interactive buttons and attach click handlers works smoothly.
  2. **JSON Object Mutation & Unknown Property Preservation**: Otter's `read json ... into data` parses JSON into an `OtterObject` (`thing`), and `set "key" to val in data` mutates specific fields without disturbing unmapped or unknown fields (`assets`, `scripts`, `build`, etc.). `convert data to json into jsonText` cleanly serializes the complete preserved object.
  3. **Atomic Persistence**: `write jsonText to manifestPath atomically` (D72) writes to a temporary sibling file and performs a single atomic rename/replace, preventing partial writes during crashes.
  4. **Post-Save Validation**: Executing `otter check <project>` via asynchronous process dispatch immediately after saving settings allows real-time diagnostics if invalid configuration is introduced.
- **Toolchain Acceptance**:
  - `otter check .\OtterWorkspace` -> **PASSED** (exit code 0)
  - `otter test .\OtterWorkspace` -> **PASSED** (5/5 test suites passed: `app_test.ot`, `project_management_test.ot`, `project_service_test.ot`, `project_store_test.ot`, `task_runner_test.ot`)
  - `otter build .\OtterWorkspace` -> **PASSED** (output `dist/`, exit code 0)
  - `otter publish .\OtterWorkspace` -> **PASSED** (artifact `publish/OtterWorkspace-0.1.0.zip`, SHA-256 computed, exit code 0)
  - `tests/AsyncCommand.Tests.ps1` -> **PASSED** (13/13 passing)
- **Workaround Audit**:
  - Host-Language Application Workaround LOC: **0** (Strictly maintained).

---

### Entry 006: Phase 4 Project Explorer, Tree Enumeration, Search, Metadata & File Watching
- **Date**: 2026-09-25
- **Task**: Implement **Phase 4 Project Explorer** in Otter Workspace: recursive tree discovery, ignored path filtering (`dist/`, `publish/`, `.git/`), file category and extension classification, project-wide text search (`searchInProject`), text vs binary inspection (`inspectProjectFile`), live file watching (`watch folder ... and subfolders`), and integrated Workspace UI.
- **Files Created / Updated**:
  - `OtterWorkspace/src/workspace/explorer_service.ot` (Created module with `ProjectItem`, `SearchResult`, `isTextExtension`, `getFileCategory`, `isIgnoredPath`, `getProjectFiles`, `searchInProject`, `inspectProjectFile`, and factory constructors `createProjectItem`, `createSearchResult`).
  - `OtterWorkspace/src/ui/shell.ot` (Integrated Project Explorer & Search Card, file list view with category icons, live search input, file preview inspector, and live project refresh).
  - `OtterWorkspace/tests/explorer_test.ot` (Added comprehensive test suite covering file enumeration, filtering of build outputs, text vs binary classification, project search, and inspection).
- **Dogfooding Observations**:
  - **1. Object Instantiation Pattern in Loops**:
    - Defining custom records in Otter (`a ProjectItem has ...`) and instantiating them via helper constructor functions (`to createProjectItem ... return a ProjectItem with ...`) is the clean and idiomatic Otter pattern when processing dynamic collections. Directly re-declaring variable bindings as `item is a ProjectItem with ...` in the outer loop scope is intentionally guarded by Otter's runtime redefinition protection.
  - **2. Filesystem Enumeration & Error Resiliency**:
    - `get files in <path> and subfolders into <var>` provides complete recursive file traversal. Wrapping discovery in `try ... otherwise` handles locked or unreadable paths cleanly.
  - **3. Text vs Binary Preview Inspection**:
    - Distinguishing text extensions (`.ot`, `.json`, `.txt`, `.md`, `.css`, etc.) allows the inspector to read text safely while protecting against binary preview corruption on assets and archives.
  - **4. Zero Host-Language Workarounds Maintained**:
    - The entire explorer service, project search, metadata classification, and UI integration were implemented in 100% pure native Otter with **0 host-language workaround LOC**.
- **Toolchain Acceptance**:
  - `otter check .\OtterWorkspace` -> **PASSED** (exit code 0)
  - `otter test .\OtterWorkspace` -> **PASSED** (6/6 test suites passed: `app_test.ot`, `explorer_test.ot`, `project_management_test.ot`, `project_service_test.ot`, `project_store_test.ot`, `task_runner_test.ot`)
  - `otter build .\OtterWorkspace` -> **PASSED** (output `dist/`, exit code 0)
  - `otter publish .\OtterWorkspace` -> **PASSED** (artifact `publish/OtterWorkspace-0.1.0.zip`, SHA-256 computed, exit code 0)
  - `tests/Run-Tests.ps1` -> **PASSED** (54/54 test suites passing)
- **Workaround Audit**:
  - Host-Language Application Workaround LOC: **0** (Strictly maintained).

