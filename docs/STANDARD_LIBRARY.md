# Otter 1.0 — Standard Library Boundary

This is the public boundary for Otter 1.0. It deliberately distinguishes the
portable language library from host and target integrations. A construct is
not portable merely because one runtime implements it.

The grammar remains authoritative in `rules.md` and `SPEC-DECISIONS.md`.
Release status and exclusions are authoritative in
[the release scope matrix](OTTER_1_0_RELEASE_SCOPE_MATRIX.md). The detailed
syntax-to-runtime audit is [the reachability matrix](STANDARD_LIBRARY_REACHABILITY.md).

## Portable core library

The following surface is supported by both the console interpreter and the
JavaScript/web compiler, subject to the normal target test suites:

| Area | Public forms (representative, not alternate-spelling exhaustive) |
|---|---|
| Values and control flow | numbers, text, booleans, `gone`, assignment, conditions, loops, functions, `try` / `otherwise`, `fail with` |
| Math | `plus`, `minus`, `times`, `divided by`, `percent of`, `power`, `round`, `round up`, `round down`, `absolute value`, `square root`, `larger`, `smaller`, trig and logarithms |
| Text | `length of`, `uppercase of`, `lowercase of`, `first of`, `last of`, `contains`, `starts with`, `ends with`, `replace`, `split`, `join` |
| Collections and things | list definitions, `add ... to`, `remove ... from`, `sort`, `reverse`, `for each`, things, custom types, `name of thing`, dynamic `get` / `set` keys |
| Data | `convert ... to json` and `convert ... from json` |
| Dates and randomness | `today`, `now`, date-part reads, date adjustment/formatting, `random number`, `random item` |
| Diagnostics | `say`, `log`, `warn`, `error`, and line-aware Otter diagnostics |

## Console runtime library

These are supported public console facilities. They are not a claim that the
same operation is available in an unbridged browser application:

| Area | Public forms |
|---|---|
| Files and folders | `read`, `write`, `append`, copy/move/delete, `file ... exists`, file locking, folder discovery and folder create/copy/move/delete |
| Archives and bytes | `zip folder`, `unzip`, byte conversion and file-byte operations |
| Processes | `run`, `run command`, output/exit-code inspection, process discovery/control, and D119 command jobs with streaming output and cancellation |
| System integration | environment variables, system folders/information, notifications, interactive file/folder choice, and the supported clipboard implementation |
| Security and administration | hashing/HMAC, encryption, Windows credential store, registry, event log, print, and remote-command facilities where the host supports them |
| File modules | `use "relative-file.ot"` is supported through console production entry points; package/registry imports are not part of 1.0 |

## Target-specific library

The following public syntax has an intentionally narrower availability and
must retain its target diagnostic when unavailable:

| Capability | Supported target / qualification |
|---|---|
| HTTP client (`get`, `post`, `put`, `delete`) | Web target via browser `fetch`; not the headless console interpreter |
| Clipboard | Windows console implementation and browser Clipboard API; browser availability also depends on permission/security context |
| Registry, DPAPI credentials, print spooler, session power actions | Windows console only |
| File I/O in a browser app | Requires the web bridge/selected browser capability; it is not ambient browser filesystem access |
| UI, desktop, server, database, and remote facilities | See the release scope matrix for supported, experimental, deferred, or target-specific status; none are implied by the portable core label |

## Certification basis

`tests/StandardLibrary.Tests.ps1` is the compact 31-capability smoke matrix:
its rows are the 31 entries in the reachability matrix and each is exercised
through canonical Otter syntax and the production CLI. It is not the complete
enumeration of every standard-library operation.

The broader public surface is exercised by the focused suites named in the
[contract coverage manifest](OTTER_1_0_CONTRACT_COVERAGE_MANIFEST.md),
including filesystem, bytes, CSV, JSON/data, dates, crypto, process, system,
network, XML, modules, UI, web, and diagnostic suites. A release claim must
name its runtime target and cite the relevant suite; it must not infer support
from a similarly named operation on another target.
