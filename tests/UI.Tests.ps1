using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.UI.psm1
using module ..\src\Otter.Interpreter.psm1

# UI.Tests.ps1
#
# D44: external UI resources. Tests the lifecycle guarantees directly -
# real WPF object created immediately, same identity for its whole life -
# and confirms the boundary D44 principle 5 requires: no WPF-specific name
# ever reaches an Otter-facing string.

. "$PSScriptRoot\TestHelpers.ps1"

function Lit { param($v, [int]$l = 1) [LiteralExpr]::new($v, $l) }

function Invoke-TestProgram {
    param([Node[]]$Statements)
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($t) $collected.Add($t) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        Invoke-OtterProgram -Program ([ProgramNode]::new($Statements)) -Environment (New-OtterEnvironment)
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return , $collected.ToArray()
}

# Same as Invoke-TestProgram, but also hands back the environment, the
# collected-output list, and the writer itself - a D46 test registers a
# handler while the program runs, then fires the underlying native event
# AFTERWARD (outside the program), so the writer needs to be re-armed
# around that later call too, or the handler's `say` would go nowhere.
function Invoke-TestProgramWithEnv {
    param([Node[]]$Statements)
    $env = New-OtterEnvironment
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($t) $collected.Add($t) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        Invoke-OtterProgram -Program ([ProgramNode]::new($Statements)) -Environment $env
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    return @{ Env = $env; Output = $collected; Writer = $writer }
}

# Runs $Body (typically firing a native WPF event) with the writer armed,
# so any `say` inside a D46 handler that fires during $Body is captured.
function Invoke-WithOtterWriter {
    param([scriptblock]$Writer, [scriptblock]$Body)
    Set-OtterOutputWriter -Writer $Writer
    try { & $Body }
    finally { Set-OtterOutputWriter -Writer $null }
}

Write-Host ''
Write-Host 'External UI resources (D44)' -ForegroundColor Cyan

Test-Otter 'row and column are real provider-backed layout resources' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('row', 'toolbar', 1),
        [CreateUiResourceStmt]::new('column', 'sidebar', 2)
    )
    $row = $env.Get('toolbar'); $column = $env.Get('sidebar')
    Assert-True (Test-OtterUiResource $row) 'row must be a UI resource'
    Assert-True (Test-OtterUiResource $column) 'column must be a UI resource'
    Assert-AreEqual -Expected 'StackPanel' -Actual $row.Native.GetType().Name
    Assert-AreEqual -Expected 'Horizontal' -Actual $row.Native.Orientation.ToString()
    Assert-AreEqual -Expected 'Vertical' -Actual $column.Native.Orientation.ToString()
}

Test-Otter 'ordinary controls are content-sized by default' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('button', 'button', 1),
        [CreateUiResourceStmt]::new('text box', 'box', 2),
        [CreateUiResourceStmt]::new('text', 'label', 3)
    )
    foreach ($name in @('button', 'box', 'label')) {
        Assert-AreEqual -Expected 'Left' -Actual $env.Get($name).Native.HorizontalAlignment.ToString()
    }
}

Test-Otter 'rows and columns accept ordered and nested children' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('row', 'toolbar', 2),
        [CreateUiResourceStmt]::new('column', 'panel', 3),
        [CreateUiResourceStmt]::new('text', 'first', 4),
        [CreateUiResourceStmt]::new('button', 'second', 5),
        [PutInStmt]::new([VariableExpr]::new('first', 6), [VariableExpr]::new('toolbar', 6), 6),
        [PutInStmt]::new([VariableExpr]::new('second', 7), [VariableExpr]::new('toolbar', 7), 7),
        [PutInStmt]::new([VariableExpr]::new('toolbar', 8), [VariableExpr]::new('panel', 8), 8),
        [PutInStmt]::new([VariableExpr]::new('panel', 9), [VariableExpr]::new('app', 9), 9)
    )
    $row = $env.Get('toolbar'); $panel = $env.Get('panel'); $app = $env.Get('app')
    Assert-AreEqual -Expected 2 -Actual $row.Native.Children.Count
    Assert-True ([object]::ReferenceEquals($row.Native.Children[0], $env.Get('first').Native)) 'row order must be preserved'
    Assert-True ([object]::ReferenceEquals($row.Native.Children[1], $env.Get('second').Native)) 'row order must be preserved'
    Assert-True ([object]::ReferenceEquals($panel.Native.Children[0], $row.Native)) 'row must nest in column'
    Assert-True ([object]::ReferenceEquals($app.Native.Content.Children[0], $panel.Native)) 'column must nest in window'
}

Test-Otter 'a column can nest in a row and empty layout resources are valid' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('row', 'row', 1),
        [CreateUiResourceStmt]::new('column', 'column', 2),
        [PutInStmt]::new([VariableExpr]::new('column', 3), [VariableExpr]::new('row', 3), 3)
    )
    Assert-AreEqual -Expected 1 -Actual $env.Get('row').Native.Children.Count
    Assert-AreEqual -Expected 0 -Actual $env.Get('column').Native.Children.Count
}

Test-Otter 'row and column spacing works before and after children' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('row', 'row', 1),
        [ObjectDefStmt]::new('row', 'thing', @([AssignStmt]::new('spacing', (Lit 10), 2)), 2),
        [CreateUiResourceStmt]::new('text', 'one', 3),
        [PutInStmt]::new([VariableExpr]::new('one', 4), [VariableExpr]::new('row', 4), 4),
        [ObjectDefStmt]::new('row', 'thing', @([AssignStmt]::new('spacing', (Lit 20), 5)), 5),
        [CreateUiResourceStmt]::new('text', 'two', 6),
        [PutInStmt]::new([VariableExpr]::new('two', 7), [VariableExpr]::new('row', 7), 7)
    )
    $row = $env.Get('row')
    Assert-AreEqual -Expected 20 -Actual (Get-OtterUiProperty -Resource $row -Property 'spacing' -Line 8)
    Assert-AreEqual -Expected 20 -Actual $row.Native.Children[0].Margin.Right
    Assert-AreEqual -Expected 20 -Actual $row.Native.Children[1].Margin.Right
}

Test-Otter 'layout resources support width and height' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('column', 'panel', 1),
        [ObjectDefStmt]::new('panel', 'thing', @(
            [AssignStmt]::new('width', (Lit 300), 2),
            [AssignStmt]::new('height', (Lit 200), 2)
        ), 2)
    )
    Assert-AreEqual -Expected 300 -Actual $env.Get('panel').Native.Width
    Assert-AreEqual -Expected 200 -Actual $env.Get('panel').Native.Height
}

Test-Otter 'layout resources reject duplicate parenting and show' {
    Assert-OtterFails -Containing 'one place at a time' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [CreateUiResourceStmt]::new('row', 'row', 2),
            [PutInStmt]::new([VariableExpr]::new('row', 3), [VariableExpr]::new('app', 3), 3),
            [PutInStmt]::new([VariableExpr]::new('row', 4), [VariableExpr]::new('app', 4), 4)
        )
    }
    Assert-OtterFails -Containing 'only show a window' -Body {
        Invoke-TestProgram @([CreateUiResourceStmt]::new('row', 'row', 1), [ShowStmt]::new([VariableExpr]::new('row', 2), 2))
    }
    Assert-OtterFails -Containing 'only show a window' -Body {
        Invoke-TestProgram @([CreateUiResourceStmt]::new('column', 'column', 1), [ShowStmt]::new([VariableExpr]::new('column', 2), 2))
    }
}


# =================================================================
# lifecycle - the central claim, verified directly
# =================================================================

