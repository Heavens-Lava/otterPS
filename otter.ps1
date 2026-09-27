using module .\Otter.Contract.psm1
using module .\src\Otter.Runtime.psm1
using module .\src\Otter.Lexer.psm1
using module .\src\Otter.Parser.psm1
using module .\src\Otter.Database.psm1
using module .\src\Otter.Interpreter.psm1
using module .\src\Otter.Module.psm1
using module .\src\Otter.Project.psm1

# otter.ps1 - the Otter interpreter
# Author: Jeffrey Macy
#
#   otter                 -> the REPL (Read, Evaluate, Print, Loop)
#   otter hello.ot        -> run a script
#   otter hello.ot -DebugTokens -DebugAst   -> developer views
#
# Otter 0.1 ran each line through a chain of StartsWith checks. 0.2 runs a
# real pipeline, and this file is only the plumbing for it:
#
#   source text
#       |
#       v  ConvertTo-OtterTokens   (src/Otter.Lexer.psm1)
#   Token[]
#       |
#       v  ConvertTo-OtterAst      (src/Otter.Parser.psm1)
#   ProgramNode
#       |
#       v  Invoke-OtterProgram     (src/Otter.Interpreter.psm1)
#   output
#
# The `using module` lines above must come before everything except comments -
# that is a PowerShell rule, and it is also what makes the Token and Node
# classes the same types in every module here.

param(
    # The command ("web", "serve", "browse") or the .ot script to run. With no path at all, we start the REPL.
    [Parameter(Position = 0)]
    [string]$Path,

    # Target script file when a command like "web" or "serve" is used: otter web app.ot
    [Parameter(Position = 1)]
    [string]$Target,

    # Web options
    [switch]$Open,
    [switch]$NoOpen,
    [int]$Port = 0,

    # Developer views. These are for people working on Otter itself;
    # ordinary Otter output stays clean.
    [switch]$DebugTokens,
    [switch]$DebugAst,

    # Check that a program is well formed WITHOUT running it. Nothing is
    # printed, no file is touched, no program is launched. Used by the
    # documentation build to prove every published example still parses,
    # and useful to any editor that wants to check a file as it is typed.
    [switch]$ParseOnly,

    # Show the underlying PowerShell error instead of a friendly Otter one.
    [switch]$DebugErrors,

    # otter debug <file.ot> -Breakpoints "5,12"  - comma-separated 1-based
    # Otter source line numbers. First-slice debugger: see
    # src/Otter.Debugger.psm1.
    [string]$Breakpoints,

    # D57: PowerShell's own argument binder turns `--version`/`--help` into
    # `-version`/`-help` before matching parameter names, so these need to
    # be real switches (matched via alias) rather than caught as $Path text.
    [Parameter()][Alias('version')][switch]$VersionFlag,
    [Parameter()][Alias('help')][switch]$HelpFlag,

    # Trailing arguments passed to the Otter program (D94 / Batch 1)
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'

# Otter source files are read as UTF-8 explicitly (see Invoke-OtterFile
# below), but without this, `say`/output written through the CONSOLE still
# goes out re-encoded as whatever legacy OEM code page the host happens to
# be running (437 on a stock US Windows install) - any character outside
# that code page (CJK, emoji, most accented Latin) silently becomes "?" on
# the way out, and the same corruption hits a parent process capturing
# otter.ps1's stdout (e.g. `& powershell ... otter.ps1 file.ot`), since a
# child's OutputEncoding governs how it encodes bytes onto its own stdout
# handle regardless of who is on the other end. Forcing real UTF-8 here
# makes Unicode `say` output correct both for a real terminal and for any
# caller capturing this process's output.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # Some hosts (a redirected/non-interactive stdout, certain CI runners)
    # refuse to let a script change console encoding - not fatal, since
    # ASCII-only output is unaffected either way.
}

# D57: ONE authoritative version source - the VERSION file at the repo root,
# read here and nowhere else. --version and the REPL banner both read
# $OtterVersion, so there is no second place that could drift out of sync.
# Do not report 1.0.0 until the release version is intentionally frozen in
# that file - it is not, yet.
$versionFile = Join-Path $PSScriptRoot 'VERSION'
$OtterVersionNumber = if (Test-Path -LiteralPath $versionFile) {
    (Get-Content -LiteralPath $versionFile -Raw).Trim()
} else {
    '0.0.0-unknown'
}
$OtterVersion = "Otter $OtterVersionNumber"

