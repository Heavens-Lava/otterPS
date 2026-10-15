<#
.SYNOPSIS
Runs every Otter code sample in the documentation the way a reader runs it,
so the website and guides never teach code that no longer works.

.DESCRIPTION
Two places, each through the entry point its readers use:

  - The website (otter-docs/pages/*.ot). The site is built from this checkout
    into a temporary folder and every Run button is pressed in headless
    Chromium (tools/documentation-samples-browser.mjs), exactly as a reader
    presses it. As on the site, a sample runs after the samples above it on
    its page, so a sample may use a name an earlier one set up. Needs Node and
    playwright-core (set OTTER_PLAYWRIGHT_CORE to its folder).

  - README.md and TOUR.md, read by people typing code into `otter`. Each
    ```otter block goes through `otter check` and `otter run`, together with
    the blocks before it in the same file that ran, the same story rule as the
    website. Blocks that open a window, use the network, run on a timer, act
    on the computer (clipboard, registry, credentials, notifications,
    printing, programs) or need a real console are checked, not run, and the
    report says why. Each runs in its own folder holding Pictures, Documents
    and Downloads folders and a photo.jpg, which the file samples use; every
    question gets the answer 29.

Some samples show an error on purpose; tools/documentation-samples.json lists
them under "expectedErrors" with the reason. A sample that uses another file
the page shows (use "helpers.ot") is listed under "companionFiles", naming the
sample that holds that file. A listed sample passes only if it
still stops with an error, and a sample that is not listed fails if it stops
with one.

Exit code 0 when no sample failed, 1 otherwise. The report is written as
Markdown to -ReportPath.

.EXAMPLE
powershell -NoProfile -File tools\Test-OtterDocumentationSamples.ps1 -ReportPath docs-samples.md
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$ReportPath = '',
    [int]$TimeoutSeconds = 30,
    [switch]$SkipWebsite
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 has no $PSScriptRoot while parameter defaults run.
if (-not $RepositoryRoot) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
if (-not $ReportPath) { $ReportPath = Join-Path ([System.IO.Path]::GetTempPath()) 'otter-documentation-samples.md' }
$otterPs1 = Join-Path $RepositoryRoot 'otter.ps1'
$hostExe = (Get-Process -Id $PID).Path
$settings = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'documentation-samples.json') -Raw | ConvertFrom-Json
$expectedErrors = @{}
foreach ($p in $settings.expectedErrors.PSObject.Properties) { $expectedErrors[$p.Name] = $p.Value }
# A sample that uses another file (use "helpers.ot") gets that file, taken
# from the sample on the same page that shows it.
$companionFiles = @{}
if ($settings.companionFiles) {
    foreach ($p in $settings.companionFiles.PSObject.Properties) {
        $files = @{}
        foreach ($f in $p.Value.PSObject.Properties) { $files[$f.Name] = $f.Value }
        $companionFiles[$p.Name] = $files
    }
}

$inputLines = ("29`n" * 20)

# README and TOUR blocks matching one of these are checked but not run.
$checkOnlyRules = @(
    @{ Pattern = '\bwindow\b|\bshow app\b|\bis a page\b'; Reason = 'opens a window or page' },
    @{ Pattern = 'https?://|\bhttp\b|\bconnect (securely )?to\b|\blisten (securely )?for\b|\bopen udp\b|\bwebsocket\b|\bdownload\b|\bsend email\b|\breceives (GET|POST|PUT|DELETE)\b'; Reason = 'uses the network or is a web server' },
    @{ Pattern = '\bevery \d+ (second|minute)|\bwatch (file|folder)\b|\bwait for\b|\bschedule\b'; Reason = 'runs on a timer or waits for events' },
    @{ Pattern = '\bclipboard\b|\bregistry\b|\bcredential\b|\bnotification\b|\bnotify\b|\bprint (file|document)\b|\bevent log\b|\brun command\b|\bstart process\b'; Reason = 'acts on the computer (clipboard, registry, credentials, notifications, printing or programs)' },
    @{ Pattern = '\bset cursor\b|\bclear (the )?screen\b|\bread key\b'; Reason = 'needs a real console window' }
)

function ConvertFrom-OtterStringLiteral {
    param([string]$Text)
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq '\' -and $i + 1 -lt $Text.Length) {
            $i++
            switch ($Text[$i]) {
                'n' { [void]$sb.Append("`n") }
                't' { [void]$sb.Append("`t") }
                default { [void]$sb.Append($Text[$i]) }
            }
        }
        else { [void]$sb.Append($c) }
    }
    return $sb.ToString()
}

function Invoke-OtterSampleCommand {
    param([string]$Command, [string]$Folder)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $hostExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$otterPs1`" $Command sample.ot"
    $psi.WorkingDirectory = $Folder
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    try { $process.StandardInput.Write($inputLines); $process.StandardInput.Close() } catch { }
    $finished = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $finished) { try { $process.Kill() } catch { } ; [void]$process.WaitForExit(5000) }
    return [pscustomobject]@{ ExitCode = $(if ($finished) { $process.ExitCode } else { -1 }); TimedOut = (-not $finished); Text = ($stdout.Result + $stderr.Result).Trim() }
}

$results = [System.Collections.Generic.List[object]]::new()
function Add-SampleResult {
    param([string]$Id, [string]$Where, [string]$Outcome, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Id = $Id; Where = $Where; Outcome = $Outcome; Detail = $Detail })
}

# Decides a sample's outcome from whether it stopped with an error.
function Resolve-SampleOutcome {
    param([string]$Id, [string]$Where, [bool]$Failed, [string]$Text)
    $expected = $expectedErrors[$Id]
    if (-not $Failed -and -not $expected) { Add-SampleResult -Id $Id -Where $Where -Outcome 'passed' }
    elseif ($Failed -and $expected) { Add-SampleResult -Id $Id -Where $Where -Outcome 'passed' -Detail "stops with an error on purpose: $expected" }
    elseif ($expected) { Add-SampleResult -Id $Id -Where $Where -Outcome 'FAILED' -Detail "listed as stopping with an error ($expected), but it did not: $Text" }
    else { Add-SampleResult -Id $Id -Where $Where -Outcome 'FAILED' -Detail $Text }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('otter-doc-samples-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # ---- The website: press every Run button --------------------------------
    $pagesRoot = Join-Path $RepositoryRoot 'otter-docs\pages'
    $slugs = @(Get-ChildItem -LiteralPath $pagesRoot -Filter '*.ot' | Where-Object { $_.Name -notlike '_*' } |
        Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match 'runnable true' } | ForEach-Object { $_.BaseName } | Sort-Object)
    $sourceLines = @{}; $pageSources = @{}; $pageOrder = @{}
    foreach ($slug in $slugs) {
        $n = 0
        $pageOrder[$slug] = [System.Collections.Generic.List[string]]::new()
        foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $pagesRoot "$slug.ot"))) {
            $n++
            if ($line -notmatch 'runnable true') { continue }
            if ($line -notmatch '^\s*(\w+) is a text with value "((?:[^"\\]|\\.)*)"') { throw "$slug.ot line ${n}: a runnable sample this tool cannot read." }
            $id = "$slug.ot:$($Matches[1])"
            $sourceLines[$id] = $n
            $pageSources[$id] = ConvertFrom-OtterStringLiteral -Text $Matches[2]
            $pageOrder[$slug].Add($id)
        }
    }
    if ($SkipWebsite) {
        Add-SampleResult -Id '(website)' -Where 'otter-docs/pages' -Outcome 'skipped' -Detail "-SkipWebsite: $($sourceLines.Count) website samples not tested"
    }
    elseif (-not $env:OTTER_PLAYWRIGHT_CORE -or -not (Test-Path -LiteralPath $env:OTTER_PLAYWRIGHT_CORE) -or -not (Get-Command node -ErrorAction SilentlyContinue)) {
        Add-SampleResult -Id '(website)' -Where 'otter-docs/pages' -Outcome 'FAILED' -Detail "the website samples need Node and playwright-core (set OTTER_PLAYWRIGHT_CORE); $($sourceLines.Count) samples not tested. Use -SkipWebsite to leave them out on purpose."
    }
    else {
        $site = Join-Path $work 'site'
        Write-Host "Building the website into $site ..."
        $build = & $hostExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepositoryRoot 'otter-docs\scripts\build-otter-pages.ps1') -OutputRoot $site 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Building the website failed: $($build -join ' / ')" }
        Write-Host "Pressing every Run button on $($slugs.Count) pages ..."
        $json = & node (Join-Path $PSScriptRoot 'documentation-samples-browser.mjs') $site @slugs
        if ($LASTEXITCODE -ne 0) { throw "The browser driver failed: $($json -join ' / ')" }
        $seen = @{}
        foreach ($r in (($json -join "`n") | ConvertFrom-Json)) {
            $id = "$($r.slug).ot:$($r.id)"
            $where = if ($sourceLines.ContainsKey($id)) { "otter-docs/pages/$($r.slug).ot line $($sourceLines[$id])" } else { "otter-docs/pages/$($r.slug).ot" }
            $seen[$id] = $true
            if (-not $r.finished) { Add-SampleResult -Id $id -Where $where -Outcome 'FAILED' -Detail "the Run button did not finish in 10 seconds: $($r.text)"; continue }
            Resolve-SampleOutcome -Id $id -Where $where -Failed ([bool]$r.error) -Text $r.text
        }
        # The site gives no Run button to a sample that cannot run honestly in
        # a browser (it asks a question, uses files, the network, the computer
        # or a window) - and also, silently, to one that does not compile. So
        # each of these goes through `otter check`: alone, then after the
        # samples above it on its page (it may use a name they set up).
        foreach ($id in ($sourceLines.Keys | Sort-Object)) {
            if ($seen.ContainsKey($id)) { continue }
            $slug = $id.Split(':')[0] -replace '\.ot$', ''
            $where = "otter-docs/pages/$slug.ot line $($sourceLines[$id])"
            $folder = Join-Path $work ('w' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
            New-Item -ItemType Directory -Path $folder | Out-Null
            $own = $pageSources[$id]
            [System.IO.File]::WriteAllText((Join-Path $folder 'sample.ot'), $own + "`n", [System.Text.UTF8Encoding]::new($false))
            if ($companionFiles.ContainsKey($id)) {
                foreach ($name in $companionFiles[$id].Keys) {
                    [System.IO.File]::WriteAllText((Join-Path $folder $name), $pageSources[$companionFiles[$id][$name]] + "`n", [System.Text.UTF8Encoding]::new($false))
                }
            }
            $check = Invoke-OtterSampleCommand -Command 'check' -Folder $folder
            if ($check.ExitCode -ne 0) {
                $before = @($pageOrder[$slug] | Where-Object { $sourceLines[$_] -lt $sourceLines[$id] } | ForEach-Object { $pageSources[$_] })
                [System.IO.File]::WriteAllText((Join-Path $folder 'sample.ot'), ((@($before) + @($own)) -join "`n`n") + "`n", [System.Text.UTF8Encoding]::new($false))
                $check = Invoke-OtterSampleCommand -Command 'check' -Folder $folder
            }
            if ($check.ExitCode -ne 0) { Resolve-SampleOutcome -Id $id -Where $where -Failed $true -Text "no Run button on the site, and otter check fails: $($check.Text)" }
            else { Add-SampleResult -Id $id -Where $where -Outcome 'checked' -Detail 'no Run button on the site (it needs the console, files, the network or a window); otter check passes' }
        }
    }

    # ---- README and TOUR: the console ---------------------------------------
    $index = 0
    foreach ($doc in @('README.md', 'TOUR.md')) {
        $lines = [System.IO.File]::ReadAllLines((Join-Path $RepositoryRoot $doc))
        $blocks = [System.Collections.Generic.List[object]]::new()
        $block = $null; $start = 0
        for ($i = 0; $i -lt $lines.Length; $i++) {
            if ($null -eq $block -and $lines[$i] -match '^```otter\s*$') { $block = [System.Collections.Generic.List[string]]::new(); $start = $i + 2; continue }
            if ($null -ne $block -and $lines[$i] -match '^```\s*$') {
                $blocks.Add([pscustomobject]@{ Id = "${doc}:$($blocks.Count + 1)"; Where = "$doc line $start"; Source = ($block -join "`n") })
                $block = $null; continue
            }
            if ($null -ne $block) { $block.Add($lines[$i]) }
        }
        $story = [System.Collections.Generic.List[string]]::new()   # the blocks above that ran
        foreach ($b in $blocks) {
            $index++
            $folder = Join-Path $work ('c' + $index)
            foreach ($sub in @('Pictures', 'Documents', 'Downloads')) {
                New-Item -ItemType Directory -Path (Join-Path $folder $sub) -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path $folder "$sub\notes.txt"), "sample`n")
            }
            [System.IO.File]::WriteAllBytes((Join-Path $folder 'photo.jpg'), [byte[]](255, 216, 255, 217))
            $program = (@($story) + @($b.Source)) -join "`n`n"
            [System.IO.File]::WriteAllText((Join-Path $folder 'sample.ot'), $program + "`n", [System.Text.UTF8Encoding]::new($false))
            $check = Invoke-OtterSampleCommand -Command 'check' -Folder $folder
            if ($check.ExitCode -ne 0) { Resolve-SampleOutcome -Id $b.Id -Where $b.Where -Failed $true -Text "otter check: $($check.Text)"; continue }
            $checkOnly = $null
            foreach ($rule in $checkOnlyRules) { if ($b.Source -match $rule.Pattern) { $checkOnly = $rule.Reason; break } }
            if ($checkOnly) { Add-SampleResult -Id $b.Id -Where $b.Where -Outcome 'checked' -Detail "checked, not run: $checkOnly"; continue }
            $run = Invoke-OtterSampleCommand -Command 'run' -Folder $folder
            if ($run.TimedOut) { Add-SampleResult -Id $b.Id -Where $b.Where -Outcome 'FAILED' -Detail "otter run did not finish in $TimeoutSeconds seconds"; continue }
            Resolve-SampleOutcome -Id $b.Id -Where $b.Where -Failed ($run.ExitCode -ne 0) -Text "otter run exited $($run.ExitCode): $($run.Text)"
            if ($run.ExitCode -eq 0) { $story.Add($b.Source) }
        }
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

$counts = @{}
foreach ($o in @('passed', 'checked', 'skipped', 'FAILED')) { $counts[$o] = @($results | Where-Object { $_.Outcome -eq $o }).Count }
$report = [System.Collections.Generic.List[string]]::new()
$report.Add('# Otter documentation samples')
$report.Add('')
$report.Add("$($results.Count) samples: $($counts['passed']) passed, $($counts['checked']) checked but not run, $($counts['skipped']) skipped, **$($counts['FAILED']) failed**.")
$report.Add('')
$report.Add('| Sample | Where | Result | Detail |')
$report.Add('|---|---|---|---|')
foreach ($r in ($results | Sort-Object @{ Expression = { if ($_.Outcome -eq 'FAILED') { 0 } else { 1 } } }, Id)) {
    $detail = ($r.Detail -replace '\r?\n', ' / ' -replace '\|', '\|')
    if ($detail.Length -gt 400) { $detail = $detail.Substring(0, 400) + '...' }
    $report.Add("| $($r.Id) | $($r.Where) | $($r.Outcome) | $detail |")
}
[System.IO.File]::WriteAllText($ReportPath, ($report -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))

Write-Host "$($results.Count) samples: $($counts['passed']) passed, $($counts['checked']) checked only, $($counts['skipped']) skipped, $($counts['FAILED']) failed. Report: $ReportPath"
foreach ($r in ($results | Where-Object { $_.Outcome -eq 'FAILED' })) { Write-Host "  FAILED $($r.Id) ($($r.Where))" -ForegroundColor Red }
if ($counts['FAILED'] -gt 0) { exit 1 }
exit 0
