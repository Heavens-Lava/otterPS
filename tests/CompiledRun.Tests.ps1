# CompiledRun.Tests.ps1
#
# `otter run` uses the compiled engine (src/Otter.Compiler.Native.psm1) for a
# program it can compile and the interpreter for everything else. These tests
# go through otter.ps1, the entry point a user runs, and check that the choice
# is invisible: the same output, errors and exit codes either way.
#
# This file must stay portable: no powershell.exe, cmd or $env:TEMP.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Compiled engine through otter run' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:HostExe = (Get-Process -Id $PID).Path
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_compiled_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null

# Runs source through otter.ps1 with OTTER_ENGINE set ('' = the default) and
# OTTER_ENGINE_TRACE on; the trace line is split from the program's output.
function Invoke-OtterEngine {
    param([string]$Source, [string]$Engine = '', [string[]]$Arguments = @(), [string]$InputText = $null)
    $path = Join-Path $script:Tmp ('p' + [Guid]::NewGuid().ToString('N') + '.ot')
    [System.IO.File]::WriteAllText($path, $Source, [System.Text.UTF8Encoding]::new($false))
    $saved = @{ Engine = $env:OTTER_ENGINE; Trace = $env:OTTER_ENGINE_TRACE }
    try {
        $env:OTTER_ENGINE = $Engine
        $env:OTTER_ENGINE_TRACE = '1'
        if ($null -ne $InputText) { $output = $InputText | & $script:HostExe -NoProfile -File $script:OtterPs1 run $path @Arguments 2>&1 }
        else { $output = & $script:HostExe -NoProfile -File $script:OtterPs1 run $path @Arguments 2>&1 }
        $code = $LASTEXITCODE
    }
    finally { $env:OTTER_ENGINE = $saved.Engine; $env:OTTER_ENGINE_TRACE = $saved.Trace }
    $lines = @($output | ForEach-Object { $_.ToString() })
    return [pscustomobject]@{
        ExitCode = $code
        Engine = (@($lines | Where-Object { $_ -like 'otter engine:*' }) -join ' ')
        Lines = @($lines | Where-Object { $_ -notlike 'otter engine:*' -and $_ -ne '' })
    }
}

# The default run and a forced-interpreter run of the same program agree.
function Assert-SameAsInterpreter {
    param([string]$Source, [string]$ExpectEngine = 'compiled', [string[]]$Arguments = @(), [string]$InputText = $null)
    $default = Invoke-OtterEngine -Source $Source -Arguments $Arguments -InputText $InputText
    $interpreted = Invoke-OtterEngine -Source $Source -Engine 'interpreter' -Arguments $Arguments -InputText $InputText
    Assert-True ($default.Engine -like "otter engine: $ExpectEngine*") "expected the $ExpectEngine engine, trace was: $($default.Engine)"
    Assert-AreEqual -Expected $interpreted.ExitCode -Actual $default.ExitCode
    Assert-AreEqual -Expected ($interpreted.Lines -join "`n") -Actual ($default.Lines -join "`n")
    return $default
}

