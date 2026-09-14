using module ..\Otter.Contract.psm1

# tests/Terminal.Tests.ps1
# Native Desktop Terminal Engine & Hardened Host Bridge Test Suite (D60)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Desktop.psm1') -Force

Write-Output 'Otter Desktop Terminal Engine (D60)'

# Test 1: Discover available system shells
$shells = Get-OtterAvailableShells
if ($null -eq $shells -or $shells.Length -eq 0) {
    throw "Expected at least one shell discovered on system."
}
$defaultShell = $shells | Where-Object { $_.IsDefault }
if ($null -eq $defaultShell) {
    throw "Expected a default shell to be identified."
}
Write-Output "  pass  shell discovery detects $($shells.Length) shell(s) with default '$($defaultShell.Name)'"

# Test 2: Execute real command in default shell and capture real stdout
$res = Invoke-OtterShellCommand -Command "Write-Output 'Otter Terminal Engine Verified'"
if ($res.ExitCode -ne 0) {
    throw "Command exited with non-zero code $($res.ExitCode): $($res.Stderr)"
}
if ($res.Stdout -notmatch 'Otter Terminal Engine Verified') {
    throw "Expected stdout match, got: $($res.Stdout)"
}
Write-Output '  pass  Invoke-OtterShellCommand executes real shell process and captures stdout'

# Test 3: Command executes in specified working directory
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$resDir = Invoke-OtterShellCommand -Command "git status -s" -WorkingDirectory $repoRoot
if ($resDir.ExitCode -ne 0) {
    throw "git status failed: $($resDir.Stderr)"
}
Write-Output '  pass  Invoke-OtterShellCommand runs in specified working directory'

# Test 4: Cryptographic token generation
$token1 = New-OtterSessionToken
$token2 = New-OtterSessionToken
if ([string]::IsNullOrEmpty($token1) -or $token1.Length -lt 32) {
    throw "Expected secure cryptographic token with length >= 32"
}
if ($token1 -eq $token2) {
    throw "Cryptographic tokens must be unpredictable and unique"
}
Write-Output '  pass  New-OtterSessionToken generates unique 256-bit cryptographically random tokens'

# Test 5: Ephemeral port binding on loopback
$session = Start-OtterTerminalBridge -Port 0 -Cwd $repoRoot
if (-not $session.IsRunning) {
    throw "Expected bridge session to be running."
}
if ($session.Port -le 1024) {
    throw "Expected ephemeral loopback port > 1024, got $($session.Port)"
}
if ([string]::IsNullOrEmpty($session.AuthToken)) {
    throw "Expected session to possess an authentication secret"
}
Write-Output "  pass  Start-OtterTerminalBridge binds ephemeral loopback port $($session.Port) with auth secret"

# Test 5b: Physical loopback binding verification
foreach ($prefix in $session.Listener.Prefixes) {
    if ($prefix -notmatch '^https?://127\.0\.0\.1:\d+/') {
        throw "Security failure: Listener prefix '$prefix' is not strictly bound to 127.0.0.1 loopback!"
    }
    if ($prefix -match '[*+]' -or $prefix -match '0\.0\.0\.0') {
        throw "Security failure: Listener prefix '$prefix' contains wildcard or all-interfaces binding!"
    }
}
Write-Output '  pass  security: listener is physically bound strictly to 127.0.0.1 (no wildcards or LAN exposure)'

