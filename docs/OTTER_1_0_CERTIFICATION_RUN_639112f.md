# Otter release certification record

| | |
|---|---|
| Kind | **release-certification** |
| Commit | `f170a5f32719fc57e6387e49a9f90c413c6467a1` modules: check use-path case before existence so every host gives the same diagnostic |
| Candidate SHA | `f170a5f32719fc57e6387e49a9f90c413c6467a1` (HEAD matches: True) |
| Clean checkout | True |
| Host | PowerShell 5.1.26100.8115 (Desktop), Microsoft Windows NT 10.0.26200.0 |
| Fuzz | 1000 programs per fuzz gate, seed 20261001 |
| Result | **all gates passed** |

| Gate | Command | Start (UTC) | End (UTC) | Exit | Result |
|---|---|---|---|---:|---|
| contract-structural | `C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Test-OtterContractCoverage.ps1` | 2026-09-27T15:47:55.9432443Z | 2026-09-27T15:47:56.4847491Z | 0 | pass |
| platform-regression | `C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Run-Tests.ps1` | 2026-09-27T15:47:56.4957493Z | 2026-09-27T16:10:24.7004561Z | 0 | pass |
| conformance | `C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Test-OtterReleaseConformance.ps1` | 2026-09-27T16:10:24.7024562Z | 2026-09-27T16:11:00.2403405Z | 0 | pass |
| differential-fuzz | `C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Invoke-OtterDifferentialFuzzer.ps1 -Mode Differential -Iterations 1000 -Seed 20261001` | 2026-09-27T16:11:00.2413569Z | 2026-09-27T16:13:25.1637093Z | 0 | pass |
| malformed-input-fuzz | `C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Invoke-OtterDifferentialFuzzer.ps1 -Mode MutationFuzz -Iterations 1000 -Seed 20261001` | 2026-09-27T16:13:25.1759101Z | 2026-09-27T16:14:52.9580409Z | 0 | pass |
| release-surface-audit | `C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Test-OtterReleaseSurface.ps1` | 2026-09-27T16:14:52.9590416Z | 2026-09-27T16:14:54.6521725Z | 0 | pass |
| distribution-smoke | `C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/Test-OtterDistribution.ps1` | 2026-09-27T16:14:54.6531778Z | 2026-09-27T16:15:03.6429958Z | 0 | pass |

Record produced by `tools/Invoke-OtterReleaseCertification.ps1` from a clean,
detached worktree of the commit above. The four-host companion evidence is
[D120 run 36327608764](https://github.com/Heavens-Lava/otterPS/actions/runs/36327608764):
the portable language suite (20 suites, including `HostPortability.Tests.ps1`)
and the project workflow passed on Windows PowerShell 5.1 and on PowerShell 7 on
Windows, Linux and macOS, at the same commit.
