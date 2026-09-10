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
$script:OtterUiSpacing = @{}
$script:OtterUiDimensionFull = @{}

function Get-OtterUiSpacingKey {
    param([OtterUiResource]$Resource)
    return [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Resource.Native).ToString()
}

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
    # Controls default to content-sized widths in Otter.  WPF's default
    # Stretch behavior makes a simple button or label fill its parent, which
    # is surprising for beginner-facing programs; explicit width still wins.
    'button'   = { $control = [System.Windows.Controls.Button]::new(); $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left; $control }
    'text'     = { $control = [System.Windows.Controls.TextBlock]::new(); $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left; $control }
    'text box' = { $control = [System.Windows.Controls.TextBox]::new(); $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left; $control }
    'row'      = { $panel = [System.Windows.Controls.StackPanel]::new(); $panel.Orientation = [System.Windows.Controls.Orientation]::Horizontal; $panel }
    'column'   = { $panel = [System.Windows.Controls.StackPanel]::new(); $panel.Orientation = [System.Windows.Controls.Orientation]::Vertical; $panel }
    # D53: vertical-scroll-first, matching ScrollViewer's own real
    # defaults - Vertical=Visible, Horizontal=Disabled already, out of
    # the box. Overridden to Auto (not WPF's raw Visible) so an empty or
    # non-overflowing scroll shows no scrollbar at all, the same
    # "nicer default than raw WPF" instinct already behind the
    # HorizontalAlignment override above. A scroll with no explicit
    # height set will NOT scroll - verified directly: inside Otter's
    # StackPanel-based window root, an unbounded ScrollViewer just grows
    # to fit all its content (ScrollableHeight stayed 0). This is not
    # something Otter works around with an implicit default height -
    # that would be magic that varies unpredictably by provider. A
    # scroll region only becomes scrollable once it has a bound.
    'scroll'   = {
        $control = [System.Windows.Controls.ScrollViewer]::new()
        $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $control.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
        $control.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Disabled
        $control
    }
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
# D48: width/height/background/foreground apply uniformly to all four
# kinds - verified via reflection that Window, Button, TextBox, and even
# TextBlock (which isn't a Control) each define real Width/Height
# (System.Double) and Background/Foreground (System.Windows.Media.Brush)
# properties of their own. `spacing` is window-only and synthetic - see
# Get-/Set-OtterUiSpacing below; it has no Native entry because it never
# reads or writes a single native property directly.
$script:OtterUiProperties = @{
    'button' = @{
        'text'       = @{ Native = 'Content'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
    }
    'text box' = @{
        'text'       = @{ Native = 'Text'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
    }
    'text' = @{
        'text'       = @{ Native = 'Text'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
    }
    'window' = @{
        'title'      = @{ Native = 'Title'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
        'spacing'    = @{ Type = 'spacing' }
    }
    'row' = @{
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'spacing'    = @{ Type = 'spacing' }
    }
    'column' = @{
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'spacing'    = @{ Type = 'spacing' }
    }
    # D53: no spacing - scroll owns exactly one child (a ContentControl,
    # like window itself before D47's implicit panel), so "distribute
    # multiple children apart" is meaningless here.
    'scroll' = @{
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
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
#
# D45 maintenance fix (found during D48 investigation): every numeric UI
# property so far (width, height, and now spacing) is a size, and WPF
# itself throws a raw ArgumentException naming "Width" directly for a
# negative value - verified, and previously unguarded here. Rejected
# BEFORE the native object is ever touched, same discipline as the
# not-a-number case below. Zero remains valid.
function Assert-OtterUiNumber {
    param([object]$Value, [string]$Property, [string]$Kind, [int]$Line)

    if (-not (Test-OtterNumeric $Value)) {
        $shown = Format-OtterValue -Value $Value
        if ($Value -is [string]) { $shown = '"' + $Value + '"' }
        throw [OtterError]::new(
            "I expected a number for the $Property of this $Kind but got $shown.",
            $Line, 'runtime')
    }

    $number = ConvertTo-OtterNumber $Value
    if ($number -lt 0) {
        throw [OtterError]::new(
            "The $Property of a $Kind can't be negative, but I got $number.",
            $Line, 'runtime')
    }

    return $number
}

# D48: named colors ("blue") and hex colors ("#3366FF") go through the
# exact same BrushConverter API - verified directly, no named-vs-hex
# branching needed anywhere. An invalid string throws a real
# System.FormatException - caught here so "notacolor" never reaches an
# Otter user as .NET exception text. Cached lazily (not at module load
# time) so this file never assumes PresentationCore is already loaded;
# by the time any property write can happen, Initialize-OtterWpfProvider
# already ran as part of creating the resource itself.
$script:OtterUiBrushConverter = $null

function Assert-OtterUiColor {
    param([object]$Value, [string]$Property, [string]$Kind, [int]$Line)

    if ($null -eq $script:OtterUiBrushConverter) {
        $script:OtterUiBrushConverter = [System.Windows.Media.BrushConverter]::new()
    }

    $text = Format-OtterValue -Value $Value
    try {
        return $script:OtterUiBrushConverter.ConvertFromString($text)
    }
    catch {
        throw [OtterError]::new(
            "I don't understand the color `"$text`".", $Line, 'runtime')
    }
}

function Get-OtterUiProperty {
    param([OtterUiResource]$Resource, [string]$Property, [int]$Line)

    $mapping = Get-OtterUiPropertyMapping -Kind $Resource.Kind -Property $Property -Line $Line

    # spacing has no single Native property to read - see Get-OtterUiSpacing.
    if ($mapping.Type -eq 'spacing') {
        return (Get-OtterUiSpacing -Window $Resource)
    }

    $fullKey = (Get-OtterUiSpacingKey $Resource) + "_$Property"
    if ($script:OtterUiDimensionFull.ContainsKey($fullKey)) {
        return 'full'
    }

    $raw = $Resource.Native.($mapping.Native)

    # A color always round-trips as a hex string ("#FF3366FF"), never the
    # raw WPF Brush object - verified every color this provider ever sets
    # IS a SolidColorBrush, so .Color.ToString() is always safe here. A
    # brush Otter never set (some other theme-provided brush type) reads
    # as gone rather than guessing at a text form for it.
    if ($mapping.Type -eq 'color') {
        if ($raw -is [System.Windows.Media.SolidColorBrush]) { return $raw.Color.ToString() }
        return $null
    }

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

    if ($mapping.Type -eq 'spacing') {
        Set-OtterUiSpacing -Window $Resource -Value $Value -Line $Line
        return
    }

    if ($mapping.Type -eq 'number') {
        $fullKey = (Get-OtterUiSpacingKey $Resource) + "_$Property"
        if ($Property -in @('width', 'height') -and $Value -eq 'full') {
            $script:OtterUiDimensionFull[$fullKey] = $true
            if ($Property -eq 'width') {
                if ($Resource.Kind -eq 'window') {
                    $Resource.Native.Width = [System.Windows.SystemParameters]::WorkArea.Width
                } else {
                    $Resource.Native.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
                    $Resource.Native.Width = [double]::NaN
                }
            } else {
                if ($Resource.Kind -eq 'window') {
                    $Resource.Native.Height = [System.Windows.SystemParameters]::WorkArea.Height
                } else {
                    $Resource.Native.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
                    $Resource.Native.Height = [double]::NaN
                }
            }
            return
        }
        $number = Assert-OtterUiNumber -Value $Value -Property $Property -Kind $Resource.Kind -Line $Line
        $script:OtterUiDimensionFull.Remove($fullKey)
        if ($Property -eq 'width' -and $Resource.Kind -ne 'window') {
            $Resource.Native.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        } elseif ($Property -eq 'height' -and $Resource.Kind -ne 'window') {
            $Resource.Native.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
        }
        $Resource.Native.($mapping.Native) = $number
        return
    }

    if ($mapping.Type -eq 'color') {
        $brush = Assert-OtterUiColor -Value $Value -Property $Property -Kind $Resource.Kind -Line $Line
        $Resource.Native.($mapping.Native) = $brush
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
#
# The lazily-created panel is shared with Set-OtterUiSpacing below, which
# also needs to read/create it - factored out so there is exactly one
# place that ever creates it.
function Get-OtterUiContainerPanel {
    param([OtterUiResource]$Container)

    if ($Container.Kind -eq 'window') {
        if ($null -eq $Container.Native.Content) {
            $Container.Native.Content = [System.Windows.Controls.StackPanel]::new()
        }
        return $Container.Native.Content
    }

    return $Container.Native
}

# put fileList in fileArea                                        (D53)
#
# scroll is a ContentControl (like Window), not a panel - exactly one
# child, set via .Content, never via a Children collection. Verified
# directly that .Content does NOT protect itself the way Children.Add
# does for window/row/column - it neither throws on a second set on the
# SAME container (silently replaces) nor on attaching an element that is
# ALREADY parented somewhere else entirely (silently steals it away from
# its real parent). Both are checked explicitly here, before touching
# the native object, so neither silent failure mode can happen through
# Otter's put - the one-parent rule window/row/column get for free from
# WPF, scroll has to enforce itself.
function Add-OtterUiScrollChild {
    param([OtterUiResource]$Container, [OtterUiResource]$Item, [int]$Line)

    if ($null -ne $Container.Native.Content) {
        throw [OtterError]::new(
            'A scroll can only hold one thing. Put a column or row in it first if you need more than one.',
            $Line, 'runtime')
    }
    if ($null -ne $Item.Native.Parent) {
        throw [OtterError]::new(
            "A $($Item.Kind) can only be in one place at a time, and this one is already somewhere else.",
            $Line, 'runtime')
    }
    $Container.Native.Content = $Item.Native
}

function Add-OtterUiChild {
    param([OtterUiResource]$Container, [OtterUiResource]$Item, [int]$Line)

    if ($Container.Kind -eq 'scroll') {
        Add-OtterUiScrollChild -Container $Container -Item $Item -Line $Line
        return
    }

    if ($Container.Kind -notin @('window', 'row', 'column')) {
        throw [OtterError]::new(
            "I can only put things in a window, row, column, or scroll, not a $($Container.Kind).", $Line, 'runtime')
    }

    $panel = Get-OtterUiContainerPanel -Container $Container

    try {
        [void]$panel.Children.Add($Item.Native)
    }
    catch {
        throw [OtterError]::new(
            "A $($Item.Kind) can only be in one place at a time, and this one is already somewhere else.",
            $Line, 'runtime')
    }

    # D48: a child put in AFTER spacing was already set inherits it
    # automatically - verified this does NOT happen for free (a newly
    # added child's Margin stays 0,0,0,0 otherwise), so it's applied
    # explicitly here. The spacing value itself lives on the panel's own
    # Tag - entirely inside this file, so tracking it needed no
    # OtterUiResource contract change at all.
    $spacingKey = Get-OtterUiSpacingKey -Resource $Container
    if ($script:OtterUiSpacing.ContainsKey($spacingKey)) {
        $spacing = [double]$script:OtterUiSpacing[$spacingKey]
        if ($panel.Orientation -eq [System.Windows.Controls.Orientation]::Horizontal) {
            $Item.Native.Margin = [System.Windows.Thickness]::new(0, 0, $spacing, 0)
        } else {
            $Item.Native.Margin = [System.Windows.Thickness]::new(0, 0, 0, $spacing)
        }
    }
}

# spacing of app is 12                                            (D48)
#
# StackPanel has no built-in spacing concept - Margin on each child is
# WPF's only real mechanism, verified directly. Every child gets the same
# bottom margin, including the last one - simpler and more robust than
# tracking which child is currently last just to skip its margin.
#
# Works regardless of put order: sets Tag on the panel for any FUTURE
# child (read by Add-OtterUiChild above) and re-margins every EXISTING
# child right here, so `spacing` set before or after any number of `put`s
# produces the same result either way - verified both orders directly.
function Set-OtterUiSpacing {
    param([OtterUiResource]$Window, [object]$Value, [int]$Line)

    $number = Assert-OtterUiNumber -Value $Value -Property 'spacing' -Kind $Window.Kind -Line $Line

    $panel = Get-OtterUiContainerPanel -Container $Window
    $script:OtterUiSpacing[(Get-OtterUiSpacingKey -Resource $Window)] = $number
    foreach ($child in $panel.Children) {
        if ($panel.Orientation -eq [System.Windows.Controls.Orientation]::Horizontal) {
            $child.Margin = [System.Windows.Thickness]::new(0, 0, $number, 0)
        } else {
            $child.Margin = [System.Windows.Thickness]::new(0, 0, 0, $number)
        }
    }
}

function Get-OtterUiSpacing {
    param([OtterUiResource]$Window)

    # No put has happened yet, so there is no panel and nothing has ever
    # been set - gone (D22), not 0, matching the unset-text-property
    # precedent rather than inventing a UI-specific default.
    $spacingKey = Get-OtterUiSpacingKey -Resource $Window
    if (-not $script:OtterUiSpacing.ContainsKey($spacingKey)) { return $null }
    return $script:OtterUiSpacing[$spacingKey]
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
