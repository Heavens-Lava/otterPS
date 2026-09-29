# Changelog

All notable changes to the Otter Programming Language platform are documented in this file.

## [Unreleased]

## [1.0.0-rc.4] - 2026-09-29

Fourth Otter 1.0 release candidate: rc.3 plus D128. Evidence:
`docs/OTTER_1_0_RC4_EVIDENCE.md`.

### Decided
- **D128:** web UI created while the page runs. On rc.3, `create`, `has`, `put`, `show` and `when` inside an event handler, function or loop compiled to nothing on the web/Electron target, so the page silently did nothing (for example the Add button of `examples/v1/tasks.ot`). They now behave as on the console.

### Fixed
- Inside a web handler, `status has text "..."` on a top-level element created an unrelated thing named `status` instead of changing the element.
- The web compiler compiled any statement it had no case for to nothing. It now refuses it: `hide`, `focus`, `memo`, `on start`/`on close`, `shared` and `use files` with the console's "not supported in Otter 1.0" message (D56), `start command` and server statements as unsupported on the web, anything else as not supported on the web target yet. Web programs that used these compiled before and silently skipped them; they now fail to compile.

### Changed
- `plus` can no longer stand in for `and` between two conditions (D123, in rc.3): `if a is 1 plus b is 2` is now a syntax error; write `and`.

## [1.0.0-rc.3] - 2026-09-28

Third Otter 1.0 release candidate, from the production-readiness audit of
rc.2 (CLI, manifest and build, language, diagnostics, web and Studio audits;
`docs/OTTER_1_0_FREEZE_FOLLOWUPS.md`). Every behavioural fix has a regression
test that fails on rc.2.

### Decided
- **D123 (D-1):** arithmetic in a condition means what it says: `if x plus 1 is 5` compares `x plus 1` with 5. On rc.2 it was silently read as `x and (1 is 5)`. The parser fix is implemented in the final RC3 candidate and covered by `tests/ConditionArithmetic.Tests.ps1`; final release certification remains required before tagging.
- **D124 (D-2):** a declaration the grammar would silently misread is refused before anything runs. Examples: `to main` (a line starting with `main` is read as a UI element and never calls the function), and a variable named `completed` (read as a job-state check in comparisons). See `docs/OTTER_1_0_RESERVED_WORDS.md`.
- **D125 (D-3):** the only web stylesheet rule is `<entry>.css` beside the entry file; `otter new web` creates `main.css`.
- **D126 (D-4):** web `say` output uses the console's formatting (D8).
- **D127 (D-5):** generated web applications load nothing from other hosts and work offline (system fonts; no Google Fonts).

### Fixed
- `otter new web` / `otter new game` suggested `otter run .`, which failed on the fresh project; they now suggest and record `otter web .`.
- A control with two `when` handlers compiled to a page whose script never ran (duplicate declaration); each handler is now scoped.
- The web scaffold's stylesheet was copied into `dist/` but never applied; the scaffold now uses `main.css`, which is inlined.
- A bad manifest (for example `"build": null`) crashed with a raw PowerShell error; every manifest field is type-checked with a message naming the field. Manifests that were silently accepted before are now refused: a number for `name` or `version`, a single string for `assets`, `"clean": "false"`.
- `otter.build.json` was invalid JSON when the project name contained a quote; build metadata is now written as JSON. Its indentation now comes from the PowerShell host.
- The `.sha256` file broke for non-ASCII project names; it is now UTF-8 without BOM, without the trailing blank line.
- `otter publish` could package files deleted from the project when `build.clean` was false; publish always packages a clean build.
- `otter serve` stopped after one aborted request; each request is now handled separately, and request bodies are capped at 10 MB (413 above it).
- Missing, folder or unreadable source files gave "a bug in Otter" or raw PowerShell errors; they now give an Otter message and exit 1.
- An absolute `use` path skipped the D122 exact-case check.
- Web `$` sequences in a stylesheet (`$_`, `$1`) corrupted the generated page.

