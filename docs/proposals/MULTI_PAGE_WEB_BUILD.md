# Websites of several pages

**Status:** approved by Jeff, 2026-09-30 (option "Every page file"). To be
given a D-number in SPEC-DECISIONS.md when the Studio line and the release
line merge; their D-numbers differ today, so none is assigned here.

## Problem

`otter build` compiled one entry point into `dist/index.html`. A website of
several pages (home, about, contact) could not be built; only one page with
in-page links (`url "#features"`).

## Decision

For a project whose target is `web`, `otter build` builds **every page file
beside the entry point** into its own page:

- The entry point builds to `index.html`, as before.
- Any other `.ot` file in the entry's folder that **declares a page and shows
  it** (`about is a page ...` / `show about`) builds to `<name>.html`:
  `about.ot` to `about.html`.
- Each page uses its own stylesheet, `<name>.css` beside it (D125's rule, per
  page).
- A file that does not declare and show a page - a module (`to greet ...`), a
  part of a page included with `use` - is not a page and is not built.
- A page file named `index.ot` that is not the entry point is refused: it
  would build over the entry's `index.html`. The message says so.
- Links between pages name the built file: `url "about.html"`,
  `url "index.html"`.

Desktop and game targets stay one window, built from the entry point only.

## Studio

- File > New Page... creates `<name>.ot` (a page with a heading, some text and
  a link home) and `<name>.css`, and opens it in the Designer.
- A page file renders as itself in the Designer and Live App; a part of a
  page still renders as the whole project from its entry point.
- A link's "Link to" field suggests `index.html`, the other pages, and the
  sections of the page (`#features`).

## Evidence

- `tests/ProjectBuild.Tests.ps1` tests 17-18: two pages and a module; the
  `index.ot` clash.
- `otter-studio/scripts/workspace-projects.test.mjs` 4d: a page file renders
  as itself.
- Dogfood (docs/studio/DESIGNER_FRICTION_LOG.md, pass 7): a website of two
  pages made through Studio, built, and clicked through from disk (Home ->
  About -> Home).
