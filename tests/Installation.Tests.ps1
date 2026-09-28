[CmdletBinding()]
param(
    [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Otter 1.0 RC - Clean Installation Certification Suite" -ForegroundColor Cyan
Write-Host "Version: $version" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-install-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

$passCount = 0
$failCount = 0

function Assert-Test ($Name, [scriptblock]$Action) {
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
    # 1. Build release distribution payload
    $payloadDir = Join-Path $testRoot 'payload'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\New-OtterDistribution.ps1') -OutputDirectory $payloadDir -Force | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to build release distribution." }

    $package = Join-Path $payloadDir ("otter-$version-windows-powershell")
    $installer = Join-Path $package 'Install-Otter.ps1'
    $uninstaller = Join-Path $package 'Uninstall-Otter.ps1'

    Assert-Test "Distribution package contains required release artifacts" {
        foreach ($file in @('otter.ps1', 'otter.cmd', 'Otter.Contract.psm1', 'VERSION', 'README.md', 'Install-Otter.ps1', 'Uninstall-Otter.ps1', 'release-manifest.json')) {
            $p = Join-Path $package $file
            if (-not (Test-Path -LiteralPath $p)) { throw "Missing $file in distribution." }
        }
        $srcDir = Join-Path $package 'src'
        if (-not (Test-Path -LiteralPath $srcDir)) { throw "Missing src directory in distribution." }
    }

    # 2. Test standard clean installation
    $installDir1 = Join-Path $testRoot 'standard_install'
    Assert-Test "Clean per-user installation completes successfully" {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $installDir1 -Force | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Install-Otter exited with code $LASTEXITCODE" }
        if (-not (Test-Path -LiteralPath (Join-Path $installDir1 'otter.cmd'))) { throw "otter.cmd not found in $installDir1" }
        if (-not (Test-Path -LiteralPath (Join-Path $installDir1 'Uninstall-Otter.ps1'))) { throw "Uninstall-Otter.ps1 not found in $installDir1" }
    }

    # 3. Test installed Otter CLI execution from clean isolated directory
    $workIsolated = Join-Path $testRoot 'isolated_work'
    New-Item -ItemType Directory -Path $workIsolated | Out-Null
    $helloOt = Join-Path $workIsolated 'hello.ot'
    Set-Content -LiteralPath $helloOt -Value 'say "Installation verification passed."' -Encoding UTF8

    Assert-Test "Installed otter --version works cleanly" {
        $cmd = Join-Path $installDir1 'otter.cmd'
        $res = & $cmd --version 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE - $($res -join "`n")" }
        if ($res -notmatch "Otter $version") { throw "Unexpected version text: $res" }
    }

    Assert-Test "Installed otter run executes script from unrelated directory" {
        $cmd = Join-Path $installDir1 'otter.cmd'
        Push-Location $workIsolated
        try {
            $res = & $cmd run hello.ot 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE - $($res -join "`n")" }
            if ($res -notmatch "Installation verification passed.") { throw "Unexpected output: $res" }
        } finally {
            Pop-Location
        }
    }

    Assert-Test "Installed otter web compiles script in isolated directory" {
        $webOt = Join-Path $workIsolated 'app.ot'
        Set-Content -LiteralPath $webOt -Value @"
btn is a button
    text is "Click Me"
.
"@ -Encoding UTF8
        $cmd = Join-Path $installDir1 'otter.cmd'
        Push-Location $workIsolated
        try {
            $res = & $cmd web app.ot -NoOpen 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE - $($res -join "`n")" }
            if (-not (Test-Path -LiteralPath (Join-Path $workIsolated 'app.html'))) {
                throw "app.html was not generated"
            }
        } finally {
            Pop-Location
        }
    }

    # 4. Test installation to a path with spaces
    $installDirSpaces = Join-Path $testRoot 'Otter Install Directory With Spaces'
    Assert-Test "Installation to path containing spaces succeeds" {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $installDirSpaces -Force | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Install-Otter with spaces exited with code $LASTEXITCODE" }
        $cmd = Join-Path $installDirSpaces 'otter.cmd'
        $res = & $cmd --version 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Installed otter in spaced directory failed: $res" }
        if ($res -notmatch "Otter $version") { throw "Unexpected version text: $res" }
    }

    # 5. Test reinstall without -Force is rejected
    Assert-Test "Reinstalling without -Force is safely rejected" {
        $failed = $false
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $installDir1 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $failed = $true }
        } catch { $failed = $true }
        if (-not $failed) { throw "Expected non-forced reinstall to be rejected!" }
    }

    # 6. Test reinstall with -Force succeeds (upgrade path)
    Assert-Test "Reinstalling with -Force succeeds" {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $installDir1 -Force | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Forced reinstall exited with code $LASTEXITCODE" }
    }

    # 7. Test PATH addition and uninstallation cleanup
    $installDirUser = Join-Path $testRoot 'path_test_install'
    Assert-Test "AddToUserPath and Uninstall-Otter PATH cleanup" {
        # Install with -AddToUserPath
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $installDirUser -AddToUserPath -Force | Out-Null
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notmatch [regex]::Escape($installDirUser)) {
            throw "PATH did not contain installed directory $installDirUser"
        }

        # Run uninstaller from the installed directory
        $uninstCmd = Join-Path $installDirUser 'Uninstall-Otter.ps1'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstCmd -Force | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Uninstall-Otter exited with code $LASTEXITCODE" }

        # Verify directory was deleted
        if (Test-Path -LiteralPath $installDirUser) {
            throw "Installation directory $installDirUser was not removed after uninstallation!"
        }

        # Verify PATH was cleaned up
        $newUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($newUserPath -and $newUserPath -match [regex]::Escape($installDirUser)) {
            throw "User PATH still contains $installDirUser after uninstallation!"
        }
    }

    # 8. Test rejection of filesystem root as destination
    Assert-Test "Refusing root directory destination" {
        $failed = $false
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination 'C:\' 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $failed = $true }
        } catch { $failed = $true }
        if (-not $failed) { throw "Expected installer to refuse 'C:\' destination!" }
    }

    # 8a. -Force must never delete a folder that is not an Otter installation
    # (regression: -Force used to Remove-Item -Recurse any existing destination)
    $userFolder = Join-Path $testRoot 'user_documents'
    New-Item -ItemType Directory -Path $userFolder | Out-Null
    $userFile = Join-Path $userFolder 'thesis.txt'
    Set-Content -LiteralPath $userFile -Value 'irreplaceable user data' -Encoding UTF8
    Assert-Test "Forced install into a non-Otter folder is refused and user data survives" {
        $failed = $false
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $userFolder -Force 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $failed = $true }
        } catch { $failed = $true }
        if (-not $failed) { throw "Expected forced install into a non-Otter folder to be refused!" }
        if (-not (Test-Path -LiteralPath $userFile)) { throw "User file $userFile was deleted by the installer!" }
    }

    # 8b. An existing EMPTY folder is a valid destination
    $emptyFolder = Join-Path $testRoot 'empty_folder'
    New-Item -ItemType Directory -Path $emptyFolder | Out-Null
    Assert-Test "Installation into an existing empty folder succeeds" {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $emptyFolder | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Install into empty folder exited with code $LASTEXITCODE" }
        if (-not (Test-Path -LiteralPath (Join-Path $emptyFolder '.otter-install'))) { throw ".otter-install marker not written" }
    }

    # 8c. -Force upgrades a real previous install, including one made by an
    # earlier installer that did not write the .otter-install marker
    $legacyInstall = Join-Path $testRoot 'legacy_install'
    Assert-Test "Forced install upgrades a previous (pre-marker) Otter installation" {
        Copy-Item -LiteralPath $installDir1 -Destination $legacyInstall -Recurse
        Remove-Item -LiteralPath (Join-Path $legacyInstall '.otter-install') -Force
        Set-Content -LiteralPath (Join-Path $legacyInstall 'stale-from-old-version.txt') -Value 'old' -Encoding UTF8
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $legacyInstall -Force | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Forced upgrade exited with code $LASTEXITCODE" }
        if (Test-Path -LiteralPath (Join-Path $legacyInstall 'stale-from-old-version.txt')) { throw "Old installation was not replaced" }
        if (-not (Test-Path -LiteralPath (Join-Path $legacyInstall '.otter-install'))) { throw ".otter-install marker not written on upgrade" }
        if (-not (Test-Path -LiteralPath (Join-Path $legacyInstall 'otter.cmd'))) { throw "otter.cmd missing after upgrade" }
    }

    # 8d. A destination that contains the extracted package must be refused
    # (regression: -Force used to delete the package mid-install)
    Assert-Test "Forced install into an ancestor of the package is refused and the package survives" {
        $failed = $false
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Destination $payloadDir -Force 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $failed = $true }
        } catch { $failed = $true }
        if (-not $failed) { throw "Expected install into an ancestor of the package to be refused!" }
        if (-not (Test-Path -LiteralPath $installer)) { throw "Extracted package was deleted by the installer!" }
    }

    # 8e. The uninstaller must never delete a source checkout or a random
    # folder, even with -Force (regression: otter.cmd alone was its marker,
    # and -Force skipped even that)
    $fakeCheckout = Join-Path $testRoot 'source_checkout'
    New-Item -ItemType Directory -Path $fakeCheckout | Out-Null
    foreach ($file in @('otter.cmd', 'otter.ps1', 'Otter.Contract.psm1', 'VERSION')) {
        Copy-Item -LiteralPath (Join-Path $package $file) -Destination $fakeCheckout
    }
    Copy-Item -LiteralPath (Join-Path $package 'src') -Destination $fakeCheckout -Recurse
    New-Item -ItemType Directory -Path (Join-Path $fakeCheckout '.git') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fakeCheckout 'tests') | Out-Null
    Assert-Test "Uninstaller refuses a source checkout and a random folder even with -Force" {
        foreach ($target in @($fakeCheckout, $userFolder)) {
            $failed = $false
            try {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstaller -Destination $target -Force 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { $failed = $true }
            } catch { $failed = $true }
            if (-not $failed) { throw "Expected uninstaller to refuse $target!" }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $fakeCheckout 'otter.cmd'))) { throw "Source checkout was deleted by the uninstaller!" }
        if (-not (Test-Path -LiteralPath $userFile)) { throw "User file $userFile was deleted by the uninstaller!" }
    }

    Assert-Test "Uninstaller still removes a real installation" {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstaller -Destination $emptyFolder -Force | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Uninstall-Otter exited with code $LASTEXITCODE" }
        if (Test-Path -LiteralPath $emptyFolder) { throw "Installation directory $emptyFolder was not removed!" }
    }

    # 9. Test corrupted distribution rejection
    $corruptPackage = Join-Path $testRoot 'corrupt_package'
    New-Item -ItemType Directory -Path $corruptPackage | Out-Null
    Copy-Item -LiteralPath $installer -Destination $corruptPackage
    Assert-Test "Corrupted/incomplete distribution payload is rejected" {
        $failed = $false
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $corruptPackage 'Install-Otter.ps1') -Destination (Join-Path $testRoot 'corrupt_dest') 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { $failed = $true }
        } catch { $failed = $true }
        if (-not $failed) { throw "Expected incomplete package to be rejected!" }
    }

} finally {
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $testRoot)) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Installation Certification: $passCount passed, $failCount failed." -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
if ($failCount -ne 0) { exit 1 }
exit 0
