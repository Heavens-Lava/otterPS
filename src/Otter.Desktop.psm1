using module ..\Otter.Contract.psm1
using module .\Otter.Compiler.JavaScript.psm1
using module .\Otter.Module.psm1
using module .\Otter.Web.psm1

# Otter.Desktop.psm1 - Native Desktop Application Host & Terminal Bridge for Otter
#
# D60 Desktop Host Architecture:
# 1. Launches compiled Otter Web/CSS/JS applications inside dedicated desktop WebView windows.
# 2. Backs interactive Terminal components (terminal.ot) with real OS process execution:
#    - Windows: ConPTY & System.Diagnostics.Process UTF-8 streams
#    - Linux:   PTY (forkpty / openpty)
#    - macOS:   PTY (forkpty / openpty)
#    bridged via host-neutral local loopback IPC (http://127.0.0.1:<port>).

class OtterTerminalBridgeSession {
    [System.Net.HttpListener]$Listener
    [int]$Port
    [bool]$IsRunning
    [string]$Cwd
    [string]$AuthToken
    [System.Collections.Generic.List[string]]$AllowedOrigins
    [hashtable]$ActiveShell
    [System.IAsyncResult]$PendingAsyncResult
    [System.DateTime]$StartTimeUtc

    # D62: durable session lifetime via page heartbeat, not the launcher
    # process's PID (Chromium's launcher/browser/renderer process split
    # makes PID-matching fundamentally unreliable - confirmed directly:
    # `Start-Process`'s returned PID for an Edge/Chrome `--app=` launch
    # exits within about a second while the real browser window keeps
    # running under a separate PID). LastHeartbeatUtc starts at UtcNow
    # so a freshly-created session is considered alive immediately,
    # covering the gap between bridge creation and the page's first
    # heartbeat POST.
    [System.DateTime]$LastHeartbeatUtc
    [bool]$HasReceivedHeartbeat
    [int]$HeartbeatGraceMs = 8000
    [int]$StartupGraceMs = 20000

    OtterTerminalBridgeSession([System.Net.HttpListener]$listener, [int]$port, [string]$cwd, [string]$authToken) {
        $this.Listener = $listener
        $this.Port = $port
        $this.IsRunning = $true
        $this.Cwd = $cwd
        $this.AuthToken = $authToken
        $this.AllowedOrigins = [System.Collections.Generic.List[string]]::new()
        $this.AllowedOrigins.Add("http://127.0.0.1:$port")
        $this.AllowedOrigins.Add("http://localhost:$port")
        $this.AllowedOrigins.Add("null")
        $this.ActiveShell = $null
        $this.PendingAsyncResult = $null
        $this.StartTimeUtc = [System.DateTime]::UtcNow
        $this.LastHeartbeatUtc = [System.DateTime]::UtcNow
        $this.HasReceivedHeartbeat = $false
    }

    # D62: before the first real heartbeat arrives, tolerate up to
    # StartupGraceMs of silence (browser launch + page load + script
    # init latency); once at least one heartbeat has arrived, tolerate
    # up to HeartbeatGraceMs between beats (a few missed ticks from tab
    # throttling or a busy event loop, not an immediate teardown on one
    # delayed beat). UTC throughout - no local-timezone comparison.
    [bool] IsSessionAlive() {
        $graceMs = if ($this.HasReceivedHeartbeat) { $this.HeartbeatGraceMs } else { $this.StartupGraceMs }
        $elapsedMs = ([System.DateTime]::UtcNow - $this.LastHeartbeatUtc).TotalMilliseconds
        return $elapsedMs -le $graceMs
    }

    [bool] HandleNextRequest([int]$TimeoutMs = 0) {
        if (-not $this.IsRunning -or -not $this.Listener.IsListening) {
            return $false
        }

        $context = $null
        if ($TimeoutMs -le 0) {
            try {
                $context = $this.Listener.GetContext()
            } catch {
                return $false
            }
        } else {
            try {
                if ($null -eq $this.PendingAsyncResult) {
                    $this.PendingAsyncResult = $this.Listener.BeginGetContext($null, $null)
                }
                if (-not $this.PendingAsyncResult.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                    return $false
                }
                $context = $this.Listener.EndGetContext($this.PendingAsyncResult)
                $this.PendingAsyncResult = $null
            } catch {
                $this.PendingAsyncResult = $null
                return $false
            }
        }

        $req = $context.Request
        $res = $context.Response

        # Security Check 1: Origin Validation (Reject Malicious Cross-Origin Callers)
        $originHeader = $req.Headers["Origin"]
        $originAllowed = $true
        if (-not [string]::IsNullOrEmpty($originHeader)) {
            $normOrigin = $originHeader.Trim().ToLowerInvariant()
            $isLoopback = $normOrigin.StartsWith("http://127.0.0.1:") -or $normOrigin.StartsWith("http://localhost:")
            $isExplicitAllowed = ($normOrigin -in $this.AllowedOrigins)
            $originAllowed = ($isLoopback -or $isExplicitAllowed)
        }

        if (-not $originAllowed) {
            $res.StatusCode = 403
            $res.StatusDescription = "Forbidden - Invalid Origin"
            $res.ContentType = "application/json; charset=utf-8"
            $errBuf = [System.Text.Encoding]::UTF8.GetBytes('{"error":"Forbidden: cross-origin requests from unauthorized origins are rejected."}')
            $res.ContentLength64 = $errBuf.Length
            $res.OutputStream.Write($errBuf, 0, $errBuf.Length)
            $res.Close()
            return $true
        }

        # If origin is allowed, set precise origin (never wildcard '*')
        if (-not [string]::IsNullOrEmpty($originHeader)) {
            $res.Headers.Add("Access-Control-Allow-Origin", $originHeader)
            $res.Headers.Add("Vary", "Origin")
            $res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            $res.Headers.Add("Access-Control-Allow-Headers", "Content-Type, X-Otter-Token, Authorization")
        }

        # Preflight OPTIONS handler
        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 200
            $res.Close()
            return $true
        }

