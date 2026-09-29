[CmdletBinding()]
param(
    [string]$WorkDirectory,
    [switch]$KeepArtifacts
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
$hostArgs = if ($onWindows) { @('-NoProfile', '-ExecutionPolicy', 'Bypass') } else { @('-NoProfile') }
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
    $payloads = Join-Path $work 'payloads'
    & $hostExe @hostArgs -File (Join-Path $PSScriptRoot 'New-OtterDistribution.ps1') -OutputDirectory $payloads -Force | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Distribution build failed.' }

    $package = Join-Path $payloads ("otter-$version")
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
