using module ..\Otter.Contract.psm1

# Otter.Module.psm1 - Shared Otter Source & Module Resolver
#
# Resolves `use "..."` module dependencies identically across all targets
# (Web, Desktop, Console) per D60.
#
# Tracks source file origins and line maps so diagnostics know:
#   terminal.ot:42
#   studio.ot:118
# instead of flattening everything into an anonymous giant file.

class OtterSourceLocation {
    [int]$CombinedLine
    [string]$FilePath
    [int]$LocalLine

    OtterSourceLocation([int]$combinedLine, [string]$filePath, [int]$localLine) {
        $this.CombinedLine = $combinedLine
        $this.FilePath = $filePath
        $this.LocalLine = $localLine
    }
}

class OtterResolvedProgram {
    [string]$CombinedSource
    [string[]]$LoadedFiles
    [OtterSourceLocation[]]$SourceMap

    OtterResolvedProgram([string]$combinedSource, [string[]]$loadedFiles, [OtterSourceLocation[]]$sourceMap) {
        $this.CombinedSource = $combinedSource
        $this.LoadedFiles = $loadedFiles
        $this.SourceMap = $sourceMap
    }

    [OtterSourceLocation] FindOrigin([int]$combinedLine) {
        if ($null -eq $this.SourceMap -or $this.SourceMap.Length -eq 0) {
            return $null
        }
        foreach ($loc in $this.SourceMap) {
            if ($loc.CombinedLine -eq $combinedLine) {
                return $loc
            }
        }
        return $null
    }
}

class OtterModuleContext {
    [System.Collections.Generic.HashSet[string]]$LoadedFiles
    [System.Collections.Generic.List[string]]$CallStack
    [System.Collections.Generic.List[OtterSourceLocation]]$SourceMap
    [int]$GlobalLineCounter

    OtterModuleContext() {
        # Ordinal: module identity is the file's exact on-disk path (M1). Two
        # files whose names differ only in case are two modules on hosts that
        # allow both to exist.
        $this.LoadedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $this.CallStack = [System.Collections.Generic.List[string]]::new()
        $this.SourceMap = [System.Collections.Generic.List[OtterSourceLocation]]::new()
        $this.GlobalLineCounter = 1
    }
}