try {
    # Test 6: Security Negative Test — Missing Token rejected with 401
    $clientJobNoToken = Start-Job -ScriptBlock {
        param($port)
        Start-Sleep -Milliseconds 150
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/terminal/ping" -Method Get -UseBasicParsing
            return @{ status = $resp.StatusCode }
        } catch [System.Net.WebException] {
            $resp = $_.Exception.Response
            return @{ status = [int]$resp.StatusCode }
        }
    } -ArgumentList $session.Port

    $session.HandleNextRequest(3000) | Out-Null
    $resNoToken = Receive-Job -Job $clientJobNoToken -Wait
    Remove-Job -Job $clientJobNoToken -Force

    if ($resNoToken.status -ne 401) {
        throw "Expected HTTP 401 Unauthorized for missing token, got $($resNoToken.status)"
    }
    Write-Output '  pass  security: unauthenticated request without token rejected with HTTP 401'

    # Test 7: Security Negative Test — Wrong/Tampered Token rejected with 403
    $clientJobBadToken = Start-Job -ScriptBlock {
        param($port)
        Start-Sleep -Milliseconds 150
        try {
            $headers = @{ "X-Otter-Token" = "attacker-tampered-token-xyz" }
            $body = @{ command = "Write-Output 'Pwned'" } | ConvertTo-Json
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/terminal/exec" -Method Post -Headers $headers -Body $body -ContentType "application/json" -UseBasicParsing
            return @{ status = $resp.StatusCode }
        } catch [System.Net.WebException] {
            $resp = $_.Exception.Response
            return @{ status = [int]$resp.StatusCode }
        }
    } -ArgumentList $session.Port

    $session.HandleNextRequest(3000) | Out-Null
    $resBadToken = Receive-Job -Job $clientJobBadToken -Wait
    Remove-Job -Job $clientJobBadToken -Force

    if ($resBadToken.status -ne 403) {
        throw "Expected HTTP 403 Forbidden for invalid token, got $($resBadToken.status)"
    }
    Write-Output '  pass  security: request with invalid token rejected with HTTP 403'

    # Test 8: Security Negative Test — Unauthorized Origin rejected with 403
    $clientJobBadOrigin = Start-Job -ScriptBlock {
        param($port, $token)
        Start-Sleep -Milliseconds 150
        try {
            $headers = @{
                "X-Otter-Token" = $token
                "Origin" = "http://malicious-website.com"
            }
            $body = @{ command = "Write-Output 'Cross-Site'" } | ConvertTo-Json
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/terminal/exec" -Method Post -Headers $headers -Body $body -ContentType "application/json" -UseBasicParsing
            return @{ status = $resp.StatusCode }
        } catch [System.Net.WebException] {
            $resp = $_.Exception.Response
            return @{ status = [int]$resp.StatusCode }
        }
    } -ArgumentList $session.Port, $session.AuthToken

    $session.HandleNextRequest(3000) | Out-Null
    $resBadOrigin = Receive-Job -Job $clientJobBadOrigin -Wait
    Remove-Job -Job $clientJobBadOrigin -Force

    if ($resBadOrigin.status -ne 403) {
        throw "Expected HTTP 403 Forbidden for unauthorized origin, got $($resBadOrigin.status)"
    }
    Write-Output '  pass  security: cross-origin request from unauthorized Origin rejected with HTTP 403'

    # Test 8b: Browser CORS Preflight (OPTIONS) flow
    $clientJobOptions = Start-Job -ScriptBlock {
        param($port)
        Start-Sleep -Milliseconds 150
        $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$port/api/terminal/exec")
        $req.Method = "OPTIONS"
        $req.Headers.Add("Origin", "http://127.0.0.1:$port")
        $req.Headers.Add("Access-Control-Request-Method", "POST")
        $req.Headers.Add("Access-Control-Request-Headers", "Content-Type, X-Otter-Token")
        $resp = $req.GetResponse()
        return @{
            statusCode = [int]$resp.StatusCode
            allowOrigin = $resp.Headers["Access-Control-Allow-Origin"]
            vary = $resp.Headers["Vary"]
            allowHeaders = $resp.Headers["Access-Control-Allow-Headers"]
        }
    } -ArgumentList $session.Port

    $session.HandleNextRequest(3000) | Out-Null
    $resOptions = Receive-Job -Job $clientJobOptions -Wait
    Remove-Job -Job $clientJobOptions -Force

    if ($resOptions.statusCode -ne 200) {
        throw "Expected HTTP 200 for valid OPTIONS preflight, got $($resOptions.statusCode)"
    }
    if ($resOptions.allowOrigin -ne "http://127.0.0.1:$($session.Port)") {
        throw "Expected exact origin grant 'http://127.0.0.1:$($session.Port)', got '$($resOptions.allowOrigin)'"
    }
    if ($resOptions.vary -ne "Origin") {
        throw "Expected Vary: Origin header in preflight response, got '$($resOptions.vary)'"
    }
    Write-Output '  pass  security: browser CORS preflight grants exact trusted origin with Vary: Origin'

    # Test 9: Security Positive Test — Authenticated request with valid token & origin succeeds
    $clientJobAuth = Start-Job -ScriptBlock {
        param($port, $token)
        Start-Sleep -Milliseconds 150
        $headers = @{
            "X-Otter-Token" = $token
            "Origin" = "http://127.0.0.1:$port"
        }
        $body = @{
            command = "Write-Output 'AuthenticatedTerminalPass'"
        } | ConvertTo-Json
        return (Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/terminal/exec" -Method Post -Headers $headers -Body $body -ContentType "application/json")
    } -ArgumentList $session.Port, $session.AuthToken

    $session.HandleNextRequest(8000) | Out-Null
    $execResult = Receive-Job -Job $clientJobAuth -Wait
    Remove-Job -Job $clientJobAuth -Force

    if ($execResult.exitCode -ne 0 -or $execResult.stdout -notmatch 'AuthenticatedTerminalPass') {
        throw "Unexpected authenticated exec response: $($execResult | ConvertTo-Json)"
    }
    Write-Output '  pass  security: authenticated request with valid token & origin executes and captures stdout'
}
finally {
    # Test 10: Clean shutdown and credential invalidation
    $oldToken = $session.AuthToken
    Stop-OtterTerminalBridge -Session $session
    if ($session.IsRunning) {
        throw "Expected session to be stopped."
    }
    if ($session.AuthToken -eq $oldToken) {
        throw "Expected authentication token to be invalidated on shutdown."
    }
    Write-Output '  pass  Stop-OtterTerminalBridge cleanly shuts down and invalidates session token'
}

