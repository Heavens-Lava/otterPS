# Otter macOS test results

Run 2026-09-30 by Claude Code (test only, no edits/commits/pushes). Repo: `~/Projects/otterPS` (not `~/otterPS`).

## 1. Environment

```
$ git rev-parse --short HEAD; sw_vers; uname -m; pwsh --version
080fcf2
ProductName:		macOS
ProductVersion:		26.1
BuildVersion:		25B78
arm64
PowerShell 7.6.6
```
Branch `perf/benchmark-suite`. PowerShell installed with `brew install powershell` (the `powershell` cask the doc names no longer exists in Homebrew; it is now a formula).

## 2. Distribution

`pwsh -NoProfile -File tools/Test-OtterDistribution.ps1` → exit 0, 69s. PASS.

```
Removed the otter command from /var/folders/pj/dghk050n7kx0bsl76g9r9krm0000gn/T/otter-distribution-9e88a97227174ffa80eb6da66a4b59bf/home/.local/bin.
Otter has been uninstalled successfully.
Distribution smoke test passed on PowerShell 7.6.6: /var/folders/pj/dghk050n7kx0bsl76g9r9krm0000gn/T/otter-distribution-9e88a97227174ffa80eb6da66a4b59bf
```

## 3. Documented CLI

`pwsh -NoProfile -File tools/Test-OtterDocumentedCli.ps1` → exit 0, 113s. PASS — 28 passed, 0 failed.

## 4. Portable language and module suite

Each run as `pwsh -NoProfile -File tests/<name>` from the repo root.

| Test file | Exit | Time | Result |
|---|---|---|---|
| HostPortability.Tests.ps1 | 0 | 90s | 31 passed, 0 failed |
| EventContract.Tests.ps1 | 0 | 36s | 6 passed, 0 failed |
| Http.Tests.ps1 | 0 | 43s | 35 passed, 0 failed |
| Lexer.Tests.ps1 | 0 | 1s | Lexer tests passed. |
| Parser.Tests.ps1 | 0 | 7s | Parser tests passed. |
| Grammar.Tests.ps1 | 0 | 2s | 32 passed, 0 failed |
| Collections.Tests.ps1 | 0 | 4s | 22 passed, 0 failed |
| Objects.Tests.ps1 | 0 | 3s | 14 passed, 0 failed |
| Data.Tests.ps1 | 0 | 4s | 15 passed, 0 failed |
| Dates.Tests.ps1 | 0 | 3s | 38 passed, 0 failed |
| Bytes.Tests.ps1 | 0 | 96s | 23 passed, 0 failed |
| Csv.Tests.ps1 | 0 | 5s | 41 passed, 0 failed |
| Xml.Tests.ps1 | 0 | 90s | 22 passed, 0 failed |
| Interpreter.Tests.ps1 | 0 | 6s | 75 passed, 0 failed |
| Conformance.Tests.ps1 | 0 | 6s | 13 passed, 0 failed |
| Module.Tests.ps1 | 0 | 2s | 11 passed, 0 failed |
| UseModuleProduction.Tests.ps1 | 0 | 42s | 10 passed, 0 failed |
| Project.Tests.ps1 | 0 | 38s | 15 passed, 0 failed |
| ProjectBuild.Tests.ps1 | 0 | 196s | 20 passed, 0 failed |
| ProjectCreationAndTestRunner.Tests.ps1 | 0 | 190s | 19 passed, 0 failed |
| ProjectPublish.Tests.ps1 | 0 | 139s | 24 passed, 0 failed |
| Web.Tests.ps1 | 0 | 29s | 36 passed, 0 failed |
| WebRuntimeUi.Tests.ps1 | 0 | 8s | 5 passed, 0 failed |
| PlatformBoundaries.Tests.ps1 | 0 | 65s | 15 passed, 0 failed |

All 24 exit 0, no failing cases.

## 5. Real Windows-built download

SKIPPED — `~/Downloads/otter-mac-test` does not exist, so `tools/Test-OtterMacInstall.sh` was not run.

## 6. `./otter web examples/hello-app.ot`

Exit 1. **FAIL** — page compiles but no browser opens.

```
Otter Web application compiled to: /Users/jeffreymacy/Projects/otterPS/examples/hello-app.html
Otter: I could not open a browser. The page is at /Users/jeffreymacy/Projects/otterPS/examples/hello-app.html - open it yourself, or use -NoOpen to skip this step.
exit 1
```

Cause: `otter.ps1:878` calls `Start-Process $htmlPath`. On macOS under PowerShell 7.6.6 that tries to *execute* the .html file:

```
$ pwsh -NoProfile -c 'Start-Process ".../examples/hello-app.html"'
System.ComponentModel.Win32Exception: An error occurred trying to start process
'/Users/jeffreymacy/Projects/otterPS/examples/hello-app.html' with working directory
'/Users/jeffreymacy/Projects/otterPS'. Permission denied
```

Both of these do open the page from the same pwsh, so a fix is straightforward:
- `[Diagnostics.Process]::Start(` a `ProcessStartInfo` with `UseShellExecute = $true` `)`
- `Start-Process -FilePath open -ArgumentList $htmlPath` on macOS

Note: this machine's default browser is Microsoft Edge, not Safari; `open -a Safari examples/hello-app.html` did show the page in Safari.

`tests/HostPortability.Tests.ps1:356` asserts the clean "I could not open a browser" failure, which is why the suite passes while the real launch fails.

Also: `examples/hello-app.html` is a tracked file. The doc says to delete it afterwards, but deleting it dirties the checkout, and rebuilding it changes it (`git diff --stat`: 79 insertions, 16 deletions — the committed copy is stale). It was restored with `git restore`.

## 7. Clean checkout

`git status --short` → exit 0, no output. PASS (after `git restore examples/hello-app.html`, see step 6).

## Summary

| Step | Result |
|---|---|
| 1. Environment | 080fcf2, macOS 26.1 (25B78), arm64, PowerShell 7.6.6 |
| 2. Test-OtterDistribution.ps1 | PASS |
| 3. Test-OtterDocumentedCli.ps1 | PASS (28/28) |
| 4. Portable suite (24 files) | PASS (24/24 files, exit 0) |
| 5. Test-OtterMacInstall.sh | SKIPPED (no ~/Downloads/otter-mac-test) |
| 6. otter web hello-app.ot | **FAIL** — Start-Process can't open .html on macOS |
| 7. git status clean | PASS (after restoring tracked hello-app.html) |
