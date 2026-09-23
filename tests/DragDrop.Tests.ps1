# tests/DragDrop.Tests.ps1
#
# Certification for D110 (drag and drop, web/declarative UI). Programs are
# compiled through the REAL `otter web` entry point. The generated drag/drop
# runtime is then executed in Node against a small DOM stub, and the same
# compiled page was verified by hand in a real Chromium (Playwright) with
# real DragEvents/DataTransfer/File objects - see the D110 notes.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Drag and drop (D110)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function Invoke-OtterDragProgram {
    param([string]$Source, [string]$Mode = 'web')
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_drag_$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $otFile = Join-Path $dir 'program.ot'
        [System.IO.File]::WriteAllText($otFile, $Source, [System.Text.UTF8Encoding]::new($false))
        $extra = if ($Mode -eq 'web') { '-NoOpen' } else { '' }
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:OtterPs1 $Mode $otFile $extra 2>&1
        $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
        $html = $null
        $htmlPath = Join-Path $dir 'program.html'
        if (Test-Path -LiteralPath $htmlPath) { $html = [System.IO.File]::ReadAllText($htmlPath) }
        return [pscustomobject]@{ Stdout = $text; Html = $html }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$script:FullProgram = @"
app is a page
    title is "Drag Test"
.

card is panel with draggable is true, width 100, height 60
board is panel with accepts drops is true, width 300, height 200
canvas is a panel
    accepts drops is true
.

put card, board, canvas in app

on drag of card
    set drag data to "task-42"
.

on drop on board
    say drag data
    say drop x
    say drop y
    say dragged item
.

on files dropped on canvas
    for each file in dropped files
        say name of file
    .
.

show app
"@

# --- 1. Properties become real DOM attributes (inline and block form) --------

Test-Otter 'draggable / accepts drops render as real attributes, in both the inline `with` and block forms' {
    $r = Invoke-OtterDragProgram -Source $script:FullProgram
    Assert-True ($null -ne $r.Html) "expected compiled HTML, got: $($r.Stdout)"
    Assert-True ($r.Html -match '<div id="card" draggable="true"') 'inline with: draggable attribute'
    Assert-True ($r.Html -match '<div id="board" data-otter-accepts-drops="true"') 'inline with: accepts drops attribute'
    Assert-True ($r.Html -match '<div id="canvas" data-otter-accepts-drops="true"') 'block form: accepts drops attribute'
}

