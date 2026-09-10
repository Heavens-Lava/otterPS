using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1

# Otter.UI.psm1
#
# D44: external UI resources. Everything WPF-specific lives in this ONE
# file, on purpose - "Otter semantics must not expose WPF-specific class
# names or APIs" (D44, principle 5) is enforced by FILE STRUCTURE here, not
# by discipline alone. No other module ever mentions System.Windows.*, and
# nothing outside this file needs to.
#
# D43 already settled the boundary: a UI control is an external/domain
# resource, created with `create`, never with `has`. D44 settles what that
# produces and how its identity works:
#
#   - create button into helloButton   ->   a REAL WPF Button exists NOW,
#     not a description that becomes real later
#   - helloButton keeps the SAME identity for its whole lifetime - reading
#     it twice never clones it, and attaching it to a window later (D47)
#     reuses this exact object, it does not recreate it
#
# What this file does NOT do, on purpose:
#   - no property translation (text of helloButton is "...") - that is D45
#   - no layout/attachment (add helloButton to mainWindow) - that is D47
#   - no events (when helloButton is clicked) - that is D46
#   - no control kinds beyond the small D44 proving set (window, button,
#     text, text box) - more kinds follow the exact same pattern later


# ===============================================================
# THE WRAPPER - never a raw WPF object in an Otter variable
# ===============================================================
#
#     helloButton
#         |
#         v
#     OtterUiResource
#         Kind:     "button"
#         Provider: "wpf"
#         Native:   the real System.Windows.Controls.Button
#
# Kept as a wrapper, not the raw WPF object directly, so a later provider
# (web: Provider = "web", Native = some HTML element handle) changes
# nothing about what `helloButton` means at the Otter language level -
# exactly Jeff's point in freezing this shape now.

class OtterUiResource {
    [string]$Kind        # "button", "window", "text", "text box", ...
    [string]$Provider    # "wpf" - the only provider D44 implements
    [object]$Native      # the real, live WPF object. Never printed, never
                          # named in an error message, never reflected on
                          # from outside this file.

    OtterUiResource([string]$kind, [string]$provider, [object]$native) {
        $this.Kind = $kind
        $this.Provider = $provider
        $this.Native = $native
    }
}

function Test-OtterUiResource {
    param([object]$Value)
    return $Value -is [OtterUiResource]
}


# ===============================================================
# THE PROVIDER - the only place System.Windows.* is allowed to appear
# ===============================================================

$script:OtterWpfLoaded = $false

function Initialize-OtterWpfProvider {
    if ($script:OtterWpfLoaded) { return }
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        Add-Type -AssemblyName WindowsBase -ErrorAction Stop
    }
    catch {
        throw [OtterError]::new(
            'Otter could not start its UI provider. WPF may not be available on this system.',
            0, 'runtime')
    }
    $script:OtterWpfLoaded = $true
}

# One control kind, one line, one WPF type. Adding a new kind later - D44's
# own proving set is deliberately small - means adding one line here, not
# redesigning anything.
$script:OtterWpfKinds = @{
    'window'   = { [System.Windows.Window]::new() }
    'button'   = { [System.Windows.Controls.Button]::new() }
    'text'     = { [System.Windows.Controls.TextBlock]::new() }
    'text box' = { [System.Windows.Controls.TextBox]::new() }
}

# create <kind> into <name>
#
# Creates the REAL native object immediately - this is the whole point of
# D44's lifecycle decision. Nothing here is a description waiting to be
# materialized later.
function New-OtterUiResourceValue {
    param([string]$Kind, [int]$Line)

    Initialize-OtterWpfProvider

    if (-not $script:OtterWpfKinds.ContainsKey($Kind)) {
        $known = ($script:OtterWpfKinds.Keys | Sort-Object) -join ', '
        throw [OtterError]::new(
            "I don't know how to create a $Kind yet.",
            $Line, 'runtime', 0, $null, "Otter currently knows: $known")
    }

    $native = & $script:OtterWpfKinds[$Kind]
    return [OtterUiResource]::new($Kind, 'wpf', $native)
}


