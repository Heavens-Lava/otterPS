# Otter 1.0.0-rc.11 — release evidence

Candidate: `9e7cdac4b5b5358d30bc87f9095ad24925b5598f` (`VERSION` 1.0.0-rc.11),
**not tagged yet**. rc.10 (`3ba7890`, certified on Windows and Linux but
superseded; see `docs/OTTER_1_0_RC10_EVIDENCE.md`) merged with `master` since
rc.9:

- `eff1e3b` — the Windows clipboard retries briefly when another program
  holds it;
- `73587f0` — parser follow-ups: D27 `replace ... into`, D32.3 variable date
  amounts (reviewed: `add days to total` still adds a variable), P4 call
  `into`, P6 `an`, the top-level `count is 3` message;
- `245427a`, `5a618df`, `2b8a2fa` — false checklist ticks and the
  premature `[1.0.0]` changelog entry reverted or un-ticked (2026-10-06
  review);
- `87e37dd` — merge of rc.10 (`otter web` on macOS);
- `9e7cdac` — version 1.0.0-rc.11, changelog `[1.0.0-rc.11]`.

The 1.1 prototypes on `master` (the experimental compiled backend in
`src/Otter.Compiler.Native.psm1` and `src/native/`, Otter Studio) are not
reachable from any `otter` command; the compiled backend's files are copied
into the archive with the rest of `src`.

Release archive: `otter-1.0.0-rc.11.zip`, 434,531 bytes, SHA-256
`0F9421B15C8A2B7016A41AABEA28806656A2EC698B0CC12BE6524144CABED1AA`
(built from this commit with Windows PowerShell 5.1 by
`tools/New-OtterDistribution.ps1`).

| Check | Result | Where |
|---|---|---|
| Release certification, clean checkout, Windows PowerShell 5.1 | **Pass.** All eight gates: contract structure; platform regression 63/63 test files; conformance 15/15; differential fuzz 1,000/1,000; malformed-input fuzz 1,000/1,000; release-surface audit; distribution smoke; repository clean afterwards. | `tools/Invoke-OtterReleaseCertification.ps1`, 2026-10-06, record `20261006T201428Z-9e7cdac` |
| Windows PowerShell 5.1 recursion probe | **Pass**, 24 of 24 cases. | `tools/Test-OtterRecursionProbe.ps1`, PowerShell 5.1.26100.8115 |
| Desktop (WPF) smoke test | **Pass**, 9 of 9 checks. | `tools/Test-OtterDesktopSmoke.ps1`, PowerShell 5.1.26100.8115 |
| Linux, this commit | **Pass.** Clean container (PowerShell 7.4.2, Ubuntu 22.04, Node.js 20): the Windows-built archive above unzipped, run directly, installed twice, the project workflow and the built app's `dist/run` run through the installed `otter`, uninstalled; the 24 D120 portable suites pass. | Docker Desktop on the release machine, 2026-10-06 |
| macOS, hands-on | **Pending** on Jeff's Mac (`docs/MACOS_AGENT_TEST.md`, branch `release/rc.11`, including the real-download test). | — |
| D120 four-host workflow, this commit | **Not run** (GitHub Actions account spending limit). | — |
| Fresh-machine test (Windows) | **Not run.** | — |

All certification records are kept in `otter-certification-records` beside
the repository.