Test-Otter 'draggable is false leaves the element non-draggable' {
    $r = Invoke-OtterDragProgram -Source "app is a page`n    title is `"T`"`n.`nitem is panel with draggable is false`nput item in app`nshow app"
    Assert-False ($r.Html -match 'id="item"[^>]*draggable') 'draggable must not be set when false'
}

# --- 2. Events compile to real DOM listeners ---------------------------------------

Test-Otter 'drag / drop / files dropped handlers attach the right DOM events and the compiled JS is valid' {
    $r = Invoke-OtterDragProgram -Source $script:FullProgram
    Assert-True ($r.Html -match "getElementById\('card'\)[\s\S]{0,80}addEventListener\('dragstart'") 'on drag of -> dragstart'
    Assert-True ($r.Html -match "getElementById\('board'\)[\s\S]{0,80}addEventListener\('drop'") 'on drop on -> drop'
    Assert-True ($r.Html -match "getElementById\('canvas'\)[\s\S]{0,80}addEventListener\('drop'") 'on files dropped on -> drop'
    Assert-True ($r.Html -match 'otterIsFileDrop\(event\)') 'files handler is guarded to real file drops'
    Assert-True ($r.Html -match 'otterIsItemDrop\(event\)') 'item drop handler ignores pure file drops'
    Assert-True ($r.Html -match "otterSetDragData\(event, `"task-42`"\)") 'set drag data compiles'
    $script = [regex]::Match($r.Html, '(?s)<script>(.*?)</script>').Groups[1].Value
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "otter_drag_$([Guid]::NewGuid().ToString('N')).js"
    try {
        [System.IO.File]::WriteAllText($tmp, $script)
        & node --check $tmp
        Assert-AreEqual -Expected 0 -Actual $LASTEXITCODE -Message 'compiled JS failed a Node syntax check'
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

Test-Otter 'one element can carry both a drag and a drop handler (no duplicate declarations)' {
    $r = Invoke-OtterDragProgram -Source @"
app is a page
    title is "T"
.
tile is panel with draggable is true, accepts drops is true
put tile in app
on drag of tile
    set drag data to 1
.
on drop on tile
    say drag data
.
show app
"@
    $script = [regex]::Match($r.Html, '(?s)<script>(.*?)</script>').Groups[1].Value
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "otter_drag_$([Guid]::NewGuid().ToString('N')).js"
    try {
        [System.IO.File]::WriteAllText($tmp, $script)
        & node --check $tmp
        Assert-AreEqual -Expected 0 -Actual $LASTEXITCODE -Message 'compiled JS failed a Node syntax check'
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    Assert-True ($r.Html -match 'draggable="true" data-otter-accepts-drops="true"') 'both attributes present'
}

# --- 3. The runtime, executed for real in Node against a DOM stub ---------------

Test-Otter 'the drag/drop runtime computes drop position, drag data round-trip, files and context errors' {
    $r = Invoke-OtterDragProgram -Source $script:FullProgram
    $start = $r.Html.IndexOf('const otterDragState')
    $end = $r.Html.IndexOf('function otterGetText')
    Assert-True ($start -ge 0 -and $end -gt $start) 'runtime block not found in compiled HTML'
    $runtime = $r.Html.Substring($start, $end - $start)
    $harness = @"
const listeners = {};
global.document = { addEventListener: (t, fn) => { (listeners[t] = listeners[t] || []).push(fn); } };
global.window = {};
$runtime
const store = {};
const dt = { types: [], files: [], setData(t, v) { store[t] = v; if (!this.types.includes(t)) this.types.push(t); }, getData(t) { return store[t] || ''; } };
const el = { getBoundingClientRect: () => ({ x: 100, y: 50, left: 100, top: 50 }) };
const results = {};

// context outside any event is a clear error
try { otterDragField('drop x'); results.outside = 'no error'; } catch (e) { results.outside = e.message; }

// dragstart: record the dragged element, attach data
const card = { id: 'card', closest: (s) => (s === '[draggable="true"]' ? card : null) };
listeners['dragstart'][0]({ target: card });
const startEvent = { type: 'dragstart', dataTransfer: dt, clientX: 0, clientY: 0 };
window.otterDragCtx = otterMakeDragCtx(startEvent, el, 'drag');
otterSetDragData(startEvent, { id: 42, tags: ['a'] });
results.dragItem = otterDragField('dragged item');
try { otterDragField('drop x'); results.dragDropX = 'no error'; } catch (e) { results.dragDropX = 'error'; }

// drop: data survives the round trip, position is relative to the receiver
const dropEvent = { type: 'drop', dataTransfer: dt, clientX: 140, clientY: 75 };
window.otterDragCtx = otterMakeDragCtx(dropEvent, el, 'drop');
results.data = otterDragField('drag data');
results.x = otterDragField('drop x');
results.y = otterDragField('drop y');
results.item = otterDragField('dragged item');
results.itemDrop = otterIsItemDrop(dropEvent);

// files
const fdt = { types: ['Files'], files: [{ name: 'a.txt', size: 3, type: 'text/plain', lastModified: 1 }], getData: () => '' };
const fileEvent = { type: 'drop', dataTransfer: fdt, clientX: 100, clientY: 50 };
window.otterDragCtx = otterMakeDragCtx(fileEvent, el, 'files dropped');
const files = otterDragField('dropped files');
results.fileName = files[0].props.name;
results.isThing = files[0].__otterThing;
results.fileDrop = otterIsFileDrop(fileEvent);

// set drag data outside dragstart is refused
try { otterSetDragData(dropEvent, 1); results.setOutside = 'no error'; } catch (e) { results.setOutside = e.message; }
console.log(JSON.stringify(results));
"@
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "otter_drag_$([Guid]::NewGuid().ToString('N')).js"
    try {
        [System.IO.File]::WriteAllText($tmp, $harness)
        $out = & node $tmp 2>&1
        Assert-AreEqual -Expected 0 -Actual $LASTEXITCODE -Message "node failed: $out"
        $res = ($out | Select-Object -Last 1) | ConvertFrom-Json
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    Assert-True ($res.outside -like '*only available inside*') "outside-event error: $($res.outside)"
    Assert-AreEqual -Expected 'card' -Actual $res.dragItem
    Assert-AreEqual -Expected 'error' -Actual $res.dragDropX
    Assert-AreEqual -Expected 42 -Actual $res.data.id
    Assert-AreEqual -Expected 'a' -Actual $res.data.tags[0]
    Assert-AreEqual -Expected 40 -Actual $res.x
    Assert-AreEqual -Expected 25 -Actual $res.y
    Assert-AreEqual -Expected 'card' -Actual $res.item
    Assert-AreEqual -Expected 'True' -Actual $res.itemDrop
    Assert-AreEqual -Expected 'a.txt' -Actual $res.fileName
    Assert-AreEqual -Expected 'True' -Actual $res.isThing
    Assert-AreEqual -Expected 'True' -Actual $res.fileDrop
    Assert-True ($res.setOutside -like '*only works inside*') "set-outside error: $($res.setOutside)"
}

# --- 4. The runtime is only emitted for programs that use drag/drop ---------------------

Test-Otter 'programs without drag/drop do not carry the drag/drop runtime' {
    $r = Invoke-OtterDragProgram -Source "app is a page`n    title is `"T`"`n.`nt is a text`n    text is `"hi`"`n.`nput t in app`nshow app"
    Assert-False ($r.Html -match 'otterDragState') 'no drag runtime expected'
}

# --- 5. Grammar guards and existing grammar untouched -------------------------------------------

Test-Otter 'a variable named panel, drop, drag, accepts still works as an ordinary name' {
    $r = Invoke-OtterDragProgram -Mode 'run' -Source "panel is 5`ndrop is 6`ndrag is 7`naccepts is 8`nsay panel drop drag accepts"
    Assert-True ($r.Stdout -match '5 6 7 8') "expected ordinary variables to keep working, got: $($r.Stdout)"
}

Test-Otter 'drag/drop is refused on WPF windows with a clear message' {
    $r = Invoke-OtterDragProgram -Mode 'run' -Source "create window into app`ncreate button into b`non drag of b`n    say `"x`"`n."
    Assert-True ($r.Stdout -match 'not supported for windows yet') "expected the window diagnostic, got: $($r.Stdout)"
    $r2 = Invoke-OtterDragProgram -Mode 'run' -Source 'say drop x'
    Assert-True ($r2.Stdout -match 'only available in web applications') "expected the context diagnostic, got: $($r2.Stdout)"
}

Complete-OtterTests
