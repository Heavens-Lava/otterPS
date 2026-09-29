# tests/RuntimeUi.Tests.ps1
#
# Runtime UI on the web/desktop target: UI declared while the program runs
# (inside functions, handlers and loops), elements as values (components),
# put / remove / clear / show / hide / focus, `when` registered at run time,
# the shared property mapping, the new common properties (class, hidden,
# enabled, tooltip, label, shortcut), the `submitted` event, and awaiting
# calls to async user functions.
#
# Every program is compiled through the REAL `otter web` entry point and then
# run in a real browser (headless Microsoft Edge, `--dump-dom`). A small
# driver script appended to the page plays the user (clicks, key presses) and
# writes what it saw into #otter-test-result as JSON.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Runtime UI (web target)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:Edge = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

function Invoke-OtterUiProgram {
    param([Parameter(Mandatory)][string]$Source, [string]$Driver = '')
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_rtui_$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $otFile = Join-Path $dir 'program.ot'
        [System.IO.File]::WriteAllText($otFile, $Source, [System.Text.UTF8Encoding]::new($false))
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:OtterPs1 web $otFile -NoOpen 2>&1
        $compileText = ($output | ForEach-Object { [string]$_ }) -join "`n"
        $htmlPath = Join-Path $dir 'program.html'
        if (-not (Test-Path -LiteralPath $htmlPath)) {
            return [pscustomobject]@{ Compiled = $false; Stdout = $compileText; Html = $null; Dom = ''; Result = $null; Console = '' }
        }
        $html = [System.IO.File]::ReadAllText($htmlPath)
        $driverJs = @"
<script>
window.addEventListener('load', () => setTimeout(async () => {
  const result = {};
  const q = (s) => document.querySelector(s);
  const qa = (s) => Array.from(document.querySelectorAll(s));
  const key = (el, k, opts) => el.dispatchEvent(new KeyboardEvent('keydown', Object.assign({ key: k, bubbles: true, cancelable: true }, opts || {})));
  try {
$Driver
  } catch (err) { result.driverError = String(err && err.message || err); }
  await new Promise(r => setTimeout(r, 50));
  const pre = document.createElement('pre');
  pre.id = 'otter-test-result';
  pre.textContent = JSON.stringify(result);
  document.body.appendChild(pre);
}, 150));
</script>
"@
        $at = $html.LastIndexOf('</body>')
        $html = $html.Insert($at, $driverJs)
        [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($false))
        $profile = Join-Path $dir 'edge-profile'
        $uri = ([System.Uri]$htmlPath).AbsoluteUri
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $script:Edge
        $psi.Arguments = "--headless=new --disable-gpu --no-first-run --no-default-browser-check --user-data-dir=`"$profile`" --enable-logging=stderr --v=0 --virtual-time-budget=4000 --dump-dom `"$uri`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $errTask = $proc.StandardError.ReadToEndAsync()
        $dom = $proc.StandardOutput.ReadToEnd()
        [void]$proc.WaitForExit(60000)
        $consoleLines = @(($errTask.Result -split "`n") | Where-Object { $_ -match 'CONSOLE' }) -join "`n"
        $result = $null
        $m = [regex]::Match($dom, '<pre id="otter-test-result">(.*?)</pre>', 'Singleline')
        if ($m.Success) { $result = [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value) | ConvertFrom-Json }
        return [pscustomobject]@{ Compiled = $true; Stdout = $compileText; Html = $html; Dom = $dom; Result = $result; Console = $consoleLines }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Assert-UiRan {
    param($Run)
    Assert-True $Run.Compiled "the program did not compile: $($Run.Stdout)"
    Assert-True ($null -ne $Run.Result) "the page produced no result (console: $($Run.Console))"
    Assert-True (-not $Run.Result.driverError) "driver error: $($Run.Result.driverError) (console: $($Run.Console))"
}

if (-not $script:Edge) {
    Test-Otter 'Microsoft Edge is available to run compiled pages' {
        Assert-True $false 'Microsoft Edge (msedge.exe) was not found; these tests run compiled pages in a real browser.'
    }
    Complete-OtterTests
    return
}

# --- 1. Components: a function builds an element and returns it ------------------

Test-Otter 'a function builds UI and returns it; each call keeps its own values for its handlers' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
grid is a column with spacing 8
status is a text with value "none"
put grid, status in app

to makeCard title and amount
    card is a card with padding 12, class "stat-card"
    label is a text with value title
    count is a badge with text amount
    put label, count in card
    when card is clicked
        text of status is "clicked " plus title
        background of card is "rgb(1, 2, 3)"
    .
    return card
.

names are
    "Alpha"
    "Beta"
    "Gamma"
.
for each name in names
    makeCard name and 7 make built
    put built in grid
.
show app
'@ -Driver @'
  result.before = qa('.stat-card').length;
  qa('.stat-card')[1].click();
  await new Promise(r => setTimeout(r, 20));
  result.status = q('#status').textContent;
  result.bg = qa('.stat-card').map(c => c.style.background);
  result.labels = qa('.stat-card .otter-text').map(t => t.textContent);
  result.badges = qa('.stat-card .otter-badge').map(t => t.textContent);
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 3 -Actual $run.Result.before -Message 'three cards were put in the grid'
    Assert-AreEqual -Expected 'clicked Beta' -Actual $run.Result.status
    Assert-AreEqual -Expected 'Alpha,Beta,Gamma' -Actual ($run.Result.labels -join ',')
    Assert-AreEqual -Expected '7,7,7' -Actual ($run.Result.badges -join ',')
    Assert-AreEqual -Expected ',rgb(1, 2, 3),' -Actual ($run.Result.bg -join ',') -Message 'only the clicked card changed'
}

