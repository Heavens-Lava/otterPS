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
    param([string]$Path, [string]$Content, [int]$Line, [bool]$Atomic = $false)

    $full = Resolve-OtterPath -Path $Path -Line $Line
    Initialize-OtterParentFolder -FullPath $full -Line $Line

    if (Test-Path -LiteralPath $full -PathType Container) {
        throw [OtterError]::new("`"$Path`" is a folder, not a file.", $Line, 'runtime')
    }

    # WriteAllText, not Set-Content -Encoding UTF8: on PowerShell 5.1 that
    # switch always prepends a byte-order mark, which other tools show as
    # a stray "i>>?" at the start of the file and which makes "size of
    # file" three bytes larger than the text the programmer wrote.
    # UTF8Encoding($false) means "UTF-8, no BOM".
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    if (-not $Atomic) {
        try {
            [System.IO.File]::WriteAllText($full, $Content, $utf8NoBom)
        }
        catch {
            throw [OtterError]::new("I could not write to `"$Path`". $($_.Exception.Message)", $Line, 'runtime')
        }
        return
    }

    # D72: write the real content to a TEMP file in the same folder first,
    # then perform a single atomic rename onto the real path - a reader
    # (or a crash mid-write) never sees a half-written file, unlike the
    # plain path above which writes directly into place. File.Replace
    # (when the target already exists) and File.Move (when it does not)
    # are both single filesystem operations on the same volume, which is
    # what "atomic" actually means here - a temp-then-copy would not be.
    #
    # File.Replace's backup-path argument MUST be a real path here, not
    # null or empty - confirmed by direct testing: passing $null (per its
    # own MSDN-documented "no backup file created" meaning) throws "The
    # path is not of a legal form" on this PowerShell 5.1/.NET Framework
    # combination, a real, reproducible quirk, not a hypothetical one. A
    # second temp suffix is used as a throwaway backup path and deleted
    # immediately after.
    $tempPath = $full + '.otter-tmp-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $backupPath = $full + '.otter-bak-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        [System.IO.File]::WriteAllText($tempPath, $Content, $utf8NoBom)
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            [System.IO.File]::Replace($tempPath, $full, $backupPath)
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        } else {
            [System.IO.File]::Move($tempPath, $full)
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
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

# if file "x" is locked                                              (D72)
# A file that does not exist is not "locked" - that is what "exists"
# already answers; this asks the DIFFERENT question of whether the file
# is currently held open elsewhere. Detected the only reliable way on
# Windows PowerShell 5.1: try to open it exclusively (FileShare.None)
# and see whether that succeeds - there is no direct "who has this open"
# API available without a native/PInvoke dependency this module does
# not carry.
function Test-OtterFileLocked {
    param([string]$Path, [int]$Line)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $full = Resolve-OtterPath -Path $Path -Line $Line
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }

    try {
        $stream = [System.IO.File]::Open($full, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $stream.Close()
        return $false
    } catch [System.IO.IOException] {
        return $true
    } catch {
        # Some other failure (permissions, etc.) - not the same question
        # as "locked", so fail with a clean Otter error rather than
        # silently reporting a wrong answer either way.
        throw [OtterError]::new("I could not check whether `"$Path`" is locked. $($_.Exception.Message)", $Line, 'runtime')
    }
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

# create symbolic link "l" pointing to "t"                            (D73)
# The link kind (file vs. directory) is auto-detected from whatever
# already exists at TargetPath - New-Item -ItemType SymbolicLink needs
# to know which kind it is making, and Windows treats file/directory
# symlinks as genuinely different reparse-point types. Requires either
# Administrator privileges or Windows 10+ Developer Mode - a real,
# environment-dependent limitation, so a permission failure is
# translated into a clean Otter error naming that cause specifically,
# not a generic "could not create" message.
function New-OtterSymbolicLink {
    param([string]$LinkPath, [string]$TargetPath, [int]$Line)

    $fullTarget = Resolve-OtterPath -Path $TargetPath -Line $Line
    if (-not (Test-Path -LiteralPath $fullTarget)) {
        throw [OtterError]::new("I could not find `"$TargetPath`" to point the link at.", $Line, 'runtime')
    }
    $fullLink = Resolve-OtterPath -Path $LinkPath -Line $Line
    Initialize-OtterParentFolder -FullPath $fullLink -Line $Line

    try {
        # New-Item -ItemType SymbolicLink handles both file and directory
        # targets uniformly on PowerShell 5.1 - it inspects -Target itself
        # to pick the right underlying reparse-point flavor, so Otter does
        # not need to (and, per the class comment above, should not have
        # to) tell it which kind this is.
        [void](New-Item -ItemType SymbolicLink -Path $fullLink -Target $fullTarget -Force -ErrorAction Stop)
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match 'privilege' -or $message -match 'required privilege') {
            throw [OtterError]::new(
                "I could not create the symbolic link `"$LinkPath`" - this needs Administrator privileges or Developer Mode turned on.",
                $Line, 'runtime', 0, $null,
                'Run as Administrator, or turn on Developer Mode in Windows Settings.')
        }
        throw [OtterError]::new("I could not create the symbolic link `"$LinkPath`". $message", $Line, 'runtime')
    }
}

# get symbolic link target of "l" into t                              (D73)
function Get-OtterSymbolicLinkTarget {
    param([string]$LinkPath, [int]$Line)

    $full = Resolve-OtterPath -Path $LinkPath -Line $Line
    if (-not (Test-Path -LiteralPath $full)) {
        throw [OtterError]::new("I could not find a link called `"$LinkPath`".", $Line, 'runtime')
    }
    $item = Get-Item -LiteralPath $full -Force
    if (-not $item.LinkType) {
        throw [OtterError]::new("`"$LinkPath`" is not a symbolic link.", $Line, 'runtime')
    }
    return [string]$item.Target
}

# if file "l" is a symbolic link                                      (D73)
function Test-OtterSymbolicLink {
    param([string]$Path, [int]$Line)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $full = Resolve-OtterPath -Path $Path -Line $Line
    if (-not (Test-Path -LiteralPath $full)) { return $false }
    $item = Get-Item -LiteralPath $full -Force
    return [bool]$item.LinkType
}

# Registry key paths (D78) are their OWN namespace, not filesystem
# paths - "HKCU:\Software\MyApp" must never go through Resolve-
# OtterPath (which anchors relative paths against the current working
# directory, a filesystem-only concept). This validates the drive
# prefix instead, so a typo'd path fails with a clear Otter error
# rather than silently becoming a nonsense filesystem lookup.
function Assert-OtterRegistryKeyPath {
    param([string]$KeyPath, [int]$Line)

    if ($KeyPath -notmatch '^(HKCU|HKLM|HKCR|HKU|HKCC):') {
        throw [OtterError]::new(
            "`"$KeyPath`" does not look like a registry key path.",
            $Line, 'runtime', 0, $null,
            'Registry paths start with HKCU:, HKLM:, HKCR:, HKU:, or HKCC: - for example "HKCU:\Software\MyApp".')
    }
}

# get registry value "n" from "path" into t                           (D78)
# `gone` (not an error) when the value or the key does not exist -
# matching GetEnvironmentVariable's own "unset means gone" choice.
function Get-OtterRegistryValue {
    param([string]$ValueName, [string]$KeyPath, [int]$Line)

    Assert-OtterRegistryKeyPath -KeyPath $KeyPath -Line $Line
    if (-not (Test-Path -LiteralPath $KeyPath)) { return $null }
    try {
        $item = Get-ItemProperty -LiteralPath $KeyPath -Name $ValueName -ErrorAction Stop
        $raw = $item.$ValueName
        # A REG_DWORD/REG_QWORD comes back as a .NET integer type, which
        # Otter's own number runtime type is always a double - cast here
        # so `add`/comparisons on a registry-read number work the same
        # way they do on a number literal, matching how JSON-number
        # decoding already normalizes to double elsewhere in this module.
        if ($raw -is [int] -or $raw -is [long] -or $raw -is [uint32] -or $raw -is [uint64]) {
            return [double]$raw
        }
        return $raw
    } catch {
        return $null
    }
}

# set registry value "n" to "d" in "path"                              (D78)
# Creates the key path if it does not exist yet, matching WriteFile's
# own "creates the parent folder if needed" convention.
function Set-OtterRegistryValue {
    param([string]$ValueName, [string]$Value, [string]$KeyPath, [int]$Line)

    Assert-OtterRegistryKeyPath -KeyPath $KeyPath -Line $Line
    try {
        if (-not (Test-Path -LiteralPath $KeyPath)) {
            [void](New-Item -Path $KeyPath -Force -ErrorAction Stop)
        }
        [void](New-ItemProperty -Path $KeyPath -Name $ValueName -Value $Value -PropertyType String -Force -ErrorAction Stop)
    } catch {
        throw [OtterError]::new(
            "I could not set the registry value `"$ValueName`" in `"$KeyPath`". $($_.Exception.Message)",
            $Line, 'runtime')
    }
}

# delete registry value "n" from "path"                                (D78)
# Deleting a value that is already gone is success, not an error - the
# same "asking for an end state that already holds" tolerance kill/stop
# already use elsewhere in this module.
function Remove-OtterRegistryValue {
    param([string]$ValueName, [string]$KeyPath, [int]$Line)

    Assert-OtterRegistryKeyPath -KeyPath $KeyPath -Line $Line
    if (-not (Test-Path -LiteralPath $KeyPath)) { return }
    try {
        Remove-ItemProperty -LiteralPath $KeyPath -Name $ValueName -ErrorAction Stop
    } catch {
        # already gone, or never existed - nothing left to do
    }
}

# if registry key "path" exists                                       (D78)
function Test-OtterRegistryKeyExists {
    param([string]$KeyPath)

    if ($KeyPath -notmatch '^(HKCU|HKLM|HKCR|HKU|HKCC):') { return $false }
    return (Test-Path -LiteralPath $KeyPath)
}

# get event log entries from "System" up to 20 into entries           (D79)
# LogName is any real Windows event log name ("System", "Application",
# "Security", or a real custom application/provider log) - a plain
# string VALUE, matched at runtime, same design as GetSystemFolder's
# FolderName. Covers both "Event log provider" and "System logs
# provider" on the platform checklist: Windows' own "System" log IS
# the system log on this platform - there is no separate OS-level
# syslog-style provider to add on top of the same Get-WinEvent surface.
# Newest entries first, matching what Event Viewer itself shows by
# default and what most callers actually want ("what just happened").
function Get-OtterEventLogEntries {
    param([string]$LogName, [double]$MaxEntries, [int]$Line)

    $list = [System.Collections.Generic.List[object]]::new()
    try {
        $events = Get-WinEvent -LogName $LogName -MaxEvents ([int]$MaxEntries) -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -match 'No events were found') {
            Write-Output -NoEnumerate $list
            return
        }
        throw [OtterError]::new(
            "I could not read the event log `"$LogName`". $($_.Exception.Message)",
            $Line, 'runtime')
    }
    foreach ($evt in $events) {
        $entry = [OtterObject]::new('event log entry')
        $entry.WriteProperty('source', $evt.ProviderName)
        $entry.WriteProperty('level', $evt.LevelDisplayName)
        $entry.WriteProperty('time', $evt.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))
        $message = $null
        try { $message = $evt.Message } catch { $message = $null }
        $entry.WriteProperty('message', $message)
        $list.Add($entry)
    }
    Write-Output -NoEnumerate $list
}

# Where D81's credential vault lives - one file per credential name,
# under this user's own LOCALAPPDATA (never roamed, never synced,
# never shared with other Windows accounts on the same machine).
function Get-OtterCredentialStorePath {
    $dir = Join-Path $env:LOCALAPPDATA 'Otter\Credentials'
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    return $dir
}

# A credential NAME becomes a filename - reject anything that is not a
# safe, boring identifier before it ever touches the filesystem, so a
# name like "..\..\..\Windows\System32\evil" cannot escape the
# credential store directory (a real path-traversal shape, checked for
# deliberately, not assumed impossible).
function Assert-OtterCredentialName {
    param([string]$Name, [int]$Line)

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -notmatch '^[A-Za-z0-9_.\- ]+$') {
        throw [OtterError]::new(
            "`"$Name`" is not a valid credential name.",
            $Line, 'runtime', 0, $null,
            'Credential names may only use letters, numbers, spaces, dots, dashes, and underscores.')
    }
}

# set credential "n" to "secret"                                      (D81)
# Encrypted with Windows DPAPI, CurrentUser scope: System.Security.
# Cryptography.ProtectedData ties the encryption key to this specific
# Windows login on this specific machine - decrypting the stored file
# on another account, or copying it to another machine, does not work.
# This is a local-only vault, not a secrets-sharing mechanism.
function Set-OtterCredential {
    param([string]$Name, [string]$Secret, [int]$Line)

    Assert-OtterCredentialName -Name $Name -Line $Line
    Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
    $path = Join-Path (Get-OtterCredentialStorePath) "$Name.cred"
    try {
        $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
        $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $plainBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        [System.IO.File]::WriteAllText($path, [Convert]::ToBase64String($protectedBytes))
    } catch {
        throw [OtterError]::new("I could not save the credential `"$Name`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

# get credential "n" into secret                                      (D81)
# `gone` (not an error) when no credential by that name has been set -
# matching GetEnvironmentVariable/GetRegistryValue's own "unset means
# gone" choice.
function Get-OtterCredential {
    param([string]$Name, [int]$Line)

    Assert-OtterCredentialName -Name $Name -Line $Line
    $path = Join-Path (Get-OtterCredentialStorePath) "$Name.cred"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        $protectedBytes = [Convert]::FromBase64String([System.IO.File]::ReadAllText($path))
        $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $protectedBytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [System.Text.Encoding]::UTF8.GetString($plainBytes)
    } catch {
        # A file that exists but cannot be decrypted (wrong user account,
        # moved from another machine, corrupted) is functionally the
        # same as "no usable credential here" - gone, not a crash.
        return $null
    }
}

# delete credential "n"                                               (D81)
# Deleting a credential that is already gone is success, not an error -
# the same "asking for an end state that already holds" tolerance
# kill/registry-value-delete already established elsewhere.
function Remove-OtterCredential {
    param([string]$Name, [int]$Line)

    Assert-OtterCredentialName -Name $Name -Line $Line
    $path = Join-Path (Get-OtterCredentialStorePath) "$Name.cred"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

# The real command line for each power action, as a PURE lookup with no
# side effect - deliberately split out from Invoke-OtterPowerAction
# below so this mapping can be tested exhaustively without ever letting
# a test suite actually shut down, restart, sign out of, or lock the
# machine it runs on. "restart"/"shutDown" pass a real, non-zero grace
# period (30 seconds) rather than /t 0, so a program using this is
# never able to end a user's session with zero warning - the "explicit
# safety" this checklist item's own name asks for.
function Get-OtterPowerActionCommandLine {
    param([string]$Action, [int]$Line)

    switch ($Action) {
        'lock' { return 'rundll32.exe user32.dll,LockWorkStation' }
        'signOut' { return 'shutdown.exe /l' }
        'restart' { return 'shutdown.exe /r /t 30 /c "An Otter program requested a restart."' }
        'shutDown' { return 'shutdown.exe /s /t 30 /c "An Otter program requested a shutdown."' }
        default {
            throw [OtterError]::new("I do not know a power action called ""$Action"".", $Line, 'runtime')
        }
    }
}

# lock the computer / sign out / restart the computer /               (D82)
# shut down the computer
# Every action shells out to the real Windows shutdown.exe/rundll32.exe
# tools - the same real OS mechanism the Start menu's own power/account
# controls use, not a simulation.
function Invoke-OtterPowerAction {
    param([string]$Action, [int]$Line)

    $commandLine = Get-OtterPowerActionCommandLine -Action $Action -Line $Line
    try {
        Invoke-OtterCommand -CommandLine $commandLine -Line $Line | Out-Null
    } catch {
        throw [OtterError]::new("I could not $Action the computer. $($_.Exception.Message)", $Line, 'runtime')
    }
}

# print "file.txt" to "PrinterName"                                   (D83)
# Scoped to plain text, matching every other filesystem statement in
# this language: the file's own text content is sent to the printer
# directly via System.Drawing.Printing.PrintDocument, one physical page
# per real page of text (measured against the printer's own real
# printable area, not assumed), rather than shelling out to a
# document-format-specific print handler. The printer name is checked
# against the real, currently-installed printer list FIRST, so a
# typo'd name fails with a clean, specific Otter error instead of
# either silently going to the default printer or a confusing .NET
# printing exception.
function Send-OtterFileToPrinter {
    param([string]$Path, [string]$PrinterName, [int]$Line)

    $content = Read-OtterFile -Path $Path -Line $Line

    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $installed = [System.Drawing.Printing.PrinterSettings]::InstalledPrinters
    if ($installed -notcontains $PrinterName) {
        throw [OtterError]::new(
            "I could not find a printer called ""$PrinterName"".",
            $Line, 'runtime', 0, $null,
            'Check the exact printer name with get system information "printers" into list.')
    }

    try {
        $doc = [System.Drawing.Printing.PrintDocument]::new()
        $doc.PrinterSettings.PrinterName = $PrinterName
        $font = [System.Drawing.Font]::new('Consolas', 10)
        # A bare reassigned closure variable does NOT reliably persist
        # across separate PrintPage event invocations for the same
        # document (the same WPF-timer-closure gotcha CLAUDE.md already
        # documents for DispatcherTimer.Tick) - a mutable reference type
        # (this hashtable), mutated by field rather than reassigned by
        # name, is used instead so multi-page documents print their
        # later pages' real remaining text, not a stale first-page copy.
        $state = @{ Remaining = $content }
        $printPageHandler = {
            param($sender, $e)
            $linesPerPage = [int]($e.MarginBounds.Height / $font.GetHeight($e.Graphics))
            $lines = $state.Remaining -split "`r`n|`n"
            $pageLines = $lines | Select-Object -First $linesPerPage
            $y = [float]$e.MarginBounds.Top
            foreach ($lineText in $pageLines) {
                $e.Graphics.DrawString($lineText, $font, [System.Drawing.Brushes]::Black, [float]$e.MarginBounds.Left, $y)
                $y += $font.GetHeight($e.Graphics)
            }
            $remainingLines = @($lines | Select-Object -Skip $linesPerPage)
            $state.Remaining = ($remainingLines -join "`n")
            $e.HasMorePages = ($remainingLines.Count -gt 0)
        }.GetNewClosure()
        $doc.add_PrintPage($printPageHandler)
        $doc.Print()
    } catch {
        throw [OtterError]::new("I could not print `"$Path`" to `"$PrinterName`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

# run command "..." on remote "host" using credential "n" [into result]
#                                                                       (D84)
# Real PowerShell Remoting (WinRM) via Invoke-Command - the natural,
# already-idiomatic Windows remote-administration mechanism, not a
# custom protocol. CredentialName doubles as the remote username: it is
# looked up in D81's credential vault for the PASSWORD, so `using
# credential "AZLEG\jmacy"` means "connect as AZLEG\jmacy using the
# password stored under that exact name" - no separate username field,
# and no change to D81's own storage format or meaning.
#
# The remote command is run as a native process ON THE REMOTE MACHINE
# (Start-Process -Wait piped through Get-Content on its own captured
# output), matching the SAME "run a real external program" semantics
# Invoke-OtterCommand already gives locally, rather than executing the
# command text as arbitrary remote PowerShell script - the two are not
# interchangeable, and staying consistent with the local statement's
# own meaning was judged more important than exposing everything WinRM
# could technically do.
#
# The result is captured OUTPUT TEXT, not the local CommandResult's
# separate stdout/stderr/exit-code thing - a WinRM session does not
# expose those the same way a local System.Diagnostics.Process does,
# and approximating them would risk implying a precision this
# mechanism cannot actually deliver.
function Invoke-OtterRemoteCommand {
    param([string]$Command, [string]$HostName, [string]$CredentialName, [int]$Line)

    $password = Get-OtterCredential -Name $CredentialName -Line $Line
    if ($null -eq $password) {
        throw [OtterError]::new(
            "I do not have a credential called `"$CredentialName`" - use set credential `"$CredentialName`" to `"...`" to store one first.",
            $Line, 'runtime')
    }

    try {
        $secure = ConvertTo-SecureString -String $password -AsPlainText -Force
        $psCredential = [System.Management.Automation.PSCredential]::new($CredentialName, $secure)
    } catch {
        throw [OtterError]::new("I could not build a credential for `"$CredentialName`". $($_.Exception.Message)", $Line, 'runtime')
    }

    try {
        $result = Invoke-Command -ComputerName $HostName -Credential $psCredential -ScriptBlock {
            param($cmd)
            $parts = $cmd -split '\s+', 2
            $exe = $parts[0]
            $args = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            if ($args) {
                & $exe $args 2>&1 | Out-String
            } else {
                & $exe 2>&1 | Out-String
            }
        } -ArgumentList $Command -ErrorAction Stop
        return [string]$result
    } catch {
        throw [OtterError]::new(
            "I could not run that command on `"$HostName`". $($_.Exception.Message)",
            $Line, 'runtime')
    }
}

# run command "..." over ssh to "user@host" [into result]             (D85)
# Shells out to the real ssh.exe (Windows' own built-in OpenSSH client
# at System32\OpenSSH, confirmed present, falling back to any ssh.exe
# on PATH otherwise) via the existing Invoke-OtterCommand path - a real
# SSH session, not a custom protocol implementation. -o BatchMode=yes
# is always passed: it makes ssh FAIL IMMEDIATELY with a clean error
# instead of hanging forever at an interactive password/passphrase
# prompt it has no way to answer non-interactively (confirmed directly:
# ssh reads such prompts from the real terminal device, not stdin) -
# the same "explicit safety" spirit D82 already applies to power
# actions, here preventing an Otter program from silently hanging
# rather than preventing an accidental action. -o StrictHostKeyChecking
# =accept-new auto-trusts a NEW host key (first contact) without an
# interactive prompt, while still rejecting a CHANGED one (a real
# potential man-in-the-middle indicator) - accept-new, not the fully
# permissive "no", preserves that one genuine safety check.
function Invoke-OtterSshCommand {
    param([string]$Command, [string]$HostName, [int]$Line)

    $sshPath = if (Test-Path -LiteralPath 'C:\Windows\System32\OpenSSH\ssh.exe') {
        'C:\Windows\System32\OpenSSH\ssh.exe'
    } else {
        'ssh.exe'
    }

    try {
        $commandLine = "$sshPath -o BatchMode=yes -o StrictHostKeyChecking=accept-new $HostName $Command"
        # Invoke-OtterCommand returns an OtterObject (the same "command
        # result" thing D65's plain local `run command` already produces)
        # - read via ReadProperty, not dot-notation, which this class does
        # not support.
        $result = Invoke-OtterCommand -CommandLine $commandLine -Line $Line
        $exitCode = $result.ReadProperty('exit code')
        $stdout = $result.ReadProperty('output')
        $stderr = $result.ReadProperty('error output')
        if ($exitCode -ne 0) {
            $detail = if ($stderr) { $stderr } else { $stdout }
            throw [OtterError]::new(
                ("I could not run that command over ssh on `"$HostName`". $detail").Trim(),
                $Line, 'runtime')
        }
        return $stdout
    } catch [OtterError] {
        throw
    } catch {
        throw [OtterError]::new(
            "I could not run that command over ssh on `"$HostName`". $($_.Exception.Message)",
            $Line, 'runtime')
    }
}

# get owner of "x" into owner                                        (D74)
# Works on either a file or a folder - ownership is a filesystem-wide
# concept, unlike read-only below, which this module deliberately
# restricts to files only (see Test-OtterFileReadOnly's comment).
function Get-OtterFileOwner {
    param([string]$Path, [int]$Line)

    $full = Resolve-OtterPath -Path $Path -Line $Line
    if (-not (Test-Path -LiteralPath $full)) {
        throw [OtterError]::new("I could not find `"$Path`" to check its owner.", $Line, 'runtime')
    }
    try {
        $acl = Get-Acl -LiteralPath $full -ErrorAction Stop
        return $acl.Owner
    }
    catch {
        throw [OtterError]::new("I could not read the owner of `"$Path`". $($_.Exception.Message)", $Line, 'runtime')
    }
}

# if file "x" is read only                                           (D74)
# Deliberately files only, not folders: Windows' read-only ATTRIBUTE on
# a folder is a long-standing, well-known no-op for the "cannot
# accidentally modify" protection a programmer actually wants (Explorer
# and most tools ignore it entirely for folders) - answering this
# question for a folder would return a real bit flag that does not mean
# what the same flag means on a file, which is worse than not answering
# it at all.
function Test-OtterFileReadOnly {
    param([string]$Path, [int]$Line)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $full = Resolve-OtterPath -Path $Path -Line $Line
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $full -Force
    return [bool]($item.Attributes -band [System.IO.FileAttributes]::ReadOnly)
}

# set file "x" to read only / to writable                            (D74)
function Set-OtterFileReadOnly {
    param([string]$Path, [bool]$ReadOnly, [int]$Line)

    $full = Resolve-OtterPath -Path $Path -Line $Line
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw [OtterError]::new("I could not find a file called `"$Path`" to change.", $Line, 'runtime')
    }
    try {
        $current = [System.IO.File]::GetAttributes($full)
        $updated = if ($ReadOnly) {
            $current -bor [System.IO.FileAttributes]::ReadOnly
        } else {
            $current -band (-bnot [System.IO.FileAttributes]::ReadOnly)
        }
        [System.IO.File]::SetAttributes($full, $updated)
    }
    catch {
        throw [OtterError]::new("I could not change `"$Path`"'s read-only setting. $($_.Exception.Message)", $Line, 'runtime')
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

# run "notepad.exe"                - starts it and carries straight on
# run "notepad.exe" into p          - same, and hands back a real process
#                                     handle (id, name) for kill/details
#                                     later (D70). Was silently discarded
#                                     before D70 - `into p` parsed fine but
#                                     the interpreter never populated it
#                                     for the non-command form.
function Start-OtterProgram {
    param([string]$Target, [int]$Line)

    $parts = Split-OtterCommandLine -CommandLine $Target -Line $Line
    $program = $parts[0]
    $arguments = @($parts | Select-Object -Skip 1)

    try {
        $started = if ($arguments.Count -gt 0) {
            Start-Process -FilePath $program -ArgumentList $arguments -PassThru -ErrorAction Stop
        }
        else {
            Start-Process -FilePath $program -PassThru -ErrorAction Stop
        }
    }
    catch {
        throw [OtterError]::new(
            "I could not start `"$program`". $($_.Exception.Message)",
            $Line, 'runtime')
    }
    return New-OtterProcessObject -Process $started
}

# The shared shape for a running-process handle, whether it came from
# `run ... into p` (D70's fix) or `get processes into list` (D70).
function New-OtterProcessObject {
    param([System.Diagnostics.Process]$Process)

    $info = [OtterObject]::new('process')
    $info.WriteProperty('id', [double]$Process.Id)
    $name = $null
    try { $name = $Process.ProcessName } catch { $name = $null }
    $info.WriteProperty('name', $name)

    # D75: memory/CPU/start-time. Each read is wrapped INDIVIDUALLY, not
    # in one shared try/catch, because `get processes into list` walks
    # every running process on the machine, including ones owned by
    # other users or SYSTEM - querying .WorkingSet64/.TotalProcessorTime/
    # .StartTime on those throws a real Win32Exception ("Access is
    # denied"), confirmed directly, while .Id/.ProcessName above stay
    # readable for any process. One field failing degrades to null for
    # that field alone rather than losing the whole process entry.
    $memoryBytes = $null
    try { $memoryBytes = [double]$Process.WorkingSet64 } catch { $memoryBytes = $null }
    $info.WriteProperty('memoryBytes', $memoryBytes)

    $cpuSeconds = $null
    try { $cpuSeconds = [double]$Process.TotalProcessorTime.TotalSeconds } catch { $cpuSeconds = $null }
    $info.WriteProperty('cpuSeconds', $cpuSeconds)

    $startTime = $null
    try { $startTime = $Process.StartTime.ToString('yyyy-MM-dd HH:mm:ss') } catch { $startTime = $null }
    $info.WriteProperty('startTime', $startTime)

    return $info
}

# get processes into list                                              (D70)
function Get-OtterProcessList {
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($proc in (Get-Process -ErrorAction SilentlyContinue)) {
        $list.Add((New-OtterProcessObject -Process $proc))
    }
    Write-Output -NoEnumerate $list
}

# kill process p                    - a single process, by its real PID
# kill process p and its children   - that process and its whole subtree
#
# "and its children" walks Win32_Process's ParentProcessId links via CIM,
# because .NET alone has no portable way to find a process's children on
# Windows PowerShell 5.1 - the same reason D69's "os"/"cpu"/"memory" kinds
# go through CIM. A process that has already exited is not an error - it
# is already gone, which is exactly what `kill` was asked to make true.
function Stop-OtterProcess {
    param([double]$ProcessId, [bool]$IncludeChildren, [int]$Line)

    $rootPid = [int]$ProcessId
    $targets = [System.Collections.Generic.List[int]]::new()
    $targets.Add($rootPid)

    if ($IncludeChildren) {
        try {
            $frontier = [System.Collections.Generic.Queue[int]]::new()
            $frontier.Enqueue($rootPid)
            while ($frontier.Count -gt 0) {
                $current = $frontier.Dequeue()
                $children = Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $current" -ErrorAction Stop
                foreach ($child in $children) {
                    $childId = [int]$child.ProcessId
                    if (-not $targets.Contains($childId)) {
                        $targets.Add($childId)
                        $frontier.Enqueue($childId)
                    }
                }
            }
        } catch {
            # CIM unavailable on this host - fall back to killing just the
            # one process rather than crashing the whole statement.
        }
    }

    foreach ($targetId in $targets) {
        try {
            Stop-Process -Id $targetId -Force -ErrorAction Stop
        } catch {
            # Already exited, or never existed - `kill` making that true
            # is success, not failure (matches the interpreter's own
            # "a closed window cannot be shown again" tolerance elsewhere:
            # asking for an end state that already holds is not an error).
        }
    }
}

# set priority of process p to "high"                                 (D71)
function Set-OtterProcessPriority {
    param([double]$ProcessId, [string]$Priority, [int]$Line)

    $priorityClass = switch ($Priority.ToLowerInvariant()) {
        'low' { [System.Diagnostics.ProcessPriorityClass]::Idle }
        'below normal' { [System.Diagnostics.ProcessPriorityClass]::BelowNormal }
        'normal' { [System.Diagnostics.ProcessPriorityClass]::Normal }
        'above normal' { [System.Diagnostics.ProcessPriorityClass]::AboveNormal }
        'high' { [System.Diagnostics.ProcessPriorityClass]::High }
        'realtime' { [System.Diagnostics.ProcessPriorityClass]::RealTime }
        default {
            throw [OtterError]::new(
                "I do not know a process priority called ""$Priority"".",
                $Line, 'runtime', 0, $null,
                'set priority of process p to "high" (also: "low", "below normal", "normal", "above normal", "realtime")')
        }
    }

    try {
        $proc = Get-Process -Id ([int]$ProcessId) -ErrorAction Stop
        $proc.PriorityClass = $priorityClass
    } catch {
        throw [OtterError]::new(
            "I could not set that process's priority. $($_.Exception.Message)",
            $Line, 'runtime')
    }
}

# wait for process p up to 5 seconds [into finished]                  (D71)
# Real, blocking, with a real timeout - Process.WaitForExit(ms) returns
# whether the process had already exited by the deadline. A process that
# does not exist (already gone) counts as "finished" - there is nothing
# left to wait for, matching this feature's own kill/stop tolerance for
# an end state that already holds.
function Wait-OtterProcess {
    param([double]$ProcessId, [double]$TimeoutSeconds)

    try {
        $proc = Get-Process -Id ([int]$ProcessId) -ErrorAction Stop
    } catch {
        return $true
    }

    $timeoutMs = [int]([Math]::Max(0, $TimeoutSeconds * 1000))
    return [bool]$proc.WaitForExit($timeoutMs)
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


# ===============================================================
# SYSTEM INTEGRATION (D67)
# ===============================================================

# notify "Title" with "Message" - a real Windows balloon-tip
# notification via System.Windows.Forms.NotifyIcon, the same
# dependency-free approach the Desktop bridge's file dialogs already
# use. Deliberately real, not an in-page/console-only stand-in - the
# whole point of D67 was closing gaps where a "notification" turned out
# to only ever be a fake DOM toast.
function Show-OtterNotification {
    param([string]$Title, [string]$Message)

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $icon = [System.Windows.Forms.NotifyIcon]::new()
        $icon.Icon = [System.Drawing.SystemIcons]::Information
        $icon.Visible = $true
        $icon.BalloonTipTitle = $Title
        $icon.BalloonTipText = $Message
        $icon.ShowBalloonTip(5000)
        Start-Sleep -Milliseconds 200
        $icon.Dispose()
    } catch {
        # A host with no desktop session (a CI runner, a plain shell with
        # no Windows Forms message loop available) cannot show a real
        # toast - fails quietly rather than crashing the whole program,
        # the same "unsupported host capability fails clearly, not
        # silently" principle applied at the narrowest possible point
        # (this call), not by pretending the notification succeeded.
    }
}

# choose file / choose folder / choose file to save - real Windows
# common dialogs (OpenFileDialog/FolderBrowserDialog/SaveFileDialog) on
# a dedicated STA thread, since these dialogs require STA and the
# interpreter's own thread is not guaranteed to be one. Blocks until
# the user closes the dialog - no artificial timeout - matching how a
# real, synchronous "choose a file" call in a desktop application
# actually behaves. Returns $null (gone) if the user cancels.
function Show-OtterFileDialog {
    param([ValidateSet('OpenFile', 'SaveFile', 'Folder')][string]$Mode)

    $resultPath = $null
    $thread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            $dialog = switch ($Mode) {
                'OpenFile' { [System.Windows.Forms.OpenFileDialog]::new() }
                'SaveFile' { [System.Windows.Forms.SaveFileDialog]::new() }
                'Folder' { [System.Windows.Forms.FolderBrowserDialog]::new() }
            }
            if ($dialog.GetType().Name -eq 'FolderBrowserDialog') {
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $script:otterDialogResult = $dialog.SelectedPath
                }
            } else {
                if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $script:otterDialogResult = $dialog.FileName
                }
            }
        } catch {
            $script:otterDialogResult = $null
        }
    })
    $script:otterDialogResult = $null
    $thread.SetApartmentState([System.Threading.ApartmentState]::STA)
    $thread.Start()
    $thread.Join()
    return $script:otterDialogResult
}


# get system information "os"/"cpu"/"memory"/"disk"/"network" into info  (D69)
#
# "os", "cpu", and "memory" go through CIM (WMI) because .NET alone has no
# portable way to name the OS/CPU or read total-vs-free physical memory on
# Windows PowerShell 5.1; each is wrapped in try/catch so a locked-down or
# CIM-less host degrades to $null fields instead of a crash. "disk" and
# "network" use plain .NET (DriveInfo / NetworkInformation) - faster, and
# no WMI dependency for the two kinds that do not need it.
#
# Every kind but "network" returns a single OtterObject; "network" returns
# a LIST of them (one per active, non-loopback interface) - the natural
# shape for "how many network interfaces does this machine have", the same
# way GetFolders returns a list rather than a single folder.
function Get-OtterSystemInfoValue {
    param([string]$Kind, [int]$Line)

    switch ($Kind.ToLowerInvariant()) {
        'os' {
            $info = [OtterObject]::new('operating system')
            $caption = $null
            $version = $null
            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $caption = $os.Caption
                $version = $os.Version
            } catch {
                $caption = [System.Environment]::OSVersion.VersionString
                $version = [System.Environment]::OSVersion.Version.ToString()
            }
            $info.WriteProperty('name', $caption)
            $info.WriteProperty('version', $version)
            $info.WriteProperty('architecture', $(if ([System.Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' }))
            $info.WriteProperty('machineName', [System.Environment]::MachineName)
            return $info
        }
        'cpu' {
            $info = [OtterObject]::new('cpu')
            $name = $null
            try {
                $proc = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
                $name = $proc.Name
            } catch {
                $name = $null
            }
            $info.WriteProperty('name', $name)
            $info.WriteProperty('cores', [double][System.Environment]::ProcessorCount)
            return $info
        }
        'memory' {
            $info = [OtterObject]::new('memory')
            $totalBytes = $null
            $freeBytes = $null
            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                $totalBytes = [double]($os.TotalVisibleMemorySize) * 1024.0
                $freeBytes = [double]($os.FreePhysicalMemory) * 1024.0
            } catch {
                $totalBytes = $null
                $freeBytes = $null
            }
            $info.WriteProperty('totalBytes', $totalBytes)
            $info.WriteProperty('freeBytes', $freeBytes)
            return $info
        }
        'disk' {
            $info = [OtterObject]::new('disk')
            $drive = (Get-Location).Drive
            $totalBytes = $null
            $freeBytes = $null
            $driveName = $null
            if ($drive) {
                try {
                    $driveInfo = [System.IO.DriveInfo]::new($drive.Name)
                    $totalBytes = [double]$driveInfo.TotalSize
                    $freeBytes = [double]$driveInfo.AvailableFreeSpace
                    $driveName = $drive.Name
                } catch {
                    $totalBytes = $null
                    $freeBytes = $null
                }
            }
            $info.WriteProperty('drive', $driveName)
            $info.WriteProperty('totalBytes', $totalBytes)
            $info.WriteProperty('freeBytes', $freeBytes)
            return $info
        }
        'network' {
            $list = [System.Collections.Generic.List[object]]::new()
            try {
                $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
                    Where-Object {
                        $_.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up -and
                        $_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback
                    }
                foreach ($iface in $interfaces) {
                    $entry = [OtterObject]::new('network interface')
                    $entry.WriteProperty('name', $iface.Name)
                    $address = $null
                    foreach ($unicast in $iface.GetIPProperties().UnicastAddresses) {
                        if ($unicast.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                            $address = $unicast.Address.ToString()
                            break
                        }
                    }
                    $entry.WriteProperty('address', $address)
                    $list.Add($entry)
                }
            } catch {
                # leave $list empty rather than crash on a locked-down host
            }
            Write-Output -NoEnumerate $list
            return
        }
        # get system information "user" into u                          (D76)
        'user' {
            $info = [OtterObject]::new('user')
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $nameParts = $identity.Name -split '\\', 2
            $domain = if ($nameParts.Count -eq 2) { $nameParts[0] } else { $null }
            $name = if ($nameParts.Count -eq 2) { $nameParts[1] } else { $nameParts[0] }
            $info.WriteProperty('name', $name)
            $info.WriteProperty('domain', $domain)
            $isAdmin = $false
            try {
                $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
                $isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
            } catch { $isAdmin = $false }
            $info.WriteProperty('isAdmin', $isAdmin)
            return $info
        }
        # get system information "groups" into g                        (D76)
        # A list of plain group-name strings, not things - a group here
        # has no further structure worth exposing yet, unlike "network"'s
        # entries. Some of the current user's group SIDs can fail to
        # translate to a name (a stale/orphaned SID from a deleted group
        # or a domain the machine can no longer reach) - those are
        # skipped individually rather than failing the whole list, the
        # same tolerance GetProcesses/GetSystemInfo already use elsewhere.
        'groups' {
            $list = [System.Collections.Generic.List[object]]::new()
            try {
                $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
                foreach ($group in $identity.Groups) {
                    try {
                        $list.Add($group.Translate([System.Security.Principal.NTAccount]).Value)
                    } catch {
                        # an untranslatable SID - skip it, not the whole list
                    }
                }
            } catch {
                # leave $list empty rather than crash on a locked-down host
            }
            Write-Output -NoEnumerate $list
            return
        }
        # get system information "software" into list                   (D77)
        # A list of "software" things (name/version/publisher) read from
        # the registry's own Uninstall keys - the same place Windows'
        # "Apps & features" panel reads from. Deliberately NOT
        # Get-CimInstance Win32_Product: that class is documented and
        # widely known to trigger a Windows Installer CONSISTENCY CHECK
        # (effectively re-validating, and sometimes repairing, every MSI
        # package on the machine) as a side effect of merely being
        # queried - a real, surprising cost for what looks like a
        # read-only question, avoided here on purpose. Entries with no
        # DisplayName (patches/updates/components, not real applications)
        # are skipped, matching what "Apps & features" itself shows.
        'software' {
            $list = [System.Collections.Generic.List[object]]::new()
            $uninstallPaths = @(
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
            foreach ($regPath in $uninstallPaths) {
                try {
                    $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                    foreach ($entry in $entries) {
                        if ([string]::IsNullOrWhiteSpace($entry.DisplayName)) { continue }
                        $software = [OtterObject]::new('software')
                        $software.WriteProperty('name', $entry.DisplayName)
                        $software.WriteProperty('version', $(if ($entry.DisplayVersion) { $entry.DisplayVersion } else { $null }))
                        $software.WriteProperty('publisher', $(if ($entry.Publisher) { $entry.Publisher } else { $null }))
                        $list.Add($software)
                    }
                } catch {
                    # this registry hive/path is unavailable on this host -
                    # move on to the next one rather than failing the list
                }
            }
            Write-Output -NoEnumerate $list
            return
        }
        # get system information "tasks" into list                       (D80)
        # A list of "scheduled task" things (name/state/lastRunTime/
        # nextRunTime) via the Windows Task Scheduler. lastRunTime/
        # nextRunTime come from a SEPARATE call (Get-ScheduledTaskInfo)
        # per task - confirmed directly that TaskScheduler occasionally
        # refuses that second call for a specific task (a stale/disabled
        # task definition) even though the task itself enumerated fine,
        # so that lookup is wrapped per-task, degrading only those two
        # fields to null rather than dropping the task or the whole list.
        'tasks' {
            $list = [System.Collections.Generic.List[object]]::new()
            try {
                $tasks = Get-ScheduledTask -ErrorAction Stop
            } catch {
                Write-Output -NoEnumerate $list
                return
            }
            foreach ($task in $tasks) {
                $entry = [OtterObject]::new('scheduled task')
                $entry.WriteProperty('name', $task.TaskName)
                $entry.WriteProperty('state', $task.State.ToString())
                $lastRun = $null
                $nextRun = $null
                try {
                    $info = $task | Get-ScheduledTaskInfo -ErrorAction Stop
                    if ($info.LastRunTime) { $lastRun = $info.LastRunTime.ToString('yyyy-MM-dd HH:mm:ss') }
                    if ($info.NextRunTime) { $nextRun = $info.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss') }
                } catch {
                    $lastRun = $null
                    $nextRun = $null
                }
                $entry.WriteProperty('lastRunTime', $lastRun)
                $entry.WriteProperty('nextRunTime', $nextRun)
                $list.Add($entry)
            }
            Write-Output -NoEnumerate $list
            return
        }
        # get system information "printers" into list                   (D83)
        # Win32_Printer, not Get-Printer: its .Default is a plain boolean
        # already on the object (confirmed directly), where Get-Printer
        # requires a second lookup to find the default - simpler, and
        # available on every PowerShell 5.1 host without an extra module.
        'printers' {
            $list = [System.Collections.Generic.List[object]]::new()
            try {
                $printers = Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop
            } catch {
                Write-Output -NoEnumerate $list
                return
            }
            # Win32_Printer.PrinterStatus is a raw WMI value-mapped code
            # (confirmed directly via Get-CimClass's ValueMap qualifier),
            # not a friendly string - translated here so "status" reads
            # like the rest of this language's output, not a bare number.
            $statusNames = @{
                1 = 'other'; 2 = 'unknown'; 3 = 'idle'; 4 = 'printing'
                5 = 'warming up'; 6 = 'stopped printing'; 7 = 'offline'
            }
            foreach ($printer in $printers) {
                $entry = [OtterObject]::new('printer')
                $entry.WriteProperty('name', $printer.Name)
                $statusCode = [int]$printer.PrinterStatus
                $statusText = if ($statusNames.ContainsKey($statusCode)) { $statusNames[$statusCode] } else { 'unknown' }
                $entry.WriteProperty('status', $statusText)
                $entry.WriteProperty('isDefault', [bool]$printer.Default)
                $list.Add($entry)
            }
            Write-Output -NoEnumerate $list
            return
        }
        default {
            throw [OtterError]::new(
                "I do not know a kind of system information called ""$Kind"".",
                $Line, 'runtime', 0, $null,
                'get system information "os" into info (also: "cpu", "memory", "disk", "network", "user", "groups", "software", "tasks", "printers")')
        }
    }
}

Export-ModuleMember -Function `
    Resolve-OtterPath, Read-OtterFile, Write-OtterFile, Add-OtterFileContent, Copy-OtterFile, `
    Move-OtterFile, Remove-OtterFile, Test-OtterFileExists, Test-OtterFileLocked, `
    Split-OtterCommandLine, Start-OtterProgram, Invoke-OtterCommand, `
    New-OtterFileObject, Resolve-OtterFileArgument, New-OtterFolderObject, `
    Get-OtterFilesIn, Get-OtterFoldersIn, New-OtterFolder, Remove-OtterFolder, `
    Copy-OtterFolder, Move-OtterFolder, `
    ConvertFrom-OtterJsonText, ConvertTo-OtterJsonText, Read-OtterJsonFile, `
    Show-OtterNotification, Show-OtterFileDialog, Get-OtterSystemInfoValue, `
    New-OtterProcessObject, Get-OtterProcessList, Stop-OtterProcess, `
    Set-OtterProcessPriority, Wait-OtterProcess, `
    New-OtterSymbolicLink, Get-OtterSymbolicLinkTarget, Test-OtterSymbolicLink, `
    Get-OtterFileOwner, Test-OtterFileReadOnly, Set-OtterFileReadOnly, `
    Get-OtterRegistryValue, Set-OtterRegistryValue, Remove-OtterRegistryValue, Test-OtterRegistryKeyExists, `
    Get-OtterEventLogEntries, `
    Set-OtterCredential, Get-OtterCredential, Remove-OtterCredential, `
    Get-OtterPowerActionCommandLine, Invoke-OtterPowerAction, Send-OtterFileToPrinter, `
    Invoke-OtterRemoteCommand, Invoke-OtterSshCommand
