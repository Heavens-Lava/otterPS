# Otter 1.1 Master Checklist

> **Status (2026-09-30):** planning document on the `planning/1.1` branch. The
> decided 1.1 work (section 2) comes from `SPEC-DECISIONS.md` (the D56
> affirmation of 2026-09-29) and from `docs/OTTER_1_1_PLANNING.md`; nothing here
> is a decision until it is recorded in `SPEC-DECISIONS.md` with a D-number.
> Otter 1.0 is finished first: 1.1 work proceeds in parallel as design and
> experiments until 1.0.0 is published.

> **Release theme:** Build serious applications more naturally.
>
> Otter 1.1 expands the language only where Otter 1.0 dogfooding and production use demonstrate real friction. The 1.0 contract remains the compatibility baseline. New syntax and semantics must be deliberate, specified, tested, and reachable through the production toolchain.

## 0. Release Rules

- [ ] Otter 1.0 grammar remains backward compatible.
- [ ] Every 1.0-valid program remains valid unless correcting a documented security defect.
- [ ] No silent semantic changes.
- [ ] New grammar requires an explicit specification decision before implementation.
- [ ] New capabilities require production `.ot` examples.
- [ ] Interpreter and compiled/Web behavior must agree where the capability exists on both targets.
- [ ] Unsupported host capabilities fail explicitly.
- [ ] Every new public capability receives positive and negative tests.
- [ ] New syntax receives parser, AST, semantic, and conformance coverage.
- [ ] No feature is advertised until reachable through the production CLI/runtime.
- [ ] PowerShell reference implementation remains the semantic oracle until a replacement backend is independently certified.
- [ ] Performance optimization cannot change observable semantics.
- [ ] Native/direct compilation work must be differential-tested against the reference implementation.
- [ ] Otter 1.1 does not require rewriting the reference implementation.
- [ ] Features may be implemented experimentally without becoming 1.1 release blockers.
- [ ] Every release-blocking capability must have an explicit owner, test evidence, and release gate.

## 1. Otter 1.0 Follow-Up Cleanup

- [ ] Review `docs/OTTER_1_0_FREEZE_FOLLOWUPS.md`.
- [ ] Classify every remaining item as 1.1 required, 1.1 optional, later, or rejected.
- [ ] Resolve remaining documentation conflicts.
- [ ] Resolve remaining cross-runtime discrepancies.
- [ ] Review accidental parser syntax discovered during the 1.0 audit.
- [ ] Review diagnostics-quality findings.
- [ ] Review CLI usability findings.
- [ ] Review Web compiler follow-ups.
- [ ] Review module/path hardening follow-ups.
- [ ] Review HTTP/download timeout behavior.
- [ ] Review URL/error-message information exposure.
- [ ] Review `otter serve` robustness.
- [ ] Preserve all 1.0 regression tests.

### 1.1 Before 1.0.0 (rc.9 and release)

Work done on the 1.0 line after rc.8, waiting to merge into an rc.9 (branches
`release/installed-cli-workflow` through `perf/benchmark-suite`, all pushed):

