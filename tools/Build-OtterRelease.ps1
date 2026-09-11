# Build-OtterRelease.ps1 - D58 packaging
#
# Builds the smallest complete v1 Windows distribution from a clean checkout
# and produces a versioned zip plus a SHA-256 checksum file, both under
# dist\. Nothing here changes the language, the CLI contract, or runtime
# behavior - it only decides what ships and assembles it.
#
# Usage:
#   powershell -NoProfile -File .\tools\Build-OtterRelease.ps1

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $repoRoot 'VERSION') -Raw).Trim()
$packageName = "otter-$version-windows-x64"

$distDir = Join-Path $repoRoot 'dist'
$stagingDir = Join-Path $distDir $packageName
$zipPath = Join-Path $distDir "$packageName.zip"
$shaPath = "$zipPath.sha256"

Write-Host "Building Otter release $version"

if (Test-Path -LiteralPath $stagingDir) { Remove-Item -LiteralPath $stagingDir -Recurse -Force }
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if (Test-Path -LiteralPath $shaPath) { Remove-Item -LiteralPath $shaPath -Force }
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

# The smallest complete v1 distribution: the CLI entry point, the contract,
# every module the interpreter, desktop UI, web compiler, and server need at
# runtime, the frozen v1 dogfood examples, one plain non-UI example, and the
# release README. Deliberately excludes: scratch/, test-only assets, backup/,
# experimental examples, build artifacts (*.html exports), and developer-only
# docs (rules*.md, KEYWORD-AUDIT.md, SPEC-DECISIONS.md).
$filesToCopy = @(
    'otter.cmd',
    'otter.ps1',
    'VERSION',
    'Otter.Contract.psm1'
)

$srcModules = @(
    'Otter.Runtime.psm1',
    'Otter.Lexer.psm1',
    'Otter.Parser.psm1',
    'Otter.Interpreter.psm1',
    'Otter.Library.psm1',
    'Otter.UI.psm1',
    'Otter.Web.psm1',
    'Otter.Server.psm1'
)

foreach ($file in $filesToCopy) {
    Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination (Join-Path $stagingDir $file)
}

$srcDest = Join-Path $stagingDir 'src'
New-Item -ItemType Directory -Path $srcDest -Force | Out-Null
foreach ($module in $srcModules) {
    Copy-Item -LiteralPath (Join-Path $repoRoot "src\$module") -Destination (Join-Path $srcDest $module)
}

$examplesDest = Join-Path $stagingDir 'examples'
$v1Dest = Join-Path $examplesDest 'v1'
New-Item -ItemType Directory -Path $v1Dest -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'examples\hello.ot') -Destination (Join-Path $examplesDest 'hello.ot')
Get-ChildItem -LiteralPath (Join-Path $repoRoot 'examples\v1') -Filter '*.ot' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $v1Dest $_.Name)
}

$readme = @"
# Otter $version

Readable like English. Precise like code.

## Install

1. Extract this archive anywhere - including a path with spaces.
2. Add the extracted folder to your PATH (see below), or run ``otter.cmd``
   with its full path.
3. Open a *new* terminal window (PATH changes do not apply to windows
   already open).

You do **not** need to change your system-wide PowerShell execution policy.
``otter.cmd`` runs its own script with ``-ExecutionPolicy Bypass`` scoped to
that one call only - it never touches your machine's policy.

### Add to PATH (current user only, reversible)

``````powershell
`$otterDir = 'C:\path\to\extracted\otter'
`$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
[Environment]::SetEnvironmentVariable('Path', "`$userPath;`$otterDir", 'User')
``````

This only appends to your personal PATH - it does not touch the system PATH
or remove anything already there. To undo it, remove that one entry from
Control Panel > Environment Variables, or:

