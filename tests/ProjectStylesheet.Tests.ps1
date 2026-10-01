using module ..\Otter.Contract.psm1
. "$PSScriptRoot\TestHost.ps1"

# Project stylesheet resolution for every web-producing command - D125 (the
# release line's rule, adopted on this line 2026-09-30): `otter web`,
# `otter build` (and `otter desktop`) share one code path,
# Export-OtterWebApplication, and a program <entry>.ot uses <entry>.css from
# the same folder and nothing else (no styles.css). The stylesheet must
# resolve, following links, inside the entry's folder.
# These tests drive the real CLI, not the module functions.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$otterPs1 = Join-Path $repoRoot 'otter.ps1'

Write-Output 'Project stylesheet resolution (otter web / otter build)'

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_stylesheet_tests_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

$program = @'
app is a window with title "Styled"
go is a button with text "Go"
put go in app
show app
'@

function New-Case {
    param([string]$Name, [hashtable]$Files)
    $dir = Join-Path $testTmp $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($relative in $Files.Keys) {
        $path = Join-Path $dir $relative
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [System.IO.File]::WriteAllText($path, $Files[$relative], (New-Object System.Text.UTF8Encoding($false)))
    }
    return $dir
}

function Invoke-OtterWeb {
    param([string]$EntryPath)
    $out = & $script:OtterHostExe @script:OtterHostArgs -File $otterPs1 web $EntryPath -NoOpen 2>&1
    if ($LASTEXITCODE -ne 0) { throw "otter web $EntryPath exited with $LASTEXITCODE. Output: $out" }
    $html = [System.IO.Path]::ChangeExtension($EntryPath, '.html')
    return [System.IO.File]::ReadAllText($html)
}

function Invoke-OtterBuild {
    param([string]$ProjectDir)
    $out = & $script:OtterHostExe @script:OtterHostArgs -File $otterPs1 build $ProjectDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "otter build $ProjectDir exited with $LASTEXITCODE. Output: $out" }
    return [System.IO.File]::ReadAllText((Join-Path $ProjectDir 'dist/index.html'))
}

function Get-Count {
    param([string]$Text, [string]$Needle)
    return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
}

function New-Manifest {
    param([string]$Entry)
    return "{`n  `"name`": `"styled`",`n  `"version`": `"1.0.0`",`n  `"archetype`": `"web`",`n  `"target`": `"web`",`n  `"entryPoint`": `"$Entry`"`n}`n"
}

$mainCss = "/* MAIN_CSS_MARKER */`n#go { color: red; }`n"
$stylesCss = "/* STYLES_CSS_MARKER */`n#go { color: blue; }`n"

try {
    # 1. main.css exists -> it is included, exactly once.
    $dir = New-Case 'named' @{ 'main.ot' = $program; 'main.css' = $mainCss }
    $html = Invoke-OtterWeb (Join-Path $dir 'main.ot')
    if ((Get-Count $html 'MAIN_CSS_MARKER') -ne 1) { throw 'Test 1: main.css should appear exactly once.' }
    if ((Get-Count $html 'otter-sidecar-style') -ne 1) { throw 'Test 1: expected exactly one project stylesheet block.' }
    Write-Output '  pass  main.css beside main.ot is included exactly once'

    # 2. Only styles.css exists -> it is not used (D125: no styles.css).
    $dir = New-Case 'studio' @{ 'main.ot' = $program; 'styles.css' = $stylesCss }
    $html = Invoke-OtterWeb (Join-Path $dir 'main.ot')
    if ((Get-Count $html 'STYLES_CSS_MARKER') -ne 0) { throw 'Test 2: styles.css must not be used (D125).' }
    Write-Output '  pass  styles.css is not a stylesheet any more (D125)'

    # 3. Both exist -> only main.css.
    $dir = New-Case 'both' @{ 'main.ot' = $program; 'main.css' = $mainCss; 'styles.css' = $stylesCss }
    $html = Invoke-OtterWeb (Join-Path $dir 'main.ot')
    if ((Get-Count $html 'MAIN_CSS_MARKER') -ne 1) { throw 'Test 3: main.css should appear exactly once.' }
    if ((Get-Count $html 'STYLES_CSS_MARKER') -ne 0) { throw 'Test 3: styles.css must not be added.' }
    Write-Output '  pass  with both, only main.css is used'

    # 4. Neither exists -> the program still compiles, with no stylesheet block.
    $dir = New-Case 'none' @{ 'main.ot' = $program }
    $html = Invoke-OtterWeb (Join-Path $dir 'main.ot')
    if ($html -notmatch 'id="go"') { throw 'Test 4: expected the compiled button.' }
    if ((Get-Count $html 'otter-sidecar-style') -ne 0) { throw 'Test 4: no stylesheet should be embedded.' }
    Write-Output '  pass  no stylesheet: compiles normally without one'

    # 5. Responsive rules and interaction states survive compilation verbatim,
    # and `$` sequences in the CSS are not treated as regex substitutions.
    $richCss = @'
#go {
    background: #2563eb !important;
}

