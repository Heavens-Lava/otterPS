# Runtime UI, phrase functions, and the other additions from OtterBoard

Written while building **OtterBoard** (the flagship example application),
proposed for Otter 1.1 on the `proposal/1.1-otterboard` branch, which starts
from v1.0.0-rc.4. Every addition below is general, tested, and in use by
OtterBoard. It builds on D128 (UI created while a web page runs): the same
handles, templates and messages, extended so that UI resources are values.
None changes the meaning of a program that worked before, except where noted
(the D56 amendment in P1, and fixes).

`SPEC-DECISIONS.md` is frozen, so these are **proposed decisions**, numbered
here only for reference (P1–P9). Each lists its tests.

---

## P1. Runtime UI: elements are values

UI can be built while the program runs - inside a function, a handler or a
loop - and an element is an ordinary value. A function that builds one and
returns it is a **component**.

```otter
to makeStatCard label and value
    card is a card with style "stat-card"
    title is a text with value label, style "stat-label"
    number is a text with value value, style "stat-value"
    put title, number in card
    when card is clicked
        say "You clicked" label
    .
    return card
.

makeStatCard "Projects" and 6 into projectsCard
put projectsCard in statRow
```

What works at run time, on declared and built elements alike:

| Statement | Meaning |
|---|---|
| `x is a <kind> with ...` / `create <kind> into x` | build an element |
| `put a, b in container` | attach (an element can be in one place only) |
| `remove item from container` | detach one element |
| `clear container` | remove everything put in it; a text box loses its text, a dropdown its options, a list its items (contextual: `clear` stays a usable name) |
| `show x` / `hide x` / `focus x` | visibility and keyboard focus (**D56 amendment**: `hide` and `focus` were refused in 1.0; they now run on the web and on the console) |
| `when x is <event>` | a handler, registered where it runs; it sees that call's or that loop iteration's variables |
| `<property> of x is value` | the same property meanings as in a declaration |

D128 made `create`, `put`, `show` and `when` work while a page runs, for names
made by `create`. This makes every UI resource a value: any operation decides
at run time what a name refers to - the resource it holds, or the element the
page rendered under that name - so component functions, lists of resources
and resources passed as arguments all work. Runtime resources are made from
the same per-kind templates D128 uses, so they are the same markup as
rendered ones.

Mistakes are Otter errors, with the interpreter's wording ("I can only put a
UI resource somewhere, but this is some text."): putting something that is
not UI, putting a resource that is already somewhere, putting one inside
itself, removing one from a container it is not in.

**Tests:** `tests/RuntimeUi.Tests.ps1` (real `otter web`, run in headless
Microsoft Edge), `tests/WebRuntimeUi.Tests.ps1` (D128's, updated for the D56
amendment), `tests/UI.Tests.ps1` (console: hide, show, focus, clear).

## P2. Properties shared by every kind

| Property | Meaning |
|---|---|
| `style "panel selected"` | named styles from the project's stylesheet (`class` is accepted as the older spelling) |
| `hidden true` | starts hidden; `show x` reveals it |
| `enabled false` | disabled and shown as such |
| `tooltip "Settings"` | hover text; also the accessible name of an icon-only button |
| `label "Search projects"` | accessible name for a control without visible text |
| `shortcut "Ctrl+K"` | the key combination activates the element: a text box is focused, anything else clicked. The visible element latest in the page wins, so a dialog's `shortcut "Escape"` takes precedence over the page's |
| `icon "calendar"` (button) | a symbol from the page's icon sprite before the label |

New kind and page property:

```otter
app is a page with title "OtterBoard", icons "assets/icons/app-icons.svg"
home is an icon with name "dashboard", size 18
```

The page's `icons` sprite (an SVG file of `<symbol>`s) is embedded once, so
icons work from a file, a server and inside Electron. A missing sprite is a
compile error.

While something is dragged over an element with `accepts drops true`, it
carries the `otter-drop-over` class, so a stylesheet can show where a drop
will land.

New event word: `when box is submitted` - Enter in a text box (Ctrl+Enter in a
text area).

A declaration may use computed values (`out is a text with value name of
first`, `pick is a dropdown with options names`); they are applied when the
program starts. Any kind may be declared without properties (`entry is a text
box`).

