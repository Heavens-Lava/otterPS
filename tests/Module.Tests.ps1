using module ..\Otter.Contract.psm1

# tests/Module.Tests.ps1
# Shared Otter Module & Source Resolution Test Suite (D60)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Module.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force

Write-Output 'Otter Module Resolver (D60)'

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    # Test 1: Basic use statement resolution
    $fileB = Join-Path $tempDir 'b.ot'
    $fileA = Join-Path $tempDir 'a.ot'

    @'
say "hello from B"
'@ | Set-Content -LiteralPath $fileB -Encoding UTF8

    @'
use "b.ot"
say "hello from A"
'@ | Set-Content -LiteralPath $fileA -Encoding UTF8

    $resolved = Resolve-OtterModuleSource -FilePath $fileA
    if ($resolved.LoadedFiles.Count -ne 2) {
        throw "Expected 2 loaded files, got $($resolved.LoadedFiles.Count)"
    }
    if ($resolved.CombinedSource -notmatch 'hello from B' -or $resolved.CombinedSource -notmatch 'hello from A') {
        throw "Combined source missing content from imported module: $($resolved.CombinedSource)"
    }
    Write-Output '  pass  basic use "..." resolves and combines source'

    # Test 2: Source map tracks line origins back to original files
    # Line 1 of a.ot was use "b.ot", which expanded to:
    # # --- imported from b.ot --- (line 1)
    # say "hello from B" (line 2)
    # # --- end import b.ot --- (line 3)
    # say "hello from A" (line 4)
    $originB = $resolved.FindOrigin(2)
    if ($null -eq $originB -or $originB.LocalLine -ne 1 -or ([System.IO.Path]::GetFileName($originB.FilePath) -ne 'b.ot')) {
        throw "SourceMap failed to map line 2 to b.ot:1. Got $($originB.FilePath):$($originB.LocalLine)"
    }

    $originA = $resolved.FindOrigin(4)
    if ($null -eq $originA -or $originA.LocalLine -ne 2 -or ([System.IO.Path]::GetFileName($originA.FilePath) -ne 'a.ot')) {
        throw "SourceMap failed to map line 4 to a.ot:2. Got $($originA.FilePath):$($originA.LocalLine)"
    }
    Write-Output '  pass  source map tracks origin file and local line number for diagnostics'

    # Test 3: Diamond dependency / DAG does not duplicate imports
    $fileBase = Join-Path $tempDir 'base.ot'
    $fileMid1 = Join-Path $tempDir 'mid1.ot'
    $fileMid2 = Join-Path $tempDir 'mid2.ot'
    $fileTop = Join-Path $tempDir 'top.ot'

    @'
baseVal is 10
'@ | Set-Content -LiteralPath $fileBase -Encoding UTF8

    @'
use "base.ot"
mid1Val is 20
'@ | Set-Content -LiteralPath $fileMid1 -Encoding UTF8

    @'
use "base.ot"
mid2Val is 30
'@ | Set-Content -LiteralPath $fileMid2 -Encoding UTF8

    @'
use "mid1.ot"
use "mid2.ot"
topVal is 40
'@ | Set-Content -LiteralPath $fileTop -Encoding UTF8

    $resolvedTop = Resolve-OtterModuleSource -FilePath $fileTop
    $matchesBase = [regex]::Matches($resolvedTop.CombinedSource, 'baseVal is 10')
    if ($matchesBase.Count -ne 1) {
        throw "Expected baseVal to be imported exactly once in diamond dependency, got $($matchesBase.Count)"
    }
    Write-Output '  pass  diamond dependency prevents duplicate module inclusion'

    # Test 4: Circular import detection throws clean diagnostic
    $fileCycle1 = Join-Path $tempDir 'c1.ot'
    $fileCycle2 = Join-Path $tempDir 'c2.ot'

    @'
use "c2.ot"
'@ | Set-Content -LiteralPath $fileCycle1 -Encoding UTF8

    @'
use "c1.ot"
'@ | Set-Content -LiteralPath $fileCycle2 -Encoding UTF8

    $caughtCycle = $false
    try {
        Resolve-OtterModuleSource -FilePath $fileCycle1 | Out-Null
    } catch [OtterError] {
        if ($_.Exception.Message -match 'Circular import detected') {
            $caughtCycle = $true
        }
    }
    if (-not $caughtCycle) {
        throw "Expected OtterError on circular import."
    }
    Write-Output '  pass  circular import throws diagnostic identifying the cycle chain'

    # Test 5: Missing imported file throws clean diagnostic
    $fileBad = Join-Path $tempDir 'bad.ot'
    @'
use "nonexistent.ot"
'@ | Set-Content -LiteralPath $fileBad -Encoding UTF8

    $caughtMissing = $false
    try {
        Resolve-OtterModuleSource -FilePath $fileBad | Out-Null
    } catch [OtterError] {
        if ($_.Exception.Message -match 'Cannot find imported Otter file') {
            $caughtMissing = $true
        }
    }
    if (-not $caughtMissing) {
        throw "Expected OtterError on missing imported file."
    }
    Write-Output '  pass  missing imported file throws clean diagnostic with path and line'

    # Test 6: Combined source tokens and parses successfully into AST
    $tokens = ConvertTo-OtterTokens -Source ($resolvedTop.CombinedSource + "`n")
    $ast = ConvertTo-OtterAst -Tokens $tokens
    if ($null -eq $ast -or $ast.Statements.Length -eq 0) {
        throw "Expected parsed AST statements."
    }
    Write-Output '  pass  resolved multi-file source produces valid AST'

} finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
