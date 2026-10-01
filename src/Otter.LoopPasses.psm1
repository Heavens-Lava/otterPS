using module ..\Otter.Contract.psm1

# Otter.LoopPasses.psm1 - which names belong to each loop pass (D130).
#
# A handler set up during a loop pass remembers that pass. The names that
# belong to a pass are the loop variable and every name the loop body sets
# that is set nowhere else in the same scope (the program's top level, or one
# function's body with its parameters). Everything else - counters, totals,
# anything that existed before the loop - is shared and read live.
#
# The interpreter and the JavaScript compiler both use this one analysis, so
# the console and the web agree. The result maps each loop node (by
# reference) to a HashSet of its pass names.

# The variable names one statement sets (not its children's).
function Get-OtterStatementBindings {
    param([Node]$Statement)
    $names = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Statement) { return , $names }
    if ($Statement -is [FunctionDefStmt]) { return , $names }
    if ($Statement.Kind -eq [NodeKind]::Assign) {
        if ($Statement.Target -is [VariableExpr]) { $names.Add($Statement.Target.Name) }
        return , $names
    }
    foreach ($prop in @('Target', 'ResultTarget', 'TargetName', 'ErrorTarget', 'RequestTarget', 'ItemName', 'VariableName')) {
        $p = $Statement.PSObject.Properties[$prop]
        if ($p -and $p.Value -is [string] -and $p.Value) { $names.Add($p.Value) }
    }
    if ($Statement.Kind -eq [NodeKind]::ListDef -or $Statement.Kind -eq [NodeKind]::ObjectDef) {
        if ($Statement.Name) { $names.Add($Statement.Name) }
    }
    return , $names
}

# The statement lists directly inside one statement: bodies, branches,
# otherwise blocks and handler bodies. Function bodies are their own scope.
function Get-OtterChildStatementLists {
    param([Node]$Statement)
    $lists = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Statement -or $Statement -is [FunctionDefStmt]) { return , $lists }
    foreach ($p in $Statement.PSObject.Properties) {
        $v = $p.Value
        if ($null -eq $v -or $v -is [string] -or $v -is [Node]) { continue }
        if ($v -is [System.Collections.IEnumerable]) {
            $stmts = [System.Collections.Generic.List[Node]]::new()
            foreach ($item in $v) {
                if ($item -is [Node]) { $stmts.Add($item) }
                elseif ($null -ne $item -and $item.PSObject.Properties['Body'] -and $item.Body -is [System.Collections.IEnumerable]) {
                    $lists.Add(@($item.Body | Where-Object { $_ -is [Node] }))
                }
            }
            if ($stmts.Count -gt 0) { $lists.Add($stmts.ToArray()) }
        }
    }
    return , $lists
}

function Test-OtterLoopStatement {
    param([Node]$Statement)
    return ($null -ne $Statement -and $Statement.Kind -in @([NodeKind]::ForEach, [NodeKind]::CountLoop, [NodeKind]::Repeat, [NodeKind]::While))
}

# Statements whose body runs later, with the variables of the place it was
# written: only a loop that sets one of these up needs a scope per pass.
# Without one, a pass scope changes nothing a program can see, so such loops
# get no pass names and run exactly as they did before D130 (a scope per pass
# costs PowerShell a few milliseconds each).
$script:OtterDeferredKinds = @(
    [NodeKind]::When, [NodeKind]::WebRoute, [NodeKind]::UiEvent, [NodeKind]::MemoDef,
    [NodeKind]::Watch, [NodeKind]::Lifecycle, [NodeKind]::RouteChange,
    [NodeKind]::WatchEvent, [NodeKind]::NetworkEvent
)

function Test-OtterContainsDeferredBody {
    param($Stmts)
    foreach ($s in @($Stmts)) {
        if ($s -isnot [Node]) { continue }
        if ($s.Kind -in $script:OtterDeferredKinds) { return $true }
        foreach ($list in (Get-OtterChildStatementLists -Statement $s)) {
            if (Test-OtterContainsDeferredBody -Stmts $list) { return $true }
        }
    }
    return $false
}

function Get-OtterLoopPassNames {
    param([Node[]]$Statements)
    $result = @{}

    # Every binding in a scope, each with the loops (innermost last) it sits in.
    function Add-OtterScopeBindings {
        param($Stmts, $LoopStack, $Occurrences, $Loops, $Scopes)
        foreach ($s in @($Stmts)) {
            if ($s -isnot [Node]) { continue }
            if ($s -is [FunctionDefStmt]) { $Scopes.Add($s); continue }
            foreach ($n in (Get-OtterStatementBindings -Statement $s)) {
                # A loop's own variable belongs to that loop's passes.
                $owner = if ((Test-OtterLoopStatement $s) -and $n -eq $s.VariableName) { @($LoopStack) + @($s) } else { @($LoopStack) }
                $Occurrences.Add(@{ Name = $n; Loops = $owner })
            }
            $inner = $LoopStack
            if (Test-OtterLoopStatement $s) { $Loops.Add($s); $inner = @($LoopStack) + @($s) }
            foreach ($list in (Get-OtterChildStatementLists -Statement $s)) {
                Add-OtterScopeBindings -Stmts $list -LoopStack $inner -Occurrences $Occurrences -Loops $Loops -Scopes $Scopes
            }
        }
    }

    $pending = [System.Collections.Generic.Queue[object]]::new()
    $pending.Enqueue(@{ Body = $Statements; Parameters = @() })
    while ($pending.Count -gt 0) {
        $scope = $pending.Dequeue()
        $occurrences = [System.Collections.Generic.List[object]]::new()
        $loops = [System.Collections.Generic.List[object]]::new()
        $functions = [System.Collections.Generic.List[object]]::new()
        Add-OtterScopeBindings -Stmts $scope.Body -LoopStack @() -Occurrences $occurrences -Loops $loops -Scopes $functions
        foreach ($loop in $loops) {
            $inside = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $outside = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($p in @($scope.Parameters)) { [void]$outside.Add($p) }
            foreach ($o in $occurrences) {
                $within = $false
                foreach ($l in $o.Loops) { if ([object]::ReferenceEquals($l, $loop)) { $within = $true; break } }
                if ($within) { [void]$inside.Add($o.Name) } else { [void]$outside.Add($o.Name) }
            }
            $inside.ExceptWith($outside)
            if (-not (Test-OtterContainsDeferredBody -Stmts $loop.Body)) { $inside.Clear() }
            $result[$loop] = $inside
        }
        foreach ($f in $functions) {
            $pending.Enqueue(@{ Body = $f.Body; Parameters = @($f.Parameters) })
        }
    }
    return $result
}

Export-ModuleMember -Function Get-OtterLoopPassNames, Test-OtterLoopStatement
