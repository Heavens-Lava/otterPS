using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Lexer.psm1
using module ..\src\Otter.Parser.psm1

<#
.SYNOPSIS
    Derives per-TokenKind, per-NodeKind and per-diagnostic evidence from the
    repository and writes release/otter-1.0-contract-coverage.json.

.DESCRIPTION
    This is EVIDENCE, not a contract decision. Nothing here says a token, node
    or diagnostic is public. It records, for every declared member:

      * who produces / consumes it in the production pipeline (static references);
      * which real programs exercise it: every Otter program in conformance/,
        examples/, benchmarks/, otter-docs/pages and every parseable Otter source
        embedded in tests/*.Tests.ps1 is run through the REAL lexer and parser,
        and the tokens/nodes it produces are recorded with the file they came from;
      * what documents it (decision records cited in the contract, keyword
        mentions in the grammar documents);
      * an explicit disposition, so nothing is silently unaccounted for.

    "Exercised by a program in test file X" means X contains a program that
    parses to that member. It does not prove X asserts that member's behavior;
    it is the strongest reproducible automatic evidence, and the report says so.

    Read-only with respect to source and documentation: the only file written is
    the JSON output.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = 'release/otter-1.0-contract-coverage.json'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ReleaseSurface.Common.ps1"
$repoRoot = Get-OtterRepoRoot

$contractText = Read-OtterText 'Otter.Contract.psm1'
$tokenInventory = Get-OtterEnumInventory -ContractText $contractText -EnumName 'TokenKind'
$nodeInventory = Get-OtterEnumInventory -ContractText $contractText -EnumName 'NodeKind'
$nodeClasses = Get-OtterNodeClassMap -ContractText $contractText
$lexerText = Read-OtterText 'src/Otter.Lexer.psm1'
$parserText = Read-OtterText 'src/Otter.Parser.psm1'
$keywords = Get-OtterLexerKeywords -LexerText $lexerText

# Reserved members are recorded by tools/Test-OtterContractCoverage.ps1 (Codex's
# structural audit). They are mirrored here so the two reports agree; adding an
# exception is a release-contract decision, not a change made in this file.
$declaredTokenExceptions = @{ 'Thing' = 'contextual keyword read by token text in object-type parsing; see docs/OTTER_1_0_CONTRACT_COVERAGE_MANIFEST.md' }
$declaredNodeExceptions = @{ 'UiLayout' = 'reserved; layout data is carried by UiElement (docs/D114_5_LANGUAGE_INTEGRITY_AUDIT.md)' }

# --- 1. the corpus ------------------------------------------------------------

function New-Snippet { param([string]$Origin, [string]$Group, [string]$Source) [pscustomobject]@{ Origin = $Origin; Group = $Group; Source = $Source } }

$corpus = New-Object System.Collections.Generic.List[object]

# Otter source files.
$otFolders = @('conformance', 'examples', 'benchmarks', 'otter-docs/pages', 'selfhost', 'projects')
foreach ($folder in $otFolders) {
    $full = Join-Path $repoRoot $folder
    if (-not (Test-Path -LiteralPath $full)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $full -Recurse -Filter '*.ot' -File -ErrorAction SilentlyContinue) {
        $relative = $file.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
        $group = switch -Wildcard ($relative) {
            'conformance/*' { 'conformance' }
            'examples/*' { 'examples' }
            'benchmarks/*' { 'benchmarks' }
            default { 'other-programs' }
        }
        $corpus.Add((New-Snippet -Origin $relative -Group $group -Source ([System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8))))
    }
}

# Otter programs embedded as here-strings in the test files. Interpolations are
# replaced with a placeholder so the program still parses; a snippet that still
# fails to parse is counted and skipped, never guessed at.
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*.Tests.ps1' -File) {
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $relative = 'tests/' + $file.Name
    foreach ($m in [regex]::Matches($text, '@"\r?\n(.*?)\r?\n"@', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $body = $m.Groups[1].Value
        $body = [regex]::Replace($body, '\$\([^)]*\)', '1')
        $body = [regex]::Replace($body, '\$\{?[A-Za-z_][A-Za-z0-9_:]*\}?', '1')
        $body = $body.Replace('`$', '$').Replace('``', '`')
        $corpus.Add((New-Snippet -Origin $relative -Group 'tests' -Source $body))
    }
    foreach ($m in [regex]::Matches($text, "@'\r?\n(.*?)\r?\n'@", [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        $corpus.Add((New-Snippet -Origin $relative -Group 'tests' -Source $m.Groups[1].Value))
    }
}

# --- 2. run the real lexer and parser over it ---------------------------------

$tokenPrograms = @{}    # TokenKind -> set of origins
$nodePrograms = @{}     # NodeKind  -> set of origins
$parsedCount = 0
$failedCount = 0
$lexedOnlyCount = 0

foreach ($snippet in $corpus) {
    if ([string]::IsNullOrWhiteSpace($snippet.Source)) { continue }
    $tokens = $null
    try { $tokens = ConvertTo-OtterTokens -Source $snippet.Source } catch { $failedCount++; continue }
    foreach ($t in @($tokens)) {
        $name = $t.Kind.ToString()
        if (-not $tokenPrograms.ContainsKey($name)) { $tokenPrograms[$name] = New-Object 'System.Collections.Generic.HashSet[string]' }
        [void]$tokenPrograms[$name].Add($snippet.Origin)
    }
    $ast = $null
    try { $ast = ConvertTo-OtterAst -Tokens $tokens } catch { $lexedOnlyCount++; continue }
    $parsedCount++
    foreach ($kind in (Get-OtterNodeKindsInTree -Root $ast)) {
        if (-not $nodePrograms.ContainsKey($kind)) { $nodePrograms[$kind] = New-Object 'System.Collections.Generic.HashSet[string]' }
        [void]$nodePrograms[$kind].Add($snippet.Origin)
    }
}

# --- 3. documentation evidence ------------------------------------------------

$specText = Read-OtterText 'SPEC-DECISIONS.md'
$specHeadings = @{}
foreach ($m in [regex]::Matches($specText, '(?m)^#{1,4}\s+(D\d{1,3}(?:\.\d+)?[A-Z]?)\b')) { $specHeadings[$m.Groups[1].Value] = $true }

$grammarDocs = @('rules.md', 'docs/GRAMMAR.md', 'docs/SEMANTICS.md', 'docs/STANDARD_LIBRARY.md', 'docs/STANDARD_LIBRARY_REACHABILITY.md')
$grammarText = @{}
foreach ($doc in $grammarDocs) { $t = Read-OtterText $doc; if ($null -ne $t) { $grammarText[$doc] = $t } }

function Get-DecisionDocs {
    param([string[]]$Refs)
    $docs = New-Object System.Collections.Generic.List[string]
    foreach ($ref in $Refs) {
        if ($specHeadings.ContainsKey($ref)) { $docs.Add("SPEC-DECISIONS.md#$ref") }
    }
    return $docs.ToArray()
}

# --- 4. per-token records -----------------------------------------------------

$tokenRecords = New-Object System.Collections.Generic.List[object]
foreach ($member in $tokenInventory) {
    $name = $member.Name
    $lexerRefs = ([regex]::Matches($lexerText, '\[TokenKind\]::' + [regex]::Escape($name) + '\b')).Count
    $parserRefs = ([regex]::Matches($parserText, '\[TokenKind\]::' + [regex]::Escape($name) + '\b')).Count
    $words = if ($keywords.ContainsKey($name)) { @($keywords[$name]) } else { @() }
    $origins = if ($tokenPrograms.ContainsKey($name)) { @($tokenPrograms[$name] | Sort-Object) } else { @() }
    $refs = @(Get-OtterDecisionRefs ($member.Section + ' ' + $member.Comment))
    $docFiles = New-Object System.Collections.Generic.List[string]
    foreach ($d in (Get-DecisionDocs -Refs $refs)) { $docFiles.Add($d) }
    foreach ($word in $words) {
        foreach ($doc in $grammarText.Keys) {
            if ($grammarText[$doc] -match ('(?i)(?<![A-Za-z])' + [regex]::Escape($word) + '(?![A-Za-z])') -and -not $docFiles.Contains($doc)) { $docFiles.Add($doc) }
        }
    }

    $disposition =
        if ($declaredTokenExceptions.ContainsKey($name)) { 'declared-exception' }
        elseif ($lexerRefs + $parserRefs -eq 0) { 'unwired' }
        elseif ($origins.Count -gt 0) { 'exercised' }
        else { 'wired-not-exercised-by-corpus' }

    $tokenRecords.Add([ordered]@{
        name          = $name
        section       = $member.Section
        contractNote  = $member.Comment
        keywords      = $words
        producers     = [ordered]@{ lexerReferences = $lexerRefs; parserReferences = $parserRefs }
        corpus        = [ordered]@{ programs = $origins.Count; origins = @($origins | Select-Object -First 12) }
        documentation = [ordered]@{ files = @($docFiles); decisionRefs = $refs; derivation = 'D-number headings in SPEC-DECISIONS.md and keyword word-match in grammar documents (weak for very common words)' }
        disposition   = $disposition
        exceptionReason = if ($declaredTokenExceptions.ContainsKey($name)) { $declaredTokenExceptions[$name] } else { $null }
    })
}

# --- 5. per-node records ------------------------------------------------------

$groups = Get-OtterConsumerGroups
$groupText = @{}
foreach ($g in $groups.Keys) {
    $groupText[$g] = (($groups[$g] | ForEach-Object { Read-OtterText $_ }) -join "`n")
}

$nodeRecords = New-Object System.Collections.Generic.List[object]
foreach ($member in $nodeInventory) {
    $name = $member.Name
    $class = if ($nodeClasses.ContainsKey($name)) { $nodeClasses[$name] } else { $null }
    $constructed = if ($class) { ($parserText -match ('\[' + [regex]::Escape($class) + '\]::new\(')) } else { $false }
    $consumers = [ordered]@{}
    foreach ($g in $groups.Keys) { $consumers[$g] = (Test-OtterNodeReferenced -NodeName $name -ClassName $class -Text $groupText[$g]) }
    $origins = if ($nodePrograms.ContainsKey($name)) { @($nodePrograms[$name] | Sort-Object) } else { @() }
    $refs = @(Get-OtterDecisionRefs ($member.Section + ' ' + $member.Comment))
    $docFiles = @(Get-DecisionDocs -Refs $refs)
    $anyConsumer = ($consumers.Values | Where-Object { $_ }).Count -gt 0

    $disposition =
        if ($declaredNodeExceptions.ContainsKey($name)) { 'declared-exception' }
        elseif (-not $class) { 'no-ast-class' }
        elseif (-not $constructed) { 'not-constructed-by-parser' }
        elseif (-not $anyConsumer) { 'no-runtime-consumer' }
        elseif ($origins.Count -gt 0) { 'exercised' }
        else { 'wired-not-exercised-by-corpus' }

    $nodeRecords.Add([ordered]@{
        name          = $name
        astClass      = $class
        section       = $member.Section
        contractNote  = $member.Comment
        parser        = [ordered]@{ constructsClass = $constructed }
        consumers     = $consumers
        corpus        = [ordered]@{ programs = $origins.Count; origins = @($origins | Select-Object -First 12) }
        documentation = [ordered]@{ files = $docFiles; decisionRefs = $refs; derivation = 'D-number headings in SPEC-DECISIONS.md cited by the contract comment or section' }
        disposition   = $disposition
        exceptionReason = if ($declaredNodeExceptions.ContainsKey($name)) { $declaredNodeExceptions[$name] } else { $null }
    })
}

# --- 6. diagnostics -----------------------------------------------------------

$evidenceTexts = New-Object System.Collections.Generic.List[object]
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests') -Filter '*.ps1' -File) {
    $evidenceTexts.Add([pscustomobject]@{ File = 'tests/' + $file.Name; Text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8) })
}
foreach ($rel in @('conformance/manifest.json', 'docs/DIAGNOSTIC_MATRIX.md', 'docs/OTTER_1_0_RED_TEAM_REPORT.md')) {
    $t = Read-OtterText $rel
    if ($null -ne $t) { $evidenceTexts.Add([pscustomobject]@{ File = $rel; Text = $t }) }
}

$diagnosticModules = @(
    'src/Otter.Lexer.psm1', 'src/Otter.Parser.psm1', 'src/Otter.Interpreter.psm1', 'src/Otter.Library.psm1',
    'src/Otter.Compiler.JavaScript.psm1', 'src/Otter.Database.psm1', 'src/Otter.Module.psm1', 'src/Otter.Project.psm1',
    'src/Otter.UI.psm1', 'src/Otter.Desktop.psm1', 'src/Otter.Web.psm1')
$diagnosticRecords = New-Object System.Collections.Generic.List[object]
$errorCall = '(?:New-OtterRuntimeError|New-OtterParserError|New-OtterXmlRuntimeError|New-OtterSyntaxError|New-OtterError|\[OtterError\]::new\()'

# Longest run of fixed text in a message literal (the parts between interpolations).
function Get-LongestStaticFragment {
    param([string]$Literal)
    $clean = $Literal.Replace('`"', '"').Replace('``', '`')
    $parts = [regex]::Split($clean, '\$\{[^}]*\}|\$\([^)]*\)|\$[A-Za-z_][A-Za-z0-9_:]*')
    $best = ''
    foreach ($part in $parts) { $t = $part.Trim(); if ($t.Length -gt $best.Length) { $best = $t } }
    return $best
}

foreach ($module in $diagnosticModules) {
    $text = Read-OtterText $module
    if ($null -eq $text) { continue }
    $lines = $text -split "`r?`n"
    $currentFunction = '(module scope)'
    $indexInFunction = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*function\s+([A-Za-z0-9_-]+)') { $currentFunction = $Matches[1] }
        if ($line -notmatch $errorCall) { continue }
        if ($line -match '^\s*#') { continue }
        # The message argument may be on this line or the next few.
        $window = ($lines[$i..([Math]::Min($i + 3, $lines.Count - 1))] -join ' ')
        $literal = $null
        if ($window -match "-Message\s+'((?:[^']|'')*)'") { $literal = $Matches[1].Replace("''", "'") }
        elseif ($window -match '-Message\s+"((?:[^"`]|`.)*)"') { $literal = $Matches[1] }
        elseif ($window -match "\[OtterError\]::new\(\s*'((?:[^']|'')*)'") { $literal = $Matches[1].Replace("''", "'") }
        elseif ($window -match '\[OtterError\]::new\(\s*"((?:[^"`]|`.)*)"') { $literal = $Matches[1] }
        elseif ($window -match "(?:New-Otter\w+Error)\s+'((?:[^']|'')*)'") { $literal = $Matches[1].Replace("''", "'") }
        elseif ($window -match '(?:New-Otter\w+Error)\s+"((?:[^"`]|`.)*)"') { $literal = $Matches[1] }
        $fragment = $null
        if ($null -ne $literal) { $fragment = Get-LongestStaticFragment -Literal $literal }
        $key = "$module|$currentFunction"
        if (-not $indexInFunction.ContainsKey($key)) { $indexInFunction[$key] = 0 }
        $indexInFunction[$key]++
        $stage = $null
        if ($window -match ",\s*'(runtime|parser|check|syntax|lexer)'\s*\)") { $stage = $Matches[1] }
        $family = if ($stage -in @('parser', 'syntax', 'lexer')) { 'syntax' }
                  elseif ($stage) { $stage }
                  elseif ($module -match 'Lexer|Parser') { 'syntax' }
                  else { 'runtime' }

        $testFiles = New-Object System.Collections.Generic.List[string]
        if ($fragment -and $fragment.Length -ge 15) {
            foreach ($e in $evidenceTexts) {
                if ($e.Text.Contains($fragment)) { $testFiles.Add($e.File) }
            }
        }
        $evidenceKind =
            if ($null -eq $literal) { 'dynamic-message' }
            elseif ($fragment.Length -lt 15) { 'message-too-short-to-match' }
            elseif ($testFiles.Count -gt 0) { 'message-text-found' }
            else { 'message-text-not-found' }

        $diagnosticRecords.Add([ordered]@{
            id             = ('{0}#{1}#{2}' -f ($module -replace '^src/', ''), $currentFunction, $indexInFunction[$key])
            module         = $module
            family         = $family
            function       = $currentFunction
            messageFragment = $fragment
            evidence       = [ordered]@{ kind = $evidenceKind; files = @($testFiles | Select-Object -First 6) }
        })
    }
}

# --- 7. write -----------------------------------------------------------------

function Get-Count { param($Records, [string]$Field, [string]$Value) @($Records | Where-Object { $_[$Field] -eq $Value }).Count }

$summary = [ordered]@{
    tokens = [ordered]@{
        declared = $tokenRecords.Count
        exercised = (Get-Count $tokenRecords 'disposition' 'exercised')
        wiredNotExercised = (Get-Count $tokenRecords 'disposition' 'wired-not-exercised-by-corpus')
        declaredException = (Get-Count $tokenRecords 'disposition' 'declared-exception')
        unwired = (Get-Count $tokenRecords 'disposition' 'unwired')
    }
    nodes = [ordered]@{
        declared = $nodeRecords.Count
        exercised = (Get-Count $nodeRecords 'disposition' 'exercised')
        wiredNotExercised = (Get-Count $nodeRecords 'disposition' 'wired-not-exercised-by-corpus')
        declaredException = (Get-Count $nodeRecords 'disposition' 'declared-exception')
        problems = @($nodeRecords | Where-Object { $_['disposition'] -in @('no-ast-class', 'not-constructed-by-parser', 'no-runtime-consumer') }).Count
    }
    diagnostics = [ordered]@{
        callSites = $diagnosticRecords.Count
        messageTextFoundInTests = @($diagnosticRecords | Where-Object { $_['evidence']['kind'] -eq 'message-text-found' }).Count
        messageTextNotFound = @($diagnosticRecords | Where-Object { $_['evidence']['kind'] -eq 'message-text-not-found' }).Count
        dynamicMessage = @($diagnosticRecords | Where-Object { $_['evidence']['kind'] -eq 'dynamic-message' }).Count
        tooShortToMatch = @($diagnosticRecords | Where-Object { $_['evidence']['kind'] -eq 'message-too-short-to-match' }).Count
    }
}

$document = [ordered]@{
    schemaVersion = 1
    purpose       = 'Derived evidence for every declared TokenKind, NodeKind and diagnostic call site. Evidence only: nothing here decides what is public.'
    derivedFrom   = [ordered]@{
        commit          = Get-OtterGitSha
        contractSha256  = Get-OtterSha256 'Otter.Contract.psm1'
        lexerSha256     = Get-OtterSha256 'src/Otter.Lexer.psm1'
        parserSha256    = Get-OtterSha256 'src/Otter.Parser.psm1'
        corpus          = [ordered]@{ snippets = $corpus.Count; parsedPrograms = $parsedCount; lexedButNotParsed = $lexedOnlyCount; failedToLex = $failedCount }
        method          = 'Every Otter program found in conformance/, examples/, benchmarks/, otter-docs/pages, selfhost/, projects/ and embedded in tests/*.Tests.ps1 was run through the real lexer and parser. "Exercised by a program in test file X" means X contains a program that produces that token or node; it does not prove X asserts that member''s behavior.'
    }
    summary       = $summary
    tokens        = $tokenRecords.ToArray()
    nodes         = $nodeRecords.ToArray()
    diagnostics   = $diagnosticRecords.ToArray()
}

$outPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repoRoot $OutputPath }
$outDir = Split-Path -Parent $outPath
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[System.IO.File]::WriteAllText($outPath, ($document | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))

Write-Output ("Corpus: {0} snippets, {1} parsed programs, {2} lexed but not parsed, {3} failed to lex" -f $corpus.Count, $parsedCount, $lexedOnlyCount, $failedCount)
Write-Output ("Tokens: {0} declared, {1} exercised, {2} wired but not exercised, {3} declared exceptions, {4} unwired" -f $summary.tokens.declared, $summary.tokens.exercised, $summary.tokens.wiredNotExercised, $summary.tokens.declaredException, $summary.tokens.unwired)
Write-Output ("Nodes: {0} declared, {1} exercised, {2} wired but not exercised, {3} declared exceptions, {4} structural problems" -f $summary.nodes.declared, $summary.nodes.exercised, $summary.nodes.wiredNotExercised, $summary.nodes.declaredException, $summary.nodes.problems)
Write-Output ("Diagnostics: {0} call sites; message fragment found in tests/docs: {1}; not found: {2}; dynamic: {3}; too short to match: {4}" -f $summary.diagnostics.callSites, $summary.diagnostics.messageTextFoundInTests, $summary.diagnostics.messageTextNotFound, $summary.diagnostics.dynamicMessage, $summary.diagnostics.tooShortToMatch)
Write-Output "Written: $outPath"
