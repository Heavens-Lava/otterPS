using module ..\Otter.Contract.psm1
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
if ($controlsHtml -notmatch '<input type="checkbox" id="tSwitch" class="otter-toggle"') {
    throw 'Expected compiled HTML to contain <input type="checkbox" id="tSwitch" class="otter-toggle"...'
}
if ($controlsHtml -notmatch '<input type="radio" id="rBtn" name="opts" class="otter-radio"') {
    throw 'Expected compiled HTML to contain <input type="radio" id="rBtn" name="opts" class="otter-radio"...'
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
if ($httpPlainJs -notmatch 'await fetch\("https://api\.example\.com/data", \{\}\);') {
    throw 'Expected a plain get to still call fetch with an empty options object.'
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
    $consolePsi.FileName = 'powershell.exe'
    $consolePsi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$otterPs1Path`" run `"$goToConsoleFile`""
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

Write-Output 'Web compiler tests passed.'
