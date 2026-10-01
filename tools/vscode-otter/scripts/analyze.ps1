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
    $references = [System.Collections.Generic.List[object]]::new()
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
    function Add-Symbol([string]$name, [string]$kind, [int]$line, [object]$scope, [string[]]$parameters = @()) {
        $existing = $symbols | Where-Object { $_.Name -eq $name -and $_.ScopeId -eq $scope.Id }
        if ($name -and -not $existing) {
            $column = 0
            if ($line -gt 0 -and $line -le $sourceLines.Count) { $found = $sourceLines[$line - 1].IndexOf($name); if ($found -ge 0) { $column = $found } }
            $sym = [pscustomobject]@{ Name = $name; Kind = $kind; Line = $line; Column = $column; ScopeId = $scope.Id; Parameters = @($parameters) }
            $symbols.Add($sym)
            $scope.Symbols.Add($name)
            $references.Add([pscustomobject]@{ Name = $name; Line = $line; Column = $column; ScopeId = $scope.Id; IsDeclaration = $true })
        } elseif ($existing -and $parameters -and $parameters.Count -gt 0 -and (-not $existing.Parameters -or $existing.Parameters.Count -eq 0)) {
            $existing.Parameters = @($parameters)
        }
    }
    function Resolve-SymbolScope([string]$name, [object]$scope) {
        $current = $scope
        while ($null -ne $current) {
            if ($symbols | Where-Object { $_.Name -eq $name -and $_.ScopeId -eq $current.Id }) { return $current.Id }
            $current = $scopes | Where-Object { $_.Id -eq $current.Parent } | Select-Object -First 1
        }
        return -1
    }
    function Visit([object]$node, [object]$scope) {
        if ($null -eq $node) { return }
        if ($node.Line -gt $scope.EndLine) { $scope.EndLine = $node.Line }
        switch ($node.GetType().Name) {
            'VariableExpr' {
                $symbolScope = Resolve-SymbolScope $node.Name $scope
                if ($symbolScope -ge 0) { $lineText = if ($node.Line -le $sourceLines.Count) { $sourceLines[$node.Line - 1] } else { '' }; $column = $lineText.IndexOf($node.Name); if ($column -lt 0) { $column = 0 }; $references.Add([pscustomobject]@{ Name = $node.Name; Line = $node.Line; Column = $column; ScopeId = $symbolScope; IsDeclaration = $false }) }
            }
            'CallExpr' {
                $symbolScope = Resolve-SymbolScope $node.Name $scope
                if ($symbolScope -ge 0) { $lineText = if ($node.Line -le $sourceLines.Count) { $sourceLines[$node.Line - 1] } else { '' }; $column = $lineText.IndexOf($node.Name); if ($column -lt 0) { $column = 0 }; $references.Add([pscustomobject]@{ Name = $node.Name; Line = $node.Line; Column = $column; ScopeId = $symbolScope; IsDeclaration = $false }) }
            }
            'AssignStmt' {
                if ($node.Target.GetType().Name -eq 'VariableExpr') {
                    $variables.Add($node.Target.Name)
                    # Assignment updates the variable where it already lives
                    # (Environment.Set in Otter.Runtime.psm1): inside a
                    # function, `currentPage is name` writes the top-level
                    # currentPage - a write to it, not a new local.
                    $outerScope = Resolve-SymbolScope $node.Target.Name $scope
                    if ($outerScope -ge 0 -and $outerScope -ne $scope.Id) {
                        $lineText = if ($node.Line -le $sourceLines.Count) { $sourceLines[$node.Line - 1] } else { '' }
                        $column = $lineText.IndexOf($node.Target.Name); if ($column -lt 0) { $column = 0 }
                        $references.Add([pscustomobject]@{ Name = $node.Target.Name; Line = $node.Line; Column = $column; ScopeId = $outerScope; IsDeclaration = $true })
                    } else {
                        Add-Symbol $node.Target.Name 'variable' $node.Line $scope
                    }
                }
                Visit $node.Value $scope
            }
            'ListDefStmt' { $variables.Add($node.Name); Add-Symbol $node.Name 'variable' $node.Line $scope; foreach ($item in $node.Items) { Visit $item $scope } }
            'AskStmt' { $variables.Add($node.Name); Add-Symbol $node.Name 'variable' $node.Line $scope; Visit $node.Prompt $scope }
            'FunctionDefStmt' {
                $functions.Add($node.Name); Add-Symbol $node.Name 'function' $node.Line $scope $node.Parameters
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
        # Properties the case above already visited (or must not, like an
        # assignment's Target, which is a write). Only for those node types:
        # skipping Value everywhere lost every read in `return result`,
        # `set ... to value`, `respond` and the rest - a variable read only
        # there was reported as never read, and Find References missed it.
        $handled = switch ($node.GetType().Name) {
            'AssignStmt' { @('Target', 'Value') }
            'ListDefStmt' { @('Items') }
            'AskStmt' { @('Prompt') }
            'FunctionDefStmt' { @('Body') }
            'ObjectDefStmt' { @('Properties') }
            'ForEachStmt' { @('Body', 'Collection') }
            'CountStmt' { @('Body', 'From', 'To') }
            'CallStmt' { @('Call') }
            default { @() }
        }
        foreach ($property in $node.PSObject.Properties) {
            if ($property.Name -in $handled) { continue }
            if ($property.Value -is [System.Array]) { foreach ($child in $property.Value) { if ($null -ne $child -and $null -ne $child.PSObject.Properties['Line']) { Visit $child $scope } } }
            elseif ($null -ne $property.Value -and $null -ne $property.Value.PSObject.Properties['Line']) { Visit $property.Value $scope }
        }
    }
    foreach ($statement in $ast.Statements) { Visit $statement $rootScope }
    $rootScope.EndLine = [Math]::Max($rootScope.EndLine, $sourceLines.Count)
    [pscustomobject]@{ Ok = $true; Variables = @($variables | Select-Object -Unique); Functions = @($functions | Select-Object -Unique); Symbols = @($symbols); References = @($references); Scopes = @($scopes); ObjectProperties = $objectProperties } | ConvertTo-Json -Compress -Depth 8
}
catch {
    $err = $_.Exception
    [pscustomobject]@{ Ok = $false; Message = $err.Message; Line = $err.Line; Column = $err.Column; SourceLine = $err.SourceLine; Suggestion = $err.Suggestion } | ConvertTo-Json -Compress
    exit 1
}
