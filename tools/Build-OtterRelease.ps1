# Build-OtterRelease.ps1 - D58 packaging
#
# Builds the smallest complete v1 Windows distribution from a clean checkout
# and produces a versioned zip plus a SHA-256 checksum file, both under
# dist\. Nothing here changes the language, the CLI contract, or runtime
# behavior - it only decides what ships and assembles it.
#
# Usage:
#   powershell -NoProfile -File .\tools\Build-OtterRelease.ps1

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
$packageName = "otter-$version-windows-x64"

$distDir = Join-Path $repoRoot 'dist'
$stagingDir = Join-Path $distDir $packageName
$zipPath = Join-Path $distDir "$packageName.zip"
$shaPath = "$zipPath.sha256"

Write-Host "Building Otter release $version"

if (Test-Path -LiteralPath $stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if (Test-Path -LiteralPath $shaPath) { Remove-Item -LiteralPath $shaPath -Force }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

# The smallest complete v1 distribution: the CLI entry point, the contract,
# every module the interpreter, desktop UI, web compiler, and server need at
# runtime, the frozen v1 dogfood examples, one plain non-UI example, and the
# release README. Deliberately excludes: scratch/, test-only assets, backup/,
# experimental examples, build artifacts (*.html exports), and developer-only
# docs (rules*.md, KEYWORD-AUDIT.md, SPEC-DECISIONS.md).
$filesToCopy = @(
    'otter.cmd',
    'otter.ps1',
    'VERSION',
    'Otter.Contract.psm1'
)

$srcModules = @(
    'Otter.Runtime.psm1',
    'Otter.Lexer.psm1',
    'Otter.Parser.psm1',
    'Otter.Interpreter.psm1',
    'Otter.Library.psm1',
    'Otter.UI.psm1',
    'Otter.Web.psm1',
    'Otter.Server.psm1'
)

foreach ($file in $filesToCopy) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination (Join-Path $stagingDir $file)
}

$srcDest = Join-Path $stagingDir 'src'
New-Item -ItemType Directory -Path $srcDest -Force | Out-Null
foreach ($module in $srcModules) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "src\$module") -Destination (Join-Path $srcDest $module)
}

$examplesDest = Join-Path $stagingDir 'examples'
$v1Dest = Join-Path $examplesDest 'v1'
New-Item -ItemType Directory -Path $v1Dest -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'examples\hello.ot') -Destination (Join-Path $examplesDest 'hello.ot')
Get-ChildItem -LiteralPath (Join-Path $repoRoot 'examples\v1') -Filter '*.ot' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $v1Dest $_.Name)
}

$readme = @"
# Otter $version

Readable like English. Precise like code.

## Install

1. Extract this archive anywhere - including a path with spaces.
2. Add the extracted folder to your PATH (see below), or run ``otter.cmd``
   with its full path.
3. Open a *new* terminal window (PATH changes do not apply to windows
   already open).

### Add to PATH (current user only, reversible)

``````powershell
`$otterDir = 'C:\path\to\extracted\otter'
`$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
[Environment]::SetEnvironmentVariable('Path', "`$userPath;`$otterDir", 'User')
``````

This only appends to your personal PATH - it does not touch the system PATH
or remove anything already there. To undo it, remove that one entry from
Control Panel > Environment Variables, or:

``````powershell
`$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
`$cleaned = (`$userPath -split ';' | Where-Object { `$_ -ne '`$otterDir' }) -join ';'
[Environment]::SetEnvironmentVariable('Path', `$cleaned, 'User')
``````

## Try it

``````
otter --version
otter help
otter check examples\hello.ot
otter examples\hello.ot
``````

## Requirements

- Windows 10 or later
- Windows PowerShell 5.1 (built into Windows; this is not PowerShell 7/pwsh)
- .NET Framework / WPF (built into Windows) for desktop UI programs

## What is in this package

- ``otter.cmd`` / ``otter.ps1`` - the CLI
- ``Otter.Contract.psm1``, ``src\*.psm1`` - the interpreter, runtime, desktop
  UI, and web/server modules
- ``examples\hello.ot`` - a plain non-UI example
- ``examples\v1\`` - the certified v1 desktop applications (task list, file
  browser, contact manager)

See ``otter help`` for the full command list.
"@
Set-Content -LiteralPath (Join-Path $stagingDir 'README.md') -Value $readme -Encoding utf8

Write-Host "Staged at $stagingDir"

Compress-Archive -Path (Join-Path $stagingDir '*') -DestinationPath $zipPath -Force
Write-Host "Archive: $zipPath"

$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
"$($hash.Hash.ToLowerInvariant())  $packageName.zip" | Set-Content -LiteralPath $shaPath -Encoding ascii
Write-Host "Checksum: $shaPath"
Write-Host "SHA-256: $($hash.Hash)"

Write-Host "Done."
