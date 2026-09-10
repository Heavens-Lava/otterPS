# tests/Server.Tests.ps1
# Otter Web Server & API Route Test Suite (D51)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Server.psm1') -Force

Write-Output 'Otter Web Server (D51)'

# Test 1: Parse and inspect api-server.ot
$apiServerPath = Join-Path $PSScriptRoot '..\examples\api-server.ot'
$source = Get-Content -LiteralPath $apiServerPath -Raw
$tokens = ConvertTo-OtterTokens -Source $source
$ast = ConvertTo-OtterAst -Tokens $tokens

$def = Get-OtterServerDefinition -Program $ast
if (-not $def.Servers.Contains('api')) { throw 'Expected api server definition.' }
if ($def.Servers['api'].Port -ne 8080) { throw 'Expected port 8080 on api server.' }
if ($def.Routes.Count -ne 4) { throw "Expected 4 routes, found $($def.Routes.Count)." }
Write-Output '  pass  api-server.ot parses and extracts server definition with 4 routes'

# Test 2: In-memory route dispatch & response evaluation
$healthResp = Invoke-OtterServerRoute -Routes $def.Routes -Method 'GET' -Path '/health'
if ($healthResp.StatusCode -ne 200 -or $healthResp.Content -ne 'OK') {
    throw "Expected 200 OK from /health, got $($healthResp.StatusCode) $($healthResp.Content)"
}

$greetResp = Invoke-OtterServerRoute -Routes $def.Routes -Method 'GET' -Path '/api/greeting'
if ($greetResp.StatusCode -ne 200 -or $greetResp.Content -ne 'Hello from Otter Web Server!') {
    throw "Expected greeting text, got $($greetResp.Content)"
}

$usersResp = Invoke-OtterServerRoute -Routes $def.Routes -Method 'GET' -Path '/api/users'
if ($usersResp.StatusCode -ne 200 -or $usersResp.ContentType -notmatch 'application/json') {
    throw "Expected JSON response from /api/users, got $($usersResp.ContentType)"
}

$postResp = Invoke-OtterServerRoute -Routes $def.Routes -Method 'POST' -Path '/api/users'
if ($postResp.StatusCode -ne 201 -or $postResp.ContentType -notmatch 'application/json') {
    throw "Expected 201 Created from POST /api/users, got $($postResp.StatusCode)"
}

$notFoundResp = Invoke-OtterServerRoute -Routes $def.Routes -Method 'GET' -Path '/nonexistent'
if ($notFoundResp.StatusCode -ne 404) {
    throw "Expected 404 for unknown route, got $($notFoundResp.StatusCode)"
}
Write-Output '  pass  route matching, JSON serialization, and status codes evaluate correctly'

# Test 3: Live HTTP socket test via native HttpListener
$testPort = 18989
$session = Start-OtterServer -Program $ast -Port $testPort -Host 'localhost'

try {
    # Launch async request handler
    $handlerJob = Start-Job -ScriptBlock {
        param($port)
        # Give server time to spin up
        Start-Sleep -Milliseconds 200
        $resp = Invoke-RestMethod -Uri "http://localhost:$port/health" -Method Get
        return $resp
    } -ArgumentList $testPort

    # Process the single request on the main thread
    $session.HandleNextRequest()

    $jobResult = Receive-Job -Job $handlerJob -Wait
    if ($jobResult -ne 'OK') {
        throw "Expected 'OK' from live HTTP request, got: $jobResult"
    }
    Remove-Job -Job $handlerJob -Force
    Write-Output '  pass  live HTTP request handled over loopback socket'
} finally {
    Stop-OtterServer -Session $session
}

Write-Output 'Server tests passed.'
