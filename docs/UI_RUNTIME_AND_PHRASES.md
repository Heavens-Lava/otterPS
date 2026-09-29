# Runtime UI, phrase functions, and the other additions from OtterBoard

Written while building **OtterBoard** (the flagship example application) on
the `feature/otterboard` branch. Every addition below is general, tested, and
in use by OtterBoard. None changes the meaning of a program that worked
before, except where noted as a fix.

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
| `clear container` | remove everything put in it (contextual: `clear` stays a usable name) |
| `show x` / `hide x` / `focus x` | visibility and keyboard focus |
| `when x is <event>` | a handler, registered where it runs; it sees that call's or that loop iteration's variables |
| `<property> of x is value` | the same property meanings as in a declaration |

Before this, on the web and desktop targets, UI built at run time became a
plain `thing`, and `put`, `show`, `hide` and a nested `when` compiled to
**nothing** - silently. Unsupported UI statements are now either compiled or
reported.

Mistakes are Otter errors: putting something that is not UI, putting an
element that is already somewhere, removing an element from a container it
is not in.

**Tests:** `tests/RuntimeUi.Tests.ps1` (real `otter web`, run in headless
Microsoft Edge).

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

## P9. Desktop and Studio

* **Electron** opens the window the page declares: `app is a page with ...
  width 1600, height 1000, minwidth 1080, minheight 700, background
  "#0a1224"` (carried in `<meta name="otter-window">` into `package.json`),
  instead of a fixed light 1200 x 800. `otter desktop` uses the declared
  size too.
* **`otter studio <folder>`** opens a project anywhere on the computer.
  Studio gets access to that folder and its own installation, nothing else.
* **`otter web copy.ot -SourceDir <folder>`** compiles a file as though it
  lived in `<folder>`; Studio uses it to render unsaved buffers of project
  files, so the Designer and Live App resolve `use` imports and load images.
* **`otter run`** (and Studio's Run) opens a program whose root is a declared
  page or window in the desktop host, as `otter desktop` does; the console
  interpreter could only stop at its first `put`. Studio does not stop such a
  run after its 30-second console limit. The desktop host's startup grace now
  starts when the window opens, not before compiling (a large program's
  window used to close a few seconds after opening).
* **Live App** runs the real program (the project's entry point), not source
  regenerated from the Designer model; the Designer canvas renders the
  document itself.

**Tests:** `otter-studio/scripts/workspace-projects.test.mjs`,
`tests/ElectronExport.Tests.ps1`.

---

## What the Designer can and cannot show

The Designer shows and edits **declared** UI - the application's frame,
pages, panels, dialogs and forms. UI a program builds while running (the
cards in a project grid, the rows of a task list) exists only when the
program runs, so it appears in the Live App, not as selectable elements in
the Designer. The declared container it goes into is selectable and
styleable, and the components are ordinary Otter functions in the editor.