Test-Otter 'create button into helloButton makes a REAL WPF Button, immediately' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1)
    )))
    $resource = $env.Get('helloButton')
    Assert-True (Test-OtterUiResource $resource) 'expected an OtterUiResource'
    Assert-AreEqual -Expected 'button' -Actual $resource.Kind
    Assert-AreEqual -Expected 'wpf' -Actual $resource.Provider
    Assert-AreEqual -Expected 'Button' -Actual $resource.Native.GetType().Name
}

Test-Otter 'the resource keeps the SAME identity across every read (Jeff''s core lifecycle requirement)' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1)
    )))
    $first = $env.Get('helloButton')
    $second = $env.Get('helloButton')
    Assert-True ([object]::ReferenceEquals($first, $second)) 'the wrapper must be the same instance'
    Assert-True ([object]::ReferenceEquals($first.Native, $second.Native)) 'the underlying WPF object must be the same instance'
}

Test-Otter 'a property set directly on the native object is visible through every reference to it' {
    # Proves "attachment/layout reuses the same object, it does not
    # recreate it" is actually true of the underlying value, not just
    # asserted - set .Content directly (standing in for what D45's real
    # property-write will eventually do) and confirm every read sees it.
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1)
    )))
    $resource = $env.Get('helloButton')
    $resource.Native.Content = 'Say Hello'

    $readBack = $env.Get('helloButton')
    Assert-AreEqual -Expected 'Say Hello' -Actual $readBack.Native.Content
}

Test-Otter 'each of the D44 proving-set control kinds creates its real WPF type' {
    $expected = @{
        'window'   = 'Window'
        'button'   = 'Button'
        'text'     = 'TextBlock'
        'text box' = 'TextBox'
    }
    foreach ($kind in $expected.Keys) {
        $resource = New-OtterUiResourceValue -Kind $kind -Line 1
        Assert-AreEqual -Expected $kind -Actual $resource.Kind -Message $kind
        Assert-AreEqual -Expected $expected[$kind] -Actual $resource.Native.GetType().Name -Message $kind
    }
}

Test-Otter 'an unsupported kind is a clear Otter error, not a raw exception' {
    Assert-OtterFails -Containing "don't know how to create a checkbox" -Body {
        New-OtterUiResourceValue -Kind 'checkbox' -Line 1
    }
}


# =================================================================
# the boundary - D44 principle 5: no WPF names ever reach Otter output
# =================================================================

Test-Otter 'say prints "a button", never the WPF class name' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [SayStmt]::new(@([VariableExpr]::new('helloButton', 2)), 2)
    )
    Assert-Lines -Expected @('a button') -Actual $out
    Assert-False ($out[0] -like '*System.Windows*') 'must not leak the WPF type name'
}

Test-Otter 'a created resource is truthy, the same reasoning as an object' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('window', 'app', 1)
    )))
    Assert-True (Test-OtterTruthy -Value ($env.Get('app')))
}

Test-Otter 'an unsupported property still names the kind, never a WPF type name (D45)' {
    Assert-OtterFails -Containing 'a text box' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('text box', 'nameBox', 1),
            [SayStmt]::new(@([PropertyAccessExpr]::new('color', [VariableExpr]::new('nameBox', 2), 2)), 2)
        )
    }
}


# =================================================================
# D45 - property read/write, routed through the toolkit-neutral mapping
# =================================================================

Test-Otter 'text of a button writes and reads back through ordinary property syntax' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2), (Lit 'Say Hello'), 2),
        [SayStmt]::new(@([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 3), 3)), 3)
    )
    Assert-Lines -Expected @('Say Hello') -Actual $out
}

Test-Otter 'button text maps to native Content, not Text - verified on the real object' {
    # This is the exact mapping the investigation confirmed empirically:
    # TextBox does not even have a Content property; Button does not have
    # a settable Text property the same way. Getting this backwards would
    # be a silent, wrong write, not an error.
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2), (Lit 'Say Hello'), 2)
    )))
    $resource = $env.Get('helloButton')
    Assert-AreEqual -Expected 'Say Hello' -Actual $resource.Native.Content
}

Test-Otter 'text box text maps to native Text, not Content' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('text box', 'nameBox', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('nameBox', 2), 2), (Lit 'Jeff'), 2)
    )))
    $resource = $env.Get('nameBox')
    Assert-AreEqual -Expected 'Jeff' -Actual $resource.Native.Text
}

Test-Otter 'window title, width and height all read and write correctly' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('title', [VariableExpr]::new('app', 2), 2), (Lit 'My App'), 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 3), 3), (Lit 500.0), 3),
        [AssignStmt]::new([PropertyAccessExpr]::new('height', [VariableExpr]::new('app', 4), 4), (Lit 300.0), 4),
        [SayStmt]::new(@([PropertyAccessExpr]::new('title', [VariableExpr]::new('app', 5), 5)), 5),
        [SayStmt]::new(@([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 6), 6)), 6),
        [SayStmt]::new(@([PropertyAccessExpr]::new('height', [VariableExpr]::new('app', 7), 7)), 7)
    )
    Assert-Lines -Expected @('My App', '500', '300') -Actual $out
}

Test-Otter 'text properties coerce any value, the same conversion say already uses' {
    # text of X is 5 sets it to "5" rather than erroring - matching how
    # "say 5" already prints "5", not a type mismatch.
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2), (Lit 5.0), 2),
        [SayStmt]::new(@([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 3), 3)), 3)
    )
    Assert-Lines -Expected @('5') -Actual $out
}

Test-Otter 'a numeric property rejects the wrong type as a clean Otter error, not a raw .NET exception' {
    # Verified before writing Set-OtterUiProperty: WPF itself throws
    # SetValueInvocationException naming "System.Double" directly in its
    # message for exactly this case. That must never reach a user.
    Assert-OtterFails -Containing 'I expected a number for the width' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 2), 2), (Lit 'not a number'), 2)
        )
    }
}

Test-Otter 'the numeric-type error never leaks System.Double or any .NET name' {
    $env = New-OtterEnvironment
    try {
        Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 2), 2), (Lit 'not a number'), 2)
        )))
        throw 'expected this to fail'
    }
    catch {
        Assert-False ($_.Exception.Message -like '*System.*') 'must not leak a .NET type name'
        Assert-False ($_.Exception.Message -like '*SetValueInvocation*') 'must not leak the raw WPF exception type'
    }
}

Test-Otter 'a negative size is a clean Otter error, not a raw .NET one (D45 maintenance fix)' {
    # Found during D48 investigation: WPF itself throws
    # ArgumentException("'-10' is not a valid value for property 'Width'")
    # for a negative Width - previously unguarded here. Zero remains valid.
    Assert-OtterFails -Containing "The width of a window can't be negative" -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 2), 2), (Lit -10.0), 2)
        )
    }
}

Test-Otter 'a zero size is still valid' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('app', 2), 2), (Lit 0.0), 2)
    )))
    Assert-AreEqual -Expected 0 -Actual $env.Get('app').Native.Width
}

Test-Otter 'reading an unset text property is gone, not an error, not empty text' {
    # D22: no value exists here yet is a different state from "" - a
    # freshly created button has never had its text set at all.
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [SayStmt]::new(@([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 2), 2)), 2)
    )
    Assert-Lines -Expected @('gone') -Actual $out
}

Test-Otter 'an unsupported property on a window names the window and the property' {
    Assert-OtterFails -Containing 'a window has no property called "color"' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [SayStmt]::new(@([PropertyAccessExpr]::new('color', [VariableExpr]::new('app', 2), 2)), 2)
        )
    }
}

Test-Otter 'setting an unsupported property fails before touching the native object at all' {
    $env = New-OtterEnvironment
    Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1)
    )))
    $resource = $env.Get('helloButton')
    $before = $resource.Native.Content

    Assert-OtterFails -Containing 'no property called' -Body {
        Set-OtterUiProperty -Resource $resource -Property 'color' -Value 'red' -Line 1
    }
    Assert-AreEqual -Expected $before -Actual $resource.Native.Content
}


