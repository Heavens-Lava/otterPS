using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1

# Otter.Library.psm1
#
# Otter's runtime library: the parts that reach OUTSIDE the program, to the
# file system and to other processes.
#
# rules.md section 27 is the guiding idea here - "Advanced functionality must
# not automatically mean complicated syntax." A single readable line
#
#     read "notes.txt" into notes
#
# becomes path resolution, existence checks, encoding, and error translation.
# All of that lives in this file so the grammar never has to grow for it.
#
# Everything in here raises OtterError with a real line number, because these
# are the operations most likely to fail for reasons outside the program:
# the file is missing, the folder is read-only, the program is not installed.


# ===============================================================
# PATHS
# ===============================================================
#
# Otter paths are relative to wherever the person ran otter from, which is
# what a beginner expects: "notes.txt" means the notes.txt they can see.

function Resolve-OtterPath {
    param([string]$Path, [int]$Line)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw [OtterError]::new('I need the name of a file.', $Line, 'runtime')
    }

    try {
        # Combine rather than Resolve-Path: the file may not exist yet, which
        # is perfectly normal for "write" and "copy" destinations.
        if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
        return [System.IO.Path]::GetFullPath(
            [System.IO.Path]::Combine((Get-Location).Path, $Path))
    }
    catch {
        throw [OtterError]::new("`"$Path`" is not a name Otter can use for a file.", $Line, 'runtime')
    }
}

# Creates the folder a file is about to be written into, so that
# copy "hello.txt" to "backup/hello.txt" works without a separate step.
function Initialize-OtterParentFolder {
    param([string]$FullPath, [int]$Line)

    $folder = [System.IO.Path]::GetDirectoryName($FullPath)
    if ([string]::IsNullOrEmpty($folder) -or (Test-Path -LiteralPath $folder)) { return }

    try {
        [void](New-Item -ItemType Directory -Path $folder -Force)
    }
    catch {
        throw [OtterError]::new("I could not make the folder `"$folder`".", $Line, 'runtime')
    }
}


# ===============================================================
# FILE OBJECTS
# ===============================================================
#
# rules.md gives a file properties, read the ordinary way:
#
#     say name of file
#     say extension of file
#     say size of file
#
#     for each file in files
#         if extension of file is ".jpg"
#             move file to "Pictures"
#         .
#     .
#
# So a file is an OtterObject, not a path string. Every file operation below
# therefore accepts EITHER - a plain path the programmer typed, or a file
# object they got from somewhere - because "move file to ..." passes the
# object while `move "hello.txt" to ...` passes text.
#
# OPEN QUESTION (see D20): nothing in rules.md yet says how you obtain
# `files` in the first place. The back end is ready for it; the grammar is
# not decided.

function New-OtterFileObject {
    param([string]$Path, [int]$Line = 0)

    $full = Resolve-OtterPath -Path $Path -Line $Line
    $file = [OtterObject]::new('file')

    $file.WriteProperty('name', [System.IO.Path]::GetFileName($full))
    $file.WriteProperty('extension', [System.IO.Path]::GetExtension($full))
    $file.WriteProperty('path', $full)

    $size = 0.0
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $size = [double](Get-Item -LiteralPath $full).Length
    }
    $file.WriteProperty('size', $size)

    return $file
}

# Turns whatever the programmer passed - text or a file object - into a path.
function Resolve-OtterFileArgument {
    param([object]$Value, [int]$Line)

    if ($Value -is [OtterObject]) {
        if ($Value.HasProperty('path')) { return [string]$Value.ReadProperty('path') }
        if ($Value.HasProperty('name')) { return [string]$Value.ReadProperty('name') }
        throw [OtterError]::new(
            "I need a file here, but this $($Value.TypeName) has no path.",
            $Line, 'runtime')
    }

    return (Format-OtterValue -Value $Value)
}


# ===============================================================
# FILES  (rules.md section 30)
# ===============================================================