## P3. Phrase functions

A function is a phrase. Prepositions (`with`, `for`, `to`, `from`, `in`,
`on`, `at`, `by`) may introduce its parameters, and calls may use the same
words:

```otter
to openNote with noteId
    ...
.
to recordActivity kind and description for projectId
    ...
.

openNote with 12
recordActivity "task" and "You finished it" for 4
projectName for 5 into name
```

The words are optional at a call (`openNote 12` still works), but a word that
is written must be the declared one: `openNote for 12` is an error that shows
how the function is written. Built-in statements still come first (D1), so a
function named `move` is reached by the built-in `move`.

**Tests:** `tests/Parser.Tests.ps1` (phrase section).

## P4. `into` for a call's result; `make` stays

`findProject with 3 into project` captures the result, like every other
statement that produces a value (`read ... into`, `split ... into`). `make`
remains accepted.

## P5. `its`, and `find` without `into`

Inside `each` and a `find` condition, `its <property>` means that property of
the item in hand:

```otter
each task in tasks
    if its done
        its status is "Done"
    .
.

to findProject with projectId
    return project in projects where its id is projectId
.
```

`find x in xs where ...` without `into` puts the match (or `gone`) in `x`;
`return x in xs where ...` finds and returns it. Outside those places `its`
is an ordinary name.

**Tests:** `tests/Parser.Tests.ps1`, `tests/Collections.Tests.ps1`,
`tests/RuntimeUi.Tests.ps1`.

## P6. Smaller language gaps

| Addition | Example |
|---|---|
| `an` is the article `a` | `home is an icon`, `an Activity has` |
| call arguments may be expressions; `and` separates them | `label "Due " plus day and count times 2` |
| `return` may return a comparison | `return due of task is todayKey` |
| a date moves by a computed amount | `add offset days to due` |
| `weekday of date` | 1 = Monday ... 7 = Sunday, web and interpreter |
| `text of number` | `"You have " plus text of count plus " tasks"` |
| two functions with one name | a compile error naming both lines (it used to break the page) |

## P7. Fixes in the JavaScript compiler

* Calls to async user functions (any function that reads a file, or calls
  one that does) are awaited, program-wide. Before, `loadData into data`
  bound a pending promise, and failures escaped `try ... otherwise`.
* Inside a function, variables assigned in a loop body are bound per
  iteration for the handlers registered in that iteration (and copied back,
  so counters and "the last value after the loop" behave as before).
* `replace ... in x` inside a function changes the local `x`, not a new
  global.

## P8. Files in a plain browser tab

With no desktop bridge, `write`, `read`, `append`, `delete file` and `file
... exists` use the page's own browser storage, so a program's data persists
between visits. Reading a file the program never wrote is "File not found",
as on a desktop. Other file operations report that they need the desktop
application. (Before: `read` returned `""` and `write` returned `false`, with
only a console warning.)

## P9. Desktop

* **`otter desktop`** opens the window at the size the page declares: `app is
  a page with ... width 1600, height 1000, minwidth 1080, minheight 700,
  background "#0a1224"` (carried in `<meta name="otter-window">`).
* **`otter web copy.ot -SourceDir <folder>`** compiles a file as though it
  lived in `<folder>`: its `use` imports, its `<entry>.css` and its icon
  sprite are found there. For editors that render an unsaved buffer.
* **`otter run`** opens a program whose root is a declared page or window in
  the desktop host, as `otter desktop` does; the console interpreter could
  only stop at its first `put`.
* The desktop host's startup grace starts when the window opens, not before
  compiling (a large program's window used to close a few seconds after
  opening).

Studio and Electron follow-ups (window settings in the Electron export,
`otter studio <folder>`, multi-file Designer and Live App renders) belong to
the Studio/Electron preview branch, not to this proposal.

**Tests:** `tests/Web.Tests.ps1` (-SourceDirectory and the window meta).

---

## What the Designer can and cannot show

The Designer shows and edits **declared** UI - the application's frame,
pages, panels, dialogs and forms. UI a program builds while running (the
cards in a project grid, the rows of a task list) exists only when the
program runs, so it appears in the Live App, not as selectable elements in
the Designer. The declared container it goes into is selectable and
styleable, and the components are ordinary Otter functions in the editor.