Test-Otter 'a handler registered inside a loop keeps its own iteration''s item, and text of a number joins with plus' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
bar is a row
out is a text with value ""
put bar, out in app
to buildButtons
    names are
        "one"
        "two"
        "three"
    .
    for each name in names
        b is a button with text name, class "each"
        put b in bar
        when b is clicked
            text of out is "each " plus name
        .
    .
    count from 1 to 3 as n
        c is a button with text "n", class "count"
        put c in bar
        when c is clicked
            text of out is "count " plus text of n
        .
    .
    total is 0
    each name in names
        label is "made " plus name
        add 1 to total
        m is a button with text label, class "made"
        put m in bar
        when m is clicked
            text of out is label plus " of " plus text of total
        .
    .
    last is label
    text of summary is text of total plus " " plus last
.
summary is a text with value ""
put summary in app
buildButtons
'@ -Driver @'
  qa('.made')[0].click();
  await new Promise(r => setTimeout(r, 20));
  result.made = q('#out').textContent;
  result.summary = q('#summary').textContent;
  qa('.each')[1].click();
  await new Promise(r => setTimeout(r, 20));
  result.each = q('#out').textContent;
  qa('.count')[0].click();
  await new Promise(r => setTimeout(r, 20));
  result.count = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'each two' -Actual $run.Result.each
    Assert-AreEqual -Expected 'count 1' -Actual $run.Result.count
    # A variable assigned in the loop body is the iteration's own for its
    # handler, while counting and "the last value" still work after the loop.
    Assert-AreEqual -Expected 'made one of 1' -Actual $run.Result.made
    Assert-AreEqual -Expected '3 made three' -Actual $run.Result.summary
}

# --- 2. The shared property mapping, on runtime and static elements ---------------

Test-Otter 'runtime property writes use the same mapping as declarations, for built and static elements' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
box is a column with class "start"
put box in app
to build
    tile is a row with spacing 4
    padding of tile is 14
    radius of tile is 6
    width of tile is "50%"
    class of tile is "tile wide"
    put tile in box
    return tile
