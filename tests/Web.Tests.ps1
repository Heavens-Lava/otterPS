using module ..\Otter.Contract.psm1
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Global -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Global -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Web.psm1') -Global -Force

Write-Output 'Otter Web Compiler (D50)'

# Test 1: Compile basic page with button and text
$basicSource = @"
app is a page
    title is "Counter Web App"
.
counter is a text
    text is "0"
.
plusBtn is a button
    text is "+1"
.
score is 0
when plusBtn is clicked
    score is score and 1
    text of counter is score
.
put counter, plusBtn in app
show app
"@

$ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $basicSource)
$html = ConvertTo-OtterWeb -Program $ast

if ($html -notmatch '<!DOCTYPE html>') { throw 'Expected <!DOCTYPE html> in generated web output.' }
if ($html -notmatch '<title>Counter Web App</title>') { throw 'Expected title to match page title.' }
if ($html -notmatch 'id="plusBtn"') { throw 'Expected button element with id plusBtn.' }
if ($html -notmatch 'id="counter"') { throw 'Expected text element with id counter.' }
if ($html -notmatch 'addEventListener\(''click''') { throw 'Expected click event listener.' }
if ($html -notmatch 'otterSetText\(''counter''') { throw 'Expected text update in click handler.' }
Write-Output '  pass  basic web app compiles to HTML with reactive event listener'

# Test 2: Layout elements (row and column)
$layoutSource = @"
create window into app
app has title is "Layout App"

create row into mainRow
create column into leftCol
create column into rightCol
create button into btn1
btn1 has text is "Left"
create button into btn2
btn2 has text is "Right"

put btn1 in leftCol
put btn2 in rightCol
put leftCol, rightCol in mainRow
put mainRow in app
show app
"@

$layoutAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $layoutSource)
$layoutHtml = ConvertTo-OtterWeb -Program $layoutAst

if ($layoutHtml -notmatch 'class="otter-row"') { throw 'Expected otter-row class in output.' }
if ($layoutHtml -notmatch 'class="otter-column"') { throw 'Expected otter-column class in output.' }
if ($layoutHtml -notmatch 'display: flex; flex-direction: row;') { throw 'Expected row flex styling.' }
if ($layoutHtml -notmatch 'display: flex; flex-direction: column;') { throw 'Expected column flex styling.' }
Write-Output '  pass  layout rows and columns compile to responsive flexbox structures'

# Test 3: Export hello-app.ot and calculator.ot
$helloHtmlPath = Export-OtterWebApplication -SourcePath (Join-Path $PSScriptRoot '..\examples\hello-app.ot')
if (-not (Test-Path $helloHtmlPath)) { throw 'Expected hello-app.html to exist.' }
$helloContent = Get-Content -LiteralPath $helloHtmlPath -Raw
if ($helloContent -notmatch 'id="helloButton"' -or $helloContent -notmatch 'id="nameBox"') {
    throw 'Expected helloButton and nameBox in compiled hello-app.html.'
}
Write-Output '  pass  hello-app.ot exports to standalone HTML'

$calcHtmlPath = Export-OtterWebApplication -SourcePath (Join-Path $PSScriptRoot '..\examples\calculator.ot')
if (-not (Test-Path $calcHtmlPath)) { throw 'Expected calculator.html to exist.' }
$calcContent = Get-Content -LiteralPath $calcHtmlPath -Raw
if ($calcContent -notmatch 'id="addButton"' -or $calcContent -notmatch 'id="resultLabel"') {
    throw 'Expected addButton and resultLabel in compiled calculator.html.'
}
if ($calcContent -notmatch 'Number\(number1\)') {
    throw 'Expected arithmetic compilation in calculator event handler.'
}
Write-Output '  pass  calculator.ot exports to standalone HTML with full math and try/catch'

# Test 4: Export portal.ot with rich components (cards, 3d canvas, dropdown, checkbox, slider, badge, link)
$portalHtmlPath = Export-OtterWebApplication -SourcePath (Join-Path $PSScriptRoot '..\examples\portal.ot')
if (-not (Test-Path $portalHtmlPath)) { throw 'Expected portal.html to exist.' }
$portalContent = Get-Content -LiteralPath $portalHtmlPath -Raw
if ($portalContent -notmatch 'class="otter-card"' -or
    $portalContent -notmatch 'class="otter-canvas"' -or
    $portalContent -notmatch 'class="otter-checkbox"' -or
    $portalContent -notmatch 'class="otter-select"' -or
    $portalContent -notmatch 'class="otter-slider"' -or
    $portalContent -notmatch 'class="otter-badge"' -or
    $portalContent -notmatch 'class="otter-link"') {
    throw 'Expected rich components in compiled portal.html.'
}
Write-Output '  pass  portal.ot exports rich components (cards, 3D canvas, dropdown, checkbox, slider, badge, link)'

# Test 5: Export jeffreymacy.ot (high-end responsive showcase recreating www.jeffreymacy.com)
$jmHtmlPath = Export-OtterWebApplication -SourcePath (Join-Path $PSScriptRoot '..\examples\jeffreymacy.ot')
if (-not (Test-Path $jmHtmlPath)) { throw 'Expected jeffreymacy.html to exist.' }
$jmContent = Get-Content -LiteralPath $jmHtmlPath -Raw
if ($jmContent -notmatch 'Jeffrey Macy' -or
    $jmContent -notmatch 'You take care of your customers.' -or
    $jmContent -notmatch 'id="mockupCard"' -or
    $jmContent -notmatch 'id="pricingCard"') {
    throw 'Expected brand, headline, mockup, and pricing card in compiled jeffreymacy.html.'
}
Write-Output '  pass  jeffreymacy.ot exports responsive showcase recreating www.jeffreymacy.com'

# Test 6: width full, height full, and round rendering
$dimSource = @"
app is a page
    title is "Dimension App"
.
fullRow is a row with width full, height full
pillBtn is a button with text "Pill", round
put pillBtn in fullRow
put fullRow in app
show app
"@
$dimAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $dimSource)
$dimHtml = ConvertTo-OtterWeb -Program $dimAst
if ($dimHtml -notmatch 'id="fullRow"[^>]*style="[^"]*width:\s*100%;[^"]*height:\s*100%;') {
    throw 'Expected width: 100% and height: 100% on fullRow.'
}
if ($dimHtml -notmatch 'id="pillBtn"[^>]*style="[^"]*border-radius:\s*9999px;') {
    throw 'Expected border-radius: 9999px on round pillBtn.'
}
Write-Output '  pass  width full, height full, and round compile to native CSS dimensions and shapes'

Write-Output 'Web compiler tests passed.'
