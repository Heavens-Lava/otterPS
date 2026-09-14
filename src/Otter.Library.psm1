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

    # rules3 section 8: name, path, extension, size, created, modified.
    $size = 0.0
    $created = $null
    $modified = $null
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $item = Get-Item -LiteralPath $full
        $size = [double]$item.Length
        $created = $item.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
        $modified = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    }
    $file.WriteProperty('size', $size)
    $file.WriteProperty('created', $created)
    $file.WriteProperty('modified', $modified)

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
        # ReadAllText with an explicit UTF-8 decoder, not Get-Content -Raw:
        # Get-Content's default encoding on Windows PowerShell 5.1 is the
        # system codepage when a file has no BOM, not UTF-8 - and
        # Write-OtterFile deliberately writes BOM-less UTF-8 (see its own
        # comment). Confirmed directly: round-tripping "José Müller 你好"
        # through write then read came back as mojibake
        # ("JosÃ© MÃ¼ller ä½ å¥½") purely from this mismatch - the bytes on
        # disk were already correct UTF-8, only the read side decoded them
        # wrong. .NET's UTF8Encoding still honors a BOM if one is present
        # (e.g. a file from another tool), so this is strictly a superset
        # of what Get-Content's guess could get right, never a regression
        # for an already-working case.
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $content = [System.IO.File]::ReadAllText($full, $utf8)
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