# ===============================================================
# PROPERTIES (D45)
# ===============================================================
#
#     text of helloButton is "Say Hello"    - button.Content, not button.Text
#     text of nameBox is "..."              - textBox.Text
#     title of app is "My App"              - window.Title
#     width of app is 500                   - window.Width, a real number
#
# "What does 'text' mean for a button" is provider-specific knowledge - the
# same reasoning that put the create-kind lookup table in this file puts
# this table here too, not in the generic interpreter. Reading OR writing
# through Otter's ordinary "property of thing" grammar (D19) never touches
# WPF directly; it always goes through Get-/Set-OtterUiProperty below, which
# are the only functions outside object construction itself allowed to read
# or write a native WPF property.
#
# Type is the validation/coercion strategy, not a WPF concept:
#   'text'   - any Otter value is accepted and rendered through
#              Format-OtterValue, the same conversion "say" already uses.
#              text of helloButton is 5 sets it to "5", it does not error -
#              consistent with how say already treats every value.
#   'number' - the Otter value must already BE a number. Checked and
#              converted BEFORE the native object is ever touched, so a
#              type mismatch is always a clean Otter error, never the raw
#              .NET exception WPF itself throws (verified before writing
#              this: assigning text to Window.Width throws
#              SetValueInvocationException naming "System.Double" directly
#              in its message - exactly what D44 principle 5 forbids
#              reaching a Otter user).
$script:OtterUiProperties = @{
    'button' = @{
        'text' = @{ Native = 'Content'; Type = 'text' }
    }
    'text box' = @{
        'text' = @{ Native = 'Text'; Type = 'text' }
    }
    'text' = @{
        'text' = @{ Native = 'Text'; Type = 'text' }
    }
    'window' = @{
        'title'  = @{ Native = 'Title'; Type = 'text' }
        'width'  = @{ Native = 'Width'; Type = 'number' }
        'height' = @{ Native = 'Height'; Type = 'number' }
    }
}

# Every property in the table above is both readable and writable on its
# real WPF type - verified directly, not assumed - so there is no
# read/write asymmetry to design around for this proving set. The table
# shape (one entry per property, not two) already allows a future
# read-only property later without changing how this function is called;
# it would just check a flag this entry does not need yet.
function Get-OtterUiPropertyMapping {
    param([string]$Kind, [string]$Property, [int]$Line)

    if (-not $script:OtterUiProperties.ContainsKey($Kind)) {
        throw [OtterError]::new(
            "A $Kind has no properties Otter knows about yet.", $Line, 'runtime')
    }

    $forKind = $script:OtterUiProperties[$Kind]
    if (-not $forKind.ContainsKey($Property)) {
        $known = ($forKind.Keys | Sort-Object) -join ', '
        throw [OtterError]::new(
            "A $Kind has no property called `"$Property`".",
            $Line, 'runtime', 0, $null, "A $Kind has: $known")
    }

    return $forKind[$Property]
}

# Self-contained on purpose: Assert-OtterNumber (the interpreter's version)
# lives in Otter.Interpreter.psm1, which imports THIS file - importing it
# back would invert the layering D44 already established. Test-OtterNumeric
# and ConvertTo-OtterNumber (Otter.Runtime.psm1, the foundation layer) are
# reused directly instead.
function Assert-OtterUiNumber {
    param([object]$Value, [string]$Property, [string]$Kind, [int]$Line)

    if (Test-OtterNumeric $Value) { return (ConvertTo-OtterNumber $Value) }

    $shown = Format-OtterValue -Value $Value
    if ($Value -is [string]) { $shown = '"' + $Value + '"' }
    throw [OtterError]::new(
        "I expected a number for the $Property of this $Kind but got $shown.",
        $Line, 'runtime')
}

function Get-OtterUiProperty {
    param([OtterUiResource]$Resource, [string]$Property, [int]$Line)

    $mapping = Get-OtterUiPropertyMapping -Kind $Resource.Kind -Property $Property -Line $Line
    $raw = $Resource.Native.($mapping.Native)

    # Both directions already produce/consume exactly the .NET types Otter
    # itself uses - a WPF string IS an Otter string, a WPF double IS an
    # Otter number - so reading needs no conversion at all. gone (D22) for
    # an unset text property, matching how an empty Otter value already
    # prints and compares, rather than inventing a UI-specific "empty" idea.
    if ($mapping.Type -eq 'text' -and $null -eq $raw) { return $null }
    return $raw
}

function Set-OtterUiProperty {
    param([OtterUiResource]$Resource, [string]$Property, [object]$Value, [int]$Line)

    $mapping = Get-OtterUiPropertyMapping -Kind $Resource.Kind -Property $Property -Line $Line

    if ($mapping.Type -eq 'number') {
        $number = Assert-OtterUiNumber -Value $Value -Property $Property -Kind $Resource.Kind -Line $Line
        $Resource.Native.($mapping.Native) = $number
        return
    }

    # 'text' - the same conversion "say" already applies to every value,
    # so this can never throw the way the numeric path can.
    $Resource.Native.($mapping.Native) = (Format-OtterValue -Value $Value)
}


# ===============================================================
# EVENTS (D46) - registration only
# ===============================================================
#
#     when helloButton is clicked
#         say "Hello"
#     .
#
# Same shape as the property table above, for the same reason: "what does
# 'clicked' mean for a button" is provider-specific knowledge. Otter only
# ever sees the left-hand word; the CLR event name is a WPF-provider
# implementation detail.
#
# Subscription is ONE generic function for every kind/event, not one path
# per event - verified directly that .NET reflection subscribes correctly
# even though Click/TextChanged/Closed are three different delegate types
# (RoutedEventHandler, TextChangedEventHandler, plain EventHandler): the
# event's own EventHandlerType is read via reflection and the handler
# script block is cast to it, so no per-event-type code is needed here or
# for any future event this table gains.
$script:OtterUiEvents = @{
    'button'   = @{ 'clicked' = 'Click' }
    'text box' = @{ 'changed' = 'TextChanged' }
    'window'   = @{ 'closed'  = 'Closed' }
}

function Get-OtterUiEventMapping {
    param([string]$Kind, [string]$EventName, [int]$Line)

    if (-not $script:OtterUiEvents.ContainsKey($Kind)) {
        throw [OtterError]::new(
            "A $Kind has no events Otter knows about yet.", $Line, 'runtime')
    }

    $forKind = $script:OtterUiEvents[$Kind]
    if (-not $forKind.ContainsKey($EventName)) {
        $known = ($forKind.Keys | Sort-Object) -join ', '
        throw [OtterError]::new(
            "A $Kind has no event called `"$EventName`".",
            $Line, 'runtime', 0, $null, "A $Kind has: $known")
    }

    return $forKind[$EventName]
}

