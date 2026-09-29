using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1

# WebRuntimeUi.Tests.ps1
#
# UI created while a web page runs (D128): `create`, `has`, property
# assignment, `put`, `show` and `when` inside event handlers,
# functions and loops. Before D128 the web compiler dropped all of these
# without a word, so examples/v1/tasks.ot's Add button did nothing.
#
# Two layers:
#   1. Compile checks (every host): the page contains the runtime code, and a
#      page without runtime UI is unchanged.
#   2. Behavior in a real browser (headless Chromium through playwright-core),
#      when playwright-core can be found: $env:OTTER_PLAYWRIGHT_CORE (the
#      package folder), or node_modules/playwright-core in the repository or
#      in otter-studio. Otherwise these are reported as skipped.

. "$PSScriptRoot\TestHelpers.ps1"
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Web.psm1') -Force

Write-Host ''
Write-Host 'Web runtime UI (D128)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_webui_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null

function Build-OtterWebPage {
    param([string]$Name, [string]$Source)
    $ot = Join-Path $script:Tmp "$Name.ot"
    [System.IO.File]::WriteAllText($ot, $Source, [System.Text.UTF8Encoding]::new($false))
    return (Export-OtterWebApplication -SourcePath $ot -OutputPath (Join-Path $script:Tmp "$Name.html") -PassThruExceptions)
}

$boardSource = @'
create page into app
app has title "Board"

create column into cards
cards has spacing 6
put cards in app

create text box into titleInput
put titleInput in app

create button into addButton
addButton has text "Add card"
put addButton in app

create text into status
status has text "ready"
put status in app

to addCard label
    create card into box
    box has background "#eef"
    box has padding 10
    create row into line
    line has spacing 4
    create text into caption
    caption has text label
    create button into closer
    closer has text "x"
    put caption in line
    put closer in line
    put line in box
    put box in cards
    when closer clicked
        doneName is text of caption
        message is "done " and doneName
        status has text message
        caption has text "done"
    .
.

seeds are
    "alpha"
    "beta"
.
for each seed in seeds
    addCard seed
.

when addButton clicked
    addCard text of titleInput
    newTitle is text of titleInput
    message is "added " and newTitle
    status has text message
.

show app
'@

$putErrorSource = @'
create page into app
create column into holder
put holder in app
create button into goButton
goButton has text "Go"
put goButton in app
when goButton clicked
    n is 5
    put n in holder
.
show app
'@

