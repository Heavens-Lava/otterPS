# Builds the Microsoft Store package (MSIX) for Otter.
#
#     powershell -NoProfile -File tools\New-OtterMsix.ps1 -OutputDirectory <dir>
#
# The package holds the same payload as the release zip
# (tools/New-OtterDistribution.ps1) plus otter.exe, a launcher that does what
# otter.cmd does: an MSIX app execution alias must name an executable. After a
# Store install, "otter" works in any terminal and the Start menu entry opens
# the Otter REPL.
#
# The identity defaults are the Partner Center values for "Otter Programming
# Language" (Product management > Product identity). The Store signs the
# package on submission; -TestCertificate signs it locally for a test install.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$IdentityName = 'JeffreyMacy.OtterProgrammingLanguage',
    [string]$Publisher = 'CN=D215EFF1-924C-455B-B234-3E3234DCD083',
    [string]$PublisherDisplayName = 'Jeffrey Macy',
    # Four parts; the Store requires the last to be 0. Default: VERSION's x.y.z.
    [string]$PackageVersion = '',
    # A code-signing certificate (thumbprint in Cert:\CurrentUser\My) whose
    # subject equals -Publisher, for a local test install only.
    [string]$TestCertificate = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()

if (-not $PackageVersion) {
    if ($version -notmatch '^(\d+)\.(\d+)\.(\d+)') { throw "VERSION '$version' does not start with x.y.z." }
    $PackageVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3]).0"
    if ($version -match '-') {
        Write-Warning "VERSION is a pre-release ($version); the package is $PackageVersion. Submit only a final release to the Store."
    }
}
if ($PackageVersion -notmatch '^\d+\.\d+\.\d+\.0$') { throw "PackageVersion must be x.y.z.0 for the Store, not '$PackageVersion'." }

# The Windows SDK tools: the newest makeappx/signtool for this machine.
$kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$makeappx = Get-ChildItem -LiteralPath $kits -Recurse -Filter makeappx.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.Directory.Name -eq 'x64' } | Sort-Object FullName | Select-Object -Last 1
if (-not $makeappx) { throw 'makeappx.exe was not found. Install the Windows 10/11 SDK.' }
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "The .NET Framework C# compiler was not found at $csc." }

$outputFull = [System.IO.Path]::GetFullPath($OutputDirectory)
$work = Join-Path $outputFull 'msix-work'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
New-Item -ItemType Directory -Path $work -Force | Out-Null

# 1. The release payload, exactly as the zip has it.
& (Join-Path $PSScriptRoot 'New-OtterDistribution.ps1') -OutputDirectory $work -Force -SkipArchive | Out-Null
$payload = Join-Path $work "otter-$version"
if (-not (Test-Path -LiteralPath (Join-Path $payload 'otter.ps1'))) { throw "The release payload was not built at $payload." }
# The Store installs and updates Otter; the zip's own installer does not belong here.
foreach ($item in @('Install-Otter.ps1', 'Uninstall-Otter.ps1')) {
    Remove-Item -LiteralPath (Join-Path $payload $item) -Force -ErrorAction SilentlyContinue
}

# 2. otter.exe.
$launcherSource = Join-Path $root 'distribution\msix\OtterLauncher.cs'
$cscOutput = & $csc /nologo /optimize+ /target:exe /platform:anycpu "/out:$(Join-Path $payload 'otter.exe')" $launcherSource 2>&1
if ($LASTEXITCODE -ne 0) { throw "Compiling otter.exe failed:`n$($cscOutput -join "`n")" }

# 3. Tile and Store images from the Otter icon.
Add-Type -AssemblyName System.Drawing
$assets = Join-Path $payload 'Assets'
New-Item -ItemType Directory -Path $assets -Force | Out-Null
$icon = [System.Drawing.Image]::FromFile((Join-Path $root 'otter-studio\img\otter-ide-icon.png'))
try {
    foreach ($size in @(@{ Name = 'Square44x44Logo.png'; Px = 44 }, @{ Name = 'Square150x150Logo.png'; Px = 150 }, @{ Name = 'StoreLogo.png'; Px = 50 })) {
        $bitmap = New-Object System.Drawing.Bitmap $size.Px, $size.Px
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($icon, 0, 0, $size.Px, $size.Px)
            $bitmap.Save((Join-Path $assets $size.Name), [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
}
finally { $icon.Dispose() }

# 4. The manifest.
$escape = { param($text) [System.Security.SecurityElement]::Escape($text) }
$manifest = Get-Content -LiteralPath (Join-Path $root 'distribution\msix\AppxManifest.template.xml') -Raw
$manifest = $manifest.Replace('{{IDENTITY_NAME}}', (& $escape $IdentityName)).
    Replace('{{PUBLISHER}}', (& $escape $Publisher)).
    Replace('{{PACKAGE_VERSION}}', $PackageVersion).
    Replace('{{PUBLISHER_DISPLAY_NAME}}', (& $escape $PublisherDisplayName))
[System.IO.File]::WriteAllText((Join-Path $payload 'AppxManifest.xml'), $manifest, [System.Text.UTF8Encoding]::new($false))

# 5. Pack.
$msix = Join-Path $outputFull "otter-$version.msix"
$packOutput = & $makeappx.FullName pack /o /d $payload /p $msix 2>&1
if ($LASTEXITCODE -ne 0) { throw "makeappx pack failed:`n$($packOutput -join "`n")" }

if ($TestCertificate) {
    $signtool = Join-Path $makeappx.DirectoryName 'signtool.exe'
    $signOutput = & $signtool sign /fd SHA256 /sha1 $TestCertificate /s My $msix 2>&1
    if ($LASTEXITCODE -ne 0) { throw "signtool failed:`n$($signOutput -join "`n")" }
}

Remove-Item -LiteralPath $work -Recurse -Force
$hash = (Get-FileHash -LiteralPath $msix -Algorithm SHA256).Hash
Write-Host "Created $msix ($PackageVersion, $((Get-Item -LiteralPath $msix).Length) bytes, SHA-256 $hash)"