### Security
- **Build and publish inputs stay inside the project.** The entry point, every asset and the web `<entry>.css` must resolve, following symbolic links and junctions, inside the project (for `<entry>.css`, the entry's folder). On rc.2 a symlinked asset or an `entryPoint` of `../x.ot` put files from outside the project into the published zip.
- The web page title is HTML-escaped; a title containing `</title><script>` ran script.

### Removed
- `otter studio` is no longer listed in `otter help`. Otter Studio is a separate preview and is not part of Otter 1.0. Without the Studio folder, `otter studio` says so and exits 1.

### Documentation
- Corrected the grammar reference (flat left-to-right arithmetic, no parentheses, `otherwise` optional), string escapes (`\n \t \\ \"`; no `\r`), one value per function argument, program arguments Otter itself consumes, Linux/macOS use with `pwsh`, REPL behaviour, and `otter check .` scope.
- New `docs/OTTER_1_0_PROJECT_MANIFEST.md` (the `otter.json` specification) and `docs/OTTER_1_0_RESERVED_WORDS.md`.
- Removed examples of syntax that is not part of 1.0; labelled database support as outside the certified 1.0 surface; removed the "sandboxed file operations" and "100% parity" claims; reconciled DC2–DC5.

## [1.0.0-rc.2] - 2026-09-28

Second Otter 1.0 release candidate. The 1.0 language contract is frozen and
every 1.0 contract decision is recorded in `SPEC-DECISIONS.md`; no contract
question remains open. (`v1.0.0-rc.1`, tagged 2026-09-11, was a baseline
checkpoint taken before the 1.0 scope was widened.) From this candidate to
1.0.0, only release-blocking fixes are accepted.

### Decided
- **Event contract (D121):** cross-source fairness is best-effort with eventual progress; no source may do unbounded work while another is ready; ordering is guaranteed within a source only; the loop is cooperative (one handler at a time, run to completion). Measured limits are runtime characteristics, documented in `docs/OTTER_1_0_EVENT_MODEL.md`.
- **Console HTTP is part of Otter 1.0 (DC1):** the HTTP client (D116A/D116B) is supported on console and web.
- **Module paths are case-sensitive on every host (D122 / M1):** a `use` path must match the on-disk name exactly; a case-only mismatch gives the same diagnostic on Windows, Linux and macOS.
- **The query language (D99) is deferred to Otter 1.1.** It is not part of Otter 1.0; the implementation remains in the source tree as an experimental preview, unchanged. Use `query` and `execute` with parameterized SQL.
- The decision ledger now records D99-D114 and D119, reconstructed from their approved specifications, commits and tests.

### Security
Found by the pre-release security and data-loss review; each fix has a regression test.
- **`otter publish`** refuses a manifest `version` that is not a plain version string (letters, digits, `.`, `+`, `-`). A crafted version such as `1/../../x` could make publish write files outside the project.
- **`otter build` and `otter publish`** only delete and replace an output folder that is empty or that Otter created (it holds `otter.build.json` / `otter.publish.json`), and never one containing the entry point, the manifest or `.git`. Before, `"outputDir": "src"` deleted the project's sources.
- **`Install-Otter.ps1 -Force`** only replaces a folder it recognises as an Otter installation (new `.otter-install` marker, or the full file set of an earlier install). It refuses non-empty folders that are not installs, the user profile and special folders, filesystem roots, relative and drive-relative paths, and any folder that contains or is inside the extracted package. Before, `-Force` deleted whatever folder it was given.
- **`Uninstall-Otter.ps1`** uses the same recognition and never deletes an unrecognised folder, even with `-Force`. Before, a source checkout (which has `otter.cmd` at its root) was treated as an installation.
- **`run command` and `run` on `.cmd`/`.bat` scripts** quote arguments by cmd.exe's own rules and refuse `"`, `%` and line breaks, which cmd.exe cannot take literally. Before, an argument such as `foo&calc` ran a second command (the "BatBadBut" class, CVE-2024-24576).
- **HTTP requests** refuse line breaks and NUL in header names and values. Before, a header value containing CR/LF injected extra headers.
- **`run command ... over ssh`** refuses a host that is empty, starts with `-`, or contains spaces, quotes or control characters, and passes `--` before the host. Before, a host such as `-oProxyCommand=...` was read as an ssh option that runs a local command.
- Known, not yet fixed: the Otter Studio development server (not part of the 1.0 distribution) is not safe on an untrusted network; see `docs/OTTER_1_0_FREEZE_FOLLOWUPS.md`.

### Added
- **Four-host support:** Windows PowerShell 5.1, and PowerShell 7 on Windows, Linux and macOS, all pass the portable language suite (D120 CI matrix).
- **Release certification runner** (`tools/Invoke-OtterReleaseCertification.ps1`): runs every release gate from a clean checkout of a nominated SHA and records the outcome of each. A final `repository-clean` check fails the run if any gate changes the working tree.
- Release-surface evidence manifest (`release/otter-1.0-surface.json`) with a read-only auditor, and contract coverage evidence.
- **`otter profile <file.ot>`** (`src/Otter.Profiler.psm1`): runs a program normally, then reports which Otter functions ran (calls, total and self time) and which Otter source lines were hottest, in Otter terms only. Built on the interpreter's existing statement hook, so a normal `otter run` never loads it and pays nothing.

### Changed
- Low-risk interpreter optimization pass (measured: 43% to 59% faster on arithmetic, loops, calls, recursion and list work; `contains` on a number list about 6.7x faster). Three local fast paths, none changing behavior: `Test-OtterEqual` for two plain numbers, `Assert-OtterNumber` for plain numbers, and variable reads of numbers, text and booleans skipping the list-protection wrapper. Verified against golden results captured before the change (`tests/Optimizations.Tests.ps1`), the full regression suite, all 15 conformance fixtures, and 1,000-program differential and malformed-input fuzzing. See `docs/OTTER_1_0_PERFORMANCE_BASELINE.md`.
- A `return` written directly in a function body now ends the call without throwing an exception (the profiler showed the exception was the single most expensive step per call). A `return` nested inside `if` or a loop behaves exactly as before.

### Fixed
- `otter debug` and `otter profile` with no file now exit with the usage-error code instead of 0.
- PowerShell 7 hosts: values, atomic writes and publish names now behave the same as on Windows PowerShell 5.1 (PowerShell 7 previously failed 15 suites).
- `wait` now services every event source; a program polling a socket inside `wait` could previously wait forever (D121, EV3).
- A busy command job can no longer starve other event sources (D121, EV2).
- The test suites no longer modify tracked files: Studio and web-compiler tests use temporary projects and output folders.
- `otter test` launches tests with the PowerShell host that is running Otter instead of a hard-coded `powershell.exe`, so it works on Linux and macOS (found by the D120 CI matrix).

## [1.0.0-rc.1] - 2026-09-17

### Added
- **Manifest-Driven Release Conformance Suite** (`tools/Test-OtterReleaseConformance.ps1`):
  - 15 hermetic fixtures covering hello, variables & control flow, functions, files, JSON, command execution, date math, try/fail, things & dynamic keys, collections & text, and negative diagnostics.
  - Live headless browser runtime execution via Microsoft Edge / Chromium (`--headless --disable-gpu --dump-dom`), verifying complete DOM mounting and script execution.
  - Hermetic isolation: test runner copies files into clean temporary working directories.
- **Distribution Packaging & Installer**:
  - `tools/New-OtterDistribution.ps1`: Builds versioned standalone distribution ZIP with SHA-256 checksum generation.
  - `distribution/Install-Otter.ps1`: Per-user Windows PowerShell 5.1 installer script with safety guardrails against filesystem root and payload root destinations.
  - `tools/Test-OtterDistribution.ps1`: Hermetic build, packaging, installation, version check, console run, and web compile verification.
- **Documentation & Audits**:
  - `docs/OTTER_1_0_CAPABILITY_MATRIX.md`: Explicit matrix separating Console, Web, Desktop, Portable Core, and Certification Status.
  - `docs/OTTER_1_0_SECURITY_REVIEW.md`: Comprehensive threat model and security audit.
  - `docs/OTTER_1_0_CLEAN_MACHINE_CERTIFICATION.md`: Step-by-step clean-machine installation and verification procedure.
  - `docs/OTTER_1_0_RC_NOTES.md`: Release Candidate notes and explicit scope definitions.
  - `docs/OTTER_1_0_RELEASE_GATE_CERTIFICATION.md`: Release-gate certification status across all platform components.

### Security Fixes
- **Web Notification Sanitization**: Fixed XSS / HTML injection in `src/Otter.Web.psm1` runtime notification UI by replacing `innerHTML` assignment with safe DOM construction using `textContent` for title and message.

### Semantic & Bug Fixes
- **`and`/`or` Outside Condition Disambiguation**: Restored `and` as valid addition and string-concatenation syntax outside conditional statements, moving boolean operand checks to the runtime evaluation layer with a clear diagnostic instead of an overbroad parser rejection. Preserved parse-time rejection for `or` outside conditions.

### Scope & Deferrals
- **Core Scope**: Windows PowerShell 5.1 console language and runtime (`otter run`, `otter check`), and web compiler (`otter web`).
- **HTTP**: Certified as target-specific for Web (`otter web` emits browser `fetch`). Console core cleanly reports unsupported diagnostic.
- **Modules**: `use` module system explicitly deferred post-1.0; compiler emits clear diagnostic.
- **Desktop/Server Listener**: Platform-dependent `HttpListener` hosting remains uncertified for this RC.
