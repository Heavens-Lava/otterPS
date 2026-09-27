using module ..\Otter.Contract.psm1
. "$PSScriptRoot\TestHost.ps1"

# Electron desktop target.
#
#   Otter source -> web compiler -> app/index.html -> Electron shell
#
# The first tests drive the real CLI (`otter build --target electron`,
# `otter desktop --electron`) and inspect what it writes: the compiled page
# with its project stylesheet, the shell files, and the security settings the
# shell must keep. The last test launches the exported application in a real
# Electron when one can be found, and checks the whole chain: compiled page ->
# window.otterNative (preload) -> IPC -> Node, through the program's own
# window.otter* functions. Without an Electron runtime that test is skipped
# and says so; set OTTER_ELECTRON_PATH to point at one.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$otterPs1 = Join-Path $repoRoot 'otter.ps1'

Write-Output 'Electron desktop target (otter build --target electron / otter desktop --electron)'

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_electron_tests_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

$program = @'
app is a window with title "Electron Smoke"
greeting is a text with text "Hello from Otter"
go is a button with text "Go"
put greeting, go in app
show app
'@
$stylesCss = "/* STYLES_CSS_MARKER */`n#go { color: blue; }`n#go:hover { color: green; }`n@media (max-width: 600px) { #greeting { font-size: 14px; } }`n"

function New-Files {
    param([string]$Dir, [hashtable]$Files)
    foreach ($relative in $Files.Keys) {
        $path = Join-Path $Dir $relative
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [System.IO.File]::WriteAllText($path, $Files[$relative], (New-Object System.Text.UTF8Encoding($false)))
    }
}

function Invoke-Otter {
    param([string[]]$CliArgs)
    $out = & $script:OtterHostExe @script:OtterHostArgs -File $otterPs1 @CliArgs 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = ($out -join "`n") }
}

function Get-Count {
    param([string]$Text, [string]$Needle)
    return ([regex]::Matches($Text, [regex]::Escape($Needle))).Count
}

function Assert-ShellFiles {
    param([string]$Dir, [string]$Label)
    foreach ($file in @('package.json', 'main.js', 'preload.js', 'app/index.html')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dir $file) -PathType Leaf)) { throw "${Label}: missing $file" }
    }
    $mainJs = Get-Content -LiteralPath (Join-Path $Dir 'main.js') -Raw
    $preloadJs = Get-Content -LiteralPath (Join-Path $Dir 'preload.js') -Raw
    $indexHtml = Get-Content -LiteralPath (Join-Path $Dir 'app/index.html') -Raw
    $pkg = Get-Content -LiteralPath (Join-Path $Dir 'package.json') -Raw | ConvertFrom-Json

    # Security settings the shell must keep.
    if ($mainJs -notmatch 'contextIsolation:\s*true') { throw "${Label}: main.js must enable contextIsolation" }
    if ($mainJs -notmatch 'nodeIntegration:\s*false') { throw "${Label}: main.js must disable nodeIntegration" }
    if ($mainJs -notmatch 'sandbox:\s*true') { throw "${Label}: main.js must enable the renderer sandbox" }
    if ($mainJs -notmatch "setWindowOpenHandler") { throw "${Label}: main.js must control window.open" }
    if ($preloadJs -notmatch "contextBridge\.exposeInMainWorld\('otterNative'") { throw "${Label}: preload must expose window.otterNative through contextBridge" }
    if ($preloadJs -match "exposeInMainWorld\('(ipcRenderer|require|process|electron)'" -or $preloadJs -match 'ipcRenderer\s*:\s*ipcRenderer') {
        throw "${Label}: preload must not hand ipcRenderer or Node objects to the page"
    }
    # The page is a plain web page: no Node in the renderer.
    if ($indexHtml -match '\brequire\s*\(') { throw "${Label}: the compiled page must not use require()" }
    if ($indexHtml -notmatch 'otterNativeMethod') { throw "${Label}: the compiled page must carry the window.otterNative hook" }
    # Package manifest.
    if ($pkg.main -ne 'main.js') { throw "${Label}: package.json main must be main.js" }
    if (-not $pkg.devDependencies.electron) { throw "${Label}: package.json must declare electron" }
    if ($pkg.name -notmatch '^[a-z0-9][a-z0-9._-]*$') { throw "${Label}: package name '$($pkg.name)' is not a valid npm name" }
    return @{ MainJs = $mainJs; PreloadJs = $preloadJs; IndexHtml = $indexHtml; Package = $pkg }
}

