# Designer friction log

The acceptance test for the Designer is not "does drag and drop work" but
"can someone comfortably design a professional application without
thinking about the Designer itself". This log records every moment the
interaction pass had to fight the Designer, and what was done about it.

Method: a blank desktop project, built only through Designer
interactions - drags from Components, the canvas's handles and keyboard,
and typing into the inspector - driven in a real browser against the real
server, then compared with Preview (the production compiler's page). No
hand edits to the .ot or the CSS. Scripts: the pass's `s80`-`s92`, `s90`
(the dashboard).

## Pass 1 - 2026-09-29

### The first test (empty window; five controls)

Label, Button, Text Box, Image and Card each land exactly where they are
let go, at a sensible size (151x18, 100x33, 220x38, 200x140, 300x200),
none across a whole row. Move, all eight resize handles, arrows, Shift +
arrows, delete, duplicate, copy / paste, Shift / Ctrl + click all work.
Snapping (edges, centres, window centre, equal gaps) shows its guides and
leaves a spot 10 px from anything exactly where it was put. Row drops show
an insertion line and land in order; a Grid card shows the cell
("column 3, row 1") and places the control in it.

### Friction found, and fixed

| # | Friction | Kind | Fix |
|---|---|---|---|
| 1 | Clicking a button inside a row selected (and started moving) the row | fight selection / nesting | a placed container leaves presses on its children to them (577219e) |
| 2 | The marquee picked only controls entirely inside it | fight selection | picks everything it touches, as Visual Studio does (577219e) |
| 3 | The inspector showed every section for every control (Layout on a button, two Position sections) | too much, equally prominent | sections follow the control's context (577219e) |
| 4 | A column with no background is invisible on the canvas once it has content: the sidebar "vanished" | guess the drop target | containers show a faint dashed outline on the canvas (design time only) |
| 5 | An empty Row in a card is 0 px tall: nothing to drop into, so the table's cells landed in the card | guess the drop target, fight nesting | an empty container keeps a 56 x 120 "Drop controls here" area on the canvas |
| 6 | Typing in an inspector field was lost when the panel redrew meanwhile (a render finishing): about half the text edits in the dashboard run | lose work | typing not yet committed survives a redraw of the same selection |

Result after the fixes: the dashboard (sidebar with logo and four
navigation buttons, heading, search box, action button, three equal stat
cards, a content panel with a three-row table) builds with no failed step,
and Preview matches the canvas.

### Fixed in the second round

| # | Friction | Fix |
|---|---|---|
| 7 | Table cells hugged their text; columns did not line up | Layout -> Cells: Hug / Equal on a row (every selected row at once, one undo step): `#row > * { flex: 1 1 0; min-width: 0 }`, ordinary CSS the compiler embeds; duplicating a row keeps it. Checked: the three rows' cells start at the same x on the canvas and in Preview |
| 8 | Sidebar navigation did not fill the column; no inner padding | a new Column no longer writes `align "left"` or `padding 0` to the source (the compiled column stretches its children; the source `padding 0` was overriding the designer's padding): buttons fill the sidebar, 12 px inside |
| 9 | A window made larger than the view was partly off screen until Shift+1 | the view fits by itself when a window resize leaves it too big |
| 10 | A one-line row was ~20 px tall and hard to drop into | a new Row gets 8 px padding (no `padding 0` in the source): 34 px, an easy target, and a better-looking table line |

After both rounds the dashboard builds through the Designer alone with no
failed step and no fighting, and Preview (the compiled app) matches the
canvas: sidebar with logo and full-width navigation, heading, search,
action button, three equal stat cards, and a content panel whose table
columns line up.

## Pass 2 - 2026-09-29: a settings form

A Visual Studio-style form in a Free window: three labels in a column,
two text boxes and a dropdown beside them, two checkboxes, Cancel / Save
bottom right. Fields dropped 3 px off the one above snapped into line;
Align Right Edges lined the labels up; the checkbox's Checked box works.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 11 | A placed checkbox came apart in the compiled app: the box where it was put, its words at the window's top-left; on the canvas its words wrapped one per line | fight positioning; canvas and app differ | the compiler puts a checkbox's id on its label (the control as seen), the input is `<name>-box`, and the runtime reads / sets checked through the input (a33f3fc) |
| 12 | A dropdown's choices could not be set in the inspector | switch to source | an Options field (comma separated; Otter's `options "..."`) |
| 13 | A dropdown arrived 200 x 43 beside 220 x 38 text boxes | fight sizing | a dropdown arrives at a text box's size |

After the fixes the form builds with no failed step and Preview matches
the canvas: checkboxes with their words beside them, the dropdown offering
its languages.

### Found by OtterBoard (a multi-file app, 17 files)

| # | Friction | Fix |
|---|---|---|
| 14 | The Designer assumed `<project>/styles.css`; OtterBoard's stylesheet is app.css beside app.ot (D125) | the Designer edits the stylesheet the compiler uses: `<entry>.css`, else styles.css beside the entry, else the root's |
| 15 | Controls made inside a component function showed as page elements | only the program's top level is the design; a `when` keeps its nested `if ... .` |
| 16 | A page file (shell.ot) never got its real render: compiled alone it lacks what the entry brings in | the canvas and Live App compile the entry from a private mirror of the project with the open file's text in place |

### OtterBoard's Phase 6 checks (on a copy, with the Otter 1.1 compiler)

Run through the real UI against a copy of OtterBoard, never the real
folder. Passed: property edits (text, font size, colours, background,
gap, width, radius, rename) update the canvas, keep the source valid, and
survive save and reopen; undo / redo; resize handles on flow children; a
control typed in Code appears once in the Designer (no duplicates) and an
inspector edit reaches the code; Split, Designer Right, Designer, Live App
and Code keep an unsaved edit; Ctrl+S from Code mode saves it; a recent
project reopens with its tabs.

| # | Friction | Fix |
|---|---|---|
| 17 | Runtime-built pages (1.1) had almost no controls in the static HTML, so the canvas lost the real look | fewer than 60% of the design's ids found: the canvas reads the render from a hidden sandboxed run |
| 18 | An icon-only button showed the word "Button" | an icon placeholder (the icon's name on hover) |
| 19 | Ctrl+S sometimes waited many seconds | slow renders held all six browser connections; a newer render now aborts the older one and the server skips renders nobody waits for (save: 4 ms) |
| 20 | `currentPage` flagged unused though a function assigns it | the analyzer treats an assignment to an outer variable as a write to it |
| 21 | A project opened at launch (`?folder=`) never reached Recent Projects | recorded in loadProjectTree, whatever the way in |

Not a Studio fix: `mystery is a hologram` (an unknown control type) is
accepted by `otter check` and compiles to nothing. The Designer copes (it
leaves it out and the design is unharmed), but nothing tells the user.
That is for the compiler.

### Next pass

A responsive layout: the dashboard at Tablet and Mobile (Free layout
positions are per breakpoint; does rearranging for a phone feel right?).
