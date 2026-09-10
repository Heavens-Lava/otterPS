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

Complete-OtterTests
