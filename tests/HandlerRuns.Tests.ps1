# HandlerRuns.Tests.ps1
#
# Otter 1.0: a handler set up while another handler runs does not remember
# that run, so an inner handler that uses a name the outer handler makes on
# each run would act on the last run's value - a Delete button removing the
# newest row instead of its own (found by the task-tracker tutorial,
# docs/PROPOSAL_HANDLER_RUN_VALUES.md on feature/p8-browser-storage). Until
# 1.1 gives each run its own names, the check stage refuses that form with
# the form that works. These tests go through otter.ps1 (check and web).
#
# This file must stay portable: no powershell.exe, cmd or $env:TEMP.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Handler runs (inner handlers and the outer run''s names)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:HostExe = (Get-Process -Id $PID).Path
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_handlers_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null

$script:Head = "app is a page with title `"Rows`"`naddButton is a primary button with text `"Add`"`ntaskList is a column with spacing 8`n"

function Invoke-OtterCommand {
    param([string]$Command, [string]$Source)
    $path = Join-Path $script:Tmp ('h' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.ot')
    [System.IO.File]::WriteAllText($path, $Source, [System.Text.UTF8Encoding]::new($false))
    $arguments = @('-NoProfile', '-File', $script:OtterPs1, $Command, $path)
    if ($Command -eq 'web') { $arguments += '-NoOpen' }
    $output = & $script:HostExe @arguments 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (($output | ForEach-Object { $_.ToString() }) -join "`n") }
}

try {
    Test-Otter 'an inner handler using the row the outer handler makes is refused by check and web' {
        $source = $script:Head + @"
when addButton is clicked
    create row into line
    create button into deleteButton
    put deleteButton in line
    put line in taskList
    when deleteButton is clicked
        customstyle of line is "display: none;"
    .
.
"@
        foreach ($command in 'check', 'web') {
            $r = Invoke-OtterCommand -Command $command -Source $source
            Assert-AreEqual -Expected 2 -Actual $r.ExitCode
            Assert-True ($r.Text.Contains('This handler uses "line"')) "$command message: $($r.Text)"
            Assert-True ($r.Text.Contains('Line 9:')) "$command should point at the inner handler: $($r.Text)"
            Assert-True ($r.Text.Contains('in a function')) "$command should show the working form: $($r.Text)"
        }
    }

    Test-Otter 'the same row built in a function is accepted (the working form)' {
        $source = $script:Head + @"
to addRow
    create row into line
    create button into deleteButton
    put deleteButton in line
    put line in taskList
    when deleteButton is clicked
        customstyle of line is "display: none;"
    .
.
when addButton is clicked
    addRow
.
"@
        Assert-AreEqual -Expected 0 -Actual (Invoke-OtterCommand -Command 'check' -Source $source).ExitCode
    }

    Test-Otter 'a shared value set outside the handler is not refused' {
        $source = $script:Head + @"
clicks is 0
when addButton is clicked
    clicks is clicks plus 1
    create button into resetButton
    put resetButton in taskList
    when resetButton is clicked
        clicks is 0
    .
.
"@
        Assert-AreEqual -Expected 0 -Actual (Invoke-OtterCommand -Command 'check' -Source $source).ExitCode
    }

    Test-Otter 'rows made in a loop inside a handler are accepted (each pass keeps its own, D130)' {
        $source = $script:Head + @"
when addButton is clicked
    count from 1 to 3 as n
        create row into line
        create button into deleteButton
        put deleteButton in line
        put line in taskList
        when deleteButton is clicked
            customstyle of line is "display: none;"
        .
    .
.
"@
        Assert-AreEqual -Expected 0 -Actual (Invoke-OtterCommand -Command 'check' -Source $source).ExitCode
    }

    Test-Otter 'the inner handler''s own target is not the problem: using only it is accepted' {
        $source = $script:Head + @"
when addButton is clicked
    create button into deleteButton
    put deleteButton in taskList
    when deleteButton is clicked
        say "clicked"
    .
.
"@
        Assert-AreEqual -Expected 0 -Actual (Invoke-OtterCommand -Command 'check' -Source $source).ExitCode
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
