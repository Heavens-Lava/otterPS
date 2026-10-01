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

# Forms (docs/proposals/FORMS_AND_VALIDATION.md): the rules a field states
# (required, format, minlength, ...) ride on it as data attributes, which the
# web runtime checks when the field's form is sent.
$script:OtterFieldKinds = @('text box', 'text area', 'textarea', 'dropdown', 'drop down', 'select', 'checkbox', 'check box', 'toggle', 'switch')
$script:OtterFieldRuleKeys = @('required', 'format', 'minlength', 'maxlength', 'minimum', 'maximum', 'message', 'label')
function Get-OtterFieldAttributes {
    param([string]$Kind, $Props)
    if ($Kind -notin $script:OtterFieldKinds) { return '' }
    $attrs = ''
    foreach ($key in $script:OtterFieldRuleKeys) {
        if (-not $Props.Contains($key)) { continue }
        $value = $Props[$key]
        if ($key -eq 'required') {
            if (-not ($value -eq $true -or "$value" -eq 'true')) { continue }
            $value = 'true'
        }
        $attrs += " data-$key=`"$(Escape-OtterHtmlAttr -Text ([string]$value))`""
    }
    if ($attrs) { return " data-otter-field$attrs" }
    return ''
}

# A readable error colour for the page's text colour: light text means a dark
# page (a light red), dark text a light page (a deep red).
function Get-OtterErrorColor {
    param([string]$Foreground)
    $hex = "$Foreground".Trim().TrimStart('#')
    if ($hex.Length -eq 3) { $hex = ($hex.ToCharArray() | ForEach-Object { "$_$_" }) -join '' }
    if ($hex -notmatch '^[0-9a-fA-F]{6}$') { return '#dc2626' }
    $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
    $luminance = (0.2126 * $r + 0.7152 * $g + 0.0722 * $b) / 255
    if ($luminance -ge 0.6) { return '#fca5a5' }
    return '#b91c1c'
}

# The colours cards, inputs and borders get when a program does not give its
# own: a dark app's by default, a light set on a light page (background
# "#ffffff") - otherwise a card or text box made while the page runs was dark
# navy on a white page, with the page's dark text on it.
function Get-OtterSurfacePalette {
    param([string]$Background)
    $palette = @{ CardBg = '#1e293b'; Muted = '#94a3b8'; InputBg = '#0f172a'; Border = '#334155'; Shadow = '0 10px 25px -5px rgba(0, 0, 0, 0.3), 0 8px 10px -6px rgba(0, 0, 0, 0.3)' }
    $hex = "$Background".Trim().TrimStart('#')
    if ($hex.Length -eq 3) { $hex = ($hex.ToCharArray() | ForEach-Object { "$_$_" }) -join '' }
    if ($hex -notmatch '^[0-9a-fA-F]{6}$') { return $palette }
    $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
    $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
    $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
    if ((0.2126 * $r + 0.7152 * $g + 0.0722 * $b) / 255 -lt 0.6) { return $palette }
    return @{ CardBg = '#ffffff'; Muted = '#64748b'; InputBg = '#ffffff'; Border = '#cbd5e1'; Shadow = '0 1px 2px rgba(15, 23, 42, 0.06), 0 4px 12px -2px rgba(15, 23, 42, 0.08)' }
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

# `runnable true` on a text resource turns its value into a live code sample:
# the text is parsed and compiled by the Otter web compiler when the page is
# built, and a Run button executes it in the browser, with `say` output shown
# under the sample. A sample the web target cannot run (files, sockets, other
# operating-system features, or `ask`) simply gets no Run button - never a
# button that would fail. Returns the JS function source, or $null.
function Get-OtterRunnableJs {
    param([Parameter(Mandatory)][string]$Source)
    if ($Source -match '(?m)^\s*ask\s' -or $Source -match '\barguments\b') { return $null }   # ask and the console arguments list need a console
    try {
        $sampleAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $Source)
        $sampleStatements = @($sampleAst.Statements)
        if ($sampleStatements.Count -eq 0) { return $null }
        $sampleGlobals = (Get-OtterJsTopLevelGlobalNames -TopLevelStatements $sampleStatements).Names
        $sampleJs = foreach ($sampleStatement in $sampleStatements) {
            ConvertTo-OtterJsStatement -Stmt $sampleStatement -Indent 2 -KnownGlobals $sampleGlobals
        }
        $sampleCode = $sampleJs -join "`n"
        # Samples that need the operating system (through the desktop bridge) or
        # the network cannot run honestly in a browser: no Run button for them.
        if ($sampleCode -match '\botter[A-Za-z]*(File|Folder|Directory|Command|Registry|Clipboard|Environment)[A-Za-z]*\s*\(|__OTTER_DESKTOP_BRIDGE__|\bfetch\(') { return $null }
        # Each run starts from a clean slate: the variables a sample creates are
        # tracked so the page can remove them again (the compiled code keeps
        # program variables on window).
        $sampleVars = @([regex]::Matches($sampleCode, 'window\.([A-Za-z_]\w*)\s*=') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
        $varsJson = ConvertTo-Json -InputObject $sampleVars -Compress
        if ($sampleVars.Count -eq 0) { $varsJson = '[]' }
        return "{ vars: $varsJson, run: async (otterSay) => {`n$sampleCode`n} }"
    } catch {
        return $null
    }
}

# The browser half of runtime UI. Property handling mirrors
# Render-OtterElementCore (the static renderer) property for property, so a
# property set at runtime looks the same as the same property written at the
# top level. Errors match the interpreter's wording.
function Get-OtterWebRuntimeUiJs {
    return @'
    let otterUiCounter = 0;
    function otterIsUi(v) { return !!(v && typeof v === 'object' && v.__otterUi); }
    function otterUiKindOf(v) { return otterIsUi(v) ? v.kind : ''; }
    function otterUiTypeName(v) { return (v && typeof v === 'object' && v.__otterThing) ? 'a thing' : (v === null || v === undefined) ? 'gone' : (typeof v === 'number') ? 'a number' : (typeof v === 'string') ? 'some text' : 'something else'; }
    function otterCreateUi(kind, variant, name) {
      const html = otterUiTemplates[kind];
      if (html === undefined) { throw new Error('I do not know how to create a ' + kind + ' on the web target.'); }
      const t = document.createElement('template');
      t.innerHTML = html;
      const root = t.content.firstElementChild;
      const el = root.id === '__otter_rt__' ? root : root.querySelector('#__otter_rt__');
      const id = 'otter-ui-' + (++otterUiCounter);
      el.id = id;
      if (variant) { el.classList.add('otter-button-' + variant); }
      // create card into entry: every such card has the class "entry", so
      // the page's stylesheet can style them all (.entry { ... }).
      if (name) { el.classList.add(name); }
      return { __otterUi: true, kind: kind, root: root, el: el || root, id: id };
    }
    // The outermost element of a resource: what gets moved by `put`, hidden
    // by `hide` and styled (a checkbox's label, not its input).
    function otterUiRoot(ref) {
      if (otterIsUi(ref)) { return ref.root; }
      const el = document.getElementById(ref);
      if (!el) { return null; }
      const wrap = el.closest ? el.closest('label.otter-checkbox-label, label.otter-toggle-label, label.otter-radio-label, .otter-runnable') : null;
      return wrap || el;
    }
    // Where children go: windows and pages hold them in their content area.
    function otterUiContent(root) {
      if (!root || !root.classList) { return root; }
      if (root.classList.contains('otter-window')) { return root.querySelector(':scope > .otter-window-content') || root; }
      if (root.classList.contains('otter-page')) { return root.querySelector(':scope > .otter-page-content') || root; }
      return root;
    }
    function otterUiKind(ref, root) {
      if (otterIsUi(ref)) { return ref.kind; }
      const c = root && root.classList ? root.classList : null;
      if (!c) { return ''; }
      if (c.contains('otter-row')) { return 'row'; }
      if (c.contains('otter-column')) { return 'column'; }
      if (c.contains('otter-card')) { return 'card'; }
      if (c.contains('otter-window')) { return 'window'; }
      if (c.contains('otter-page')) { return 'page'; }
      return '';
    }
    function otterUiPx(v) { return (typeof v === 'number') ? (v + 'px') : String(v); }
    function otterUiTrue(v) { return v === true || v === 'true'; }
    function otterPutIn(item, container) {
      const itemRoot = (otterIsUi(item) || typeof item === 'string') ? otterUiRoot(item) : null;
      if (!itemRoot) { throw new Error('I can only put a UI resource somewhere, but this is ' + otterUiTypeName(item) + '.'); }
      const holder = (otterIsUi(container) || typeof container === 'string') ? otterUiRoot(container) : null;
      if (!holder) { throw new Error('I can only put something in a UI resource, but this is ' + otterUiTypeName(container) + '.'); }
      otterUiContent(holder).appendChild(itemRoot);
    }
    function otterUiAction(ref, action) {
      const root = (otterIsUi(ref) || typeof ref === 'string') ? otterUiRoot(ref) : null;
      if (!root) {
        if (action === 'show') { throw new Error('I can only show a UI resource, but this is ' + otterUiTypeName(ref) + '.'); }
        throw new Error('I can only ' + action + ' a UI resource, but this is ' + otterUiTypeName(ref) + '.');
      }
      if (action === 'hide') { root.style.display = 'none'; return; }
      if (action === 'focus') { const el = otterGetElement(ref); if (el && el.focus) { el.focus(); } return; }
      root.hidden = false;
      if (root.style.display === 'none') { root.style.display = ''; }
      if (root.tagName === 'DIALOG' && !root.open && root.showModal) { root.showModal(); }
    }
    function otterOnUi(ref, eventName, handler) {
      const el = (otterIsUi(ref) || typeof ref === 'string') ? otterGetElement(ref) : null;
      if (!el) { throw new Error('I can only listen for an event on a UI resource or command job, but this is ' + otterUiTypeName(ref) + '.'); }
      el.addEventListener(eventName, handler);
    }
    function otterUiLayout(root, kind, prop, value) {
      const s = root.style;
      const isRow = kind === 'row';
      if (prop === 'spacing') { s.gap = otterUiPx(value); return true; }
      if (prop === 'wrap') { s.flexWrap = (otterUiTrue(value) || value === 'wrap') ? 'wrap' : 'nowrap'; return true; }
      if (prop === 'spread') { if (otterUiTrue(value)) { s.justifyContent = 'space-between'; } return true; }
      if (prop === 'justify') { s.justifyContent = value; return true; }
      if (prop === 'alignitems' || prop === 'items') { s.alignItems = value; return true; }
      if (prop === 'align') {
        const map = { left: 'flex-start', center: 'center', right: 'flex-end', top: 'flex-start', middle: 'center', bottom: 'flex-end' };
        const horizontal = value === 'left' || value === 'center' || value === 'right';
        if (map[value] === undefined) { s.textAlign = value; return true; }
        if (horizontal === isRow) { s.justifyContent = map[value]; } else { s.alignItems = map[value]; }
        return true;
      }
      return false;
    }
    function otterSetUiProp(ref, prop, value) {
      const el = otterGetElement(ref);
      if (!el) { return; }
      const root = otterUiRoot(ref) || el;
      const kind = otterUiKind(ref, root);
      const p = String(prop).toLowerCase();
      const s = root.style;
      if ((kind === 'row' || kind === 'column') && otterUiLayout(root, kind, p, value)) { return; }
      if (p === 'spacing' && (kind === 'window' || kind === 'page' || kind === 'card')) { s.gap = otterUiPx(value); otterUiContent(root).style.gap = otterUiPx(value); return; }
      switch (p) {
        case 'text':
        case 'value':
          if (el.type === 'checkbox' || el.type === 'radio') {
            if (p === 'value') { el.checked = otterUiTrue(value); return; }
            const span = root.querySelector('span:last-of-type'); if (span) { span.textContent = value; } return;
          }
          if (el.tagName === 'PROGRESS' || el.type === 'range') { el.value = value; return; }
          // On the element itself, like otterSetText: a runtime element is
          // often not in the page yet when its properties are set.
          if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT') { el.value = value; } else { el.textContent = value; }
          return;
        case 'placeholder': el.placeholder = value; return;
        case 'title':
          if (kind === 'card') {
            let h = root.querySelector(':scope > .otter-card-title');
            if (!h) { h = document.createElement('h3'); h.className = 'otter-card-title'; root.insertBefore(h, root.firstChild); }
            h.textContent = value; return;
          }
          if (kind === 'window' || kind === 'page') { const t = root.querySelector('.otter-title'); if (t) { t.textContent = value; } return; }
          el.title = value; return;
        case 'width': s.width = value === 'full' ? '100%' : otterUiPx(value); if (value === 'full') { s.maxWidth = '100%'; } return;
        case 'height': s.height = value === 'full' ? '100%' : otterUiPx(value); return;
        case 'maxwidth': s.maxWidth = otterUiPx(value); return;
        case 'minwidth': s.minWidth = otterUiPx(value); return;
        case 'minheight': s.minHeight = otterUiPx(value); return;
        case 'background': s.background = value; return;
        case 'foreground': s.color = value; return;
        case 'round': if (otterUiTrue(value)) { s.borderRadius = '9999px'; } return;
        case 'radius': s.borderRadius = value === 'round' ? '9999px' : otterUiPx(value); return;
        case 'border': s.border = value; return;
        case 'shadow': s.boxShadow = value; return;
        case 'padding': s.padding = otterUiPx(value); return;
        case 'margin': s.margin = otterUiPx(value); return;
        case 'size':
        case 'fontsize': s.fontSize = otterUiPx(value); return;
        case 'weight':
        case 'fontweight': s.fontWeight = value; return;
        case 'fontstyle': s.fontStyle = value; return;
        case 'style': if (value === 'italic' || value === 'normal') { s.fontStyle = value; } return;
        case 'family':
        case 'fontfamily': s.fontFamily = value; return;
        case 'lineheight': s.lineHeight = value; return;
        case 'letterspacing': s.letterSpacing = value; return;
        case 'whitespace': s.whiteSpace = value; return;
        case 'overflow': s.overflow = value; return;
        case 'align': s.textAlign = value; return;
        case 'flex': s.flex = value; s.minWidth = '0'; return;
        case 'grow': s.flexGrow = value; return;
        case 'cursor': s.cursor = value; return;
        case 'position': s.position = value; return;
        case 'top': s.top = otterUiPx(value); return;
        case 'bottom': s.bottom = otterUiPx(value); return;
        case 'left': s.left = otterUiPx(value); return;
        case 'right': s.right = otterUiPx(value); return;
        case 'zindex': s.zIndex = value; return;
        case 'customstyle': s.cssText += ';' + value; return;
        case 'source':
        case 'src': el.src = value; return;
        case 'alt': el.alt = value; return;
        case 'url':
        case 'href':
          el.href = value;
          if (/^https?:\/\//i.test(String(value))) { el.target = '_blank'; el.rel = 'noopener noreferrer'; }
          return;
        case 'checked': el.checked = otterUiTrue(value); return;
        case 'min': el.min = value; return;
        case 'max': el.max = value; return;
        case 'rows': el.rows = value; return;
        case 'group':
        case 'name': if (el.type === 'radio') { el.name = value; return; } break;
        case 'options': {
          const opts = Array.isArray(value) ? value : String(value).split(',').map(x => x.trim());
          el.innerHTML = '';
          for (const o of opts) { const opt = document.createElement('option'); opt.value = String(o); opt.textContent = String(o); el.appendChild(opt); }
          return;
        }
        case 'draggable': if (otterUiTrue(value)) { el.setAttribute('draggable', 'true'); } else { el.removeAttribute('draggable'); } return;
        case 'accepts drops': if (otterUiTrue(value)) { el.setAttribute('data-otter-accepts-drops', 'true'); } else { el.removeAttribute('data-otter-accepts-drops'); } return;
      }
      // Anything else: as otterSetProperty, on the element itself.
      if (p === 'url' && el.tagName === 'A') { el.href = value; return; }
      el[p] = value;
      if (el.dataset) { el.dataset[p] = value; }
    }
'@
}

# Runtime UI (web target). Walks the whole program and reports which UI
# resources are created while the page runs rather than rendered up front:
# every `create KIND into NAME` that is not itself a top-level statement
# (inside an event handler, a function, a loop or an if). Also reports the
# kinds they use (one HTML template is generated per kind) and whether the
# program uses any runtime UI statement at all, so pages that do not keep
# their exact previous output.
function Get-OtterWebRuntimeUiInfo {
    param([Node[]]$Statements)
    $names = [System.Collections.Generic.HashSet[string]]::new()
    $kinds = [System.Collections.Generic.HashSet[string]]::new()
    $state = @{ Uses = $false }
    # ObjectDef: a nested `X has ...` may set a UI resource's properties.
    $runtimeKinds = @([NodeKind]::CreateUiResource, [NodeKind]::PutIn, [NodeKind]::Show, [NodeKind]::UiAction, [NodeKind]::When, [NodeKind]::ObjectDef)

    function Visit-OtterWebRuntimeUi {
        param([object]$Value, [bool]$Nested)
        if ($null -eq $Value -or $Value -is [string] -or $Value -is [enum] -or $Value -is [System.ValueType]) { return }
        if ($Value -is [System.Collections.IEnumerable]) {
            foreach ($item in $Value) { Visit-OtterWebRuntimeUi -Value $item -Nested $Nested }
            return
        }
        if (-not $Value.GetType().Assembly.IsDynamic) { return }
        if ($Value -is [Node]) {
            if ($Nested -and $Value.Kind -in $runtimeKinds) { $state.Uses = $true }
            if (-not $Nested -and $Value.Kind -eq [NodeKind]::UiAction) { $state.Uses = $true }
            if ($Nested -and $Value -is [CreateUiResourceStmt]) {
                [void]$names.Add($Value.Target)
                $kind = $Value.TypeName.ToLowerInvariant()
                foreach ($v in @('primary', 'secondary', 'danger')) {
                    if ($kind.StartsWith("$v ")) { $kind = $kind.Substring($v.Length + 1); break }
                }
                [void]$kinds.Add($kind)
            }
        }
        foreach ($prop in $Value.PSObject.Properties) {
            if ($prop.Name -in @('Kind', 'Line')) { continue }
            Visit-OtterWebRuntimeUi -Value $prop.Value -Nested $true
        }
    }

    foreach ($stmt in @($Statements)) { Visit-OtterWebRuntimeUi -Value $stmt -Nested $false }
    if ($names.Count -gt 0) { $state.Uses = $true }
    return [pscustomobject]@{ Names = $names; Kinds = $kinds; Uses = $state.Uses }
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
    $runnableSamples = [System.Collections.Generic.List[hashtable]]::new()
    $topLevelStatements = [System.Collections.Generic.List[Node]]::new()
    $declarativeRoots = [System.Collections.Generic.List[UiElementStmt]]::new()
    $stateDefs = [ordered]@{}
    $deriveDefs = [ordered]@{}
    $watchStmts = [System.Collections.Generic.List[WatchStmt]]::new()
    $functions = [ordered]@{}

    $runtimeUi = Get-OtterWebRuntimeUiInfo -Statements $Program.Statements
    Set-OtterJsRuntimeUiNames -Names @($runtimeUi.Names)

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
                'dialog', 'modal', 'panel', 'form'
            )
            # `aboutButton is a primary button` - a variant-qualified kind
            # (matches the `primary button`/`secondary card`/`danger
            # panel`-style prefix the inline UI-element grammar already
            # supports). Found as a real bug during D103 testing: unless
            # the "primary " prefix is stripped here, "primary button"
            # never matches $knownKinds, so it falls all the way through
            # to ObjectDef's generic "thing" codegen - which then
            # interpolates the two-word type name as a BARE JS
            # IDENTIFIER (`typeof primary button !== 'undefined'`),
            # producing a hard SyntaxError that breaks the entire
            # compiled script, confirmed by actually compiling and
            # running one in a browser.
            $variant = $null
            foreach ($v in @('primary', 'secondary', 'danger')) {
                if ($kind.StartsWith("$v ")) {
                    $variant = $v
                    $kind = $kind.Substring($v.Length + 1)
                    break
                }
            }
            if ($kind -in $knownKinds) {
                $res = @{
                    Kind = $kind
                    Name = $stmt.Name
                    Properties = [ordered]@{}
                }
                if ($variant) { $res.Properties['variant'] = $variant }
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
        if ($stmt -is [PutInStmt] -and (
                ($stmt.Item -is [VariableExpr] -and $runtimeUi.Names.Contains($stmt.Item.Name)) -or
                ($stmt.Container -is [VariableExpr] -and $runtimeUi.Names.Contains($stmt.Container.Name)))) {
            # Involves a resource created while the page runs: it cannot be
            # placed in the static HTML, so it runs where it is written.
            $topLevelStatements.Add($stmt)
            continue
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
        if ($stmt -is [WhenStmt] -and $stmt.Target -is [VariableExpr] -and $runtimeUi.Names.Contains($stmt.Target.Name) -and
            $stmt.EventName -notin @('drag', 'drop', 'files dropped')) {
            $topLevelStatements.Add($stmt)
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

    # Page UI addressed by DOM id: the top-level resources, plus named elements
    # of the declarative form (`page "..."` / `button "Go" as goButton`), whose
    # id is their name.
    $staticUiNames = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $resources.Keys) { $staticUiNames.Add([string]$k) }
    $declStack = [System.Collections.Generic.Stack[object]]::new()
    foreach ($d in $declarativeRoots) { $declStack.Push($d) }
    while ($declStack.Count -gt 0) {
        $d = $declStack.Pop()
        if ($d.Name) { $staticUiNames.Add([string]$d.Name) }
        foreach ($c in @($d.Children)) { if ($c -is [UiElementStmt]) { $declStack.Push($c) } }
    }
    Set-OtterJsRuntimeUiNames -Names @($runtimeUi.Names) -StaticNames @($staticUiNames)

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
    # A page's description and icon: what a search result, a shared link and
    # the browser tab show (`app is a page with description "...", icon "..."`).
    $pageMeta = New-Object System.Collections.Generic.List[string]
    if ($isPage) {
        $rootProps = $resources[$rootName].Properties
        if ($rootProps.Contains('description') -and "$($rootProps['description'])".Trim()) {
            $description = Escape-OtterHtmlAttr -Text ([string]$rootProps['description'])
            $pageMeta.Add("  <meta name=`"description`" content=`"$description`">")
            $pageMeta.Add("  <meta property=`"og:description`" content=`"$description`">")
        }
        if ($rootProps.Contains('icon') -and "$($rootProps['icon'])".Trim()) {
            $pageMeta.Add("  <link rel=`"icon`" href=`"$(Escape-OtterHtmlAttr -Text ([string]$rootProps['icon']))`">")
        }
    }
    # `scroll true` on the page: it scrolls like an ordinary document (a
    # website) instead of filling the window like an app shell.
    $pageScrolls = ($isPage -and $resources[$rootName].Properties.Contains('scroll') -and
        ($resources[$rootName].Properties['scroll'] -eq $true -or "$($resources[$rootName].Properties['scroll'])" -eq 'true'))
    $bodyClass = if ($pageScrolls) { ' class="otter-has-page otter-doc-scroll"' } elseif ($isPage) { ' class="otter-has-page"' } else { '' }

    # HTML rendering helper
    function Render-OtterElementCore([string]$resName, [bool]$Hidden = $false) {
        if (-not $resources.Contains($resName)) { return "" }
        $r = $resources[$resName]
        $kind = $r.Kind
        $props = $r.Properties

        $styles = [System.Collections.Generic.List[string]]::new()
        # D103: a route-managed page not matching the initially-loaded URL
        # starts hidden, so nothing flashes before the router's own
        # showForCurrentPath() (which runs right after these top-level
        # statements execute) picks the one that actually matches.
        if ($Hidden) { $styles.Add('display: none;') }
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
                # .otter-window caps a window at 520px wide. A window that states
                # its own width (width 900) gets that width - still no wider than
                # the screen - unless it also sets a maximum itself.
                if ($props.Contains('width') -and -not $props.Contains('maxwidth')) { $styles.Add("max-width: 100%;") }
                $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
                return @"
    <div id="$resName" class="otter-window"$styleAttr>
      <header class="otter-window-header"><h1 class="otter-title">$(Escape-OtterHtmlAttr -Text $appTitle)</h1></header>
      <div class="otter-window-content" style="display: flex; flex-direction: column; gap: ${spacing}px; min-width: 0;">$childHtml</div>
    </div>
"@
            }
            'page' {
                $spacing = if ($props.Contains('spacing')) { $props['spacing'] } else { 12 }
                if (-not $props.Contains('gap')) { $styles.Add("gap: ${spacing}px;") }
                $styleAttr = if ($styles.Count -gt 0) { " style=`"$($styles -join ' ')`"" } else { "" }
                $showHeader = (-not ($props.Contains('hideheader') -and $props['hideheader']))
                $headerHtml = if ($showHeader -and $appTitle) { "<header class=`"otter-page-header`"><h1 class=`"otter-title`">$(Escape-OtterHtmlAttr -Text $appTitle)</h1></header>" } else { "" }
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
                # `primary button`/`secondary button`/`danger button` -
                # reuses the same otter-button-<variant> CSS classes the
                # inline UI-element grammar's own renderer already defines.
                $variantClass = if ($props.Contains('variant')) { " otter-button-$($props['variant'])" } else { "" }
                return "      <button id=`"$resName`" class=`"otter-button$variantClass`"$styleAttr>$text</button>"
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
                if ($props.Contains('runnable') -and ($props['runnable'] -eq $true -or "$($props['runnable'])" -eq 'true')) {
                    $sampleJs = Get-OtterRunnableJs -Source $rawVal
                    if ($null -ne $sampleJs) {
                        $runnableSamples.Add(@{ Id = $resName; Js = $sampleJs })
                        return @"
      <div class="otter-runnable">
        <div id="$resName" class="otter-text"$styleAttr>$val</div>
        <div class="otter-run-bar"><button type="button" class="otter-run-btn" data-otter-run="$resName">&#9654; Run</button></div>
        <pre id="$resName-output" class="otter-run-output" hidden></pre>
      </div>
"@
                    }
                }
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
                # The control is the labelled checkbox: its id is on the label, so a
                # stylesheet rule for it (a position, a size) moves the box and its
                # text together. The input inside is <name>-box; the runtime reads
                # and sets its checked state through otterValueElement.
                return "      <label id=`"$resName`" class=`"otter-checkbox-label`"$styleAttr><input type=`"checkbox`" id=`"$resName-box`" class=`"otter-checkbox`"$checked /> <span>$text</span></label>"
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
                # The animation's starting speed and colours; a program changes
                # them while it runs with `speed of cube is ...` and so on.
                $animAttrs = ''
                foreach ($animProp in @('speed', 'color', 'glow')) {
                    if ($props.Contains($animProp)) { $animAttrs += " data-$animProp=`"$(Escape-OtterHtmlAttr -Text ([string]$props[$animProp]))`"" }
                }
                return "      <canvas id=`"$resName`" class=`"otter-canvas`" width=`"$w`" height=`"$h`" data-animation=`"$anim`" data-mode=`"$mode`"$animAttrs$styleAttr></canvas>"
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
                # As a checkbox: the id is on the label (the control as seen), so a
                # position or size moves the switch and its text together.
                return "      <label id=`"$resName`" class=`"otter-toggle-label`"$styleAttr><input type=`"checkbox`" id=`"$resName-box`" class=`"otter-toggle`" role=`"switch`"$checked /><span class=`"otter-toggle-track`"><span class=`"otter-toggle-thumb`"></span></span><span class=`"otter-toggle-text`">$text</span></label>"
            }
            { $_ -in @('radio', 'radio button') } {
                $rawText = if ($props.Contains('text')) { [string]$props['text'] } else { "" }
                $text = Escape-OtterHtmlAttr -Text $rawText
                $rawGroup = if ($props.Contains('group')) { [string]$props['group'] } elseif ($props.Contains('name')) { [string]$props['name'] } else { "default-group" }
                $group = Escape-OtterHtmlAttr -Text $rawGroup
                $checked = if ($props.Contains('checked') -and ($props['checked'] -eq $true -or $props['checked'] -eq 'true')) { " checked" } else { "" }
                return "      <label id=`"$resName`" class=`"otter-radio-label`"$styleAttr><input type=`"radio`" id=`"$resName-box`" name=`"$group`" class=`"otter-radio`"$checked /> <span>$text</span></label>"
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
            { $_ -in @('column', 'form') } {
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
                # A form is a column that checks its fields when it is sent.
                if ($kind -eq 'form') {
                    return @"
      <form id="$resName" class="otter-column otter-form" novalidate$styleAttr>$childHtml</form>
"@
                }
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

    # D110: `draggable is true` and `accepts drops is true` become real DOM
    # attributes on whatever element the resource rendered as - one place,
    # so every resource kind gets them without each renderer knowing.
    function Render-OtterElement([string]$resName, [bool]$Hidden = $false) {
        $html = Render-OtterElementCore -resName $resName -Hidden $Hidden
        if (-not $resources.Contains($resName)) { return $html }
        $dragProps = $resources[$resName].Properties
        $dragAttrs = ''
        if ($dragProps.Contains('draggable') -and ($dragProps['draggable'] -eq $true -or "$($dragProps['draggable'])" -eq 'true')) {
            $dragAttrs += ' draggable="true"'
        }
        if ($dragProps.Contains('accepts drops') -and ($dragProps['accepts drops'] -eq $true -or "$($dragProps['accepts drops'])" -eq 'true')) {
            $dragAttrs += ' data-otter-accepts-drops="true"'
        }
        $fieldKind = $resources[$resName].Kind
        $dragAttrs += Get-OtterFieldAttributes -Kind $fieldKind -Props $dragProps
        if ($dragAttrs) {
            $idMarker = "id=`"$resName`""
            $at = $html.IndexOf($idMarker)
            if ($at -ge 0) { $html = $html.Insert($at + $idMarker.Length, $dragAttrs) }
        }
        # A field's label: shown above it (and its accessible name), with the
        # place for its message under it.
        if ($dragProps.Contains('label') -and "$($dragProps['label'])".Trim() -and $fieldKind -in @('text box', 'text area', 'textarea', 'dropdown', 'drop down', 'select')) {
            $labelText = Escape-OtterHtmlAttr -Text ([string]$dragProps['label'])
            $html = "      <div class=`"otter-field`" data-otter-field-for=`"$resName`">`n        <label class=`"otter-field-label`" for=`"$resName`">$labelText</label>`n$html`n        <div class=`"otter-field-error`" id=`"$resName-error`" role=`"alert`" hidden></div>`n      </div>"
        }
        return $html
    }

    # D103: every page a `route` statement names must reach the DOM, not
    # just the usual single "first resource" root - the router decides
    # at runtime which one is visible, so all of them have to exist to
    # be shown/hidden. Order-preserving, de-duplicated (the same page
    # can legitimately back more than one route pattern).
    $routePageNames = [System.Collections.Generic.List[string]]::new()
    $routePageSeen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($stmt in $Program.Statements) {
        if ($stmt -is [RouteStmt] -and $stmt.PageName -and $routePageSeen.Add($stmt.PageName)) {
            $routePageNames.Add($stmt.PageName)
        }
    }

    $elementsHtml = ""
    if ($routePageNames.Count -gt 0) {
        $parts = for ($ri = 0; $ri -lt $routePageNames.Count; $ri++) {
            Render-OtterElement -resName $routePageNames[$ri] -Hidden ($ri -gt 0)
        }
        $elementsHtml = $parts -join "`n"
    } elseif ($rootName) {
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

    # Runtime UI: one template per kind the program creates while running,
    # rendered by the same renderer as the static page (no properties), so a
    # runtime button is the same markup as a top-level one.
    $runtimeUiJs = ''
    if ($runtimeUi.Uses) {
        $templates = [ordered]@{}
        $templateName = '__otter_rt__'
        foreach ($kind in @($runtimeUi.Kinds)) {
            $resources[$templateName] = @{ Kind = $kind; Name = $templateName; Properties = [ordered]@{} }
            try { $templates[$kind] = (Render-OtterElementCore -resName $templateName).Trim() }
            finally { $resources.Remove($templateName) }
        }
        $templatesJson = if ($templates.Count -gt 0) { ConvertTo-Json -InputObject $templates -Compress } else { '{}' }
        $runtimeUiJs = "    const otterUiTemplates = $templatesJson;`n" + (Get-OtterWebRuntimeUiJs)
    }

    # Compile event handlers
    $jsHandlers = [System.Collections.Generic.List[string]]::new()
    foreach ($when in $whenHandlers) {
        $targetName = if ($when.Target -is [VariableExpr]) { $when.Target.Name } else { 'target' }
        # D110: drag/drop events. Block-scoped, so one element can carry
        # several of them (drag AND drop) without redeclaring a constant.
        if ($when.EventName -in @('drag', 'drop', 'files dropped')) {
            $dragBodyLines = [System.Collections.Generic.List[string]]::new()
            foreach ($s in $when.Body) { $dragBodyLines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent 5)) }
            $dragBody = $dragBodyLines -join "`n"
            $domEvent = switch ($when.EventName) { 'drag' { 'dragstart' } default { 'drop' } }
            $dragGuard = switch ($when.EventName) {
                'drag' { '' }
                'drop' { "        if (!otterIsItemDrop(event)) { return; }`n" }
                'files dropped' { "        if (!otterIsFileDrop(event)) { return; }`n" }
            }
            $jsHandlers.Add(@"
    {
      const _dragEl = document.getElementById('$targetName');
      if (_dragEl) {
        _dragEl.addEventListener('$domEvent', async (event) => {
$dragGuard        window.otterDragCtx = otterMakeDragCtx(event, _dragEl, '$($when.EventName)');
$dragBody
        });
      }
    }
"@)
            continue
        }
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

    # D110: the generic drag/drop plumbing (drop-target permission, the
    # dragged-item tracker, context objects) - emitted only for programs
    # that declare something draggable/droppable or handle those events.
    $usesDragDrop = $false
    foreach ($resValue in $resources.Values) {
        foreach ($dragKey in @('draggable', 'accepts drops')) {
            if ($resValue.Properties.Contains($dragKey) -and ($resValue.Properties[$dragKey] -eq $true -or "$($resValue.Properties[$dragKey])" -eq 'true')) { $usesDragDrop = $true }
        }
    }
    foreach ($w in $whenHandlers) { if ($w.EventName -in @('drag', 'drop', 'files dropped')) { $usesDragDrop = $true } }
    $runnableRuntimeJs = ''
    $runnableCss = ''
    if ($runnableSamples.Count -gt 0) {
        $runnableCss = @'
    .otter-runnable { display: flex; flex-direction: column; gap: 0; min-width: 0; }
    .otter-runnable > .otter-text { border-bottom-left-radius: 0; border-bottom-right-radius: 0; }
    .otter-run-bar { display: flex; justify-content: flex-end; padding: 8px 12px; background: #16263f; border-radius: 0 0 12px 12px; }
    .otter-run-btn { font: inherit; font-size: 13px; font-weight: 700; color: #ffffff; background: #2563eb; border: 0; border-radius: 8px; padding: 6px 16px; cursor: pointer; }
    .otter-run-btn:hover { background: #1d4ed8; }
    .otter-run-btn:disabled { opacity: 0.6; cursor: progress; }
    .otter-run-output { margin: 8px 0 0; padding: 14px 18px; background: #e8eef7; color: #0f1f36; border-radius: 12px; font-family: 'JetBrains Mono', Consolas, monospace; font-size: 14px; line-height: 1.7; white-space: pre-wrap; overflow-x: auto; }
    .otter-run-output.otter-run-error { background: #fdecec; color: #8a1c1c; }
'@
        $sampleRegistry = ($runnableSamples | ForEach-Object { "    window.otterRunnables[$(ConvertTo-Json -InputObject $_.Id -Compress)] = $($_.Js);" }) -join "`n"
        $orderIds = @($runnableSamples | ForEach-Object { $_.Id })
        $orderJson = '[' + (($orderIds | ForEach-Object { ConvertTo-Json -InputObject $_ -Compress }) -join ',') + ']'
        $runnableRuntimeJs = (@'
    window.otterRunnables = {};
    window.otterRunOrder = @@ORDER@@;
    function otterFormatSaid(value) {
      if (value === null || value === undefined) { return 'gone'; }
      if (Array.isArray(value)) { return value.map(otterFormatSaid).join(', '); }
      if (typeof value === 'object' && value.__otterThing) { return 'a ' + (value.typeName || 'thing'); }
      return String(value);
    }
    document.addEventListener('click', async (e) => {
      const button = e.target && e.target.closest ? e.target.closest('[data-otter-run]') : null;
      if (!button || button.disabled) { return; }
      const id = button.getAttribute('data-otter-run');
      const output = document.getElementById(id + '-output');
      if (!output || !window.otterRunnables[id]) { return; }
      // A page's samples read as one story ("games are ..." then "each game in games"),
      // so a sample runs after the samples above it - silently - and only its own
      // output is shown. Every run starts and ends with no variables left behind.
      const chain = window.otterRunOrder.slice(0, window.otterRunOrder.indexOf(id) + 1);
      const touched = new Set();
      for (const step of chain) { for (const v of window.otterRunnables[step].vars) { touched.add(v); } }
      const saved = Array.from(touched).map((v) => [v, Object.getOwnPropertyDescriptor(window, v)]);
      const clean = () => { for (const v of touched) { try { delete window[v]; } catch (err) { /* keep going */ } if (v === 'name') { window.name = ''; } } };
      const lines = [];
      output.hidden = false;
      output.classList.remove('otter-run-error');
      output.textContent = '';
      button.disabled = true;
      clean();
      try {
        for (const step of chain.slice(0, -1)) {
          try { await window.otterRunnables[step].run(() => {}); } catch (err) { /* an earlier sample that cannot run is skipped */ }
        }
        const say = (...parts) => { lines.push(parts.map(otterFormatSaid).join(' ')); output.textContent = lines.join('\n'); };
        await window.otterRunnables[id].run(say);
        if (lines.length === 0) { output.textContent = '(nothing to show - this sample only sets things up for the ones below)'; }
      } catch (err) {
        output.classList.add('otter-run-error');
        lines.push('Otter stopped: ' + (err && err.message ? err.message : String(err)));
        output.textContent = lines.join('\n');
      } finally {
        clean();
        for (const [v, descriptor] of saved) { if (descriptor) { try { Object.defineProperty(window, v, descriptor); } catch (err) { /* keep going */ } } }
        button.disabled = false;
      }
    });
'@).Replace('@@ORDER@@', $orderJson) + "`n" + $sampleRegistry
    }
    $usesForms = $false
    foreach ($resValue in $resources.Values) {
        if ($resValue.Kind -eq 'form') { $usesForms = $true }
        if ($resValue.Kind -in $script:OtterFieldKinds) {
            foreach ($ruleKey in $script:OtterFieldRuleKeys) { if ($resValue.Properties.Contains($ruleKey)) { $usesForms = $true } }
        }
    }
    $formRuntimeJs = ''
    $formCss = ''
    if ($usesForms) {
        $formCss = (@'
    .otter-field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
    .otter-field-label { font-size: 0.9em; font-weight: 600; }
    .otter-field-error { color: @@ERROR@@; font-size: 0.85em; line-height: 1.4; margin-top: 4px; }
    .otter-field > .otter-field-error { margin-top: 0; }
    input.otter-invalid, textarea.otter-invalid, select.otter-invalid { border-color: @@ERROR@@ !important; box-shadow: 0 0 0 1px @@ERROR@@; }
    input.otter-invalid:focus, textarea.otter-invalid:focus, select.otter-invalid:focus { box-shadow: 0 0 0 3px color-mix(in srgb, @@ERROR@@ 35%, transparent); }
    .otter-invalid input[type="checkbox"] { outline: 2px solid @@ERROR@@; outline-offset: 1px; }
'@).Replace('@@ERROR@@', (Get-OtterErrorColor -Foreground $rootFg))
        $formRuntimeJs = @'
    // Forms (docs/proposals/FORMS_AND_VALIDATION.md): sending a form - a
    // button in it, or Enter in one of its text boxes - checks the rules its
    // fields state, shows each message under its field, and fires "sent"
    // (when <form> is sent) only when every field passes.
    function otterFieldsOf(form) { return Array.prototype.slice.call(form.querySelectorAll('[data-otter-field]')); }
    function otterFieldInput(el) { return otterValueElement(el.id) || el; }
    function otterCheckField(el) {
      const d = el.dataset;
      if (d.otterError) return d.otterError;
      const input = otterFieldInput(el);
      const name = d.label || input.placeholder || 'this field';
      const title = name.charAt(0).toUpperCase() + name.slice(1);
      const say = function (text) { return d.message || text; };
      if (input.type === 'checkbox' || input.type === 'radio') {
        return (d.required === 'true' && !input.checked) ? say('Please tick ' + name + '.') : '';
      }
      const value = String(input.value == null ? '' : input.value).trim();
      if (value === '') return d.required === 'true' ? say('Please fill in ' + name + '.') : '';
      const format = String(d.format || '').toLowerCase();
      if (format === 'email' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return say(title + ' needs to be an email address, like name@example.com.');
      if (format === 'phone' && !(/^\+?[0-9 ()\-]+$/.test(value) && value.replace(/\D/g, '').length >= 6)) return say(title + ' needs to be a phone number.');
      if (format === 'url' && !/^(https?:\/\/)?[^\s\/]+\.[^\s]+$/i.test(value)) return say(title + ' needs to be a web address, like https://example.com.');
      if (format === 'number') {
        const n = Number(value);
        if (!isFinite(n)) return say(title + ' needs to be a number.');
        if (d.minimum !== undefined && n < Number(d.minimum)) return say(title + ' needs to be at least ' + d.minimum + '.');
        if (d.maximum !== undefined && n > Number(d.maximum)) return say(title + ' needs to be at most ' + d.maximum + '.');
      }
      if (d.minlength !== undefined && value.length < Number(d.minlength)) return say(title + ' needs at least ' + d.minlength + ' characters.');
      if (d.maxlength !== undefined && value.length > Number(d.maxlength)) return say(title + ' can have at most ' + d.maxlength + ' characters.');
      return '';
    }
    // A field placed at x / y (Free layout): its label sits just above it and
    // its message just under it.
    function otterIsPlaced(el) { const p = getComputedStyle(el).position; return p === 'absolute' || p === 'fixed'; }
    function otterPlaceNear(el, part, above) {
      part.style.position = getComputedStyle(el).position;
      part.style.left = el.offsetLeft + 'px';
      part.style.width = el.offsetWidth + 'px';
      part.style.top = (above ? el.offsetTop - part.offsetHeight - 4 : el.offsetTop + el.offsetHeight + 4) + 'px';
    }
    function otterShowFieldError(el, message) {
      let box = document.getElementById(el.id + '-error');
      if (!box && message) {
        box = document.createElement('div');
        box.id = el.id + '-error';
        box.className = 'otter-field-error';
        box.setAttribute('role', 'alert');
        el.insertAdjacentElement('afterend', box);
      }
      if (box) {
        box.textContent = message;
        box.hidden = !message;
        if (message && otterIsPlaced(el)) otterPlaceNear(el, box, false);
      }
      el.classList.toggle('otter-invalid', Boolean(message));
      const input = otterFieldInput(el);
      if (message) {
        input.setAttribute('aria-invalid', 'true');
        if (box) input.setAttribute('aria-describedby', box.id);
      } else {
        input.removeAttribute('aria-invalid');
      }
    }
    function otterSendForm(form) {
      let first = null;
      otterFieldsOf(form).forEach(function (el) {
        const message = otterCheckField(el);
        otterShowFieldError(el, message);
        if (message && !first) first = el;
      });
      if (first) {
        const input = otterFieldInput(first);
        if (input.focus) input.focus();
        return false;
      }
      form.dispatchEvent(new CustomEvent('sent'));
      return true;
    }
    document.addEventListener('submit', function (event) {
      const form = event.target;
      if (!form.classList || !form.classList.contains('otter-form')) return;
      event.preventDefault();
      // Secondary and danger buttons do their own thing; they never send.
      const by = event.submitter;
      if (by && by.classList && (by.classList.contains('otter-button-secondary') || by.classList.contains('otter-button-danger'))) return;
      otterSendForm(form);
    });
    document.addEventListener('keydown', function (event) {
      if (event.key !== 'Enter' || event.shiftKey || event.isComposing) return;
      const t = event.target;
      if (!t || t.tagName !== 'INPUT' || ['checkbox', 'radio', 'button', 'submit', 'range'].indexOf(t.type) >= 0) return;
      const form = t.closest ? t.closest('form.otter-form') : null;
      if (!form) return;
      event.preventDefault();
      otterSendForm(form);
    });
    // Once a field shows a message, the message follows what is typed.
    function otterRecheckField(event) {
      const t = event.target;
      const el = t && t.closest ? t.closest('[data-otter-field]') : null;
      if (!el) return;
      if (el.dataset.otterError) delete el.dataset.otterError;
      const box = document.getElementById(el.id + '-error');
      if (box && !box.hidden) otterShowFieldError(el, otterCheckField(el));
    }
    document.addEventListener('input', otterRecheckField);
    document.addEventListener('change', otterRecheckField);
    // valid of <form or field>, error of <field>
    function otterFormProperty(id, prop) {
      const el = otterGetElement(id);
      if (prop === 'error') {
        if (!el) return '';
        if (el.dataset.otterError) return el.dataset.otterError;
        const box = document.getElementById(id + '-error');
        return box && !box.hidden ? box.textContent : '';
      }
      if (!el) return true;
      const fields = el.classList.contains('otter-form') ? otterFieldsOf(el) : (el.hasAttribute('data-otter-field') ? [el] : []);
      return fields.every(function (f) { return otterCheckField(f) === ''; });
    }
    // error of <field> is "..." - a message of the program's own (an answer
    // from a server); "" clears it. Typing in the field clears it too.
    function otterSetFieldError(id, message) {
      const el = otterGetElement(id);
      if (!el) return;
      const text = message == null ? '' : String(message);
      el.setAttribute('data-otter-field', '');
      if (text) el.dataset.otterError = text; else delete el.dataset.otterError;
      otterShowFieldError(el, text);
    }
    document.querySelectorAll('.otter-field[data-otter-field-for]').forEach(function (wrap) {
      const el = document.getElementById(wrap.dataset.otterFieldFor);
      const label = wrap.querySelector('.otter-field-label');
      if (!el || !otterIsPlaced(el)) return;
      // The wrapper takes no room in the flow; its parts sit around the box.
      wrap.style.display = 'contents';
      if (label) otterPlaceNear(el, label, true);
    });
'@
    }
    $dragDropRuntimeJs = ''
    $cryptoRuntimeJs = Get-OtterJsCryptoRuntime
    if ($usesDragDrop) {
        $dragDropRuntimeJs = @'
    const otterDragState = { draggedId: null };
    window.otterDragCtx = null;
    function otterClosest(t, selector) { return t && t.closest ? t.closest(selector) : null; }
    document.addEventListener('dragstart', (e) => { const d = otterClosest(e.target, '[draggable="true"]'); otterDragState.draggedId = d ? d.id : null; }, true);
    document.addEventListener('dragend', () => { otterDragState.draggedId = null; }, true);
    // A drop only happens on elements whose dragover was cancelled: this is
    // what `accepts drops is true` means. Files dropped elsewhere are left
    // to the browser.
    document.addEventListener('dragover', (e) => { if (otterClosest(e.target, '[data-otter-accepts-drops="true"]')) { e.preventDefault(); } });
    document.addEventListener('drop', (e) => { if (otterClosest(e.target, '[data-otter-accepts-drops="true"]')) { e.preventDefault(); } });
    function otterIsFileDrop(event) { return !!(event.dataTransfer && event.dataTransfer.files && event.dataTransfer.files.length > 0); }
    function otterIsItemDrop(event) {
      const types = event.dataTransfer && event.dataTransfer.types ? Array.from(event.dataTransfer.types) : [];
      return types.indexOf('application/x-otter') >= 0 || otterDragState.draggedId !== null;
    }
    function otterMakeDragCtx(event, el, kind) {
      const rect = el.getBoundingClientRect();
      let data = null;
      try {
        const raw = event.dataTransfer ? event.dataTransfer.getData('application/x-otter') : '';
        if (raw) { data = JSON.parse(raw); }
      } catch (err) { data = null; }
      const files = [];
      if (event.dataTransfer && event.dataTransfer.files) {
        for (const f of Array.from(event.dataTransfer.files)) { files.push({ __otterThing: true, typeName: 'file', props: { name: f.name, size: f.size, type: f.type, modified: f.lastModified }, file: f }); }
      }
      return { kind: kind, event: event, x: event.clientX - rect.left, y: event.clientY - rect.top, data: data, draggedId: otterDragState.draggedId, files: files };
    }
    function otterDragField(field) {
      const c = window.otterDragCtx;
      const where = { 'dragged item': 'a drag or drop event', 'drag data': 'a drag or drop event', 'dropped files': '"on files dropped on ..." or "on drop on ..."', 'drop x': '"on drop on ..." or "on files dropped on ..."', 'drop y': '"on drop on ..." or "on files dropped on ..."' };
      if (!c) { throw new Error('"' + field + '" is only available inside ' + where[field] + '.'); }
      if ((field === 'drop x' || field === 'drop y') && c.kind === 'drag') { throw new Error('"' + field + '" is only available inside ' + where[field] + '.'); }
      switch (field) {
        case 'dragged item': return c.draggedId;
        case 'dropped files': return c.files;
        case 'drag data': return c.data;
        case 'drop x': return c.x;
        case 'drop y': return c.y;
      }
      throw new Error('Unknown drag field: ' + field);
    }
    function otterSetDragData(event, value) {
      if (!event || event.type !== 'dragstart' || !event.dataTransfer) { throw new Error('"set drag data" only works inside "on drag of ...".'); }
      if (window.otterDragCtx) { window.otterDragCtx.data = value; }
      event.dataTransfer.setData('application/x-otter', JSON.stringify(value));
      event.dataTransfer.setData('text/plain', String(value));
    }
'@
    }

    $surface = Get-OtterSurfacePalette -Background $rootBg
    # The title is final here (a window's label can name the app, above).
    $titleHtml = Escape-OtterHtmlAttr -Text $appTitle
    if ($pageMeta.Count -gt 0 -and $pageMeta[0] -like '*name="description"*') {
        $pageMeta.Insert(1, "  <meta property=`"og:title`" content=`"$titleHtml`">")
    }
    $pageMetaHtml = if ($pageMeta.Count -gt 0) { "`n" + ($pageMeta -join "`n") } else { '' }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$titleHtml</title>$pageMetaHtml
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:ital,wght@0,300;0,400;0,500;0,600;0,700;0,800;1,400;1,600;1,700&family=Playfair+Display:ital,wght@1,500;1,600;1,700&family=Newsreader:ital,opsz,wght@1,6..72,500;1,6..72,600;1,6..72,700&display=swap" rel="stylesheet">
  <style>
    :root {
      --otter-bg: $rootBg;
      --otter-card-bg: $($surface.CardBg);
      --otter-text: $rootFg;
      --otter-text-muted: $($surface.Muted);
      --otter-primary: #2563eb;
      --otter-primary-hover: #1d4ed8;
      --otter-input-bg: $($surface.InputBg);
      --otter-border: $($surface.Border);
      --otter-card-shadow: $($surface.Shadow);
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
$runnableCss
$formCss
    body.otter-has-page.otter-doc-scroll {
      height: auto;
      max-height: none;
      overflow-x: hidden;
      overflow-y: auto;
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
      box-shadow: var(--otter-card-shadow);
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
    function otterGetElement(id) { if (id && typeof id === 'object' && id.__otterUi) { return id.el; } return document.getElementById(id); }
    // The element that holds a control's value: the input inside a
    // checkbox, toggle or radio button's label.
    function otterValueElement(id) {
      const el = otterGetElement(id);
      const labelled = el && el.classList && ['otter-checkbox-label', 'otter-toggle-label', 'otter-radio-label'].some(c => el.classList.contains(c));
      return labelled ? (el.querySelector('input') || el) : el;
    }
$dragDropRuntimeJs
$runnableRuntimeJs
$cryptoRuntimeJs
$formRuntimeJs
    function otterGetText(id) {
      const el = otterValueElement(id);
      if (!el) return '';
      if (el.type === 'checkbox' || el.type === 'radio') return el.checked;
      const tag = el.tagName ? el.tagName.toUpperCase() : '';
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') {
        return el.value;
      }
      return el.textContent || '';
    }
    function otterSetText(id, val) {
      const el = otterValueElement(id);
      if (!el) return;
      if (el.type === 'checkbox' || el.type === 'radio') { el.checked = Boolean(val); return; }
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
    // A checkbox's checked / enabled state is its input's; everything else
    // (styles, visibility) is the labelled control's.
    const otterInputProps = new Set(['checked', 'disabled', 'value']);
    function otterSetProperty(id, prop, val) {
      if (prop === 'error' && typeof otterSetFieldError === 'function') { otterSetFieldError(id, val); return; }
      const el = otterInputProps.has(prop) ? otterValueElement(id) : otterGetElement(id);
      if (el) {
        if (prop === 'url' && el.tagName === 'A') { el.href = val; return; }
        el[prop] = val;
        if (el.dataset) el.dataset[prop] = val;
      }
    }
    function otterGetProperty(id, prop) {
      if ((prop === 'valid' || prop === 'error') && typeof otterFormProperty === 'function') return otterFormProperty(id, prop);
      const el = otterInputProps.has(prop) ? otterValueElement(id) : otterGetElement(id);
      return el ? el[prop] : '';
    }
$runtimeUiJs
    function otterSay(...args) {
      console.log(...args);
      const out = document.getElementById('otter-live-output');
      if (out) {
        out.style.display = 'block';
        out.textContent = args.join(' ');
      }
    }
    // A desktop shell can provide these operations natively as
    // window.otterNative (the Electron export does, from its preload
    // script). When it is present it is used before the loopback bridge
    // and the browser fallbacks, so the same compiled page runs in a
    // browser tab, under the PowerShell desktop bridge, or in Electron.
    function otterNativeMethod(group, name) {
      const native = window.otterNative;
      const members = native ? native[group] : null;
      return (members && typeof members[name] === 'function') ? members[name] : null;
    }
    async function otterReadFile(filePath) {
      const nativeRead = otterNativeMethod('files', 'read');
      if (nativeRead) return String(await nativeRead(filePath));
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
    window.otterReadFile = otterReadFile;
    async function otterWriteFile(filePath, content) {
      const nativeWrite = otterNativeMethod('files', 'write');
      if (nativeWrite) return await nativeWrite(filePath, content);
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
      const nativeDownload = otterNativeMethod('files', 'download');
      if (nativeDownload) return await nativeDownload(url, filePath);
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
      let data;
      const nativeRun = otterNativeMethod('commands', 'exec');
      if (nativeRun) {
        data = await nativeRun(command);
      } else {
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
        data = await resp.json();
      }
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
      const nativeFiles = otterNativeMethod('files', 'list');
      if (nativeFiles) return await nativeFiles(folderPath, includeSubfolders);
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
      const nativeFolders = otterNativeMethod('folders', 'list');
      if (nativeFolders) return await nativeFolders(folderPath, includeSubfolders);
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
      const nativeOperation = otterNativeMethod('files', 'operate');
      if (nativeOperation) return await nativeOperation(operation, payload || {});
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
        const nativeCopy = otterNativeMethod('clipboard', 'write');
        if (nativeCopy) return await nativeCopy(text);
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
        const nativePaste = otterNativeMethod('clipboard', 'read');
        if (nativePaste) return String((await nativePaste()) || '');
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
      const nativeNotify = otterNativeMethod('system', 'notification');
      if (nativeNotify) { nativeNotify(title, message).catch(() => {}); }
      const bridge = getDesktopBridge();
      if (bridge && !nativeNotify) {
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
      const nativeEnv = otterNativeMethod('system', 'env');
      if (nativeEnv) return await nativeEnv(name);
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
      const nativePaths = otterNativeMethod('system', 'paths');
      if (nativePaths) return await nativePaths();
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
      const nativeChoose = otterNativeMethod('dialogs', 'openFile');
      if (nativeChoose) return String((await nativeChoose()) || '');
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
      const nativeChoose = otterNativeMethod('dialogs', 'openFolder');
      if (nativeChoose) return String((await nativeChoose()) || '');
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
      const nativeSave = otterNativeMethod('dialogs', 'save');
      if (nativeSave) return String((await nativeSave()) || '');
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

    // D103: SPA routing. A generic capability (no app-specific IDs or
    // behavior baked in here - every page id/path comes from the
    // compiled program's own route statements), matching this
    // project's own rule that shared runtime modules stay generic.
    // Route patterns are validated here, at genuine RUNTIME, rather than
    // only for literal-string paths at parse time - this way every path
    // (literal or computed) goes through the exact same checks.
    window.otterRouter = {
      routes: [],
      otherwiseId: null,
      currentParams: {},
      changeHandlers: [],
      register: function(pathPattern, pageId) {
        if (typeof pathPattern !== 'string' || pathPattern.length === 0 || pathPattern.charAt(0) !== '/') {
          throw new Error('A route must begin with "/", but got "' + pathPattern + '".');
        }
        const segs = pathPattern.split('/').filter(function(s) { return s.length > 0; });
        const paramNames = [];
        const regexParts = segs.map(function(seg) {
          if (seg.charAt(0) === ':') {
            const name = seg.substring(1);
            if (paramNames.indexOf(name) !== -1) {
              throw new Error('Route "' + pathPattern + '" uses the parameter name "' + name + '" more than once.');
            }
            paramNames.push(name);
            return '([^/]+)';
          }
          return seg.replace(/[.*+?^`${}()|[\]\\]/g, '\\`$&');
        });
        if (this.routes.some(function(r) { return r.pattern === pathPattern; })) {
          throw new Error('Route "' + pathPattern + '" is already registered.');
        }
        const regex = new RegExp('^/' + regexParts.join('/') + '/?$');
        this.routes.push({ pattern: pathPattern, paramNames: paramNames, regex: regex, pageId: pageId, isStatic: paramNames.length === 0 });
        // Static routes must win over parameterized ones at the same
        // depth (design spec item 16: /users/settings beats /users/:id) -
        // keeping static routes sorted first makes "match" a plain
        // first-match scan with no separate specificity pass.
        this.routes.sort(function(a, b) { return (a.isStatic === b.isStatic) ? 0 : (a.isStatic ? -1 : 1); });
      },
      registerOtherwise: function(pageId) { this.otherwiseId = pageId; },
      match: function(path) {
        let p = path.length > 1 && path.charAt(path.length - 1) === '/' ? path.slice(0, -1) : path;
        for (let i = 0; i < this.routes.length; i++) {
          const r = this.routes[i];
          const m = r.regex.exec(p);
          if (m) {
            const params = {};
            r.paramNames.forEach(function(name, idx) { params[name] = decodeURIComponent(m[idx + 1]); });
            return { pageId: r.pageId, params: params };
          }
        }
        return this.otherwiseId ? { pageId: this.otherwiseId, params: {} } : null;
      },
      showForCurrentPath: function() {
        const path = window.location.pathname;
        const matched = this.match(path);
        if (!matched) {
          throw new Error('No route matches "' + path + '" and no "route otherwise" fallback was declared.');
        }
        this.currentParams = matched.params;
        this.routes.forEach((r) => { const el = document.getElementById(r.pageId); if (el) el.style.display = 'none'; });
        if (this.otherwiseId) { const el = document.getElementById(this.otherwiseId); if (el) el.style.display = 'none'; }
        const target = document.getElementById(matched.pageId);
        if (target) target.style.display = '';
        this.changeHandlers.forEach((h) => h());
      },
      goTo: function(path) {
        window.history.pushState({}, '', path);
        this.showForCurrentPath();
      },
      replaceRoute: function(path) {
        window.history.replaceState({}, '', path);
        this.showForCurrentPath();
      },
      param: function(name) { return Object.prototype.hasOwnProperty.call(this.currentParams, name) ? this.currentParams[name] : null; },
      queryParam: function(name) { return new URLSearchParams(window.location.search).get(name); }
    };
    window.addEventListener('popstate', function() { window.otterRouter.showForCurrentPath(); });

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

          // The canvas's own speed (25 = normal), set when it is declared
          // (speed 50) or while the program runs (speed of cube is 50).
          let spd = 1.0;
          if (canvas.speed !== undefined && canvas.speed !== null && canvas.speed !== '') {
            spd = Number(canvas.speed) / 25;
          } else if (canvas.dataset.speed) {
            spd = Number(canvas.dataset.speed) / 25;
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
          const strokeCol = canvas.color || canvas.dataset.color || '#38bdf8';
          const glowCol = canvas.glow || canvas.dataset.glow || '#0284c7';
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
      }
    });

    // Top-level application initialization
    (async function() {
$topLevelJoined

    // D103: show the page matching the URL the browser actually loaded -
    // the programmer never calls go-to at startup (design spec item
    // 13). Guarded so a program with no route statements at all pays
    // nothing and behaves exactly as before D103.
    if (window.otterRouter.routes.length > 0 || window.otterRouter.otherwiseId) {
      window.otterRouter.showForCurrentPath();
    }

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

# The real location of a path, with every symbolic link or junction along it
# followed (the file itself and any linked folder on the way). From the
# release line (RC3 B4). A path that does not exist yet is returned as far as
# it could be resolved.
function Resolve-OtterRealPath {
    param([Parameter(Mandatory)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $hops = 0
    while ($true) {
        $root = [System.IO.Path]::GetPathRoot($full)
        $parts = @($full.Substring($root.Length) -split '[\\/]' | Where-Object { $_ -ne '' })
        $current = $root
        $relinked = $false
        for ($i = 0; $i -lt $parts.Count; $i++) {
            $next = [System.IO.Path]::Combine($current, $parts[$i])
            $item = Get-Item -LiteralPath $next -Force -ErrorAction SilentlyContinue
            if ($item -and ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction')) {
                $target = @($item.Target)[0]
                if ($target) {
                    $hops++
                    if ($hops -gt 40) {
                        throw [OtterError]::new("The path '$Path' has too many links to follow (a link loop?).", 0, 'build')
                    }
                    # A relative target is relative to the link's own folder.
                    $resolvedTarget = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($current, $target))
                    $rest = @($parts | Select-Object -Skip ($i + 1))
                    $full = $resolvedTarget
                    foreach ($r in $rest) { $full = [System.IO.Path]::Combine($full, $r) }
                    $full = [System.IO.Path]::GetFullPath($full)
                    $relinked = $true
                    break
                }
            }
            $current = $next
        }
        if (-not $relinked) { return $current }
    }
}

# True when $Path is $Folder itself or somewhere beneath it (both real paths).
function Test-OtterPathInside {
    param([string]$Path, [string]$Folder)
    $onWindows = ($PSVersionTable.PSEdition -ne 'Core') -or [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
    $comparison = if ($onWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    $folderWithSep = $Folder.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    return $Path.Equals($Folder.TrimEnd('\', '/'), $comparison) -or $Path.StartsWith($folderWithSep, $comparison)
}

# Which stylesheet belongs to a program - D125, the release line's rule,
# adopted on this line 2026-09-30 (Jeff): a web program <entry>.ot uses
# <entry>.css from the same folder (main.ot uses main.css), and nothing else.
# Every web-producing command (otter web, build, desktop, Studio's render)
# goes through here. The stylesheet must resolve, following symbolic links,
# inside the entry's folder: a link to a file elsewhere (~/.ssh/id_rsa) is
# refused before anything is written. No stylesheet is not an error.
function Resolve-OtterProjectStylesheet {
    param([Parameter(Mandatory)][string]$SourcePath)

    $entry = [System.IO.Path]::GetFullPath($SourcePath)
    $named = [System.IO.Path]::ChangeExtension($entry, '.css')
    if (-not (Test-Path -LiteralPath $named -PathType Leaf)) { return $null }
    $folderReal = Resolve-OtterRealPath -Path ([System.IO.Path]::GetDirectoryName($entry))
    $cssReal = Resolve-OtterRealPath -Path $named
    if (-not (Test-OtterPathInside -Path $cssReal -Folder $folderReal)) {
        throw [OtterError]::new("The stylesheet '$([System.IO.Path]::GetFileName($named))' is a link to '$cssReal', which is outside the folder that holds '$([System.IO.Path]::GetFileName($entry))'. Otter only includes files from inside that folder, so nothing was written.", 0, 'build')
    }
    return $cssReal
}

# Embed the program's stylesheet once, just before the first </head>. A plain
# string insert, not -replace, so `$` sequences in the CSS stay as written.
function Add-OtterProjectStylesheet {
    param(
        [Parameter(Mandatory)][string]$Html,
        [Parameter(Mandatory)][string]$StylesheetPath
    )
    $cssContent = [System.IO.File]::ReadAllText($StylesheetPath, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    $headEnd = $Html.IndexOf('</head>', [System.StringComparison]::OrdinalIgnoreCase)
    if ($headEnd -lt 0) { return $Html }
    $block = "<style id=`"otter-sidecar-style`">`n$cssContent`n</style>`n"
    return $Html.Insert($headEnd, $block)
}

function Export-OtterWebApplication {
    param(
        [Parameter(Mandatory)][string[]]$SourcePath,
        [string]$OutputPath,
        [switch]$PassThruExceptions,
        # Compile the source as though it lived in this folder: its `use`
        # imports and (when no stylesheet sits beside the source itself) its
        # project stylesheet are found there. For an editor compiling an
        # unsaved copy of a project file (Otter Studio).
        [string]$SourceDirectory = ''
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
        $resolvedProgram = if ($SourceDirectory -and $resolved.Path -eq (Resolve-Path -LiteralPath $SourcePath[0]).Path) { Resolve-OtterModuleSource -FilePath $resolved.Path -ImportDirectory $SourceDirectory } else { Resolve-OtterModuleSource -FilePath $resolved.Path }
        $sourceParts.Add($resolvedProgram.CombinedSource)
    }
    $sourceText = $sourceParts -join "`n"

    try {
        $tokens = ConvertTo-OtterTokens -Source $sourceText
        $ast = ConvertTo-OtterAst -Tokens $tokens

        $defaultTitle = [System.IO.Path]::GetFileNameWithoutExtension($primarySource)
        $html = ConvertTo-OtterWeb -Program $ast -Title $defaultTitle

        $stylesheet = Resolve-OtterProjectStylesheet -SourcePath $primarySource
        if (-not $stylesheet -and $SourceDirectory) {
            $besideSource = Join-Path ([System.IO.Path]::GetFullPath($SourceDirectory)) ([System.IO.Path]::GetFileName($primarySource))
            $stylesheet = Resolve-OtterProjectStylesheet -SourcePath $besideSource
        }
        if ($stylesheet) {
            $html = Add-OtterProjectStylesheet -Html $html -StylesheetPath $stylesheet
        }
    }
    catch [OtterError] {
        if ($PassThruExceptions) { throw }
        $err = $_.Exception
        if ($resolvedProgram) {
            $err = ConvertTo-OtterRemappedDiagnostics -Error $err -ResolvedProgram $resolvedProgram -RootFile $primarySource
        }
        Write-Host ''
        Write-Host $err.FormatDetailed() -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit(2)
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

# build.minify (project.json): a smaller page with the same behaviour. Only
# what cannot change meaning is removed, inside the page's own <style> and
# <script> blocks: CSS comments, whole-line // comments, the indentation at the
# start of each line and blank lines. Nothing inside a line is touched, so
# strings, regular expressions and selectors stay exactly as compiled. The
# compiler writes no string that spans lines, which is what would make
# removing indentation unsafe.
function ConvertTo-OtterMinifiedHtml {
    param([Parameter(Mandatory)][string]$Html)
    $evaluator = {
        param($m)
        $open = $m.Groups[1].Value
        $body = $m.Groups[3].Value
        if ($m.Groups[2].Value -ieq 'style') {
            $body = [regex]::Replace($body, '(?s)/\*.*?\*/', '')
        }
        $kept = foreach ($line in ($body -split "`r?`n")) {
            $trimmed = $line.Trim()
            if (-not $trimmed) { continue }
            if ($m.Groups[2].Value -ieq 'script' -and $trimmed.StartsWith('//')) { continue }
            $trimmed
        }
        return $open + "`n" + (@($kept) -join "`n") + "`n" + "</$($m.Groups[2].Value)>"
    }
    # <style ...> and <script> without src="...": the page's own code.
    return [regex]::Replace($Html, '(?is)(<(style|script)\b(?![^>]*\bsrc=)[^>]*>)(.*?)</\2>', [System.Text.RegularExpressions.MatchEvaluator]$evaluator)
}

Export-ModuleMember -Function ConvertTo-OtterWeb, Export-OtterWebApplication, Resolve-OtterProjectStylesheet, ConvertTo-OtterMinifiedHtml