.
build make made
padding of box is 20
class of box is "boxed"
border of box is "1px solid rgb(9, 9, 9)"
align of box is "center"
'@ -Driver @'
  const tile = q('.tile');
  result.tile = [tile.style.padding, tile.style.borderRadius, tile.style.width, tile.style.gap, tile.className];
  const box = q('#box');
  result.box = [box.style.padding, box.className, box.style.border, box.style.alignItems];
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected '14px|6px|50%|4px|otter-row tile wide' -Actual ($run.Result.tile -join '|')
    Assert-AreEqual -Expected '20px|otter-column boxed|1px solid rgb(9, 9, 9)|center' -Actual ($run.Result.box -join '|')
}

Test-Otter 'reading properties of a built element returns what the program set' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
out is a text with value ""
put out in app
to check
    field is a text box with placeholder "Name", class "field"
    text of field is "Jeff"
    put field in app
    text of out is text of field plus "/" plus placeholder of field plus "/" plus class of field
.
check
'@ -Driver @'
  result.out = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'Jeff/Name/field' -Actual $run.Result.out
}

# --- 3. Visibility, enabled state, tooltip, label -----------------------------------

Test-Otter 'hidden / show / hide, enabled false, tooltip and label render and change at run time' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
panel is a card with hidden true, class "panel"
saveButton is a button with text "Save", enabled false, tooltip "Save the file"
iconButton is a button with text "", tooltip "Settings"
search is a text box with label "Search everything"
openButton is a button with text "Open"
put panel, saveButton, iconButton, search, openButton in app
when openButton is clicked
    show panel
    enabled of saveButton is true
    hide openButton
.
'@ -Driver @'
  result.before = [q('#panel').classList.contains('otter-hidden'), q('#saveButton').disabled, q('#saveButton').title, q('#iconButton').getAttribute('aria-label'), q('#search').getAttribute('aria-label')];
  q('#openButton').click();
  await new Promise(r => setTimeout(r, 20));
  result.after = [q('#panel').classList.contains('otter-hidden'), q('#saveButton').disabled, q('#openButton').classList.contains('otter-hidden'), getComputedStyle(q('#panel')).display];
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'True|True|Save the file|Settings|Search everything' -Actual ($run.Result.before -join '|')
    Assert-AreEqual -Expected 'False|False|True|flex' -Actual ($run.Result.after -join '|')
}

# --- 4. clear and remove -------------------------------------------------------

Test-Otter 'a rendered resource passed to a function is that resource: the function can clear it, fill it and style it' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
left is a column
right is a column
put left, right in app
to fill container with label
    clear container
    line is a text with value label, class "line"
    put line in container
    padding of container is 7
.
fill left with "a"
fill left with "b"
fill right with "c"
'@ -Driver @'
  result.left = Array.from(q('#left').querySelectorAll('.line')).map(e => e.textContent).join(',');
  result.right = Array.from(q('#right').querySelectorAll('.line')).map(e => e.textContent).join(',');
  result.padding = q('#left').style.padding;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'b' -Actual $run.Result.left
    Assert-AreEqual -Expected 'c' -Actual $run.Result.right
    Assert-AreEqual -Expected '7px' -Actual $run.Result.padding
}

Test-Otter 'an element that accepts drops carries otter-drop-over while something is dragged over it' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
target is a column with accepts drops true
other is a column
label is a text with value "inside"
put label in target
put target, other in app
on drop on target
    say "dropped"
.
'@ -Driver @'
  const fire = (el, type, related) => el.dispatchEvent(new DragEvent(type, { bubbles: true, cancelable: true, relatedTarget: related || null }));
  fire(q('#label'), 'dragover');
  result.over = q('#target').classList.contains('otter-drop-over');
  fire(q('#target'), 'dragleave', q('#label'));
  result.stillOverInside = q('#target').classList.contains('otter-drop-over');
  fire(q('#other'), 'dragover');
  result.afterMove = q('#target').classList.contains('otter-drop-over');
  fire(q('#target'), 'dragover');
  fire(q('#target'), 'drop');
  result.afterDrop = q('#target').classList.contains('otter-drop-over');
