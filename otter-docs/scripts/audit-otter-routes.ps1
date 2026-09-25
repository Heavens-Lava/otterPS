param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\generated')
)

$root = (Resolve-Path $OutputRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$checked = 0

foreach ($page in Get-ChildItem -LiteralPath $root -Recurse -Filter 'index.html') {
    $relativePage = $page.FullName.Substring($root.Length).Replace('\', '/')
    $baseUri = [Uri]("https://heavens-lava.github.io$relativePage")
    $html = Get-Content -LiteralPath $page.FullName -Raw

    foreach ($match in [regex]::Matches($html, 'href="([^"]+)"')) {
        $href = $match.Groups[1].Value
        if ($href -match '^(?i)https?://' -or $href.StartsWith('#')) { continue }

        $targetPath = ([Uri]::new($baseUri, $href)).AbsolutePath.Trim('/')
        # Static files (stylesheets, scripts, images) are copied alongside the
        # generated routes. Audit those exact files instead of assuming every
        # href is a directory URL.
        $target = if ($targetPath -match '\.[a-zA-Z0-9]{1,8}$') {
            Join-Path $root ($targetPath.Replace('/', '\'))
        }
        elseif ([string]::IsNullOrWhiteSpace($targetPath)) {
            Join-Path $root 'home\index.html'
        }
        else {
            Join-Path $root ($targetPath.Replace('/', '\') + '\index.html')
        }

        $checked++
        if (-not (Test-Path -LiteralPath $target)) {
            $failures.Add("$relativePage -> $href does not resolve to a generated route.")
        }
    }
}

if ($failures.Count -gt 0) {
    throw "Otter route audit failed:`n- $($failures -join "`n- ")"
}

Write-Host "Otter route audit passed: $checked internal links resolve across generated pages."