#go:hover {
    background: #16a34a !important;
}

#go:active {
    transform: scale(0.97);
}

#go:focus {
    outline: 3px solid #93c5fd;
}

@media (max-width: 900px) {
    #go {
        width: 100%;
    }
}

@media (max-width: 600px) {
    #go {
        font-size: 14px;
    }
}

#go::after {
    content: "$1 $& $$";
}
'@
    $dir = New-Case 'rich' @{ 'main.ot' = $program; 'main.css' = $richCss }
    $html = Invoke-OtterWeb (Join-Path $dir 'main.ot')
    foreach ($needle in @('#go:hover {', '#go:active {', '#go:focus {', '@media (max-width: 900px) {', '@media (max-width: 600px) {', 'font-size: 14px;', 'content: "$1 $& $$";')) {
        if ((Get-Count $html $needle) -ne 1) { throw "Test 5: expected '$needle' exactly once in the compiled output." }
    }
    Write-Output '  pass  @media rules and :hover / :active / :focus states survive compilation'
    Write-Output '  pass  CSS is inserted verbatim ($ sequences are not rewritten)'

    # 6. otter build uses the same rule: main.css beside main.ot.
    $dir = New-Case 'build-root' @{ 'main.ot' = $program; 'main.css' = $mainCss; 'styles.css' = $stylesCss; 'otter.json' = (New-Manifest 'main.ot') }
    $html = Invoke-OtterBuild $dir
    if ((Get-Count $html 'MAIN_CSS_MARKER') -ne 1 -or (Get-Count $html 'STYLES_CSS_MARKER') -ne 0) { throw 'Test 6: otter build should embed main.css only.' }
    Write-Output '  pass  otter build embeds main.css, like otter web'

    # 7. An entry in src/ uses src/main.css; a stylesheet at the project root is not used.
    $dir = New-Case 'build-src' @{ 'src/main.ot' = $program; 'src/main.css' = $mainCss; 'main.css' = $stylesCss; 'otter.json' = (New-Manifest 'src/main.ot') }
    $html = Invoke-OtterBuild $dir
    if ((Get-Count $html 'MAIN_CSS_MARKER') -ne 1 -or (Get-Count $html 'STYLES_CSS_MARKER') -ne 0) { throw 'Test 7: src/main.ot should use src/main.css only.' }
    Write-Output '  pass  an entry in src/ uses the stylesheet beside it'

    # 8. A main.css that is a link to a file outside the entry's folder is
    # refused, and nothing is written (RC3 B4 on the release line).
    $dir = New-Case 'link' @{ 'main.ot' = $program }
    $secret = Join-Path $testTmp 'secret.txt'
    [System.IO.File]::WriteAllText($secret, 'SECRET_MARKER')
    $linked = $true
    try { New-Item -ItemType SymbolicLink -Path (Join-Path $dir 'main.css') -Target $secret -ErrorAction Stop | Out-Null } catch { $linked = $false }
    if ($linked) {
        $out = & $script:OtterHostExe @script:OtterHostArgs -File $otterPs1 web (Join-Path $dir 'main.ot') -NoOpen 2>&1
        if ($LASTEXITCODE -eq 0) { throw 'Test 8: a stylesheet linked from outside the folder must fail the build.' }
        if (($out -join "`n") -notmatch 'outside the folder') { throw "Test 8: unclear message: $out" }
        if (Test-Path -LiteralPath (Join-Path $dir 'main.html')) { throw 'Test 8: nothing should have been written.' }
        Write-Output '  pass  a stylesheet that links outside the entry folder is refused; nothing is written'
    } else {
        Write-Output '  skip  a stylesheet linked from outside the folder (this system cannot create file links without Developer Mode)'
    }

    # 10. No project manifest anywhere and no stylesheet beside the entry: nothing is embedded.
    $dir = New-Case 'loose/deeper' @{ 'main.ot' = $program }
    $html = Invoke-OtterWeb (Join-Path $dir 'main.ot')
    if ((Get-Count $html 'otter-sidecar-style') -ne 0) { throw 'Test 10: a loose file without a stylesheet embeds none.' }
    Write-Output '  pass  a loose program without a stylesheet embeds none'
}
finally {
    Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Project stylesheet tests passed.'