        # Security Check 2: Cryptographic Token Authentication
        $providedToken = $req.Headers["X-Otter-Token"]
        if ([string]::IsNullOrEmpty($providedToken)) {
            $authHeader = $req.Headers["Authorization"]
            if ($authHeader -and $authHeader.StartsWith("Bearer ", [System.StringComparison]::OrdinalIgnoreCase)) {
                $providedToken = $authHeader.Substring(7).Trim()
            }
        }
        if ([string]::IsNullOrEmpty($providedToken)) {
            $providedToken = $req.QueryString["token"]
        }

        if ([string]::IsNullOrEmpty($providedToken)) {
            $res.StatusCode = 401
            $res.StatusDescription = "Unauthorized - Missing Token"
            $res.ContentType = "application/json; charset=utf-8"
            $errBuf = [System.Text.Encoding]::UTF8.GetBytes('{"error":"Unauthorized: missing session authentication token."}')
            $res.ContentLength64 = $errBuf.Length
            $res.OutputStream.Write($errBuf, 0, $errBuf.Length)
            $res.Close()
            return $true
        }

        if ($providedToken -ne $this.AuthToken) {
            $res.StatusCode = 403
            $res.StatusDescription = "Forbidden - Invalid Token"
            $res.ContentType = "application/json; charset=utf-8"
            $errBuf = [System.Text.Encoding]::UTF8.GetBytes('{"error":"Forbidden: invalid or expired session authentication token."}')
            $res.ContentLength64 = $errBuf.Length
            $res.OutputStream.Write($errBuf, 0, $errBuf.Length)
            $res.Close()
            return $true
        }

        # Authenticated & authorized request handling
        $path = $req.Url.AbsolutePath.ToLowerInvariant()

