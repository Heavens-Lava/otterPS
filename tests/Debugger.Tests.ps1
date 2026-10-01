# Debugger.Tests.ps1
#
# Real end-to-end proof of the first debugger slice, through the ACTUAL
# production entry point (otter.ps1 debug <file.ot>), not a renderer/helper
# called directly - the same "production entry point" rule CLAUDE.md holds
# every other Otter capability to. This spawns a real otter.ps1 process
# against a real dogfood .ot file, feeds it "continue" on real stdin exactly
# like Otter Studio's backend will, and asserts on its real stdout.
#
# In-process unit tests for the interpreter hook itself
# (Set-OtterStatementHook, Get-OtterCallStackSnapshot) live in
# tests/Interpreter.Tests.ps1, next to the rest of that module's tests.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Debugger (first slice)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:DogfoodFile = 'examples/debugger-demo.ot'

# Runs `otter.ps1 debug <RelativePath> -Breakpoints <Breakpoints>`, writes
# each line in $StdinLines to the child's real stdin (one "continue" per
# pause, in order), and returns its full stdout as a single string. Uses
# System.Diagnostics.Process directly (not PowerShell's own & / 2>&1) so
# stdin can be written to interactively while the child is still running -
# exactly what Otter Studio's backend needs to do to resume a paused program.
function Invoke-OtterDebugProcess {
    param(
        [string]$RelativePath,
        [string]$Breakpoints,
        [string[]]$StdinLines = @()
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" debug `"$RelativePath`" -Breakpoints `"$Breakpoints`""
    $psi.WorkingDirectory = $script:RepoRoot
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()

    foreach ($line in $StdinLines) {
        $process.StandardInput.WriteLine($line)
        $process.StandardInput.Flush()
    }
    $process.StandardInput.Close()

    $stdout = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit(15000) | Out-Null
    return $stdout
}

function Get-OtterDebugEvents {
    param([string]$Stdout)

    $events = @()
    foreach ($line in ($Stdout -split "`r?`n")) {
        if ($line.StartsWith('@@OTTER_DEBUG@@ ')) {
            $json = $line.Substring('@@OTTER_DEBUG@@ '.Length)
            $events += (ConvertFrom-Json -InputObject $json)
        }
    }
    # A bare array with exactly one element gets silently unwrapped to a
    # scalar when a function returns it through the pipeline - the leading
    # comma forces PowerShell to emit the array itself as one object.
    return ,$events
}

function Get-OtterProgramOutputLines {
    param([string]$Stdout)

    $lines = @(($Stdout -split "`r?`n") | Where-Object {
        $_ -ne '' -and -not $_.StartsWith('@@OTTER_DEBUG@@ ')
    })
    return ,$lines
}


Test-Otter 'debug with no breakpoints behaves exactly like a normal run, plus one closing "finished" event' {
    $stdout = Invoke-OtterDebugProcess -RelativePath $script:DogfoodFile -Breakpoints ''
    $events = Get-OtterDebugEvents -Stdout $stdout
    $programLines = Get-OtterProgramOutputLines -Stdout $stdout

    Assert-AreEqual -Expected 1 -Actual $events.Count
    Assert-AreEqual -Expected 'finished' -Actual $events[0].event
    Assert-Lines -Expected @('Score is 5', 'Final score is 8', 'Done Jeff') -Actual $programLines
}

Test-Otter 'a breakpoint pauses execution at the exact Otter source line, before that line runs, with correct Otter locals' {
    # Line 7 of examples/debugger-demo.ot is `say "Score is" score` - by the
    # time execution reaches it, `add 5 to score` (line 6) has already run
    # (score is 5) but the say itself has not, so "Score is 5" must NOT be
    # in the program output yet when the pause event is produced.
    $stdout = Invoke-OtterDebugProcess -RelativePath $script:DogfoodFile -Breakpoints '7' -StdinLines @('continue')
    $events = Get-OtterDebugEvents -Stdout $stdout

    Assert-AreEqual -Expected 2 -Actual $events.Count
    Assert-AreEqual -Expected 'paused' -Actual $events[0].event
    Assert-AreEqual -Expected 'debugger-demo.ot' -Actual $events[0].file
    Assert-AreEqual -Expected 7 -Actual $events[0].line
    Assert-AreEqual -Expected 'Jeff' -Actual $events[0].locals.name
    Assert-AreEqual -Expected 5 -Actual $events[0].locals.score
    Assert-AreEqual -Expected 'finished' -Actual $events[1].event
}

Test-Otter 'continue resumes execution and the program finishes normally with unaltered output' {
    $stdout = Invoke-OtterDebugProcess -RelativePath $script:DogfoodFile -Breakpoints '7' -StdinLines @('continue')
    $programLines = Get-OtterProgramOutputLines -Stdout $stdout

    # Exactly what `otter run` (no debugging at all) produces for this file -
    # instrumentation must not alter program results.
    Assert-Lines -Expected @('Score is 5', 'Final score is 8', 'Done Jeff') -Actual $programLines
}

Test-Otter 'multiple breakpoints pause more than once, each at its own exact line and locals' {
    $stdout = Invoke-OtterDebugProcess -RelativePath $script:DogfoodFile -Breakpoints '7,9' -StdinLines @('continue', 'continue')
    $events = Get-OtterDebugEvents -Stdout $stdout

    Assert-AreEqual -Expected 3 -Actual $events.Count
    Assert-AreEqual -Expected 7 -Actual $events[0].line
    Assert-AreEqual -Expected 5 -Actual $events[0].locals.score
    Assert-AreEqual -Expected 9 -Actual $events[1].line
    Assert-AreEqual -Expected 8 -Actual $events[1].locals.score
    Assert-AreEqual -Expected 'finished' -Actual $events[2].event
}

Test-Otter 'plain `otter run` (no debug subcommand at all) never emits the debug protocol prefix' {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" run `"$script:DogfoodFile`""
    $psi.WorkingDirectory = $script:RepoRoot
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit(15000) | Out-Null

    Assert-Lines -Expected @('Score is 5', 'Final score is 8', 'Done Jeff') -Actual (Get-OtterProgramOutputLines -Stdout $stdout)
    if ($stdout -match [regex]::Escape('@@OTTER_DEBUG@@')) {
        throw 'ordinary `otter run` must never emit the debug protocol prefix'
    }
}

# --- Stepping, watches, conditions, pause and errors --------------------------
#
# A conversation like Studio's: read the events as they come and answer each
# pause with the next reply (one command or several; the last one resumes).
# `BeforeFirst` is sent as soon as the process starts (for `pause`).
function Invoke-OtterDebugConversation {
    param(
        [string]$RelativePath,
        [string]$Breakpoints = '',
        [object[]]$Replies = @(),
        [string[]]$BeforeFirst = @(),
        [int]$BeforeFirstDelayMs = 0,
        # Sent once, when the program prints this line (for `pause` mid-run).
        [string]$PauseWhenOutput = ''
    )
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" debug `"$RelativePath`" -Breakpoints `"$Breakpoints`""
    $psi.WorkingDirectory = $script:RepoRoot
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    if ($BeforeFirst.Count -gt 0) {
        if ($BeforeFirstDelayMs -gt 0) { Start-Sleep -Milliseconds $BeforeFirstDelayMs }
        foreach ($line in $BeforeFirst) { $process.StandardInput.WriteLine($line); $process.StandardInput.Flush() }
    }
    $events = [System.Collections.Generic.List[object]]::new()
    $output = [System.Collections.Generic.List[string]]::new()
    $pauses = 0
    while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
        if (-not $line.StartsWith('@@OTTER_DEBUG@@ ')) {
            if ($line) { $output.Add($line) }
            if ($PauseWhenOutput -and $line -eq $PauseWhenOutput) { $process.StandardInput.WriteLine('pause'); $process.StandardInput.Flush(); $PauseWhenOutput = '' }
            continue
        }
        $event = ConvertFrom-Json -InputObject $line.Substring('@@OTTER_DEBUG@@ '.Length)
        $events.Add($event)
        if ($event.event -eq 'paused') {
            $reply = if ($pauses -lt $Replies.Count) { $Replies[$pauses] } else { 'continue' }
            $pauses++
            foreach ($command in @($reply)) { $process.StandardInput.WriteLine($command); $process.StandardInput.Flush() }
        }
    }
    $process.StandardInput.Close()
    $process.WaitForExit(15000) | Out-Null
    return @{ Events = $events; Output = $output; ExitCode = $process.ExitCode }
}

