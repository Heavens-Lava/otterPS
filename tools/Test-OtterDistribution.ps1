[CmdletBinding()]
param(
    [string]$WorkDirectory,
    [switch]$KeepArtifacts,
    # Test this release archive instead of building one (for example the zip
    # Windows PowerShell 5.1 built, on a macOS or Linux runner).
    [string]$Archive
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if (-not $WorkDirectory) {
    $WorkDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-distribution-' + [Guid]::NewGuid().ToString('N'))
}
$work = [System.IO.Path]::GetFullPath($WorkDirectory)
# The PowerShell running this test builds, installs and runs Otter; the
# installed launcher is otter.cmd on Windows and `otter` on macOS and Linux.
$hostExe = (Get-Process -Id $PID).Path
$onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
# @(...): a one-element array from an if would unroll to a plain string, and
# splatting a string passes its characters one by one.
$hostArgs = @(if ($onWindows) { '-NoProfile', '-ExecutionPolicy', 'Bypass' } else { '-NoProfile' })
$launcherName = if ($onWindows) { 'otter.cmd' } else { 'otter' }

function Invoke-InstalledOtter {
    param([string[]]$Arguments, [string]$ExpectedText)
    $output = & (Join-Path $script:installed $launcherName) @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Installed otter failed: $($output -join "`n")" }
    $text = ($output -join "`n").Trim()
    if ($ExpectedText -and $text -notmatch [regex]::Escape($ExpectedText)) {
        throw "Expected installed otter output to contain '$ExpectedText', got '$text'."
    }
}

try {
    New-Item -ItemType Directory -Path $work | Out-Null
    if ($Archive) {
        $archive = [System.IO.Path]::GetFullPath($Archive)
        if ((Split-Path -Leaf $archive) -ne "otter-$version.zip") { throw "Expected otter-$version.zip, got $archive" }
    } else {
        $payloads = Join-Path $work 'payloads'
        & $hostExe @hostArgs -File (Join-Path $PSScriptRoot 'New-OtterDistribution.ps1') -OutputDirectory $payloads -Force | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'Distribution build failed.' }
        $archive = Join-Path $payloads ("otter-$version.zip")
    }

    # Install from the archive a user downloads, extracted the way they would:
    # Expand-Archive on Windows, unzip on macOS and Linux (it keeps the Unix
    # modes the archive records, so `otter` must arrive executable and every
    # path must use forward slashes).
    $extracted = Join-Path $work 'extracted'
    if ($onWindows) {
        Expand-Archive -LiteralPath $archive -DestinationPath $extracted
    } else {
        & unzip -q $archive -d $extracted
        if ($LASTEXITCODE -ne 0) { throw "unzip failed on $archive (exit $LASTEXITCODE)" }
    }
    $package = Join-Path $extracted ("otter-$version")
    $flat = @(Get-ChildItem -LiteralPath $extracted -Recurse | Where-Object { $_.Name.Contains('\') })
    if ($flat.Count -gt 0) { throw "The archive extracted file names containing backslashes: $($flat[0].Name)" }
    if (-not (Test-Path -LiteralPath (Join-Path $package 'src'))) { throw "The archive did not extract to $package" }
    if (-not $onWindows) {
        # Without installing: the extracted `otter` runs directly.
        $direct = (& (Join-Path $package 'otter') --version 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0 -or $direct -notmatch [regex]::Escape("Otter $version")) { throw "The extracted ./otter did not run: $direct" }
    }
    $script:installed = Join-Path $work 'installed'
    & $hostExe @hostArgs -File (Join-Path $package 'Install-Otter.ps1') -Destination $script:installed -Force | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Distribution installation failed.' }

    Invoke-InstalledOtter -Arguments @('--version') -ExpectedText "Otter $version"
    $programs = Join-Path $work 'programs'
    New-Item -ItemType Directory -Path $programs | Out-Null
    foreach ($fixture in @('hello.ot', 'file_json_command.ot', 'date_math.ot', 'web_hello.ot')) {
        Copy-Item -LiteralPath (Join-Path $root (Join-Path 'conformance' (Join-Path 'release' $fixture))) -Destination $programs
    }

    Push-Location $programs
    try {
        Invoke-InstalledOtter -Arguments @('run', 'hello.ot') -ExpectedText 'Hello from Otter'
        Invoke-InstalledOtter -Arguments @('run', 'file_json_command.ot') -ExpectedText 'command-ok'
        Invoke-InstalledOtter -Arguments @('run', 'date_math.ot') -ExpectedText '1'
        Invoke-InstalledOtter -Arguments @('web', 'web_hello.ot', '-NoOpen') -ExpectedText 'compiled to:'
    }
    finally { Pop-Location }

    if (-not $onWindows) {
        # macOS and Linux: -AddToUserPath writes ~/.local/bin/otter, which runs
        # this installation, and the uninstaller removes it again. HOME points at
        # a folder inside the work directory so the real profile is untouched.
        $realHome = $env:HOME
        $env:HOME = Join-Path $work 'home'
        New-Item -ItemType Directory -Path $env:HOME | Out-Null
        try {
            $second = Join-Path $work 'installed-with-path'
            & $hostExe @hostArgs -File (Join-Path $package 'Install-Otter.ps1') -Destination $second -AddToUserPath -Force | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Installation with -AddToUserPath failed.' }
            $shim = Join-Path $env:HOME '.local/bin/otter'
            if (-not (Test-Path -LiteralPath $shim)) { throw "-AddToUserPath did not create $shim" }
            # Installing again (a repair or reinstall) replaces the installer's own command.
            & $hostExe @hostArgs -File (Join-Path $package 'Install-Otter.ps1') -Destination $second -AddToUserPath -Force | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Installing a second time with -AddToUserPath failed.' }
            $shimOut = (& $shim --version 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0 -or $shimOut -notmatch [regex]::Escape("Otter $version")) { throw "The ~/.local/bin/otter command did not run Otter: $shimOut" }
            & $hostExe @hostArgs -File (Join-Path $second 'Uninstall-Otter.ps1') -Destination $second | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Uninstall failed.' }
            if (Test-Path -LiteralPath $shim) { throw "The uninstaller left $shim behind" }
            if (Test-Path -LiteralPath $second) { throw "The uninstaller left $second behind" }
        }
        finally { $env:HOME = $realHome }
    }

    Write-Output "Distribution smoke test passed on PowerShell $($PSVersionTable.PSVersion): $work"
}
finally {
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