        try {
            if ($path -eq "/api/session/heartbeat") {
                # D62: the ONLY place heartbeat state is updated - kept
                # off the generic per-request path deliberately, so a
                # test (or a future auditor) can trust that
                # HasReceivedHeartbeat/LastHeartbeatUtc reflect this
                # specific endpoint having been hit, not merely "some
                # authenticated request happened."
                $this.LastHeartbeatUtc = [System.DateTime]::UtcNow
                $this.HasReceivedHeartbeat = $true
                $res.ContentType = "application/json; charset=utf-8"
                $payload = @{
                    status = "ok"
                    serverTimeUtc = [System.DateTime]::UtcNow.ToString("o")
                } | ConvertTo-Json -Compress
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($payload)
                $res.ContentLength64 = $buffer.Length
                $res.OutputStream.Write($buffer, 0, $buffer.Length)
                $res.StatusCode = 200
            }
            elseif ($path -eq "/api/terminal/ping") {
                $res.ContentType = "application/json; charset=utf-8"
                $payload = @{
                    status = "ok"
                    port = $this.Port
                    cwd = $this.Cwd
                } | ConvertTo-Json -Compress
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($payload)
                $res.ContentLength64 = $buffer.Length
                $res.OutputStream.Write($buffer, 0, $buffer.Length)
                $res.StatusCode = 200
            }
            elseif ($path -eq "/api/terminal/profiles") {
                $res.ContentType = "application/json; charset=utf-8"
                $profiles = Get-OtterAvailableShells
                $payload = $profiles | ConvertTo-Json -Compress
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($payload)
                $res.ContentLength64 = $buffer.Length
                $res.OutputStream.Write($buffer, 0, $buffer.Length)
                $res.StatusCode = 200
            }
            elseif ($path -eq "/api/terminal/exec" -and $req.HttpMethod -eq "POST") {
                $reader = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd()
                $json = if ($body) { ConvertFrom-Json $body } else { $null }

                $cmdText = if ($json -and $json.command) { [string]$json.command } else { "" }
                $shellId = if ($json -and $json.shell) { [string]$json.shell } else { $null }
                $execCwd = if ($json -and $json.cwd) { [string]$json.cwd } else { $this.Cwd }

                $execResult = Invoke-OtterShellCommand -Command $cmdText -ShellId $shellId -WorkingDirectory $execCwd

                $res.ContentType = "application/json; charset=utf-8"
                $respObj = @{
                    command = $cmdText
                    shell = $execResult.Shell
                    shellId = $execResult.ShellId
                    cwd = $execResult.Cwd
                    exitCode = $execResult.ExitCode
                    stdout = $execResult.Stdout
                    stderr = $execResult.Stderr
                    output = $execResult.Output
                }
                $payload = $respObj | ConvertTo-Json -Compress
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($payload)
                $res.ContentLength64 = $buffer.Length
                $res.OutputStream.Write($buffer, 0, $buffer.Length)
                $res.StatusCode = 200
            }
            elseif ($path -eq "/api/fs/read" -and ($req.HttpMethod -eq "POST" -or $req.HttpMethod -eq "GET")) {
                $targetPath = $null
                if ($req.HttpMethod -eq "POST") {
                    $reader = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                    $body = $reader.ReadToEnd()
                    $json = if ($body) { ConvertFrom-Json $body } else { $null }
                    $targetPath = if ($json -and $json.path) { [string]$json.path } else { "" }
                } else {
                    $targetPath = [string]$req.QueryString["path"]
                }

                if ([string]::IsNullOrEmpty($targetPath)) {
                    $res.StatusCode = 400
                    $errPayload = @{ error = "Path parameter is required." } | ConvertTo-Json -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errPayload)
                    $res.ContentLength64 = $buffer.Length
                    $res.OutputStream.Write($buffer, 0, $buffer.Length)
                } else {
                    $fullPath = if ([System.IO.Path]::IsPathRooted($targetPath)) {
                        $targetPath
                    } else {
                        [System.IO.Path]::Combine($this.Cwd, $targetPath)
                    }

                    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                        $parentCwd = Split-Path -Parent $this.Cwd
                        if ($parentCwd) {
                            $altPath = [System.IO.Path]::Combine($parentCwd, $targetPath)
                            if (Test-Path -LiteralPath $altPath -PathType Leaf) {
                                $fullPath = $altPath
                            }
                        }
                    }

                    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                        $res.StatusCode = 404
                        $errPayload = @{ error = "File not found: $targetPath" } | ConvertTo-Json -Compress
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($errPayload)
                        $res.ContentLength64 = $buffer.Length
                        $res.OutputStream.Write($buffer, 0, $buffer.Length)
                    } else {
                        $content = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)
                        $res.ContentType = "application/json; charset=utf-8"
                        $respObj = @{
                            path = $targetPath
                            fullPath = (Resolve-Path -LiteralPath $fullPath).Path
                            content = $content
                            size = $content.Length
                        }
                        $payload = $respObj | ConvertTo-Json -Compress
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($payload)
                        $res.ContentLength64 = $buffer.Length
                        $res.OutputStream.Write($buffer, 0, $buffer.Length)
                        $res.StatusCode = 200
                    }
                }
            }
            elseif ($path -eq "/api/fs/write" -and $req.HttpMethod -eq "POST") {
                $reader = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                $body = $reader.ReadToEnd()
                $json = if ($body) { ConvertFrom-Json $body } else { $null }

                $targetPath = if ($json -and $json.path) { [string]$json.path } else { "" }
                $content = if ($json -and $null -ne $json.content) { [string]$json.content } else { "" }

                if ([string]::IsNullOrEmpty($targetPath)) {
                    $res.StatusCode = 400
                    $errPayload = @{ error = "Path parameter is required." } | ConvertTo-Json -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errPayload)
                    $res.ContentLength64 = $buffer.Length
                    $res.OutputStream.Write($buffer, 0, $buffer.Length)
                } else {
                    $fullPath = if ([System.IO.Path]::IsPathRooted($targetPath)) {
                        $targetPath
                    } else {
                        [System.IO.Path]::Combine($this.Cwd, $targetPath)
                    }

                    $parentDir = [System.IO.Path]::GetDirectoryName($fullPath)
                    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
                        [System.IO.Directory]::CreateDirectory($parentDir) | Out-Null
                    }

                    [System.IO.File]::WriteAllText($fullPath, $content, [System.Text.Encoding]::UTF8)
                    $res.ContentType = "application/json; charset=utf-8"
                    $respObj = @{
                        path = $targetPath
                        fullPath = (Resolve-Path -LiteralPath $fullPath).Path
                        size = $content.Length
                        saved = $true
                    }
                    $payload = $respObj | ConvertTo-Json -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($payload)
                    $res.ContentLength64 = $buffer.Length
                    $res.OutputStream.Write($buffer, 0, $buffer.Length)
                    $res.StatusCode = 200
                }
            }
            elseif ($path -eq "/api/fs/files" -and ($req.HttpMethod -eq "POST" -or $req.HttpMethod -eq "GET")) {
                $targetPath = $null
                $recursive = $false
                if ($req.HttpMethod -eq "POST") {
                    $reader = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                    $body = $reader.ReadToEnd()
                    $json = if ($body) { ConvertFrom-Json $body } else { $null }
                    $targetPath = if ($json -and $json.path) { [string]$json.path } else { "" }
                    $recursive = if ($json -and $json.recursive) { [bool]$json.recursive } else { $false }
                } else {
                    $targetPath = [string]$req.QueryString["path"]
                    $recursive = [string]$req.QueryString["recursive"] -eq "true"
                }

                if ([string]::IsNullOrEmpty($targetPath)) {
                    $targetPath = "."
                }

                $fullPath = if ([System.IO.Path]::IsPathRooted($targetPath)) {
                    $targetPath
                } else {
                    [System.IO.Path]::Combine($this.Cwd, $targetPath)
                }

                if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
                    $parentCwd = Split-Path -Parent $this.Cwd
                    if ($parentCwd) {
                        $altPath = [System.IO.Path]::Combine($parentCwd, $targetPath)
                        if (Test-Path -LiteralPath $altPath -PathType Container) {
                            $fullPath = $altPath
                        }
                    }
                }

                if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
                    $res.StatusCode = 404
                    $errPayload = @{ error = "Folder not found: $targetPath" } | ConvertTo-Json -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errPayload)
                    $res.ContentLength64 = $buffer.Length
                    $res.OutputStream.Write($buffer, 0, $buffer.Length)
                } else {
                    $gciParams = @{
                        LiteralPath = $fullPath
                        File = $true
                    }
                    if ($recursive) {
                        $gciParams['Recurse'] = $true
                    }
                    $files = @(Get-ChildItem @gciParams | ForEach-Object {
                        @{
                            __otterThing = $true
                            typeName = "file"
                            props = @{
                                name = $_.Name
                                path = (Resolve-Path -LiteralPath $_.FullName).Path
                                extension = $_.Extension
                                size = $_.Length
                                created = $_.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                                modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                            }
                            order = @("name", "path", "extension", "size", "created", "modified")
                        }
                    })

                    $res.ContentType = "application/json; charset=utf-8"
                    $payload = if ($files.Count -eq 0) { "[]" } else { ConvertTo-Json -InputObject $files -Depth 10 -Compress }
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($payload)
                    $res.ContentLength64 = $buffer.Length
                    $res.OutputStream.Write($buffer, 0, $buffer.Length)
                    $res.StatusCode = 200
                }
            }
            elseif ($path -eq "/api/fs/folders" -and ($req.HttpMethod -eq "POST" -or $req.HttpMethod -eq "GET")) {
                $targetPath = $null
                $recursive = $false
                if ($req.HttpMethod -eq "POST") {
                    $reader = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                    $body = $reader.ReadToEnd()
                    $json = if ($body) { ConvertFrom-Json $body } else { $null }
                    $targetPath = if ($json -and $json.path) { [string]$json.path } else { "" }
                    $recursive = if ($json -and $json.recursive) { [bool]$json.recursive } else { $false }
                } else {
                    $targetPath = [string]$req.QueryString["path"]
                    $recursive = [string]$req.QueryString["recursive"] -eq "true"
                }

                if ([string]::IsNullOrEmpty($targetPath)) {
                    $targetPath = "."
                }

                $fullPath = if ([System.IO.Path]::IsPathRooted($targetPath)) {
                    $targetPath
                } else {
                    [System.IO.Path]::Combine($this.Cwd, $targetPath)
                }

                if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
                    $parentCwd = Split-Path -Parent $this.Cwd
                    if ($parentCwd) {
                        $altPath = [System.IO.Path]::Combine($parentCwd, $targetPath)
                        if (Test-Path -LiteralPath $altPath -PathType Container) {
                            $fullPath = $altPath
                        }
                    }
                }

                if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
                    $res.StatusCode = 404
                    $errPayload = @{ error = "Folder not found: $targetPath" } | ConvertTo-Json -Compress
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($errPayload)
                    $res.ContentLength64 = $buffer.Length
                    $res.OutputStream.Write($buffer, 0, $buffer.Length)
                } else {
                    $gciParams = @{
                        LiteralPath = $fullPath
                        Directory = $true
                    }
                    if ($recursive) {
                        $gciParams['Recurse'] = $true
                    }
                    $folders = @(Get-ChildItem @gciParams | ForEach-Object {
                        @{
                            __otterThing = $true
                            typeName = "folder"
                            props = @{
                                name = $_.Name
                                path = (Resolve-Path -LiteralPath $_.FullName).Path
                                created = $_.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                                modified = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                            }
                            order = @("name", "path", "created", "modified")
                        }
                    })

                    $res.ContentType = "application/json; charset=utf-8"
                    $payload = if ($folders.Count -eq 0) { "[]" } else { ConvertTo-Json -InputObject $folders -Depth 10 -Compress }
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($payload)
                    $res.ContentLength64 = $buffer.Length
                    $res.OutputStream.Write($buffer, 0, $buffer.Length)
                    $res.StatusCode = 200
                }
            }
            else {
                $res.StatusCode = 404
                $buffer = [System.Text.Encoding]::UTF8.GetBytes('{"error":"Not Found"}')
                $res.ContentLength64 = $buffer.Length
                $res.OutputStream.Write($buffer, 0, $buffer.Length)
            }
        }
        catch {
            $res.StatusCode = 500
            $errPayload = @{ error = $_.Exception.Message } | ConvertTo-Json -Compress
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($errPayload)
            $res.ContentLength64 = $buffer.Length
            $res.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        finally {
            $res.Close()
        }

        return $true
    }
}