# =================================================================
# D48 - width/height on every kind, background/foreground colors,
# window spacing. All routed through the existing D45 property system -
# zero grammar/AST changes.
# =================================================================

Test-Otter 'width and height now work on button, text box, and text - not just window' {
    foreach ($kind in @('button', 'text box', 'text')) {
        $env = New-OtterEnvironment
        Invoke-OtterProgram -Environment $env -Program ([ProgramNode]::new(@(
            [CreateUiResourceStmt]::new($kind, 'control', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('control', 2), 2), (Lit 140.0), 2),
            [AssignStmt]::new([PropertyAccessExpr]::new('height', [VariableExpr]::new('control', 3), 3), (Lit 42.0), 3)
        )))
        $native = $env.Get('control').Native
        Assert-AreEqual -Expected 140 -Actual $native.Width
        Assert-AreEqual -Expected 42 -Actual $native.Height
    }
}

Test-Otter 'background and foreground work on all four kinds via named colors' {
    foreach ($kind in @('window', 'button', 'text box', 'text')) {
        $out = Invoke-TestProgram @(
            [CreateUiResourceStmt]::new($kind, 'control', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('background', [VariableExpr]::new('control', 2), 2), (Lit 'blue'), 2),
            [AssignStmt]::new([PropertyAccessExpr]::new('foreground', [VariableExpr]::new('control', 3), 3), (Lit 'white'), 3),
            [SayStmt]::new(@([PropertyAccessExpr]::new('background', [VariableExpr]::new('control', 4), 4)), 4),
            [SayStmt]::new(@([PropertyAccessExpr]::new('foreground', [VariableExpr]::new('control', 5), 5)), 5)
        )
        Assert-Lines -Expected @('#FF0000FF', '#FFFFFFFF') -Actual $out
    }
}

Test-Otter 'hex colors work identically to named colors, through the same one conversion path' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'saveButton', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('background', [VariableExpr]::new('saveButton', 2), 2), (Lit '#2563EB'), 2),
        [SayStmt]::new(@([PropertyAccessExpr]::new('background', [VariableExpr]::new('saveButton', 3), 3)), 3)
    )
    Assert-Lines -Expected @('#FF2563EB') -Actual $out
}

Test-Otter 'an invalid color gives an Otter diagnostic, never the raw .NET FormatException' {
    Assert-OtterFails -Containing 'I don''t understand the color "notacolor"' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('button', 'helloButton', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('background', [VariableExpr]::new('helloButton', 2), 2), (Lit 'notacolor'), 2)
        )
    }
}

Test-Otter 'a color never set reads as gone, not an error, not a WPF brush' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [SayStmt]::new(@([PropertyAccessExpr]::new('background', [VariableExpr]::new('app', 2), 2)), 2)
    )
    Assert-Lines -Expected @('gone') -Actual $out
}

Test-Otter 'spacing set BEFORE put still applies to controls put in afterward' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('button', 'first', 2),
        [CreateUiResourceStmt]::new('button', 'second', 3),
        [AssignStmt]::new([PropertyAccessExpr]::new('spacing', [VariableExpr]::new('app', 4), 4), (Lit 12.0), 4),
        [PutInStmt]::new([VariableExpr]::new('first', 5), [VariableExpr]::new('app', 5), 5),
        [PutInStmt]::new([VariableExpr]::new('second', 6), [VariableExpr]::new('app', 6), 6)
    )
    $panel = $env.Get('app').Native.Content
    Assert-AreEqual -Expected ([System.Windows.Thickness]::new(0, 0, 0, 12)) -Actual $panel.Children[0].Margin
    Assert-AreEqual -Expected ([System.Windows.Thickness]::new(0, 0, 0, 12)) -Actual $panel.Children[1].Margin
}

Test-Otter 'spacing set AFTER put re-margins the controls already there' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('button', 'first', 2),
        [PutInStmt]::new([VariableExpr]::new('first', 3), [VariableExpr]::new('app', 3), 3),
        [AssignStmt]::new([PropertyAccessExpr]::new('spacing', [VariableExpr]::new('app', 4), 4), (Lit 12.0), 4)
    )
    $panel = $env.Get('app').Native.Content
    Assert-AreEqual -Expected ([System.Windows.Thickness]::new(0, 0, 0, 12)) -Actual $panel.Children[0].Margin
}

Test-Otter 'a control put in AFTER spacing is changed again still inherits the latest value' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('button', 'first', 2),
        [CreateUiResourceStmt]::new('button', 'second', 3),
        [PutInStmt]::new([VariableExpr]::new('first', 4), [VariableExpr]::new('app', 4), 4),
        [AssignStmt]::new([PropertyAccessExpr]::new('spacing', [VariableExpr]::new('app', 5), 5), (Lit 20.0), 5),
        [PutInStmt]::new([VariableExpr]::new('second', 6), [VariableExpr]::new('app', 6), 6)
    )
    $panel = $env.Get('app').Native.Content
    Assert-AreEqual -Expected ([System.Windows.Thickness]::new(0, 0, 0, 20)) -Actual $panel.Children[0].Margin
    Assert-AreEqual -Expected ([System.Windows.Thickness]::new(0, 0, 0, 20)) -Actual $panel.Children[1].Margin
}

Test-Otter 'spacing never set reads as gone' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [SayStmt]::new(@([PropertyAccessExpr]::new('spacing', [VariableExpr]::new('app', 2), 2)), 2)
    )
    Assert-Lines -Expected @('gone') -Actual $out
}

Test-Otter 'spacing round-trips once set, even with no controls put in yet' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('spacing', [VariableExpr]::new('app', 2), 2), (Lit 8.0), 2),
        [SayStmt]::new(@([PropertyAccessExpr]::new('spacing', [VariableExpr]::new('app', 3), 3)), 3)
    )
    Assert-Lines -Expected @('8') -Actual $out
}

Test-Otter 'negative spacing is rejected the same way negative sizes are' {
    Assert-OtterFails -Containing "The spacing of a window can't be negative" -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('spacing', [VariableExpr]::new('app', 2), 2), (Lit -5.0), 2)
        )
    }
}

Test-Otter 'spacing is window-only - not a property on button, text box, or text' {
    foreach ($kind in @('button', 'text box', 'text')) {
        Assert-OtterFails -Containing 'no property called "spacing"' -Body {
            Invoke-TestProgram @(
                [CreateUiResourceStmt]::new($kind, 'control', 1),
                [AssignStmt]::new([PropertyAccessExpr]::new('spacing', [VariableExpr]::new('control', 2), 2), (Lit 10.0), 2)
            )
        }
    }
}


# =================================================================
# D53 - scroll container. A dedicated, single-child resource - a scroll
# region only becomes scrollable once it has an explicit bound, verified
# directly before writing any of this (an unbounded ScrollViewer inside
# Otter's StackPanel-based window root just grows to fit all its
# content; it does not clip or scroll on its own).
# =================================================================

Test-Otter 'scroll is a real provider-backed resource kind' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('scroll', 'fileArea', 1)
    )
    $resource = $env.Get('fileArea')
    Assert-True (Test-OtterUiResource $resource) 'expected an OtterUiResource'
    Assert-AreEqual -Expected 'ScrollViewer' -Actual $resource.Native.GetType().Name
}

Test-Otter 'put attaches the one child directly - no implicit panel, unlike window' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('scroll', 'fileArea', 1),
        [CreateUiResourceStmt]::new('column', 'fileList', 2),
        [PutInStmt]::new([VariableExpr]::new('fileList', 3), [VariableExpr]::new('fileArea', 3), 3)
    )
    $scroll = $env.Get('fileArea')
    Assert-True ([object]::ReferenceEquals($scroll.Native.Content, $env.Get('fileList').Native)) 'Content must be the exact same native object, attached directly'
}

