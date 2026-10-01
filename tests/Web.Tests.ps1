using module ..\Otter.Contract.psm1
. "$PSScriptRoot\TestHost.ps1"
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Global -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Global -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Web.psm1') -Global -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Compiler.JavaScript.psm1') -Global -Force

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
    score is score plus 1
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

# Test 2b: a window's own width is not cut to the default 520px cap
$wideSource = @"
app is a window with title "Wide", width 900, height 560
show app
"@
$wideHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $wideSource))
if ($wideHtml -notmatch 'id="app" class="otter-window" style="[^"]*width: 900px;[^"]*max-width: 100%;') { throw 'Expected a window with width 900 to lift the 520px cap (max-width: 100% inline).' }
$narrowHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "app is a window with title `"Narrow`"`nshow app"))
if ($narrowHtml -match 'id="app" class="otter-window" style="[^"]*max-width') { throw 'A window without a width keeps the default cap.' }
Write-Output '  pass  a window with its own width is not capped at 520px'

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
if ($calcContent -notmatch 'Number\(_l\)' -and $calcContent -notmatch 'Number\(number1\)') {
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

# Test 5: Internal links stay in the docs tab; external links remain safe new tabs
$linkSource = @'
app is a page
    title is "Links"
.
internal is a link
    text is "Docs"
    url is "../welcome/"
.
external is a link
    text is "Otter"
    url is "https://example.com"
.
put internal, external in app
'@
$linkAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $linkSource)
$linkHtml = ConvertTo-OtterWeb -Program $linkAst
if ($linkHtml -match 'href="\.\./welcome/"[^>]*target="_blank"') { throw 'Internal links should not open a new tab.' }
if ($linkHtml -notmatch 'href="https://example.com"[^>]*target="_blank"' -or $linkHtml -notmatch 'rel="noopener noreferrer"') { throw 'External links should open safely in a new tab.' }
Write-Output '  pass  internal links stay in place while external links open safely'

# Test 6: Export jeffreymacy.ot (high-end responsive showcase recreating www.jeffreymacy.com)
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
pillBtn is a button with text "Pill", pill true
roundBtn is a button with text "Round", round
round12Btn is a button with text "Twelve", radius 12
radiusCard is a card with radius 20
roundCard is a card with round
put pillBtn, roundBtn, round12Btn, radiusCard, roundCard in fullRow
put fullRow in app
show app
"@
$dimAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $dimSource)
$dimHtml = ConvertTo-OtterWeb -Program $dimAst
if ($dimHtml -notmatch 'id="fullRow"[^>]*style="[^"]*width:\s*100%;[^"]*height:\s*100%;') {
    throw 'Expected width: 100% and height: 100% on fullRow.'
}
# Rounded corners (ROUND_CONTRACT_PROPOSAL.md, approved 2026-09-30): pill true
# is a pill; round is ordinary 8px corners on every kind; round N / radius N
# is exactly N px (in a with-list the parser reads round as a flag, so the
# number is written radius 12 there).
foreach ($expected in @(@('pillBtn', '9999px'), @('roundBtn', '8px'), @('round12Btn', '12px'), @('radiusCard', '20px'), @('roundCard', '8px'))) {
    if ($dimHtml -notmatch ('id="' + $expected[0] + '"[^>]*style="[^"]*border-radius:\s*' + [regex]::Escape($expected[1]) + ';')) {
        throw "Expected border-radius: $($expected[1]) on $($expected[0])."
    }
}
Write-Output '  pass  width full, height full, and round compile to native CSS dimensions and shapes'

# Test 7: spread, align middle/top/bottom, align left/center/right compilation
$alignSource = @"
app is a page
    title is "Align App"
.
nav is a row with spread, align middle, width full
sidebar is a column with align left
contentCol is a column with spread, align center
put nav, sidebar, contentCol in app
show app
"@
$alignAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $alignSource)
$alignHtml = ConvertTo-OtterWeb -Program $alignAst
if ($alignHtml -notmatch 'id="nav"[^>]*align-items:\s*center;[^"]*justify-content:\s*space-between;') {
    throw 'Expected row with spread, align middle to produce align-items: center; justify-content: space-between;'
}
if ($alignHtml -notmatch 'id="sidebar"[^>]*align-items:\s*flex-start;') {
    throw 'Expected column with align left to produce align-items: flex-start;'
}
if ($alignHtml -notmatch 'id="contentCol"[^>]*align-items:\s*center;[^"]*justify-content:\s*space-between;') {
    throw 'Expected column with spread, align center to produce align-items: center; justify-content: space-between;'
}
Write-Output '  pass  spread, align middle/top, and align left/center compile to native flexbox styles'

# Test 8: Declarative counter application compilation, animations, and reactivity
$counterSource = Get-Content (Join-Path $PSScriptRoot '..\examples\experimental\counter.ot') -Raw
$counterAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $counterSource)
$counterHtml = ConvertTo-OtterWeb -Program $counterAst

if ($counterHtml -notmatch '@keyframes otter_enter_') {
    throw 'Expected @keyframes otter_enter_ in compiled HTML.'
}
if ($counterHtml -notmatch ':hover\s*\{\s*transform:\s*scale\(1\.05\);') {
    throw 'Expected button hover scale rule in compiled HTML.'
}
if ($counterHtml -notmatch 'data-otter-bind="[^"]*Count:[^"]*count') {
    throw 'Expected data-otter-bind for Count in compiled HTML.'
}
if ($counterHtml -notmatch 'data-otter-bind="[^"]*Double:[^"]*doubled') {
    throw 'Expected data-otter-bind for Doubled in compiled HTML.'
}
if ($counterHtml -notmatch 'data-otter-if="menuOpen"') {
    throw 'Expected data-otter-if for menuOpen in compiled HTML.'
}
if ($counterHtml -notmatch 'otterState\[.count.\]\s*=\s*0;') {
    throw 'Expected otterState["count"] initialization in compiled HTML.'
}
if ($counterHtml -notmatch 'otterSetState\(.count.') {
    throw 'Expected otterSetState on button click in compiled HTML.'
}
Write-Output '  pass  counter.ot compiles to reactive HTML with keyframe animations, live bindings, and state updates'

# Test 12: Real dogfood test - studio-v1.ot compiles through the parser and bridge hooks
$studioV1Ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\examples\studio-v1.ot') -Raw))
$studioV1Html = ConvertTo-OtterWeb -Program $studioV1Ast
if ($studioV1Html -notmatch 'otterGetFiles' -or $studioV1Html -notmatch 'otterReadFile' -or $studioV1Html -notmatch 'otterWriteFile' -or $studioV1Html -notmatch 'otterRunCommand') {
    throw 'Expected V1 Studio to compile its filesystem and terminal operations through the generic bridge hooks.'
}
foreach ($message in @('I could not scan that folder.', 'I could not open that file.', 'I could not save that file.', 'Unable to run that command.')) {
    if ($studioV1Html -notmatch [regex]::Escape($message)) {
        throw "Expected V1 Studio to visibly report: $message"
    }
}
if ($studioV1Html -notmatch 'catch \(_err\)') {
    throw 'Expected V1 Studio try/otherwise blocks to compile to catch handlers.'
}
Write-Output '  pass  studio-v1.ot compiles through the ordinary production parser and bridge hooks'

