using module ..\Otter.Contract.psm1

# Otter.Project.psm1 - Otter Project Manifest & Resolution Engine
# Supports canonical otter.json with project.json fallback.

class OtterProjectBuild {
    [string]$OutputDir = "dist"
    [bool]$Clean = $true
    [bool]$SourceMaps = $true
    [bool]$Minify = $false
}

class OtterProjectPublish {
    [string]$OutputDir = "publish"
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
    [OtterProjectPublish]$Publish = [OtterProjectPublish]::new()
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

# Returns the real, fully resolved path of $Path: every symbolic link or
# junction along the way (the file itself AND each ancestor folder) is
# replaced by the place it points to. Lexical checks such as GetFullPath plus
# StartsWith only look at the spelling, so "assets/link.txt" pointing at
# /etc/secret, or "assets/" being a link to C:\Users\me, looked like it was
# inside the project and was copied into dist/ and the publish zip.
# Components that do not exist yet are appended as spelled. Link targets are
# read with FileSystemInfo.LinkTarget on PowerShell 7 (.NET 6+) and with the
# LinkType/Target properties Windows PowerShell 5.1 adds to Get-Item output.
# Hard links are not redirects (they have no target path) and are left alone.
function Get-OtterRealPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $separators = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $full = [System.IO.Path]::GetFullPath($Path)
    $current = [System.IO.Path]::GetPathRoot($full)
    $pending = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in $full.Substring($current.Length).Split($separators, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $pending.Add($segment)
    }

    # A link cycle (a -> b -> a) would otherwise loop forever.
    $linkHops = 0
    while ($pending.Count -gt 0) {
        $segment = $pending[0]
        $pending.RemoveAt(0)
        if ($segment -eq '.') { continue }
        if ($segment -eq '..') {
            # $current is already real here, so its parent is the real parent.
            $parent = [System.IO.Path]::GetDirectoryName($current)
            if ($parent) { $current = $parent }
            continue
        }

        $candidate = [System.IO.Path]::Combine($current, $segment)
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        $linkTarget = $null
        if ($item -and $item.PSObject.Properties['LinkType'] -and ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction')) {
            if ($item.PSObject.Properties['LinkTarget'] -and $item.LinkTarget) {
                $linkTarget = [string]$item.LinkTarget
            } elseif ($item.PSObject.Properties['Target']) {
                $linkTarget = [string](@($item.Target) | Select-Object -First 1)
            }
        }

        if ([string]::IsNullOrEmpty($linkTarget)) {
            $current = $candidate
            continue
        }

        $linkHops++
        if ($linkHops -gt 64) {
            throw [OtterError]::new("Otter: too many symbolic links or junctions while resolving `"$Path`".", 0, 'check')
        }
        # Windows can report a junction target in NT form (\??\C:\dir).
        if ($linkTarget.StartsWith('\??\')) { $linkTarget = $linkTarget.Substring(4) }
        if (-not [System.IO.Path]::IsPathRooted($linkTarget)) {
            # A relative link target is relative to the folder holding the link.
            $linkTarget = [System.IO.Path]::Combine($current, $linkTarget)
        }
        # Restart from the target's root and walk the target's own segments
        # first, so links inside the target are resolved too.
        $targetFull = [System.IO.Path]::GetFullPath($linkTarget)
        $current = [System.IO.Path]::GetPathRoot($targetFull)
        $targetSegments = $targetFull.Substring($current.Length).Split($separators, [System.StringSplitOptions]::RemoveEmptyEntries)
        $pending.InsertRange(0, [string[]]$targetSegments)
    }

    return $current
}

# The single containment gate for project inputs. Invariant (Otter 1.0 RC3):
# every file build or publish includes (the entry point, its <entry>.css
# stylesheet, every declared asset) must resolve inside the project root,
# because Otter has no explicit external-file feature. Both sides are
# compared as REAL paths (Get-OtterRealPath), so a symbolic link or junction
# anywhere in the path cannot smuggle an outside file in, and an entryPoint of
# "../x.ot" or an absolute path elsewhere is refused. The prefix check ends in
# a separator ("/proj/" never matches "/project2/...") and ignores case on
# Windows, where the file system does. Returns the real path of the input;
# throws an OtterError naming the manifest field otherwise.
function Resolve-OtterProjectInputPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootDirectory,
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        # How the error names the input, e.g. 'otter.json: entryPoint "../x.ot"'.
        [Parameter(Mandatory = $true)]
        [string]$FieldDescription
    )

    $realRoot = Get-OtterRealPath -Path $RootDirectory
    $realInput = Get-OtterRealPath -Path ([System.IO.Path]::Combine($RootDirectory, $InputPath))

    $rootWithSep = $realRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $comparison = if (Test-OtterProjectWindowsHost) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if (-not $realInput.StartsWith($rootWithSep, $comparison)) {
        throw [OtterError]::new("${FieldDescription} escapes the project directory: it resolves to `"$realInput`", which is outside `"$realRoot`". Every file Otter builds or publishes must be inside the project folder (symbolic links and junctions are followed).", 0, 'check')
    }
    return $realInput
}

# Names a ConvertFrom-Json value's type in the words the manifest errors use.
function Get-OtterManifestValueKind {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return 'text' }
    if ($Value -is [bool]) { return 'true/false' }
    if ($Value -is [System.Management.Automation.PSCustomObject]) { return 'an object' }
    if ($Value -is [System.Array] -or $Value -is [System.Collections.IList]) { return 'a list' }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal] -or $Value -is [System.Numerics.BigInteger]) { return 'a number' }
    return $Value.GetType().Name
}