Test-Otter 'a second put into an already-filled scroll is a clean Otter error, not a silent replace' {
    Assert-OtterFails -Containing 'A scroll can only hold one thing' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('scroll', 'fileArea', 1),
            [CreateUiResourceStmt]::new('text', 'first', 2),
            [CreateUiResourceStmt]::new('text', 'second', 3),
            [PutInStmt]::new([VariableExpr]::new('first', 4), [VariableExpr]::new('fileArea', 4), 4),
            [PutInStmt]::new([VariableExpr]::new('second', 5), [VariableExpr]::new('fileArea', 5), 5)
        )
    }
}

Test-Otter 'the first child is unaffected after a rejected second put' {
    # Confirms the check happens BEFORE touching .Content a second time -
    # verified separately that WPF's own ContentControl.Content setter
    # does not throw on a second set, it silently replaces - so this
    # guards against a regression that would go back to that behavior.
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('scroll', 'fileArea', 1),
        [CreateUiResourceStmt]::new('text', 'first', 2),
        [CreateUiResourceStmt]::new('text', 'second', 3),
        [PutInStmt]::new([VariableExpr]::new('first', 4), [VariableExpr]::new('fileArea', 4), 4)
    )
    $scroll = $env.Get('fileArea')
    try {
        Add-OtterUiChild -Container $scroll -Item $env.Get('second') -Line 5
    } catch { }
    Assert-True ([object]::ReferenceEquals($scroll.Native.Content, $env.Get('first').Native)) 'the original child must still be attached'
}

Test-Otter 'a scroll with enough content and an explicit height actually scrolls - not just visually present' {
    # This is the acceptance test the investigation itself demanded: not
    # "a ScrollViewer object exists," but that with real overflowing
    # content and a real bound, the provider reports genuine scrollable
    # range and the viewport can actually move - the exact thing that
    # was FALSE before an explicit height was set, verified by hand
    # during the design pass.
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('scroll', 'fileArea', 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('height', [VariableExpr]::new('fileArea', 3), 3), (Lit 150.0), 3),
        [CreateUiResourceStmt]::new('column', 'fileList', 4),
        [PutInStmt]::new([VariableExpr]::new('fileList', 5), [VariableExpr]::new('fileArea', 5), 5),
        [PutInStmt]::new([VariableExpr]::new('fileArea', 6), [VariableExpr]::new('app', 6), 6)
    )
    $fileList = $env.Get('fileList')
    for ($i = 0; $i -lt 40; $i++) {
        $t = [System.Windows.Controls.TextBlock]::new()
        $t.Text = "item $i"
        $fileList.Native.Children.Add($t) | Out-Null
    }
    $scroll = $env.Get('fileArea')
    $app = $env.Get('app')

    $results = [hashtable]::Synchronized(@{ ScrollableHeight = $null; Offset = $null })
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.add_Tick({
        $timer.Stop()
        $app.Native.UpdateLayout()
        $results.ScrollableHeight = $scroll.Native.ScrollableHeight
        $scroll.Native.ScrollToVerticalOffset(50)
        $scroll.Native.UpdateLayout()
        $results.Offset = $scroll.Native.VerticalOffset
        $app.Native.Close()
    }.GetNewClosure())
    $timer.Start()
    $app.Native.ShowDialog() | Out-Null

    Assert-True ($results.ScrollableHeight -gt 0) 'overflowing content with a bound must produce a positive scrollable range'
    Assert-AreEqual -Expected 50 -Actual $results.Offset
}

Test-Otter 'content that does not overflow produces no scrollable range - not an error, not a fake one' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('scroll', 'fileArea', 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('height', [VariableExpr]::new('fileArea', 3), 3), (Lit 300.0), 3),
        [CreateUiResourceStmt]::new('text', 'label', 4),
        [PutInStmt]::new([VariableExpr]::new('label', 5), [VariableExpr]::new('fileArea', 5), 5),
        [PutInStmt]::new([VariableExpr]::new('fileArea', 6), [VariableExpr]::new('app', 6), 6)
    )
    $scroll = $env.Get('fileArea')
    $app = $env.Get('app')
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.add_Tick({ $timer.Stop(); $app.Native.Close() }.GetNewClosure())
    $timer.Start()
    $app.Native.ShowDialog() | Out-Null

    Assert-AreEqual -Expected 0 -Actual $scroll.Native.ScrollableHeight
}

Test-Otter 'width, height, and background all work on scroll' {
    $out = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('scroll', 'fileArea', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('fileArea', 2), 2), (Lit 400.0), 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('height', [VariableExpr]::new('fileArea', 3), 3), (Lit 300.0), 3),
        [AssignStmt]::new([PropertyAccessExpr]::new('background', [VariableExpr]::new('fileArea', 4), 4), (Lit 'white'), 4),
        [SayStmt]::new(@([PropertyAccessExpr]::new('width', [VariableExpr]::new('fileArea', 5), 5)), 5),
        [SayStmt]::new(@([PropertyAccessExpr]::new('height', [VariableExpr]::new('fileArea', 6), 6)), 6),
        [SayStmt]::new(@([PropertyAccessExpr]::new('background', [VariableExpr]::new('fileArea', 7), 7)), 7)
    )
    Assert-Lines -Expected @('400', '300', '#FFFFFFFF') -Actual $out
}

Test-Otter 'spacing is not supported on scroll' {
    Assert-OtterFails -Containing 'no property called "spacing"' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('scroll', 'fileArea', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('spacing', [VariableExpr]::new('fileArea', 2), 2), (Lit 10.0), 2)
        )
    }
}

Test-Otter 'a scroll can be put into a window, row, or column like any other resource' {
    foreach ($containerKind in @('window', 'row', 'column')) {
        $env = New-OtterEnvironment
        Invoke-OtterStatements -Environment $env -Statements @(
            [CreateUiResourceStmt]::new($containerKind, 'container', 1),
            [CreateUiResourceStmt]::new('scroll', 'fileArea', 2),
            [PutInStmt]::new([VariableExpr]::new('fileArea', 3), [VariableExpr]::new('container', 3), 3)
        )
        $container = $env.Get('container')
        # window (like row/column) wraps put-in children in its own
        # implicit panel (D47) - scroll is just another item that panel
        # holds; only when SCROLL is itself the container does D53's new
        # direct-Content behavior apply, covered by the tests above.
        if ($containerKind -eq 'window') {
            Assert-True ([object]::ReferenceEquals($container.Native.Content.Children[0], $env.Get('fileArea').Native)) "scroll must attach into $containerKind"
        } else {
            Assert-True ([object]::ReferenceEquals($container.Native.Children[0], $env.Get('fileArea').Native)) "scroll must attach into $containerKind"
        }
    }
}

Test-Otter 'a scroll can nest inside another scroll with no special-casing' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('scroll', 'outer', 1),
        [CreateUiResourceStmt]::new('scroll', 'inner', 2),
        [PutInStmt]::new([VariableExpr]::new('inner', 3), [VariableExpr]::new('outer', 3), 3)
    )
    Assert-True ([object]::ReferenceEquals($env.Get('outer').Native.Content, $env.Get('inner').Native)) 'nested scroll must attach directly'
}

