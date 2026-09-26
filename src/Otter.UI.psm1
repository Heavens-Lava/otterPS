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
$script:OtterUiPadding = @{}
$script:OtterUiWrappers = @{}
$script:OtterUiPlaceholders = @{}
$script:OtterUiOriginalBackgrounds = @{}
$script:OtterUiDimensionFull = @{}
$script:OtterUiLayout = @{}

function Get-OtterUiNativeKey {
    param([object]$Native)
    return [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Native).ToString()
}

function Get-OtterUiSpacingKey {
    param([OtterUiResource]$Resource)
    return Get-OtterUiNativeKey -Native $Resource.Native
}

function Get-OtterUiElementForParent {
    param([OtterUiResource]$Resource)
    $wrapKey = Get-OtterUiSpacingKey -Resource $Resource
    if ($script:OtterUiWrappers.ContainsKey($wrapKey)) {
        return $script:OtterUiWrappers[$wrapKey]
    }
    return $Resource.Native
}

# D54: MainAlign/CrossAlign/Spread are resolved by AXIS, never by the
# property name used to set them - "align" is one property; the word
# itself (top/middle/bottom vs left/center/right) says which axis it
# belongs to, via Get-OtterUiAlignAxis below.
function Get-OtterUiLayoutEntry {
    param([OtterUiResource]$Resource)
    $key = Get-OtterUiSpacingKey -Resource $Resource
    if (-not $script:OtterUiLayout.ContainsKey($key)) {
        $script:OtterUiLayout[$key] = @{ MainAlign = $null; CrossAlign = $null; Spread = $false; LastAlign = $null }
    }
    return $script:OtterUiLayout[$key]
}