- [x] Built and published console apps get a POSIX `run` launcher beside `run.cmd` (D129 gap found by the installed-workflow test).
- [x] `otter help` lists `otter serve`.
- [x] Distribution test runs `new`/`check`/`test`/`run`/`build`/`publish` through the installed payload (Windows PowerShell 5.1 and Linux).
- [x] `tools/Test-OtterDocumentedCli.ps1`: 28 documented CLI claims checked against the installed payload.
- [x] Reviewed resource soak with measured leak checks (`docs/RESOURCE_SOAK_RESULTS.md`).
- [x] Documentation reconciled with D122-D131 and D114; platform boundaries labelled at point of use.
- [x] Benchmark suite with compile, HTTP and UI sections; first 1.0 baseline recorded.
- [x] D130 limited to loops that set up a handler (other loops run the rc.7 code).
- [x] `tools/Test-OtterMacInstall.sh`: one-command macOS/Linux install test for a release zip.
- [ ] Cut rc.9 from those branches and certify it (release certification, recursion probe, desktop smoke, Linux, four-host run).
- [ ] macOS hands-on test (Jeff's Mac; the agent prompt and `tools/Test-OtterMacInstall.sh` are ready).
- [ ] Clean-machine and per-user installer test on a fresh Windows machine or VM.
- [ ] Four-host GitHub run on the candidate (blocked by the GitHub Actions spending limit; or make the repository public).
- [ ] Tag, publish the GitHub Release with the zip, and publish the website (`website/improvements`).

### 1.2 Post-1.0 follow-ups found during the 1.0 release work

- [ ] An ambiguous short flag (`otter run app.ot -p`) prints PowerShell's own parameter-binding error, not an Otter message (D14). Needs a launcher-level fix and a CLI contract decision.
- [ ] `otter debug` and `otter profile` work but are undocumented: decide whether they are public.
- [ ] Web: an uncaught runtime error appears only in the browser's developer console and the page stops; decide whether pages show errors visibly.
- [ ] Web compile grows memory by about 17 MB over 200 compiles in one process (soak review); run a longer soak before relying on long-lived compilers (Studio, `otter serve`).
- [ ] The release zip is post-processed after Compress-Archive (forward-slash names, Unix modes); consider writing the archive directly.
- [ ] A published app's `run` launcher is executable inside the zip only when published on macOS/Linux; decide whether Windows-published zips should record Unix modes too.
- [ ] `docs/V1_CHECKLIST_RECONCILIATION.md` still states console HTTP is web-only and modules are deferred (reversed by DC1 and D122).
- [x] Parser: a reserved word used as a variable at the top level (`count is 3`) gives "I expected a value here" instead of the reserved-word message (Codex).
- [x] Parser: D27's `replace "a" with "b" in name into other` is decided and the interpreter supports it, but the 1.0 parser rejects the `into` form ("I expected the replace statement to end here") (Codex).
- [ ] Importing `src/Otter.Interpreter.psm1` makes a PowerShell script's `exit N` return exit code 0 (`otter.ps1` uses `[Environment]::Exit` for this reason); find and fix the cause, or document it for tool authors.
- [x] Parser: `add amount days to date` with a variable amount is rejected ("I expected "to" and a variable name"); D32.3 makes the amount an expression and only literals parse (Codex).
- [ ] `convert date to json` writes .NET's raw object (`{"Value": "\/Date(1706684400000)\/", "HasTime": false}`, local-time dependent) instead of a date text. Decide the JSON form of a date (the compiled backend reproduces it today).
- [ ] JSON output differs by platform: `convert 5 to json` gives `5` on Windows PowerShell 5.1 and `5.0` on PowerShell 7 (macOS, Linux), because the two ConvertTo-Json implementations differ (found 2026-10-07 while testing fast start). Decide one Otter JSON format for every platform.
- [ ] Equality's last fallback compares PowerShell's text of two values, so a list equals its text (`1, 2` equals `"1 2"`) and any two types are equal. Decide whether 1.1 keeps this (the compiled backend reproduces it today).

## 2. Decided 1.1 Work — OtterBoard and Runtime UI

> This is the 1.1 flagship. OtterBoard (the planning application in
> `C:\Users\jmacy\projects\OtterBoard`, proposal branch
> `proposal/1.1-otterboard`) is the 1.1 flagship and dogfood application: the
> features below exist because building it needed them.

### 2.1 D56: `hide`, `show`, `focus` and `clear` (decided 2026-09-29)

D56 stands for 1.0 (these are refused with "'hide' is not supported in Otter
1.0."). For 1.1 they are planned on the console (WPF) and the web target
together:

- [ ] Record the 1.1 D-number that replaces the 1.0 refusal.
- [ ] `hide x` / `show x` make a UI resource invisible / visible again (`show` of a window keeps its 1.0 meaning).
- [ ] `focus x` moves keyboard focus.
- [ ] `clear x` empties a container; a text box loses its text, a dropdown its options, a list its items. `clear` stays usable as a name elsewhere.
- [ ] Same behaviour on console and web; certified together (console WPF tests, headless-browser tests).
- [ ] Wrong targets are Otter errors with the interpreter's wording.
- [ ] Documentation pages updated where they say these are not part of 1.0.

### 2.2 Accepted OtterBoard proposals (accepted in principle 2026-09-30)

Source: `docs/UI_RUNTIME_AND_PHRASES.md` on `proposal/1.1-otterboard`;
review: `docs/OTTER_1_1_PLANNING.md`. Each becomes a D-number before it merges.

- [ ] **P1 Runtime UI: elements are values.** Component functions return UI; `remove`, `clear`, `show`/`hide`/`focus` (2.1) at run time on declared and built elements; mistakes are Otter errors.
- [ ] **P2 Shared properties.** `style` (keep `class` only if a 1.0 program can already use it), `hidden`, `enabled`, `tooltip`, `label`, `shortcut`, `icon` and the page `icons` sprite; the `submitted` event; computed and bare declarations; the three-level look rule; stylesheets can change row/column layout; `otter-drop-over`.
- [ ] **P8 Browser storage.** In a plain browser tab, files persist in the page's own storage (builds on D131, which made them errors in 1.0).
- [ ] **P9 Desktop.** Window size from the page; `otter web -SourceDir`; `otter run` opens page programs in the desktop host (refused on macOS/Linux, D129); startup grace starts when the window opens.
- [ ] Rebase the proposal branch onto the 1.0 line (it starts from rc.4 and lacks D129-D131).
- [ ] Release-surface record updated for every accepted proposal.

### 2.3 Syntax proposals with Codex (P3-P6)

Status 2026-09-30: sent to Codex for grammar design (Jeff's decision). Not
accepted yet; the parser changes on the proposal branch are Codex's to accept,
rewrite or reject.

- [ ] **P3 Phrase functions** (prepositions introduce parameters). Concern: `with`, `for`, `to`, `in`, `from` already mean something; every combination needs a parse test.
- [x] **P4 `into` for a call's result** (`make` stays).
- [ ] **P5 `its`** inside `each`/`find`; `find` without `into`. Rethink `return x in xs where`, which reads like a membership test.
- [ ] **P6 Smaller gaps:** `an` (supported); `return` of a comparison; computed date moves; `weekday of`; `text of number`; duplicate function names an error; `wait` on web/desktop. Hold `and` as an argument separator: `and` already adds (D11).

### 2.4 P7 fixes already made in 1.0

- [x] A handler set up in a loop pass remembers that pass (D130, rc.8; console and web).
- [x] Browser file operations without the desktop application are errors (D131, rc.8).
- [x] Top-level `has` with a variable uses the variable's value on the web (rc.8).
- [ ] Remaining P7 items: calls to async user functions awaited program-wide (file-read case not yet reproduced on 1.0); `replace ... in x` inside a function changes the local `x`.

## 3. D99 — Otter Query Language

### 3.1 Design

- [ ] Reopen D99 as an Otter 1.1 design proposal.
- [ ] Define query grammar.
- [ ] Decide whether queries operate over database providers, lists/collections, or both.
- [ ] Define `where`.
- [ ] Define `order by`.
- [ ] Define ascending/descending.
- [ ] Define `take`.
- [ ] Define projection.
- [ ] Define result shape.
- [ ] Define empty-result behavior.
- [ ] Define `gone` semantics.
- [ ] Define parameterization.
- [ ] Define error behavior.
- [ ] Define provider contract.
- [ ] Define transaction relationship.
- [ ] Prevent SQL injection by construction.
- [ ] Decide whether joins belong in 1.1 or later.

### 3.2 Implementation

- [ ] Add parser support.
- [ ] Add AST representation.
- [ ] Add interpreter support.
- [ ] Add provider interface.
- [ ] Implement first production provider.
- [ ] Add parameter binding.
- [ ] Add result conversion.
- [ ] Add cancellation where supported.
- [ ] Add positive tests.
- [ ] Add malformed-query tests.
- [ ] Add provider-failure tests.
- [ ] Add injection regression tests.
- [ ] Add production `.ot` application example.
- [ ] Add Query Language documentation.

Target readability:

```otter
get name and email from customers in db
    where state is "Arizona"
    order by name ascending
    take 10
    into customers
```

## 4. Program Permissions & Capability Security

> The removed Studio permissions card must not return until permissions are actually enforced.

### 4.1 Design

- [ ] Create formal permissions proposal.
- [ ] Decide whether permissions belong in `otter.json`.
- [ ] Decide whether capabilities are declared, granted, or both.
- [ ] Define default behavior.
- [ ] Define compatibility behavior for 1.0 projects with no permission declaration.
- [ ] Define whether permissions apply to imported modules.
- [ ] Define permission inheritance.
- [ ] Define CLI overrides.
- [ ] Define development behavior.
- [ ] Define packaged-application behavior.
- [ ] Define whether a user can inspect requested capabilities before running an application.
- [ ] Define whether permission changes invalidate build/publish artifacts.

### 4.2 Candidate Capabilities

- [ ] File read.
- [ ] File write.
- [ ] Process execution.
- [ ] HTTP/network access.
- [ ] TCP.
- [ ] UDP.
- [ ] WebSockets.
- [ ] Local server/listening sockets.
- [ ] Clipboard.
- [ ] Credentials/secrets.
- [ ] File watching.
- [ ] Notifications.
- [ ] External URL/application launch.

### 4.3 Enforcement

- [ ] Enforce permissions below individual language statements.
- [ ] `run` cannot bypass process permission.
- [ ] `run command` cannot bypass process permission.
- [ ] HTTP cannot bypass network permission.
- [ ] TCP/UDP/WebSocket cannot bypass network permission.
- [ ] Libraries/modules cannot bypass application permissions.
- [ ] Denied operations produce Otter diagnostics.
- [ ] No permission denial silently does nothing.
- [ ] Test console runtime.
- [ ] Test desktop runtime.
- [ ] Define Web behavior separately where browser security already governs access.
- [ ] Add hostile-project tests.
- [ ] Add permission-escalation tests.
- [ ] Add capability-discovery API for tooling.
- [ ] Document that Otter permissions are an application capability boundary, not a replacement for OS security.

Example direction only — not frozen grammar:

```json
{
  "permissions": {
    "files": "project",
    "network": true,
    "processes": false,
    "clipboard": false
  }
}
```

## 5. Modules & Packages 1.1

- [ ] Review 1.0 module limitations.
- [ ] Preserve exact-case D122 behavior.
- [ ] Formalize package identity.
- [ ] Formalize module identity.
- [ ] Define package metadata.
- [ ] Define dependency declaration.
- [ ] Decide dependency version syntax.
- [ ] Define deterministic dependency resolution.
- [ ] Define local dependencies.
- [ ] Define package cache.
- [ ] Define offline behavior.
- [ ] Define dependency conflicts.
- [ ] Define circular dependency diagnostics.
- [ ] Add dependency integrity verification.
- [ ] Prevent dependency path escape.
- [ ] Add reproducible package-resolution tests.
- [ ] Decide whether `otter add` belongs in 1.1.
- [ ] Decide whether `otter remove` belongs in 1.1.
- [ ] Decide whether a public package registry belongs in 1.1 or later.

## 6. Collections & Data Improvements

- [ ] Review list performance and ergonomics.
- [ ] Decide whether Otter needs a first-class set type.
- [ ] Decide whether Otter needs a first-class dictionary/map type.
- [ ] Decide filtering syntax.
- [ ] Decide mapping/transformation syntax.
- [ ] Decide sorting improvements.
- [ ] Decide grouping.
- [ ] Decide distinct/unique operations.
- [ ] Improve `contains` implementation if benchmarks justify it.
- [ ] Add collection benchmarks.
- [ ] Preserve simple English syntax.
- [ ] Avoid introducing LINQ-like complexity solely for feature parity.

## 7. Async & Concurrency 1.1

- [ ] Preserve cooperative event semantics by default.
- [ ] Preserve one-handler-at-a-time behavior unless explicitly changed by a future proposal.
- [ ] Preserve bounded event-loop work.
- [ ] Improve fairness regression tests.
- [ ] Review cancellation across asynchronous operations.
- [ ] Standardize asynchronous handle states where practical: pending, completed, failed, cancelled.
- [ ] Review retained terminal events.
- [ ] Improve HTTP cancellation.
- [ ] Add network timeouts.
- [ ] Add download timeouts.
- [ ] Review async file operations.
- [ ] Decide whether explicit parallelism belongs in 1.1 or later.
- [ ] Do not expose host threads merely because the host supports them.
- [ ] Add long-running event-loop soak tests.

## 8. HTTP & Networking 1.1

- [ ] Consolidate HTTP API documentation.
- [ ] Add explicit timeout support.
- [ ] Improve cancellation.
- [ ] Define redirect policy.
- [ ] Add upload support if justified.
- [ ] Add download progress if justified.
- [ ] Add streaming responses if justified.
- [ ] Improve structured network errors.
- [ ] Avoid leaking credentials through errors.
- [ ] Sanitize URLs in diagnostics.
- [ ] Preserve HTTP header validation.
- [ ] Document TLS behavior.
- [ ] Review WebSocket reliability.
- [ ] Review TCP lifecycle.
- [ ] Review UDP lifecycle.
- [ ] Integrate network permissions if the capability model is accepted.

## 9. File System 1.1

- [ ] Formalize canonical path behavior.
- [ ] Formalize symlink behavior.
- [ ] Formalize junction behavior on Windows.
- [ ] Centralize project-root containment helpers.
- [ ] Preserve atomic-write guarantees.
- [ ] Add temporary-file API if dogfooding demonstrates need.
- [ ] Expand file metadata if justified.
- [ ] Review permission/ownership APIs.
- [ ] Define read-only/writable behavior.
- [ ] Define cross-platform owner semantics.
- [ ] Harden recursive operations.
- [ ] Add explicit safeguards for destructive operations.
- [ ] Improve diagnostics for permission failures.
- [ ] Keep file permission APIs distinct from application capability permissions.

## 10. Diagnostics 1.1

- [ ] Introduce stable diagnostic IDs.
- [ ] Include file, line, column/source span when available.
- [ ] Every diagnostic states the problem.
- [ ] Add deterministic suggested corrections where safe.
- [ ] Distinguish syntax, runtime, provider, and host-capability errors.
- [ ] Remove remaining raw PowerShell exceptions.
- [ ] Remove “bug in Otter” for ordinary user mistakes.
- [ ] Improve unknown-name diagnostics.
- [ ] Improve reserved-word diagnostics.
- [ ] Preserve module path case-correction diagnostics.
- [ ] Improve manifest diagnostics.
- [ ] Improve networking diagnostics.
- [ ] Add permission-denied diagnostics.
- [ ] Add machine-readable diagnostics for IDEs and agents.

## 11. Tooling & Agent Experience

- [ ] Machine-readable `otter check`.
- [ ] Machine-readable `otter test`.
- [ ] Machine-readable build results.
- [ ] Structured diagnostics.
- [ ] Stable exit-code contract.
- [ ] Runtime capability discovery.
- [ ] Language-version discovery.
- [ ] Project metadata discovery.
- [ ] Agent-friendly documentation index.
- [ ] Deterministic formatter if justified.
- [ ] Add `otter doctor`.
- [ ] Environment/runtime diagnostics.
- [ ] Dependency diagnostics.
- [ ] Improve profiler output.
- [ ] Add benchmark comparison tooling.
- [ ] Provide a stable command/tool manifest for coding agents.

Example direction:

```text
Otter 1.1.0
PowerShell 7.6
Windows 11

Console     ready
Web         ready
Desktop     experimental
Network     ready
Credentials ready

Project     valid
Modules     4
Tests       18
```

## 12. Testing Framework 1.1

- [ ] Add assertion vocabulary only where demonstrated necessary.
- [ ] Test setup.
- [ ] Test cleanup.
- [ ] Temporary directories.
- [ ] Expected-failure testing.
- [ ] Better test discovery.
- [ ] Test filtering.
- [ ] Individual test selection.
- [ ] Machine-readable results.
- [ ] Test timing.
- [ ] Failure source locations.
- [ ] Stable test exit-code contract.
- [ ] Parallel testing only if deterministic.

## 13. Web Compiler 1.1

- [ ] Formalize Web compiler contract.
- [ ] Preserve the frozen stylesheet discovery rule.
- [ ] Expand CSS round-trip tests.
- [ ] Preserve asset containment.
- [ ] Test nested entry-point assets.
- [ ] Preserve offline-first generated output.
- [ ] HTML escaping audit.
- [ ] CSS escaping audit.
- [ ] JavaScript escaping audit.
- [ ] Event-handler generation tests.
- [ ] Runtime-created control behavior.
- [ ] Handle-aware element lookup regression coverage.
- [ ] Multiple-handler regression coverage.
- [ ] Shared Otter value formatter.
- [ ] Browser compatibility matrix.
- [ ] Accessibility defaults.
- [ ] Responsive-layout behavior.
- [ ] Optional production minification if justified.
- [ ] Source maps if practical.
- [ ] Runnable documentation samples compile in isolated UI scopes.
- [ ] Build output remains deterministic.

## 14. Desktop 1.1

- [ ] Decide whether WPF remains the reference desktop host.
- [ ] Decide whether Electron becomes an official backend.
- [ ] Do not promise Electron until implementation exists.
- [ ] Define a desktop host interface independent of a single GUI framework.
- [ ] Window lifecycle.
- [ ] Menus.
- [ ] Dialogs.
- [ ] Clipboard.
- [ ] Drag/drop.
- [ ] File associations.
- [ ] Native notifications.
- [ ] Application icons.
- [ ] Packaging.
- [ ] Installer.
- [ ] Portable application.
- [ ] Update behavior.
- [ ] Windows certification.
- [ ] macOS strategy.
- [ ] Linux strategy.
- [ ] Decide when Desktop can graduate from experimental.

## 15. Otter Studio

> Studio development remains separate from language release gates unless explicitly promoted into the 1.1 product surface.

- [ ] Never rewrite hand-written `.ot` code destructively.
- [ ] Never overwrite `styles.css` merely by Save/Run.
- [ ] Preserve comments.
- [ ] Preserve functions.
- [ ] Preserve loops.
- [ ] Preserve unknown constructs.
- [ ] CSS round-trip preserves `@media`.
- [ ] CSS round-trip preserves data URIs.
- [ ] Undo restores source-affecting designer operations.
- [ ] Existing-project creation cannot overwrite silently.
- [ ] Designer operates on structured source safely.
- [ ] Preview and production compiler agree.
- [ ] Studio uses documented language behavior.
- [ ] Studio permissions UI remains absent until permissions are enforced.
- [ ] Add destructive-edit regression suite.
- [ ] Decide whether Studio is bundled with Otter 1.1 or remains a separate preview.

## 16. Language Server / IDE Protocol

- [ ] Decide LSP scope.
- [ ] Syntax diagnostics.
- [ ] Semantic diagnostics.
- [ ] Hover.
- [ ] Go to definition.
- [ ] Find references.
- [ ] Document symbols.
- [ ] Completion.
- [ ] Signature help.
- [ ] Rename.
- [ ] Reserved-word awareness.
- [ ] Module awareness.
- [ ] Incremental parsing strategy.
- [ ] VS Code proof of concept.
- [ ] Studio consumes the same language service rather than inventing another parser.

## 17. Performance

- [x] Record the Otter 1.0 benchmark baseline (`benchmarks/results/baseline-1.0-c404ef8.json`: interpreter, startup, compile, HTTP, UI; on `perf/benchmark-suite`, merging with rc.9).
- [ ] Preserve the Otter 1.0 benchmark baseline on master.
- [ ] Establish the Otter 1.1 baseline.
- [ ] Detect benchmark regressions automatically.
- [ ] Investigate remaining event-dispatch cost.
- [ ] Investigate function dispatch.
- [ ] Investigate collection lookup.
- [ ] Investigate startup time.
- [ ] Investigate parser time.
- [x] Establish memory baseline (`docs/RESOURCE_SOAK_RESULTS.md`, reviewed on rc.8: 8 workloads stable; no files, child processes or handles left behind).
- [ ] Add long-running memory/resource soak tests (the 1.0 soak is short; web compile needs a longer run).
- [ ] Optimize only measured bottlenecks.
- [ ] Differential-test every semantic optimization.
- [ ] Keep PowerShell reference behavior as the compatibility oracle.

## 18. Direct / Native Compilation Track

> Goal: allow Otter programs to run without interpreting every statement through PowerShell at runtime, while preserving exactly the same Otter semantics.

### 18.1 Architecture Decision

- [x] Write `docs/OTTER_NATIVE_COMPILER_DESIGN.md` (first draft, 2026-09-30).
- [x] Decide build/runtime prerequisites first: hybrid (decided 2026-09-30) - accelerated runs need nothing extra; executables use the .NET SDK when present (design document section 2).
- [x] Decide the C# language ceiling: C# 5, so Windows PowerShell 5.1 works (decided 2026-09-30).
- [x] Generated coverage list of every node kind: `docs/NATIVE_COMPILER_COVERAGE.md` (`tools/New-OtterNativeCoverage.ps1`).
- [ ] Decide first backend:
  - [ ] C# source generation + .NET compilation
  - [ ] direct .NET IL generation
  - [ ] another backend only with written justification
- [ ] Prefer C# source generation as the first native backend unless benchmarks prove it inadequate.
- [ ] Define compiler pipeline: source → lexer → parser → AST → semantic analysis → backend-neutral IR/lowered AST → generated C#/.NET → executable/library.
- [ ] Define which standard-library functions remain runtime-library calls.
- [ ] Define how host capabilities are linked.
- [ ] Define source mapping from generated code back to `.ot`.
- [ ] Define compiler version compatibility.
- [ ] Define deterministic build requirements.

### 18.2 Do Not Rewrite the Language

- [ ] Reuse the existing lexer/parser/AST contract wherever possible.
- [ ] Do not fork grammar between interpreter and compiler.
- [ ] Do not create compiler-only syntax.
- [ ] Do not change semantics merely because C#/.NET behaves differently.
- [ ] Route platform differences through Otter runtime/provider abstractions.
- [ ] Treat the PowerShell implementation as semantic reference until native certification is complete.

### 18.3 Minimal Native Compiler Milestone

- [ ] Compile `say "hello"` to a runnable executable.
- [x] Compile variables.
- [x] Compile arithmetic.
- [x] Compile booleans/comparisons.
- [x] Compile `if`.
- [x] Compile loops (count, repeat, while, for each).
- [x] Compile functions.
- [x] Compile recursion (with the 250-call limit).
- [x] Compile lists (add, remove, contains, length/first/last of, sort, reverse).
- [x] Compile things/objects (plain things and declared types).
- [x] Compile strings (uppercase/lowercase of, replace, split, join).
- [x] Compile JSON (through the library bridge).
- [x] Preserve Otter value formatting.
- [x] Preserve contractual Otter error behavior (message, line, suggestion, exit code, for the compiled subset).
- [x] Preserve `gone`.
- [x] Preserve reserved identifier semantics (the shared parser and checks run first).
- [x] Preserve line/source information for diagnostics.

### 18.4 Standard Library Bridge

- [x] Create a compiled runtime library (`src/native/OtterNativeRuntime.cs`, C# 5).
- [ ] Move semantic helpers into backend-neutral/runtime-testable units where appropriate.
- [x] Files: write (atomically), append, read, read json, delete, copy, move, `file ... exists` (bridge to the interpreter's own functions in `Otter.Library.psm1`).
- [x] JSON: `convert ... to json` / `from json` (bridge).
- [x] dates/time: `today`, `now`, `date from`, add/remove, `between`, `format date`, date parts, comparison (mirrored in the runtime library; not milliseconds or elapsed time yet).
- [ ] random.
- [ ] bytes.
- [ ] HTTP.
- [ ] process execution.
- [ ] crypto.
- [ ] XML.
- [ ] modules.
- [ ] events.
- [ ] UI provider boundary.
- [ ] credentials.
- [ ] Ensure compiled code calls Otter semantics rather than raw .NET behavior when they differ.

### 18.5 Differential Certification

Reuse the existing comparison infrastructure rather than building a parallel
one: the conformance fixtures (`conformance/`, `tools/Test-OtterReleaseConformance.ps1`)
and the differential fuzzer (`tools/Invoke-OtterDifferentialFuzzer.ps1`, which
already compares two implementations of Otter) gain the native backend as
another implementation (design document section 5).

For every compiled feature:

- [x] Run the same `.ot` program through the PowerShell reference runtime.
- [x] Run it through the native compiler (`tools/Invoke-OtterDifferentialFuzzer.ps1 -IncludeNative`, `experiments/native-compiler/`).
- [x] Compare stdout.
- [x] Compare stderr/diagnostic category.
- [x] Compare exit status.
- [ ] Compare files/output artifacts where relevant (cases compare what is read back; no artifact diff yet).
- [ ] Compare deterministic random behavior when seeded.
- [x] Compare JSON behavior (`cases/ok_json.ot`, `err_json.ot`, the json benchmark).
- [ ] Compare numeric edge cases.
- [ ] Compare string/Unicode behavior.
- [ ] Compare collection behavior.
- [x] Compare error behavior.
- [x] Add mismatches to a permanent regression corpus (`experiments/native-compiler/cases`).

### 18.6 Native Compiler Performance Gates

- [x] Measure compile time (100-350 ms per program, cached).
- [ ] Measure cold startup.
- [x] Measure arithmetic benchmark.
- [x] Measure loop benchmark.
- [x] Measure function-call benchmark.
- [x] Measure recursion benchmark.
- [ ] Measure list benchmark.
- [ ] Measure object benchmark.
- [ ] Measure strings.
- [x] Measure JSON (2.2x: the time is in the library, not the language).
- [x] Measure file I/O (1.3x: the time is in the file system).
- [ ] Measure event dispatch where supported.
- [x] Compare against Otter 1.0 PowerShell baseline (`tools/Invoke-OtterBenchmarks.ps1 -Native`: 480x-1,700x).
- [ ] Do not advertise performance numbers without reproducible benchmark records.

### 18.7 CLI Integration

Possible future commands — syntax not frozen:

- [ ] Decide whether `otter build` automatically chooses a native backend.
- [ ] Or add explicit target selection such as `otter build --target dotnet`.
- [ ] Decide executable naming.
- [ ] Decide framework-dependent vs self-contained publishing.
- [ ] Decide runtime prerequisites.
- [ ] Add `otter run` path for compiled programs.
- [ ] Add native build cache.
- [ ] Add clean/rebuild behavior.
- [ ] Add compiled artifact metadata.
- [ ] Ensure `otter check` uses the same semantic validation before compilation.

### 18.8 Native Backend Release Status

- [x] Experimental prototype (branch `native/prototype`; coverage in `docs/NATIVE_COMPILER_COVERAGE.md`).
- [ ] Dogfood-ready.
- [ ] Console language subset certified.
- [ ] Full 1.0 core semantics certified.
- [ ] Standard library certified.
- [ ] Cross-platform .NET host matrix certified.
- [ ] Security review.
- [ ] Performance baseline.
- [ ] Fresh-machine build test.
- [ ] Decide whether native compilation ships experimental in 1.1, stable in 1.1, or stable later.

> **Recommended 1.1 goal:** ship or dogfood a native compiler as an experimental backend without making it a release blocker for the rest of Otter 1.1.

## 19. Cross-Platform

- [x] Four-host reference-runtime matrix exists and passed for the 1.0 candidates (`.github/workflows/d120-host-matrix.yml`: Windows PowerShell 5.1 and PowerShell 7 on Windows, Linux and macOS; the Windows-built release zip installed on Linux and macOS). 1.1 must pass it again.

- [ ] Windows PowerShell 5.1.
- [ ] Windows PowerShell 7.
- [ ] Linux PowerShell 7.
- [ ] macOS PowerShell 7.
- [ ] Native/.NET Windows backend if implemented.
- [ ] Native/.NET Linux backend if implemented.
- [ ] Native/.NET macOS backend if implemented.
- [ ] Module casing.
- [ ] Paths.
- [ ] Newlines.
- [ ] File permissions.
- [ ] Process invocation.
- [ ] Networking.
- [ ] Credentials.
- [ ] Temporary directories.
- [ ] Unicode filenames.
- [ ] Non-ASCII source.
- [ ] Locale independence.

## 20. Security

- [ ] Update threat model.
- [ ] Project containment.
- [ ] Build containment.
- [ ] Publish containment.
- [ ] Symlink/junction handling.
- [ ] Command injection.
- [ ] Shell escaping.
- [ ] HTTP header injection.
- [ ] SSH option injection.
- [ ] Path traversal.
- [ ] Zip-slip.
- [ ] XML safety.
- [ ] HTML escaping.
- [ ] JavaScript escaping.
- [ ] CSS escaping.
- [ ] Secret handling.
- [ ] Error-message information disclosure.
- [ ] Dependency integrity.
- [ ] Permission/capability model if approved.
- [ ] Native compiler generated-code injection review.
- [ ] Malicious-project regression corpus.

## 21. Formal Specification 1.1

- [ ] Update grammar.
- [ ] Update AST contract.
- [ ] Update semantics.
- [ ] Update reserved identifiers.
- [ ] Update event contract only if semantics actually change.
- [ ] Query specification if D99 ships.
- [ ] Permission specification if permissions ship.
- [ ] Package/module specification.
- [ ] Diagnostics specification.
- [ ] Host capability specification.
- [ ] Native compiler equivalence specification.
- [ ] Compatibility chapter: 1.0 → 1.1.
- [ ] Explicit list of experimental capabilities.

## 22. Documentation

- [ ] Otter 1.1 language tour.
- [ ] Migration from 1.0.
- [ ] Query guide if shipped.
- [ ] Permissions guide if shipped.
- [ ] Modules/packages.
- [ ] HTTP/networking.
- [ ] Files.
- [ ] Testing.
- [ ] Diagnostics.
- [ ] Web applications.
- [ ] Desktop status.
- [ ] Native compiler status and limitations.
- [ ] Agent/tooling guide.
- [ ] Every example checked by compiler.
- [ ] Every runnable Web sample browser-tested.
- [ ] Internal links checked.
- [ ] No documentation for features absent from release.

## 23. Dogfood

- [ ] OtterBoard is the 1.1 flagship dogfood application: rebuilt on the 1.1 line with the section 2 features and no host-language workarounds.
- [ ] Continue OtterWorkspace on 1.1.
- [ ] Build at least one new substantial Otter application.
- [ ] Application uses modules.
- [ ] Application uses async work.
- [ ] Application uses files.
- [ ] Application uses HTTP.
- [ ] Application uses tests.
- [ ] Application uses packaging.
- [ ] Application exercises each flagship 1.1 feature intended to ship.
- [ ] Compile at least one substantial dogfood program with the native backend if available.
- [ ] Compare interpreted and compiled behavior.
- [ ] Record every workaround.
- [ ] Zero unjustified host-language application workarounds.
- [ ] Any severe language friction becomes a documented proposal rather than ad-hoc grammar.

## 24. Otter 1.1 Flagship Scope

The decided flagship (D56 affirmation, 2026-09-29):

- [ ] **OtterBoard with runtime UI** — section 2: D56 `hide`/`show`/`focus`/`clear` on console and web, and the accepted proposals P1, P2, P8, P9.

Major 1.1 tracks. Each ships in 1.1 only if it is certified; none replaces the
flagship, and which of them ship is decided as they mature:

- [ ] **D99 Query Language** (section 3)
- [ ] **Program permissions/capabilities** (section 4)
- [ ] **Diagnostics and agent tooling** (sections 10-11)
- [ ] **Web compiler maturity** (section 13)
- [ ] **Native/direct compilation** (section 18) — experimental; cannot block 1.1.

May advance without automatically blocking 1.1:

- [ ] Packages/registry.
- [ ] LSP.
- [ ] Studio rehabilitation.
- [ ] Desktop backend expansion.
- [ ] Electron.
- [ ] Advanced concurrency.
- [ ] Native compiler stable status.

## 25. Otter 1.1 Release Gates

- [ ] 1.1 grammar frozen.
- [ ] 1.1 semantics frozen.
- [ ] No unresolved 1.1 specification decisions.
- [ ] All 1.0 programs remain compatible within documented policy.
- [ ] OtterBoard certified through the production entry points (console and web).
- [ ] D56 UI actions certified on console and web together.
- [ ] Accepted OtterBoard proposals recorded as D-numbers and certified.
- [ ] D99 certified if shipped.
- [ ] Permissions certified if shipped.
- [ ] New standard-library APIs certified.
- [ ] Console certified.
- [ ] Web certified.
- [ ] Desktop status accurately advertised.
- [ ] Native compiler status accurately advertised.
- [ ] Four-host reference-runtime matrix green.
- [ ] Native host matrix green if native backend is advertised.
- [ ] Conformance green.
- [ ] Differential testing green.
- [ ] Native-vs-reference differential suite green if applicable.
- [ ] Parser fuzzing green.
- [ ] Malformed-input fuzzing green.
- [ ] Security regression corpus green.
- [ ] Performance has no unexplained major regression.
- [ ] Clean checkout after certification.
- [ ] Fresh installation verified.
- [ ] Upgrade from 1.0 verified.
- [ ] Offline workflow verified where promised.
- [ ] Documentation frozen.
- [ ] Website matches release.
- [ ] Dogfood application certified.
- [ ] No known data-loss bugs.
- [ ] No known critical security bugs.
- [ ] No advertised feature silently does nothing.
- [ ] Exact candidate SHA certified.
- [ ] Tag `v1.1.0-rc.1`.
- [ ] RC stabilization.
- [ ] Tag `v1.1.0`.

# Suggested 1.1 Development Order

```text
Otter 1.0 frozen
    |
    +-- 0. Publish 1.0.0 (rc.9, macOS, clean machine, tag)
    +-- 1. Freeze 1.1 goals and decision process
    +-- 2. 1.0 follow-up triage
    +-- 3. OtterBoard: D56 UI actions + accepted proposals (flagship)
    +-- 4. Native compiler: prerequisites decision, then prototype (parallel, experimental)
    +-- 5. Diagnostics / machine-readable tooling
    +-- 6. D99 Query Language design + implementation
    +-- 7. Permission/capability model design + enforcement
    +-- 8. Web compiler hardening
    +-- 9. Modules/packages improvements
    +-- 10. Dogfood everything in real Otter applications
    +-- 11. Performance + cross-platform certification
    +-- 12. 1.1 contract freeze
    +-- 13. Release certification
    |
    v
v1.1.0-rc.1
    |
    v
v1.1.0
```

# Native Compiler Principle

The native compiler must be treated as a **new implementation of Otter**, not a new language.

The PowerShell implementation defines the currently certified behavior. The compiler may become dramatically faster, but it does not get to reinterpret the language to make implementation easier.

```text
                  +-------------------------+
Otter source ---> | Lexer / Parser / AST    |
                  +------------+------------+
                               |
                     Semantic / Lowering
                               |
                    Backend-neutral model
                       +-------+--------+
                       |                |
                       v                v
              Reference Runtime   Native .NET Backend
                PowerShell          C# / IL
                       |                |
                       v                v
                 Oracle/Test      Compiled program
```

# Definition of Success

Otter 1.1 succeeds when it is **more capable without becoming less predictable**.

1. Otter 1.0 programs still work.
2. New 1.1 features are deliberate and documented.
3. Security controls are real rather than cosmetic.
4. Diagnostics are useful to both humans and coding agents.
5. The Web compiler behaves like a production backend.
6. Real applications can be built without host-language workarounds.
7. A native compiler, if included, produces behavior equivalent to the reference implementation.
8. Performance improves through measured engineering rather than semantic shortcuts.