Test-Otter 'putting something into a scroll follows the same one-parent rule as everything else' {
    Assert-OtterFails -Containing 'already somewhere else' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('scroll', 'areaOne', 1),
            [CreateUiResourceStmt]::new('scroll', 'areaTwo', 2),
            [CreateUiResourceStmt]::new('text', 'label', 3),
            [PutInStmt]::new([VariableExpr]::new('label', 4), [VariableExpr]::new('areaOne', 4), 4),
            [PutInStmt]::new([VariableExpr]::new('label', 5), [VariableExpr]::new('areaTwo', 5), 5)
        )
    }
}


# =================================================================
# D46 - event registration. Real native events, fired for real, not
# simulated - the handler runs because the actual WPF event fired, the
# same way it would in a running app once D47 adds a message loop.
# =================================================================

Test-Otter 'when helloButton is clicked runs the handler body when Click actually fires' {
    $result = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [WhenStmt]::new([VariableExpr]::new('helloButton', 2), 'clicked', @([SayStmt]::new(@((Lit 'Hello')), 3)), 2)
    )
    Assert-Lines -Expected @() -Actual $result.Output.ToArray()

    $resource = $result.Env.Get('helloButton')
    Invoke-WithOtterWriter -Writer $result.Writer -Body {
        $resource.Native.RaiseEvent(
            [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    }
    Assert-Lines -Expected @('Hello') -Actual $result.Output.ToArray()
}

Test-Otter 'when nameBox is changed runs when the real TextChanged event fires' {
    $result = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('text box', 'nameBox', 1),
        [WhenStmt]::new([VariableExpr]::new('nameBox', 2), 'changed', @([SayStmt]::new(@((Lit 'typed')), 3)), 2)
    )
    $resource = $result.Env.Get('nameBox')
    Invoke-WithOtterWriter -Writer $result.Writer -Body {
        $resource.Native.Text = 'Jeff'
    }
    Assert-Lines -Expected @('typed') -Actual $result.Output.ToArray()
}

Test-Otter 'when app is closed runs when the real Closed event fires' {
    $result = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [WhenStmt]::new([VariableExpr]::new('app', 2), 'closed', @([SayStmt]::new(@((Lit 'bye')), 3)), 2)
    )
    $resource = $result.Env.Get('app')
    Invoke-WithOtterWriter -Writer $result.Writer -Body {
        $resource.Native.Close()
    }
    Assert-Lines -Expected @('bye') -Actual $result.Output.ToArray()
}

Test-Otter 'the handler closes over the environment at registration, with no new scope' {
    # Confirms D46's frozen scoping rule directly: a variable assigned
    # inside the handler body is visible afterward in the SAME
    # environment, exactly like an If/While body already behaves - not
    # trapped in a function-call-style child scope.
    $result = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('button', 'helloButton', 1),
        [WhenStmt]::new([VariableExpr]::new('helloButton', 2), 'clicked',
            @([AssignStmt]::new('clickCount', (Lit 1.0), 3)), 2)
    )
    $resource = $result.Env.Get('helloButton')
    Invoke-WithOtterWriter -Writer $result.Writer -Body {
        $resource.Native.RaiseEvent(
            [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    }
    Assert-AreEqual -Expected 1 -Actual $result.Env.Get('clickCount')
}

Test-Otter 'an unsupported event names the kind and lists what it actually has' {
    Assert-OtterFails -Containing 'a button has no event called "dragged"' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('button', 'helloButton', 1),
            [WhenStmt]::new([VariableExpr]::new('helloButton', 2), 'dragged', @(), 2)
        )
    }
}

Test-Otter 'listening on something that is not a UI resource explains itself, never a WPF name' {
    Assert-OtterFails -Containing 'this is some text' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('notAResource', (Lit 'just text'), 1),
            [WhenStmt]::new([VariableExpr]::new('notAResource', 2), 'clicked', @(), 2)
        )
    }
}


# =================================================================
# D47 - put/show. The smallest end-to-end app: a real window appears,
# stays alive, accepts a real click, and closes cleanly.
# =================================================================

Test-Otter 'D47 end-to-end: create, put, show - a real click runs the handler, then the window closes cleanly' {
    $env = New-OtterEnvironment
    $collected = [System.Collections.Generic.List[string]]::new()
    $writer = { param($t) $collected.Add($t) }.GetNewClosure()
    Set-OtterOutputWriter -Writer $writer
    try {
        Invoke-OtterStatements -Environment $env -Statements @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [CreateUiResourceStmt]::new('button', 'helloButton', 2),
            [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('helloButton', 3), 3), (Lit 'Say Hello'), 3),
            [WhenStmt]::new([VariableExpr]::new('helloButton', 4), 'clicked', @([SayStmt]::new(@((Lit 'Hello!')), 5)), 4),
            [PutInStmt]::new([VariableExpr]::new('helloButton', 6), [VariableExpr]::new('app', 6), 6)
        )

        $appResource = $env.Get('app')
        $buttonResource = $env.Get('helloButton')

        # Stands in for a real user click, exactly as D46's own tests do -
        # then closes the window the way a person closing it via the
        # title bar would, so `show` (ShowDialog, blocking) returns and
        # this test cannot hang.
        $fired = $false
        $timer = [System.Windows.Threading.DispatcherTimer]::new()
        $timer.Interval = [TimeSpan]::FromMilliseconds(200)
        $timer.add_Tick({
            if (-not $fired) {
                $fired = $true
                $buttonResource.Native.RaiseEvent(
                    [System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            }
            $timer.Stop()
            $appResource.Native.Close()
        })
        $timer.Start()

        Invoke-OtterStatement -Statement ([ShowStmt]::new([VariableExpr]::new('app', 7), 7)) -Environment $env
    }
    finally {
        Set-OtterOutputWriter -Writer $null
    }
    Assert-Lines -Expected @('Hello!') -Actual $collected.ToArray()
}

Test-Otter 'put attaches the existing resource - identity is unchanged, never recreated or copied' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('button', 'helloButton', 2),
        [PutInStmt]::new([VariableExpr]::new('helloButton', 3), [VariableExpr]::new('app', 3), 3)
    )
    $button = $env.Get('helloButton')
    $panel = $env.Get('app').Native.Content
    Assert-True ([object]::ReferenceEquals($panel.Children[0], $button.Native)) 'put must attach the same native object, not a copy'
}

Test-Otter 'repeated puts preserve order in the invisible default container' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('button', 'first', 2),
        [CreateUiResourceStmt]::new('button', 'second', 3),
        [PutInStmt]::new([VariableExpr]::new('first', 4), [VariableExpr]::new('app', 4), 4),
        [PutInStmt]::new([VariableExpr]::new('second', 5), [VariableExpr]::new('app', 5), 5)
    )
    $panel = $env.Get('app').Native.Content
    Assert-True ([object]::ReferenceEquals($panel.Children[0], $env.Get('first').Native)) 'first put must come first'
    Assert-True ([object]::ReferenceEquals($panel.Children[1], $env.Get('second').Native)) 'second put must come second'
}

Test-Otter 'a resource can have only one parent - putting it into a second window is a clean Otter error' {
    Assert-OtterFails -Containing 'already somewhere else' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [CreateUiResourceStmt]::new('window', 'other', 2),
            [CreateUiResourceStmt]::new('button', 'helloButton', 3),
            [PutInStmt]::new([VariableExpr]::new('helloButton', 4), [VariableExpr]::new('app', 4), 4),
            [PutInStmt]::new([VariableExpr]::new('helloButton', 5), [VariableExpr]::new('other', 5), 5)
        )
    }
}

Test-Otter 'putting the same resource twice into the same window is also a clean Otter error, not a raw .NET one' {
    Assert-OtterFails -Containing 'already somewhere else' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [CreateUiResourceStmt]::new('button', 'helloButton', 2),
            [PutInStmt]::new([VariableExpr]::new('helloButton', 3), [VariableExpr]::new('app', 3), 3),
            [PutInStmt]::new([VariableExpr]::new('helloButton', 4), [VariableExpr]::new('app', 4), 4)
        )
    }
}

