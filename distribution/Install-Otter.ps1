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

# Windows (Windows PowerShell 5.1 or PowerShell 7) uses otter.cmd; macOS and
# Linux use the `otter` shell launcher and PowerShell 7.
$onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
$launcher = if ($onWindows) { 'otter.cmd' } else { 'otter' }

if (-not $Destination) {
    if ($onWindows) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            throw 'LOCALAPPDATA is unavailable. Specify -Destination explicitly.'
        }
        $Destination = Join-Path $env:LOCALAPPDATA (Join-Path 'Otter' $version)
    } else {
        # The XDG data folder (~/.local/share unless XDG_DATA_HOME says otherwise).
        $dataHome = if (-not [string]::IsNullOrWhiteSpace($env:XDG_DATA_HOME)) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local/share' }
        $Destination = Join-Path $dataHome (Join-Path 'otter' $version)
    }
}

$required = @('otter.ps1', $launcher, 'Otter.Contract.psm1', 'VERSION', 'src')
foreach ($item in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $item))) {
        throw "This is not a complete Otter distribution: missing $item."
    }
}

# --- Destination safety --------------------------------------------------
# -Force replaces an existing destination with Remove-Item -Recurse, and
# INSTALL.md tells users to pass -Force when upgrading. Everything below
# exists so that a mistyped or unlucky -Destination can never delete user
# data: the installer only ever deletes a folder it can recognise as an
# earlier Otter installation, and refuses destinations that are dangerous
# even when empty or recognised (roots, the profile, special folders, and
# anything overlapping the extracted package it is copying from).

# Returns $true only for a folder that is recognisably an Otter installation.
# The same function is duplicated in Uninstall-Otter.ps1, because both
# scripts ship standalone in the distribution zip; keep the copies identical.
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

