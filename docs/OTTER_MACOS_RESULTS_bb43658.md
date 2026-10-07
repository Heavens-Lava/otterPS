# Otter 1.0.0-rc.12: macOS hands-on test results

Tested 2026-10-07 by Claude Code (Opus 5.5) on Jeff's Mac, following
`AGENT-INSTRUCTIONS.md` from the USB drive. No repository files were edited.

## Part 1: setup

- Copied the USB folder to `~/Downloads/otter-mac-test`.
- `shasum -a 256 ~/Downloads/otter-mac-test/otter-1.0.0-rc.12.zip` →
  `8531e38872f0155bea8c21a0f18120e709b7f0717510e5bf43fb37d3290addf2` (matches).
- `pwsh --version` → `PowerShell 7.6.6`; `git --version` → `git version 2.50.1 (Apple Git-155)`;
  `gh auth status` → logged in as Heavens-Lava.
- Repository `~/Projects/otterPS`: `git fetch`, `git checkout release/rc.11`, `git pull`
  ("Already up to date"). `cat VERSION` → `1.0.0-rc.12`. `git status --short` → empty.

## Part 2: the tests

### 1. Environment

| Item | Value |
|---|---|
| `git rev-parse --short HEAD` | `bb43658` (branch `release/rc.11`) |
| `sw_vers` | macOS 26.1, build 25B78 |
| `uname -m` | `arm64` |
| `pwsh --version` | PowerShell 7.6.6 |

### 2. Distribution smoke test

Command: `pwsh -NoProfile -File tools/Test-OtterDistribution.ps1`
Exit code: **0**. Built the zip and payload, installed twice (with and without
`-AddToUserPath`), ran the project workflow, uninstalled. Final line:

```
Distribution smoke test passed on PowerShell 7.6.6: /var/folders/pj/.../otter-distribution-3f92a745356a43468d75082f71afb1b0
```

### 3. Documented CLI

Command: `pwsh -NoProfile -File tools/Test-OtterDocumentedCli.ps1`
Exit code: **0**.

```
Documented CLI checks on PowerShell 7.6.6: 28 passed, 0 failed.
```

### 4. Portable language and module suite (25 files from `d120-host-matrix.yml`)

Each was run separately as `pwsh -NoProfile -File tests/<name>`. The counts are the
suite's own summary where it prints one, otherwise the number of `pass` lines in its
output. No suite printed a `fail` line.

| Suite | Exit | Passed | Failed |
|---|---|---|---|
| HostPortability.Tests.ps1 | 0 | 32 | 0 |
| EventContract.Tests.ps1 | 0 | 6 | 0 |
| Http.Tests.ps1 | 0 | 35 | 0 |
| Lexer.Tests.ps1 | 0 | "Lexer tests passed." (no count printed) | 0 |
| Parser.Tests.ps1 | 0 | "Parser tests passed." (no count printed) | 0 |
| Grammar.Tests.ps1 | 0 | 32 | 0 |
| Collections.Tests.ps1 | 0 | 22 | 0 |
| Objects.Tests.ps1 | 0 | 14 | 0 |
| Data.Tests.ps1 | 0 | 15 | 0 |
| Dates.Tests.ps1 | 0 | 38 | 0 |
| Bytes.Tests.ps1 | 0 | 23 | 0 |
| Csv.Tests.ps1 | 0 | 41 | 0 |
| Xml.Tests.ps1 | 0 | 22 | 0 |
| Interpreter.Tests.ps1 | 0 | 75 | 0 |
| Conformance.Tests.ps1 | 0 | 13 ("All cross-runtime tests passed!") | 0 |
| Module.Tests.ps1 | 0 | 11 | 0 |
| UseModuleProduction.Tests.ps1 | 0 | 10 | 0 |
| Project.Tests.ps1 | 0 | 15/15 | 0 |
| ProjectBuild.Tests.ps1 | 0 | 20/20 | 0 |
| ProjectCreationAndTestRunner.Tests.ps1 | 0 | 19/19 | 0 |
| ProjectPublish.Tests.ps1 | 0 | 24/24 | 0 |
| Web.Tests.ps1 | 0 | 36 ("Web compiler tests passed.") | 0 |
| WebRuntimeUi.Tests.ps1 | 0 | 5 | 0 |
| PlatformBoundaries.Tests.ps1 | 0 | 15 | 0 |
| CompiledRun.Tests.ps1 | 0 | 10 | 0 |