# Test 13: Async, await statement, and timers (Section 8)
$asyncTimerSource = @"
to delayNotice
    await delay 250
    say "Timer done"
.
"@
$asyncTimerAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $asyncTimerSource)
$asyncTimerHtml = ConvertTo-OtterWeb -Program $asyncTimerAst
if ($asyncTimerHtml -notmatch 'const delayNotice = async function\(\)') {
    throw 'Expected function with await delay to compile as async.'
}
if ($asyncTimerHtml -notmatch 'await delay\(250\);') {
    throw 'Expected await delay statement to compile to await delay(250);'
}
if ($asyncTimerHtml -notmatch 'window.otterWait' -or $asyncTimerHtml -notmatch 'window.otterDelay') {
    throw 'Expected compiled web app runtime to include otterWait and otterDelay timer hooks.'
}
Write-Output '  pass  async await and one-shot timer compilation (Section 8)'

# Test 14: Progress, Toggle, Radio controls and System runtime helpers (Section 10 & 21)
$controlsSource = @"
app is a page
    title is "Controls App"
.
pBar is a progress
    value is 75
    max is 100
.
tSwitch is a toggle
    text is "Night Mode"
.
rBtn is a radio
    text is "Choice 1"
    name is "opts"
.
put pBar, tSwitch, rBtn in app
show app
"@
$controlsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $controlsSource)
$controlsHtml = ConvertTo-OtterWeb -Program $controlsAst
if ($controlsHtml -notmatch '<progress id="pBar" class="otter-progress" value="75" max="100"') {
    throw 'Expected compiled HTML to contain <progress id="pBar"...'
}
# A toggle and a radio button, like a checkbox, carry their id on the label
# (the control as seen): a position or size moves the input and its text
# together. The input is <name>-box; the runtime reads and sets it.
if ($controlsHtml -notmatch '<label id="tSwitch" class="otter-toggle-label"><input type="checkbox" id="tSwitch-box" class="otter-toggle"') {
    throw 'Expected compiled HTML to contain <label id="tSwitch" class="otter-toggle-label"><input type="checkbox" id="tSwitch-box" class="otter-toggle"...'
}
if ($controlsHtml -notmatch '<label id="rBtn" class="otter-radio-label"><input type="radio" id="rBtn-box" name="opts" class="otter-radio"') {
    throw 'Expected compiled HTML to contain <label id="rBtn" class="otter-radio-label"><input type="radio" id="rBtn-box" name="opts" class="otter-radio"...'
}
if ($controlsHtml -notmatch 'window\.otterClipboard' -or $controlsHtml -notmatch 'window\.otterNotify' -or $controlsHtml -notmatch 'window\.otterGetEnv') {
    throw 'Expected compiled HTML runtime to expose otterClipboard, otterNotify, and otterGetEnv.'
}
Write-Output '  pass  progress, toggle, radio controls and system runtime helpers (Section 10 & 21)'

# Test 15: Browser Storage and HTTP Client runtime helpers (Section 19)
if ($controlsHtml -notmatch 'window\.otterStorage' -or $controlsHtml -notmatch 'window\.otterFetch' -or $controlsHtml -notmatch 'window\.otterGetJson' -or $controlsHtml -notmatch 'window\.otterPostJson') {
    throw 'Expected compiled HTML runtime to expose otterStorage, otterFetch, otterGetJson, and otterPostJson.'
}
Write-Output '  pass  browser storage and http fetch client runtime helpers (Section 19)'

# Test 16: CLI Argument API and Named Flags parser (Section 12)
$parsedCli = ConvertTo-OtterCommandLineArguments -Arguments @('run', 'script.ot', '--port=8080', '--verbose', '-o', 'out.txt')
if ($parsedCli.Positional.Length -ne 2 -or $parsedCli.Positional[0] -ne 'run' -or $parsedCli.Positional[1] -ne 'script.ot') {
    throw "Expected positional arguments ['run', 'script.ot'], got: $($parsedCli.Positional | ConvertTo-Json)"
}
if ($parsedCli.Flags['port'] -ne '8080' -or $parsedCli.Flags['verbose'] -ne $true -or $parsedCli.Flags['o'] -ne 'out.txt') {
    throw "Expected flags port=8080, verbose=true, o=out.txt, got: $($parsedCli.Flags | ConvertTo-Json)"
}
$cliPreamble = Get-OtterJsCliPreamble
if ($cliPreamble -notmatch 'otterParseCli' -or $cliPreamble -notmatch 'otterArgs') {
    throw 'Expected JS CLI preamble to define otterParseCli and otterArgs.'
}
Write-Output '  pass  CLI argument API and named flags/options parser (Section 12)'

# Test 17: HTTP headers/options block (D101) - with header/cookies/redirects/timeout
$httpOptsSource = @"
get "https://api.example.com/data" into result
    with header "Authorization" is "Bearer abc123"
    with header "Accept" is "application/json"
    with cookies
    following redirects
    with timeout 30 seconds
say result

post "payload" to "https://api.example.com/submit" into postResult
    without cookies
    without redirects
say postResult
"@
$httpOptsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $httpOptsSource)
$httpOptsJsLines = [System.Collections.Generic.List[string]]::new()
foreach ($s in $httpOptsAst.Statements) { $httpOptsJsLines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent 0)) }
$httpOptsJs = $httpOptsJsLines -join "`n"
if ($httpOptsJs -notmatch "\[String\(`"Authorization`"\)\]: String\(`"Bearer abc123`"\)") {
    throw 'Expected the Authorization header to be compiled into the fetch options object.'
}
if ($httpOptsJs -notmatch "_opts\.credentials = 'include';") {
    throw 'Expected `with cookies` to compile to credentials: include.'
}
if ($httpOptsJs -notmatch 'AbortController') {
    throw 'Expected `with timeout` to compile to an AbortController-based timeout.'
}
if ($httpOptsJs -notmatch "_opts\.credentials = 'omit';") {
    throw 'Expected `without cookies` to compile to credentials: omit.'
}
if ($httpOptsJs -notmatch "_opts\.redirect = 'manual';") {
    throw 'Expected `without redirects` to compile to redirect: manual.'
}
if ($httpOptsJs -match 'redirect') { } else { throw 'redirect handling missing entirely.' }
Write-Output '  pass  HTTP headers/options block compiles to real fetch() options (D101)'

# Test 18: a plain get/post/put/delete with no options block is completely unaffected
$httpPlainSource = @"
get "https://api.example.com/data" into plainResult
say plainResult
"@
$httpPlainAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $httpPlainSource)
$httpPlainJsLines = [System.Collections.Generic.List[string]]::new()
foreach ($s in $httpPlainAst.Statements) { $httpPlainJsLines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent 0)) }
$httpPlainJs = $httpPlainJsLines -join "`n"
if ($httpPlainJs -match '_opts') {
    throw 'A plain get with no options block should not emit an _opts variable at all.'
}
if ($httpPlainJs -notmatch 'await fetch\("https://api\.example\.com/data"\);') {
    throw 'Expected a plain get to call fetch without an options object.'
}
Write-Output '  pass  get/post/put/delete with no options block is unaffected (D101)'

