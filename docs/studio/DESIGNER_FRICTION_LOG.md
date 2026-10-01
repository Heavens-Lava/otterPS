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

## Pass 3 - 2026-09-29: the dashboard at Tablet and Mobile

The pass-1 dashboard (a Free window, 1104 wide), rearranged through the
Designer for Tablet (768) and Mobile (375), then compiled and measured in
a browser at 1280, 768 and 375. Tablet: sidebar narrowed, header and
cards dragged in. Mobile: the window set to Flow, the sidebar hidden (⊘).

| # | Friction | Kind | Fix |
|---|---|---|---|
| 22 | At Tablet / Mobile everything placed past the screen's width was clipped away; pressing where card 3 hung out started a marquee instead of moving it. The app does not clip: it scrolls sideways | can't reach; canvas and app differ | on a device width the window draws what hangs past its edge, so it can be grabbed; the window's badge counts it ("5 past the edge") |
| 23 | Flow for the window at Mobile did nothing: turning Free off removed values that live on Desktop | switch to source | on a narrower breakpoint Flow stacks there explicitly (`position: static`, no wider than the screen) and Desktop / Tablet keep their layout |
| 24 | Stacked, the controls came in the order they were added (New Project first, the sidebar last) | fight order | they stack in the order they are seen on the wider layout: `order` at that breakpoint only |
| 25 | Dragging card 3 over the panel at Tablet put it inside the panel - on every screen: on Desktop it then sat 800 px into the panel | structure changed by a size-only edit | on Tablet / Mobile a move only places a control; the drag label says to use Desktop to put it in another container |
| 26 | In the stacked Mobile layout the cards were squeezed (panel 215 px tall; 439 in the app) | canvas and app differ | the canvas window's children never shrink to its height, as in the compiled window |

After the fixes the compiled app is 1280 wide at Desktop (unchanged),
stacks within 375 px on a phone in reading order with the sidebar hidden,
and neither narrower edit changed a wider one.

Still open:

- In the test harness a drop from Components into a card is sometimes not
  delivered (the browser ends the drag with no drop event) - about half
  the runs of the full build, never in a short one. Not diagnosed; not
  seen by hand.
- Stacked on a phone, cards keep their Desktop width (260 of 325); making
  them full width is a Width edit per card at Mobile.

## Pass 4 - 2026-09-30: a website, from New Project to a folder to upload

A new Website through the New Project dialog, edited in the Designer,
built with Ctrl+Shift+B, and the output opened from disk at 1280 and 390
px. Also a real 196-line site (examples/jeffreymacy.ot) opened and edited.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 27 | The Web starter was a 720 x 520 "window" with a counter that did not count (its buttons only said so in the output) | not a website; starter lies | a Website starter: `app is a page` with navigation links, a hero, features the Features link jumps to, a footer; responsive (rows wrap) |
| 28 | Links, badges, text areas, toggles, radio buttons (and lists, tables...) vanished from the canvas: the designer dropped every kind it did not know | can't see or select | they are designer components; links have a Link to field; kinds the designer cannot edit yet are shown and selectable ("edited in code"); other spellings (switch, textarea, check box...) map too |
| 29 | A page was modelled as a desktop window: "Window (app)", a traffic-light frame, regenerated source `app is a window` | wrong kind | the model remembers a page: "Page", "Page title", a browser frame with an address bar, and source keeps `page` |
| 30 | A full-width page filled the whole canvas stage (1697 px) and was cut off both sides | can't see it | on Desktop a full-width page is drawn at a desktop browser's width (1280) |
| 31 | New controls in a starter carried designer defaults (pale text, a dark window) as inline styles that beat the stylesheet | stylesheet ignored | starters write only what they mean; a control with no properties still compiles (it keeps one default) |
| 32 | Rows could not wrap from the stylesheet (the compiler inlines `flex-wrap: nowrap`) | fight CSS | `wrap true` is written to the source; the starter's feature cards stack on a phone |
| 33 | After a build nothing said where the site went or let you see it | dead end | the Output offers Open the website (the system browser, never Studio's origin) and Show the build folder; also Build > Open Built Website |
| 34 | A toggle or radio button placed in a Free window would come apart (its id was on the input, like the old checkbox) | fight positioning | the id is on the label, the input is `<name>-box` (as the checkbox) |
| 35 | The desktop starter's "Click Me" only printed a line | starter lies | "Say hello" greets the name typed in the box |

Result: a new website builds to `dist/index.html` + `styles.css` in
about 5 s, 1280 and 390 px wide with nothing overflowing, links working
(`#features`, `#footer`, mailto).

## Pass 5 - 2026-09-30: a task app (state and events)

`examples/v1/tasks.ot` rebuilt through the Designer as a user: heading,
text box, Add button and a list column dropped and renamed (taskInput,
addButton, taskList); the Add handler written through the Events tab;
then run in Live App, two tasks added.

A task list creates a row per task while it runs: Otter 1.1's D128 (web
UI created at runtime), which is only on `proposal/1.1-otterboard`. The
pass ran on a throwaway local tree (that branch + this Studio, never
pushed); every fix below is Studio-side and applies to both lines.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 36 | The Events tab's handler editor lost the caret after the first character (the panel redrew on every keystroke): the handler was `t`. It also had no highlighting, completion or indentation, and "Configured" was a toggle that deleted the handler | can't write code | handlers are written in the code editor: Add handler writes `when x is clicked` with a first line to replace, shows Split, selects that line; the panel previews each handler and opens it; Remove asks first |
| 37 | The running app lost the design's layout (the Add button full width above the box, the window's own title shown) | canvas and app differ | renders compile a copy named like the entry (main.ot) with the designer's stylesheet, saved or not, beside it and in the project mirror: what runs is what is on screen |
| 38 | New projects' styles went to styles.css, which the release line's compiler never reads (its D125: only `<entry>.css`) | styling lost on build | new projects get `<entry>.css` (main.css), the stylesheet every compiler reads; a project with styles.css still works here; the inspector names the real file |

