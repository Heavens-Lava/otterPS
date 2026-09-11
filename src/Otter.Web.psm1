using module ..\Otter.Contract.psm1

# Otter.Web.psm1
#
# D50: Otter Web App Compiler
# Compiles Otter AST / UI programs into standalone, responsive, modern HTML5/CSS3/JavaScript web apps.

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

function Escape-OtterHtmlAttr {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return $Text -replace '&', '&amp;' -replace '"', '&quot;' -replace '<', '&lt;' -replace '>', '&gt;'
}

function ConvertTo-OtterCssEasing {
    param([string]$Easing)
    switch ($Easing) {
        'ease-out' { return 'cubic-bezier(0.16, 1, 0.3, 1)' }
        'ease-in'  { return 'cubic-bezier(0.7, 0, 0.84, 0)' }
        'spring'   { return 'cubic-bezier(0.34, 1.56, 0.64, 1)' }
        'linear'   { return 'linear' }
        default    { return 'ease' }
    }
}

function Render-OtterDeclarativeElementWeb {
    param(
        [Parameter(Mandatory)][Node]$Element,
        [hashtable]$StateVars,
        [hashtable]$DeriveVars,
        [System.Collections.Generic.List[string]]$CssRules,
        [System.Collections.Generic.List[string]]$JsListeners,
        [ref]$IdCounter,
        [int]$Depth = 1
    )

    if ($Element -isnot [UiElementStmt]) {
        return ""
    }

    $id = if ($Element.Name) {
        $Element.Name
    } else {
        $curId = [int]$IdCounter.Value
        $IdCounter.Value = $curId + 1
        "otter_el_$curId"
    }
    $tag = if ($Element.Tag) { $Element.Tag.ToLowerInvariant() } else { "panel" }
    $variant = if ($Element.Variant) { $Element.Variant.ToLowerInvariant() } else { $null }

    $styles = [System.Collections.Generic.List[string]]::new()
    $classes = [System.Collections.Generic.List[string]]::new()
    $classes.Add("otter-$tag")
    if ($variant) {
        $classes.Add("otter-$tag-$variant")
        $classes.Add("otter-btn-$variant")
    }

    # Layout mode & presets
    if ($Element.Layout) {
        $mode = if ($Element.Layout.Mode) { $Element.Layout.Mode.ToLowerInvariant() } else { $null }
        switch ($mode) {
            'centered' {
                $styles.Add("display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100%;")
            }
            'split' {
                $styles.Add("display: flex; flex-direction: row; justify-content: space-between; align-items: center; width: 100%;")
            }
            'sidebar' {
                $styles.Add("display: grid; grid-template-columns: 240px 1fr; width: 100%; min-height: 100%;")
            }
            'stack' {
                $styles.Add("display: flex; flex-direction: column; width: 100%;")
            }
            'cards' {
                $styles.Add("display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); width: 100%;")
            }
            'navbar' {
                $styles.Add("display: flex; flex-direction: row; align-items: center; justify-content: space-between; width: 100%; padding: 12px 24px;")
            }
            'form' {
                $styles.Add("display: flex; flex-direction: column; width: 100%; max-width: 480px; margin: 0 auto;")
            }
            'row' {
                $styles.Add("display: flex; flex-direction: row;")
            }
            'column' {
                $styles.Add("display: flex; flex-direction: column;")
            }
            'grid' {
                $styles.Add("display: grid;")
                if ($Element.Layout.Columns) {
                    $colCount = if ($Element.Layout.Columns -is [LiteralExpr]) { $Element.Layout.Columns.Value } else { 2 }
                    $styles.Add("grid-template-columns: repeat($colCount, minmax(0, 1fr));")
                }
            }
        }

        # Gap
        if ($Element.Layout.Gap) {
            $gapVal = if ($Element.Layout.Gap -is [LiteralExpr]) { $Element.Layout.Gap.Value } else { 12 }
            $styles.Add("gap: ${gapVal}px;")
        }

        # Spread
        if ($Element.Layout.Spread) {
            $styles.Add("justify-content: space-between;")
        }

        # Align
        if ($Element.Layout.Align) {
            $align = $Element.Layout.Align.ToLowerInvariant()
            switch ($align) {
                'center' { $styles.Add("align-items: center; text-align: center; justify-content: center;") }
                'left'   { $styles.Add("align-items: flex-start; text-align: left; justify-content: flex-start;") }
                'right'  { $styles.Add("align-items: flex-end; text-align: right; justify-content: flex-end;") }
                'top'    { $styles.Add("align-items: flex-start;") }
                'middle' { $styles.Add("align-items: center;") }
                'bottom' { $styles.Add("align-items: flex-end;") }
            }
        }

        # Responsive
        if ($Element.Layout.Responsive) {
            foreach ($r in $Element.Layout.Responsive) {
                $bpPx = switch ($r.Breakpoint.ToLowerInvariant()) {
                    'small'  { '640px' }
                    'medium' { '768px' }
                    'large'  { '1024px' }
                    default  { '768px' }
                }
                if ($r.Stack) {
                    $CssRules.Add("@media (max-width: $bpPx) { #$id { flex-direction: column !important; } }")
                }
                if ($r.Columns -gt 0) {
                    $CssRules.Add("@media (max-width: $bpPx) { #$id { grid-template-columns: repeat($($r.Columns), 1fr) !important; } }")
                }
            }
        }
    }

    # Properties
    if ($Element.Properties) {
        foreach ($prop in $Element.Properties) {
            if ($prop -is [AssignStmt]) {
                $pName = if ($prop.Target -is [VariableExpr]) { $prop.Target.Name.ToLowerInvariant() } else { [string]$prop.Target.ToLowerInvariant() }
                $pVal = if ($prop.Value -is [LiteralExpr]) { $prop.Value.Value } else { $null }
                switch ($pName) {
                    'round' {
                        $rad = if ($null -ne $pVal -and $pVal -ne $true) { "${pVal}px" } else { "12px" }
                        $styles.Add("border-radius: $rad;")
                    }
                    'gap' {
                        $styles.Add("gap: ${pVal}px;")
                    }
                    'align' {
                        switch ([string]$pVal) {
                            'center' { $styles.Add("align-items: center; text-align: center; justify-content: center;") }
                            'left'   { $styles.Add("align-items: flex-start; text-align: left; justify-content: flex-start;") }
                            'right'  { $styles.Add("align-items: flex-end; text-align: right; justify-content: flex-end;") }
                            'top'    { $styles.Add("align-items: flex-start;") }
                            'middle' { $styles.Add("align-items: center;") }
                            'bottom' { $styles.Add("align-items: flex-end;") }
                        }
                    }
                    'spread' {
                        if ($pVal -eq $true -or $pVal -eq 'true') { $styles.Add("justify-content: space-between;") }
                    }
                    'padding' {
                        $styles.Add("padding: ${pVal}px;")
                    }
                    'width' {
                        $w = if ($pVal -eq 'full') { "100%" } elseif ($pVal -is [int] -or $pVal -is [double]) { "${pVal}px" } else { $pVal }
                        $styles.Add("width: $w;")
                    }
                    'height' {
                        $h = if ($pVal -eq 'full') { "100%" } elseif ($pVal -is [int] -or $pVal -is [double]) { "${pVal}px" } else { $pVal }
                        $styles.Add("height: $h;")
                    }
                    'background' {
                        $styles.Add("background: $pVal;")
                    }
                    'foreground' {
                        $styles.Add("color: $pVal;")
                    }
                }
            }
        }
    }

    # Animations
    if ($Element.Animations) {
        foreach ($anim in $Element.Animations) {
            $dur = if ($anim.DurationMs -gt 0) { $anim.DurationMs } else { 200 }
            $easingCss = ConvertTo-OtterCssEasing -Easing $anim.Easing

            switch ($anim.Trigger.ToLowerInvariant()) {
                'hover' {
                    $scale = 1.05
                    foreach ($step in $anim.Steps) {
                        if ($step.Operation -in @('grow', 'scale') -and $step.Amount -and $step.Amount -is [LiteralExpr]) {
                            $scale = $step.Amount.Value
                        }
                    }
                    $styles.Add("transition: transform ${dur}ms $easingCss, box-shadow ${dur}ms $easingCss;")
                    $CssRules.Add("#$($id):hover { transform: scale($scale); }")
                }
                'press' {
                    $styles.Add("transition: transform 100ms ease;")
                    $CssRules.Add("#$($id):active { transform: scale(0.96); }")
                }
                'enter' {
                    $fromTransforms = [System.Collections.Generic.List[string]]::new()
                    $fromOpacity = $null
                    foreach ($step in $anim.Steps) {
                        if ($step.Operation -eq 'fade' -and $step.Direction -eq 'in') { $fromOpacity = '0' }
                        if ($step.Operation -eq 'move') {
                            $amt = if ($step.Amount -and $step.Amount -is [LiteralExpr]) { $step.Amount.Value } else { 20 }
                            switch ($step.Direction) {
                                'up'    { $fromTransforms.Add("translateY(${amt}px)") }
                                'down'  { $fromTransforms.Add("translateY(-${amt}px)") }
                                'left'  { $fromTransforms.Add("translateX(${amt}px)") }
                                'right' { $fromTransforms.Add("translateX(-${amt}px)") }
                            }
                        }
                        if ($step.Operation -eq 'slide') {
                            $fromOpacity = '0'
                            switch ($step.Direction) {
                                'left'   { $fromTransforms.Add("translateX(-30px)") }
                                'right'  { $fromTransforms.Add("translateX(30px)") }
                                'top'    { $fromTransforms.Add("translateY(-30px)") }
                                'bottom' { $fromTransforms.Add("translateY(30px)") }
                                default  { $fromTransforms.Add("translateX(-30px)") }
                            }
                        }
                    }
                    $fromCss = ""
                    if ($null -ne $fromOpacity) { $fromCss += "opacity: $fromOpacity; " }
                    if ($fromTransforms.Count -gt 0) { $fromCss += "transform: $($fromTransforms -join ' '); " }
                    $toCss = "opacity: 1; transform: translate(0, 0) scale(1);"

                    $animName = "otter_enter_$id"
                    $CssRules.Add("@keyframes $animName { from { $fromCss } to { $toCss } }")
                    $styles.Add("animation: $animName ${dur}ms $easingCss forwards;")
                }
                'leave' {
                    $animName = "otter_leave_$id"
                    $CssRules.Add("@keyframes $animName { from { opacity: 1; transform: scale(1); } to { opacity: 0; transform: scale(0.95); } }")
                }
            }
        }
    }

    # Events
    if ($Element.Events) {
        foreach ($evt in $Element.Events) {
            $evtName = switch ($evt.EventName.ToLowerInvariant()) {
                'click'   { 'click' }
                'input'   { 'input' }
                'change'  { 'change' }
                'submit'  { 'submit' }
                'hover'   { 'mouseenter' }
                'press'   { 'mousedown' }
                'focus'   { 'focus' }
                'blur'    { 'blur' }
                default   { $evt.EventName.ToLowerInvariant() }
            }

            $bodyStatements = [System.Collections.Generic.List[string]]::new()
            foreach ($s in $evt.Body) {
                $bodyStatements.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent 3))
            }
            $bodyCode = $bodyStatements -join "`n"

            $JsListeners.Add(@"
    const el_$id = document.getElementById('$id');
    if (el_$id) {
      el_$id.addEventListener('$evtName', async (event) => {
$bodyCode
        if (typeof otterUpdateReactivity === 'function') otterUpdateReactivity();
      });
    }
"@)
        }
    }

    # Label and dynamic data binding
    $labelAttr = ""
    $labelText = ""
    if ($Element.Label) {
        if ($Element.Label -is [LiteralExpr]) {
            $labelText = [string]$Element.Label.Value
        } else {
            $jsExpr = ConvertTo-OtterJsExpression -Expr $Element.Label
            $escapedExpr = Escape-OtterHtmlAttr -Text $jsExpr
            $labelAttr = " data-otter-bind=`"$escapedExpr`""
            $labelText = ""
        }
    }

    # Children
    $childrenHtml = [System.Collections.Generic.List[string]]::new()
    if ($Element.Children) {
        foreach ($child in $Element.Children) {
            if ($child -is [UiElementStmt]) {
                $cHtml = Render-OtterDeclarativeElementWeb -Element $child -StateVars $StateVars -DeriveVars $DeriveVars -CssRules $CssRules -JsListeners $JsListeners -IdCounter $IdCounter -Depth ($Depth + 1)
                $childrenHtml.Add($cHtml)
            } elseif ($child -is [IfStmt]) {
                if ($child.Branches.Count -gt 0) {
                    $b0 = $child.Branches[0]
                    $condExpr = ConvertTo-OtterJsExpression -Expr $b0.Condition
                    $escapedCond = Escape-OtterHtmlAttr -Text $condExpr
                    $subHtml = [System.Collections.Generic.List[string]]::new()
                    foreach ($sub in $b0.Body) {
                        if ($sub -is [UiElementStmt]) {
                            $subHtml.Add((Render-OtterDeclarativeElementWeb -Element $sub -StateVars $StateVars -DeriveVars $DeriveVars -CssRules $CssRules -JsListeners $JsListeners -IdCounter $IdCounter -Depth ($Depth + 2)))
                        }
                    }
                    $subJoined = $subHtml -join "`n"
                    $currIfNum = [int]$IdCounter.Value
                    $IdCounter.Value = $currIfNum + 1
                    $ifId = "otter_if_$currIfNum"
                    $childrenHtml.Add("      <div id=`"$ifId`" class=`"otter-conditional`" data-otter-if=`"$escapedCond`" style=`"display: none;`">`n$subJoined`n      </div>")
                }
            }
        }
    }

    $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
    $classAttr = " class=`"$($classes -join ' ')`""
    $content = if ($childrenHtml.Count -gt 0) {
        if ($labelText) { "$labelText`n" + ($childrenHtml -join "`n") } else { "`n" + ($childrenHtml -join "`n") + "`n    " }
    } else {
        $labelText
    }

    $pad = '  ' * $Depth

    switch ($tag) {
        'heading' {
            return "${pad}<h2 id=`"$id`"$classAttr$styleAttr$labelAttr>$content</h2>"
        }
        'button' {
            return "${pad}<button id=`"$id`"$classAttr$styleAttr$labelAttr>$content</button>"
        }
        'text' {
            return "${pad}<div id=`"$id`"$classAttr$styleAttr$labelAttr>$content</div>"
        }
        'input' {
            return "${pad}<input type=`"text`" id=`"$id`"$classAttr$styleAttr$labelAttr value=`"$labelText`" />"
        }
        'section' {
            return "${pad}<section id=`"$id`"$classAttr$styleAttr$labelAttr>$content</section>"
        }
        'page' {
            return "${pad}<main id=`"$id`"$classAttr$styleAttr$labelAttr>$content</main>"
        }
        default {
            # card, panel, row, column, grid, window
            return "${pad}<div id=`"$id`"$classAttr$styleAttr$labelAttr>$content</div>"
        }
    }
}

function ConvertTo-OtterWeb {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [string]$Title = "Otter Web App"
    )

    # Collect UI resources and initial configuration
    $resources = [ordered]@{}
    $containers = [ordered]@{} # parent -> children list
    $whenHandlers = [System.Collections.Generic.List[WhenStmt]]::new()
    $topLevelStatements = [System.Collections.Generic.List[Node]]::new()
    $declarativeRoots = [System.Collections.Generic.List[UiElementStmt]]::new()
    $stateDefs = [ordered]@{}
    $deriveDefs = [ordered]@{}
    $watchStmts = [System.Collections.Generic.List[WatchStmt]]::new()
    $functions = [ordered]@{}

    # Pass 1: Identify resources and configurations
    foreach ($stmt in $Program.Statements) {
        if ($stmt -is [StateDefStmt]) {
            $stateDefs[$stmt.Name] = $stmt
            continue
        }
        if ($stmt -is [DeriveDefStmt]) {
            $deriveDefs[$stmt.Name] = $stmt
            continue
        }
        if ($stmt -is [WatchStmt]) {
            $watchStmts.Add($stmt)
            continue
        }
        if ($stmt -is [FunctionDefStmt]) {
            $functions[$stmt.Name] = $stmt
            continue
        }
        if ($stmt -is [UiElementStmt]) {
            $declarativeRoots.Add($stmt)
            continue
        }
        if ($stmt -is [CreateUiResourceStmt]) {
            $resources[$stmt.Target] = @{
                Kind = $stmt.TypeName.ToLowerInvariant()
                Name = $stmt.Target
                Properties = [ordered]@{}
            }
            continue
        }
        if ($stmt -is [ObjectDefStmt]) {
            if ($resources.Contains($stmt.Name)) {
                if ($stmt.Properties) {
                    foreach ($p in $stmt.Properties) {
                        if ($p -is [AssignStmt]) {
                            $propKey = if ($p.Target -is [VariableExpr]) { $p.Target.Name.ToLowerInvariant() } else { [string]$p.Target.ToLowerInvariant() }
                            $val = if ($p.Value -is [LiteralExpr]) { $p.Value.Value } else { ConvertTo-OtterJsExpression -Expr $p.Value }
                            $resources[$stmt.Name].Properties[$propKey] = $val
                        }
                    }
                }
                continue
            }
            $kind = $stmt.TypeName.ToLowerInvariant()
            $knownKinds = @(
                'window', 'page', 'button', 'text box', 'text', 'row', 'column',
                'image', 'list', 'link', 'card', 'checkbox', 'check box',
                'dropdown', 'drop down', 'select', 'slider', 'range',
                'text area', 'textarea', 'badge', 'tag', 'canvas', 'table'
            )
            if ($kind -in $knownKinds) {
                $res = @{
                    Kind = $kind
                    Name = $stmt.Name
                    Properties = [ordered]@{}
                }
                if ($stmt.Properties) {
                    foreach ($p in $stmt.Properties) {
                        if ($p -is [AssignStmt]) {
                            $propKey = if ($p.Target -is [VariableExpr]) { $p.Target.Name.ToLowerInvariant() } else { [string]$p.Target.ToLowerInvariant() }
                            $val = if ($p.Value -is [LiteralExpr]) { $p.Value.Value } else { ConvertTo-OtterJsExpression -Expr $p.Value }
                            $res.Properties[$propKey] = $val
                        }
                    }
                }
                $resources[$stmt.Name] = $res
                continue
            }
        }
        if ($stmt -is [AssignStmt] -and $stmt.Target -is [PropertyAccessExpr]) {
            $target = $stmt.Target.Target
            $targetName = if ($target -is [VariableExpr]) { $target.Name } else { $null }
            if ($targetName -and $resources.Contains($targetName) -and $stmt.Value -is [LiteralExpr]) {
                $pKey = $stmt.Target.Property.ToLowerInvariant()
                $val = $stmt.Value.Value
                $resources[$targetName].Properties[$pKey] = $val
                continue
            }
        }
        if ($stmt -is [PutInStmt]) {
            $item = if ($stmt.Item -is [VariableExpr]) { $stmt.Item.Name } else { $null }
            $cont = if ($stmt.Container -is [VariableExpr]) { $stmt.Container.Name } else { $null }
            if ($cont -and $item) {
                if (-not $containers.Contains($cont)) {
                    $containers[$cont] = [System.Collections.Generic.List[string]]::new()
                }
                $containers[$cont].Add($item)
            }
            continue
        }
        if ($stmt -is [WhenStmt]) {
            $whenHandlers.Add($stmt)
            continue
        }
        if ($stmt -is [ShowStmt]) {
            continue
        }
        $topLevelStatements.Add($stmt)
    }

    # Determine root container (first page or window, or default)
    $rootName = $null
    foreach ($name in $resources.Keys) {
        $r = $resources[$name]
        if ($r.Kind -eq 'window' -or $r.Kind -eq 'page') {
            $rootName = $name
            break
        }
    }
    if ($null -eq $rootName -and $resources.Count -gt 0) {
        $rootName = ($resources.Keys | Select-Object -First 1)
    }

    $appTitle = $Title
    $rootBg = "#0f172a"
    $rootFg = "#f8fafc"
    if ($rootName) {
        if ($resources[$rootName].Properties.Contains('title')) {
            $appTitle = [string]$resources[$rootName].Properties['title']
        }
        if ($resources[$rootName].Properties.Contains('background')) {
            $rootBg = [string]$resources[$rootName].Properties['background']
        }
        if ($resources[$rootName].Properties.Contains('foreground')) {
            $rootFg = [string]$resources[$rootName].Properties['foreground']
        }
    }

    # HTML rendering helper
    function Render-OtterElement([string]$resName) {
        if (-not $resources.Contains($resName)) { return "" }
        $r = $resources[$resName]
        $kind = $r.Kind
        $props = $r.Properties

        $styles = [System.Collections.Generic.List[string]]::new()
        if ($props.Contains('width')) {
            $w = $props['width']
            $wCss = if ($w -eq 'full') { "100%" } elseif ($w -is [int] -or $w -is [double]) { "${w}px" } else { $w }
            $styles.Add("width: $wCss;")
        }
        if ($props.Contains('height')) {
            $h = $props['height']
            $hCss = if ($h -eq 'full') { "100%" } elseif ($h -is [int] -or $h -is [double]) { "${h}px" } else { $h }
            $styles.Add("height: $hCss;")
        }
        if ($props.Contains('maxwidth')) {
            $mw = $props['maxwidth']
            $styles.Add("max-width: $(if ($mw -is [int] -or $mw -is [double]) { "${mw}px" } else { $mw });")
        }
        if ($props.Contains('minwidth')) {
            $mw = $props['minwidth']
            $styles.Add("min-width: $(if ($mw -is [int] -or $mw -is [double]) { "${mw}px" } else { $mw });")
        }
        if ($props.Contains('minheight')) {
            $mh = $props['minheight']
            $styles.Add("min-height: $(if ($mh -is [int] -or $mh -is [double]) { "${mh}px" } else { $mh });")
        }
        if ($props.Contains('background')) {
            $styles.Add("background: $($props['background']);")
        }
        if ($props.Contains('foreground')) {
            $styles.Add("color: $($props['foreground']);")
        }
        if ($props.Contains('round') -and ($props['round'] -eq $true -or $props['round'] -eq 'true')) {
            $styles.Add("border-radius: 9999px;")
        } elseif ($props.Contains('radius')) {
            $rad = $props['radius']
            $radCss = if ($rad -eq 'round') { "9999px" } elseif ($rad -is [int] -or $rad -is [double]) { "${rad}px" } else { $rad }
            $styles.Add("border-radius: $radCss;")
        }
        if ($props.Contains('border')) {
            $styles.Add("border: $($props['border']);")
        }
        if ($props.Contains('shadow')) {
            $styles.Add("box-shadow: $($props['shadow']);")
        }
        if ($props.Contains('padding')) {
            $pad = $props['padding']
            $styles.Add("padding: $(if ($pad -is [int] -or $pad -is [double]) { "${pad}px" } else { $pad });")
        }
        if ($props.Contains('margin')) {
            $mar = $props['margin']
            $styles.Add("margin: $(if ($mar -is [int] -or $mar -is [double]) { "${mar}px" } else { $mar });")
        }
        if ($props.Contains('size') -or $props.Contains('fontsize')) {
            $fs = if ($props.Contains('fontsize')) { $props['fontsize'] } else { $props['size'] }
            $styles.Add("font-size: $(if ($fs -is [int] -or $fs -is [double]) { "${fs}px" } else { $fs });")
        }
        if ($props.Contains('weight') -or $props.Contains('fontweight')) {
            $fw = if ($props.Contains('fontweight')) { $props['fontweight'] } else { $props['weight'] }
            $styles.Add("font-weight: $fw;")
        }
        if ($props.Contains('fontstyle')) {
            $styles.Add("font-style: $($props['fontstyle']);")
        } elseif ($props.Contains('style') -and ($props['style'] -eq 'italic' -or $props['style'] -eq 'normal')) {
            $styles.Add("font-style: $($props['style']);")
        }
        if ($props.Contains('family') -or $props.Contains('fontfamily')) {
            $ff = if ($props.Contains('fontfamily')) { $props['fontfamily'] } else { $props['family'] }
            $styles.Add("font-family: $ff;")
        }
        if ($props.Contains('lineheight')) {
            $styles.Add("line-height: $($props['lineheight']);")
        }
        if ($props.Contains('letterspacing')) {
            $styles.Add("letter-spacing: $($props['letterspacing']);")
        }
        if ($props.Contains('align')) {
            $styles.Add("text-align: $($props['align']);")
        } elseif ($kind -notin @('row', 'column') -and $props.Contains('align_h')) {
            $styles.Add("text-align: $($props['align_h']);")
        }
        if ($props.Contains('flex')) {
            $styles.Add("flex: $($props['flex']); min-width: 0;")
        }
        if ($props.Contains('grow')) {
            $styles.Add("flex-grow: $($props['grow']);")
        }
        if ($props.Contains('cursor')) {
            $styles.Add("cursor: $($props['cursor']);")
        }
        if ($props.Contains('position')) {
            $styles.Add("position: $($props['position']);")
        }
        if ($props.Contains('bottom')) {
            $b = $props['bottom']
            $styles.Add("bottom: $(if ($b -is [int] -or $b -is [double]) { "${b}px" } else { $b });")
        }
        if ($props.Contains('top')) {
            $t = $props['top']
            $styles.Add("top: $(if ($t -is [int] -or $t -is [double]) { "${t}px" } else { $t });")
        }
        if ($props.Contains('left')) {
            $l = $props['left']
            $styles.Add("left: $(if ($l -is [int] -or $l -is [double]) { "${l}px" } else { $l });")
        }
        if ($props.Contains('right')) {
            $rg = $props['right']
            $styles.Add("right: $(if ($rg -is [int] -or $rg -is [double]) { "${rg}px" } else { $rg });")
        }
        if ($props.Contains('zindex')) {
            $styles.Add("z-index: $($props['zindex']);")
        }
        if ($props.Contains('customstyle')) {
            $styles.Add("$($props['customstyle']);")
        }
        $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }

        $childHtml = ""
        if ($containers.Contains($resName)) {
            $childParts = foreach ($child in $containers[$resName]) { Render-OtterElement -resName $child }
            $childHtml = "`n" + ($childParts -join "`n") + "`n"
        }

        switch ($kind) {
            'window' {
                $spacing = if ($props.Contains('spacing')) { $props['spacing'] } else { 12 }
                if (-not $props.Contains('gap')) { $styles.Add("gap: ${spacing}px;") }
                $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
                return @"
    <div id="$resName" class="otter-window"$styleAttr>
      <header class="otter-window-header"><h1 class="otter-title">$appTitle</h1></header>
      <div class="otter-window-content" style="display: flex; flex-direction: column; gap: ${spacing}px; min-width: 0;">$childHtml</div>
    </div>
"@
            }
            'page' {
                $spacing = if ($props.Contains('spacing')) { $props['spacing'] } else { 12 }
                if (-not $props.Contains('gap')) { $styles.Add("gap: ${spacing}px;") }
                $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
                $showHeader = (-not ($props.Contains('hideheader') -and $props['hideheader']))
                $headerHtml = if ($showHeader -and $appTitle) { "<header class=`"otter-page-header`"><h1 class=`"otter-title`">$appTitle</h1></header>" } else { "" }
                return @"
    <main id="$resName" class="otter-page"$styleAttr>
      $headerHtml
      <div class="otter-page-content" style="display: flex; flex-direction: column; gap: ${spacing}px; width: 100%; min-width: 0;">$childHtml</div>
    </main>
"@
            }
            'card' {
                $spacing = if ($props.Contains('spacing')) { $props['spacing'] } else { 12 }
                if (-not $props.Contains('gap')) { $styles.Add("gap: ${spacing}px;") }
                $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
                $cardTitle = if ($props.Contains('title')) { "<h3 class=`"otter-card-title`">$($props['title'])</h3>" } else { "" }
                return @"
      <div id="$resName" class="otter-card"$styleAttr>
        $cardTitle
        $childHtml
      </div>
"@
            }
            'button' {
                $text = if ($props.Contains('text')) { $props['text'] } else { "Button" }
                return "      <button id=`"$resName`" class=`"otter-button`"$styleAttr>$text</button>"
            }
            'text box' {
                $val = if ($props.Contains('text')) { $props['text'] } elseif ($props.Contains('value')) { $props['value'] } else { "" }
                $ph = if ($props.Contains('placeholder')) { " placeholder=`"$($props['placeholder'])`"" } else { "" }
                return "      <input type=`"text`" id=`"$resName`" class=`"otter-text-box`" value=`"$val`"$ph$styleAttr />"
            }
            'text' {
                $val = if ($props.Contains('text')) { $props['text'] } elseif ($props.Contains('value')) { $props['value'] } else { "" }
                return "      <div id=`"$resName`" class=`"otter-text`"$styleAttr>$val</div>"
            }
            'image' {
                $src = if ($props.Contains('source')) { $props['source'] } elseif ($props.Contains('src')) { $props['src'] } else { "" }
                $alt = if ($props.Contains('alt')) { $props['alt'] } else { $resName }
                return "      <img id=`"$resName`" class=`"otter-image`" src=`"$src`" alt=`"$alt`"$styleAttr />"
            }
            'link' {
                $href = if ($props.Contains('url')) { $props['url'] } elseif ($props.Contains('href')) { $props['href'] } else { "#" }
                $text = if ($props.Contains('text')) { $props['text'] } else { $href }
                $isExternal = [string]$href -match '^(?i)https?://'
                $linkAttrs = if ($isExternal) { ' target="_blank" rel="noopener noreferrer"' } else { '' }
                return "      <a id=`"$resName`" class=`"otter-link`" href=`"$href`"$styleAttr$linkAttrs>$text</a>"
            }
            { $_ -in @('checkbox', 'check box') } {
                $text = if ($props.Contains('text')) { $props['text'] } else { "" }
                $checked = if ($props.Contains('checked') -and $props['checked']) { " checked" } else { "" }
                return "      <label class=`"otter-checkbox-label`"$styleAttr><input type=`"checkbox`" id=`"$resName`" class=`"otter-checkbox`"$checked /> <span>$text</span></label>"
            }
            { $_ -in @('dropdown', 'drop down', 'select') } {
                $opts = @()
                if ($props.Contains('options')) {
                    $rawOpts = $props['options']
                    if ($rawOpts -is [System.Collections.IEnumerable] -and $rawOpts -isnot [string]) {
                        $opts = @($rawOpts)
                    } else {
                        $opts = ([string]$rawOpts -split ',') | ForEach-Object { $_.Trim() }
                    }
                }
                $optHtml = ($opts | ForEach-Object { "        <option value=`"$_`">$_</option>" }) -join "`n"
                return @"
      <select id="$resName" class="otter-select"$styleAttr>
$optHtml
      </select>
"@
            }
            { $_ -in @('slider', 'range') } {
                $min = if ($props.Contains('min')) { $props['min'] } else { 0 }
                $max = if ($props.Contains('max')) { $props['max'] } else { 100 }
                $val = if ($props.Contains('value')) { $props['value'] } else { 50 }
                return "      <input type=`"range`" id=`"$resName`" class=`"otter-slider`" min=`"$min`" max=`"$max`" value=`"$val`"$styleAttr />"
            }
            { $_ -in @('text area', 'textarea') } {
                $val = if ($props.Contains('text')) { $props['text'] } elseif ($props.Contains('value')) { $props['value'] } else { "" }
                $ph = if ($props.Contains('placeholder')) { " placeholder=`"$($props['placeholder'])`"" } else { "" }
                $rows = if ($props.Contains('rows')) { $props['rows'] } else { 3 }
                return "      <textarea id=`"$resName`" class=`"otter-text-area`" rows=`"$rows`"$ph$styleAttr>$val</textarea>"
            }
            { $_ -in @('badge', 'tag') } {
                $text = if ($props.Contains('text')) { $props['text'] } else { "" }
                return "      <span id=`"$resName`" class=`"otter-badge`"$styleAttr>$text</span>"
            }
            'canvas' {
                $w = if ($props.Contains('width')) { $props['width'] } else { 400 }
                $h = if ($props.Contains('height')) { $props['height'] } else { 300 }
                $anim = if ($props.Contains('animation')) { $props['animation'] } else { "" }
                $mode = if ($props.Contains('mode')) { $props['mode'] } else { "2d" }
                return "      <canvas id=`"$resName`" class=`"otter-canvas`" width=`"$w`" height=`"$h`" data-animation=`"$anim`" data-mode=`"$mode`"$styleAttr></canvas>"
            }
            'row' {
                $spacing = if ($props.Contains('spacing')) { $props['spacing'] } else { 8 }
                $wrap = if ($props.Contains('wrap') -and ($props['wrap'] -eq $true -or $props['wrap'] -eq 'true' -or $props['wrap'] -eq 'wrap')) { 'wrap' } else { 'nowrap' }
                
                # D54: align is one property; its word selects the physical axis.
                $direction = if ($props.Contains('align')) { [string]$props['align'] } else { $null }
                if ($props.Contains('spread') -and ($props['spread'] -eq $true -or $props['spread'] -eq 'true') -and $direction -in @('left', 'center', 'right')) {
                    throw [OtterError]::new("Horizontal alignment 'align $direction' conflicts with 'spread' on a row.", 0, 'runtime')
                }

                # Horizontal placement (main axis)
                $justify = if ($props.Contains('spread') -and ($props['spread'] -eq $true -or $props['spread'] -eq 'true')) {
                    'space-between'
                } elseif ($direction -in @('left', 'center', 'right')) {
                    switch ($direction) {
                        'left'   { 'flex-start' }
                        'center' { 'center' }
                        'right'  { 'flex-end' }
                        default  { 'flex-start' }
                    }
                } elseif ($props.Contains('justify')) {
                    $props['justify']
                } else {
                    'flex-start'
                }

                # Vertical placement (cross axis)
                $align = if ($direction -in @('top', 'middle', 'bottom')) {
                    switch ($direction) {
                        'top'    { 'flex-start' }
                        'middle' { 'center' }
                        'bottom' { 'flex-end' }
                        default  { 'center' }
                    }
                } elseif ($props.Contains('alignitems')) {
                    $props['alignitems']
                } elseif ($props.Contains('items')) {
                    $props['items']
                } else {
                    'center'
                }

                $styles.Add("display: flex; flex-direction: row;")
                $styles.Add("gap: ${spacing}px;")
                $styles.Add("align-items: $align;")
                $styles.Add("justify-content: $justify;")
                $styles.Add("flex-wrap: $wrap;")
                $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
                return @"
      <div id="$resName" class="otter-row"$styleAttr>$childHtml</div>
"@
            }
            'column' {
                $spacing = if ($props.Contains('spacing')) { $props['spacing'] } else { 8 }

                # D54: align is one property; its word selects the physical axis.
                $direction = if ($props.Contains('align')) { [string]$props['align'] } else { $null }
                if ($props.Contains('spread') -and ($props['spread'] -eq $true -or $props['spread'] -eq 'true') -and $direction -in @('top', 'middle', 'bottom')) {
                    throw [OtterError]::new("Vertical alignment 'align $direction' conflicts with 'spread' on a column.", 0, 'runtime')
                }

                # Vertical placement (main axis)
                $justify = if ($props.Contains('spread') -and ($props['spread'] -eq $true -or $props['spread'] -eq 'true')) {
                    'space-between'
                } elseif ($direction -in @('top', 'middle', 'bottom')) {
                    switch ($direction) {
                        'top'    { 'flex-start' }
                        'middle' { 'center' }
                        'bottom' { 'flex-end' }
                        default  { 'flex-start' }
                    }
                } elseif ($props.Contains('justify')) {
                    $props['justify']
                } else {
                    'flex-start'
                }

                # Horizontal placement (cross axis)
                $align = if ($direction -in @('left', 'center', 'right')) {
                    switch ($direction) {
                        'left'   { 'flex-start' }
                        'center' { 'center' }
                        'right'  { 'flex-end' }
                        default  { 'stretch' }
                    }
                } elseif ($props.Contains('alignitems')) {
                    $props['alignitems']
                } elseif ($props.Contains('items')) {
                    $props['items']
                } else {
                    'stretch'
                }

                $styles.Add("display: flex; flex-direction: column;")
                $styles.Add("gap: ${spacing}px;")
                $styles.Add("align-items: $align;")
                $styles.Add("justify-content: $justify;")
                $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
                return @"
      <div id="$resName" class="otter-column"$styleAttr>$childHtml</div>
"@
            }
            default {
                return "      <div id=`"$resName`" class=`"otter-resource otter-$kind`"$styleAttr>$childHtml</div>"
            }
        }
    }

    $elementsHtml = ""
    if ($rootName) {
        $elementsHtml = Render-OtterElement -resName $rootName
    } else {
        $parts = foreach ($name in $resources.Keys) { Render-OtterElement -resName $name }
        $elementsHtml = $parts -join "`n"
    }

    # Check for calls to functions that define declarative UI
    foreach ($stmt in $topLevelStatements) {
        if ($stmt -is [CallStmt]) {
            $fnName = $stmt.Call.Name
            if ($functions.Contains($fnName)) {
                $fnDef = $functions[$fnName]
                foreach ($bodyStmt in $fnDef.Body) {
                    if ($bodyStmt -is [UiElementStmt]) {
                        $declarativeRoots.Add($bodyStmt)
                    }
                }
            }
        }
    }

    # Render declarative elements if any
    $declarativeCssRules = [System.Collections.Generic.List[string]]::new()
    $declarativeJsListeners = [System.Collections.Generic.List[string]]::new()
    $declarativeHtmlParts = [System.Collections.Generic.List[string]]::new()
    $idCounter = [ref]0

    foreach ($rootEl in $declarativeRoots) {
        $rendered = Render-OtterDeclarativeElementWeb -Element $rootEl `
            -StateVars $stateDefs `
            -DeriveVars $deriveDefs `
            -CssRules $declarativeCssRules `
            -JsListeners $declarativeJsListeners `
            -IdCounter $idCounter `
            -Depth 2
        if ($rendered) { $declarativeHtmlParts.Add($rendered) }
    }

    $declarativeHtml = $declarativeHtmlParts -join "`n"
    if ($declarativeHtml) {
        if ($elementsHtml) {
            $elementsHtml = "$elementsHtml`n$declarativeHtml"
        } else {
            $elementsHtml = $declarativeHtml
        }
    }

    if ($appTitle -eq "Otter Web App") {
        foreach ($r in $declarativeRoots) {
            if ($r.Tag -in @('window', 'page') -and $r.Label -is [LiteralExpr]) {
                $appTitle = [string]$r.Label.Value
                break
            }
            if ($r.Children) {
                foreach ($c in $r.Children) {
                    if ($c -is [UiElementStmt] -and $c.Tag -eq 'heading' -and $c.Label -is [LiteralExpr]) {
                        $appTitle = [string]$c.Label.Value
                        break
                    }
                }
            }
        }
    }

    $declarativeCssJoined = $declarativeCssRules -join "`n"
    $declarativeListenersJoined = $declarativeJsListeners -join "`n"

    $stateInitJs = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $stateDefs.Keys) {
        $sNode = $stateDefs[$k]
        $valJs = ConvertTo-OtterJsExpression -Expr $sNode.InitialValue
        $stateInitJs.Add("    otterState['$k'] = $valJs;`n    window['$k'] = $valJs;")
    }
    $stateInitJoined = $stateInitJs -join "`n"

    $deriveInitJs = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $deriveDefs.Keys) {
        $dNode = $deriveDefs[$k]
        $valJs = ConvertTo-OtterJsExpression -Expr $dNode.Expression
        $deriveInitJs.Add(@"
    Object.defineProperty(otterDerived, '$k', {
      get: () => {
        const fn = new Function('state', 'derived', 'with(state) { with(derived) { return ($valJs); } }');
        return fn(otterState, otterDerived);
      },
      enumerable: true,
      configurable: true
    });
    Object.defineProperty(window, '$k', {
      get: () => otterDerived['$k'],
      enumerable: true,
      configurable: true
    });
"@)
    }
    $deriveInitJoined = $deriveInitJs -join "`n"

    $watcherInitJs = [System.Collections.Generic.List[string]]::new()
    foreach ($wNode in $watchStmts) {
        $wTarget = $wNode.TargetName
        $wBodyJs = foreach ($s in $wNode.Body) { ConvertTo-OtterJsStatement -Stmt $s -Indent 3 }
        $wBodyJoined = $wBodyJs -join "`n"
        $watcherInitJs.Add(@"
    otterWatchers.push({
      target: '$wTarget',
      callback: () => {
$wBodyJoined
      }
    });
"@)
    }
    $watcherInitJoined = $watcherInitJs -join "`n"

    # Compile event handlers
    $jsHandlers = [System.Collections.Generic.List[string]]::new()
    foreach ($when in $whenHandlers) {
        $targetName = if ($when.Target -is [VariableExpr]) { $when.Target.Name } else { 'target' }
        $eventName = switch ($when.EventName.ToLowerInvariant()) {
            'clicked' { 'click' }
            'changed' { 'input' }
            default { $when.EventName.ToLowerInvariant() }
        }
        $bodyJs = [System.Collections.Generic.List[string]]::new()
        foreach ($s in $when.Body) {
            $bodyJs.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent 3))
        }
        $bodyJoined = $bodyJs -join "`n"
        $jsHandlers.Add(@"
    const el_$targetName = document.getElementById('$targetName');
    if (el_$targetName) {
      el_$targetName.addEventListener('$eventName', async (event) => {
$bodyJoined
      });
    }
"@)
    }

    # Compile top-level code
    $topLevelJs = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $topLevelStatements) {
        $topLevelJs.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent 2))
    }
    $topLevelJoined = $topLevelJs -join "`n"
    $handlersJoined = $jsHandlers -join "`n"

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$appTitle</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:ital,wght@0,300;0,400;0,500;0,600;0,700;0,800;1,400;1,600;1,700&family=Playfair+Display:ital,wght@1,500;1,600;1,700&family=Newsreader:ital,opsz,wght@1,6..72,500;1,6..72,600;1,6..72,700&display=swap" rel="stylesheet">
  <style>
    :root {
      --otter-bg: $rootBg;
      --otter-card-bg: #1e293b;
      --otter-text: $rootFg;
      --otter-text-muted: #94a3b8;
      --otter-primary: #2563eb;
      --otter-primary-hover: #1d4ed8;
      --otter-input-bg: #0f172a;
      --otter-border: #334155;
    }
    *, *::before, *::after { box-sizing: border-box; }
    * { margin: 0; padding: 0; }
    body {
      font-family: 'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
      background: $rootBg;
      color: $rootFg;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      margin: 0;
      padding: 24px;
      overflow-x: hidden;
      box-sizing: border-box;
    }
    .otter-row {
      display: flex;
      flex-direction: row;
      align-items: center;
      justify-content: flex-start;
      box-sizing: border-box;
      min-width: 0;
    }
    .otter-column {
      display: flex;
      flex-direction: column;
      align-items: stretch;
      justify-content: flex-start;
      box-sizing: border-box;
      min-width: 0;
    }
    .otter-window {
      background-color: #1e293b;
      border: 1px solid var(--otter-border);
      width: 100%;
      max-width: 520px;
      margin: 24px auto;
      display: flex;
      flex-direction: column;
      box-sizing: border-box;
      min-width: 0;
    }
    .otter-page {
      background: transparent;
      border: none;
      width: 100%;
      max-width: 1320px;
      margin: 0 auto;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      box-sizing: border-box;
      min-width: 0;
    }
    .otter-card {
      background-color: var(--otter-card-bg);
      border: 1px solid var(--otter-border);
      border-radius: 12px;
      padding: 24px;
      box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.3), 0 8px 10px -6px rgba(0, 0, 0, 0.3);
      display: flex;
      flex-direction: column;
      box-sizing: border-box;
      min-width: 0;
    }
    .otter-title {
      font-size: 1.35rem;
      font-weight: 700;
      margin-bottom: 8px;
      letter-spacing: -0.02em;
    }
    .otter-button {
      background-color: var(--otter-primary);
      color: white;
      border: none;
      border-radius: 8px;
      padding: 10px 18px;
      font-size: 0.95rem;
      font-weight: 600;
      cursor: pointer;
      transition: background-color 0.15s ease, transform 0.08s ease;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      white-space: nowrap;
      user-select: none;
    }
    .otter-button:hover { background-color: var(--otter-primary-hover); }
    .otter-button:active { transform: scale(0.98); }
    .otter-text-box {
      background-color: var(--otter-input-bg);
      color: var(--otter-text);
      border: 1px solid var(--otter-border);
      border-radius: 8px;
      padding: 10px 14px;
      font-size: 0.95rem;
      outline: none;
      transition: border-color 0.15s ease;
      width: 100%;
    }
    .otter-text-box:focus {
      border-color: var(--otter-primary);
      box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.25);
    }
    .otter-text {
      font-size: 1rem;
      min-height: 1.2em;
    }
    .otter-heading {
      font-size: 1.5rem;
      font-weight: 700;
      margin-bottom: 8px;
      letter-spacing: -0.02em;
      color: inherit;
    }
    .otter-button-primary, .otter-btn-primary {
      background-color: #2563eb !important;
      color: #ffffff !important;
      border: none !important;
      border-radius: 8px;
      padding: 10px 18px;
      font-weight: 600;
      cursor: pointer;
    }
    .otter-button-primary:hover, .otter-btn-primary:hover {
      background-color: #1d4ed8 !important;
    }
    .otter-button-secondary, .otter-btn-secondary {
      background-color: #334155 !important;
      color: #f8fafc !important;
      border: 1px solid #475569 !important;
      border-radius: 8px;
      padding: 10px 18px;
      font-weight: 500;
      cursor: pointer;
    }
    .otter-button-secondary:hover, .otter-btn-secondary:hover {
      background-color: #475569 !important;
    }
    .otter-button-danger, .otter-btn-danger {
      background-color: #dc2626 !important;
      color: #ffffff !important;
      border: none !important;
      border-radius: 8px;
      padding: 10px 18px;
      font-weight: 600;
      cursor: pointer;
    }
    .otter-button-danger:hover, .otter-btn-danger:hover {
      background-color: #b91c1c !important;
    }
    .otter-panel {
      display: flex;
      flex-direction: column;
      box-sizing: border-box;
      min-width: 0;
    }
    .otter-conditional {
      display: flex;
      flex-direction: column;
      box-sizing: border-box;
      width: 100%;
    }
    .otter-card-title {
      font-size: 1.15rem;
      font-weight: 700;
      color: var(--otter-text);
      letter-spacing: -0.01em;
      margin-bottom: 12px;
    }
    .otter-image {
      max-width: 100%;
      height: auto;
      border-radius: 6px;
      display: block;
    }
    .otter-link {
      color: #38bdf8;
      text-decoration: none;
      font-weight: 500;
      transition: color 0.15s ease;
    }
    .otter-link:hover {
      color: #7dd3fc;
      text-decoration: underline;
    }
    .otter-checkbox-label {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      cursor: pointer;
      user-select: none;
      font-size: 0.95rem;
    }
    .otter-checkbox {
      width: 18px;
      height: 18px;
      cursor: pointer;
      accent-color: var(--otter-primary);
    }
    .otter-select {
      background-color: var(--otter-input-bg);
      color: var(--otter-text);
      border: 1px solid var(--otter-border);
      border-radius: 8px;
      padding: 10px 14px;
      font-size: 0.95rem;
      outline: none;
      cursor: pointer;
      width: 100%;
    }
    .otter-slider {
      width: 100%;
      cursor: pointer;
      accent-color: var(--otter-primary);
    }
    .otter-textarea {
      background-color: var(--otter-input-bg);
      color: var(--otter-text);
      border: 1px solid var(--otter-border);
      border-radius: 8px;
      padding: 10px 14px;
      font-size: 0.95rem;
      outline: none;
      width: 100%;
      resize: vertical;
      font-family: inherit;
    }
    .otter-badge {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 4px 10px;
      border-radius: 9999px;
      font-size: 0.75rem;
      font-weight: 600;
      white-space: nowrap;
      background: rgba(37,99,235,0.2);
      color: #93c5fd;
      border: 1px solid rgba(37,99,235,0.3);
    }
    .otter-canvas {
      background: #020617;
      border: 1px solid var(--otter-border);
      border-radius: 8px;
      max-width: 100%;
      display: block;
    }
    #otter-live-output {
      margin-top: 16px;
      padding: 8px 12px;
      background: rgba(0,0,0,0.3);
      border-radius: 6px;
      font-family: monospace;
      font-size: 0.85rem;
      color: #38bdf8;
      display: none;
    }
