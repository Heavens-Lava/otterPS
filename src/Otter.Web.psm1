using module ..\Otter.Contract.psm1
using module .\Otter.Compiler.JavaScript.psm1
using module .\Otter.Module.psm1

# Otter.Web.psm1
#
# D50: Otter Web App Compiler
# Compiles Otter AST / UI programs into standalone, responsive, modern HTML5/CSS3/JavaScript web apps.
#
# D60 Phase 1A: ConvertTo-OtterJsExpression/ConvertTo-OtterJsStatement moved
# to Otter.Compiler.JavaScript.psm1 (the provider-agnostic AST->JS emitter,
# owned separately per D60). This file is now a target adapter: it consumes
# that module rather than defining the generic emission logic itself.

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
            $labelText = Escape-OtterHtmlAttr -Text ([string]$Element.Label.Value)
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
            # D60 Phase 1F: also let this reach the normal top-level
            # compilation pass (below) so it compiles to a real callable JS
            # function, in addition to the existing $functions lookup this
            # file already uses for declarative-UI-root scanning. No
            # `continue` - deliberately falls through to
            # $topLevelStatements.Add($stmt) at the end of this loop.
            $functions[$stmt.Name] = $stmt
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
                'text area', 'textarea', 'badge', 'tag', 'canvas', 'table', 'scroll',
                'progress', 'progress bar', 'toggle', 'switch', 'radio', 'radio button',
                'dialog', 'modal'
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

    $isPage = ($null -ne $rootName -and $resources[$rootName].Kind -eq 'page')
    $bodyClass = if ($isPage) { ' class="otter-has-page"' } else { '' }

    # HTML rendering helper
    function Render-OtterElement([string]$resName) {
        if (-not $resources.Contains($resName)) { return "" }
        $r = $resources[$resName]
        $kind = $r.Kind
        $props = $r.Properties

        $styles = [System.Collections.Generic.List[string]]::new()
        if ($props.Contains('width')) {
            $w = $props['width']
            $wCss = if ($w -eq 'full') { "100%; max-width: 100%" } elseif ($w -is [int] -or $w -is [double]) { "${w}px" } else { $w }
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
        if ($props.Contains('whitespace')) {
            $styles.Add("white-space: $($props['whitespace']);")
        }
        if ($props.Contains('overflow')) {
            $styles.Add("overflow: $($props['overflow']);")
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
      <div class="otter-page-content" style="display: flex; flex-direction: column; gap: ${spacing}px; width: 100%; min-width: 0; flex: 1 1 0%; min-height: 0; height: 100%;">$childHtml</div>
    </main>
"@
            }
            'card' {
                $spacing = if ($props.Contains('spacing')) { $props['spacing'] } else { 12 }
                if (-not $props.Contains('gap')) { $styles.Add("gap: ${spacing}px;") }
                $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
                $cardTitle = if ($props.Contains('title')) { "<h3 class=`"otter-card-title`">$(Escape-OtterHtmlAttr -Text ([string]$props['title']))</h3>" } else { "" }
                return @"
      <div id="$resName" class="otter-card"$styleAttr>
        $cardTitle
        $childHtml
      </div>
"@
            }
            'button' {
                $rawText = if ($props.Contains('text')) { [string]$props['text'] } else { "Button" }
                $text = Escape-OtterHtmlAttr -Text $rawText
                return "      <button id=`"$resName`" class=`"otter-button`"$styleAttr>$text</button>"
            }
            'text box' {
                $rawVal = if ($props.Contains('text')) { [string]$props['text'] } elseif ($props.Contains('value')) { [string]$props['value'] } else { "" }
                $val = Escape-OtterHtmlAttr -Text $rawVal
                $ph = if ($props.Contains('placeholder')) { " placeholder=`"$(Escape-OtterHtmlAttr -Text ([string]$props['placeholder']))`"" } else { "" }
                return "      <input type=`"text`" id=`"$resName`" class=`"otter-text-box`" value=`"$val`"$ph$styleAttr />"
            }
            'text' {
                $rawVal = if ($props.Contains('text')) { [string]$props['text'] } elseif ($props.Contains('value')) { [string]$props['value'] } else { "" }
                $val = Escape-OtterHtmlAttr -Text $rawVal
                return "      <div id=`"$resName`" class=`"otter-text`"$styleAttr>$val</div>"
            }
            'image' {
                $rawSrc = if ($props.Contains('source')) { [string]$props['source'] } elseif ($props.Contains('src')) { [string]$props['src'] } else { "" }
                $rawAlt = if ($props.Contains('alt')) { [string]$props['alt'] } else { $resName }
                $src = Escape-OtterHtmlAttr -Text $rawSrc
                $alt = Escape-OtterHtmlAttr -Text $rawAlt
                return "      <img id=`"$resName`" class=`"otter-image`" src=`"$src`" alt=`"$alt`"$styleAttr />"
            }
            'link' {
                $rawHref = if ($props.Contains('url')) { [string]$props['url'] } elseif ($props.Contains('href')) { [string]$props['href'] } else { "#" }
                $rawText = if ($props.Contains('text')) { [string]$props['text'] } else { $rawHref }
                $href = Escape-OtterHtmlAttr -Text $rawHref
                $text = Escape-OtterHtmlAttr -Text $rawText
                $isExternal = [string]$rawHref -match '^(?i)https?://'
                $linkAttrs = if ($isExternal) { ' target="_blank" rel="noopener noreferrer"' } else { '' }
                return "      <a id=`"$resName`" class=`"otter-link`" href=`"$href`"$styleAttr$linkAttrs>$text</a>"
            }
            { $_ -in @('checkbox', 'check box') } {
                $rawText = if ($props.Contains('text')) { [string]$props['text'] } else { "" }
                $text = Escape-OtterHtmlAttr -Text $rawText
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
                $optHtml = ($opts | ForEach-Object {
                    $escOpt = Escape-OtterHtmlAttr -Text ([string]$_)
                    "        <option value=`"$escOpt`">$escOpt</option>"
                }) -join "`n"
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
                $rawVal = if ($props.Contains('text')) { [string]$props['text'] } elseif ($props.Contains('value')) { [string]$props['value'] } else { "" }
                $val = Escape-OtterHtmlAttr -Text $rawVal
                $ph = if ($props.Contains('placeholder')) { " placeholder=`"$(Escape-OtterHtmlAttr -Text ([string]$props['placeholder']))`"" } else { "" }
                $rows = if ($props.Contains('rows')) { $props['rows'] } else { 3 }
                return "      <textarea id=`"$resName`" class=`"otter-text-area`" rows=`"$rows`"$ph$styleAttr>$val</textarea>"
            }
            { $_ -in @('badge', 'tag') } {
                $rawText = if ($props.Contains('text')) { [string]$props['text'] } else { "" }
                $text = Escape-OtterHtmlAttr -Text $rawText
                return "      <span id=`"$resName`" class=`"otter-badge`"$styleAttr>$text</span>"
            }
            'canvas' {
                $w = if ($props.Contains('width')) { $props['width'] } else { 400 }
                $h = if ($props.Contains('height')) { $props['height'] } else { 300 }
                $anim = if ($props.Contains('animation')) { Escape-OtterHtmlAttr -Text ([string]$props['animation']) } else { "" }
                $mode = if ($props.Contains('mode')) { Escape-OtterHtmlAttr -Text ([string]$props['mode']) } else { "2d" }
                return "      <canvas id=`"$resName`" class=`"otter-canvas`" width=`"$w`" height=`"$h`" data-animation=`"$anim`" data-mode=`"$mode`"$styleAttr></canvas>"
            }
            { $_ -in @('progress', 'progress bar') } {
                $val = if ($props.Contains('value')) { $props['value'] } else { 0 }
                $max = if ($props.Contains('max')) { $props['max'] } else { 100 }
                return "      <progress id=`"$resName`" class=`"otter-progress`" value=`"$val`" max=`"$max`"$styleAttr></progress>"
            }
            { $_ -in @('toggle', 'switch') } {
                $rawText = if ($props.Contains('text')) { [string]$props['text'] } else { "" }
                $text = Escape-OtterHtmlAttr -Text $rawText
                $checked = if ($props.Contains('checked') -and ($props['checked'] -eq $true -or $props['checked'] -eq 'true')) { " checked" } else { "" }
                return "      <label class=`"otter-toggle-label`"$styleAttr><input type=`"checkbox`" id=`"$resName`" class=`"otter-toggle`" role=`"switch`"$checked /><span class=`"otter-toggle-track`"><span class=`"otter-toggle-thumb`"></span></span><span class=`"otter-toggle-text`">$text</span></label>"
            }
            { $_ -in @('radio', 'radio button') } {
                $rawText = if ($props.Contains('text')) { [string]$props['text'] } else { "" }
                $text = Escape-OtterHtmlAttr -Text $rawText
                $rawGroup = if ($props.Contains('group')) { [string]$props['group'] } elseif ($props.Contains('name')) { [string]$props['name'] } else { "default-group" }
                $group = Escape-OtterHtmlAttr -Text $rawGroup
                $checked = if ($props.Contains('checked') -and ($props['checked'] -eq $true -or $props['checked'] -eq 'true')) { " checked" } else { "" }
                return "      <label class=`"otter-radio-label`"$styleAttr><input type=`"radio`" id=`"$resName`" name=`"$group`" class=`"otter-radio`"$checked /> <span>$text</span></label>"
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
            'scroll' {
                $styles.Add("overflow-y: auto; overflow-x: hidden; display: flex; flex-direction: column;")
                $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
                return @"
      <div id="$resName" class="otter-scroll"$styleAttr>$childHtml</div>
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
    # D60 Phase 1F.1: computed once, passed to every top-level statement so
    # any FunctionDefStmt among them can tell a real pre-existing global
    # apart from a genuinely function-local name - see
    # Get-OtterJsTopLevelGlobalNames for why a whole-program scan is the
    # right approximation of the interpreter's own non-hoisted, sequential
    # execution model.
    $topLevelGlobals = (Get-OtterJsTopLevelGlobalNames -TopLevelStatements $topLevelStatements).Names
    $topLevelJs = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $topLevelStatements) {
        $topLevelJs.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent 2 -KnownGlobals $topLevelGlobals))
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
    body.otter-has-page {
      display: flex;
      flex-direction: column;
      padding: 0;
      margin: 0;
      min-height: 100vh;
      height: 100vh;
      max-height: 100vh;
      box-sizing: border-box;
      overflow: hidden;
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
    .otter-scroll {
      overflow-y: auto;
      overflow-x: hidden;
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
    .otter-text-area,
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
    .otter-progress {
      width: 100%;
      height: 12px;
      border-radius: 9999px;
      overflow: hidden;
      appearance: none;
      -webkit-appearance: none;
      border: 1px solid var(--otter-border);
      background: var(--otter-input-bg);
    }
    .otter-progress::-webkit-progress-bar {
      background: var(--otter-input-bg);
      border-radius: 9999px;
    }
    .otter-progress::-webkit-progress-value {
      background: linear-gradient(90deg, #38bdf8, #818cf8);
      border-radius: 9999px;
      transition: width 0.3s ease;
    }
    .otter-progress::-moz-progress-bar {
      background: linear-gradient(90deg, #38bdf8, #818cf8);
      border-radius: 9999px;
    }
    .otter-toggle-label {
      display: inline-flex;
      align-items: center;
      gap: 10px;
      cursor: pointer;
      user-select: none;
    }
    .otter-toggle {
      position: absolute;
      opacity: 0;
      width: 0;
      height: 0;
    }
    .otter-toggle-track {
      width: 44px;
      height: 24px;
      background: rgba(255, 255, 255, 0.2);
      border-radius: 9999px;
      position: relative;
      transition: background 0.25s ease;
    }
    .otter-toggle-thumb {
      position: absolute;
      top: 2px;
      left: 2px;
      width: 20px;
      height: 20px;
      background: white;
      border-radius: 50%;
      transition: transform 0.25s ease;
      box-shadow: 0 2px 4px rgba(0,0,0,0.3);
    }
    .otter-toggle:checked + .otter-toggle-track {
      background: var(--otter-primary);
    }
    .otter-toggle:checked + .otter-toggle-track .otter-toggle-thumb {
      transform: translateX(20px);
    }
    .otter-radio-label {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      cursor: pointer;
      user-select: none;
    }
    .otter-radio {
      width: 18px;
      height: 18px;
      cursor: pointer;
      accent-color: var(--otter-primary);
    }
    .otter-toast-container {
      position: fixed;
      bottom: 24px;
      right: 24px;
      display: flex;
      flex-direction: column;
      gap: 10px;
      z-index: 99999;
      pointer-events: none;
    }
    .otter-toast {
      background: #1e293b;
      color: #f8fafc;
      border: 1px solid #334155;
      box-shadow: 0 10px 25px rgba(0,0,0,0.5);
      padding: 12px 18px;
      border-radius: 8px;
      font-size: 0.9rem;
      pointer-events: auto;
      animation: otterToastIn 0.25s ease-out;
      max-width: 320px;
    }
    @keyframes otterToastIn {
      from { transform: translateY(12px); opacity: 0; }
      to { transform: translateY(0); opacity: 1; }
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
<body$bodyClass>
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
      const tag = el.tagName ? el.tagName.toUpperCase() : '';
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') {
        return el.value;
      }
      return el.textContent || '';
    }
    function otterSetText(id, val) {
      const el = otterGetElement(id);
      if (!el) return;
      if (el.type === 'checkbox') { el.checked = Boolean(val); return; }
      const tag = el.tagName ? el.tagName.toUpperCase() : '';
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') {
        el.value = val;
      } else {
        el.textContent = val;
      }
      if ('value' in el) { el.value = val; }
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
    async function otterReadFile(filePath) {
      const bridge = window.__OTTER_DESKTOP_BRIDGE__;
      if (!bridge || !bridge.port || !bridge.token) {
        console.warn('Desktop Bridge is not available to read "' + filePath + '".');
        return '';
      }
      const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/fs/read', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Otter-Token': bridge.token
        },
        body: JSON.stringify({ path: filePath })
      });
      if (!resp.ok) {
        throw new Error('Could not read file "' + filePath + '": HTTP ' + resp.status);
      }
      const data = await resp.json();
      return data.content || '';
    }
    async function otterWriteFile(filePath, content) {
      const bridge = window.__OTTER_DESKTOP_BRIDGE__;
      if (!bridge || !bridge.port || !bridge.token) {
        console.warn('Desktop Bridge is not available to write "' + filePath + '".');
        return false;
      }
      const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/fs/write', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Otter-Token': bridge.token
        },
        body: JSON.stringify({ path: filePath, content: content })
      });
      if (!resp.ok) {
        throw new Error('Could not write file "' + filePath + '": HTTP ' + resp.status);
      }
      return await resp.json();
    }
    window.otterWriteFile = otterWriteFile;

    async function otterDownloadFile(url, filePath) {
      const bridge = window.__OTTER_DESKTOP_BRIDGE__;
      if (!bridge || !bridge.port || !bridge.token) {
        throw new Error('Desktop Bridge is not available for file download in this browser.');
      }
      const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/fs/download', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Otter-Token': bridge.token
        },
        body: JSON.stringify({ url: url, path: filePath })
      });
      if (!resp.ok) {
        const err = await resp.json().catch(() => ({}));
        throw new Error(err.error || ('Download failed with HTTP ' + resp.status));
      }
      return await resp.json();
    }
    window.otterDownloadFile = otterDownloadFile;

    async function otterRunCommand(command) {
      const bridge = window.__OTTER_DESKTOP_BRIDGE__;
      if (!bridge || !bridge.port || !bridge.token) {
        throw new Error('Desktop Bridge is not available to run "' + command + '".');
      }
      const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/terminal/exec', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Otter-Token': bridge.token
        },
        body: JSON.stringify({ command: command })
      });
      if (!resp.ok) {
        throw new Error('Could not execute command "' + command + '": HTTP ' + resp.status);
      }
      const data = await resp.json();
      const stdout = data.stdout || '';
      const stderr = data.stderr || '';
      return {
        __otterThing: true,
        typeName: 'command result',
        props: {
          output: stdout,
          'error output': stderr,
          'exit code': Number.isFinite(Number(data.exitCode)) ? Number(data.exitCode) : -1
        },
        order: ['output', 'error output', 'exit code']
      };
    }
    window.otterRunCommand = otterRunCommand;

    async function otterGetFiles(folderPath, includeSubfolders = false) {
      const bridge = window.__OTTER_DESKTOP_BRIDGE__;
      if (!bridge || !bridge.port || !bridge.token) {
        console.warn('Desktop Bridge is not available to get files in "' + folderPath + '".');
        return [];
      }
      const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/fs/files', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Otter-Token': bridge.token
        },
        body: JSON.stringify({ path: folderPath, recursive: includeSubfolders })
      });
      if (!resp.ok) {
        throw new Error('Could not get files in "' + folderPath + '": HTTP ' + resp.status);
      }
      return await resp.json();
    }
    window.otterGetFiles = otterGetFiles;

    async function otterGetFolders(folderPath, includeSubfolders = false) {
      const bridge = window.__OTTER_DESKTOP_BRIDGE__;
      if (!bridge || !bridge.port || !bridge.token) {
        console.warn('Desktop Bridge is not available to get folders in "' + folderPath + '".');
        return [];
      }
      const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/fs/folders', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Otter-Token': bridge.token
        },
        body: JSON.stringify({ path: folderPath, recursive: includeSubfolders })
      });
      if (!resp.ok) {
        throw new Error('Could not get folders in "' + folderPath + '": HTTP ' + resp.status);
      }
      return await resp.json();
    }
    window.otterGetFolders = otterGetFolders;

    async function otterFileOperation(operation, payload) {
      const bridge = window.__OTTER_DESKTOP_BRIDGE__;
      if (!bridge || !bridge.port || !bridge.token) {
        throw new Error('Desktop Bridge is not available for file operations.');
      }
      const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/fs/operate', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Otter-Token': bridge.token
        },
        body: JSON.stringify(Object.assign({ operation: operation }, payload || {}))
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) {
        throw new Error(data.error || 'The filesystem operation could not be completed.');
      }
      return data;
    }
    async function otterFileExists(filePath) {
      const result = await otterFileOperation('file-exists', { path: filePath });
      return Boolean(result.exists);
    }
    function otterAppendFile(filePath, content) { return otterFileOperation('append-file', { path: filePath, content: content }); }
    function otterCopyFile(source, destination) { return otterFileOperation('copy-file', { source: source, destination: destination }); }
    function otterMoveFile(source, destination) { return otterFileOperation('move-file', { source: source, destination: destination }); }
    function otterDeleteFile(filePath) { return otterFileOperation('delete-file', { path: filePath }); }
    function otterCreateFolder(folderPath) { return otterFileOperation('create-folder', { path: folderPath }); }
    function otterDeleteFolder(folderPath) { return otterFileOperation('delete-folder', { path: folderPath }); }
    function otterCopyFolder(source, destination) { return otterFileOperation('copy-folder', { source: source, destination: destination }); }
    function otterMoveFolder(source, destination) { return otterFileOperation('move-folder', { source: source, destination: destination }); }
    window.otterFileExists = otterFileExists;
    window.otterAppendFile = otterAppendFile;
    window.otterCopyFile = otterCopyFile;
    window.otterMoveFile = otterMoveFile;
    window.otterDeleteFile = otterDeleteFile;
    window.otterCreateFolder = otterCreateFolder;
    window.otterDeleteFolder = otterDeleteFolder;
    window.otterCopyFolder = otterCopyFolder;
    window.otterMoveFolder = otterMoveFolder;
    function otterWait(seconds) {
      const ms = Math.max(0, Number(seconds) * 1000);
      return new Promise(resolve => setTimeout(resolve, ms));
    }
    function otterDelay(ms) {
      const delayMs = Math.max(0, Number(ms));
      return new Promise(resolve => setTimeout(resolve, delayMs));
    }
    window.otterWait = otterWait;
    window.otterDelay = otterDelay;
    window.wait = otterWait;
    window.delay = otterDelay;
    // D67: getDesktopBridge() was called by every system-integration hook
    // below (clipboard/notify/env/systemPaths/chooseFile/chooseFolder/
    // saveFileDialog) but never actually defined anywhere in this file -
    // a real, confirmed "ReferenceError: getDesktopBridge is not
    // defined" for every one of them on a plain `otter web` compile
    // (found by loading a real compiled page in a real browser, not by
    // reading the code). The desktop-bridge path itself was unaffected,
    // since Otter.Desktop.psm1's own injection completely overrides
    // window.otterClipboard/etc. before this file's definitions would
    // ever run. Matches the exact `window.__OTTER_DESKTOP_BRIDGE__`
    // check every other already-working hook (otterReadFile,
    // otterGetFiles, etc.) already uses inline, just factored into the
    // one shared helper name this file's own code already assumed existed.
    function getDesktopBridge() {
      return window.__OTTER_DESKTOP_BRIDGE__ || null;
    }
    window.otterClipboard = {
      copy: async function(text) {
        const bridge = getDesktopBridge();
        if (bridge) {
          const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/system/clipboard', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-Otter-Token': bridge.token },
            body: JSON.stringify({ text: text })
          });
          return await resp.json();
        }
        if (navigator.clipboard) {
          await navigator.clipboard.writeText(text);
          return { completed: true };
        }
        return { completed: false };
      },
      paste: async function() {
        const bridge = getDesktopBridge();
        if (bridge) {
          const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/system/clipboard', {
            method: 'GET',
            headers: { 'X-Otter-Token': bridge.token }
          });
          const data = await resp.json();
          return data.text || '';
        }
        if (navigator.clipboard) {
          return await navigator.clipboard.readText();
        }
        return '';
      }
    };
    window.otterNotify = async function(title, message) {
      const bridge = getDesktopBridge();
      if (bridge) {
        fetch('http://127.0.0.1:' + bridge.port + '/api/system/notify', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Otter-Token': bridge.token },
          body: JSON.stringify({ title: title, message: message })
        }).catch(() => {});
      }
      let container = document.getElementById('otter-toast-container');
      if (!container) {
        container = document.createElement('div');
        container.id = 'otter-toast-container';
        container.className = 'otter-toast-container';
        document.body.appendChild(container);
      }
      const toast = document.createElement('div');
      toast.className = 'otter-toast';
      const toastTitle = document.createElement('strong');
      toastTitle.textContent = title || 'Notification';
      const toastMsg = document.createElement('div');
      toastMsg.textContent = message || '';
      toast.appendChild(toastTitle);
      toast.appendChild(toastMsg);
      container.appendChild(toast);
      setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transition = 'opacity 0.3s';
        setTimeout(() => toast.remove(), 300);
      }, 3500);
      return { completed: true };
    };
    window.otterGetEnv = async function(name) {
      const bridge = getDesktopBridge();
      if (bridge) {
        const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/system/env', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Otter-Token': bridge.token },
          body: JSON.stringify({ name: name })
        });
        const data = await resp.json();
        return data.value;
      }
      return null;
    };
    window.otterGetSystemPaths = async function() {
      const bridge = getDesktopBridge();
      if (bridge) {
        const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/system/env', {
          method: 'GET',
          headers: { 'X-Otter-Token': bridge.token }
        });
        return await resp.json();
      }
      return {};
    };
    window.otterChooseFile = async function() {
      const bridge = getDesktopBridge();
      if (bridge) {
        const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/dialog/open-file', {
          method: 'POST',
          headers: { 'X-Otter-Token': bridge.token }
        });
        const data = await resp.json();
        return data.path || '';
      }
      return '';
    };
    window.otterChooseFolder = async function() {
      const bridge = getDesktopBridge();
      if (bridge) {
        const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/dialog/folder', {
          method: 'POST',
          headers: { 'X-Otter-Token': bridge.token }
        });
        const data = await resp.json();
        return data.path || '';
      }
      return '';
    };
    window.otterSaveFileDialog = async function() {
      const bridge = getDesktopBridge();
      if (bridge) {
        const resp = await fetch('http://127.0.0.1:' + bridge.port + '/api/dialog/save-file', {
          method: 'POST',
          headers: { 'X-Otter-Token': bridge.token }
        });
        const data = await resp.json();
        return data.path || '';
      }
      return '';
    };
    window.copyToClipboard = window.otterClipboard.copy;
    window.getClipboard = window.otterClipboard.paste;
    window.notify = window.otterNotify;
    window.chooseFile = window.otterChooseFile;
    window.chooseFolder = window.otterChooseFolder;
    window.saveFileDialog = window.otterSaveFileDialog;
    window.otterStorage = {
      get: function(key, defaultVal = null) {
        try {
          const val = localStorage.getItem(key);
          if (val === null) return defaultVal;
          try { return JSON.parse(val); } catch(_) { return val; }
        } catch(_) { return defaultVal; }
      },
      set: function(key, val) {
        try {
          const serialized = (typeof val === 'object' && val !== null) ? JSON.stringify(val) : String(val);
          localStorage.setItem(key, serialized);
          return true;
        } catch(_) { return false; }
      },
      remove: function(key) {
        try { localStorage.removeItem(key); return true; } catch(_) { return false; }
      },
      clear: function() {
        try { localStorage.clear(); return true; } catch(_) { return false; }
      },
      session: {
        get: function(key, defaultVal = null) {
          try {
            const val = sessionStorage.getItem(key);
            if (val === null) return defaultVal;
            try { return JSON.parse(val); } catch(_) { return val; }
          } catch(_) { return defaultVal; }
        },
        set: function(key, val) {
          try {
            const serialized = (typeof val === 'object' && val !== null) ? JSON.stringify(val) : String(val);
            sessionStorage.setItem(key, serialized);
            return true;
          } catch(_) { return false; }
        },
        remove: function(key) {
          try { sessionStorage.removeItem(key); return true; } catch(_) { return false; }
        }
      }
    };
    window.getStorage = window.otterStorage.get;
    window.setStorage = window.otterStorage.set;
    window.removeStorage = window.otterStorage.remove;
    window.otterFetch = async function(url, options = {}) {
      const resp = await fetch(url, options);
      const contentType = resp.headers.get('content-type') || '';
      let data;
      if (contentType.includes('application/json')) {
        data = await resp.json();
      } else {
        data = await resp.text();
      }
      return {
        ok: resp.ok,
        status: resp.status,
        statusText: resp.statusText,
        data: data,
        headers: Object.fromEntries(resp.headers.entries())
      };
    };
    window.otterGetJson = async function(url, headers = {}) {
      const res = await window.otterFetch(url, { method: 'GET', headers: Object.assign({ 'Accept': 'application/json' }, headers) });
      return res.data;
    };
    window.otterPostJson = async function(url, body = {}, headers = {}) {
      const res = await window.otterFetch(url, {
        method: 'POST',
        headers: Object.assign({ 'Content-Type': 'application/json', 'Accept': 'application/json' }, headers),
        body: JSON.stringify(body)
      });
      return res.data;
    };
    window.httpGet = window.otterGetJson;
    window.httpPost = window.otterPostJson;

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
        [Parameter(Mandatory)][string[]]$SourcePath,
        [string]$OutputPath,
        [switch]$PassThruExceptions
    )

    if (-not (Get-Command ConvertTo-OtterTokens -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Lexer.psm1') -Global
    }
    if (-not (Get-Command ConvertTo-OtterAst -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Parser.psm1') -Global
    }
    if (-not (Get-Command Resolve-OtterModuleSource -ErrorAction SilentlyContinue)) {
        Import-Module (Join-Path $PSScriptRoot 'Otter.Module.psm1') -Global
    }

    $sourceParts = [System.Collections.Generic.List[string]]::new()
    $primarySource = $null
    $resolvedProgram = $null

    foreach ($src in $SourcePath) {
        $resolved = Resolve-Path -LiteralPath $src
        if ($null -eq $primarySource) { $primarySource = $resolved.Path }
        $resolvedProgram = Resolve-OtterModuleSource -FilePath $resolved.Path
        $sourceParts.Add($resolvedProgram.CombinedSource)
    }
    $sourceText = $sourceParts -join "`n"

    try {
        $tokens = ConvertTo-OtterTokens -Source $sourceText
        $ast = ConvertTo-OtterAst -Tokens $tokens

        $defaultTitle = [System.IO.Path]::GetFileNameWithoutExtension($primarySource)
        $html = ConvertTo-OtterWeb -Program $ast -Title $defaultTitle

        $sidecarCss = [System.IO.Path]::ChangeExtension($primarySource, '.css')
        if (Test-Path -LiteralPath $sidecarCss) {
            $cssContent = [System.IO.File]::ReadAllText($sidecarCss, [System.Text.Encoding]::UTF8)
            if ($html -match '(?i)</head>') {
                $html = $html -replace '(?i)</head>', "<style id=`"otter-sidecar-style`">`n$cssContent`n</style>`n</head>"
            }
        }
    }
    catch [OtterError] {
        if ($PassThruExceptions) { throw }
        # Remap combined line number back to originating file & line if source map exists
        $err = $_.Exception
        if ($resolvedProgram -and $err.Line -gt 0) {
            $origin = $resolvedProgram.FindOrigin($err.Line)
            if ($origin) {
                $err.Line = $origin.LocalLine
                $relFile = [System.IO.Path]::GetFileName($origin.FilePath)
                Write-Host ''
                Write-Host "In $($relFile):" -ForegroundColor DarkGray
            }
        }
        Write-Host ''
        Write-Host $err.FormatDetailed() -ForegroundColor Red
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
        $OutputPath = [System.IO.Path]::ChangeExtension($primarySource, '.html')
    }

    Set-Content -LiteralPath $OutputPath -Value $html -Encoding UTF8
    Write-Verbose "Otter Web App compiled to: $OutputPath"
    return $OutputPath
}

Export-ModuleMember -Function ConvertTo-OtterWeb, Export-OtterWebApplication
