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
| 7 | Table cells hugged their text; columns did not line up | Layout -> Cells: Hug / Equal on a row (every selected row at once, one undo step): , ordinary CSS the compiler embeds; duplicating a row keeps it. Checked: the three rows' cells start at the same x on the canvas and in Preview |
| 8 | Sidebar navigation did not fill the column; no inner padding | a new Column no longer writes  or  to the source (the compiled column stretches its children; the source  was overriding the designer's padding): buttons fill the sidebar, 12 px inside |
| 9 | A window made larger than the view was partly off screen until Shift+1 | the view fits by itself when a window resize leaves it too big |
| 10 | A one-line row was ~20 px tall and hard to drop into | a new Row gets 8 px padding (no  in the source): 34 px, an easy target, and a better-looking table line |

After both rounds the dashboard builds through the Designer alone with no
failed step and no fighting, and Preview (the compiled app) matches the
canvas: sidebar with logo and full-width navigation, heading, search,
action button, three equal stat cards, and a content panel whose table
columns line up.

### Next pass

Build a second, different application (a settings form with labelled
inputs, checkboxes and a footer of buttons; then a responsive layout at
Tablet and Mobile) to find the next set of friction.