# D94 CLI arguments, corrected: declaring `[Parameter(ValueFromRemainingArguments
# = $true)]` above (needed to capture arbitrary trailing arguments for the
# Otter PROGRAM) makes this an "advanced" script, which makes PowerShell
# silently add its own common parameters (-Verbose, -Debug, -ErrorAction,
# -WarningAction, -InformationAction, -ErrorVariable, -WarningVariable,
# -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable) to it.
# Confirmed by direct testing: `otter run script.ot -Verbose` silently
# vanishes from $Arguments entirely (intercepted as PowerShell's own
# -Verbose switch instead), and `otter run script.ot -OutVariable foo`
# swallows BOTH tokens, leaving the Otter program with zero arguments and
# no error - exactly the "silently narrows/corrupts a real capability"
# failure mode this project treats as a bug, not a footnote. None of these
# common parameters have ever done anything for otter.ps1 itself (nothing
# here reads $VerbosePreference, Write-Verbose, etc.), so recovering them
# for the Otter program costs nothing. Fixed by bypassing the parameter
# binder for the trailing-arguments slice entirely: recompute it from the
# real, raw command line (which is never touched by parameter binding) and
# strip out only otter.ps1's own known flags ourselves.
$script:OtterOwnSwitchFlags = @('-DebugTokens', '-DebugAst', '-ParseOnly', '-DebugErrors', '-Open', '-NoOpen', '-version', '-help')
$script:OtterOwnValueFlags = @('-Breakpoints', '-Port')

function Get-OtterRawTrailingArguments {
    param([int]$SkipCount)

    $all = [Environment]::GetCommandLineArgs()
    $scriptIndex = -1
    for ($i = 0; $i -lt $all.Count; $i++) {
        if ($all[$i] -ieq '-File' -and ($i + 1) -lt $all.Count) {
            $scriptIndex = $i + 1
            break
        }
    }
    # Not a `-File` invocation (dot-sourced, -Command, ISE, ...) - no reliable
    # raw command line to recover from. Returning $null (not @()) tells the
    # caller to fall back to whatever PowerShell's own binder produced,
    # rather than silently truncating real arguments to nothing.
    if ($scriptIndex -lt 0) { return $null }

    # Deliberately NOT using PowerShell's range-slice operator (`..`) here.
    # Reproduced directly and repeatedly: in this exact advanced-script
    # context (this param block, with -Debug actually bound), a range slice
    # that resolves to exactly one element - even wrapped in @() - comes
    # back corrupted to just that element's first CHARACTER instead of the
    # element itself (`otter run file.ot -Debug` turned the single
    # remaining token "-Debug" into "-"). Root cause not fully pinned down
    # after extensive isolation (survives removing @(), using two distinct
    # variables instead of self-reassignment, and stripping comments - only
    # avoiding `..` slicing entirely made it go away in every case tried).
    # A plain index copy-loop sidesteps the whole family of quirks.
    $indexToken = $scriptIndex + 1
    $result = [System.Collections.Generic.List[string]]::new()
    $skipRemaining = $SkipCount
    while ($indexToken -lt $all.Count) {
        $token = $all[$indexToken]
        $indexToken++
        if ($skipRemaining -gt 0) { $skipRemaining--; continue }
        if ($script:OtterOwnSwitchFlags -icontains $token) { continue }
        if ($script:OtterOwnValueFlags -icontains $token) { $indexToken++; continue }
        $result.Add($token)
    }
    return ,$result.ToArray()
}

# D57: deliberate, documented exit codes - never PowerShell's accidental
# default. A CLI script or CI step can rely on these to tell why otter
# failed, not just that it did.
$script:ExitSuccess = 0
$script:ExitUsageError = 1     # bad CLI invocation: unknown command, missing
                                # argument, file not found, wrong extension
$script:ExitCheckError = 2     # the source itself does not lex/parse
$script:ExitRuntimeError = 3   # a well-formed program failed while running


# ===============================================================
# ERROR REPORTING (D14)
# ===============================================================
#
# A raw PowerShell exception must never reach someone who is just trying to
# learn to program. Everything funnels through here.

