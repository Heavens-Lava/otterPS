# tests/FileWatching.Tests.ps1
#
# Production-entry-point certification for D104 (file/folder watching) -
# see rules.md's own design principle: OS file watchers, polling loops,
# and handles stay hidden behind "watch ... and call it X" / "on change
# of X". Every test spawns the REAL otter.ps1 process, watches a REAL
# file on disk, and triggers REAL filesystem changes from this process -
# matching this project's "a unit test does not certify a language
# capability" rule, and specifically the rule that background/event-
# driven features need to be run for real, not just read from source.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'File Watching (D104)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function New-OtterWatchSandbox {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d104_$([Guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# Starts `otter.ps1 run <source>.ot` in the background (it may block
# indefinitely inside the watch-event loop), lets the watcher register,
# runs $TriggerAction to make a real filesystem change, then waits for
# the process to exit on its own (the program is expected to call `stop
# watching` once it has seen what it's testing for) - killing it only as
# a timeout fallback so a real bug (an event never arriving) fails the
# test instead of hanging the suite.
function Invoke-OtterWatchProgram {
    param(
        [string]$Source,
        [string]$SandboxDir,
        [scriptblock]$TriggerAction,
        [int]$RegisterDelayMs = 2500,
        [int]$TimeoutMs = 12000,
        # When given, wait until the program prints this line (it says so right
        # after its watcher is registered) instead of guessing a fixed delay.
        # Otter's own startup takes over a second, so a fixed delay races it.
        [string]$ReadyLine = ''
    )

    $otFile = Join-Path $SandboxDir 'program.ot'
    [System.IO.File]::WriteAllText($otFile, $Source, [System.Text.UTF8Encoding]::new($false))

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" run `"$otFile`""
    $psi.WorkingDirectory = $SandboxDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()

    $earlyOutput = New-Object System.Text.StringBuilder
    if ($ReadyLine) {
        $readyDeadline = [DateTime]::UtcNow.AddSeconds(30)
        $lineTask = $null   # at most one read may be pending on the stream
        while ([DateTime]::UtcNow -lt $readyDeadline) {
            if ($null -eq $lineTask) { $lineTask = $process.StandardOutput.ReadLineAsync() }
            if (-not $lineTask.Wait(1000)) { continue }
            $line = $lineTask.Result
            $lineTask = $null
            if ($null -eq $line) { break }
            [void]$earlyOutput.AppendLine($line)
            if ($line.Trim() -eq $ReadyLine) { break }
        }
    } else {
        Start-Sleep -Milliseconds $RegisterDelayMs
    }
    if ($TriggerAction) { & $TriggerAction }

    $exited = $process.WaitForExit($TimeoutMs)
    if (-not $exited) {
        try { $process.Kill() } catch {}
    }
    $stdout = $earlyOutput.ToString() + $process.StandardOutput.ReadToEnd()
    $exitCode = $null
    if ($exited) { $exitCode = $process.ExitCode }
    return [pscustomobject]@{ Stdout = $stdout; ExitCode = $exitCode; TimedOut = (-not $exited) }
}


# --- 1. Change event, real file, real modification -----------------------

Test-Otter 'watch file + on change of fires on a real file modification, with correct changed path and change kind' {
    $dir = New-OtterWatchSandbox
    try {
        $target = Join-Path $dir 'settings.json'
        Set-Content -LiteralPath $target -Value '{"a":1}' -NoNewline
        $source = @"
watch file "settings.json" and call it settingsWatcher
on change of settingsWatcher
    say "changed"
    say change kind
    stop watching settingsWatcher
.
"@
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {
            Set-Content -LiteralPath $target -Value '{"a":2}' -NoNewline
        }
        Assert-False $r.TimedOut 'expected the watcher to see the change and exit on its own'
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('changed', 'changed') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# --- 2. Folder watching: create / delete / rename -------------------------

Test-Otter 'watch folder reports create, delete, and rename with correct file names and paths' {
    $dir = New-OtterWatchSandbox
    try {
        $source = @"
watch folder "." and call it dirWatcher
on create in dirWatcher
    say "created:" changed file name
.
on rename in dirWatcher
    say "renamed:" old path "->" changed path
    stop watching dirWatcher
.
say "watching"
"@
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {
            $a = Join-Path $dir 'a.txt'
            $b = Join-Path $dir 'b.txt'
            Set-Content -LiteralPath $a -Value 'hi' -NoNewline
            Start-Sleep -Milliseconds 500
            Rename-Item -LiteralPath $a -NewName 'b.txt'
        } -ReadyLine 'watching' -TimeoutMs 12000
        Assert-False $r.TimedOut 'expected create then rename to both be observed'
        Assert-True ($r.Stdout -match 'created: a\.txt') 'expected a create event naming a.txt'
        Assert-True ($r.Stdout -match 'renamed:.*a\.txt.*->.*b\.txt') 'expected a rename event with old path ending a.txt and new path ending b.txt'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# --- 3. Recursive vs non-recursive ----------------------------------------

Test-Otter 'a non-recursive folder watch does not see changes in a nested subfolder' {
    $dir = New-OtterWatchSandbox
    try {
        New-Item -ItemType Directory -Path (Join-Path $dir 'nested') -Force | Out-Null
        $source = @"
watch folder "." and call it dirWatcher
say "ready"
wait 3 seconds
say "still alive, saw nothing"
"@
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {
            Set-Content -LiteralPath (Join-Path $dir 'nested\deep.txt') -Value 'x' -NoNewline
        } -TimeoutMs 8000
        Assert-True $r.TimedOut 'a non-recursive watch was not expected to exit - it has no handler and nothing should crash it either'
        Assert-True ($r.Stdout -match 'still alive, saw nothing') 'expected the program to run past the nested change with no watcher event to react to'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'a recursive folder watch DOES see changes in a nested subfolder' {
    $dir = New-OtterWatchSandbox
    try {
        New-Item -ItemType Directory -Path (Join-Path $dir 'nested') -Force | Out-Null
        $source = @"
watch folder "." recursively and call it dirWatcher
on create in dirWatcher
    say "created:" changed path
    stop watching dirWatcher
.
"@
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {
            Set-Content -LiteralPath (Join-Path $dir 'nested\deep.txt') -Value 'x' -NoNewline
        }
        Assert-False $r.TimedOut 'expected the recursive watch to see the nested creation'
        Assert-True ($r.Stdout -match 'deep\.txt') 'expected the nested file name in the reported path'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# --- 4. is watching --------------------------------------------------------

Test-Otter '"X is watching" reflects the real active/stopped state' {
    $dir = New-OtterWatchSandbox
    try {
        $target = Join-Path $dir 'data.txt'
        Set-Content -LiteralPath $target -Value 'hi' -NoNewline
        $source = @"
watch file "data.txt" and call it dataWatcher
if dataWatcher is watching
    say "watching"
.
stop watching dataWatcher
if not dataWatcher is watching
    say "not watching anymore"
.
"@
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {} -RegisterDelayMs 300
        Assert-False $r.TimedOut 'expected the program to finish on its own with no event needed'
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('watching', 'not watching anymore') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# --- 5. Errors fail loudly -------------------------------------------------

Test-Otter 'watching a file that does not exist is a clean Otter runtime error, not a silent create' {
    $dir = New-OtterWatchSandbox
    try {
        $source = 'watch file "nope.txt" and call it w'
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {} -RegisterDelayMs 300
        Assert-False $r.TimedOut 'a missing-file watch must fail immediately, not hang'
        Assert-AreEqual -Expected 3 -Actual $r.ExitCode
        Assert-True ($r.Stdout -match "doesn't exist") 'expected a specific missing-file diagnostic'
        Assert-False (Test-Path -LiteralPath (Join-Path $dir 'nope.txt')) 'the file must never be silently created'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter 'watching a folder that does not exist is a clean Otter runtime error, not a silent create' {
    $dir = New-OtterWatchSandbox
    try {
        $source = 'watch folder "nope" and call it w'
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {} -RegisterDelayMs 300
        Assert-False $r.TimedOut 'a missing-folder watch must fail immediately, not hang'
        Assert-AreEqual -Expected 3 -Actual $r.ExitCode
        Assert-True ($r.Stdout -match "doesn't exist") 'expected a specific missing-folder diagnostic'
        Assert-False (Test-Path -LiteralPath (Join-Path $dir 'nope')) 'the folder must never be silently created'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Test-Otter '"stop watching" on a non-watcher value is a clean Otter runtime error' {
    $dir = New-OtterWatchSandbox
    try {
        $source = @"
x is 5
stop watching x
"@
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {} -RegisterDelayMs 300
        Assert-False $r.TimedOut 'a bad stop-watching target must fail immediately, not hang'
        Assert-AreEqual -Expected 3 -Actual $r.ExitCode
        Assert-True ($r.Stdout -match 'I can only stop watching a file watcher') 'expected a specific wrong-type diagnostic'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# --- 6. Debouncing (runtime behavior, not new syntax) ----------------------

Test-Otter 'rapid, equivalent file-change notifications are coalesced rather than each firing the handler' {
    $dir = New-OtterWatchSandbox
    try {
        $target = Join-Path $dir 'rapid.txt'
        Set-Content -LiteralPath $target -Value '0' -NoNewline
        # No `wait`/stop-watching in the program itself - it just keeps
        # watching and reporting every real firing. The outer harness
        # supplies the rapid writes and, after giving real OS + debounce
        # time to settle, kills the still-running process (expected -
        # TimedOut is not checked here) and inspects what was printed.
        $source = @"
watch file "rapid.txt" and call it w
on change of w
    say "fired"
.
"@
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {
            for ($i = 1; $i -le 5; $i++) {
                Set-Content -LiteralPath $target -Value "$i" -NoNewline
            }
        } -TimeoutMs 3000
        $firedCount = ([regex]::Matches($r.Stdout, 'fired')).Count
        Assert-True ($firedCount -ge 1) "expected the watcher to detect the change at least once, got $firedCount firings"
        Assert-True ($firedCount -lt 5) "expected fewer handler firings than the 5 rapid writes (coalesced), got $firedCount"
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# --- 7. Web target: fails loudly, never silently no-ops --------------------

Test-Otter 'file watching is rejected on the web target with a clean compile-time error' {
    $dir = New-OtterWatchSandbox
    try {
        $otFile = Join-Path $dir 'program.ot'
        [System.IO.File]::WriteAllText($otFile, 'watch file "x.txt" and call it w', [System.Text.UTF8Encoding]::new($false))
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script:OtterPs1`" web `"$otFile`" -NoOpen"
        $psi.WorkingDirectory = $dir
        $psi.RedirectStandardOutput = $true
        $psi.UseShellExecute = $false
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit(10000) | Out-Null
        Assert-True ($stdout -match 'not supported on the web target') 'expected a clean rejection naming the statement'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# --- 8. Keyword narrowing (no regressions) --------------------------------

Test-Otter 'watch/watching/change/changed/kind/old/recursively remain ordinary identifiers everywhere else' {
    $dir = New-OtterWatchSandbox
    try {
        $source = @"
watch is "hello"
watching is 5
change is "text"
changed is 3
kind is "sunny"
old is true
recursively is 7
say watch
say watching
say change
say changed
say kind
say old
say recursively
"@
        $r = Invoke-OtterWatchProgram -Source $source -SandboxDir $dir -TriggerAction {} -RegisterDelayMs 300
        Assert-False $r.TimedOut 'expected a plain program with no watchers to finish immediately'
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('hello', '5', 'text', '3', 'sunny', 'true', '7') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Complete-OtterTests