# Test 11: Security Negative Test — Old token rejected against new session
$newSession = Start-OtterTerminalBridge -Port 0 -Cwd $repoRoot
try {
    $clientJobExpired = Start-Job -ScriptBlock {
        param($port, $expiredToken)
        Start-Sleep -Milliseconds 150
        try {
            $headers = @{ "X-Otter-Token" = $expiredToken }
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/terminal/ping" -Method Get -Headers $headers -UseBasicParsing
            return @{ status = $resp.StatusCode }
        } catch [System.Net.WebException] {
            $resp = $_.Exception.Response
            return @{ status = [int]$resp.StatusCode }
        }
    } -ArgumentList $newSession.Port, $oldToken

    $newSession.HandleNextRequest(3000) | Out-Null
    $resExpired = Receive-Job -Job $clientJobExpired -Wait
    Remove-Job -Job $clientJobExpired -Force

    if ($resExpired.status -ne 403) {
        throw "Expected HTTP 403 Forbidden when reusing old session token, got $($resExpired.status)"
    }
    Write-Output '  pass  security: old session token from restarted host rejected with HTTP 403'
}
finally {
    Stop-OtterTerminalBridge -Session $newSession
}

# Test 12: Authenticated Filesystem Read via Bridge (/api/fs/read)
$fsSession = Start-OtterTerminalBridge -Port 0 -Cwd $repoRoot
try {
    # 12a: Positive read of README.txt
    $clientJobFs = Start-Job -ScriptBlock {
        param($port, $token)
        Start-Sleep -Milliseconds 150
        $headers = @{
            "X-Otter-Token" = $token
            "Origin" = "http://127.0.0.1:$port"
        }
        $body = @{ path = "examples/file-organizer/README.txt" } | ConvertTo-Json
        return (Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/fs/read" -Method Post -Headers $headers -Body $body -ContentType "application/json")
    } -ArgumentList $fsSession.Port, $fsSession.AuthToken

    $fsSession.HandleNextRequest(5000) | Out-Null
    $fsResult = Receive-Job -Job $clientJobFs -Wait
    Remove-Job -Job $clientJobFs -Force

    if ($null -eq $fsResult -or $fsResult.content -notmatch 'Otter File Organizer Project') {
        throw "Expected README.txt content from /api/fs/read, got: $($fsResult | ConvertTo-Json)"
    }
    Write-Output '  pass  /api/fs/read reads real workspace file with valid token'

    # 12b: 404 for nonexistent file
    $clientJobMissing = Start-Job -ScriptBlock {
        param($port, $token)
        Start-Sleep -Milliseconds 150
        try {
            $headers = @{ "X-Otter-Token" = $token }
            $body = @{ path = "nonexistent_file_123.txt" } | ConvertTo-Json
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/fs/read" -Method Post -Headers $headers -Body $body -ContentType "application/json" -UseBasicParsing
            return @{ status = $resp.StatusCode }
        } catch [System.Net.WebException] {
            return @{ status = [int]$_.Exception.Response.StatusCode }
        }
    } -ArgumentList $fsSession.Port, $fsSession.AuthToken

    $fsSession.HandleNextRequest(5000) | Out-Null
    $missingResult = Receive-Job -Job $clientJobMissing -Wait
    Remove-Job -Job $clientJobMissing -Force

    if ($missingResult.status -ne 404) {
        throw "Expected HTTP 404 for nonexistent file, got $($missingResult.status)"
    }
    Write-Output '  pass  /api/fs/read returns HTTP 404 for nonexistent file'
}
finally {
    Stop-OtterTerminalBridge -Session $fsSession
}

# Test 13: Real Desktop Application Entry Point wiring (Start-OtterDesktopApplication)
$studioOtPath = (Resolve-Path (Join-Path $repoRoot 'examples\studio.ot')).Path
$app = Start-OtterDesktopApplication -SourcePath $studioOtPath -PassThru -NoWait
try {
    if ($null -eq $app.Bridge -or -not $app.Bridge.IsRunning) {
        throw "Expected Start-OtterDesktopApplication to start the authenticated terminal bridge"
    }
    if ($app.Bridge.Port -le 1024) {
        throw "Expected bridge port to be an ephemeral loopback port > 1024, got $($app.Bridge.Port)"
    }
    if ([string]::IsNullOrEmpty($app.Bridge.AuthToken) -or $app.Bridge.AuthToken.Length -lt 32) {
        throw "Expected session auth token to be present on desktop app bridge"
    }

    # Verify static HTML does not contain the session token
    $staticHtml = Get-Content -LiteralPath $app.HtmlPath -Raw -Encoding UTF8
    if ($staticHtml -match [regex]::Escape($app.Bridge.AuthToken)) {
        throw "Security failure: Static HTML contains the private session auth token!"
    }

    # Verify runtime instance HTML has the injected bridge credentials
    if (-not (Test-Path $app.InstanceHtmlPath)) {
        throw "Expected runtime instance HTML '$($app.InstanceHtmlPath)' to exist"
    }
    $instHtml = Get-Content -LiteralPath $app.InstanceHtmlPath -Raw -Encoding UTF8
    if ($instHtml -notmatch "window\.__OTTER_DESKTOP_BRIDGE__") {
        throw "Expected runtime instance HTML to contain window.__OTTER_DESKTOP_BRIDGE__ injection"
    }
    if ($instHtml -notmatch [regex]::Escape($app.Bridge.AuthToken)) {
        throw "Expected runtime instance HTML to contain the session auth token"
    }

    # Verify authenticated bridge communication through the desktop entry point
    $clientJobApp = Start-Job -ScriptBlock {
        param($port, $token)
        Start-Sleep -Milliseconds 150
        $headers = @{
            "X-Otter-Token" = $token
            "Origin" = "http://127.0.0.1:$port"
        }
        $body = @{
            command = "Write-Output 'DesktopAppEntryPass'"
        } | ConvertTo-Json
        return (Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/terminal/exec" -Method Post -Headers $headers -Body $body -ContentType "application/json")
    } -ArgumentList $app.Bridge.Port, $app.Bridge.AuthToken

    # D62: the real launched page begins sending its own heartbeat
    # immediately on load (the whole point of this phase), so the
    # bridge's request queue can legitimately receive that heartbeat
    # BEFORE this test's own deliberately-delayed exec request -
    # servicing exactly one request here would then consume the
    # heartbeat and leave the exec request unanswered. Loop servicing
    # requests (heartbeats included) until the job completes or an
    # overall deadline passes, rather than assuming the very next
    # request on the wire is always the one this test cares about.
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline -and $clientJobApp.State -eq 'Running') {
        $app.HandleNextRequest(500) | Out-Null
    }
    $appResult = Receive-Job -Job $clientJobApp -Wait
    Remove-Job -Job $clientJobApp -Force

    if ($appResult.exitCode -ne 0 -or $appResult.stdout -notmatch 'DesktopAppEntryPass') {
        throw "Unexpected desktop app exec response: $($appResult | ConvertTo-Json)"
    }
    Write-Output '  pass  Start-OtterDesktopApplication starts bridge, injects credentials, and executes commands'
}
finally {
    $instPath = $app.InstanceHtmlPath
    $app.Stop()
    if ($app.Bridge.IsRunning) {
        throw "Expected desktop app bridge to be stopped"
    }
    if (Test-Path $instPath) {
        throw "Expected temporary instance HTML to be cleaned up after Stop()"
    }
    Write-Output '  pass  OtterDesktopAppSession cleanly tears down bridge and deletes session instance HTML'
}

# Test 14: D62 - a real /api/session/heartbeat request sets
# HasReceivedHeartbeat and advances LastHeartbeatUtc
$hbBridge = Start-OtterTerminalBridge
try {
    if ($hbBridge.HasReceivedHeartbeat) {
        throw "Expected new bridge session to have HasReceivedHeartbeat = `$false initially"
    }
    $beforeUtc = $hbBridge.LastHeartbeatUtc

    # A real clock tick between session creation and the heartbeat request,
    # so LastHeartbeatUtc actually advancing is provable, not coincidental.
    Start-Sleep -Milliseconds 50

    $hbJob = Start-Job -ScriptBlock {
        param($port, $token)
        Start-Sleep -Milliseconds 100
        $headers = @{
            "X-Otter-Token" = $token
            "Origin" = "http://127.0.0.1:$port"
        }
        return (Invoke-RestMethod -Uri "http://127.0.0.1:$port/api/session/heartbeat" -Method Post -Headers $headers -ContentType "application/json")
    } -ArgumentList $hbBridge.Port, $hbBridge.AuthToken

    $hbBridge.HandleNextRequest(5000) | Out-Null
    $hbRes = Receive-Job -Job $hbJob -Wait
    Remove-Job -Job $hbJob -Force

    if ($hbRes.status -ne 'ok') {
        throw "Expected heartbeat response status 'ok', got '$($hbRes.status)'"
    }
    if (-not $hbBridge.HasReceivedHeartbeat) {
        throw "Expected HasReceivedHeartbeat to be true after a real heartbeat request"
    }
    if ($hbBridge.LastHeartbeatUtc -le $beforeUtc) {
        throw "Expected LastHeartbeatUtc to advance past its pre-request value after a real heartbeat request"
    }
    Write-Output '  pass  /api/session/heartbeat sets HasReceivedHeartbeat and advances LastHeartbeatUtc'
}
finally {
    Stop-OtterTerminalBridge -Session $hbBridge
}

# Test 15: D62 - /api/session/heartbeat requires the normal bridge token,
# the same as every other route, and a rejected request must NOT count as
# a heartbeat
$hbAuthBridge = Start-OtterTerminalBridge
try {
    $hbNoTokenJob = Start-Job -ScriptBlock {
        param($port)
        Start-Sleep -Milliseconds 150
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/api/session/heartbeat" -Method Post -UseBasicParsing
            return @{ status = $resp.StatusCode }
        } catch [System.Net.WebException] {
            $resp = $_.Exception.Response
            return @{ status = [int]$resp.StatusCode }
        }
    } -ArgumentList $hbAuthBridge.Port

    $hbAuthBridge.HandleNextRequest(3000) | Out-Null
    $hbNoTokenRes = Receive-Job -Job $hbNoTokenJob -Wait
    Remove-Job -Job $hbNoTokenJob -Force

    if ($hbNoTokenRes.status -ne 401) {
        throw "Expected HTTP 401 Unauthorized for a heartbeat request with no token, got $($hbNoTokenRes.status)"
    }
    if ($hbAuthBridge.HasReceivedHeartbeat) {
        throw "Expected an unauthenticated heartbeat request to NOT set HasReceivedHeartbeat"
    }
    Write-Output '  pass  /api/session/heartbeat requires the normal bridge token and rejects a missing one'
}
finally {
    Stop-OtterTerminalBridge -Session $hbAuthBridge
}

