using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1
using module ..\src\Otter.Interpreter.psm1

# HostPortability.Tests.ps1
#
# Otter values must be the same on Windows PowerShell 5.1 and PowerShell 7.
#
# The defect this guards against (D120, found by the PowerShell 7 CI matrix):
# a PowerShell function that emits ONE value with `Write-Output -NoEnumerate`
# hands its caller that value itself on 5.1, but on PowerShell 7 (7.6.6
# measured) the caller receives a List[object] containing it. The interpreter
# used that form at every value boundary, so on PowerShell 7 a thing arrived
# as "a list", a returned number as a one-item list, and "gone" as a list
# holding nothing. The runtime now uses `return , value`, which behaves the
# same on both hosts.
#
# This file must itself stay portable: no powershell.exe, cmd or $env:TEMP.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Host portability (Windows PowerShell 5.1 and PowerShell 7)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'
$script:HostExe = (Get-Process -Id $PID).Path
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_portability_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null

function Invoke-OtterFileRun {
    param([string]$Source)
    $path = Join-Path $script:Tmp ('p' + [Guid]::NewGuid().ToString('N') + '.ot')
    [System.IO.File]::WriteAllText($path, $Source, [System.Text.UTF8Encoding]::new($false))
    $output = & $script:HostExe -NoProfile -File $script:OtterPs1 run $path 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Lines = @($output | ForEach-Object { $_.ToString() } | Where-Object { $_ -ne '' }) }
}

# Evaluates one Otter expression in a fresh environment and returns the raw runtime value.
function Get-OtterExpressionValue {
    param([string]$Setup, [string]$Expression)
    $source = $Setup + "`nresultValue is " + $Expression + "`n"
    $ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source)
    $environment = New-OtterEnvironment
    Set-OtterOutputWriter -Writer { param($t) }
    try { Invoke-OtterProgram -Program $ast -Environment $environment } finally { Set-OtterOutputWriter -Writer $null }
    return , $environment.Get('resultValue')
}

function Get-TypeLabel { param($Value) if ($null -eq $Value) { return 'null' }; return $Value.GetType().Name }

