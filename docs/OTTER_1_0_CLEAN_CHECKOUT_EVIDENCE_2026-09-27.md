# Otter 1.0 — Clean-Checkout Evidence (2026-09-27)

This record closes the clean-checkout evidence requirement for the language
contract freeze. It is not a claim that every later 1.0 release gate is
complete.

## Candidate

| Field | Value |
|---|---|
| Commit | `a6e1a814e6134eef8fb9ea4e61e97ecbc6c398bb` |
| Subject | `release: add contract coverage evidence and D120 resolution` |
| Checkout form | Detached Git worktree, created from the SHA above |
| Working-tree contamination | None: the worktree was created before any test command and was not shared with the development checkout |
| Host | Windows PowerShell 5.1 |

## Commands and observed results

All commands below were executed from the detached worktree.

| Command | Exit code | Observed result |
|---|---:|---|
| `powershell.exe -NoProfile -File .\tools\Test-OtterContractCoverage.ps1` | 0 | 178 `TokenKind` declarations, 226 `NodeKind` declarations, 225 AST classes, and the documented `UiLayout` reservation; structural coverage passed. |
| `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1` | 0 | **All test files passed (55 of 55).** |
| `powershell.exe -NoProfile -File .\tools\Test-OtterReleaseConformance.ps1` | 0 | **Release conformance passed (15 fixtures).** |

The complete-suite result includes the clean installation certification
(11/11) and five-cycle installation soak (21/21). Those suites create a
distribution archive, perform per-user installation, exercise installed
`--version`, `run`, and `web`, and cleanly uninstall. This supplies the
fresh-distribution evidence required by the packaging portion of the release
checklist on the Windows PowerShell 5.1 host.

## Related cross-platform evidence

The GitHub Actions [D120 resolution run](https://github.com/Heavens-Lava/otterPS/actions/runs/36286141126)
passed the portable CLI and fresh-project workflow on Windows PowerShell 5.1,
PowerShell 7 on Windows, PowerShell 7 on Linux, and PowerShell 7 on macOS.
It predates this documentation-only candidate commit; the tested runtime
source is unchanged between that run and this candidate.

## Limit

This evidence certifies the nominated checkout and the contract-freeze Gate 1
checks. Target-specific cross-platform facilities, browser combinations, and
the remaining release gates retain their own scope and evidence requirements.
