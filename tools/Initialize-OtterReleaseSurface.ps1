<#
.SYNOPSIS
    Seeds release/otter-1.0-surface.json (the Otter 1.0 candidate-surface evidence
    manifest) from the repository's existing evidence.

.DESCRIPTION
    THIS DOES NOT DECIDE WHAT IS PUBLIC. Every capability is seeded with
    status "candidate" and boundaryStatus "unresolved". Disagreements between
    documents are recorded as `conflicts`, never resolved by picking one side.
    The public boundary is Codex's decision; this manifest exists so that decision
    can be made against evidence.

    Seed sources (all read-only):
      docs/STANDARD_LIBRARY_REACHABILITY.md   the reachability matrix
      docs/STANDARD_LIBRARY.md                the standard-library boundary document
      Otter.Contract.psm1                     the frozen contract (NodeKind members, sections, comments)
      release/otter-1.0-contract-coverage.json  derived evidence (run tools/New-OtterContractEvidence.ps1 first)
      docs/OTTER_1_0_EVENT_LOOP_REVIEW.md     measured event-loop facts
      tests/StandardLibrary.Tests.ps1         the 31 reachability cases

    After seeding, the JSON is the authoritative evidence file and is edited
    directly; this script refuses to overwrite it without -Force.

    Links between documentation phrases and contract members are DERIVED by
    word matching against the contract's own comments (each is labelled with its
    derivation) and are hints for a human reviewer, not decisions.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = 'release/otter-1.0-surface.json',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ReleaseSurface.Common.ps1"
$repoRoot = Get-OtterRepoRoot

$outPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $repoRoot $OutputPath }
if ((Test-Path -LiteralPath $outPath) -and -not $Force) {
    throw "$OutputPath already exists. It is the authoritative evidence file; pass -Force to re-seed it (this discards manual edits)."
}

