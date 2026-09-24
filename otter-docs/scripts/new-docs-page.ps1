# new-docs-page.ps1 - scaffolding for the Otter-authored documentation pages.
#
# A docs page is dozens of near-identical Otter resource declarations (a text
# resource per heading, paragraph and code block). This turns a short content
# list into that Otter source. The OUTPUT (pages/<slug>.ot) is the source of
# truth and is committed; nothing here runs at site-build time. Use it to
# scaffold a new page, then edit the .ot directly.
#
#   . .\scripts\new-docs-page.ps1
#   New-OtterDocsPage -Slug 'loops' -Title 'Loops' -Side 'sideLoops' -Items @(
#       (Item h1 'Loops'), (Item p 'Text.'), (Item code 'say "hi"'))

function Item {
    param([string]$Kind, [string]$Text, [string]$Url = '')
    return , @($Kind, $Text, $Url)
}

function ConvertTo-OtterString {
    param([string]$Text)
    $escaped = $Text.Replace('\', '\\').Replace('"', '\"') -replace "`r?`n", '\n'
    return '"' + $escaped + '"'
}

function New-OtterDocsPage {
    param(
        [Parameter(Mandatory)][string]$Slug,
        [Parameter(Mandatory)][string]$Title,
        [string]$Side = '',
        [Parameter(Mandatory)]$Items,
        [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\pages')
    )

    $mono = 'fontfamily "''JetBrains Mono'', Consolas, monospace", whitespace "pre"'
    $names = [System.Collections.Generic.List[string]]::new()
    $lines = [System.Collections.Generic.List[string]]::new()
    $index = 0
    foreach ($item in $Items) {
        $index++
        $name = "b$index"
        $names.Add($name)
        $text = ConvertTo-OtterString $item[1]
        switch ($item[0]) {
            'h1'   { $lines.Add("$name is a text with value $text, size 40, weight 800, foreground ""#0b1d36"", letterspacing ""-0.03em"", lineheight ""1.1""") }
            'lead' { $lines.Add("$name is a text with value $text, size 18, foreground ""#3a4d6b"", lineheight ""1.55""") }
            'h2'   { $lines.Add("$name is a text with value $text, size 26, weight 800, foreground ""#0b1d36"", letterspacing ""-0.02em"", margin ""14px 0 0 0""") }
            'p'    { $lines.Add("$name is a text with value $text, size 16, foreground ""#3a4d6b"", lineheight ""1.6""") }
            'code' { $lines.Add("$name is a text with value $text, size 14, foreground ""#e5edf8"", background ""#0f1b2e"", radius 12, $mono, customstyle ""padding: 18px 22px; line-height: 1.7; overflow-x: auto;"", runnable true") }
            'out'  { $lines.Add("$name is a text with value $text, size 14, foreground ""#0f1f36"", background ""#e8eef7"", radius 12, $mono, customstyle ""padding: 16px 22px; line-height: 1.7; overflow-x: auto;""") }
            'note' { $lines.Add("$name is a text with value $text, size 15, foreground ""#1e3a6b"", background ""#eaf2ff"", radius 12, border ""1px solid #cfe0ff"", lineheight ""1.55"", customstyle ""padding: 14px 18px;""") }
            'link' { $lines.Add("$name is a link with text $text, url $(ConvertTo-OtterString $item[2]), foreground ""#2563eb"", weight 600, size 15") }
            default { throw "Unknown item kind '$($item[0])'." }
        }
    }

    $activeStyle = 'padding: 8px 12px; border-left: 3px solid #2563eb; border-radius: 4px; display: block; background: #e6efff; color: #1d4ed8; font-weight: 600;'
    $sideLine = if ($Side) { "customstyle of $Side is $(ConvertTo-OtterString $activeStyle)`n" } else { '' }
    $pageTitle = ConvertTo-OtterString "$Title - Otter Documentation"

    $source = @"
# Otter website - $Title
# Authored in Otter. Scaffolded by scripts/new-docs-page.ps1, now edited here directly.

use "_shell.ot"
use "_docs.ot"

app is a page with title $pageTitle, hideheader true, scroll true, width full, background "#f4f7fb", foreground "#0f1f36", spacing 0, padding 0

customstyle of navDocs is "padding: 22px 0; border-bottom: 2px solid #4d8dff; color: #ffffff;"
$sideLine
$($lines -join "`n")

docsMain is a column with spacing 16, flex 1, padding "40px 56px 24px", customstyle "box-sizing: border-box; min-width: 0; max-width: 940px;"
put $($names -join ', ') in docsMain
docsBody is a row with align top, spacing 0, width full, customstyle "align-items: stretch;"
put docsSidebar, docsMain in docsBody

put topBar, docsBody, siteFooter in app
show app
"@
    $path = Join-Path $OutputDirectory "$Slug.ot"
    [System.IO.File]::WriteAllText($path, ($source -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Wrote $path"
}