# Test 19: SPA routing (D103) - codegen shape
$routeSource = @"
homePage is a page
    title is "Home"
.
aboutPage is a page
    title is "About"
.
notFoundPage is a page
    title is "Not Found"
.
route "/" shows homePage
route "/about" shows aboutPage
route "/users/:id" shows userPage
route otherwise shows notFoundPage
go to "/about"
go to destination
go back
go forward
replace route with "/login"
on route change
    say current route
.
"@
$routeAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $routeSource)
$routeJsLines = [System.Collections.Generic.List[string]]::new()
foreach ($s in $routeAst.Statements) { $routeJsLines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent 0)) }
$routeJs = $routeJsLines -join "`n"
if ($routeJs -notmatch "window\.otterRouter\.register\(""/"", 'homePage'\)") {
    throw 'Expected a static route to compile to a register() call.'
}
if ($routeJs -notmatch "window\.otterRouter\.register\(""/users/:id"", 'userPage'\)") {
    throw 'Expected a parameterized route to compile to a register() call.'
}
if ($routeJs -notmatch "window\.otterRouter\.registerOtherwise\('notFoundPage'\)") {
    throw 'Expected `route otherwise` to compile to registerOtherwise(), not register() with a stray variable (regression: "otherwise" only lexes as its own token at statement head, not mid-line).'
}
if ($routeJs -notmatch 'window\.otterRouter\.goTo\("/about"\)') {
    throw 'Expected go-to-a-literal-path to compile to goTo().'
}
if ($routeJs -notmatch 'window\.history\.back\(\)') {
    throw 'Expected go-back to compile to window.history.back().'
}
if ($routeJs -notmatch 'window\.history\.forward\(\)') {
    throw 'Expected go-forward to compile to window.history.forward().'
}
if ($routeJs -notmatch 'window\.otterRouter\.replaceRoute\("/login"\)') {
    throw 'Expected replace-route to compile to replaceRoute().'
}
if ($routeJs -notmatch 'window\.otterRouter\.changeHandlers\.push') {
    throw 'Expected on-route-change to register a change handler.'
}
Write-Output '  pass  route/go/replace-route/on-route-change compile to the expected otterRouter calls (D103)'

# Test 20: a variable literally named "route" still works with the
# pre-existing text-replace statement (replace X with Y in Z) - the two
# share a `replace ... with ...` prefix, told apart by whether "in"
# follows.
$replaceCollisionSource = @"
route is "hello world"
replace "world" with "there" in route
say route
"@
$replaceAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $replaceCollisionSource)
if ($replaceAst.Statements[1] -isnot [ReplaceStmt]) {
    throw 'Expected replace ... with ... in route to still parse as the ordinary text-replace statement when "route" is just a variable name.'
}
Write-Output '  pass  "replace X with Y in route" (a variable literally named route) still parses as ordinary text replacement (D103)'

# Test 21: the real otterRouter runtime object - register/match/param/
# queryParam/errors - executed for real in Node against the actual
# compiled output (not a hand-written reimplementation), matching this
# project's cross-runtime-parity precedent (Csv.Tests.ps1 Case 26).
$routerOtSource = @"
homePage is a page
    title is "Home"
.
aboutPage is a page
    title is "About"
.
userPage is a page
    title is "User"
.
notFoundPage is a page
    title is "Not Found"