function Get-OtterAvailableShells {
    <#
    .SYNOPSIS
    Detects available shell environments on the host system, prioritizing PowerShell 7 over 5.1.
    #>
    [CmdletBinding()]
    param()

    $shells = [System.Collections.Generic.List[hashtable]]::new()

    # 1. PowerShell 7+ (pwsh)
    $pwshPath = $null
    $pwshCmd = Get-Command 'pwsh' -ErrorAction SilentlyContinue
    if ($pwshCmd) {
        $pwshPath = $pwshCmd.Source
    } elseif (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') {
        $pwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
    }

    if ($pwshPath) {
        $shells.Add(@{
            Id = 'pwsh'
            Name = 'PowerShell 7'
            Path = $pwshPath
            Args = @('-NoLogo')
            IsDefault = $true
            Prompt = "PS $PWD> "
        })
    }

    # 2. Windows PowerShell 5.1
    $ps5Path = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $ps5Path) {
        $shells.Add(@{
            Id = 'powershell'
            Name = 'Windows PowerShell'
            Path = $ps5Path
            Args = @('-NoLogo')
            IsDefault = ($null -eq $pwshPath)
            Prompt = "PS $PWD> "
        })
    }

    # 3. Command Prompt
    $cmdPath = if ($env:COMSPEC) { $env:COMSPEC } else { "$env:WINDIR\System32\cmd.exe" }
    if (Test-Path $cmdPath) {
        $shells.Add(@{
            Id = 'cmd'
            Name = 'Command Prompt'
            Path = $cmdPath
            Args = @()
            IsDefault = $false
            Prompt = "$PWD> "
        })
    }

    # 4. Git Bash
    $gitBashCandidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe',
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($cand in $gitBashCandidates) {
        if (Test-Path $cand) {
            $shells.Add(@{
                Id = 'bash'
                Name = 'Git Bash'
                Path = $cand
                Args = @('--login', '-i')
                IsDefault = $false
                Prompt = "user@otter:$PWD$ "
            })
            break
        }
    }

    # 5. WSL (Windows Subsystem for Linux)
    $wslPath = "$env:WINDIR\System32\wsl.exe"
    if (Test-Path $wslPath) {
        $shells.Add(@{
            Id = 'wsl'
            Name = 'WSL (Linux)'
            Path = $wslPath
            Args = @()
            IsDefault = $false
            Prompt = "otter@linux:~$ "
        })
    }

    # 6. Otter REPL
    $otterCmd = Join-Path $PSScriptRoot '..\otter.cmd'
    if (Test-Path $otterCmd) {
        $shells.Add(@{
            Id = 'otter'
            Name = 'Otter REPL'
            Path = (Resolve-Path $otterCmd).Path
            Args = @()
            IsDefault = $false
            Prompt = "otter> "
        })
    }

    return $shells.ToArray()
}

