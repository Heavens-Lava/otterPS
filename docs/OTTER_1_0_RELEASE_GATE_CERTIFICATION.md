# Otter 1.0 Release-Gate Certification

**Audit basis:** `b6ca844`, with the current PowerShell 5.1 workspace
re-validated on 2026-09-17. This is a certification record, not a feature
roadmap. An unchecked release-gate item is not evidence that its syntax is
absent; it means the current evidence is insufficient to claim it as a
production-certified Otter 1.0 capability.

## Release scope recommended for Otter 1.0

Otter 1.0 should mean the frozen core language, its PowerShell console
interpreter, and the web compiler for the common cross-runtime subset, run
from a source checkout on a supported Windows PowerShell 5.1 host. Web-only
capabilities must be labelled target-specific. It must not claim portable
HTTP, production module loading, packaged installation, clean-machine
readiness, a completed security review, or desktop/server availability on
every host.

## Gate classification

| Gate | Classification | Evidence / release consequence |
|---|---|---|
| Core syntax frozen | CERTIFIED | Lexer/parser regressions and V1 audit pass. |
| Semantics frozen | CERTIFIED | V1 audit and interpreter/JS differential conformance pass. |
| Formal specification | CERTIFIED | Frozen `rules.md` and `SPEC-DECISIONS.md` define the supported core. |
| Conformance suite | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED | `conformance/manifest.json` now drives deterministic console and web checks through the real entry point; exhaustive fixture coverage and host-matrix execution remain open. |
| No silent no-ops | CERTIFIED | The audited boolean, literal-name, and typed-initializer cases have explicit diagnostics. |
| Portable JS parity | TARGET-SPECIFIC | Shared-core differential conformance passes; HTTP is emitted only by the web target. |
| Core standard library | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED | Most Part 3 cases pass, but host-backed providers have not been certified across a release host matrix. |
| Files / JSON / dates / random | CERTIFIED | Dedicated regressions and cross-runtime conformance pass. |
| HTTP | TARGET-SPECIFIC | `otter web` emits `fetch`; `otter run` reports that it cannot run `HttpGet`. This is acceptable only when release material says web-only. |
| Command/process API | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED | Normal process tests pass; process-tree coverage requires a host able to expose a child process. |
| Module system | DEFERRED FROM 1.0 | A resolver exists, but `otter run` still rejects `use`; it is not a production module system. |
| Console target | CERTIFIED | Production CLI and cross-runtime core fixtures pass. |
| Advertised Web target | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED | Compiler fixtures pass, including generated HTTP helpers; browser/runtime certification needs a hermetic browser execution record. |
| Advertised Desktop target | BLOCKED BY ENVIRONMENT | This host throws `PlatformNotSupportedException` for `HttpListener`, blocking the terminal bridge test. |
| Diagnostics | CERTIFIED | V1 diagnostic fixtures and parser/interpreter tests pass. |
| Packaging / install | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED | A versioned Windows PowerShell payload builder and per-user installer now exist; clean-machine certification and signing remain open. |
| Security review | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED | Security-sensitive code exists, but there is no threat model, security review, signing, SBOM, or supply-chain audit. |
| Documentation | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED | Core and target-specific status are documented; installation and security guidance remain incomplete. |
| Real dogfood applications | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED | Examples exist, but this pass did not independently certify their complete production paths. |
| No known data-loss / critical-security bugs | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED | No failing core case was found here, but the missing security review and host matrix prevent a certification claim. |
| Every advertised feature reachable through a production entry point | BROKEN | `use` is unreachable through `otter run`; HTTP is unreachable outside `otter web`. |

## Modules

Choose **C: explicitly experimental/deferred** for 1.0. Keep the resolver as
unreleased groundwork, retain the current clear `use` diagnostic, and remove
modules from 1.0 capability claims. Option B (implement before 1.0) requires
one resolver path before lexing for every entry point plus source-map,
ordering, cache, cycle, and initialization certification. Option A is the
same release outcome as C but loses useful forward-looking status.

## HTTP

The specification can support target-specific HTTP provided the target is
visible at the point of use. Current evidence supports only browser/web
`fetch`; it does not establish an interpreter-level request/response
contract. Keep HTTP as a web-only capability for 1.0 and do not call it
portable. `docs/OTTER_1_0_HTTP_TARGET_PARITY.md` is the capability matrix.

## Environment findings

| Test finding | Classification | Reason |
|---|---|---|
| D69 memory, D80 scheduled tasks | BLOCKED BY ENVIRONMENT | This host does not supply the Windows management data expected by the tests. |
| D78 registry writes, D81 credential writes | BLOCKED BY ENVIRONMENT | The sandbox denies writes below HKCU and LocalAppData. |
| D83 installed/default printer | BLOCKED BY ENVIRONMENT | No printer/default-printer resource is exposed. |
| D70 process-tree kill | TEST-HARNESS / ENVIRONMENT ISSUE | The spawned PowerShell process exposed no child to inspect. |
| D51 server loopback | BLOCKED BY ENVIRONMENT | Constructing `System.Net.HttpListener` raises `PlatformNotSupportedException`. |
| D60 terminal bridge | BLOCKED BY ENVIRONMENT | It uses the same `HttpListener`; its 20-port retry means this is not a simple transient port conflict. |

None of these justify changing Otter semantics or weakening production tests.

## Remaining release work

For the recommended scoped definition, the remaining true release blockers
are release communication and certification work: publish the target matrix,
defer modules, label HTTP web-only, automate hermetic conformance fixtures,
and either perform a security/clean-machine release audit or state that this
is a source-checkout technical release rather than an installable distribution.