$declarativeCssJoined
  </style>
</head>
<body>
$elementsHtml
  <div id="otter-live-output"></div>

  <script>
    // Otter Runtime helpers for the browser
    const empty = "";
    const gone = null;
    function otterGetElement(id) { return document.getElementById(id); }
    function otterGetText(id) {
      const el = otterGetElement(id);
      if (!el) return '';
      if (el.type === 'checkbox') return el.checked;
      if ('value' in el) return el.value;
      return el.textContent || '';
    }
    function otterSetText(id, val) {
      const el = otterGetElement(id);
      if (!el) return;
      if (el.type === 'checkbox') { el.checked = Boolean(val); return; }
      if ('value' in el) { el.value = val; }
      else { el.textContent = val; }
    }
    function otterGetTitle(id) { return document.title; }
    function otterSetTitle(id, val) { document.title = val; }
    function otterSetStyle(id, prop, val) {
      const el = otterGetElement(id);
      if (el) el.style[prop] = val;
    }
    function otterGetStyle(id, prop) {
      const el = otterGetElement(id);
      return el ? el.style[prop] : '';
    }
    function otterSetProperty(id, prop, val) {
      const el = otterGetElement(id);
      if (el) {
        if (prop === 'url' && el.tagName === 'A') { el.href = val; return; }
        el[prop] = val;
        if (el.dataset) el.dataset[prop] = val;
      }
    }
    function otterGetProperty(id, prop) {
      const el = otterGetElement(id);
      return el ? el[prop] : '';
    }
    function otterSay(...args) {
      console.log(...args);
      const out = document.getElementById('otter-live-output');
      if (out) {
        out.style.display = 'block';
        out.textContent = args.join(' ');
      }
    }

    // Otter Declarative Reactivity Engine
    const otterState = {};
    const otterDerived = {};
    const otterWatchers = [];