# Wrong-typed manifest values used to reach code that dereferences them
# ("build": null crashed with "Cannot index into a null array." plus the
# script path), or were silently coerced ("clean": "false" became $true,
# "assets": 5 was ignored). Get-OtterProject calls this for every field it
# reads, so a bad manifest ends in one OtterError that names the field and
# the expected type. An absent field is still fine; a present one must have
# the right type (a JSON null is not "absent").
function Assert-OtterManifestFieldType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestName,
        [Parameter(Mandatory = $true)]
        [string]$Field,
        [AllowNull()]
        $Value,
        [Parameter(Mandatory = $true)]
        [ValidateSet('string', 'object', 'list', 'boolean')]
        [string]$Expected
    )

    $ok = switch ($Expected) {
        'string'  { $Value -is [string] }
        'object'  { $Value -is [System.Management.Automation.PSCustomObject] }
        'list'    { $Value -is [System.Array] -or $Value -is [System.Collections.IList] }
        'boolean' { $Value -is [bool] }
    }
    if ($ok) { return }

    $expectedText = switch ($Expected) {
        'string'  { 'text (a JSON string)' }
        'object'  { 'an object ({ ... })' }
        'list'    { 'a list of text ([ ... ])' }
        'boolean' { 'true or false' }
    }
    $kind = Get-OtterManifestValueKind -Value $Value
    throw [OtterError]::new("${ManifestName}: property `"$Field`" must be $expectedText, but it is $kind.", 0, 'check')
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

    # B5: every field below is read through $parsed.<name>, so a manifest
    # that is a list or plain text (["a"], "hello") must stop here with a
    # clear message instead of failing later on a missing property.
    if ($parsed -isnot [System.Management.Automation.PSCustomObject]) {
        throw [OtterError]::new("${manifestName}: the manifest must be a JSON object ({ ... }), but it is $(Get-OtterManifestValueKind -Value $parsed).", 0, 'check')
    }

    # 1. Entry point validation
    $entryPoint = $null
    $entryField = 'entryPoint'
    if ($parsed.PSObject.Properties['entryPoint']) {
        Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'entryPoint' -Value $parsed.entryPoint -Expected 'string'
        if (-not [string]::IsNullOrWhiteSpace($parsed.entryPoint)) { $entryPoint = [string]$parsed.entryPoint }
    } elseif ($manifestName -eq 'project.json' -and $parsed.PSObject.Properties['main']) {
        Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'main' -Value $parsed.main -Expected 'string'
        if (-not [string]::IsNullOrWhiteSpace($parsed.main)) { $entryPoint = [string]$parsed.main }
        $entryField = 'main'
    }

    if ([string]::IsNullOrWhiteSpace($entryPoint)) {
        throw [OtterError]::new("${manifestName}: property `"entryPoint`" is required.", 0, 'check')
    }

    # Characters the host cannot use in a path (NUL everywhere; | < > " on
    # Windows PowerShell 5.1) make GetFullPath throw a raw .NET exception.
    $resolvedEntry = $null
    try {
        $resolvedEntry = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $entryPoint))
    } catch {
        throw [OtterError]::new("${manifestName}: entry point `"$entryPoint`" is not a valid file path.", 0, 'check')
    }
    if (-not (Test-Path -LiteralPath $resolvedEntry -PathType Leaf)) {
        throw [OtterError]::new("${manifestName}: entry point `"$entryPoint`" does not exist.", 0, 'check')
    }

    # B4: the entry point must really live inside the project (no "../x.ot",
    # no absolute path elsewhere, no symlink or junction leading out). Every
    # command that reads the manifest (run, check, build, publish, web,
    # desktop) comes through here, so it is refused before any of them reads
    # or copies the file.
    $null = Resolve-OtterProjectInputPath -RootDirectory $rootDir -InputPath $entryPoint -FieldDescription "${manifestName}: $entryField `"$entryPoint`""

    # 2. Target validation
    $target = 'console'
    if ($parsed.PSObject.Properties['target']) {
        Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'target' -Value $parsed.target -Expected 'string'
    }
    if ($parsed.PSObject.Properties['archetype']) {
        Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'archetype' -Value $parsed.archetype -Expected 'string'
    }
    if ($parsed.PSObject.Properties['target'] -and -not [string]::IsNullOrWhiteSpace($parsed.target)) {
        $target = [string]$parsed.target
    } elseif ($parsed.PSObject.Properties['archetype'] -and -not [string]::IsNullOrWhiteSpace($parsed.archetype)) {
        $target = [string]$parsed.archetype
    }

    $supportedTargets = @('console', 'desktop', 'web', 'game', 'server', 'automation')
    if ($supportedTargets -notcontains $target.ToLowerInvariant()) {
        throw [OtterError]::new("${manifestName}: target `"$target`" is not supported.", 0, 'check')
    }

    # B5: name and version end up in file names and JSON metadata; a number
    # or object used to be stringified silently (1.10 became "1.1").
    foreach ($textField in @('name', 'version')) {
        if ($parsed.PSObject.Properties[$textField]) {
            Assert-OtterManifestFieldType -ManifestName $manifestName -Field $textField -Value $parsed.$textField -Expected 'string'
        }
    }

    # 3. Output directory containment validation
    $buildObj = [OtterProjectBuild]::new()
    if ($parsed.PSObject.Properties['build']) {
        $b = $parsed.build
        Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'build' -Value $b -Expected 'object'
        if ($b.PSObject.Properties['outputDir']) {
            Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'build.outputDir' -Value $b.outputDir -Expected 'string'
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
        # [bool]"false" is $true, so the flags must be real JSON booleans.
        foreach ($flag in @('clean', 'sourceMaps', 'minify')) {
            if ($b.PSObject.Properties[$flag]) {
                Assert-OtterManifestFieldType -ManifestName $manifestName -Field "build.$flag" -Value $b.$flag -Expected 'boolean'
            }
        }
        if ($b.PSObject.Properties['clean']) { $buildObj.Clean = [bool]$b.clean }
        if ($b.PSObject.Properties['sourceMaps']) { $buildObj.SourceMaps = [bool]$b.sourceMaps }
        if ($b.PSObject.Properties['minify']) { $buildObj.Minify = [bool]$b.minify }
    }

    $publishObj = [OtterProjectPublish]::new()
    if ($parsed.PSObject.Properties['publish']) {
        $p = $parsed.publish
        Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'publish' -Value $p -Expected 'object'
        if ($p.PSObject.Properties['outputDir']) {
            Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'publish.outputDir' -Value $p.outputDir -Expected 'string'
            $pOut = [string]$p.outputDir
            if (-not [string]::IsNullOrWhiteSpace($pOut)) {
                $publishObj.OutputDir = $pOut.Trim()
            }
        }
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
    $project.Publish = $publishObj

    # Assets: a list of relative file paths. A single string, a number or an
    # object used to be accepted or silently ignored (B5).
    if ($parsed.PSObject.Properties['assets']) {
        Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'assets' -Value $parsed.assets -Expected 'list'
        $assetIndex = 0
        foreach ($assetValue in @($parsed.assets)) {
            Assert-OtterManifestFieldType -ManifestName $manifestName -Field "assets[$assetIndex]" -Value $assetValue -Expected 'string'
            $assetIndex++
        }
        $project.Assets = @($parsed.assets | ForEach-Object { [string]$_ })
    }

    # Scripts: an object whose values are command lines.
    if ($parsed.PSObject.Properties['scripts']) {
        Assert-OtterManifestFieldType -ManifestName $manifestName -Field 'scripts' -Value $parsed.scripts -Expected 'object'
        $scriptsTable = @{}
        foreach ($p in $parsed.scripts.PSObject.Properties) {
            Assert-OtterManifestFieldType -ManifestName $manifestName -Field "scripts.$($p.Name)" -Value $p.Value -Expected 'string'
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
    # B1: the command `otter new` prints as the last "To get started" step
    # and writes as scripts.start. `otter run .` interprets the program, and
    # the interpreter has no page/text/canvas UI, so for web and game
    # projects it failed with exit 3 ("I can only put a UI resource
    # somewhere, but this is a text"). Those archetypes start with
    # `otter web .`, which compiles the page and opens it. Desktop keeps
    # `otter run .` (it needs Windows WPF).
    $startCommand = 'otter run .'

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
            $startCommand = 'otter web .'
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
            # B3 / D-3: Otter 1.0 finds a page's stylesheet only as <entry>.css
            # (main.ot -> main.css), which the web compiler inlines into
            # index.html. The old assets/styles.css was copied to dist/ but
            # never linked, so edits to it had no effect.
            Set-Content -LiteralPath (Join-Path $projectDir 'main.css') -Value $cssContent -Encoding UTF8
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
            $startCommand = 'otter web .'
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
            # B3 / D-3: main.css beside main.ot, the only stylesheet the web
            # compiler picks up (see the web archetype above).
            Set-Content -LiteralPath (Join-Path $projectDir 'main.css') -Value $cssContent -Encoding UTF8
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
    "start": "$startCommand",
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


# Tests run in a child process of the same PowerShell that is running Otter, so
# `otter test` behaves the same on Windows PowerShell 5.1 and on PowerShell 7 on
# Windows, Linux and macOS. `powershell.exe` exists only on Windows.
function Test-OtterProjectWindowsHost {
    if ($PSVersionTable.PSEdition -ne 'Core') { return $true }
    return [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

function Get-OtterProjectPowerShellHost {
    $current = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    if ($current -and (Test-Path -LiteralPath $current -PathType Leaf) -and ([System.IO.Path]::GetFileNameWithoutExtension($current) -match '^(powershell|pwsh)$')) {
        return $current
    }
    if ($PSHOME) {
        foreach ($name in @('powershell.exe', 'pwsh.exe', 'pwsh')) {
            $candidate = Join-Path $PSHOME $name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    $found = Get-Command -Name 'pwsh', 'powershell' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found -and $found.Path) { return $found.Path }
    if (Test-OtterProjectWindowsHost) { return 'powershell.exe' }
    return 'pwsh'
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
        $psExe = Get-OtterProjectPowerShellHost
        $hostArguments = @('-NoProfile')
        if (Test-OtterProjectWindowsHost) { $hostArguments += @('-ExecutionPolicy', 'Bypass') }
        $output = & $psExe @hostArguments -File $OtterPs1Path run $file 2>&1
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
        [string]$Target,
        [switch]$Quiet
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

    # 1b. Replacement safety: step 7 deletes the output folder when clean is
    # on. Refuse, before anything is written, a folder Otter did not create
    # (no otter.build.json and not empty) or one holding the entry point,
    # the manifest, or .git, so "outputDir": "src" can no longer wipe sources.
    Assert-OtterReplaceableOutputDir -Project $project -ResolvedDir $resolvedOutDir -MarkerFileName 'otter.build.json' -SettingName 'otter.json: build.outputDir' -WillDelete:($project.Build.Clean)

    if (-not $Quiet) {
        Write-Host "Building $($project.Name)..."
        Write-Host "Target: $($project.Target)"
        Write-Host ""
        Write-Host "Checking project..."
    }

    # 2. Syntax & Module checking before touching any output
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
    # Real (link-resolved) source path of each asset, filled by the B4 check
    # below; step 5 copies from these so what is copied is what was checked.
    $realAssetPaths = @{}
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
        # B4: the lexical check above cannot see symbolic links or junctions;
        # a link inside the project (or an asset under a linked folder) used
        # to ship the outside file's content in dist/ and the publish zip.
        # Refused here, before the staging folder or dist/ is written.
        try {
            $realAssetPaths[$trimmedAsset] = Resolve-OtterProjectInputPath -RootDirectory $rootDir -InputPath $trimmedAsset -FieldDescription "otter.json: asset `"$asset`""
        } catch [OtterError] {
            Write-Host "Build failed." -ForegroundColor Red
            Write-Host ""
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host ""
            return 1
        }
    }

    # B4: the web compiler inlines <entry>.css (main.ot -> main.css) into
    # index.html, so that stylesheet is a build input too and must pass the
    # same containment gate before anything is written.
    if ($project.Target.ToLowerInvariant() -in @('web', 'desktop', 'game')) {
        $sidecarCss = [System.IO.Path]::ChangeExtension($project.ResolvedEntryPoint, '.css')
        if (Test-Path -LiteralPath $sidecarCss) {
            try {
                $null = Resolve-OtterProjectInputPath -RootDirectory $rootDir -InputPath $sidecarCss -FieldDescription "otter.json: stylesheet `"$([System.IO.Path]::GetFileName($sidecarCss))`" (beside entryPoint `"$($project.EntryPoint)`")"
            } catch [OtterError] {
                Write-Host "Build failed." -ForegroundColor Red
                Write-Host ""
                Write-Host $_.Exception.Message -ForegroundColor Red
                Write-Host ""
                return 1
            }
        }
    }

    # 4. Staging directory for atomic promotion & safety
    $stagingDir = Join-Path $rootDir (".otter_build_staging_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    try {
        if (-not $Quiet) {
            Write-Host "Building application..."
        }
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
            if (-not $Quiet) {
                Write-Host "Copying assets..."
            }
            foreach ($asset in $project.Assets) {
                if ([string]::IsNullOrWhiteSpace($asset)) { continue }
                $trimmedAsset = $asset.Trim()
                $srcPath = $realAssetPaths[$trimmedAsset]
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

    if (-not $Quiet) {
        Write-Host ""
        Write-Host "Build succeeded." -ForegroundColor Green
        $relOutput = if ($resolvedOutDir.StartsWith($rootDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $resolvedOutDir.Substring($rootDir.Length).TrimStart('\', '/')
        } else {
            $outDir
        }
        $relOutput = ($relOutput -replace '\\', '/') + '/'
        Write-Host "Output: $relOutput"
    }
    return 0
}

function Get-OtterSafeFileName {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'app' }
    # A fixed set, not [System.IO.Path]::GetInvalidFileNameChars(): that list
    # is per host (Windows forbids < > : " / \ | ? * and control characters;
    # Linux and macOS forbid only / and NUL), so the same project published a
    # differently named artifact on each host. This is the Windows set, which
    # is also a safe name on every other host.
    $invalid = [char[]]@([char]'<', [char]'>', [char]':', [char]'"', [char]'/', [char]92, [char]'|', [char]'?', [char]'*') + [char[]](0..31 | ForEach-Object { [char]$_ })
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $Name.ToCharArray()) {
        if ($invalid -contains $ch -or [char]::IsWhiteSpace($ch)) {
            [void]$sb.Append('-')
        } else {
            [void]$sb.Append($ch)
        }
    }
    $sanitized = [System.Text.RegularExpressions.Regex]::Replace($sb.ToString(), '-+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($sanitized)) { return 'app' }
    return $sanitized
}

# Guards an output folder that build or publish is about to delete and
# replace. Before this check existed, containment alone decided what could be
# removed, so "build": { "outputDir": "src" } (with clean:true, the `otter new`
# default) wiped the project's sources, and `otter publish --output tests`
# wiped its tests. Now a folder is only replaced when Otter can tell it owns
# it:
#   - it never contains the project's entry point or manifest, and is never a
#     .git folder (or inside one), whatever else is true;
#   - it does not exist yet, is empty, or holds the marker file Otter writes
#     into every output it produces (otter.build.json for build,
#     otter.publish.json for publish).
# Anything else is refused with a message telling the user how to proceed,
# BEFORE anything is written, so a refused run leaves the project untouched.
function Assert-OtterReplaceableOutputDir {
    param(
        [Parameter(Mandatory = $true)]
        $Project,
        [Parameter(Mandatory = $true)]
        [string]$ResolvedDir,
        [Parameter(Mandatory = $true)]
        [string]$MarkerFileName,
        [Parameter(Mandatory = $true)]
        [string]$SettingName,
        # Set when the folder will be deleted and recreated (build clean:true,
        # every publish). When clear, only the hard refusals below apply,
        # because the run merely copies files into the existing folder.
        [switch]$WillDelete
    )

    $sep = [System.IO.Path]::DirectorySeparatorChar
    $dirWithSep = $ResolvedDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + $sep
    $ic = [System.StringComparison]::OrdinalIgnoreCase

    # Hard refusal 1: a .git segment anywhere in the path relative to the
    # project root means the output would delete or overwrite version-control
    # data.
    $rootDir = $Project.RootDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $relative = $ResolvedDir.Substring([Math]::Min($rootDir.Length, $ResolvedDir.Length))
    foreach ($segment in $relative.Split([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar), [System.StringSplitOptions]::RemoveEmptyEntries)) {
        if ($segment -ieq '.git') {
            throw [OtterError]::new("${SettingName} cannot be a .git folder or inside one: $ResolvedDir. Choose a different output folder.", 0, 'check')
        }
    }

    # Hard refusal 2: the folder holds the project's entry point or manifest,
    # so replacing (or overwriting into) it would destroy the program itself.
    foreach ($protected in @($Project.ResolvedEntryPoint, $Project.ManifestPath)) {
        if ([string]::IsNullOrWhiteSpace($protected)) { continue }
        $protectedFull = [System.IO.Path]::GetFullPath($protected)
        if ($protectedFull.StartsWith($dirWithSep, $ic)) {
            throw [OtterError]::new("${SettingName} `"$ResolvedDir`" contains the project's own file `"$protectedFull`". Choose an empty output folder such as `"dist`" or `"publish`".", 0, 'check')
        }
    }

    if (-not $WillDelete) { return }
    if (-not (Test-Path -LiteralPath $ResolvedDir)) { return }

    # A plain file with the output folder's name was never produced by Otter.
    if (-not (Test-Path -LiteralPath $ResolvedDir -PathType Container)) {
        throw [OtterError]::new("${SettingName} `"$ResolvedDir`" is a file, not a folder. Otter will not delete it; choose a different output folder or remove the file yourself.", 0, 'check')
    }

    # Safe to replace: empty, or carries the marker from an earlier Otter run.
    $firstEntry = Get-ChildItem -LiteralPath $ResolvedDir -Force | Select-Object -First 1
    if ($null -eq $firstEntry) { return }
    if (Test-Path -LiteralPath (Join-Path $ResolvedDir $MarkerFileName) -PathType Leaf) { return }

    throw [OtterError]::new("${SettingName} `"$ResolvedDir`" already exists and was not created by Otter (it has no $MarkerFileName), so Otter will not delete it. Choose an empty or new output folder, or delete that folder yourself if you no longer need its contents.", 0, 'check')
}

function Get-OtterVersionString {
    $candidates = @(
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION'),
        (Join-Path (Get-Location).Path 'VERSION'),
        (Join-Path $PSScriptRoot 'VERSION')
    )
    foreach ($cand in $candidates) {
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            try {
                $ver = (Get-Content -LiteralPath $cand -Raw).Trim()
                if (-not [string]::IsNullOrWhiteSpace($ver)) {
                    return $ver
                }
            } catch {}
        }
    }
    return '0.9.0'
}

function New-OtterDeterministicZip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        [Parameter(Mandatory = $true)]
        [string]$ZipPath
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -LiteralPath $ZipPath -Force
    }

    $sourceFull = [System.IO.Path]::GetFullPath($SourceDir)
    $files = @(Get-ChildItem -LiteralPath $sourceFull -Recurse -File | Sort-Object FullName)
    $fixedDate = [DateTimeOffset]::new(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

    $zipStream = [System.IO.File]::Create($ZipPath)
    $archive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $rel = $file.FullName.Substring($sourceFull.Length).TrimStart('\', '/') -replace '\\', '/'
            if ($rel.Contains('..') -or $rel.StartsWith('/') -or $rel -match '^[a-zA-Z]:') {
                throw [OtterError]::new("Forbidden path in package archive: $rel", 0, 'publish')
            }
            $entry = $archive.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $fixedDate
            $entryStream = $entry.Open()
            $fileStream = [System.IO.File]::OpenRead($file.FullName)
            try {
                $fileStream.CopyTo($entryStream)
            } finally {
                $fileStream.Dispose()
                $entryStream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
        $zipStream.Dispose()
    }
}

function Expand-OtterDeterministicArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationDir
    )
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $destFull = [System.IO.Path]::GetFullPath($DestinationDir)
    if (-not (Test-Path -LiteralPath $destFull)) {
        New-Item -ItemType Directory -Path $destFull -Force | Out-Null
    }
    $destWithSep = $destFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    $zipStream = [System.IO.File]::OpenRead($ZipPath)
    $archive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Read)
    try {
        foreach ($entry in $archive.Entries) {
            $normName = $entry.FullName -replace '\\', '/'
            if ($normName.Contains('..')) {
                throw [OtterError]::new("Archive entry contains forbidden path traversal: $normName", 0, 'publish')
            }
            if ($normName.StartsWith('/') -or $normName -match '^[a-zA-Z]:') {
                throw [OtterError]::new("Archive entry cannot be an absolute path: $normName", 0, 'publish')
            }
            $targetPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($destFull, $normName.Replace('/', [System.IO.Path]::DirectorySeparatorChar)))
            if (-not $targetPath.StartsWith($destWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw [OtterError]::new("Archive entry escapes extraction destination: $normName", 0, 'publish')
            }
            if ($normName.EndsWith('/')) {
                if (-not (Test-Path -LiteralPath $targetPath)) {
                    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                }
            } else {
                $targetParent = Split-Path -Parent $targetPath
                if (-not (Test-Path -LiteralPath $targetParent)) {
                    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
                }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            }
        }
    } finally {
        $archive.Dispose()
        $zipStream.Dispose()
    }
}

function Invoke-OtterProjectPublish {
    param(
        [Parameter(Mandatory = $false)]
        [string]$Target,
        [Parameter(Mandatory = $false)]
        [string]$OutputDir
    )

    if ([string]::IsNullOrWhiteSpace($Target)) {
        $Target = '.'
    }

    $project = Get-OtterProject -Path $Target
    $rootDir = $project.RootDirectory

    # 1. Manifest properties validation
    $manifestRaw = Get-Content -LiteralPath $project.ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifestRaw.PSObject.Properties['name'] -or [string]::IsNullOrWhiteSpace($manifestRaw.name)) {
        throw [OtterError]::new("otter.json: property `"name`" is required for publish.", 0, 'check')
    }
    if (-not $manifestRaw.PSObject.Properties['version'] -or [string]::IsNullOrWhiteSpace($manifestRaw.version)) {
        throw [OtterError]::new("otter.json: property `"version`" is required for publish.", 0, 'check')
    }
    if ([string]::IsNullOrWhiteSpace($project.Target)) {
        throw [OtterError]::new("otter.json: property `"target`" is required for publish.", 0, 'check')
    }
    if ([string]::IsNullOrWhiteSpace($project.EntryPoint)) {
        throw [OtterError]::new("otter.json: property `"entryPoint`" is required for publish.", 0, 'check')
    }

    # 2. Output directory containment validation
    $outDirName = if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir.Trim()
    } elseif ($project.Publish -and -not [string]::IsNullOrWhiteSpace($project.Publish.OutputDir)) {
        $project.Publish.OutputDir.Trim()
    } else {
        'publish'
    }

    if ($outDirName.StartsWith('/') -or $outDirName.StartsWith('\') -or $outDirName -match '^[a-zA-Z]:') {
        throw [OtterError]::new("publish.outputDir cannot be an absolute path: $outDirName", 0, 'check')
    }
    $resolvedPublishDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $outDirName))
    $rootWithSep = $rootDir.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if ($resolvedPublishDir -eq $rootDir -or (-not $resolvedPublishDir.StartsWith($rootWithSep, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw [OtterError]::new("publish.outputDir must stay inside the project directory and cannot be the project root itself.", 0, 'check')
    }

    # Replacement safety: step 5 always deletes the publish folder. Refuse,
    # before the build or anything else writes, a folder Otter did not create
    # (no otter.publish.json and not empty) or one holding the entry point,
    # the manifest, or .git, so `otter publish --output tests` cannot wipe
    # the project's tests.
    Assert-OtterReplaceableOutputDir -Project $project -ResolvedDir $resolvedPublishDir -MarkerFileName 'otter.publish.json' -SettingName 'publish.outputDir' -WillDelete

    $safeName = Get-OtterSafeFileName -Name $project.Name
    $version = $project.Version.Trim()
    # The version becomes part of folder and file names below
    # ("<name>-<version>", "<name>-<version>.zip"). Unlike the name it is not
    # sanitized, so a version such as "1/../../../victim/Startup" made publish
    # create folders and copy the entry point, assets and launcher outside the
    # project. Only accept a plain version string (letters, digits, and
    # . + - after a leading letter or digit, no ".."): it can never contain a
    # path separator, a drive colon, or a parent-folder step. Checked before
    # anything is built, staged, or written. \z (not $) so a trailing newline
    # cannot slip past the anchor.
    if ([string]::IsNullOrEmpty($version) -or $version -notmatch '^[0-9A-Za-z][0-9A-Za-z.+-]*\z' -or $version.Contains('..')) {
        throw [OtterError]::new("otter.json: property `"version`" must be a plain version such as `"1.2.3`" or `"1.0.0-rc.2`" (letters, digits, '.', '+', '-'; no '..' or path separators) to publish. Got: `"$version`".", 0, 'check')
    }
    $packageFolder = "$safeName-$version"
    $zipName = "$safeName-$version.zip"
    $sha256Name = "$safeName-$version.zip.sha256"

    Write-Host "Publishing $($project.Name) $version..."
    Write-Host "Target: $($project.Target)"
    Write-Host ""

    # 3. Build project first using the certified build system
    Write-Host "Building project..."
    $buildExitCode = Invoke-OtterProjectBuild -Target $rootDir -Quiet
    if ($buildExitCode -ne 0) {
        Write-Host "Publish failed." -ForegroundColor Red
        return $buildExitCode
    }

    # 4. Staging directory for atomic packaging & promotion
    $stagingDir = Join-Path $rootDir (".otter_publish_staging_" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    try {
        Write-Host "Packaging files..."
        $stagedPkgDir = Join-Path $stagingDir $packageFolder
        # Defense in depth behind the version check above: the package folder
        # and zip are built from manifest text, so confirm both resolve to
        # paths inside the staging folder before creating or copying
        # anything. If a future change lets a separator or ".." through, this
        # stops publish from writing outside the project instead of trusting it.
        $stagingWithSep = [System.IO.Path]::GetFullPath($stagingDir).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        foreach ($stagedCandidate in @($stagedPkgDir, (Join-Path $stagingDir $zipName))) {
            if (-not [System.IO.Path]::GetFullPath($stagedCandidate).StartsWith($stagingWithSep, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw [OtterError]::new("otter.json: name and version must not form a path outside the publish staging folder: $stagedCandidate", 0, 'check')
            }
        }
        New-Item -ItemType Directory -Path $stagedPkgDir -Force | Out-Null

        $resolvedBuildOutDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($rootDir, $project.Build.OutputDir))
        if (-not (Test-Path -LiteralPath $resolvedBuildOutDir -PathType Container)) {
            Write-Host "Publish failed." -ForegroundColor Red
            Write-Host ""
            Write-Host "Build output directory does not exist: $resolvedBuildOutDir" -ForegroundColor Red
            Write-Host ""
            return 1
        }

        # Copy build output files to package folder
        Get-ChildItem -LiteralPath $resolvedBuildOutDir -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $stagedPkgDir -Recurse -Force
        }

        # Collect included files list
        $includedFiles = @(Get-ChildItem -LiteralPath $stagedPkgDir -Recurse -File | ForEach-Object {
            $_.FullName.Substring($stagedPkgDir.Length).TrimStart('\', '/') -replace '\\', '/'
        } | Sort-Object)

        # Create deterministic ZIP archive
        $stagedZipPath = Join-Path $stagingDir $zipName
        New-OtterDeterministicZip -SourceDir $stagedPkgDir -ZipPath $stagedZipPath

        # Compute SHA-256
        Write-Host "Computing SHA-256..."
        $fileHash = (Get-FileHash -LiteralPath $stagedZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $stagedSha256Path = Join-Path $stagingDir $sha256Name
        $sha256Content = "$fileHash  $zipName`r`n"
        Set-Content -LiteralPath $stagedSha256Path -Value $sha256Content -Encoding ASCII

        # Generate publish metadata (otter.publish.json)
        $runtimeReq = switch ($project.Target.ToLowerInvariant()) {
            'web' { 'Modern web browser with JavaScript enabled.' }
            'game' { 'Modern web browser with HTML5 Canvas / WebGL enabled.' }
            'desktop' { 'Requires Otter runtime (otter in PATH) to run desktop application shell.' }
            { $_ -in @('console', 'automation') } { 'Requires Otter runtime (otter in PATH) to execute application.' }
            default { 'Standard execution environment.' }
        }

        $entryRel = if ($project.Target.ToLowerInvariant() -in @('web', 'desktop', 'game')) { 'index.html' } else { Split-Path -Leaf $project.ResolvedEntryPoint }
        $otterVer = Get-OtterVersionString

        $publishMetaObj = [ordered]@{
            name                = $project.Name
            version             = $version
            target              = $project.Target
            archetype           = $project.Archetype
            entryPoint          = $entryRel
            otterVersion        = $otterVer
            includedFiles       = $includedFiles
            assetManifest       = $project.Assets
            artifactFilename    = $zipName
            sha256              = $fileHash
            runtimeRequirements = $runtimeReq
        }
        $publishMetaJson = ConvertTo-Json -InputObject $publishMetaObj -Depth 5

        # Place otter.publish.json in staging root and package directory
        Set-Content -LiteralPath (Join-Path $stagingDir 'otter.publish.json') -Value $publishMetaJson -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $stagedPkgDir 'otter.publish.json') -Value $publishMetaJson -Encoding UTF8

        # Verify package
        Write-Host "Verifying package..."
        $testArchive = [System.IO.Compression.ZipFile]::OpenRead($stagedZipPath)
        try {
            if ($testArchive.Entries.Count -eq 0) {
                throw [OtterError]::new("Generated archive has zero entries.", 0, 'publish')
            }
            $entryNames = @($testArchive.Entries | ForEach-Object { $_.FullName })
            if ($entryNames -notcontains $entryRel) {
                throw [OtterError]::new("Generated archive is missing entry point $entryRel.", 0, 'publish')
            }
        } finally {
            $testArchive.Dispose()
        }

        # Checksum verification
        $verifyHash = (Get-FileHash -LiteralPath $stagedZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($verifyHash -ne $fileHash) {
            throw [OtterError]::new("Checksum verification mismatch for $zipName.", 0, 'publish')
        }

        # 5. Atomic promotion to publishDir
        if (Test-Path -LiteralPath $resolvedPublishDir) {
            Remove-Item -LiteralPath $resolvedPublishDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $resolvedPublishDir -Force | Out-Null

        Get-ChildItem -LiteralPath $stagingDir -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $resolvedPublishDir -Recurse -Force
        }
    }
    catch [OtterError] {
        Write-Host "Publish failed." -ForegroundColor Red
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        return 1
    }
    catch {
        Write-Host "Publish failed." -ForegroundColor Red
        Write-Host ""
        Write-Host "Otter hit a problem while publishing: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return 1
    }
    finally {
        if (Test-Path -LiteralPath $stagingDir) {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host ""
    Write-Host "Publish succeeded." -ForegroundColor Green
    Write-Host ""
    Write-Host "Artifact:"
    $relOutput = if ($resolvedPublishDir.StartsWith($rootDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $resolvedPublishDir.Substring($rootDir.Length).TrimStart('\', '/')
    } else {
        $outDirName
    }
    $relZip = ($relOutput -replace '\\', '/') + "/$zipName"
    Write-Host "  $relZip"
    Write-Host ""
    Write-Host "SHA-256:"
    Write-Host "  $fileHash"
    return 0
}

Export-ModuleMember -Function Find-OtterProjectManifest, Get-OtterProject, New-OtterProject, Get-OtterProjectTestFiles, Invoke-OtterProjectTests, Invoke-OtterProjectBuild, Invoke-OtterProjectPublish, Get-OtterSafeFileName, New-OtterDeterministicZip, Expand-OtterDeterministicArchive
