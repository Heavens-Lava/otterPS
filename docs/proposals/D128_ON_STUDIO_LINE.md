# D128 on the Studio line: UI created while the page runs

**Status:** approved by Jeff, 2026-09-30 ("Port D128 core"). D128 itself was
decided on 2026-09-29 for the release line (`proposal/1.1-otterboard`,
SPEC-DECISIONS.md there). This record exists because SPEC-DECISIONS.md is
frozen on this line and its D-numbers differ. The entry comes across when the
lines merge.

## Why

A page could not show data that changes. `tasks is a list` drew an empty box,
and a handler that created a card or a line compiled to nothing: the page
ran, and nothing appeared. A guestbook, a task list or a basket was not
possible to build in Otter Studio.

## What came across

From `proposal/1.1-otterboard`:

- `ce2ea11`: `create`, `put`, `show`, `hide`, `focus` and `when` work while
  the page runs (`src/Otter.Web.psm1`, `src/Otter.Compiler.JavaScript.psm1`).
- `11aaeaf`: `tests/WebRuntimeUi.Tests.ps1` and its headless driver. The
  browser part needs `OTTER_PLAYWRIGHT_CORE`, and skips without it.
- `0328289`: the compiler and test parts only. The web compiler never
  compiles a statement to nothing; it follows D56 like the console.
  `SPEC-DECISIONS.md` and `CHANGELOG.md` were not touched.

Not brought: `fdda7e2` ("UI resources are values", component functions,
`hide` / `focus` / `clear` as a 1.1 proposal). It is still undecided.

## Found while using it

- **Created cards were unreadable on a light page:** dark navy (the dark-app
  default) with the page's dark text on them. The web compiler now picks
  light card, input and border colours when the page's background is light
  (`Get-OtterSurfacePalette`, tests/Web.Tests.ps1 36). A dark app keeps its
  colours.
- **Created elements can't be styled from the stylesheet:** they get
  generated ids (`otter-ui-1`), so no `#name` rule reaches them. They are
  styled from code with `has` (`entry has background "#f8fafc"`). A class
  named after the variable (`.entry`) would let a stylesheet reach them. That
  is a small addition for Jeff to decide on; it is not built.

## Evidence

- `tests/WebRuntimeUi.Tests.ps1`: 7 of 7 with the browser, including
  `examples/v1/tasks.ot`.
- Studio friction-log pass 12: a guestbook built in Studio (a Form and an
  entries column; the Sent handler creates a card per message), used in Live
  App and in the built page at phone width.
