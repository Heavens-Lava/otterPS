# ValueFirstProperties.Tests.ps1
# Automated verification for Value-First Property Syntax (<value> <property>),
# multi-line `with ... .` blocks, legacy compatibility, UI property validation,
# and byte-for-byte HTML equivalence in otterPS.

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $repoRoot 'src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\Otter.Parser.psm1') -Force
Import-Module (Join-Path $repoRoot 'src\Otter.Web.psm1') -Force

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Assert-ParserFails {
    param([string]$Source, [string]$ExpectedPattern, [string]$Label)
    $caught = $false
    try {
        [void](ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $Source))
    } catch {
        $caught = $true
        if ($_.Exception.Message -notlike "*$ExpectedPattern*") {
            throw "[$Label] Expected message matching '*$ExpectedPattern*', got: $($_.Exception.Message)"
        }
    }
    if (-not $caught) {
        throw "[$Label] Expected parser error matching '*$ExpectedPattern*', but parsing succeeded."
    }
    Write-Output "  pass  rejects: $Label"
}

Write-Output '=== otterPS Value-First Property Syntax Tests ==='

# 1. Section 3 full multi-line + single-line navbar vs legacy byte-for-byte HTML equivalence
$newSrc = @'
app is a page with
    "Otter Site" title,
    true hideheader,
    true scroll,
    full width,
    "#f4f7fb" background,
    "#0f1f36" foreground,
    0 spacing,
    0 padding
.

brandMark is a image with "/static/logo.png" source, "Otter" alt, 34 width, 34 height, 17 radius
brandName is a link with "Otter" text, "/" url, "#ffffff" foreground, 22 size, 700 weight
brandGroup is a row with 10 spacing, middle align
put brandMark, brandName in brandGroup

navPlayground is a link with
    "Playground" text,
    "/playground/" url,
    "#d7e3f4" foreground,
    14 size,
    600 weight,
    "padding: 22px 0; border-bottom: 2px solid transparent;" customstyle
.

navLibrary is a link with
    "Library" text,
    "/library/" url,
    "#d7e3f4" foreground,
    14 size,
    500 weight
.

navPulse is a link with
    "Otter Pulse" text,
    "/otter-pulse/" url,
    "#d7e3f4" foreground,
    14 size,
    500 weight
.

navDocs is a link with "Documentation" text, "/docs/" url, 14 size, 500 weight

docsSearchButton is a button with
    "Search docs & library...  Ctrl K" text,
    12 size,
    500 weight,
    "#173252" background,
    "#dbeafe" foreground,
    8 radius,
    "8px 14px" padding,
    "border: 1px solid #315377; min-width: 214px; text-align: left;" customstyle
.

navLinks is a row with
    18 spacing,
    middle align
.

put navPlayground, navLibrary, navPulse, navDocs, docsSearchButton in navLinks

topBar is a row with
    spread,
    middle align,
    36 spacing,
    full width,
    "#0b1d36" background,
    "0 40px" padding,
    64 height,
    "box-sizing: border-box; position: sticky; top: 0; z-index: 50;" customstyle
.

put brandGroup, navLinks in topBar
put topBar in app
show app
'@

$legacySrc = @'
app is a page with title "Otter Site", hideheader true, scroll true, width full, background "#f4f7fb", foreground "#0f1f36", spacing 0, padding 0

brandMark is a image with source "/static/logo.png", alt "Otter", width 34, height 34, radius 17
brandName is a link with text "Otter", url "/", foreground "#ffffff", size 22, weight 700
brandGroup is a row with spacing 10, align middle
put brandMark, brandName in brandGroup

navPlayground is a link with text "Playground", url "/playground/", foreground "#d7e3f4", size 14, weight 600, customstyle "padding: 22px 0; border-bottom: 2px solid transparent;"
navLibrary is a link with text "Library", url "/library/", foreground "#d7e3f4", size 14, weight 500
navPulse is a link with text "Otter Pulse", url "/otter-pulse/", foreground "#d7e3f4", size 14, weight 500
navDocs is a link with text "Documentation", url "/docs/", size 14, weight 500
docsSearchButton is a button with text "Search docs & library...  Ctrl K", size 12, weight 500, background "#173252", foreground "#dbeafe", radius 8, padding "8px 14px", customstyle "border: 1px solid #315377; min-width: 214px; text-align: left;"
navLinks is a row with spacing 18, align middle
put navPlayground, navLibrary, navPulse, navDocs, docsSearchButton in navLinks
topBar is a row with spread, align middle, spacing 36, width full, background "#0b1d36", padding "0 40px", height 64, customstyle "box-sizing: border-box; position: sticky; top: 0; z-index: 50;"
put brandGroup, navLinks in topBar
put topBar in app
show app
'@

$htmlNew = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $newSrc))
$htmlLegacy = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $legacySrc))
Assert-True ($htmlNew -ceq $htmlLegacy -and $htmlNew.Length -gt 500) 'Value-first multi-line navbar must compile byte-for-byte identically to legacy property-first navbar'
Write-Output '  pass  Section 3 multi-line + single-line navbar matches legacy HTML byte-for-byte'

