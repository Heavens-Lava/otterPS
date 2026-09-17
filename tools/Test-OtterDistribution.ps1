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

function Invoke-InstalledOtter {
    param([string[]]$Arguments, [string]$ExpectedText)
    $output = & (Join-Path $script:installed 'otter.cmd') @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Installed otter failed: $($output -join "`n")" }
    $text = ($output -join "`n").Trim()
    if ($ExpectedText -and $text -notmatch [regex]::Escape($ExpectedText)) {
        throw "Expected installed otter output to contain '$ExpectedText', got '$text'."
    }
}

try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $payloads = Join-Path $work 'payloads'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'New-OtterDistribution.ps1') -OutputDirectory $payloads -Force | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Distribution build failed.' }

    $package = Join-Path $payloads ("otter-$version-windows-powershell")
    $script:installed = Join-Path $work 'installed'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $package 'Install-Otter.ps1') -Destination $script:installed -Force | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Distribution installation failed.' }

    Invoke-InstalledOtter -Arguments @('--version') -ExpectedText "Otter $version"
    $programs = Join-Path $work 'programs'
    New-Item -ItemType Directory -Path $programs | Out-Null
    foreach ($fixture in @('hello.ot', 'file_json_command.ot', 'date_math.ot', 'web_hello.ot')) {
        Copy-Item -LiteralPath (Join-Path $root (Join-Path 'conformance\release' $fixture)) -Destination $programs
    }

    Push-Location $programs
    try {
        Invoke-InstalledOtter -Arguments @('run', 'hello.ot') -ExpectedText 'Hello from Otter'
        Invoke-InstalledOtter -Arguments @('run', 'file_json_command.ot') -ExpectedText 'command-ok'
        Invoke-InstalledOtter -Arguments @('run', 'date_math.ot') -ExpectedText '1'
        Invoke-InstalledOtter -Arguments @('web', 'web_hello.ot', '-NoOpen') -ExpectedText 'compiled to:'
    }
    finally { Pop-Location }

    Write-Output "Distribution smoke test passed: $work"
}
finally {
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