$script:StepsFile = 'examples/debugger-steps.ot'

Test-Otter 'step into, step over and step out follow the program into a function and back' {
    # Line 14 calls double (lines 3-6); line 15 runs after it returns.
    $run = Invoke-OtterDebugConversation -RelativePath $script:StepsFile -Breakpoints '14' -Replies @(
        'step',                                  # at 14 -> into double, line 4
        'next',                                  # at 4  -> line 5 (return)
        'out',                                   # at 5  -> back in the loop, line 15
        @('breakpoints []', 'continue')          # at 15 -> run to the end
    )
    $paused = @($run.Events | Where-Object { $_.event -eq 'paused' })
    Assert-AreEqual -Expected '14,4,5,15' -Actual (($paused | ForEach-Object { $_.line }) -join ',')
    Assert-AreEqual -Expected 'double' -Actual $paused[1].frames[0].function
    Assert-AreEqual -Expected 14 -Actual $paused[1].frames[1].line
    Assert-AreEqual -Expected 1 -Actual @($paused[3].frames).Count
    Assert-AreEqual -Expected 'step' -Actual $paused[1].reason
    Assert-Lines -Expected @('Total is 70') -Actual @($run.Output)
}

Test-Otter 'while paused, expressions evaluate in the paused frame (watches); locals, globals and lists are inspectable' {
    $run = Invoke-OtterDebugConversation -RelativePath $script:StepsFile -Breakpoints '4' -Replies @(
        ,@('eval w1 n times 10', 'eval w2 total', 'eval w3 nosuchthing', 'eval w4 prices', 'breakpoints []', 'continue')
    )
    $paused = @($run.Events | Where-Object { $_.event -eq 'paused' })[0]
    $locals = @($paused.scopes | Where-Object { $_.name -eq 'Locals' })[0]
    $globals = @($paused.scopes | Where-Object { $_.name -eq 'Globals' })[0]
    Assert-AreEqual -Expected 'n' -Actual (@($locals.variables | ForEach-Object { $_.name }) -join ',')
    Assert-AreEqual -Expected '5' -Actual @($locals.variables)[0].value
    $prices = @($globals.variables | Where-Object { $_.name -eq 'prices' })[0]
    Assert-AreEqual -Expected 'a list' -Actual $prices.type
    Assert-AreEqual -Expected '5,10,20' -Actual ((@($prices.children) | ForEach-Object { $_.value }) -join ',')
    if (@($globals.variables | Where-Object { $_.name -eq 'double' }).Count -ne 0) { throw 'functions are not variables in the Variables view' }
    $evaluated = @{}
    foreach ($e in @($run.Events | Where-Object { $_.event -eq 'evaluated' })) { $evaluated[$e.id] = $e }
    Assert-AreEqual -Expected '50' -Actual $evaluated['w1'].value
    Assert-AreEqual -Expected '0' -Actual $evaluated['w2'].value
    if (-not $evaluated['w3'].error -or $evaluated['w3'].error -notmatch 'nosuchthing') { throw "an unknown name is an Otter error naming it, got: $($evaluated['w3'] | ConvertTo-Json -Compress)" }
    Assert-AreEqual -Expected 3 -Actual @($evaluated['w4'].children).Count
    Assert-Lines -Expected @('Total is 70') -Actual @($run.Output)
}