$stateInitJoined

$deriveInitJoined

$watcherInitJoined

    function otterEvaluateExpr(expr) {
      try {
        const fn = new Function('state', 'derived', 'with(state) { with(derived) { return (' + expr + '); } }');
        return fn(otterState, otterDerived);
      } catch(err) {
        console.warn('Otter eval error in expr:', expr, err);
        return '';
      }
    }

    function otterUpdateReactivity() {
      document.querySelectorAll('[data-otter-bind]').forEach(el => {
        const expr = el.getAttribute('data-otter-bind');
        if (!expr) return;
        const val = otterEvaluateExpr(expr);
        if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
          if (el.type === 'checkbox') el.checked = Boolean(val);
          else el.value = val;
        } else {
          el.textContent = (val === null || val === undefined) ? '' : String(val);
        }
      });

      document.querySelectorAll('[data-otter-if]').forEach(el => {
        const cond = el.getAttribute('data-otter-if');
        if (!cond) return;
        const show = Boolean(otterEvaluateExpr(cond));
        el.style.display = show ? '' : 'none';
      });
    }

    function otterNotifyWatchers(name) {
      for (const w of otterWatchers) {
        if (w.target === name && typeof w.callback === 'function') {
          try { w.callback(); } catch(e) { console.error('Watcher callback error:', e); }
        }
      }
    }

    function otterSetState(name, value) {
      otterState[name] = value;
      window[name] = value;
      otterUpdateReactivity();
      otterNotifyWatchers(name);
    }

    // Automatic 3D Canvas and Animation Runner
    document.querySelectorAll('canvas.otter-canvas').forEach((canvas) => {
      const mode = canvas.getAttribute('data-mode') || '2d';
      const anim = canvas.getAttribute('data-animation') || '';
      if (mode === '3d' || anim === 'spin' || anim === '3d') {
        const ctx = canvas.getContext('2d');
        if (!ctx) return;
        let angleX = 0;
        let angleY = 0;
        const vertices = [
          [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
          [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]
        ];
        const edges = [
          [0,1],[1,2],[2,3],[3,0],
          [4,5],[5,6],[6,7],[7,4],
          [0,4],[1,5],[2,6],[3,7]
        ];
        function render3D() {
          ctx.clearRect(0, 0, canvas.width, canvas.height);

          // Dynamic speed calculation from slider or canvas property
          let spd = 1.0;
          const liveSlider = document.getElementById('speedSlider') || document.querySelector('input[type="range"]');
          if (canvas.speed !== undefined && canvas.speed !== null && canvas.speed !== '') {
            spd = Number(canvas.speed) / 25;
          } else if (canvas.dataset.speed) {
            spd = Number(canvas.dataset.speed) / 25;
          } else if (liveSlider) {
            spd = Number(liveSlider.value) / 25;
          }
          const turbo = document.getElementById('agreeCheckbox');
          if (turbo && turbo.checked) {
            spd *= 2.0;
          }
          if (isNaN(spd) || spd < 0) spd = 0;

          angleX += 0.015 * spd;
          angleY += 0.02 * spd;
          const cx = canvas.width / 2;
          const cy = canvas.height / 2;
          const scale = Math.min(cx, cy) * 0.55;
          const projected = vertices.map(([x, y, z]) => {
            let cosY = Math.cos(angleY), sinY = Math.sin(angleY);
            let x1 = x * cosY - z * sinY;
            let z1 = x * sinY + z * cosY;
            let cosX = Math.cos(angleX), sinX = Math.sin(angleX);
            let y2 = y * cosX - z1 * sinX;
            let z2 = y * sinX + z1 * cosX;
            const distance = 3.2;
            const p = distance / (distance + z2);
            return [cx + x1 * scale * p, cy + y2 * scale * p];
          });
          const themeSel = document.getElementById('themeDropdown');
          let strokeCol = canvas.color || canvas.dataset.color || '#38bdf8';
          let glowCol = canvas.glow || canvas.dataset.glow || '#0284c7';
          if (themeSel) {
            if (themeSel.value === 'Electric Indigo') {
              strokeCol = '#c084fc'; glowCol = '#a855f7';
            } else if (themeSel.value === 'Cyberpunk Emerald') {
              strokeCol = '#34d399'; glowCol = '#059669';
            }
          }
          ctx.strokeStyle = strokeCol;
          ctx.lineWidth = 2.5;
          ctx.shadowColor = glowCol;
          ctx.shadowBlur = 8;
          edges.forEach(([i, j]) => {
            ctx.beginPath();
            ctx.moveTo(projected[i][0], projected[i][1]);
            ctx.lineTo(projected[j][0], projected[j][1]);
            ctx.stroke();
          });
          requestAnimationFrame(render3D);
        }
        render3D();

        const liveSlider = document.getElementById('speedSlider') || document.querySelector('input[type="range"]');
        if (liveSlider) {
          const updateSpeedLabel = () => {
            const lbl = document.getElementById('speedLabel');
            if (lbl) {
              lbl.textContent = 'Animation Speed: ' + liveSlider.value + '%';
            }
          };
          liveSlider.addEventListener('input', updateSpeedLabel);
          updateSpeedLabel();
        }
      }
    });

    // Top-level application initialization
    (async function() {
$topLevelJoined

    // Register event listeners
$handlersJoined

$declarativeListenersJoined

    if (typeof otterUpdateReactivity === 'function') {
      otterUpdateReactivity();
    }
    })();
  </script>
</body>
</html>
"@

    return $html
}

