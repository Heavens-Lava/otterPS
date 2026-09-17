# Otter 1.0 RC capability matrix

`CERTIFIED` means exercised through a production entry point in this RC pass.
`TARGET-SPECIFIC` means usable only on the named target. `DEFERRED` means it
is intentionally not part of Otter 1.0.

| Feature | Console | Web | Desktop | Portable core | Certification status |
|---|---|---|---|---|---|
| Core values, control flow, functions, things, lists | Yes | Yes | Not certified here | Yes | CERTIFIED for console/shared core |
| Files, JSON, deterministic date math | Yes | Bridge-dependent | Not certified here | Yes for console | CERTIFIED for console |
| Local command execution | Yes | Bridge-dependent | Not certified here | Yes for console | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED across hosts |
| HTTP GET/POST/PUT/DELETE | No | Yes (`fetch`) | No claim | No | TARGET-SPECIFIC |
| `use` modules | No — explicit diagnostic | Resolver groundwork only | No claim | No | DEFERRED FROM 1.0 |
| Browser UI compilation | No | Yes | No claim | No | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED in a browser runtime |
| Desktop/server listener hosting | No | No | Host-dependent | No | BLOCKED BY ENVIRONMENT in this pass |
| Packaging / installer | Per-user script | N/A | N/A | N/A | IMPLEMENTED BUT NOT PRODUCTION-CERTIFIED on a clean machine |

Do not describe a `Yes` in the Web column as availability through `otter run`.
In particular, HTTP is not portable core functionality.
