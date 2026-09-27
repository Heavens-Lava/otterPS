# ReleaseSurface.Tests.ps1
#
# Proves tools/Test-OtterReleaseSurface.ps1 actually rejects bad manifests.
# Each test copies the real release/otter-1.0-surface.json to a temp file,
# breaks exactly one thing, and asserts the auditor exits 1 with a message that
# names the problem. The real manifest must pass unchanged.
#
# The auditor is read-only; these tests never touch the real manifest.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Release-surface manifest auditor' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Auditor = Join-Path $script:RepoRoot 'tools\Test-OtterReleaseSurface.ps1'
$script:RealManifest = Join-Path $script:RepoRoot 'release\otter-1.0-surface.json'
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_surface_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null

function Invoke-Auditor {
    param([string]$ManifestPath)
    $hostExe = (Get-Process -Id $PID).Path
    $output = & $hostExe -NoProfile -ExecutionPolicy Bypass -File $script:Auditor -Manifest $ManifestPath -Quiet 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = (($output | ForEach-Object { $_.ToString() }) -join "`n") }
}

# Loads the real manifest, applies $Mutate to it, writes it to a temp file.
function New-BrokenManifest {
    param([string]$Name, [scriptblock]$Mutate)
    $doc = [System.IO.File]::ReadAllText($script:RealManifest, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    & $Mutate $doc
    $path = Join-Path $script:Tmp "$Name.json"
    [System.IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 14), [System.Text.UTF8Encoding]::new($false))
    return $path
}

function Get-Cap { param($Doc, [string]$Id) @($Doc.capabilities | Where-Object { $_.id -eq $Id })[0] }

try {
    Test-Otter 'the real manifest passes the audit' {
        $r = Invoke-Auditor -ManifestPath $script:RealManifest
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-True ($r.Text -match 'PASS') 'expected PASS'
    }

    Test-Otter 'a round-tripped copy of the real manifest still passes (the harness itself is sound)' {
        $path = New-BrokenManifest 'roundtrip' { param($d) }
        $r = Invoke-Auditor -ManifestPath $path
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    }

    $cases = @(
        @{ Name = 'duplicate id'; Expect = "duplicate capability id 'R-text-uppercase'"; Mutate = {
            param($d) $copy = (Get-Cap $d 'R-text-lowercase') | ConvertTo-Json -Depth 12 | ConvertFrom-Json; $copy.id = 'R-text-uppercase'; $d.capabilities += $copy } }
        @{ Name = 'invalid status'; Expect = "invalid status 'shipped'"; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').status = 'shipped' } }
        @{ Name = 'certified while boundary unresolved'; Expect = 'is certified but boundaryStatus is'; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').status = 'certified' } }
        @{ Name = 'certified with conflicts and no reachability'; Expect = 'is certified but production reachability is not true'; Mutate = {
            param($d) $c = Get-Cap $d 'N-TcpConnect'; $c.status = 'certified'; $c.boundaryStatus = 'decided-public' } }
        @{ Name = 'decided-not-public but still candidate'; Expect = 'is decided-not-public but status is'; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').boundaryStatus = 'decided-not-public' } }
        @{ Name = 'missing host is not silently allowed'; Expect = 'hosts.linuxPowerShell7 is missing'; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').hosts.PSObject.Properties.Remove('linuxPowerShell7') } }
        @{ Name = 'hostSpecific without an unsupported host'; Expect = 'is hostSpecific but no host is marked unsupported'; Mutate = {
            param($d) $c = Get-Cap $d 'R-text-uppercase'; $c.status = 'hostSpecific'; $c.boundaryStatus = 'decided-public' } }
        @{ Name = 'unknown NodeKind'; Expect = "references NodeKind 'NoSuchNode'"; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').contract.nodeKinds = @('NoSuchNode') } }
        @{ Name = 'unknown TokenKind'; Expect = "references TokenKind 'NoSuchToken'"; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').contract.tokenKinds = @('NoSuchToken') } }
        @{ Name = 'missing test file'; Expect = "references missing test file 'tests/NoSuch.Tests.ps1'"; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').tests.files = @('tests/NoSuch.Tests.ps1') } }
        @{ Name = 'test case that does not exist'; Expect = "test case 'Text :: no such case' was not found"; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').tests.cases = @('Text :: no such case') } }
        @{ Name = 'missing documentation file'; Expect = "references missing documentation file 'docs/NO_SUCH.md'"; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').documentation.files = @('docs/NO_SUCH.md') } }
        @{ Name = 'broken documentation anchor'; Expect = "anchor '#no-such-heading' matches no heading"; Mutate = {
            param($d) (Get-Cap $d 'R-text-uppercase').documentation.anchors = @('docs/STANDARD_LIBRARY.md#no-such-heading') } }
        @{ Name = 'implementation claim of not-referenced that is false'; Expect = "implementation.interpreter claims 'not-referenced' but a linked contract member is now referenced"; Mutate = {
            param($d) (Get-Cap $d 'N-TcpConnect').implementation.interpreter.state = 'not-referenced' } }
        @{ Name = 'implementation claim of referenced that is false'; Expect = "implementation.browser claims 'referenced' but no linked contract member is referenced"; Mutate = {
            param($d) (Get-Cap $d 'N-TcpConnect').implementation.browser.state = 'referenced' } }
        @{ Name = 'contract member left unaccounted for'; Expect = "NodeKind 'TcpConnect' is not linked from any manifest capability"; Mutate = {
            param($d) $d.capabilities = @($d.capabilities | Where-Object { $_.id -ne 'N-TcpConnect' }) } }
        @{ Name = 'reachability field absent instead of null'; Expect = 'productionReachability.reachable is missing'; Mutate = {
            param($d) (Get-Cap $d 'N-TcpConnect').productionReachability.PSObject.Properties.Remove('reachable') } }
        @{ Name = 'event question without a decision field'; Expect = "event-contract question EV3 has no 'decision' field"; Mutate = {
            param($d) (@($d.eventContract.questions | Where-Object { $_.id -eq 'EV3' })[0]).PSObject.Properties.Remove('decision') } }
    )

    foreach ($case in $cases) {
        $caseName = $case.Name
        $caseExpect = $case.Expect
        $caseMutate = $case.Mutate
        Test-Otter "rejects: $caseName" ({
            $path = New-BrokenManifest ($caseName -replace '[^a-z]+', '-') $caseMutate
            $r = Invoke-Auditor -ManifestPath $path
            Assert-AreEqual -Expected 1 -Actual $r.ExitCode
            Assert-True ($r.Text.Contains($caseExpect)) "expected the message '$caseExpect'; got: $($r.Text)"
        }.GetNewClosure())
    }

    Test-Otter 'the auditor never modifies the manifest it reads' {
        $before = [System.IO.File]::ReadAllText($script:RealManifest)
        [void](Invoke-Auditor -ManifestPath $script:RealManifest)
        $after = [System.IO.File]::ReadAllText($script:RealManifest)
        Assert-True ($before -eq $after) 'manifest changed'
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
