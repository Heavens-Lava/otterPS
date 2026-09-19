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
        $this.LoadedFiles = [System.Collections.Generic.HashSet[string]]::new()
        $this.CallStack = [System.Collections.Generic.List[string]]::new()
        $this.SourceMap = [System.Collections.Generic.List[OtterSourceLocation]]::new()
        $this.GlobalLineCounter = 1
    }
}

function Resolve-OtterModuleSourceInternal {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][OtterModuleContext]$Context
    )

    $resolved = Resolve-Path -LiteralPath $FilePath -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw [OtterError]::new("Cannot find Otter source file `"$FilePath`".", 0, 'runtime')
    }
    $fullPath = $resolved.Path

    # Check for circular import in active call stack
    if ($Context.CallStack.Contains($fullPath)) {
        $cycleList = [System.Collections.Generic.List[string]]::new($Context.CallStack)
        $cycleList.Add($fullPath)
        $cycleNames = $cycleList | ForEach-Object { [System.IO.Path]::GetFileName($_) }
        $cycleChain = $cycleNames -join ' -> '
        throw [OtterError]::new("Circular import detected: $cycleChain", 0, 'runtime')
    }

    # If already loaded in an earlier sibling/branch, do not re-emit
    if ($Context.LoadedFiles.Contains($fullPath)) {
        return ""
    }
    $Context.LoadedFiles.Add($fullPath) | Out-Null
    $Context.CallStack.Add($fullPath)

    $dir = [System.IO.Path]::GetDirectoryName($fullPath)
    $lines = @(Get-Content -LiteralPath $fullPath -Encoding UTF8)
    $expandedLines = [System.Collections.Generic.List[string]]::new()

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $localLineNum = $i + 1
        $line = $lines[$i]

        if ($line -match '^\s*use\s+"([^"]+)"\s*$') {
            $importRel = $Matches[1]
            $importTarget = [System.IO.Path]::Combine($dir, $importRel)

            if (-not (Test-Path -LiteralPath $importTarget)) {
                throw [OtterError]::new("Cannot find imported Otter file `"$importRel`" at `"$importTarget`".", $localLineNum, 'runtime', 1, $line, "Check that `"$importRel`" exists in `"$dir`".")
            }

            # Emit comment header for import
            $importHeader = "# --- imported from $importRel ---"
            $expandedLines.Add($importHeader)
            $Context.SourceMap.Add([OtterSourceLocation]::new($Context.GlobalLineCounter, $fullPath, $localLineNum))
            $Context.GlobalLineCounter = $Context.GlobalLineCounter + 1

            $imported = Resolve-OtterModuleSourceInternal `
                -FilePath $importTarget `
                -Context $Context

            if ($imported.Length -gt 0) {
                $expandedLines.Add($imported)
            }

            $importFooter = "# --- end import $importRel ---"
            $expandedLines.Add($importFooter)
            $Context.SourceMap.Add([OtterSourceLocation]::new($Context.GlobalLineCounter, $fullPath, $localLineNum))
            $Context.GlobalLineCounter = $Context.GlobalLineCounter + 1
        } else {
            $expandedLines.Add($line)
            $Context.SourceMap.Add([OtterSourceLocation]::new($Context.GlobalLineCounter, $fullPath, $localLineNum))
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

Export-ModuleMember -Function Resolve-OtterModuleSource, Get-OtterSourceLocation
