# Run-Tests.ps1
#
# Runs every *.Tests.ps1 in this folder and reports one overall result.
#
# Each test file runs in its own PowerShell process, on purpose. PowerShell
# 5.1 caches the classes a `using module` line loads for the life of a
# session, so a second test file importing an edited module would quietly get
# the STALE version. A fresh process per file makes that impossible.
#
#     powershell -NoProfile -File .\tests\Run-Tests.ps1

$ErrorActionPreference = 'Stop'

$testFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' | Sort-Object Name

if ($testFiles.Count -eq 0) {
    Write-Host 'No test files found.' -ForegroundColor Yellow
    exit 0
}

$failedFiles = @()

foreach ($file in $testFiles) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file.FullName
    if ($LASTEXITCODE -ne 0) {
        $failedFiles += $file.Name
    }
}

Write-Host ''
Write-Host ('=' * 52)

if ($failedFiles.Count -eq 0) {
    Write-Host "All test files passed ($($testFiles.Count) of $($testFiles.Count))." -ForegroundColor Green
    exit 0
}

Write-Host "Failing test files: $($failedFiles -join ', ')" -ForegroundColor Red
exit 1