Test-Otter 'breakpoints change while the program runs; a condition decides, a logpoint writes without stopping' {
    $run = Invoke-OtterDebugConversation -RelativePath $script:StepsFile -Breakpoints '7' -Replies @(
        @('breakpoints [{"line":15,"condition":"price is 20"},{"line":17,"log":"about to say {total}"}]', 'continue'),
        'continue'
    )
    $paused = @($run.Events | Where-Object { $_.event -eq 'paused' })
    Assert-AreEqual -Expected '7,15' -Actual (($paused | ForEach-Object { $_.line }) -join ',')
    Assert-AreEqual -Expected '20' -Actual $paused[1].locals.price
    $logs = @($run.Events | Where-Object { $_.event -eq 'log' })
    Assert-AreEqual -Expected 'about to say 70' -Actual $logs[0].text
    Assert-Lines -Expected @('Total is 70') -Actual @($run.Output)
}

Test-Otter 'hit counts: the Nth hit, from the Nth on, every Nth - and a condition decides what is a hit' {
    # Line 15 runs three times: price 5, 10, 20.
    $cases = @(
        @{ Hits = '2'; Prices = '10' },
        @{ Hits = '>= 2'; Prices = '10,20' },
        @{ Hits = '% 3'; Prices = '20' },
        @{ Hits = '1'; Condition = 'price is greater than 5'; Prices = '10' }
    )
    foreach ($case in $cases) {
        $bp = [ordered]@{ line = 15; hits = $case.Hits }
        if ($case.Condition) { $bp['condition'] = $case.Condition }
        $json = ConvertTo-Json -InputObject @($bp) -Compress
        $run = Invoke-OtterDebugConversation -RelativePath $script:StepsFile -Breakpoints '7' -Replies @(,@("breakpoints $json", 'continue'))
        $prices = @($run.Events | Where-Object { $_.event -eq 'paused' -and $_.line -eq 15 } | ForEach-Object { $_.locals.price }) -join ','
        Assert-AreEqual -Expected $case.Prices -Actual $prices
        Assert-Lines -Expected @('Total is 70') -Actual @($run.Output)
    }
}

