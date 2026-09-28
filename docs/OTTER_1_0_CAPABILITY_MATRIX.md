# Otter 1.0 RC capability matrix

`CERTIFIED` means exercised through a production entry point in this RC pass.
`TARGET-SPECIFIC` means usable only on the named target. `DEFERRED` means it
is intentionally not part of Otter 1.0.

| Feature | Console | Web | Desktop | Portable core | Certification status |
|---|---|---|---|---|---|
| Core values, control flow, functions, things, lists | Yes | Yes | Not certified here | Yes | CERTIFIED for console/shared core |
| Files, JSON, deterministic date math | Yes | Bridge-dependent | Not certified here | Yes for console | CERTIFIED for console |
| Local command execution | Yes | Bridge-dependent | Not certified here | Yes for console | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED across hosts |
| HTTP GET/POST/PUT/DELETE and request handles (D116A/B) | Yes | Yes (`fetch`) | No claim | Yes (console and web) | CERTIFIED on console (four D120 hosts, `tests/Http.Tests.ps1`) and web |
| `use "file.ot"` file modules | Yes | Separate resolver path; works, not certified | No claim | No | CERTIFIED for the console production entry points (`otter run`, `otter check`, `otter debug`; `tests/UseModuleProduction.Tests.ps1`); web/desktop/serve parity is a target certification item |
| Package imports (`use web`, `use json`, registries) | No — explicit diagnostic | No | No claim | No | DEFERRED FROM 1.0 |
| Browser UI compilation | No | Yes | No claim | No | CERTIFIED in browser runtime (Edge/Chromium headless DOM mounting) |
| Desktop/server listener hosting | No | No | Host-dependent | No | BLOCKED BY ENVIRONMENT in this pass |
| Packaging / installer | Per-user script | N/A | N/A | N/A | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED on a clean machine |

Do not describe a `Yes` in the Web column as availability through `otter run`.
HTTP was listed here as web-only until 2026-09-27; that predated D116A/B, which
added the console HTTP client. See the D116 affirmation in `SPEC-DECISIONS.md`.