With these the task app works end to end through Studio: Add handler, the
handler typed in the editor (it indents and closes the `if` block itself),
no problems, and in Live App each Add creates a row and clears the box,
laid out as designed.

**Needs a decision (Jeff):** the two lines disagree on D125 - this branch
reads `<entry>.css`, then `styles.css`; `proposal/1.1-otterboard` reads only
`<entry>.css`. Studio now writes `<entry>.css`, which both read. And real
apps (anything that adds items while it runs) need D128 on the line Studio
ships with.

## Pass 6 - 2026-09-30: tick and remove on each task

The task app again (1.1 tree), now with a `to addTask label` function
pasted into the code: each Add builds a row (a checkbox with the task, a
Remove button) and gives that row's button its own handler
(`when removeButton clicked` / `line has visible false`). Then back in the
Designer, the heading edited in the inspector.

No new friction. The Designer kept the hand-written function byte for byte
through a designer edit and did not take the controls the function makes
for design elements; the source stayed valid; in Live App three tasks were
added, one ticked, one removed, each row's handler acting on its own row.

## Pass 7 - 2026-09-30: a website of two pages

Jeff chose "every page file" (docs/proposals/MULTI_PAGE_WEB_BUILD.md). A new
Website; File > New Page... "about"; the home page's second nav link pointed
at the About page from the Link to suggestions; built with Ctrl+Shift+B;
then dist/index.html opened from disk and clicked through like a visitor.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 39 | A site of several pages could not be built (one entry, one index.html) | can't ship | every page file beside the entry builds to its own page (about.ot -> about.html) with its own stylesheet; modules and parts of pages do not |
| 40 | No way to add a page | missing | File > New Page... (about.ot + about.css, opened in the Designer) |
| 41 | A page other than the entry rendered as the entry (the canvas showed the home page while about.ot was open) | wrong document | a page file renders as itself; a part of a page still renders as the project |
| 42 | Typing page names into Link to | guessing | Link to suggests index.html, the other pages and this page's sections |
| 43 | Every new website failed its first build: its project.json listed an asset "styles.css" that no longer exists (new projects' stylesheet is <entry>.css) | build fails | new projects list no stylesheet as an asset (the compiler embeds it) |
| 44 | New Page and Open Built Website were commands but not in the File / Build menus | can't find | both are in their menus |

Result: Home -> About -> Home works in the built site from disk
(index.html, about.html).

## Pass 8 - 2026-09-30: a contact form and a picture

A new Website: a picture imported through Assets > + Import and clicked
onto the home page; File > New Page... "contact"; name, email and message
fields, a Send button and a status line added from Components and renamed;
Send's handler (an empty name asks for it, otherwise thanks and clears the
box) through Add handler; used in Live App; built; then the built pages
opened from disk.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 45 | The picture was missing from the built site: the page pointed at assets/images/team-photo.png, which the build never copied | broken on publish | Studio keeps the manifest's assets in step: an imported image is listed, and before each build the project's own images its pages show are listed (the build copies listed assets); the Output says what was added |
| 46 | Controls added to a white page came with dark-app colours: dark navy fields, and pale grey status text ("Thanks, Ada!") barely readable on white | unreadable | a control added onto a light surface (the nearest background up its containers) gets light-surface colours; colours given explicitly are kept; dark apps keep theirs |

Result: the built contact page validates and thanks ("Please tell us your
name." / "Thanks, Grace! ..."), readable (slate text, dark text on light
fields); the picture loads in the built home page (dist/assets/images/).

## Pass 9 - 2026-09-30: publishing a website

