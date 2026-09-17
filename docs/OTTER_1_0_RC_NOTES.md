# Otter 1.0.0-rc.1 release notes

## Included

- Frozen console-language core: values, control flow, functions, things,
  lists, files, JSON, deterministic date math, and direct command execution.
- A web compiler target for supported browser application features.
- A versioned Windows PowerShell 5.1 distribution builder, ZIP checksum, and
  per-user installer.
- Manifest-driven release conformance through the real `otter.ps1` entry
  point, plus an installed-payload smoke test.

## Explicit limitations

- `use` modules are deferred from Otter 1.0. The resolver is groundwork only;
  the console production entry point reports a clear unsupported-feature
  diagnostic.
- HTTP is web-target-specific. It is generated as browser `fetch` by `otter
  web` and is not available through `otter run`.
- Desktop/server listener hosting is not certified for this RC.
- The installer is per-user and requires Windows PowerShell 5.1. There is no
  package registry, auto-update service, or signed installer yet.
- Otter is a trusted local-programming runtime, not a sandbox for untrusted
  scripts. Dynamic web notification text is safely set with textContent.

## Verification commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-OtterReleaseConformance.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-OtterDistribution.ps1
```
