using module ..\Otter.Contract.psm1
. "$PSScriptRoot\TestHost.ps1"
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Global -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Global -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Web.psm1') -Global -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Compiler.JavaScript.psm1') -Global -Force

Write-Output 'River Slate Web UI Renderer Tests'

# Test 1: Dark River Slate default tokens, grid, card subtitle, fields, slider output, variants
$darkSource = @'
app is a page
    title is "River Slate Dark"
    scroll is true
.
mainGrid is a grid
    columns is 2
    spacing is 20
.
formCard is a card
    title is "Account Profile"
    subtitle is "Manage workspace preferences."
.
emailInput is a text box
    label is "Email address"
    placeholder is "dev@otter.example"
    hint is "Used for alerts and receipts."
.
badInput is a text box
    label is "Workspace slug"
    value is "Bad Slug!"
    error is "Use lowercase letters and hyphens only."
.
volumeSlider is a slider
    label is "Alert threshold"
    min is 0
    max is 100
    value is 65
    showvalue is true
.
outlineBtn is an outline button with text "Preview"
ghostBtn is a ghost button with text "Cancel"
disabledBtn is a button with text "Locked", disabled true
okBadge is a badge with text "Healthy", variant "success"
put emailInput, badInput, volumeSlider, outlineBtn, ghostBtn, disabledBtn, okBadge in formCard
put formCard in mainGrid
put mainGrid in app
show app
'@

$darkHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $darkSource))
if ($darkHtml -notmatch '<body class="otter-has-page otter-doc-scroll">') { throw 'Expected dark default body classes without otter-theme-light.' }
if ($darkHtml -notmatch '--otter-bg:\s*#0b1220;') { throw 'Expected River Slate dark background token.' }
if ($darkHtml -notmatch 'id="mainGrid" class="otter-grid"') { throw 'Expected otter-grid container.' }
if ($darkHtml -notmatch '--otter-cols:\s*2;') { throw 'Expected --otter-cols: 2 on grid.' }
if ($darkHtml -notmatch '<p class="otter-card-subtitle">Manage workspace preferences\.</p>') { throw 'Expected card subtitle.' }
if ($darkHtml -notmatch '<label class="otter-field-label" for="emailInput">Email address</label>') { throw 'Expected labeled input field.' }
if ($darkHtml -notmatch 'aria-invalid="true"') { throw 'Expected aria-invalid on error input.' }
if ($darkHtml -notmatch 'data-otter-slider-for="volumeSlider">65</output>') { throw 'Expected slider live output.' }
if ($darkHtml -notmatch 'class="otter-button otter-button-outline"') { throw 'Expected outline button variant.' }
if ($darkHtml -notmatch 'class="otter-button otter-button-ghost"') { throw 'Expected ghost button variant.' }
if ($darkHtml -notmatch 'id="disabledBtn" class="otter-button" disabled>') { throw 'Expected disabled button.' }
if ($darkHtml -notmatch 'class="otter-badge otter-badge-success"') { throw 'Expected success badge variant.' }
Write-Output '  pass  dark River Slate default tokens, grid, fields, variants, and slider output'

# Test 2: Light River Slate opt-in theme + nested dark card
$lightSource = @'
app is a page
    title is "River Slate Light"
    theme is "light"
    scroll is true
.
lightCard is a card
    title is "Light Surface"
.
darkCard is a card
    title is "Dark Preview"
    theme is "dark"
.
put lightCard, darkCard in app
show app
'@

$lightHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $lightSource))
if ($lightHtml -notmatch '<body class="otter-has-page otter-doc-scroll otter-theme-light">') { throw 'Expected otter-theme-light class on body.' }
if ($lightHtml -notmatch '--otter-bg:\s*#f4f7fb;') { throw 'Expected River Slate light background.' }
if ($lightHtml -notmatch '--otter-text:\s*#0b1d36;') { throw 'Expected River Slate light foreground.' }
if ($lightHtml -notmatch 'id="darkCard" class="otter-card otter-theme-dark"') { throw 'Expected embedded dark theme card.' }
Write-Output '  pass  light River Slate theme opt-in and embedded container theme'

# Test 3: Backward compatibility for unlabeled controls and author overrides
$compatSource = @'
app is a page
    title is "Compat"
    background is "#101828"
    padding is 0
.
plainBtn is a button with text "Go"
plainBox is a text box with placeholder "Name"
put plainBtn, plainBox in app
show app
'@

$compatHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $compatSource))
if ($compatHtml -notmatch '--otter-bg:\s*#101828;') { throw 'Expected author background override to win.' }
if ($compatHtml -notmatch 'padding:\s*0px;') { throw 'Expected author padding 0 override to win.' }
if ($compatHtml -notmatch '<button id="plainBtn" class="otter-button">Go</button>') { throw 'Expected exact legacy button markup.' }
if ($compatHtml -match 'class="otter-field"') { throw 'Plain controls without label/hint/error must not add wrapper.' }
Write-Output '  pass  backward compatibility preserved for plain controls and author overrides'

Write-Output 'All River Slate Web UI renderer tests passed.'