# Registers $Handler (a scriptblock taking no arguments - D46 carries no
# event payload) to run whenever the native event fires. The handler is
# responsible for its own environment closure; this function only wires
# the native subscription, exactly like Get-/Set-OtterUiProperty only
# translate the property name, not the value semantics.
function Add-OtterUiEventHandler {
    param([OtterUiResource]$Resource, [string]$EventName, [scriptblock]$Handler, [int]$Line)

    $clrName = Get-OtterUiEventMapping -Kind $Resource.Kind -EventName $EventName -Line $Line
    $eventInfo = $Resource.Native.GetType().GetEvent($clrName)
    $typedHandler = $Handler -as $eventInfo.EventHandlerType
    $eventInfo.AddEventHandler($Resource.Native, $typedHandler)
}


# ===============================================================
# LAYOUT AND SHOW (D47) - the smallest possible container and message
# loop, not a general layout system.
# ===============================================================
#
#     put helloButton in app
#     show app
#
# A window's put-in children live in an Otter-invisible, provider-managed
# StackPanel (default vertical stacking) - created lazily on the first
# put. Nothing outside this function ever creates, names, or reads that
# panel; Otter code never sees it, the same way it never sees Window's
# other backing fields. `put` attaches the EXISTING resource - it never
# recreates or copies it (D44 identity guarantee still holds). Repeated
# puts preserve order because Children.Add always appends.
#
# A resource can have only one parent. WPF itself already enforces this
# (verified: a second Children.Add of the same element throws
# InvalidOperationException, wrapped by PowerShell as a
# MethodInvocationException) - caught and translated here so no .NET
# exception text ever reaches an Otter user.
function Add-OtterUiChild {
    param([OtterUiResource]$Container, [OtterUiResource]$Item, [int]$Line)

    if ($Container.Kind -ne 'window') {
        throw [OtterError]::new(
            "I can only put things in a window right now, not a $($Container.Kind).", $Line, 'runtime')
    }

    if ($null -eq $Container.Native.Content) {
        $Container.Native.Content = [System.Windows.Controls.StackPanel]::new()
    }
    $panel = $Container.Native.Content

    try {
        [void]$panel.Children.Add($Item.Native)
    }
    catch {
        throw [OtterError]::new(
            "A $($Item.Kind) can only be in one place at a time, and this one is already somewhere else.",
            $Line, 'runtime')
    }
}

# show app
#
# Modal only for D47: blocks until the window closes, then returns.
# Showing an empty window (nothing ever put in it) is valid - verified
# directly, WPF raises no error for that. A window that has already been
# closed cannot be shown again - verified WPF itself throws
# InvalidOperationException for this too; translated the same way.
function Show-OtterUiResource {
    param([OtterUiResource]$Resource, [int]$Line)

    if ($Resource.Kind -ne 'window') {
        throw [OtterError]::new(
            "I can only show a window right now, not a $($Resource.Kind).", $Line, 'runtime')
    }

    try {
        [void]$Resource.Native.ShowDialog()
    }
    catch {
        throw [OtterError]::new(
            "This window has already been closed, so it can't be shown again.", $Line, 'runtime')
    }
}


Export-ModuleMember -Function `
    Test-OtterUiResource, New-OtterUiResourceValue, Initialize-OtterWpfProvider, `
    Get-OtterUiProperty, Set-OtterUiProperty, Add-OtterUiEventHandler, `
    Add-OtterUiChild, Show-OtterUiResource
