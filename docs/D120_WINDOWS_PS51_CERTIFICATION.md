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
| PowerShell 7 / Windows | D120 CI production CLI smoke | SMOKE PASS | GitHub Actions `windows-2025`, PowerShell 7.6.6, x64: `--version`, `run`, and `check` passed. Full host suite and project commands remain unverified. |
| PowerShell 7 / Linux | D120 CI production CLI smoke | SMOKE PASS | GitHub Actions `ubuntu-24.04`, PowerShell 7.6.6, x64: `--version`, `run`, and `check` passed. Full host suite and project commands remain unverified. |
| PowerShell 7 / macOS | D120 CI production CLI smoke | SMOKE PASS | GitHub Actions `macos-15`, PowerShell 7.6.5, arm64: `--version`, `run`, and `check` passed. Full host suite and project commands remain unverified. |
| Browser runtime | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Test-OtterReleaseConformance.ps1` | PASS ON THIS HOST | 15/15 fixtures passed on 2026-09-26, including both web fixtures in headless Edge, when run outside the restricted sandbox. Inside the sandbox Edge's GPU process crashed and the same harness failed 2/15; that failure is an environment constraint, not a web fixture pass. |

The four-job [D120 host smoke run](https://github.com/Heavens-Lava/otterPS/actions/runs/36282483112)
completed successfully on commit `bbafb89527e4cd6f62549acbcd2ffbdec231dabd`.
Its Windows PowerShell 5.1 job ran on Windows NT 10.0.26100.0, x64 with
PowerShell 5.1.26100.33438. The local Windows host still lacks `pwsh`; the CI
results supply the PowerShell 7 host evidence above.

## Scope and interpretation

This record is D120 evidence, not a cross-platform certification. Windows
PowerShell 5.1 is Otter's primary engine and can be certified on this host
after the full suite exits successfully. The four-host CI smoke verifies the
production CLI's version, run, and check paths only. It is not yet the full
D120 command or test matrix. The Edge result verifies this Windows host;
it does not establish browser parity elsewhere.

The checkout contains unrelated uncommitted documentation, generated
timestamp, and whitespace changes. Those changes do not modify the committed
runtime source under test, but the final release gate must repeat this record
from a clean checkout of the candidate SHA.

## Next actions

1. Capture the exit code and final summary from a fresh Windows PowerShell
   suite run; update this record only with its observed result.
2. Expand the successful four-host CI smoke to `new`, `test`, `build`, and
   `publish` against temporary projects, and run the relevant platform
   regression suites under each intended host.
3. Repeat the browser fixtures on a clean release candidate checkout and on
   the other advertised host/browser combinations.
