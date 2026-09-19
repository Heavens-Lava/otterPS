[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$Force,
    [switch]$SkipArchive
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
$outputFull = [System.IO.Path]::GetFullPath($OutputDirectory)
$name = "otter-$version-windows-powershell"
$stage = Join-Path $outputFull $name

if (-not (Test-Path -LiteralPath (Join-Path $root 'distribution\Install-Otter.ps1'))) {
    throw 'distribution\Install-Otter.ps1 is required to build a release payload.'
}
New-Item -ItemType Directory -Path $outputFull -Force | Out-Null
if (Test-Path -LiteralPath $stage) {
    if (-not $Force) { throw "Distribution directory already exists: $stage. Use -Force to replace it." }
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage | Out-Null

foreach ($item in @('otter.ps1', 'otter.cmd', 'Otter.Contract.psm1', 'VERSION', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'INSTALL.md', 'TOUR.md')) {
    $src = Join-Path $root $item
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination $stage -Force
    }
}
Copy-Item -LiteralPath (Join-Path $root 'src') -Destination $stage -Recurse -Force
$examplesStage = Join-Path $stage 'examples'
New-Item -ItemType Directory -Path $examplesStage -Force | Out-Null
foreach ($ex in @('hello.ot', 'csv.ot', 'download.ot', 'cli-arguments.ot', 'conditions.ot', 'objects.ot', 'math.ot', 'files.ot', 'calculator.ot', 'hello-app.ot')) {
    $exPath = Join-Path (Join-Path $root 'examples') $ex
    if (Test-Path -LiteralPath $exPath) {
        Copy-Item -LiteralPath $exPath -Destination $examplesStage -Force
    }
}
Copy-Item -LiteralPath (Join-Path $root 'distribution\Install-Otter.ps1') -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $root 'distribution\Uninstall-Otter.ps1') -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $root 'distribution\README.md') -Destination (Join-Path $stage 'README.md') -Force

$files = Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
    [pscustomobject]@{
        Path = $_.FullName.Substring($stage.Length).TrimStart('\')
        Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
}
[pscustomobject]@{
    Product = 'Otter'
    Version = $version
    Runtime = 'Windows PowerShell 5.1'
    EntryPoint = 'otter.cmd'
    Files = $files
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage 'release-manifest.json') -Encoding UTF8

if (-not $SkipArchive) {
    $archive = Join-Path $outputFull ($name + '.zip')
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    Compress-Archive -LiteralPath $stage -DestinationPath $archive -Force
    (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash | Set-Content -LiteralPath ($archive + '.sha256') -Encoding ASCII
    Write-Output "Created $archive"
}
Write-Output "Created release payload $stage"
