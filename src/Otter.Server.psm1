using module ..\Otter.Contract.psm1

# src/Otter.Server.psm1
# Otter Web Server and API Route Engine (D51)
# Readable HTTP services with native .NET HttpListener

function Get-OtterServerDefinition {
    param([Parameter(Mandatory)][ProgramNode]$Program)

    $servers = [ordered]@{}
    $routes = [System.Collections.Generic.List[WebRouteStmt]]::new()
    $startServers = [System.Collections.Generic.List[StartServerStmt]]::new()
    $listenServers = [System.Collections.Generic.List[ListenServerStmt]]::new()

    foreach ($stmt in $Program.Statements) {
        if ($stmt -is [ObjectDefStmt] -and $stmt.TypeName -eq 'web server') {
            $port = 8080
            $hostName = 'localhost'
            if ($stmt.Properties) {
                foreach ($prop in $stmt.Properties) {
                    if ($prop -is [AssignStmt]) {
                        $propName = if ($prop.Target -is [VariableExpr]) { $prop.Target.Name } else { [string]$prop.Target }
                        if ($propName -eq 'port' -and $prop.Value -is [LiteralExpr]) {
                            $port = [int]$prop.Value.Value
                        } elseif ($propName -eq 'host' -and $prop.Value -is [LiteralExpr]) {
                            $hostName = [string]$prop.Value.Value
                        }
                    }
                }
            }
            $servers[$stmt.Name] = @{
                Name = $stmt.Name
                Port = $port
                Host = $hostName
            }
        } elseif ($stmt -is [WebRouteStmt]) {
            $routes.Add($stmt)
        } elseif ($stmt -is [StartServerStmt]) {
            $startServers.Add($stmt)
        } elseif ($stmt -is [ListenServerStmt]) {
            $listenServers.Add($stmt)
        }
    }

    # If no server object declared but routes exist, provide a default server
    if ($servers.Count -eq 0 -and $routes.Count -gt 0) {
        $defaultPort = 8080
        if ($listenServers.Count -gt 0 -and $listenServers[0].Port -is [LiteralExpr]) {
            $defaultPort = [int]$listenServers[0].Port.Value
        }
        $servers['server'] = @{
            Name = 'server'
            Port = $defaultPort
            Host = 'localhost'
        }
    }

    return @{
        Servers = $servers
        Routes = $routes.ToArray()
        StartServers = $startServers.ToArray()
        ListenServers = $listenServers.ToArray()
    }
}

function Find-OtterMatchingRoute {
    param(
        [WebRouteStmt[]]$Routes,
        [string]$Method,
        [string]$Path
    )

    $reqMethod = $Method.ToUpperInvariant()
    $normalizedPath = if ($Path.StartsWith('/')) { $Path } else { '/' + $Path }
    if ($normalizedPath.Length -gt 1 -and $normalizedPath.EndsWith('/')) {
        $normalizedPath = $normalizedPath.TrimEnd('/')
    }

    foreach ($route in $Routes) {
        # Check method
        $routeMethod = $route.Method.ToUpperInvariant()
        if ($routeMethod -ne 'ALL' -and $routeMethod -ne 'REQUEST' -and $routeMethod -ne $reqMethod) {
            continue
        }

        # Check path
        $routePath = ''
        if ($route.Path -is [LiteralExpr]) {
            $routePath = [string]$route.Path.Value
        }
        if (-not $routePath.StartsWith('/')) { $routePath = '/' + $routePath }
        if ($routePath.Length -gt 1 -and $routePath.EndsWith('/')) {
            $routePath = $routePath.TrimEnd('/')
        }

        if ($routePath -eq $normalizedPath) {
            return $route
        }
    }

    return $null
}

