# check-otter-page-examples.ps1 - parse-checks every Otter code block on the
# Otter-authored pages with the real parser (otter check). A block that starts
# like a shell command or a REPL transcript is skipped; everything else is
# Otter source and must parse. Nothing is executed.
#
# The blocks are found by their code-block styling (background #0f1b2e), so it
# checks exactly what a reader sees as a code sample.
param([string[]]$Only = @())
$Only = @($Only | ForEach-Object { $_ -split "," } | Where-Object { $_ })   # -File passes "a,b" as one string

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$otter = Join-Path $repoRoot 'otter.ps1'
$skipStarts = '^(otter\b|otter>|git\b|cd\b|pwsh\b|\./|\.\\|Set-ExecutionPolicy|&|PS |use "|\[Environment\]|\{|-[A-Za-z]|is\s{2,})'   # use "x.ot" needs the other file
$blockPattern = '^\w+ is a text with value "((?:[^"\\]|\\.)*)".*background "#0f1b2e"'
$failed = 0
$checked = 0
$pages = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\pages') -Filter '*.ot' |
    Where-Object { -not $_.Name.StartsWith('_') -and ($Only.Count -eq 0 -or $Only -contains [System.IO.Path]::GetFileNameWithoutExtension($_.Name)) }
foreach ($page in $pages) {
    foreach ($line in [System.IO.File]::ReadAllLines($page.FullName)) {
        $match = [regex]::Match($line, $blockPattern)
        if (-not $match.Success) { continue }
        # Undo the Otter string escaping left to right (\n newline, \" quote, \\ backslash).
        $code = [regex]::Replace($match.Groups[1].Value, '\\(.)', {
            param($m)
            if ($m.Groups[1].Value -eq 'n') { "`n" } else { $m.Groups[1].Value }
        })
        if ([regex]::IsMatch($code, $skipStarts) -or $line.Contains('foreground "#a5e3b5"')) { continue }   # shell commands and program output
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("otter-doc-check-$([guid]::NewGuid().ToString('N')).ot")
        [System.IO.File]::WriteAllText($tmp, $code + "`n", (New-Object System.Text.UTF8Encoding($false)))
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $otter check $tmp 2>&1 | Out-String
        $ok = ($LASTEXITCODE -eq 0)
        Remove-Item -LiteralPath $tmp -Force
        $checked++
        if (-not $ok) {
            $failed++
            Write-Host "FAIL $($page.Name):" -ForegroundColor Red
            Write-Host $code
            Write-Host $output
        }
    }
}
Write-Host "Checked $checked Otter code blocks; $failed failed."
if ($failed -gt 0) { exit 1 }
