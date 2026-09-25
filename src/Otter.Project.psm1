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

Export-ModuleMember -Function Find-OtterProjectManifest, Get-OtterProject
