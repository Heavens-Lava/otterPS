# release/

Machine-readable Otter 1.0 release evidence. **Evidence, not decisions:** nothing in
this folder decides what is public in Otter 1.0. Codex owns the public boundary; the
contract freeze itself is recorded in `docs/OTTER_1_0_CONTRACT_FREEZE_REPORT.md`.

| File | What it is | Produced by |
|---|---|---|
| `otter-1.0-surface.json` | The candidate-surface manifest: every capability found in `docs/STANDARD_LIBRARY.md`, `docs/STANDARD_LIBRARY_REACHABILITY.md` or the contract, with its contract members, implementation per target, tests, hosts, documentation, production reachability, conflicts and status. All entries start `candidate` / `unresolved`. Also records the event-contract questions and cross-document conflicts, each with `decision: null` until decided. | `tools/Initialize-OtterReleaseSurface.ps1` (seed once; then edit the JSON) |
| `otter-1.0-contract-coverage.json` | Derived evidence for every declared `TokenKind`, `NodeKind` and diagnostic call site: producers and consumers, which real programs exercise it (the real lexer and parser run over every Otter program in the repository), documentation, and an explicit disposition. | `tools/New-OtterContractEvidence.ps1` (regenerate; never edit) |
| `certification/` | Records from `tools/Invoke-OtterReleaseCertification.ps1`. Git-ignored: a record that certifies a nominated candidate is copied into `docs/` deliberately. | |

## Workflow

```powershell
# 1. Regenerate derived evidence after any contract, lexer or parser change (about 2 minutes).
powershell -NoProfile -File tools\New-OtterContractEvidence.ps1

# 2. Audit the manifest against the repository. Read-only; exit 1 on any error.
powershell -NoProfile -File tools\Test-OtterReleaseSurface.ps1

# 3. Regenerate the human-readable reconciliation report.
powershell -NoProfile -File tools\New-OtterSurfaceReconciliation.ps1

# 4. Certify a nominated candidate from a clean detached worktree.
git worktree add --detach ..\otter-cert <candidate-sha>
powershell -NoProfile -ExecutionPolicy Bypass -File ..\otter-cert\tools\Invoke-OtterReleaseCertification.ps1 -CandidateSha <candidate-sha>
```

## Recording a boundary decision

Edit the capability in `otter-1.0-surface.json`:

* `boundaryStatus`: `decided-public` or `decided-not-public`.
* `status`: `certified` (requires `decided-public`, production reachability `true` with
  evidence, tests, documentation, a contract link, Windows PowerShell 5.1 `exercised`, an
  interpreter implementation and no remaining conflicts), `hostSpecific` (requires
  `decided-public` and at least one host marked `unsupported` or `not-applicable`),
  `deferred` or `internal` (both require `decided-not-public`).
* Remove a `conflicts` entry only when the underlying disagreement has actually been fixed.

Then run the auditor. It rejects any combination that the evidence does not support.

## Vocabulary

* Implementation `not-referenced` means *searched, not found*. It is never a claim of
  `unsupported`; that value is used only when a diagnostic or document says so.
* Host `unverified` means nothing was run for this capability on that host.
* `productionReachability.reachable: null` means *not established by this evidence*, not *unreachable*.
* Links between documentation phrases and contract members are derived by word matching
  and labelled with their derivation. Confirm them before relying on them.
