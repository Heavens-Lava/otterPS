# FastStart.Tests.ps1
#
# Fast start runs a program that otter.ps1 already compiled straight from the
# cache: otter.exe on Windows (distribution/launcher/OtterLauncher.cs, no
# PowerShell at all) and the `otter` launcher with otter-fast.ps1 on macOS and
# Linux (PowerShell 7 without Otter's modules). These tests run each program
# through otter.ps1 first (which compiles it and writes the fast-start entry),
# then through the launcher, and require the same standard-output bytes and
# exit code - and that every case the fast path must not handle goes to
# otter.ps1. They use a copy of Otter in a temporary folder, so editing "Otter
# itself" cannot touch the repository.

. "$PSScriptRoot\TestHelpers.ps1"

$script:OnWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
Write-Host ''
Write-Host $(if ($script:OnWindows) { 'Fast start (otter.exe)' } else { 'Fast start (otter launcher + otter-fast.ps1)' }) -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_fast_' + [Guid]::NewGuid().ToString('N'))
$script:Install = Join-Path $script:Tmp 'otter'
$script:Work = Join-Path $script:Tmp 'work'
$script:Cache = Join-Path $script:Tmp 'cache'
New-Item -ItemType Directory -Path $script:Install, $script:Work, $script:Cache -Force | Out-Null
foreach ($item in @('otter.ps1', 'otter-fast.ps1', 'otter.cmd', 'otter', 'Otter.Contract.psm1', 'VERSION')) {
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot $item) -Destination $script:Install
}
Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'src') -Destination $script:Install -Recurse
$script:Ps1 = Join-Path $script:Install 'otter.ps1'
if ($script:OnWindows) {
    & (Join-Path $script:RepoRoot 'tools\Build-OtterLauncher.ps1') -Destination $script:Install | Out-Null
    $script:Launcher = Join-Path $script:Install 'otter.exe'
    $script:LauncherPrefix = @()
    $script:PowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
}
else {
    $script:Launcher = '/bin/sh'
    $script:LauncherPrefix = @((Join-Path $script:Install 'otter'))
    $script:PowerShell = (Get-Process -Id $PID).Path
}

# Runs a program and returns its raw standard-output bytes (as Base64, so a
# byte difference is a string difference), its stderr text and exit code.
function Invoke-Captured {
    param([string]$FileName, [string[]]$Arguments, [hashtable]$Environment = @{})
    $start = [System.Diagnostics.ProcessStartInfo]::new($FileName)
    $start.Arguments = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.WorkingDirectory = $script:Work
    $start.EnvironmentVariables['OTTER_COMPILED_CACHE'] = $script:Cache
    $start.EnvironmentVariables['OTTER_ENGINE_TRACE'] = '1'
    foreach ($k in $Environment.Keys) { $start.EnvironmentVariables[$k] = $Environment[$k] }
    $process = [System.Diagnostics.Process]::Start($start)
    $errTask = $process.StandardError.ReadToEndAsync()
    $buffer = [System.IO.MemoryStream]::new()
    $process.StandardOutput.BaseStream.CopyTo($buffer)
    $process.WaitForExit()
    return [pscustomobject]@{
        Stdout = [Convert]::ToBase64String($buffer.ToArray())
        Text = [System.Text.Encoding]::UTF8.GetString($buffer.ToArray())
        Trace = $errTask.Result
        ExitCode = $process.ExitCode
    }
}

