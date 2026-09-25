using module ..\Otter.Contract.psm1

# Otter.Project.psm1 - Otter Project Manifest & Resolution Engine
# Supports canonical otter.json with project.json fallback.

class OtterProjectBuild {
    [string]$OutputDir = "dist"
    [bool]$Clean = $true
    [bool]$SourceMaps = $true
    [bool]$Minify = $false
}

class OtterProject {
    [string]$RootDirectory
    [string]$ManifestPath
    [string]$ManifestFileName
    [string]$Name
    [string]$Version = "0.1.0"
    [string]$Archetype = "console"
    [string]$Target = "console"
    [string]$EntryPoint
    [string]$ResolvedEntryPoint
    [string[]]$Assets = @()
    [OtterProjectBuild]$Build = [OtterProjectBuild]::new()
    [hashtable]$Scripts = @{}

    OtterProject() {}
}

function Find-OtterProjectManifest {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = '.'
    }

    $trimmed = $Path.Trim()
    if ($trimmed.ToLowerInvariant().EndsWith('.ot')) {
        return $null
    }

    $resolvedPath = $null
    try {
        $resolvedPath = (Resolve-Path -LiteralPath $trimmed -ErrorAction Stop).Path
    } catch {
        return $null
    }

    if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
        $otterJson = Join-Path $resolvedPath 'otter.json'
        if (Test-Path -LiteralPath $otterJson -PathType Leaf) {
            return @{
                RootDirectory    = $resolvedPath
                ManifestPath     = $otterJson
                ManifestFileName = 'otter.json'
            }
        }
        $projJson = Join-Path $resolvedPath 'project.json'
        if (Test-Path -LiteralPath $projJson -PathType Leaf) {
            return @{
                RootDirectory    = $resolvedPath
                ManifestPath     = $projJson
                ManifestFileName = 'project.json'
            }
        }
        return $null
    }
    elseif (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
        $leaf = Split-Path -Leaf $resolvedPath
        if ($leaf.Equals('otter.json', [System.StringComparison]::OrdinalIgnoreCase) -or
            $leaf.Equals('project.json', [System.StringComparison]::OrdinalIgnoreCase)) {
            return @{
                RootDirectory    = (Split-Path -Parent $resolvedPath)
                ManifestPath     = $resolvedPath
                ManifestFileName = $leaf
            }
        }
    }

    return $null
}

