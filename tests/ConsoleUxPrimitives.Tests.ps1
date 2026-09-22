# tests/ConsoleUxPrimitives.Tests.ps1
#
# Production-entry-point certification for D100 (console UX primitives:
# colors, cursor positioning, menus, progress, secret input, TTY
# detection) - see docs/D100-CONSOLE-UX-PRIMITIVES-DESIGN.md.
#
# Every test spawns the real otter.ps1 process against a real .ot source
# file, matching this project's own "a renderer/helper/unit test does not
# certify a language capability" rule. Two things this sandbox genuinely
# cannot verify (documented, not silently skipped):
#   - Real cursor movement: this environment has no attached console
#     handle even when stdout isn't explicitly redirected by the test
#     itself, so [Console]::SetCursorPosition always fails here. The
#     validation logic in front of it (row/column >= 1) IS verified.
#   - Real character masking for `ask secretly`: [Console]::ReadKey
#     throws under redirected stdin, so these tests exercise the
#     documented Read-Host fallback path instead (see the interpreter's
#     Read-OtterSecretLine).

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Console UX Primitives (D100)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function Invoke-OtterProgram {
    param([string]$Source, [string[]]$StdinLines = @())

    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d100_$([Guid]::NewGuid().ToString('N')).ot")
    [System.IO.File]::WriteAllText($tmpFile, $Source, [System.Text.UTF8Encoding]::new($false))
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" run `"$tmpFile`""
        $psi.WorkingDirectory = $script:RepoRoot
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        foreach ($line in $StdinLines) { $process.StandardInput.WriteLine($line) }
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit(15000) | Out-Null
        return [pscustomobject]@{ Stdout = $stdout; ExitCode = $process.ExitCode }
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
}


# --- 1. Colors ------------------------------------------------------

Test-Otter 'say "..." in color "red" prints the text unchanged and exits cleanly' {
    $r = Invoke-OtterProgram -Source 'say "Alert!" in color "red"'
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'Alert!') 'expected the text itself to still print'
}

Test-Otter 'an unrecognized color name is a clean diagnostic naming the valid list, not a crash' {
    $r = Invoke-OtterProgram -Source 'say "Alert!" in color "puce"'
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match "don't recognize the color") 'expected the specific color diagnostic'
    Assert-True ($r.Stdout -match 'red, green, yellow') 'expected the valid-colors list in the message'
}

Test-Otter 'plain say (no color clause) is completely unaffected' {
    $r = Invoke-OtterProgram -Source 'say "Plain text"'
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'Plain text') 'expected ordinary say output unchanged'
}


# --- 2. Cursor positioning -------------------------------------------

Test-Otter 'set cursor to row 0 column 5 is rejected before touching the real console (row must be >= 1)' {
    $r = Invoke-OtterProgram -Source 'set cursor to row 0 column 5'
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'row and column of 1 or greater') 'expected the range-validation diagnostic'
}

Test-Otter 'set cursor to row 5 column 0 is rejected the same way (column must be >= 1)' {
    $r = Invoke-OtterProgram -Source 'set cursor to row 5 column 0'
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'row and column of 1 or greater') 'expected the range-validation diagnostic'
}


# --- 3. Interactive menus ---------------------------------------------

Test-Otter 'choose from a list returns the SELECTED ITEM, not its position' {
    $source = @'
options are
    "Apple"
    "Banana"
    "Cherry"
choose from options into choice
say "Picked:" choice
'@
    $r = Invoke-OtterProgram -Source $source -StdinLines @('2')
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'Picked: Banana') 'expected the item text, not "2"'
}

Test-Otter 'choose from a list re-prompts on non-numeric and out-of-range input rather than crashing' {
    $source = @'
options are
    "Apple"
    "Banana"
choose from options into choice
say "Picked:" choice
'@
    $r = Invoke-OtterProgram -Source $source -StdinLines @('notanumber', '99', '1')
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'Please enter a number from 1 to 2') 'expected re-prompt guidance'
    Assert-True ($r.Stdout -match 'Picked: Apple') 'expected the eventual valid selection to still work'
}

Test-Otter 'choosing from an empty list is a clean diagnostic, not a crash' {
    $r = Invoke-OtterProgram -Source "options are empty`nchoose from options into choice"
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'cannot choose from an empty list') 'expected the empty-list diagnostic'
}


