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
                    # D60 Phase 1D-B. The old check here was STATIC (did the
                    # AST show a literal string, or did the generated JS text
                    # start with a quote?) - wrong whenever a string arrives
                    # through a variable rather than a literal, which is the
                    # common case ("joined is joined plus item" produced
                    # "NaN", not the concatenation the interpreter actually
                    # does). Matches Otter.Interpreter.psm1's real 'Math'
                    # case exactly instead, verified against the interpreter
                    # for every combination before writing this, not assumed:
                    #   - "a" plus "b" -> "ab" (both operands are STRING
                    #     TYPE, so concatenate - unconditionally, even if
                    #     both look numeric: "5" plus "3" concatenates to
                    #     "53", it does NOT add to 8)
                    #   - "5" plus 3 / 5 plus "3" -> 8 (only one side is a
                    #     string, so both sides are coerced to numbers
                    #     instead - a numeric-looking string parses fine)
                    #   - 5 plus 10 -> 15 (plain arithmetic)
                    #   - "a" plus 5 / 5 plus "a" -> throws (a non-numeric
                    #     string fails coercion, matching Assert-OtterNumber)
                    #   - "" or "  " plus 5 -> throws (empty/whitespace-only
                    #     fails coercion too, matching .NET's double.TryParse)
                    #   - true plus 5 -> throws (booleans are explicitly
                    #     rejected as numeric, matching Test-OtterNumeric's
                    #     `if ($Value -is [bool]) { return $false }` - a
                    #     naive Number(true) would silently succeed as 1 in
                    #     JS, which is exactly the kind of gap this phase
                    #     exists to close)
                    # This is a RUNTIME check (typeof, on the actual value),
                    # not a static one - that is the whole fix. An IIFE is
                    # used because this is expression position; no shared
                    # runtime helper was added to keep this change entirely
                    # inside this module (Otter.Web.psm1's boilerplate is
                    # untouched).
                    return "(() => { const _l = $left; const _r = $right; if (typeof _l === 'string' && typeof _r === 'string') { return _l + _r; } const _lOk = typeof _l === 'number' || (typeof _l === 'string' && _l.trim() !== '' && !Number.isNaN(Number(_l))); if (!_lOk) { throw new Error('I expected a number for the left side of this calculation but got ' + JSON.stringify(_l) + '.'); } const _rOk = typeof _r === 'number' || (typeof _r === 'string' && _r.trim() !== '' && !Number.isNaN(Number(_r))); if (!_rOk) { throw new Error('I expected a number for the right side of this calculation but got ' + JSON.stringify(_r) + '.'); } return Number(_l) + Number(_r); })()"
                }
                # Subtract/Multiply/Divide have the SAME underlying gap
                # (Assert-OtterNumber throws on a non-numeric operand in the
                # interpreter; Number(...) here silently produces NaN
                # instead) - confirmed present, deliberately NOT fixed in
                # this commit. Phase 1D-B's scope, per instruction, is `plus`
                # specifically; this is flagged as a separate, still-open
                # finding, not silently folded in here.
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
        ([NodeKind]::TextMatch) {
            # D60 Phase 1D-A. Matches Otter.Interpreter.psm1's 'TextMatch'
            # case: both operands go through Format-OtterValue first (so
            # this works on any formattable value, not just string
            # literals), comparison is ordinal/case-sensitive (confirmed:
            # "jeff" does not match a subject starting with "Jeff"), result
            # is a plain boolean. String(...) stands in for Format-
            # OtterValue here - full parity (list-joining, Otter's exact
            # number formatting) is not attempted, matching-string use is
            # the case this was verified against.
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Expr.Subject
            $valueJs = ConvertTo-OtterJsExpression -Expr $Expr.Value
            $method = if ($Expr.Match.ToString() -eq 'StartsWith') { 'startsWith' } else { 'endsWith' }
            return "String($subjectJs).$method(String($valueJs))"
        }
        ([NodeKind]::OfOperation) {
            # D60 Phase 1D-A: Uppercase/Lowercase only. Length/First/Last
            # are part of the same OfOperation NodeKind but are DELIBERATELY
            # left unhandled here (falling through to the same "null"
            # default every other unimplemented case already returns) -
            # verified against the interpreter that Length is polymorphic
            # (works on lists too) and First/Last are list-only, so all
            # three belong with Phase 1E's collection-operations work, not
            # bundled into this string-operations commit.
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Expr.Subject
            switch ($Expr.Operation.ToString()) {
                'Uppercase' { return "String($subjectJs).toUpperCase()" }
                'Lowercase' { return "String($subjectJs).toLowerCase()" }
                default { return "null" }
            }
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
        ([NodeKind]::Replace) {
            # D60 Phase 1D-A. Matches Otter.Interpreter.psm1's 'Replace'
            # case exactly:
            #   - Target is a variable NAME, read directly (not a general
            #     expression) - mirrors the interpreter's
            #     $Environment.Get/Set($Statement.Target)
            #   - empty find text is a thrown runtime error, not a silent
            #     no-op (confirmed: "I cannot replace empty text.")
            #   - ALL occurrences are replaced, not just the first
            #     (confirmed: .NET's String.Replace replaces every
            #     occurrence in one pass) - split+join gives the same
            #     single-pass, non-recursive, literal-substring (no regex)
            #     replacement semantics
            #   - VERIFIED DEAD IN THE CURRENT PARSER, so not implemented:
            #     the contract's ResultTarget field ("replace X with Y in
            #     text into newText", leaving the source unchanged) has no
            #     parser support today - Read-OtterStatement's Replace case
            #     always asserts Newline immediately after the target, so
            #     ResultTarget is always $null in practice. Only the
            #     in-place mutation path is reachable, so only that path is
            #     emitted here.
            $findJs = ConvertTo-OtterJsExpression -Expr $Stmt.Find
            $replacementJs = ConvertTo-OtterJsExpression -Expr $Stmt.Replacement
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _find = String($findJs);")
            $lines.Add("${inner}if (_find.length === 0) { throw new Error('I cannot replace empty text.'); }")
            $lines.Add("${inner}const _replaced = String($target).split(_find).join(String($replacementJs));")
            $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _replaced); } else { window.$target = _replaced; }")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        ([NodeKind]::Split) {
            # D60 Phase 1D-A. Matches Otter.Interpreter.psm1's 'Split' case:
            #   - Subject and Separator are both general expressions
            #   - empty separator is a thrown runtime error ("I need
            #     something to split by."), not a silent no-op
            #   - StringSplitOptions.None means empty entries ARE kept in
            #     the result (confirmed: "a,,b" by "," gives 3 pieces, the
            #     middle one empty) - JS's native .split(sep) already keeps
            #     empty entries by default, so no extra handling is needed
            #     to match this
            #   - the result is a genuine list (Phase 1C's ListDef write
            #     pattern - otterState-or-window - reused here, since a
            #     plain JS array is already the correct representation)
            $subjectJs = ConvertTo-OtterJsExpression -Expr $Stmt.Subject
            $separatorJs = ConvertTo-OtterJsExpression -Expr $Stmt.Separator
            $target = $Stmt.Target
            $lines = [System.Collections.Generic.List[string]]::new()
            $inner = '  ' * ($Indent + 1)
            $lines.Add("${pad}{")
            $lines.Add("${inner}const _sep = String($separatorJs);")
            $lines.Add("${inner}if (_sep.length === 0) { throw new Error('I need something to split by.'); }")
            $lines.Add("${inner}const _pieces = String($subjectJs).split(_sep);")
            $lines.Add("${inner}if (typeof otterSetState === 'function' && typeof otterState !== 'undefined' && ('$target' in otterState)) { otterSetState('$target', _pieces); } else { window.$target = _pieces; }")
            $lines.Add("${pad}}")
            return ($lines -join "`n")
        }
        default {
            return ""
        }
    }
}

Export-ModuleMember -Function `
    ConvertTo-OtterJsExpression, ConvertTo-OtterJsStatement
