# tests/InstallSoak.Tests.ps1
#
# Release Installation Soak Suite for Otter 1.0 RC.
# Validates repeated lifecycle operations:
#   install -> run -> web compile -> uninstall
# across multiple isolated directories and test cycles.
#
# Checks:
# 1. PATH integrity (no duplicate or corrupted entries)
# 2. Complete file cleanup on uninstall (no stale or orphaned files)
# 3. Deterministic upgrade / re-installation with -Force
# 4. Multi-cycle stability (5 sequential full cycles)

[CmdletBinding()]
param(
    [int]$Cycles = 5
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC - Release Installation Soak Suite" -ForegroundColor Cyan
Write-Host "Version: $version | Soak Cycles: $Cycles" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-install-soak-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

$passCount = 0
$failCount = 0

function Assert-SoakStep ($Name, [scriptblock]$Action) {
    try {
        & $Action
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passCount++
    } catch {
        Write-Host "  [FAIL] ${Name}: $($_.Exception.Message)" -ForegroundColor Red
        $script:failCount++
    }
}

try {
    # 1. Build release payload
    $payloadDir = Join-Path $testRoot 'payload'
    Write-Host "Building release distribution payload..." -ForegroundColor Yellow
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'tools\New-OtterDistribution.ps1') -OutputDirectory $payloadDir -Force | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to build distribution." }

    $package = Join-Path $payloadDir ("otter-$version-windows-powershell")
    $installer = Join-Path $package 'Install-Otter.ps1'

    # 2. Soak: 5 sequential install -> run -> web compile -> uninstall cycles
    for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
        Write-Host "`n--- Soak Cycle $cycle of $Cycles ---" -ForegroundColor Yellow
        $dest = Join-Path $testRoot ("install_cycle_$cycle")

        # Step A: Install
        Assert-SoakStep "Cycle $cycle - Install to isolated destination" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $dest -Force | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Installer exited with code $LASTEXITCODE" }
            if (-not (Test-Path -LiteralPath (Join-Path $dest 'otter.cmd'))) { throw "otter.cmd missing" }
            if (-not (Test-Path -LiteralPath (Join-Path $dest 'Uninstall-Otter.ps1'))) { throw "Uninstall-Otter.ps1 missing" }
        }

        # Step B: Run CLI
        $otterCmd = Join-Path $dest 'otter.cmd'
        $scriptFile = Join-Path $testRoot 'soak_test.ot'
        Set-Content -LiteralPath $scriptFile -Value 'say "soak-cycle-ok"' -Encoding utf8

        Assert-SoakStep "Cycle $cycle - Execute script using installed binary" {
            $res = & $otterCmd run $scriptFile
            if ($LASTEXITCODE -ne 0) { throw "CLI run failed with code $LASTEXITCODE" }
            if ($res -ne 'soak-cycle-ok') { throw "Expected 'soak-cycle-ok', got '$res'" }
        }

        # Step C: Web compile
        $webScriptFile = Join-Path $testRoot 'web_app.ot'
        Set-Content -LiteralPath $webScriptFile -Value @"
app is a page
    title is "Soak"
.
show app
"@ -Encoding utf8

        Assert-SoakStep "Cycle $cycle - Web compile using installed binary" {
            $webOut = & $otterCmd web $webScriptFile
            if ($LASTEXITCODE -ne 0) { throw "Web compile failed with code $LASTEXITCODE" }
            $expectedHtml = Join-Path $testRoot 'web_app.html'
            if (-not (Test-Path -LiteralPath $expectedHtml)) { throw "Generated web HTML not found" }
            Remove-Item -LiteralPath $expectedHtml -Force -ErrorAction SilentlyContinue
        }

        # Step D: Uninstall and check for zero stale files
        $uninstaller = Join-Path $dest 'Uninstall-Otter.ps1'
        Assert-SoakStep "Cycle $cycle - Clean uninstallation leaves no stale files" {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstaller -Destination $dest -Force | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Uninstaller exited with code $LASTEXITCODE" }
            if (Test-Path -LiteralPath $dest) { throw "Install directory $dest still exists after uninstallation!" }
        }
    }

    # 3. Test PATH deduplication behavior
    Write-Host "`n--- PATH Deduplication Certification ---" -ForegroundColor Yellow
    $pathDest = Join-Path $testRoot 'path_install'

    Assert-SoakStep "PATH registration prevents duplicate entries across reinstalls" {
        # Install twice with AddToUserPath simulated
        $initialUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')

        # Clean any prior residue
        $cleanPath = ($initialUserPath -split ';' | Where-Object { $_ -ne $pathDest }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $cleanPath, 'User')

        try {
            # 1st install
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $pathDest -AddToUserPath -Force | Out-Null
            $after1 = [Environment]::GetEnvironmentVariable('Path', 'User')
            $matches1 = ($after1 -split ';' | Where-Object { $_ -eq $pathDest }).Count
            if ($matches1 -ne 1) { throw "Expected exactly 1 PATH entry, found $matches1" }

            # 2nd reinstall (upgrade/force)
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $pathDest -AddToUserPath -Force | Out-Null
            $after2 = [Environment]::GetEnvironmentVariable('Path', 'User')
            $matches2 = ($after2 -split ';' | Where-Object { $_ -eq $pathDest }).Count
            if ($matches2 -ne 1) { throw "Duplicate PATH entry created on re-installation! Found $matches2 matches." }

            # Uninstall with automated PATH cleanup
            $uninst = Join-Path $pathDest 'Uninstall-Otter.ps1'
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninst -Destination $pathDest -Force | Out-Null
            $afterUninstall = [Environment]::GetEnvironmentVariable('Path', 'User')
            $matches3 = ($afterUninstall -split ';' | Where-Object { $_ -eq $pathDest }).Count
            if ($matches3 -ne 0) { throw "PATH entry remained after uninstall! Found $matches3 matches." }
        }
        finally {
            [Environment]::SetEnvironmentVariable('Path', $initialUserPath, 'User')
        }
    }
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "Install Soak Summary: $passCount passed, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
Write-Host "====================================================" -ForegroundColor Cyan

if ($failCount -ne 0) { exit 1 }
