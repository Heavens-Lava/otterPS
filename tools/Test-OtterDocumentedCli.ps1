# tools/Test-OtterDocumentedCli.ps1
#
# Checks what the documentation site's CLI and Projects pages
# (otter-docs/pages/cli.ot, projects.ot) say about the otter command against
# the INSTALLED release payload: it builds the payload, installs it into a
# temporary folder, and runs every documented form through the installed
# launcher (otter.cmd on Windows, otter on macOS and Linux). Each claim is one
# check; every mismatch is reported, not only the first.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/Test-OtterDocumentedCli.ps1
#   pwsh -NoProfile -File tools/Test-OtterDocumentedCli.ps1 [-Archive otter-<version>.zip]

[CmdletBinding()]
param(
    [string]$WorkDirectory,
    [switch]$KeepArtifacts,
    [string]$Archive
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if (-not $WorkDirectory) {
    $WorkDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-doc-cli-' + [Guid]::NewGuid().ToString('N'))
}
$work = [System.IO.Path]::GetFullPath($WorkDirectory)
$hostExe = (Get-Process -Id $PID).Path
$onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
$hostArgs = @(if ($onWindows) { '-NoProfile', '-ExecutionPolicy', 'Bypass' } else { '-NoProfile' })
$launcherName = if ($onWindows) { 'otter.cmd' } else { 'otter' }

$results = [System.Collections.Generic.List[object]]::new()

function Invoke-Otter {
    param([string[]]$Arguments, [string]$InputText)
    # Stderr from the launcher is output to inspect, not an exception
    # (Windows PowerShell 5.1 turns it into one under 'Stop').
    $ErrorActionPreference = 'Continue'
    $launcher = Join-Path $script:installed $launcherName
    if ($PSBoundParameters.ContainsKey('InputText')) {
        $output = $InputText | & $launcher @Arguments 2>&1
    } else {
        $output = & $launcher @Arguments 2>&1
    }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = (($output | ForEach-Object { "$_" }) -join "`n").Trim() }
}

function Test-Claim {
    param([string]$Page, [string]$Claim, [scriptblock]$Check)
    try {
        $detail = & $Check
        $results.Add([pscustomobject]@{ Page = $Page; Claim = $Claim; Pass = $true; Detail = "$detail" })
        Write-Output "  pass  [$Page] $Claim"
    } catch {
        $results.Add([pscustomobject]@{ Page = $Page; Claim = $Claim; Pass = $false; Detail = $_.Exception.Message })
        Write-Output "  FAIL  [$Page] $Claim"
        Write-Output "        $($_.Exception.Message)"
    }
}