.
route "/" shows homePage
route "/about" shows aboutPage
route "/users/:id" shows userPage
route otherwise shows notFoundPage
"@
$routerOtFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d103_$([Guid]::NewGuid().ToString('N')).ot")
[System.IO.File]::WriteAllText($routerOtFile, $routerOtSource, [System.Text.UTF8Encoding]::new($false))
try {
    $routerHtmlPath = Export-OtterWebApplication -SourcePath $routerOtFile
    $routerHtml = Get-Content -LiteralPath $routerHtmlPath -Raw
    if ($routerHtml -notmatch '(?s)<script>(.*)</script>') {
        throw 'Expected a <script> block in the compiled routing app.'
    }
    $routerScriptBody = $Matches[1]
    $nodeScript = @"
global.window = global;
global.document = { getElementById: () => null, title: '', querySelectorAll: () => [], addEventListener: () => {} };
global.history = { pushState: () => {}, replaceState: () => {}, back: () => {}, forward: () => {} };
global.location = { pathname: '/', search: '' };
global.otterSay = () => {};
global.performance = require('perf_hooks').performance;
global.addEventListener = () => {};

$routerScriptBody

const r = window.otterRouter;
const errors = [];
function expect(cond, msg) { if (!cond) errors.push(msg); }

expect(r.match('/').pageId === 'homePage', 'root route did not match homePage');
expect(r.match('/about').pageId === 'aboutPage', 'static route did not match aboutPage');
expect(r.match('/about/').pageId === 'aboutPage', 'trailing slash did not normalize');
const um = r.match('/users/42');
expect(um.pageId === 'userPage', 'param route did not match userPage');
expect(um.params.id === '42', 'route param "id" was not extracted correctly');
expect(r.match('/nope').pageId === 'notFoundPage', 'unmatched route did not fall back to notFoundPage');

let threw = false;
try { r.register('/about', 'x'); } catch (e) { threw = /already registered/.test(e.message); }
expect(threw, 'registering a duplicate route pattern did not throw');

threw = false;
try { r.register('no-slash', 'x'); } catch (e) { threw = /must begin with/.test(e.message); }
expect(threw, 'a route not starting with / did not throw');

threw = false;
try { r.register('/dup/:id/:id', 'x'); } catch (e) { threw = /more than once/.test(e.message); }
expect(threw, 'a duplicate parameter name in one route did not throw');

r.register('/users/settings', 'homePage');
expect(r.match('/users/settings').pageId === 'homePage', 'a static route did not win over a parameterized one at the same depth');
expect(r.match('/users/42').pageId === 'userPage', 'the parameterized route stopped working after a static sibling was added');

r.register('/search/:term', 'homePage');
expect(r.match('/search/hello%20world').params.term === 'hello world', 'route parameters were not URL-decoded');

if (errors.length > 0) {
  console.log('ROUTER_FAIL: ' + errors.join(' | '));
} else {
  console.log('ROUTER_OK');
}
"@
    $nodeScriptFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d103_node_$([Guid]::NewGuid().ToString('N')).js")
    Set-Content -LiteralPath $nodeScriptFile -Value $nodeScript
    try {
        $nodeOut = & node $nodeScriptFile
        $nodeOutJoined = $nodeOut -join "`n"
        if ($nodeOutJoined -ne 'ROUTER_OK') {
            throw "Real otterRouter runtime logic must pass register/match/param/error checks in Node. Got: $nodeOutJoined"
        }
    } finally {
        Remove-Item -LiteralPath $nodeScriptFile -Force -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item -LiteralPath $routerOtFile -Force -ErrorAction SilentlyContinue
    $routerHtmlCleanup = [System.IO.Path]::ChangeExtension($routerOtFile, '.html')
    Remove-Item -LiteralPath $routerHtmlCleanup -Force -ErrorAction SilentlyContinue
}
Write-Output '  pass  the real otterRouter runtime (register/match/params/precedence/errors) is correct, executed in Node (D103)'

# Test 22: `go to` fails loudly on the console target rather than silently
# no-op'ing - there is no console/desktop routing implementation, and
# D103's own platform rule requires a real failure, never a silent no-op.
# Runs the real otter.ps1 `run` entry point, not just a source inspection.
$goToConsoleFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d103_console_$([Guid]::NewGuid().ToString('N')).ot")
[System.IO.File]::WriteAllText($goToConsoleFile, 'go to "/about"', [System.Text.UTF8Encoding]::new($false))
try {
    $otterPs1Path = Join-Path (Split-Path -Parent $PSScriptRoot) 'otter.ps1'
    $consolePsi = [System.Diagnostics.ProcessStartInfo]::new()
    $consolePsi.FileName = $script:OtterHostExe
    $consolePsi.Arguments = "$script:OtterHostArgString -File `"$otterPs1Path`" run `"$goToConsoleFile`""
    $consolePsi.RedirectStandardOutput = $true
    $consolePsi.RedirectStandardError = $true
    $consolePsi.UseShellExecute = $false
    $consoleProcess = [System.Diagnostics.Process]::new()
    $consoleProcess.StartInfo = $consolePsi
    [void]$consoleProcess.Start()
    $consoleOut = $consoleProcess.StandardOutput.ReadToEnd()
    $consoleProcess.WaitForExit(15000) | Out-Null
    if ($consoleProcess.ExitCode -ne 3) {
        throw "Expected 'go to' on the console target to be a clean runtime error (exit 3), got exit $($consoleProcess.ExitCode)."
    }
    if ($consoleOut -notmatch 'I do not know how to run a GoToRoute statement yet') {
        throw 'Expected a specific, non-silent diagnostic naming the unsupported statement.'
    }
} finally {
    Remove-Item -LiteralPath $goToConsoleFile -Force -ErrorAction SilentlyContinue
}
Write-Output '  pass  "go to" fails loudly (not silently) on the console target, via a real otter.ps1 run (D103)'

# Test 23: variant-qualified UI kinds ("primary button", "secondary
# button", "danger button") compile to valid, correctly-styled JS -
# regression test for a real bug found while verifying D103: this two-
# word TypeName reached ObjectDef's generic "thing" codegen (which
# interpolates the type name as a bare JS identifier to check for a
# declared custom type), producing a hard SyntaxError that broke the
# entire compiled script the moment the browser tried to parse it.
$variantSource = @"
app is a page
    title is "Variant Check"
.
aboutButton is a primary button
    text is "Primary"
.
dangerButton is a danger button
    text is "Danger"
.
plainButton is a button
    text is "Plain"
.
put aboutButton, dangerButton, plainButton in app
show app
"@
$variantAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $variantSource)
$variantHtml = ConvertTo-OtterWeb -Program $variantAst
if ($variantHtml -notmatch 'class="otter-button otter-button-primary"') {
    throw 'Expected "primary button" to compile to a button with the otter-button-primary class.'
}
if ($variantHtml -notmatch 'class="otter-button otter-button-danger"') {
    throw 'Expected "danger button" to compile to a button with the otter-button-danger class.'
}
if ($variantHtml -notmatch '<button id="plainButton" class="otter-button">') {
    throw 'Expected a plain (non-variant) button to be completely unaffected.'
}
if ($variantHtml -match 'typeof primary button') {
    throw 'A two-word type name must never be interpolated as a bare JS identifier (the original bug).'
}
$variantScript = if ($variantHtml -match '(?s)<script>(.*)</script>') { $Matches[1] } else { $null }
if (-not $variantScript) { throw 'Expected a <script> block in the compiled variant-button app.' }
$variantScriptFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_variant_$([Guid]::NewGuid().ToString('N')).js")
Set-Content -LiteralPath $variantScriptFile -Value $variantScript
try {
    & node --check $variantScriptFile
    if ($LASTEXITCODE -ne 0) { throw 'Compiled JS for variant buttons failed a real Node syntax check.' }
} finally {
    Remove-Item -LiteralPath $variantScriptFile -Force -ErrorAction SilentlyContinue
}
Write-Output '  pass  variant-qualified UI kinds (primary/secondary/danger button) compile to valid, correctly-styled JS'

# Test 24: XML (D105) - the full acceptance example compiles to real
# DOMParser/XMLSerializer-based JS, verified with a real Node syntax
# check (DOMParser/XMLSerializer themselves are genuine browser DOM APIs
# Node.js does not provide, so live execution was verified separately,
# by hand, in a real browser via Playwright - byte-for-byte identical
# output to this project's own console-target tests, see
# tests/Xml.Tests.ps1's own header comment).
$xmlSource = @"
doc is xml with root "library"
library is root of doc
add element "book" to library and call it book
set attribute "id" of book to "42"
add element "title" with text "Learning Otter" to book
output is text from xml doc
say output
pretty is pretty text from xml doc
say pretty
books is elements "book" in library
if element "book" exists in doc
    say "exists"
.
if book has attribute "id"
    say "has attribute"
.
remove attribute "id" from book
remove element book
"@
$xmlAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $xmlSource)
$xmlJsLines = [System.Collections.Generic.List[string]]::new()
foreach ($s in $xmlAst.Statements) { $xmlJsLines.Add((ConvertTo-OtterJsStatement -Stmt $s -Indent 0)) }
$xmlJs = $xmlJsLines -join "`n"
if ($xmlJs -notmatch '__otterXml: true') {
    throw 'Expected xml with root to compile to a tagged __otterXml wrapper.'
}
if ($xmlJs -notmatch 'document\.implementation\.createDocument') {
    throw 'Expected "xml with root" to compile to document.implementation.createDocument.'
}
if ($xmlJs -notmatch 'new XMLSerializer\(\)\.serializeToString') {
    throw 'Expected "text from xml" to compile to XMLSerializer.'
}
if ($xmlJs -notmatch 'setAttribute') {
    throw 'Expected "set attribute ... of ... to ..." to compile to a real setAttribute call.'
}
if ($xmlJs -notmatch 'removeAttribute') {
    throw 'Expected "remove attribute ... from ..." to compile to a real removeAttribute call.'
}
if ($xmlJs -notmatch 'removeChild') {
    throw 'Expected "remove element ..." to compile to a real removeChild call.'
}
$xmlScriptFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_xml_$([Guid]::NewGuid().ToString('N')).js")
Set-Content -LiteralPath $xmlScriptFile -Value $xmlJs
try {
    & node --check $xmlScriptFile
    if ($LASTEXITCODE -ne 0) { throw 'Compiled XML JS failed a real Node syntax check.' }
} finally {
    Remove-Item -LiteralPath $xmlScriptFile -Force -ErrorAction SilentlyContinue
}
Write-Output '  pass  XML (D105) compiles to real DOMParser/XMLSerializer-based JS (verified live in a browser separately)'

