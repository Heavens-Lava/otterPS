using module ..\Otter.Contract.psm1

# Otter.Package.psm1 - turns an Electron export into distributables.
#
#   Otter source -> web compiler -> Electron export -> electron-builder -> installer / portable
#
# `otter package` runs the ordinary Electron build (Otter.Project.psm1 +
# Otter.Electron.psm1) into the project's output folder, writes an
# electron-builder configuration next to it, and hands that folder to
# electron-builder. Nothing is compiled a second time.
#
# Building needs a toolchain (Node.js with electron and electron-builder) on
# the developer's machine. People who receive the installer or the portable
# .exe need nothing: Electron is inside the package, and Otter, PowerShell and
# Node.js are not involved at run time.
#
# Windows (NSIS installer + portable .exe) is implemented and tested. The
# configuration is structured per platform so macOS and Linux can be added,
# but they are refused until they have been run and tested on those systems.

$script:ToolchainElectronRange = '^32.0.0'
$script:ToolchainBuilderRange = '^25.0.0'

# -----------------------------------------------------------------------------
# Toolchain
# -----------------------------------------------------------------------------

# Where electron-builder lives. In order:
#   1. $env:OTTER_ELECTRON_TOOLCHAIN  - a folder whose node_modules has it
#   2. <project>/node_modules          - the project installed it itself
#   3. %LOCALAPPDATA%\Otter\electron-toolchain - Otter's own shared copy
function Get-OtterElectronToolchain {
    param([string]$ProjectRoot)

    $candidates = @()
    if ($env:OTTER_ELECTRON_TOOLCHAIN) { $candidates += $env:OTTER_ELECTRON_TOOLCHAIN }
    if ($ProjectRoot) { $candidates += $ProjectRoot }
    $candidates += (Get-OtterSharedToolchainRoot)

    foreach ($root in $candidates) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $cli = Join-Path $root 'node_modules\electron-builder\out\cli\cli.js'
        $electronPackage = Join-Path $root 'node_modules\electron\package.json'
        if ((Test-Path -LiteralPath $cli -PathType Leaf) -and (Test-Path -LiteralPath $electronPackage -PathType Leaf)) {
            $electronVersion = (Get-Content -LiteralPath $electronPackage -Raw | ConvertFrom-Json).version
            return [pscustomobject]@{
                Root            = (Resolve-Path -LiteralPath $root).Path
                BuilderCli      = $cli
                ElectronVersion = [string]$electronVersion
            }
        }
    }
    return $null
}

function Get-OtterSharedToolchainRoot {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.otter' }
    return Join-Path $base 'Otter\electron-toolchain'
}

