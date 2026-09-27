# tools/ReleaseSurface.Common.ps1
#
# Shared, READ-ONLY helpers for the Otter 1.0 release-surface tooling:
#   tools/New-OtterContractEvidence.ps1      derives token/node/diagnostic evidence
#   tools/Initialize-OtterReleaseSurface.ps1 seeds release/otter-1.0-surface.json
#   tools/Test-OtterReleaseSurface.ps1       audits the manifest (read-only)
#   tools/New-OtterSurfaceReconciliation.ps1 writes the reconciliation report
#
# Nothing here decides what is public. It only reads the repository and reports
# what it finds.

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Get-OtterRepoRoot { return $script:RepoRoot }

function Read-OtterText {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $script:RepoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Get-OtterSha256 {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $script:RepoRoot $RelativePath
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        # Normalize line endings so the hash does not depend on autocrlf.
        $text = [System.Text.Encoding]::UTF8.GetString($bytes) -replace "`r`n", "`n"
        $hash = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally { $sha.Dispose() }
}

function Get-OtterGitSha {
    try {
        $sha = (& git -C $script:RepoRoot rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $sha) { return ([string]$sha).Trim() }
    } catch {}
    return $null
}

# Parses one `enum Name { ... }` block out of the frozen contract text and returns
# each member with the standalone comment above it (its "section") and its own
# trailing comment.
function Get-OtterEnumInventory {
    param([Parameter(Mandatory)][string]$ContractText, [Parameter(Mandatory)][string]$EnumName)

    $lines = $ContractText -split "`r?`n"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*enum\s+' + [regex]::Escape($EnumName) + '\s*\{')) { $start = $i; break }
    }
    if ($start -lt 0) { throw "enum $EnumName not found in the contract." }

    $members = New-Object System.Collections.Generic.List[object]
    $section = ''
    $previousWasComment = $false
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*\}\s*$') { break }
        $trim = $line.Trim()
        if ($trim -eq '') { $previousWasComment = $false; continue }
        if ($trim.StartsWith('#')) {
            # A block of consecutive comment lines is ONE section heading: only its
            # first line names the section; the rest is continuation text.
            if (-not $previousWasComment) {
                $text = ($trim -replace '^#+\s*', '') -replace '\s*-{2,}\s*$', '' -replace '^-{2,}\s*', ''
                $section = $text.Trim()
            }
            $previousWasComment = $true
            continue
        }
        $previousWasComment = $false
        if ($trim -match '^([A-Za-z_][A-Za-z0-9_]*)\s*(?:#\s*(.*))?$') {
            $comment = if ($Matches[2]) { $Matches[2].Trim() } else { '' }
            $members.Add([pscustomobject]@{ Name = $Matches[1]; Section = $section; Comment = $comment })
        }
    }
    return $members
}

# NodeKind -> AST class name (same approach as tools/Test-OtterContractCoverage.ps1).
function Get-OtterNodeClassMap {
    param([Parameter(Mandatory)][string]$ContractText)
    $map = @{}
    $pattern = 'class\s+([A-Za-z0-9_]+)\s*:\s*Node\s*\{(?:(?!\r?\nclass\s).)*?\[NodeKind\]::([A-Za-z0-9_]+)'
    foreach ($m in [regex]::Matches($ContractText, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $map[$m.Groups[2].Value] = $m.Groups[1].Value
    }
    return $map
}

# Keyword text -> TokenKind names, from the lexer's keyword table.
function Get-OtterLexerKeywords {
    param([Parameter(Mandatory)][string]$LexerText)
    $map = @{}
    foreach ($m in [regex]::Matches($LexerText, "'([^']+)'\s*=\s*\[TokenKind\]::([A-Za-z0-9_]+)")) {
        $token = $m.Groups[2].Value
        if (-not $map.ContainsKey($token)) { $map[$token] = New-Object System.Collections.Generic.List[string] }
        if (-not $map[$token].Contains($m.Groups[1].Value)) { $map[$token].Add($m.Groups[1].Value) }
    }
    return $map
}

# D-numbers (D41, D107 ...) cited in a comment or section title.
function Get-OtterDecisionRefs {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return @() }
    $refs = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($Text, '\bD(\d{1,3}(?:\.\d+)?[A-Z]?)\b')) {
        $id = 'D' + $m.Groups[1].Value
        if (-not $refs.Contains($id)) { $refs.Add($id) }
    }
    return $refs.ToArray()
}

# The modules whose text counts as a "consumer" of a contract member, per target.
function Get-OtterConsumerGroups {
    return [ordered]@{
        interpreter = @('src/Otter.Interpreter.psm1')
        javascript  = @('src/Otter.Compiler.JavaScript.psm1')
        browser     = @('src/Otter.Web.psm1')
        desktop     = @('src/Otter.Desktop.psm1', 'src/Otter.UI.psm1')
        provider    = @('src/Otter.Library.psm1', 'src/Otter.Database.psm1', 'src/Otter.Server.psm1', 'src/Otter.Runtime.psm1')
    }
}

function Test-OtterNodeReferenced {
    param([string]$NodeName, [string]$ClassName, [string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $false }
    if ($ClassName -and $Text -match ('\[' + [regex]::Escape($ClassName) + '\]')) { return $true }
    if ($Text -match [regex]::Escape("'$NodeName'")) { return $true }
    if ($Text -match ('\[NodeKind\]::' + [regex]::Escape($NodeName) + '\b')) { return $true }
    return $false
}

# All child nodes of a node, found by reflection so this does not need a
# per-class visitor. Walks arrays and nested plain objects (layout specs, etc.).
function Get-OtterNodeKindsInTree {
    param($Root)
    $found = New-Object 'System.Collections.Generic.HashSet[string]'
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Root)
    $guard = 0
    while ($stack.Count -gt 0 -and $guard -lt 200000) {
        $guard++
        $item = $stack.Pop()
        if ($null -eq $item) { continue }
        if ($item -is [string] -or $item -is [ValueType]) { continue }
        if ($item -is [System.Collections.IDictionary]) {
            foreach ($v in $item.Values) { $stack.Push($v) }
            continue
        }
        if ($item -is [System.Collections.IEnumerable]) {
            foreach ($v in $item) { $stack.Push($v) }
            continue
        }
        $props = $item.PSObject.Properties
        $kind = $props['Kind']
        if ($null -ne $kind -and $null -ne $kind.Value) {
            [void]$found.Add($kind.Value.ToString())
        }
        foreach ($p in $props) {
            if ($p.Name -eq 'Kind') { continue }
            $value = $null
            try { $value = $p.Value } catch { continue }
            if ($null -ne $value -and -not ($value -is [string]) -and -not ($value -is [ValueType])) { $stack.Push($value) }
        }
    }
    return $found
}