# 2. Mixed property order, expressions, custom types, variables, and inline `has`
$exprSrc = @'
a Person has
    name
    age
    role
.

baseAge is 25
userLabel is "Ada"
author has
    title is "Engineer"
.

p1 is a Person with
    userLabel name,
    baseAge plus 4 age,
    title of author role
.

p2 is a Person with "Grace" name, 35 age, "Admiral" role
inlineObj has "Otter" lang, 101 version
mixedBtn is a button with "Click" text, size 14, middle align, width full, spread
'@
$exprAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $exprSrc)
Assert-True ($exprAst.Statements.Count -eq 8) "Expected 8 statements, got $($exprAst.Statements.Count)"
$p1 = $exprAst.Statements[4]
Assert-True ($p1.Properties[0].Target.Name -eq 'name' -and $p1.Properties[0].Value.Name -eq 'userLabel') 'Rule 9A two-identifier entry parses as value-first'
Assert-True ($p1.Properties[1].Target.Name -eq 'age' -and $p1.Properties[1].Value.GetType().Name -eq 'MathExpr') 'Expression-valued property parses cleanly'
Assert-True ($p1.Properties[2].Target.Name -eq 'role' -and $p1.Properties[2].Value.GetType().Name -eq 'PropertyAccessExpr') 'Property-access expression value parses cleanly'
$mixedBtn = $exprAst.Statements[7]
Assert-True ($mixedBtn.Properties.Count -eq 5 -and $mixedBtn.Properties[0].Target.Name -eq 'text' -and $mixedBtn.Properties[1].Target.Name -eq 'size' -and $mixedBtn.Properties[2].Value.Value -eq 'middle' -and $mixedBtn.Properties[3].Value.Value -eq 'full' -and $mixedBtn.Properties[4].Value.Value -eq $true) 'Mixed order + UI keywords + bare flag'
Write-Output '  pass  expressions, Rule 9A variables, custom types, inline has, and mixed order'

# 3. Negative diagnostics
Assert-ParserFails 'b is a button with "A" text, "B" text' 'Duplicate property' 'duplicate property (value-first)'
Assert-ParserFails 'b is a button with "A" text, text "B"' 'Duplicate property' 'duplicate property (mixed)'
Assert-ParserFails 'b is a button with "Click" bogusProp' 'Unknown property' 'unknown UI property'
Assert-ParserFails 'b is a button with true size' 'expects a number' 'invalid boolean for size'
Assert-ParserFails 'r is a row with "wide" spacing' 'expects a number' 'invalid string for spacing'
Assert-ParserFails 'p is a page with "yes" scroll' 'true/false' 'invalid string for boolean scroll'
Assert-ParserFails 's is a slider with "yes" showvalue' 'true/false' 'invalid string for boolean showvalue'
Assert-ParserFails 'g is a grid with "two" columns' 'expects a number' 'invalid string for numeric columns'
Assert-ParserFails 'p is a page with 123 theme' 'expects text' 'invalid number for text theme'
Assert-ParserFails 'l is a link with 123 url' 'expects text' 'invalid number for url'
Assert-ParserFails 'r is a row with "diagonal" align' 'alignment direction' 'invalid string alignment'
Assert-ParserFails 'r is a row with sideways align' 'alignment direction' 'invalid identifier alignment'
Assert-ParserFails 'b is a button with 14' 'expected a property name' 'missing property name after value'
Assert-ParserFails 'b is a button with text is' 'expected a value' 'missing value after is'
Assert-ParserFails "b is a button with`n    `"Hi`" text, 14 size`n." 'each property on its own line' 'two entries on one multiline line'

# 4. River Slate UI components with value-first syntax
$riverSlateVf = @'
app is a page with
    "River Slate Value-First" title,
    "light" theme,
    true scroll
.
mainGrid is a grid with 2 columns, 20 spacing
infoCard is a card with
    "Form Controls" title,
    "Validated under value-first syntax." subtitle,
    "dark" theme
.
emailBox is a text box with
    "Email address" label,
    "dev@otter.example" placeholder,
    "Used for notifications." hint,
    "Invalid email" error
.
thresholdSlider is a slider with
    "CPU threshold" label,
    0 min,
    100 max,
    65 value,
    5 step,
    true showvalue
.
primaryBtn is a primary button with "Primary" text
outlineBtn is an outline button with "Outline" text
ghostBtn is a ghost button with "Ghost" text
disabledBtn is a button with "Locked" text, true disabled
okBadge is a badge with "Healthy" text, "success" variant
put emailBox, thresholdSlider, primaryBtn, outlineBtn, ghostBtn, disabledBtn, okBadge in infoCard
put infoCard in mainGrid
put mainGrid in app
show app
'@
$rsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $riverSlateVf)
Assert-True ($rsAst.Statements.Count -gt 10) "Expected River Slate value-first AST to parse cleanly"
Write-Output '  pass  River Slate components with value-first syntax (theme, label, hint, error, subtitle, showvalue, step, columns, outline/ghost buttons)'

Write-Output '=== ALL otterPS Value-First Property Syntax Tests PASSED ==='
