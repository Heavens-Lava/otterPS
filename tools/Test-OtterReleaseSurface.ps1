<#
.SYNOPSIS
    Audits release/otter-1.0-surface.json against the repository. READ-ONLY.

.DESCRIPTION
    Verifies the evidence manifest is internally consistent and that its claims
    are still true of the source. It never modifies source or documentation and
    it never decides what is public.

    Errors (exit code 1):
      * the manifest or the derived coverage file is missing or malformed
      * duplicate capability ids; missing required fields
      * invalid status / boundaryStatus values or combinations
      * a capability marked `certified` with missing required evidence
      * a host or implementation target that is missing instead of explicit
      * referenced files, contract members, test cases or documentation anchors that do not exist
      * an implementation claim ('referenced' / 'not-referenced') that no longer matches the source
      * a contract member that no capability accounts for
      * derived coverage evidence that is stale relative to the contract or that
        reports a structural problem in a declared token or node
      * an unfilled or malformed event-contract question

    Warnings (reported, exit code unaffected): counts of unresolved boundary
    decisions, documentation conflicts, and capabilities without production
    reachability evidence.

.PARAMETER Manifest
    Path to the manifest (default release/otter-1.0-surface.json).
.PARAMETER Coverage
    Path to the derived contract-coverage file.
.PARAMETER Quiet
    Print only errors and the final result line.
#>
[CmdletBinding()]
param(
    [string]$Manifest = 'release/otter-1.0-surface.json',
    [string]$Coverage = 'release/otter-1.0-contract-coverage.json',
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ReleaseSurface.Common.ps1"
$repoRoot = Get-OtterRepoRoot

$errors = New-Object System.Collections.Generic.List[string]
function Add-AuditError { param([string]$Message) $script:errors.Add($Message) }

function Resolve-RepoPath { param([string]$Path) if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repoRoot $Path } }

# --- load ----------------------------------------------------------------------