function Get-OtterProject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $found = Find-OtterProjectManifest -Path $Path
    if ($null -eq $found) {
        throw [OtterError]::new("Otter: I cannot find an otter.json manifest in `"$Path`".", 0, 'check')
    }

    $manifestPath = $found.ManifestPath
    $rootDir = $found.RootDirectory
    $manifestName = $found.ManifestFileName

    $jsonRaw = $null
    try {
        $jsonRaw = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
    } catch {
        throw [OtterError]::new("${manifestName}: cannot read manifest file: $($_.Exception.Message)", 0, 'check')
    }

    $parsed = $null
    try {
        $parsed = $jsonRaw | ConvertFrom-Json
    } catch {
        throw [OtterError]::new("${manifestName}: invalid JSON syntax: $($_.Exception.Message)", 0, 'check')
    }

    if ($null -eq $parsed) {
        throw [OtterError]::new("${manifestName}: manifest is empty.", 0, 'check')
    }

    # 1. Entry point validation
    $entryPoint = $null
    if ($parsed.PSObject.Properties['entryPoint'] -and -not [string]::IsNullOrWhiteSpace($parsed.entryPoint)) {
        $entryPoint = [string]$parsed.entryPoint
    } elseif ($manifestName -eq 'project.json' -and $parsed.PSObject.Properties['main'] -and -not [string]::IsNullOrWhiteSpace($parsed.main)) {
        $entryPoint = [string]$parsed.main
    }

    if ([string]::IsNullOrWhiteSpace($entryPoint)) {
        throw [OtterError]::new("${manifestName}: property `"entryPoint`" is required.", 0, 'check')
    }

    $resolvedEntry = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $entryPoint))
    if (-not (Test-Path -LiteralPath $resolvedEntry -PathType Leaf)) {
        throw [OtterError]::new("${manifestName}: entry point `"$entryPoint`" does not exist.", 0, 'check')
    }

    # 2. Target validation
    $target = 'console'
    if ($parsed.PSObject.Properties['target'] -and -not [string]::IsNullOrWhiteSpace($parsed.target)) {
        $target = [string]$parsed.target
    } elseif ($parsed.PSObject.Properties['archetype'] -and -not [string]::IsNullOrWhiteSpace($parsed.archetype)) {
        $target = [string]$parsed.archetype
    }

    $supportedTargets = @('console', 'desktop', 'web', 'game', 'server')
    if ($supportedTargets -notcontains $target.ToLowerInvariant()) {
        throw [OtterError]::new("${manifestName}: target `"$target`" is not supported.", 0, 'check')
    }

    # 3. Output directory containment validation
    $buildObj = [OtterProjectBuild]::new()
    if ($parsed.PSObject.Properties['build']) {
        $b = $parsed.build
        if ($b.PSObject.Properties['outputDir']) {
            $outDir = [string]$b.outputDir
            if ([string]::IsNullOrWhiteSpace($outDir)) {
                throw [OtterError]::new("${manifestName}: build.outputDir must stay inside the project directory.", 0, 'check')
            }
            $resolvedOut = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $outDir))
            $rootWithSep = $rootDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $resolvedOut.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw [OtterError]::new("${manifestName}: build.outputDir must stay inside the project directory.", 0, 'check')
            }
            $buildObj.OutputDir = $outDir
        }
        if ($b.PSObject.Properties['clean']) { $buildObj.Clean = [bool]$b.clean }
        if ($b.PSObject.Properties['sourceMaps']) { $buildObj.SourceMaps = [bool]$b.sourceMaps }
        if ($b.PSObject.Properties['minify']) { $buildObj.Minify = [bool]$b.minify }
    }

    # 4. Construct OtterProject instance
    $project = [OtterProject]::new()
    $project.RootDirectory = $rootDir
    $project.ManifestPath = $manifestPath
    $project.ManifestFileName = $manifestName
    $project.EntryPoint = $entryPoint
    $project.ResolvedEntryPoint = $resolvedEntry
    $project.Target = $target.ToLowerInvariant()
    $project.Archetype = if ($parsed.PSObject.Properties['archetype'] -and -not [string]::IsNullOrWhiteSpace($parsed.archetype)) { [string]$parsed.archetype } else { $project.Target }
    $project.Name = if ($parsed.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace($parsed.name)) { [string]$parsed.name } else { [System.IO.Path]::GetFileName($rootDir) }
    $project.Version = if ($parsed.PSObject.Properties['version'] -and -not [string]::IsNullOrWhiteSpace($parsed.version)) { [string]$parsed.version } else { '0.1.0' }
    $project.Build = $buildObj

    # Assets
    if ($parsed.PSObject.Properties['assets'] -and $parsed.assets -is [System.Collections.IEnumerable]) {
        $project.Assets = @($parsed.assets | ForEach-Object { [string]$_ })
    }

    # Scripts
    if ($parsed.PSObject.Properties['scripts']) {
        $scriptsTable = @{}
        foreach ($p in $parsed.scripts.PSObject.Properties) {
            $scriptsTable[$p.Name] = [string]$p.Value
        }
        $project.Scripts = $scriptsTable
    }

    return $project
}

