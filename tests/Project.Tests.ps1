using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Project.psm1
. "$PSScriptRoot\TestHost.ps1"

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "Otter Project System (D118B)" -ForegroundColor Cyan

$testTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_proj_tests_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testTmp -Force | Out-Null

try {
    # Test 1: Find-OtterProjectManifest finds canonical otter.json
    $p1Dir = Join-Path $testTmp 'Proj1'
    New-Item -ItemType Directory -Path $p1Dir -Force | Out-Null
    $p1Json = Join-Path $p1Dir 'otter.json'
    Set-Content -LiteralPath $p1Json -Value '{"name":"p1","entryPoint":"main.ot"}' -Encoding UTF8
    $found1 = Find-OtterProjectManifest -Path $p1Dir
    if ($null -eq $found1) { throw "Test 1 failed: Expected to find otter.json in $p1Dir" }
    if ($found1.ManifestFileName -ne 'otter.json') { throw "Test 1 failed: Expected otter.json, got $($found1.ManifestFileName)" }
    Write-Output '  pass  Find-OtterProjectManifest discovers canonical otter.json in a directory'

    # Test 2: Find-OtterProjectManifest falls back to project.json
    $p2Dir = Join-Path $testTmp 'Proj2'
    New-Item -ItemType Directory -Path $p2Dir -Force | Out-Null
    $p2Json = Join-Path $p2Dir 'project.json'
    Set-Content -LiteralPath $p2Json -Value '{"name":"p2","entryPoint":"main.ot"}' -Encoding UTF8
    $found2 = Find-OtterProjectManifest -Path $p2Dir
    if ($null -eq $found2) { throw "Test 2 failed: Expected to find project.json fallback in $p2Dir" }
    if ($found2.ManifestFileName -ne 'project.json') { throw "Test 2 failed: Expected project.json, got $($found2.ManifestFileName)" }
    Write-Output '  pass  Find-OtterProjectManifest falls back to project.json when otter.json is absent'

    # Test 3: otter.json takes strict precedence when both exist
    $p3Dir = Join-Path $testTmp 'Proj3'
    New-Item -ItemType Directory -Path $p3Dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $p3Dir 'otter.json') -Value '{"name":"p3-canonical","entryPoint":"main.ot"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $p3Dir 'project.json') -Value '{"name":"p3-legacy","entryPoint":"legacy.ot"}' -Encoding UTF8
    $found3 = Find-OtterProjectManifest -Path $p3Dir
    if ($found3.ManifestFileName -ne 'otter.json') { throw "Test 3 failed: Expected otter.json to take precedence over project.json" }
    Write-Output '  pass  otter.json takes strict precedence when both manifests are present'

    # Test 4: Full OtterProject object shape and relative path resolution
    $p4Dir = Join-Path $testTmp 'Proj4'
    $p4Src = Join-Path $p4Dir 'src'
    New-Item -ItemType Directory -Path $p4Src -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $p4Src 'app.ot') -Value 'say "app ready"' -Encoding UTF8
    $p4Manifest = @'
{
  "$schema": "https://otter-lang.org/schema/project-v1.json",
  "name": "my-app",
  "version": "0.1.0",
  "archetype": "desktop",
  "target": "desktop",
  "entryPoint": "src/app.ot",
  "assets": ["assets/icon.png", "styles.css"],
  "build": {
    "outputDir": "dist",
    "clean": true
  },
  "scripts": {
    "start": "otter run src/app.ot"
  }
}
'@
    Set-Content -LiteralPath (Join-Path $p4Dir 'otter.json') -Value $p4Manifest -Encoding UTF8
    $proj4 = Get-OtterProject -Path $p4Dir
    if ($proj4.Name -ne 'my-app') { throw "Test 4 failed: Expected name 'my-app', got $($proj4.Name)" }
    if ($proj4.Version -ne '0.1.0') { throw "Test 4 failed: Expected version '0.1.0', got $($proj4.Version)" }
    if ($proj4.Archetype -ne 'desktop') { throw "Test 4 failed: Expected archetype 'desktop', got $($proj4.Archetype)" }
    if ($proj4.Target -ne 'desktop') { throw "Test 4 failed: Expected target 'desktop', got $($proj4.Target)" }
    if ($proj4.EntryPoint -ne 'src/app.ot') { throw "Test 4 failed: Expected entryPoint 'src/app.ot', got $($proj4.EntryPoint)" }
    $expectedEntry = [System.IO.Path]::GetFullPath((Join-Path $p4Dir 'src/app.ot'))
    if ($proj4.ResolvedEntryPoint -ne $expectedEntry) { throw "Test 4 failed: Entry point did not resolve relative to project root" }
    if ($proj4.Build.OutputDir -ne 'dist') { throw "Test 4 failed: Build outputDir expected 'dist'" }
    if ($proj4.Build.Clean -ne $true) { throw "Test 4 failed: Build clean expected true" }
    if ($proj4.Assets.Count -ne 2) { throw "Test 4 failed: Expected 2 assets, got $($proj4.Assets.Count)" }
    if ($proj4.Scripts['start'] -ne 'otter run src/app.ot') { throw "Test 4 failed: Expected scripts.start" }
    Write-Output '  pass  Get-OtterProject populates full OtterProject structure with relative resolution'

    # Test 5: Validation - property "entryPoint" is required
    $p5Dir = Join-Path $testTmp 'Proj5'
    New-Item -ItemType Directory -Path $p5Dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $p5Dir 'otter.json') -Value '{"name":"p5"}' -Encoding UTF8
    $err5 = $null
    try {
        Get-OtterProject -Path $p5Dir
    } catch [OtterError] {
        $err5 = $_.Exception.Message
    }
    if ($err5 -ne 'otter.json: property "entryPoint" is required.') {
        throw "Test 5 failed: Expected 'otter.json: property `"entryPoint`" is required.', got: '$err5'"
    }
    Write-Output '  pass  validation: missing entryPoint produces `otter.json: property "entryPoint" is required.`'

    # Test 6: Validation - entry point does not exist
    $p6Dir = Join-Path $testTmp 'Proj6'
    New-Item -ItemType Directory -Path $p6Dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $p6Dir 'otter.json') -Value '{"name":"p6","entryPoint":"src/main.ot"}' -Encoding UTF8
    $err6 = $null
    try {
        Get-OtterProject -Path $p6Dir
    } catch [OtterError] {
        $err6 = $_.Exception.Message
    }
    if ($err6 -ne 'otter.json: entry point "src/main.ot" does not exist.') {
        throw "Test 6 failed: Expected 'otter.json: entry point `"src/main.ot`" does not exist.', got: '$err6'"
    }
    Write-Output '  pass  validation: nonexistent entry point produces `otter.json: entry point "src/main.ot" does not exist.`'

    # Test 7: Validation - target not supported
    $p7Dir = Join-Path $testTmp 'Proj7'
    New-Item -ItemType Directory -Path $p7Dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $p7Dir 'main.ot') -Value 'say "hello"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $p7Dir 'otter.json') -Value '{"name":"p7","entryPoint":"main.ot","target":"phone"}' -Encoding UTF8
    $err7 = $null
    try {
        Get-OtterProject -Path $p7Dir
    } catch [OtterError] {
        $err7 = $_.Exception.Message
    }
    if ($err7 -ne 'otter.json: target "phone" is not supported.') {
        throw "Test 7 failed: Expected 'otter.json: target `"phone`" is not supported.', got: '$err7'"
    }
    Write-Output '  pass  validation: unsupported target produces `otter.json: target "phone" is not supported.`'

    # Test 8: Validation - build.outputDir must stay inside project directory
    $p8Dir = Join-Path $testTmp 'Proj8'
    New-Item -ItemType Directory -Path $p8Dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $p8Dir 'main.ot') -Value 'say "hello"' -Encoding UTF8

    # Case 8a: parent directory traversal "../outside"
    Set-Content -LiteralPath (Join-Path $p8Dir 'otter.json') -Value '{"name":"p8","entryPoint":"main.ot","build":{"outputDir":"../outside"}}' -Encoding UTF8
    $err8a = $null
    try { Get-OtterProject -Path $p8Dir } catch [OtterError] { $err8a = $_.Exception.Message }
    if ($err8a -ne 'otter.json: build.outputDir must stay inside the project directory.') {
        throw "Test 8a failed: Expected 'otter.json: build.outputDir must stay inside the project directory.', got: '$err8a'"
    }

    # Case 8b: project root itself "."
    Set-Content -LiteralPath (Join-Path $p8Dir 'otter.json') -Value '{"name":"p8","entryPoint":"main.ot","build":{"outputDir":"."}}' -Encoding UTF8
    $err8b = $null
    try { Get-OtterProject -Path $p8Dir } catch [OtterError] { $err8b = $_.Exception.Message }
    if ($err8b -ne 'otter.json: build.outputDir must stay inside the project directory.') {
        throw "Test 8b failed: Expected 'otter.json: build.outputDir must stay inside the project directory.', got: '$err8b'"
    }
    Write-Output '  pass  validation: outputDir outside project root produces `otter.json: build.outputDir must stay inside the project directory.`'

    # Test 9: CLI execution: otter run ./MyApp
    $appDir = Join-Path $testTmp 'MyApp'
    New-Item -ItemType Directory -Path $appDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $appDir 'main.ot') -Value 'say "MyApp Running"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $appDir 'otter.json') -Value '{"name":"MyApp","entryPoint":"main.ot"}' -Encoding UTF8
    $cliOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') run $appDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 9 failed: CLI exited with code $LASTEXITCODE. Output: $cliOut" }
    if (($cliOut -join "`n") -notmatch 'MyApp Running') { throw "Test 9 failed: Stdout did not contain 'MyApp Running'" }
    Write-Output '  pass  CLI: `otter run ./MyApp` discovers otter.json, resolves entry point, and runs program'

    # Test 10: CLI execution: otter check ./MyApp
    $checkOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') check $appDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 10 failed: CLI exited with code $LASTEXITCODE. Output: $checkOut" }
    if (($checkOut -join "`n") -notmatch 'is valid') { throw "Test 10 failed: Output did not contain 'is valid': $checkOut" }
    Write-Output '  pass  CLI: `otter check ./MyApp` validates project entry point and modules without running'

    # Test 11: CLI execution: otter run . and otter check .
    $prevCwd = Get-Location
    try {
        Set-Location -LiteralPath $appDir
        $dotRunOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') run . 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 11a failed: otter run . exited with code $LASTEXITCODE. Output: $dotRunOut" }
        if (($dotRunOut -join "`n") -notmatch 'MyApp Running') { throw "Test 11a failed: otter run . did not execute MyApp: $dotRunOut" }

        $dotCheckOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') check . 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Test 11b failed: otter check . exited with code $LASTEXITCODE. Output: $dotCheckOut" }
        if (($dotCheckOut -join "`n") -notmatch 'is valid') { throw "Test 11b failed: otter check . did not report valid: $dotCheckOut" }
    } finally {
        Set-Location -LiteralPath $prevCwd
    }
    Write-Output '  pass  CLI: `otter run .` and `otter check .` discover and execute/validate project in current directory'

    # Test 12: CLI invalid manifest produces clean diagnostic and exit code 2
    $badManifestDir = Join-Path $testTmp 'BadManifest'
    New-Item -ItemType Directory -Path $badManifestDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $badManifestDir 'otter.json') -Value '{"name":"bad","entryPoint":"missing.ot"}' -Encoding UTF8
    $badOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') check $badManifestDir 2>&1
    if ($LASTEXITCODE -ne 2) { throw "Test 12 failed: Expected exit code 2 for invalid manifest, got $LASTEXITCODE. Output: $badOut" }
    if (($badOut -join "`n") -notmatch 'otter\.json: entry point "missing\.ot" does not exist\.') {
        throw "Test 12 failed: Output did not match expected diagnostic: $badOut"
    }
    Write-Output '  pass  CLI: invalid manifest fails early with clean diagnostic and exit code 2'

    # Test 13: CLI directory without manifest produces clean diagnostic and exit code 1
    $noManifestDir = Join-Path $testTmp 'EmptyDir'
    New-Item -ItemType Directory -Path $noManifestDir -Force | Out-Null
    $noManOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') run $noManifestDir 2>&1
    if ($LASTEXITCODE -ne 1) { throw "Test 13 failed: Expected exit code 1 for missing manifest in directory, got $LASTEXITCODE. Output: $noManOut" }
    if (($noManOut -join "`n") -notmatch 'cannot find an otter\.json manifest') {
        throw "Test 13 failed: Expected cannot find otter.json manifest, got: $noManOut"
    }
    Write-Output '  pass  CLI: directory without manifest produces `Otter: I cannot find an otter.json manifest` (exit 1)'

    # Test 14: Project with multi-file modules resolves relative imports correctly
    $modAppDir = Join-Path $testTmp 'ModApp'
    $modSrc = Join-Path $modAppDir 'src'
    New-Item -ItemType Directory -Path $modSrc -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $modSrc 'helpers.ot') -Value 'greeting is "Hello from module"' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $modSrc 'main.ot') -Value "use `"helpers.ot`"`nsay greeting" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $modAppDir 'otter.json') -Value '{"name":"ModApp","entryPoint":"src/main.ot"}' -Encoding UTF8
    $modRunOut = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') run $modAppDir 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Test 14 failed: otter run $modAppDir exited with code $LASTEXITCODE. Output: $modRunOut" }
    if (($modRunOut -join "`n") -notmatch 'Hello from module') { throw "Test 14 failed: Expected 'Hello from module', got: $modRunOut" }
    Write-Output '  pass  CLI: project entryPoint with imported modules resolves relative to source files'

    # Test 15 (RC3 B5): wrong-typed manifest fields are OtterErrors naming the
    # field and the expected type. "build": null used to crash with the raw
    # PowerShell error "Cannot index into a null array." (plus otter.ps1's
    # path and source line); other wrong types were silently coerced/ignored.
    # RC3-B5 begin
    $b5Dir = Join-Path $testTmp 'B5App'
    New-Item -ItemType Directory -Path $b5Dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $b5Dir 'main.ot') -Value 'say "b5"' -Encoding UTF8
    $b5Cases = @(
        @{ Json = '{"name":"b5","entryPoint":"main.ot","build":null}';              Field = 'build';       Kind = 'null' }
        @{ Json = '{"name":"b5","entryPoint":"main.ot","build":"dist"}';            Field = 'build';       Kind = 'text' }
        @{ Json = '{"name":"b5","entryPoint":"main.ot","build":{"clean":"false"}}'; Field = 'build.clean'; Kind = 'text' }
        @{ Json = '{"name":"b5","entryPoint":"main.ot","publish":null}';            Field = 'publish';     Kind = 'null' }
        @{ Json = '{"name":"b5","entryPoint":"main.ot","publish":["x"]}';           Field = 'publish';     Kind = 'a list' }
        @{ Json = '{"name":"b5","entryPoint":"main.ot","assets":null}';             Field = 'assets';      Kind = 'null' }
        @{ Json = '{"name":"b5","entryPoint":"main.ot","assets":5}';                Field = 'assets';      Kind = 'a number' }
        @{ Json = '{"name":"b5","entryPoint":"main.ot","assets":"main.ot"}';        Field = 'assets';      Kind = 'text' }
        @{ Json = '{"name":"b5","entryPoint":"main.ot","assets":[{"a":1}]}';        Field = 'assets[0]';   Kind = 'an object' }
        @{ Json = '{"name":"b5","entryPoint":null}';                                Field = 'entryPoint';  Kind = 'null' }
        @{ Json = '{"name":"b5","entryPoint":5}';                                   Field = 'entryPoint';  Kind = 'a number' }
        @{ Json = '{"name":"b5","entryPoint":["main.ot"]}';                         Field = 'entryPoint';  Kind = 'a list' }
        @{ Json = '{"name":null,"entryPoint":"main.ot"}';                           Field = 'name';        Kind = 'null' }
        @{ Json = '{"name":42,"entryPoint":"main.ot"}';                             Field = 'name';        Kind = 'a number' }
        @{ Json = '{"name":{"x":1},"entryPoint":"main.ot"}';                        Field = 'name';        Kind = 'an object' }
        @{ Json = '{"name":"b5","version":1.10,"entryPoint":"main.ot"}';            Field = 'version';     Kind = 'a number' }
        @{ Json = '{"name":"b5","entryPoint":"main.ot","scripts":["a"]}';           Field = 'scripts';     Kind = 'a list' }
    )
    foreach ($b5Case in $b5Cases) {
        Set-Content -LiteralPath (Join-Path $b5Dir 'otter.json') -Value $b5Case.Json -Encoding UTF8
        $b5Threw = $false
        try {
            Get-OtterProject -Path $b5Dir | Out-Null
        } catch [OtterError] {
            $b5Threw = $true
            $b5Expected = 'otter.json: property "' + $b5Case.Field + '" must be '
            if (-not $_.Exception.Message.StartsWith($b5Expected) -or -not $_.Exception.Message.EndsWith("but it is $($b5Case.Kind).")) {
                throw "Test 15 failed: $($b5Case.Json) gave an unexpected message: $($_.Exception.Message)"
            }
        } catch {
            throw "Test 15 failed: $($b5Case.Json) raised a raw PowerShell error instead of an OtterError: $($_.Exception.Message)"
        }
        if (-not $b5Threw) { throw "Test 15 failed: $($b5Case.Json) was accepted" }
    }

    # Through the CLI: build/publish exit 1 and run/check exit 2 with the
    # Otter message, never a PowerShell error record, and nothing is written.
    Set-Content -LiteralPath (Join-Path $b5Dir 'otter.json') -Value '{"name":"b5","version":"1.0.0","entryPoint":"main.ot","build":null}' -Encoding UTF8
    foreach ($b5Command in @('build', 'publish', 'run', 'check')) {
        $b5Out = & $script:OtterHostExe @script:OtterHostArgs -File (Join-Path $repoRoot 'otter.ps1') $b5Command $b5Dir 2>&1
        $b5Code = $LASTEXITCODE
        $b5Text = $b5Out -join "`n"
        $b5ExpectedCode = if ($b5Command -in @('build', 'publish')) { 1 } else { 2 }
        if ($b5Code -ne $b5ExpectedCode) { throw "Test 15 failed: otter $b5Command with build:null exited $b5Code, expected $b5ExpectedCode. Output: $b5Text" }
        if ($b5Text -notmatch 'otter\.json: property "build" must be an object') { throw "Test 15 failed: otter $b5Command did not name the field. Output: $b5Text" }
        if ($b5Text -match 'Cannot index|otter\.ps1:\d+|Get-OtterProject:') { throw "Test 15 failed: otter $b5Command leaked a PowerShell error. Output: $b5Text" }
    }
    foreach ($b5Written in @('dist', 'publish')) {
        if (Test-Path -LiteralPath (Join-Path $b5Dir $b5Written)) { throw "Test 15 failed: a bad manifest still wrote $b5Written/" }
    }
    Write-Output '  pass  wrong-typed build, publish, assets, entryPoint, name, version, scripts give an OtterError naming the field'
    # RC3-B5 end

} finally {
    Remove-Item -LiteralPath $testTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "`nAll Otter project system tests passed (15/15)."