A new Website with a picture from Assets on the home page, then Build >
Publish... - which did not exist, so it was added: it saves, runs the real
`otter publish`, and the Output ends with where the upload folder is and two
buttons, Open the website and Show the files to upload.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 47 | No way to publish from Studio: `otter publish` existed only on the command line | missing | Build > Publish... runs it; the Output names the folder and .zip to upload to any static host, with Open the website and Show the files to upload |
| 48 | In the Designer a build or publish ran with the Output panel folded, so the result (or the failure) was invisible | invisible result | Build and Publish open the Output panel |
| 49 | After publishing, Assets showed the published copies: the picture twice, and otter.build.json / otter.publish.json under Data | wrong | Assets skips publish/, the manifest's build and publish output folders, and Otter's build records |

Result: publish/zz-publish-1.0.0/ holds index.html and assets/images/, beside
the .zip and its .sha256; the published page opened from disk shows its title
and the picture.

## Pass 10 - 2026-09-30: on a phone, and a site's description and icon

The Website starter plus File > New Page... "about", built, and the built
pages viewed at 375px (phone) and 768px (tablet). Then a new Website with an
icon imported through Assets, the page's Description and Icon set in Page
properties (Jeff's decision: they belong to the page), built.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 50 | On a phone the links (Features, Contact, the email, a new page's Home) were about 20px tall, under the 24px minimum to tap | hard to use | the starter's and New Page's links are 32px tall |
| 51 | A website could not say what it is: no description for search results or shared links, no icon in the browser tab | missing | `description` and `icon` on a page (docs/proposals/PAGE_DESCRIPTION_AND_ICON.md); Page properties has both; the build lists the icon as an asset |
| 52 | An image imported through Assets did not appear in the Explorer, or among the choices for a link or icon, until the project was reopened: the import's "files changed" event had no listener | stale | Studio reloads the project's files when Assets adds one |
| 53 | A page title with & or < broke the built page's markup | broken | the title is escaped in the head and the header |

Result: at 375px and 768px nothing overflows, rows stack, text wraps and
every link is tappable; the built page's head has the description, og tags and
the icon, which loads from dist/assets/images/.

## Pass 11 - 2026-09-30: a form that checks itself

Jeff approved forms (docs/proposals/FORMS_AND_VALIDATION.md). The pass: a
new Website, then File > New Page... "contact". A Form was added from
Components and filled with name, email and message fields and an "I agree"
box, each given a Label and rules in the new Validation section (Required,
Format: Email address, Min length). Then a Send button, and the form's Sent
handler added through Events. It was used in Live App, built, and the built
page used at phone width.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 54 | Every form rule was an `if` in a click handler; no email check, one status line for all messages | missing | the `form` container, rules on fields, messages under each field, `when <form> is sent` |
| 55 | Live App: Send did nothing - the preview iframe's sandbox had no allow-forms, so the browser dropped the submit (the built page worked) | broken in Studio only | Live App allows forms (still sandboxed without same-origin) |
| 56 | A new checkbox started ticked, so a required "I agree" box passed untouched | wrong default | new checkboxes start unticked |
| 57 | A text area on a light page was dark navy (it had no colours for the light-page fitting to change) | unreadable | text areas get the same default colours as text boxes, so a light page gets light ones |
| 58 | The Designer did not show a field's label; the built page did | Studio differs from the build | the canvas draws it above the box and gives it its line, as the page does |
| 59 | A labelled box kept the stock hint "Enter text..." into the built page | noise | setting a Label clears the stock placeholder |

Result: in Live App and in the built page, Send with nothing filled in shows
"Please fill in Your name." and the other messages under their fields, and
focuses the first. A bad email shows "Email needs to be an email address, like
name@example.com.", and each message goes as you correct the field. Enter in
a box sends, and "Thanks!" appears only when everything passes.

## Pass 12 - 2026-09-30: a page that shows data and adds to it

The goal was a guestbook: sign it, and your entry appears under the form.
The first finding was a language gap. On this line a web page could not draw
anything a program made while it ran: `tasks is a list` drew an empty box,
and a card created in a handler compiled to nothing. Jeff approved bringing
D128 (decided for the release line) across
(docs/proposals/D128_ON_STUDIO_LINE.md).

Then, in Studio: a new Website and File > New Page... "guestbook". A Form
(Your name, Message, both required) with a "Sign the guestbook" button, and
an entries column under it. The form's Sent handler was added through Events:
it creates a card with the name and the message, puts it in entries, and
clears the boxes. It was used in Live App (two signatures), built, and signed
again on the built page at phone width.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 60 | A page could not show anything made while it ran: a list drew nothing, and a card created in a handler compiled to nothing | missing (language) | D128 brought to this line: `create`, `put`, `show`, `when` work while the page runs |
| 61 | The created entries were dark navy cards with dark text on a white page | unreadable | on a light page the compiler's default cards, inputs and borders are light |
| 62 | Created entries can't be styled from the stylesheet (generated ids) | limitation | style them in the handler with `has`; a class named after the variable is noted for Jeff |
| 63 | The handler that builds an entry is written by hand; the Designer can't lay out "one entry" | missing | open: a way to design a repeated item |