function New-OtterProject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Archetype,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Path = '.'
    )

    $validArchetypes = @('console', 'desktop', 'web', 'automation', 'game')
    $arch = $Archetype.Trim().ToLowerInvariant()
    if ($validArchetypes -notcontains $arch) {
        throw [OtterError]::new("Otter: archetype `"$Archetype`" is not supported. Supported archetypes: console, desktop, web, automation, game.", 0, 'check')
    }

    $cleanName = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($cleanName) -or $cleanName -match '[<>:"/\\|?*]') {
        throw [OtterError]::new("Otter: `"$Name`" is not a valid project name.", 0, 'check')
    }

    $projectDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($Path, $cleanName))
    if (Test-Path -LiteralPath $projectDir) {
        $children = @(Get-ChildItem -LiteralPath $projectDir -Force)
        if ($children.Count -gt 0) {
            throw [OtterError]::new("Otter: destination folder `"$cleanName`" already exists and is not empty.", 0, 'check')
        }
    } else {
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
    }

    # Folders: src/, tests/, assets/
    $srcDir = Join-Path $projectDir 'src'
    $testsDir = Join-Path $projectDir 'tests'
    $assetsDir = Join-Path $projectDir 'assets'
    New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null

    # Template code per archetype
    $mainCode = ''
    $targetName = 'console'
    $assetList = @()

    switch ($arch) {
        'console' {
            $targetName = 'console'
            $mainCode = @"
# $cleanName - Console Application

say "Hello from $cleanName!"
"@
        }
        'desktop' {
            $targetName = 'desktop'
            $assetList = @('assets/styles.css')
            $mainCode = @"
# $cleanName - Desktop Application

create window into app
title of app is "$cleanName"

create button into btn
text of btn is "Click Me"

put btn in app
show app
"@
            $cssContent = "/* Stylesheet for $cleanName */`nbody { margin: 0; padding: 16px; }`n"
            Set-Content -LiteralPath (Join-Path $assetsDir 'styles.css') -Value $cssContent -Encoding UTF8
        }
        'web' {
            $targetName = 'web'
            $assetList = @('assets/styles.css')
            $mainCode = @"
# $cleanName - Web Application

app is a page
    title is "$cleanName"
.

welcomeText is a text
    value is "Welcome to $cleanName!"
.

put welcomeText in app
show app
"@
            $cssContent = "/* Stylesheet for $cleanName */`nbody { margin: 0; font-family: sans-serif; }`n"
            Set-Content -LiteralPath (Join-Path $assetsDir 'styles.css') -Value $cssContent -Encoding UTF8
        }
        'automation' {
            $targetName = 'console'
            $mainCode = @"
# $cleanName - Automation Task

get current directory into cwd
say "Running automation task in:" cwd

get files in "." into projectFiles
say "Found" length of projectFiles "files."
"@
        }
        'game' {
            $targetName = 'game'
            $assetList = @('assets/styles.css')
            $mainCode = @"
# $cleanName - 2D Game

app is a page
    title is "$cleanName"
.

gameCanvas is a canvas
    width is 640
    height is 480
    mode is "2d"
.

put gameCanvas in app
show app
"@
            $cssContent = "/* Stylesheet for $cleanName */`nbody { margin: 0; background: #000; }`n"
            Set-Content -LiteralPath (Join-Path $assetsDir 'styles.css') -Value $cssContent -Encoding UTF8
        }
    }

    # Write main.ot
    Set-Content -LiteralPath (Join-Path $projectDir 'main.ot') -Value $mainCode -Encoding UTF8

    # Write tests/app_test.ot
    $testCode = @"
# Tests for $cleanName

score is 100

if score is not 100
    fail with "Expected score to be 100."
.

say "All checks passed"
"@
    Set-Content -LiteralPath (Join-Path $testsDir 'app_test.ot') -Value $testCode -Encoding UTF8

    # Write canonical otter.json
    $assetsJson = if ($assetList.Count -gt 0) {
        "`n    " + (($assetList | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress }) -join ",`n    ") + "`n  "
    } else { "" }

    $manifestJson = @"
{
  "`$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "$cleanName",
  "version": "0.1.0",
  "archetype": "$arch",
  "target": "$targetName",
  "entryPoint": "main.ot",
  "assets": [$assetsJson],
  "build": {
    "outputDir": "dist",
    "clean": true
  },
  "scripts": {
    "start": "otter run .",
    "test": "otter test .",
    "check": "otter check ."
  }
}
"@
    Set-Content -LiteralPath (Join-Path $projectDir 'otter.json') -Value $manifestJson -Encoding UTF8

    return Get-OtterProject -Path $projectDir
}

function Get-OtterProjectTestFiles {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Target
    )

    if ([string]::IsNullOrWhiteSpace($Target)) {
        $Target = '.'
    }

    $trimmed = $Target.Trim()

    # Case 1: Target is directly an existing .ot test file
    if ($trimmed.ToLowerInvariant().EndsWith('.ot')) {
        $resolvedFile = Resolve-Path -LiteralPath $trimmed -ErrorAction SilentlyContinue
        if ($resolvedFile -and (Test-Path -LiteralPath $resolvedFile.Path -PathType Leaf)) {
            return @($resolvedFile.Path)
        }
        throw [OtterError]::new("Otter: I cannot find test file `"$Target`".", 0, 'check')
    }

    # Case 2: Target is a project directory or '.'
    $projectRoot = $null
    $manifestInfo = Find-OtterProjectManifest -Path $trimmed
    if ($manifestInfo) {
        $projectRoot = $manifestInfo.RootDirectory
    } else {
        # Check if $trimmed is an existing directory
        $resolvedDir = Resolve-Path -LiteralPath $trimmed -ErrorAction SilentlyContinue
        if ($resolvedDir -and (Test-Path -LiteralPath $resolvedDir.Path -PathType Container)) {
            $projectRoot = $resolvedDir.Path
        } else {
            throw [OtterError]::new("Otter: I cannot find project or test directory `"$Target`".", 0, 'check')
        }
    }

    # Search in <projectRoot>/tests
    $testsDir = Join-Path $projectRoot 'tests'
    if (-not (Test-Path -LiteralPath $testsDir -PathType Container)) {
        if ($trimmed -ne '.' -and (Split-Path -Leaf $projectRoot).ToLowerInvariant() -eq 'tests') {
            $testsDir = $projectRoot
        } else {
            return @()
        }
    }

    # Discover *_test.ot and test_*.ot
    $files = @(Get-ChildItem -LiteralPath $testsDir -Filter '*.ot' -Recurse -File | Where-Object {
        $name = $_.Name.ToLowerInvariant()
        $name.EndsWith('_test.ot') -or $name.StartsWith('test_')
    } | Sort-Object FullName)

    return @($files | ForEach-Object { $_.FullName })
}

