. "$PSScriptRoot\TestHost.ps1"
# tests/Xml.Tests.ps1
#
# Production-entry-point certification for D105 (XML) on the CONSOLE
# target - see rules.md's own design principle: text is text, xml is
# xml, and the boundary between them (`xml from text/file`, `text from
# xml`) is always explicit. Web-target XML (DOMParser/XMLSerializer -
# genuine browser DOM APIs Node.js does not provide, and this project
# does not add a jsdom-style dependency just to simulate them) was
# verified live in a real browser via Playwright, producing output
# byte-for-byte identical to this file's own console-target tests - see
# tests/Web.Tests.ps1 for the codegen-shape checks that run in this
# suite instead.

. "$PSScriptRoot\TestHelpers.ps1"

Write-Host ''
Write-Host 'XML (D105)' -ForegroundColor Cyan

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:OtterPs1 = Join-Path $script:RepoRoot 'otter.ps1'

function Invoke-OtterXmlProgram {
    param([string]$Source, [string]$WorkingDir = $null)

    $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d105_$([Guid]::NewGuid().ToString('N')).ot")
    [System.IO.File]::WriteAllText($tmpFile, $Source, [System.Text.UTF8Encoding]::new($false))
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $script:OtterHostExe
        $psi.Arguments = "$script:OtterHostArgString -File `"$script:OtterPs1`" run `"$tmpFile`""
        $psi.WorkingDirectory = if ($WorkingDir) { $WorkingDir } else { $script:RepoRoot }
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit(15000) | Out-Null
        return [pscustomobject]@{ Stdout = $stdout; ExitCode = $process.ExitCode }
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
}


# --- 1. The full D105 acceptance example from the design spec -----------

Test-Otter 'the full D105 acceptance example (build, read, write attributes) produces the exact specified output' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"

library is root of document

add element "book" to library and call it book
set attribute "id" of book to "42"

add element "title" with text "Learning Otter" to book
add element "author" with text "Jeff" to book

output is text from xml document
say output
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('<library><book id="42"><title>Learning Otter</title><author>Jeff</author></book></library>') `
        -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'pretty text from xml produces real multi-line indented output' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book
add element "title" with text "Learning Otter" to book

pretty is pretty text from xml document
say pretty
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    $expected = @(
        '<?xml version="1.0" encoding="utf-8"?>',
        '<library>',
        '  <book>',
        '    <title>Learning Otter</title>',
        '  </book>',
        '</library>'
    )
    Assert-Lines -Expected $expected -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}


# --- 2. Reading: element/elements, text of ... in ..., attribute -------

Test-Otter 'element/elements search direct children by tag name, for each iterates them' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it b1
set attribute "id" of b1 to "1"
add element "title" with text "First" to b1
add element "book" to library and call it b2
set attribute "id" of b2 to "2"
add element "title" with text "Second" to b2

books is elements "book" in library
say length of books

for each b in books
    t is text of "title" in b
    i is attribute "id" of b
    say t
    say i
.
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('2', 'First', '1', 'Second', '2') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'child/children select by direct position, not by tag name' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library
add element "movie" to library
add element "game" to library

first is child 0 in library
say name of first
third is child 2 in library
say name of third

all is children 0 in library
say length of all

outOfRange is child 99 in library
if outOfRange is gone
    say "out of range is gone"
.
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('book', 'game', '3', 'out of range is gone') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'attribute of a missing attribute reads as gone, not an error' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book

missing is attribute "isbn" of book
if missing is gone
    say "missing attribute is gone"
.
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('missing attribute is gone') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}


# --- 3. Predicates: element exists / has attribute ------------------------

Test-Otter 'element "X" exists in Y is a real boolean predicate, true and false cases both correct' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library

if element "book" exists in document
    say "book exists"
.
if not element "movie" exists in document
    say "movie does not exist"
.
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('book exists', 'movie does not exist') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'X has attribute Y is a real boolean predicate' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book
set attribute "id" of book to "42"

if book has attribute "id"
    say "has id"
.
if not book has attribute "isbn"
    say "no isbn"
.
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('has id', 'no isbn') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}


# --- 4. Modification: set text/attribute, add/remove element/attribute --

Test-Otter 'set text of / set attribute of actually mutate the real element' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book
add element "title" with text "Draft Title" to book

titleElem is element "title" in book
set text of titleElem to "Learning Otter"
set attribute "id" of book to "42"

say text of titleElem
say attribute "id" of book
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('Learning Otter', '42') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'set text of "name" in xml (the sugar form) finds and mutates the right element' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book
add element "title" with text "Draft Title" to book

set text of "title" in book to "Learning Otter"
say text of "title" in book
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('Learning Otter') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'remove attribute genuinely removes it; a second removal attempt does not error' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book
set attribute "id" of book to "42"

remove attribute "id" from book
after is attribute "id" of book
if after is gone
    say "removed"
.
remove attribute "id" from book
say "second removal did not throw"
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('removed', 'second removal did not throw') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'remove element genuinely detaches it - it no longer shows up under its old parent' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book

say "before:"
say text from xml library

remove element book
say "after:"
say text from xml library
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('before:', '<library><book /></library>', 'after:', '<library></library>') `
        -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'add element ... and call it X binds the new element for immediate use' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it newBook
