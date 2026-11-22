# publish-site.ps1 - builds the Otter website and stages it in the GitHub Pages
# repository (Heavens-Lava.github.io, checked out at ..\otter-site-publish).
#
# The website is authored in Otter (otter-docs/pages/*.ot) and compiled by the
# Otter compiler in this repository, so the SOURCE lives here and the
# deployable OUTPUT lives in its own repository. This script only stages the
# output; it never commits or pushes - review `git status` in the Pages
# repository and publish deliberately.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\otter-docs\scripts\publish-site.ps1
param(
    [string]$PublishRepo = (Join-Path $PSScriptRoot '..\..\otter-site-publish'),
    [string]$OtterNetLibrary = '',
    [switch]$SkipBuild   # reuse the existing generated\ output
)

$ErrorActionPreference = 'Stop'
$generated = Join-Path $PSScriptRoot '..\generated'

if (-not $SkipBuild) {
    $buildArgs = @{}
    if ($OtterNetLibrary) { $buildArgs.OtterNetLibrary = $OtterNetLibrary }
    & (Join-Path $PSScriptRoot 'build-otter-pages.ps1') @buildArgs | Out-Null
}
& (Join-Path $PSScriptRoot 'audit-otter-routes.ps1')

$libraryIndex = Join-Path $generated (Join-Path 'library' 'index.html')
$libraryCatalog = Join-Path $generated (Join-Path 'static' 'library-catalog.json')
if (-not (Test-Path -LiteralPath $libraryIndex) -or -not (Test-Path -LiteralPath $libraryCatalog)) {
    throw "Component library output is missing from $generated. Refusing to stage a publish without /library/."
}

$PublishRepo = (Resolve-Path -LiteralPath $PublishRepo).Path
if (-not (Test-Path -LiteralPath (Join-Path $PublishRepo '.git'))) {
    throw "$PublishRepo is not a git repository. Clone the GitHub Pages repository there first."
}

$generatedPath = (Resolve-Path -LiteralPath $generated).Path

# Mirror the build into the Pages repository, leaving its own files alone.
if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    & robocopy $generatedPath $PublishRepo /MIR /XD '.git' /XF '.nojekyll' 'README.md' 'CNAME' /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE." }
} else {
    $srcWithSlash = $generatedPath.TrimEnd('/') + '/'
    $dstWithSlash = $PublishRepo.TrimEnd('/') + '/'
    & rsync -a --delete --exclude '.git' --exclude '.nojekyll' --exclude 'README.md' --exclude 'CNAME' $srcWithSlash $dstWithSlash
    if ($LASTEXITCODE -ne 0) { throw "rsync failed with exit code $LASTEXITCODE." }
}

# The public root is the home page (/home/): what Otter is, a runnable
# example, the comparison with JavaScript and Python, and the download - the
# front door for someone new. The documentation stays at /docs/.
Copy-Item -LiteralPath (Join-Path $generated (Join-Path 'home' 'index.html')) -Destination (Join-Path $PublishRepo 'index.html') -Force
if (-not (Test-Path -LiteralPath (Join-Path $PublishRepo '.nojekyll'))) {
    New-Item -ItemType File -Path (Join-Path $PublishRepo '.nojekyll') | Out-Null
}

Write-Host "Staged the site (including /library/) in $PublishRepo"
Write-Host 'Review with: git -C otter-site-publish status   (nothing has been committed or pushed)'