try {
    Test-Otter 'a loop program runs on the compiled engine with the interpreter''s output' {
        $r = Assert-SameAsInterpreter -Source "total is 0`ncount from 1 to 2000 as n`n    total is total plus n`n.`nsay `"total`" total"
        Assert-AreEqual -Expected 'total 2001000' -Actual ($r.Lines -join '')
    }

    Test-Otter 'functions, lists, things and text match the interpreter' {
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
say numbers
square 7 make s
say s
person has name "Ada", age 36
say name of person "is" age of person
say uppercase of "otter"
'@
        [void](Assert-SameAsInterpreter -Source $source)
    }

    Test-Otter 'a runtime error has the interpreter''s message, line and exit code' {
        $r = Assert-SameAsInterpreter -Source "say `"before`"`nx is 1 / 0"
        Assert-AreEqual -Expected 3 -Actual $r.ExitCode
        Assert-True (($r.Lines -join "`n").Contains('I cannot divide by zero.')) "missing the Otter message: $($r.Lines -join ' | ')"
    }

    Test-Otter 'arguments reach a compiled program as text' {
        $r = Assert-SameAsInterpreter -Source "say arguments`nsay length of arguments" -Arguments @('one', 'two words')
        Assert-AreEqual -Expected "one, two words`n2" -Actual ($r.Lines -join "`n")
    }

    Test-Otter 'set random seed gives the same numbers on both engines' {
        $source = "set random seed to 42`ncount from 1 to 5 as n`n    random number from 1 to 100 into r`n    say r`n.`ncolors are`n    `"red`"`n    `"green`"`n    `"blue`"`n.`nrandom item from colors into c`nsay c"
        [void](Assert-SameAsInterpreter -Source $source)
    }

    Test-Otter 'a program with a feature the compiled engine lacks runs on the interpreter' {
        $r = Assert-SameAsInterpreter -Source "ask `"Name?`" and call it name`nsay `"Hi`" name" -ExpectEngine 'interpreter' -InputText 'Jeff'
        Assert-True (($r.Lines -join ' ').Contains('Hi Jeff')) "ask fallback output: $($r.Lines -join ' | ')"
    }

    Test-Otter 'OTTER_ENGINE=interpreter turns the compiled engine off' {
        $r = Invoke-OtterEngine -Source 'say "hi"' -Engine 'interpreter'
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-AreEqual -Expected '' -Actual $r.Engine
        Assert-AreEqual -Expected 'hi' -Actual ($r.Lines -join '')
    }

    Test-Otter 'OTTER_ENGINE=compiled refuses to fall back, with an Otter message' {
        $r = Invoke-OtterEngine -Source "ask `"Name?`" and call it name" -Engine 'compiled' -InputText 'x'
        Assert-AreEqual -Expected 3 -Actual $r.ExitCode
        Assert-True (($r.Lines -join ' ').Contains('cannot be compiled')) "forced compiled message: $($r.Lines -join ' | ')"
        Assert-False (($r.Lines -join ' ') -match 'at line:|CategoryInfo|Exception') "a raw PowerShell error leaked: $($r.Lines -join ' | ')"
    }

    Test-Otter 'an unwritable cache folder falls back to the interpreter (read-only installs)' {
        # A file where the cache folder should go: the cache cannot be made.
        $blocker = Join-Path $script:Tmp 'cache-blocker'
        [System.IO.File]::WriteAllText($blocker, 'not a folder')
        $saved = $env:OTTER_COMPILED_CACHE
        try {
            $env:OTTER_COMPILED_CACHE = Join-Path $blocker 'compiled'
            $r = Invoke-OtterEngine -Source 'say "still runs"'
        }
        finally { $env:OTTER_COMPILED_CACHE = $saved }
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-True ($r.Engine -like 'otter engine: interpreter*') "expected the interpreter, trace was: $($r.Engine)"
        Assert-AreEqual -Expected 'still runs' -Actual ($r.Lines -join '')
    }

    Test-Otter 'otter check never runs the program on either engine' {
        $marker = Join-Path $script:Tmp 'ran.txt'
        $r = Invoke-OtterEngine -Source "write `"x`" to `"$($marker.Replace('\', '\\'))`""
        Remove-Item -LiteralPath $marker -ErrorAction SilentlyContinue
        $path = Join-Path $script:Tmp 'check.ot'
        [System.IO.File]::WriteAllText($path, "write `"x`" to `"$($marker.Replace('\', '\\'))`"", [System.Text.UTF8Encoding]::new($false))
        $output = & $script:HostExe -NoProfile -File $script:OtterPs1 check $path 2>&1
        Assert-AreEqual -Expected 0 -Actual $LASTEXITCODE
        Assert-False (Test-Path -LiteralPath $marker) "otter check wrote the file: $output"
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
