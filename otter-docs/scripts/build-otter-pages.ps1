param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\generated'),
    [string[]]$Only = @()   # build just these page slugs (fast iteration)
)
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$webModule = Join-Path $repoRoot 'src\Otter.Web.psm1'
Import-Module $webModule -Force

$pagesRoot = Join-Path $PSScriptRoot '..\pages'
$releaseDataPath = Join-Path $PSScriptRoot '..\release-data.json'
$releaseData = Get-Content -LiteralPath $releaseDataPath -Raw | ConvertFrom-Json
$versionPath = Join-Path $repoRoot 'VERSION'
$repositoryVersion = (Get-Content -LiteralPath $versionPath -Raw).Trim()
if ($releaseData.version -ne $repositoryVersion) {
    throw "Release metadata version '$($releaseData.version)' does not match VERSION '$repositoryVersion'."
}

function Expand-OtterReleaseTokens {
    param([string]$Text)

    $tokens = @{
        '{{RELEASE_VERSION}}' = $releaseData.version
        '{{RELEASE_CHANNEL}}' = $releaseData.channel
        '{{WINDOWS_REQUIREMENTS}}' = $releaseData.windowsRequirements
        '{{INSTALLER_STATUS}}' = $releaseData.installerStatus
        '{{INSTALLER_SIZE}}' = $releaseData.installerSize
        '{{RELEASE_DATE}}' = $releaseData.releaseDate
        '{{SHA256}}' = $releaseData.sha256
        '{{RELEASE_NOTES_STATUS}}' = $releaseData.releaseNotesStatus
        '{{STUDIO_STATUS}}' = $releaseData.studioStatus
    }

    foreach ($token in $tokens.Keys) {
        $Text = $Text.Replace($token, [string]$tokens[$token])
    }
    return $Text
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$imageSource = Join-Path $PSScriptRoot '..\static\images'
$imageDestination = Join-Path $OutputRoot 'static\images'
if (Test-Path -LiteralPath $imageSource) {
    New-Item -ItemType Directory -Force -Path $imageDestination | Out-Null
    Get-ChildItem -LiteralPath $imageSource -File | Copy-Item -Destination $imageDestination -Force
}
$staticSource = Join-Path $PSScriptRoot '..\static'
$staticDestination = Join-Path $OutputRoot 'static'
if (Test-Path -LiteralPath $staticSource) {
    New-Item -ItemType Directory -Force -Path $staticDestination | Out-Null
    Get-ChildItem -LiteralPath $staticSource -File | Copy-Item -Destination $staticDestination -Force
}

# The search index is deliberately generated from the Otter-authored page
# sources. It stays in sync with the content and needs no server or package.
$searchPages = foreach ($page in Get-ChildItem -LiteralPath $pagesRoot -Filter '*.ot' | Where-Object { -not $_.Name.StartsWith('_') }) {
    $sourceText = Get-Content -LiteralPath $page.FullName -Raw
    $titleMatch = [regex]::Match($sourceText, 'title\s+"((?:[^"\\]|\\.)*)"')
    $title = if ($titleMatch.Success) { $titleMatch.Groups[1].Value -replace '\\"', '"' } else { [IO.Path]::GetFileNameWithoutExtension($page.Name) }
    $title = $title -replace '\s+-\s+Otter Documentation$', ''
    $parts = foreach ($match in [regex]::Matches($sourceText, '(?:value|text)\s+"((?:[^"\\]|\\.)*)"')) {
        $match.Groups[1].Value.Replace('\\n', ' ').Replace('\\"', '"')
    }
    [pscustomobject]@{
        title = $title
        url = '/' + [IO.Path]::GetFileNameWithoutExtension($page.Name) + '/'
        text = ($parts -join ' ')
    }
}
$searchPages | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $staticDestination 'docs-index.json') -Encoding UTF8

foreach ($source in Get-ChildItem -LiteralPath $pagesRoot -Filter '*.ot' | Where-Object { -not $_.Name.StartsWith('_') -and -not $_.Name.StartsWith('.') -and ($Only.Count -eq 0 -or $Only -contains [IO.Path]::GetFileNameWithoutExtension($_.Name)) } | Sort-Object Name) {
    $slug = [IO.Path]::GetFileNameWithoutExtension($source.Name)
    $destinationDir = Join-Path $OutputRoot $slug
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    $destination = Join-Path $destinationDir 'index.html'
    $sourceText = Get-Content -LiteralPath $source.FullName -Raw
    $sourcePath = $source.FullName
    $temporarySource = $null
    if ($sourceText.Contains('{{')) {
        # Beside the real source, so `use "shell.ot"` still resolves relative to the pages folder.
        $temporarySource = Join-Path $source.DirectoryName (".build-$([guid]::NewGuid().ToString('N')).ot")
        Set-Content -LiteralPath $temporarySource -Value (Expand-OtterReleaseTokens $sourceText) -Encoding UTF8
        $sourcePath = $temporarySource
    }

    try {
        Export-OtterWebApplication -SourcePath $sourcePath -OutputPath $destination | Out-Null
        $enhancement = '<link rel="stylesheet" href="/static/docs-enhancements.css">' + "`n" + '<script defer src="/static/docs-enhancements.js"></script>' + "`n"
        $html = Get-Content -LiteralPath $destination -Raw
        $html = $html -replace '(?i)</head>', ($enhancement + '</head>')
        Set-Content -LiteralPath $destination -Value $html -Encoding UTF8
    }
    finally {
        if ($temporarySource -and (Test-Path -LiteralPath $temporarySource)) {
            Remove-Item -LiteralPath $temporarySource -Force
        }
    }
    Write-Host "Built /$slug/"
}
