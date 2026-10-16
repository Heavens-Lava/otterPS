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
$releaseData = [System.IO.File]::ReadAllText($releaseDataPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
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
        # The release zip on GitHub; before a release, the repository page.
        '{{DOWNLOAD_URL}}' = $(if ($releaseData.downloadUrl) { $releaseData.downloadUrl } else { 'https://github.com/Heavens-Lava/otterPS' })
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
    # Fill in {{RELEASE_VERSION}} and friends, as the page build does, so search
    # results never show the raw tokens.
    $sourceText = Expand-OtterReleaseTokens ([System.IO.File]::ReadAllText($page.FullName, [System.Text.Encoding]::UTF8))
    $titleMatch = [regex]::Match($sourceText, 'title\s+"((?:[^"\\]|\\.)*)"')
    $title = if ($titleMatch.Success) { $titleMatch.Groups[1].Value -replace '\\"', '"' } else { [IO.Path]::GetFileNameWithoutExtension($page.Name) }
    $title = $title -replace '\s+-\s+Otter Documentation$', ''
    $parts = foreach ($match in [regex]::Matches($sourceText, '(?:value|text)\s+"((?:[^"\\]|\\.)*)"')) {
        # Undo the Otter string escaping left to right: \n and \t read as a space, \" as ", \\ as \.
        [regex]::Replace($match.Groups[1].Value, '\\(.)', {
            param($escape)
            if ('n', 't' -contains $escape.Groups[1].Value) { ' ' } else { $escape.Groups[1].Value }
        })
    }
    [pscustomobject]@{
        title = $title
        url = '/' + [IO.Path]::GetFileNameWithoutExtension($page.Name) + '/'
        text = ($parts -join ' ')
    }
}
$searchPages | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $staticDestination 'docs-index.json') -Encoding UTF8

# --- Search engines -------------------------------------------------------
# Every page gets a description, a canonical address and link-preview tags;
# the site gets robots.txt and sitemap.xml. The public root (/) is the home
# page (publish-site.ps1 copies /home/ there), so /home/ points at it.
$siteUrl = 'https://otterprogramming.com'
$socialImage = "$siteUrl/static/images/otter-social.jpg"
$pageDescriptions = @{
    'home'            = 'Otter is a programming language that reads like English. Write scripts, desktop apps, web apps and servers in plain words. Free for Windows, macOS and Linux.'
    'download'        = 'Download Otter {{RELEASE_VERSION}}, the programming language that reads like English. One free zip for Windows, macOS and Linux, with nothing else to install on Windows.'
    'docs'            = 'Learn Otter from the ground up: install it, write your first program, then the whole language - values, decisions, loops, lists, functions, files, the web and more.'
    'quick-reference' = 'The whole Otter language on one printable page: running programs, values, math, text, decisions, loops, lists, functions, files, CSV, JSON, the internet, servers, databases and apps.'
    'first-program'   = 'Write and run your first Otter program in a few minutes: one line, say "Hello, Otter!", and the otter command.'
    'what-is-otter'   = 'What Otter is: a programming language designed so a program makes sense when you read it out loud, with errors that explain themselves.'
    'examples'        = 'Real Otter programs to open, change and run: greetings, input, decisions, counting, lists, finding and organising files, and handling errors.'
    'installation'    = 'Install Otter on Windows, macOS or Linux. On Windows, Otter runs on the Windows PowerShell already built in - no runtime and no administrator rights.'
    'about'           = 'About Otter, the programming language that reads like English, and why it was made.'
}