# $true when $Path is $Ancestor itself or lies anywhere beneath it. Both are
# full paths without a trailing separator. Case-insensitive, as on Windows,
# so the check errs on the side of refusing.
function Test-PathIsSameOrAncestor {
    param([string]$Ancestor, [string]$Path)
    if ($Path.Equals($Ancestor, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $Path.StartsWith($Ancestor + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

# Require a fully qualified destination. A drive-relative path such as 'C:'
# or 'C:Otter' silently resolves against the current folder on that drive
# (which may be the user's profile), and a plain relative path resolves
# against the process folder rather than the PowerShell location, so either
# could point the -Force delete somewhere the user never intended.
$isWindowsPathStyle = [System.IO.Path]::DirectorySeparatorChar -eq '\'
$isFullyQualified = if ($isWindowsPathStyle) {
    ($Destination -match '^[A-Za-z]:[\\/]') -or ($Destination -match '^[\\/]{2}[^\\/]')
} else {
    $Destination.StartsWith('/')
}
if (-not $isFullyQualified) {
    throw "Refusing installation destination '$Destination' because it is not a full path. Pass a complete folder path such as C:\Tools\Otter, or omit -Destination to use the default per-user location."
}

$destinationFull = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
$packageFull = [System.IO.Path]::GetFullPath($packageRoot).TrimEnd('\', '/')
$rootFull = [System.IO.Path]::GetPathRoot($destinationFull).TrimEnd('\', '/')
# A filesystem root (C:\ normalises to 'C:', and / to '') is never a valid
# install folder: replacing it would wipe the whole drive.
if ([string]::IsNullOrWhiteSpace($destinationFull) -or $destinationFull -eq $rootFull) {
    throw "Refusing installation destination '$Destination' because it is a filesystem root. Choose a dedicated folder such as C:\Tools\Otter."
}
# The destination must not overlap the extracted package: if it is the
# package or an ancestor of it, replacing it deletes the package while it is
# being copied; if it is inside the package, the install copies into itself.
if (Test-PathIsSameOrAncestor -Ancestor $destinationFull -Path $packageFull) {
    throw "Refusing installation destination $destinationFull because it is, or contains, the extracted Otter package at $packageFull. Choose a folder outside the package, or omit -Destination to use the default per-user location."
}
if (Test-PathIsSameOrAncestor -Ancestor $packageFull -Path $destinationFull) {
    throw "Refusing installation destination $destinationFull because it is inside the extracted Otter package at $packageFull. Choose a folder outside the package, or omit -Destination to use the default per-user location."
}
# The user's profile and well-known special folders (and any folder that
# contains one of them) are refused even when empty: installing into one
# would make a later -Force upgrade or uninstall delete that whole folder.
# GetFolderPath returns '' for folders a platform lacks (e.g. Windows on
# Linux), so empty values are skipped rather than treated as a path.
$specialFolders = @($HOME, $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, [System.IO.Path]::GetTempPath())
foreach ($name in @('UserProfile', 'Desktop', 'DesktopDirectory', 'MyDocuments', 'MyMusic', 'MyPictures', 'MyVideos', 'Favorites', 'StartMenu', 'Programs', 'Startup', 'Templates', 'ApplicationData', 'LocalApplicationData', 'CommonApplicationData', 'CommonDesktopDirectory', 'CommonDocuments', 'ProgramFiles', 'ProgramFilesX86', 'CommonProgramFiles', 'Windows', 'System', 'SystemX86')) {
    $specialFolders += [Environment]::GetFolderPath([Environment+SpecialFolder]$name)
}
foreach ($special in $specialFolders) {
    if ([string]::IsNullOrWhiteSpace($special)) { continue }
    $specialFull = [System.IO.Path]::GetFullPath($special).TrimEnd('\', '/')
    if ([string]::IsNullOrWhiteSpace($specialFull)) { continue }
    if (Test-PathIsSameOrAncestor -Ancestor $destinationFull -Path $specialFull) {
        throw "Refusing installation destination $destinationFull because it is, or contains, the special folder $specialFull. Install into a dedicated subfolder instead, such as $(Join-Path $destinationFull 'Otter'), or omit -Destination to use the default per-user location."
    }
}

if (Test-Path -LiteralPath $destinationFull) {
    if (-not (Test-Path -LiteralPath $destinationFull -PathType Container)) {
        throw "Refusing installation destination $destinationFull because it is a file, not a folder. Choose a folder path instead."
    }
    # An existing EMPTY folder is fine to install into; nothing is deleted.
    # A non-empty folder is only ever replaced when it is recognisably an
    # Otter installation - never user data, a source checkout, or anything
    # else, whether or not -Force was passed - and even then only with -Force.
    $existingItems = @(Get-ChildItem -LiteralPath $destinationFull -Force)
    if ($existingItems.Count -gt 0) {
        if (-not (Test-OtterInstallation -Path $destinationFull)) {
            throw "Refusing to install into $destinationFull because the folder is not empty and is not an Otter installation, so it will not be replaced even with -Force. Choose a new or empty folder, such as $(Join-Path $destinationFull 'Otter'), or move the folder's contents elsewhere first."
        }
        if (-not $Force) {
            throw "Otter is already installed at $destinationFull. Re-run with -Force to replace this installation."
        }
        Remove-Item -LiteralPath $destinationFull -Recurse -Force
    }
}
if (-not (Test-Path -LiteralPath $destinationFull)) {
    New-Item -ItemType Directory -Path $destinationFull | Out-Null
}
# Mark the folder as an Otter installation before copying anything, so that
# Test-OtterInstallation (here and in Uninstall-Otter.ps1) recognises it -
# including after an interrupted install - and nothing else.
Set-Content -LiteralPath (Join-Path $destinationFull '.otter-install') -Value @(
    'Otter installation marker - written by Install-Otter.ps1. Install-Otter -Force and Uninstall-Otter only replace or remove folders that carry it.',
    "Version: $version"
) -Encoding ASCII

foreach ($item in @('otter.ps1', 'otter.cmd', 'otter.exe', 'otter', 'Otter.Contract.psm1', 'VERSION', 'README.md', 'Uninstall-Otter.ps1', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'INSTALL.md', 'TOUR.md')) {
    $source = Join-Path $packageRoot $item
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $destinationFull -Force }
}
Copy-Item -LiteralPath (Join-Path $packageRoot 'src') -Destination $destinationFull -Recurse -Force
if (Test-Path -LiteralPath (Join-Path $packageRoot 'examples')) {
    Copy-Item -LiteralPath (Join-Path $packageRoot 'examples') -Destination $destinationFull -Recurse -Force
}

$installedCommand = Join-Path $destinationFull $launcher
if (-not $onWindows) {
    # A zip does not carry the executable bit; the launcher needs it.
    & chmod +x $installedCommand
    if ($LASTEXITCODE -ne 0) { throw "Could not make $installedCommand executable (chmod exit $LASTEXITCODE)." }
}
& $installedCommand --version | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Installed Otter failed its --version check (exit $LASTEXITCODE)." }

if ($AddToUserPath -and -not $onWindows) {
    # macOS and Linux: a small `otter` command in ~/.local/bin that runs this
    # installation. It is only ever replaced when it is one this installer
    # wrote (its second line says so), never another program called otter.
    $binDir = Join-Path $HOME '.local/bin'
    $shim = Join-Path $binDir 'otter'
    $shimMarker = '# Otter launcher - written by Install-Otter.ps1'
    if (Test-Path -LiteralPath $shim) {
        $existing = @(Get-Content -LiteralPath $shim -TotalCount 2 -ErrorAction SilentlyContinue)
        if ($existing.Count -lt 2 -or -not $existing[1].StartsWith($shimMarker)) {
            throw "Refusing to replace $shim because it was not written by the Otter installer. Remove or rename it, or run $installedCommand directly."
        }
    }
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    $escaped = $installedCommand.Replace("'", "'\''")
    [System.IO.File]::WriteAllText($shim, "#!/bin/sh`n$shimMarker ($version)`nexec '$escaped' `"`$@`"`n", [System.Text.UTF8Encoding]::new($false))
    & chmod +x $shim
    if ($LASTEXITCODE -ne 0) { throw "Could not make $shim executable (chmod exit $LASTEXITCODE)." }
    $pathDirs = @($env:PATH -split ':' | ForEach-Object { $_.TrimEnd('/') })
    if ($pathDirs -contains $binDir.TrimEnd('/')) {
        Write-Output "Added the otter command to $binDir."
    } else {
        Write-Output "Added the otter command to $binDir, which is not on your PATH yet. Add this line to your shell profile (~/.zshrc or ~/.bashrc) and open a new terminal:"
        Write-Output "    export PATH=`"`$HOME/.local/bin:`$PATH`""
    }
}

if ($AddToUserPath -and $onWindows) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($current -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts -notcontains $destinationFull) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $destinationFull) -join ';'), 'User')
        Write-Output 'Added Otter to the current user PATH. Open a new terminal before typing otter.'
    }
}

Write-Output "Otter $version installed to $destinationFull"