Test-Otter 'pause stops a running program at its next statement; continue lets it finish' {
    $file = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-debug-pause-" + [Guid]::NewGuid().ToString('N') + '.ot')
    [System.IO.File]::WriteAllText($file, "say `"started`"`ntally is 0`nwhile tally is less than 2000`n    add 1 to tally`n.`nsay `"counted`" tally`n")
    try {
        $run = Invoke-OtterDebugConversation -RelativePath $file -PauseWhenOutput 'started' -Replies @('next', @('eval c tally', 'continue'))
        $paused = @($run.Events | Where-Object { $_.event -eq 'paused' })
        # Paused at the statement after the one running when pause arrived (it
        # may already be in the loop); one step later tally exists.
        Assert-AreEqual -Expected 2 -Actual $paused.Count
        Assert-AreEqual -Expected 'pause' -Actual $paused[0].reason
        if ($paused[0].line -lt 2) { throw "paused before the program ran: line $($paused[0].line)" }
        $c = @($run.Events | Where-Object { $_.event -eq 'evaluated' })[0]
        if ($c.error -or $c.value -notmatch '^\d+$') { throw "tally should be a number when paused mid-run, got: $($c | ConvertTo-Json -Compress)" }
        Assert-Lines -Expected @('started', 'counted 2000') -Actual @($run.Output)
    } finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
}

Test-Otter 'an error stops the session at the failing line with its message and the variables, then the run ends as it would' {
    $file = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-debug-error-" + [Guid]::NewGuid().ToString('N') + '.ot')
    [System.IO.File]::WriteAllText($file, "total is 10`nparts is 0`ntotal divided by parts make share`nsay share`n")
    try {
        $run = Invoke-OtterDebugConversation -RelativePath $file -Replies @('continue')
        $paused = @($run.Events | Where-Object { $_.event -eq 'paused' })
        Assert-AreEqual -Expected 1 -Actual $paused.Count
        Assert-AreEqual -Expected 'error' -Actual $paused[0].reason
        Assert-AreEqual -Expected 3 -Actual $paused[0].line
        if ($paused[0].message -notmatch 'zero') { throw "expected the division-by-zero message, got: $($paused[0].message)" }
        Assert-AreEqual -Expected '0' -Actual $paused[0].locals.parts
        Assert-AreEqual -Expected 'finished' -Actual @($run.Events)[-1].event
        if ($run.ExitCode -eq 0) { throw 'the run still fails after the error stop' }
    } finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
}

Complete-OtterTests