set attribute "id" of newBook to "7"
say attribute "id" of newBook
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('7') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}


# --- 5. Round trip through a real file ------------------------------------

Test-Otter 'write xml ... to file / xml from file round-trips a real file on disk exactly' {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("otter_d105_$([Guid]::NewGuid().ToString('N')))")
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $r = Invoke-OtterXmlProgram -WorkingDir $dir -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book
set attribute "id" of book to "42"
add element "title" with text "Learning Otter" to book

write xml document to file "books.xml"

reloaded is xml from file "books.xml"
reloadedLibrary is root of reloaded
reloadedBook is element "book" in reloadedLibrary
say attribute "id" of reloadedBook
say text of "title" in reloadedBook
'@
        Assert-AreEqual -Expected 0 -Actual $r.ExitCode
        Assert-Lines -Expected @('42', 'Learning Otter') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
        Assert-True (Test-Path -LiteralPath (Join-Path $dir 'books.xml')) 'expected a real books.xml file on disk'
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


# --- 6. Errors fail loudly, never silently --------------------------------

Test-Otter 'malformed XML text is a clean Otter runtime error, not a raw exception' {
    $r = Invoke-OtterXmlProgram -Source 'document is xml from text "<library><book></library>"'
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'not valid XML') 'expected a specific malformed-XML diagnostic'
    Assert-False ($r.Stdout -match 'at System\.') 'a raw .NET stack trace must never reach the user'
}

Test-Otter 'watching a non-existent xml file is a clean Otter runtime error' {
    $r = Invoke-OtterXmlProgram -Source 'document is xml from file "does-not-exist-12345.xml"'
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
}

Test-Otter 'set attribute on an xml DOCUMENT (not an element) is a clean Otter runtime error' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
set attribute "id" of document to "42"
'@
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'xml document') 'expected a diagnostic naming the document/element distinction'
}

Test-Otter 'setting the text of a name that does not exist in xml is a clean Otter runtime error' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
set text of "missing" in library to "x"
'@
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match "couldn't find an element") 'expected a specific not-found diagnostic'
}


# --- 7. XML is its own type, not conflated with anything else -----------

Test-Otter 'xml is a distinct type - `say` never guesses it is a list, thing, or plain text' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
say length of document
'@
    Assert-AreEqual -Expected 3 -Actual $r.ExitCode
    Assert-True ($r.Stdout -match 'this is xml') 'expected Get-OtterTypeName to correctly report "xml"'
}


# --- 8. Keyword narrowing (no regressions) --------------------------------

Test-Otter 'xml/element/elements/child/children/attribute/attributes/root remain ordinary identifiers elsewhere' {
    $r = Invoke-OtterXmlProgram -Source @'
xml is "hello"
element is 5
elements is "text"
child is 3
children is true
attribute is "sunny"
attributes is 7
root is "top"
say xml
say element
say elements
say child
say children
say attribute
say attributes
say root
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('hello', '5', 'text', '3', 'true', 'sunny', '7', 'top') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'a variable literally named "element" still works with add/remove element statements naming it as the tag' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
element is "book"
add element element to library
say text from xml library
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('<library><book /></library>') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

# --- 9. Regression: "the X" filler-word compatibility -----------------
#
# A real bug found while verifying D105 against Codex's OWN pre-existing
# Parser.Tests.ps1 (not this file's own tests, none of which happened to
# use "the"): every new "X of Y"/"X in Y" grammar form here originally
# called Read-OtterValue for its target WITHOUT -PropertyTarget, so a
# bare "the book"/"the document" at the end of a clause (nothing further
# for the OTHER, PropertyTarget-independent "the X of Y" lookahead to
# key off) was read as an ordinary variable literally named "the",
# leaving the real target name as unconsumed trailing input - it
# actually broke Otter's own PRE-EXISTING "text of the nameBox" UI
# grammar, caught only by running the full suite, not by any test in
# this file.

Test-Otter '"the" is accepted as filler before an xml/element target, same as everywhere else in Otter' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book
set attribute "id" of the book to "42"
say attribute "id" of the book

titleElem is element "title" in the library
if titleElem is gone
    say "no title yet"
.

remove attribute "id" from the book
after is attribute "id" of the book
if after is gone
    say "removed"
.
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('42', 'no title yet', 'removed') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Test-Otter 'the pre-existing "text of the X" UI-property grammar is completely unaffected by the new "text of" xml grammar' {
    $r = Invoke-OtterXmlProgram -Source @'
document is xml with root "library"
library is root of document
add element "book" to library and call it book
add element "title" with text "Learning Otter" to book

titleElem is element "title" in book
say the text of the titleElem
'@
    Assert-AreEqual -Expected 0 -Actual $r.ExitCode
    Assert-Lines -Expected @('Learning Otter') -Actual (($r.Stdout -split "`r?`n") | Where-Object { $_ -ne '' })
}

Complete-OtterTests
