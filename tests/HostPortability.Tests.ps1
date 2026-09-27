using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Interpreter.psm1

# HostPortability.Tests.ps1
#
# Otter values must be the same on Windows PowerShell 5.1 and PowerShell 7.
#
# The defect this guards against (D120, found by the PowerShell 7 CI matrix):
# a PowerShell function that emits ONE value with `Write-Output -NoEnumerate`
# hands its caller that value itself on 5.1, but on PowerShell 7 (7.6.6
# measured) the caller receives a List[object] containing it. The interpreter
# used that form at every value boundary, so on PowerShell 7 a thing arrived
# as "a list", a returned number as a one-item list, and "gone" as a list
# holding nothing. The runtime now uses `return , value`, which behaves the
# same on both hosts.
#
# This file must itself stay portable: no powershell.exe, cmd or $env:TEMP.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Host portability (Windows PowerShell 5.1 and PowerShell 7)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:HostExe = (Get-Process -Id $PID).Path
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_portability_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null

function Invoke-OtterFileRun {
    param([string]$Source)
    $path = Join-Path $script:Tmp ('p' + [Guid]::NewGuid().ToString('N') + '.ot')
    [System.IO.File]::WriteAllText($path, $Source, [System.Text.UTF8Encoding]::new($false))
    $output = & $script:HostExe -NoProfile -File $script:OtterPs1 run $path 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = @($output | ForEach-Object { $_.ToString() } | Where-Object { $_ -ne '' }) }
}

# Evaluates one Otter expression in a fresh environment and returns the raw runtime value.
function Get-OtterExpressionValue {
    param([string]$Setup, [string]$Expression)
    $source = $Setup + "`nresultValue is " + $Expression + "`n"
    $ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source)
    $environment = New-OtterEnvironment
    Set-OtterOutputWriter -Writer { param($t) }
    try { Invoke-OtterProgram -Program $ast -Environment $environment } finally { Set-OtterOutputWriter -Writer $null }
    return , $environment.Get('resultValue')
}

function Get-TypeLabel { param($Value) if ($null -eq $Value) { return 'null' }; return $Value.GetType().Name }

try {
    Test-Otter "minimal reproducer: reading a property of a thing (host: PowerShell $($PSVersionTable.PSVersion))" {
        $r = Invoke-OtterFileRun "person has name `"Jeff`"`nsay name of person`n"
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('Jeff') -Actual $r.Lines
    }

    Test-Otter 'minimal reproducer: a returned number is still a number' {
        $r = Invoke-OtterFileRun "to ten`n    return 10`n.`n`nanswer is ten`nsay answer plus 1`n"
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('11') -Actual $r.Lines
    }

    Test-Otter 'find that matches nothing gives gone, not a list holding nothing' {
        $r = Invoke-OtterFileRun "games are`n    `"Zelda`"`n    `"Mario`"`n.`nfind game in games where game starts with `"Q`" into found`nif found is gone`n    say `"none`"`n.`n"
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('none') -Actual $r.Lines
    }

    $setup = @'
thing1 has color "blue"
many are
    1
    2
single are
    "only"
nothing are empty
nested are
    many
to identity value
    return value
.
'@
    $cases = @(
        @{ Name = 'a thing read from a variable'; Expr = 'thing1'; Type = 'OtterObject' }
        @{ Name = 'a thing returned from a function'; Expr = 'identity thing1'; Type = 'OtterObject' }
        @{ Name = 'a property read'; Expr = 'color of thing1'; Type = 'String' }
        @{ Name = 'a number returned from a function'; Expr = 'identity 10'; Type = 'Double' }
        @{ Name = 'a two-item list'; Expr = 'many'; Type = 'List`1'; Count = 2 }
        @{ Name = 'a two-item list returned from a function'; Expr = 'identity many'; Type = 'List`1'; Count = 2 }
        @{ Name = 'a one-item list (must not collapse to its item)'; Expr = 'single'; Type = 'List`1'; Count = 1 }
        @{ Name = 'an empty list'; Expr = 'nothing'; Type = 'List`1'; Count = 0 }
        @{ Name = 'a nested list (must not flatten)'; Expr = 'nested'; Type = 'List`1'; Count = 1 }
        @{ Name = 'first of a list'; Expr = 'first of many'; Type = 'Int32' }
        @{ Name = 'first of an empty list is gone'; Expr = 'first of nothing'; Type = 'null' }
    )
    foreach ($case in $cases) {
        $caseName = $case.Name; $caseExpr = $case.Expr; $caseType = $case.Type; $caseCount = $case['Count']
        Test-Otter "value boundary keeps its type: $caseName" ({
            $value = Get-OtterExpressionValue -Setup $setup -Expression $caseExpr
            $label = Get-TypeLabel $value
            if ($caseType -eq 'Int32') {
                Assert-True ($label -in @('Int32', 'Double')) "expected a plain number, got $label"
            } else {
                Assert-AreEqual -Expected $caseType -Actual $label
            }
            if ($null -ne $caseCount) { Assert-AreEqual -Expected $caseCount -Actual $value.Count }
        }.GetNewClosure())
    }

    Test-Otter 'an atomic write to a read-only file fails the same way on every host' {
        # Windows refuses to replace a read-only file; Linux/macOS rename would allow it.
        $target = Join-Path $script:Tmp 'locked.txt'
        [System.IO.File]::WriteAllText($target, 'original')
        $info = [System.IO.FileInfo]::new($target); $info.IsReadOnly = $true
        try {
            $otterPath = $target.Replace([string][char]92, '/')
            $r = Invoke-OtterFileRun "write `"changed`" to `"$otterPath`" atomically`nsay `"should not print`"`n"
            Assert-AreEqual -Expected 3 -Actual $r.ExitCode
            Assert-True (($r.Lines -join ' ') -match 'The file is read-only') "expected the read-only diagnostic, got: $($r.Lines -join ' | ')"
        } finally { $info.IsReadOnly = $false }
        Assert-AreEqual -Expected 'original' -Actual ([System.IO.File]::ReadAllText($target))
    }

    Test-Otter 'published artifact names are sanitized identically on every host' {
        Import-Module (Join-Path $script:RepoRoot 'src/Otter.Project.psm1') -Force
        Assert-AreEqual -Expected 'My-Special-App-2026' -Actual (Get-OtterSafeFileName 'My-Special:App-*2026*')
        Assert-AreEqual -Expected 'a-b-c-d' -Actual (Get-OtterSafeFileName ('a/b' + [char]92 + 'c<d>'))
    }

    Test-Otter 'the runtime modules never return a value with Write-Output -NoEnumerate' {
        $offenders = @()
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'src') -Filter '*.psm1') {
            $lineNo = 0
            foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
                $lineNo++
                if ($line.TrimStart().StartsWith('#')) { continue }
                if ($line -match 'Write-Output\s+-NoEnumerate') { $offenders += "$($file.Name):$lineNo" }
            }
        }
        Assert-True ($offenders.Count -eq 0) "Write-Output -NoEnumerate wraps values in a List on PowerShell 7; use 'return , value'. Found at: $($offenders -join ', ')"
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