# Test 16: D62 - IsSessionAlive() honors StartupGraceMs before any
# heartbeat has arrived (deterministic - timeouts shortened locally so
# this stays fast)
$startupBridge = Start-OtterTerminalBridge
try {
    $startupBridge.StartupGraceMs = 100
    if (-not $startupBridge.IsSessionAlive()) {
        throw "Expected a freshly-created session to be alive immediately (within startup grace)"
    }
    Start-Sleep -Milliseconds 250
    if ($startupBridge.IsSessionAlive()) {
        throw "Expected the session to go stale once StartupGraceMs elapsed with no heartbeat"
    }
    Write-Output '  pass  IsSessionAlive() honors StartupGraceMs before the first heartbeat arrives'
}
finally {
    Stop-OtterTerminalBridge -Session $startupBridge
}

# Test 17: D62 - a fresh heartbeat keeps the session alive, and it goes
# stale again once HeartbeatGraceMs elapses with no further heartbeat
$steadyBridge = Start-OtterTerminalBridge
try {
    $steadyBridge.HeartbeatGraceMs = 150
    $steadyBridge.HasReceivedHeartbeat = $true
    $steadyBridge.LastHeartbeatUtc = [System.DateTime]::UtcNow
    if (-not $steadyBridge.IsSessionAlive()) {
        throw "Expected the session to be alive immediately after a fresh heartbeat"
    }
    Start-Sleep -Milliseconds 300
    if ($steadyBridge.IsSessionAlive()) {
        throw "Expected the session to go stale once HeartbeatGraceMs elapsed with no further heartbeat"
    }
    Write-Output '  pass  IsSessionAlive() honors HeartbeatGraceMs once a heartbeat has been received'
}
finally {
    Stop-OtterTerminalBridge -Session $steadyBridge
}

