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
    # The .ot script to run. With no path at all, we start the REPL.
    [Parameter(Position = 0)]
    [string]$Path,

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
    [switch]$DebugErrors
)

$ErrorActionPreference = 'Stop'

$OtterVersion = 'Otter 0.2'


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

function Invoke-OtterSource {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Source,
        [Parameter(Mandatory)][OtterEnvironment]$Environment
    )

    # Split once so runtime errors can quote the line they happened on.
    $sourceLines = $Source -split "`r?`n"

    $tokens = ConvertTo-OtterTokens -Source $Source

    if ($DebugTokens) {
        Write-Host '--- tokens ---' -ForegroundColor DarkCyan
        foreach ($token in $tokens) { Write-Host "  $token" -ForegroundColor DarkGray }
        Write-Host ''
    }

    $program = ConvertTo-OtterAst -Tokens $tokens

    if ($ParseOnly) {
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
    param([string]$ScriptPath)

    $resolved = Resolve-Path -LiteralPath $ScriptPath -ErrorAction SilentlyContinue
    if (-not $resolved) {
        Write-Host "Otter: I cannot find a file called `"$ScriptPath`"." -ForegroundColor Red
        exit 1
    }

    $source = Get-Content -LiteralPath $resolved -Raw
    if ($null -eq $source) { $source = '' }

    $environment = New-OtterEnvironment

    try {
        Invoke-OtterSource -Source $source -Environment $environment
    }
    catch {
        Show-OtterFailure -ErrorRecord $_
        exit 1
    }
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

if ($Path) {
    Invoke-OtterFile -ScriptPath $Path
    if ($ParseOnly) { Write-Host "ok: $Path" }
}
else {
    Start-OtterRepl
}
