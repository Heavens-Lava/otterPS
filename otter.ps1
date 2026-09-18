using module .\Otter.Contract.psm1
using module .\src\Otter.Runtime.psm1
using module .\src\Otter.Lexer.psm1
using module .\src\Otter.Parser.psm1
using module .\src\Otter.Interpreter.psm1

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
    [Parameter()][Alias('help')][switch]$HelpFlag
)

$ErrorActionPreference = 'Stop'

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
        [switch]$DebugSession
    )

    if (-not $ScriptPath.ToLowerInvariant().EndsWith('.ot')) {
        Write-Host "Otter: `"$ScriptPath`" is not an Otter file - expected a .ot file." -ForegroundColor Red
        exit $script:ExitUsageError
    }

    $resolved = Resolve-Path -LiteralPath $ScriptPath -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Write-Host "Otter: I cannot find a file called `"$ScriptPath`"." -ForegroundColor Red
        exit $script:ExitUsageError
    }

    # Explicit UTF-8 (no BOM) on the read side, matching the write side, so
    # round-tripped Unicode text never silently corrupts (see Otter.Library).
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $source = [System.IO.File]::ReadAllText($resolved.Path, $utf8)
    if ($null -eq $source) { $source = '' }

    $environment = New-OtterEnvironment
    $script:LastFailureStage = $null

    try {
        Invoke-OtterSource -Source $source -Environment $environment -CheckOnly:$CheckOnly
    }
    catch {
        if ($DebugSession) { Complete-OtterDebugSession }
        Show-OtterFailure -ErrorRecord $_
        if ($script:LastFailureStage -eq 'check') {
            exit $script:ExitCheckError
        }
        exit $script:ExitRuntimeError
    }

    if ($DebugSession) { Complete-OtterDebugSession }

    if ($CheckOnly) {
        Write-Host "Otter: $ScriptPath is valid." -ForegroundColor Green
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
    Write-Host '  otter run <file.ot>    Run an Otter program (explicit form)'
    Write-Host '  otter web <file.ot>    Compile an Otter web application to HTML/JS'
    Write-Host '  otter check <file.ot>  Validate a program without running it'
    Write-Host '  otter desktop <file.ot> Run an Otter Desktop app with system bridge'
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

if ($Path -eq 'run' -or $Path -eq 'check') {
    if (-not $Target) {
        Write-Host "Usage: otter $Path <file.ot>" -ForegroundColor Red
        exit $script:ExitUsageError
    }
    Invoke-OtterFile -ScriptPath $Target -CheckOnly:($Path -eq 'check')
    # Invoke-OtterFile always exits itself.
}

if ($Path -eq 'debug') {
    if (-not $Target) {
        Write-Host 'Usage: otter debug <file.ot> -Breakpoints "5,12"' -ForegroundColor Red
        exit $script:ExitUsageError
    }
    $breakpointLines = @()
    if ($Breakpoints) {
        $breakpointLines = @($Breakpoints -split ',' | ForEach-Object { [int]($_.Trim()) })
    }
    Import-Module (Join-Path $PSScriptRoot 'src\Otter.Debugger.psm1') -Force
    Start-OtterDebugSession -FileName (Split-Path -Leaf $Target) -Breakpoints $breakpointLines
    Invoke-OtterFile -ScriptPath $Target -DebugSession
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
    if ($Path -eq 'desktop') {
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
        $tokens = ConvertTo-OtterTokens -Source (Get-Content -LiteralPath $scriptFile -Raw)
        $ast = ConvertTo-OtterAst -Tokens $tokens
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
    # Canonical shortest form: otter <file.ot>. Anything that is not a
    # recognized command and does not look like a .ot file is a usage error,
    # not a silent attempt to read a nonexistent file.
    if (-not $Path.ToLowerInvariant().EndsWith('.ot')) {
        Write-Host "Otter: I do not recognize the command `"$Path`"." -ForegroundColor Red
        Write-Host "Run 'otter help' to see the available commands." -ForegroundColor Red
        exit $script:ExitUsageError
    }
    Invoke-OtterFile -ScriptPath $Path
    # Invoke-OtterFile always exits itself.
}
else {
    Start-OtterRepl
}
