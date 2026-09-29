[CmdletBinding()]
param(
    [string]$Destination,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Returns $true only for a folder that is recognisably an Otter installation.
# This is a copy of the function in Install-Otter.ps1 (both scripts ship
# standalone in the distribution zip); keep the two copies identical. The
# uninstaller deletes the whole folder recursively, so it must refuse
# anything this does not recognise - user folders and source checkouts.
function Test-OtterInstallation {
    param([string]$Path)
    # A source checkout (or a source zip) has otter.cmd, otter.ps1, VERSION
    # and src\ at its root just like an install, so any repository-only
    # folder proves this is NOT an install and must never be deleted.
    foreach ($checkoutOnly in @('.git', 'tests', 'tools', 'distribution')) {
        if (Test-Path -LiteralPath (Join-Path $Path $checkoutOnly)) { return $false }
    }
    # Installs made by this version onwards carry an '.otter-install' marker
    # file, written before any other file so that an interrupted install is
    # still recognised (and can be repaired with -Force or uninstalled).
    $marker = Join-Path $Path '.otter-install'
    if (Test-Path -LiteralPath $marker -PathType Leaf) {
        $firstLine = Get-Content -LiteralPath $marker -TotalCount 1 -ErrorAction SilentlyContinue
        if ($firstLine -like 'Otter installation marker*') { return $true }
    }
    # Installs made by earlier installers have no marker; recognise them by
    # the full runtime file set that every Otter install has always contained.
    $legacyMarkers = @(
        (Join-Path $Path 'VERSION'),
        (Join-Path $Path 'otter.cmd'),
        (Join-Path $Path 'otter.ps1'),
        (Join-Path $Path 'Otter.Contract.psm1'),
        (Join-Path (Join-Path $Path 'src') 'Otter.Runtime.psm1')
    )
    foreach ($file in $legacyMarkers) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $false }
    }
    return $true
}

$onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)

# Determine destination to uninstall
if (-not $Destination) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.otter-install')) {
        $Destination = $PSScriptRoot
    } elseif ($onWindows -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'otter.cmd'))) {
        $Destination = $PSScriptRoot
    } else {
        $versionFile = Join-Path $PSScriptRoot 'VERSION'
        $version = if (Test-Path -LiteralPath $versionFile) { (Get-Content -LiteralPath $versionFile -Raw).Trim() } else { '*' }
        $defaultDir = $null
        if ($onWindows -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            $defaultDir = Join-Path $env:LOCALAPPDATA (Join-Path 'Otter' $version)
        } elseif (-not $onWindows) {
            $dataHome = if (-not [string]::IsNullOrWhiteSpace($env:XDG_DATA_HOME)) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local/share' }
            $defaultDir = Join-Path $dataHome (Join-Path 'otter' $version)
        }
        if ($defaultDir -and (Test-Path -LiteralPath $defaultDir)) {
            $Destination = $defaultDir
        }
    }
}

if ([string]::IsNullOrWhiteSpace($Destination)) {
    throw 'Could not determine installation location. Specify -Destination explicitly.'
}

$destFull = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
$rootFull = [System.IO.Path]::GetPathRoot($destFull).TrimEnd('\', '/')

if ($destFull -eq $rootFull -or $destFull.Length -le 3) {
    throw "Refusing to uninstall a filesystem root: $destFull."
}

if (-not (Test-Path -LiteralPath $destFull)) {
    Write-Output "Otter installation directory does not exist: $destFull (already uninstalled)."
} else {
    # Verify this is an actual Otter installation directory before the
    # recursive delete. -Force does NOT override this: an unrecognised folder
    # (user data, a source checkout that also has otter.cmd) is never removed.
    if (-not (Test-OtterInstallation -Path $destFull)) {
        throw "Refusing to remove $destFull because it is not an Otter installation (no .otter-install marker or Otter runtime file set, or it looks like a source checkout). Pass -Destination with the folder Otter was installed into, or delete this folder yourself if you are sure."
    }

    try {
        Remove-Item -LiteralPath $destFull -Recurse -Force
        Write-Output "Removed Otter files from $destFull."
    } catch {
        throw "Failed to remove files at $destFull (files may be in use by running process): $($_.Exception.Message)"
    }

    # If parent Otter directory in LOCALAPPDATA is now empty, remove it too
    $parent = Split-Path -Parent $destFull
    if ($parent -and (Test-Path -LiteralPath $parent)) {
        $children = Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue
        if ($children.Count -eq 0) {
            Remove-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
        }
    }
}

# macOS and Linux: remove the ~/.local/bin/otter command, but only when the
# installer wrote it and it runs the installation just removed.
if (-not $onWindows) {
    $shim = Join-Path $HOME '.local/bin/otter'
    if (Test-Path -LiteralPath $shim -PathType Leaf) {
        $lines = @(Get-Content -LiteralPath $shim -ErrorAction SilentlyContinue)
        $ours = $lines.Count -ge 3 -and $lines[1].StartsWith('# Otter launcher - written by Install-Otter.ps1')
        if ($ours -and ($lines[2].Contains("'" + $destFull + "/otter'") -or $lines[2].Contains("'" + $destFull.Replace("'", "'\''") + "/otter'"))) {
            Remove-Item -LiteralPath $shim -Force
            Write-Output "Removed the otter command from $(Split-Path -Parent $shim)."
        }
    }
}

# Clean up User PATH (Windows)
$currentPath = if ($onWindows) { [Environment]::GetEnvironmentVariable('Path', 'User') } else { $null }
if ($currentPath) {
    $parts = @($currentPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cleaned = @($parts | Where-Object { [System.IO.Path]::GetFullPath($_).TrimEnd('\', '/') -ne $destFull })
    if ($parts.Count -ne $cleaned.Count) {
        [Environment]::SetEnvironmentVariable('Path', ($cleaned -join ';'), 'User')
        Write-Output 'Removed Otter from the current user PATH. Changes will apply to newly opened terminals.'
    }
}

Write-Output 'Otter has been uninstalled successfully.'