# A direction word carries its own axis, independent of the container it
# is applied to - this is the ONLY place that mapping lives. Everything
# else asks this function "which axis does this word belong to," rather
# than assuming from which property name was used.
function Get-OtterUiAlignAxis {
    param([string]$Direction, [string]$Kind, [int]$Line)
    switch ($Direction) {
        'top'    { return 'vertical' }
        'middle' { return 'vertical' }
        'bottom' { return 'vertical' }
        'left'   { return 'horizontal' }
        'center' { return 'horizontal' }
        'right'  { return 'horizontal' }
        default {
            throw [OtterError]::new(
                "A $Kind has no alignment called `"$Direction`".", $Line, 'runtime', 0, $null,
                'Otter accepts: top, middle, bottom, left, center, right')
        }
    }
}

function Get-OtterUiWpfAlignmentValue {
    param([string]$Axis, [string]$Direction)
    if ($Axis -eq 'vertical') {
        switch ($Direction) {
            'top'    { return [System.Windows.VerticalAlignment]::Top }
            'middle' { return [System.Windows.VerticalAlignment]::Center }
            'bottom' { return [System.Windows.VerticalAlignment]::Bottom }
        }
    }
    switch ($Direction) {
        'left'   { return [System.Windows.HorizontalAlignment]::Left }
        'center' { return [System.Windows.HorizontalAlignment]::Center }
        'right'  { return [System.Windows.HorizontalAlignment]::Right }
    }
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
    'window'   = {
        $win = [System.Windows.Window]::new()
        Set-OtterUiDispatcher -Dispatcher $win.Dispatcher
        $win
    }
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
    'card'     = {
        $border = [System.Windows.Controls.Border]::new()
        $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1e293b')
        $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#334155')
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.CornerRadius = [System.Windows.CornerRadius]::new(12)
        $border.Padding = [System.Windows.Thickness]::new(24)
        $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
        $shadow.BlurRadius = 24
        $shadow.Opacity = 0.35
        $shadow.ShadowDepth = 8
        $shadow.Direction = 270
        $border.Effect = $shadow
        $panel = [System.Windows.Controls.StackPanel]::new()
        $panel.Orientation = [System.Windows.Controls.Orientation]::Vertical
        $border.Child = $panel
        $border
    }
    'heading'  = {
        $tb = [System.Windows.Controls.TextBlock]::new()
        $tb.FontSize = 22
        $tb.FontWeight = [System.Windows.FontWeights]::Bold
        $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#f8fafc')
        $tb.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $tb
    }
    'panel'    = {
        $panel = [System.Windows.Controls.StackPanel]::new()
        $panel.Orientation = [System.Windows.Controls.Orientation]::Vertical
        $panel
    }
    'grid'     = {
        [System.Windows.Controls.Grid]::new()
    }
    'primary button' = {
        $btn = [System.Windows.Controls.Button]::new()
        $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2563eb')
        $btn.Foreground = [System.Windows.Media.Brushes]::White
        $btn.BorderThickness = [System.Windows.Thickness]::new(0)
        $btn.Padding = [System.Windows.Thickness]::new(18, 10, 18, 10)
        $btn.FontWeight = [System.Windows.FontWeights]::SemiBold
        $btn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $btn
    }
    'secondary button' = {
        $btn = [System.Windows.Controls.Button]::new()
        $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#334155')
        $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#f8fafc')
        $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#475569')
        $btn.BorderThickness = [System.Windows.Thickness]::new(1)
        $btn.Padding = [System.Windows.Thickness]::new(18, 10, 18, 10)
        $btn.FontWeight = [System.Windows.FontWeights]::Medium
        $btn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $btn
    }
    'danger button' = {
        $btn = [System.Windows.Controls.Button]::new()
        $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#dc2626')
        $btn.Foreground = [System.Windows.Media.Brushes]::White
        $btn.BorderThickness = [System.Windows.Thickness]::new(0)
        $btn.Padding = [System.Windows.Thickness]::new(18, 10, 18, 10)
        $btn.FontWeight = [System.Windows.FontWeights]::SemiBold
        $btn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
        $btn
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
    # D54: 'align' is ONE property everywhere - the physical word itself
    # carries its own axis (top/middle/bottom = vertical, left/center/
    # right = horizontal), never the property name. button/text/text box
    # have no main/cross axis of their own, so they only accept the
    # horizontal words (their own content alignment); row/column resolve
    # the word's axis against their own orientation - see Set-/
    # Get-OtterUiProperty's 'align' handling below, not this table.
    'button' = @{
        'text'       = @{ Native = 'Content'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
        'align'      = @{ Type = 'align' }
    }
    'text box' = @{
        'text'        = @{ Native = 'Text'; Type = 'text' }
        'placeholder' = @{ Type = 'placeholder' }
        'width'       = @{ Native = 'Width'; Type = 'number' }
        'height'      = @{ Native = 'Height'; Type = 'number' }
        'background'  = @{ Native = 'Background'; Type = 'color' }
        'foreground'  = @{ Native = 'Foreground'; Type = 'color' }
        'align'       = @{ Type = 'align' }
    }
    'text' = @{
        'text'       = @{ Native = 'Text'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
        'align'      = @{ Type = 'align' }
    }
    'window' = @{
        'title'      = @{ Native = 'Title'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
        'spacing'    = @{ Type = 'spacing' }
        'padding'    = @{ Type = 'padding' }
    }
    'row' = @{
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'spacing'    = @{ Type = 'spacing' }
        'padding'    = @{ Type = 'padding' }
        'align'      = @{ Type = 'align' }
        'spread'     = @{ Type = 'spread' }
    }
    'column' = @{
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'spacing'    = @{ Type = 'spacing' }
        'padding'    = @{ Type = 'padding' }
        'align'      = @{ Type = 'align' }
        'spread'     = @{ Type = 'spread' }
    }
    # D53: no spacing - scroll owns exactly one child (a ContentControl,
    # like window itself before D47's implicit panel), so "distribute
    # multiple children apart" is meaningless here.
    'scroll' = @{
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
    }
    'primary button' = @{
        'text'       = @{ Native = 'Content'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
        'align'      = @{ Type = 'align' }
    }
    'secondary button' = @{
        'text'       = @{ Native = 'Content'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
        'align'      = @{ Type = 'align' }
    }
    'danger button' = @{
        'text'       = @{ Native = 'Content'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
        'align'      = @{ Type = 'align' }
    }
    'heading' = @{
        'text'       = @{ Native = 'Text'; Type = 'text' }
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'foreground' = @{ Native = 'Foreground'; Type = 'color' }
        'align'      = @{ Type = 'align' }
    }
    'panel' = @{
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'spacing'    = @{ Type = 'spacing' }
        'padding'    = @{ Type = 'padding' }
        'align'      = @{ Type = 'align' }
        'spread'     = @{ Type = 'spread' }
    }
    'grid' = @{
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'spacing'    = @{ Type = 'spacing' }
        'padding'    = @{ Type = 'padding' }
        'align'      = @{ Type = 'align' }
        'spread'     = @{ Type = 'spread' }
    }
    'card' = @{
        'width'      = @{ Native = 'Width'; Type = 'number' }
        'height'     = @{ Native = 'Height'; Type = 'number' }
        'background' = @{ Native = 'Background'; Type = 'color' }
        'spacing'    = @{ Type = 'spacing' }
        'padding'    = @{ Type = 'padding' }
        'align'      = @{ Type = 'align' }
        'spread'     = @{ Type = 'spread' }
        'round'      = @{ Type = 'number' }
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

    if ($mapping.Type -eq 'padding') {
        return (Get-OtterUiPadding -Resource $Resource)
    }

    if ($mapping.Type -eq 'placeholder') {
        return (Get-OtterUiPlaceholder -Resource $Resource)
    }

    if ($mapping.Type -eq 'spread') {
        $layoutKey = Get-OtterUiSpacingKey -Resource $Resource
        if (-not $script:OtterUiLayout.ContainsKey($layoutKey)) { return $false }
        return $script:OtterUiLayout[$layoutKey].Spread
    }

    # 'align' reads back whichever direction was set most recently -
    # both axes can be filled at once (a valid "corner" combination, D54),
    # so there is no single unambiguous answer when both are set; most-
    # recent is simplest and consistent with how writing any other
    # property already just overwrites.
    if ($mapping.Type -eq 'align') {
        $layoutKey = Get-OtterUiSpacingKey -Resource $Resource
        if (-not $script:OtterUiLayout.ContainsKey($layoutKey)) { return $null }
        return $script:OtterUiLayout[$layoutKey].LastAlign
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

    if ($mapping.Type -eq 'padding') {
        Set-OtterUiPadding -Resource $Resource -Value $Value -Line $Line
        return
    }

    if ($mapping.Type -eq 'placeholder') {
        Set-OtterUiPlaceholder -Resource $Resource -Value $Value -Line $Line
        return
    }

    # D54: align/spread. See Get-OtterUiAlignAxis - the WORD decides the
    # axis, never the property name. row/column additionally split that
    # axis into "main" (the flow direction - group positioning, shared
    # with spread) vs "cross" (perpendicular - a per-child property).
    # button/text/text box have no axis of their own, so only the
    # horizontal words apply to them (their own content alignment) - a
    # vertical word there is a clear error, never a silent default.
    if ($mapping.Type -eq 'align') {
        $direction = ([string]$Value).ToLowerInvariant()
        $axis = Get-OtterUiAlignAxis -Direction $direction -Kind $Resource.Kind -Line $Line

        if ($Resource.Kind -notin @('row', 'column')) {
            if ($axis -ne 'horizontal') {
                throw [OtterError]::new(
                    "A $($Resource.Kind) can only align left, center, or right.", $Line, 'runtime')
            }
            $wpfValue = Get-OtterUiWpfAlignmentValue -Axis 'horizontal' -Direction $direction
            if ($Resource.Native -is [System.Windows.Controls.Button]) {
                $Resource.Native.HorizontalContentAlignment = $wpfValue
            } elseif ($Resource.Native -is [System.Windows.Controls.TextBlock] -or $Resource.Native -is [System.Windows.Controls.TextBox]) {
                $ta = switch ($direction) {
                    'left'   { [System.Windows.TextAlignment]::Left }
                    'center' { [System.Windows.TextAlignment]::Center }
                    'right'  { [System.Windows.TextAlignment]::Right }
                }
                $Resource.Native.TextAlignment = $ta
            }
            return
        }

        $layout = Get-OtterUiLayoutEntry -Resource $Resource
        $mainAxis = if ($Resource.Kind -eq 'row') { 'horizontal' } else { 'vertical' }
        $layout.LastAlign = $direction

        if ($axis -eq $mainAxis) {
            if ($layout.Spread) {
                throw [OtterError]::new(
                    "align `"$direction`" conflicts with spread - they both control this $($Resource.Kind)'s main-axis position.",
                    $Line, 'runtime')
            }
            if ($layout.MainAlign -and $layout.MainAlign -ne $direction) {
                throw [OtterError]::new(
                    "align `"$direction`" conflicts with the earlier align `"$($layout.MainAlign)`" - only one alignment is allowed per axis.",
                    $Line, 'runtime')
            }
            $layout.MainAlign = $direction
            Set-OtterUiMainAxisAlign -Resource $Resource -Direction $direction
            return
        }

        if ($layout.CrossAlign -and $layout.CrossAlign -ne $direction) {
            throw [OtterError]::new(
                "align `"$direction`" conflicts with the earlier align `"$($layout.CrossAlign)`" - only one alignment is allowed per axis.",
                $Line, 'runtime')
        }
        $layout.CrossAlign = $direction
        $panel = Get-OtterUiContainerPanel -Container $Resource
        $wpfValue = Get-OtterUiWpfAlignmentValue -Axis $axis -Direction $direction
        foreach ($c in $panel.Children) {
            if ($axis -eq 'vertical') { $c.VerticalAlignment = $wpfValue } else { $c.HorizontalAlignment = $wpfValue }
        }
        return
    }

    if ($mapping.Type -eq 'spread') {
        $layout = Get-OtterUiLayoutEntry -Resource $Resource
        if ($layout.MainAlign) {
            throw [OtterError]::new(
                "spread conflicts with the earlier align `"$($layout.MainAlign)`" - they both control this $($Resource.Kind)'s main-axis position.",
                $Line, 'runtime')
        }
        $layout.Spread = $true
        Update-OtterUiSpread -Resource $Resource
        return
    }

    if ($mapping.Type -eq 'number') {
        $fullKey = (Get-OtterUiSpacingKey $Resource) + "_$Property"
        $wrapKey = Get-OtterUiSpacingKey $Resource
        if ($Property -in @('width', 'height') -and $Value -eq 'full') {
            $script:OtterUiDimensionFull[$fullKey] = $true
            if ($Property -eq 'width') {
                if ($Resource.Kind -eq 'window') {
                    $Resource.Native.Width = [System.Windows.SystemParameters]::WorkArea.Width
                } else {
                    $Resource.Native.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
                    $Resource.Native.Width = [double]::NaN
                    if ($script:OtterUiWrappers.ContainsKey($wrapKey)) {
                        $script:OtterUiWrappers[$wrapKey].HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
                        $script:OtterUiWrappers[$wrapKey].Width = [double]::NaN
                    }
                }
            } else {
                if ($Resource.Kind -eq 'window') {
                    $Resource.Native.Height = [System.Windows.SystemParameters]::WorkArea.Height
                } else {
                    $Resource.Native.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
                    $Resource.Native.Height = [double]::NaN
                    if ($script:OtterUiWrappers.ContainsKey($wrapKey)) {
                        $script:OtterUiWrappers[$wrapKey].VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
                        $script:OtterUiWrappers[$wrapKey].Height = [double]::NaN
                    }
                }
            }
            return
        }
        $number = Assert-OtterUiNumber -Value $Value -Property $Property -Kind $Resource.Kind -Line $Line
        $script:OtterUiDimensionFull.Remove($fullKey)
        if ($Property -eq 'width' -and $Resource.Kind -ne 'window') {
            $Resource.Native.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
            if ($script:OtterUiWrappers.ContainsKey($wrapKey)) {
                $script:OtterUiWrappers[$wrapKey].HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
                $script:OtterUiWrappers[$wrapKey].Width = $number
            }
        } elseif ($Property -eq 'height' -and $Resource.Kind -ne 'window') {
            $Resource.Native.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
            if ($script:OtterUiWrappers.ContainsKey($wrapKey)) {
                $script:OtterUiWrappers[$wrapKey].VerticalAlignment = [System.Windows.VerticalAlignment]::Top
                $script:OtterUiWrappers[$wrapKey].Height = $number
            }
        }
        $Resource.Native.($mapping.Native) = $number
        return
    }

    if ($mapping.Type -eq 'color') {
        $brush = Assert-OtterUiColor -Value $Value -Property $Property -Kind $Resource.Kind -Line $Line
        $Resource.Native.($mapping.Native) = $brush
        $wrapKey = Get-OtterUiSpacingKey $Resource
        if ($script:OtterUiWrappers.ContainsKey($wrapKey)) {
            $script:OtterUiWrappers[$wrapKey].Background = $brush
        }
        if ($script:OtterUiOriginalBackgrounds.ContainsKey($wrapKey)) {
            $script:OtterUiOriginalBackgrounds[$wrapKey] = $brush
            Update-OtterUiPlaceholderWatermark -TextBox $Resource.Native
        }
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
    'button'           = @{ 'clicked' = 'Click'; 'click' = 'Click' }
    'primary button'   = @{ 'clicked' = 'Click'; 'click' = 'Click' }
    'secondary button' = @{ 'clicked' = 'Click'; 'click' = 'Click' }
    'danger button'    = @{ 'clicked' = 'Click'; 'click' = 'Click' }
    'card'             = @{ 'clicked' = 'PreviewMouseDown'; 'click' = 'PreviewMouseDown' }
    'text box'         = @{ 'changed' = 'TextChanged' }
    'window'           = @{ 'closed'  = 'Closed' }
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
            $panel = [System.Windows.Controls.StackPanel]::new()
            $wrapKey = Get-OtterUiSpacingKey -Resource $Container
            if ($script:OtterUiPadding.ContainsKey($wrapKey)) {
                $border = [System.Windows.Controls.Border]::new()
                $border.Padding = [System.Windows.Thickness]::new([double]$script:OtterUiPadding[$wrapKey])
                $border.Child = $panel
                $Container.Native.Content = $border
                $script:OtterUiWrappers[$wrapKey] = $border
            } else {
                $Container.Native.Content = $panel
            }
        }
        if ($Container.Native.Content -is [System.Windows.Controls.Border]) {
            return $Container.Native.Content.Child
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
    $elementToAdd = Get-OtterUiElementForParent -Resource $Item
    if ($null -ne $elementToAdd.Parent) {
        throw [OtterError]::new(
            "A $($Item.Kind) can only be in one place at a time, and this one is already somewhere else.",
            $Line, 'runtime')
    }
    $Container.Native.Content = $elementToAdd
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
    $elementToAdd = Get-OtterUiElementForParent -Resource $Item

    try {
        [void]$panel.Children.Add($elementToAdd)
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
            $elementToAdd.Margin = [System.Windows.Thickness]::new(0, 0, $spacing, 0)
        } else {
            $elementToAdd.Margin = [System.Windows.Thickness]::new(0, 0, 0, $spacing)
        }
    }

    # D54: a child put in AFTER align/spread inherits it automatically -
    # same "future children inherit the current value" rule D48 already
    # established for spacing. CrossAlign is a per-child property applied
    # directly here; MainAlign/Spread reposition the whole group, so they
    # re-run their group-level function instead.
    $layoutKey = Get-OtterUiSpacingKey -Resource $Container
    if ($script:OtterUiLayout.ContainsKey($layoutKey)) {
        $layout = $script:OtterUiLayout[$layoutKey]
        if ($layout.CrossAlign) {
            $crossAxis = if ($panel.Orientation -eq [System.Windows.Controls.Orientation]::Horizontal) { 'vertical' } else { 'horizontal' }
            $wpfValue = Get-OtterUiWpfAlignmentValue -Axis $crossAxis -Direction $layout.CrossAlign
            if ($crossAxis -eq 'vertical') { $elementToAdd.VerticalAlignment = $wpfValue } else { $elementToAdd.HorizontalAlignment = $wpfValue }
        }
        if ($layout.Spread) {
            Update-OtterUiSpread -Resource $Container
        } elseif ($layout.MainAlign) {
            Set-OtterUiMainAxisAlign -Resource $Container -Direction $layout.MainAlign
        }
    }
}

# Main-axis group positioning (align "left"/"center"/"right" on a row,
# align "top"/"middle"/"bottom" on a column) - NOT a per-child property.
# StackPanel always packs children tightly from its start edge with no
# built-in "pack to the end" or "center as a block" option (verified -
# checked its full property list, and FlowDirection was tried and
# confirmed NOT to reverse packing order for a Horizontal StackPanel, so
# it isn't the mechanism here). Achieved instead by measuring the
# group's total size and putting the leftover space into a margin before
# the first child (right/bottom), split before-and-after (center/middle),
# or none at all (left/top - already the default). Same measurement
# technique Update-OtterUiSpread already uses, and shares its real
# limitation: computed once, not a live layout constraint, so it will
# not re-flow automatically if the container is resized afterward.
function Set-OtterUiMainAxisAlign {
    param([OtterUiResource]$Resource, [string]$Direction)

    $panel = Get-OtterUiContainerPanel -Container $Resource
    $count = $panel.Children.Count
    if ($count -eq 0) { return }

    $horizontal = $panel.Orientation -eq [System.Windows.Controls.Orientation]::Horizontal
    $avail = if ($horizontal) {
        if (-not [double]::IsNaN($panel.Width) -and $panel.Width -gt 0) { $panel.Width } else { $panel.ActualWidth }
    } else {
        if (-not [double]::IsNaN($panel.Height) -and $panel.Height -gt 0) { $panel.Height } else { $panel.ActualHeight }
    }

    $total = 0
    foreach ($c in $panel.Children) {
        $c.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
        $total += if ($horizontal) { $c.DesiredSize.Width } else { $c.DesiredSize.Height }
    }
    $leftover = $avail - $total
    if ($leftover -le 0) { return }

    $first = $panel.Children[0]
    $before = 0
    if ($Direction -in @('right', 'bottom')) { $before = $leftover }
    elseif ($Direction -in @('center', 'middle')) { $before = $leftover / 2 }
    # 'left'/'top' - no leading margin needed, StackPanel already starts there.

    if ($horizontal) {
        $first.Margin = [System.Windows.Thickness]::new($before, $first.Margin.Top, $first.Margin.Right, $first.Margin.Bottom)
    } else {
        $first.Margin = [System.Windows.Thickness]::new($first.Margin.Left, $before, $first.Margin.Right, $first.Margin.Bottom)
    }
}

function Update-OtterUiSpread {
    param([OtterUiResource]$Resource)

    $key = Get-OtterUiSpacingKey -Resource $Resource
    if (-not $script:OtterUiLayout.ContainsKey($key) -or -not $script:OtterUiLayout[$key].spread) { return }

    $panel = Get-OtterUiContainerPanel -Container $Resource
    $count = $panel.Children.Count
    if ($count -le 1) { return }

    if ($panel.Orientation -eq [System.Windows.Controls.Orientation]::Horizontal) {
        $avail = if (-not [double]::IsNaN($panel.Width) -and $panel.Width -gt 0) {
            $panel.Width
        } elseif ($panel.ActualWidth -gt 0) {
            $panel.ActualWidth
        } else {
            0
        }
        $totalChildWidth = 0
        foreach ($c in $panel.Children) {
            if (-not [double]::IsNaN($c.Width) -and $c.Width -gt 0) {
                $totalChildWidth += $c.Width
            } elseif ($c.DesiredSize.Width -gt 0) {
                $totalChildWidth += $c.DesiredSize.Width
            } else {
                $c.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
                $totalChildWidth += $c.DesiredSize.Width
            }
        }
        if ($avail -gt $totalChildWidth) {
            $gap = ($avail - $totalChildWidth) / ($count - 1)
            for ($i = 0; $i -lt $count - 1; $i++) {
                $c = $panel.Children[$i]
                $c.Margin = [System.Windows.Thickness]::new($c.Margin.Left, $c.Margin.Top, $gap, $c.Margin.Bottom)
            }
            $last = $panel.Children[$count - 1]
            $last.Margin = [System.Windows.Thickness]::new($last.Margin.Left, $last.Margin.Top, 0, $last.Margin.Bottom)
        }
    } else {
        $avail = if (-not [double]::IsNaN($panel.Height) -and $panel.Height -gt 0) {
            $panel.Height
        } elseif ($panel.ActualHeight -gt 0) {
            $panel.ActualHeight
        } else {
            0
        }
        $totalChildHeight = 0
        foreach ($c in $panel.Children) {
            if (-not [double]::IsNaN($c.Height) -and $c.Height -gt 0) {
                $totalChildHeight += $c.Height
            } elseif ($c.DesiredSize.Height -gt 0) {
                $totalChildHeight += $c.DesiredSize.Height
            } else {
                $c.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
                $totalChildHeight += $c.DesiredSize.Height
            }
        }
        if ($avail -gt $totalChildHeight) {
            $gap = ($avail - $totalChildHeight) / ($count - 1)
            for ($i = 0; $i -lt $count - 1; $i++) {
                $c = $panel.Children[$i]
                $c.Margin = [System.Windows.Thickness]::new($c.Margin.Left, $c.Margin.Top, $c.Margin.Right, $gap)
            }
            $last = $panel.Children[$count - 1]
            $last.Margin = [System.Windows.Thickness]::new($last.Margin.Left, $last.Margin.Top, $last.Margin.Right, 0)
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

function Set-OtterUiPadding {
    param([OtterUiResource]$Resource, [object]$Value, [int]$Line)

    $number = Assert-OtterUiNumber -Value $Value -Property 'padding' -Kind $Resource.Kind -Line $Line
    $wrapKey = Get-OtterUiSpacingKey -Resource $Resource
    $script:OtterUiPadding[$wrapKey] = $number

    if ($Resource.Kind -eq 'window') {
        if ($null -eq $Resource.Native.Content) {
            $panel = [System.Windows.Controls.StackPanel]::new()
            $border = [System.Windows.Controls.Border]::new()
            $border.Padding = [System.Windows.Thickness]::new($number)
            $border.Child = $panel
            $Resource.Native.Content = $border
            $script:OtterUiWrappers[$wrapKey] = $border
        } elseif ($Resource.Native.Content -is [System.Windows.Controls.Border]) {
            $Resource.Native.Content.Padding = [System.Windows.Thickness]::new($number)
        } else {
            $panel = $Resource.Native.Content
            $Resource.Native.Content = $null
            $border = [System.Windows.Controls.Border]::new()
            $border.Padding = [System.Windows.Thickness]::new($number)
            $border.Child = $panel
            $Resource.Native.Content = $border
            $script:OtterUiWrappers[$wrapKey] = $border
        }
        return
    }

    # For 'row' and 'column'
    if ($script:OtterUiWrappers.ContainsKey($wrapKey)) {
        $border = $script:OtterUiWrappers[$wrapKey]
        $border.Padding = [System.Windows.Thickness]::new($number)
    } else {
        $border = [System.Windows.Controls.Border]::new()
        $border.Padding = [System.Windows.Thickness]::new($number)
        $panel = $Resource.Native
        $border.Width = $panel.Width
        $border.Height = $panel.Height
        $border.HorizontalAlignment = $panel.HorizontalAlignment
        $border.VerticalAlignment = $panel.VerticalAlignment
        $border.Margin = $panel.Margin
        $panel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 0)
        if ($null -ne $panel.Background) {
            $border.Background = $panel.Background
        }

        $parent = $panel.Parent
        if ($null -ne $parent) {
            if ($parent -is [System.Windows.Controls.Panel]) {
                $idx = $parent.Children.IndexOf($panel)
                if ($idx -ge 0) {
                    $parent.Children.RemoveAt($idx)
                    $border.Child = $panel
                    $parent.Children.Insert($idx, $border)
                }
            } elseif ($parent -is [System.Windows.Controls.ContentControl]) {
                $parent.Content = $null
                $border.Child = $panel
                $parent.Content = $border
            }
        } else {
            $border.Child = $panel
        }
        $script:OtterUiWrappers[$wrapKey] = $border
    }
}

function Get-OtterUiPadding {
    param([OtterUiResource]$Resource)

    $wrapKey = Get-OtterUiSpacingKey -Resource $Resource
    if (-not $script:OtterUiPadding.ContainsKey($wrapKey)) { return $null }
    return $script:OtterUiPadding[$wrapKey]
}

function New-OtterUiWatermarkBrush {
    param([string]$Text, [System.Windows.Media.Brush]$Background)

    $textBlock = [System.Windows.Controls.TextBlock]::new()
    $textBlock.Text = $Text
    $textBlock.Foreground = [System.Windows.Media.Brushes]::DarkGray
    $textBlock.FontStyle = [System.Windows.FontStyles]::Italic
    $textBlock.Margin = [System.Windows.Thickness]::new(4, 2, 0, 0)

    $grid = [System.Windows.Controls.Grid]::new()
    if ($null -ne $Background) {
        $grid.Background = $Background
    } else {
        $grid.Background = [System.Windows.Media.Brushes]::White
    }
    [void]$grid.Children.Add($textBlock)

    $brush = [System.Windows.Media.VisualBrush]::new($grid)
    $brush.Stretch = [System.Windows.Media.Stretch]::None
    $brush.TileMode = [System.Windows.Media.TileMode]::None
    $brush.AlignmentX = [System.Windows.Media.AlignmentX]::Left
    $brush.AlignmentY = [System.Windows.Media.AlignmentY]::Top
    return $brush
}

function Update-OtterUiPlaceholderWatermark {
    param([System.Windows.Controls.TextBox]$TextBox)

    $wrapKey = Get-OtterUiNativeKey -Native $TextBox
    if (-not $script:OtterUiPlaceholders.ContainsKey($wrapKey)) { return }
    $placeholderText = $script:OtterUiPlaceholders[$wrapKey]
    $origBg = if ($script:OtterUiOriginalBackgrounds.ContainsKey($wrapKey)) { $script:OtterUiOriginalBackgrounds[$wrapKey] } else { $null }

    if ([string]::IsNullOrEmpty($TextBox.Text)) {
        $TextBox.Background = New-OtterUiWatermarkBrush -Text $placeholderText -Background $origBg
    } else {
        if ($null -ne $origBg) {
            $TextBox.Background = $origBg
        } else {
            $TextBox.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
        }
    }
}

function Set-OtterUiPlaceholder {
    param([OtterUiResource]$Resource, [object]$Value, [int]$Line)

    $text = Format-OtterValue -Value $Value
    $wrapKey = Get-OtterUiSpacingKey -Resource $Resource
    $script:OtterUiPlaceholders[$wrapKey] = $text

    $tb = $Resource.Native
    if (-not $script:OtterUiOriginalBackgrounds.ContainsKey($wrapKey)) {
        $script:OtterUiOriginalBackgrounds[$wrapKey] = $tb.Background
        $tb.add_TextChanged({
            param($sender, $e)
            Update-OtterUiPlaceholderWatermark -TextBox $sender
        })
    }

    Update-OtterUiPlaceholderWatermark -TextBox $tb
}

function Get-OtterUiPlaceholder {
    param([OtterUiResource]$Resource)

    $wrapKey = Get-OtterUiSpacingKey -Resource $Resource
    if (-not $script:OtterUiPlaceholders.ContainsKey($wrapKey)) { return $null }
    return $script:OtterUiPlaceholders[$wrapKey]
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
        Set-OtterUiDispatcher -Dispatcher $Resource.Native.Dispatcher
        [void]$Resource.Native.ShowDialog()
    }
    catch {
        throw [OtterError]::new(
            "This window has already been closed, so it can't be shown again.", $Line, 'runtime')
    }
}


# ===============================================================
# DECLARATIVE WPF RENDERING AND ANIMATIONS
# ===============================================================

function Add-OtterUiAnimationWpf {
    param(
        [Parameter(Mandatory)][System.Windows.FrameworkElement]$Control,
        [Parameter(Mandatory)][UiAnimationBlock]$Anim
    )

    Initialize-OtterWpfProvider

    # Setup transform group if not present
    $transGroup = $Control.RenderTransform -as [System.Windows.Media.TransformGroup]
    if ($null -eq $transGroup) {
        $transGroup = [System.Windows.Media.TransformGroup]::new()
        $scale = [System.Windows.Media.ScaleTransform]::new(1.0, 1.0)
        $translate = [System.Windows.Media.TranslateTransform]::new(0.0, 0.0)
        [void]$transGroup.Children.Add($scale)
        [void]$transGroup.Children.Add($translate)
        $Control.RenderTransform = $transGroup
        $Control.RenderTransformOrigin = [System.Windows.Point]::new(0.5, 0.5)
    } else {
        $scale = $transGroup.Children[0] -as [System.Windows.Media.ScaleTransform]
        $translate = $transGroup.Children[1] -as [System.Windows.Media.TranslateTransform]
    }

    $durMs = if ($Anim.DurationMs -gt 0) { $Anim.DurationMs } else { 200 }
    $duration = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds($durMs))
    $easing = [System.Windows.Media.Animation.QuadraticEase]::new()
    switch ($Anim.Easing.ToLowerInvariant()) {
        'ease-in'     { $easing.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseIn }
        'ease-out'    { $easing.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
        'ease-in-out' { $easing.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut }
        default       { $easing.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut }
    }

    switch ($Anim.Trigger.ToLowerInvariant()) {
        'hover' {
            $targetScale = 1.05
            foreach ($step in $Anim.Steps) {
                if ($step.Operation -in @('grow', 'scale') -and $step.Amount -is [LiteralExpr]) {
                    $targetScale = [double]$step.Amount.Value
                }
            }
            $Control.add_MouseEnter({
                $scaleAnimX = [System.Windows.Media.Animation.DoubleAnimation]::new($targetScale, $duration)
                $scaleAnimX.EasingFunction = $easing
                $scaleAnimY = [System.Windows.Media.Animation.DoubleAnimation]::new($targetScale, $duration)
                $scaleAnimY.EasingFunction = $easing
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $scaleAnimX)
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $scaleAnimY)
            }.GetNewClosure())
            $Control.add_MouseLeave({
                $scaleAnimX = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, $duration)
                $scaleAnimX.EasingFunction = $easing
                $scaleAnimY = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, $duration)
                $scaleAnimY.EasingFunction = $easing
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $scaleAnimX)
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $scaleAnimY)
            }.GetNewClosure())
        }
        'press' {
            $Control.add_PreviewMouseDown({
                $scaleAnimX = [System.Windows.Media.Animation.DoubleAnimation]::new(0.96, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(100)))
                $scaleAnimX.EasingFunction = $easing
                $scaleAnimY = [System.Windows.Media.Animation.DoubleAnimation]::new(0.96, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(100)))
                $scaleAnimY.EasingFunction = $easing
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $scaleAnimX)
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $scaleAnimY)
            }.GetNewClosure())
            $Control.add_PreviewMouseUp({
                $scaleAnimX = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(100)))
                $scaleAnimX.EasingFunction = $easing
                $scaleAnimY = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(100)))
                $scaleAnimY.EasingFunction = $easing
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $scaleAnimX)
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $scaleAnimY)
            }.GetNewClosure())
        }
        'enter' {
            $fromOpacity = $null
            $fromX = $null
            $fromY = $null
            foreach ($step in $Anim.Steps) {
                if ($step.Operation -eq 'fade' -and $step.Direction -eq 'in') {
                    $fromOpacity = 0.0
                }
                if ($step.Operation -eq 'move') {
                    $amt = if ($step.Amount -is [LiteralExpr]) { [double]$step.Amount.Value } else { 20.0 }
                    switch ($step.Direction) {
                        'up'    { $fromY = $amt }
                        'down'  { $fromY = -$amt }
                        'left'  { $fromX = $amt }
                        'right' { $fromX = -$amt }
                    }
                }
                if ($step.Operation -eq 'slide') {
                    $fromOpacity = 0.0
                    switch ($step.Direction) {
                        'left'   { $fromX = -30.0 }
                        'right'  { $fromX = 30.0 }
                        'top'    { $fromY = -30.0 }
                        'bottom' { $fromY = 30.0 }
                        default  { $fromX = -30.0 }
                    }
                }
            }

            if ($null -ne $fromOpacity) { $Control.Opacity = $fromOpacity }
            if ($null -ne $fromX) { $translate.X = $fromX }
            if ($null -ne $fromY) { $translate.Y = $fromY }

            $runEnter = {
                if ($null -ne $fromOpacity) {
                    $animOp = [System.Windows.Media.Animation.DoubleAnimation]::new($fromOpacity, 1.0, $duration)
                    $animOp.EasingFunction = $easing
                    $Control.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animOp)
                }
                if ($null -ne $fromX) {
                    $animX = [System.Windows.Media.Animation.DoubleAnimation]::new($fromX, 0.0, $duration)
                    $animX.EasingFunction = $easing
                    $translate.BeginAnimation([System.Windows.Media.TranslateTransform]::XProperty, $animX)
                }
                if ($null -ne $fromY) {
                    $animY = [System.Windows.Media.Animation.DoubleAnimation]::new($fromY, 0.0, $duration)
                    $animY.EasingFunction = $easing
                    $translate.BeginAnimation([System.Windows.Media.TranslateTransform]::YProperty, $animY)
                }
            }.GetNewClosure()

            if ($Control.IsLoaded) {
                & $runEnter
            } else {
                $Control.add_Loaded({ & $runEnter }.GetNewClosure())
            }
        }
        'leave' {
            $runLeave = {
                $animOp = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, 0.0, $duration)
                $animOp.EasingFunction = $easing
                $animScaleX = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, 0.95, $duration)
                $animScaleX.EasingFunction = $easing
                $animScaleY = [System.Windows.Media.Animation.DoubleAnimation]::new(1.0, 0.95, $duration)
                $animScaleY.EasingFunction = $easing
                $Control.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $animOp)
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleXProperty, $animScaleX)
                $scale.BeginAnimation([System.Windows.Media.ScaleTransform]::ScaleYProperty, $animScaleY)
            }.GetNewClosure()
            $Control.Tag = @{ LeaveAction = $runLeave }
        }
    }
}

function Get-OtterUiExpressionValue {
    param(
        [Parameter(Mandatory)][Node]$Expr,
        [Parameter(Mandatory)][OtterEnvironment]$Environment
    )

    if ($null -eq $Expr) { return $null }
    if ($Expr -is [LiteralExpr]) { return $Expr.Value }
    if ($Expr -is [VariableExpr]) { return $Environment.Get($Expr.Name) }
    if ($Expr -is [NotExpr]) {
        $v = Get-OtterUiExpressionValue -Expr $Expr.Operand -Environment $Environment
        return (-not [bool]$v)
    }
    if ($Expr -is [MathExpr]) {
        $l = Get-OtterUiExpressionValue -Expr $Expr.Left -Environment $Environment
        $r = Get-OtterUiExpressionValue -Expr $Expr.Right -Environment $Environment
        $op = $Expr.Op.ToString()
        if ($op -eq 'Add') {
            if (($l -is [string]) -or ($r -is [string])) {
                return ([string](Format-OtterValue -Value $l) + [string](Format-OtterValue -Value $r))
            }
            return ([double]$l + [double]$r)
        } elseif ($op -eq 'Subtract') {
            return ([double]$l - [double]$r)
        } elseif ($op -eq 'Multiply') {
            return ([double]$l * [double]$r)
        } elseif ($op -eq 'Divide') {
            return ([double]$l / [double]$r)
        }
    }
    if ($Expr -is [CompareExpr]) {
        $l = Get-OtterUiExpressionValue -Expr $Expr.Left -Environment $Environment
        $r = Get-OtterUiExpressionValue -Expr $Expr.Right -Environment $Environment
        $cop = $Expr.Op.ToString()
        switch ($cop) {
            'Equal' { return (Test-OtterEqual -Left $l -Right $r) }
            'NotEqual' { return (-not (Test-OtterEqual -Left $l -Right $r)) }
            'LessThan' { return ($l -lt $r) }
            'GreaterThan' { return ($l -gt $r) }
            'LessThanOrEqual' { return ($l -le $r) }
            'GreaterThanOrEqual' { return ($l -ge $r) }
        }
    }
    if ($Expr -is [LogicExpr]) {
        $l = [bool](Get-OtterUiExpressionValue -Expr $Expr.Left -Environment $Environment)
        $lop = $Expr.Op.ToString()
        if ($lop -eq 'And') {
            if (-not $l) { return $false }
            return [bool](Get-OtterUiExpressionValue -Expr $Expr.Right -Environment $Environment)
        } elseif ($lop -eq 'Or') {
            if ($l) { return $true }
            return [bool](Get-OtterUiExpressionValue -Expr $Expr.Right -Environment $Environment)
        }
    }
    if (Get-Command -Name Get-OtterValue -ErrorAction SilentlyContinue) {
        return (Get-OtterValue -Expression $Expr -Environment $Environment)
    }
    return $null
}

function ConvertTo-OtterDeclarativeElementWpf {
    param(
        [Parameter(Mandatory)][Node]$Element,
        [Parameter(Mandatory)][OtterEnvironment]$Environment
    )

    Initialize-OtterWpfProvider

    if ($Element -isnot [UiElementStmt]) { return $null }

    $tag = if ($Element.Tag) { $Element.Tag.ToLowerInvariant() } else { "panel" }
    $variant = if ($Element.Variant) { $Element.Variant.ToLowerInvariant() } else { $null }

    $control = $null
    $innerPanel = $null

    switch ($tag) {
        'card' {
            $border = [System.Windows.Controls.Border]::new()
            $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1e293b')
            $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#334155')
            $border.BorderThickness = [System.Windows.Thickness]::new(1)
            $border.CornerRadius = [System.Windows.CornerRadius]::new(12)
            $border.Padding = [System.Windows.Thickness]::new(24)
            $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
            $shadow.BlurRadius = 24
            $shadow.Opacity = 0.35
            $shadow.ShadowDepth = 8
            $shadow.Direction = 270
            $border.Effect = $shadow

            $inner = [System.Windows.Controls.StackPanel]::new()
            $inner.Orientation = [System.Windows.Controls.Orientation]::Vertical
            $border.Child = $inner
            $control = $border
            $innerPanel = $inner
        }
        'heading' {
            $tb = [System.Windows.Controls.TextBlock]::new()
            $tb.FontSize = 22
            $tb.FontWeight = [System.Windows.FontWeights]::Bold
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#f8fafc')
            $tb.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
            $control = $tb
        }
        'text' {
            $tb = [System.Windows.Controls.TextBlock]::new()
            $tb.FontSize = 15
            $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#f8fafc')
            $control = $tb
        }
        'button' {
            $btn = [System.Windows.Controls.Button]::new()
            $btn.Padding = [System.Windows.Thickness]::new(18, 10, 18, 10)
            $btn.FontWeight = [System.Windows.FontWeights]::SemiBold
            $btn.FontSize = 14
            $btn.Cursor = [System.Windows.Input.Cursors]::Hand
            $btn.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left

            switch ($variant) {
                'primary' {
                    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2563eb')
                    $btn.Foreground = [System.Windows.Media.Brushes]::White
                    $btn.BorderThickness = [System.Windows.Thickness]::new(0)
                }
                'secondary' {
                    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#334155')
                    $btn.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#f8fafc')
                    $btn.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#475569')
                    $btn.BorderThickness = [System.Windows.Thickness]::new(1)
                }
                'danger' {
                    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#dc2626')
                    $btn.Foreground = [System.Windows.Media.Brushes]::White
                    $btn.BorderThickness = [System.Windows.Thickness]::new(0)
                }
                default {
                    $btn.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2563eb')
                    $btn.Foreground = [System.Windows.Media.Brushes]::White
                    $btn.BorderThickness = [System.Windows.Thickness]::new(0)
                }
            }
            $control = $btn
        }
        'panel' {
            $p = [System.Windows.Controls.StackPanel]::new()
            $p.Orientation = [System.Windows.Controls.Orientation]::Vertical
            $control = $p
            $innerPanel = $p
        }
        'row' {
            $p = [System.Windows.Controls.StackPanel]::new()
            $p.Orientation = [System.Windows.Controls.Orientation]::Horizontal
            $control = $p
            $innerPanel = $p
        }
        'column' {
            $p = [System.Windows.Controls.StackPanel]::new()
            $p.Orientation = [System.Windows.Controls.Orientation]::Vertical
            $control = $p
            $innerPanel = $p
        }
        default {
            $p = [System.Windows.Controls.StackPanel]::new()
            $control = $p
            $innerPanel = $p
        }
    }

    # Label / Dynamic data binding
    if ($Element.Label) {
        if ($Element.Label -is [LiteralExpr]) {
            $lblVal = [string]$Element.Label.Value
            if ($control -is [System.Windows.Controls.TextBlock]) {
                $control.Text = $lblVal
            } elseif ($control -is [System.Windows.Controls.Button]) {
                $control.Content = $lblVal
            }
        } else {
            $expr = $Element.Label
            $boundControl = $control
            $updateAction = {
                $val = Get-OtterUiExpressionValue -Expr $expr -Environment $Environment
                $txt = [string](Format-OtterValue -Value $val)
                if ($boundControl.Dispatcher.CheckAccess()) {
                    if ($boundControl -is [System.Windows.Controls.TextBlock]) { $boundControl.Text = $txt }
                    elseif ($boundControl -is [System.Windows.Controls.Button]) { $boundControl.Content = $txt }
                } else {
                    $boundControl.Dispatcher.Invoke([Action]{
                        if ($boundControl -is [System.Windows.Controls.TextBlock]) { $boundControl.Text = $txt }
                        elseif ($boundControl -is [System.Windows.Controls.Button]) { $boundControl.Content = $txt }
                    })
                }
            }.GetNewClosure()

            $null = & $updateAction

            # Subscribe to signals and derived values in Environment
            foreach ($k in $Environment.Variables.Keys) {
                $raw = $Environment.GetRaw($k)
                if ($raw -is [OtterSignal]) {
                    $raw.Subscribe($updateAction)
                } elseif ($raw -is [OtterDerived]) {
                    $raw.Subscribe($updateAction)
                }
            }
        }
    }

    # Layout modes & presets
    $childGap = 0
    if ($Element.Layout) {
        $mode = if ($Element.Layout.Mode) { $Element.Layout.Mode.ToLowerInvariant() } else { $null }
        if ($innerPanel -is [System.Windows.Controls.StackPanel]) {
            switch ($mode) {
                'row'      { $innerPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal }
                'column'   { $innerPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical }
                'stack'    { $innerPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical }
                'centered' {
                    $innerPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical
                    $innerPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                    $innerPanel.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                }
            }
        }

        if ($Element.Layout.Gap) {
            $childGap = if ($Element.Layout.Gap -is [LiteralExpr]) { [int]$Element.Layout.Gap.Value } else { 8 }
        }

        if ($Element.Layout.Align) {
            $alignStr = $Element.Layout.Align.ToLowerInvariant()
            switch ($alignStr) {
                'center' {
                    $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                    if ($innerPanel) { $innerPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center }
                    if ($control -is [System.Windows.Controls.TextBlock]) { $control.TextAlignment = [System.Windows.TextAlignment]::Center }
                }
                'left'   {
                    $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
                    if ($innerPanel) { $innerPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left }
                }
                'right'  {
                    $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
                    if ($innerPanel) { $innerPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right }
                }
                'top'    { $control.VerticalAlignment = [System.Windows.VerticalAlignment]::Top }
                'middle' { $control.VerticalAlignment = [System.Windows.VerticalAlignment]::Center }
                'bottom' { $control.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom }
            }
        }

        if ($Element.Layout.Spread) {
            $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
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
                        $rad = if ($null -ne $pVal -and $pVal -ne $true) { [double]$pVal } else { 12.0 }
                        if ($control -is [System.Windows.Controls.Border]) {
                            $control.CornerRadius = [System.Windows.CornerRadius]::new($rad)
                        }
                    }
                    'gap' {
                        $childGap = [int]$pVal
                    }
                    'align' {
                        switch ([string]$pVal) {
                            'center' {
                                $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
                                if ($control -is [System.Windows.Controls.TextBlock]) { $control.TextAlignment = [System.Windows.TextAlignment]::Center }
                            }
                            'left'   { $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left }
                            'right'  { $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right }
                            'top'    { $control.VerticalAlignment = [System.Windows.VerticalAlignment]::Top }
                            'middle' { $control.VerticalAlignment = [System.Windows.VerticalAlignment]::Center }
                            'bottom' { $control.VerticalAlignment = [System.Windows.VerticalAlignment]::Bottom }
                        }
                    }
                    'padding' {
                        $padVal = [double]$pVal
                        if ($control -is [System.Windows.Controls.Border]) {
                            $control.Padding = [System.Windows.Thickness]::new($padVal)
                        } elseif ($control -is [System.Windows.Controls.Control]) {
                            $control.Padding = [System.Windows.Thickness]::new($padVal)
                        }
                    }
                    'width' {
                        if ($pVal -eq 'full') {
                            $control.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Stretch
                        } else {
                            $control.Width = [double]$pVal
                        }
                    }
                    'height' {
                        if ($pVal -eq 'full') {
                            $control.VerticalAlignment = [System.Windows.VerticalAlignment]::Stretch
                        } else {
                            $control.Height = [double]$pVal
                        }
                    }
                    'background' {
                        $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString([string]$pVal)
                        if ($control -is [System.Windows.Controls.Border]) { $control.Background = $brush }
                        elseif ($control -is [System.Windows.Controls.Control]) { $control.Background = $brush }
                    }
                    'foreground' {
                        $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromString([string]$pVal)
                        if ($control -is [System.Windows.Controls.TextBlock]) { $control.Foreground = $brush }
                        elseif ($control -is [System.Windows.Controls.Control]) { $control.Foreground = $brush }
                    }
                }
            }
        }
    }

    # Animations
    if ($Element.Animations) {
        foreach ($anim in $Element.Animations) {
            Add-OtterUiAnimationWpf -Control $control -Anim $anim
        }
    }

    # Events
    if ($Element.Events) {
        foreach ($evt in $Element.Events) {
            $evtName = $evt.EventName.ToLowerInvariant()
            $evtBody = $evt.Body
            $targetControl = $control

            if ($evtName -in @('click', 'clicked')) {
                $clickHandler = {
                    param($s, $e)
                    foreach ($bStmt in $evtBody) {
                        if ($bStmt -is [AssignStmt]) {
                            $tName = if ($bStmt.Target -is [VariableExpr]) { $bStmt.Target.Name } else { [string]$bStmt.Target }
                            $newVal = Get-OtterUiExpressionValue -Expr $bStmt.Value -Environment $Environment
                            $Environment.Set($tName, $newVal)
                        } elseif (Get-Command -Name Invoke-OtterStatement -ErrorAction SilentlyContinue) {
                            Invoke-OtterStatement -Statement $bStmt -Environment $Environment
                        }
                    }
                }.GetNewClosure()

                if ($targetControl -is [System.Windows.Controls.Button]) {
                    $targetControl.add_Click($clickHandler)
                } else {
                    $targetControl.add_MouseDown($clickHandler)
                }
            }
        }
    }

    # Children
    if ($Element.Children -and $innerPanel) {
        $first = $true
        foreach ($child in $Element.Children) {
            if ($child -is [UiElementStmt]) {
                $childControl = ConvertTo-OtterDeclarativeElementWpf -Element $child -Environment $Environment
                if ($childControl) {
                    if (-not $first -and $childGap -gt 0) {
                        if ($innerPanel.Orientation -eq [System.Windows.Controls.Orientation]::Horizontal) {
                            $childControl.Margin = [System.Windows.Thickness]::new($childGap, 0, 0, 0)
                        } else {
                            $childControl.Margin = [System.Windows.Thickness]::new(0, $childGap, 0, 0)
                        }
                    }
                    [void]$innerPanel.Children.Add($childControl)
                    $first = $false
                }
            } elseif ($child -is [IfStmt]) {
                if ($child.Branches.Count -gt 0) {
                    $b0 = $child.Branches[0]
                    $subPanel = [System.Windows.Controls.StackPanel]::new()
                    $subPanel.Orientation = [System.Windows.Controls.Orientation]::Vertical
                    $subFirst = $true
                    foreach ($sub in $b0.Body) {
                        if ($sub -is [UiElementStmt]) {
                            $subCtrl = ConvertTo-OtterDeclarativeElementWpf -Element $sub -Environment $Environment
                            if ($subCtrl) {
                                if (-not $subFirst -and $childGap -gt 0) {
                                    $subCtrl.Margin = [System.Windows.Thickness]::new(0, $childGap, 0, 0)
                                }
                                [void]$subPanel.Children.Add($subCtrl)
                                $subFirst = $false
                            }
                        }
                    }

                    # Conditional visibility binding
                    $condExpr = $b0.Condition
                    $updateCond = {
                        $res = [bool](Get-OtterUiExpressionValue -Expr $condExpr -Environment $Environment)
                        if ($subPanel.Dispatcher.CheckAccess()) {
                            $subPanel.Visibility = if ($res) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
                        } else {
                            $subPanel.Dispatcher.Invoke([Action]{
                                $subPanel.Visibility = if ($res) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
                            })
                        }
                    }.GetNewClosure()

                    $null = & $updateCond

                    foreach ($k in $Environment.Variables.Keys) {
                        $raw = $Environment.GetRaw($k)
                        if ($raw -is [OtterSignal]) {
                            $raw.Subscribe($updateCond)
                        } elseif ($raw -is [OtterDerived]) {
                            $raw.Subscribe($updateCond)
                        }
                    }

                    if (-not $first -and $childGap -gt 0) {
                        $subPanel.Margin = [System.Windows.Thickness]::new(0, $childGap, 0, 0)
                    }
                    [void]$innerPanel.Children.Add($subPanel)
                    $first = $false
                }
            }
        }
    }

    return $control
}

function ConvertTo-OtterWpfWindow {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [OtterEnvironment]$Environment = $null,
        [string]$Title = "Otter App"
    )

    Initialize-OtterWpfProvider

    if ($null -eq $Environment) {
        $Environment = [OtterEnvironment]::new()
    }

    # Execute top-level non-UI statements first (state, derive, watch, functions, calls)
    $declarativeRoots = [System.Collections.Generic.List[UiElementStmt]]::new()
    $functions = [ordered]@{}
    $componentFunctionNames = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($stmt in $Program.Statements) {
        if ($stmt -is [FunctionDefStmt]) {
            $functions[$stmt.Name] = $stmt
            foreach ($bs in $stmt.Body) {
                if ($bs -is [UiElementStmt]) {
                    [void]$componentFunctionNames.Add($stmt.Name)
                    break
                }
            }
        }
    }

    foreach ($stmt in $Program.Statements) {
        if ($stmt -is [FunctionDefStmt]) {
            continue
        }
        if ($stmt -is [UiElementStmt]) {
            $declarativeRoots.Add($stmt)
            continue
        }
        if ($stmt -is [CallStmt] -and $componentFunctionNames.Contains($stmt.Call.Name)) {
            # Handled below as declarative component root
            continue
        }
        if ($stmt -is [StateDefStmt]) {
            $val = Get-OtterUiExpressionValue -Expr $stmt.InitialValue -Environment $Environment
            $Environment.SetRaw($stmt.Name, [OtterSignal]::new($stmt.Name, $val))
            continue
        }
        if ($stmt -is [DeriveDefStmt]) {
            $derived = [OtterDerived]::new($stmt.Name, $stmt.Expression, $Environment)
            $Environment.SetRaw($stmt.Name, $derived)
            continue
        }
        if (Get-Command -Name Invoke-OtterStatement -ErrorAction SilentlyContinue) {
            Invoke-OtterStatement -Statement $stmt -Environment $Environment
        }
    }

    # Check for calls that invoke declarative component functions (e.g. counterCard)
    foreach ($stmt in $Program.Statements) {
        if ($stmt -is [CallStmt] -and $componentFunctionNames.Contains($stmt.Call.Name)) {
            $fnDef = $functions[$stmt.Call.Name]
            foreach ($bodyStmt in $fnDef.Body) {
                if ($bodyStmt -is [UiElementStmt]) {
                    $declarativeRoots.Add($bodyStmt)
                }
            }
        }
    }

    # Create host Window
    $window = [System.Windows.Window]::new()
    $window.Title = $Title
    $window.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#0f172a')
    $window.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $window.MinWidth = 420
    $window.MinHeight = 320

    $rootGrid = [System.Windows.Controls.Grid]::new()
    $rootGrid.Margin = [System.Windows.Thickness]::new(24)
    $rootGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $rootGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    $mainStack = [System.Windows.Controls.StackPanel]::new()
    $mainStack.Orientation = [System.Windows.Controls.Orientation]::Vertical
    $mainStack.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
    $mainStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

    foreach ($rootEl in $declarativeRoots) {
        $ctrl = ConvertTo-OtterDeclarativeElementWpf -Element $rootEl -Environment $Environment
        if ($ctrl) {
            [void]$mainStack.Children.Add($ctrl)
            if ($rootEl.Tag -in @('window', 'page') -and $rootEl.Label -is [LiteralExpr]) {
                $window.Title = [string]$rootEl.Label.Value
            }
        }
    }

    [void]$rootGrid.Children.Add($mainStack)
    $window.Content = $rootGrid

    return $window
}

function ConvertTo-OtterWpfElement {
    param(
        [Parameter(Mandatory)][Node]$Element,
        [Parameter(Mandatory)][OtterEnvironment]$Environment
    )
    return ConvertTo-OtterDeclarativeElementWpf -Element $Element -Environment $Environment
}

function Show-OtterDeclarativeAppWpf {
    param(
        [Parameter(Mandatory)][ProgramNode]$Program,
        [OtterEnvironment]$Environment = $null,
        [string]$Title = "Otter App"
    )

    $window = ConvertTo-OtterWpfWindow -Program $Program -Environment $Environment -Title $Title
    [void]$window.ShowDialog()
}


Export-ModuleMember -Function `
    Test-OtterUiResource, New-OtterUiResourceValue, Initialize-OtterWpfProvider, `
    Get-OtterUiProperty, Set-OtterUiProperty, Add-OtterUiEventHandler, `
    Add-OtterUiChild, Show-OtterUiResource, `
    Add-OtterUiAnimationWpf, ConvertTo-OtterDeclarativeElementWpf, ConvertTo-OtterWpfElement, `
    Get-OtterUiExpressionValue, ConvertTo-OtterWpfWindow, Show-OtterDeclarativeAppWpf
