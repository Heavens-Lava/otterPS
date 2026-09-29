using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Project.psm1
. "$PSScriptRoot\TestHost.ps1"

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Otter Project Publishing & Packaging (D118E)" -ForegroundColor Cyan

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d118e_tests_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

# New projects declare no assets (their stylesheet is embedded in the page),
# so give a test project one, to check that publish carries assets along.
function Add-TestDeclaredAsset {
    param([string]$ProjectDir)
    $imagesDir = Join-Path $ProjectDir 'assets/images'
    New-Item -ItemType Directory -Path $imagesDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $imagesDir 'logo.svg') -Value '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"/>' -Encoding UTF8
    $manifestPath = Join-Path $ProjectDir 'otter.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.assets = @('assets/images/logo.svg')
    Set-Content -LiteralPath $manifestPath -Value ($manifest | ConvertTo-Json -Depth 5) -Encoding UTF8
}

try {
    # Test 1: Web publish produces package folder, zip, checksum, and metadata
    $wProj = New-OtterProject -Archetype 'web' -Name 'WebPubApp' -Path $testTmp
    $wDir = $wProj.RootDirectory
    Add-TestDeclaredAsset $wDir
    $wPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $wDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 1 failed: otter publish WebPubApp exited with $LASTEXITCODE. Output: $wPubOut" }
    if (($wPubOut -join "`n") -notmatch 'Publish succeeded') { throw "Test 1 failed: Missing 'Publish succeeded'. Output: $wPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'dist/index.html') -PathType Leaf)) { throw "Test 1 failed: Missing dist/index.html (build first)" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'publish/WebPubApp-0.1.0/index.html') -PathType Leaf)) { throw "Test 1 failed: Missing publish/WebPubApp-0.1.0/index.html" }
    if (-not (Test-Path -LiteralPath (Join-Path $wDir 'publish/WebPubApp-0.1.0/assets/images/logo.svg') -PathType Leaf)) { throw "Test 1 failed: Missing publish/WebPubApp-0.1.0/assets/images/logo.svg" }
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
    Add-TestDeclaredAsset $gDir
    $gPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $gDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 4 failed: otter publish GamePubApp exited with $LASTEXITCODE. Output: $gPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $gDir 'publish/GamePubApp-0.1.0/index.html') -PathType Leaf)) { throw "Test 4 failed: Missing index.html in game package" }
    if (-not (Test-Path -LiteralPath (Join-Path $gDir 'publish/GamePubApp-0.1.0/assets/images/logo.svg') -PathType Leaf)) { throw "Test 4 failed: Missing assets/images/logo.svg in game package" }
    Write-Output '  pass  game publish packages canvas runtime bundle and assets'

    # Test 5: Automation publish maps to runnable task artifact
    $aProj = New-OtterProject -Archetype 'automation' -Name 'AutoPubApp' -Path $testTmp
    $aDir = $aProj.RootDirectory
    $aPubOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') publish $aDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 5 failed: otter publish AutoPubApp exited with $LASTEXITCODE. Output: $aPubOut" }
    if (-not (Test-Path -LiteralPath (Join-Path $aDir 'publish/AutoPubApp-0.1.0/main.ot') -PathType Leaf)) { throw "Test 5 failed: Missing main.ot in auto package" }
    if (-not (Test-Path -LiteralPath (Join-Path $aDir 'publish/AutoPubApp-0.1.0/run.cmd') -PathType Leaf)) { throw "Test 5 failed: Missing run.cmd in auto package" }
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
        if ($entryNames -notcontains 'assets/images/logo.svg') { throw "Test 7 failed: Archive missing assets/images/logo.svg. Entries: $($entryNames -join ', ')" }
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
    if (-not (Test-Path -LiteralPath (Join-Path $extractCleanDir 'assets/images/logo.svg') -PathType Leaf)) { throw "Test 17 failed: Extracted archive missing assets/images/logo.svg" }
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

    Write-Host ""
    Write-Host "All Otter project publishing tests passed (18/18)." -ForegroundColor Green
    exit 0
}
finally {
    if (Test-Path -LiteralPath $testTmp) {
        Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