function Export-OtterWebApplication {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [string]$OutputPath,
        [switch]$PassThruExceptions
    )

    $resolvedSource = Resolve-Path -LiteralPath $SourcePath
    $sourceText = Get-Content -LiteralPath $resolvedSource -Raw -Encoding UTF8

    if (-not (Get-Command ConvertTo-OtterTokens -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Lexer.psm1') -Global
    }
    if (-not (Get-Command ConvertTo-OtterAst -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Parser.psm1') -Global
    }

    try {
        $tokens = ConvertTo-OtterTokens -Source $sourceText
        $ast = ConvertTo-OtterAst -Tokens $tokens

        $defaultTitle = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)
        $html = ConvertTo-OtterWeb -Program $ast -Title $defaultTitle
    }
    catch [OtterError] {
        if ($PassThruExceptions) { throw }
        Write-Host ''
        Write-Host $_.Exception.FormatDetailed() -ForegroundColor Red
        Write-Host ''
        exit 1
    }
    catch {
        if ($PassThruExceptions) { throw }
        Write-Host ''
        Write-Host 'Otter hit a problem inside itself, which means this is a bug in Otter.' -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
        Write-Host ''
        exit 1
    }

    if (-not $OutputPath) {
        $OutputPath = [System.IO.Path]::ChangeExtension($resolvedSource, '.html')
    }

    Set-Content -LiteralPath $OutputPath -Value $html -Encoding UTF8
    Write-Verbose "Otter Web App compiled to: $OutputPath"
    return $OutputPath
}

Export-ModuleMember -Function ConvertTo-OtterWeb, Export-OtterWebApplication