$coveragePath = Join-Path $repoRoot 'release/otter-1.0-contract-coverage.json'
if (-not (Test-Path -LiteralPath $coveragePath)) {
    throw 'release/otter-1.0-contract-coverage.json is missing. Run tools/New-OtterContractEvidence.ps1 first.'
}
$coverage = [System.IO.File]::ReadAllText($coveragePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$nodeEvidence = @{}
foreach ($n in $coverage.nodes) { $nodeEvidence[$n.name] = $n }

$contractText = Read-OtterText 'Otter.Contract.psm1'
$nodeInventory = Get-OtterEnumInventory -ContractText $contractText -EnumName 'NodeKind'
$nodeClasses = Get-OtterNodeClassMap -ContractText $contractText
$classToNode = @{}
foreach ($k in $nodeClasses.Keys) { $classToNode[$nodeClasses[$k]] = $k }
$nodeByName = @{}
foreach ($m in $nodeInventory) { $nodeByName[$m.Name] = $m }

$reachText = Read-OtterText 'docs/STANDARD_LIBRARY_REACHABILITY.md'
$stdlibText = Read-OtterText 'docs/STANDARD_LIBRARY.md'
$stdlibTestText = Read-OtterText 'tests/StandardLibrary.Tests.ps1'
$suiteEvidence = 'tests/Run-Tests.ps1 passed on Windows PowerShell 5.1 (55 of 55 test files, 2026-09-27, docs/OTTER_1_0_PERFORMANCE_BASELINE.md validation gates)'
$hostSmokeEvidence = 'D120 CI matrix (.github/workflows/d120-host-matrix.yml) ran --version, run, check and the project commands on this host; it did not exercise this capability'

# --- helpers -----------------------------------------------------------------

function ConvertTo-Slug { param([string]$Text) ((($Text.ToLowerInvariant()) -replace '[^a-z0-9]+', '-').Trim('-')) }

function New-HostBlock {
    # $TestEvidence: 'yes' (a test program covers it), 'no' (linked, but no test program
    # produces the linked member), 'unknown' (no contract link, so nothing could be checked).
    param([string]$TestEvidence, [string]$Browser, [string]$BrowserEvidence)
    $ps51 = switch ($TestEvidence) {
        'yes' { [ordered]@{ state = 'exercised'; evidence = $suiteEvidence } }
        'no' { [ordered]@{ state = 'not-exercised'; evidence = 'the linked contract member is produced by no program in the test or conformance corpus' } }
        default { [ordered]@{ state = 'unverified'; evidence = 'no contract member is linked to this capability, so test coverage could not be determined mechanically' } }
    }
    $unverified = [ordered]@{ state = 'unverified'; evidence = $hostSmokeEvidence }
    return [ordered]@{
        windowsPowerShell51 = $ps51
        windowsPowerShell7  = $unverified
        linuxPowerShell7    = $unverified
        macosPowerShell7    = $unverified
        browser             = [ordered]@{ state = $Browser; evidence = $BrowserEvidence }
    }
}

function New-ImplementationBlock {
    param($Consumers)   # $null => unknown
    $groups = Get-OtterConsumerGroups
    $block = [ordered]@{}
    foreach ($g in @('interpreter', 'javascript', 'browser', 'desktop', 'provider')) {
        $modules = @($groups[$g])
        if ($null -eq $Consumers) {
            $block[$g] = [ordered]@{ state = 'unknown'; modules = $modules; note = 'no contract member is linked to this capability, so no reference search was possible' }
        }
        else {
            $hit = @($Consumers | Where-Object { $_.$g }).Count -gt 0
            $block[$g] = [ordered]@{
                state = if ($hit) { 'referenced' } else { 'not-referenced' }
                modules = $modules
                note  = if ($hit) { 'a linked contract member is dispatched or constructed in these modules' } else { 'searched these modules; NOT a claim of unsupported (generic handling is possible)' }
            }
        }
    }
    return $block
}

# --- 1. reachability matrix rows ---------------------------------------------

$reachRows = New-Object System.Collections.Generic.List[object]
foreach ($line in ($reachText -split "`r?`n")) {
    if ($line -notmatch '^\|\s*\*\*(?<area>[^*]+)\*\*\s*\|\s*(?<cap>[^|]+?)\s*\|\s*(?<syntax>.+?)\s*\|\s*(?<handler>[^|]+?)\s*\|\s*(?<status>[A-Z-]+)\s*\|\s*$') { continue }
    $reachRows.Add([pscustomobject]@{
        Area = $Matches['area'].Trim(); Capability = $Matches['cap'].Trim()
        Syntax = ($Matches['syntax'] -replace '`', '').Trim(); Handler = $Matches['handler'].Trim(); Status = $Matches['status'].Trim()
    })
}

# The suite's 31 cases, and which matrix rows each covers. Curated: the matrix has
# 34 rows but the suite has 31 cases, so several rows share a case and one has none.
# Every case name here is verified to exist in the test file by the auditor.
$caseForRow = @{
    'Uppercase' = 'uppercase'; 'Lowercase' = 'lowercase'; 'Starts/Ends With' = 'starts with and ends with'
    'In-place Replace' = 'replace'; 'Split' = 'split'; 'Contains' = 'contains'; 'Length' = 'length'
    'Arithmetic' = 'basic arithmetic'; 'Percent Of' = 'percent of'; 'Power' = 'power'; 'Rounding' = 'rounding'
    'Absolute Value' = 'absolute value'; 'Square Root' = 'square root'; 'Min / Max' = 'min and max'
    'Trigonometry' = 'trigonometry'; 'Logarithms' = 'logarithms'
    'Lists' = 'definition and mutation'; 'Mutation' = 'definition and mutation'; 'Empty List' = 'empty list'; 'Iteration' = 'for each loop'
    'Object Definition' = 'thing has and of'; 'Property Read/Write' = 'thing has and of'; 'Dynamic Keys' = 'dynamic keys get/set'
    'Nested Objects' = 'nested properties'; 'Convert To/From' = 'convert to/from json'; 'Clock & Math' = 'today and date math'
    'Number & Item' = 'random number and item'; 'File I/O' = 'write read append delete'
    'Run & Capture' = 'run command into'; 'Process List' = 'get processes'
    'System Information' = 'system information'; 'Clipboard' = 'clipboard'; 'Environment' = 'environment variable'
}
# Reachability-matrix area -> the -Area label the test file actually uses, where they differ.
$testAreaForRowArea = @{ 'Processes' = 'Process' }
# Which reachability areas each STANDARD_LIBRARY.md row is compared against (curated).
$areasForStdRow = @{
    'Math' = @('Math'); 'Text' = @('Text'); 'Collections and things' = @('Collections', 'Objects'); 'Data' = @('JSON')
    'Dates and randomness' = @('Dates', 'Random'); 'Files and folders' = @('Filesystem'); 'Processes' = @('Processes')
    'System integration' = @('System'); 'Clipboard' = @('System')
}

# --- 2. STANDARD_LIBRARY.md phrases ------------------------------------------

$stdPhrases = New-Object System.Collections.Generic.List[object]
$section = ''
foreach ($line in ($stdlibText -split "`r?`n")) {
    if ($line -match '^##\s+(.+)$') { $section = $Matches[1].Trim(); continue }
    if ($line -notmatch '^\|\s*(?<area>[^|]+?)\s*\|\s*(?<cell>.+?)\s*\|\s*$') { continue }
    $area = $Matches['area'].Trim()
    if ($area -in @('Area', 'Capability', '---') -or $area -match '^-+$') { continue }
    $cell = $Matches['cell']
    # Split on commas that are not inside backticks.
    $parts = New-Object System.Collections.Generic.List[string]
    $buffer = New-Object System.Text.StringBuilder
    $inTick = $false
    foreach ($ch in $cell.ToCharArray()) {
        if ($ch -eq '`') { $inTick = -not $inTick }
        if ($ch -eq ',' -and -not $inTick) { $parts.Add($buffer.ToString().Trim()); [void]$buffer.Clear() } else { [void]$buffer.Append($ch) }
    }
    if ($buffer.Length -gt 0) { $parts.Add($buffer.ToString().Trim()) }
    foreach ($part in $parts) {
        $clean = ($part -replace '`', '' -replace '^and\s+', '' -replace '\s*\.\.\.\s*', ' ').Trim().TrimEnd('.', ';')
        if ($clean.Length -lt 2) { continue }
        $stdPhrases.Add([pscustomobject]@{ Section = $section; Area = $area; Phrase = $clean; Raw = $part })
    }
}

# --- 3. link phrases to matrix rows and contract members (derived) -----------

function Get-PhraseWords { param([string]$Phrase) @(($Phrase.ToLowerInvariant() -split '[^a-z0-9]+') | Where-Object { $_ }) }

$claimedNodes = New-Object 'System.Collections.Generic.HashSet[string]'
$capabilities = New-Object System.Collections.Generic.List[object]
$idsUsed = @{}
function New-UniqueId { param([string]$Base) $id = $Base; $n = 2; while ($idsUsed.ContainsKey($id)) { $id = "$Base-$n"; $n++ }; $idsUsed[$id] = $true; return $id }

$stdMatchedToRow = @{}      # phrase index -> R ids
$rowStdMatches = @{}        # R capability key -> phrases
for ($pi = 0; $pi -lt $stdPhrases.Count; $pi++) {
    $p = $stdPhrases[$pi]
    $areas = if ($areasForStdRow.ContainsKey($p.Area)) { $areasForStdRow[$p.Area] } else { @() }
    if ($areas.Count -eq 0 -or $p.Phrase.Length -lt 4) { continue }
    foreach ($row in $reachRows) {
        if ($areas -notcontains $row.Area) { continue }
        $hay = ($row.Syntax + ' ' + $row.Capability).ToLowerInvariant()
        if ($hay.Contains($p.Phrase.ToLowerInvariant())) {
            if (-not $stdMatchedToRow.ContainsKey($pi)) { $stdMatchedToRow[$pi] = New-Object System.Collections.Generic.List[string] }
            $stdMatchedToRow[$pi].Add("$($row.Area)|$($row.Capability)")
            $key = "$($row.Area)|$($row.Capability)"
            if (-not $rowStdMatches.ContainsKey($key)) { $rowStdMatches[$key] = New-Object System.Collections.Generic.List[string] }
            $rowStdMatches[$key].Add($p.Phrase)
        }
    }
}

# Derive contract-member links for a phrase by word match against member names and comments.
function Find-NodesForPhrase {
    param([string]$Phrase)
    $words = Get-PhraseWords $Phrase
    if ($words.Count -eq 0 -or $Phrase.Length -lt 3) { return @() }
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($m in $nodeInventory) {
        $nameWords = @(([regex]::Matches($m.Name, '[A-Z][a-z0-9]*')) | ForEach-Object { $_.Value.ToLowerInvariant() })
        $nameText = ($nameWords -join ' ')
        $commentText = ($m.Comment.ToLowerInvariant() -replace '"[^"]*"', ' ')
        $phraseText = ($words -join ' ')
        if ($nameText -eq $phraseText -or ($words.Count -eq 1 -and $nameWords -contains $words[0] -and $nameWords.Count -le 2) -or
            ($phraseText.Length -ge 3 -and ($commentText -match ('(?<![a-z])' + [regex]::Escape($phraseText) + '(?![a-z])')))) {
            $hits.Add($m.Name)
        }
    }
    return $hits.ToArray()
}

# --- 4. build capability records ---------------------------------------------

function Get-NodeConsumers {
    param([string[]]$NodeNames)
    $list = @()
    foreach ($n in $NodeNames) { if ($nodeEvidence.ContainsKey($n)) { $list += $nodeEvidence[$n].consumers } }
    if ($list.Count -eq 0) { return $null }
    return $list
}

function Get-NodeTestFiles {
    param([string[]]$NodeNames)
    $files = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($n in $NodeNames) {
        if (-not $nodeEvidence.ContainsKey($n)) { continue }
        foreach ($o in $nodeEvidence[$n].corpus.origins) { if ($o -like 'tests/*' -or $o -like 'conformance/*') { [void]$files.Add($o) } }
    }
    return @($files | Sort-Object)
}

function Get-NodeDocFiles {
    param([string[]]$NodeNames)
    $files = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($n in $NodeNames) { if ($nodeEvidence.ContainsKey($n)) { foreach ($d in $nodeEvidence[$n].documentation.files) { [void]$files.Add($d) } } }
    return @($files | Sort-Object)
}

function Get-BrowserState {
    param([string[]]$NodeNames, [string]$ExtraText = '')
    $text = $ExtraText
    foreach ($n in $NodeNames) { if ($nodeByName.ContainsKey($n)) { $text += ' ' + $nodeByName[$n].Section + ' ' + $nodeByName[$n].Comment } }
    if ($text -match '(?i)web (target )?(reports unsupported|fails loudly)|console/desktop only|console only|windows console only|not supported on the web') {
        return @('unsupported', 'stated in the contract comment or boundary document for this capability; the web target reports it as unsupported')
    }
    $consumers = Get-NodeConsumers -NodeNames $NodeNames
    if ($null -ne $consumers -and (@($consumers | Where-Object { $_.javascript -or $_.browser }).Count -gt 0)) {
        return @('unverified', 'the JavaScript compiler or web runtime references a linked contract member; no browser execution of this capability was found in the manifest evidence')
    }
    return @('unverified', 'no browser evidence gathered')
}

function Get-Hints {
    param([string]$Section, [string]$Comment, [string]$StdSection)
    $hints = New-Object System.Collections.Generic.List[string]
    $text = "$Section $Comment"
    if ($text -match '(?i)console/desktop only|console only|windows console only|windows only') { $hints.Add('host-specific: the contract comment limits this to console/desktop or Windows') }
    if ($StdSection -match 'Target-specific') { $hints.Add('host-specific: listed under "Target-specific library" in STANDARD_LIBRARY.md') }
    if ($text -match '(?i)internal|reserved|legacy|deprecated') { $hints.Add('possibly-internal-or-legacy: the contract comment says internal, reserved, legacy or deprecated') }
    return $hints.ToArray()
}

# 4a. reachability rows
foreach ($row in $reachRows) {
    $key = "$($row.Area)|$($row.Capability)"
    $classNames = @([regex]::Matches($row.Handler, '\b([A-Z][A-Za-z]+(?:Stmt|Expr))\b') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $nodes = New-Object System.Collections.Generic.List[string]
    $unresolved = New-Object System.Collections.Generic.List[string]
    foreach ($c in $classNames) { if ($classToNode.ContainsKey($c)) { $nodes.Add($classToNode[$c]) } else { $unresolved.Add($c) } }
    foreach ($op in @([regex]::Matches($row.Handler, '\b([A-Z][A-Za-z]+Op)\b') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)) {
        $unresolved.Add("$op (an operator enum member, not an AST node class)")
    }
    foreach ($n in $nodes) { [void]$claimedNodes.Add($n) }
    $testFiles = @('tests/StandardLibrary.Tests.ps1') + @(Get-NodeTestFiles -NodeNames $nodes | Where-Object { $_ -ne 'tests/StandardLibrary.Tests.ps1' })
    $case = if ($caseForRow.ContainsKey($row.Capability)) { $caseForRow[$row.Capability] } else { $null }
    # The test file's -Area label; recorded as-is so the auditor can verify it exists.
    $testArea = if ($testAreaForRowArea.ContainsKey($row.Area)) { $testAreaForRowArea[$row.Area] } else { $row.Area }
    $cases = @()
    if ($case) { $cases = @("$testArea :: $case") }
    $browser = Get-BrowserState -NodeNames $nodes.ToArray()
    $conflicts = New-Object System.Collections.Generic.List[object]
    if (-not $rowStdMatches.ContainsKey($key)) {
        $conflicts.Add([ordered]@{ code = 'REACHABILITY_ONLY'; detail = 'Listed in STANDARD_LIBRARY_REACHABILITY.md; no phrase in STANDARD_LIBRARY.md was matched to it within its area.' })
    }
    if (-not $case) {
        $conflicts.Add([ordered]@{ code = 'NO_DEDICATED_TEST_CASE'; detail = 'The reachability matrix lists this row, but tests/StandardLibrary.Tests.ps1 has no case named for it.' })
    }
    if ($testArea -ne $row.Area) {
        $conflicts.Add([ordered]@{ code = 'AREA_NAME_MISMATCH'; detail = "The reachability matrix names this area '$($row.Area)' but tests/StandardLibrary.Tests.ps1 labels its case area '$testArea'." })
    }
    $docFiles = @('docs/STANDARD_LIBRARY_REACHABILITY.md') + $(if ($rowStdMatches.ContainsKey($key)) { @('docs/STANDARD_LIBRARY.md') } else { @() })
    $sources = @('reachability-matrix') + $(if ($rowStdMatches.ContainsKey($key)) { @('stdlib-boundary-doc') } else { @() })
    $id = New-UniqueId ('R-' + (ConvertTo-Slug $row.Area) + '-' + (ConvertTo-Slug $row.Capability))
    $implBlock = New-ImplementationBlock -Consumers (Get-NodeConsumers -NodeNames $nodes.ToArray())
    $hostsBlock = New-HostBlock -TestEvidence 'yes' -Browser $browser[0] -BrowserEvidence $browser[1]
    $nodeList = @($nodes | Select-Object -Unique)
    $capabilities.Add([ordered]@{
        id = $id
        category = $row.Area
        publicName = $row.Capability
        syntaxOrForm = $row.Syntax
        sources = $sources
        boundaryStatus = 'unresolved'
        status = 'candidate'
        hints = @()
        conflicts = $conflicts.ToArray()
        contract = [ordered]@{ tokenKinds = @(); nodeKinds = $nodeList; unresolvedReferences = @($unresolved); derivation = 'AST classes named in the reachability matrix handler column, mapped to NodeKind through the contract' }
        implementation = $implBlock
        tests = [ordered]@{ files = @($testFiles | Select-Object -Unique); cases = $cases; derivation = 'curated: StandardLibrary.Tests.ps1 case name, plus test files whose programs parse to a linked node' }
        hosts = $hostsBlock
        documentation = [ordered]@{ files = $docFiles; anchors = @('docs/STANDARD_LIBRARY_REACHABILITY.md#reachability-matrix') }
        productionReachability = [ordered]@{ reachable = $true; evidence = @("docs/STANDARD_LIBRARY_REACHABILITY.md row '$($row.Area) / $($row.Capability)' marked $($row.Status)", $(if ($case) { "tests/StandardLibrary.Tests.ps1 case '$testArea :: $case' runs canonical syntax through otter.cmd run" } else { 'no dedicated suite case' })) }
    })
}

# 4b. STANDARD_LIBRARY.md phrases (merged into a node or reachability capability when linked)
$nodeCapabilityIndex = @{}   # node name -> capability record (for merging documentation)
$stdOnlyCount = 0
for ($pi = 0; $pi -lt $stdPhrases.Count; $pi++) {
    if ($stdMatchedToRow.ContainsKey($pi)) { continue }
    $p = $stdPhrases[$pi]
    $linked = @(Find-NodesForPhrase -Phrase $p.Phrase)
    $isTarget = $p.Section -match 'Target-specific'
    $conflicts = New-Object System.Collections.Generic.List[object]
    $conflicts.Add([ordered]@{ code = 'STDLIB_DOC_ONLY'; detail = 'Listed in STANDARD_LIBRARY.md; not in the reachability matrix.' })
    if ($linked.Count -eq 0) { $conflicts.Add([ordered]@{ code = 'NO_CONTRACT_LINK_FOUND'; detail = 'No contract member could be linked by name or comment word match; this may be prose or a broad area rather than one operation.' }) }
    foreach ($n in $linked) { [void]$claimedNodes.Add($n) }
    $browser = Get-BrowserState -NodeNames $linked -ExtraText ($(if ($isTarget) { $p.Raw + ' ' + $p.Area } else { '' }))
    $testFiles = @(Get-NodeTestFiles -NodeNames $linked)
    $id = New-UniqueId ('S-' + (ConvertTo-Slug $p.Area) + '-' + (ConvertTo-Slug $p.Phrase))
    $stdOnlyCount++
    $capabilities.Add([ordered]@{
        id = $id
        category = $p.Area
        publicName = $p.Phrase
        syntaxOrForm = $p.Raw
        sources = @('stdlib-boundary-doc')
        boundaryStatus = 'unresolved'
        status = 'candidate'
        hints = @(Get-Hints -Section '' -Comment '' -StdSection $p.Section)
        conflicts = $conflicts.ToArray()
        contract = [ordered]@{ tokenKinds = @(); nodeKinds = @($linked); unresolvedReferences = @(); derivation = 'word match against contract member names and comments (a hint for review, not a decision)' }
        implementation = New-ImplementationBlock -Consumers (Get-NodeConsumers -NodeNames $linked)
        tests = [ordered]@{ files = $testFiles; cases = @(); derivation = 'test files or conformance fixtures containing a program that parses to a linked node' }
        hosts = New-HostBlock -TestEvidence $(if ($linked.Count -eq 0) { 'unknown' } elseif ($testFiles.Count -gt 0) { 'yes' } else { 'no' }) -Browser $browser[0] -BrowserEvidence $browser[1]
        documentation = [ordered]@{ files = @('docs/STANDARD_LIBRARY.md'); anchors = @("docs/STANDARD_LIBRARY.md#$(ConvertTo-Slug $p.Section)") }
        productionReachability = [ordered]@{ reachable = $null; evidence = @('not in the reachability matrix; production reachability is not established by the manifest evidence') }
        docSection = $p.Section
    })
}

# 4c. contract members not claimed above
$stdRefFiles = 'docs/STANDARD_LIBRARY.md'
foreach ($m in $nodeInventory) {
    if ($claimedNodes.Contains($m.Name)) { continue }
    $ev = $nodeEvidence[$m.Name]
    $section = $m.Section
    # The contract has runs of members with no heading of their own (for example
    # CopyFile/MoveFile/FileLocked follow the "UI layout/show (D47)" comment), so the
    # nearest section comment can be inherited. Unambiguous names are classified by
    # name first; everything else falls back to the section.
    $kindClass = if ($m.Name -match '(File|Folder|Directory|Program|Json|Csv)') { 'library-operation' }
                 elseif ($m.Name -eq 'UseModule') { 'language-construct' }
                 elseif ($section -match '^(expressions|statements)$' -or $m.Name -in @('Program', 'Literal', 'Variable')) { 'language-construct' }
                 elseif ($section -match '(?i)UI|layout|animation|reactiv|route|component|drag') { 'ui-or-web' }
                 elseif ($section -match '(?i)tcp|udp|websocket|http|network|server|socket') { 'network' }
                 else { 'library-operation' }
    $testFiles = @(Get-NodeTestFiles -NodeNames @($m.Name))
    $browser = Get-BrowserState -NodeNames @($m.Name)
    $conflicts = New-Object System.Collections.Generic.List[object]
    $conflicts.Add([ordered]@{ code = 'IMPLEMENTATION_ONLY'; detail = 'Declared in the frozen contract and implemented; not listed in STANDARD_LIBRARY_REACHABILITY.md, and no STANDARD_LIBRARY.md phrase could be linked to it.' })
    if ($ev.disposition -eq 'wired-not-exercised-by-corpus') {
        $conflicts.Add([ordered]@{ code = 'NO_PROGRAM_IN_CORPUS'; detail = 'No program anywhere in the test/conformance/example corpus parses to this node.' })
    }
    if ($ev.disposition -eq 'declared-exception') { $conflicts.Add([ordered]@{ code = 'RESERVED_MEMBER'; detail = [string]$ev.exceptionReason }) }
    $desc = if ($m.Comment) { $m.Comment } else { $m.Name }
    $id = New-UniqueId ('N-' + $m.Name)
    $capabilities.Add([ordered]@{
        id = $id
        category = $section
        publicName = $m.Name
        syntaxOrForm = $desc
        sources = @('contract')
        surfaceKind = $kindClass
        boundaryStatus = 'unresolved'
        status = 'candidate'
        hints = @(Get-Hints -Section $section -Comment $m.Comment -StdSection '')
        conflicts = $conflicts.ToArray()
        contract = [ordered]@{ tokenKinds = @(); nodeKinds = @($m.Name); unresolvedReferences = @(); derivation = 'declared in the frozen contract; category is the contract''s own section comment' }
        implementation = New-ImplementationBlock -Consumers @($ev.consumers)
        tests = [ordered]@{ files = $testFiles; cases = @(); derivation = 'test files or conformance fixtures containing a program that parses to this node' }
        hosts = New-HostBlock -TestEvidence $(if ($testFiles.Count -gt 0) { 'yes' } else { 'no' }) -Browser $browser[0] -BrowserEvidence $browser[1]
        documentation = [ordered]@{ files = @(Get-NodeDocFiles -NodeNames @($m.Name)); anchors = @() }
        productionReachability = [ordered]@{ reachable = $null; evidence = @('not in the reachability matrix; production reachability is not established by the manifest evidence') }
    })
}

# --- 5. event system (curated from docs/OTTER_1_0_EVENT_LOOP_REVIEW.md) --------

$eventFamilies = [ordered]@{
    'file-watcher'    = [ordered]@{ nodes = @('WatchDeclare', 'WatchEvent', 'StopWatching', 'IsWatching'); passesPerEvent = '1 (Wait-Event); events with no handler still use a pass'; queueBehavior = 'one PowerShell event per pass'; measured = 'watcher_burst: 40 events in 177 ms (about 226 events/s), no sleeping' }
    'websocket'       = [ordered]@{ nodes = @('WebSocketConnect', 'WebSocketSend', 'WebSocketClose', 'WebSocketEvent', 'WebSocketIsState', 'WebSocketErrorValue'); passesPerEvent = '1 (arms and checks in the same pass)'; queueBehavior = 'at most one message per socket per pass'; measured = 'capped near one message per loop pass per socket; each pass sleeps about 16 ms' }
    'tcp-udp'         = [ordered]@{ nodes = @('TcpConnect', 'TcpListen', 'TcpStop', 'UdpOpen', 'UdpSend', 'NetClose'); passesPerEvent = '2 for UDP datagrams and TCP reads (arm, then consume); 1 for TCP accept'; queueBehavior = 'at most one event per socket per pass'; measured = 'udp_burst: 200 datagrams in 6,385 ms (31 events/s), 400 passes, 91% of loop time asleep' }
    'command-job'     = [ordered]@{ nodes = @('StartCommand', 'JobContext'); passesPerEvent = '1'; queueBehavior = 'drains the whole queue in one step (unbounded)'; measured = 'job_output: 300 events in 347 ms (about 865 events/s); job_starve: one step ran about 1.5 s and delayed a UDP handler until 4,000 job lines had finished' }
    'http'            = [ordered]@{ nodes = @('HttpStart', 'HttpCancel', 'HttpEvent'); passesPerEvent = '1'; queueBehavior = 'every completed request per pass'; measured = 'not separately measured' }
    'wait'            = [ordered]@{ nodes = @('WaitDelay'); passesPerEvent = 'n/a'; queueBehavior = 'pumps only HTTP and command-job steps during the wait; socket, WebSocket and watcher events are not dispatched during a wait'; measured = 'from source review (docs/OTTER_1_0_EVENT_LOOP_REVIEW.md section 2); not benchmarked' }
    'timer'           = [ordered]@{ nodes = @('StartTimer'); passesPerEvent = 'n/a'; queueBehavior = 'a stopwatch value; Otter has no timer event source'; measured = 'n/a' }
    'ui-event'        = [ordered]@{ nodes = @('When', 'UiEvent'); passesPerEvent = 'n/a'; queueBehavior = 'dispatched by the WPF dispatcher (desktop) or browser JavaScript (web); NOT part of the interpreter event loop'; measured = 'outside the loop; the 30 events/s figure does not apply' }
}
$eventTagged = @{}
foreach ($family in $eventFamilies.Keys) {
    foreach ($n in $eventFamilies[$family].nodes) { $eventTagged[$n] = $family }
}
foreach ($cap in $capabilities) {
    foreach ($n in $cap.contract.nodeKinds) {
        if ($eventTagged.ContainsKey($n)) {
            $family = $eventTagged[$n]
            $cap['eventSource'] = [ordered]@{
                family = $family
                currentBehavior = [ordered]@{
                    passesPerEvent = $eventFamilies[$family].passesPerEvent
                    queueBehavior = $eventFamilies[$family].queueBehavior
                    measured = $eventFamilies[$family].measured
                }
                reference = 'docs/OTTER_1_0_EVENT_LOOP_REVIEW.md'
                semanticsStatus = 'pending-contract-decision'
            }
            break
        }
    }
}

$eventContract = [ordered]@{
    reference = 'docs/OTTER_1_0_EVENT_LOOP_REVIEW.md'
    status = 'pending-contract-decision'
    note = 'The answers below are NOT chosen here. Each records the CURRENT measured behavior so the contract decision can be made against facts; decision stays null until the contract freeze records it.'
    questions = @(
        [ordered]@{ id = 'EV1'; question = 'Is cross-source fairness guaranteed or best-effort?'; currentBehavior = 'Fixed per-pass order (watcher, WebSocket, TCP/UDP, HTTP, jobs). No fairness guarantee; command jobs win under load.'; decision = $null }
        [ordered]@{ id = 'EV2'; question = 'May one event source drain an unbounded queue before others run?'; currentBehavior = 'Yes for command jobs (while TryDequeue). No for sockets, WebSockets and watchers (one event per source per pass).'; decision = $null }
        [ordered]@{ id = 'EV3'; question = 'Which event sources are dispatched during wait?'; currentBehavior = 'Only HTTP and command jobs. Socket, WebSocket and watcher events are held until the main program ends.'; decision = $null }
        [ordered]@{ id = 'EV4'; question = 'Is event ordering guaranteed only within a source?'; currentBehavior = 'FIFO within a source; unspecified across sources.'; decision = $null }
        [ordered]@{ id = 'EV5'; question = 'Are TCP/UDP receive callbacks allowed to be delayed by polling cadence?'; currentBehavior = 'Yes: two loop passes per UDP/TCP event and a 10 ms sleep that lasts about 16 ms on Windows (about 31 events/s).'; decision = $null }
        [ordered]@{ id = 'EV6'; question = 'Is the event loop cooperative rather than real-time?'; currentBehavior = 'Cooperative: handlers run to completion on one thread and are never preempted.'; decision = $null }
        [ordered]@{ id = 'EV7'; question = 'Are the current scheduling limits documented as part of 1.0?'; currentBehavior = 'Documented in docs/OTTER_1_0_EVENT_LOOP_REVIEW.md only; not in the user documentation.'; decision = $null }
    )
}

# --- 5b. cross-document conflicts (each verified by hand; evidence paths are audited) ---

$documentConflicts = @(
    [ordered]@{
        id = 'DC1'; topic = 'HTTP client on the console target'
        claims = @(
            [ordered]@{ file = 'docs/STANDARD_LIBRARY.md'; says = 'HTTP client: "Web target via browser fetch; not the headless console interpreter"' }
            [ordered]@{ file = 'docs/OTTER_1_0_CAPABILITY_MATRIX.md'; says = 'HTTP GET/POST/PUT/DELETE: Console "No"' }
            [ordered]@{ file = 'docs/OTTER_1_0_RELEASE_SCOPE_MATRIX.md'; says = 'HTTP Client: "Not supported on headless Console runtime"' }
        )
        evidence = @('src/Otter.Interpreter.psm1', 'tests/Http.Tests.ps1')
        observation = 'The console interpreter implements HttpGet/HttpPost/HttpPut/HttpDelete (Invoke-OtterHttpRequest, D116A) and tests/Http.Tests.ps1 exercises them against a local server, in-process and through otter.ps1. The three documents understate the implementation.'
        decision = $null
    }
    [ordered]@{
        id = 'DC2'; topic = 'use "file.ot" modules'
        claims = @(
            [ordered]@{ file = 'docs/OTTER_1_0_CAPABILITY_MATRIX.md'; says = '`use` modules: Console "No - explicit diagnostic", status "DEFERRED FROM 1.0"' }
            [ordered]@{ file = 'docs/OTTER_1_0_RELEASE_SCOPE_MATRIX.md'; says = 'File modules: TARGET-SPECIFIC, certified through console production entry points' }
            [ordered]@{ file = 'docs/OTTER_1_0_MODULE_STATUS.md'; says = 'file imports certified for the console production entry point' }
        )
        evidence = @('tests/UseModuleProduction.Tests.ps1')
        observation = 'Codex reconciled GRAMMAR.md and the scope matrix (553bf33) but docs/OTTER_1_0_CAPABILITY_MATRIX.md still carries the older DEFERRED row.'
        decision = $null
    }
    [ordered]@{
        id = 'DC3'; topic = 'Size of the reachability matrix'
        claims = @(
            [ordered]@{ file = 'docs/STANDARD_LIBRARY_REACHABILITY.md'; says = '"31 / 31 capabilities certified"' }
        )
        evidence = @('docs/STANDARD_LIBRARY_REACHABILITY.md', 'tests/StandardLibrary.Tests.ps1')
        observation = 'The matrix table has 34 rows; the suite has 31 cases. Lists/Mutation share one case, as do Object Definition/Property Read-Write. The per-row mapping is in this manifest (tests.cases).'
        decision = $null
    }
    [ordered]@{
        id = 'DC4'; topic = 'Area naming between the reachability matrix and its suite'
        claims = @(
            [ordered]@{ file = 'docs/STANDARD_LIBRARY_REACHABILITY.md'; says = 'area "Processes"' }
            [ordered]@{ file = 'tests/StandardLibrary.Tests.ps1'; says = 'area "Process"' }
        )
        evidence = @('docs/STANDARD_LIBRARY_REACHABILITY.md', 'tests/StandardLibrary.Tests.ps1')
        observation = 'Cosmetic, but it breaks mechanical matching between the document and its certification suite.'
        decision = $null
    }
    [ordered]@{
        id = 'DC5'; topic = 'Full-suite evidence counts'
        claims = @(
            [ordered]@{ file = 'docs/OTTER_1_0_CONTRACT_COVERAGE_MANIFEST.md'; says = '"53 of 53 test files passed" (2026-09-27)' }
            [ordered]@{ file = 'docs/OTTER_1_0_PERFORMANCE_BASELINE.md'; says = '"55 of 55" test files pass (post-optimization validation)' }
        )
        evidence = @('tests/Run-Tests.ps1')
        observation = 'Both may be true at their own commits (test files were added in between: Profiler, Optimizations). Neither is a clean-checkout run; the certification record must name the candidate SHA it ran against.'
        decision = $null
    }
)

# --- 6. write ---------------------------------------------------------------

$sorted = @($capabilities | Sort-Object { $_['id'] })
$bySource = @{}
foreach ($c in $sorted) { $k = ($c['sources'] -join '+'); if (-not $bySource.ContainsKey($k)) { $bySource[$k] = 0 }; $bySource[$k]++ }

$document = [ordered]@{
    schemaVersion = 1
    manifest = [ordered]@{
        purpose = 'Evidence manifest for the Otter 1.0 candidate surface. It records what exists, what is documented, what is tested and where they disagree. It does NOT decide what is public.'
        authority = 'Codex owns the public-boundary decision. Every capability is seeded status=candidate, boundaryStatus=unresolved.'
        seededFromCommit = Get-OtterGitSha
        candidateSha = 'a5146971fa6c0a4c2d33dee283897e640e38fae5'
        candidateShaSource = 'docs/OTTER_1_0_CONTRACT_FREEZE_REPORT.md (Gate 1, certified by Codex) and docs/OTTER_1_0_CLEAN_CHECKOUT_EVIDENCE_2026-09-27.md'
        candidateShaNote = 'Recorded, not chosen here: the Gate 1 candidate Codex nominated. It contains the optimization pass and the event-loop review. The earlier candidate 344db09b is superseded. The public boundary in this manifest is still unresolved.'
        seededFrom = @('docs/STANDARD_LIBRARY_REACHABILITY.md', 'docs/STANDARD_LIBRARY.md', 'Otter.Contract.psm1', 'release/otter-1.0-contract-coverage.json', 'docs/OTTER_1_0_EVENT_LOOP_REVIEW.md', 'tests/StandardLibrary.Tests.ps1')
        contractSha256 = Get-OtterSha256 'Otter.Contract.psm1'
        capabilityCountBySource = $bySource
    }
    vocabulary = [ordered]@{
        status = @('candidate', 'certified', 'hostSpecific', 'deferred', 'internal')
        statusNote = 'certified requires complete evidence (see tools/Test-OtterReleaseSurface.ps1). Seeds are all candidate.'
        boundaryStatus = @('unresolved', 'decided-public', 'decided-not-public')
        implementationState = @('referenced', 'not-referenced', 'unknown', 'not-applicable', 'unsupported')
        implementationStateNote = 'not-referenced means searched and not found; it does NOT mean unsupported. unsupported is used only when a diagnostic or document says so.'
        hostState = @('exercised', 'not-exercised', 'unverified', 'unsupported', 'not-applicable')
        hostStateNote = 'exercised: a test that runs on that host covers the capability. unverified: nothing was run for this capability on that host. Missing is never used to imply support.'
        reachability = 'true / false / null. null means not established by the manifest evidence; it is not false.'
        tokenKindsNote = 'contract.tokenKinds is empty in seeded entries: token-level evidence (producers, corpus programs, documentation, disposition) is in release/otter-1.0-contract-coverage.json, not linked per capability.'
        conflictCodes = [ordered]@{
            REACHABILITY_ONLY = 'listed in STANDARD_LIBRARY_REACHABILITY.md but not in STANDARD_LIBRARY.md'
            STDLIB_DOC_ONLY = 'listed in STANDARD_LIBRARY.md but not in the reachability matrix'
            IMPLEMENTATION_ONLY = 'declared and implemented but in neither document'
            NO_DEDICATED_TEST_CASE = 'in the reachability matrix but no dedicated suite case'
            NO_CONTRACT_LINK_FOUND = 'a documented phrase could not be linked to any contract member'
            NO_PROGRAM_IN_CORPUS = 'no program in the test/conformance/example corpus parses to the linked member'
            RESERVED_MEMBER = 'a declared, documented reservation'
            AREA_NAME_MISMATCH = 'the reachability matrix and its certification suite name the same area differently'
        }
    }
    eventContract = $eventContract
    documentConflicts = $documentConflicts
    capabilities = $sorted
}

$outDir = Split-Path -Parent $outPath
if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[System.IO.File]::WriteAllText($outPath, ($document | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))

Write-Output ("Reachability rows: {0}; STANDARD_LIBRARY.md phrases: {1} ({2} matched to reachability rows, {3} own entries)" -f $reachRows.Count, $stdPhrases.Count, $stdMatchedToRow.Count, $stdOnlyCount)
Write-Output ("Capabilities seeded: {0}" -f $sorted.Count)
foreach ($k in ($bySource.Keys | Sort-Object)) { Write-Output ("  {0}: {1}" -f $k, $bySource[$k]) }
Write-Output "Written: $outPath"
