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


Export-ModuleMember -Function `
    Test-OtterUiResource, New-OtterUiResourceValue, Initialize-OtterWpfProvider