function Invoke-OtterShellCommand {
    <#
    .SYNOPSIS
    Executes an arbitrary command against a specified host shell with redirected UTF-8 I/O.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        [string]$ShellId = $null,
        [string]$WorkingDirectory = $PWD.Path,
        [int]$TimeoutSeconds = 30
    )

    $shells = Get-OtterAvailableShells
    $targetShell = $null
    if ($ShellId) {
        foreach ($sh in $shells) {
            if ($sh.Id -eq $ShellId) {
                $targetShell = $sh
                break
            }
        }
    }
    if (-not $targetShell) {
        foreach ($sh in $shells) {
            if ($sh.IsDefault) {
                $targetShell = $sh
                break
            }
        }
    }
    if (-not $targetShell -and $shells.Length -gt 0) {
        $targetShell = $shells[0]
    }

    if (-not $targetShell) {
        throw [OtterError]::new("No suitable shell found on host system.", 0, 'runtime')
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.WorkingDirectory = if (Test-Path -LiteralPath $WorkingDirectory) { (Resolve-Path -LiteralPath $WorkingDirectory).Path } else { $PWD.Path }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    switch ($targetShell.Id) {
        { $_ -in @('pwsh', 'powershell') } {
            $psi.FileName = $targetShell.Path
            $psi.Arguments = "-NoLogo -NoProfile -NonInteractive -Command `"$Command`""
        }
        'cmd' {
            $psi.FileName = $targetShell.Path
            $psi.Arguments = "/c `"$Command`""
        }
        'bash' {
            $psi.FileName = $targetShell.Path
            $psi.Arguments = "-c `"$Command`""
        }
        'wsl' {
            $psi.FileName = $targetShell.Path
            $psi.Arguments = "-e sh -c `"$Command`""
        }
        'otter' {
            $psi.FileName = 'powershell.exe'
            $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
            $otterScript = Join-Path $repoRoot 'otter.ps1'
            $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$otterScript`" $Command"
        }
        default {
            $psi.FileName = $targetShell.Path
            $psi.Arguments = "-Command `"$Command`""
        }
    }

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit([Math]::Max(1000, $TimeoutSeconds * 1000)) | Out-Null

    $exitCode = if ($proc.HasExited) { $proc.ExitCode } else { -1 }

    $combined = if ($stdout -and $stderr) {
        "$stdout`n$stderr"
    } elseif ($stdout) {
        $stdout
    } else {
        $stderr
    }

    return [PSCustomObject]@{
        Command = $Command
        Shell = $targetShell.Name
        ShellId = $targetShell.Id
        Cwd = $psi.WorkingDirectory
        ExitCode = $exitCode
        Stdout = $stdout
        Stderr = $stderr
        Output = $combined
    }
}