function Invoke-OtterServerRoute {
    param(
        [Parameter(Mandatory)][WebRouteStmt[]]$Routes,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [object]$Body = $null,
        [hashtable]$Headers = @{},
        [hashtable]$Query = @{}
    )

    $matched = Find-OtterMatchingRoute -Routes $Routes -Method $Method -Path $Path
    if ($null -eq $matched) {
        return @{
            StatusCode = 404
            ContentType = 'application/json'
            Content = '{"error":"Not Found"}'
            Headers = @{}
        }
    }

    # Execute route statements
    $responseResult = @{
        StatusCode = 200
        ContentType = 'text/plain; charset=utf-8'
        Content = ''
        Headers = @{}
    }

    foreach ($stmt in $matched.Body) {
        if ($stmt -is [RespondStmt]) {
            $val = $null
            if ($null -ne $stmt.Value) {
                if ($stmt.Value -is [LiteralExpr]) {
                    $val = $stmt.Value.Value
                } else {
                    $val = [string]$stmt.Value
                }
            }

            $status = 200
            if ($null -ne $stmt.Status -and $stmt.Status -is [LiteralExpr]) {
                $status = [int]$stmt.Status.Value
            }

            $responseResult.StatusCode = $status

            if ($stmt.AsJson) {
                $responseResult.ContentType = 'application/json; charset=utf-8'
                $responseResult.Content = if ($null -ne $val) { ConvertTo-Json -InputObject $val -Compress } else { 'null' }
            } elseif ($null -ne $val) {
                $responseResult.Content = [string]$val
            } else {
                $responseResult.Content = ''
            }
            break
        }
    }

    return $responseResult
}

class OtterServerSession {
    [System.Net.HttpListener]$Listener
    [int]$Port
    [string]$Host
    [WebRouteStmt[]]$Routes
    [bool]$IsRunning

    OtterServerSession([int]$port, [string]$hostName, [WebRouteStmt[]]$routes) {
        $this.Port = $port
        $this.Host = $hostName
        $this.Routes = $routes
        $this.Listener = [System.Net.HttpListener]::new()
        $this.IsRunning = $false
    }

    [void] Start() {
        $prefix = "http://$($this.Host):$($this.Port)/"
        $this.Listener.Prefixes.Add($prefix)
        $this.Listener.Start()
        $this.IsRunning = $true
    }

    [void] Stop() {
        if ($this.IsRunning) {
            $this.IsRunning = $false
            $this.Listener.Stop()
            $this.Listener.Close()
        }
    }

    [void] HandleNextRequest() {
        if (-not $this.IsRunning) { return }
        $context = $this.Listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $reqBody = ''
        if ($request.HasEntityBody) {
            $reader = [System.IO.StreamReader]::new($request.InputStream, $request.ContentEncoding)
            $reqBody = $reader.ReadToEnd()
            $reader.Close()
        }

        $result = Invoke-OtterServerRoute -Routes $this.Routes -Method $request.HttpMethod -Path $request.Url.AbsolutePath -Body $reqBody

        $response.StatusCode = $result.StatusCode
        $response.ContentType = $result.ContentType

        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$result.Content)
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.OutputStream.Close()
    }
}

function Start-OtterServer {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [int]$Port = 0,
        [string]$Host = 'localhost'
    )

    $def = Get-OtterServerDefinition -Program $Program
    $targetPort = if ($Port -gt 0) { $Port } else {
        if ($def.Servers.Count -gt 0) {
            $first = $def.Servers.GetEnumerator() | Select-Object -First 1
            $first.Value.Port
        } else { 8080 }
    }

    $targetHost = if ($Host -ne 'localhost') { $Host } else {
        if ($def.Servers.Count -gt 0) {
            $first = $def.Servers.GetEnumerator() | Select-Object -First 1
            $first.Value.Host
        } else { 'localhost' }
    }

    $session = [OtterServerSession]::new($targetPort, $targetHost, $def.Routes)
    $session.Start()
    Write-Verbose "Otter web server listening on http://$($targetHost):$($targetPort)/"
    return $session
}

function Stop-OtterServer {
    param([Parameter(Mandatory)][OtterServerSession]$Session)
    $Session.Stop()
}

Export-ModuleMember -Function Get-OtterServerDefinition, Find-OtterMatchingRoute, Invoke-OtterServerRoute, Start-OtterServer, Stop-OtterServer
