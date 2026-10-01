using module ..\..\Otter.Contract.psm1
using module ..\..\src\Otter.Runtime.psm1
using module ..\..\src\Otter.Interpreter.psm1
using module ..\..\src\Otter.Compiler.Native.psm1

# experiments/native-compiler/Invoke-OtterCompiled.ps1
#
# Runs an Otter program through the EXPERIMENTAL compiled backend
# (src/Otter.Compiler.Native.psm1). Not part of the otter command.
#
#   powershell -NoProfile -File experiments/native-compiler/Invoke-OtterCompiled.ps1 program.ot
#     -ShowCSharp   print the generated C# instead of running
#     -Compare      also run the interpreter and compare the output exactly
#     -Time         report compile time and run time
#
# Exit codes follow the otter command: 0 success, 2 syntax error, 3 runtime
# error, 4 not supported by the compiled backend yet, 5 -Compare mismatch.

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][string]$Path,
    [switch]$ShowCSharp,
    [switch]$Compare,
    [switch]$Time
)

Import-Module (Join-Path $PSScriptRoot '..\..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\..\src\Otter.Parser.psm1') -Force

$ErrorActionPreference = 'Stop'
$cache = Join-Path ([System.IO.Path]::GetTempPath()) 'otter-native-cache'
$source = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
$sourceLines = $source -split "`r?`n"

try { $program = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source) }
catch { Write-Output $_.Exception.FormatDetailed(); exit 2 }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try { $compiled = New-OtterNativeProgram -Program $program -SourceText $source -CacheDirectory $cache }
catch {
    if ($_.Exception -is [OtterError]) { Write-Output "Not compiled: $($_.Exception.Message)"; exit 4 }
    throw
}
$compileMs = $sw.Elapsed.TotalMilliseconds
if ($ShowCSharp) { Write-Output $compiled.CSharp; exit 0 }

function Invoke-Backend {
    param([string]$Name)
    $lines = [System.Collections.Generic.List[string]]::new()
    $code = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if ($Name -eq 'compiled') {
            Invoke-OtterNativeProgram -Compiled $compiled -Writer { param($t) $lines.Add($t) }.GetNewClosure() -SourceLines $sourceLines
        } else {
            Set-OtterOutputWriter -Writer { param($t) $lines.Add($t) }.GetNewClosure()
            try { Invoke-OtterProgram -Program $program -Environment (New-OtterEnvironment) -SourceLines $sourceLines }
            finally { Set-OtterOutputWriter -Writer $null }
        }
    }
    catch {
        if ($_.Exception -is [OtterError]) { $lines.Add($_.Exception.FormatDetailed()); $code = 3 } else { throw }
    }
    return [pscustomobject]@{ Lines = $lines; Code = $code; Ms = $sw.Elapsed.TotalMilliseconds }
}

$native = Invoke-Backend -Name 'compiled'
foreach ($l in $native.Lines) { Write-Output $l }
if ($Time) { Write-Host ('compiled: compile {0:N0} ms, run {1:N2} ms' -f $compileMs, $native.Ms) -ForegroundColor Cyan }

if ($Compare) {
    $reference = Invoke-Backend -Name 'interpreter'
    if ($Time) { Write-Host ('interpreter: run {0:N0} ms' -f $reference.Ms) -ForegroundColor Cyan }
    $same = ($native.Code -eq $reference.Code) -and (($native.Lines -join "`n") -ceq ($reference.Lines -join "`n"))
    if (-not $same) {
        Write-Host 'MISMATCH with the interpreter:' -ForegroundColor Red
        Write-Host "  compiled (exit $($native.Code)):"; $native.Lines | ForEach-Object { Write-Host "    $_" }
        Write-Host "  interpreter (exit $($reference.Code)):"; $reference.Lines | ForEach-Object { Write-Host "    $_" }
        exit 5
    }
    Write-Host 'matches the interpreter' -ForegroundColor Green
}
exit $native.Code
