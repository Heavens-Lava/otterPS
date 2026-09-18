# tests/DiagnosticMatrix.Tests.ps1
#
# Phase 5 - Formal Release Diagnostic Certification Matrix
# Asserts that all major error categories produce clean, formatted Otter diagnostics
# with deterministic exit codes and zero raw host / .NET / PowerShell stack traces.

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$otterCmd = Join-Path $repoRoot 'otter.cmd'
$scratchDir = Join-Path $repoRoot 'scratch\diag_tests'

if (Test-Path -LiteralPath $scratchDir) {
    Remove-Item -LiteralPath $scratchDir -Recurse -Force
}
New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null

$script:passCount = 0
$script:failCount = 0

function Assert-Diagnostic {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][int]$ExpectedExitCode,
        [Parameter(Mandatory)][string]$ExpectedBanner, # "Otter Syntax Error" or "Otter Runtime Error"
        [string[]]$ExpectedKeywords = @()
    )

    $testFile = Join-Path $scratchDir "diag_${Category}.ot"
    Set-Content -Path $testFile -Value $Source -Encoding utf8

    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $otterCmd
        $pinfo.Arguments = "run `"$testFile`""
        $pinfo.WorkingDirectory = $scratchDir
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        $allOutput = "$stdout`n$stderr".Trim()

        if ($proc.ExitCode -ne $ExpectedExitCode) {
            throw "Expected exit code $ExpectedExitCode but got $($proc.ExitCode). Output: $allOutput"
        }

        if (-not ($allOutput -match [regex]::Escape($ExpectedBanner))) {
            throw "Expected banner '$ExpectedBanner' not found in output: $allOutput"
        }

        # Assert no host leaks
        $hostLeaks = @(
            'System.Management.Automation',
            'NullReferenceException',
            'Otter.Interpreter.psm1',
            'Otter.Parser.psm1',
            'Otter.Lexer.psm1',
            'at <ScriptBlock>',
            'StackTrace'
        )
        foreach ($leak in $hostLeaks) {
            if ($allOutput -match [regex]::Escape($leak)) {
                throw "Host leak detected ('$leak') in output: $allOutput"
            }
        }

        # Assert expected keywords
        foreach ($kw in $ExpectedKeywords) {
            if (-not ($allOutput -match [regex]::Escape($kw))) {
                throw "Expected keyword '$kw' not found in diagnostic output: $allOutput"
            }
        }

        # Assert real line number present
        if (-not ($allOutput -match 'Line \d+:')) {
            throw "Diagnostic output is missing line number reference ('Line X:'): $allOutput"
        }

        Write-Host "  [PASS] $Category (Exit $ExpectedExitCode, clean Otter diagnostic)" -ForegroundColor Green
        $script:passCount++
    }
    catch {
        Write-Host "  [FAIL] ${Category}: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
    finally {
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC - Diagnostic Certification Matrix Suite" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

try {
    # 1. Lexer Failure
    Assert-Diagnostic -Category "lexer_unclosed_string" -Source @"
say "unterminated string
"@ -ExpectedExitCode 2 -ExpectedBanner "Otter Syntax Error" -ExpectedKeywords @("never closes")

    # 2. Parser Failure
    Assert-Diagnostic -Category "parser_missing_than" -Source @"
if age is greater 18
    say "invalid"
.
"@ -ExpectedExitCode 2 -ExpectedBanner "Otter Syntax Error" -ExpectedKeywords @("I expected the statement to end here")

    # 3. Indentation Failure
    Assert-Diagnostic -Category "indentation_inconsistent" -Source @"
if true
  say "bad indent"
"@ -ExpectedExitCode 2 -ExpectedBanner "Otter Syntax Error" -ExpectedKeywords @("indentation")

    # 4. Type Mismatch
    Assert-Diagnostic -Category "type_mismatch_numeric" -Source @"
total is "banana" plus 5
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error" -ExpectedKeywords @("number")

    # 5. Bad Arithmetic
    Assert-Diagnostic -Category "bad_arithmetic_strings" -Source @"
answer is "apple" times 5
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error" -ExpectedKeywords @("number")

    # 6. Division by Zero
    Assert-Diagnostic -Category "division_by_zero" -Source @"
answer is 10 divided by 0
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error" -ExpectedKeywords @("zero")

    # 7. Missing File
    Assert-Diagnostic -Category "missing_file" -Source @"
read "nonexistent_file_987654.txt" into content
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error" -ExpectedKeywords @("nonexistent_file_987654.txt")

    # 8. Directory as File
    Assert-Diagnostic -Category "directory_as_file" -Source @"
write "hello" to "."
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error" -ExpectedKeywords @("is a folder, not a file")

    # 9. Malformed JSON
    Assert-Diagnostic -Category "malformed_json" -Source @"
convert "{ bad: json" from json into obj
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error" -ExpectedKeywords @("JSON")

    # 10. Invalid Collection Operation
    Assert-Diagnostic -Category "invalid_collection_target" -Source @"
num is 42
remove "item" from num
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error"

    # 11. Missing Object Property
    Assert-Diagnostic -Category "missing_object_property" -Source @"
p is a thing
.
say age of p
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error" -ExpectedKeywords @("age")

    # 12. Bad Function Arguments
    Assert-Diagnostic -Category "bad_function_args" -Source @"
to greet first and second
    say first second
.
greet "only_one"
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error"

    # 13. Recursion Overflow
    Assert-Diagnostic -Category "recursion_overflow" -Source @"
to overflowLoop x
    overflowLoop x
.
overflowLoop 1
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error" -ExpectedKeywords @("Call depth limit exceeded")

    # 14. Failed / Nonexistent Program Invocation
    Assert-Diagnostic -Category "unsupported_process" -Source @"
run "definitely_nonexistent_executable_12345.exe"
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error"

    # 15. Undefined Variable
    Assert-Diagnostic -Category "undefined_variable" -Source @"
say missingVariable123
"@ -ExpectedExitCode 3 -ExpectedBanner "Otter Runtime Error" -ExpectedKeywords @("missingVariable123")

} finally {
    Remove-Item -LiteralPath $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Diagnostic Certification Results: $passCount passed, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
if ($failCount -ne 0) { exit 1 }
exit 0