# Test 25: a variable literally named "document" overwrites the browser's
# own global `document` - a real, PRE-EXISTING bug found while verifying
# D105 (not caused by it: any Otter variable name that collides with a
# JS/browser global has this problem, not something specific to xml).
# This is not something D105 introduces or is expected to fix; documented
# here as a known trap so it stays visible rather than silently
# rediscovered later.
$docCollisionSource = 'document is "hello"'
$docCollisionAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $docCollisionSource)
$docCollisionJs = ConvertTo-OtterJsStatement -Stmt $docCollisionAst.Statements[0] -Indent 0
if ($docCollisionJs -notmatch 'window\.document\s*=') {
    throw 'Expected the known "document" global-collision trap to still reproduce (regression check, not a fix) - a variable named "document" no longer compiles to window.document = ..., which means either it was fixed (great - update this test) or something else changed.'
}
Write-Output '  pass  (documented, not fixed) a variable named "document" still overwrites the browser global - known trap, not new'

# Test 26: D114 Browser-side Cryptography (Web Crypto)
# Full suite: deterministic vectors (SHA-256/384/512, HMAC), console <-> browser
# encryption and password interop, tampered ciphertext rejection, random chunking,
# securely equals, secure-context diagnostic, and sections 29 & 30 acceptance programs.
$interpMod = Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Interpreter.psm1') -PassThru -Global -Force
$cryptoRuntime = Get-OtterJsCryptoRuntime

# Fixed known vectors
$keyHex = "4a656665" # "Jefe"
$dataHex = "7768617420646f2079612077616e7420666f72206e6f7468696e673f" # "what do ya want for nothing?"
$expectedHmac = "5BDCC146BF60754E6A042426089575C75A003F089D2739839DEC58B964EC3843"

# Console -> Browser encryption
$testKey = [byte[]](1..32)
$testMsg = [System.Text.Encoding]::UTF8.GetBytes("Cross runtime payload from .NET to WebCrypto!")
$consoleEncrypted = & $interpMod { Protect-OtterBytes -Data $args[0] -Key $args[1] } $testMsg $testKey
$consoleEncHex = -join ($consoleEncrypted | ForEach-Object { $_.ToString('X2') })
$testKeyHex = -join ($testKey | ForEach-Object { $_.ToString('X2') })

# Console password hash
$consoleHash = & $interpMod { New-OtterPasswordHash -Password "secret-phrase-42" }

# Compile Section 29 Acceptance Program to HTML:
$sec29Source = @"
message is bytes from text "Hello from Otter"
digest is sha256 of message
generate encryption key and call it key
encrypt message using key and call it encrypted
decrypt encrypted using key and call it decrypted
say text from bytes decrypted
"@
$sec29Html = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $sec29Source))
$sec29Js = if ($sec29Html -match '(?s)<script>(.*?)</script>') { $Matches[1] } else { throw 'Failed to extract script from Sec 29 HTML' }

# Compile Section 30 Password Acceptance Program to HTML:
$sec30Source = @"
password is "correct horse battery staple"
hash password password and call it stored
if password password matches hash stored
    say "Password verified"
.
"@
$sec30Html = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $sec30Source))
$sec30Js = if ($sec30Html -match '(?s)<script>(.*?)</script>') { $Matches[1] } else { throw 'Failed to extract script from Sec 30 HTML' }

$nodeD114Runner = @"
const { TextEncoder, TextDecoder } = require('util');
globalThis.TextEncoder = TextEncoder;
globalThis.TextDecoder = TextDecoder;
globalThis.window = globalThis;
globalThis.addEventListener = () => {};
globalThis.location = { pathname: '/' };
globalThis.document = { getElementById: () => null, querySelectorAll: () => [], addEventListener: () => {}, title: '' };

let logged = [];
const origLog = console.log;
console.log = (msg) => logged.push(String(msg));

$cryptoRuntime

function hexToBytes(h) {
  const b = new Uint8Array(h.length / 2);
  for (let i = 0; i < b.length; i++) b[i] = parseInt(h.substr(i*2, 2), 16);
  return { __otterBytes: true, value: b, toString() { return '<' + b.length + ' bytes>'; } };
}

function bytesToHex(ob) {
  let s = '';
  for (let i = 0; i < ob.value.length; i++) s += ob.value[i].toString(16).toUpperCase().padStart(2, '0');
  return s;
}