function Show-OtterFailure {
    param(
        [Parameter(Mandatory)]$ErrorRecord,
        [switch]$Short
    )

    $exception = $ErrorRecord.Exception

    if ($exception -is [OtterError]) {
        if ($Short) {
            Write-Host $exception.Format() -ForegroundColor Red
        }
        else {
            Write-Host ''
            Write-Host $exception.FormatDetailed() -ForegroundColor Red
            Write-Host ''
        }
        return
    }

    # Not an Otter error - that means Otter itself has a bug. Say so honestly
    # rather than blaming the user's program.
    Write-Host ''
    Write-Host 'Otter hit a problem inside itself, which means this is a bug in Otter.' -ForegroundColor Red
    Write-Host "  $($exception.Message)" -ForegroundColor DarkGray

    if ($DebugErrors) {
        Write-Host ''
        Write-Host $ErrorRecord.ScriptStackTrace -ForegroundColor DarkGray
    }
    else {
        Write-Host '  Run again with -DebugErrors to see where.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

# Module resolution (src/Otter.Module.psm1) splices imported files' text
# directly into the combined source before lexing, so any diagnostic's
# `.Line` is a position in that COMBINED text, not the file a user actually
# wrote. Without this, every error inside an imported module would quote
# the wrong line number and the wrong source text (whatever happens to sit
# at that line in the spliced-together result). Translates the line back
# through the resolver's own source map and, for anything outside the root
# script itself, names which imported file it actually came from - the
# closest this can get to real per-file diagnostics without a FilePath
# field on the frozen OtterError contract class.
function Get-OtterRemappedError {
    param(
        [Parameter(Mandatory)]$ErrorRecord,
        [Parameter(Mandatory)][OtterResolvedProgram]$ResolvedProgram,
        [Parameter(Mandatory)][string]$RootFile
    )

    $exception = $ErrorRecord.Exception
    if ($exception -isnot [OtterError]) {
        return $ErrorRecord
    }

    $remapped = ConvertTo-OtterRemappedDiagnostics -Error $exception -ResolvedProgram $ResolvedProgram -RootFile $RootFile
    return [System.Management.Automation.ErrorRecord]::new(
        $remapped, $ErrorRecord.FullyQualifiedErrorId, $ErrorRecord.CategoryInfo.Category, $ErrorRecord.TargetObject)
}


# ===============================================================
# THE PIPELINE
# ===============================================================

# D57: which stage a failure happened in, so the caller can pick the right
# exit code (check error vs. runtime error) without wrapping every call site
# in its own try/catch pair.
$script:LastFailureStage = $null

function Invoke-OtterSource {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Source,
        [Parameter(Mandatory)][OtterEnvironment]$Environment,

        # D57: `otter check` passes this explicitly so it does not depend on
        # the -ParseOnly developer switch. Either one stops after lex+parse.
        [switch]$CheckOnly
    )

    # Split once so runtime errors can quote the line they happened on.
    $sourceLines = $Source -split "`r?`n"

    try {
        $tokens = ConvertTo-OtterTokens -Source $Source

        if ($DebugTokens) {
            Write-Host '--- tokens ---' -ForegroundColor DarkCyan
            foreach ($token in $tokens) { Write-Host "  $token" -ForegroundColor DarkGray }
            Write-Host ''
        }

        $program = ConvertTo-OtterAst -Tokens $tokens
    }
    catch {
        # D57: tag this as a check-stage failure so the caller can map it to
        # the check exit code instead of the runtime one.
        $script:LastFailureStage = 'check'
        throw
    }

    if ($ParseOnly -or $CheckOnly) {
        # Reaching here means the lexer and parser both accepted the source.
        return
    }

    if ($DebugAst) {
        Write-Host '--- ast ---' -ForegroundColor DarkCyan
        Show-OtterAst -Node $program -Depth 1
        Write-Host ''
    }

    Invoke-OtterProgram -Program $program -Environment $Environment -SourceLines $sourceLines
}

# A rough tree view of the AST, for -DebugAst. Deliberately simple: it walks
# whatever child nodes a node happens to have rather than knowing every type.
function Show-OtterAst {
    param([object]$Node, [int]$Depth = 0)

    if ($null -eq $Node) { return }
    $pad = '  ' * $Depth

    if ($Node -is [Node]) {
        $label = $Node.Kind.ToString()
        foreach ($extra in @('Name', 'Target', 'VariableName', 'ResultTarget')) {
            $value = $Node.PSObject.Properties[$extra]
            if ($value -and $value.Value) { $label += " $($value.Value)"; break }
        }
        if ($Node.Kind -eq [NodeKind]::Literal) {
            $label += " = $($Node.Value)"
        }
        Write-Host "$pad$label" -ForegroundColor DarkGray

        foreach ($property in $Node.PSObject.Properties) {
            if ($property.Name -in @('Kind', 'Line', 'Name', 'Value', 'Target', 'VariableName', 'ResultTarget')) { continue }
            Show-OtterAst -Node $property.Value -Depth ($Depth + 1)
        }
        return
    }

    if ($Node -is [IfBranch]) {
        Write-Host "$pad" + 'branch' -ForegroundColor DarkGray
        Show-OtterAst -Node $Node.Condition -Depth ($Depth + 1)
        foreach ($statement in $Node.Body) { Show-OtterAst -Node $statement -Depth ($Depth + 1) }
        return
    }

    if ($Node -is [System.Array]) {
        foreach ($item in $Node) { Show-OtterAst -Node $item -Depth $Depth }
    }
}


# ===============================================================
# FILE MODE
# ===============================================================

function Invoke-OtterFile {
    param(
        [string]$ScriptPath,

        # D57: `otter check` validates source without executing it or
        # opening any UI. Same pipeline, it just stops after the parser.
        [switch]$CheckOnly,

        # otter debug: a debug session (src/Otter.Debugger.psm1) was already
        # wired into the interpreter before this call. The only thing this
        # flag adds is emitting the "finished" protocol event once the
        # program stops, however it stops - normally or on error - so
        # Studio can always tell "still running/paused" apart from "done".
        [switch]$DebugSession,

        # otter profile: src/Otter.Profiler.psm1 was already wired into the
        # interpreter. This flag prints its report once the program stops,
        # however it stops - normally or on error.
        [switch]$ProfileSession,

        [string[]]$Arguments = @(),
        [string]$DisplayTarget = $null
    )

    if (-not $ScriptPath.ToLowerInvariant().EndsWith('.ot')) {
        Write-Host "Otter: `"$ScriptPath`" is not an Otter file - expected a .ot file." -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }

    $resolved = Resolve-Path -LiteralPath $ScriptPath -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Write-Host "Otter: I cannot find a file called `"$ScriptPath`"." -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }

    # D94-follow-on (module resolution, console targets): `use "file.ot"`
    # is resolved at the SOURCE TEXT level, before anything is lexed -
    # exactly the approach docs/OTTER_1_0_MODULE_STATUS.md already
    # recommended, and exactly what src/Otter.Module.psm1 already
    # implements (it just was never called from a production entry point).
    # A file with no `use` lines resolves to itself unchanged, so this is
    # always safe to run, not just when imports are present.
    $script:LastFailureStage = $null
    $resolvedProgram = $null
    try {
        $resolvedProgram = Resolve-OtterModuleSource -FilePath $resolved.Path
    }
    catch {
        $script:LastFailureStage = 'check'
        if ($DebugSession) { Complete-OtterDebugSession }
        Show-OtterFailure -ErrorRecord $_
        [Environment]::Exit($script:ExitCheckError)
    }
    $source = $resolvedProgram.CombinedSource
    if ($null -eq $source) { $source = '' }

    # D111: secrets are scoped to this program's identity.
    Set-OtterApplicationId -Path $resolved.Path

    $environment = New-OtterEnvironment -Arguments $Arguments

    try {
        Invoke-OtterSource -Source $source -Environment $environment -CheckOnly:$CheckOnly
    }
    catch {
        if ($DebugSession) { Complete-OtterDebugSession }
        if ($ProfileSession) { Write-OtterProfileReport -SourceLines ($source -split "`r?`n") }
        # Remap the combined-source line the error actually fired on back to
        # the real imported file it came from - otherwise every diagnostic
        # inside an imported module quotes the WRONG line (a position in the
        # spliced-together text no one ever sees) and the wrong source text.
        $remapped = Get-OtterRemappedError -ErrorRecord $_ -ResolvedProgram $resolvedProgram -RootFile $resolved.Path
        Show-OtterFailure -ErrorRecord $remapped
        if ($script:LastFailureStage -eq 'check') {
            [Environment]::Exit($script:ExitCheckError)
        }
        [Environment]::Exit($script:ExitRuntimeError)
    }

    if ($DebugSession) { Complete-OtterDebugSession }
    if ($ProfileSession) { Write-OtterProfileReport -SourceLines ($source -split "`r?`n") }

    if ($CheckOnly) {
        $msgTarget = if ($DisplayTarget) { $DisplayTarget } else { $ScriptPath }
        Write-Host "Otter: $msgTarget is valid." -ForegroundColor Green
    }
    elseif ($ParseOnly) {
        # Legacy developer flag: -ParseOnly on any run still just checks.
        Write-Host "ok: $ScriptPath"
    }
    exit $script:ExitSuccess
}


# ===============================================================
# REPL
# ===============================================================
#
# One environment lives for the whole session, so variables you set on one
# line are still there on the next.
#
# Blocks need more than one line, so when a line opens a block the prompt
# changes to "..... " and keeps collecting until you enter a blank line.

$script:BlockOpeners = @('if', 'while', 'repeat', 'count', 'for', 'to', 'otherwise')

function Test-OtterOpensBlock {
    param([string]$Line)

    $trimmed = $Line.Trim()
    if ($trimmed -eq '') { return $false }

    $firstWord = ($trimmed -split '\s+')[0]
    if ($script:BlockOpeners -contains $firstWord) { return $true }

    # "games are" starts a list that runs over several lines.
    if ($trimmed -match '\bare$') { return $true }

    return $false
}

function Start-OtterRepl {

    Write-Host $OtterVersion
    Write-Host 'Readable like English. Precise like code.'
    Write-Host ''

    $environment = New-OtterEnvironment

    while ($true) {
        Write-Host 'otter> ' -NoNewline
        $line = Read-Host

        if ($null -eq $line) { break }
        if ($line.Trim() -eq 'exit') { break }
        if ($line.Trim() -eq 'reset') {
            $environment = New-OtterEnvironment
            Write-Host 'Otter: session reset - all variables and functions cleared.' -ForegroundColor DarkGray
            continue
        }
        if ($line.Trim() -eq '') { continue }

        $buffer = [System.Collections.Generic.List[string]]::new()
        $buffer.Add($line)

        # Keep collecting while we are inside a block.
        if (Test-OtterOpensBlock -Line $line) {
            while ($true) {
                Write-Host '..... ' -NoNewline
                $more = Read-Host
                if ($null -eq $more -or $more.Trim() -eq '') { break }
                $buffer.Add($more)
            }
        }

        $source = ($buffer -join "`n")

        try {
            Invoke-OtterSource -Source $source -Environment $environment
        }
        catch {
            # Short form in the REPL: you can see your own line right above.
            Show-OtterFailure -ErrorRecord $_ -Short
        }
    }
}


# ===============================================================
# MAIN
# ===============================================================

function Show-OtterHelp {
    Write-Host $OtterVersion
    Write-Host ''
    Write-Host 'Usage:'
    Write-Host '  otter <file.ot>        Run an Otter program (shortest form)'
    Write-Host '  otter run <file.ot>    Run an Otter program or project'
    Write-Host '  otter check <file.ot>  Validate a program or project without running it'
    Write-Host '  otter build [target]   Build an Otter project into its output directory (dist/)'
    Write-Host '        --target electron  Build the project as an Electron desktop application'
    Write-Host '  otter publish [target] Publish an Otter project into a distributable archive (publish/)'
    Write-Host '  otter new <type> <name> Create a new Otter project (console, desktop, web, automation, game)'
    Write-Host '  otter test [target]    Run tests in an Otter project or test file'
    Write-Host '  otter profile <file.ot> Run a program and report which functions and lines took the time'
    Write-Host '  otter web <file.ot>    Compile an Otter web application to HTML/JS'
    Write-Host '  otter desktop <file.ot> Run an Otter Desktop app with system bridge'
    Write-Host '        --electron [--output <folder>]  Write it as an Electron application instead'
    Write-Host '  otter studio           Launch Otter Studio IDE & UI Designer'
    Write-Host '  otter help             Show this help'
    Write-Host '  otter --help           Show this help'
    Write-Host '  otter --version        Show the Otter version'
    Write-Host '  otter                  Start the interactive REPL'
    Write-Host ''
}

# D57: unknown-command / missing-argument detection lives here, before any
# subcommand branch runs, so every usage error goes through the same path.
if ($VersionFlag -or $Path -eq '--version') {
    Write-Host $OtterVersion
    exit $script:ExitSuccess
}

if ($HelpFlag -or $Path -eq 'help' -or $Path -eq '--help') {
    Show-OtterHelp
    exit $script:ExitSuccess
}

if ($Path -eq 'new') {
    $supportedArchetypes = @('console', 'desktop', 'web', 'automation', 'game')
    if (-not $Target) {
        Write-Host 'Usage: otter new <archetype> <name>' -ForegroundColor Red
        Write-Host 'Supported archetypes: console, desktop, web, automation, game.' -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }

    if ($supportedArchetypes -notcontains $Target.ToLowerInvariant()) {
        Write-Host "Otter: Unknown archetype `"$Target`"." -ForegroundColor Red
        Write-Host 'Usage: otter new <archetype> <name>' -ForegroundColor Red
        Write-Host 'Supported archetypes: console, desktop, web, automation, game.' -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }

    $archetype = $Target.ToLowerInvariant()
    $rawArgs = Get-OtterRawTrailingArguments -SkipCount 2
    $projectName = if ($rawArgs -and $rawArgs.Count -gt 0) { $rawArgs[0] } elseif ($Arguments -and $Arguments.Count -gt 0) { $Arguments[0] } else { $null }

    if (-not $projectName) {
        Write-Host "Usage: otter new $archetype <name>" -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }

    try {
        $createdProject = New-OtterProject -Archetype $archetype -Name $projectName -Path (Get-Location).Path
        Write-Host "Created new Otter $archetype project in `"$($createdProject.RootDirectory)`"." -ForegroundColor Green
        Write-Host ''
        Write-Host 'To get started:'
        Write-Host "  cd $projectName"
        Write-Host '  otter check .'
        Write-Host '  otter test .'
        Write-Host '  otter run .'
        Write-Host ''
        [Environment]::Exit($script:ExitSuccess)
    }
    catch [OtterError] {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit($script:ExitUsageError)
    }
    catch {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit($script:ExitUsageError)
    }
}

if ($Path -eq 'test') {
    $testTarget = if ($Target) { $Target } else { '.' }
    try {
        $testCode = Invoke-OtterProjectTests -Target $testTarget -OtterPs1Path $PSCommandPath
        [Environment]::Exit($testCode)
    }
    catch [OtterError] {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit($script:ExitUsageError)
    }
    catch {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit($script:ExitUsageError)
    }
}

if ($Path -eq 'build') {
    # `--target electron` collides with this script's own -Target parameter
    # (PowerShell binds `--target x` as `-Target x`, dropping the path), so
    # the build arguments are read back from the raw command line.
    $buildRaw = Get-OtterRawTrailingArguments -SkipCount 1
    $buildTarget = $null
    $buildTargetOverride = $null
    if ($null -ne $buildRaw) {
        for ($i = 0; $i -lt $buildRaw.Count; $i++) {
            $token = [string]$buildRaw[$i]
            if ($token -in @('--target', '-target', '-Target') -and ($i + 1) -lt $buildRaw.Count) {
                $buildTargetOverride = [string]$buildRaw[$i + 1]
                $i++
            } elseif (-not $buildTarget -and -not $token.StartsWith('-')) {
                $buildTarget = $token
            }
        }
    } elseif ($Target) {
        $buildTarget = $Target
    }
    if (-not $buildTarget) { $buildTarget = '.' }
    try {
        $exitCode = Invoke-OtterProjectBuild -Target $buildTarget -TargetOverride $buildTargetOverride
        [Environment]::Exit($exitCode)
    }
    catch [OtterError] {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit($script:ExitUsageError)
    }
    catch {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit($script:ExitUsageError)
    }
}

if ($Path -eq 'publish') {
    $publishTarget = if ($Target -and -not $Target.StartsWith('-')) { $Target } else { '.' }
    $rawArgs = Get-OtterRawTrailingArguments -SkipCount 2
    $outputDir = $null
    if ($rawArgs) {
        for ($i = 0; $i -lt $rawArgs.Count; $i++) {
            if ($rawArgs[$i] -in @('--output', '-Output') -and ($i + 1) -lt $rawArgs.Count) {
                $outputDir = $rawArgs[$i + 1]
                break
            }
        }
    }
    if (-not $outputDir -and $Target -in @('--output', '-Output')) {
        $outputDir = if ($Arguments -and $Arguments.Count -gt 0) { $Arguments[0] } else { $null }
    }
    try {
        $exitCode = Invoke-OtterProjectPublish -Target $publishTarget -OutputDir $outputDir
        [Environment]::Exit($exitCode)
    }
    catch [OtterError] {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit($script:ExitUsageError)
    }
    catch {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ''
        [Environment]::Exit($script:ExitUsageError)
    }
}

if ($Path -eq 'run' -or $Path -eq 'check') {
    if (-not $Target) {
        Write-Host "Usage: otter $Path <file.ot>" -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }
    # SkipCount 2: raw trailing tokens are [run|check, <target>, ...program args]
    $rawArgs = Get-OtterRawTrailingArguments -SkipCount 2
    $effectiveArguments = if ($null -ne $rawArgs) { $rawArgs } else { $Arguments }

    # D118B: Project vs script resolution
    $isOtFile = $Target.ToLowerInvariant().EndsWith('.ot')
    if (-not $isOtFile) {
        $projManifest = Find-OtterProjectManifest -Path $Target
        if ($projManifest) {
            $project = $null
            try {
                $project = Get-OtterProject -Path $Target
            } catch [OtterError] {
                Write-Host ''
                Write-Host $_.Exception.Message -ForegroundColor Red
                Write-Host ''
                [Environment]::Exit($script:ExitCheckError)
            }
            Invoke-OtterFile -ScriptPath $project.ResolvedEntryPoint -CheckOnly:($Path -eq 'check') -Arguments $effectiveArguments -DisplayTarget $Target
        }

        # If not a manifest, check if Target is an existing directory or '.' with no manifest
        $resolvedDir = Resolve-Path -LiteralPath $Target -ErrorAction SilentlyContinue
        if (($resolvedDir -and (Test-Path -LiteralPath $resolvedDir.Path -PathType Container)) -or $Target -eq '.') {
            Write-Host "Otter: I cannot find an otter.json manifest in `"$Target`"." -ForegroundColor Red
            [Environment]::Exit($script:ExitUsageError)
        }

        # Otherwise not a valid .ot file
        Write-Host "Otter: `"$Target`" is not an Otter file - expected a .ot file." -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }

    Invoke-OtterFile -ScriptPath $Target -CheckOnly:($Path -eq 'check') -Arguments $effectiveArguments
    # Invoke-OtterFile always exits itself.
}

if ($Path -eq 'profile') {
    if (-not $Target) {
        Write-Host 'Usage: otter profile <file.ot>' -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }
    Import-Module (Join-Path $PSScriptRoot 'src\Otter.Profiler.psm1') -Force
    Start-OtterProfile
    # SkipCount 2: raw trailing tokens are [profile, <target>, ...program args]
    $rawArgs = Get-OtterRawTrailingArguments -SkipCount 2
    $effectiveArguments = if ($null -ne $rawArgs) { $rawArgs } else { $Arguments }
    Invoke-OtterFile -ScriptPath $Target -ProfileSession -Arguments $effectiveArguments
    # Invoke-OtterFile always exits itself.
}

if ($Path -eq 'debug') {
    if (-not $Target) {
        Write-Host 'Usage: otter debug <file.ot> -Breakpoints "5,12"' -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }
    $breakpointLines = @()
    if ($Breakpoints) {
        $breakpointLines = @($Breakpoints -split ',' | ForEach-Object { [int]($_.Trim()) })
    }
    Import-Module (Join-Path $PSScriptRoot 'src\Otter.Debugger.psm1') -Force
    Start-OtterDebugSession -FileName (Split-Path -Leaf $Target) -Breakpoints $breakpointLines
    # SkipCount 2: raw trailing tokens are [debug, <target>, ...program args]
    # (-Breakpoints itself is stripped out by Get-OtterRawTrailingArguments
    # regardless of where it appears, same as every other otter.ps1 flag).
    $rawArgs = Get-OtterRawTrailingArguments -SkipCount 2
    $effectiveArguments = if ($null -ne $rawArgs) { $rawArgs } else { $Arguments }
    Invoke-OtterFile -ScriptPath $Target -DebugSession -Arguments $effectiveArguments
    # Invoke-OtterFile always exits itself.
}

if ($Path -in @('web', 'browse', 'serve', 'desktop', 'studio')) {
    if ($Path -eq 'studio') {
        Import-Module (Join-Path $PSScriptRoot 'src\Otter.Desktop.psm1') -Force
        Start-OtterStudio
        exit 0
    }
    $scriptFile = $Target
    if (-not $scriptFile) {
        Write-Host "Usage: otter $Path <script.ot>"
        exit 1
    }
    $projManifest = Find-OtterProjectManifest -Path $scriptFile
    if ($projManifest) {
        try {
            $proj = Get-OtterProject -Path $scriptFile
            $scriptFile = $proj.ResolvedEntryPoint
        } catch [OtterError] {
            Write-Host ''
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host ''
            [Environment]::Exit($script:ExitCheckError)
        }
    }
    if ($Path -eq 'desktop') {
        # `otter desktop app.ot --electron [--output <folder>]` writes a
        # self-contained Electron application instead of launching the
        # PowerShell-hosted desktop window.
        $desktopArgs = Get-OtterRawTrailingArguments -SkipCount 2
        if ($null -eq $desktopArgs) { $desktopArgs = @($Arguments) }
        $wantsElectron = $false
        $electronOutput = $null
        for ($i = 0; $i -lt $desktopArgs.Count; $i++) {
            $token = [string]$desktopArgs[$i]
            if ($token -in @('--electron', '-electron', '-Electron')) {
                $wantsElectron = $true
            } elseif ($token -in @('--output', '-output', '-Output') -and ($i + 1) -lt $desktopArgs.Count) {
                $electronOutput = [string]$desktopArgs[$i + 1]
                $i++
            }
        }
        if ($wantsElectron) {
            Import-Module (Join-Path $PSScriptRoot 'src\Otter.Electron.psm1') -Force
            $entryFull = (Resolve-Path -LiteralPath $scriptFile -ErrorAction SilentlyContinue).Path
            if (-not $entryFull) {
                Write-Host "Otter: I cannot find a file called `"$scriptFile`"." -ForegroundColor Red
                [Environment]::Exit($script:ExitUsageError)
            }
            $baseDir = if ($projManifest) { $proj.RootDirectory } else { Split-Path -Parent $entryFull }
            if (-not $electronOutput) {
                $electronOutput = Join-Path $baseDir 'dist-electron'
            } elseif (-not [System.IO.Path]::IsPathRooted($electronOutput)) {
                $electronOutput = Join-Path (Get-Location).Path $electronOutput
            }
            $exportParams = @{ SourcePath = $entryFull; OutputDir = $electronOutput }
            if ($projManifest) {
                $exportParams.Name = $proj.Name
                $exportParams.Version = $proj.Version
                $exportParams.Assets = @($proj.Assets)
                $exportParams.AssetRoot = $proj.RootDirectory
            }
            $exported = Export-OtterElectronApplication @exportParams
            Write-Host "Otter Electron application written to: $($exported.OutputDir)"
            Write-Host "Run it with Electron installed:  npm install  then  npm start  (inside that folder)"
            exit 0
        }
        Import-Module (Join-Path $PSScriptRoot 'src\Otter.Desktop.psm1') -Force
        Start-OtterDesktopApplication -SourcePath $scriptFile
        exit 0
    }
    if ($Path -eq 'web' -or $Path -eq 'browse') {
        Import-Module (Join-Path $PSScriptRoot 'src\Otter.Web.psm1') -Force
        $htmlPath = Export-OtterWebApplication -SourcePath $scriptFile
        Write-Host "Otter Web application compiled to: $htmlPath"
        if (-not $NoOpen) {
            Start-Process $htmlPath
            Write-Host "Opened in your default browser."
        }
        exit 0
    }
    if ($Path -eq 'serve') {
        Import-Module (Join-Path $PSScriptRoot 'src\Otter.Server.psm1') -Force
        $resolved = Resolve-Path -LiteralPath $scriptFile -ErrorAction SilentlyContinue
        if (-not $resolved) {
            Write-Host "Otter: I cannot find a file called `"$scriptFile`"." -ForegroundColor Red
            [Environment]::Exit($script:ExitUsageError)
        }
        $resolvedProgram = $null
        try {
            $resolvedProgram = Resolve-OtterModuleSource -FilePath $resolved.Path
            $tokens = ConvertTo-OtterTokens -Source $resolvedProgram.CombinedSource
            $ast = ConvertTo-OtterAst -Tokens $tokens
        } catch [OtterError] {
            $err = $_.Exception
            if ($resolvedProgram) {
                $err = ConvertTo-OtterRemappedDiagnostics -Error $err -ResolvedProgram $resolvedProgram -RootFile $resolved.Path
            }
            Write-Host ''
            Write-Host $err.FormatDetailed() -ForegroundColor Red
            Write-Host ''
            [Environment]::Exit($script:ExitCheckError)
        }
        $session = Start-OtterServer -Program $ast -Port $Port
        Write-Host "Otter Web Server running on port $($session.Port). Press Ctrl+C to stop."
        try {
            while ($session.IsRunning) {
                $session.HandleNextRequest()
            }
        } finally {
            Stop-OtterServer -Session $session
        }
        exit 0
    }
}

if ($Path) {
    # D118B: Check if $Path is a project directory or manifest
    $projManifest = Find-OtterProjectManifest -Path $Path
    if ($projManifest) {
        $rawArgs = Get-OtterRawTrailingArguments -SkipCount 1
        $scriptArgs = if ($null -ne $rawArgs) {
            $rawArgs
        } else {
            $fallback = @()
            if ($Target) { $fallback += $Target }
            if ($Arguments) { $fallback += $Arguments }
            $fallback
        }
        $project = $null
        try {
            $project = Get-OtterProject -Path $Path
        } catch [OtterError] {
            Write-Host ''
            Write-Host $_.Exception.Message -ForegroundColor Red
            Write-Host ''
            [Environment]::Exit($script:ExitCheckError)
        }
        Invoke-OtterFile -ScriptPath $project.ResolvedEntryPoint -Arguments $scriptArgs -DisplayTarget $Path
    }

    # Canonical shortest form: otter <file.ot>. Anything that is not a
    # recognized command and does not look like a .ot file is a usage error,
    # not a silent attempt to read a nonexistent file.
    if (-not $Path.ToLowerInvariant().EndsWith('.ot')) {
        $resolvedDir = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
        if (($resolvedDir -and (Test-Path -LiteralPath $resolvedDir.Path -PathType Container)) -or $Path -eq '.') {
            Write-Host "Otter: I cannot find an otter.json manifest in `"$Path`"." -ForegroundColor Red
            [Environment]::Exit($script:ExitUsageError)
        }

        Write-Host "Otter: I do not recognize the command `"$Path`"." -ForegroundColor Red
        Write-Host "Run 'otter help' to see the available commands." -ForegroundColor Red
        [Environment]::Exit($script:ExitUsageError)
    }
    # SkipCount 1: raw trailing tokens are [<path.ot>, ...program args]. Not
    # relying on bound $Target/$Arguments here at all - in this form $Target
    # binds to whatever the program's OWN first argument happens to be
    # (position 1), which the raw-argv reconstruction never needs to know or
    # compensate for since it reads the real command line directly.
    $rawArgs = Get-OtterRawTrailingArguments -SkipCount 1
    $scriptArgs = if ($null -ne $rawArgs) {
        $rawArgs
    } else {
        $fallback = @()
        if ($Target) { $fallback += $Target }
        if ($Arguments) { $fallback += $Arguments }
        $fallback
    }
    Invoke-OtterFile -ScriptPath $Path -Arguments $scriptArgs
    # Invoke-OtterFile always exits itself.
}
else {
    Start-OtterRepl
}