Test-Otter 'putting into a non-window names the actual kind, never Panel or Grid' {
    Assert-OtterFails -Containing 'not a button' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('button', 'a', 1),
            [CreateUiResourceStmt]::new('button', 'b', 2),
            [PutInStmt]::new([VariableExpr]::new('b', 3), [VariableExpr]::new('a', 3), 3)
        )
    }
}

Test-Otter 'putting a non-UI-resource, or into one, explains itself in Otter terms' {
    Assert-OtterFails -Containing 'this is some text' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('window', 'app', 1),
            [AssignStmt]::new('notAResource', (Lit 'just text'), 2),
            [PutInStmt]::new([VariableExpr]::new('notAResource', 3), [VariableExpr]::new('app', 3), 3)
        )
    }
}

Test-Otter 'showing a non-window names the actual kind' {
    Assert-OtterFails -Containing 'not a button' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('button', 'helloButton', 1),
            [ShowStmt]::new([VariableExpr]::new('helloButton', 2), 2)
        )
    }
}

Test-Otter 'showing a value that is not a UI resource at all explains itself' {
    Assert-OtterFails -Containing 'this is some text' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('notAResource', (Lit 'just text'), 1),
            [ShowStmt]::new([VariableExpr]::new('notAResource', 2), 2)
        )
    }
}

Test-Otter 'an empty window (nothing ever put in it) shows and closes cleanly' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1)
    )
    $appResource = $env.Get('app')
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.add_Tick({ $timer.Stop(); $appResource.Native.Close() })
    $timer.Start()
    Invoke-OtterStatement -Statement ([ShowStmt]::new([VariableExpr]::new('app', 2), 2)) -Environment $env
    # reaching this line at all is the assertion - ShowDialog returned
    Assert-True $true 'an empty window must show and close without error'
}

Test-Otter 'a closed window cannot be shown again - a clean Otter error, not the raw .NET one' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1)
    )
    $appResource = $env.Get('app')
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.add_Tick({ $timer.Stop(); $appResource.Native.Close() })
    $timer.Start()
    Invoke-OtterStatement -Statement ([ShowStmt]::new([VariableExpr]::new('app', 2), 2)) -Environment $env

    Assert-OtterFails -Containing "can't be shown again" -Body {
        Invoke-OtterStatement -Statement ([ShowStmt]::new([VariableExpr]::new('app', 3), 3)) -Environment $env
    }
}


# =================================================================
# D40/D43: has still means data, create still means an external resource
# =================================================================

Test-Otter 'has-built things are unaffected - still ordinary OtterObject' {
    $out = Invoke-TestProgram @(
        [ObjectDefStmt]::new('person', 'thing', @([AssignStmt]::new('name', (Lit 'Jeff'), 2)), 1),
        [SayStmt]::new(@([PropertyAccessExpr]::new('name', [VariableExpr]::new('person', 3), 3)), 3)
    )
    Assert-Lines -Expected @('Jeff') -Actual $out
}

Test-Otter 'a UI resource does not accept dynamic get/set (D41 rule 9, inherited automatically)' {
    # Assert-OtterDynamicKeyTarget checks Test-OtterObject specifically -
    # OtterUiResource is a different class entirely, so this exclusion
    # needed no new code at all. Confirmed, not just assumed.
    Assert-OtterFails -Containing 'a button' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('button', 'helloButton', 1),
            [SetKeyStmt]::new((Lit 'text'), (Lit 'Say Hello'), [VariableExpr]::new('helloButton', 2), 2)
        )
    }
}

Test-Otter 'has configures an existing UI resource without replacing it' {
    $env = New-OtterEnvironment
    Invoke-OtterStatements -Environment $env -Statements @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [ObjectDefStmt]::new('app', 'thing', @(
            [AssignStmt]::new('title', (Lit 'Configured'), 2),
            [AssignStmt]::new('width', (Lit 640), 2)
        ), 2)
    )
    $app = $env.Get('app')
    Assert-True (Test-OtterUiResource $app) 'has must preserve the existing UI resource.'
    Assert-AreEqual -Expected 'Configured' -Actual $app.Native.Title
    Assert-AreEqual -Expected 640 -Actual $app.Native.Width
}

Test-Otter 'has refuses to replace an existing non-UI value' {
    Assert-OtterFails -Containing 'will not replace existing' -Body {
        Invoke-TestProgram @(
            [AssignStmt]::new('score', (Lit 10), 1),
            [ObjectDefStmt]::new('score', 'thing', @([AssignStmt]::new('value', (Lit 20), 2)), 2)
        )
    }
}

Test-Otter 'width full and height full stretch a WPF control to fill available container space' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('button', 'fullBtn', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('fullBtn', 2), 2), [LiteralExpr]::new('full', 2), 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('height', [VariableExpr]::new('fullBtn', 3), 3), [LiteralExpr]::new('full', 3), 3)
    )
    $btn = $res.Env.Get('fullBtn')
    Assert-True (Test-OtterUiResource $btn) 'fullBtn must be a UI resource.'
    Assert-AreEqual -Expected 'Stretch' -Actual $btn.Native.HorizontalAlignment.ToString()
    Assert-AreEqual -Expected 'Stretch' -Actual $btn.Native.VerticalAlignment.ToString()
    Assert-True ([double]::IsNaN($btn.Native.Width)) 'Explicit Width must be NaN to allow stretching.'
    Assert-True ([double]::IsNaN($btn.Native.Height)) 'Explicit Height must be NaN to allow stretching.'

    # Verify reading the property round-trips 'full'
    $readWidth = Invoke-TestProgram @(
        [CreateUiResourceStmt]::new('button', 'btn', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('btn', 2), 2), [LiteralExpr]::new('full', 2), 2),
        [SayStmt]::new(@([PropertyAccessExpr]::new('width', [VariableExpr]::new('btn', 3), 3)), 3)
    )
    Assert-Lines -Expected @('full') -Actual $readWidth
}

Test-Otter 'row with spread distributes children across available container width' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('row', 'spreadRow', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('spreadRow', 2), 2), (Lit 500), 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('spread', [VariableExpr]::new('spreadRow', 3), 3), (Lit $true), 3),
        [CreateUiResourceStmt]::new('button', 'b1', 4),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('b1', 5), 5), (Lit 100), 5),
        [CreateUiResourceStmt]::new('button', 'b2', 6),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('b2', 7), 7), (Lit 100), 7),
        [PutInStmt]::new([VariableExpr]::new('b1', 8), [VariableExpr]::new('spreadRow', 8), 8),
        [PutInStmt]::new([VariableExpr]::new('b2', 9), [VariableExpr]::new('spreadRow', 9), 9)
    )
    $row = $res.Env.Get('spreadRow').Native
    $b1 = $res.Env.Get('b1').Native
    $b2 = $res.Env.Get('b2').Native

    # Measure and arrange the row to verify layout geometry
    $row.Measure([System.Windows.Size]::new(500, 100))
    $row.Arrange([System.Windows.Rect]::new(0, 0, 500, 100))

    $pos1 = $b1.TransformToAncestor($row).Transform([System.Windows.Point]::new(0,0))
    $pos2 = $b2.TransformToAncestor($row).Transform([System.Windows.Point]::new(0,0))

    Assert-AreEqual -Expected 0 -Actual $pos1.X
    Assert-AreEqual -Expected 400 -Actual $pos2.X
}