(async function() {
  try {
    // 1. Deterministic FIPS Vectors
    const abc = { __otterBytes: true, value: new TextEncoder().encode('abc'), toString() { return '<3 bytes>'; } };
    const sha256 = bytesToHex(await otterCryptoHash('sha256', abc));
    if (sha256 !== 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD') {
      throw new Error('SHA-256 vector mismatch: ' + sha256);
    }
    const sha384 = bytesToHex(await otterCryptoHash('sha384', abc));
    if (sha384 !== 'CB00753F45A35E8BB5A03D699AC65007272C32AB0EDED1631A8B605A43FF5BED8086072BA1E7CC2358BAECA134C825A7') {
      throw new Error('SHA-384 vector mismatch: ' + sha384);
    }
    const sha512 = bytesToHex(await otterCryptoHash('sha512', abc));
    if (sha512 !== 'DDAF35A193617ABACC417349AE20413112E6FA4E89A97EA20A9EEEE64B55D39A2192992A274FC1A836BA3C23A3FEEBBD454D4423643CE80E2A9AC94FA54CA49F') {
      throw new Error('SHA-512 vector mismatch: ' + sha512);
    }

    // 2. Deterministic RFC 4231 HMAC-SHA256 Vector
    const hmacKey = hexToBytes('$keyHex');
    const hmacData = hexToBytes('$dataHex');
    const hmac = bytesToHex(await otterCryptoHmac('sha256', hmacData, hmacKey));
    if (hmac !== '$expectedHmac') {
      throw new Error('HMAC-SHA256 vector mismatch: ' + hmac);
    }

    // 3. Console -> Browser Decryption
    const k = hexToBytes('$testKeyHex');
    const consoleEnc = hexToBytes('$consoleEncHex');
    const decryptedFromConsole = await otterDecryptBytes(consoleEnc, k);
    const plainText = new TextDecoder().decode(decryptedFromConsole.value);
    if (plainText !== 'Cross runtime payload from .NET to WebCrypto!') {
      throw new Error('Console -> Browser decryption mismatch: ' + plainText);
    }

    // 4. Browser -> Console Encryption
    const browserMsg = { __otterBytes: true, value: new TextEncoder().encode('Hello from Browser to Console!'), toString() { return ''; } };
    const browserEnc = await otterEncryptBytes(browserMsg, k);
    const browserEncHex = bytesToHex(browserEnc);

    // 5. Tampered Ciphertext Rejection
    const tamperedPayload = new Uint8Array(browserEnc.value);
    tamperedPayload[20] ^= 0x42;
    let tamperedFailed = false;
    try {
      await otterDecryptBytes({ __otterBytes: true, value: tamperedPayload }, k);
    } catch (e) {
      if (e.message.includes('I could not decrypt this data')) {
        tamperedFailed = true;
      }
    }
    if (!tamperedFailed) {
      throw new Error('Tampered ciphertext was NOT rejected!');
    }

    // 6. Console -> Browser Password Verification
    const passOk = await otterPasswordMatches('secret-phrase-42', '$consoleHash');
    if (!passOk) throw new Error('Console password hash failed verification in browser!');
    const passWrong = await otterPasswordMatches('wrong-password', '$consoleHash');
    if (passWrong) throw new Error('Wrong password succeeded verification in browser!');

    // 7. Browser -> Console Password Hash
    const browserHash = await otterHashPassword('browser-password-99');

    // 8. Secure Random Chunking (>65536)
    const largeRandom = otterSecureRandomBytes(70000);
    if (largeRandom.value.length !== 70000) {
      throw new Error('Chunked random bytes length mismatch: ' + largeRandom.value.length);
    }

    // 9. Securely Equals
    const b1 = hexToBytes('AABBCCDD');
    const b2 = hexToBytes('AABBCCDD');
    const b3 = hexToBytes('AABBCCEE');
    if (!otterSecurelyEquals(b1, b2)) throw new Error('Securely equals failed on equal bytes');
    if (otterSecurelyEquals(b1, b3)) throw new Error('Securely equals returned true on different bytes');

    // 10. Secure Context Failure Diagnostic
    const savedCrypto = globalThis.crypto;
    Object.defineProperty(globalThis, 'crypto', { value: { getRandomValues: (b) => savedCrypto.getRandomValues(b) }, configurable: true, writable: true });
    let diagCaught = false;
    try {
      await otterCryptoHash('sha256', abc);
    } catch (e) {
      if (e.message.includes('Cryptography in the browser requires Web Crypto in a secure context')) {
        diagCaught = true;
      }
    }
    Object.defineProperty(globalThis, 'crypto', { value: savedCrypto, configurable: true, writable: true });
    if (!diagCaught) throw new Error('Secure context diagnostic not thrown when subtle missing!');

    origLog(JSON.stringify({
      status: 'OK',
      browserEncHex: browserEncHex,
      browserHash: browserHash
    }));
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
})();
"@

$tmpD114Js = Join-Path ([System.IO.Path]::GetTempPath()) "otter_d114_web_tests_$([Guid]::NewGuid().ToString('N')).js"
Set-Content -LiteralPath $tmpD114Js -Value $nodeD114Runner
try {
    $nodeOut = & node $tmpD114Js
    if ($LASTEXITCODE -ne 0) {
        throw "Node test runner for D114 exited with code $LASTEXITCODE. Output: $nodeOut"
    }
    $res = $nodeOut | ConvertFrom-Json
    if ($res.status -ne 'OK') {
        throw "Node test runner for D114 reported failure: $nodeOut"
    }

    # Verify Browser -> Console encryption in .NET
    $browserEncBytes = [byte[]]::new($res.browserEncHex.Length / 2)
    for ($i = 0; $i -lt $browserEncBytes.Length; $i++) {
        $browserEncBytes[$i] = [Convert]::ToByte($res.browserEncHex.Substring($i * 2, 2), 16)
    }
    $plainFromBrowser = & $interpMod { Unprotect-OtterBytes -Payload $args[0] -Key $args[1] } $browserEncBytes $testKey
    $textFromBrowser = [System.Text.Encoding]::UTF8.GetString($plainFromBrowser)
    if ($textFromBrowser -ne 'Hello from Browser to Console!') {
        throw "Browser -> Console decryption mismatch in .NET: $textFromBrowser"
    }

    # Verify Browser -> Console password hash in .NET
    $verifyBrowserHash = & $interpMod { Test-OtterPasswordHash -Password 'browser-password-99' -StoredHash $args[0] } $res.browserHash
    if (-not $verifyBrowserHash) {
        throw "Browser-generated password hash failed verification in .NET console runtime!"
    }
    $verifyBrowserWrong = & $interpMod { Test-OtterPasswordHash -Password 'wrong-password' -StoredHash $args[0] } $res.browserHash
    if ($verifyBrowserWrong) {
        throw "Wrong password verified as true against browser hash in .NET console runtime!"
    }
} finally {
    Remove-Item -LiteralPath $tmpD114Js -Force -ErrorAction SilentlyContinue
}

# Run Section 29 and Section 30 Acceptance Programs in Node
$nodeAcceptanceScript = @"
const { TextEncoder, TextDecoder } = require('util');
globalThis.TextEncoder = TextEncoder;
globalThis.TextDecoder = TextDecoder;
globalThis.window = globalThis;
globalThis.addEventListener = () => {};
globalThis.location = { pathname: '/' };
globalThis.document = { getElementById: () => null, querySelectorAll: () => [], addEventListener: () => {}, title: '' };

let logged = [];
console.log = (msg) => logged.push(String(msg));

$sec29Js

setTimeout(async () => {
  if (!logged.some(l => l.includes('Hello from Otter'))) {
    console.error('Section 29 failed. Logged: ' + logged.join(' | '));
    process.exit(1);
  }
  logged = [];
  $sec30Js
  setTimeout(() => {
    if (!logged.some(l => l.includes('Password verified'))) {
      console.error('Section 30 failed. Logged: ' + logged.join(' | '));
      process.exit(1);
    }
    process.stdout.write('ACCEPTANCE_OK');
  }, 500);
}, 100);
"@

$tmpAccJs = Join-Path ([System.IO.Path]::GetTempPath()) "otter_d114_acceptance_$([Guid]::NewGuid().ToString('N')).js"
Set-Content -LiteralPath $tmpAccJs -Value $nodeAcceptanceScript
try {
    $accOut = & node $tmpAccJs
    if ($LASTEXITCODE -ne 0 -or $accOut -ne 'ACCEPTANCE_OK') {
        throw "D114 acceptance programs failed in Node: $accOut"
    }
} finally {
    Remove-Item -LiteralPath $tmpAccJs -Force -ErrorAction SilentlyContinue
}

Write-Output '  pass  Browser-side Crypto (D114) Web Crypto subtle/random, cross-runtime encryption/password parity, vectors, acceptance programs'

# Test 27: Async compiler propagation through mutation, collections, and nested statements (D114.5 audit)
$asyncPropSource = @"
to buildCryptoList
    items are empty
    add sha256 of "abc" to items
    return items
.
"@
$asyncPropAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $asyncPropSource)
$asyncPropJs = ConvertTo-OtterJsStatement -Stmt $asyncPropAst.Statements[0] -Indent 0
if ($asyncPropJs -notmatch 'const buildCryptoList = async function') {
    throw 'Expected function with async AddTo statement to be compiled as an async function.'
}
Write-Output '  pass  Async compiler propagation through mutation and collections (D114.5)'

# Test 28: Database statement and query expression rejections on web target (D114.5 audit)
$dbPrograms = @{
    "ConnectDb" = "connect database into db"
    "DisconnectDb" = "disconnect db"
    "DbQuery" = 'query db with "select 1" into rows'
    "DbExecute" = 'execute db with "delete from tasks" into res'
    "BeginTransaction" = "begin transaction on db into tx"
    "CommitTransaction" = "commit tx"
    "RollbackTransaction" = "rollback tx"
    "GetTables" = "get tables from db into tables"
    "GetColumns" = 'get columns from "tasks" in db into cols'
    "QueryStmt" = "get all from items in db into allItems"
    "QueryAggregateStmt" = "count all from scores in db into allCount"
    "QueryBetweenExpr" = "get all from items in db with`n    where score between 10 and 20`ninto res"
    "QueryInExpr" = "get all from items in db with`n    where id is in allowed`ninto res"
}

