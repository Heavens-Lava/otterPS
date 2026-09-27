using module ..\Otter.Contract.psm1
. "$PSScriptRoot\TestHost.ps1"

# Project stylesheet resolution for every web-producing command.
# `otter web`, `otter build` (and `otter desktop`) share one code path,
# Export-OtterWebApplication, which picks the program's stylesheet:
#   1. main.ot -> main.css            (hand-written Otter)
#   2. styles.css beside the entry    (Otter Studio projects)
#   3. styles.css in the project root (entry kept in src/)
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

    # 2. Only styles.css exists -> it is included, exactly once.
    $dir = New-Case 'studio' @{ 'main.ot' = $program; 'styles.css' = $stylesCss }
    $html = Invoke-OtterWeb (Join-Path $dir 'main.ot')
    if ((Get-Count $html 'STYLES_CSS_MARKER') -ne 1) { throw 'Test 2: styles.css should appear exactly once.' }
    if ((Get-Count $html 'otter-sidecar-style') -ne 1) { throw 'Test 2: expected exactly one project stylesheet block.' }
    Write-Output '  pass  styles.css (Otter Studio project stylesheet) is included exactly once'

    # 3. Both exist -> main.css wins and styles.css is not added.
    $dir = New-Case 'both' @{ 'main.ot' = $program; 'main.css' = $mainCss; 'styles.css' = $stylesCss }
    $html = Invoke-OtterWeb (Join-Path $dir 'main.ot')
    if ((Get-Count $html 'MAIN_CSS_MARKER') -ne 1) { throw 'Test 3: main.css should be used.' }
    if ((Get-Count $html 'STYLES_CSS_MARKER') -ne 0) { throw 'Test 3: styles.css must not be added when main.css exists.' }
    Write-Output '  pass  main.css wins over styles.css'

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
    $dir = New-Case 'rich' @{ 'main.ot' = $program; 'styles.css' = $richCss }
    $html = Invoke-OtterWeb (Join-Path $dir 'main.ot')
    foreach ($needle in @('#go:hover {', '#go:active {', '#go:focus {', '@media (max-width: 900px) {', '@media (max-width: 600px) {', 'font-size: 14px;', 'content: "$1 $& $$";')) {
        if ((Get-Count $html $needle) -ne 1) { throw "Test 5: expected '$needle' exactly once in the compiled output." }
    }
    Write-Output '  pass  @media rules and :hover / :active / :focus states survive compilation'
    Write-Output '  pass  CSS is inserted verbatim ($ sequences are not rewritten)'

    # 6. otter build uses the same resolution: Studio layout (entry + styles.css at the root).
    $dir = New-Case 'build-root' @{ 'main.ot' = $program; 'styles.css' = $stylesCss; 'otter.json' = (New-Manifest 'main.ot') }
    $html = Invoke-OtterBuild $dir
    if ((Get-Count $html 'STYLES_CSS_MARKER') -ne 1) { throw 'Test 6: otter build should embed styles.css exactly once.' }
    Write-Output '  pass  otter build embeds the project styles.css'

    # 7. otter build with the entry in src/ finds styles.css at the project root.
    $dir = New-Case 'build-src' @{ 'src/main.ot' = $program; 'styles.css' = $stylesCss; 'otter.json' = (New-Manifest 'src/main.ot') }
    $html = Invoke-OtterBuild $dir
    if ((Get-Count $html 'STYLES_CSS_MARKER') -ne 1) { throw 'Test 7: styles.css at the project root should be embedded for src/main.ot.' }
    Write-Output '  pass  entry in src/ uses styles.css from the project root'

    # 8. otter build with main.css beside the entry: named stylesheet still wins.
    $dir = New-Case 'build-both' @{ 'main.ot' = $program; 'main.css' = $mainCss; 'styles.css' = $stylesCss; 'otter.json' = (New-Manifest 'main.ot') }
    $html = Invoke-OtterBuild $dir
    if ((Get-Count $html 'MAIN_CSS_MARKER') -ne 1 -or (Get-Count $html 'STYLES_CSS_MARKER') -ne 0) { throw 'Test 8: otter build should prefer main.css.' }
    Write-Output '  pass  otter build prefers main.css, like otter web'

    # 9. The search stays inside the project: a styles.css above the project root is ignored.
    $dir = New-Case 'outer' @{ 'styles.css' = $stylesCss; 'app/otter.json' = (New-Manifest 'src/main.ot'); 'app/src/main.ot' = $program }
    $html = Invoke-OtterWeb (Join-Path $dir 'app/src/main.ot')
    if ((Get-Count $html 'STYLES_CSS_MARKER') -ne 0) { throw 'Test 9: a styles.css outside the project must not be used.' }
    Write-Output '  pass  a styles.css outside the project is never picked up'

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
