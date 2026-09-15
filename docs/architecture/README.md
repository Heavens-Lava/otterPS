# Otter architecture diagrams

These diagrams are editable Draw.io documents generated from a small,
deterministic build script. The master diagram also reads the two repository
checklists so its certification counts stay connected to the planning source.

Sources:

- `../../OTTER_PROGRAMMING_LANGUAGE_COMPLETE_PLATFORM_CHECKLIST.md`
- `../../OTTER_STUDIO_PROFESSIONAL_IDE_MASTER_CHECKLIST.md`

Build and export everything from the repository root:

```powershell
node .\docs\architecture\scripts\build-diagrams.mjs
```

The script always builds the editable `.drawio` files. When Draw.io Desktop is
installed at its normal Windows path, it also exports cropped SVG and PNG
copies under `exported/`.

Current diagrams:

- `otter-master.drawio` — platform-wide systems, dependencies, targets, hosts,
  governance, and certification.
- `compiler-pipeline.drawio` — source resolution through frontend, direct
  execution, compiled application, providers, and delivery targets.
- `studio-architecture.drawio` — Studio workbench, shared services, engines,
  integrations, runtimes, and host boundaries.
- `designer-roundtrip.drawio` — visual editing through the canonical UI model,
  source regeneration, real compilation, and equivalence certification.
- `runtime-providers.drawio` — stable language semantics, capability contracts,
  provider implementations, and host delivery.
- `target-platforms.drawio` — shared core and the Console, Web, Desktop,
  Server/API, and planned target stacks.
- `feature-dependencies.drawio` — dependency graph from contract/parser/runtime
  foundations through professional IDE features.
- `release-roadmap.drawio` — P0–P7 roadmap with live combined progress from
  both master checklists.

Open a source diagram directly:

```powershell
& "C:\Program Files\draw.io\draw.io.exe" .\docs\architecture\otter-master.drawio
```

Generated SVG files are intended for Markdown, the documentation site, and
release material. Edit the architecture in the generator when possible so a
rebuild remains deterministic; manual Draw.io edits can still be used for
exploration before being folded back into the generator.
