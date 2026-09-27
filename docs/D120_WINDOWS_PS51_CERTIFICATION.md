# D120 Windows PowerShell 5.1 Certification Record

## Candidate

- Commit: `072fe4fd6acaa61af8e9d129e5166e297934de41`
- Subject: `feat: complete D119 dogfood workspace and async jobs`
- Recorded: 2026-09-26
- Follow-up browser conformance source revision: `75b0705`

## Host

| Field | Value |
|---|---|
| Operating system | Microsoft Windows NT 10.0.26200.0 |
| Architecture | x64 |
| PowerShell | Windows PowerShell 5.1.26100.8115 |
| PowerShell edition | Desktop |
| PowerShell 7 (`pwsh`) | Not installed |
| Node.js | 24.11.0 |
| Headless Edge/Chrome | Edge is installed at `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe` |

## Evidence

| Check | Command | Status | Notes |
|---|---|---|---|
| Async command regression | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/AsyncCommand.Tests.ps1` | PASS | 13 of 13 assertions passed. |
| Full platform test suite | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1` | PENDING RE-RUN | The earlier process finished without a captured exit code or final summary. |
| PowerShell 7 / Windows | `pwsh -File tests/Run-Tests.ps1` | BLOCKED | `pwsh` is not installed on this host. |
| PowerShell 7 / Linux | CI runner required | BLOCKED | No Linux runner is available in this workspace. |
| PowerShell 7 / macOS | CI runner required | BLOCKED | No macOS runner is available in this workspace. |
| Browser runtime | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Test-OtterReleaseConformance.ps1` | PASS ON THIS HOST | 15/15 fixtures passed on 2026-09-26, including both web fixtures in headless Edge, when run outside the restricted sandbox. Inside the sandbox Edge's GPU process crashed and the same harness failed 2/15; that failure is an environment constraint, not a web fixture pass. |

## Scope and interpretation

This record is D120 evidence, not a cross-platform certification. Windows
PowerShell 5.1 is Otter's primary engine and can be certified on this host
after the full suite exits successfully. PowerShell 7, Linux, and macOS
require their respective runners. The Edge result verifies this Windows host;
it does not establish browser parity elsewhere.

The checkout contains unrelated uncommitted documentation, generated
timestamp, and whitespace changes. Those changes do not modify the committed
runtime source under test, but the final release gate must repeat this record
from a clean checkout of the candidate SHA.

## Next actions

1. Capture the exit code and final summary from a fresh Windows PowerShell
   suite run; update this record only with its observed result.
2. Add or provision Windows, Ubuntu, and macOS PowerShell 7 runners and run a
   host-neutral certification command on each.
3. Repeat the browser fixtures on a clean release candidate checkout and on
   the other advertised host/browser combinations.