'@
    Assert-UiRan $run
    Assert-True $run.Result.over 'dragging over a child of the target marks the target'
    Assert-True $run.Result.stillOverInside 'moving onto a child of the target keeps the mark'
    Assert-False $run.Result.afterMove 'dragging over something else takes the mark away'
    Assert-False $run.Result.afterDrop 'a drop takes the mark away'
}

Test-Otter 'clear empties a container; remove takes one element out' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
list is a column
put list in app
to addItem label
    item is a text with value label, class "item"
    put item in list
    return item
.
addItem "one" make first
addItem "two" make second
addItem "three" make third
remove second from list
'@ -Driver @'
  result.afterRemove = qa('.item').map(i => i.textContent).join(',');
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'one,three' -Actual $run.Result.afterRemove

    $run2 = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
list is a column
put list in app
count from 1 to 4 as n
    row is a text with value n, class "item"
    put row in list
.
clear list
names are
    "a"
    "b"
.
clear names
status is a text with value "full"
put status in app
remaining is 0
each name in names
    add 1 to remaining
.
text of status is text of remaining
'@ -Driver @'
  result.left = qa('.item').length;
  result.status = q('#status').textContent;
'@
    Assert-UiRan $run2
    Assert-AreEqual -Expected 0 -Actual $run2.Result.left
    Assert-AreEqual -Expected '0' -Actual $run2.Result.status
}

Test-Otter '`clear` is only a statement for `clear <name>`; clear stays usable as a variable' {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_rtui_$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $f = Join-Path $dir 'p.ot'
        [System.IO.File]::WriteAllText($f, "clear is 5`nsky is clear plus 1`nsay clear sky", [System.Text.UTF8Encoding]::new($false))
        $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $script:OtterPs1 run $f 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
        Assert-True ($out -match '5 6') "expected 5 6, got: $out"
        [System.IO.File]::WriteAllText($f, "create window into app`ncreate column into list`nclear list", [System.Text.UTF8Encoding]::new($false))
        $out2 = (& powershell -NoProfile -ExecutionPolicy Bypass -File $script:OtterPs1 run $f 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
        Assert-True ($out2 -notmatch 'not supported') "the console clears a column too (D56 amendment), got: $out2"
    } finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- 5. Mistakes fail loudly ------------------------------------------------------------

Test-Otter 'putting something that is not UI, putting twice, and removing a non-child are Otter errors' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
list is a column
other is a column
out is a text with value ""
put list, other, out in app
to tryThings
    try
        put "hello" in list
    otherwise into reason
        text of out is reason
    .
    tile is a card
    put tile in list
    try
        put tile in other
    otherwise into reason
        text of out is text of out plus " | " plus reason
    .
    stray is a card
    try
        remove stray from list
    otherwise into reason
        text of out is text of out plus " | " plus reason
    .
.
tryThings
'@ -Driver @'
  result.out = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-True ($run.Result.out -match 'I can only put a UI resource somewhere, but this is some text\.') "put text: $($run.Result.out)"
    Assert-True ($run.Result.out -match 'can only be in one place at a time') "put twice: $($run.Result.out)"
    Assert-True ($run.Result.out -match 'is not in this column') "remove non-child: $($run.Result.out)"
}

# --- 6. `when` on elements built at top level -------------------------------------------

Test-Otter 'a top-level when on an element built at run time is registered in program order' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
out is a text with value "none"
put out in app
extra is a button with text "Late", class "late"
put extra in app
when extra is clicked
    text of out is "late clicked"
.
'@ -Driver @'
  q('.late').click();
  await new Promise(r => setTimeout(r, 20));
  result.out = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'late clicked' -Actual $run.Result.out
}