function Assert-That {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    New-Item -ItemType Directory -Path $work | Out-Null

    # Build (or take) the archive and install it, as a user would.
    if ($Archive) {
        $zip = [System.IO.Path]::GetFullPath($Archive)
    } else {
        $payloads = Join-Path $work 'payloads'
        & $hostExe @hostArgs -File (Join-Path $PSScriptRoot 'New-OtterDistribution.ps1') -OutputDirectory $payloads -Force | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Distribution build failed.' }
        $zip = Join-Path $payloads "otter-$version.zip"
    }
    $extracted = Join-Path $work 'extracted'
    if ($onWindows) { Expand-Archive -LiteralPath $zip -DestinationPath $extracted }
    else { & unzip -q $zip -d $extracted; if ($LASTEXITCODE -ne 0) { throw 'unzip failed' } }
    $script:installed = Join-Path $work 'installed'
    & $hostExe @hostArgs -File (Join-Path $extracted "otter-$version/Install-Otter.ps1") -Destination $script:installed -Force | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Installation failed.' }

    $play = Join-Path $work 'play'
    New-Item -ItemType Directory -Path $play | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $play 'hello.ot'), "say `"Hello from Otter`"`n")
    # The arguments example exactly as the CLI page shows it.
    [System.IO.File]::WriteAllText((Join-Path $play 'script.ot'), "say `"Arguments received:`" length of arguments`n`neach arg in arguments`n    say `"  Arg:`" arg`n.`n")
    [System.IO.File]::WriteAllText((Join-Path $play 'broken.ot'), "say `"unterminated`n")
    [System.IO.File]::WriteAllText((Join-Path $play 'fails.ot'), "x is 1`nsay x / 0`n")
    [System.IO.File]::WriteAllText((Join-Path $play 'writes.ot'), "write `"touched`" to `"check-side-effect.txt`"`n")
    [System.IO.File]::WriteAllText((Join-Path $play 'app.ot'), "create page into app`ncreate text into hello`nhello has text `"hi`"`nput hello in app`nshow app`n")
    # The web-server page's form: a server resource and a route.
    [System.IO.File]::WriteAllText((Join-Path $play 'server.ot'), "api is a web server`n    port is 4791`n    host is `"localhost`"`n.`n`nwhen api receives GET at `"/`"`n    respond with `"otter-served`"`n.`n")
    Push-Location $play
    try {
        # --- cli.ot -----------------------------------------------------------
        Test-Claim 'cli' 'otter --version shows the version' {
            $r = Invoke-Otter @('--version'); Assert-That ($r.Code -eq 0 -and $r.Text -match [regex]::Escape("Otter $version")) "exit $($r.Code): $($r.Text)"; $r.Text
        }
        Test-Claim 'cli' 'otter help lists every documented command' {
            $r = Invoke-Otter @('help')
            $missing = @(foreach ($c in 'run', 'check', 'test', 'build', 'publish', 'new', 'web', 'serve', 'desktop') { if ($r.Text -notmatch "otter $c\b") { $c } })
            Assert-That ($r.Code -eq 0 -and $missing.Count -eq 0) "not in help: $($missing -join ', ')"
        }
        Test-Claim 'cli' 'otter (no arguments) starts the REPL; exit leaves' {
            $r = Invoke-Otter @() -InputText "say 2 and 2`nexit`n"
            Assert-That ($r.Text -match '(?m)^\s*(otter>\s*)?4\s*$') "REPL output: $($r.Text)"
        }
        Test-Claim 'cli' 'otter run hello.ot and otter hello.ot do the same thing' {
            $a = Invoke-Otter @('run', 'hello.ot'); $b = Invoke-Otter @('hello.ot')
            Assert-That ($a.Code -eq 0 -and $a.Text -eq $b.Text -and $a.Code -eq $b.Code) "run: $($a.Text) | short: $($b.Text)"
        }
        Test-Claim 'cli' 'otter run script.ot deploy staging prints Arguments received: 2, then each argument' {
            $r = Invoke-Otter @('run', 'script.ot', 'deploy', 'staging')
            Assert-That ($r.Code -eq 0 -and $r.Text -match 'Arguments received: 2' -and $r.Text -match 'Arg: deploy' -and $r.Text -match 'Arg: staging') $r.Text
        }
        Test-Claim 'cli' 'otter run script.ot --help shows Otter''s help instead of running the program' {
            $r = Invoke-Otter @('run', 'script.ot', '--help')
            Assert-That ($r.Text -match 'Usage:' -and $r.Text -notmatch 'Arguments received') $r.Text
        }
        Test-Claim 'cli' 'double-dash options such as --name=bob and --port 8080 are passed through' {
            $r = Invoke-Otter @('run', 'script.ot', '--name=bob', '--port', '8080')
            Assert-That ($r.Text -match 'Arguments received: 3' -and $r.Text -match 'Arg: --name=bob' -and $r.Text -match 'Arg: --port' -and $r.Text -match 'Arg: 8080') $r.Text
        }
        Test-Claim 'cli' 'a short flag such as -p stops with an error that the parameter name is ambiguous' {
            $r = Invoke-Otter @('run', 'script.ot', '-p')
            Assert-That ($r.Code -ne 0 -and $r.Text -match 'ambiguous') "exit $($r.Code): $($r.Text)"
        }
        # D14: no PowerShell error text reaches a user, even for a bad flag.
        Test-Claim 'cli' 'the ambiguous-flag error is an Otter message, not raw PowerShell error text' {
            $r = Invoke-Otter @('run', 'script.ot', '-p')
            Assert-That ($r.Text -notmatch 'CategoryInfo|FullyQualifiedErrorId|ParentContainsErrorRecordException') 'raw PowerShell error text reaches the user'
        }
        Test-Claim 'cli' 'otter check validates without running: exit 0, and no files are touched' {
            $r = Invoke-Otter @('check', 'writes.ot')
            Assert-That ($r.Code -eq 0 -and -not (Test-Path -LiteralPath 'check-side-effect.txt')) "exit $($r.Code); file exists: $(Test-Path 'check-side-effect.txt')"
        }
        Test-Claim 'cli' 'exit code 1: unknown command or file not found' {
            $r = Invoke-Otter @('run', 'no-such-file.ot')
            Assert-That ($r.Code -eq 1) "exit $($r.Code): $($r.Text)"
        }
        Test-Claim 'cli' 'exit code 1: wrong extension' {
            [System.IO.File]::WriteAllText((Join-Path $play 'notes.txt'), "say 1`n")
            $r = Invoke-Otter @('run', 'notes.txt')
            Assert-That ($r.Code -eq 1) "exit $($r.Code): $($r.Text)"
        }
        Test-Claim 'cli' 'exit code 2: the source does not parse' {
            $r = Invoke-Otter @('run', 'broken.ot'); Assert-That ($r.Code -eq 2) "exit $($r.Code): $($r.Text)"
        }
        Test-Claim 'cli' 'exit code 3: a well-formed program failed while running' {
            $r = Invoke-Otter @('run', 'fails.ot'); Assert-That ($r.Code -eq 3) "exit $($r.Code): $($r.Text)"
        }
        Test-Claim 'cli' 'otter web app.ot -NoOpen compiles only and writes app.html next to the source' {
            $r = Invoke-Otter @('web', 'app.ot', '-NoOpen')
            Assert-That ($r.Code -eq 0 -and (Test-Path -LiteralPath (Join-Path $play 'app.html'))) "exit $($r.Code): $($r.Text)"
        }
        Test-Claim 'cli' 'otter serve <file.ot> runs a web server program' {
            $launcher = Join-Path $script:installed $launcherName
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            if ($onWindows) { $psi.FileName = $env:ComSpec; $psi.Arguments = "/c `"`"$launcher`" serve server.ot`"" }
            else { $psi.FileName = $launcher; $psi.Arguments = 'serve server.ot' }
            $psi.WorkingDirectory = $play; $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            try {
                $body = $null
                for ($i = 0; $i -lt 60 -and $null -eq $body; $i++) {
                    Start-Sleep -Milliseconds 500
                    try { $body = (Invoke-WebRequest -Uri 'http://localhost:4791/' -UseBasicParsing -TimeoutSec 2).Content } catch { }
                }
                Assert-That ("$body" -match 'otter-served') "no response from the server (got '$body')"
            }
            finally {
                if (-not $proc.HasExited) {
                    if ($onWindows) { & taskkill /PID $proc.Id /T /F | Out-Null } else { $proc.Kill() }
                }
            }
        }

        # --- projects.ot -----------------------------------------------------
        Test-Claim 'projects' 'otter new console my-app creates main.ot, otter.json, src/, assets/ and tests/app_test.ot' {
            $r = Invoke-Otter @('new', 'console', 'my-app')
            $missing = @(foreach ($p in 'main.ot', 'otter.json', 'src', 'assets', 'tests/app_test.ot') { if (-not (Test-Path -LiteralPath (Join-Path $play "my-app/$p"))) { $p } })
            Assert-That ($r.Code -eq 0 -and $missing.Count -eq 0) "exit $($r.Code); missing: $($missing -join ', ')"
        }
        Push-Location (Join-Path $play 'my-app')
        try {
            foreach ($cmd in 'check', 'test', 'run', 'build', 'publish') {
                Test-Claim 'projects' "otter $cmd . works from inside a console project" ({
                    $r = Invoke-Otter @($cmd, '.'); Assert-That ($r.Code -eq 0) "exit $($r.Code): $($r.Text)"
                }.GetNewClosure())
            }
            Test-Claim 'projects' 'otter publish writes publish/<name>-<version>.zip with a SHA-256 checksum' {
                Assert-That ((Test-Path -LiteralPath 'publish/my-app-0.1.0.zip') -and (Test-Path -LiteralPath 'publish/my-app-0.1.0.zip.sha256')) ((Get-ChildItem -LiteralPath 'publish' -ErrorAction SilentlyContinue | ForEach-Object Name) -join ', ')
            }
        }
        finally { Pop-Location }
        foreach ($type in 'desktop', 'web', 'automation', 'game') {
            Test-Claim 'projects' "otter new $type creates a project that otter check accepts" ({
                $name = "$type-app"
                $r = Invoke-Otter @('new', $type, $name); Assert-That ($r.Code -eq 0) "new: exit $($r.Code): $($r.Text)"
                $c = Invoke-Otter @('check', $name); Assert-That ($c.Code -eq 0) "check: exit $($c.Code): $($c.Text)"
            }.GetNewClosure())
        }
        Test-Claim 'projects' 'otter web . works for a web project' {
            Push-Location (Join-Path $play 'web-app')
            try { $r = Invoke-Otter @('web', '.', '-NoOpen'); Assert-That ($r.Code -eq 0) "exit $($r.Code): $($r.Text)" }
            finally { Pop-Location }
        }
    }
    finally { Pop-Location }

    $failed = @($results | Where-Object { -not $_.Pass })
    Write-Output ''
    Write-Output "Documented CLI checks on PowerShell $($PSVersionTable.PSVersion): $($results.Count - $failed.Count) passed, $($failed.Count) failed."
    if ($failed.Count -gt 0) { exit 1 }
}
finally {
    if (-not $KeepArtifacts -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