try {
    Test-Otter "minimal reproducer: reading a property of a thing (host: PowerShell $($PSVersionTable.PSVersion))" {
        $r = Invoke-OtterFileRun "person has name `"Jeff`"`nsay name of person`n"
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('Jeff') -Actual $r.Lines
    }

    Test-Otter 'minimal reproducer: a returned number is still a number' {
        $r = Invoke-OtterFileRun "to ten`n    return 10`n.`n`nanswer is ten`nsay answer plus 1`n"
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('11') -Actual $r.Lines
    }

    Test-Otter 'find that matches nothing gives gone, not a list holding nothing' {
        $r = Invoke-OtterFileRun "games are`n    `"Zelda`"`n    `"Mario`"`n.`nfind game in games where game starts with `"Q`" into found`nif found is gone`n    say `"none`"`n.`n"
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('none') -Actual $r.Lines
    }

    $setup = @'
thing1 has color "blue"
many are
    1
    2
single are
    "only"
nothing are empty
nested are
    many
to identity value
    return value
.
'@
    $cases = @(
        @{ Name = 'a thing read from a variable'; Expr = 'thing1'; Type = 'OtterObject' }
        @{ Name = 'a thing returned from a function'; Expr = 'identity thing1'; Type = 'OtterObject' }
        @{ Name = 'a property read'; Expr = 'color of thing1'; Type = 'String' }
        @{ Name = 'a number returned from a function'; Expr = 'identity 10'; Type = 'Double' }
        @{ Name = 'a two-item list'; Expr = 'many'; Type = 'List`1'; Count = 2 }
        @{ Name = 'a two-item list returned from a function'; Expr = 'identity many'; Type = 'List`1'; Count = 2 }
        @{ Name = 'a one-item list (must not collapse to its item)'; Expr = 'single'; Type = 'List`1'; Count = 1 }
        @{ Name = 'an empty list'; Expr = 'nothing'; Type = 'List`1'; Count = 0 }
        @{ Name = 'a nested list (must not flatten)'; Expr = 'nested'; Type = 'List`1'; Count = 1 }
        @{ Name = 'first of a list'; Expr = 'first of many'; Type = 'Int32' }
        @{ Name = 'first of an empty list is gone'; Expr = 'first of nothing'; Type = 'null' }
    )
    foreach ($case in $cases) {
        $caseName = $case.Name; $caseExpr = $case.Expr; $caseType = $case.Type; $caseCount = $case['Count']
        Test-Otter "value boundary keeps its type: $caseName" ({
            $value = Get-OtterExpressionValue -Setup $setup -Expression $caseExpr
            $label = Get-TypeLabel $value
            if ($caseType -eq 'Int32') {
                Assert-True ($label -in @('Int32', 'Double')) "expected a plain number, got $label"
            } else {
                Assert-AreEqual -Expected $caseType -Actual $label
            }
            if ($null -ne $caseCount) { Assert-AreEqual -Expected $caseCount -Actual $value.Count }
        }.GetNewClosure())
    }

    Test-Otter 'an atomic write to a read-only file fails the same way on every host' {
        # Windows refuses to replace a read-only file; Linux/macOS rename would allow it.
        $target = Join-Path $script:Tmp 'locked.txt'
        [System.IO.File]::WriteAllText($target, 'original')
        $info = [System.IO.FileInfo]::new($target); $info.IsReadOnly = $true
        try {
            $otterPath = $target.Replace([string][char]92, '/')
            $r = Invoke-OtterFileRun "write `"changed`" to `"$otterPath`" atomically`nsay `"should not print`"`n"
            Assert-AreEqual -Expected 3 -Actual $r.ExitCode
            Assert-True (($r.Lines -join ' ') -match 'The file is read-only') "expected the read-only diagnostic, got: $($r.Lines -join ' | ')"
        } finally { $info.IsReadOnly = $false }
        Assert-AreEqual -Expected 'original' -Actual ([System.IO.File]::ReadAllText($target))
    }

    Test-Otter 'published artifact names are sanitized identically on every host' {
        Import-Module (Join-Path $script:RepoRoot 'src/Otter.Project.psm1') -Force
        Assert-AreEqual -Expected 'My-Special-App-2026' -Actual (Get-OtterSafeFileName 'My-Special:App-*2026*')
        Assert-AreEqual -Expected 'a-b-c-d' -Actual (Get-OtterSafeFileName ('a/b' + [char]92 + 'c<d>'))
    }

    # M1: module paths are case-sensitive on every host, including Windows and
    # macOS whose file systems would otherwise accept a mismatch.
    $moduleDir = Join-Path $script:Tmp 'modcase'
    New-Item -ItemType Directory -Path (Join-Path $moduleDir 'Helpers') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $moduleDir 'Utils.ot'), "say `"from Utils`"`n")
    [System.IO.File]::WriteAllText((Join-Path $moduleDir 'Helpers/Tool.ot'), "say `"from Tool`"`n")

    function Invoke-OtterModuleRun {
        param([string]$Name, [string]$Source)
        $path = Join-Path $moduleDir $Name
        [System.IO.File]::WriteAllText($path, $Source, [System.Text.UTF8Encoding]::new($false))
        $output = & $script:HostExe -NoProfile -File $script:OtterPs1 run $path 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (($output | ForEach-Object { $_.ToString() }) -join "`n") }
    }

    Test-Otter 'use "Utils.ot" succeeds when the file is Utils.ot' {
        $r = Invoke-OtterModuleRun 'exact.ot' "use `"Utils.ot`"`nuse `"Helpers/Tool.ot`"`n"
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-True ($r.Text -match 'from Utils' -and $r.Text -match 'from Tool') "expected both imports to run, got: $($r.Text)"
    }

    Test-Otter 'use "utils.ot" fails when only Utils.ot exists, on every host' {
        $r = Invoke-OtterModuleRun 'wrongfile.ot' "use `"utils.ot`"`n"
        Assert-AreEqual -Expected 2 -Actual $r.ExitCode
        Assert-True ($r.Text -match 'The file is named "Utils.ot", but this use says "utils.ot"') "expected the case diagnostic, got: $($r.Text)"
        Assert-False ($r.Text -match 'from Utils') 'the mismatched import must not run'
    }

    Test-Otter 'use "helpers/Tool.ot" fails when the folder is Helpers, on every host' {
        $r = Invoke-OtterModuleRun 'wrongdir.ot' "use `"helpers/Tool.ot`"`n"
        Assert-AreEqual -Expected 2 -Actual $r.ExitCode
        Assert-True ($r.Text -match 'The folder is named "Helpers", but this use says "helpers"') "expected the folder case diagnostic, got: $($r.Text)"
    }

    # cmd.exe argument injection ("BatBadBut", CVE-2024-24576 class). A .cmd or
    # .bat script runs as `cmd.exe /d /v:off /s /c "<script> <args>"`, and cmd
    # parses that line itself. ConvertTo-OtterCmdArgument is a pure function,
    # so its quoting is checked here on every host; the real cmd.exe round
    # trip is in CommandDispatch.Tests.ps1 (Windows only).
    $script:Library = Get-Module Otter.Library | Select-Object -First 1
    if ($null -eq $script:Library) { $script:Library = Import-Module (Join-Path $script:RepoRoot 'src/Otter.Library.psm1') -PassThru }

    Test-Otter 'cmd arguments: plain values stay as they are, special ones are quoted' {
        $cases = @(
            @{ In = 'first'; Out = 'first' }
            @{ In = 'C:\tools\build.cmd'; Out = 'C:\tools\build.cmd' }
            @{ In = ''; Out = '""' }
            @{ In = 'foo&echo INJECTED'; Out = '"foo&echo INJECTED"' }
            @{ In = 'foo&calc'; Out = '"foo&calc"' }
            @{ In = 'a|b'; Out = '"a|b"' }
            @{ In = 'a<b'; Out = '"a<b"' }
            @{ In = 'a>b'; Out = '"a>b"' }
            @{ In = 'a^b'; Out = '"a^b"' }
            @{ In = '(x)'; Out = '"(x)"' }
            @{ In = 'a,b'; Out = '"a,b"' }
            @{ In = 'a;b'; Out = '"a;b"' }
            @{ In = 'a=b'; Out = '"a=b"' }
            @{ In = 'hi!'; Out = '"hi!"' }
            @{ In = 'two words'; Out = '"two words"' }
            @{ In = ("tab" + [char]9 + "here"); Out = ('"tab' + [char]9 + 'here"') }
            @{ In = 'C:\R&D\x.cmd'; Out = '"C:\R&D\x.cmd"' }
            @{ In = 'C:\Program Files (x86)\x.cmd'; Out = '"C:\Program Files (x86)\x.cmd"' }
        )
        foreach ($case in $cases) {
            $caseIn = $case.In
            $actual = & $script:Library { param($a) ConvertTo-OtterCmdArgument -Argument $a -Line 1 } $caseIn
            Assert-AreEqual -Expected $case.Out -Actual $actual -Message "input [$caseIn]"
        }
    }

    Test-Otter 'cmd arguments: quote, percent, CR, LF and NUL are refused' {
        $refused = @('a"b', '"', '100%', '%PATH%', ('a' + [char]13 + 'b'), ('a' + [char]10 + 'echo x'), ('a' + [char]0 + 'b'))
        foreach ($value in $refused) {
            $caseValue = $value
            Assert-OtterFails -Containing 'safely to a .cmd or .bat script' -Body {
                & $script:Library { param($a) ConvertTo-OtterCmdArgument -Argument $a -Line 1 } $caseValue
            }
        }
    }

    # ssh option injection: `run command "..." over ssh to "<host>"` builds an
    # ssh command line, so a host starting with '-' would be read by ssh as an
    # option (-oProxyCommand runs a LOCAL command). The refusal happens before
    # any ssh process is looked up or started, so no ssh is needed here.
    Test-Otter 'ssh: a host starting with - is refused before ssh runs' {
        $r = Invoke-OtterFileRun "try`n    run command `"whoami`" over ssh to `"-oProxyCommand=echo`" into res`n    say `"UNEXPECTED_SUCCESS`"`notherwise into err`n    say `"CAUGHT:`" err`n.`n"
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        $text = $r.Lines -join ' '
        Assert-True ($text -match 'CAUGHT:.*cannot use "-oProxyCommand=echo" as an ssh host') "expected the ssh host refusal, got: $text"
        Assert-False ($text -match 'UNEXPECTED_SUCCESS') 'the ssh command must not run'
    }

    Test-Otter 'ssh: a host with whitespace, quotes or control characters is refused' {
        foreach ($badHost in @('-oProxyCommand=calc.exe user@example', 'user@example -oProxyCommand=x', "user'@example", 'user"@example', ('user@example' + [char]10), '')) {
            $caseHost = $badHost
            Assert-OtterFails -Containing 'as an ssh host' -Body {
                & $script:Library { param($h) Invoke-OtterSshCommand -Command 'whoami' -HostName $h -Line 1 } $caseHost
            }
        }
    }

    # ---------------------------------------------------------------
    # RC3 CLI robustness (B11, B12, B14). All run the real otter.ps1 in a
    # child process, from a scratch folder under $script:Tmp.
    # ---------------------------------------------------------------

    # Text that means a raw PowerShell error or an internal failure reached
    # the user instead of an Otter sentence.
    $script:RawErrorMarkers = @('Resolve-Path:', 'Get-Content:', 'Set-Content:', 'Start-Process:', 'bug in Otter', 'Exception calling', 'Line |')

    function Invoke-OtterCli {
        param([string[]]$Arguments, [string]$Otter = $script:OtterPs1)
        Push-Location -LiteralPath $script:CliWork
        try { $output = & $script:HostExe -NoProfile -File $Otter @Arguments 2>&1 }
        finally { Pop-Location }
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (@($output | ForEach-Object { $_.ToString() }) -join "`n") }
    }

    function Assert-OtterCleanUsageFailure {
        param($Result, [string]$Expected, [string]$Label)
        Assert-AreEqual -Expected 1 -Actual $Result.ExitCode -Message "$Label exit code (output: $($Result.Text))"
        foreach ($marker in $script:RawErrorMarkers) {
            Assert-False ($Result.Text.Contains($marker)) "$Label printed raw error text '$marker': $($Result.Text)"
        }
        if ($Expected) { Assert-True ($Result.Text.Contains($Expected)) "$Label should say '$Expected', got: $($Result.Text)" }
    }

    # Starts otter.ps1 as a background process with redirected output.
    function Start-OtterCliProcess {
        param([string[]]$Arguments, [string]$Otter = $script:OtterPs1, [string]$Name)
        $quoted = @('-NoProfile', '-File', $Otter) + $Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
        $out = Join-Path $script:CliWork "$Name.out.txt"
        $err = Join-Path $script:CliWork "$Name.err.txt"
        $process = Start-Process -FilePath $script:HostExe -ArgumentList $quoted -WorkingDirectory $script:CliWork -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        # Windows PowerShell 5.1: a Start-Process -PassThru object reports an
        # empty ExitCode unless its handle was opened while the process ran.
        $null = $process.Handle
        return [pscustomobject]@{ Process = $process; Out = $out; Err = $err }
    }

    function Get-OtterProcessText {
        param($Started)
        $text = ''
        foreach ($file in @($Started.Out, $Started.Err)) {
            if (-not (Test-Path -LiteralPath $file)) { continue }
            # Share the file: on Windows the redirect target can still be held
            # open briefly after the process is killed; Linux never locks it.
            $stream = [System.IO.FileStream]::new($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
            try { $text += [System.IO.StreamReader]::new($stream).ReadToEnd() } finally { $stream.Dispose() }
        }
        return $text
    }

    $script:CliWork = Join-Path $script:Tmp 'cli'
    New-Item -ItemType Directory -Path $script:CliWork -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $script:CliWork 'hello.ot'), "say `"hi`"`n", [System.Text.UTF8Encoding]::new($false))
    New-Item -ItemType Directory -Path (Join-Path $script:CliWork 'folder.ot') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:CliWork 'emptydir') -Force | Out-Null

    Test-Otter 'B12: a missing file is an Otter message and exit 1 for every command that reads one' {
        foreach ($argv in @(@('missing.ot'), @('run', 'missing.ot'), @('check', 'missing.ot'), @('web', 'missing.ot', '-NoOpen'), @('browse', 'missing.ot', '-NoOpen'), @('desktop', 'missing.ot'), @('serve', 'missing.ot'))) {
            $r = Invoke-OtterCli -Arguments $argv
            Assert-OtterCleanUsageFailure -Result $r -Expected 'I cannot find a file called "missing.ot"' -Label ($argv -join ' ')
        }
    }

    Test-Otter 'B12: a folder where a .ot file is expected is an Otter message and exit 1' {
        foreach ($argv in @(@('folder.ot'), @('run', 'folder.ot'), @('check', 'folder.ot'))) {
            $r = Invoke-OtterCli -Arguments $argv
            Assert-OtterCleanUsageFailure -Result $r -Expected '"folder.ot" is a folder, not an Otter file' -Label ($argv -join ' ')
        }
        foreach ($argv in @(@('web', 'emptydir', '-NoOpen'), @('web', 'folder.ot', '-NoOpen'), @('serve', 'folder.ot'))) {
            $r = Invoke-OtterCli -Arguments $argv
            Assert-OtterCleanUsageFailure -Result $r -Expected 'I cannot find an otter.json manifest' -Label ($argv -join ' ')
        }
    }

    Test-Otter 'B12: an unreadable .ot file is "I could not read", exit 1, for run, check and web' {
        $locked = Join-Path $script:CliWork 'locked.ot'
        [System.IO.File]::WriteAllText($locked, "say `"secret`"`n", [System.Text.UTF8Encoding]::new($false))
        $isWindowsHost = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
        $lock = $null
        try {
            if ($isWindowsHost) {
                # Windows: hold the file open with no sharing, so no other
                # process may read it (the same "cannot read" path as an ACL).
                $lock = [System.IO.File]::Open($locked, 'Open', 'ReadWrite', 'None')
                $expected = 'I could not read "locked.ot"'
            }
            else {
                if ((& id -u) -eq '0') {
                    Write-Host '        skip  unreadable-file case: running as root, which ignores file permissions' -ForegroundColor DarkYellow
                    return
                }
                & chmod 000 $locked
                $expected = 'I could not read "locked.ot": permission denied.'
            }
            foreach ($argv in @(@('run', 'locked.ot'), @('check', 'locked.ot'), @('locked.ot'), @('web', 'locked.ot', '-NoOpen'))) {
                $r = Invoke-OtterCli -Arguments $argv
                Assert-OtterCleanUsageFailure -Result $r -Expected $expected -Label ($argv -join ' ')
                Assert-False ($r.Text.Contains('secret')) "$($argv -join ' ') must not run the program"
            }
        }
        finally {
            if ($lock) { $lock.Dispose() }
            if (-not $isWindowsHost) { & chmod 644 $locked }
        }
    }

    Test-Otter 'B12: web says plainly when no browser can be opened (Linux only: no xdg-open on PATH)' {
        if (-not $IsLinux) {
            Write-Host '        skip  browser-failure case: only reproducible on Linux, where hiding xdg-open makes Start-Process fail' -ForegroundColor DarkYellow
            return
        }
        $emptyBin = Join-Path $script:Tmp 'emptybin'
        New-Item -ItemType Directory -Path $emptyBin -Force | Out-Null
        $savedPath = $env:PATH
        try {
            $env:PATH = $emptyBin
            $r = Invoke-OtterCli -Arguments @('web', 'hello.ot')
        }
        finally { $env:PATH = $savedPath }
        Assert-OtterCleanUsageFailure -Result $r -Expected 'I could not open a browser' -Label 'web hello.ot'
        Assert-True ($r.Text.Contains('compiled to:')) "the page should still be compiled: $($r.Text)"
    }

    Test-Otter 'B14: otter help does not advertise Otter Studio' {
        $r = Invoke-OtterCli -Arguments @('help')
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-False ($r.Text -match '(?i)studio') "help must not mention studio: $($r.Text)"
    }

    Test-Otter 'B14: otter studio without otter-studio/ (the release layout) prints one sentence and exits 1' {
        # The distribution layout (tools/New-OtterDistribution.ps1): no otter-studio/.
        $dist = Join-Path $script:Tmp 'dist'
        New-Item -ItemType Directory -Path $dist -Force | Out-Null
        foreach ($item in @('otter.ps1', 'Otter.Contract.psm1', 'VERSION')) {
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot $item) -Destination $dist
        }
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'src') -Destination $dist -Recurse
        $started = Start-OtterCliProcess -Arguments @('studio') -Otter (Join-Path $dist 'otter.ps1') -Name 'studio'
        if (-not $started.Process.WaitForExit(60000)) {
            try { $started.Process.Kill() } catch { }
            throw "otter studio did not exit within 60 seconds: $(Get-OtterProcessText $started)"
        }
        $started.Process.WaitForExit()
        $r = [pscustomobject]@{ ExitCode = $started.Process.ExitCode; Text = (Get-OtterProcessText $started) }
        Assert-OtterCleanUsageFailure -Result $r -Expected 'Otter Studio is not part of this Otter release.' -Label 'studio'
        Assert-False ($r.Text.Contains('Exception')) "studio printed an exception: $($r.Text)"
    }

    Test-Otter 'B11: otter serve survives an aborted request, refuses an oversized body, and keeps serving' {
        $serverSource = "api is a web server`n    port is 8080`n    host is `"localhost`"`n.`n`nwhen api receives GET at `"/health`"`n    respond with `"OK`"`n.`n`nwhen api receives POST at `"/health`"`n    respond with `"posted`"`n.`n`nstart api`n"
        [System.IO.File]::WriteAllText((Join-Path $script:CliWork 'server.ot'), $serverSource, [System.Text.UTF8Encoding]::new($false))
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()

        $started = Start-OtterCliProcess -Arguments @('serve', 'server.ot', '-Port', [string]$port) -Name 'serve'
        try {
            $deadline = (Get-Date).AddSeconds(60)
            $up = $false
            while (-not $up -and (Get-Date) -lt $deadline -and -not $started.Process.HasExited) {
                try { $c = [System.Net.Sockets.TcpClient]::new('localhost', $port); $c.Close(); $up = $true }
                catch { Start-Sleep -Milliseconds 250 }
            }
            Assert-True $up "the server never started listening: $(Get-OtterProcessText $started)"

            # 1. Declare a 100000-byte body, send 3 bytes, disconnect.
            $client = [System.Net.Sockets.TcpClient]::new('localhost', $port)
            $stream = $client.GetStream()
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("POST /health HTTP/1.1`r`nHost: localhost`r`nContent-Length: 100000`r`n`r`nabc")
            $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
            Start-Sleep -Milliseconds 300
            $client.Close()
            Start-Sleep -Milliseconds 700

            # 2. A normal request still succeeds.
            $web = [System.Net.WebClient]::new()
            $body = $null
            try { $body = $web.DownloadString("http://localhost:$port/health") }
            catch { throw "the server stopped after an aborted request: $($_.Exception.Message) / $(Get-OtterProcessText $started)" }
            Assert-AreEqual -Expected 'OK' -Actual $body

            # 3. A body over the 10 MB limit is refused with 413, unread.
            $client = [System.Net.Sockets.TcpClient]::new('localhost', $port)
            $stream = $client.GetStream()
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("POST /health HTTP/1.1`r`nHost: localhost`r`nContent-Length: 20000000`r`n`r`n")
            $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
            $stream.ReadTimeout = 10000
            $statusLine = [System.IO.StreamReader]::new($stream).ReadLine()
            $client.Close()
            Assert-True ($statusLine -match '^HTTP/1\.[01] 413') "expected 413 for an oversized body, got: $statusLine"

            # 4. And the server is still up afterwards.
            Assert-AreEqual -Expected 'OK' -Actual $web.DownloadString("http://localhost:$port/health")
            Assert-False $started.Process.HasExited "the server exited: $(Get-OtterProcessText $started)"
        }
        finally {
            if (-not $started.Process.HasExited) { try { $started.Process.Kill() } catch { } }
            $started.Process.WaitForExit(10000) | Out-Null
        }
        $text = Get-OtterProcessText $started
        Assert-True ($text.Contains('could not be completed and was skipped')) "expected one Otter log line for the aborted request: $text"
        Assert-False ($text.Contains('Exception calling')) "raw exception text in server output: $text"
    }

    Test-Otter 'the runtime modules never return a value with Write-Output -NoEnumerate' {
        $offenders = @()
        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'src') -Filter '*.psm1') {
            $lineNo = 0
            foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
                $lineNo++
                if ($line.TrimStart().StartsWith('#')) { continue }
                if ($line -match 'Write-Output\s+-NoEnumerate') { $offenders += "$($file.Name):$lineNo" }
            }
        }
        Assert-True ($offenders.Count -eq 0) "Write-Output -NoEnumerate wraps values in a List on PowerShell 7; use 'return , value'. Found at: $($offenders -join ', ')"
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