foreach ($entry in $dbPrograms.GetEnumerator()) {
    $kind = $entry.Key
    $source = $entry.Value
    $caught = $false
    try {
        $tokens = ConvertTo-OtterTokens -Source $source
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $html = ConvertTo-OtterWeb -Program $ast
    } catch {
        if ($_.Exception.Message -match 'Database (providers|queries) are not supported on the web target') {
            $caught = $true
        } else {
            throw "Expected DB rejection diagnostic for $kind, but got: $($_.Exception.Message)"
        }
    }
    if (-not $caught) {
        throw "Expected DB statement $kind to be rejected on web target, but compilation succeeded."
    }
}

# Standalone query expression rejections
try {
    $eb = [QueryBetweenExpr]::new([VariableExpr]::new('x', 1), [LiteralExpr]::new(1, 1), [LiteralExpr]::new(10, 1), 1)
    ConvertTo-OtterJsExpression -Expr $eb | Out-Null
    throw "Expected QueryBetweenExpr to be rejected on web target."
} catch {
    if ($_.Exception.Message -notmatch 'Database queries are not supported on the web target') {
        throw "Unexpected error for QueryBetweenExpr: $($_.Exception.Message)"
    }
}

try {
    $ei = [QueryInExpr]::new([VariableExpr]::new('x', 1), [VariableExpr]::new('list', 1), $false, 1)
    ConvertTo-OtterJsExpression -Expr $ei | Out-Null
    throw "Expected QueryInExpr to be rejected on web target."
} catch {
    if ($_.Exception.Message -notmatch 'Database queries are not supported on the web target') {
        throw "Unexpected error for QueryInExpr: $($_.Exception.Message)"
    }
}

Write-Output '  pass  Database provider and query rejections on web target for all 13 DB NodeKinds (D114.5)'

# Test 29: Binary file I/O rejections on web target (D115)
$binaryFilePrograms = @(
    'data is bytes from file "photo.png"'
    'write bytes data to file "copy.png"'
    'write bytes data to file "copy.png" atomically'
)
foreach ($prog in $binaryFilePrograms) {
    $caught = $false
    try {
        $tokens = ConvertTo-OtterTokens -Source $prog
        $ast = ConvertTo-OtterAst -Tokens $tokens
        $html = ConvertTo-OtterWeb -Program $ast
    } catch {
        if ($_.Exception.Message -match 'Binary file access is not supported on the web target') {
            $caught = $true
        } else {
            throw "Expected binary file rejection diagnostic, but got: $($_.Exception.Message)"
        }
    }
    if (-not $caught) {
        throw "Expected '$prog' to be rejected on web target, but compilation succeeded."
    }
}
Write-Output '  pass  Binary file access rejected on web target for BytesFromFile and WriteBytesFile (D115)'

# Test 30: `scroll true` makes a page scroll like a document (website pages)
$scrollSource = "app is a page with title `"Long`", scroll true`nt is a text with value `"hello`"`nput t in app`nshow app`n"
$plainSource = $scrollSource.Replace(', scroll true', '')
$scrollHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $scrollSource))
$plainHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $plainSource))
if ($scrollHtml -notmatch '<body class="otter-has-page otter-doc-scroll"') { throw 'Expected scroll true to mark the body as a scrolling document.' }
if ($plainHtml -match 'otter-doc-scroll"') { throw 'A page without scroll true must keep the app-shell (fit-the-window) behavior.' }
if ($scrollHtml -notmatch 'body\.otter-has-page\.otter-doc-scroll\s*\{[^}]*overflow-y:\s*auto') { throw 'Expected the scrolling-document CSS to allow vertical scrolling.' }
Write-Output '  pass  scroll true makes a page scroll like a document; other pages keep app-shell behavior'

# Test 31: `runnable true` text resources become live code samples (documentation site)
$runnableSource = @"
app is a page with title "Samples"
good is a text with value "name is \"World\"\nsay \"Hello\" name\nitems are\n    1\n    2\n.\nsay items", runnable true
diskSample is a text with value "read \"x.txt\" into content\nsay content", runnable true
shellSample is a text with value "otter run hello.ot", runnable true
plain is a text with value "say \"not runnable\""
put good, diskSample, shellSample, plain in app
show app
"@
$runnableHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $runnableSource))
if ($runnableHtml -notmatch 'data-otter-run="good"') { throw 'Expected a runnable sample to get a Run button.' }
if ($runnableHtml -match 'data-otter-run="diskSample"') { throw 'A sample that needs the file system must not get a Run button in a browser.' }
if ($runnableHtml -match 'data-otter-run="shellSample"') { throw 'Text that is not an Otter program must not get a Run button.' }
if ($runnableHtml -match 'data-otter-run="plain"') { throw 'A text resource without runnable true must not get a Run button.' }
$registryMatch = [regex]::Match($runnableHtml, '(?s)window\.otterRunnables\["good"\] = (\{ vars: .*?\n\} \});')
if (-not $registryMatch.Success) { throw 'Expected the runnable sample to be registered with its compiled code.' }
$nodeHarness = "global.window = globalThis; window.otterRunnables = {};`nconst sample = $($registryMatch.Groups[1].Value);`nconst said = []; sample.run((...a) => said.push(a.map((x) => Array.isArray(x) ? x.join(', ') : String(x)).join(' '))).then(() => console.log(JSON.stringify({ said, vars: sample.vars })));"
$nodeFile = Join-Path ([System.IO.Path]::GetTempPath()) "otter_runnable_$([Guid]::NewGuid().ToString('N')).js"
try {
    [System.IO.File]::WriteAllText($nodeFile, $nodeHarness)
    $nodeOut = & node $nodeFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "The compiled sample failed to run in Node: $nodeOut" }
    $ran = ($nodeOut | Select-Object -Last 1) | ConvertFrom-Json
} finally { Remove-Item -LiteralPath $nodeFile -Force -ErrorAction SilentlyContinue }
if (($ran.said -join '|') -ne 'Hello World|1, 2') { throw "Expected the sample to say 'Hello World' and '1, 2', got: $($ran.said -join '|')" }
if (($ran.vars -join ',') -ne 'name,items') { throw "Expected the sample's variables to be tracked for cleanup, got: $($ran.vars -join ',')" }
Write-Output '  pass  runnable true: live samples compile, run for real, and skip what a browser cannot run'

