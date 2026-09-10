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
    function Add-Symbol([string]$name, [string]$kind, [int]$line) {
        if ($name -and -not ($symbols | Where-Object Name -eq $name)) {
            $symbols.Add([pscustomobject]@{ Name = $name; Kind = $kind; Line = $line; Column = 0 })
        }
    }
    function Visit([object]$node) {
        if ($null -eq $node) { return }
        switch ($node.GetType().Name) {
            'AssignStmt' { if ($node.Target.GetType().Name -eq 'VariableExpr') { $variables.Add($node.Target.Name); Add-Symbol $node.Target.Name 'variable' $node.Line }; Visit $node.Value }
            'ListDefStmt' { $variables.Add($node.Name); Add-Symbol $node.Name 'variable' $node.Line; foreach ($item in $node.Items) { Visit $item } }
            'AskStmt' { $variables.Add($node.Name); Add-Symbol $node.Name 'variable' $node.Line; Visit $node.Prompt }
            'FunctionDefStmt' { $functions.Add($node.Name); Add-Symbol $node.Name 'function' $node.Line; foreach ($p in $node.Parameters) { $variables.Add($p) }; foreach ($item in $node.Body) { Visit $item } }
            'ObjectDefStmt' {
                $variables.Add($node.Name); Add-Symbol $node.Name 'object' $node.Line
                $properties = [System.Collections.Generic.List[string]]::new()
                foreach ($item in $node.Properties) {
                    if ($item.GetType().Name -eq 'AssignStmt' -and $item.Target.GetType().Name -eq 'VariableExpr') {
                        $properties.Add($item.Target.Name)
                        Visit $item.Value
                    } else { Visit $item }
                }
                $objectProperties[$node.Name] = @($properties)
            }
            'CallStmt' { if ($node.ResultTarget) { $variables.Add($node.ResultTarget); Add-Symbol $node.ResultTarget 'variable' $node.Line }; Visit $node.Call }
        }
        foreach ($property in $node.PSObject.Properties) {
            if ($property.Name -in @('Target','Value','Items','Prompt','Body','Properties','Call')) { continue }
            if ($property.Value -is [System.Array]) { foreach ($child in $property.Value) { if ($null -ne $child -and $child.GetType().Name -like '*Node*') { Visit $child } } }
            elseif ($null -ne $property.Value -and $property.Value.GetType().Name -like '*Node*') { Visit $property.Value }
        }
    }
    foreach ($statement in $ast.Statements) { Visit $statement }
    [pscustomobject]@{ Ok = $true; Variables = @($variables | Select-Object -Unique); Functions = @($functions | Select-Object -Unique); Symbols = @($symbols); ObjectProperties = $objectProperties } | ConvertTo-Json -Compress -Depth 6
}
catch {
    $error = $_.Exception
    [pscustomobject]@{ Ok = $false; Message = $error.Message; Line = $error.Line; Column = $error.Column; SourceLine = $error.SourceLine; Suggestion = $error.Suggestion } | ConvertTo-Json -Compress
    exit 1
}
