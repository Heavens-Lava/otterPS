using module ..\Otter.Contract.psm1

# Otter.Compiler.JavaScript.psm1
#
# D60: the universal Otter-AST -> JavaScript emitter. Portable behavior only
# - this module must know how Otter behaves, not where the generated
# JavaScript will run. No document/window/WebView/Tauri/Electron references
# belong here; those are target-adapter concerns (Otter.Web.psm1,
# Otter.Desktop.psm1, Otter.Console.psm1), which consume this module rather
# than the other way around.
#
# Phase 1A: extracted from Otter.Web.psm1 verbatim, behavior-preserving.
# No new syntax, no new NodeKind coverage, no output changes in this pass -
# see SPEC-DECISIONS.md D60 for the extraction contract this followed.
#
# Known pre-existing portability note, not fixed in this extraction (would
# be a behavior change, out of scope for a boring move): ConvertTo-
# OtterJsStatement's Assign/HttpGet/HttpPost cases fall back to a bare
# `window.<name>` global for variables outside otterState. `window` only
# exists in a browser target - a future console/desktop-neutral pass will
# need to route this through an injected runtime hook instead.

function ConvertTo-OtterJsExpression {
    param([Parameter(Mandatory)][Node]$Expr)

    switch ($Expr.Kind) {
        ([NodeKind]::Literal) {
            $val = $Expr.Value
            if ($null -eq $val) { return 'null' }
            if ($val -is [bool]) { return $(if ($val) { 'true' } else { 'false' }) }
            if ($val -is [double] -or $val -is [int] -or $val -is [long]) { return [string]$val }
            $escaped = [string]$val -replace '\\', '\\' -replace '"', '\"' -replace "`n", '\n' -replace "`r", ''
            return "`"$escaped`""
        }
        ([NodeKind]::Variable) {
            if ($Expr.Name -eq 'empty') { return '""' }
            if ($Expr.Name -eq 'gone') { return 'null' }
            return $Expr.Name
        }
        ([NodeKind]::PropertyAccess) {
            $prop = $Expr.Property.ToLowerInvariant()
            $target = $Expr.Target
            $targetName = if ($target -is [VariableExpr]) { $target.Name } else { 'target' }
            switch ($prop) {
                'text' { return "otterGetText('$targetName')" }
                'value' { return "otterGetText('$targetName')" }
                'title' { return "otterGetTitle('$targetName')" }
                'width' { return "otterGetStyle('$targetName', 'width')" }
                'height' { return "otterGetStyle('$targetName', 'height')" }
                default { return "otterGetProperty('$targetName', '$prop')" }
            }
        }
        ([NodeKind]::Math) {
            $left = ConvertTo-OtterJsExpression -Expr $Expr.Left
            $right = ConvertTo-OtterJsExpression -Expr $Expr.Right
            switch ($Expr.Op) {
                ([MathOp]::Add) {
                    if (($Expr.Left -is [LiteralExpr] -and $Expr.Left.Value -is [string]) -or
                        ($Expr.Right -is [LiteralExpr] -and $Expr.Right.Value -is [string]) -or
                        $left.StartsWith('"') -or $right.StartsWith('"')) {
                        return "($left + $right)"
                    }
                    return "(Number($left) + Number($right))"
                }
                ([MathOp]::Subtract) { return "(Number($left) - Number($right))" }
                ([MathOp]::Multiply) { return "(Number($left) * Number($right))" }
                ([MathOp]::Divide) { return "(Number($left) / Number($right))" }
            }
        }
        ([NodeKind]::Await) {
            $inner = ConvertTo-OtterJsExpression -Expr $Expr.Expression
            return "(await $inner)"
        }
        ([NodeKind]::Comparison) {
            $left = ConvertTo-OtterJsExpression -Expr $Expr.Left
            $right = ConvertTo-OtterJsExpression -Expr $Expr.Right
            switch ($Expr.Op) {
                ([CompareOp]::Equal) { return "($left === $right)" }
                ([CompareOp]::NotEqual) { return "($left !== $right)" }
                ([CompareOp]::AtLeast) { return "($left >= $right)" }
                ([CompareOp]::AtMost) { return "($left <= $right)" }
                ([CompareOp]::GreaterThan) { return "($left > $right)" }
                ([CompareOp]::LessThan) { return "($left < $right)" }
            }
        }
        ([NodeKind]::Logical) {
            $left = ConvertTo-OtterJsExpression -Expr $Expr.Left
            $right = ConvertTo-OtterJsExpression -Expr $Expr.Right
            switch ($Expr.Op) {
                ([LogicalOp]::And) { return "($left && $right)" }
                ([LogicalOp]::Or) { return "($left || $right)" }
            }
        }
        ([NodeKind]::Not) {
            $innerNode = if ($Expr.Operand) { $Expr.Operand } else { $Expr.Expression }
            $inner = ConvertTo-OtterJsExpression -Expr $innerNode
            return "(!$inner)"
        }
        ([NodeKind]::Contains) {
            $collection = ConvertTo-OtterJsExpression -Expr $Expr.Collection
            $item = ConvertTo-OtterJsExpression -Expr $Expr.Item
            return "($collection && $collection.includes ? $collection.includes($item) : false)"
        }
        default {
            return "null"
        }
    }
}

function ConvertTo-OtterJsStatement {
    param(
        [Parameter(Mandatory)][Node]$Stmt,
        [int]$Indent = 2
    )

    $pad = '  ' * $Indent

    switch ($Stmt.Kind) {
        ([NodeKind]::Assign) {
            if ($Stmt.Target -is [PropertyAccessExpr]) {
                $prop = $Stmt.Target.Property.ToLowerInvariant()
                $target = $Stmt.Target.Target
                $targetName = if ($target -is [VariableExpr]) { $target.Name } else { 'target' }
                $valExpr = ConvertTo-OtterJsExpression -Expr $Stmt.Value
                switch ($prop) {
                    'text' { return "${pad}otterSetText('$targetName', $valExpr);" }
                    'value' { return "${pad}otterSetText('$targetName', $valExpr);" }
                    'title' { return "${pad}otterSetTitle('$targetName', $valExpr);" }
                    'background' { return "${pad}otterSetStyle('$targetName', 'backgroundColor', $valExpr);" }
                    'foreground' { return "${pad}otterSetStyle('$targetName', 'color', $valExpr);" }
                    'width' { return "${pad}otterSetStyle('$targetName', 'width', typeof ($valExpr) === 'number' ? ($valExpr + 'px') : $valExpr);" }
                    'height' { return "${pad}otterSetStyle('$targetName', 'height', typeof ($valExpr) === 'number' ? ($valExpr + 'px') : $valExpr);" }
                    default { return "${pad}otterSetProperty('$targetName', '$prop', $valExpr);" }
                }
            }
            $varName = if ($Stmt.Target -is [VariableExpr]) { $Stmt.Target.Name } else { [string]$Stmt.Target }
            $valExpr = ConvertTo-OtterJsExpression -Expr $Stmt.Value
            return "${pad}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$varName' in otterState)) { otterSetState('$varName', $valExpr); } else { window.$varName = $valExpr; }"
        }
        ([NodeKind]::Say) {
            $parts = foreach ($p in $Stmt.Parts) { ConvertTo-OtterJsExpression -Expr $p }
            $joined = $parts -join ' + " " + '
            return "${pad}otterSay($joined);"
        }
        ([NodeKind]::If) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $first = $true
            foreach ($branch in $Stmt.Branches) {
                $cond = ConvertTo-OtterJsExpression -Expr $branch.Condition
                $keyword = if ($first) { "if ($cond)" } else { "else if ($cond)" }
                $lines.Add("${pad}$keyword {")
                foreach ($s in $branch.Body) {
                    $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1)))
                }
                $lines.Add("${pad}}")
                $first = $false
            }
            if ($Stmt.ElseBody -and $Stmt.ElseBody.Count -gt 0) {
                $lines.Add("${pad}else {")
                foreach ($s in $Stmt.ElseBody) {
                    $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1)))
                }
                $lines.Add("${pad}}")
            }
            return ($lines -join "`n")
        }
        ([NodeKind]::While) {
            $cond = ConvertTo-OtterJsExpression -Expr $Stmt.Condition
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}while ($cond) {")
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1)))
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::CountLoop) {
            # D60 Phase 1B. Matches Otter.Interpreter.psm1's 'CountLoop' case
            # exactly (verified against the real interpreter, not assumed
            # from JS `for`-loop habits):
            #   - both ends inclusive
            #   - descending ranges are valid ("count from 10 to 1" counts
            #     down); direction is decided once, from from<=to
            #   - From/To are evaluated exactly once, before the loop starts
            #     (bound in _from/_to below) - a mutating bound expression
            #     does not change an already-running loop
            #   - the loop variable has NO separate per-iteration scope: it
            #     is written into the same place a plain Assign would write
            #     it (otterState if reactive, else `window.<name>`), so it
            #     is still readable - and last-writer-wins shared with any
            #     nested loop reusing the same name - after the loop ends,
            #     matching SetLocal's real behavior (writes into the
            #     CURRENT environment, never a child scope)
            #   - the loop's own stepping counter (_n, below) is internal
            #     and is never re-read from the visible variable, so the
            #     body reassigning the visible variable does not affect
            #     iteration - matching the interpreter's PowerShell-local
            #     $n, which the same is true of
            #   - `stop` needs no special case: it parses to a bare Return
            #     node (verified via -DebugAst), and the existing Return
            #     case's `return;` already exits the whole enclosing JS
            #     function from inside a `for`, exactly matching D37
            # Non-numeric bounds are coerced via Number(), the same silent-
            # coercion convention the Math case already uses - not a new
            # gap introduced here, the same one already shipped.
            $fromJs = ConvertTo-OtterJsExpression -Expr $Stmt.From
            $toJs = ConvertTo-OtterJsExpression -Expr $Stmt.To
            $varName = $Stmt.VariableName
            $inner = '  ' * ($Indent + 1)
            $bodyIndent = '  ' * ($Indent + 2)
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _from = Number($fromJs);")
            $lines.Add("${inner}const _to = Number($toJs);")
            $lines.Add("${inner}const _step = _from <= _to ? 1 : -1;")
            $lines.Add("${inner}for (let _n = _from; (_step > 0 && _n <= _to) || (_step < 0 && _n >= _to); _n += _step) {")
            $lines.Add("${bodyIndent}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$varName' in otterState)) { otterSetState('$varName', _n); } else { window.$varName = _n; }")
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 2)))
            }
            $lines.Add("${inner}}")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::ListDef) {
            # D60 Phase 1C. Matches Otter.Interpreter.psm1's 'ListDef' case
            # exactly (verified against the real interpreter):
            #   - each item expression is evaluated exactly once, in order
            #   - duplicates are preserved (no dedup)
            #   - mixed element types are allowed
            #   - a literal empty list ("items are" with nothing indented
            #     under it) is already a PARSE-time error today (confirmed:
            #     Read-OtterListItems requires at least one indented item),
            #     so there is no empty-list-literal case to emit here
            #   - the parser only allows Read-OtterValue forms as items
            #     (literal, variable, property-access - confirmed: a full
            #     expression like `x plus 1` is a syntax error), so every
            #     item Otter can hand this case is something
            #     ConvertTo-OtterJsExpression already knows how to compile
            #   - THE NON-OBVIOUS ONE, verified directly: if an item
            #     expression evaluates to a LIST (e.g. a bare variable
            #     already holding a list), its elements are SPLICED into
            #     the new list rather than nested as one element - `outer
            #     are / inner / inner / .` produces a 4-element flat list,
            #     not a 2-element list of lists (length of outer is 4,
            #     first of outer is 1, not [1,2]). This falls out of
            #     PowerShell's own `+=` auto-enumerating an array RHS in
            #     the interpreter, intentional or not - it is current
            #     behavior, so it is preserved here via Array.isArray.
            #   - list assignment/sharing (`listB is listA` sharing the
            #     same underlying list, so mutating one mutates the other)
            #     needs no special handling: JS arrays are reference types
            #     by default, so a plain Assign of one list variable to
            #     another already behaves identically with zero extra code.
            $varName = $Stmt.Name
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}{")
            $itemsInner = '  ' * ($Indent + 1)
            $lines.Add("${itemsInner}const _items = [];")
            $itemIndex = 0
            foreach ($item in $Stmt.Items) {
                $itemJs = ConvertTo-OtterJsExpression -Expr $item
                $tmp = "_v$itemIndex"
                $lines.Add("${itemsInner}const $tmp = $itemJs;")
                $lines.Add("${itemsInner}if (Array.isArray($tmp)) { _items.push(...$tmp); } else { _items.push($tmp); }")
                $itemIndex++
            }
            $lines.Add("${itemsInner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$varName' in otterState)) { otterSetState('$varName', _items); } else { window.$varName = _items; }")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Repeat) {
            $count = ConvertTo-OtterJsExpression -Expr $Stmt.Count
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}for (let _i = 0; _i < $count; _i++) {")
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1)))
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::ForEach) {
            $coll = ConvertTo-OtterJsExpression -Expr $Stmt.Collection
            $var = $Stmt.VariableName
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}for (const $var of ($coll || [])) {")
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1)))
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Try) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("${pad}try {")
            foreach ($s in $Stmt.Body) {
                $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1)))
            }
            $lines.Add("${pad}} catch (_err) {")
            if ($Stmt.OtherwiseBody) {
                foreach ($s in $Stmt.OtherwiseBody) {
                    $lines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent ($Indent + 1)))
                }
            }
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Return) {
            if ($Stmt.Value) {
                $val = ConvertTo-OtterJsExpression -Expr $Stmt.Value
                return "${pad}return $val;"
            }
            return "${pad}return;"
        }
        ([NodeKind]::HttpGet) {
            $url = ConvertTo-OtterJsExpression -Expr $Stmt.Url
            $target = $Stmt.Target
            if ($Stmt.AsJson) {
                return "${pad}const res = await fetch($url); const $target = await res.json(); window.$target = $target;"
            }
            return "${pad}const res = await fetch($url); const $target = await res.text(); window.$target = $target;"
        }
        ([NodeKind]::HttpPost) {
            $data = ConvertTo-OtterJsExpression -Expr $Stmt.Data
            $url = ConvertTo-OtterJsExpression -Expr $Stmt.Url
            $target = $Stmt.Target
            $body = if ($Stmt.AsJson) { "JSON.stringify($data)" } else { "(typeof $data === 'object' ? JSON.stringify($data) : String($data))" }
            if ($target) {
                return "${pad}const res = await fetch($url, { method: 'POST', body: $body }); const $target = await res.text(); window.$target = $target;"
            }
            return "${pad}await fetch($url, { method: 'POST', body: $body });"
        }
        default {
            return ""
        }
    }
}

Export-ModuleMember -Function `
    ConvertTo-OtterJsExpression, ConvertTo-OtterJsStatement
