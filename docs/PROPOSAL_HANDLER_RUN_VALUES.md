# Proposal: a handler set up while another handler runs remembers that run

Status: **proposed, not decided.** Found 2026-10-13 while planning the task
tracker tutorial. Needs Jeff's decision (it extends D130) and a Windows run,
because the console half lives in the WPF host.

## The problem

```otter
when addButton is clicked
    create row into line
    create button into deleteButton
    text of deleteButton is "Delete"
    put deleteButton in line
    put line in taskList
    when deleteButton is clicked
        customstyle of line is "display: none;"
    .
.
```

Add three rows (alpha, beta, gamma) and click alpha's Delete: **gamma** is
hidden. On the web, names a top-level handler sets compile to `window.line`,
one shared global, so every row's Delete handler reads the last row.
Reproduced in Edge on macOS with rc.12 plus `feature/p8-browser-storage`.

The console very likely does the same (the handler body runs in the global
scope), so today the two targets agree. Both give a silent wrong answer, the
same kind D130 fixed for loops.

## What already works

Building the row in a function: its names are real locals, and each Delete
handler keeps its own row. `tests/WebRuntimeUi.Tests.ps1` covers this ("a
function builds cards (locals), each card button acts on its own card").
The tutorial teaches this form.

## Proposed rule (extends D130)

Treat each run of a `when` handler like a loop pass: the names the handler's
body sets, and that are set nowhere else in the same scope, belong to that
run. A handler set up during the run keeps them. Every other name is shared
and read live, as in D130.

## Implementation sketch

- `Otter.LoopPasses.psm1`: also return run names for `When` statements (a
  separate map, so `Test-OtterLoopStatement` and the loop paths don't change).
- `Otter.Compiler.JavaScript.psm1`: while a handler body compiles, push its
  run names on `OtterJsLoopPassStack`. The nested-`when` capture already turns
  that stack into closure parameters.
- `Otter.Interpreter.psm1`: give each handler run the same per-run values the
  loop-pass path gives each pass.
- Tests: the reproduction above, on the web (headless Chromium) and the
  console (`tests/UI.Tests.ps1`, real WPF clicks, Windows).
