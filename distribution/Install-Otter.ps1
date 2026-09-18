[CmdletBinding()]
param(
    [string]$Destination,
    [switch]$AddToUserPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
# The source template lives in distribution\, while the builder copies this
# script to the root of the extracted release payload. Support both locations
# so the installed artifact never depends on repository layout.
$packageRoot = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'VERSION')) {
    $PSScriptRoot
} else {
    Split-Path -Parent $PSScriptRoot
}
$version = (Get-Content -LiteralPath (Join-Path $packageRoot 'VERSION') -Raw).Trim()

if (-not $Destination) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is unavailable. Specify -Destination explicitly.'
    }
    $Destination = Join-Path $env:LOCALAPPDATA (Join-Path 'Otter' $version)
}

$required = @('otter.ps1', 'otter.cmd', 'Otter.Contract.psm1', 'VERSION', 'src')
foreach ($item in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $item))) {
        throw "This is not a complete Otter distribution: missing $item."
    }
}

$destinationFull = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
$packageFull = [System.IO.Path]::GetFullPath($packageRoot).TrimEnd('\', '/')
$rootFull = [System.IO.Path]::GetPathRoot($destinationFull).TrimEnd('\', '/')
if ([string]::IsNullOrWhiteSpace($destinationFull) -or $destinationFull -eq $rootFull -or $destinationFull -eq $packageFull) {
    throw 'Refusing an installation destination that is a filesystem root or the extracted package itself.'
}
if (Test-Path -LiteralPath $destinationFull) {
    if (-not $Force) {
        throw "Otter is already installed at $destinationFull. Re-run with -Force to replace only this version."
    }
    Remove-Item -LiteralPath $destinationFull -Recurse -Force
}
New-Item -ItemType Directory -Path $destinationFull | Out-Null

foreach ($item in @('otter.ps1', 'otter.cmd', 'Otter.Contract.psm1', 'VERSION', 'README.md', 'Uninstall-Otter.ps1')) {
    $source = Join-Path $packageRoot $item
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $destinationFull -Force }
}
Copy-Item -LiteralPath (Join-Path $packageRoot 'src') -Destination $destinationFull -Recurse -Force

$installedCommand = Join-Path $destinationFull 'otter.cmd'
& $installedCommand --version | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Installed Otter failed its --version check (exit $LASTEXITCODE)." }

if ($AddToUserPath) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($current -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts -notcontains $destinationFull) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $destinationFull) -join ';'), 'User')
        Write-Output 'Added Otter to the current user PATH. Open a new terminal before typing otter.'
    }
}

Write-Output "Otter $version installed to $destinationFull"
