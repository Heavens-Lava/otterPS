# otter-fast.ps1 - fast start on macOS and Linux (PowerShell 7).
#
# The `otter` launcher sends a plain run here (`otter run hello.ot ...` or
# `otter hello.ot ...` with no argument starting with "-"). When otter.ps1 has
# already compiled the program and wrote a fast-start entry for this
# PowerShell, and neither the file nor Otter has changed since, the cached
# compiled program runs straight away - without loading Otter's modules, which
# is most of a normal start. Anything else runs otter.ps1, in this same
# process, exactly as the launcher would have.
#
# This mirrors otter.exe on Windows (distribution/launcher/OtterLauncher.cs):
# the same entry, the same checks, and the same output and exit codes as
# otter.ps1 (tests/FastStart.Tests.ps1). OTTER_ENGINE_TRACE=1 reports the path.

function Write-FastTrace([string]$Text) {
    if ($env:OTTER_ENGINE_TRACE -eq '1') { [Console]::Error.WriteLine("otter engine: $Text") }
}

function Get-FastSha256([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (([System.BitConverter]::ToString($sha.ComputeHash($Bytes))) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

# Get-OtterToolchainFingerprint in otter.ps1, unchanged.
function Get-FastToolchain([string]$Root) {
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @('otter.ps1', 'Otter.Contract.psm1', 'VERSION')) { $files.Add((Join-Path $Root $name)) }
    $src = Join-Path $Root 'src'
    if (Test-Path -LiteralPath $src) {
        foreach ($f in [System.IO.Directory]::GetFiles($src, '*', [System.IO.SearchOption]::AllDirectories)) {
            $ext = [System.IO.Path]::GetExtension($f).ToLowerInvariant()
            if ($ext -eq '.psm1' -or $ext -eq '.cs') { $files.Add($f) }
        }
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $files) {
        $relative = [System.IO.Path]::GetFullPath($f).Substring($Root.Length + 1).Replace('\', '/').ToLowerInvariant()
        $info = [System.IO.FileInfo]::new($f)
        if ($info.Exists) { $parts.Add("${relative}:$($info.Length):$($info.LastWriteTimeUtc.Ticks)") } else { $parts.Add("${relative}:missing") }
    }
    $sorted = $parts.ToArray()
    [Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    return (Get-FastSha256 ([System.Text.Encoding]::UTF8.GetBytes(($sorted -join "`n"))))
}

# Returns $true when the program ran here (the process then exits with its code).
function Invoke-FastStart([object[]]$Arguments) {
    if ($env:OTTER_ENGINE -eq 'interpreter' -or $env:OTTER_FAST_START -eq '0') { Write-FastTrace 'interpreter path via otter.ps1 (switched off)'; return $false }
    $fileIndex = if ($Arguments.Count -ge 2 -and [string]$Arguments[0] -eq 'run') { 1 } elseif ($Arguments.Count -ge 1) { 0 } else { -1 }
    if ($fileIndex -lt 0 -or -not ([string]$Arguments[$fileIndex]).EndsWith('.ot', [StringComparison]::OrdinalIgnoreCase)) { Write-FastTrace 'interpreter path via otter.ps1 (not a run of a .ot file)'; return $false }

    $root = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
    $fullPath = [System.IO.Path]::GetFullPath([string]$Arguments[$fileIndex], (Get-Location).ProviderPath)
    if (-not [System.IO.File]::Exists($fullPath)) { Write-FastTrace 'interpreter path via otter.ps1 (file not found)'; return $false }

    $edition = $PSVersionTable.PSEdition
    $sourceKey = if ($IsWindows -or $edition -eq 'Desktop') { $fullPath.ToLowerInvariant() } else { $fullPath }
    $cache = if ($env:OTTER_COMPILED_CACHE) { $env:OTTER_COMPILED_CACHE } elseif ($env:XDG_CACHE_HOME) { Join-Path $env:XDG_CACHE_HOME 'otter/compiled' } else { Join-Path $HOME '.cache/otter/compiled' }
    $key = (Get-FastSha256 ([System.Text.Encoding]::UTF8.GetBytes("$sourceKey|$edition"))).Substring(0, 32)
    $entryPath = Join-Path (Join-Path $cache 'fast') "$key.entry"
    if (-not [System.IO.File]::Exists($entryPath)) { Write-FastTrace 'interpreter path via otter.ps1 (no fast-start entry yet)'; return $false }
    $entry = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($entryPath)) { $eq = $line.IndexOf('='); if ($eq -gt 0) { $entry[$line.Substring(0, $eq)] = $line.Substring($eq + 1) } }

    $version = ([System.IO.File]::ReadAllText((Join-Path $root 'VERSION'))).Trim()
    $reason = $null
    if ($entry['format'] -ne '1') { $reason = 'entry format' }
    elseif ($entry['psEdition'] -ne $edition -or $entry['psVersion'] -ne $PSVersionTable.PSVersion.ToString()) { $reason = 'compiled by another PowerShell' }
    elseif ($entry['otterVersion'] -ne $version) { $reason = 'different Otter version' }
    elseif ($entry['toolchain'] -ne (Get-FastToolchain $root)) { $reason = 'Otter itself changed' }
    elseif ($entry['source'] -cne $sourceKey) { $reason = 'entry for another file' }
    if ($reason) { Write-FastTrace "interpreter path via otter.ps1 ($reason)"; return $false }
    $sourceBytes = [System.IO.File]::ReadAllBytes($fullPath)
    if ($entry['sourceSha256'] -ne (Get-FastSha256 $sourceBytes)) { Write-FastTrace 'interpreter path via otter.ps1 (the file changed)'; return $false }
    if (-not ([System.IO.File]::Exists($entry['assembly']) -and [System.IO.File]::Exists($entry['runtime']))) { Write-FastTrace 'interpreter path via otter.ps1 (compiled program missing from the cache)'; return $false }

    try {
        if (-not ('OtterNative.R' -as [type])) { Add-Type -Path $entry['runtime'] -ErrorAction Stop }
        Add-Type -Path $entry['assembly'] -ErrorAction Stop
        $programType = $entry['className'] -as [type]
        if (-not $programType) { throw 'program type not found' }
    }
    catch { Write-FastTrace "interpreter path via otter.ps1 (cannot load the compiled program: $($_.Exception.Message))"; return $false }

    Write-FastTrace "compiled (fast start, $($entry['className']))"
    $global = [OtterNative.Env]::new($null)
    $programArgs = [System.Collections.Generic.List[object]]::new()
    for ($i = $fileIndex + 1; $i -lt $Arguments.Count; $i++) { $programArgs.Add([string]$Arguments[$i]) }
    $global.Set('arguments', $programArgs)
    # Write-OtterLine: each `say` is one Write-Host line, as in otter.ps1.
    [OtterNative.R]::Reset($global, [Action[string]] { param($text) Write-Host $text })
    try {
        $programType.GetMethod('Run').Invoke($null, @(, $global)) | Out-Null
    }
    catch {
        $inner = $_.Exception
        while (($inner -is [System.Management.Automation.MethodInvocationException] -or $inner -is [System.Reflection.TargetInvocationException]) -and $inner.InnerException) { $inner = $inner.InnerException }
        if ($inner -is [OtterNative.OtterNativeError] -or $inner -is [OtterNative.OtterStopSignal]) {
            $lineNumber = $inner.Line
            $suggestion = if ($inner -is [OtterNative.OtterNativeError]) { $inner.Suggestion } else { $null }
            $message = $inner.Message
        }
        else {
            $lineNumber = 0
            $suggestion = 'Run it again with the interpreter: set OTTER_ENGINE=interpreter, and please report this.'
            $message = "Otter's compiled engine hit an internal problem: $($inner.Message)"
        }
        # Show-OtterFailure + OtterError.FormatDetailed, quoting the file's own
        # line as otter.ps1's error remap does.
        $sourceLines = [System.IO.File]::ReadAllLines($fullPath)
        $text = [System.Text.StringBuilder]::new()
        [void]$text.AppendLine('Otter Runtime Error')
        [void]$text.AppendLine('')
        if ($lineNumber -gt 0) {
            [void]$text.AppendLine("Line ${lineNumber}:")
            if ($lineNumber -le $sourceLines.Count -and $sourceLines[$lineNumber - 1]) { [void]$text.AppendLine("    $($sourceLines[$lineNumber - 1].TrimStart().TrimEnd())") }
            [void]$text.AppendLine('')
        }
        [void]$text.AppendLine($message)
        if ($suggestion) { [void]$text.AppendLine(''); [void]$text.AppendLine('Try:'); [void]$text.AppendLine("    $suggestion") }
        Write-Host ''
        Write-Host $text.ToString().TrimEnd() -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit(3)
    }
    [Environment]::Exit(0)
}

if (-not (Invoke-FastStart -Arguments $args)) {
    & (Join-Path $PSScriptRoot 'otter.ps1') @args
    exit $LASTEXITCODE
}
