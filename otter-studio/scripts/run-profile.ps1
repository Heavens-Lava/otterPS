# run-profile.ps1 - Profiler executor for Otter Studio
using module ..\..\Otter.Contract.psm1
using module ..\..\src\Otter.Runtime.psm1
using module ..\..\src\Otter.Lexer.psm1
using module ..\..\src\Otter.Parser.psm1
using module ..\..\src\Otter.Validation.psm1
using module ..\..\src\Otter.Interpreter.psm1
using module ..\..\src\Otter.Module.psm1
using module ..\..\src\Otter.Profiler.psm1

param(
    [string]$FilePath,
    [string]$Source,
    [int]$Top = 25
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path "$scriptDir\..\..").Path

$sourceText = ''
$resolvedProgram = $null
$effectivePath = $FilePath

if ($FilePath) {
    $resolved = Resolve-Path -LiteralPath $FilePath -ErrorAction SilentlyContinue
    if (-not $resolved -or (Test-Path -LiteralPath $resolved.Path -PathType Container)) {
        [pscustomobject]@{
            ok = $false
            error = [pscustomobject]@{
                message = "File not found: $FilePath"
                line = 1
                stage = 'file'
            }
            output = @()
            profile = $null
        } | ConvertTo-Json -Depth 6
        exit 0
    }
    $effectivePath = $resolved.Path
    $resolvedProgram = Resolve-OtterModuleSource -FilePath $effectivePath
    $sourceText = $resolvedProgram.CombinedSource
} elseif ($Source) {
    $sourceText = $Source
} else {
    [pscustomobject]@{
        ok = $false
        error = [pscustomobject]@{
            message = "Either FilePath or Source must be provided"
            line = 1
            stage = 'cli'
        }
        output = @()
        profile = $null
    } | ConvertTo-Json -Depth 6
    exit 0
}

$sourceLines = $sourceText -split "`r?`n"
$outputList = [System.Collections.Generic.List[string]]::new()
$writer = {
    param($text)
    $outputList.Add($text)
}
Set-OtterOutputWriter -Writer $writer

$env = New-OtterEnvironment
if ($effectivePath) {
    Set-OtterApplicationId -Path $effectivePath
}

$errorInfo = $null
$exitCode = 0

try {
    $tokens = ConvertTo-OtterTokens -Source $sourceText
    $ast = ConvertTo-OtterAst -Tokens $tokens
    Assert-OtterLanguageContract -Program $ast -SourceLines $sourceLines

    Start-OtterProfile
    Invoke-OtterProgram -Program $ast -Environment $env -SourceLines $sourceLines
} catch {
    $exitCode = 3
    $line = if ($_.Exception.PSObject.Properties['Line']) { $_.Exception.Line } else { 1 }
    $column = if ($_.Exception.PSObject.Properties['Column']) { $_.Exception.Column } else { 1 }
    $errorInfo = [pscustomobject]@{
        message = $_.Exception.Message
        line = $line
        column = $column
        stage = if ($_.Exception.PSObject.Properties['Stage']) { $_.Exception.Stage } else { 'runtime' }
    }
}

$profileResult = $null
try {
    $profileResult = Get-OtterProfileResult -SourceLines $sourceLines -Top $Top
} catch {
    if ($null -eq $errorInfo) {
        $errorInfo = [pscustomobject]@{
            message = "Profiler collection error: $($_.Exception.Message)"
            line = 1
            stage = 'profiler'
        }
    }
}

Set-OtterStatementHook -Hook $null
Set-OtterOutputWriter -Writer $null

[pscustomobject]@{
    ok = ($null -eq $errorInfo)
    exitCode = $exitCode
    error = $errorInfo
    output = $outputList.ToArray()
    profile = $profileResult
} | ConvertTo-Json -Depth 6
