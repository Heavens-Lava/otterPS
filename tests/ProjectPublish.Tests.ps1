using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Project.psm1
. "$PSScriptRoot\TestHost.ps1"

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Otter Project Publishing & Packaging (D118E)" -ForegroundColor Cyan

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d118e_tests_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

try {
    # Test 1: Web publish produces package folder, zip, checksum, and metadata
    $wProj = New-OtterProject -Archetype 'web' -Name 'WebPubApp' -Path $testTmp
    $wDir = $wProj.RootDirectory
    $wPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $wDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 1 failed: otter publish WebPubApp exited with $LASTEXITCODE. Output: $wPubOut" }
    if (($wPubOut -join "`n") -notmatch 'Publish succeeded') { throw "Test 1 failed: Missing 'Publish succeeded'. Output: $wPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'dist/index.html') -PathType Leaf)) { throw "Test 1 failed: Missing dist/index.html (build first)" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'publish/WebPubApp-0.1.0/index.html') -PathType Leaf)) { throw "Test 1 failed: Missing publish/WebPubApp-0.1.0/index.html" }
    # D-3: the web scaffold's stylesheet is main.css, inlined into index.html.
    if ((Get-Content -LiteralPath (Join-Path $wDir 'publish/WebPubApp-0.1.0/index.html') -Raw -Encoding UTF8) -notmatch 'otter-sidecar-style') { throw "Test 1 failed: main.css not inlined into the packaged index.html" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'publish/WebPubApp-0.1.0.zip') -PathType Leaf)) { throw "Test 1 failed: Missing publish/WebPubApp-0.1.0.zip" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'publish/WebPubApp-0.1.0.zip.sha256') -PathType Leaf)) { throw "Test 1 failed: Missing publish/WebPubApp-0.1.0.zip.sha256" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'publish/otter.publish.json') -PathType Leaf)) { throw "Test 1 failed: Missing publish/otter.publish.json" }
    Write-Output '  pass  web publish produces package folder, zip archive, checksum, and metadata'

    # Test 2: Console publish packages runnable source, manifest, and launcher
    $cProj = New-OtterProject -Archetype 'console' -Name 'ConsolePubApp' -Path $testTmp
    $cDir = $cProj.RootDirectory
    $cPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $cDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 2 failed: otter publish ConsolePubApp exited with $LASTEXITCODE. Output: $cPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'publish/ConsolePubApp-0.1.0/main.ot') -PathType Leaf)) { throw "Test 2 failed: Missing main.ot in console package" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'publish/ConsolePubApp-0.1.0/otter.json') -PathType Leaf)) { throw "Test 2 failed: Missing otter.json in console package" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'publish/ConsolePubApp-0.1.0/run.cmd') -PathType Leaf)) { throw "Test 2 failed: Missing run.cmd in console package" }
    if (-not (Test-Path -LiteralPath (Join-Path $cDir 'publish/ConsolePubApp-0.1.0/run') -PathType Leaf)) { throw "Test 2 failed: Missing the macOS/Linux run launcher in console package" }
    $cMeta = Get-Content -LiteralPath (Join-Path $cDir 'publish/otter.publish.json') -Raw | ConvertFrom-Json
    if ($cMeta.runtimeRequirements -notmatch 'Otter runtime') { throw "Test 2 failed: Expected runtime requirement to mention Otter runtime. Got: $($cMeta.runtimeRequirements)" }
    Write-Output '  pass  console publish packages runnable source, manifest, and launcher'

    # Test 3: Desktop publish packages web bundle and desktop runner
    $dProj = New-OtterProject -Archetype 'desktop' -Name 'DesktopPubApp' -Path $testTmp
    $dDir = $dProj.RootDirectory
    $dPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $dDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 3 failed: otter publish DesktopPubApp exited with $LASTEXITCODE. Output: $dPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $dDir 'publish/DesktopPubApp-0.1.0/index.html') -PathType Leaf)) { throw "Test 3 failed: Missing index.html in desktop package" }
    if (-not (Test-Path -LiteralPath (Join-Path $dDir 'publish/DesktopPubApp-0.1.0/run-desktop.cmd') -PathType Leaf)) { throw "Test 3 failed: Missing run-desktop.cmd in desktop package" }
    Write-Output '  pass  desktop publish packages web application and desktop runner script'

    # Test 4: Game publish packages canvas runtime bundle and assets
    $gProj = New-OtterProject -Archetype 'game' -Name 'GamePubApp' -Path $testTmp
    $gDir = $gProj.RootDirectory
    $gPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $gDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 4 failed: otter publish GamePubApp exited with $LASTEXITCODE. Output: $gPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $gDir 'publish/GamePubApp-0.1.0/index.html') -PathType Leaf)) { throw "Test 4 failed: Missing index.html in game package" }
    if ((Get-Content -LiteralPath (Join-Path $gDir 'publish/GamePubApp-0.1.0/index.html') -Raw -Encoding UTF8) -notmatch 'otter-sidecar-style') { throw "Test 4 failed: main.css not inlined into the packaged game index.html" }
    Write-Output '  pass  game publish packages canvas runtime bundle and assets'

    # Test 5: Automation publish maps to runnable task artifact
    $aProj = New-OtterProject -Archetype 'automation' -Name 'AutoPubApp' -Path $testTmp
    $aDir = $aProj.RootDirectory
    $aPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $aDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 5 failed: otter publish AutoPubApp exited with $LASTEXITCODE. Output: $aPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $aDir 'publish/AutoPubApp-0.1.0/main.ot') -PathType Leaf)) { throw "Test 5 failed: Missing main.ot in auto package" }
    if (-not (Test-Path -LiteralPath (Join-Path $aDir 'publish/AutoPubApp-0.1.0/run.cmd') -PathType Leaf)) { throw "Test 5 failed: Missing run.cmd in auto package" }
    if (-not (Test-Path -LiteralPath (Join-Path $aDir 'publish/AutoPubApp-0.1.0/run') -PathType Leaf)) { throw "Test 5 failed: Missing the macOS/Linux run launcher in auto package" }
    Write-Output '  pass  automation publish maps to runnable task artifact'

    # Test 6: Versioned filename accurately reflects manifest name and version
    $vProjDir = Join-Path $testTmp 'VerApp'
    New-Item -ItemType Directory -Path $vProjDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $vProjDir 'main.ot') -Value 'say "ver test"' -Encoding UTF8
    $vManifest = @"
{
  "`$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "CustomVerApp",
  "version": "2.3.4",
  "target": "console",
  "entryPoint": "main.ot"
}
"@
    Set-Content -LiteralPath (Join-Path $vProjDir 'otter.json') -Value $vManifest -Encoding UTF8
    $vPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $vProjDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 6 failed: Publish exited with $LASTEXITCODE. Output: $vPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $vProjDir 'publish/CustomVerApp-2.3.4.zip') -PathType Leaf)) { throw "Test 6 failed: Missing CustomVerApp-2.3.4.zip" }
    if (-not (Test-Path -LiteralPath (Join-Path $vProjDir 'publish/CustomVerApp-2.3.4.zip.sha256') -PathType Leaf)) { throw "Test 6 failed: Missing CustomVerApp-2.3.4.zip.sha256" }
    Write-Output '  pass  versioned filename accurately reflects manifest name and version'

    # Test 7: Archive contains expected files without missing entries
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipPath = Join-Path $wDir 'publish/WebPubApp-0.1.0.zip'
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
        if ($entryNames -notcontains 'index.html') { throw "Test 7 failed: Archive missing index.html. Entries: $($entryNames -join ', ')" }
        if ($entryNames -contains 'assets/styles.css') { throw "Test 7 failed: Archive still ships the unused assets/styles.css. Entries: $($entryNames -join ', ')" }
        if ($entryNames -notcontains 'otter.build.json') { throw "Test 7 failed: Archive missing otter.build.json. Entries: $($entryNames -join ', ')" }
    } finally {
        $archive.Dispose()
    }
    Write-Output '  pass  archive contains expected files without missing or corrupted entries'

    # Test 8: Nested assets preserved across directory hierarchies
    $nestDir = Join-Path $testTmp 'NestApp'
    New-Item -ItemType Directory -Path (Join-Path $nestDir 'assets/images/icons') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $nestDir 'main.ot') -Value 'say "nest"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $nestDir 'assets/images/icons/logo.png') -Value 'FAKEPNGDATA' -Encoding ASCII
    $nestManifest = @"
{
  "`$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "NestApp",
  "version": "1.0.0",
  "target": "console",
  "entryPoint": "main.ot",
  "assets": ["assets/images/icons/logo.png"]
}
"@
    Set-Content -LiteralPath (Join-Path $nestDir 'otter.json') -Value $nestManifest -Encoding UTF8
    $nestPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $nestDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 8 failed: Publish exited with $LASTEXITCODE. Output: $nestPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $nestDir 'publish/NestApp-1.0.0/assets/images/icons/logo.png') -PathType Leaf)) {
        throw "Test 8 failed: Missing nested asset in package folder"
    }
    $nestZip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $nestDir 'publish/NestApp-1.0.0.zip'))
    try {
        $nestEntries = @($nestZip.Entries | ForEach-Object { $_.FullName })
        if ($nestEntries -notcontains 'assets/images/icons/logo.png') {
            throw "Test 8 failed: Zip missing nested asset entry: $($nestEntries -join ', ')"
        }
    } finally {
        $nestZip.Dispose()
    }
    Write-Output '  pass  nested assets preserved across directory hierarchies'

    # Test 9: Checksum matches archive byte-for-byte
    $shaFile = Join-Path $wDir 'publish/WebPubApp-0.1.0.zip.sha256'
    $shaText = (Get-Content -LiteralPath $shaFile -Raw).Trim()
    $computedHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedLine = "$computedHash  WebPubApp-0.1.0.zip"
    if ($shaText -ne $expectedLine) {
        throw "Test 9 failed: Expected sha256 '$expectedLine', but got '$shaText'"
    }
    Write-Output '  pass  checksum matches archive byte-for-byte'

    # Test 10: Metadata correctly documents project attributes, runtime, and checksum
    $metaPath = Join-Path $wDir 'publish/otter.publish.json'
    $pubMeta = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
    if ($pubMeta.name -ne 'WebPubApp') { throw "Test 10 failed: Expected name WebPubApp, got $($pubMeta.name)" }
    if ($pubMeta.version -ne '0.1.0') { throw "Test 10 failed: Expected version 0.1.0, got $($pubMeta.version)" }
    if ($pubMeta.target -ne 'web') { throw "Test 10 failed: Expected target web, got $($pubMeta.target)" }
    if ($pubMeta.artifactFilename -ne 'WebPubApp-0.1.0.zip') { throw "Test 10 failed: Expected artifactFilename WebPubApp-0.1.0.zip, got $($pubMeta.artifactFilename)" }
    if ($pubMeta.sha256 -ne $computedHash) { throw "Test 10 failed: Expected sha256 $computedHash, got $($pubMeta.sha256)" }
    if (-not $pubMeta.otterVersion) { throw "Test 10 failed: Missing otterVersion in metadata" }
    Write-Output '  pass  metadata correctly documents project attributes, runtime, and checksum'

    # Test 11: Invalid manifest fails publish with informative diagnostic
    $invDir = Join-Path $testTmp 'InvApp'
    New-Item -ItemType Directory -Path $invDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $invDir 'main.ot') -Value 'say "ok"' -Encoding UTF8
    $invManifest = @"
{
  "`$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "",
  "version": "",
  "target": "console",
  "entryPoint": "main.ot"
}
"@
    Set-Content -LiteralPath (Join-Path $invDir 'otter.json') -Value $invManifest -Encoding UTF8
    $invPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $invDir 2>&1
    if ($LASTEXITCODE -eq 0) { throw "Test 11 failed: Expected failure for empty name/version, got exit code 0" }
    if (($invPubOut -join "`n") -notmatch 'property "name" is required for publish') {
        throw "Test 11 failed: Unexpected output: $invPubOut"
    }
    if (Test-Path -LiteralPath (Join-Path $invDir 'publish')) { throw "Test 11 failed: publish directory should not be created on validation failure" }
    Write-Output '  pass  invalid manifest fails publish with informative diagnostic'

    # Test 12: Build failure prevents publish and aborts without publishing
    $failDir = Join-Path $testTmp 'FailApp'
    New-Item -ItemType Directory -Path $failDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $failDir 'main.ot') -Value "val1 is 10 +`n" -Encoding UTF8
    $failManifest = @"
{
  "`$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "FailApp",
  "version": "1.0.0",
  "target": "console",
  "entryPoint": "main.ot"
}
"@
    Set-Content -LiteralPath (Join-Path $failDir 'otter.json') -Value $failManifest -Encoding UTF8
    $failPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $failDir 2>&1
    if ($LASTEXITCODE -ne 2) { throw "Test 12 failed: Expected syntax error exit 2, got $LASTEXITCODE. Output: $failPubOut" }
    if (Test-Path -LiteralPath (Join-Path $failDir 'publish')) { throw "Test 12 failed: publish folder should not exist after build failure" }
    Write-Output '  pass  build failure prevents publish and aborts without publishing'

    # Test 13: Previous successful publish survives subsequent build failure intact
    $presDir = Join-Path $testTmp 'PreserveApp'
    New-Item -ItemType Directory -Path $presDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $presDir 'main.ot') -Value 'say "initial ok"' -Encoding UTF8
    $presManifest = @"
{
  "`$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "PreserveApp",
  "version": "1.0.0",
  "target": "console",
  "entryPoint": "main.ot"
}
"@
    Set-Content -LiteralPath (Join-Path $presDir 'otter.json') -Value $presManifest -Encoding UTF8
    $presPub1 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $presDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 13 failed: Initial publish failed: $presPub1" }
    $presZipPath = Join-Path $presDir 'publish/PreserveApp-1.0.0.zip'
    $initialHash = (Get-FileHash -LiteralPath $presZipPath -Algorithm SHA256).Hash

    # Break project
    Set-Content -LiteralPath (Join-Path $presDir 'main.ot') -Value "val1 is 10 +`n" -Encoding UTF8
    $presPub2 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $presDir 2>&1
    if ($LASTEXITCODE -eq 0) { throw "Test 13 failed: Broken build was supposed to fail publish" }

    # Verify previous publish files are STILL intact
    if (-not (Test-Path -LiteralPath $presZipPath -PathType Leaf)) { throw "Test 13 failed: Previous zip was deleted on failure" }
    $survivingHash = (Get-FileHash -LiteralPath $presZipPath -Algorithm SHA256).Hash
    if ($survivingHash -ne $initialHash) { throw "Test 13 failed: Previous zip was corrupted: expected $initialHash, got $survivingHash" }
    Write-Output '  pass  previous successful publish survives subsequent build failure intact'

    # Test 14: Path traversal strictly rejected during archive extraction and invalid outputDir
    $badOutDir = Join-Path $testTmp 'BadOutApp'
    New-Item -ItemType Directory -Path $badOutDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $badOutDir 'main.ot') -Value 'say "bad out"' -Encoding UTF8
    $badOutManifest = @"
{
  "`$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "BadOutApp",
  "version": "1.0.0",
  "target": "console",
  "entryPoint": "main.ot",
  "publish": {
    "outputDir": "../outside"
  }
}
"@
    Set-Content -LiteralPath (Join-Path $badOutDir 'otter.json') -Value $badOutManifest -Encoding UTF8
    $badOutRes = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $badOutDir 2>&1
    if ($LASTEXITCODE -eq 0) { throw "Test 14 failed: Escaping outputDir should fail, but got exit 0" }
    if (($badOutRes -join "`n") -notmatch 'publish.outputDir must stay inside the project directory') {
        throw "Test 14 failed: Missing containment error. Output: $badOutRes"
    }

    # Test Expand-OtterDeterministicArchive path traversal rejection
    $fakeZipPath = Join-Path $testTmp 'traversal.zip'
    $zipStream = [System.IO.File]::Create($fakeZipPath)
    $zipArch = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
    $entry = $zipArch.CreateEntry('../escape.txt')
    $writer = [System.IO.StreamWriter]::new($entry.Open())
    $writer.Write('evil')
    $writer.Dispose()
    $zipArch.Dispose()
    $zipStream.Dispose()

    $extractTarget = Join-Path $testTmp 'extract_target'
    $traversalCaught = $false
    try {
        Expand-OtterDeterministicArchive -ZipPath $fakeZipPath -DestinationDir $extractTarget
    } catch {
        $traversalCaught = $true
    }
    if (-not $traversalCaught) { throw "Test 14 failed: Expand-OtterDeterministicArchive failed to catch path traversal" }
    Write-Output '  pass  path traversal strictly rejected during archive creation and extraction'

    # Test 15: Repeated publish runs are deterministic and produce byte-identical archives
    $detProj = New-OtterProject -Archetype 'web' -Name 'DetPubApp' -Path $testTmp
    $detDir = $detProj.RootDirectory
    $detRes1 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $detDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 15 failed: Publish 1 failed: $detRes1" }
    $detZip = Join-Path $detDir 'publish/DetPubApp-0.1.0.zip'
    $hash1 = (Get-FileHash -LiteralPath $detZip -Algorithm SHA256).Hash

    Start-Sleep -Seconds 1

    $detRes2 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $detDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 15 failed: Publish 2 failed: $detRes2" }
    $hash2 = (Get-FileHash -LiteralPath $detZip -Algorithm SHA256).Hash

    if ($hash1 -ne $hash2) {
        throw "Test 15 failed: Non-deterministic archives produced: Hash 1: $hash1, Hash 2: $hash2"
    }
    Write-Output '  pass  repeated publish runs are deterministic and produce byte-identical archives'

    # Test 16: Project name sanitization replaces filesystem-invalid characters deterministically
    $sanDir = Join-Path $testTmp 'SanitizeApp'
    New-Item -ItemType Directory -Path $sanDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $sanDir 'main.ot') -Value 'say "sanitized"' -Encoding UTF8
    $sanManifest = @"
{
  "`$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "My Special:App *2026*",
  "version": "1.0.0",
  "target": "console",
  "entryPoint": "main.ot"
}
"@
    Set-Content -LiteralPath (Join-Path $sanDir 'otter.json') -Value $sanManifest -Encoding UTF8
    $sanPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $sanDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 16 failed: Publish exited with $LASTEXITCODE. Output: $sanPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $sanDir 'publish/My-Special-App-2026-1.0.0.zip') -PathType Leaf)) {
        throw "Test 16 failed: Expected My-Special-App-2026-1.0.0.zip. Found files: $((Get-ChildItem (Join-Path $sanDir 'publish') | Select-Object -ExpandProperty Name) -join ', ')"
    }
    Write-Output '  pass  project name sanitization replaces filesystem-invalid characters deterministically'

    # Test 17: Full archive verification succeeds after extraction into clean directory
    $extractCleanDir = Join-Path $testTmp 'clean_extracted'
    Expand-OtterDeterministicArchive -ZipPath $zipPath -DestinationDir $extractCleanDir
    if (-not (Test-Path -LiteralPath (Join-Path $extractCleanDir 'index.html') -PathType Leaf)) { throw "Test 17 failed: Extracted archive missing index.html" }
    if (-not (Test-Path -LiteralPath (Join-Path $extractCleanDir 'otter.build.json') -PathType Leaf)) { throw "Test 17 failed: Extracted archive missing otter.build.json" }
    $origHtml = Get-Content -LiteralPath (Join-Path $wDir 'dist/index.html') -Raw
    $extrHtml = Get-Content -LiteralPath (Join-Path $extractCleanDir 'index.html') -Raw
    if ($origHtml -ne $extrHtml) { throw "Test 17 failed: Extracted index.html does not match original build output" }
    Write-Output '  pass  full archive verification succeeds after extraction into clean directory'

    # Test 18: Existing build and single-file behaviors remain completely unchanged
    $bApp = New-OtterProject -Archetype 'console' -Name 'OnlyBuildApp' -Path $testTmp
    $bDir = $bApp.RootDirectory
    $bOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') build $bDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 18 failed: otter build failed: $bOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $bDir 'dist') -PathType Container)) { throw "Test 18 failed: dist/ was not created by build" }
    if (Test-Path -LiteralPath (Join-Path $bDir 'publish')) { throw "Test 18 failed: otter build should not create publish/" }

    $singleScript = Join-Path $testTmp 'single_standalone.ot'
    Set-Content -LiteralPath $singleScript -Value 'say "standalone ok"' -Encoding UTF8
    $runStandalone = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') run $singleScript 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 18 failed: otter run single_standalone.ot failed: $runStandalone" }
    if (($runStandalone -join "`n") -notmatch 'standalone ok') { throw "Test 18 failed: Unexpected output from standalone run: $runStandalone" }
    Write-Output '  pass  existing build and single-file behaviors remain completely unchanged'

    # Test 19: A version that forms a path is refused before anything is written
    # (regression: "1/../../../escape" made publish write outside the project)
    $escRoot = Join-Path $testTmp 'EscapeHost'
    $escDir = Join-Path $escRoot 'EscApp'
    New-Item -ItemType Directory -Path $escDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $escDir 'main.ot') -Value 'say "escape"' -Encoding UTF8
    foreach ($badVersion in @('1/../../../escape', '1/../../escape', '1\..\..\..\escape', '..', '1..2', ' ', '-1')) {
        $escManifest = [ordered]@{ name = 'EscApp'; version = $badVersion; target = 'console'; entryPoint = 'main.ot' }
        Set-Content -LiteralPath (Join-Path $escDir 'otter.json') -Value (ConvertTo-Json -InputObject $escManifest) -Encoding UTF8
        $escRes = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $escDir 2>&1
        if ($LASTEXITCODE -eq 0) { throw "Test 19 failed: version '$badVersion' should be refused. Output: $escRes" }
        if (($escRes -join "`n") -notmatch 'property "version"') { throw "Test 19 failed: Missing version diagnostic for '$badVersion'. Output: $escRes" }
        foreach ($escapeTarget in @((Join-Path $escRoot 'escape'), (Join-Path $escDir 'escape'), (Join-Path $escDir 'publish'), (Join-Path $escDir 'dist'))) {
            if (Test-Path -LiteralPath $escapeTarget) { throw "Test 19 failed: version '$badVersion' created $escapeTarget" }
        }
        $escLeftovers = @(Get-ChildItem -LiteralPath $escRoot -Force | Where-Object { $_.Name -ne 'EscApp' })
        if ($escLeftovers.Count -gt 0) { throw "Test 19 failed: version '$badVersion' wrote outside the project: $($escLeftovers.Name -join ', ')" }
    }
    Write-Output '  pass  unsafe manifest versions are refused and nothing is written outside the project'

    # Test 20: Ordinary release and prerelease versions still publish
    foreach ($goodVersion in @('1.2.3', '1.0.0-rc.2')) {
        $goodDir = Join-Path $testTmp ("GoodVer-" + $goodVersion)
        New-Item -ItemType Directory -Path $goodDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $goodDir 'main.ot') -Value 'say "good"' -Encoding UTF8
        $goodManifest = [ordered]@{ name = 'GoodVerApp'; version = $goodVersion; target = 'console'; entryPoint = 'main.ot' }
        Set-Content -LiteralPath (Join-Path $goodDir 'otter.json') -Value (ConvertTo-Json -InputObject $goodManifest) -Encoding UTF8
        $goodRes = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $goodDir 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 20 failed: version '$goodVersion' publish exited with $LASTEXITCODE. Output: $goodRes" }
        if (-not (Test-Path -LiteralPath (Join-Path $goodDir "publish/GoodVerApp-$goodVersion.zip") -PathType Leaf)) { throw "Test 20 failed: Missing GoodVerApp-$goodVersion.zip" }
        if (-not (Test-Path -LiteralPath (Join-Path $goodDir "publish/GoodVerApp-$goodVersion/main.ot") -PathType Leaf)) { throw "Test 20 failed: Missing GoodVerApp-$goodVersion/main.ot" }
    }
    Write-Output '  pass  ordinary release and prerelease versions (1.2.3, 1.0.0-rc.2) still publish'

    # Test 21: Publish refuses to replace a folder Otter did not create
    # (regression: `otter publish --output tests` deleted the project's tests)
    $ownProj = New-OtterProject -Archetype 'console' -Name 'OwnOutApp' -Path $testTmp
    $ownDir = $ownProj.RootDirectory
    $ownTestFile = Join-Path $ownDir 'tests/app_test.ot'
    $ownTestBefore = Get-Content -LiteralPath $ownTestFile -Raw
    $ownRes = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $ownDir --output tests 2>&1
    if ($LASTEXITCODE -eq 0) { throw "Test 21 failed: publish --output tests should be refused. Output: $ownRes" }
    if (($ownRes -join "`n") -notmatch 'was not created by Otter') { throw "Test 21 failed: Missing refusal diagnostic. Output: $ownRes" }
    if (-not (Test-Path -LiteralPath $ownTestFile -PathType Leaf)) { throw "Test 21 failed: tests/app_test.ot was deleted" }
    if ((Get-Content -LiteralPath $ownTestFile -Raw) -ne $ownTestBefore) { throw "Test 21 failed: tests/app_test.ot was changed" }
    Set-Content -LiteralPath (Join-Path $ownDir 'src/keep.ot') -Value 'say "keep"' -Encoding UTF8
    $ownSrcRes = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $ownDir --output src 2>&1
    if ($LASTEXITCODE -eq 0) { throw "Test 21 failed: publish --output src should be refused. Output: $ownSrcRes" }
    if (-not (Test-Path -LiteralPath (Join-Path $ownDir 'src/keep.ot') -PathType Leaf)) { throw "Test 21 failed: src/keep.ot was deleted" }
    Write-Output '  pass  publish refuses to replace folders Otter did not create and leaves their files intact'

    # Test 22: Republishing into the Otter-created publish/ folder still replaces it
    $repRes1 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $ownDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 22 failed: first publish failed: $repRes1" }
    $repStale = Join-Path $ownDir 'publish/stale.txt'
    Set-Content -LiteralPath $repStale -Value 'stale' -Encoding UTF8
    $repRes2 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $ownDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 22 failed: republish into Otter-created publish/ failed: $repRes2" }
    if (Test-Path -LiteralPath $repStale) { throw "Test 22 failed: republish did not replace publish/" }
    if (-not (Test-Path -LiteralPath (Join-Path $ownDir 'publish/OwnOutApp-0.1.0.zip') -PathType Leaf)) { throw "Test 22 failed: Missing OwnOutApp-0.1.0.zip after republish" }
    Write-Output '  pass  republish still replaces the Otter-created publish/ and dist/ folders'

    # Test 23 (RC3 B7): the .sha256 file is UTF-8 (no BOM), so a non-ASCII
    # project name is written as-is. It was written as ASCII, which turned
    # "cafe" with e-acute into "caf?" and broke `sha256sum -c`.
    # RC3-B7 begin
    $b7Name = "caf$([char]0xE9)"
    $b7Dir = Join-Path $testTmp 'B7App'
    New-Item -ItemType Directory -Path $b7Dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $b7Dir 'main.ot') -Value 'say "b7"' -Encoding UTF8
    $b7Manifest = ConvertTo-Json -InputObject ([ordered]@{ name = $b7Name; version = '1.0.0'; target = 'console'; entryPoint = 'main.ot' })
    [System.IO.File]::WriteAllText((Join-Path $b7Dir 'otter.json'), $b7Manifest, [System.Text.UTF8Encoding]::new($false))
    $b7Out = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $b7Dir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 23 failed: publish of '$b7Name' exited $LASTEXITCODE. Output: $b7Out" }
    $b7Zip = Join-Path $b7Dir "publish/$b7Name-1.0.0.zip"
    if (-not (Test-Path -LiteralPath $b7Zip -PathType Leaf)) { throw "Test 23 failed: missing $b7Zip" }
    $b7ShaBytes = [System.IO.File]::ReadAllBytes("$b7Zip.sha256")
    if ($b7ShaBytes.Length -ge 3 -and $b7ShaBytes[0] -eq 0xEF -and $b7ShaBytes[1] -eq 0xBB -and $b7ShaBytes[2] -eq 0xBF) { throw "Test 23 failed: .sha256 starts with a UTF-8 BOM" }
    $b7ShaLine = [System.Text.UTF8Encoding]::new($false, $true).GetString($b7ShaBytes).Trim()
    $b7Hash = (Get-FileHash -LiteralPath $b7Zip -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($b7ShaLine -cne "$b7Hash  $b7Name-1.0.0.zip") { throw "Test 23 failed: .sha256 line is '$b7ShaLine', expected '$b7Hash  $b7Name-1.0.0.zip'" }
    Write-Output '  pass  .sha256 is UTF-8 without BOM and names a non-ASCII zip exactly, with a matching hash'
    # RC3-B7 end

    # Test 24 (RC3 B8): publish always packages a clean build. With
    # "clean": false an overlay build kept deleted assets (and an earlier
    # publish folder inside the build folder), and all of it shipped.
    # RC3-B8 begin
    $b8Dir = Join-Path $testTmp 'B8App'
    New-Item -ItemType Directory -Path (Join-Path $b8Dir 'assets') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $b8Dir 'main.ot') -Value 'say "b8"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $b8Dir 'assets/keep.txt') -Value 'keep' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $b8Dir 'assets/extra.txt') -Value 'extra' -Encoding UTF8
    $b8Write = {
        param([string[]]$Assets)
        $b8Obj = [ordered]@{ name = 'B8App'; version = '1.0.0'; target = 'console'; entryPoint = 'main.ot'; assets = [string[]]@($Assets); build = [ordered]@{ outputDir = 'dist'; clean = $false }; publish = [ordered]@{ outputDir = 'dist/pub' } }
        Set-Content -LiteralPath (Join-Path $b8Dir 'otter.json') -Value (ConvertTo-Json -InputObject $b8Obj -Depth 5) -Encoding UTF8
    }
    & $b8Write @('assets/keep.txt', 'assets/extra.txt')
    $b8Pub1 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $b8Dir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 24 failed: first publish exited $LASTEXITCODE. Output: $b8Pub1" }

    # The user deletes an asset from disk and from the manifest.
    Remove-Item -LiteralPath (Join-Path $b8Dir 'assets/extra.txt') -Force
    & $b8Write @('assets/keep.txt')

    # A plain build keeps the documented clean:false overlay behavior.
    $b8Build = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') build $b8Dir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 24 failed: overlay build exited $LASTEXITCODE. Output: $b8Build" }
    if (-not (Test-Path -LiteralPath (Join-Path $b8Dir 'dist/assets/extra.txt'))) { throw "Test 24 failed: clean:false build no longer overlays dist/" }

    $b8Pub2 = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $b8Dir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 24 failed: second publish exited $LASTEXITCODE. Output: $b8Pub2" }
    $b8Zip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $b8Dir 'dist/pub/B8App-1.0.0.zip'))
    try {
        $b8Entries = @($b8Zip.Entries | ForEach-Object { $_.FullName })
    } finally {
        $b8Zip.Dispose()
    }
    if ($b8Entries -contains 'assets/extra.txt') { throw "Test 24 failed: deleted asset still shipped in the zip: $($b8Entries -join ', ')" }
    if ($b8Entries -notcontains 'assets/keep.txt') { throw "Test 24 failed: declared asset missing from the zip: $($b8Entries -join ', ')" }
    if (@($b8Entries | Where-Object { $_ -like 'pub/*' }).Count -gt 0) { throw "Test 24 failed: an earlier publish folder was nested into the zip: $($b8Entries -join ', ')" }
    $b8Meta = Get-Content -LiteralPath (Join-Path $b8Dir 'dist/pub/otter.publish.json') -Raw | ConvertFrom-Json
    if (@($b8Meta.includedFiles) -contains 'assets/extra.txt') { throw "Test 24 failed: includedFiles still lists the deleted asset" }
    Write-Output '  pass  publish packages a clean build even with build.clean:false (no deleted assets, no nested publish output)'
    # RC3-B8 end

    Write-Host ""
    Write-Host "All Otter project publishing tests passed (24/24)." -ForegroundColor Green
    exit 0
}
finally {
    if (Test-Path -LiteralPath $testTmp) {
        Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