# --- 7. Keyboard: shortcut and submitted ---------------------------------------------------

Test-Otter 'shortcut "Ctrl+K" focuses a text box; "Escape" clicks the last visible button that owns it' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
search is a text box with shortcut "Ctrl+K"
out is a text with value "open"
pageClose is a button with text "Close page", shortcut "Escape"
dialog is a card with hidden true
dialogClose is a button with text "Close dialog", shortcut "esc"
put dialogClose in dialog
put search, out, pageClose, dialog in app
when pageClose is clicked
    text of out is "page closed"
.
when dialogClose is clicked
    text of out is "dialog closed"
    hide dialog
.
'@ -Driver @'
  result.attr = q('#search').dataset.otterShortcut + '/' + q('#dialogClose').dataset.otterShortcut;
  key(document.body, 'k', { ctrlKey: true });
  result.focused = document.activeElement && document.activeElement.id;
  key(document.body, 'Escape');
  await new Promise(r => setTimeout(r, 20));
  result.first = q('#out').textContent;
  document.getElementById('dialog').classList.remove('otter-hidden');
  key(document.body, 'Escape');
  await new Promise(r => setTimeout(r, 20));
  result.second = q('#out').textContent;
  result.dialogHidden = q('#dialog').classList.contains('otter-hidden');
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'Ctrl+k/escape' -Actual $run.Result.attr
    Assert-AreEqual -Expected 'search' -Actual $run.Result.focused
    Assert-AreEqual -Expected 'page closed' -Actual $run.Result.first -Message 'with the dialog hidden, Escape reaches the page button'
    Assert-AreEqual -Expected 'dialog closed' -Actual $run.Result.second -Message 'the visible dialog, later in the page, takes Escape'
    Assert-True $run.Result.dialogHidden
}

Test-Otter 'when <text box> is submitted runs on Enter, for static and built text boxes' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
entry is a text box
out is a text with value ""
put entry, out in app
when entry is submitted
    text of out is "static:" plus text of entry
.
to buildField
    field is a text box with class "built"
    put field in app
    when field is submitted
        text of out is "built:" plus text of field
    .
.
buildField
'@ -Driver @'
  q('#entry').value = 'one';
  key(q('#entry'), 'a');
  result.notYet = q('#out').textContent;
  key(q('#entry'), 'Enter');
  await new Promise(r => setTimeout(r, 20));
  result.first = q('#out').textContent;
  q('.built').value = 'two';
  key(q('.built'), 'Enter');
  await new Promise(r => setTimeout(r, 20));
  result.second = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected '' -Actual $run.Result.notYet
    Assert-AreEqual -Expected 'static:one' -Actual $run.Result.first
    Assert-AreEqual -Expected 'built:two' -Actual $run.Result.second
}

# --- 8. Calls to async functions are awaited --------------------------------------------

Test-Otter 'a call to a function that does file I/O is awaited, including through another function' {
    # `file ... exists` is awaited inside loadName, so loadName is async; if
    # its callers did not await it, `name` would be a pending promise.
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
out is a text with value ""
put out in app
to loadName
    if file "never-there.txt" exists
        return "found"
    .
    return "missing"
.
to describe
    loadName make name
    return "name is " plus name
.
describe make message
text of out is message
'@ -Driver @'
  result.out = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'name is missing' -Actual $run.Result.out -Message 'without awaiting, the text would be [object Promise]'
    Assert-True ($run.Html -match 'const describe = async function') 'describe calls an async function, so it is async itself'
}

Test-Otter 'a date moves by a computed amount on the web target, and weekday matches the interpreter' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
out is a text with value ""
put out in app
begin is date from "2026-09-28"
offset is 7
add offset days to begin
format begin as "yyyy-MM-dd" into moved
back is 2
remove back days from begin
format begin as "yyyy-MM-dd" into movedBack
text of out is moved plus " " plus movedBack plus " " plus text of weekday of begin
'@ -Driver @'
  result.out = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected '2026-10-05 2026-10-03 6' -Actual $run.Result.out
}