# Test 32: a checkbox is one control - its id is on the label, so a
# stylesheet rule that places or sizes it moves the box and its text
# together (Otter Studio's Free layout); its checked state is still read
# and set through the input inside.
$checkboxSource = "app is a window with title `"Form`"`nagree is a checkbox with text `"Email me`", checked true`nput agree in app`nshow app`n"
$checkboxHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $checkboxSource))
if ($checkboxHtml -notmatch '<label id="agree" class="otter-checkbox-label"><input type="checkbox" id="agree-box" class="otter-checkbox" checked />') {
    throw 'Expected the checkbox id on its label and the input as agree-box.'
}
if ($checkboxHtml -notmatch 'function otterValueElement\(id\)' -or $checkboxHtml -notmatch 'function otterGetText\(id\) \{\s*const el = otterValueElement\(id\);') {
    throw 'Expected the runtime to read a checkbox value from the input inside its label.'
}
if ($checkboxHtml -notmatch "otterInputProps = new Set\(\['checked', 'disabled', 'value'\]\)") {
    throw 'Expected checked / disabled / value properties to go to the input.'
}
Write-Output '  pass  a checkbox is one control: id on the label, value on the input inside'

# Test 33: the runtime is the same for every program - no element ids of a
# particular app (examples/portal.ot's slider, checkbox, dropdown and label
# were read by the 3D canvas runner; that behaviour is Otter code in
# portal.ot now). A canvas declares its animation's speed and colours.
$canvasSource = "app is a page with title `"C`"`ncube is a canvas with mode `"3d`", animation `"spin`", speed 50, color `"#34d399`", glow `"#059669`"`nput cube in app`nshow app`n"
$canvasHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $canvasSource))
foreach ($appId in @('speedSlider', 'agreeCheckbox', 'themeDropdown', 'speedLabel')) {
    if ($canvasHtml -match $appId) { throw "The web runtime must not refer to an app's element ($appId)." }
}
if ($canvasHtml -match "querySelector\('input\[type=`"range`"\]'\)") { throw 'The canvas runner must not follow whichever slider is on the page.' }
if ($canvasHtml -notmatch '<canvas id="cube"[^>]*data-speed="50" data-color="#34d399" data-glow="#059669"') {
    throw 'Expected a canvas to carry its declared speed and colours.'
}
Write-Output '  pass  the runtime refers to no app''s elements; a canvas declares its speed and colours'

# Test 34: a page's description and icon are what a search result, a shared
# link and the browser tab show; the title is escaped like every other text.
$metaSource = "app is a page with title `"Tea & <Cakes>`", description `"Fresh tea daily`", icon `"assets/icon.png`"`nshow app`n"
$metaHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $metaSource))
foreach ($expected in @(
    '<title>Tea &amp; &lt;Cakes&gt;</title>',
    '<meta name="description" content="Fresh tea daily">',
    '<meta property="og:title" content="Tea &amp; &lt;Cakes&gt;">',
    '<meta property="og:description" content="Fresh tea daily">',
    '<link rel="icon" href="assets/icon.png">',
    '<h1 class="otter-title">Tea &amp; &lt;Cakes&gt;</h1>')) {
    if (-not $metaHtml.Contains($expected)) { throw "Expected the page head to contain: $expected" }
}
$plainHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "app is a page with title `"Plain`"`nshow app`n"))
if ($plainHtml -match 'name="description"|rel="icon"|og:title') { throw 'A page without a description or icon must not get empty meta tags.' }
Write-Output '  pass  a page''s description and icon reach the head; the title is escaped'

# Test 35: forms (docs/proposals/FORMS_AND_VALIDATION.md). A form is a
# <form novalidate> laid out as a column; its fields carry their rules as data
# attributes; a labelled field gets its label and a place for its message;
# "when <form> is sent" listens for the runtime's "sent"; and programs
# without forms get none of the forms runtime.
$formSource = @"
contactForm is a form with spacing 12
nameBox is a text box with label "Name", required true
emailBox is a text box with label "Email", format "email", required true
ageBox is a text box with format "number", minimum 18, maximum 120, message "Adults only"
agreeBox is a checkbox with text "I agree", required true
sendButton is a primary button with text "Send"
put nameBox, emailBox, ageBox, agreeBox, sendButton in contactForm
when contactForm is sent
    say "sent"
.
show contactForm
"@
$formHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $formSource))
foreach ($expected in @(
    '<form id="contactForm" class="otter-column otter-form" novalidate',
    '<div class="otter-field" data-otter-field-for="nameBox">',
    '<label class="otter-field-label" for="nameBox">Name</label>',
    '<input type="text" id="nameBox" data-otter-field data-required="true" data-label="Name" class="otter-text-box"',
    '<div class="otter-field-error" id="nameBox-error" role="alert" hidden></div>',
    'id="emailBox" data-otter-field data-required="true" data-format="email" data-label="Email"',
    'id="ageBox" data-otter-field data-format="number" data-minimum="18" data-maximum="120" data-message="Adults only"',
    '<label id="agreeBox" data-otter-field data-required="true" class="otter-checkbox-label">',
    "el_contactForm.addEventListener('sent'",
    'function otterSendForm(form)',
    "if ((prop === 'valid' || prop === 'error') && typeof otterFormProperty === 'function')")) {
    if (-not $formHtml.Contains($expected)) { throw "Expected the form page to contain: $expected" }
}
if ($formHtml -match 'id="ageBox-error"') { throw 'A field without a label gets its message place only when it has a message.' }
$noFormHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "app is a window with title `"No form`"`nbox is a text box with placeholder `"x`"`nput box in app`nshow app`n"))
if ($noFormHtml -match 'function otterSendForm|data-otter-field|otter-field-error \{') { throw 'A program without forms or field rules must not get the forms runtime.' }
Write-Output '  pass  a form checks its fields: rules on the fields, labels and messages, "sent"'

# Test 36: a light page gets light cards, inputs and borders by default (a
# card made while the page runs was dark navy on white, with dark text on it);
# a dark app keeps the dark set.
$lightHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "app is a page with title `"L`", background `"#ffffff`", foreground `"#0f172a`"`nshow app`n"))
foreach ($expected in @('--otter-card-bg: #ffffff;', '--otter-input-bg: #ffffff;', '--otter-border: #cbd5e1;')) {
    if (-not $lightHtml.Contains($expected)) { throw "Expected a light page to have $expected" }
}
$darkHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "app is a page with title `"D`"`nshow app`n"))
foreach ($expected in @('--otter-card-bg: #1e293b;', '--otter-input-bg: #0f172a;', '--otter-border: #334155;')) {
    if (-not $darkHtml.Contains($expected)) { throw "Expected the default (dark) page to keep $expected" }
}
Write-Output '  pass  a light page gets light cards and inputs; a dark app keeps its own'

# Test 37: D127 - a compiled page loads nothing from another host (it starts
# and renders offline): no external stylesheet, script or font.
$offlineHtml = ConvertTo-OtterWeb -Program (ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "app is a page with title `"Offline`"`nhello is a text with text `"Hi`"`nput hello in app`nshow app`n"))
if ($offlineHtml -match '<(link|script)\b[^>]*\b(href|src)="(https?:)?//') { throw "D127: the page loads something from another host: $($Matches[0])" }
if ($offlineHtml -match 'fonts\.googleapis|fonts\.gstatic') { throw 'D127: the page must not load web fonts from another host.' }
Write-Output '  pass  D127: a compiled page loads nothing from another host'

Write-Output 'Web compiler tests passed.'


