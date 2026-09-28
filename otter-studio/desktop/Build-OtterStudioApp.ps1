<#
.SYNOPSIS
    Builds and installs the Otter Studio desktop app (Windows).

.DESCRIPTION
    Packages otter-studio/desktop (a small Electron shell) with electron-builder
    into a per-user NSIS installer, then installs it silently. The installed app
    serves Studio from the Otter checkout this script lives in, so pulling new
    commits into that checkout updates the app without reinstalling.

    Needs an Electron toolchain (electron + electron-builder). By default the one
    under ..\formwright\node_modules is used; pass -Toolchain to choose another.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File otter-studio\desktop\Build-OtterStudioApp.ps1
#>
[CmdletBinding()]
param(
    [string]$Toolchain,
    [switch]$NoInstall
)

$ErrorActionPreference = 'Stop'
$desktopDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $desktopDir '..\..')).Path
if (-not $Toolchain) {
    $Toolchain = if ($env:OTTER_ELECTRON_TOOLCHAIN) { $env:OTTER_ELECTRON_TOOLCHAIN } else { Join-Path (Split-Path -Parent $repoRoot) 'formwright' }
}
$builderCli = Join-Path $Toolchain 'node_modules\electron-builder\out\cli\cli.js'
$electronPkg = Join-Path $Toolchain 'node_modules\electron\package.json'
if (-not (Test-Path $builderCli) -or -not (Test-Path $electronPkg)) {
    throw "No Electron toolchain in $Toolchain (need node_modules\electron and node_modules\electron-builder)."
}
$electronVersion = (Get-Content $electronPkg -Raw | ConvertFrom-Json).version

# 1. Stage the app: shell files, the checkout path, and the icon.
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-studio-app-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $stage 'build') -Force | Out-Null
Copy-Item (Join-Path $desktopDir 'main.js'), (Join-Path $desktopDir 'preload.js') -Destination $stage
$pkg = Get-Content (Join-Path $desktopDir 'package.json') -Raw | ConvertFrom-Json
$pkg.otterStudio.root = $repoRoot
[System.IO.File]::WriteAllText((Join-Path $stage 'package.json'), ($pkg | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

# The icon: the Otter mascot on the Studio blue, rendered at 256x256.
Add-Type -AssemblyName System.Drawing
$iconPng = Join-Path $stage 'build\icon.png'
$sourcePng = Join-Path $desktopDir 'icon.png'
if (Test-Path $sourcePng) {
    Copy-Item $sourcePng $iconPng
} else {
    throw "Missing $sourcePng"
}

# 2. electron-builder configuration.
$outDir = Join-Path $repoRoot 'otter-studio\desktop\dist'
$config = [ordered]@{
    appId = 'org.otterlang.studio'
    productName = 'Otter Studio'
    electronVersion = $electronVersion
    directories = [ordered]@{ output = $outDir; buildResources = 'build' }
    files = @('main.js', 'preload.js', 'package.json', 'build/icon.png')
    asar = $true
    npmRebuild = $false
    nodeGypRebuild = $false
    win = [ordered]@{ target = @('nsis'); icon = 'build/icon.png'; artifactName = 'OtterStudio-Setup.${ext}' }
    nsis = [ordered]@{
        oneClick = $true
        perMachine = $false
        createDesktopShortcut = $true
        createStartMenuShortcut = $true
        shortcutName = 'Otter Studio'
        runAfterFinish = $false
    }
}
$configPath = Join-Path $stage 'electron-builder.json'
[System.IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Building Otter Studio desktop app (Electron $electronVersion)..."
$savedRunAsNode = $env:ELECTRON_RUN_AS_NODE
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
$env:CSC_IDENTITY_AUTO_DISCOVERY = 'false'
Push-Location $stage
try {
    & node $builderCli --win nsis --config $configPath --projectDir $stage 2>&1 | ForEach-Object { if ($_ -match 'error|⨯') { Write-Host $_ -ForegroundColor Red } }
    if ($LASTEXITCODE -ne 0) { throw "electron-builder failed with exit code $LASTEXITCODE." }
} finally {
    Pop-Location
    if ($null -ne $savedRunAsNode) { $env:ELECTRON_RUN_AS_NODE = $savedRunAsNode }
}
foreach ($extra in @('win-unpacked', 'builder-debug.yml', 'builder-effective-config.yaml', '.icon-ico')) {
    Remove-Item -LiteralPath (Join-Path $outDir $extra) -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem $outDir -Filter '*.blockmap' | Remove-Item -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue

$installer = Join-Path $outDir 'OtterStudio-Setup.exe'
Write-Host "Installer: $installer ($([Math]::Round((Get-Item $installer).Length / 1MB, 1)) MB)"

# 3. Install for this user (silent), replacing an earlier install.
if (-not $NoInstall) {
    Get-Process -Name 'Otter Studio' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath $installer -ArgumentList '/S' -Wait
    # electron-builder names the per-user install folder after the package name.
    $exe = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs') -Filter 'Otter Studio.exe' -Recurse -Depth 1 -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if ($exe -and (Test-Path $exe)) {
        Write-Host "Installed: $exe" -ForegroundColor Green
        Write-Host "Start menu and Desktop shortcuts: 'Otter Studio'. Right-click the running app on the taskbar > Pin to taskbar."
    } else {
        throw "The installer ran but $exe was not found."
    }
}