# --- 4. Progress indicators -------------------------------------------

Test-Otter 'show progress renders a bar reflecting the percentage' {
    $r = Invoke-OtterProgram -Source 'show progress 50 percent'
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match '\[#{10}-{10}\] 50%') 'expected a half-filled 20-char bar at 50%'
}

Test-Otter 'show progress 0 percent and 100 percent render fully empty and fully filled bars' {
    $rZero = Invoke-OtterProgram -Source 'show progress 0 percent'
    $rFull = Invoke-OtterProgram -Source 'show progress 100 percent'
    Assert-True ($rZero.Stdout -match '\[-{20}\] 0%') 'expected a fully empty bar at 0%'
    Assert-True ($rFull.Stdout -match '\[#{20}\] 100%') 'expected a fully filled bar at 100%'
}

Test-Otter 'a percentage outside 0-100 is a clean diagnostic, never silently clamped' {
    $r = Invoke-OtterProgram -Source 'show progress 150 percent'
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'percentage between 0 and 100, but got 150') 'expected the specific out-of-range diagnostic'
}

Test-Otter 'a say after show progress lands on its own line, not glued onto the bar' {
    $r = Invoke-OtterProgram -Source "show progress 50 percent`nsay `"done`""
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match '(?m)^done\s*$') 'expected "done" as its own line, not appended after the bar text'
}


# --- 5. Secret input ---------------------------------------------------

Test-Otter 'ask secretly stores the typed value like ordinary ask (via the documented Read-Host fallback under redirected stdin)' {
    $r = Invoke-OtterProgram -Source 'ask secretly "Password:" and call it pw' -StdinLines @('hunter2')
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
}

Test-Otter 'ask secretly followed by using the value works end to end' {
    $r = Invoke-OtterProgram -Source "ask secretly `"Password:`" and call it pw`nsay `"Got it:`" pw" -StdinLines @('hunter2')
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'Got it: hunter2') 'expected the typed value to be usable afterward'
}

Test-Otter 'plain ask (no secretly) is completely unaffected' {
    $r = Invoke-OtterProgram -Source "ask `"Name:`" and call it n`nsay `"Hi`" n" -StdinLines @('Jeff')
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'Hi Jeff') 'expected ordinary ask unaffected'
}


# --- 6. TTY detection (and "noninteractive mode" via `not`) -----------

Test-Otter 'console is interactive is false under redirected stdout (this test harness itself)' {
    $r = Invoke-OtterProgram -Source "if console is interactive`n    say `"interactive`"`notherwise`n    say `"not interactive`"`n."
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'not interactive') 'expected false under this test harness''s redirected stdout'
}

Test-Otter '"not console is interactive" composes correctly (D11''s existing not) - this is the whole answer to "noninteractive mode"' {
    $r = Invoke-OtterProgram -Source "if not console is interactive`n    say `"confirmed noninteractive`"`n."
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'confirmed noninteractive') 'expected `not` to compose with the new expression'
}


# --- Keyword-narrowing safety: every new contextual word stays a real, ---
# --- ordinary variable name everywhere outside its specific phrase.   ---

Test-Otter 'console/cursor/color/progress/row/column/choice/secretly all still work as ordinary variable names' {
    $source = @'
console is 5
cursor is "blinking"
color is "blue"
progress is 75
row is 1
column is 2
choice is "picked"
secretly is true
say console
say cursor
say color
say progress
say row
say column
say choice
say secretly
'@
    $r = Invoke-OtterProgram -Source $source
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('5', 'blinking', 'blue', '75', '1', '2', 'picked', 'true') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Complete-OtterTests