Result: in Live App and in the built page, each signature adds a readable
white card with the name and message under the form, and the boxes empty for
the next one.

## Pass 13 - 2026-09-30: styling entries, components, getting online, honest settings

Jeff approved four pieces of work: a class for created elements, P1 from the
1.1 proposal, host guides, and honest project settings.

- **Styling created entries (friction 62):** `create card into entry` now
  gives the card the class `entry`, so `.entry { ... }` in the page's
  stylesheet styles every one. Checked in a browser.
- **Designing one entry (friction 63):** P1 ("UI resources are values", from
  the 1.1 proposal) is on its own branch, `studio/p1-runtime`. A function that
  builds a card and returns it works there. Half of P1 needs Codex's 1.1
  parser changes (declarations inside functions, `clear`, `remove ... from`,
  `is submitted`), so it waits for those. Then the Designer can design a
  component.
- **Getting online:** Publish ends with "How to put it online...", which gives
  the steps for Netlify Drop, GitHub Pages, Cloudflare Pages or your own host.
  Each names the folder and .zip that Publish just made. Nothing is uploaded
  from Studio.
- **Project Settings:** checked against what `otter build` does.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 62 | Created entries could not be styled from the stylesheet | limitation | the element has its variable as a class (`.entry`) |
| 64 | "Minify Output Bundle" did nothing: the build read build.minify and ignored it | Studio differs from the build | `otter build` minifies each page's code (comments, indentation), about a fifth smaller with the same behaviour; the switch is now "Minify pages" |
| 65 | "Generate Source Maps" (on by default) did nothing: no build makes source maps | Studio differs from the build | the switch is gone |
| 66 | "Security & Permissions" switches did nothing: nothing in Otter reads manifest.permissions, so unticking Process Execution did not stop a program starting one | misleading | the card is gone (Jeff); enforcing permissions would be a language decision |
| 67 | After Publish, nothing said how to get the folder onto the web | missing | the host guide |

### Next pass

When Codex's 1.1 parser changes arrive: merge studio/p1-runtime and design a
component in the Designer (friction 63).

## Pass 14 - 2026-10-01: a project's whole Git life

A new project folder, opened from This computer, taken through Git with the
Source Control pane only (scratch dogfood d21 and d21b):

1. Initialize Repository. The three files show U in the Explorer.
2. Stage all, write "First version", Ctrl+Enter.
3. Change line 3 in the editor. The gutter marks it modified before saving.
   After saving, the Explorer shows M.
4. Click the file. The side-by-side diff shows +1 -1.
5. Stage it with + and commit.
6. Branches: create and switch to "feature". Change a line and commit. With
   nothing staged, Studio asks "Commit all changed tracked files?".
7. Switch back. The open editor shows the old line.
8. Merge "feature". The editor shows the new line.
9. Remotes: add origin, a bare repository in a folder. Push publishes the
   branch: ↑0 ↓0, and History shows origin/master.
10. Two branches change the same line, and the merge conflicts:
    - Merge Conflicts lists the file with !, the banner offers Abort Merge,
      and Commit is disabled;
    - the conflict editor shows Ours and Theirs; Accept theirs, then Save and
      mark resolved;
    - the merge commit goes in with Git's message.

| # | Friction | Kind | Fix |
|---|---|---|---|
| 68 | A remote given as a folder path (C:\...\shared.git) was refused: only URLs were accepted, although Git takes a folder | limitation | a full folder path is accepted (C:\, \server\, /); relative paths and other transports such as `ext::` are still refused |
| 69 | After Commit, the message box still held the old message. The pane was redrawn from the box before it was emptied | broken | the box is emptied before the redraw |
| 70 | Committing a merge started from an empty message box, although Git had prepared "Merge branch 'other'" | missing | the box is filled with Git's message once per merge, and the user can still change it |
| 71 | "Merge in progress" checked .git/MERGE_HEAD. In a Git worktree, .git is a file, so a merge there would not show (found while making 70; not seen in the UI) | broken in worktrees | Studio asks git for the path (`rev-parse --git-path`) |

Not Git, and not fixed here: the fixture design's `image1 is a image` does
not run on the desktop.
- The run stops with "I can only put a UI resource somewhere, but this is a
  image".
- `an image` is a syntax error.
- `with width 48, source "a.png"` does not parse, though other orders do.

The web build has an image kind. The interpreter and parser (Codex's) do not
handle it the same way. This is for Jeff.
