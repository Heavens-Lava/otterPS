[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [switch]$Force,
    [switch]$SkipArchive
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1's Compress-Archive stores entry names with backslashes
# (`otter-1.0.0\otter`), which the zip format does not allow: macOS and Linux
# tools extract them as flat files with backslashes in their names. It also
# records no Unix permissions, so the `otter` launcher would lose its
# executable bit. This rewrites every name to forward slashes (in the central
# directory and in each local header; same length, so nothing moves) and marks
# each entry as made on Unix (version-made-by host 3) with mode 644 (755 for
# folders and the listed executables). Windows tools ignore the modes.
function Set-OtterZipUnixModes {
    param([string]$Path, [string[]]$Executables)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $eocd = -1
    for ($i = $bytes.Length - 22; $i -ge 0; $i--) {
        if ([BitConverter]::ToUInt32($bytes, $i) -eq 0x06054b50) { $eocd = $i; break }
    }
    if ($eocd -lt 0) { throw "Not a zip archive: $Path" }
    $count = [BitConverter]::ToUInt16($bytes, $eocd + 10)
    $p = [int][BitConverter]::ToUInt32($bytes, $eocd + 16)
    for ($n = 0; $n -lt $count; $n++) {
        if ([BitConverter]::ToUInt32($bytes, $p) -ne 0x02014b50) { throw "Unexpected zip central directory layout in $Path" }
        $nameLength = [BitConverter]::ToUInt16($bytes, $p + 28)
        $extraLength = [BitConverter]::ToUInt16($bytes, $p + 30)
        $commentLength = [BitConverter]::ToUInt16($bytes, $p + 32)
        $local = [int][BitConverter]::ToUInt32($bytes, $p + 42)
        if ([BitConverter]::ToUInt32($bytes, $local) -ne 0x04034b50) { throw "Unexpected zip local header layout in $Path" }
        for ($k = 0; $k -lt $nameLength; $k++) {
            if ($bytes[$p + 46 + $k] -eq 0x5C) { $bytes[$p + 46 + $k] = 0x2F }
        }
        $localNameLength = [BitConverter]::ToUInt16($bytes, $local + 26)
        for ($k = 0; $k -lt $localNameLength; $k++) {
            if ($bytes[$local + 30 + $k] -eq 0x5C) { $bytes[$local + 30 + $k] = 0x2F }
        }
        $name = [System.Text.Encoding]::UTF8.GetString($bytes, $p + 46, $nameLength)
        $mode = if ($name.EndsWith('/')) { 0x41ED } elseif ($Executables -contains $name) { 0x81ED } else { 0x81A4 }
        $dos = if ($name.EndsWith('/')) { 0x10 } else { 0 }
        $bytes[$p + 5] = 3
        [BitConverter]::GetBytes([uint32]($mode * 65536 + $dos)).CopyTo($bytes, $p + 38)
        $p += 46 + $nameLength + $extraLength + $commentLength
    }
    [System.IO.File]::WriteAllBytes($Path, $bytes)
}

$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
$outputFull = [System.IO.Path]::GetFullPath($OutputDirectory)
# One payload for every platform: otter.cmd (Windows) and the `otter` shell
# launcher (macOS, Linux) sit side by side; both run otter.ps1.
$name = "otter-$version"
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

foreach ($item in @('otter.ps1', 'otter.cmd', 'otter', 'Otter.Contract.psm1', 'VERSION', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'INSTALL.md', 'TOUR.md')) {
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
        Path = $_.FullName.Substring($stage.Length).TrimStart('\', '/').Replace('\', '/')
        Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
}
[pscustomobject]@{
    Product = 'Otter'
    Version = $version
    Runtime = 'Windows: Windows PowerShell 5.1 or PowerShell 7. macOS and Linux: PowerShell 7.'
    EntryPoint = 'otter.cmd (Windows), otter (macOS, Linux)'
    Files = $files
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage 'release-manifest.json') -Encoding UTF8

if (-not $SkipArchive) {
    $archive = Join-Path $outputFull ($name + '.zip')
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    Compress-Archive -LiteralPath $stage -DestinationPath $archive -Force
    Set-OtterZipUnixModes -Path $archive -Executables @("$name/otter")
    (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash | Set-Content -LiteralPath ($archive + '.sha256') -Encoding ASCII
    Write-Output "Created $archive"
}
Write-Output "Created release payload $stage"