function Invoke-OtterProjectTests {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Target,

        [Parameter(Mandatory = $false)]
        [string]$OtterPs1Path
    )

    if (-not $OtterPs1Path) {
        $OtterPs1Path = Join-Path (Split-Path -Parent $PSScriptRoot) 'otter.ps1'
    }

    $testFiles = Get-OtterProjectTestFiles -Target $Target
    if ($testFiles.Count -eq 0) {
        Write-Host "No tests found." -ForegroundColor Yellow
        return 0
    }

    $count = $testFiles.Count
    $label = if ($count -eq 1) { "1 Otter test" } else { "$count Otter tests" }
    Write-Host "Running $label..."
    Write-Host ""

    $passed = 0
    $failed = 0
    $syntaxErrors = 0
    $failureDetails = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $testFiles) {
        $relPath = if ($Target -and (Test-Path -LiteralPath $Target -PathType Container)) {
            $resolvedTarget = (Resolve-Path -LiteralPath $Target).Path
            if ($file.StartsWith($resolvedTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
                $file.Substring($resolvedTarget.Length).TrimStart('\', '/')
            } else {
                Split-Path -Leaf $file
            }
        } else {
            $leaf = Split-Path -Leaf $file
            $parent = Split-Path -Leaf (Split-Path -Parent $file)
            if ($parent -and $parent.ToLowerInvariant() -eq 'tests') {
                "tests/$leaf"
            } else {
                $leaf
            }
        }
        $relPath = $relPath -replace '\\', '/'

        # Execute test in isolated PowerShell process
        $psExe = if ($PSHOME -and (Test-Path -LiteralPath (Join-Path $PSHOME 'powershell.exe') -PathType Leaf)) {
            Join-Path $PSHOME 'powershell.exe'
        } else {
            'powershell.exe'
        }
        $output = & $psExe -NoProfile -ExecutionPolicy Bypass -File $OtterPs1Path run $file 2>&1
        $code = $LASTEXITCODE

        if ($code -eq 0) {
            Write-Host "PASS $relPath" -ForegroundColor Green
            $passed++
        }
        elseif ($code -eq 2) {
            Write-Host "FAIL $relPath (syntax error)" -ForegroundColor Red
            $syntaxErrors++
            $diagLines = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ -ne '' })
            $detail = "FAIL $relPath (syntax error)`n" + ($diagLines -join "`n")
            $failureDetails.Add($detail)
        }
        else {
            Write-Host "FAIL $relPath" -ForegroundColor Red
            $failed++

            $rawLines = @($output | ForEach-Object { $_.ToString() })
            $errLine = $null
            $errMsg = $null
            for ($i = 0; $i -lt $rawLines.Count; $i++) {
                if ($rawLines[$i] -match '^Line\s+(\d+):') {
                    $errLine = $matches[1]
                }
            }

            # Filter out runtime header and line block to isolate message
            $filtered = @($rawLines | Where-Object {
                $t = $_.Trim()
                $t -ne '' -and $t -notmatch '^(Otter Runtime Error|Line \d+:)' -and $t -notmatch '^\s*fail with\b'
            })
            if ($filtered.Count -gt 0) {
                $errMsg = $filtered[-1].Trim()
            } else {
                $errMsg = "Test assertion failed."
            }

            $loc = if ($errLine) { "${relPath}:${errLine}" } else { $relPath }
            $detail = "FAIL $loc`n  $errMsg"
            $failureDetails.Add($detail)
        }
    }

    if ($failureDetails.Count -gt 0) {
        Write-Host ""
        foreach ($d in $failureDetails) {
            Write-Host $d -ForegroundColor Red
            Write-Host ""
        }
    }

    Write-Host ""
    if ($failed -eq 0 -and $syntaxErrors -eq 0) {
        Write-Host "$passed passed" -ForegroundColor Green
        return 0
    }

    $summaryParts = @()
    if ($passed -gt 0) { $summaryParts += "$passed passed" }
    $totalFails = $failed + $syntaxErrors
    $summaryParts += "$totalFails failed"
    Write-Host ($summaryParts -join ', ') -ForegroundColor Red

    if ($syntaxErrors -gt 0) { return 2 }
    return 3
}