function New-Program {
    param([string]$Source, [string]$Name = ('p' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.ot'))
    $path = Join-Path $script:Work $Name
    [System.IO.File]::WriteAllText($path, $Source, [System.Text.UTF8Encoding]::new($false))
    return $path
}

function Invoke-ViaPs1 { param([string]$Path, [string[]]$ProgramArgs = @(), [hashtable]$Environment = @{})
    return Invoke-Captured -FileName $script:PowerShell -Arguments (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Ps1, 'run', $Path) + $ProgramArgs) -Environment $Environment }
function Invoke-ViaExe { param([string[]]$Arguments, [hashtable]$Environment = @{})
    return Invoke-Captured -FileName $script:Launcher -Arguments (@($script:LauncherPrefix) + $Arguments) -Environment $Environment }
function Skip-UnlessWindows([string]$Why) {
    if ($script:OnWindows) { return $false }
    Write-Host "        skip  $Why" -ForegroundColor DarkYellow
    return $true
}

# The program runs through otter.ps1 (compiling it), then through otter.exe on
# the fast path; both must produce the same bytes and exit code.
#
# -Setup runs before each of the two runs (it puts the files the program uses
# in place, and may return open file handles that lock files); everything it
# returns is disposed after the run, and -Check sees the folder afterwards.
function Assert-FastMatches {
    param([string]$Source, [string[]]$ProgramArgs = @(), [scriptblock]$Setup = $null, [scriptblock]$Check = $null)
    $path = New-Program -Source $Source
    $held = if ($Setup) { @(& $Setup) } else { @() }
    try { $reference = Invoke-ViaPs1 -Path $path -ProgramArgs $ProgramArgs } finally { foreach ($h in $held) { if ($h) { $h.Dispose() } } }
    $after = if ($Check) { & $Check } else { $null }
    Assert-True ($reference.Trace -match 'otter engine: compiled') "otter.ps1 did not compile it: $($reference.Trace)"
    $held = if ($Setup) { @(& $Setup) } else { @() }
    try { $fast = Invoke-ViaExe -Arguments (@('run', $path) + $ProgramArgs) } finally { foreach ($h in $held) { if ($h) { $h.Dispose() } } }
    if ($Check) { Assert-AreEqual -Expected $after -Actual (& $Check) }
    Assert-True ($fast.Trace -match 'fast start') "otter.exe did not take the fast path: $($fast.Trace)"
    Assert-AreEqual -Expected $reference.ExitCode -Actual $fast.ExitCode
    Assert-AreEqual -Expected $reference.Text -Actual $fast.Text
    Assert-AreEqual -Expected $reference.Stdout -Actual $fast.Stdout
    return $fast
}

try {
    Test-Otter 'a compiled program runs on the fast path with the same output bytes and arguments' {
        $r = Assert-FastMatches -Source "total is 0`ncount from 1 to 2000 as n`n    total is total plus n`n.`nsay `"total`" total`nsay arguments" -ProgramArgs @('one', 'two words')
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    }

    Test-Otter 'functions, lists, things, text and dates match otter.ps1 byte for byte' {
        $source = @'
to square n
    return n times n
.
numbers are
    3
    1
    2
.
sort numbers
square 12 make s
say numbers s
person has name "Ada", age 36
say name of person "is" age of person
say uppercase of "otter"
d is date from "2024-01-31"
add 1 month to d
say d
'@
        [void](Assert-FastMatches -Source $source)
    }

    Test-Otter 'non-ASCII text is written exactly as otter.ps1 writes it' {
        [void](Assert-FastMatches -Source "say `"héllo wörld ✓ 世界`"")
    }

    Test-Otter 'a runtime error has the same text and exit code 3' {
        $r = Assert-FastMatches -Source "say `"before`"`nx is 1 / 0"
        Assert-AreEqual -Expected 3 -Actual $r.ExitCode
        Assert-True ($r.Text.Contains('I cannot divide by zero.')) "missing message: $($r.Text)"
    }

    Test-Otter 'an error with a suggestion, and a top-level stop, match too' {
        [void](Assert-FastMatches -Source "say `"a`"`n    `nsay missingName")
        [void](Assert-FastMatches -Source "say `"a`"`nstop")
    }

    # --- the library without PowerShell (OtterLibrary) -----------------------

    Test-Otter 'set random seed gives Get-Random''s numbers on the fast path' {
        [void](Assert-FastMatches -Source "set random seed to 42`ncount from 1 to 8 as n`n    random number from 1 to 100 into r`n    say r`n.`ncolors are`n    `"red`"`n    `"green`"`n    `"blue`"`n.`nrandom item from colors into c`nsay c`nset random seed to 7`nlow is 0 minus 5`nrandom number from low to 5 into x`nsay x")
    }

    Test-Otter 'an unseeded random number runs on the fast path and stays in range' {
        $path = New-Program -Source "random number from 1 to 6 into roll`nsay roll"
        [void](Invoke-ViaPs1 -Path $path)
        foreach ($i in 1..5) {
            $r = Invoke-ViaExe -Arguments @('run', $path)
            Assert-True ($r.Trace -match 'fast start') "trace: $($r.Trace)"
            Assert-AreEqual -Expected 0 -Actual $r.ExitCode
            $n = [int]$r.Text.Trim()
            Assert-True ($n -ge 1 -and $n -le 6) "roll out of range: $n"
        }
    }

    # Every file case starts from the same files, made fresh in its own folder.
    function New-FileCase {
        param([hashtable]$Files = @{})
        $folder = Join-Path $script:Work ('f' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        return [pscustomobject]@{ Folder = $folder; Files = $Files }
    }
    function Reset-FileCase {
        param($Case)
        if (Test-Path -LiteralPath $Case.Folder) {
            Get-ChildItem -LiteralPath $Case.Folder -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }
            Remove-Item -LiteralPath $Case.Folder -Recurse -Force
        }
        New-Item -ItemType Directory -Path $Case.Folder | Out-Null
        foreach ($name in $Case.Files.Keys) {
            $spec = $Case.Files[$name]
            $target = Join-Path $Case.Folder $name
            if ($spec -eq '<folder>') { New-Item -ItemType Directory -Path $target -Force | Out-Null; continue }
            $readOnly = $spec.StartsWith('<ro>')
            [System.IO.File]::WriteAllText($target, $spec.Replace('<ro>', '').Replace('<locked>', ''), [System.Text.UTF8Encoding]::new($false))
            if ($readOnly) { (Get-Item -LiteralPath $target).IsReadOnly = $true }
        }
        foreach ($name in $Case.Files.Keys) {
            if ($Case.Files[$name] -like '<locked>*') { [System.IO.File]::Open((Join-Path $Case.Folder $name), 'Open', 'ReadWrite', 'None') }
        }
    }
    function Get-FileCaseState {
        param($Case)
        @(Get-ChildItem -LiteralPath $Case.Folder -Recurse -File | Sort-Object FullName | ForEach-Object {
            $_.FullName.Substring($Case.Folder.Length) + '=' + [System.IO.File]::ReadAllText($_.FullName) + $(if ($_.IsReadOnly) { ' (read-only)' } else { '' })
        }) -join '; '
    }
    function Assert-FileCase {
        param([string]$Source, [hashtable]$Files = @{})
        $case = New-FileCase -Files $Files
        $program = $Source.Replace('DIR', $case.Folder.Replace('\', '/'))
        return (Assert-FastMatches -Source $program -Setup { Reset-FileCase $case }.GetNewClosure() -Check { Get-FileCaseState $case }.GetNewClosure())
    }

    Test-Otter 'writing, appending, reading, copying, moving and deleting files match otter.ps1' {
        $r = Assert-FileCase -Source @'
write "first" to "DIR/a.txt"
append " second" to "DIR/a.txt"
read "DIR/a.txt" into t
say t length of t
write "atomic ü 世界" to "DIR/sub/b.txt" atomically
read "DIR/sub/b.txt" into u
say u
if file "DIR/a.txt" exists
    say "yes"
.
copy "DIR/a.txt" to "DIR/c.txt"
copy "DIR/a.txt" to "DIR/box"
move "DIR/c.txt" to "DIR/d.txt"
delete file "DIR/sub/b.txt"
if file "DIR/sub/b.txt" exists
    say "still there"
otherwise
    say "deleted"
.
'@ -Files @{ 'box' = '<folder>' }
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    }

    Test-Otter 'copy, move and delete replace or remove read-only files, as -Force does' {
        if (Skip-UnlessWindows 'read-only files: Windows semantics') { return }
        [void](Assert-FileCase -Source "copy `"DIR/src.txt`" to `"DIR/ro1.txt`"`nmove `"DIR/src2.txt`" to `"DIR/ro2.txt`"`ndelete file `"DIR/ro3.txt`"`nsay `"done`"" -Files @{ 'src.txt' = 'S'; 'src2.txt' = 'T'; 'ro1.txt' = '<ro>old'; 'ro2.txt' = '<ro>old'; 'ro3.txt' = '<ro>old' })
    }

    Test-Otter 'file errors have otter.ps1''s exact text: missing, folder, read-only, things without a path' {
        foreach ($case in @(
            @{ S = "read `"DIR/missing.txt`" into t" },
            @{ S = "delete file `"DIR/missing.txt`"" },
            @{ S = "copy `"DIR/missing.txt`" to `"DIR/x.txt`"" },
            @{ S = "move `"DIR/missing.txt`" to `"DIR/x.txt`"" },
            @{ S = "write `"x`" to `"DIR/box`""; F = @{ 'box' = '<folder>' } },
            @{ S = "append `"x`" to `"DIR/box`""; F = @{ 'box' = '<folder>' } },
            @{ S = "delete file `"DIR/box`""; F = @{ 'box' = '<folder>' } },
            @{ S = "write `"x`" to `"DIR/ro.txt`" atomically"; F = @{ 'ro.txt' = '<ro>old' }; W = $true },
            @{ S = "write `"x`" to `"DIR/ro.txt`""; F = @{ 'ro.txt' = '<ro>old' }; W = $true },
            @{ S = "write `"x`" to `"`"" },
            @{ S = "note is a thing`nnote has size 3`nwrite `"x`" to note" },
            @{ S = "note is a thing`nnote has path `"DIR/n.txt`"`nwrite `"via path`" to note`nread note into t`nsay t" }
        )) {
            if ($case.W -and -not $script:OnWindows) { continue }  # read-only: Windows semantics
            $files = if ($case.F) { $case.F } else { @{} }
            [void](Assert-FileCase -Source $case.S -Files $files)
        }
    }

    Test-Otter 'locked files fail with otter.ps1''s exact text' {
        if (Skip-UnlessWindows 'file locks: Windows only') { return }
        foreach ($s in @(
            "read `"DIR/l.txt`" into t",
            "write `"x`" to `"DIR/l.txt`"",
            "write `"x`" to `"DIR/l.txt`" atomically",
            "append `"x`" to `"DIR/l.txt`"",
            "delete file `"DIR/l.txt`"",
            "copy `"DIR/l.txt`" to `"DIR/x.txt`"",
            "copy `"DIR/ok.txt`" to `"DIR/l.txt`"",
            "move `"DIR/l.txt`" to `"DIR/x.txt`"",
            "move `"DIR/ok.txt`" to `"DIR/l.txt`""
        )) {
            $r = Assert-FileCase -Source "say `"start`"`n$s" -Files @{ 'l.txt' = '<locked>held'; 'ok.txt' = 'free' }
            Assert-AreEqual -Expected 3 -Actual $r.ExitCode
        }
    }

    Test-Otter 'an edited file goes through otter.ps1, then runs fast again' {
        $path = New-Program -Source 'say "one"'
        [void](Invoke-ViaPs1 -Path $path)
        [System.IO.File]::WriteAllText($path, 'say "two"', [System.Text.UTF8Encoding]::new($false))
        $edited = Invoke-ViaExe -Arguments @('run', $path)
        Assert-True ($edited.Trace -match 'the file changed') "expected the changed-file fallback: $($edited.Trace)"
        Assert-AreEqual -Expected 'two' -Actual $edited.Text.Trim()
        $again = Invoke-ViaExe -Arguments @('run', $path)
        Assert-True ($again.Trace -match 'fast start') "expected the fast path after recompiling: $($again.Trace)"
        Assert-AreEqual -Expected 'two' -Actual $again.Text.Trim()
    }

    Test-Otter 'JSON runs on the fast path with otter.ps1''s exact text, both ways' {
        if (-not $script:OnWindows) {
            # PowerShell 7: JSON needs PowerShell, so such a program never takes the fast path.
            $path = New-Program -Source "convert 5 to json into j`nsay j"
            $reference = Invoke-ViaPs1 -Path $path
            $r = Invoke-ViaExe -Arguments @('run', $path)
            Assert-True ($r.Trace -match 'no fast-start entry') "a JSON program took the fast path on PowerShell 7: $($r.Trace)"
            Assert-AreEqual -Expected $reference.Stdout -Actual $r.Stdout
            return
        }
        $r = Assert-FileCase -Source @'
person has name "Ada <&>", age 36
skills are
    "math"
    "engines"
.
langs of person is skills
convert person to json into text
say text
write text to "DIR/p.json"
read json from "DIR/p.json" into back
say name of back age of back langs of back
convert "[1, 2.5, true, null, \"x\", {\"a\": {\"b\": []}}]" from json into mixed
say mixed length of mixed
d is date from "2024-01-31"
convert d to json into dj
say dj
convert 42 to json into numText
say numText
'@
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        foreach ($bad in @("convert `"{bad`" from json into x", "convert `"{\`"a\`":1,\`"A\`":2}`" from json into x", "convert `"`" from json into x", "read json from `"DIR/nope.json`" into x")) {
            $e = Assert-FileCase -Source "say `"start`"`n$bad"
            Assert-AreEqual -Expected 3 -Actual $e.ExitCode
        }
    }

    Test-Otter 'randomized JSON parity with the interpreter (tools/Test-OtterJsonParity.ps1, 300 values)' {
        if (Skip-UnlessWindows 'JSON on the fast path is Windows only') { return }
        $output = & $script:PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:RepoRoot 'tools\Test-OtterJsonParity.ps1') -Count 300 2>&1
        Assert-AreEqual -Expected 0 -Actual $LASTEXITCODE
        Assert-True (($output -join ' ') -match 'all identical') "JSON parity: $($output -join ' | ')"
    }

    Test-Otter 'a program with use imports never takes the fast path' {
        [void](New-Program -Source "to helper`n    say `"from helper`"`n." -Name 'helper.ot')
        $main = New-Program -Source "use `"helper.ot`"`nhelper"
        [void](Invoke-ViaPs1 -Path $main)
        $r = Invoke-ViaExe -Arguments @('run', $main)
        Assert-True ($r.Trace -match 'no fast-start entry') "a program with imports took the fast path: $($r.Trace)"
        Assert-AreEqual -Expected 'from helper' -Actual $r.Text.Trim()
    }

    Test-Otter 'OTTER_ENGINE=interpreter, other commands and developer flags go to otter.ps1' {
        $path = New-Program -Source 'say "hi"'
        [void](Invoke-ViaPs1 -Path $path)
        $r = Invoke-ViaExe -Arguments @('run', $path) -Environment @{ OTTER_ENGINE = 'interpreter' }
        Assert-False ($r.Trace -match 'fast start') "trace: $($r.Trace)"
        Assert-AreEqual -Expected 'hi' -Actual $r.Text.Trim()
        $check = Invoke-ViaExe -Arguments @('check', $path)
        Assert-False ($check.Trace -match 'fast start') "trace: $($check.Trace)"
        Assert-AreEqual -Expected 0 -Actual $check.ExitCode
        $flag = Invoke-ViaExe -Arguments @('run', $path, '-DebugAst')
        Assert-False ($flag.Trace -match 'fast start') "trace: $($flag.Trace)"
        $plain = Invoke-ViaExe -Arguments @($path)
        Assert-True ($plain.Trace -match 'fast start') "otter file.ot should take the fast path: $($plain.Trace)"
    }

    Test-Otter 'an edited Otter installation never runs an old compiled program' {
        $path = New-Program -Source 'say "hi"'
        [void](Invoke-ViaPs1 -Path $path)
        $module = Join-Path $script:Install (Join-Path 'src' 'Otter.Interpreter.psm1')
        [System.IO.File]::SetLastWriteTimeUtc($module, [DateTime]::UtcNow.AddMinutes(1))
        $r = Invoke-ViaExe -Arguments @('run', $path)
        Assert-True ($r.Trace -match 'Otter itself changed') "expected the toolchain fallback: $($r.Trace)"
        Assert-AreEqual -Expected 'hi' -Actual $r.Text.Trim()
    }

    Test-Otter 'a missing file is otter.ps1''s message and exit code' {
        $missing = Join-Path $script:Work 'nope.ot'
        $viaPs1 = Invoke-ViaPs1 -Path $missing
        $viaExe = Invoke-ViaExe -Arguments @('run', $missing)
        Assert-AreEqual -Expected $viaPs1.ExitCode -Actual $viaExe.ExitCode
        Assert-AreEqual -Expected $viaPs1.Text -Actual $viaExe.Text
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
