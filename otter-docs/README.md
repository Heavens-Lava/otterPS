# Otter Documentation

This is a dependency-free, generated static documentation site. Pages live in
`src/pages.mjs`; the build script gives each page a clean directory URL such as
`/learn/conditions/`.

```powershell
cd otter-docs
npm run dev
```

Then open `http://localhost:4173`. `npm run build` writes the deployable site
to `dist/`. The generated search index is `dist/search-index.json`.

The site intentionally documents only implemented Otter behavior. Additions to
the language should first be frozen in the language contract and decisions,
then documented here in user-facing terms.

## Every example is checked against the real parser

```powershell
npm run check
```

`scripts/check-examples.mjs` pulls every Otter code block out of
`src/pages.mjs`, writes each one to a temporary file, and runs it through the
actual Otter parser with `otter.ps1 -ParseOnly`. The build will not produce a
site if any example fails.

`-ParseOnly` checks that a program is well formed and stops there. Nothing is
executed, so an example that deletes a file or launches a program is safe to
verify.

Documentation showing code that does not work is worse than documentation
showing less code: a beginner cannot tell "I typed it wrong" from "this page
is out of date". This makes that impossible to ship by accident.

Blocks written with `shell(...)` are terminal commands or REPL transcripts
rather than Otter source, and are skipped.

## Documenting only what runs

A feature belongs on this site when it can be **run from an Otter program**,
not when the runtime supports it. Several features are implemented in the
interpreter but have no parser grammar yet, so no Otter program can use them.
Those pages say plainly that the feature is not available rather than showing
code that will not run.
