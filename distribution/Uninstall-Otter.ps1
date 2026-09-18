[CmdletBinding()]
param(
    [string]$Destination,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Determine destination to uninstall
if (-not $Destination) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'otter.cmd')) {
        $Destination = $PSScriptRoot
    } elseif (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $versionFile = Join-Path $PSScriptRoot 'VERSION'
        $version = if (Test-Path -LiteralPath $versionFile) { (Get-Content -LiteralPath $versionFile -Raw).Trim() } else { '*' }
        $defaultDir = Join-Path $env:LOCALAPPDATA (Join-Path 'Otter' $version)
        if (Test-Path -LiteralPath $defaultDir) {
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
    # Verify this is an actual Otter installation directory
    if (-not (Test-Path -LiteralPath (Join-Path $destFull 'otter.cmd')) -and -not $Force) {
        throw "Directory $destFull does not appear to be an Otter installation (otter.cmd missing). Use -Force to override."
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

# Clean up User PATH
$currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($currentPath) {
    $parts = @($currentPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $cleaned = @($parts | Where-Object { [System.IO.Path]::GetFullPath($_).TrimEnd('\', '/') -ne $destFull })
    if ($parts.Count -ne $cleaned.Count) {
        [Environment]::SetEnvironmentVariable('Path', ($cleaned -join ';'), 'User')
        Write-Output 'Removed Otter from the current user PATH. Changes will apply to newly opened terminals.'
    }
}

Write-Output 'Otter has been uninstalled successfully.'
