param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\generated')
)

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

foreach ($source in Get-ChildItem -LiteralPath $pagesRoot -Filter '*.ot' | Where-Object { -not $_.Name.StartsWith('_') -and -not $_.Name.StartsWith('.') } | Sort-Object Name) {
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
    }
    finally {
        if ($temporarySource -and (Test-Path -LiteralPath $temporarySource)) {
            Remove-Item -LiteralPath $temporarySource -Force
        }
    }
    Write-Host "Built /$slug/"
}
