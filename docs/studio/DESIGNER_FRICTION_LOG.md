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

### Friction still open

| # | Friction | Kind | Proposed |
|---|---|---|---|
| 7 | The table's cells hug their text ("Otter Studio  In progress  Sep 30"): no columns line up without setting each cell's width | fight sizing | a table is a Grid; offer "Table" as a grid card with header row, or equal-width cells in a row (Layout: equal widths). There is no table / list control in Otter 1.0 |
| 8 | Navigation buttons in the sidebar column do not fill its width; the sidebar has no inner padding | fight sizing | a Column's default could stretch its children (align Fill) and have a little padding; today the user sets Align: Fill |
| 9 | After making the window larger than the view, part of it is off screen until Zoom to Fit (Shift+1) | orientation | fit automatically when the window outgrows the view |
| 10 | A row holding one line of text is ~20 px tall: a drop meant for it easily lands in the card around it (the target outline says so, which helps) | guess the drop target | a slightly larger hit area for thin flow containers while dragging |