Test-Otter 'D54: cross-axis align is one property everywhere - a word carries its own axis, not the property name' {
    # A row's cross axis is vertical (top/middle/bottom); a column's
    # cross axis is horizontal (left/center/right). Both go through the
    # SAME 'align' property - this is the exact bug found during the v1
    # audit: an earlier implementation split 'align' into align_h/align_v
    # and routed by property name instead of by the word's own meaning,
    # so "align top" on a row silently did nothing (fell through a
    # horizontal-only switch's default case instead of erroring or
    # working). Verified fixed by checking the actual native properties.
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('row', 'navRow', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('navRow', 2), 2), (Lit 'middle'), 2),
        [CreateUiResourceStmt]::new('button', 'btn', 3),
        [PutInStmt]::new([VariableExpr]::new('btn', 4), [VariableExpr]::new('navRow', 4), 4),
        [CreateUiResourceStmt]::new('column', 'sideCol', 5),
        [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('sideCol', 6), 6), (Lit 'right'), 6),
        [CreateUiResourceStmt]::new('text', 'txt', 7),
        [PutInStmt]::new([VariableExpr]::new('txt', 8), [VariableExpr]::new('sideCol', 8), 8)
    )
    $btn = $res.Env.Get('btn').Native
    $txt = $res.Env.Get('txt').Native
    Assert-AreEqual -Expected 'Center' -Actual $btn.VerticalAlignment.ToString()
    Assert-AreEqual -Expected 'Right' -Actual $txt.HorizontalAlignment.ToString()
}

Test-Otter 'D54: cross-axis align applies to children put in AFTER it was set too' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('row', 'navRow', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('navRow', 2), 2), (Lit 'bottom'), 2),
        [CreateUiResourceStmt]::new('button', 'btn', 3),
        [PutInStmt]::new([VariableExpr]::new('btn', 4), [VariableExpr]::new('navRow', 4), 4)
    )
    Assert-AreEqual -Expected 'Bottom' -Actual $res.Env.Get('btn').Native.VerticalAlignment.ToString()
}

Test-Otter 'D54: main-axis align on a row positions the child GROUP, not each child individually' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('row', 'toolbar', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('toolbar', 2), 2), (Lit 500), 2),
        [CreateUiResourceStmt]::new('button', 'b1', 3),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('b1', 4), 4), (Lit 100), 4),
        [CreateUiResourceStmt]::new('button', 'b2', 5),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('b2', 6), 6), (Lit 100), 6),
        [PutInStmt]::new([VariableExpr]::new('b1', 7), [VariableExpr]::new('toolbar', 7), 7),
        [PutInStmt]::new([VariableExpr]::new('b2', 8), [VariableExpr]::new('toolbar', 8), 8),
        [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('toolbar', 9), 9), (Lit 'right'), 9)
    )
    $row = $res.Env.Get('toolbar').Native
    $b1 = $res.Env.Get('b1').Native
    $b2 = $res.Env.Get('b2').Native
    $row.Measure([System.Windows.Size]::new(500, 100))
    $row.Arrange([System.Windows.Rect]::new(0, 0, 500, 100))
    $pos1 = $b1.TransformToAncestor($row).Transform([System.Windows.Point]::new(0, 0))
    $pos2 = $b2.TransformToAncestor($row).Transform([System.Windows.Point]::new(0, 0))
    # 500 total - 200 content = 300 leftover, all pushed before the group for 'right'
    Assert-AreEqual -Expected 300 -Actual $pos1.X
    Assert-AreEqual -Expected 400 -Actual $pos2.X
}

Test-Otter 'D54: same-axis align conflict is an error - only one alignment per axis' {
    Assert-OtterFails -Containing 'only one alignment is allowed per axis' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('row', 'r', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('r', 2), 2), (Lit 'left'), 2),
            [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('r', 3), 3), (Lit 'right'), 3)
        )
    }
    Assert-OtterFails -Containing 'only one alignment is allowed per axis' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('row', 'r', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('r', 2), 2), (Lit 'top'), 2),
            [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('r', 3), 3), (Lit 'bottom'), 3)
        )
    }
}

Test-Otter 'D54: spread and main-axis align conflict in both directions' {
    Assert-OtterFails -Containing 'conflicts with' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('row', 'r', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('spread', [VariableExpr]::new('r', 2), 2), (Lit $true), 2),
            [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('r', 3), 3), (Lit 'center'), 3)
        )
    }
    Assert-OtterFails -Containing 'conflicts with' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('column', 'c', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('c', 2), 2), (Lit 'top'), 2),
            [AssignStmt]::new([PropertyAccessExpr]::new('spread', [VariableExpr]::new('c', 3), 3), (Lit $true), 3)
        )
    }
}

Test-Otter 'D54: spread and cross-axis align compose validly - different axes, different slots' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('row', 'toolbar', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('toolbar', 2), 2), (Lit 500), 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('spread', [VariableExpr]::new('toolbar', 3), 3), (Lit $true), 3),
        [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('toolbar', 4), 4), (Lit 'middle'), 4),
        [CreateUiResourceStmt]::new('button', 'btn', 5),
        [PutInStmt]::new([VariableExpr]::new('btn', 6), [VariableExpr]::new('toolbar', 6), 6)
    )
    Assert-AreEqual -Expected 'Center' -Actual $res.Env.Get('btn').Native.VerticalAlignment.ToString()
}

Test-Otter 'D54: two different-axis alignments compose into a corner - valid, not a conflict' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('row', 'toolbar', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('toolbar', 2), 2), (Lit 500), 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('toolbar', 3), 3), (Lit 'top'), 3),
        [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('toolbar', 4), 4), (Lit 'right'), 4),
        [CreateUiResourceStmt]::new('button', 'btn', 5),
        [AssignStmt]::new([PropertyAccessExpr]::new('width', [VariableExpr]::new('btn', 6), 6), (Lit 100), 6),
        [PutInStmt]::new([VariableExpr]::new('btn', 7), [VariableExpr]::new('toolbar', 7), 7)
    )
    $row = $res.Env.Get('toolbar').Native
    $btn = $res.Env.Get('btn').Native
    Assert-AreEqual -Expected 'Top' -Actual $btn.VerticalAlignment.ToString()
    $row.Measure([System.Windows.Size]::new(500, 100))
    $row.Arrange([System.Windows.Rect]::new(0, 0, 500, 100))
    $pos = $btn.TransformToAncestor($row).Transform([System.Windows.Point]::new(0, 0))
    Assert-AreEqual -Expected 400 -Actual $pos.X
}

Test-Otter 'an unrecognized alignment word is a clean Otter error naming the valid options' {
    Assert-OtterFails -Containing 'A row has no alignment called "diagonal"' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('row', 'r', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('r', 2), 2), (Lit 'diagonal'), 2)
        )
    }
}

Test-Otter 'a vertical alignment word on a plain control (no axis of its own) is a clean error, not a silent default' {
    Assert-OtterFails -Containing 'can only align left, center, or right' -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('button', 'btn', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('align', [VariableExpr]::new('btn', 2), 2), (Lit 'top'), 2)
        )
    }
}


# =================================================================
# D55 - Desktop Task List Ergonomics (padding, placeholder, events)
# =================================================================

Test-Otter 'padding reads as gone when not set' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('row', 'r', 2),
        [CreateUiResourceStmt]::new('column', 'c', 3)
    )
    $app = $res.Env.Get('app')
    $r = $res.Env.Get('r')
    $c = $res.Env.Get('c')
    Assert-AreEqual -Expected $null -Actual (Get-OtterUiProperty -Resource $app -Property 'padding')
    Assert-AreEqual -Expected $null -Actual (Get-OtterUiProperty -Resource $r -Property 'padding')
    Assert-AreEqual -Expected $null -Actual (Get-OtterUiProperty -Resource $c -Property 'padding')
}

