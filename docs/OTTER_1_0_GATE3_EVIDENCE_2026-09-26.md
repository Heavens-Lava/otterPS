# Otter 1.0 Gate 3 Evidence — 2026-09-26

**Status: PARTIAL.** These checks narrow risk; they do not finish the
hardening, fuzzing, and conformance release gate.

## Revision and environment

- Language source revision: `75b0705` (`master` at the start of these runs).
- Host: Windows PowerShell 5.1.26100.8115, Windows NT 10.0.26200.0, x64.
- The checkout has pre-existing uncommitted documentation, example whitespace,
  and generated project timestamp edits. The fuzzer report fix below is also
  local during this run. Repeat final certification on a clean release commit.

## Seeded differential and malformed-input checks

Command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\Invoke-OtterDifferentialFuzzer.ps1 -Seed 20260926 -Iterations 100 -Mode All
```

Observed exit code: **0**. The tool reported **100/100** interpreter versus
JavaScript programs agreeing, with **0** disagreements. It also reported
**100/100** grammar-aware mutations handled safely, with **0** raw host
exceptions. This is a smoke sample, not the checklist's full-scale fuzz gate.

The tool previously printed a hard-coded claim of 10,000 runs even when
`-Iterations 100` was supplied. Its final summary now uses the actual count
and selected mode. Both single-mode summaries were verified with one run each.

## Production-entry conformance manifest

Command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\Test-OtterReleaseConformance.ps1
```

Observed exit code outside the restricted sandbox: **0**. All **15/15**
manifest fixtures passed, including the two web fixtures executed by local
headless Microsoft Edge.

The same command inside the restricted sandbox exited **1**: its 13 console
and negative fixtures passed, while both web fixtures failed because Edge's
GPU process crashed (`GPU process isn't usable`). A separate `web-hello` run
and the full manifest both passed outside the sandbox. The differing results
are recorded so a later gate does not mistake a sandbox failure for an Otter
compiler defect or claim browser coverage from a run that skipped the engine.

## Remaining Gate 3 work

- Run a larger recorded seed/iteration matrix for differential and mutation
  fuzzing after the candidate revision is clean.
- Run and review the resource soak, including watcher and async process
  cleanup; record private memory, handle counts, and any failures.
- Review the security regression report against the nominated candidate.
- Complete the Windows PowerShell suite and record its final exit code.
