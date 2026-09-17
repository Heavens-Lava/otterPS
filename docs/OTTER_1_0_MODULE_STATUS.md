# Otter 1.0 module status

## Decision needed, not an implementation task

`use "file.ot"` has an AST node and a source resolver, but it is deliberately
disabled by the PowerShell interpreter.  It must not be presented as an Otter
1.0 capability until that boundary is wired and certified through `otter run`.

## What exists

- `TokenKind::Use` and `UseModuleStmt` preserve a module path in the parsed
  program.
- `src/Otter.Module.psm1` contains a recursive resolver that expands literal
  `use "..."` directives, tracks loaded files, detects circular imports, and
  builds a combined-line-to-original-file source map.
- The resolver rejects missing imports with an Otter-level diagnostic.

## What is disabled

`Invoke-OtterStatement` handles `UseModule` by throwing:

```
'use' is not supported in Otter 1.0.
```

The production entry point does not import or invoke `Otter.Module.psm1`
before lexing and parsing.  Therefore resolving imports after parsing would be
too late: imported declarations cannot participate in normal parser symbol
discovery, and diagnostics cannot be reliably remapped to source files.

## What safe enablement requires

1. Resolve a root `.ot` file before lexing it.
2. Parse the resulting combined source once, preserving the resolver's source
   map for lexer, parser, and runtime diagnostics.
3. Define and test import ordering, duplicate-import behavior, circular-import
   diagnostics, relative-path policy, and module-visible declarations.
4. Route `otter run`, `check`, `web`, `desktop`, and `serve` through the same
   resolution path so modules do not vary by target.
5. Add real multi-file fixtures that execute through each supported entry
   point, not only resolver unit tests.

## Recommendation

Ship Otter 1.0 without modules and document `use` as unavailable.  The code
already gives Otter 1.1 a useful starting point, but enabling it now would be
a cross-entry-point semantic change rather than a small certification task.