# append "line one" to "log.txt"                                  (D61)
function Add-OtterFileContent {
    param([string]$Path, [string]$Content, [int]$Line)

    $full = Resolve-OtterPath -Path $Path -Line $Line
    Initialize-OtterParentFolder -FullPath $full -Line $Line

    if (Test-Path -LiteralPath $full -PathType Container) {
        throw [OtterError]::new("`"$Path`" is a folder, not a file.", $Line, 'runtime')
    }

    try {
        # AppendAllText is create-or-append by default - no separate
        # existence check needed. Same no-BOM UTF-8 as Write-OtterFile.
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::AppendAllText($full, $Content, $utf8NoBom)
    }
    catch {
        throw [OtterError]::new("I could not append to `"$Path`". $($_.Exception.Message)", $Line, 'runtime')
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
# FOLDERS AND DISCOVERY (D20, D21)
# ===============================================================
#
#     get files in "Pictures" into files
#     get files in "Pictures" and subfolders into files
#     get folders in "Documents" into folders
#
# D21: NON-RECURSIVE by default. "and subfolders" is the only way down.
# Reading an entire drive because someone named a folder is exactly the kind
# of surprise the language should not have.

function New-OtterFolderObject {
    param([string]$Path, [int]$Line = 0)

    $full = Resolve-OtterPath -Path $Path -Line $Line
    $folder = [OtterObject]::new('folder')

    $folder.WriteProperty('name', [System.IO.Path]::GetFileName($full.TrimEnd('')))
    $folder.WriteProperty('path', $full)

    if (Test-Path -LiteralPath $full -PathType Container) {
        $item = Get-Item -LiteralPath $full
        $folder.WriteProperty('created', $item.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))
        $folder.WriteProperty('modified', $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    }
    else {
        $folder.WriteProperty('created', $null)
        $folder.WriteProperty('modified', $null)
    }

    # Deliberately NO size property. Measuring a folder means walking
    # everything inside it, which is far too expensive to do just because
    # someone asked for the folder.

    return $folder
}

function Assert-OtterFolderExists {
    param([string]$Path, [int]$Line)

    $full = Resolve-OtterPath -Path $Path -Line $Line
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw [OtterError]::new("I could not find a folder called `"$Path`".", $Line, 'runtime')
    }
    return $full
}

# get files in "Pictures" [and subfolders] into files
function Get-OtterFilesIn {
    param([string]$Path, [bool]$IncludeSubfolders, [int]$Line)

    $full = Assert-OtterFolderExists -Path $Path -Line $Line

    $found = if ($IncludeSubfolders) {
        Get-ChildItem -LiteralPath $full -File -Recurse -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem -LiteralPath $full -File -ErrorAction SilentlyContinue
    }

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $found) {
        $list.Add((New-OtterFileObject -Path $item.FullName -Line $Line))
    }
    Write-Output -NoEnumerate $list
}

# get folders in "Documents" [and subfolders] into folders
function Get-OtterFoldersIn {
    param([string]$Path, [bool]$IncludeSubfolders, [int]$Line)

    $full = Assert-OtterFolderExists -Path $Path -Line $Line

    $found = if ($IncludeSubfolders) {
        Get-ChildItem -LiteralPath $full -Directory -Recurse -ErrorAction SilentlyContinue
    }
    else {
        Get-ChildItem -LiteralPath $full -Directory -ErrorAction SilentlyContinue
    }

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $found) {
        $list.Add((New-OtterFolderObject -Path $item.FullName -Line $Line))
    }
    Write-Output -NoEnumerate $list
}

# create folder "Backup"
function New-OtterFolder {
    param([string]$Path, [int]$Line)

    $full = Resolve-OtterPath -Path $Path -Line $Line
    if (Test-Path -LiteralPath $full -PathType Container) { return }

    try {
        [void](New-Item -ItemType Directory -Path $full -Force -ErrorAction Stop)
    }
    catch {
        throw [OtterError]::new("I could not make the folder `"$Path`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

# delete folder "Backup"
#
# Otter will not erase a folder that still has things in it. Jeff's own
# Part 3 note says Otter must not silently do dangerous things, and
# "delete folder" quietly removing a tree is the clearest example of that.
# Emptying a folder needs syntax that says so, which is not decided yet.
function Remove-OtterFolder {
    param([string]$Path, [int]$Line)

    $full = Resolve-OtterPath -Path $Path -Line $Line

    if (Test-Path -LiteralPath $full -PathType Leaf) {
        throw [OtterError]::new("`"$Path`" is a file, not a folder.", $Line, 'runtime', 0, $null, "delete file `"$Path`"")
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw [OtterError]::new("I could not find a folder called `"$Path`" to delete.", $Line, 'runtime')
    }

    $contents = @(Get-ChildItem -LiteralPath $full -Force -ErrorAction SilentlyContinue)
    if ($contents.Count -gt 0) {
        throw [OtterError]::new(
            "The folder `"$Path`" still has $($contents.Count) things in it. Otter only deletes empty folders.",
            $Line, 'runtime')
    }

    try {
        Remove-Item -LiteralPath $full -Force -ErrorAction Stop
    }
    catch {
        throw [OtterError]::new("I could not delete the folder `"$Path`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

function Copy-OtterFolder {
    param([string]$Source, [string]$Destination, [int]$Line)

    $from = Assert-OtterFolderExists -Path $Source -Line $Line
    $to = Resolve-OtterPath -Path $Destination -Line $Line

    if (Test-Path -LiteralPath $to -PathType Container) {
        $to = [System.IO.Path]::Combine($to, [System.IO.Path]::GetFileName($from.TrimEnd('')))
    }

    try {
        Copy-Item -LiteralPath $from -Destination $to -Recurse -Force -ErrorAction Stop
    }
    catch {
        throw [OtterError]::new("I could not copy the folder `"$Source`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

function Move-OtterFolder {
    param([string]$Source, [string]$Destination, [int]$Line)

    $from = Assert-OtterFolderExists -Path $Source -Line $Line
    $to = Resolve-OtterPath -Path $Destination -Line $Line

    if (Test-Path -LiteralPath $to -PathType Container) {
        $to = [System.IO.Path]::Combine($to, [System.IO.Path]::GetFileName($from.TrimEnd('')))
    }

    try {
        Move-Item -LiteralPath $from -Destination $to -Force -ErrorAction Stop
    }
    catch {
        throw [OtterError]::new("I could not move the folder `"$Source`". $($_.Exception.Message)", $Line, 'runtime')
    }
}


# ===============================================================
# JSON (D29)
# ===============================================================
#
# rules3 section 36: once JSON becomes an Otter value it is an ORDINARY
# object, read the ordinary way:
#
#     read json from "settings.json" into settings
#     say name of user
#     say city of address of user
#
# There is deliberately no separate JSON-navigation syntax. A JSON object
# becomes an OtterObject, a JSON array becomes an Otter list, and everything
# below works from there.

function ConvertFrom-OtterJsonValue {
    param([object]$Value, [int]$Line)

    if ($null -eq $Value) { return $null }

    # ConvertFrom-Json hands back PSCustomObject for objects.
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $object = [OtterObject]::new('thing')
        foreach ($property in $Value.PSObject.Properties) {
            $object.WriteProperty($property.Name, (ConvertFrom-OtterJsonValue -Value $property.Value -Line $Line))
        }
        return $object
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $list.Add((ConvertFrom-OtterJsonValue -Value $item -Line $Line))
        }
        Write-Output -NoEnumerate $list
        return
    }

    if ($Value -is [bool]) { return $Value }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        return [double]$Value
    }

    return [string]$Value
}

function ConvertFrom-OtterJsonText {
    param([string]$Text, [int]$Line)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw [OtterError]::new('There is no JSON here to read.', $Line, 'runtime')
    }

    try {
        $parsed = ConvertFrom-Json -InputObject $Text -ErrorAction Stop
    }
    catch {
        throw [OtterError]::new(
            'This is not valid JSON, so Otter could not read it.',
            $Line, 'runtime')
    }

    Write-Output -NoEnumerate (ConvertFrom-OtterJsonValue -Value $parsed -Line $Line)
}

# Otter value -> something ConvertTo-Json understands.
function ConvertTo-OtterJsonShape {
    param([object]$Value, [int]$Line)

    if ($null -eq $Value) { return $null }

    if ($Value -is [OtterObject]) {
        $map = [ordered]@{}
        foreach ($name in $Value.PropertyNames()) {
            $map[$name] = ConvertTo-OtterJsonShape -Value $Value.ReadProperty($name) -Line $Line
        }
        return $map
    }

    if ($Value -is [System.Collections.Generic.List[object]]) {
        $items = @()
        foreach ($item in $Value) {
            $items += , (ConvertTo-OtterJsonShape -Value $item -Line $Line)
        }
        return , $items
    }

    if ($Value -is [OtterFunction] -or $Value -is [OtterType]) {
        throw [OtterError]::new(
            'Otter cannot turn something it can do into JSON.',
            $Line, 'runtime')
    }

    return $Value
}

function ConvertTo-OtterJsonText {
    param([object]$Value, [int]$Line)

    $shape = ConvertTo-OtterJsonShape -Value $Value -Line $Line
    try {
        return (ConvertTo-Json -InputObject $shape -Depth 32)
    }
    catch {
        throw [OtterError]::new("Otter could not turn this into JSON. $($_.Exception.Message)", $Line, 'runtime')
    }
}

# read json from "settings.json" into settings
function Read-OtterJsonFile {
    param([string]$Path, [int]$Line)

    $text = Read-OtterFile -Path $Path -Line $Line
    Write-Output -NoEnumerate (ConvertFrom-OtterJsonText -Text $text -Line $Line)
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

function ConvertTo-OtterProcessArgument {
    param([string]$Argument)

    if ($Argument.Length -eq 0) { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }

    # ProcessStartInfo.Arguments is one command-line string on .NET Framework.
    # Quote only as much as Windows' command-line parser requires, retaining
    # the argument boundaries already established by Split-OtterCommandLine.
    $escaped = [regex]::Replace($Argument, '(\\*)"', '$1$1\\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

# run command "git status"              - waits, prints nothing
# run command "git status" into result  - waits, hands back a command result
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

    try {
        # Use Process directly rather than PowerShell's native-command
        # pipeline. Windows PowerShell turns native stderr into ErrorRecords;
        # Process preserves the child's two streams exactly as Otter promises.
        $info = [System.Diagnostics.ProcessStartInfo]::new()
        $info.FileName = if ($resolved.Path) { $resolved.Path } else { $program }
        $info.Arguments = (@($arguments | ForEach-Object { ConvertTo-OtterProcessArgument $_ }) -join ' ')
        $info.UseShellExecute = $false
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.CreateNoWindow = $true
        $info.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $info.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        $process = [System.Diagnostics.Process]::Start($info)
        if ($null -eq $process) { throw 'The program process did not start.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [System.Threading.Tasks.Task]::WaitAll(@($stdoutTask, $stderrTask))
        # Native programs conventionally end a displayed line with CRLF.
        # Otter values are line-oriented (as they were before D65), so keep
        # interior newlines but remove only the terminal display whitespace.
        $stdout = $stdoutTask.Result.TrimEnd()
        $stderr = $stderrTask.Result.TrimEnd()
        $exitCode = [double]$process.ExitCode
    }
    catch {
        throw [OtterError]::new("`"$program`" could not run. $($_.Exception.Message)", $Line, 'runtime')
    }

    $result = [OtterObject]::new('command result')
    $result.WriteProperty('output', $stdout)
    $result.WriteProperty('error output', $stderr)
    $result.WriteProperty('exit code', $exitCode)
    return $result
}


Export-ModuleMember -Function `
    Resolve-OtterPath, Read-OtterFile, Write-OtterFile, Add-OtterFileContent, Copy-OtterFile, `
    Move-OtterFile, Remove-OtterFile, Test-OtterFileExists, `
    Split-OtterCommandLine, Start-OtterProgram, Invoke-OtterCommand, `
    New-OtterFileObject, Resolve-OtterFileArgument, New-OtterFolderObject, `
    Get-OtterFilesIn, Get-OtterFoldersIn, New-OtterFolder, Remove-OtterFolder, `
    Copy-OtterFolder, Move-OtterFolder, `
    ConvertFrom-OtterJsonText, ConvertTo-OtterJsonText, Read-OtterJsonFile
