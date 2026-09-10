param([Parameter(Mandatory=$true)][string]$Root)

$ErrorActionPreference = 'Stop'
$source = [Console]::In.ReadToEnd()
try {
    Import-Module "$Root\src\Otter.Lexer.psm1" -Force
    Import-Module "$Root\src\Otter.Parser.psm1" -Force
    $ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source)
    $variables = [System.Collections.Generic.List[string]]::new()
    $functions = [System.Collections.Generic.List[string]]::new()
    $symbols = [System.Collections.Generic.List[object]]::new()
    $objectProperties = @{}
    $scopes = [System.Collections.Generic.List[object]]::new()
    $scopeCounter = 0
    $sourceLines = $source -split "`r?`n"
    function New-Scope([int]$parent, [int]$start) {
        $scope = [pscustomobject]@{ Id = $script:scopeCounter++; Parent = $parent; StartLine = $start; EndLine = $start; Symbols = [System.Collections.Generic.List[string]]::new() }
        $scopes.Add($scope)
        return $scope
    }
    $rootScope = New-Scope -parent -1 -start 1
    function Add-Symbol([string]$name, [string]$kind, [int]$line, [object]$scope) {
        if ($name -and -not ($symbols | Where-Object { $_.Name -eq $name -and $_.ScopeId -eq $scope.Id })) {
            $column = 0
            if ($line -gt 0 -and $line -le $sourceLines.Count) { $found = $sourceLines[$line - 1].IndexOf($name); if ($found -ge 0) { $column = $found } }
            $symbols.Add([pscustomobject]@{ Name = $name; Kind = $kind; Line = $line; Column = $column; ScopeId = $scope.Id })
            $scope.Symbols.Add($name)
        }
    }
    function Visit([object]$node, [object]$scope) {
        if ($null -eq $node) { return }
        if ($node.Line -gt $scope.EndLine) { $scope.EndLine = $node.Line }
        switch ($node.GetType().Name) {
            'AssignStmt' { if ($node.Target.GetType().Name -eq 'VariableExpr') { $variables.Add($node.Target.Name); Add-Symbol $node.Target.Name 'variable' $node.Line $scope }; Visit $node.Value $scope }
            'ListDefStmt' { $variables.Add($node.Name); Add-Symbol $node.Name 'variable' $node.Line $scope; foreach ($item in $node.Items) { Visit $item $scope } }
            'AskStmt' { $variables.Add($node.Name); Add-Symbol $node.Name 'variable' $node.Line $scope; Visit $node.Prompt $scope }
            'FunctionDefStmt' {
                $functions.Add($node.Name); Add-Symbol $node.Name 'function' $node.Line $scope
                $child = New-Scope $scope.Id $node.Line
                foreach ($p in $node.Parameters) { $variables.Add($p); Add-Symbol $p 'parameter' $node.Line $child }
                foreach ($item in $node.Body) { Visit $item $child }
            }
            'ObjectDefStmt' {
                $variables.Add($node.Name); Add-Symbol $node.Name 'object' $node.Line $scope
                $properties = [System.Collections.Generic.List[string]]::new()
                foreach ($item in $node.Properties) {
                    if ($item.GetType().Name -eq 'AssignStmt' -and $item.Target.GetType().Name -eq 'VariableExpr') {
                        $properties.Add($item.Target.Name)
                        Visit $item.Value $scope
                    } else { Visit $item $scope }
                }
                $objectProperties[$node.Name] = @($properties)
            }
            'ForEachStmt' {
                Visit $node.Collection $scope
                $child = New-Scope $scope.Id $node.Line
                Add-Symbol $node.VariableName 'loop variable' $node.Line $child
                foreach ($item in $node.Body) { Visit $item $child }
            }
            'CountStmt' {
                Visit $node.From $scope; Visit $node.To $scope
                $child = New-Scope $scope.Id $node.Line
                Add-Symbol $node.VariableName 'loop variable' $node.Line $child
                foreach ($item in $node.Body) { Visit $item $child }
            }
            'CallStmt' { if ($node.ResultTarget) { $variables.Add($node.ResultTarget); Add-Symbol $node.ResultTarget 'variable' $node.Line $scope }; Visit $node.Call $scope }
        }
        foreach ($property in $node.PSObject.Properties) {
            if ($property.Name -in @('Target','Value','Items','Prompt','Body','Properties','Call')) { continue }
            if ($property.Value -is [System.Array]) { foreach ($child in $property.Value) { if ($null -ne $child -and $child.GetType().Name -like '*Node*') { Visit $child $scope } } }
            elseif ($null -ne $property.Value -and $property.Value.GetType().Name -like '*Node*') { Visit $property.Value $scope }
        }
    }
    foreach ($statement in $ast.Statements) { Visit $statement $rootScope }
    $rootScope.EndLine = [Math]::Max($rootScope.EndLine, $sourceLines.Count)
    [pscustomobject]@{ Ok = $true; Variables = @($variables | Select-Object -Unique); Functions = @($functions | Select-Object -Unique); Symbols = @($symbols); Scopes = @($scopes); ObjectProperties = $objectProperties } | ConvertTo-Json -Compress -Depth 8
}
catch {
    $error = $_.Exception
    [pscustomobject]@{ Ok = $false; Message = $error.Message; Line = $error.Line; Column = $error.Column; SourceLine = $error.SourceLine; Suggestion = $error.Suggestion } | ConvertTo-Json -Compress
    exit 1
}
