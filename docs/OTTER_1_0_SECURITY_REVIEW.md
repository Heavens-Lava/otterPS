# Otter 1.0 RC focused security review

**Scope:** console interpreter, file/process providers, generated web output,
local listeners, credentials, temporary files, and the deferred module
resolver. This review does not change language semantics.

## Findings

| Severity | Finding | Status |
|---|---|---|
| CRITICAL | None found in the reviewed RC paths. | — |
| HIGH | None found in the reviewed RC paths. | — |
| MEDIUM | Generated web notification UI uses `innerHTML` with runtime title/message values. | RESOLVED / CLOSED: Hardened in `Otter.Web.psm1` to create DOM elements with `textContent` instead of markup parsing. |
| LOW | Otter intentionally exposes local file deletion, process execution, registry, credential, and power actions to trusted console scripts. | Documented host-capability boundary; not a sandbox. |
| HARDENING | Module resolver accepts local paths but is deferred and not reached by `otter run`; preserve that boundary until a module policy is designed. | Deferred. |
| HARDENING | Desktop/server and terminal bridges depend on local listeners. Their exposure and origin/token controls need a supported-host review. | Not certified in this RC. |

## Reviewed controls

- Process execution uses `ProcessStartInfo` with `UseShellExecute = false` and
  explicit argument splitting/quoting; shell metacharacters are not implicitly
  evaluated by the direct command path.
- File paths are normalized with `GetFullPath`; this validates path shape but
  deliberately does **not** sandbox a trusted console program to a project
  directory. Delete/overwrite behavior remains an explicit user capability.
- Atomic writes use a same-directory, GUID-suffixed temporary file and remove
  cleanup artifacts after replace/failure.
- Credential storage uses Windows DPAPI CurrentUser scope. It requires a
  writable user profile and is unavailable in restricted sandboxes.
- Static HTML attributes use the web emitter's HTML-attribute escaping helper;
  dynamic text setters and notification toasts use `textContent`.

## Release consequence

Otter 1.0 RC may be described as a trusted local-programming runtime, not a
sandbox for hostile scripts. All reviewed critical, high, and medium web output
injection findings are resolved. Generated web applications safely set dynamic
notification and UI text using `textContent`.
