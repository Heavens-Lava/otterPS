# Builds otter.exe, Otter's Windows launcher (distribution/launcher/OtterLauncher.cs),
# with the .NET Framework C# compiler that every Windows 10/11 machine has.
#
#     powershell -NoProfile -File tools\Build-OtterLauncher.ps1 [-Destination <folder>]
#
# otter.exe goes beside otter.ps1 (the repository root by default); otter.cmd
# uses it when it is there. It runs already-compiled programs without starting
# PowerShell and hands everything else to otter.ps1.
[CmdletBinding()]
param([string]$Destination = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Destination) { $Destination = $root }
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "The .NET Framework C# compiler was not found at $csc." }
$source = Join-Path $root 'distribution\launcher\OtterLauncher.cs'
$output = Join-Path $Destination 'otter.exe'
$messages = & $csc /nologo /optimize+ /target:exe /platform:anycpu "/out:$output" $source 2>&1
if ($LASTEXITCODE -ne 0) { throw "Compiling otter.exe failed:`n$($messages -join "`n")" }
Write-Host "Built $output"