Test-Otter 'padding on window wraps content in a border with padding' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('padding', [VariableExpr]::new('app', 2), 2), (Lit 20), 2),
        [CreateUiResourceStmt]::new('button', 'btn', 3),
        [PutInStmt]::new([VariableExpr]::new('btn', 4), [VariableExpr]::new('app', 4), 4)
    )
    $app = $res.Env.Get('app')
    Assert-AreEqual -Expected 20 -Actual (Get-OtterUiProperty -Resource $app -Property 'padding')
    $border = $app.Native.Content
    Assert-AreEqual -Expected 'Border' -Actual $border.GetType().Name
    Assert-AreEqual -Expected 20 -Actual $border.Padding.Top
    Assert-AreEqual -Expected 20 -Actual $border.Padding.Left
}

Test-Otter 'padding on row wraps panel in a border with padding' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('row', 'r', 2),
        [AssignStmt]::new([PropertyAccessExpr]::new('padding', [VariableExpr]::new('r', 3), 3), (Lit 16), 3),
        [CreateUiResourceStmt]::new('button', 'btn', 4),
        [PutInStmt]::new([VariableExpr]::new('btn', 5), [VariableExpr]::new('r', 5), 5),
        [PutInStmt]::new([VariableExpr]::new('r', 6), [VariableExpr]::new('app', 6), 6)
    )
    $r = $res.Env.Get('r')
    Assert-AreEqual -Expected 16 -Actual (Get-OtterUiProperty -Resource $r -Property 'padding')
    $app = $res.Env.Get('app')
    $panel = if ($app.Native.Content -is [System.Windows.Controls.Border]) { $app.Native.Content.Child } else { $app.Native.Content }
    Assert-AreEqual -Expected 1 -Actual $panel.Children.Count
    $wrapper = $panel.Children[0]
    Assert-AreEqual -Expected 'Border' -Actual $wrapper.GetType().Name
    Assert-AreEqual -Expected 16 -Actual $wrapper.Padding.Top
    Assert-AreEqual -Expected $r.Native -Actual $wrapper.Child
}

Test-Otter 'padding set AFTER put still wraps correctly in parent' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('window', 'app', 1),
        [CreateUiResourceStmt]::new('column', 'c', 2),
        [PutInStmt]::new([VariableExpr]::new('c', 3), [VariableExpr]::new('app', 3), 3),
        [AssignStmt]::new([PropertyAccessExpr]::new('padding', [VariableExpr]::new('c', 4), 4), (Lit 24), 4)
    )
    $c = $res.Env.Get('c')
    Assert-AreEqual -Expected 24 -Actual (Get-OtterUiProperty -Resource $c -Property 'padding')
    $app = $res.Env.Get('app')
    $panel = if ($app.Native.Content -is [System.Windows.Controls.Border]) { $app.Native.Content.Child } else { $app.Native.Content }
    Assert-AreEqual -Expected 1 -Actual $panel.Children.Count
    $wrapper = $panel.Children[0]
    Assert-AreEqual -Expected 'Border' -Actual $wrapper.GetType().Name
    Assert-AreEqual -Expected 24 -Actual $wrapper.Padding.Bottom
    Assert-AreEqual -Expected $c.Native -Actual $wrapper.Child
}

Test-Otter 'negative padding is rejected with an Otter diagnostic' {
    Assert-OtterFails -Containing "The padding of a row can't be negative" -Body {
        Invoke-TestProgram @(
            [CreateUiResourceStmt]::new('row', 'r', 1),
            [AssignStmt]::new([PropertyAccessExpr]::new('padding', [VariableExpr]::new('r', 2), 2), (Lit -5), 2)
        )
    }
}

Test-Otter 'placeholder on text box sets watermark and preserves empty text of box' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('text box', 'box', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('placeholder', [VariableExpr]::new('box', 2), 2), (Lit 'Add a new task...'), 2)
    )
    $box = $res.Env.Get('box')
    Assert-AreEqual -Expected 'Add a new task...' -Actual (Get-OtterUiProperty -Resource $box -Property 'placeholder')
    # Text of box must return empty string, NEVER the placeholder text!
    Assert-AreEqual -Expected '' -Actual (Get-OtterUiProperty -Resource $box -Property 'text')
    # VisualBrush watermark is on Background
    Assert-AreEqual -Expected 'VisualBrush' -Actual $box.Native.Background.GetType().Name
}

Test-Otter 'typing in text box hides watermark and clearing restores watermark' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('text box', 'box', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('placeholder', [VariableExpr]::new('box', 2), 2), (Lit 'Enter name'), 2)
    )
    $box = $res.Env.Get('box')
    Assert-AreEqual -Expected 'VisualBrush' -Actual $box.Native.Background.GetType().Name

    # Simulate user typing
    $box.Native.Text = 'Alice'
    Assert-AreEqual -Expected 'Alice' -Actual (Get-OtterUiProperty -Resource $box -Property 'text')
    Assert-AreEqual -Expected $null -Actual $box.Native.Background

    # Clear text via Otter property assignment
    Set-OtterUiProperty -Resource $box -Property 'text' -Value '' -Line 3
    Assert-AreEqual -Expected '' -Actual (Get-OtterUiProperty -Resource $box -Property 'text')
    Assert-AreEqual -Expected 'VisualBrush' -Actual $box.Native.Background.GetType().Name
}

Test-Otter 'end-to-end Task List dogfood: dynamic child insertion into padded column' {
    $res = Invoke-TestProgramWithEnv @(
        [CreateUiResourceStmt]::new('column', 'taskList', 1),
        [AssignStmt]::new([PropertyAccessExpr]::new('padding', [VariableExpr]::new('taskList', 2), 2), (Lit 12), 2),
        [CreateUiResourceStmt]::new('button', 'addButton', 3),
        [CreateUiResourceStmt]::new('text box', 'taskInput', 4),
        [AssignStmt]::new([PropertyAccessExpr]::new('placeholder', [VariableExpr]::new('taskInput', 5), 5), (Lit 'New task'), 5),
        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('taskInput', 6), 6), (Lit 'Buy groceries'), 6),
        [WhenStmt]::new([VariableExpr]::new('addButton', 7), 'clicked', @(
            [AssignStmt]::new('task', [PropertyAccessExpr]::new('text', [VariableExpr]::new('taskInput', 8), 8), 8),
            [IfStmt]::new(
                @([IfBranch]::new(
                    [ComparisonExpr]::new([VariableExpr]::new('task', 9), [CompareOp]::NotEqual, (Lit ''), 9),
                    @(
                        [CreateUiResourceStmt]::new('text', 'item', 10),
                        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('item', 11), 11), [VariableExpr]::new('task', 11), 11),
                        [PutInStmt]::new([VariableExpr]::new('item', 12), [VariableExpr]::new('taskList', 12), 12),
                        [AssignStmt]::new([PropertyAccessExpr]::new('text', [VariableExpr]::new('taskInput', 13), 13), (Lit ''), 13)
                    )
                )),
                $null,
                9
            )
        ), 7)
    )

    $btn = $res.Env.Get('addButton')
    $list = $res.Env.Get('taskList')
    $input = $res.Env.Get('taskInput')

    Assert-AreEqual -Expected 0 -Actual $list.Native.Children.Count
    Assert-AreEqual -Expected 'Buy groceries' -Actual (Get-OtterUiProperty -Resource $input -Property 'text')

    # Click Add
    $btn.Native.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))

    Assert-AreEqual -Expected 1 -Actual $list.Native.Children.Count
    Assert-AreEqual -Expected 'Buy groceries' -Actual $list.Native.Children[0].Text
    Assert-AreEqual -Expected '' -Actual (Get-OtterUiProperty -Resource $input -Property 'text')
    Assert-AreEqual -Expected 'VisualBrush' -Actual $input.Native.Background.GetType().Name
}

Complete-OtterTests

