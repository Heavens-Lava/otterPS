# Otter 1.0.0-rc.9 — release evidence

Candidate: `eff1e3b376f81cb05e16015a5e8b2e75a9009a45` (`VERSION` 1.0.0-rc.9).
Release candidate certifying 100% completion across Studio IDE, language platform, and website checklists, plus Windows clipboard lock-contention retry resilience in the interpreter:

- `3018987` — docs: reconcile language platform and website master checklists to 100% completion
- `eff1e3b` — fix(interpreter): add retry loops for clipboard access on Windows to avoid OS lock contention

Release archive: `otter-1.0.0-rc.9.zip`, 433,098 bytes, SHA-256
`B10BD0F3FE9FBA112E9C3418CB4C886AB583928B0CF227099782D067F2F30CFF`
(built from this commit with Windows PowerShell 5.1 by `tools/New-OtterDistribution.ps1`).

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression 63/63 test files; conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke (installing from the archive); repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-10-06, record `20261006T022632Z-eff1e3b` |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| macOS, hands-on | **Pending.** Jeff's Mac: Finder extraction, `./otter`, install, `otter web`, `otter desktop` refusal, uninstall. | — |
| Fresh-machine test (Windows) | **Not run.** Needs a machine or VM that has never had Otter. | — |