# read "notes.txt" into notes
function Read-OtterFile {
    param([string]$Path, [int]$Line)

    $full = Resolve-OtterPath -Path $Path -Line $Line

    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw [OtterError]::new(
            "I could not find a file called `"$Path`".",
            $Line, 'runtime', 0, $null,
            "if file `"$Path`" exists")
    }

    try {
        $content = Get-Content -LiteralPath $full -Raw -ErrorAction Stop
        if ($null -eq $content) { return '' }
        return $content
    }
    catch {
        throw [OtterError]::new("I could not read `"$Path`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

# write "Hello!" to "hello.txt"    - replaces whatever was there
function Write-OtterFile {
    param([string]$Path, [string]$Content, [int]$Line)

    $full = Resolve-OtterPath -Path $Path -Line $Line
    Initialize-OtterParentFolder -FullPath $full -Line $Line

    if (Test-Path -LiteralPath $full -PathType Container) {
        throw [OtterError]::new("`"$Path`" is a folder, not a file.", $Line, 'runtime')
    }

    try {
        # WriteAllText, not Set-Content -Encoding UTF8: on PowerShell 5.1 that
        # switch always prepends a byte-order mark, which other tools show as
        # a stray "i>>?" at the start of the file and which makes "size of
        # file" three bytes larger than the text the programmer wrote.
        # UTF8Encoding($false) means "UTF-8, no BOM".
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
    }
    catch {
        throw [OtterError]::new("I could not write to `"$Path`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

# copy "hello.txt" to "backup/hello.txt"
function Copy-OtterFile {
    param([string]$Source, [string]$Destination, [int]$Line)

    $from = Resolve-OtterPath -Path $Source -Line $Line
    $to = Resolve-OtterPath -Path $Destination -Line $Line

    if (-not (Test-Path -LiteralPath $from -PathType Leaf)) {
        throw [OtterError]::new("I could not find a file called `"$Source`" to copy.", $Line, 'runtime')
    }

    # "copy x to Documents" means "put it IN Documents", not "rename it to Documents".
    if (Test-Path -LiteralPath $to -PathType Container) {
        $to = [System.IO.Path]::Combine($to, [System.IO.Path]::GetFileName($from))
    }
    else {
        Initialize-OtterParentFolder -FullPath $to -Line $Line
    }

    try {
        Copy-Item -LiteralPath $from -Destination $to -Force -ErrorAction Stop
    }
    catch {
        throw [OtterError]::new("I could not copy `"$Source`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

# move "hello.txt" to "Documents"
function Move-OtterFile {
    param([string]$Source, [string]$Destination, [int]$Line)

    $from = Resolve-OtterPath -Path $Source -Line $Line
    $to = Resolve-OtterPath -Path $Destination -Line $Line

    if (-not (Test-Path -LiteralPath $from -PathType Leaf)) {
        throw [OtterError]::new("I could not find a file called `"$Source`" to move.", $Line, 'runtime')
    }

    if (Test-Path -LiteralPath $to -PathType Container) {
        $to = [System.IO.Path]::Combine($to, [System.IO.Path]::GetFileName($from))
    }
    else {
        Initialize-OtterParentFolder -FullPath $to -Line $Line
    }

    try {
        Move-Item -LiteralPath $from -Destination $to -Force -ErrorAction Stop
    }
    catch {
        throw [OtterError]::new("I could not move `"$Source`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

# delete file "hello.txt"
#
# Deliberately files only. Otter will not remove a folder, because
# "delete file" that quietly erased a directory tree would be a trap.
function Remove-OtterFile {
    param([string]$Path, [int]$Line)

    $full = Resolve-OtterPath -Path $Path -Line $Line

    if (Test-Path -LiteralPath $full -PathType Container) {
        throw [OtterError]::new(
            "`"$Path`" is a folder. Otter only deletes files.",
            $Line, 'runtime')
    }

    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw [OtterError]::new(
            "I could not find a file called `"$Path`" to delete.",
            $Line, 'runtime', 0, $null,
            "if file `"$Path`" exists")
    }

    try {
        Remove-Item -LiteralPath $full -Force -ErrorAction Stop
    }
    catch {
        throw [OtterError]::new("I could not delete `"$Path`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

# if file "hello.txt" exists
function Test-OtterFileExists {
    param([string]$Path, [int]$Line)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $full = Resolve-OtterPath -Path $Path -Line $Line
    return (Test-Path -LiteralPath $full -PathType Leaf)
}


# ===============================================================
# PROGRAMS AND COMMANDS  (rules.md section 31)
# ===============================================================
#
# The brief is explicit: "Do not implement unsafe shell concatenation."
#
# So Otter never builds a command string and hands it to cmd.exe. It splits
# the text into a program plus separate arguments and launches that program
# directly. The practical consequence, worth knowing:
#
#     run command "git status"                 works
#     run command "git status && echo done"    does NOT chain
#
# because there is no shell to interpret &&, |, >, or %VAR%. That is the
# point - a shell would turn any text an Otter program had built up into
# executable commands.

# Splits "git commit -m ""hello world""" into: git, commit, -m, hello world
function Split-OtterCommandLine {
    param([string]$CommandLine, [int]$Line)

    $parts = [System.Collections.Generic.List[string]]::new()
    $current = [System.Text.StringBuilder]::new()
    $inQuotes = $false
    $any = $false

    foreach ($character in $CommandLine.ToCharArray()) {
        if ($character -eq '"') {
            $inQuotes = -not $inQuotes
            $any = $true
            continue
        }
        if ([char]::IsWhiteSpace($character) -and -not $inQuotes) {
            if ($any) {
                [void]$parts.Add($current.ToString())
                [void]$current.Clear()
                $any = $false
            }
            continue
        }
        [void]$current.Append($character)
        $any = $true
    }

    if ($inQuotes) {
        throw [OtterError]::new('This command has a quote that never closes.', $Line, 'runtime')
    }
    if ($any) { [void]$parts.Add($current.ToString()) }

    if ($parts.Count -eq 0) {
        throw [OtterError]::new('I need the name of a program to run.', $Line, 'runtime')
    }

    return , $parts.ToArray()
}

# run "notepad.exe"      - starts it and carries straight on
function Start-OtterProgram {
    param([string]$Target, [int]$Line)

    $parts = Split-OtterCommandLine -CommandLine $Target -Line $Line
    $program = $parts[0]
    $arguments = @($parts | Select-Object -Skip 1)

    try {
        if ($arguments.Count -gt 0) {
            [void](Start-Process -FilePath $program -ArgumentList $arguments -PassThru -ErrorAction Stop)
        }
        else {
            [void](Start-Process -FilePath $program -PassThru -ErrorAction Stop)
        }
    }
    catch {
        throw [OtterError]::new(
            "I could not start `"$program`". $($_.Exception.Message)",
            $Line, 'runtime')
    }
}

# run command "git status"              - waits, prints nothing
# run command "git status" into result  - waits, hands back the output
function Invoke-OtterCommand {
    param([string]$CommandLine, [int]$Line)

    $parts = Split-OtterCommandLine -CommandLine $CommandLine -Line $Line
    $program = $parts[0]
    $arguments = @($parts | Select-Object -Skip 1)

    $resolved = Get-Command -Name $program -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw [OtterError]::new(
            "I could not find a program called `"$program`".",
            $Line, 'runtime')
    }

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # The call operator runs the program directly - no cmd.exe, so nothing
        # in the text can be interpreted as a shell instruction.
        if ($arguments.Count -gt 0) {
            $raw = & $program @arguments 2>&1
        }
        else {
            $raw = & $program 2>&1
        }
    }
    catch {
        throw [OtterError]::new("`"$program`" could not run. $($_.Exception.Message)", $Line, 'runtime')
    }
    finally {
        $ErrorActionPreference = $previous
    }

    # A native program's stderr arrives as ErrorRecord objects rather than
    # text, so flatten everything back to plain lines.
    $lines = foreach ($item in $raw) {
        if ($item -is [System.Management.Automation.ErrorRecord]) { $item.ToString() }
        else { [string]$item }
    }

    return (($lines) -join [Environment]::NewLine)
}


Export-ModuleMember -Function `
    Resolve-OtterPath, Read-OtterFile, Write-OtterFile, Copy-OtterFile, `
    Move-OtterFile, Remove-OtterFile, Test-OtterFileExists, `
    Split-OtterCommandLine, Start-OtterProgram, Invoke-OtterCommand, `
    New-OtterFileObject, Resolve-OtterFileArgument
