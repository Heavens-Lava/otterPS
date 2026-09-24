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

## Otter-authored site shell

`site.ot` is the first documentation page authored entirely in Otter. Compile
it from the repository root with:

```powershell
.\otter.cmd web otter-docs\site.ot -NoOpen
```

This writes `otter-docs/site.html`. The page uses Otter's current web resources,
rows, columns, links, grouped properties, and containment syntax. The existing
Node build remains available while navigation, content loading, and search are
migrated incrementally to Otter output.

Independent Otter-authored routes live in `pages/`. Build them into clean URL
directories with Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\otter-docs\scripts\build-otter-pages.ps1
```

The generated routes include the home page, Download, Examples, First Program,
Reference, Release Status, Studio status, and the current tutorial/reference
pages. Generated HTML is intentionally ignored; the `.ot` files are the source
of truth.

`release-data.json` is the single website source for the current release
version, Windows requirements, and installer metadata. The Otter route build
fails if its version differs from the repository `VERSION` file. Until an
installer is actually published, its size, date, checksum, release notes, and
download action remain explicit "not published" states rather than placeholders.

Audit generated internal navigation before publishing:

```powershell
npm run audit:otter
```

Preview the generated Otter site locally:

```powershell
npm run dev:otter
```

Then open `http://localhost:4174/`. The root route serves the Otter home page;
other routes use the generated clean directories.

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

## The new design (Otter-authored pages)

Every route under `pages/` uses one shared design, written in Otter:

- `pages/_shell.ot` - the top bar and footer. `use`d by every page.
- `pages/_docs.ot` - the docs sidebar. `use`d by every docs page. Only the
  current page's group is expanded, so the highlighted link is always visible
  without scripting.
- Files starting with `_` are modules, not routes; the build skips them.
- `scroll true` on a page makes it scroll like a document (a website) instead
  of filling the window like an app shell.

### Adding or moving pages

`scripts/new-docs-page.ps1` scaffolds a docs page from a short content list.
The generated `pages/<slug>.ot` is then the source of truth - edit it directly.
`scripts/build-docs-content.ps1` regenerated the sidebar and migrated the old
Node pages (`scripts/export-legacy-pages.mjs` -> `scripts/legacy-pages.json`);
it is a migration tool, not part of the site build.

### Checking the samples

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-otter-page-examples.ps1
```

parse-checks every Otter code sample on the Otter-authored pages with the real
parser (`otter check`), skipping shell commands and program output.