$manifestPath = Resolve-RepoPath $Manifest
$coveragePath = Resolve-RepoPath $Coverage
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { Write-Output "FAIL: manifest not found: $Manifest"; exit 1 }
try { $doc = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
catch { Write-Output "FAIL: manifest is not valid JSON: $($_.Exception.Message)"; exit 1 }

$cov = $null
if (Test-Path -LiteralPath $coveragePath -PathType Leaf) {
    try { $cov = [System.IO.File]::ReadAllText($coveragePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
    catch { Add-AuditError "coverage file is not valid JSON: $($_.Exception.Message)" }
}
else { Add-AuditError "coverage file not found: $Coverage (run tools/New-OtterContractEvidence.ps1)" }

$contractText = Read-OtterText 'Otter.Contract.psm1'
$nodeNames = @{}; foreach ($m in (Get-OtterEnumInventory -ContractText $contractText -EnumName 'NodeKind')) { $nodeNames[$m.Name] = $true }
$tokenNames = @{}; foreach ($m in (Get-OtterEnumInventory -ContractText $contractText -EnumName 'TokenKind')) { $tokenNames[$m.Name] = $true }
$nodeClasses = Get-OtterNodeClassMap -ContractText $contractText

if ($doc.schemaVersion -ne 1) { Add-AuditError "unsupported schemaVersion '$($doc.schemaVersion)' (expected 1)" }
foreach ($required in @('manifest', 'vocabulary', 'eventContract', 'capabilities')) {
    if ($null -eq $doc.PSObject.Properties[$required]) { Add-AuditError "manifest is missing the top-level section '$required'" }
}
if ($errors.Count -gt 0 -and $null -eq $doc.PSObject.Properties['capabilities']) { $errors | ForEach-Object { Write-Output "ERROR: $_" }; Write-Output "FAIL: $($errors.Count) error(s)"; exit 1 }

$vocab = $doc.vocabulary
$statusValues = @($vocab.status)
$boundaryValues = @($vocab.boundaryStatus)
$implStates = @($vocab.implementationState)
$hostStates = @($vocab.hostState)
$hostKeys = @('windowsPowerShell51', 'windowsPowerShell7', 'linuxPowerShell7', 'macosPowerShell7', 'browser')
$implKeys = @('interpreter', 'javascript', 'browser', 'desktop', 'provider')

# Module text for re-verifying implementation claims.
$consumerGroups = Get-OtterConsumerGroups
$groupText = @{}
foreach ($g in $consumerGroups.Keys) { $groupText[$g] = (($consumerGroups[$g] | ForEach-Object { Read-OtterText $_ }) -join "`n") }

# Test-file text cache for case verification.
$textCache = @{}
function Get-CachedText { param([string]$Rel) if (-not $script:textCache.ContainsKey($Rel)) { $script:textCache[$Rel] = Read-OtterText $Rel }; return $script:textCache[$Rel] }

function Get-HeadingSlugs {
    param([string]$Rel)
    $text = Get-CachedText $Rel
    $slugs = @{}
    if ($null -eq $text) { return $slugs }
    foreach ($m in [regex]::Matches($text, '(?m)^#{1,6}\s+(.+?)\s*$')) {
        $slug = ($m.Groups[1].Value.ToLowerInvariant() -replace '[`*_]', '' -replace '[^a-z0-9 \-]', '' -replace ' ', '-')
        $slugs[$slug] = $true
    }
    return $slugs
}

# --- per-capability checks -------------------------------------------------------

$seen = @{}
$certified = 0
$linkedNodes = @{}
$unresolvedBoundary = 0
$withConflicts = 0
$noReachability = 0

foreach ($cap in $doc.capabilities) {
    $id = [string]$cap.id
    if ([string]::IsNullOrWhiteSpace($id)) { Add-AuditError 'a capability has no id'; continue }
    if ($seen.ContainsKey($id)) { Add-AuditError "duplicate capability id '$id'" }
    $seen[$id] = $true
    $where = "[$id]"

    foreach ($field in @('category', 'publicName', 'syntaxOrForm', 'sources', 'boundaryStatus', 'status', 'conflicts', 'contract', 'implementation', 'tests', 'hosts', 'documentation', 'productionReachability')) {
        if ($null -eq $cap.PSObject.Properties[$field]) { Add-AuditError "$where missing required field '$field'" }
    }

    # status / boundary combinations
    if ($statusValues -notcontains $cap.status) { Add-AuditError "$where invalid status '$($cap.status)'" }
    if ($boundaryValues -notcontains $cap.boundaryStatus) { Add-AuditError "$where invalid boundaryStatus '$($cap.boundaryStatus)'" }
    if ($cap.boundaryStatus -eq 'unresolved') { $unresolvedBoundary++ }
    if ($cap.status -eq 'certified' -and $cap.boundaryStatus -ne 'decided-public') { Add-AuditError "$where is certified but boundaryStatus is '$($cap.boundaryStatus)' (certified requires decided-public)" }
    if ($cap.boundaryStatus -eq 'decided-not-public' -and $cap.status -notin @('internal', 'deferred')) { Add-AuditError "$where is decided-not-public but status is '$($cap.status)' (must be internal or deferred)" }
    if ($cap.status -in @('internal', 'deferred') -and $cap.boundaryStatus -eq 'decided-public') { Add-AuditError "$where has status '$($cap.status)' but boundaryStatus decided-public" }
    if ($cap.status -eq 'hostSpecific' -and $cap.boundaryStatus -ne 'decided-public') { Add-AuditError "$where is hostSpecific but boundaryStatus is '$($cap.boundaryStatus)'" }

    # hosts must be explicit
    foreach ($h in $hostKeys) {
        $entry = if ($cap.hosts) { $cap.hosts.PSObject.Properties[$h] } else { $null }
        if ($null -eq $entry) { Add-AuditError "$where hosts.$h is missing (unsupported hosts must be explicit, not absent)"; continue }
        if ($hostStates -notcontains $entry.Value.state) { Add-AuditError "$where hosts.$h has invalid state '$($entry.Value.state)'" }
        if ([string]::IsNullOrWhiteSpace([string]$entry.Value.evidence)) { Add-AuditError "$where hosts.$h has no evidence text" }
    }
    if ($cap.status -eq 'hostSpecific' -and $cap.hosts) {
        $limited = @($hostKeys | Where-Object { $cap.hosts.$_.state -in @('unsupported', 'not-applicable') }).Count
        if ($limited -eq 0) { Add-AuditError "$where is hostSpecific but no host is marked unsupported or not-applicable" }
    }

    # implementation targets must be explicit and match the source
    foreach ($g in $implKeys) {
        $entry = if ($cap.implementation) { $cap.implementation.PSObject.Properties[$g] } else { $null }
        if ($null -eq $entry) { Add-AuditError "$where implementation.$g is missing"; continue }
        $state = $entry.Value.state
        if ($implStates -notcontains $state) { Add-AuditError "$where implementation.$g has invalid state '$state'"; continue }
        foreach ($module in @($entry.Value.modules)) {
            if (-not (Test-Path -LiteralPath (Resolve-RepoPath $module) -PathType Leaf)) { Add-AuditError "$where implementation.$g references missing module '$module'" }
        }
        if ($state -in @('referenced', 'not-referenced')) {
            $hit = $false
            foreach ($n in @($cap.contract.nodeKinds)) {
                $class = if ($nodeClasses.ContainsKey($n)) { $nodeClasses[$n] } else { $null }
                if (Test-OtterNodeReferenced -NodeName $n -ClassName $class -Text $groupText[$g]) { $hit = $true; break }
            }
            if ($state -eq 'referenced' -and -not $hit) { Add-AuditError "$where implementation.$g claims 'referenced' but no linked contract member is referenced in $(@($entry.Value.modules) -join ', ') any more" }
            if ($state -eq 'not-referenced' -and $hit) { Add-AuditError "$where implementation.$g claims 'not-referenced' but a linked contract member is now referenced in those modules" }
        }
    }

    # contract members exist
    foreach ($n in @($cap.contract.nodeKinds)) {
        if (-not $nodeNames.ContainsKey($n)) { Add-AuditError "$where references NodeKind '$n' which is not declared in the contract" } else { $linkedNodes[$n] = $true }
    }
    foreach ($t in @($cap.contract.tokenKinds)) {
        if (-not $tokenNames.ContainsKey($t)) { Add-AuditError "$where references TokenKind '$t' which is not declared in the contract" }
    }

    # tests exist, and named cases exist in them
    foreach ($f in @($cap.tests.files)) {
        if (-not (Test-Path -LiteralPath (Resolve-RepoPath $f) -PathType Leaf)) { Add-AuditError "$where references missing test file '$f'" }
    }
    foreach ($case in @($cap.tests.cases)) {
        if ($case -notmatch '^(?<area>.+?) :: (?<name>.+)$') { Add-AuditError "$where test case '$case' is not in 'Area :: name' form"; continue }
        $needle = '-Area "' + $Matches['area'] + '" -Capability "' + $Matches['name'] + '"'
        $found = $false
        foreach ($f in @($cap.tests.files)) { $t = Get-CachedText $f; if ($t -and $t.Contains($needle)) { $found = $true; break } }
        if (-not $found) { Add-AuditError "$where test case '$case' was not found in any listed test file" }
    }

    # documentation exists, anchors resolve
    foreach ($f in @($cap.documentation.files)) {
        $rel = ($f -split '#')[0]
        if (-not (Test-Path -LiteralPath (Resolve-RepoPath $rel) -PathType Leaf)) { Add-AuditError "$where references missing documentation file '$f'" }
    }
    foreach ($a in @($cap.documentation.anchors)) {
        $parts = $a -split '#', 2
        if ($parts.Count -ne 2) { Add-AuditError "$where documentation anchor '$a' is not 'file#anchor'"; continue }
        if (-not (Test-Path -LiteralPath (Resolve-RepoPath $parts[0]) -PathType Leaf)) { Add-AuditError "$where documentation anchor file '$($parts[0])' is missing"; continue }
        if ($parts[0] -like '*.md') {
            $slugs = Get-HeadingSlugs $parts[0]
            if (-not $slugs.ContainsKey($parts[1])) { Add-AuditError "$where documentation anchor '#$($parts[1])' matches no heading in $($parts[0])" }
        }
    }

    # reachability field must be true, false or null (never absent)
    $reach = $cap.productionReachability
    if ($null -ne $reach) {
        if ($null -eq $reach.PSObject.Properties['reachable']) { Add-AuditError "$where productionReachability.reachable is missing (use true, false or null)" }
        elseif ($null -eq $reach.reachable) { $noReachability++ }
    }
    if (@($cap.conflicts).Count -gt 0) { $withConflicts++ }

    # certified requires the full evidence set
    if ($cap.status -eq 'certified') {
        $certified++
        if (@($cap.tests.files).Count -eq 0) { Add-AuditError "$where is certified but has no test files" }
        if (@($cap.contract.nodeKinds).Count + @($cap.contract.tokenKinds).Count -eq 0) { Add-AuditError "$where is certified but is linked to no contract member" }
        if (@($cap.documentation.files).Count -eq 0) { Add-AuditError "$where is certified but has no documentation" }
        if ($reach.reachable -ne $true -or @($reach.evidence).Count -eq 0) { Add-AuditError "$where is certified but production reachability is not true with evidence" }
        if ($cap.hosts.windowsPowerShell51.state -ne 'exercised') { Add-AuditError "$where is certified but Windows PowerShell 5.1 is '$($cap.hosts.windowsPowerShell51.state)', not 'exercised'" }
        if ($cap.implementation.interpreter.state -ne 'referenced') { Add-AuditError "$where is certified but the interpreter implementation is '$($cap.implementation.interpreter.state)'" }
        if (@($cap.conflicts).Count -gt 0) { Add-AuditError "$where is certified but still has $(@($cap.conflicts).Count) unresolved conflict(s)" }
    }
}

# every contract member must be accounted for by some capability
foreach ($n in $nodeNames.Keys) { if (-not $linkedNodes.ContainsKey($n)) { Add-AuditError "NodeKind '$n' is not linked from any manifest capability" } }

# --- event contract -----------------------------------------------------------------

$questions = @($doc.eventContract.questions)
if ($questions.Count -eq 0) { Add-AuditError 'eventContract has no questions' }
$questionIds = @{}
foreach ($q in $questions) {
    if ([string]::IsNullOrWhiteSpace([string]$q.id)) { Add-AuditError 'an event-contract question has no id'; continue }
    if ($questionIds.ContainsKey($q.id)) { Add-AuditError "duplicate event-contract question id '$($q.id)'" }
    $questionIds[$q.id] = $true
    if ($null -eq $q.PSObject.Properties['decision']) { Add-AuditError "event-contract question $($q.id) has no 'decision' field (use null while pending)" }
    if ([string]::IsNullOrWhiteSpace([string]$q.currentBehavior)) { Add-AuditError "event-contract question $($q.id) does not record current behavior" }
}
$pendingQuestions = @($questions | Where-Object { $null -eq $_.decision }).Count

# --- cross-document conflicts ---------------------------------------------------------

foreach ($dc in @($doc.documentConflicts)) {
    if ([string]::IsNullOrWhiteSpace([string]$dc.id)) { Add-AuditError 'a document conflict has no id'; continue }
    if ($null -eq $dc.PSObject.Properties['decision']) { Add-AuditError "document conflict $($dc.id) has no 'decision' field (use null while pending)" }
    foreach ($claim in @($dc.claims)) {
        if (-not (Test-Path -LiteralPath (Resolve-RepoPath $claim.file) -PathType Leaf)) { Add-AuditError "document conflict $($dc.id) cites missing file '$($claim.file)'" }
    }
    foreach ($e in @($dc.evidence)) {
        if (-not (Test-Path -LiteralPath (Resolve-RepoPath $e) -PathType Leaf)) { Add-AuditError "document conflict $($dc.id) cites missing evidence file '$e'" }
    }
}
$pendingDocConflicts = @(@($doc.documentConflicts) | Where-Object { $null -eq $_.decision }).Count

# --- derived coverage evidence ---------------------------------------------------------

$tokenSummary = $null; $nodeSummary = $null; $diagSummary = $null
if ($null -ne $cov) {
    $currentHash = Get-OtterSha256 'Otter.Contract.psm1'
    if ($cov.derivedFrom.contractSha256 -ne $currentHash) { Add-AuditError 'coverage file is stale: Otter.Contract.psm1 has changed since it was generated (re-run tools/New-OtterContractEvidence.ps1)' }
    if ($doc.manifest.contractSha256 -ne $currentHash) { Add-AuditError 'manifest is stale: Otter.Contract.psm1 has changed since it was seeded' }
    $covTokens = @{}; foreach ($t in $cov.tokens) { $covTokens[$t.name] = $t }
    $covNodes = @{}; foreach ($n in $cov.nodes) { $covNodes[$n.name] = $n }
    foreach ($t in $tokenNames.Keys) { if (-not $covTokens.ContainsKey($t)) { Add-AuditError "TokenKind '$t' has no record in the coverage file" } }
    foreach ($n in $nodeNames.Keys) { if (-not $covNodes.ContainsKey($n)) { Add-AuditError "NodeKind '$n' has no record in the coverage file" } }
    foreach ($t in $cov.tokens) { if ($t.disposition -eq 'unwired') { Add-AuditError "TokenKind '$($t.name)' is unwired: no lexer or parser reference and not a declared exception" } }
    foreach ($n in $cov.nodes) {
        if ($n.disposition -in @('no-ast-class', 'not-constructed-by-parser', 'no-runtime-consumer')) { Add-AuditError "NodeKind '$($n.name)' has structural problem '$($n.disposition)'" }
    }
    $tokenSummary = $cov.summary.tokens; $nodeSummary = $cov.summary.nodes; $diagSummary = $cov.summary.diagnostics
}

# --- report --------------------------------------------------------------------------

$total = @($doc.capabilities).Count
if (-not $Quiet) {
    Write-Output "Manifest: $Manifest  ($total capabilities, $certified certified)"
    Write-Output "Boundary unresolved: $unresolvedBoundary of $total"
    Write-Output "With documentation/evidence conflicts: $withConflicts"
    Write-Output "Production reachability not established (null): $noReachability"
    Write-Output "Event-contract questions pending a decision: $pendingQuestions of $($questions.Count)"
    Write-Output "Cross-document conflicts pending a decision: $pendingDocConflicts of $(@($doc.documentConflicts).Count)"
    if ($tokenSummary) {
        Write-Output ("Tokens: {0} declared, {1} exercised by a corpus program, {2} wired but not exercised, {3} declared exception(s)" -f $tokenSummary.declared, $tokenSummary.exercised, $tokenSummary.wiredNotExercised, $tokenSummary.declaredException)
        Write-Output ("Nodes: {0} declared, {1} exercised by a corpus program, {2} wired but not exercised, {3} declared exception(s), {4} structural problem(s)" -f $nodeSummary.declared, $nodeSummary.exercised, $nodeSummary.wiredNotExercised, $nodeSummary.declaredException, $nodeSummary.problems)
        Write-Output ("Diagnostics: {0} call sites; message fragment found in tests/docs for {1}; not found for {2}" -f $diagSummary.callSites, $diagSummary.messageTextFoundInTests, $diagSummary.messageTextNotFound)
    }
}

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Write-Output "ERROR: $e" }
    Write-Output "FAIL: $($errors.Count) manifest/evidence error(s)."
    exit 1
}
Write-Output 'PASS: release-surface manifest and evidence are consistent with the repository.'
exit 0