Test-Otter 'find without into, its, return-in-where and call ... into work on the web target' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
out is a text with value ""
put out in app
a Task has
    id
    title
    done
.
tasks are empty
first is a Task with id 1, title "First", done false
second is a Task with id 2, title "Second", done true
add first to tasks
add second to tasks
to findTask wanted
    find task in tasks where its id is wanted
    return task
.
to titleOf wanted
    return task in tasks where its id is wanted
.
findTask 2 into found
titleOf 1 into other
findTask 9 into missing
words is title of found plus "/" plus title of other
if missing is gone
    words is words plus "/gone"
.
each task in tasks
    if its done
        its title is "Finished"
    .
.
words is words plus "/" plus title of second
text of out is words
'@ -Driver @'
  result.out = q('#out').textContent;
  result.leak = typeof window.task;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'Second/First/gone/Finished' -Actual $run.Result.out
}

Test-Otter 'replace inside a function changes the function''s own variable' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
out is a text with value ""
put out in app
to slug words
    key is lowercase of words
    replace " " with "-" in key
    return key
.
slug "In Progress" into made
text of out is made
'@ -Driver @'
  result.out = q('#out').textContent;
  result.leaked = typeof window.key;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'in-progress' -Actual $run.Result.out
    Assert-AreEqual -Expected 'undefined' -Actual $run.Result.leaked -Message 'no global of the same name appears'
}

# --- 8b. Files in a browser tab live in the browser's storage ----------------------------

Test-Otter 'in a browser tab, write / read / append / exists / delete file work against browser storage' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
out is a text with value ""
put out in app
to exercise
    log is ""
    if file "notes.txt" exists
        log is log plus "exists-before "
    .
    write "hello" to "notes.txt"
    append " world" to "notes.txt"
    read "notes.txt" into content
    log is log plus content
    if file "notes.txt" exists
        log is log plus " exists-after"
    .
    delete file "notes.txt"
    if file "notes.txt" exists
        log is log plus " still-there"
    .
    try
        read "notes.txt" into leftover
    otherwise into reason
        log is log plus " | " plus reason
    .
    text of out is log
.
exercise
'@ -Driver @'
  result.out = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'hello world exists-after | File not found: notes.txt' -Actual $run.Result.out
}

# --- 9. Existing behavior kept ------------------------------------------------------------

Test-Otter 'a thing built inside a function is still a thing, and its property reaches a static text' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
out is a text with value ""
put out in app
to makePerson
    person is a thing
        name is "Jeff"
    .
    return person
.
makePerson make p
text of out is name of p
'@ -Driver @'
  result.out = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'Jeff' -Actual $run.Result.out
}

# --- 10. Icons -----------------------------------------------------------------------------

