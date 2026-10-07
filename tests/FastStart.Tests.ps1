# FastStart.Tests.ps1
#
# otter.exe (distribution/launcher/OtterLauncher.cs) runs a program that
# otter.ps1 already compiled straight from the cache, without starting
# PowerShell. These tests run each program through otter.ps1 first (which
# compiles it and writes the fast-start entry), then through otter.exe, and
# require the same standard-output bytes and exit code - and that every case
# the fast path must not handle goes to otter.ps1.
#
# Windows only: the launcher is a .NET Framework program. The tests use a copy
# of Otter in a temporary folder, so editing "Otter itself" cannot touch the
# repository.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Fast start (otter.exe)' -ForegroundColor Cyan

if (($PSVersionTable.PSVersion.Major -ge 6) -and -not $IsWindows) {
    Write-Host '  skip  otter.exe is the Windows launcher' -ForegroundColor DarkYellow
    Complete-OtterTests
    return
}

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_fast_' + [Guid]::NewGuid().ToString('N'))
$script:Install = Join-Path $script:Tmp 'otter'
$script:Work = Join-Path $script:Tmp 'work'
$script:Cache = Join-Path $script:Tmp 'cache'
New-Item -ItemType Directory -Path $script:Install, $script:Work, $script:Cache -Force | Out-Null
foreach ($item in @('otter.ps1', 'otter.cmd', 'Otter.Contract.psm1', 'VERSION')) {
    Copy-Item -LiteralPath (Join-Path $script:RepoRoot $item) -Destination $script:Install
}
Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'src') -Destination $script:Install -Recurse
& (Join-Path $script:RepoRoot 'tools\Build-OtterLauncher.ps1') -Destination $script:Install | Out-Null
$script:Exe = Join-Path $script:Install 'otter.exe'
$script:Ps1 = Join-Path $script:Install 'otter.ps1'
$script:PowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

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
    return Invoke-Captured -FileName $script:Exe -Arguments $Arguments -Environment $Environment }

# The program runs through otter.ps1 (compiling it), then through otter.exe on
# the fast path; both must produce the same bytes and exit code.
function Assert-FastMatches {
    param([string]$Source, [string[]]$ProgramArgs = @())
    $path = New-Program -Source $Source
    $reference = Invoke-ViaPs1 -Path $path -ProgramArgs $ProgramArgs
    Assert-True ($reference.Trace -match 'otter engine: compiled') "otter.ps1 did not compile it: $($reference.Trace)"
    $fast = Invoke-ViaExe -Arguments (@('run', $path) + $ProgramArgs)
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

    Test-Otter 'programs that need PowerShell (files, JSON, imports, ask) never take the fast path' {
        $file = (Join-Path $script:Work 'note.txt').Replace('\', '\\')
        foreach ($source in @("write `"x`" to `"$file`"`nread `"$file`" into t`nsay t", "convert 5 to json into j`nsay j")) {
            $path = New-Program -Source $source
            [void](Invoke-ViaPs1 -Path $path)
            $r = Invoke-ViaExe -Arguments @('run', $path)
            Assert-True ($r.Trace -match 'no fast-start entry') "a library program took the fast path: $($r.Trace)"
            Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        }
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
        Assert-True ($r.Trace -match 'OTTER_ENGINE=interpreter') "trace: $($r.Trace)"
        Assert-AreEqual -Expected 'hi' -Actual $r.Text.Trim()
        $check = Invoke-ViaExe -Arguments @('check', $path)
        Assert-True ($check.Trace -match 'not a run of a .ot file') "trace: $($check.Trace)"
        Assert-AreEqual -Expected 0 -Actual $check.ExitCode
        $flag = Invoke-ViaExe -Arguments @('run', $path, '-DebugAst')
        Assert-True ($flag.Trace -match 'developer flag') "trace: $($flag.Trace)"
        $plain = Invoke-ViaExe -Arguments @($path)
        Assert-True ($plain.Trace -match 'fast start') "otter file.ot should take the fast path: $($plain.Trace)"
    }

    Test-Otter 'an edited Otter installation never runs an old compiled program' {
        $path = New-Program -Source 'say "hi"'
        [void](Invoke-ViaPs1 -Path $path)
        $module = Join-Path $script:Install 'src\Otter.Interpreter.psm1'
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
