# distribution/Update-Otter.ps1
# Upgrades an existing Otter installation in-place with rollback preservation.
# Conforms to Section 35:
# - Atomic upgrade with backup snapshot
# - Preservation of user projects & settings
# - Automatic rollback upon verification failure

[CmdletBinding()]
param(
    [string]$Destination,
    [string]$Channel = 'stable',
    [switch]$CheckOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$packageRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'VERSION')) {
    $PSScriptRoot
} else {
    Split-Path -Parent $PSScriptRoot
}
$candidateVersion = (Get-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Raw).Trim()

$onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
$launcher = if ($onWindows) { 'otter.cmd' } else { 'otter' }

if (-not $Destination) {
    if ($onWindows) {
        if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $base = Join-Path $env:LOCALAPPDATA 'Otter'
            if (Test-Path -LiteralPath $base) {
                # Find latest installed folder
                $installed = Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name -Descending | Select-Object -First 1
                if ($installed) { $Destination = $installed.FullName }
            }
        }
    } else {
        $dataHome = if (-not [string]::IsNullOrWhiteSpace($env:XDG_DATA_HOME)) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local/share' }
        $base = Join-Path $dataHome 'otter'
        if (Test-Path -LiteralPath $base) {
            $installed = Get-ChildItem -LiteralPath $base -Directory | Sort-Object Name -Descending | Select-Object -First 1
            if ($installed) { $Destination = $installed.FullName }
        }
    }
}

if (-not $Destination -or -not (Test-Path -LiteralPath $Destination)) {
    throw "No existing Otter installation found. Specify -Destination to target an install folder."
}

$currentVersionPath = Join-Path $Destination 'VERSION'
$currentVersion = if (Test-Path -LiteralPath $currentVersionPath) {
    (Get-Content -LiteralPath $currentVersionPath -Raw).Trim()
} else {
    'unknown'
}

Write-Output "Current Otter installation: $Destination (Version: $currentVersion)"
Write-Output "Candidate version: $candidateVersion (Channel: $Channel)"

if ($CheckOnly) {
    if ($candidateVersion -ne $currentVersion) {
        Write-Output "Update is available: $candidateVersion"
        return $true
    } else {
        Write-Output "Otter is already up to date ($currentVersion)."
        return $false
    }
}

# --- Rollback Backup Snapshot ---
$backupPath = "$Destination.backup"
if (Test-Path -LiteralPath $backupPath) {
    Remove-Item -LiteralPath $backupPath -Recurse -Force
}

Write-Output "Creating pre-update backup snapshot at: $backupPath"
Copy-Item -LiteralPath $Destination -Destination $backupPath -Recurse -Force

try {
    Write-Output "Applying update to $Destination..."
    # Update core runtime files
    foreach ($item in @('otter.ps1', $launcher, 'Otter.Contract.psm1', 'VERSION', 'LICENSE', 'THIRD-PARTY-NOTICES.md')) {
        $src = Join-Path $packageRoot $item
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination $Destination -Force
        }
    }

    # Update src directory
    $srcDir = Join-Path $packageRoot 'src'
    if (Test-Path -LiteralPath $srcDir) {
        Copy-Item -LiteralPath $srcDir -Destination $Destination -Recurse -Force
    }

    # Update marker
    $marker = Join-Path $Destination '.otter-install'
    "Otter installation marker: $candidateVersion updated $(Get-Date -Format s)" | Set-Content -LiteralPath $marker -Encoding UTF8

    # Verify updated installation launcher exists
    $launcherPath = Join-Path $Destination $launcher
    if (-not (Test-Path -LiteralPath $launcherPath)) {
        throw "Verification failed: Launcher $launcher was not found in updated destination."
    }

    Write-Output "Successfully updated Otter to version $candidateVersion."
    Write-Output "User projects and settings preserved."
} catch {
    Write-Warning "Update failed ($($_.Exception.Message)). Rolling back from backup snapshot..."
    if (Test-Path -LiteralPath $backupPath) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
        Move-Item -LiteralPath $backupPath -Destination $Destination -Force
        Write-Output "Rollback completed. Restored version $currentVersion."
    }
    throw
}
