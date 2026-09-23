# tests/TierOneRuntime.Tests.ps1
#
# Production-entry-point certification for D101 tier-1 (general wait,
# seeded random, named timers, date parsing) - Jeff's ChatGPT-assisted
# syntax design, batched as "tier 1: small, contained" features.
#
# Every test spawns the real otter.ps1 process against a real .ot source
# file (console target via `run`, web target via `web`), matching this
# project's own "a unit test does not certify a language capability" rule.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Tier-1 Runtime Primitives (D101)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function Invoke-OtterProgram {
    param([string]$Source, [string]$Mode = 'run')

    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d101_$([Guid]::NewGuid().ToString('N')).ot")
    [System.IO.File]::WriteAllText($tmpFile, $Source, [System.Text.UTF8Encoding]::new($false))
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" $Mode `"$tmpFile`" -NoOpen"
        $psi.WorkingDirectory = $script:RepoRoot
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit(15000) | Out-Null
        return [pscustomobject]@{ Stdout = $stdout; ExitCode = $process.ExitCode }
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
        $htmlPath = [System.IO.Path]::ChangeExtension($tmpFile, '.html')
        Remove-Item -LiteralPath $htmlPath -Force -ErrorAction SilentlyContinue
    }
}


# --- 1. General wait/delay -------------------------------------------

Test-Otter 'wait 0 seconds runs to completion and exits cleanly' {
    $r = Invoke-OtterProgram -Source @'
wait 0 seconds
say "done"
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'done') 'expected the program to continue after waiting'
}

Test-Otter 'wait accepts a variable duration and a plain identifier unit word' {
    $r = Invoke-OtterProgram -Source @'
delay is 0
wait delay seconds
say "done"
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'done') 'expected variable-duration wait to parse and run'
}

Test-Otter 'a negative wait duration is a clean Otter runtime error' {
    $r = Invoke-OtterProgram -Source @'
duration is 0 minus 1
wait duration seconds
'@
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'negative amount of time') 'expected a specific negative-duration diagnostic'
}

Test-Otter 'wait is rejected on the web target with a clean compile-time error' {
    $r = Invoke-OtterProgram -Source 'wait 1 second' -Mode 'web'
    Assert-True ($r.Stdout -match 'not supported on the web target') 'expected a clean rejection naming the statement'
}


# --- 2. Seeded random --------------------------------------------------

Test-Otter 'set random seed to N makes random number reproducible' {
    $r = Invoke-OtterProgram -Source @'
set random seed to 42
random number from 1 to 1000 into firstRoll
set random seed to 42
random number from 1 to 1000 into secondRoll
say firstRoll
say secondRoll
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    $lines = ($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' }
    Assert-AreEqual -Expected $lines[0] -Actual $lines[1]
}

Test-Otter 'set random seed to is rejected on the web target with a clean compile-time error' {
    $r = Invoke-OtterProgram -Source 'set random seed to 42' -Mode 'web'
    Assert-True ($r.Stdout -match 'not supported on the web target') 'expected a clean rejection naming the statement'
}


# --- 3. Named timers ----------------------------------------------------

Test-Otter 'start timer / elapsed time of / elapsed milliseconds of all work and report a number' {
    $r = Invoke-OtterProgram -Source @'
start timer workTimer
elapsedSec is elapsed time of workTimer
elapsedMs is elapsed milliseconds of workTimer
if elapsedSec is at least 0
    say "sec ok: true"
.
if elapsedMs is at least 0
    say "ms ok: true"
.
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'sec ok: true') 'expected elapsed time of to be a non-negative number'
    Assert-True ($r.Stdout -match 'ms ok: true') 'expected elapsed milliseconds of to be a non-negative number'
}

Test-Otter 'elapsed time of a non-timer value is a clean Otter runtime error' {
    $r = Invoke-OtterProgram -Source @'
x is 5
y is elapsed time of x
'@
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'I can only measure elapsed time of a timer') 'expected a specific wrong-type diagnostic'
}

Test-Otter 'start timer / elapsed time of also work on the web target' {
    $r = Invoke-OtterProgram -Source @'
start timer workTimer
elapsedSec is elapsed time of workTimer
say elapsedSec
'@ -Mode 'web'
    Assert-True ($r.Stdout -match 'compiled to') 'expected the web build to succeed without a rejection error'
}


# --- 4. Date parsing -----------------------------------------------------

Test-Otter 'date from "yyyy-MM-dd" parses and prints without a spurious time of day' {
    $r = Invoke-OtterProgram -Source @'
d is date from "2024-01-15"
say d
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('2024-01-15') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'date from with an explicit "using" format parses correctly' {
    $r = Invoke-OtterProgram -Source @'
d is date from "01/15/2024" using "MM/dd/yyyy"
say d
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('2024-01-15') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'an unparseable date is a clean Otter runtime error, not a raw exception' {
    $r = Invoke-OtterProgram -Source 'd is date from "not a real date"'
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match "couldn't understand") 'expected a specific bad-date diagnostic'
    Assert-False ($r.Stdout -match 'at System\.') 'a raw .NET stack trace must never reach the user'
}

Test-Otter 'date from produces the correct local date on the web target too (regression: UTC-midnight timezone shift)' {
    $r = Invoke-OtterProgram -Source @'
d is date from "2024-01-15"
say d
d2 is date from "01/15/2024" using "MM/dd/yyyy"
say d2
'@ -Mode 'web'
    Assert-True ($r.Stdout -match 'compiled to') 'expected the web build to succeed'
}


# --- 5. Keyword narrowing (no regressions) --------------------------------

Test-Otter 'date/timer/seed/using/elapsed/random remain ordinary identifiers everywhere else' {
    $r = Invoke-OtterProgram -Source @'
date is "2024-01-01"
timer is "kitchen"
seed is 7
using is true
elapsed is 10
random is "dice"
say date
say timer
say seed
say using
say elapsed
say random
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('2024-01-01', 'kitchen', '7', 'true', '10', 'dice') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Complete-OtterTests