function New-OtterSessionToken {
    <#
    .SYNOPSIS
    Generates a cryptographically secure 256-bit random session authentication token.
    #>
    [CmdletBinding()]
    param()

    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    return [System.Convert]::ToBase64String($bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=')
}

function Start-OtterTerminalBridge {
    <#
    .SYNOPSIS
    Starts a secured, authenticated loopback bridge session for WebView / Desktop terminal integration.
    Per D60 security hardening:
    1. Binds exclusively to loopback (127.0.0.1).
    2. Uses an ephemeral or specified port.
    3. Enforces cryptographic session token authentication on every request.
    4. Rejects cross-origin requests from unauthorized browser origins.
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 0,
        [string]$Cwd = $PWD.Path,
        [string]$AuthToken = $null
    )

    if ([string]::IsNullOrEmpty($AuthToken)) {
        $AuthToken = New-OtterSessionToken
    }

    $chosenPort = $Port
    if ($chosenPort -le 0) {
        $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $tcp.Start()
        $chosenPort = ([System.Net.IPEndPoint]$tcp.LocalEndpoint).Port
        $tcp.Stop()
    }

    $listener = $null
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $testPort = $chosenPort + $attempt
        try {
            $l = [System.Net.HttpListener]::new()
            $prefix = "http://127.0.0.1:$testPort/"
            $l.Prefixes.Add($prefix)
            $l.Start()
            $listener = $l
            $chosenPort = $testPort
            break
        }
        catch {
            # Port busy, try next
        }
    }

    if (-not $listener) {
        throw [OtterError]::new("Could not bind terminal bridge listener on port $chosenPort.", 0, 'runtime')
    }

    $session = [OtterTerminalBridgeSession]::new($listener, $chosenPort, $Cwd, $AuthToken)
    return $session
}

function Stop-OtterTerminalBridge {
    param([Parameter(Mandatory)][OtterTerminalBridgeSession]$Session)
    if ($Session.IsRunning) {
        $Session.IsRunning = $false
        # Immediately invalidate authentication token on host shutdown
        $Session.AuthToken = [System.Guid]::NewGuid().ToString()
        try {
            $Session.Listener.Stop()
            $Session.Listener.Close()
        } catch { }
    }
}

class OtterDesktopAppSession {
    [System.Diagnostics.Process]$Process
    [OtterTerminalBridgeSession]$Bridge
    [string]$SourcePath
    [string]$HtmlPath
    [string]$InstanceHtmlPath

    [bool] HandleNextRequest([int]$TimeoutMs = 0) {
        if ($this.Bridge) {
            return $this.Bridge.HandleNextRequest($TimeoutMs)
        }
        return $false
    }

