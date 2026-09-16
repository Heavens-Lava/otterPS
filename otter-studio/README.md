# Otter Studio

Otter Studio is the professional development environment for Otter.

## Implementation strategy

Studio is being delivered in two stages:

1. **JavaScript Studio (current)** — the production reference implementation
   used to build and certify editor, designer, project, run, and tooling
   behavior while the Otter language is still gaining platform capabilities.
2. **Otter-native Studio (planned)** — a later port built in Otter against the
   same documented behavior and service boundaries.

The JavaScript implementation is not disposable. It defines the user
experience, integration contracts, and certification tests that the
Otter-native version must reproduce.

## Run locally

From this directory:

```powershell
npm.cmd run dev
```

Then open `http://127.0.0.1:4200`.

From the repository root, the supported product entry point is:

```powershell
.\otter.cmd studio
```

## Validate

```powershell
npm.cmd run check
```

The check covers JavaScript syntax, editor state behavior, and the real local
Studio API path for project scanning, file open/save, external-change
protection, program execution, terminal results, and parser diagnostics.

## File safety

Open files carry a content revision supplied by the Studio server. If another
program changes a clean file, Studio reloads the new content. If the Studio
buffer has unsaved work, Studio preserves it and asks whether to reload the
disk version or keep the editor version. A stale Save request is rejected by
the server instead of silently overwriting external changes.

## Architecture boundary

The browser workbench owns presentation and interaction. The local Studio
service owns trusted filesystem, process, and Otter frontend access. Future
Otter-native Studio work should reuse these boundaries rather than introducing
different language or project semantics.
