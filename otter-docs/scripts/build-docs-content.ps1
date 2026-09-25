# build-docs-content.ps1 - one-off migration: writes the docs sidebar module
# (pages/_docs.ot) and turns the legacy Node documentation pages
# (scripts/legacy-pages.json, from export-legacy-pages.mjs) into Otter-authored
# pages in the new design. The generated .ot files are the source of truth.
# By default only the sidebar and the all-topics page are (re)written - the pages under
# pages/ are the source of truth and carry hand edits. -RegeneratePages rebuilds the
# migrated legacy/rules pages from their JSON (overwriting any edits made since).
param([switch]$RegeneratePages)
. (Join-Path $PSScriptRoot 'new-docs-page.ps1')
$legacy = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'legacy-pages.json')) | ConvertFrom-Json

# --- sidebar --------------------------------------------------------------
$sections = @(
    @('Getting Started', @(
        @('docs', 'Overview'), @('welcome', 'Introduction'), @('what-is-otter', 'What is Otter?'), @('who-is-otter-for', 'Who is Otter for?'),
        @('what-can-you-build', 'What can you build?'), @('installation', 'Installation'), @('verify', 'Verify your installation'),
        @('first-program', 'Your first program'), @('hello', 'Hello, Otter!'), @('repl', 'The REPL'), @('running-files', 'Running .ot files'),
        @('tiny-app', 'Build a tiny application'))),
    @('Tools', @(@('cli', 'The otter command'), @('projects', 'Projects'), @('troubleshooting', 'Troubleshooting'))),
    @('Language Guide', @(
        @('values', 'Values and variables'), @('input-output', 'Input and output'), @('conditions', 'Conditions'),
        @('loops', 'Loops'), @('lists', 'Lists'), @('functions', 'Functions'), @('objects', 'Objects and properties'),
        @('files', 'Files and folders'), @('data', 'CSV and downloads'), @('error-handling', 'Error handling'),
        @('math', 'Math'), @('nested-conditions', 'Nested conditions'), @('modules', 'Modules'), @('running-programs', 'Running programs'), @('logging-debugging', 'Logging and debugging'), @('environment', 'Arguments and environment'))),
    @('Language Reference', @(
        @('gone', 'gone'), @('operators', 'Operators'), @('property-access', 'Property access'), @('strings', 'Text'),
        @('collections', 'Collections'), @('discovery', 'Finding files and folders'), @('file-objects', 'File and folder objects'), @('files-folders', 'Files'), @('folders', 'Folders'), @('try', 'try and otherwise'),
        @('json', 'JSON'), @('random', 'Random'), @('dates', 'Dates and time'), @('scope', 'Scope'),
        @('diagnostics', 'Diagnostic output'), @('reference', 'Reference index'))),
    @('Platform', @(
        @('databases', 'Databases'), @('queries', 'The query language'), @('http', 'HTTP requests'), @('web-server', 'Web servers'), @('xml', 'XML'),
        @('web-apps', 'Web applications'), @('reactivity', 'State and reactivity'), @('windows-apps', 'Windows applications'),
        @('networking', 'Networking'), @('security', 'Cryptography and secrets'))),
    @('Examples', @(
        @('examples', 'All examples'), @('example-hello', 'Hello World'), @('example-input', 'User input'),
        @('example-conditions', 'Conditions'), @('example-counting', 'Counting'), @('example-lists', 'Lists'),
        @('example-discovery', 'File discovery'), @('example-organizer', 'File organizer'),
        @('example-finding', 'Finding files'), @('example-errors', 'Handling errors'))),
    @('Language Design', @(
        @('design-readable', 'Readable like English'), @('structural-words', 'Structural words'),
        @('properties-operations', 'Properties vs operations'), @('periods', 'Period and block rules'),
        @('philosophy', 'Philosophy'))),
    @('More', @(@('topics', 'All topics'), @('download', 'Download'), @('release', 'Release status'), @('studio', 'Studio preview'), @('support', 'Support'), @('about', 'About Otter'), @('license', 'License')))
)