try {
    $tasksHtml = Export-OtterWebApplication -SourcePath (Join-Path $script:RepoRoot 'examples\v1\tasks.ot') -OutputPath (Join-Path $script:Tmp 'tasks.html') -PassThruExceptions
    $boardHtml = Build-OtterWebPage -Name 'board' -Source $boardSource
    $putErrorHtml = Build-OtterWebPage -Name 'puterror' -Source $putErrorSource

    Test-Otter 'D128 compile: a handler that creates UI compiles to runtime creation, not a dropped statement' {
        $html = [System.IO.File]::ReadAllText($tasksHtml)
        Assert-True ($html.Contains("otterCreateUi('text', '')")) 'expected create text into item to compile to otterCreateUi'
        Assert-True ($html.Contains('otterPutIn(')) 'expected put item in taskList to compile to otterPutIn'
        Assert-True ($html.Contains('const otterUiTemplates = ')) 'expected the runtime templates'
    }

    Test-Otter 'D128 compile: a page with no runtime UI carries no runtime UI code' {
        $plain = Build-OtterWebPage -Name 'plain' -Source "create page into app`ncreate text into hello`nhello has text `"hi`"`nput hello in app`nshow app`n"
        $html = [System.IO.File]::ReadAllText($plain)
        Assert-False ($html.Contains('otterUiTemplates')) 'a page without runtime UI must not include the runtime UI code'
    }

    # D56 amendment (proposed for Otter 1.1): hide, focus and clear are UI
    # actions on the web as on the console. Behavior is covered in a real
    # browser by tests/RuntimeUi.Tests.ps1.
    Test-Otter 'D56 amendment on the web: hide, focus and clear compile to runtime UI actions' {
        foreach ($word in @('hide', 'focus', 'clear')) {
            $page = Build-OtterWebPage -Name "d56$word" -Source "create page into app`ncreate button into b`nput b in app`nwhen b clicked`n    $word b`n.`nshow app`n"
            $html = [System.IO.File]::ReadAllText($page)
            Assert-True ($html.Contains("'$word');")) "expected $word b to compile to otterUiAction(..., '$word')"
        }
    }

    Test-Otter 'the web compiler refuses a statement it cannot compile instead of dropping it' {
        $err = $null
        try { Build-OtterWebPage -Name 'jobs' -Source "start command `"echo hi`" and call it job`n" | Out-Null } catch { $err = $_.Exception.Message }
        Assert-True ($err -match 'not supported on the web target') "expected a web-target refusal, got: $err"
    }

    # --- real browser --------------------------------------------------------
    $pwCore = $null
    foreach ($candidate in @($env:OTTER_PLAYWRIGHT_CORE, (Join-Path $script:RepoRoot 'node_modules\playwright-core'), (Join-Path $script:RepoRoot 'otter-studio\node_modules\playwright-core'))) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'package.json'))) { $pwCore = $candidate; break }
    }
    $node = Get-Command node -ErrorAction SilentlyContinue
    $driver = Join-Path $PSScriptRoot 'web-runtime-ui-driver.mjs'

    function Invoke-OtterWebScenario {
        param([string]$Html, [string]$Scenario)
        $out = & node $driver $pwCore $Html $Scenario 2>&1
        if ($LASTEXITCODE -ne 0) { throw "the browser driver failed: $($out -join ' ')" }
        return (($out | Select-Object -Last 1) | ConvertFrom-Json)
    }

    if (-not $pwCore -or -not $node) {
        Write-Output "  skip  D128 browser behavior: playwright-core not found (set OTTER_PLAYWRIGHT_CORE to its folder) or node missing"
    } else {
        Test-Otter 'D128 browser: examples/v1/tasks.ot - each Add creates a new line with the typed text; an empty input adds nothing' {
            $r = Invoke-OtterWebScenario -Html $tasksHtml -Scenario 'tasks'
            Assert-Lines -Expected @('Buy milk', 'Walk the otter') -Actual @($r.items)
            Assert-AreEqual -Expected '' -Actual $r.inputAfter
            Assert-AreEqual -Expected 0 -Actual @($r.pageErrors).Count
        }

        Test-Otter 'D128 browser: a function builds cards (locals), each card button acts on its own card, has works on top-level elements' {
            $r = Invoke-OtterWebScenario -Html $boardHtml -Scenario 'board'
            Assert-Lines -Expected @('alphax', 'betax') -Actual @($r.atLoad)
            Assert-Lines -Expected @('alphax', 'donex', 'gammax') -Actual @($r.after)
            Assert-AreEqual -Expected 'added gamma' -Actual $r.statusAfterAdd
            Assert-AreEqual -Expected 'done beta' -Actual $r.statusAfterRemove
            Assert-AreEqual -Expected 'rgb(238, 238, 255)' -Actual $r.cardBackground
            Assert-AreEqual -Expected '10px' -Actual $r.cardPadding
            Assert-AreEqual -Expected '4px' -Actual $r.rowGap
            Assert-AreEqual -Expected 0 -Actual @($r.pageErrors).Count
        }

        Test-Otter 'D128 browser: putting a non-UI value somewhere is the interpreter''s error, not silence' {
            $r = Invoke-OtterWebScenario -Html $putErrorHtml -Scenario 'putError'
            Assert-True (@($r.errors) -contains 'I can only put a UI resource somewhere, but this is a number.') "got: $(@($r.errors) -join ' | ')"
        }
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
