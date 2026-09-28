using module ..\Otter.Contract.psm1
using module ..\src\Otter.Project.psm1
using module ..\src\Otter.Package.psm1
. "$PSScriptRoot\TestHost.ps1"

# Electron packaging (otter package).
#
#   Otter source -> web compiler -> Electron export -> electron-builder -> installer / portable
#
# The configuration generator is pure and tested directly. The CLI is driven
# with --dry-run, which produces the export and electron-builder.json without
# running electron-builder, so the normal suite never waits on an installer
# build. A real Windows build plus a launch of the portable .exe from outside
# the repository runs only when OTTER_PACKAGE_INTEGRATION=1.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$otterPs1 = Join-Path $repoRoot 'otter.ps1'

Write-Output 'Electron packaging (otter package)'

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_package_tests_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

$program = @'
app is a window with title "Package Smoke"
greeting is a text with text "Hello from a packaged Otter app"
go is a button with text "Go"
put greeting, go in app
show app
'@
$stylesCss = "/* STYLES_CSS_MARKER */`n#go { color: blue; }`n#go:hover { color: green; }`n"

function New-Files {
    param([string]$Dir, [hashtable]$Files)
    foreach ($relative in $Files.Keys) {
        $path = Join-Path $Dir $relative
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        if ($Files[$relative] -is [byte[]]) { [System.IO.File]::WriteAllBytes($path, $Files[$relative]) }
        else { [System.IO.File]::WriteAllText($path, $Files[$relative], (New-Object System.Text.UTF8Encoding($false))) }
    }
}

function Invoke-Otter {
    param([string[]]$CliArgs)
    $out = & $script:OtterHostExe @script:OtterHostArgs -File $otterPs1 @CliArgs 2>&1
    return @{ ExitCode = $LASTEXITCODE; Output = ($out -join "`n") }
}

function New-Manifest {
    param([hashtable]$Extra = @{})
    $doc = [ordered]@{ name = 'Package Smoke'; version = '3.1.4'; archetype = 'desktop'; target = 'desktop'; entryPoint = 'main.ot' }
    foreach ($k in $Extra.Keys) { $doc[$k] = $Extra[$k] }
    return (ConvertTo-Json -InputObject $doc -Depth 4) + "`n"
}

# A real 256x256 PNG icon, drawn on the fly: electron-builder needs at least
# that size, and it converts PNG to the Windows .ico itself.
function New-IconPng {
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 256, 256
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::FromArgb(255, 9, 84, 248))
    $graphics.FillEllipse([System.Drawing.Brushes]::White, 64, 64, 128, 128)
    $graphics.Dispose()
    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    # Unary comma: without it PowerShell unrolls the byte[] into a loose array.
    return ,$stream.ToArray()
}

