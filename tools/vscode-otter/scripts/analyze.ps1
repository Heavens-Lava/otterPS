param([Parameter(Mandatory=$true)][string]$Root)

$ErrorActionPreference = 'Stop'
$source = [Console]::In.ReadToEnd()
try {
    Import-Module "$Root\src\Otter.Lexer.psm1" -Force
    Import-Module "$Root\src\Otter.Parser.psm1" -Force
    $ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source)
    $variables = [System.Collections.Generic.List[string]]::new()
    $functions = [System.Collections.Generic.List[string]]::new()
    function Visit([object]$node) {
        if ($null -eq $node) { return }
        switch ($node.GetType().Name) {
            'AssignStmt' { if ($node.Target.GetType().Name -eq 'VariableExpr') { $variables.Add($node.Target.Name) }; Visit $node.Value }
            'ListDefStmt' { $variables.Add($node.Name); foreach ($item in $node.Items) { Visit $item } }
            'AskStmt' { $variables.Add($node.Name); Visit $node.Prompt }
            'FunctionDefStmt' { $functions.Add($node.Name); foreach ($p in $node.Parameters) { $variables.Add($p) }; foreach ($item in $node.Body) { Visit $item } }
            'ObjectDefStmt' { $variables.Add($node.Name); foreach ($item in $node.Properties) { Visit $item } }
            'CallStmt' { if ($node.ResultTarget) { $variables.Add($node.ResultTarget) }; Visit $node.Call }
        }
        foreach ($property in $node.PSObject.Properties) {
            if ($property.Name -in @('Target','Value','Items','Prompt','Body','Properties','Call')) { continue }
            if ($property.Value -is [System.Array]) { foreach ($child in $property.Value) { if ($null -ne $child -and $child.GetType().Name -like '*Node*') { Visit $child } } }
            elseif ($null -ne $property.Value -and $property.Value.GetType().Name -like '*Node*') { Visit $property.Value }
        }
    }
    foreach ($statement in $ast.Statements) { Visit $statement }
    [pscustomobject]@{ Ok = $true; Variables = @($variables | Select-Object -Unique); Functions = @($functions | Select-Object -Unique) } | ConvertTo-Json -Compress
}
catch {
    $error = $_.Exception
    [pscustomobject]@{ Ok = $false; Message = $error.Message; Line = $error.Line; Column = $error.Column; SourceLine = $error.SourceLine; Suggestion = $error.Suggestion } | ConvertTo-Json -Compress
    exit 1
}