    [void] Stop() {
        if ($this.Process -and -not $this.Process.HasExited) {
            try { $this.Process.Kill() } catch { }
        }
        if ($this.Bridge) {
            Stop-OtterTerminalBridge -Session $this.Bridge
        }
        if ($this.InstanceHtmlPath -and (Test-Path $this.InstanceHtmlPath)) {
            Remove-Item -LiteralPath $this.InstanceHtmlPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-OtterDesktopApplication {
    <#
    .SYNOPSIS
    Starts an Otter Desktop application with an integrated, authenticated terminal bridge.
    Per D60 security rules:
    1. Starts an authenticated loopback bridge on an ephemeral port with a 256-bit cryptographic token.
    2. Compiles clean static HTML without baked credentials.
    3. Injects bridge credentials dynamically into a session-specific desktop runtime instance.
    4. Services terminal execution requests while the desktop application window is open.
    5. Cleanly shuts down the bridge and invalidates credentials when the application closes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [int]$Width = 1440,
        [int]$Height = 900,
        [switch]$PassThru,
        [switch]$NoWait,
        [int]$BridgePort = 0,
        [string]$Cwd = "",
        [string]$UserDataDir = $env:OTTER_BROWSER_USER_DATA_DIR
    )

    $resolved = Resolve-Path -LiteralPath $SourcePath
    if (-not (Test-Path $resolved)) {
        throw [OtterError]::new("I cannot find a file called `"$SourcePath`".", 0, 'runtime')
    }

    $projectRoot = if ($Cwd) {
        (Resolve-Path -LiteralPath $Cwd).Path
    } else {
        $parent = Split-Path -Parent $resolved.Path
        $grandParent = Split-Path -Parent $parent
        if ($grandParent -and (Test-Path (Join-Path $grandParent "Otter.Contract.psm1"))) {
            $grandParent
        } elseif (Test-Path (Join-Path (Get-Location).Path "Otter.Contract.psm1")) {
            (Get-Location).Path
        } else {
            $parent
        }
    }

    # 1. Start the authenticated terminal bridge on an ephemeral loopback port
    $bridgeSession = Start-OtterTerminalBridge -Port $BridgePort -Cwd $projectRoot

    # 2. Compile clean .ot source to static HTML application (no tokens baked into static export)
    $htmlPath = Export-OtterWebApplication -SourcePath $resolved.Path
    $resolvedHtml = (Resolve-Path $htmlPath).Path

    # 3. Create session-specific runtime instance HTML with injected bridge credentials
    $rawHtml = Get-Content -LiteralPath $resolvedHtml -Raw -Encoding UTF8
    $injectionScript = @"
<script id="otter-desktop-session-bridge">
window.__OTTER_DESKTOP_BRIDGE__ = {
  port: $($bridgeSession.Port),
  token: "$($bridgeSession.AuthToken)",
  async readFile(filePath) {
    const res = await fetch('http://127.0.0.1:' + this.port + '/api/fs/read', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Otter-Token': this.token
      },
      body: JSON.stringify({ path: filePath })
    });
    if (!res.ok) {
      throw new Error('Failed to read file ' + filePath + ': HTTP ' + res.status);
    }
    const data = await res.json();
    return data.content;
  },
  async writeFile(filePath, content) {
    const res = await fetch('http://127.0.0.1:' + this.port + '/api/fs/write', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Otter-Token': this.token
      },
      body: JSON.stringify({ path: filePath, content: content })
    });
    if (!res.ok) {
      throw new Error('Failed to write file ' + filePath + ': HTTP ' + res.status);
    }
    return await res.json();
  },
  async exec(command, shell = null, cwd = null) {
    const res = await fetch('http://127.0.0.1:' + this.port + '/api/terminal/exec', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Otter-Token': this.token
      },
      body: JSON.stringify({ command: command, shell: shell, cwd: cwd })
    });
    if (!res.ok) {
      throw new Error('Terminal execution failed: HTTP ' + res.status);
    }
    return await res.json();
  },
  async getProfiles() {
    const res = await fetch('http://127.0.0.1:' + this.port + '/api/terminal/profiles', {
      method: 'GET',
      headers: { 'X-Otter-Token': this.token }
    });
    if (!res.ok) return [];
    return await res.json();
  },
  async getFiles(folderPath, includeSubfolders = false) {
    const res = await fetch('http://127.0.0.1:' + this.port + '/api/fs/files', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Otter-Token': this.token
      },
      body: JSON.stringify({ path: folderPath, recursive: includeSubfolders })
    });
    if (!res.ok) {
      throw new Error('Failed to get files in ' + folderPath + ': HTTP ' + res.status);
    }
    return await res.json();
  },
  async getFolders(folderPath, includeSubfolders = false) {
    const res = await fetch('http://127.0.0.1:' + this.port + '/api/fs/folders', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Otter-Token': this.token
      },
      body: JSON.stringify({ path: folderPath, recursive: includeSubfolders })
    });
    if (!res.ok) {
      throw new Error('Failed to get folders in ' + folderPath + ': HTTP ' + res.status);
    }
    return await res.json();
  }
};
window.otterReadFile = function(filePath) {
  if (window.__OTTER_DESKTOP_BRIDGE__ && typeof window.__OTTER_DESKTOP_BRIDGE__.readFile === 'function') {
    return window.__OTTER_DESKTOP_BRIDGE__.readFile(filePath);
  }
  throw new Error('Desktop Bridge is not available for file operations');
};
window.otterWriteFile = function(filePath, content) {
  if (window.__OTTER_DESKTOP_BRIDGE__ && typeof window.__OTTER_DESKTOP_BRIDGE__.writeFile === 'function') {
    return window.__OTTER_DESKTOP_BRIDGE__.writeFile(filePath, content);
  }
  throw new Error('Desktop Bridge is not available for file operations');
};
window.otterRunCommand = function(command) {
  if (window.__OTTER_DESKTOP_BRIDGE__ && typeof window.__OTTER_DESKTOP_BRIDGE__.exec === 'function') {
    return window.__OTTER_DESKTOP_BRIDGE__.exec(command).then(res => (res.stdout || res.output || res.stderr || '').trim());
  }
  throw new Error('Desktop Bridge is not available for command execution');
};
window.otterGetFiles = function(folderPath, includeSubfolders = false) {
  if (window.__OTTER_DESKTOP_BRIDGE__ && typeof window.__OTTER_DESKTOP_BRIDGE__.getFiles === 'function') {
    return window.__OTTER_DESKTOP_BRIDGE__.getFiles(folderPath, includeSubfolders);
  }
  throw new Error('Desktop Bridge is not available for file discovery');
};
window.otterGetFolders = function(folderPath, includeSubfolders = false) {
  if (window.__OTTER_DESKTOP_BRIDGE__ && typeof window.__OTTER_DESKTOP_BRIDGE__.getFolders === 'function') {
    return window.__OTTER_DESKTOP_BRIDGE__.getFolders(folderPath, includeSubfolders);
  }
  throw new Error('Desktop Bridge is not available for folder discovery');
};

// D62: durable session lifetime. This is generic desktop-runtime
// infrastructure - it knows nothing about Studio or any other
// specific application, and must stay that way (no Studio-specific
// behavior belongs in this shared injection script). A grace-timeout
// design on the server side (OtterTerminalBridgeSession.IsSessionAlive)
// is the only thing keeping the bridge alive past this heartbeat, so
// no explicit close signal is sent here - the server simply notices
// the beats stop and cleans up after its own grace window elapses.
(function startOtterHeartbeat() {
  function beat() {
    fetch(
      'http://127.0.0.1:' +
      window.__OTTER_DESKTOP_BRIDGE__.port +
      '/api/session/heartbeat',
      {
        method: 'POST',
        headers: {
          'X-Otter-Token':
            window.__OTTER_DESKTOP_BRIDGE__.token
        }
      }
    ).catch(() => {});
  }

  beat();
  setInterval(beat, 2000);
})();
</script>
"@
    $instanceHtml = if ($rawHtml -match '(?i)</head>') {
        $rawHtml -replace '(?i)</head>', "$injectionScript`n</head>"
    } else {
        $injectionScript + "`n" + $rawHtml
    }

    $instanceHtmlPath = [System.IO.Path]::ChangeExtension($resolvedHtml, '.desktop.html')
    Set-Content -LiteralPath $instanceHtmlPath -Value $instanceHtml -Encoding UTF8

    # 4. Locate Edge or Chrome for dedicated App Mode
    $browserCandidates = @(
        'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
        'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        'C:\Program Files\Google\Chrome\Application\chrome.exe',
        'C:\Program Files\Google\Chrome\Application\chrome.exe'
    )

    $exePath = $null
    foreach ($cand in $browserCandidates) {
        if (Test-Path $cand) {
            $exePath = $cand
            break
        }
    }

    $uri = "file:///" + $instanceHtmlPath.Replace('\', '/')
    $proc = $null

    if ($exePath) {
        $appArgs = @(
            "--app=$uri",
            "--window-size=$Width,$Height"
        )
        if ($UserDataDir) {
            $appArgs += "--user-data-dir=$UserDataDir"
        }
        $proc = Start-Process -FilePath $exePath -ArgumentList $appArgs -PassThru
    } else {
        $proc = Start-Process -FilePath $instanceHtmlPath -PassThru
    }

    $appSession = [OtterDesktopAppSession]::new()
    $appSession.Process = $proc
    $appSession.Bridge = $bridgeSession
    $appSession.SourcePath = $resolved.Path
    $appSession.HtmlPath = $resolvedHtml
    $appSession.InstanceHtmlPath = $instanceHtmlPath

    Write-Host "Otter Desktop Application running (PID: $($proc.Id), Bridge Port: $($bridgeSession.Port))." -ForegroundColor Green

    if ($PassThru -or $NoWait) {
        return $appSession
    }

    # D62: durable session lifetime. The loop's only correctness-
    # critical condition is IsSessionAlive() (heartbeat freshness,
    # against a startup grace before the first beat and a steady-state
    # grace between beats thereafter) - $proc.HasExited is deliberately
    # NOT part of this condition at all, anywhere, since it was proven
    # unreliable for Edge/Chrome `--app=` launches (the launcher PID
    # `Start-Process` returns exits within about a second while the
    # real browser window keeps running under a different PID; trusting
    # it here would silently reintroduce the exact bug this design
    # exists to fix).
    try {
        while ($bridgeSession.IsRunning -and $bridgeSession.IsSessionAlive()) {
            $bridgeSession.HandleNextRequest(500) | Out-Null
        }
    }
    finally {
        $appSession.Stop()
        Write-Host "Otter Desktop Application closed cleanly." -ForegroundColor Gray
    }
}

Export-ModuleMember -Function Start-OtterDesktopApplication, Get-OtterAvailableShells, Invoke-OtterShellCommand, Start-OtterTerminalBridge, Stop-OtterTerminalBridge, New-OtterSessionToken