``````powershell
`$otterDir = 'C:\path\to\extracted\otter'
`$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
`$cleaned = (`$userPath -split ';' | Where-Object { `$_ -ne `$otterDir }) -join ';'
[Environment]::SetEnvironmentVariable('Path', `$cleaned, 'User')
``````

## Try it

``````
otter --version
otter help
otter check examples\hello.ot
otter examples\hello.ot
``````

## Requirements

- Windows 10 or later
- Windows PowerShell 5.1 (built into Windows; this is not PowerShell 7/pwsh)
- .NET Framework / WPF (built into Windows) for desktop UI programs

## The CLI

``````
otter <file.ot>        Run a program (shortest form)
otter run <file.ot>    Run a program (explicit form)
otter check <file.ot>  Validate a program without running it - no
                        execution, no window ever opens
otter help             Show usage
otter --help           Show usage
otter --version        Show the installed version
otter                  Start the interactive REPL
``````

This is the complete v1 command surface. Anything not listed here (a package
manager, a formatter, project scaffolding) does not exist yet.

## Getting started

### The smallest program

``````otter
say "Hello from Otter"
``````

Save that as ``hello.ot`` and run:

``````
otter hello.ot
``````

### Variables

``````otter
name is "Jeff"
age is 29
say name
say age
``````

``is`` both declares and assigns - there is no separate declaration step.

### Conditions

``````otter
age is 29

if age is at least 18
    say "You are an adult."
otherwise
    say "Not yet."
.
``````

The ``.`` on its own line closes the block. Today, a condition after ``if``
or ``while`` is a single line - it does not continue onto following lines.

### Loops

``````otter
count from 1 to 3 as number
    say number
.

games are
    "Zelda"
    "Mario"
    "Pokemon"
.

for each game in games
    say game
.
``````

``count`` is reserved for ``count from ... to ... as ...`` loops - it cannot
be used as an ordinary variable name (``count is 0`` is a syntax error).

### Lists

``````otter
games are
    "Zelda"
    "Mario"
.
say length of games
say first of games
``````

### Functions

``````otter
to add number1 and number2
    total is number1 plus number2
    return total
.

add 2 and 3 make sum
say sum
``````

A function called for its return value uses ``<call> make <result>`` - not
``result is <call>``.

### Files

``````otter
write "Otter was here." to "note.txt"
read "note.txt" into notes
say notes
``````

### Objects

``````otter
car is a thing
    brand is "Honda"
    model is "Civic"
.

color of car is "blue"

say brand of car
say color of car
``````

``is a`` constructs a new object; fields written under it set the initial
configuration. To add or change a field afterward, assign through
``<property> of <object> is <value>`` - for a plain object, ``has`` refuses
to replace an existing value rather than silently overwrite it (this is
deliberate, not a bug: see the desktop UI section below for where ``has``
*is* the right tool).

### Errors

``````otter
try
    x is 5 divided by 0
    say x
otherwise
    say "Something went wrong."
.
say "Program continues."
``````

### Desktop UI

This is real, working v1 syntax - not a mockup:

``````otter
create window into app
app has title "My App"
app has width 400
app has height 200

create button into saveButton
saveButton has text "Save"

put saveButton in app

when saveButton is clicked
    say "Saved"
.

show app
``````

``create <kind> into <name>`` makes a UI resource. ``<name> has <property>
<value>`` configures it - here, unlike plain objects, ``has`` is exactly the
right tool: it configures an *existing* UI resource in place rather than
replacing it. ``put <child> in <parent>`` attaches it to a container, and
``show <window>`` opens it. See ``examples\v1\`` for complete, larger
applications built entirely from this system.

## Language decisions worth knowing

- **``is``** assigns/declares. **``is a``** constructs a new object or UI
  resource, with fields indented underneath it as initial configuration.
  **``has``** configures an *existing* UI resource afterward (and refuses to
  silently replace a plain object with the same name - see Objects, above).
- ``total is length of files`` is valid even though ``files`` also appears as
  a keyword elsewhere (``get files``, reading files) - Otter decides what a
  word means from where it sits in the sentence, not by reserving it
  globally. The handful of true exceptions - words that are *always*
  reserved regardless of position - are called out as they come up; ``count``
  (above, under Loops) is the one you are most likely to hit.

## Examples in this package

- ``examples\hello.ot`` - the plain non-UI program above
- ``examples\v1\tasks.ot`` - a task list (desktop UI, dynamic lists)
- ``examples\v1\file-browser.ot`` - reads a real folder and lists its files
- ``examples\v1\contacts.ot`` - a full CRUD app: forms, a scrollable list,
  reading and writing a JSON file

Every one of these is run through the exact same ``otter`` command as your
own programs - nothing about them is special-cased.

## Current limitations

- **Reactive state exists but is intentionally small in v1.** ``state``,
  ``derive``, and ``when <x> changes`` work and are safe to use. A larger
  declarative UI/animation system (``card``, ``layout``, ``memo``,
  ``shared``, ``await``, ``use``, click/hover blocks, animations) exists in
  the source tree but is not connected to anything you can run - do not rely
  on it; it is not v1.
- **A damaged installation fails with a raw PowerShell error, not an Otter
  one.** If a required file under ``src\`` is missing or corrupted, Otter
  cannot catch that failure itself - the error surfaces before any of
  Otter's own error handling can run. This should never happen from an
  intact extraction of this archive; verify the archive's SHA-256 checksum
  if you suspect a bad download.
- ``otter web``, ``otter browse``, and ``otter serve`` also exist (they
  compile a program to a standalone web page, or run it as a small local web
  server) but are not part of the v1 desktop/CLI certification above - use
  them if you want to, but they are documented separately from this v1
  surface.

See ``otter help`` for the full command list.
"@
Set-Content -LiteralPath (Join-Path $stagingDir 'README.md') -Value $readme -Encoding utf8

Write-Host "Staged at $stagingDir"

Compress-Archive -Path (Join-Path $stagingDir '*') -DestinationPath $zipPath -Force
Write-Host "Archive: $zipPath"

$hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
"$($hash.Hash.ToLowerInvariant())  $packageName.zip" | Set-Content -LiteralPath $shaPath -Encoding ascii
Write-Host "Checksum: $shaPath"
Write-Host "SHA-256: $($hash.Hash)"

Write-Host "Done."
