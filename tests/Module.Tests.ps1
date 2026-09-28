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

    # Test 7: Path normalization: ./utils.ot vs sub/../utils.ot deduplication
    $subDir = Join-Path $tempDir 'sub'
    New-Item -ItemType Directory -Path $subDir -Force | Out-Null
    $fileUtils = Join-Path $tempDir 'utils.ot'
    $fileNormA = Join-Path $tempDir 'normA.ot'
    $fileNormB = Join-Path $tempDir 'normB.ot'
    $fileNormMain = Join-Path $tempDir 'normMain.ot'

    @'
utilFlag is true
'@ | Set-Content -LiteralPath $fileUtils -Encoding UTF8

    @'
use "./utils.ot"
'@ | Set-Content -LiteralPath $fileNormA -Encoding UTF8

    @'
use "sub/../utils.ot"
'@ | Set-Content -LiteralPath $fileNormB -Encoding UTF8

    @'
use "normA.ot"
use "normB.ot"
say utilFlag
'@ | Set-Content -LiteralPath $fileNormMain -Encoding UTF8

    $resolvedNorm = Resolve-OtterModuleSource -FilePath $fileNormMain
    $matchesUtil = [regex]::Matches($resolvedNorm.CombinedSource, 'utilFlag is true')
    if ($matchesUtil.Count -ne 1) {
        throw "Expected utilFlag to be imported exactly once despite relative path variations, got $($matchesUtil.Count)"
    }
    Write-Output '  pass  path normalization resolves ./utils.ot and sub/../utils.ot to the same module'

    # Test 8: Module paths are case-sensitive on every host (M1).
    # utils.ot exists (from Test 7). A `use` spelled with different case must
    # be rejected even on Windows/macOS, whose file systems would accept it.
    $fileCaseWrong = Join-Path $tempDir 'caseWrong.ot'
    @'
use "Utils.ot"
'@ | Set-Content -LiteralPath $fileCaseWrong -Encoding UTF8
    $caseError = $null
    try { Resolve-OtterModuleSource -FilePath $fileCaseWrong | Out-Null } catch { $caseError = $_.Exception }
    if ($null -eq $caseError) { throw 'Test 8 failed: use "Utils.ot" must not resolve a file named utils.ot' }
    if ($caseError.Message -notmatch 'The file is named "utils.ot", but this use says "Utils.ot"') { throw "Test 8 failed: unexpected diagnostic: $($caseError.Message)" }
    if ($caseError.Line -ne 1) { throw "Test 8 failed: expected the error on line 1, got $($caseError.Line)" }

    $fileCaseRight = Join-Path $tempDir 'caseRight.ot'
    @'
use "utils.ot"
'@ | Set-Content -LiteralPath $fileCaseRight -Encoding UTF8
    $resolvedCase = Resolve-OtterModuleSource -FilePath $fileCaseRight
    if ([regex]::Matches($resolvedCase.CombinedSource, 'utilFlag is true').Count -ne 1) { throw 'Test 8 failed: exact-case use "utils.ot" must resolve' }

    # Folder names are checked too.
    $helpersDir = Join-Path $tempDir 'Helpers'
    New-Item -ItemType Directory -Path $helpersDir -Force | Out-Null
    'helperFlag is true' | Set-Content -LiteralPath (Join-Path $helpersDir 'Tool.ot') -Encoding UTF8
    $fileDirWrong = Join-Path $tempDir 'dirWrong.ot'
    @'
