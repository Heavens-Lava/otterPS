# Changelog

All notable changes to the Otter Programming Language platform are documented in this file.

## [Unreleased]

### Added
- **`otter profile <file.ot>`** (`src/Otter.Profiler.psm1`): runs a program normally, then reports which Otter functions ran (calls, total and self time) and which Otter source lines were hottest, in Otter terms only. Built on the interpreter's existing statement hook, so a normal `otter run` never loads it and pays nothing.

### Changed
- A `return` written directly in a function body now ends the call without throwing an exception (the profiler showed the exception was the single most expensive step per call). A `return` nested inside `if` or a loop behaves exactly as before.

### Fixed
- `otter debug` and `otter profile` with no file now exit with the usage-error code instead of 0.
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
