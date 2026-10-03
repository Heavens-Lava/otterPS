# Profiler.Tests.ps1
#
# `otter profile <file.ot>` through the real production entry point, plus the
# return-statement fast path that profiling first pointed at (a `return` written
# directly in a function body no longer throws an exception to end the call).

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Profiler and return fast path' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_profiler_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null

function Invoke-OtterCommandText {
    param([string[]]$Arguments)
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:OtterPs1 @Arguments 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (($output | ForEach-Object { $_.ToString() }) -join "`n") }
}

function New-OtterTestFile {
    param([string]$Name, [string]$Source)
    $path = Join-Path $script:Tmp $Name
    [System.IO.File]::WriteAllText($path, $Source, [System.Text.UTF8Encoding]::new($false))
    return $path
}

try {
    $program = New-OtterTestFile 'work.ot' @'
to square number
    number times number make answer
    return answer

to sumSquares limit
    total is 0
    count from 1 to limit as i
        square i make sq
        total is total plus sq
    .
    return total

sumSquares 20 make result
say "Sum of squares:" result
'@

    Test-Otter 'otter profile runs the program normally and then prints a report' {
        $r = Invoke-OtterCommandText @('profile', $program)
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-True ($r.Text -match 'Sum of squares: 2870') 'the program output is still printed first'
        Assert-True ($r.Text -match 'Otter profile') 'report header'
        Assert-True ($r.Text -match 'statements run in') 'statement total'
    }

    Test-Otter 'the report lists functions with their real call counts' {
        $r = Invoke-OtterCommandText @('profile', $program)
        Assert-True ($r.Text -match 'square\s+20\s') 'square was called 20 times'
        Assert-True ($r.Text -match 'sumSquares\s+1\s') 'sumSquares was called once'
    }

    Test-Otter 'the report names hottest lines with their Otter source text' {
        $r = Invoke-OtterCommandText @('profile', $program)
        Assert-True ($r.Text -match 'Hottest lines') 'hot lines section'
        Assert-True ($r.Text -match 'number times number make answer') 'source text of a hot line'
    }

    Test-Otter 'the report never shows PowerShell or .NET internals' {
        $r = Invoke-OtterCommandText @('profile', $program)
        Assert-False ($r.Text -match 'Invoke-Otter|System\.|ScriptBlock|\.psm1') 'Otter terms only'
    }

    Test-Otter 'the profile report includes CPU time, utilization percentage, and user/kernel breakdown' {
        $r = Invoke-OtterCommandText @('profile', $program)
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-True ($r.Text -match 'CPU:\s+[0-9.]+\s+ms') 'CPU time in report summary'
        Assert-True ($r.Text -match '[0-9.]+\s*%\s+utilization') 'CPU utilization in report summary'
        Assert-True ($r.Text -match 'user:\s+[0-9.]+\s+ms') 'User processor time in report summary'
        Assert-True ($r.Text -match 'kernel:\s+[0-9.]+\s+ms') 'Kernel processor time in report summary'
        Assert-True ($r.Text -match 'cpu ms') 'cpu ms column header present'
    }

    Test-Otter 'the profile report includes memory usage, allocations, and GC statistics' {
        $r = Invoke-OtterCommandText @('profile', $program)
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-True ($r.Text -match 'Memory:\s+managed peak') 'Managed memory peak in report summary'
        Assert-True ($r.Text -match 'working set peak') 'Working set peak in report summary'
        Assert-True ($r.Text -match 'allocated:\s+[0-9.]+\s+[KMG]?B') 'Allocated memory in report summary'
        Assert-True ($r.Text -match 'GC:\s+[0-9]+\s+gen0') 'GC statistics in report summary'
        Assert-True ($r.Text -match 'alloc') 'alloc column header present'
    }

    Test-Otter 'a program that fails still prints the profile and exits with the runtime-error code' {
        $bad = New-OtterTestFile 'bad.ot' "say `"before`"`nsay missingName`n"
        $r = Invoke-OtterCommandText @('profile', $bad)
        Assert-AreEqual -Expected 3 -Actual $r.ExitCode
        Assert-True ($r.Text -match 'before') 'output before the error'
        Assert-True ($r.Text -match 'Otter profile') 'report printed even on failure'
    }

    Test-Otter 'otter profile with no file explains how to use it' {
        $r = Invoke-OtterCommandText @('profile')
        Assert-True ($r.Text -match 'Usage: otter profile') 'usage message'
        Assert-False ($r.ExitCode -eq 0) 'non-zero exit'
    }

    Test-Otter 'a normal otter run never loads the profiler or prints a report' {
        $r = Invoke-OtterCommandText @('run', $program)
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-False ($r.Text -match 'Otter profile') 'no report on a normal run'
    }

    # --- return keeps its meaning after the fast path ---------------

    $returns = New-OtterTestFile 'returns.ot' @'
to direct value
    return value plus 1

to nested value
    if value is greater than 5
        return "big"
    .
    return "small"

to inloop limit
    count from 1 to limit as i
        if i is 3
            return i
        .
    .
    return 0

to noValue
    say "in noValue"

to fact n
    if n is less than 2
        return 1
    .
    n minus 1 make smaller
    fact smaller make rest
    return n times rest

to makeList
    items are
        1
        2
        3
    .
    return items

direct 4 make r1
nested 9 make r2
nested 2 make r3
inloop 10 make r4
noValue make r5
fact 6 make r6
makeList make r7
say r1 r2 r3 r4 r6
say r7
'@
    Test-Otter 'return behaves the same directly, nested, in loops, recursively, and with lists' {
        $r = Invoke-OtterCommandText @('run', $returns)
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        $lines = @($r.Text -split "`r?`n" | Where-Object { $_ -ne '' })
        Assert-True ($lines -contains 'in noValue') 'a function with no return still runs its body'
        Assert-True ($lines -contains '5 big small 3 720') "direct/nested/in-loop/recursive results, got: $($lines -join ' | ')"
        Assert-True ($lines -contains '1, 2, 3') 'a returned list stays a list'
    }

    Test-Otter 'return at the top level is still the clean "nothing to stop" error, not a crash' {
        $top = New-OtterTestFile 'top.ot' "say `"a`"`nreturn 1`n"
        $r = Invoke-OtterCommandText @('run', $top)
        Assert-False ($r.ExitCode -eq 0) 'fails'
        Assert-False ($r.Text -match 'bug in Otter') 'not reported as an interpreter bug'
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