try {
    # --- 1. Configuration generator ------------------------------------------------
    $proj = [OtterProject]::new()
    $proj.Name = 'Sales Report'
    $proj.Version = '2.0.0'
    $proj.Author = 'Jeff Macy'
    $proj.Description = 'Reports sales'
    $cfg = New-OtterElectronBuilderConfig -Project $proj -Platform 'Windows' -OutputDir 'C:\out' -ElectronVersion '32.3.3' -IconFile 'build/icon.ico'
    if ($cfg.appId -ne 'org.otterlang.sales-report') { throw "Test 1: appId was $($cfg.appId)" }
    if ($cfg.productName -ne 'Sales Report') { throw 'Test 1: productName should be the project name' }
    if ($cfg.copyright -notmatch 'Jeff Macy') { throw 'Test 1: author should appear in the copyright line' }
    if (($cfg.win.target -join ',') -ne 'nsis,portable') { throw "Test 1: default targets should be nsis and portable, got $($cfg.win.target -join ',')" }
    if ($cfg.win.icon -ne 'build/icon.ico') { throw 'Test 1: icon should be passed to electron-builder' }
    if ($cfg.electronVersion -ne '32.3.3') { throw 'Test 1: electronVersion should be pinned to the toolchain' }
    if ($cfg.directories.output -ne 'C:\out') { throw 'Test 1: output directory should be honoured' }
    if (($cfg.files -join ',') -ne 'main.js,preload.js,package.json,app/**/*') { throw "Test 1: files should be exactly the export, got $($cfg.files -join ',')" }
    if ($cfg.nsis.oneClick -ne $false -or -not $cfg.nsis.allowToChangeInstallationDirectory) { throw 'Test 1: the installer should let people choose where to install' }
    Write-Output '  pass  configuration carries name, version, author, icon, targets and the pinned Electron version'

    $bare = [OtterProject]::new()
    $bare.Name = 'Bare'
    $cfgBare = New-OtterElectronBuilderConfig -Project $bare -Platform 'windows' -Kinds @('portable') -OutputDir 'C:\out'
    if ($cfgBare.win.Contains('icon')) { throw 'Test 1b: no icon key without an icon' }
    if ($cfgBare.Contains('electronVersion')) { throw 'Test 1b: no electronVersion without a toolchain' }
    if (($cfgBare.win.target -join ',') -ne 'portable') { throw 'Test 1b: --portable alone should build only the portable exe' }
    if ($cfgBare.copyright -notmatch '^Copyright \(c\) \d{4}$') { throw "Test 1b: copyright without an author should be plain, got $($cfgBare.copyright)" }
    Write-Output '  pass  missing optional metadata: no icon, no pinned version, plain copyright, portable-only target'

    foreach ($case in @(@{ Platform = 'toaster'; Expect = 'not a packaging target' }, @{ Platform = 'macos'; Expect = 'not available yet' }, @{ Platform = 'linux'; Expect = 'not available yet' })) {
        $threw = $null
        try { New-OtterElectronBuilderConfig -Project $bare -Platform $case.Platform -OutputDir 'C:\out' | Out-Null } catch { $threw = $_.Exception.Message }
        if (-not $threw -or $threw -notmatch $case.Expect) { throw "Test 1c: platform '$($case.Platform)' should be refused with '$($case.Expect)', got: $threw" }
    }
    $threw = $null
    try { New-OtterElectronBuilderConfig -Project $bare -Platform 'windows' -Kinds @('msi') -OutputDir 'C:\out' | Out-Null } catch { $threw = $_.Exception.Message }
    if ($threw -notmatch 'not a package kind') { throw "Test 1c: unknown kind should be refused, got: $threw" }
    Write-Output '  pass  unknown targets, untested platforms and unknown kinds are refused with readable messages'

    # --- 2. The CLI, dry run ----------------------------------------------------------
    $projDir = Join-Path $testTmp 'proj'
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null
    New-Files $projDir @{
        'main.ot' = $program
        'styles.css' = $stylesCss
        'assets/app.png' = (New-IconPng)
        'otter.json' = (New-Manifest @{ description = 'A packaged smoke test'; author = 'Otter Tests'; icon = 'assets/app.png' })
    }
    $dry = Invoke-Otter @('package', $projDir, '--target', 'windows', '--dry-run')
    if ($dry.ExitCode -ne 0) { throw "Test 2: otter package --dry-run exited with $($dry.ExitCode). Output: $($dry.Output)" }
    $dist = Join-Path $projDir 'dist'
    foreach ($file in @('main.js', 'preload.js', 'package.json', 'app/index.html', 'electron-builder.json', 'build/icon.png')) {
        if (-not (Test-Path -LiteralPath (Join-Path $dist $file) -PathType Leaf)) { throw "Test 2: dist/$file is missing after a dry run" }
    }
    $written = Get-Content -LiteralPath (Join-Path $dist 'electron-builder.json') -Raw | ConvertFrom-Json
    $pkg = Get-Content -LiteralPath (Join-Path $dist 'package.json') -Raw | ConvertFrom-Json
    if ($written.productName -ne 'Package Smoke' -or $written.win.icon -ne 'build/icon.png') { throw 'Test 2: electron-builder.json should carry the project name and icon' }
    if ($written.directories.output -ne (Join-Path $projDir 'packages')) { throw "Test 2: default output should be <project>\packages, got $($written.directories.output)" }
    if ($pkg.version -ne '3.1.4' -or $pkg.description -ne 'A packaged smoke test' -or $pkg.author -ne 'Otter Tests') { throw "Test 2: package.json should carry version, description and author; got $($pkg | ConvertTo-Json -Compress)" }
    $indexHtml = Get-Content -LiteralPath (Join-Path $dist 'app/index.html') -Raw
    if (([regex]::Matches($indexHtml, 'STYLES_CSS_MARKER')).Count -ne 1 -or $indexHtml -notmatch '#go:hover \{') { throw 'Test 2: styles.css must survive into the packaged app' }
    Write-Output '  pass  otter package --dry-run builds the Electron export, copies the icon and writes electron-builder.json'
    Write-Output '  pass  project metadata reaches package.json and the configuration; styles.css survives the pipeline'

    # --progress: one JSON event per step, for Otter Studio's Build -> Desktop App view.
    $progress = Invoke-Otter @('package', $projDir, '--target', 'windows', '--dry-run', '--progress')
    if ($progress.ExitCode -ne 0) { throw "Test 2b: --progress dry run exited with $($progress.ExitCode). Output: $($progress.Output)" }
    $events = @($progress.Output -split "`n" | Where-Object { $_.StartsWith('@otter-progress ') } | ForEach-Object { ($_.Substring(16).Trim()) | ConvertFrom-Json })
    $stepsSeen = @($events | ForEach-Object { $_.step })
    foreach ($expected in @('check', 'export', 'styles', 'configure', 'done')) {
        if ($expected -notin $stepsSeen) { throw "Test 2b: --progress should report '$expected'; saw: $($stepsSeen -join ',')" }
    }
    $stylesEvent = $events | Where-Object { $_.step -eq 'styles' } | Select-Object -First 1
    if ($stylesEvent.label -notmatch 'styles\.css') { throw "Test 2b: the styles step should name the stylesheet, got '$($stylesEvent.label)'" }
    $doneEvent = $events | Where-Object { $_.step -eq 'done' } | Select-Object -First 1
    if (-not $doneEvent.dryRun -or $doneEvent.outputDir -ne (Join-Path $projDir 'packages')) { throw "Test 2b: the done event should describe the dry run and output folder, got $($doneEvent | ConvertTo-Json -Compress)" }
    $plainRun = Invoke-Otter @('package', $projDir, '--target', 'windows', '--dry-run')
    if ($plainRun.Output -match '@otter-progress') { throw 'Test 2b: without --progress no progress lines may appear' }
    Write-Output '  pass  --progress emits one JSON event per step (check, export, styles, configure, done) and nothing without it'

    # Optional metadata absent, portable only, custom output.
    $plainDir = Join-Path $testTmp 'plain'
    New-Item -ItemType Directory -Path $plainDir -Force | Out-Null
    New-Files $plainDir @{ 'main.ot' = $program; 'otter.json' = (New-Manifest) }
    $customOut = Join-Path $testTmp 'custom-out'
    $dryPlain = Invoke-Otter @('package', $plainDir, '--target', 'windows', '--portable', '--output', $customOut, '--dry-run')
    if ($dryPlain.ExitCode -ne 0) { throw "Test 3: dry run without optional metadata failed: $($dryPlain.Output)" }
    $plainCfg = Get-Content -LiteralPath (Join-Path $plainDir 'dist/electron-builder.json') -Raw | ConvertFrom-Json
    if ($plainCfg.win.PSObject.Properties['icon']) { throw 'Test 3: no icon should be configured without one' }
    if (($plainCfg.win.target -join ',') -ne 'portable') { throw "Test 3: --portable should limit the targets, got $($plainCfg.win.target -join ',')" }
    if ($plainCfg.directories.output -ne $customOut) { throw "Test 3: --output should be honoured, got $($plainCfg.directories.output)" }
    if (Test-Path -LiteralPath (Join-Path $plainDir 'dist/build')) { throw 'Test 3: no build resources folder without an icon' }
    Write-Output '  pass  without optional metadata: no icon, --portable and --output are honoured'

    # Diagnostics through the CLI.
    $badTarget = Invoke-Otter @('package', $plainDir, '--target', 'toaster', '--dry-run')
    if ($badTarget.ExitCode -eq 0 -or $badTarget.Output -notmatch 'not a packaging target') { throw "Test 4: unknown target should fail readably. Output: $($badTarget.Output)" }
    $mac = Invoke-Otter @('package', $plainDir, '--target', 'macos', '--dry-run')
    if ($mac.ExitCode -eq 0 -or $mac.Output -notmatch 'not available yet') { throw "Test 4: macos should be refused honestly. Output: $($mac.Output)" }
    $badIconDir = Join-Path $testTmp 'badicon'
    New-Item -ItemType Directory -Path $badIconDir -Force | Out-Null
    New-Files $badIconDir @{ 'main.ot' = $program; 'otter.json' = (New-Manifest @{ icon = 'missing.ico' }) }
    $badIcon = Invoke-Otter @('package', $badIconDir, '--target', 'windows', '--dry-run')
    if ($badIcon.ExitCode -eq 0 -or $badIcon.Output -notmatch 'icon "missing.ico" does not exist') { throw "Test 4: a missing icon should be reported before building. Output: $($badIcon.Output)" }
    $smallIconDir = Join-Path $testTmp 'smallicon'
    New-Item -ItemType Directory -Path $smallIconDir -Force | Out-Null
    Add-Type -AssemblyName System.Drawing
    $small = New-Object System.Drawing.Bitmap 64, 64
    $smallStream = New-Object System.IO.MemoryStream
    $small.Save($smallStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $small.Dispose()
    New-Files $smallIconDir @{ 'main.ot' = $program; 'small.png' = $smallStream.ToArray(); 'otter.json' = (New-Manifest @{ icon = 'small.png' }) }
    $smallIcon = Invoke-Otter @('package', $smallIconDir, '--target', 'windows', '--dry-run')
    if ($smallIcon.ExitCode -eq 0 -or $smallIcon.Output -notmatch 'at least 256') { throw "Test 4: a small PNG icon should be reported before building. Output: $($smallIcon.Output)" }
    $consoleDir = Join-Path $testTmp 'console'
    New-Item -ItemType Directory -Path $consoleDir -Force | Out-Null
    New-Files $consoleDir @{ 'main.ot' = 'say "hi"'; 'otter.json' = "{`n  `"name`": `"cli`",`n  `"archetype`": `"console`",`n  `"target`": `"console`",`n  `"entryPoint`": `"main.ot`"`n}`n" }
    $consolePkg = Invoke-Otter @('package', $consoleDir, '--target', 'windows', '--dry-run')
    if ($consolePkg.ExitCode -eq 0 -or $consolePkg.Output -notmatch 'no window to package') { throw "Test 4: a console project should be refused. Output: $($consolePkg.Output)" }
    Write-Output '  pass  unknown target, untested platform, missing icon and console projects are refused before any build'

    # --- 3. Real build (opt in) -------------------------------------------------------
    if ($env:OTTER_PACKAGE_INTEGRATION -ne '1') {
        Write-Output '  skip  real electron-builder run (set OTTER_PACKAGE_INTEGRATION=1 to build and launch the portable .exe)'
    } else {
        $toolchain = Get-OtterElectronToolchain -ProjectRoot $projDir
        if (-not $toolchain) { throw 'Test 5: OTTER_PACKAGE_INTEGRATION=1 but no toolchain was found (set OTTER_ELECTRON_TOOLCHAIN).' }
        $started = Get-Date
        $real = Invoke-Otter @('package', $projDir, '--target', 'windows')
        $elapsed = (Get-Date) - $started
        if ($real.ExitCode -ne 0) { throw "Test 5: otter package failed: $($real.Output)" }
        $packages = Join-Path $projDir 'packages'
        $setup = Get-ChildItem -LiteralPath $packages -Filter '*Setup*.exe' | Select-Object -First 1
        $portable = Get-ChildItem -LiteralPath $packages -Filter '*Portable*.exe' | Select-Object -First 1
        if (-not $setup -or -not $portable) { throw "Test 5: expected a Setup and a Portable exe in $packages" }
        Write-Output ("  pass  electron-builder produced {0} ({1:N1} MB) and {2} ({3:N1} MB) in {4:N0} s" -f $setup.Name, ($setup.Length / 1MB), $portable.Name, ($portable.Length / 1MB), $elapsed.TotalSeconds)

        # The milestone: copy the portable exe away from the repository and run it.
        $standalone = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_standalone_' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $standalone -Force | Out-Null
        Copy-Item -LiteralPath $portable.FullName -Destination (Join-Path $standalone $portable.Name)
        [System.IO.File]::WriteAllText((Join-Path $standalone 'smoke-input.txt'), 'hello from smoke', (New-Object System.Text.UTF8Encoding($false)))
        $report = Join-Path $standalone 'report.json'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $standalone $portable.Name
        $psi.WorkingDirectory = $standalone
        $psi.UseShellExecute = $false
        $psi.EnvironmentVariables['OTTER_ELECTRON_SMOKE'] = $report
        $psi.EnvironmentVariables['OTTER_SMOKE_VALUE'] = 'from-test'
        foreach ($nodeOnly in @('ELECTRON_RUN_AS_NODE', 'OTTER_APP_CWD')) { if ($psi.EnvironmentVariables.ContainsKey($nodeOnly)) { $psi.EnvironmentVariables.Remove($nodeOnly) } }
        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc.WaitForExit(120000)) { try { $proc.Kill() } catch {}; throw 'Test 5: the portable app did not finish its smoke run within 120 s' }
        if (-not (Test-Path -LiteralPath $report)) { throw 'Test 5: the portable app wrote no smoke report' }
        $result = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
        if (-not $result.ok) { throw "Test 5: smoke run failed inside the portable app: $($result.error)" }
        if ($result.page.title -ne 'Package Smoke' -or $result.page.read -ne 'hello from smoke' -or $result.page.nodeInRenderer) { throw "Test 5: unexpected page results: $($result.page | ConvertTo-Json -Compress)" }
        if ($result.page.paths.currentDirectory -ne $standalone) { throw "Test 5: a portable app should work in its own folder, got $($result.page.paths.currentDirectory)" }
        if (-not (Test-Path -LiteralPath (Join-Path $standalone 'smoke-output.txt'))) { throw 'Test 5: the portable app should write files beside itself' }
        Write-Output '  pass  the portable .exe runs outside the repository with no Otter, PowerShell or Node involved, and reaches files, commands and the environment'
        Remove-Item -LiteralPath $standalone -Recurse -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'Electron packaging tests passed.'