function Get-SideName([string]$slug) {
    return 'side' + (($slug -split '-' | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join '')
}
function Q([string]$t) { '"' + $t.Replace('\', '\').Replace('"', '\"') + '"' }

$linkStyle = 'padding: 8px 12px; border-left: 3px solid transparent; border-radius: 4px; display: block;'
$out = [System.Collections.Generic.List[string]]::new()
$out.Add('# _docs.ot - the documentation sidebar, shared by every docs page.')
$out.Add('# Generated once by scripts/build-docs-content.ps1; edit here directly afterwards.')
$out.Add('# A docs page marks itself as current by assigning that link''s customstyle.')
$out.Add('')
$groupNames = @()
$g = 0
foreach ($section in $sections) {
    $g++
    $headName = "sideGroupHead$g"
    $firstSlug = $section[1][0][0]
    $firstUrl = "/$firstSlug/"
    $out.Add("$headName is a link with text $(Q $section[0]), url $(Q $firstUrl), foreground ""#0f1f36"", size 13, weight 700, customstyle ""padding: 6px 12px; display: block;""")
    $members = @($headName)
    foreach ($entry in $section[1]) {
        $name = Get-SideName $entry[0]
        $url = "/$($entry[0])/"
        $out.Add("$name is a link with text $(Q $entry[1]), url $(Q $url), foreground ""#4a5b75"", size 14, customstyle $(Q $linkStyle)")
        $members += $name
    }
    $groupName = "sideGroup$g"
    $out.Add("$groupName is a column with spacing 2")
    $out.Add("put $($members -join ', ') in $groupName")
    $out.Add('')
    $groupNames += $groupName
}
$out.Add('helpTitle is a text with value "Need help?", size 14, weight 700, foreground "#0f1f36"')
$out.Add('helpBody is a text with value "Ask a question or report a problem on GitHub.", size 13, foreground "#4a5b75", lineheight "1.45"')
$out.Add('helpLink is a link with text "Open an issue", url "https://github.com/Heavens-Lava/otterPS/issues", foreground "#2563eb", size 13, weight 600')
$out.Add('helpCard is a column with spacing 8, background "#f4f7fb", border "1px solid #e3e9f2", radius 12, padding 16')
$out.Add('put helpTitle, helpBody, helpLink in helpCard')
$out.Add('')
$out.Add('docsSidebar is a column with spacing 22, background "#ffffff", padding "24px 12px 24px 20px", customstyle "box-sizing: border-box; width: 248px; flex: 0 0 248px; border-right: 1px solid #e3e9f2; position: sticky; top: 64px; align-self: flex-start; height: calc(100vh - 64px); overflow-y: auto;"')
$out.Add("put $(($groupNames + 'helpCard') -join ', ') in docsSidebar")
$sidebarPath = Join-Path $PSScriptRoot '..\pages\_docs.ot'
[System.IO.File]::WriteAllText($sidebarPath, (($out -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $sidebarPath"

# --- legacy pages ---------------------------------------------------------
foreach ($prop in $(if ($RegeneratePages) { $legacy.pages.PSObject.Properties } else { @() })) {
    $slug = $prop.Name
    $page = $prop.Value
    $items = [System.Collections.Generic.List[object]]::new()
    $items.Add((Item h1 $page.title))
    $hasLead = $false
    foreach ($i in $page.items) {
        if ($i.k -eq 'lead') { $hasLead = $true }
        $items.Add((Item $i.k $i.t $(if ($i.u) { $i.u } else { '' })))
    }
    if (-not $hasLead) { $items.Insert(1, (Item lead "$($page.title) - a complete Otter example you can run and change.")) }
    if ($slug -like 'example-*') { $items.Add((Item link 'All examples' '/examples/')) }
    New-OtterDocsPage -Slug $slug -Title $page.title -Side (Get-SideName $slug) -Items $items
}

# --- language-rules pages (scripts/import-rules.mjs -> rules-pages.json) ---
$rulesPath = Join-Path $PSScriptRoot 'rules-pages.json'
if ($RegeneratePages -and (Test-Path -LiteralPath $rulesPath)) {
    $rules = [System.IO.File]::ReadAllText($rulesPath) | ConvertFrom-Json
    foreach ($prop in $rules.PSObject.Properties) {
        $slug = $prop.Name
        $page = $prop.Value
        $items = [System.Collections.Generic.List[object]]::new()
        $items.Add((Item h1 $page.title))
        $items.Add((Item lead $page.lead))
        foreach ($i in $page.items) { $items.Add((Item $i.k $i.t '')) }
        New-OtterDocsPage -Slug $slug -Title $page.title -Side (Get-SideName $slug) -Items $items
    }
}

# --- all topics: one page listing every page, by section ------------------
$topicItems = [System.Collections.Generic.List[object]]::new()
$topicItems.Add((Item h1 'All topics'))
$topicItems.Add((Item lead 'Every page in the documentation, grouped by section.'))
foreach ($section in $sections) {
    if ($section[0] -eq 'More') { continue }
    $topicItems.Add((Item h2 $section[0]))
    foreach ($entry in $section[1]) {
        $url = "/$($entry[0])/"
        $topicItems.Add((Item link $entry[1] $url))
    }
}
New-OtterDocsPage -Slug 'topics' -Title 'All topics' -Side 'sideTopics' -Items $topicItems

# --- live code samples ------------------------------------------------------
# Every code block gets `runnable true`. The web compiler decides at build time
# whether it can actually run in a browser: samples that need files, sockets or
# a shell get no Run button (see Get-OtterRunnableJs in Otter.Web.psm1).
foreach ($page in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\pages') -Filter '*.ot' | Where-Object { -not $_.Name.StartsWith('_') }) {
    $lines = [System.IO.File]::ReadAllLines($page.FullName)
    $changed = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\w+ is a text with value ".*background "#0f1b2e"' -and $lines[$i] -notmatch 'runnable (true|false)') {
            $lines[$i] = $lines[$i] + ', runnable true'
            $changed = $true
        }
    }
    if ($changed) { [System.IO.File]::WriteAllText($page.FullName, (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false))) }
}
# --- collapse the sidebar groups a page is not in ------------------------
# Only the current page's group is expanded, so the highlighted link is
# always in view without any script. Idempotent: the block is marked.
$marker = '# Sidebar: only the current group is expanded.'
foreach ($page in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\pages') -Filter '*.ot' | Where-Object { -not $_.Name.StartsWith('_') }) {
    $text = [System.IO.File]::ReadAllText($page.FullName)
    if (-not $text.Contains('use "_docs.ot"')) { continue }
    $lines = [System.Collections.Generic.List[string]]($text -split "`n")
    # drop any earlier collapse block (marker line + its hide lines)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -eq $marker) {
            $lines.RemoveAt($i)
            while ($i -lt $lines.Count -and $lines[$i] -like 'customstyle of side* is "display: none;"') { $lines.RemoveAt($i) }
        }
    }
    $activeIndex = -1
    $activeName = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^customstyle of (side\w+) is "padding: 8px 12px; border-left: 3px solid #2563eb') { $activeIndex = $i; $activeName = $Matches[1]; break }
    }
    if ($activeIndex -lt 0) { continue }
    $hide = [System.Collections.Generic.List[string]]::new()
    foreach ($section in $sections) {
        $names = @($section[1] | ForEach-Object { Get-SideName $_[0] })
        if ($names -contains $activeName) { continue }
        foreach ($n in $names) { $hide.Add("customstyle of $n is ""display: none;""") }
    }
    $block = @($marker) + $hide
    $lines.InsertRange($activeIndex + 1, [string[]]$block)
    [System.IO.File]::WriteAllText($page.FullName, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
}
Write-Host 'Collapsed non-current sidebar groups on every docs page.'