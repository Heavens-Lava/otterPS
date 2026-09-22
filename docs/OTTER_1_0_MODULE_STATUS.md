# Otter 1.0 module status

## Certified for the console target (`otter run` / `otter check` / `otter debug`)

`use "file.ot"` is a real, production-certified Otter 1.0 capability for the
console interpreter. It was already independently wired into the web/JS
compiler target (`src/Otter.Web.psm1`); this closed the same gap for the
console entry point, which previously rejected every `use` at runtime with
`'use' is not supported in Otter 1.0.` regardless of whether the import
itself was valid, because no production entry point ever called the
resolver that already existed.

Wired in `otter.ps1`'s `Invoke-OtterFile` (the function `otter run`,
`otter check`, and `otter debug` all share): the target file is resolved
through `Resolve-OtterModuleSource` (`src/Otter.Module.psm1`) before
lexing, and any diagnostic's line number is mapped back from the combined
source to the real file and line it came from before being shown
(`Get-OtterRemappedError`), including naming which imported file an error
came from when it isn't the root script itself.

Proven through the real entry point, not just the resolver's own unit
tests (`tests/Module.Tests.ps1`, which exercises `Resolve-OtterModuleSource`
directly): `tests/UseModuleProduction.Tests.ps1` spawns the actual
`otter.ps1` process for every case below, plus a real dogfood example pair
(`examples/module-lib.ot`, `examples/module-app.ot`) that runs cleanly
through `otter run`.

## Frozen behavior (this is the certified 1.0 semantics, not a placeholder)

- **Resolution model.** Source-text splicing before lexing/parsing - `use
  "file.ot"` lines are replaced in place with the target file's own content
  (recursively resolved first), wrapped in `# --- imported from ... ---` /
  `# --- end import ... ---` comment markers. Not an AST-level or
  module-object mechanism; imported code runs in exactly the same flat
  top-level scope as the importing file, with no additional indirection.
- **Relative paths.** `use "path.ot"` resolves relative to the
  **importing file's own directory**, not the process's current working
  directory - confirmed for both same-directory and subdirectory imports
  (`use "lib/helpers.ot"`). A parent-directory import (`use
  "../shared/x.ot"`) works the same way, since it is ordinary
  `Path.Combine` resolution.
- **Module initialization order.** Strictly depth-first, in source order:
  each `use` fully expands (including its own transitive imports) before
  the importing file's next line is processed. Deterministic, matching a
  plain textual `#include`.
- **Duplicate-load semantics.** Idempotent. If the same resolved file path
  is reached more than once (directly or via a diamond - two different
  files both importing a shared third file), only the first occurrence
  emits its content; later `use` statements for an already-loaded file are
  silent no-ops. Confirmed: a diamond import of a file that assigns a
  variable does not re-run that assignment or throw a redefinition error.
- **Circular imports.** Detected via an active-resolution call stack (not
  merely "loaded before") and rejected with a clean diagnostic naming the
  full cycle chain (`Circular import detected: a.ot -> b.ot -> a.ot`),
  exit code 2 (check-stage), never a raw PowerShell stack-overflow.
- **Namespace collision policy: DECIDED - no special detection.** Every
  imported file shares the single flat top-level scope the importing file
  itself runs in; two files declaring the same top-level name behave
  exactly like reassigning that name twice in one file already does today
  (last one wins, no error). This is a deliberate choice, not a gap:
  introducing a separate cross-file collision-detection mechanism would be
  new language complexity with a different rule from ordinary
  single-file reassignment, which the project's own stated principles
  (avoid synonyms/magic without a demonstrated dogfooding need) argue
  against absent a real case where it has caused a problem.
- **Public/private exports: DECIDED - not needed for 1.0.** There is no
  visibility modifier and none is planned for 1.0; everything a used file
  declares at its top level is visible to the importer, matching the
  "flat `#include`" model above. Revisit only if real dogfooding surfaces
  an actual encapsulation problem this causes.
- **Module caching/invalidation: N/A for 1.0's execution model.** Within a
  single `otter run`, the `LoadedFiles` set already prevents redundant
  re-reads of the same file (the duplicate-load mechanism above doubles as
  this). Across separate process invocations there is no persistent cache
  to invalidate - every `otter run` re-resolves from disk fresh, which is
  the correct behavior for a script interpreter with no daemon or watch
  mode, and carries zero staleness risk.
- **Missing imports** are rejected with a diagnostic naming the exact
  relative path and the absolute directory Otter looked in, exit code 2.

## Explicitly still deferred (real gaps, not decisions)

- **Package modules** (`use packageName` resolving through some registry
  or search path, rather than a literal relative/absolute file path) -
  no package/registry concept exists anywhere in Otter yet; this is the
  same pre-1.0 backlog as the rest of the package ecosystem (checklist
  section 31), not something this pass added.
- **First-class function values / callbacks as values** - unrelated to
  modules; Otter calls are still always by a literal function name known
  at parse time (`Read-OtterFunctionCallExpression`/`$script:KnownFunctions`).
  No real dogfooding case has yet demonstrated a need for passing a
  function itself as a value, so this stays out of 1.0 rather than adding
  a new expression kind speculatively.
- **Cross-module symbol metadata for IDE tooling** - Otter Studio/IDE
  territory, not language-core 1.0 scope.
- **Web/desktop/serve targets beyond what already existed** - the web/JS
  compiler target already had its own independent
  `Resolve-OtterModuleSource` wiring before this pass (confirmed:
  `src/Otter.Web.psm1` imports and calls it). `otter desktop` and `otter
  serve` were not touched by this pass and were not independently
  verified either way.
