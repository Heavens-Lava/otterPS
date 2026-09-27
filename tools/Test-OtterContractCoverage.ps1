using module ..\Otter.Contract.psm1

<#
.SYNOPSIS
    Audits the frozen token and AST enums against the production pipeline.

.DESCRIPTION
    This is a structural release check, not a replacement for behavioural
    tests. It makes the contract inventory reproducible: every declared token
    must be consumed by the lexer or parser, and every declared AST kind must
    be constructed by the parser or handled/rejected by a runtime target.
    Explicitly reserved contract members are named below rather than silently
    disappearing from the result.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-OtterCombinedText {
    param([string[]]$RelativePaths)

    $parts = foreach ($relativePath in $RelativePaths) {
        $path = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Coverage source is missing: $relativePath"
        }
        Get-Content -LiteralPath $path -Raw
    }
    return ($parts -join "`n")
}

function Test-OtterEnumReference {
    param(
        [string[]]$Names,
        [string]$EnumName,
        [string]$Text,
        [string[]]$AllowedUnreferenced = @()
    )

    $missing = @()
    foreach ($name in $Names) {
        if ($AllowedUnreferenced -contains $name) {
            continue
        }
        $pattern = '\[' + [regex]::Escape($EnumName) + '\]::' + [regex]::Escape($name) + '\b'
        if ($Text -notmatch $pattern) {
            $missing += $name
        }
    }
    return $missing
}

function Get-OtterNodeClassMap {
    param([string]$ContractText)

    $map = @{}
    $pattern = 'class\s+([A-Za-z0-9_]+)\s*:\s*Node\s*\{(?:(?!\r?\nclass\s).)*?\[NodeKind\]::([A-Za-z0-9_]+)'
    foreach ($match in [regex]::Matches($ContractText, $pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $map[$match.Groups[2].Value] = $match.Groups[1].Value
    }
    return $map
}

$tokenPipeline = Get-OtterCombinedText @(
    'src/Otter.Lexer.psm1',
    'src/Otter.Parser.psm1'
)
$contractText = Get-Content -LiteralPath (Join-Path $repoRoot 'Otter.Contract.psm1') -Raw
$parserText = Get-OtterCombinedText @('src/Otter.Parser.psm1')
$runtimePipeline = Get-OtterCombinedText @(
    'src/Otter.Interpreter.psm1',
    'src/Otter.Compiler.JavaScript.psm1',
    'src/Otter.Web.psm1',
    'src/Otter.Desktop.psm1',
    'src/Otter.Server.psm1'
)

$tokens = [System.Enum]::GetNames([TokenKind])
$nodes = [System.Enum]::GetNames([NodeKind])

# UiLayout is a compatibility reservation. D114.5 records that layout data is
# carried by UiElement rather than a standalone UiLayout AST node.
$tokenExceptions = @('Thing')
$nodeExceptions = @('UiLayout')

$missingTokens = Test-OtterEnumReference -Names $tokens -EnumName 'TokenKind' -Text $tokenPipeline -AllowedUnreferenced $tokenExceptions
$nodeClasses = Get-OtterNodeClassMap -ContractText $contractText
$missingNodes = @()
foreach ($node in $nodes) {
    if ($nodeExceptions -contains $node) { continue }
    if (-not $nodeClasses.ContainsKey($node)) {
        $missingNodes += "$node (no AST class)"
        continue
    }

    $className = $nodeClasses[$node]
    $parserPattern = '\[' + [regex]::Escape($className) + '\]::new\('
    if ($parserText -notmatch $parserPattern) {
        $missingNodes += "$node (parser does not construct $className)"
        continue
    }

    # Back ends commonly dispatch by class (`-is [FooStmt]`) or by the enum's
    # string value in a switch. Accept either actual dispatch representation.
    $classPattern = '\[' + [regex]::Escape($className) + '\]'
    $kindPattern = [regex]::Escape("'$node'")
    $enumPattern = '\[NodeKind\]::' + [regex]::Escape($node) + '\b'
    if ($runtimePipeline -notmatch $classPattern -and $runtimePipeline -notmatch $kindPattern -and $runtimePipeline -notmatch $enumPattern) {
        $missingNodes += "$node (no runtime/compiler dispatch reference)"
    }
}

Write-Output "TokenKind declarations: $($tokens.Count)"
Write-Output "NodeKind declarations: $($nodes.Count)"
Write-Output "NodeKind AST classes: $($nodeClasses.Count)"
Write-Output "Reserved NodeKind exceptions: $($nodeExceptions -join ', ')"

if ($missingTokens.Count -gt 0) {
    throw "Unreferenced TokenKind declarations in lexer/parser pipeline: $($missingTokens -join ', ')"
}
if ($missingNodes.Count -gt 0) {
    throw "Unreferenced NodeKind declarations in parser/runtime pipeline: $($missingNodes -join ', ')"
}

Write-Output 'Contract structural coverage passed.'