function Get-OtterCanonicalPath {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    $p = if ($resolved) { $resolved.Path } else { [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath($p).TrimEnd('\', '/')
}

# M1: module paths are case-sensitive on every host. A `use` path must spell
# every folder and file name exactly as it exists on disk. Windows and macOS
# file systems would otherwise accept "utils.ot" for a file named "Utils.ot",
# so a program could work on one machine and fail after being copied to Linux.
# Each name in the path is compared, ordinally, with the real directory entries;
# "." and ".." are navigation, not names, and are not checked. There is no
# case-insensitive fallback.
function Assert-OtterModulePathCase {
    param(
        [Parameter(Mandatory)][string]$BaseDirectory,
        [Parameter(Mandatory)][string]$ImportPath,
        [int]$Line,
        [string]$SourceLine
    )
    $current = $BaseDirectory
    $walkPath = $ImportPath
    $rootPrefix = ''
    # D122 / RC3 B13: an absolute use path ("/home/me/lib/Utils.ot",
    # "C:\lib\Utils.ot") has nothing to do with the importing file's folder.
    # Walking its segments from $BaseDirectory found no match for the first
    # one ("home", "C:") and returned silently, so absolute paths skipped the
    # exact-case check entirely: a wrong-case absolute path loaded on Windows
    # and macOS but was "Cannot find" on Linux. Start the walk at the path's
    # own root instead, so every name after the root is checked the same way.
    # The root itself (a drive letter, "/", a UNC share) is not a name in any
    # directory listing and is not compared.
    if ([System.IO.Path]::IsPathRooted($ImportPath)) {
        $pathRoot = [System.IO.Path]::GetPathRoot($ImportPath)
        if ($pathRoot) {
            $current = $pathRoot
            $walkPath = $ImportPath.Substring($pathRoot.Length)
            # Kept only to spell the corrected path in the suggestion.
            $rootPrefix = $pathRoot.Replace([char]92, [char]47)
            if (-not $rootPrefix.EndsWith('/')) { $rootPrefix += '/' }
        }
    }
    $segments = @($walkPath -split '[\\/]' | Where-Object { $_ -ne '' })
    $written = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $segment = $segments[$i]
        if ($segment -eq '.') { $written.Add($segment); continue }
        if ($segment -eq '..') { $written.Add($segment); $current = [System.IO.Path]::GetDirectoryName($current); continue }
        $names = @()
        try { $names = @([System.IO.Directory]::GetFileSystemEntries($current) | ForEach-Object { [System.IO.Path]::GetFileName($_) }) } catch { $names = @() }
        if ($names -ccontains $segment) {
            $written.Add($segment)
            $current = [System.IO.Path]::Combine($current, $segment)
            continue
        }
        $actual = @($names | Where-Object { [string]::Equals($_, $segment, [System.StringComparison]::OrdinalIgnoreCase) })
        if ($actual.Count -gt 0) {
            $isLast = ($i -eq $segments.Count - 1)
            $kind = if ($isLast) { 'file' } else { 'folder' }
            $corrected = @($written) + @($actual[0]) + @($segments | Select-Object -Skip ($i + 1))
            throw [OtterError]::new(
                "The $kind is named `"$($actual[0])`", but this use says `"$segment`". Module paths must match file and folder names exactly, including capital letters.",
                $Line, 'parser', 1, $SourceLine,
                "use `"$rootPrefix$($corrected -join '/')`"")
        }
        # Not in the listing under any case, yet it exists: a Windows 8.3
        # short name such as "RUNNER~1" (common in absolute temp and profile
        # paths). A short name has no "real" spelling to compare, so accept
        # it and keep checking the names after it; stopping here would skip
        # the case check for the rest of the path, which is what B13 fixes.
        $shortNameTarget = [System.IO.Path]::Combine($current, $segment)
        if (Test-Path -LiteralPath $shortNameTarget) {
            $written.Add($segment)
            $current = $shortNameTarget
            continue
        }
        return   # not found at all: the caller's existing "Cannot find" diagnostic applies
    }
}

# The file's path with every name spelled as it is on disk. Module identity
# (duplicate loads, cycle detection) compares these ordinally.
function Get-OtterOnDiskPath {
    param([Parameter(Mandatory)][string]$FullPath)
    $full = [System.IO.Path]::GetFullPath($FullPath).TrimEnd([char]92, [char]47)
    $root = [System.IO.Path]::GetPathRoot($full)
    $rest = $full.Substring($root.Length)
    $current = $root
    foreach ($segment in @($rest -split '[\\/]' | Where-Object { $_ -ne '' })) {
        $match = $null
        try {
            $names = @([System.IO.Directory]::GetFileSystemEntries($current) | ForEach-Object { [System.IO.Path]::GetFileName($_) })
            if ($names -ccontains $segment) { $match = $segment }
            else { $match = @($names | Where-Object { [string]::Equals($_, $segment, [System.StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1 }
        } catch { $match = $null }
        if (-not $match) { $match = $segment }
        $current = [System.IO.Path]::Combine($current, $match)
    }
    return $current
}

function Test-OtterCallStackContains {
    param(
        [System.Collections.Generic.List[string]]$CallStack,
        [string]$Path
    )
    foreach ($entry in $CallStack) {
        if ([string]::Equals($entry, $Path, [System.StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Resolve-OtterModuleSourceInternal {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][OtterModuleContext]$Context
    )

    $canonicalPath = Get-OtterCanonicalPath -Path $FilePath
    if (-not (Test-Path -LiteralPath $canonicalPath)) {
        throw [OtterError]::new("Cannot find Otter source file `"$FilePath`".", 0, 'parser')
    }
    $canonicalPath = Get-OtterOnDiskPath -FullPath $canonicalPath

    # Check for circular import in active call stack (exact on-disk path)
    if (Test-OtterCallStackContains -CallStack $Context.CallStack -Path $canonicalPath) {
        $cycleList = [System.Collections.Generic.List[string]]::new($Context.CallStack)
        $cycleList.Add($canonicalPath)
        $cycleNames = $cycleList | ForEach-Object { [System.IO.Path]::GetFileName($_) }
        $cycleChain = $cycleNames -join ' -> '
        throw [OtterError]::new("Circular import detected: $cycleChain", 0, 'parser')
    }

    # If already loaded in an earlier sibling/branch, do not re-emit (exact on-disk path)
    if ($Context.LoadedFiles.Contains($canonicalPath)) {
        return ""
    }
    $Context.LoadedFiles.Add($canonicalPath) | Out-Null
    $Context.CallStack.Add($canonicalPath)

    $dir = [System.IO.Path]::GetDirectoryName($canonicalPath)
    $lines = @(Get-Content -LiteralPath $canonicalPath -Encoding UTF8)
    $expandedLines = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $localLineNum = $i + 1
        $line = $lines[$i]

        if ($line -match '^\s*use\s+"([^"]+)"\s*$') {
            $importRel = $Matches[1]
            $importTarget = [System.IO.Path]::Combine($dir, $importRel)
            $canonicalImportTarget = Get-OtterCanonicalPath -Path $importTarget

            # Case first: a name that differs only in case must give the same
            # diagnostic on every host. On Linux such a file does not exist at
            # all, so the generic "cannot find" check below would otherwise
            # answer differently than on Windows and macOS.
            Assert-OtterModulePathCase -BaseDirectory $dir -ImportPath $importRel -Line $localLineNum -SourceLine $line
            if (-not (Test-Path -LiteralPath $canonicalImportTarget)) {
                throw [OtterError]::new("Cannot find imported Otter file `"$importRel`" at `"$importTarget`".", $localLineNum, 'parser', 1, $line, "Check that `"$importRel`" exists in `"$dir`".")
            }

            # Emit comment header for import
            $importHeader = "# --- imported from $importRel ---"
            $expandedLines.Add($importHeader)
            $Context.SourceMap.Add([OtterSourceLocation]::new($Context.GlobalLineCounter, $canonicalPath, $localLineNum))
            $Context.GlobalLineCounter = $Context.GlobalLineCounter + 1

            $imported = Resolve-OtterModuleSourceInternal `
                -FilePath $canonicalImportTarget `
                -Context $Context

            if ($imported.Length -gt 0) {
                $expandedLines.Add($imported)
            }

            $importFooter = "# --- end import $importRel ---"
            $expandedLines.Add($importFooter)
            $Context.SourceMap.Add([OtterSourceLocation]::new($Context.GlobalLineCounter, $canonicalPath, $localLineNum))
            $Context.GlobalLineCounter = $Context.GlobalLineCounter + 1
        } else {
            $expandedLines.Add($line)
            $Context.SourceMap.Add([OtterSourceLocation]::new($Context.GlobalLineCounter, $canonicalPath, $localLineNum))
            $Context.GlobalLineCounter = $Context.GlobalLineCounter + 1
        }
    }

    # Pop from active call stack
    $Context.CallStack.RemoveAt($Context.CallStack.Count - 1)

    return ($expandedLines -join "`n")
}

function Resolve-OtterModuleSource {
    param(
        [Parameter(Mandatory)][string]$FilePath
    )

    $context = [OtterModuleContext]::new()
    $combined = Resolve-OtterModuleSourceInternal -FilePath $FilePath -Context $context

    $loadedArray = [string[]]::new($context.LoadedFiles.Count)
    $context.LoadedFiles.CopyTo($loadedArray)

    return [OtterResolvedProgram]::new($combined, $loadedArray, $context.SourceMap.ToArray())
}

function Get-OtterSourceLocation {
    param(
        [Parameter(Mandatory)][OtterResolvedProgram]$Program,
        [Parameter(Mandatory)][int]$CombinedLine
    )
    return $Program.FindOrigin($CombinedLine)
}

function Remap-OtterSingleError {
    param(
        [Parameter(Mandatory)][OtterError]$Error,
        [Parameter(Mandatory)][OtterResolvedProgram]$ResolvedProgram,
        [Parameter(Mandatory)][string]$CanonicalRoot
    )

    if ($Error.Line -le 0) {
        return $Error
    }

    $origin = $ResolvedProgram.FindOrigin($Error.Line)
    if ($null -eq $origin) {
        return $Error
    }

    $message = $Error.Message
    $canonicalOrigin = Get-OtterCanonicalPath -Path $origin.FilePath
    if (-not [string]::Equals($canonicalOrigin, $CanonicalRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $fileName = [System.IO.Path]::GetFileName($origin.FilePath)
        $prefix = "In `"$fileName`": "
        if (-not $message.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $message = "$prefix$message"
        }
    }

    $sourceLine = $Error.SourceLine
    try {
        if (Test-Path -LiteralPath $origin.FilePath) {
            $originLines = [System.IO.File]::ReadAllLines($origin.FilePath)
            if ($origin.LocalLine -ge 1 -and $origin.LocalLine -le $originLines.Count) {
                $sourceLine = $originLines[$origin.LocalLine - 1]
            }
        }
    } catch {
        # Fall back to existing source line
    }

    return [OtterError]::new(
        $message,
        $origin.LocalLine,
        $Error.Stage,
        $Error.Column,
        $sourceLine,
        $Error.Suggestion,
        $Error.Code
    )
}

function ConvertTo-OtterRemappedDiagnostics {
    param(
        [Parameter(Mandatory)][OtterError]$Error,
        [Parameter(Mandatory)][OtterResolvedProgram]$ResolvedProgram,
        [Parameter(Mandatory)][string]$RootFile
    )

    $canonicalRoot = Get-OtterCanonicalPath -Path $RootFile

    if ($Error -is [OtterMultipleErrorsException]) {
        $remappedList = [System.Collections.Generic.List[OtterError]]::new()
        foreach ($diag in $Error.Diagnostics) {
            $remappedDiag = Remap-OtterSingleError -Error $diag -ResolvedProgram $ResolvedProgram -CanonicalRoot $canonicalRoot
            $remappedList.Add($remappedDiag)
        }
        return [OtterMultipleErrorsException]::new($remappedList.ToArray())
    }

    return Remap-OtterSingleError -Error $Error -ResolvedProgram $ResolvedProgram -CanonicalRoot $canonicalRoot
}

Export-ModuleMember -Function Resolve-OtterModuleSource, Get-OtterSourceLocation, Get-OtterCanonicalPath, ConvertTo-OtterRemappedDiagnostics

