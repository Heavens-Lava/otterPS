# D120 Windows PowerShell 5.1 Certification Record

## Candidate

- Commit: `167cf006c38aa211d85795109ef8b1c6c6c60628`
- Subject: `feat: complete D119 dogfood workspace and async jobs`
- Recorded: 2026-09-26
- Follow-up browser conformance source revision: `4bef286`

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
completed successfully on commit `ed8ee18324e2375eb43efeecfe94f2f7975afa18`.
Its Windows PowerShell 5.1 job ran on Windows NT 10.0.26100.0, x64 with
PowerShell 5.1.26100.33438. The local Windows host still lacks `pwsh`; the CI
results supply the PowerShell 7 host evidence above.

The [first expanded project workflow run](https://github.com/Heavens-Lava/otterPS/actions/runs/36282641423)
used commit `8482b6e` and found a real portability defect: `new`, `check`,
`run`, `build`, and `publish` passed everywhere, but `test` failed on Linux
and macOS because `Invoke-OtterProjectTests` launched `powershell.exe`.

Commit `696fc5d` changed that child launch to use the running PowerShell host.
The [resolution run](https://github.com/Heavens-Lava/otterPS/actions/runs/36286141126)
at commit `ff63057` passed all four hosts. Each host completed `--version`,
`run`, `check`, and a fresh-project `new`, `check`, `test`, `run`, `build`,
and `publish` workflow with exit code 0. This closes the specific D120
host-selection defect; it does not by itself certify every target-specific
runtime facility.

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

1. Run the complete suite from a clean checkout of the nominated candidate
   and record its exact exit code and final summary.
2. Run the relevant platform regression suites under each intended host
   beyond the portable CLI/project workflow proven above.
3. Repeat the browser fixtures on a clean release candidate checkout and on
   the other advertised host/browser combinations.
