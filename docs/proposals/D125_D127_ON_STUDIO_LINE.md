# D125 and D127 on the Studio line: stylesheets, and nothing from other hosts

**Status:** approved by Jeff, 2026-09-30 ("Adopt the release D125", together
with D127). Both are decided on the release line (`proposal/1.1-otterboard`,
SPEC-DECISIONS.md there). SPEC-DECISIONS.md is frozen on this line, so this
record stands in until the lines merge.

## D125: web stylesheet discovery

A web program `<entry>.ot` uses `<entry>.css` from the same folder
(`main.ot` uses `main.css`). Nothing else is used: no `styles.css`, and no
stylesheet at the project root for an entry in `src/`. The stylesheet must
resolve, following symbolic links, inside the folder of the entry file. A
link to a file outside it is refused before anything is written.

What changed on this line:

- **Compiler:** `Resolve-OtterProjectStylesheet` (`src/Otter.Web.psm1`) has
  the release line's rule and its link containment (`Resolve-OtterRealPath`,
  `Test-OtterPathInside`). Before, it read `<entry>.css`, then `styles.css`
  beside the entry, then `styles.css` at the project root, and did not check
  links.
- **`otter new`:** writes `main.css` (it wrote `styles.css`).
- **Otter Studio:** the Designer edits `<entry>.css` only
  (`server/stylesheet.mjs`). New Studio projects already wrote
  `<entry>.css`.
- **Sample projects:** the six in `projects/` that had a `styles.css` now
  have `<entry>.css`. Three of them listed `styles.css` as an asset and no
  longer do.
- **Tests:** `tests/ProjectStylesheet.Tests.ps1` was rewritten for the rule.
  Its link test needs a system that can create file symlinks (Developer Mode
  on Windows) and skips, saying so, otherwise. The Electron, project-creation
  and build tests, and Studio's stylesheet and package tests, use
  `main.css`.

Anyone with a `styles.css` of their own renames it to `<entry>.css`. Nothing
reads `styles.css` any more, so a page that used one loses its styling until
it is renamed.

## D127: no external resources in generated web applications

A compiled page loads nothing from another host. The Google Fonts links are
gone, and pages use the system font stack, so a page starts and renders
offline. `tests/Web.Tests.ps1` 37 checks that no `<link>` or `<script>`
reaches another host. Developers can still add external resources
deliberately in their own stylesheet or code.