Test-Otter 'icons come from the page icon sprite, statically and at run time, and `an` is an article' {
    $spriteDir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_icons_$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path (Join-Path $spriteDir 'icons') -Force | Out-Null
    $sprite = Join-Path $spriteDir 'icons\set.svg'
    [System.IO.File]::WriteAllText($sprite, '<svg xmlns="http://www.w3.org/2000/svg"><symbol id="home" viewBox="0 0 24 24"><path d="M3 11l9-7 9 7"/></symbol><symbol id="gear" viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/></symbol></svg>')
    try {
        # The sprite path is relative to the program, so the program is
        # written next to it rather than through Invoke-OtterUiProgram.
        $otFile = Join-Path $spriteDir 'program.ot'
        [System.IO.File]::WriteAllText($otFile, @'
app is a page with title "T", hideheader true, icons "icons/set.svg"
home is an icon with name "home", size 18
bar is a row
put home, bar in app
to addIcon iconName
    made is an icon with name iconName, size 24, class "made", label "Open " plus iconName
    put made in bar
.
addIcon "gear"
name of home is "gear"
'@, [System.Text.UTF8Encoding]::new($false))
        $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $script:OtterPs1 web $otFile -NoOpen 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
        $html = [System.IO.File]::ReadAllText((Join-Path $spriteDir 'program.html'))
        Assert-True ($html -match '<svg xmlns="http://www.w3.org/2000/svg" id="otter-icons" style="display: none;"[^>]*>\s*<symbol id="home"') "sprite embedded once: $out"
        # `name of home is "gear"` at top level with a literal is folded into
        # the declaration at compile time (the existing rule for every
        # static property), so the rendered icon is already the gear.
        Assert-True ($html -match '<svg id="home" class="otter-icon" aria-hidden="true" style="[^"]*width: 18px; height: 18px;"><use href="#gear"></use></svg>') 'static icon markup'
        Assert-True ($html -match "otterCreateUi\('icon'") 'runtime icon creation compiled'
    } finally { Remove-Item -LiteralPath $spriteDir -Recurse -Force -ErrorAction SilentlyContinue }

    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
an Item has
    name
.
first is an Item
name of first is "x"
out is a text with value name of first
put out in app
'@ -Driver @'
  result.out = q('#out').textContent;
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'x' -Actual $run.Result.out
}

Test-Otter 'two functions with the same name are a compile error that names both' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T"
to countThings
    return 1
.
to countThings kind
    return 2
.
'@
    Assert-False $run.Compiled 'expected no page'
    Assert-True ($run.Stdout -match 'There are two functions called "countThings"') "diagnostic: $($run.Stdout)"
}

Test-Otter 'a declaration with a computed value sets it when the program starts' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
names are
    "one"
    "two"
.
greeting is "Hello"
out is a text with value greeting plus " there"
pick is a dropdown with options names
put out, pick in app
'@ -Driver @'
  result.out = q('#out').textContent;
  result.options = Array.from(q('#pick').options).map(o => o.value).join(',');
'@
    Assert-UiRan $run
    Assert-AreEqual -Expected 'Hello there' -Actual $run.Result.out
    Assert-AreEqual -Expected 'one,two' -Actual $run.Result.options
}

Test-Otter 'a missing icon file is a compile error, not a broken page' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", icons "nowhere/set.svg"
'@
    Assert-False $run.Compiled 'expected no page'
    Assert-True ($run.Stdout -match 'I cannot find the icon file "nowhere/set.svg"') "diagnostic: $($run.Stdout)"
}

Test-Otter 'the compiled page is valid JavaScript and declarations render class/hidden/shortcut attributes' {
    $run = Invoke-OtterUiProgram -Source @'
app is a page with title "T", hideheader true
nav is a button with text "Home", style "nav-item active", shortcut "ctrl + 1"
old is a button with text "Old", class "legacy"
box is a checkbox with text "Done", hidden true, enabled false
put nav, old, box in app
to restyle
    style of nav is "nav-item"
.
restyle
'@ -Driver @'
  result.nav = q('#nav').className;
'@
    Assert-UiRan $run
    Assert-True ($run.Html -match '<button id="nav" class="otter-button nav-item active"[^>]*data-otter-shortcut="Ctrl\+1"') 'style renders as named styles'
    Assert-True ($run.Html -match '<button id="old" class="otter-button legacy"') 'class is still accepted as the older spelling'
    Assert-AreEqual -Expected 'otter-button nav-item' -Actual $run.Result.nav -Message 'style of x is ... replaces the named styles at run time'
    Assert-True ($run.Html -match '<label class="otter-checkbox-label otter-hidden otter-disabled"[^>]*aria-disabled="true"><input type="checkbox" id="box" disabled') 'checkbox wrapper classes and disabled input'
}

Complete-OtterTests