function Invoke-OtterProjectBuild {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Target
    )

    if (-not (Get-Command ConvertTo-OtterTokens -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Lexer.psm1') -Global
    }
    if (-not (Get-Command ConvertTo-OtterAst -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Parser.psm1') -Global
    }
    if (-not (Get-Command Resolve-OtterModuleSource -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Module.psm1') -Global
    }
    if (-not (Get-Command Export-OtterWebApplication -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Web.psm1') -Global
    }

    if ([string]::IsNullOrWhiteSpace($Target)) {
        $Target = '.'
    }

    $project = Get-OtterProject -Path $Target
    $rootDir = $project.RootDirectory
    $outDir = $project.Build.OutputDir

    # 1. Output directory containment validation
    $resolvedOutDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $outDir))
    if ($resolvedOutDir -eq $rootDir -or (-not $resolvedOutDir.StartsWith($rootDir + [System.IO.Path]::DirectorySeparatorChar))) {
        throw [OtterError]::new("otter.json: build.outputDir must stay inside the project directory and cannot be the project root itself.", 0, 'check')
    }

    Write-Host "Building $($project.Name)..."
    Write-Host "Target: $($project.Target)"
    Write-Host ""

    # 2. Syntax & Module checking before touching any output
    Write-Host "Checking project..."
    $resolvedProgram = $null
    try {
        $resolvedProgram = Resolve-OtterModuleSource -FilePath $project.ResolvedEntryPoint
        $tokens = ConvertTo-OtterTokens -Source $resolvedProgram.CombinedSource
        $ast = ConvertTo-OtterAst -Tokens $tokens
    }
    catch [OtterError] {
        $err = $_.Exception
        if ($resolvedProgram) {
            $err = ConvertTo-OtterRemappedDiagnostics -Error $err -ResolvedProgram $resolvedProgram -RootFile $project.ResolvedEntryPoint
        }
        Write-Host "Build failed." -ForegroundColor Red
        Write-Host ""
        Write-Host $err.FormatDetailed() -ForegroundColor Red
        Write-Host ""
        return 2
    }
    catch {
        Write-Host "Build failed." -ForegroundColor Red
        Write-Host ""
        Write-Host "Otter hit a problem inside itself: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return 1
    }

    # 3. Asset validation before staging
    foreach ($asset in $project.Assets) {
        if ([string]::IsNullOrWhiteSpace($asset)) { continue }
        $trimmedAsset = $asset.Trim()
        if ($trimmedAsset.StartsWith('/') -or $trimmedAsset.StartsWith('\') -or $trimmedAsset -match '^[a-zA-Z]:') {
            Write-Host "Build failed." -ForegroundColor Red
            Write-Host ""
            Write-Host "otter.json: asset `"$asset`" cannot be an absolute path." -ForegroundColor Red
            Write-Host ""
            return 1
        }
        $resolvedAsset = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $trimmedAsset))
        if (-not $resolvedAsset.StartsWith($rootDir + [System.IO.Path]::DirectorySeparatorChar)) {
            Write-Host "Build failed." -ForegroundColor Red
            Write-Host ""
            Write-Host "otter.json: asset `"$asset`" escapes the project directory." -ForegroundColor Red
            Write-Host ""
            return 1
        }
        if (-not (Test-Path -LiteralPath $resolvedAsset -PathType Leaf)) {
            Write-Host "Build failed." -ForegroundColor Red
            Write-Host ""
            Write-Host "otter.json: declared asset `"$asset`" does not exist." -ForegroundColor Red
            Write-Host ""
            return 1
        }
    }

    # 4. Staging directory for atomic promotion & safety
    $stagingDir = Join-Path $rootDir (".otter_build_staging_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    try {
        Write-Host "Building application..."
        $targetLower = $project.Target.ToLowerInvariant()

        switch ($targetLower) {
            { $_ -in @('web', 'desktop', 'game') } {
                $htmlOutput = Join-Path $stagingDir 'index.html'
                Export-OtterWebApplication -SourcePath $project.ResolvedEntryPoint -OutputPath $htmlOutput -PassThruExceptions | Out-Null

                if ($targetLower -eq 'desktop') {
                    $launcherCmd = "@echo off`r`notter desktop %~dp0index.html %*`r`n"
                    Set-Content -LiteralPath (Join-Path $stagingDir 'run-desktop.cmd') -Value $launcherCmd -Encoding ASCII
                }
            }
            { $_ -in @('console', 'automation') } {
                $entryLeaf = Split-Path -Leaf $project.ResolvedEntryPoint
                $destEntry = Join-Path $stagingDir $entryLeaf
                Set-Content -LiteralPath $destEntry -Value $resolvedProgram.CombinedSource -Encoding UTF8

                # Runnable project manifest inside build artifact
                $builtManifest = @"
{
  "`$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "$($project.Name)",
  "version": "$($project.Version)",
  "archetype": "$($project.Archetype)",
  "target": "$($project.Target)",
  "entryPoint": "$entryLeaf"
}
"@
                Set-Content -LiteralPath (Join-Path $stagingDir 'otter.json') -Value $builtManifest -Encoding UTF8

                # Runnable launcher script
                $launcherCmd = "@echo off`r`notter run %~dp0$entryLeaf %*`r`n"
                Set-Content -LiteralPath (Join-Path $stagingDir 'run.cmd') -Value $launcherCmd -Encoding ASCII
            }
            default {
                Write-Host "Build failed." -ForegroundColor Red
                Write-Host ""
                Write-Host "Otter: target `"$($project.Target)`" is not supported for build." -ForegroundColor Red
                Write-Host ""
                return 1
            }
        }

        # 5. Copy declared assets
        if ($project.Assets.Count -gt 0) {
            Write-Host "Copying assets..."
            foreach ($asset in $project.Assets) {
                if ([string]::IsNullOrWhiteSpace($asset)) { continue }
                $trimmedAsset = $asset.Trim()
                $srcPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $trimmedAsset))
                $destPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($stagingDir, $trimmedAsset))
                $destParent = Split-Path -Parent $destPath
                if (-not (Test-Path -LiteralPath $destParent -PathType Container)) {
                    New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                }
                Copy-Item -LiteralPath $srcPath -Destination $destPath -Force
            }
        }

        # 6. Emit deterministic build metadata
        $entryRel = if ($targetLower -in @('web', 'desktop', 'game')) { 'index.html' } else { Split-Path -Leaf $project.ResolvedEntryPoint }
        $assetsJsonArray = if ($project.Assets.Count -gt 0) {
            "`n    " + (($project.Assets | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress }) -join ",`n    ") + "`n  "
        } else { "" }

        $buildMeta = @"
{
  "name": "$($project.Name)",
  "version": "$($project.Version)",
  "target": "$($project.Target)",
  "entryPoint": "$entryRel",
  "assets": [$assetsJsonArray]
}
"@
        Set-Content -LiteralPath (Join-Path $stagingDir 'otter.build.json') -Value $buildMeta -Encoding UTF8

        # 7. Atomic promotion to outputDir
        if ($project.Build.Clean -and (Test-Path -LiteralPath $resolvedOutDir)) {
            Remove-Item -LiteralPath $resolvedOutDir -Recurse -Force
        }

        if (-not (Test-Path -LiteralPath $resolvedOutDir)) {
            New-Item -ItemType Directory -Path $resolvedOutDir -Force | Out-Null
        }

        Get-ChildItem -LiteralPath $stagingDir -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $resolvedOutDir -Recurse -Force
        }
    }
    finally {
        if (Test-Path -LiteralPath $stagingDir) {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host ""
    Write-Host "Build succeeded." -ForegroundColor Green
    $relOutput = if ($resolvedOutDir.StartsWith($rootDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $resolvedOutDir.Substring($rootDir.Length).TrimStart('\', '/')
    } else {
        $outDir
    }
    $relOutput = ($relOutput -replace '\\', '/') + '/'
    Write-Host "Output: $relOutput"
    return 0
}

Export-ModuleMember -Function Find-OtterProjectManifest, Get-OtterProject, New-OtterProject, Get-OtterProjectTestFiles, Invoke-OtterProjectTests, Invoke-OtterProjectBuild