# One-time: install electron and electron-builder into Otter's shared folder.
# Needs npm; downloads Electron (about 100 MB) the first time.
function Install-OtterElectronToolchain {
    param([switch]$Quiet)

    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (-not $npm) { $npm = Get-Command npm -ErrorAction SilentlyContinue }
    if (-not $npm) {
        throw [OtterError]::new("Packaging a desktop application needs Node.js and npm on this computer (only to build - people who run your app need nothing). Install Node.js from nodejs.org and try again.", 0, 'runtime')
    }

    $root = Get-OtterSharedToolchainRoot
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $manifest = @"
{
  "name": "otter-electron-toolchain",
  "private": true,
  "description": "Electron and electron-builder for otter package",
  "devDependencies": {
    "electron": "$script:ToolchainElectronRange",
    "electron-builder": "$script:ToolchainBuilderRange"
  }
}
"@
    [System.IO.File]::WriteAllText((Join-Path $root 'package.json'), $manifest, (New-Object System.Text.UTF8Encoding($false)))

    if (-not $Quiet) {
        Write-Host "Installing the Electron packaging toolchain into $root (one time, about 100 MB)..."
    }
    $installOutput = & $npm.Source install --no-audit --no-fund --loglevel=error --prefix $root 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw [OtterError]::new("Installing the packaging toolchain failed:`n$($installOutput -join "`n")", 0, 'runtime')
    }
    $toolchain = Get-OtterElectronToolchain
    if (-not $toolchain) {
        throw [OtterError]::new("The packaging toolchain was installed but electron-builder could not be found in $root.", 0, 'runtime')
    }
    return $toolchain
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# The electron-builder configuration for a project. Pure: nothing is read
# from or written to disk, so tests can check it directly.
function New-OtterElectronBuilderConfig {
    param(
        # An OtterProject. Untyped on purpose: PowerShell classes loaded twice
        # (using module + Import-Module -Force) are different types to the binder.
        [Parameter(Mandatory)]$Project,
        [Parameter(Mandatory)][string]$Platform,
        [string[]]$Kinds = @('installer', 'portable'),
        [Parameter(Mandatory)][string]$OutputDir,
        [string]$ElectronVersion,
        [string]$IconFile
    )

    $platformKey = $Platform.Trim().ToLowerInvariant()
    if ($platformKey -notin @('windows', 'macos', 'linux')) {
        throw [OtterError]::new("otter package: --target `"$Platform`" is not a packaging target I know. Use windows (macos and linux will follow once they have been tested).", 0, 'check')
    }
    if ($platformKey -ne 'windows') {
        throw [OtterError]::new("otter package: packaging for $platformKey is not available yet. It has not been run and tested on that operating system, so Otter does not claim it works. Windows packaging is available today.", 0, 'check')
    }

    $normalizedKinds = @($Kinds | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    if ($normalizedKinds.Count -eq 0) { $normalizedKinds = @('installer', 'portable') }
    foreach ($kind in $normalizedKinds) {
        if ($kind -notin @('installer', 'portable')) {
            throw [OtterError]::new("otter package: `"$kind`" is not a package kind I know. Use installer, portable, or both.", 0, 'check')
        }
    }

    $productName = if ([string]::IsNullOrWhiteSpace($Project.Name)) { 'Otter Application' } else { $Project.Name }
    $appId = 'org.otterlang.' + (($productName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-'))
    if ($appId.EndsWith('.')) { $appId += 'app' }

    $winTargets = @()
    if ('installer' -in $normalizedKinds) { $winTargets += 'nsis' }
    if ('portable' -in $normalizedKinds) { $winTargets += 'portable' }

    $config = [ordered]@{
        appId       = $appId
        productName = $productName
        copyright   = if ([string]::IsNullOrWhiteSpace($Project.Author)) { "Copyright (c) $([DateTime]::Now.Year)" } else { "Copyright (c) $([DateTime]::Now.Year) $($Project.Author)" }
        directories = [ordered]@{
            output = $OutputDir
            # electron-builder resources (icons) live in the export, not the project.
            buildResources = 'build'
        }
        files       = @('main.js', 'preload.js', 'package.json', 'app/**/*')
        asar        = $true
        # The export has no native modules and no npm dependencies: nothing to rebuild or install.
        npmRebuild  = $false
        nodeGypRebuild = $false
        buildDependenciesFromSource = $false
        win         = [ordered]@{
            target = $winTargets
            artifactName = '${productName}-${version}-${arch}.${ext}'
        }
        nsis        = [ordered]@{
            oneClick = $false
            perMachine = $false
            allowToChangeInstallationDirectory = $true
            createDesktopShortcut = $true
            artifactName = '${productName}-${version}-Setup.${ext}'
        }
        portable    = [ordered]@{
            artifactName = '${productName}-${version}-Portable.${ext}'
        }
    }
    # electron-builder rejects unknown keys, so the per-platform structure is
    # this function's switch above, not a section in the file.
    if ($ElectronVersion) { $config.electronVersion = $ElectronVersion }
    if ($IconFile) { $config.win.icon = $IconFile }
    return $config
}

# Width and height from a PNG's IHDR chunk, or $null if the file is not a PNG.
function Get-OtterPngSize {
    param([Parameter(Mandatory)][string]$Path)
    $bytes = New-Object byte[] 24
    $stream = [System.IO.File]::OpenRead($Path)
    try { $read = $stream.Read($bytes, 0, 24) } finally { $stream.Close() }
    if ($read -lt 24 -or $bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50 -or $bytes[2] -ne 0x4E -or $bytes[3] -ne 0x47) { return $null }
    # Cast before shifting: PowerShell keeps a shifted [byte] as a byte.
    $width = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
    $height = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
    return [pscustomobject]@{ Width = $width; Height = $height }
}

# -----------------------------------------------------------------------------
# Packaging
# -----------------------------------------------------------------------------

# Structured progress for tools that drive `otter package` (Otter Studio's
# Build -> Desktop App). One line per event, prefixed so it can never be
# mistaken for ordinary output:
#   @otter-progress {"step":"export","status":"done","label":"..."}
# Steps, in order: check, export, styles, configure, runtime, portable,
# installer, done (or failed). Only emitted with -Progress.
function Write-OtterPackageProgress {
    param([Parameter(Mandatory)][hashtable]$Event)
    Write-Host ('@otter-progress ' + (ConvertTo-Json -InputObject $Event -Compress -Depth 4))
}

function Invoke-OtterProjectPackage {
    param(
        [string]$Target = '.',
        [string]$Platform = 'windows',
        [string[]]$Kinds = @('installer', 'portable'),
        [string]$OutputDir,
        # Build the export and write the configuration, but do not run electron-builder.
        [switch]$DryRun,
        [switch]$Quiet,
        # Emit @otter-progress lines (see Write-OtterPackageProgress).
        [switch]$Progress
    )

    $emit = {
        param([hashtable]$Event)
        if ($Progress) { Write-OtterPackageProgress -Event $Event }
    }

    if (-not (Get-Command Get-OtterProject -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Project.psm1') -Global
    }
    $project = Get-OtterProject -Path $Target
    if ($project.Target.ToLowerInvariant() -in @('console', 'automation', 'server')) {
        throw [OtterError]::new("otter package: a $($project.Target) project has no window to package. Packaging is for desktop, web and game projects.", 0, 'check')
    }

    $rootDir = $project.RootDirectory
    $packagesDir = if ($OutputDir) {
        if ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $OutputDir)) }
    } else {
        Join-Path $rootDir 'packages'
    }

    # Validate the configuration inputs before spending time on a build.
    $iconSource = $null
    if (-not [string]::IsNullOrWhiteSpace($project.Icon)) {
        $iconSource = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $project.Icon))
        if (-not (Test-Path -LiteralPath $iconSource -PathType Leaf)) {
            throw [OtterError]::new("$($project.ManifestFileName): icon `"$($project.Icon)`" does not exist.", 0, 'check')
        }
        $iconExtension = [System.IO.Path]::GetExtension($iconSource).ToLowerInvariant()
        if ($iconExtension -notin @('.ico', '.png')) {
            throw [OtterError]::new("$($project.ManifestFileName): icon `"$($project.Icon)`" must be a .ico or .png file.", 0, 'check')
        }
        if ($iconExtension -eq '.png') {
            # Windows icons are built from the PNG; electron-builder needs 256x256 or larger.
            $size = Get-OtterPngSize -Path $iconSource
            if ($size -and ($size.Width -lt 256 -or $size.Height -lt 256)) {
                throw [OtterError]::new("$($project.ManifestFileName): icon `"$($project.Icon)`" is $($size.Width)x$($size.Height); a PNG icon must be at least 256x256 pixels.", 0, 'check')
            }
        }
    }
    $iconFile = if ($iconSource) { 'build/icon' + [System.IO.Path]::GetExtension($iconSource).ToLowerInvariant() } else { $null }
    $toolchain = Get-OtterElectronToolchain -ProjectRoot $rootDir
    $config = New-OtterElectronBuilderConfig -Project $project -Platform $Platform -Kinds $Kinds -OutputDir $packagesDir `
        -ElectronVersion $(if ($toolchain) { $toolchain.ElectronVersion } else { $null }) -IconFile $iconFile

    & $emit @{ step = 'check'; status = 'done'; label = "Checked $($project.Name) and its packaging settings" }

    # 1. The Electron export (the same one `otter build --target electron` makes).
    if (-not $Quiet) { Write-Host "Packaging $($project.Name) for $($Platform.ToLowerInvariant())..." }
    & $emit @{ step = 'export'; status = 'running'; label = 'Compiling Otter source and creating the Electron application' }
    $buildExit = Invoke-OtterProjectBuild -Target $rootDir -TargetOverride 'electron' -Quiet
    if ($buildExit -ne 0) {
        & $emit @{ step = 'export'; status = 'failed'; label = 'The Otter program did not compile' }
        return $buildExit
    }
    $exportDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $project.Build.OutputDir))
    if (-not (Test-Path -LiteralPath (Join-Path $exportDir 'main.js') -PathType Leaf)) {
        throw [OtterError]::new("The Electron export was not found in $exportDir after the build.", 0, 'runtime')
    }
    & $emit @{ step = 'export'; status = 'done'; label = 'Compiled Otter source and created the Electron application' }
    $stylesheet = if (Get-Command Resolve-OtterProjectStylesheet -ErrorAction SilentlyContinue) { Resolve-OtterProjectStylesheet -SourcePath $project.ResolvedEntryPoint } else { $null }
    if ($stylesheet) {
        & $emit @{ step = 'styles'; status = 'done'; label = "Embedded $(Split-Path -Leaf $stylesheet)" }
    } else {
        & $emit @{ step = 'styles'; status = 'skipped'; label = 'No project stylesheet to embed' }
    }

    # 2. Icon and configuration next to the export.
    if ($iconSource) {
        $buildResources = Join-Path $exportDir 'build'
        New-Item -ItemType Directory -Path $buildResources -Force | Out-Null
        Copy-Item -LiteralPath $iconSource -Destination (Join-Path $exportDir $iconFile) -Force
    }
    $configPath = Join-Path $exportDir 'electron-builder.json'
    $configJson = ConvertTo-Json -InputObject $config -Depth 6
    [System.IO.File]::WriteAllText($configPath, $configJson + "`n", (New-Object System.Text.UTF8Encoding($false)))
    & $emit @{ step = 'configure'; status = 'done'; label = 'Wrote the packaging configuration' }

    if ($DryRun) {
        if (-not $Quiet) {
            Write-Host "Dry run: the Electron export and electron-builder.json are ready in $exportDir."
            if (-not $toolchain) { Write-Host "No packaging toolchain was found; a real run would install one into $(Get-OtterSharedToolchainRoot)." }
        }
        & $emit @{ step = 'done'; status = 'done'; label = 'Dry run complete'; dryRun = $true; outputDir = $packagesDir; exportDir = $exportDir; artifacts = @() }
        return 0
    }

    # 3. electron-builder.
    if (-not $toolchain) {
        $toolchain = Install-OtterElectronToolchain -Quiet:$Quiet
        $config.electronVersion = $toolchain.ElectronVersion
        $configJson = ConvertTo-Json -InputObject $config -Depth 6
        [System.IO.File]::WriteAllText($configPath, $configJson + "`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        throw [OtterError]::new("Packaging needs Node.js on this computer (only to build). Install it from nodejs.org and try again.", 0, 'runtime')
    }

    $builderArgs = @($toolchain.BuilderCli, '--win') + $config.win.target + @('--config', $configPath, '--projectDir', $exportDir)
    if (-not $Quiet) {
        Write-Host "Running electron-builder $((Get-Content -LiteralPath (Join-Path $toolchain.Root 'node_modules\electron-builder\package.json') -Raw | ConvertFrom-Json).version) with Electron $($toolchain.ElectronVersion)..."
    }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $previousLocation = Get-Location
    $builderOutput = [System.Collections.Generic.List[string]]::new()
    & $emit @{ step = 'runtime'; status = 'running'; label = "Preparing the Electron $($toolchain.ElectronVersion) runtime" }
    $runtimeReported = $false
    $activeKind = $null
    try {
        Set-Location -LiteralPath $exportDir
        # Editors that embed Node set this; inherited, it would break electron-builder's own Electron launches.
        $savedRunAsNode = $env:ELECTRON_RUN_AS_NODE
        Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
        $env:CSC_IDENTITY_AUTO_DISCOVERY = 'false'
        # Streamed line by line so each target's start shows up as it happens.
        & $node.Source @builderArgs 2>&1 | ForEach-Object {
            $line = [string]$_
            $builderOutput.Add($line)
            if ($Progress -and $line -match 'building\s+target=(portable|nsis)') {
                $kind = if ($Matches[1] -eq 'nsis') { 'installer' } else { 'portable' }
                if (-not $runtimeReported) {
                    & $emit @{ step = 'runtime'; status = 'done'; label = "Prepared the Electron $($toolchain.ElectronVersion) runtime" }
                    $runtimeReported = $true
                }
                if ($activeKind -and $activeKind -ne $kind) {
                    & $emit @{ step = $activeKind; status = 'done'; label = $(if ($activeKind -eq 'installer') { 'Built the Windows installer' } else { 'Built the portable executable' }) }
                }
                if ($activeKind -ne $kind) {
                    $activeKind = $kind
                    & $emit @{ step = $kind; status = 'running'; label = $(if ($kind -eq 'installer') { 'Building the Windows installer' } else { 'Building the portable executable' }) }
                }
            }
        }
        $builderExit = $LASTEXITCODE
        if ($null -ne $savedRunAsNode) { $env:ELECTRON_RUN_AS_NODE = $savedRunAsNode }
    }
    finally {
        Set-Location $previousLocation
    }
    $stopwatch.Stop()

    if ($builderExit -ne 0) {
        $tail = ($builderOutput | Select-Object -Last 40) -join "`n"
        & $emit @{ step = 'failed'; status = 'failed'; label = 'electron-builder reported an error'; detail = (($builderOutput | Where-Object { $_ -match '⨯|Error|error' } | Select-Object -Last 5) -join "`n") }
        Write-Host "Packaging failed." -ForegroundColor Red
        Write-Host ''
        Write-Host $tail -ForegroundColor DarkGray
        Write-Host ''
        return 1
    }
    if (-not $runtimeReported) {
        & $emit @{ step = 'runtime'; status = 'done'; label = "Prepared the Electron $($toolchain.ElectronVersion) runtime" }
    }
    foreach ($kind in @('portable', 'installer')) {
        if ($kind -in @($config.win.target | ForEach-Object { if ($_ -eq 'nsis') { 'installer' } else { $_ } })) {
            & $emit @{ step = $kind; status = 'done'; label = $(if ($kind -eq 'installer') { 'Built the Windows installer' } else { 'Built the portable executable' }) }
        }
    }

    # 4. Keep packages/ to the distributables: the unpacked app (hundreds of MB),
    # the builder's debug dump and update blockmaps are scaffolding.
    foreach ($extra in @('win-unpacked', 'builder-debug.yml', 'builder-effective-config.yaml', '.icon-ico', '.icon-set')) {
        Remove-Item -LiteralPath (Join-Path $packagesDir $extra) -Recurse -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem -LiteralPath $packagesDir -Filter '*.blockmap' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # 5. Report.
    $artifacts = @(Get-ChildItem -LiteralPath $packagesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.exe', '.msi', '.zip', '.dmg', '.AppImage', '.deb', '.rpm') })
    & $emit @{
        step = 'done'; status = 'done'; label = "Build complete in $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)) s"
        seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1); outputDir = $packagesDir; dryRun = $false
        artifacts = @($artifacts | ForEach-Object { @{ name = $_.Name; path = $_.FullName; sizeBytes = $_.Length } })
    }
    if (-not $Quiet) {
        Write-Host ''
        Write-Host "Packaging succeeded in $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)) s." -ForegroundColor Green
        foreach ($artifact in $artifacts) {
            Write-Host ("  {0,-48} {1,8:N1} MB" -f $artifact.Name, ($artifact.Length / 1MB))
        }
        Write-Host "Output: $packagesDir"
        Write-Host ''
        Write-Host 'The application is not code-signed: Windows SmartScreen shows a warning the first time it runs on another computer.' -ForegroundColor DarkYellow
    }
    return 0
}

Export-ModuleMember -Function Invoke-OtterProjectPackage, New-OtterElectronBuilderConfig, Get-OtterElectronToolchain, Install-OtterElectronToolchain, Get-OtterSharedToolchainRoot