# Any Electron binary will do for the launch test; Otter never downloads one.
function Find-Electron {
    if ($env:OTTER_ELECTRON_PATH -and (Test-Path -LiteralPath $env:OTTER_ELECTRON_PATH)) { return $env:OTTER_ELECTRON_PATH }
    $onPath = Get-Command electron -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $candidates = @('node_modules\electron\dist\electron.exe', 'node_modules/electron/dist/electron', 'node_modules/electron/dist/Electron.app/Contents/MacOS/Electron')
    $parents = @($repoRoot, (Split-Path -Parent $repoRoot))
    foreach ($parent in $parents) {
        foreach ($dir in (Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
            foreach ($candidate in $candidates) {
                $full = Join-Path $dir.FullName $candidate
                if (Test-Path -LiteralPath $full -PathType Leaf) { return $full }
            }
        }
    }
    return $null
}

try {
    # 1. otter build --target electron on a Studio-style project with styles.css and an asset.
    $projDir = Join-Path $testTmp 'proj'
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null
    New-Files $projDir @{
        'main.ot' = $program
        'styles.css' = $stylesCss
        'assets/logo.txt' = 'asset payload'
        'otter.json' = "{`n  `"name`": `"Smoke App`",`n  `"version`": `"2.3.4`",`n  `"archetype`": `"desktop`",`n  `"target`": `"desktop`",`n  `"entryPoint`": `"main.ot`",`n  `"assets`": [`"assets/logo.txt`"]`n}`n"
    }
    $build = Invoke-Otter @('build', $projDir, '--target', 'electron')
    if ($build.ExitCode -ne 0) { throw "Test 1: otter build --target electron exited with $($build.ExitCode). Output: $($build.Output)" }
    if ($build.Output -notmatch 'Target: electron') { throw "Test 1: build should report the electron target. Output: $($build.Output)" }
    $dist = Join-Path $projDir 'dist'
    $files = Assert-ShellFiles -Dir $dist -Label 'Test 1'
    if ((Get-Count $files.IndexHtml 'STYLES_CSS_MARKER') -ne 1) { throw 'Test 1: styles.css must be embedded exactly once in app/index.html' }
    if ((Get-Count $files.IndexHtml '#go:hover {') -ne 1 -or (Get-Count $files.IndexHtml '@media (max-width: 600px)') -ne 1) { throw 'Test 1: states and breakpoints must survive' }
    if (-not (Test-Path -LiteralPath (Join-Path $dist 'app/assets/logo.txt') -PathType Leaf)) { throw 'Test 1: declared assets must land beside the page in app/' }
    if ($files.Package.name -ne 'smoke-app' -or $files.Package.productName -ne 'Smoke App' -or $files.Package.version -ne '2.3.4') { throw "Test 1: package.json should carry the project name and version, got $($files.Package.name) $($files.Package.version)" }
    $meta = Get-Content -LiteralPath (Join-Path $dist 'otter.build.json') -Raw | ConvertFrom-Json
    if ($meta.target -ne 'electron' -or $meta.entryPoint -ne 'app/index.html') { throw "Test 1: build metadata should record the electron target, got $($meta.target) $($meta.entryPoint)" }
    Write-Output '  pass  otter build --target electron writes package.json, main.js, preload.js and app/index.html'
    Write-Output '  pass  the exported page embeds styles.css once, with @media and :hover intact'
    Write-Output '  pass  declared assets are copied into app/ and package.json carries name and version'
    Write-Output '  pass  main.js keeps contextIsolation on, nodeIntegration off and the sandbox on'
    Write-Output '  pass  preload exposes only window.otterNative; the page has no require()'

    # 2. The manifest is untouched and the ordinary build still works.
    $manifestAfter = Get-Content -LiteralPath (Join-Path $projDir 'otter.json') -Raw | ConvertFrom-Json
    if ($manifestAfter.target -ne 'desktop') { throw 'Test 2: --target must not rewrite the manifest' }
    $plain = Invoke-Otter @('build', $projDir)
    if ($plain.ExitCode -ne 0) { throw "Test 2: plain build failed: $($plain.Output)" }
    if (-not (Test-Path -LiteralPath (Join-Path $dist 'index.html') -PathType Leaf)) { throw 'Test 2: plain desktop build should still produce dist/index.html' }
    Write-Output '  pass  --target is a build-time choice: the manifest and the default build are unchanged'

    # 3. otter desktop --electron on a loose file with a named stylesheet.
    $looseDir = Join-Path $testTmp 'loose'
    New-Item -ItemType Directory -Path $looseDir -Force | Out-Null
    New-Files $looseDir @{ 'demo.ot' = $program; 'demo.css' = "/* DEMO_CSS_MARKER */`n#go { color: red; }`n" }
    $outDir = Join-Path $testTmp 'loose-out'
    $desktop = Invoke-Otter @('desktop', (Join-Path $looseDir 'demo.ot'), '--electron', '--output', $outDir)
    if ($desktop.ExitCode -ne 0) { throw "Test 3: otter desktop --electron exited with $($desktop.ExitCode). Output: $($desktop.Output)" }
    if ($desktop.Output -notmatch 'Electron application written to') { throw "Test 3: unexpected output: $($desktop.Output)" }
    $loose = Assert-ShellFiles -Dir $outDir -Label 'Test 3'
    if ((Get-Count $loose.IndexHtml 'DEMO_CSS_MARKER') -ne 1) { throw 'Test 3: demo.css must be embedded once' }
    if ($loose.Package.name -ne 'demo') { throw "Test 3: package name should come from the file name, got $($loose.Package.name)" }
    Write-Output '  pass  otter desktop <file> --electron --output <dir> exports a loose program with its named stylesheet'

    # 4. Default output folder and bad target names.
    $desktopDefault = Invoke-Otter @('desktop', (Join-Path $looseDir 'demo.ot'), '--electron')
    if ($desktopDefault.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $looseDir 'dist-electron/main.js'))) { throw "Test 4: default output should be dist-electron beside the program. Output: $($desktopDefault.Output)" }
    $badTarget = Invoke-Otter @('build', $projDir, '--target', 'toaster')
    if ($badTarget.ExitCode -eq 0 -or $badTarget.Output -notmatch 'not a build target') { throw "Test 4: an unknown --target must fail with a readable message. Output: $($badTarget.Output)" }
    Write-Output '  pass  default output is dist-electron; an unknown --target is refused readably'

    # 5. Launch the exported app in a real Electron and use the bridge from the page.
    $electron = Find-Electron
    if (-not $electron) {
        Write-Output '  skip  launch test: no Electron runtime found (set OTTER_ELECTRON_PATH to run it)'
    } else {
        $workDir = Join-Path $testTmp 'work'
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $workDir 'smoke-input.txt'), 'hello from smoke', (New-Object System.Text.UTF8Encoding($false)))
        $reportPath = Join-Path $testTmp 'smoke-report.json'

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        # Test 2 rebuilt dist/ as a plain web build, so launch the intact
        # export from test 3 (the same program).
        $launchDir = $outDir
        $psi.FileName = $electron
        $psi.Arguments = "`"$launchDir`""
        $psi.WorkingDirectory = $launchDir
        $psi.UseShellExecute = $false
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        $psi.EnvironmentVariables['OTTER_ELECTRON_SMOKE'] = $reportPath
        $psi.EnvironmentVariables['OTTER_APP_CWD'] = $workDir
        $psi.EnvironmentVariables['OTTER_SMOKE_VALUE'] = 'from-test'
        # Editors that embed Node (VS Code) set this for their own processes;
        # inherited, it would turn Electron into a bare Node runtime.
        foreach ($nodeOnly in @('ELECTRON_RUN_AS_NODE', 'ELECTRON_NO_ATTACH_CONSOLE')) {
            if ($psi.EnvironmentVariables.ContainsKey($nodeOnly)) { $psi.EnvironmentVariables.Remove($nodeOnly) }
        }
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        if (-not $proc.WaitForExit(90000)) {
            try { $proc.Kill() } catch {}
            throw 'Test 5: Electron did not finish the smoke run within 90 seconds.'
        }
        if (-not (Test-Path -LiteralPath $reportPath)) { throw "Test 5: no smoke report was written. stderr: $($stderrTask.Result)" }
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        if (-not $report.ok) { throw "Test 5: smoke run failed: $($report.error)`nstderr: $($stderrTask.Result)" }
        $page = $report.page
        if ($page.nodeInRenderer) { throw 'Test 5: the renderer must not see require/process' }
        if (-not $page.hasNative) { throw 'Test 5: window.otterNative was not exposed' }
        if ($page.title -ne 'Electron Smoke') { throw "Test 5: expected the program's window title, got '$($page.title)'" }
        if ($page.read -ne 'hello from smoke') { throw "Test 5: read file returned '$($page.read)'" }
        if (-not $page.write.saved -or -not (Test-Path -LiteralPath (Join-Path $workDir 'smoke-output.txt'))) { throw 'Test 5: write file did not save through Node' }
        if (-not $page.exists -or $page.missing) { throw 'Test 5: file-exists answers are wrong' }
        if ($page.command.exitCode -ne 0 -or $page.command.output -notmatch 'hello-from-shell') { throw "Test 5: run command gave exit $($page.command.exitCode): $($page.command.output)" }
        if ($page.env -ne 'from-test') { throw "Test 5: environment lookup returned '$($page.env)'" }
        if ([string]::IsNullOrWhiteSpace($page.paths.tempFolder) -or $page.paths.currentDirectory -ne $workDir) { throw "Test 5: system paths are wrong: $($page.paths | ConvertTo-Json -Compress)" }
        if (($page.files -join ',') -ne 'smoke-input.txt,smoke-output.txt') { throw "Test 5: get files listed $($page.files -join ',')" }
        if ($page.readError -notmatch 'File not found') { throw "Test 5: a missing file should raise a readable error, got '$($page.readError)'" }
        if ($proc.ExitCode -ne 0) { throw "Test 5: Electron exited with $($proc.ExitCode)" }
        Write-Output "  pass  the exported app runs in Electron ($([System.IO.Path]::GetFileName((Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $electron)))))) and the page reaches files, commands and the environment through the shell"
        Write-Output '  pass  the renderer has no Node access; errors from the shell arrive as readable messages'
    }
}
finally {
    Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Electron export tests passed.'