use "helpers/Tool.ot"
'@ | Set-Content -LiteralPath $fileDirWrong -Encoding UTF8
    $dirError = $null
    try { Resolve-OtterModuleSource -FilePath $fileDirWrong | Out-Null } catch { $dirError = $_.Exception }
    if ($null -eq $dirError -or $dirError.Message -notmatch 'The folder is named "Helpers", but this use says "helpers"') { throw "Test 8 failed: use `"helpers/Tool.ot`" must not resolve folder Helpers. Got: $($dirError.Message)" }
    $fileDirRight = Join-Path $tempDir 'dirRight.ot'
    @'
use "Helpers/Tool.ot"
'@ | Set-Content -LiteralPath $fileDirRight -Encoding UTF8
    $resolvedDir = Resolve-OtterModuleSource -FilePath $fileDirRight
    if ($resolvedDir.CombinedSource -notmatch 'helperFlag is true') { throw 'Test 8 failed: exact-case use "Helpers/Tool.ot" must resolve' }
    Write-Output '  pass  module paths are case-sensitive: exact case resolves, a case mismatch in a file or folder name is rejected'

    # Test 9: Circular dependency detection across normalized relative paths
    $fileRelCycle1 = Join-Path $tempDir 'relCycle1.ot'
    $fileRelCycle2 = Join-Path $subDir 'relCycle2.ot'

    @'
use "sub/relCycle2.ot"
'@ | Set-Content -LiteralPath $fileRelCycle1 -Encoding UTF8

    @'
use "../relCycle1.ot"
'@ | Set-Content -LiteralPath $fileRelCycle2 -Encoding UTF8

    $caughtRelCycle = $false
    try {
        Resolve-OtterModuleSource -FilePath $fileRelCycle1 | Out-Null
    } catch [OtterError] {
        if ($_.Exception.Message -match 'Circular import detected') {
            $caughtRelCycle = $true
        }
    }
    if (-not $caughtRelCycle) {
        throw "Expected circular import error across normalized relative paths."
    }
    Write-Output '  pass  circular dependency detected across relative path traversal'

    # Test 10: Multi-diagnostic remapping across multiple modules
    $fileDiagA = Join-Path $tempDir 'diagA.ot'
    $fileDiagB = Join-Path $tempDir 'diagB.ot'
    $fileDiagMain = Join-Path $tempDir 'diagMain.ot'

    @'
score is
say "valid in A"
repeat times
'@ | Set-Content -LiteralPath $fileDiagA -Encoding UTF8

    @'
count is
say "valid in B"
write "data" to
'@ | Set-Content -LiteralPath $fileDiagB -Encoding UTF8

    @'
use "diagA.ot"
use "diagB.ot"
score2 is
'@ | Set-Content -LiteralPath $fileDiagMain -Encoding UTF8

    $resolvedDiags = Resolve-OtterModuleSource -FilePath $fileDiagMain
    $parseErr = $null
    try {
        $tokens = ConvertTo-OtterTokens -Source $resolvedDiags.CombinedSource
        ConvertTo-OtterAst -Tokens $tokens | Out-Null
    } catch [OtterError] {
        $parseErr = $_.Exception
    }

    if ($null -eq $parseErr -or $parseErr -isnot [OtterMultipleErrorsException]) {
        throw "Expected OtterMultipleErrorsException from multi-error source."
    }

    $remapped = ConvertTo-OtterRemappedDiagnostics -Error $parseErr -ResolvedProgram $resolvedDiags -RootFile $fileDiagMain
    if ($remapped.Diagnostics.Length -lt 5) {
        throw "Expected at least 5 recovered diagnostics, got $($remapped.Diagnostics.Length)"
    }

    # Verify attribution to original files
    $diagA_Errors = $remapped.Diagnostics | Where-Object { $_.Message -match 'In "diagA\.ot":' }
    $diagB_Errors = $remapped.Diagnostics | Where-Object { $_.Message -match 'In "diagB\.ot":' }
    $main_Errors = $remapped.Diagnostics | Where-Object { $_.Message -notmatch 'In "' }

    if ($diagA_Errors.Count -lt 2) { throw "Expected at least 2 errors attributed to diagA.ot, got $($diagA_Errors.Count)" }
    if ($diagB_Errors.Count -lt 2) { throw "Expected at least 2 errors attributed to diagB.ot, got $($diagB_Errors.Count)" }
    if ($main_Errors.Count -lt 1) { throw "Expected at least 1 error attributed to root diagMain.ot, got $($main_Errors.Count)" }

    # Verify line numbers mapped to local files
    if ($diagA_Errors[0].Line -ne 1) { throw "Expected diagA first error at local line 1, got $($diagA_Errors[0].Line)" }
    if ($diagA_Errors[1].Line -ne 3) { throw "Expected diagA second error at local line 3, got $($diagA_Errors[1].Line)" }
    if ($diagB_Errors[0].Line -ne 1) { throw "Expected diagB first error at local line 1, got $($diagB_Errors[0].Line)" }
    if ($diagB_Errors[1].Line -ne 3) { throw "Expected diagB second error at local line 3, got $($diagB_Errors[1].Line)" }
    if ($main_Errors[0].Line -ne 3) { throw "Expected root error at local line 3, got $($main_Errors[0].Line)" }

    # Verify source snippets and carets
    if ($diagA_Errors[0].SourceLine.Trim() -ne 'score is') { throw "Expected diagA source line 'score is', got $($diagA_Errors[0].SourceLine)" }
    if ($diagB_Errors[0].SourceLine.Trim() -ne 'count is') { throw "Expected diagB source line 'count is', got $($diagB_Errors[0].SourceLine)" }

    Write-Output '  pass  multi-diagnostics across multiple imported files are correctly attributed and line-mapped'

    # Test 11 (RC3 B13): the D122 exact-case rule also applies to ABSOLUTE
    # use paths. The case walk used to start at the importing file's folder,
    # found nothing for an absolute path and returned silently, so a
    # wrong-case absolute path loaded on Windows/macOS and was a generic
    # "Cannot find" on Linux. Same D122 diagnostic on every host now.
    $absDir = Join-Path $tempDir 'AbsCase'
    New-Item -ItemType Directory -Path $absDir -Force | Out-Null
    $absTarget = Join-Path $absDir 'absLib.ot'
    'absFlag is true' | Set-Content -LiteralPath $absTarget -Encoding UTF8
    $absTargetFull = (Resolve-Path -LiteralPath $absTarget).Path

    $wrongFileCase = Join-Path (Split-Path -Parent $absTargetFull) 'AbsLib.ot'
    $fileAbsWrong = Join-Path $tempDir 'absWrong.ot'
    "use `"$wrongFileCase`"" | Set-Content -LiteralPath $fileAbsWrong -Encoding UTF8
    $absError = $null
    try { Resolve-OtterModuleSource -FilePath $fileAbsWrong | Out-Null } catch { $absError = $_.Exception }
    if ($null -eq $absError -or $absError.Message -notmatch 'The file is named "absLib.ot", but this use says "AbsLib.ot"') { throw "Test 11 failed: a wrong-case absolute file name must give the D122 diagnostic. Got: $($absError.Message)" }
    if ($absError.Line -ne 1) { throw "Test 11 failed: expected the error on line 1, got $($absError.Line)" }
    if ($absError.Suggestion -notmatch 'absLib\.ot"$') { throw "Test 11 failed: the suggestion should spell the real name: $($absError.Suggestion)" }

    $wrongFolderCase = Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $absTargetFull)) 'abscase') 'absLib.ot'
    $fileAbsWrongDir = Join-Path $tempDir 'absWrongDir.ot'
    "use `"$wrongFolderCase`"" | Set-Content -LiteralPath $fileAbsWrongDir -Encoding UTF8
    $absDirError = $null
    try { Resolve-OtterModuleSource -FilePath $fileAbsWrongDir | Out-Null } catch { $absDirError = $_.Exception }
    if ($null -eq $absDirError -or $absDirError.Message -notmatch 'The folder is named "AbsCase", but this use says "abscase"') { throw "Test 11 failed: a wrong-case absolute folder name must give the D122 diagnostic. Got: $($absDirError.Message)" }

    $fileAbsRight = Join-Path $tempDir 'absRight.ot'
    "use `"$absTargetFull`"" | Set-Content -LiteralPath $fileAbsRight -Encoding UTF8
    $resolvedAbs = Resolve-OtterModuleSource -FilePath $fileAbsRight
    if ([regex]::Matches($resolvedAbs.CombinedSource, 'absFlag is true').Count -ne 1) { throw 'Test 11 failed: an exact-case absolute use path must still load' }
    Write-Output '  pass  absolute use paths get the same exact-case check (D122) and still load when spelled exactly'

} finally {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
