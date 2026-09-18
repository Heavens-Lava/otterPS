[CmdletBinding()]
param(
    [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC - CLI Contract Certification Suite" -ForegroundColor Cyan
Write-Host "Version: $version" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-cli-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

$passCount = 0
$failCount = 0

function Assert-CliCase {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [int]$ExpectedExitCode,
        [string]$MatchPattern = $null,
        [string]$WorkingDir = $null
    )

    $cmd = Join-Path $root 'otter.cmd'
    $prevLocation = Get-Location

    try {
        if ($WorkingDir) {
            if (-not (Test-Path -LiteralPath $WorkingDir)) {
                New-Item -ItemType Directory -Path $WorkingDir -Force | Out-Null
            }
            Set-Location -LiteralPath $WorkingDir
        }

        $output = & $cmd @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        $rawText = ($output -join "`n").Trim()

        # Check exit code
        if ($exitCode -ne $ExpectedExitCode) {
            throw "Expected exit code $ExpectedExitCode, but got $exitCode. Output: $rawText"
        }

        # Check pattern
        if ($MatchPattern -and $rawText -notmatch $MatchPattern) {
            throw "Output did not match pattern '$MatchPattern'. Output: $rawText"
        }

        # Check that no raw PowerShell exception / stack trace leaked
        if ($rawText -match 'System\.Management\.Automation' -or $rawText -match '\bat line:\d+\b' -or $rawText -match '\.psm1:\s*line\s*\d+') {
            throw "Raw PowerShell exception or stack trace leaked in output: $rawText"
        }

        Write-Host "  [PASS] $Name (exit $exitCode)" -ForegroundColor Green
        $script:passCount++
    }
    catch {
        Write-Host "  [FAIL] ${Name}: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
    finally {
        Set-Location -LiteralPath $prevLocation
    }
}

try {
    # Prepare test scripts
    $validScript = Join-Path $testRoot 'valid_prog.ot'
    Set-Content -LiteralPath $validScript -Value 'say "cli test ok"' -Encoding UTF8

    $syntaxErrorScript = Join-Path $testRoot 'syntax_err.ot'
    Set-Content -LiteralPath $syntaxErrorScript -Value "if 10 is`n  say `"bad`"" -Encoding UTF8

    $runtimeErrorScript = Join-Path $testRoot 'runtime_err.ot'
    Set-Content -LiteralPath $runtimeErrorScript -Value 'x is 10 divided by 0' -Encoding UTF8

    # 1. Version commands (Exit 0)
    Assert-CliCase -Name "CLI: --version" -Arguments @('--version') -ExpectedExitCode 0 -MatchPattern "Otter $version"
    Assert-CliCase -Name "CLI: -version" -Arguments @('-version') -ExpectedExitCode 0 -MatchPattern "Otter $version"

    # 2. Help commands (Exit 0)
    Assert-CliCase -Name "CLI: --help" -Arguments @('--help') -ExpectedExitCode 0 -MatchPattern "Usage:"
    Assert-CliCase -Name "CLI: help" -Arguments @('help') -ExpectedExitCode 0 -MatchPattern "otter web"

    # 3. Canonical run commands (Exit 0)
    Assert-CliCase -Name "CLI: otter <file.ot>" -Arguments @($validScript) -ExpectedExitCode 0 -MatchPattern "cli test ok"
    Assert-CliCase -Name "CLI: otter run <file.ot>" -Arguments @('run', $validScript) -ExpectedExitCode 0 -MatchPattern "cli test ok"

    # 4. Check command (Exit 0 on valid program without executing)
    Assert-CliCase -Name "CLI: otter check <file.ot> (valid)" -Arguments @('check', $validScript) -ExpectedExitCode 0 -MatchPattern "is valid"

    # 5. Check command with syntax error (Exit 2)
    Assert-CliCase -Name "CLI: otter check <syntax_err.ot> (syntax error)" -Arguments @('check', $syntaxErrorScript) -ExpectedExitCode 2

    # 6. Run command with syntax error (Exit 2)
    Assert-CliCase -Name "CLI: otter run <syntax_err.ot> (parse failure)" -Arguments @('run', $syntaxErrorScript) -ExpectedExitCode 2

    # 7. Run command with runtime error (Exit 3)
    Assert-CliCase -Name "CLI: otter run <runtime_err.ot> (runtime error)" -Arguments @('run', $runtimeErrorScript) -ExpectedExitCode 3 -MatchPattern "I cannot divide by zero"

    # 8. Missing argument for run (Exit 1)
    Assert-CliCase -Name "CLI: otter run (missing file argument)" -Arguments @('run') -ExpectedExitCode 1 -MatchPattern "Usage: otter run <file.ot>"

    # 9. Missing argument for check (Exit 1)
    Assert-CliCase -Name "CLI: otter check (missing file argument)" -Arguments @('check') -ExpectedExitCode 1 -MatchPattern "Usage: otter check <file.ot>"

    # 10. Nonexistent file (Exit 1)
    Assert-CliCase -Name "CLI: otter run nonexistent_file_xyz.ot" -Arguments @('run', 'nonexistent_file_xyz.ot') -ExpectedExitCode 1 -MatchPattern "I cannot find a file called"

    # 11. Wrong file extension (Exit 1)
    $txtFile = Join-Path $testRoot 'test.txt'
    Set-Content -LiteralPath $txtFile -Value 'hello'
    Assert-CliCase -Name "CLI: otter run not_an_ot_file.txt" -Arguments @('run', $txtFile) -ExpectedExitCode 1 -MatchPattern "expected a .ot file"

    # 12. Unknown command (Exit 1)
    Assert-CliCase -Name "CLI: otter unknownSubcommand" -Arguments @('unknownSubcommand') -ExpectedExitCode 1 -MatchPattern "I do not recognize the command"

    # 13. Execution from directory containing spaces
    $spaceDir = Join-Path $testRoot 'Directory With Spaces In Path'
    Assert-CliCase -Name "CLI: execute from directory containing spaces" -Arguments @($validScript) -ExpectedExitCode 0 -MatchPattern "cli test ok" -WorkingDir $spaceDir

    # 14. Execution from C:\ root
    Assert-CliCase -Name "CLI: execute from C:\ filesystem root" -Arguments @($validScript) -ExpectedExitCode 0 -MatchPattern "cli test ok" -WorkingDir 'C:\'

    # 15. Execution from Temp directory
    Assert-CliCase -Name "CLI: execute from System Temp directory" -Arguments @($validScript) -ExpectedExitCode 0 -MatchPattern "cli test ok" -WorkingDir ([System.IO.Path]::GetTempPath())

} finally {
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $testRoot)) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "CLI Contract Certification: $passCount passed, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
if ($failCount -ne 0) { exit 1 }
exit 0
