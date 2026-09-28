# CertificationRunner.Tests.ps1
#
# Proves the release invariant enforced by tools/Invoke-OtterReleaseCertification.ps1:
#
#     clean checkout -> run the certification gates -> git status still clean
#
# The runner's final "repository-clean" check compares `git status` after the
# gates with the snapshot taken before them. These tests make sure it really
# fails a run when a gate dirties the checkout, and passes when it does not.
#
# How: each test builds a throwaway git repository in the temp folder holding a
# copy of the real runner plus a FAKE contract-structural gate
# (tools/Test-OtterContractCoverage.ps1) whose body the test chooses, then runs
# the runner with -Only contract-structural. The real repository is never
# touched, and the real gates are not run (they take minutes).

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'Release-certification runner: repository-clean check' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:Runner = Join-Path $script:RepoRoot 'tools/Invoke-OtterReleaseCertification.ps1'
$script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('otter_certrunner_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $script:Tmp -Force | Out-Null

# Runs git inside the throwaway repository; identity is passed per call so the
# test does not depend on (or change) the machine's git configuration.
function Invoke-TestGit {
    param([string]$Repo, [string[]]$GitArgs)
    $out = & git -C $Repo -c user.name=otter-test -c user.email=otter-test@example.invalid -c core.autocrlf=false @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $out" }
    return $out
}

# Builds a committed, clean repository whose contract-structural gate runs
# $GateBody, and returns its path.
function New-CertRepo {
    param([string]$Name, [string]$GateBody)
    $repo = Join-Path $script:Tmp $Name
    New-Item -ItemType Directory -Path (Join-Path $repo 'tools') -Force | Out-Null
    Copy-Item -LiteralPath $script:Runner -Destination (Join-Path $repo 'tools/Invoke-OtterReleaseCertification.ps1')
    [System.IO.File]::WriteAllText((Join-Path $repo 'tools/Test-OtterContractCoverage.ps1'), "$GateBody`nexit 0`n")
    [System.IO.File]::WriteAllText((Join-Path $repo 'tracked.txt'), "original`n")
    [System.IO.File]::WriteAllText((Join-Path $repo '.gitignore'), "ignored/`n")
    [void](Invoke-TestGit $repo @('init', '-q'))
    [void](Invoke-TestGit $repo @('add', '-A'))
    [void](Invoke-TestGit $repo @('commit', '-q', '-m', 'fixture'))
    return $repo
}

# Runs the copied runner on one gate and returns its exit code and record.
function Invoke-CertRunner {
    param([string]$Repo)
    $out = Join-Path $script:Tmp ((Split-Path -Leaf $Repo) + '-record')
    $sha = ([string](Invoke-TestGit $Repo @('rev-parse', 'HEAD'))).Trim()
    $hostExe = (Get-Process -Id $PID).Path
    $text = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tools/Invoke-OtterReleaseCertification.ps1') -Only contract-structural -CandidateSha $sha -OutputDirectory $out 2>&1
    $exit = $LASTEXITCODE
    $record = [System.IO.File]::ReadAllText((Join-Path $out 'certification.json')) | ConvertFrom-Json
    return [pscustomobject]@{ ExitCode = $exit; Record = $record; Text = (($text | ForEach-Object { $_.ToString() }) -join "`n") }
}

function Get-CleanGate { param($Record) @($Record.gates | Where-Object { $_.gate -eq 'repository-clean' })[0] }

try {
    Test-Otter 'passes a gate that leaves the checkout untouched' {
        $repo = New-CertRepo 'untouched' '# does nothing'
        $r = Invoke-CertRunner $repo
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-AreEqual -Expected 'release-certification' -Actual $r.Record.kind
        Assert-True ((Get-CleanGate $r.Record).passed) "repository-clean should pass: $($r.Text)"
        Assert-True ($r.Record.cleanAfterGates) 'cleanAfterGates should be true'
    }

    Test-Otter 'fails a gate that rewrites a tracked file' {
        $repo = New-CertRepo 'rewrites' "[System.IO.File]::WriteAllText((Join-Path `$PSScriptRoot '../tracked.txt'), 'rewritten')"
        $r = Invoke-CertRunner $repo
        Assert-AreEqual -Expected 1 -Actual $r.ExitCode
        Assert-True (-not (Get-CleanGate $r.Record).passed) 'repository-clean should fail'
        Assert-True (-not $r.Record.allGatesPassed) 'allGatesPassed should be false'
        Assert-True (@($r.Record.pathsChangedByGates | Where-Object { $_ -match 'tracked\.txt' }).Count -eq 1) "expected tracked.txt to be reported; got: $($r.Record.pathsChangedByGates -join ', ')"
    }

    Test-Otter 'fails a gate that leaves an untracked file behind' {
        $repo = New-CertRepo 'leaves-file' "[System.IO.File]::WriteAllText((Join-Path `$PSScriptRoot '../leftover.tmp'), 'x')"
        $r = Invoke-CertRunner $repo
        Assert-AreEqual -Expected 1 -Actual $r.ExitCode
        Assert-True (@($r.Record.pathsChangedByGates | Where-Object { $_ -match 'leftover\.tmp' }).Count -eq 1) "expected leftover.tmp to be reported; got: $($r.Record.pathsChangedByGates -join ', ')"
    }

    Test-Otter 'ignores files a gate writes to git-ignored paths' {
        $body = "New-Item -ItemType Directory -Path (Join-Path `$PSScriptRoot '../ignored') -Force | Out-Null; [System.IO.File]::WriteAllText((Join-Path `$PSScriptRoot '../ignored/scratch.txt'), 'x')"
        $repo = New-CertRepo 'ignored' $body
        $r = Invoke-CertRunner $repo
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-True ((Get-CleanGate $r.Record).passed) "repository-clean should pass: $($r.Text)"
    }
}
finally {
    Remove-Item -LiteralPath $script:Tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-OtterTests
