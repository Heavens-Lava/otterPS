# Otter 0.1 - PowerShell edition
# Author: Jeffrey Macy
#
# This is the same language as the C# Otter, rewritten in PowerShell.
# Two ways to use it:
#
#   otter                 -> starts the REPL (Read, Evaluate, Print, Loop)
#   otter hello.ot        -> runs an Otter script file, line by line
#
# param() must be the first real code in the file. PowerShell fills
# these variables in from whatever the user typed on the command line.
param(
    # The .ot script to run. If the user gives no path at all,
    # $Path stays empty and we fall back to the REPL.
    [Parameter(Position = 0)]
    [string]$Path
)

# Stop the whole script on an unexpected error instead of limping along.
$ErrorActionPreference = 'Stop'


# ---------------------------------------------------------------
# Invoke-OtterLine is our entire language engine.
#
# It is the PowerShell twin of Run(string source) in the C# version.
#
# PowerShell function names use a Verb-Noun shape by convention
# ("Invoke" is the approved verb for "go do this thing"), which is
# why this is not just called Run.
# ---------------------------------------------------------------
function Invoke-OtterLine {
    param([string]$Source)

    # Remove leading/trailing spaces so indented lines in a script
    # file still work.
    $source = $Source.Trim()

    # Blank lines and comment lines do nothing.
    # In Otter, a comment starts with #, same as PowerShell.
    if ($source -eq '' -or $source.StartsWith('#')) {
        return
    }

    # ---- keyword: say ----
    # Check whether the command begins with our first Otter keyword.
    if ($source.StartsWith('say ')) {

        # Drop the first 4 characters ("say ") and keep the rest.
        #
        #   source  = say "Hello world!"
        #   message = "Hello world!"
        #
        # PowerShell has no C# range operator (source[4..]), so we use
        # Substring(4), which means "everything from index 4 onward".
        $message = $source.Substring(4).Trim()

        # If the message is wrapped in double quotes, strip them.
        #
        # The $message.Length -ge 2 check matters: a lone " character
        # starts AND ends with a quote, and without this guard we would
        # try to cut two characters off a one-character string and crash.
        # (The C# version still has that bug - worth fixing there too.)
        if ($message.Length -ge 2 -and
            $message.StartsWith('"') -and
            $message.EndsWith('"')) {

            # Substring(start, length):
            # start at index 1 (skip the opening quote) and take
            # every character except the closing quote.
            $message = $message.Substring(1, $message.Length - 2)
        }

        # PRINT: carry out the "say" command.
        Write-Host $message
        return
    }

    # No known Otter keyword matched, so say so plainly.
    Write-Host "I don't understand: $source"
}


# ---------------------------------------------------------------
# Invoke-OtterFile runs a whole .ot script.
#
# A script is just a list of Otter lines, so we read the file and
# hand each line to the same engine the REPL uses.
# ---------------------------------------------------------------
function Invoke-OtterFile {
    param([string]$ScriptPath)

    # Turn "hello.ot" into a full path based on where the user is
    # standing, so error messages are unambiguous.
    $full = Resolve-Path -LiteralPath $ScriptPath -ErrorAction SilentlyContinue

    if (-not $full) {
        Write-Host "otter: cannot find script '$ScriptPath'"
        exit 1
    }

    # Get-Content returns the file as an array of lines.
    foreach ($line in Get-Content -LiteralPath $full) {
        Invoke-OtterLine -Source $line
    }
}


# ---------------------------------------------------------------
# Start-OtterRepl is the interactive mode.
#
# REPL stands for Read -> Evaluate -> Print -> Loop.
# ---------------------------------------------------------------
function Start-OtterRepl {

    Write-Host "Otter 0.1"
    Write-Host "Readable like English. Precise like code."
    Write-Host ""

    while ($true) {

        # Write-Host -NoNewline is PowerShell's Console.Write():
        # the user types on the same line as the prompt.
        Write-Host "otter> " -NoNewline

        # READ: wait for the user to type an Otter command.
        $command = Read-Host   # note: avoid the name $input - PowerShell reserves it

        # Read-Host returns $null if the input stream closes (Ctrl+C /
        # end of piped input), which is our cue to stop.
        if ($null -eq $command -or $command.Trim() -eq 'exit') {
            break
        }

        # EVALUATE + PRINT.
        Invoke-OtterLine -Source $command
    }
}


# ---------------------------------------------------------------
# This is Main(). Everything above only defined functions;
# nothing ran until here.
#
# If we were handed a script path, run the file. Otherwise, chat.
# ---------------------------------------------------------------
if ($Path) {
    Invoke-OtterFile -ScriptPath $Path
}
else {
    Start-OtterRepl
}
