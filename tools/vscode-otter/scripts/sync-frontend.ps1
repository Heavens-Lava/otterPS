param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
)

$ErrorActionPreference = 'Stop'
$bundleRoot = (Join-Path $PSScriptRoot '..\bundled-frontend')
$bundleSource = Join-Path $RepositoryRoot 'src'
New-Item -ItemType Directory -Force -Path (Join-Path $bundleRoot 'src') | Out-Null
Copy-Item (Join-Path $RepositoryRoot 'Otter.Contract.psm1') (Join-Path $bundleRoot 'Otter.Contract.psm1') -Force
Copy-Item (Join-Path $bundleSource 'Otter.Lexer.psm1') (Join-Path $bundleRoot 'src\Otter.Lexer.psm1') -Force
Copy-Item (Join-Path $bundleSource 'Otter.Parser.psm1') (Join-Path $bundleRoot 'src\Otter.Parser.psm1') -Force

$commit = 'unknown'
try { $commit = (& git -C $RepositoryRoot rev-parse --short HEAD).Trim() } catch { }
[pscustomobject]@{
    Language = 'Otter'
    FrontendCommit = $commit
    Components = @('Otter.Contract.psm1', 'src/Otter.Lexer.psm1', 'src/Otter.Parser.psm1')
} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $bundleRoot 'manifest.json') -Encoding UTF8
Write-Output "Bundled Otter frontend commit $commit"