25 of 25 suites exited 0.

### 5. The real Windows-built download

Command: `sh tools/Test-OtterMacInstall.sh ~/Downloads/otter-mac-test`
Exit code: **0**. Extracted with `ditto` (the way Finder does).

```
PASS  checksum matches
PASS  extracted with ditto into a normal folder
PASS  no file names with backslashes
PASS  the otter launcher is executable
PASS  ./otter --version prints Otter 1.0.0-rc.12
PASS  ./otter run examples/hello.ot
PASS  install 1 with -AddToUserPath
PASS  install 2 with -AddToUserPath
PASS  ~/.local/bin/otter was created
PASS  the installed otter command runs
PASS  otter run a program
PASS  otter web compiles a page
PASS  otter desktop is refused clearly
PASS  the registry is refused clearly
PASS  the clipboard round-trips
PASS  otter new console demo
PASS  otter check .
PASS  otter test .
PASS  otter run .
PASS  otter build .
PASS  otter publish .
PASS  the built app runs with dist/run
PASS  uninstall
PASS  ~/.local/bin/otter was removed
PASS  the install folder was removed

Result: 25 passed, 0 failed.
```

### 6. `otter web` opens the default browser

Command: `./otter web examples/hello-app.ot`
Exit code: **0**.

```
Otter Web application compiled to: /Users/jeffreymacy/Projects/otterPS/examples/hello-app.html
Opened in your default browser.
```

How it was confirmed: the default browser is Microsoft Edge (LaunchServices https
handler `com.microsoft.edgemac`). AppleScript listed an open Edge tab at
`file:///Users/jeffreymacy/Projects/otterPS/examples/hello-app.html`. The page's
contents were not inspected visually.
Afterwards `git restore examples/hello-app.html` was run, and `git status --short` was empty.

### 7. Compiled engine (first run on a Mac)

Program `/tmp/loop.ot` (sums 1..20000), created with the `printf` command from the instructions.

| Command | Exit | Output | Time |
|---|---|---|---|
| `OTTER_ENGINE_TRACE=1 ./otter run /tmp/loop.ot` | 0 | `otter engine: compiled (OtterProgram_cf1abce3724686cb)` then `200010000` | not timed |
| `time ./otter run /tmp/loop.ot` | 0 | `200010000` | 3.895 s total (4.97 s user, 0.43 s system) |
| `time OTTER_ENGINE=interpreter ./otter run /tmp/loop.ot` | 0 | `200010000` | 8.672 s total (10.87 s user, 0.66 s system) |

The compiled engine was used and gave the correct answer. On this program it was about
2.2× faster than the interpreter. Both times include PowerShell start-up.

### 8. Working tree unchanged

Command: `git status --short`. Exit code 0, empty output. HEAD is still `bb43658`.

## Summary

| Step | What | Result |
|---|---|---|
| Setup | Zip checksum, tools, `release/rc.11` at VERSION 1.0.0-rc.12, clean tree | PASS |
| 1 | Environment recorded (bb43658, macOS 26.1 arm64, pwsh 7.6.6) | DONE |
| 2 | `tools/Test-OtterDistribution.ps1` | PASS (exit 0) |
| 3 | `tools/Test-OtterDocumentedCli.ps1` | PASS (28 passed, 0 failed) |
| 4 | 25 portable suites from `d120-host-matrix.yml` | PASS (25/25 exit 0, no failures) |
| 5 | `tools/Test-OtterMacInstall.sh` against the Windows-built zip | PASS (25 passed, 0 failed) |
| 6 | `./otter web examples/hello-app.ot` opens in the default browser | PASS (Edge tab confirmed; file restored) |
| 7 | Compiled engine: trace, output, timing | PASS (`compiled`, 200010000 both ways; 3.9 s vs 8.7 s) |
| 8 | `git status --short` unchanged | PASS (empty) |

No failures were seen.
