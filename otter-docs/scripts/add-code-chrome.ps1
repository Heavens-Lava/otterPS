# add-code-chrome.ps1 - gives every code and output block on the Otter-authored
# pages a header bar with a label and a Copy button, as in the site design.
#
# The Copy button is ordinary Otter (`when bNcopy is clicked` / `copy text of bN
# to clipboard`), not site JavaScript. Idempotent: a block that already has a
# `<name>block` container is left alone. One-off migration; new pages should be
# scaffolded with these blocks by new-docs-page.ps1.
$pagesDir = Join-Path $PSScriptRoot '..\pages'
$shellStarts = '^(otter\b|otter>|git\b|cd\b|\.\\|Set-ExecutionPolicy|&|PS |use "|is\s{2,})'
$blockPattern = '^(\w+) is a text with value "((?:[^"\\]|\\.)*)"(.*)$'

foreach ($page in Get-ChildItem -LiteralPath $pagesDir -Filter '*.ot' | Where-Object { -not $_.Name.StartsWith('_') }) {
    $lines = [System.Collections.Generic.List[string]]([System.IO.File]::ReadAllLines($page.FullName))
    if (($lines -join "`n") -notmatch 'background "#0f1b2e"|background "#e8eef7"') { continue }
    $renamed = [System.Collections.Generic.List[string]]::new()
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $match = [regex]::Match($line, $blockPattern)
        $rest = $match.Groups[3].Value
        $isCode = $match.Success -and $rest.Contains('background "#0f1b2e"') -and $rest.Contains('whitespace "pre"')
        $isOut = $match.Success -and $rest.Contains('background "#e8eef7"') -and $rest.Contains('whitespace "pre"')
        if (-not ($isCode -or $isOut)) { $out.Add($line); continue }
        $name = $match.Groups[1].Value
        if ($lines -contains "put ${name}head, ${name}copy in ${name}block" -or ($lines -join "`n").Contains("${name}block is a column")) { $out.Add($line); continue }

        $sample = [regex]::Replace($match.Groups[2].Value, '\\(.)', { param($m) if ($m.Groups[1].Value -eq 'n') { "`n" } else { $m.Groups[1].Value } })
        $green = $rest.Contains('foreground "#a5e3b5"')
        if ($isOut -or $green) { $label = 'Output' }
        elseif ($name -match '^py\d+$') { $label = 'Python' }   # comparison samples (Coming from Python)
        elseif ([regex]::IsMatch($sample, $shellStarts)) { $label = 'PowerShell' }
        else { $label = 'Otter' }
        $headBg = if ($isCode) { '#16263f' } else { '#dde6f2' }
        $headFg = if ($isCode) { '#b7c4d8' } else { '#4a5b75' }
        $btnBg = if ($isCode) { '#22375a' } else { '#c9d6e8' }
        $btnFg = if ($isCode) { '#e5edf8' } else { '#0f1f36' }

        # the block itself loses its top corners; the header bar owns them
        $rest = $rest -replace 'customstyle "([^"]*)"', 'customstyle "$1 border-top-left-radius: 0; border-top-right-radius: 0;"'
        $out.Add("$name is a text with value ""$($match.Groups[2].Value)""$rest")
        $out.Add("${name}label is a text with value ""$label"", size 12, weight 600, foreground ""$headFg""")
        $out.Add("${name}copy is a button with text ""Copy"", size 12, weight 600, background ""$btnBg"", foreground ""$btnFg"", radius 6, padding ""4px 12px""")
        $out.Add("${name}head is a row with spread, align middle, width full, background ""$headBg"", padding ""8px 14px"", customstyle ""box-sizing: border-box; border-radius: 12px 12px 0 0;""")
        $out.Add("put ${name}label, ${name}copy in ${name}head")
        $out.Add("${name}block is a column with spacing 0, width full")
        $out.Add("put ${name}head, $name in ${name}block")
        $out.Add("when ${name}copy is clicked")
        $out.Add("    copy text of $name to clipboard")
        $out.Add("    text of ${name}copy is ""Copied""")
        $out.Add(".")
        $renamed.Add($name)
    }
    # the page's containers now hold the block instead of the bare code text
    for ($i = 0; $i -lt $out.Count; $i++) {
        if ($out[$i] -notmatch '^put .+ in \w+$') { continue }
        if ($out[$i] -match '^put (\w+)(head|label|copy), ') { continue }
        $split = [regex]::Match($out[$i], '^put (.+) in (\w+)$')
        $items = $split.Groups[1].Value -split ',\s*'
        $changed = $false
        for ($k = 0; $k -lt $items.Count; $k++) {
            if ($renamed.Contains($items[$k]) -and $split.Groups[2].Value -ne "$($items[$k])block") { $items[$k] = "$($items[$k])block"; $changed = $true }
        }
        if ($changed) { $out[$i] = "put $($items -join ', ') in $($split.Groups[2].Value)" }
    }
    if ($renamed.Count -gt 0) {
        [System.IO.File]::WriteAllText($page.FullName, (($out -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "$($page.Name): $($renamed.Count) blocks"
    }
}
