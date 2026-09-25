using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Project.psm1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Otter Project Build System (D118D)" -ForegroundColor Cyan

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d118d_tests_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

try {
    # Test 1: Build web project produces dist/index.html, dist/assets, and dist/otter.build.json
    $wProj = New-OtterProject -Archetype 'web' -Name 'WebBuildApp' -Path $testTmp
    $wDir = $wProj.RootDirectory
    $wBuildOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $wDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 1 failed: otter build WebBuildApp exited with $LASTEXITCODE. Output: $wBuildOut" }
    if (($wBuildOut -join "`n") -notmatch 'Build succeeded') { throw "Test 1 failed: Missing 'Build succeeded'. Output: $wBuildOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'dist/index.html') -PathType Leaf)) { throw "Test 1 failed: Missing dist/index.html" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'dist/assets/styles.css') -PathType Leaf)) { throw "Test 1 failed: Missing dist/assets/styles.css" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'dist/otter.build.json') -PathType Leaf)) { throw "Test 1 failed: Missing dist/otter.build.json" }

    $wMeta = Get-Content -LiteralPath (Join-Path $wDir 'dist/otter.build.json') -Raw | ConvertFrom-Json
    if ($wMeta.target -ne 'web') { throw "Test 1 failed: Expected build target web, got $($wMeta.target)" }
    if ($wMeta.entryPoint -ne 'index.html') { throw "Test 1 failed: Expected build entryPoint index.html, got $($wMeta.entryPoint)" }
    Write-Output '  pass  build web project produces dist/index.html, assets, and build metadata'

    # Test 2: Build console project produces runnable staged artifact
    $cProj = New-OtterProject -Archetype 'console' -Name 'ConsoleBuildApp' -Path $testTmp
    $cDir = $cProj.RootDirectory
    $cBuildOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $cDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 2 failed: otter build ConsoleBuildApp exited with $LASTEXITCODE. Output: $cBuildOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'dist/main.ot') -PathType Leaf)) { throw "Test 2 failed: Missing dist/main.ot" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'dist/otter.json') -PathType Leaf)) { throw "Test 2 failed: Missing dist/otter.json" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'dist/run.cmd') -PathType Leaf)) { throw "Test 2 failed: Missing dist/run.cmd" }

    # Verify built console project runs with `otter run dist/`
    $cRunDist = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') run (Join-Path $cDir 'dist') 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 2 failed: otter run dist/ failed: $cRunDist" }
    if (($cRunDist -join "`n") -notmatch 'Hello from ConsoleBuildApp') { throw "Test 2 failed: Unexpected output from built app: $cRunDist" }
    Write-Output '  pass  build console project produces runnable staged application with launcher'

    # Test 3: Build desktop project produces web bundle and desktop runner
    $dProj = New-OtterProject -Archetype 'desktop' -Name 'DesktopBuildApp' -Path $testTmp
    $dDir = $dProj.RootDirectory
    $dBuildOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $dDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 3 failed: otter build DesktopBuildApp exited with $LASTEXITCODE. Output: $dBuildOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $dDir 'dist/index.html') -PathType Leaf)) { throw "Test 3 failed: Missing dist/index.html in desktop build" }
    if (-not (Test-Path -LiteralPath (Join-Path $dDir 'dist/run-desktop.cmd') -PathType Leaf)) { throw "Test 3 failed: Missing dist/run-desktop.cmd" }
    if (-not (Test-Path -LiteralPath (Join-Path $dDir 'dist/assets/styles.css') -PathType Leaf)) { throw "Test 3 failed: Missing desktop assets/styles.css" }
    Write-Output '  pass  build desktop project produces web bundle and desktop runner script'

    # Test 4: Build game project produces canvas bundle and assets
    $gProj = New-OtterProject -Archetype 'game' -Name 'GameBuildApp' -Path $testTmp
    $gDir = $gProj.RootDirectory
    $gBuildOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $gDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 4 failed: otter build GameBuildApp exited with $LASTEXITCODE. Output: $gBuildOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $gDir 'dist/index.html') -PathType Leaf)) { throw "Test 4 failed: Missing dist/index.html in game build" }
    $gHtml = Get-Content -LiteralPath (Join-Path $gDir 'dist/index.html') -Raw -Encoding UTF8
    if ($gHtml -notmatch 'class="otter-canvas"') { throw "Test 4 failed: Expected canvas element in compiled game HTML" }
    Write-Output '  pass  build game project compiles canvas element and assets'

    # Test 5: Build multi-module project bundles dependencies
    $mDir = Join-Path $testTmp 'MultiModuleApp'
    $mSrc = Join-Path $mDir 'src'
    New-Item -ItemType Directory -Path $mSrc -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $mSrc 'math_utils.ot') -Value 'addValue is 40' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $mSrc 'format.ot') -Value "use `"math_utils.ot`"`nfinalScore is addValue + 2" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $mSrc 'main.ot') -Value "use `"format.ot`"`nsay `"Final result is`" finalScore" -Encoding UTF8

    $mManifest = @'
{
  "$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "MultiModuleApp",
  "version": "1.0.0",
  "archetype": "console",
  "target": "console",
  "entryPoint": "src/main.ot"
}
'@
    Set-Content -LiteralPath (Join-Path $mDir 'otter.json') -Value $mManifest -Encoding UTF8
    $mBuildOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $mDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 5 failed: multi-module build failed: $mBuildOut" }
    $mRunOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') run (Join-Path $mDir 'dist') 2>&1
    if (($mRunOut -join "`n") -notmatch 'Final result is 42') { throw "Test 5 failed: Multi-module app did not run correctly: $mRunOut" }
    Write-Output '  pass  build multi-module project bundles imported modules into self-contained artifact'

    # Test 6: Assets copied correctly with nested directory preservation
    $aDir = Join-Path $testTmp 'AssetApp'
    $aSrc = Join-Path $aDir 'src'
    $aImg = Join-Path $aDir 'assets/images/nested'
    $aData = Join-Path $aDir 'data'
    New-Item -ItemType Directory -Path $aSrc -Force | Out-Null
    New-Item -ItemType Directory -Path $aImg -Force | Out-Null
    New-Item -ItemType Directory -Path $aData -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $aSrc 'main.ot') -Value 'say "assets ready"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $aImg 'icon.png') -Value 'PNG_IMAGE_DATA' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $aData 'config.json') -Value '{"mode":"prod"}' -Encoding UTF8

    $aManifest = @'
{
  "$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "AssetApp",
  "entryPoint": "src/main.ot",
  "assets": ["assets/images/nested/icon.png", "data/config.json"]
}
'@
    Set-Content -LiteralPath (Join-Path $aDir 'otter.json') -Value $aManifest -Encoding UTF8
    $aBuildOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $aDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 6 failed: AssetApp build failed: $aBuildOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $aDir 'dist/assets/images/nested/icon.png') -PathType Leaf)) { throw "Test 6 failed: Missing nested icon.png" }
    if (-not (Test-Path -LiteralPath (Join-Path $aDir 'dist/data/config.json') -PathType Leaf)) { throw "Test 6 failed: Missing data/config.json" }
    $cfgContent = Get-Content -LiteralPath (Join-Path $aDir 'dist/data/config.json') -Raw
    if ($cfgContent -notmatch '"mode":"prod"') { throw "Test 6 failed: Config asset corrupted" }
    Write-Output '  pass  assets copied correctly and nested relative directories preserved'

    # Test 7: Missing declared asset causes build failure (exit 1)
    $missingAssetDir = Join-Path $testTmp 'MissingAssetApp'
    New-Item -ItemType Directory -Path $missingAssetDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $missingAssetDir 'main.ot') -Value 'say "hi"' -Encoding UTF8
    $missingManifest = @'
{
  "$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "MissingAssetApp",
  "entryPoint": "main.ot",
  "assets": ["nonexistent_asset.png"]
}
'@
    Set-Content -LiteralPath (Join-Path $missingAssetDir 'otter.json') -Value $missingManifest -Encoding UTF8
    $missBuildOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $missingAssetDir 2>&1
    if ($LASTEXITCODE -ne 1) { throw "Test 7 failed: Expected exit code 1 for missing asset, got $LASTEXITCODE" }
    if (($missBuildOut -join "`n") -notmatch 'declared asset "nonexistent_asset\.png" does not exist') {
        throw "Test 7 failed: Expected declared asset error message. Output: $missBuildOut"
    }
    if (Test-Path -LiteralPath (Join-Path $missingAssetDir 'dist')) { throw "Test 7 failed: dist directory should not be created on asset failure" }
    Write-Output '  pass  missing declared asset causes build failure (exit 1) without creating dist/'

    # Test 8: Path escape rejected (asset escaping root and absolute path)
    $escDir = Join-Path $testTmp 'EscapeApp'
    New-Item -ItemType Directory -Path $escDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $escDir 'main.ot') -Value 'say "hi"' -Encoding UTF8
    $escManifest1 = @'
{
  "name": "EscapeApp",
  "entryPoint": "main.ot",
  "assets": ["../outside.txt"]
}
'@
    Set-Content -LiteralPath (Join-Path $escDir 'otter.json') -Value $escManifest1 -Encoding UTF8
    $escOut1 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $escDir 2>&1
    if ($LASTEXITCODE -ne 1) { throw "Test 8a failed: Expected exit code 1 for escaping asset, got $LASTEXITCODE" }
    if (($escOut1 -join "`n") -notmatch 'escapes the project directory') { throw "Test 8a failed: Expected escape error. Output: $escOut1" }

    $escManifest2 = @'
{
  "name": "EscapeApp",
  "entryPoint": "main.ot",
  "build": { "outputDir": "../dangerous_dist" }
}
'@
    Set-Content -LiteralPath (Join-Path $escDir 'otter.json') -Value $escManifest2 -Encoding UTF8
    $escOut2 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $escDir 2>&1
    if ($LASTEXITCODE -eq 0) { throw "Test 8b failed: outputDir escaping project must be rejected" }

    $escManifest3 = @'
{
  "name": "EscapeApp",
  "entryPoint": "main.ot",
  "build": { "outputDir": "." }
}
'@
    Set-Content -LiteralPath (Join-Path $escDir 'otter.json') -Value $escManifest3 -Encoding UTF8
    $escOut3 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $escDir 2>&1
    if ($LASTEXITCODE -eq 0) { throw "Test 8c failed: outputDir set to project root itself must be rejected" }
    Write-Output '  pass  path escape rejected: asset escapes and unsafe outputDir paths strictly denied'

    # Test 9: Custom outputDir works cleanly
    $customDir = Join-Path $testTmp 'CustomOutApp'
    New-Item -ItemType Directory -Path $customDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $customDir 'main.ot') -Value 'say "custom out"' -Encoding UTF8
    $customManifest = @'
{
  "name": "CustomOutApp",
  "entryPoint": "main.ot",
  "build": {
    "outputDir": "build_artifacts/prod",
    "clean": true
  }
}
'@
    Set-Content -LiteralPath (Join-Path $customDir 'otter.json') -Value $customManifest -Encoding UTF8
    $customBuildOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $customDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 9 failed: custom outputDir build failed: $customBuildOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $customDir 'build_artifacts/prod/main.ot') -PathType Leaf)) {
        throw "Test 9 failed: Output not written to custom outputDir build_artifacts/prod"
    }
    Write-Output '  pass  custom outputDir correctly resolved and populated'

    # Test 10: Clean true removes stale build files
    $cleanDir = Join-Path $testTmp 'CleanApp'
    New-Item -ItemType Directory -Path $cleanDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $cleanDir 'main.ot') -Value 'say "clean test"' -Encoding UTF8
    $cleanManifest = @'
{
  "name": "CleanApp",
  "entryPoint": "main.ot",
  "build": { "clean": true }
}
'@
    Set-Content -LiteralPath (Join-Path $cleanDir 'otter.json') -Value $cleanManifest -Encoding UTF8
    # First build
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $cleanDir 2>&1 | Out-Null
    # Plant a stale file
    $staleFile = Join-Path $cleanDir 'dist/stale_artifact.txt'
    Set-Content -LiteralPath $staleFile -Value 'stale data' -Encoding UTF8
    if (-not (Test-Path -LiteralPath $staleFile)) { throw "Test 10 failed: Could not create stale test file" }

    # Second build with clean: true
    $cleanOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $cleanDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 10 failed: Second build failed: $cleanOut" }
    if (Test-Path -LiteralPath $staleFile) { throw "Test 10 failed: Stale file was not removed with clean: true" }
    Write-Output '  pass  clean: true removes stale build files on rebuild'

    # Test 11: Failed build does not destroy previous successful build (atomic promotion safety)
    $safeDir = Join-Path $testTmp 'SafeApp'
    New-Item -ItemType Directory -Path $safeDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $safeDir 'main.ot') -Value 'say "safe v1"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $safeDir 'otter.json') -Value '{"name":"SafeApp","entryPoint":"main.ot"}' -Encoding UTF8

    # Successful initial build
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $safeDir 2>&1 | Out-Null
    $builtMain = Join-Path $safeDir 'dist/main.ot'
    if (-not (Test-Path -LiteralPath $builtMain)) { throw "Test 11 failed: Initial build missing" }
    $v1Content = Get-Content -LiteralPath $builtMain -Raw

    # Break main.ot with syntax error
    Set-Content -LiteralPath (Join-Path $safeDir 'main.ot') -Value 'bad syntax is' -Encoding UTF8
    $failedOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $safeDir 2>&1
    if ($LASTEXITCODE -ne 2) { throw "Test 11 failed: Expected syntax error exit 2, got $LASTEXITCODE" }

    # Verify previous successful build artifact is STILL INTACT!
    if (-not (Test-Path -LiteralPath $builtMain)) { throw "Test 11 failed: Previous build was destroyed by failed build!" }
    $v1AfterFail = Get-Content -LiteralPath $builtMain -Raw
    if ($v1AfterFail -ne $v1Content) { throw "Test 11 failed: Previous build was mutated by failed build!" }
    Write-Output '  pass  failed build preserves previous successful build without corruption (atomic staging safety)'

    # Test 12: Syntax error prevents build and displays syntax diagnostics
    $synDir = Join-Path $testTmp 'SyntaxApp'
    New-Item -ItemType Directory -Path $synDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $synDir 'main.ot') -Value 'number is' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $synDir 'otter.json') -Value '{"name":"SyntaxApp","entryPoint":"main.ot"}' -Encoding UTF8
    $synOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $synDir 2>&1
    if ($LASTEXITCODE -ne 2) { throw "Test 12 failed: Expected exit code 2, got $LASTEXITCODE" }
    if (($synOut -join "`n") -notmatch 'Otter Syntax Error') { throw "Test 12 failed: Expected syntax error message" }
    if (Test-Path -LiteralPath (Join-Path $synDir 'dist')) { throw "Test 12 failed: dist/ was created on syntax failure" }
    Write-Output '  pass  syntax error prevents build and produces clean diagnostics with exit code 2'

    # Test 13: Project diagnostics retain module source locations during build check
    $modDiagDir = Join-Path $testTmp 'ModDiagApp'
    $modDiagSrc = Join-Path $modDiagDir 'src'
    New-Item -ItemType Directory -Path $modDiagSrc -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $modDiagSrc 'broken.ot') -Value 'x is 10 +' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $modDiagSrc 'main.ot') -Value "use `"broken.ot`"`nsay `"hello`"" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $modDiagDir 'otter.json') -Value '{"name":"ModDiagApp","entryPoint":"src/main.ot"}' -Encoding UTF8
    $modDiagOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $modDiagDir 2>&1
    if ($LASTEXITCODE -ne 2) { throw "Test 13 failed: Expected exit code 2 for module error, got $LASTEXITCODE" }
    $modDiagJoined = $modDiagOut -join "`n"
    if ($modDiagJoined -notmatch 'broken\.ot') { throw "Test 13 failed: Diagnostic did not identify broken.ot as source of error: $modDiagJoined" }
    Write-Output '  pass  project diagnostics retain module source locations when build check fails'

    # Test 14: Repeated builds are deterministic
    $detDir = Join-Path $testTmp 'DetApp'
    $dProj = New-OtterProject -Archetype 'web' -Name 'DetApp' -Path $testTmp
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $dProj.RootDirectory 2>&1 | Out-Null
    $hash1 = (Get-FileHash -LiteralPath (Join-Path $dProj.RootDirectory 'dist/index.html') -Algorithm SHA256).Hash
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build $dProj.RootDirectory 2>&1 | Out-Null
    $hash2 = (Get-FileHash -LiteralPath (Join-Path $dProj.RootDirectory 'dist/index.html') -Algorithm SHA256).Hash
    if ($hash1 -ne $hash2) { throw "Test 14 failed: Builds produced non-deterministic output hashes" }
    Write-Output '  pass  repeated builds are deterministic and produce byte-identical output'

    # Test 15: CLI commands in current directory: `otter build` and `otter build .`
    $prevCwd = (Get-Location).Path
    try {
        Set-Location -LiteralPath $dProj.RootDirectory
        $dotBuild = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build . 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 15a failed: otter build . exited with $LASTEXITCODE. Output: $dotBuild" }

        $bareBuild = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') build 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 15b failed: bare otter build exited with $LASTEXITCODE. Output: $bareBuild" }
    } finally {
        Set-Location -LiteralPath $prevCwd
    }
    Write-Output '  pass  CLI: `otter build` and `otter build .` build project in current working directory'

    # Test 16: Existing single-file commands continue working unchanged
    $singleOt = Join-Path $testTmp 'single.ot'
    Set-Content -LiteralPath $singleOt -Value 'say "single file ok"' -Encoding UTF8
    $singleRun = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') run $singleOt 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 16 failed: otter run <file.ot> failed: $singleRun" }
    if (($singleRun -join "`n") -notmatch 'single file ok') { throw "Test 16 failed: Output: $singleRun" }

    $singleCheck = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'otter.ps1') check $singleOt 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 16 failed: otter check <file.ot> failed: $singleCheck" }
    Write-Output '  pass  existing single-file commands (otter run file.ot, otter check file.ot) completely preserved'

} finally {
    Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "`nAll Otter project build system tests passed (16/16)."