function ConvertTo-HtmlAttribute([string]$Text) {
    return $Text.Replace('&', '&amp;').Replace('"', '&quot;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function Get-OtterSearchMetadata {
    param([string]$Slug, [string]$Html)
    $url = if ($Slug -eq 'home') { "$siteUrl/" } else { "$siteUrl/$Slug/" }
    $titleMatch = [regex]::Match($Html, '(?is)<title>(.*?)</title>')
    $title = if ($titleMatch.Success) { [System.Net.WebUtility]::HtmlDecode($titleMatch.Groups[1].Value.Trim()) } else { 'Otter' }
    $description = $pageDescriptions[$Slug]
    if ($description) { $description = Expand-OtterReleaseTokens $description }
    else {
        # The page's first paragraph of prose: body-sized text (15-22px) that is
        # not code (no monospace font) and is long enough to be a sentence.
        $text = ''
        foreach ($m in [regex]::Matches($Html, '<div id="[^"]+" class="otter-text" style="([^"]*)">([^<]{40,})</div>')) {
            $style = $m.Groups[1].Value
            $sizeMatch = [regex]::Match($style, 'font-size: (\d+)px')
            if ($style -match 'monospace' -or -not $sizeMatch.Success) { continue }
            $size = [int]$sizeMatch.Groups[1].Value
            if ($size -lt 15 -or $size -gt 22) { continue }
            $text = ($text + ' ' + [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value)).Trim()
            if ($text.Length -ge 110) { break }   # one paragraph, or two short ones
        }
        if (-not $text) {
            # Otherwise the page's own opening words, after its title.
            $entry = $searchPages | Where-Object { $_.url -eq "/$Slug/" } | Select-Object -First 1
            $text = if ($entry) { [string]$entry.text } else { '' }
            if ($entry -and $text.StartsWith([string]$entry.title)) { $text = $text.Substring(([string]$entry.title).Length) }
        }
        $text = ($text -replace '\s+', ' ').Trim()
        if ($text.Length -gt 155) { $text = $text.Substring(0, 155); $text = $text.Substring(0, [Math]::Max($text.LastIndexOf(' '), 100)).TrimEnd(',', ';', ':') + '...' }
        $description = if ($text) { $text } else { 'Otter is a programming language that reads like English.' }
    }
    $t = ConvertTo-HtmlAttribute $title; $d = ConvertTo-HtmlAttribute $description
    return @(
        "<meta name=`"description`" content=`"$d`">"
        "<link rel=`"canonical`" href=`"$url`">"
        '<meta property="og:site_name" content="Otter">'
        '<meta property="og:type" content="website">'
        "<meta property=`"og:title`" content=`"$t`">"
        "<meta property=`"og:description`" content=`"$d`">"
        "<meta property=`"og:url`" content=`"$url`">"
        "<meta property=`"og:image`" content=`"$socialImage`">"
        '<meta property="og:image:width" content="1200">'
        '<meta property="og:image:height" content="630">'
        '<meta name="twitter:card" content="summary_large_image">'
        "<meta name=`"twitter:title`" content=`"$t`">"
        "<meta name=`"twitter:description`" content=`"$d`">"
        "<meta name=`"twitter:image`" content=`"$socialImage`">"
    ) -join "`n"
}

# The web compiler emits every text as a <div>, so search engines see no
# headings. Promote by styling, which is how the pages express structure:
# the first title of 40px+ (weight 800) becomes the page's single <h1>, the
# other 24px+ bold titles <h2>, and 17-23px bold card titles <h3>. Only plain
# text elements (no nested markup) are touched; ids and classes are kept.
function ConvertTo-OtterSemanticHeadings([string]$Html) {
    $script:hasH1 = $false
    return [regex]::Replace($Html, '<div (id="[^"]+" class="otter-text" style="[^"]*?font-size: (\d+(?:\.\d+)?)px; font-weight: (\d+)[^"]*")>([^<]*)</div>', {
        param($m)
        $size = [double]$m.Groups[2].Value; $weight = [int]$m.Groups[3].Value
        $tag = $null
        if ($weight -ge 800 -and $size -ge 40 -and -not $script:hasH1) { $tag = 'h1'; $script:hasH1 = $true }
        elseif ($weight -ge 800 -and $size -ge 24) { $tag = 'h2' }
        elseif ($weight -ge 700 -and $size -ge 17 -and $size -lt 24) { $tag = 'h3' }
        if (-not $tag) { return $m.Value }
        return "<$tag $($m.Groups[1].Value)>$($m.Groups[4].Value)</$tag>"
    })
}

foreach ($source in Get-ChildItem -LiteralPath $pagesRoot -Filter '*.ot' | Where-Object { -not $_.Name.StartsWith('_') -and -not $_.Name.StartsWith('.') -and ($Only.Count -eq 0 -or $Only -contains [IO.Path]::GetFileNameWithoutExtension($_.Name)) } | Sort-Object Name) {
    $slug = [IO.Path]::GetFileNameWithoutExtension($source.Name)
    $destinationDir = Join-Path $OutputRoot $slug
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    $destination = Join-Path $destinationDir 'index.html'
    $sourceText = [System.IO.File]::ReadAllText($source.FullName, [System.Text.Encoding]::UTF8)
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
        $enhancement = '<link rel="icon" href="/static/images/otter-site-icon.png" type="image/png">' + "`n" + '<link rel="apple-touch-icon" href="/static/images/otter-site-icon.png">' + "`n" + '<link rel="stylesheet" href="/static/docs-enhancements.css">' + "`n" + '<script defer src="/static/docs-enhancements.js"></script>' + "`n"
        $html = Get-Content -LiteralPath $destination -Raw
        $enhancement = (Get-OtterSearchMetadata -Slug $slug -Html $html) + $enhancement
        $html = $html -replace '(?i)</head>', ($enhancement + '</head>')
        $html = ConvertTo-OtterSemanticHeadings $html
        Set-Content -LiteralPath $destination -Value $html -Encoding UTF8
    }
    finally {
        if ($temporarySource -and (Test-Path -LiteralPath $temporarySource)) {
            Remove-Item -LiteralPath $temporarySource -Force
        }
    }
    Write-Host "Built /$slug/"
}

# robots.txt and sitemap.xml list every page, whatever -Only built this time.
# The home page lives at the root, so /home/ is left out of the sitemap.
$sitemapDate = (Get-Date).ToString('yyyy-MM-dd')
$sitemapEntries = foreach ($page in Get-ChildItem -LiteralPath $pagesRoot -Filter '*.ot' | Where-Object { -not $_.Name.StartsWith('_') -and -not $_.Name.StartsWith('.') } | Sort-Object Name) {
    $pageSlug = [IO.Path]::GetFileNameWithoutExtension($page.Name)
    $loc = if ($pageSlug -eq 'home') { "$siteUrl/" } else { "$siteUrl/$pageSlug/" }
    "  <url><loc>$loc</loc><lastmod>$sitemapDate</lastmod></url>"
}
$sitemap = @('<?xml version="1.0" encoding="UTF-8"?>', '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">') + $sitemapEntries + '</urlset>'
[System.IO.File]::WriteAllText((Join-Path $OutputRoot 'sitemap.xml'), ($sitemap -join "`n") + "`n", (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText((Join-Path $OutputRoot 'robots.txt'), "User-agent: *`nAllow: /`n`nSitemap: $siteUrl/sitemap.xml`n", (New-Object System.Text.UTF8Encoding($false)))
