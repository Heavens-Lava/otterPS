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

Complete-OtterTests
