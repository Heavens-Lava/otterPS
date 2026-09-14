using module ..\Otter.Contract.psm1
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force

$source = @'
name is "Jeff"
say "Hello" name
if age is at least 18
    say "Adult"
'@
$ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source)
if ($ast -isnot [ProgramNode]) { throw 'Expected a ProgramNode.' }
if ($ast.Statements.Count -ne 3) { throw "Expected three statements, got $($ast.Statements.Count)." }
if ($ast.Statements[0] -isnot [AssignStmt]) { throw 'Expected assignment.' }
if ($ast.Statements[1].Parts.Count -ne 2) { throw 'Expected two say parts.' }
if ($ast.Statements[2] -isnot [IfStmt]) { throw 'Expected if statement.' }
if ($ast.Statements[2].Branches[0].Condition.Op -ne [CompareOp]::AtLeast) { throw 'Expected is at least comparison.' }
if ($ast.Statements[2].Branches[0].Body[0] -isnot [SayStmt]) { throw 'Expected say in if body.' }

$mathSource = @'
number1 is 5
number2 is 10
number1 and number2 make total
add 5 to total
remove 2 from total
ask "Name?" and call it name
'@
$mathAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $mathSource)
if ($mathAst.Statements[2] -isnot [MathIntoStmt]) { throw 'Expected a math-into statement.' }
if ($mathAst.Statements[2].Expression.Op -ne [MathOp]::Add) { throw 'Expected and to mean addition in a make statement.' }
if ($mathAst.Statements[3] -isnot [AddToStmt]) { throw 'Expected add statement.' }
if ($mathAst.Statements[4] -isnot [RemoveFromStmt]) { throw 'Expected remove statement.' }
if ($mathAst.Statements[5] -isnot [AskStmt]) { throw 'Expected ask statement.' }

$controlSource = @'
games are
    "Zelda"
    "Mario"
.
if not loggedIn or games contains "Zelda"
    say "Welcome"
otherwise
    say "No entry"
repeat 2 times
    say "Again"
while score is less than 3
    add 1 to score
count from 1 to 2 as number
    say number
for each game in games
    say game
games are empty
'@
$controlAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $controlSource)
if ($controlAst.Statements[0] -isnot [ListDefStmt]) { throw 'Expected list definition.' }
if ($controlAst.Statements[1].Branches[0].Condition -isnot [LogicalExpr]) { throw 'Expected logical condition.' }
if ($controlAst.Statements[2] -isnot [RepeatStmt]) { throw 'Expected repeat.' }
if ($controlAst.Statements[3] -isnot [WhileStmt]) { throw 'Expected while.' }
if ($controlAst.Statements[4] -isnot [CountStmt]) { throw 'Expected count loop.' }
if ($controlAst.Statements[5] -isnot [ForEachStmt]) { throw 'Expected for each loop.' }
if ($controlAst.Statements[6].Items.Count -ne 0) { throw 'Expected empty list.' }

# D38B: a trailing boolean connective may continue an if/while header one
# level deeper. The continuation indent is also the body indent.
$continuedConditionSource = @'
if left is 1 and
    right is 2
    say "yes"
.
if left is 1 or
    middle is 2 and
    right is 3
    say "precedence"
.
while ready is false and
    attempts is less than 5
    say "retry"
.
'@
$continuedConditionAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $continuedConditionSource)
if ($continuedConditionAst.Statements.Count -ne 3) { throw 'Expected three continued-condition statements.' }
if ($continuedConditionAst.Statements[0] -isnot [IfStmt] -or $continuedConditionAst.Statements[0].Branches[0].Condition -isnot [LogicalExpr]) { throw 'Expected a continued and condition.' }
if ($continuedConditionAst.Statements[0].Branches[0].Body.Count -ne 1) { throw 'Expected the if body after its continued condition.' }
$precedenceCondition = $continuedConditionAst.Statements[1].Branches[0].Condition
if ($precedenceCondition.Op -ne [LogicalOp]::Or -or $precedenceCondition.Right.Op -ne [LogicalOp]::And) { throw 'Expected not > and > or precedence across continued lines.' }
if ($continuedConditionAst.Statements[2] -isnot [WhileStmt] -or $continuedConditionAst.Statements[2].Body.Count -ne 1) { throw 'Expected a while body after its continued condition.' }

foreach ($badContinuation in @(
@'
if left is 1 and
right is 2
    say "no"
.
'@,
@'
if left is 1 and
    say "no"
.
'@,
@'
if left is 1 or
    say "no"
.
'@,
@'
value is 1 and
    2
'@
)) {
    $caught = $false
    try { ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $badContinuation) } catch [OtterError] { $caught = $true }
    if (-not $caught) { throw 'Expected malformed continuation to fail.' }
}

$countStillReserved = $false
try { ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'count is length of files') } catch { $countStillReserved = $true }
if (-not $countStillReserved) { throw 'Expected count to remain a reserved loop keyword.' }

$ordinaryBodySource = @'
if left is 1
    right is 2
    say "body"
.
'@
$ordinaryBodyAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $ordinaryBodySource)
if ($ordinaryBodyAst.Statements[0].Branches[0].Condition -isnot [ComparisonExpr] -or $ordinaryBodyAst.Statements[0].Branches[0].Body.Count -ne 2) {
    throw 'Expected an ordinary if body to remain separate from its condition.'
}

$indentJumpCaught = $false
try {
    ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
if left is 1 and
        right is 2
        say "no"
.
'@)
} catch { $indentJumpCaught = $true }
if (-not $indentJumpCaught) { throw 'Expected D7 to reject an excessive continuation indentation jump.' }

$functionSource = @'
to greet name
    say "Hello" name
greet "Jeff"
to add number1 and number2
    number1 and number2 make answer
    return answer
add 5 and 10 make total
'@
$functionAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $functionSource)
if ($functionAst.Statements[0] -isnot [FunctionDefStmt]) { throw 'Expected function definition.' }
if ($functionAst.Statements[1].Call.Name -ne 'greet') { throw 'Expected greet call.' }
if ($functionAst.Statements[2].Body[1] -isnot [ReturnStmt]) { throw 'Expected return statement.' }
if ($functionAst.Statements[3].Call.Name -ne 'add' -or $functionAst.Statements[3].ResultTarget -ne 'total') { throw 'Expected add function call with result.' }

$captureSource = @'
to double number
    number times 2 make answer
    return answer
double 5 make result
say result

to five
    return 5
five make anotherResult
'@
$captureAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $captureSource)
if ($captureAst.Statements[1] -isnot [CallStmt] -or $captureAst.Statements[1].ResultTarget -ne 'result') { throw 'Expected an argument call to capture its result.' }
if ($captureAst.Statements[4] -isnot [CallStmt] -or $captureAst.Statements[4].Call.Arguments.Count -ne 0) { throw 'Expected a zero-argument call, not a variable expression.' }

$objectSource = @'
person is a thing
    name is "Jeff"
    age is 29
.
say name of person
name of person is "Jeffrey"
say name of person
a Person has
    name
    age
.
jeff is a Person
say city of address of user
'@
$objectAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $objectSource)
if ($objectAst.Statements[0] -isnot [ObjectDefStmt] -or $objectAst.Statements[0].TypeName -ne 'thing') { throw 'Expected a thing definition.' }
if ($objectAst.Statements[1].Parts[0] -isnot [PropertyAccessExpr]) { throw 'Expected property read in say.' }
if ($objectAst.Statements[2].Target -isnot [PropertyAccessExpr]) { throw 'Expected property assignment target.' }
if ($objectAst.Statements[4] -isnot [TypeDefStmt] -or $objectAst.Statements[4].FieldNames.Count -ne 2) { throw 'Expected custom type definition.' }
if ($objectAst.Statements[5] -isnot [ObjectDefStmt] -or $objectAst.Statements[5].TypeName -ne 'Person') { throw 'Expected custom-type object definition.' }
$nested = $objectAst.Statements[6].Parts[0]
if ($nested.Property -ne 'city' -or $nested.Target.Property -ne 'address' -or $nested.Target.Target.Name -ne 'user') { throw 'Property access must nest right-to-left.' }

$fileSource = @'
write "Hello" to "note.txt"
append " world" to "note.txt"
read "note.txt" into notes
copy "note.txt" to "backup/note.txt"
move "note.txt" to "archive/note.txt"
delete file "archive/note.txt"
if file "archive/note.txt" exists
    say "Still there"
run "notepad.exe"
run command "git status" into status
'@
$fileAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $fileSource)
if ($fileAst.Statements[0] -isnot [WriteFileStmt]) { throw 'Expected write file statement.' }
if ($fileAst.Statements[1] -isnot [AppendFileStmt] -or $fileAst.Statements[1].Content.Value -ne ' world' -or $fileAst.Statements[1].Path.Value -ne 'note.txt') { throw 'Expected append file statement.' }
if ($fileAst.Statements[2] -isnot [ReadFileStmt] -or $fileAst.Statements[2].Target -ne 'notes') { throw 'Expected read file statement.' }
if ($fileAst.Statements[3] -isnot [CopyFileStmt] -or $fileAst.Statements[4] -isnot [MoveFileStmt]) { throw 'Expected copy and move statements.' }
if ($fileAst.Statements[5] -isnot [DeleteFileStmt]) { throw 'Expected delete file statement.' }
if ($fileAst.Statements[6].Branches[0].Condition -isnot [FileExistsExpr]) { throw 'Expected file exists condition.' }
if (-not $fileAst.Statements[7].IsCommand -and $fileAst.Statements[8].IsCommand -and $fileAst.Statements[8].ResultTarget -eq 'status') { } else { throw 'Expected run forms to preserve command and capture flags.' }

$part3Source = @'
get files in "Pictures" and subfolders into files
get folders in "Documents" into folders
create folder "Backup"
copy folder "Work" to "Backup"
move folder "Work" to "Archive"
delete folder "Backup"
user is gone
if user is not gone
    say name of user
try
    read "settings.json" into settings
otherwise
    say "Could not load settings."
.
'@
$part3Ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $part3Source)
if ($part3Ast.Statements[0] -isnot [GetFilesStmt] -or -not $part3Ast.Statements[0].IncludeSubfolders) { throw 'Expected recursive file discovery.' }
if ($part3Ast.Statements[1] -isnot [GetFoldersStmt] -or $part3Ast.Statements[1].IncludeSubfolders) { throw 'Expected non-recursive folder discovery.' }
if ($part3Ast.Statements[2] -isnot [CreateFolderStmt] -or $part3Ast.Statements[3] -isnot [CopyFolderStmt] -or $part3Ast.Statements[4] -isnot [MoveFolderStmt] -or $part3Ast.Statements[5] -isnot [DeleteFolderStmt]) { throw 'Expected folder operation statements.' }
if ($null -ne $part3Ast.Statements[6].Value.Value) { throw 'Gone must be a null literal.' }
if ($part3Ast.Statements[7].Branches[0].Condition.Op -ne [CompareOp]::NotEqual) { throw 'Expected "is not gone" comparison.' }
if ($part3Ast.Statements[8] -isnot [TryStmt] -or $part3Ast.Statements[8].OtherwiseBody.Count -ne 1) { throw 'Expected try/otherwise statement.' }

$collectionSource = @'
name is "Jeff Macy"
first is "Jeff"
say length of name
say uppercase of name
say lowercase of name
if name contains "Jeff"
    say "Found"
if name starts with "J"
    say "Starts"
if name ends with "Macy"
    say "Ends"
sort games
reverse games
replace "Jeff" with "Jeffrey" in name
split name by " " into words
join words with ", " into text
find game in games where game is "Mario" into result
'@
$collectionAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $collectionSource)
if ($collectionAst.Statements[1].Target.Name -ne 'first') { throw 'First must remain an ordinary assignment target.' }
if ($collectionAst.Statements[2].Parts[0] -isnot [OfOperationExpr] -or $collectionAst.Statements[2].Parts[0].Operation -ne [OfOperation]::Length) { throw 'Expected length operation expression.' }
if ($collectionAst.Statements[3].Parts[0].Operation -ne [OfOperation]::Uppercase -or $collectionAst.Statements[4].Parts[0].Operation -ne [OfOperation]::Lowercase) { throw 'Expected case operation expressions.' }
if ($collectionAst.Statements[5].Branches[0].Condition -isnot [ContainsExpr]) { throw 'Contains should keep its existing AST node.' }
if ($collectionAst.Statements[6].Branches[0].Condition -isnot [TextMatchExpr] -or $collectionAst.Statements[7].Branches[0].Condition.Match -ne [TextMatch]::EndsWith) { throw 'Expected text match expressions.' }
if ($collectionAst.Statements[8] -isnot [SortStmt] -or $collectionAst.Statements[9] -isnot [ReverseStmt]) { throw 'Expected collection mutation statements.' }
if ($collectionAst.Statements[10] -isnot [ReplaceStmt] -or $collectionAst.Statements[11] -isnot [SplitStmt] -or $collectionAst.Statements[12] -isnot [JoinStmt]) { throw 'Expected string transform statements.' }
if ($collectionAst.Statements[13] -isnot [FindStmt] -or $collectionAst.Statements[13].ItemName -ne 'game' -or $collectionAst.Statements[13].Target -ne 'result') { throw 'Find must retain its item name and target.' }

try {
    ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'double 5 make result') | Out-Null
    throw 'Expected an undefined call to fail.'
}
catch [OtterError] {
    if (-not $_.Exception.SourceLine -or -not $_.Exception.Suggestion) { throw 'Parser errors must include source text and a suggestion.' }
}

$rules4Source = @'
price is 10
tax is 2
total is price plus tax
increase score by 5
increase score
decrease lives
decrease health by damage
each product in products
    say name of product
.
for each product in products
    say product
.
to stopEarly
    stop
'@
$rules4Tokens = ConvertTo-OtterTokens -Source $rules4Source
if ($rules4Tokens[11].Kind -ne [TokenKind]::And) { throw 'Plus must lex directly to And.' }
$rules4Ast = ConvertTo-OtterAst -Tokens $rules4Tokens
if ($rules4Ast.Statements[2].Value -isnot [MathExpr] -or $rules4Ast.Statements[2].Value.Op -ne [MathOp]::Add) { throw 'Plus must produce ordinary addition.' }
if ($rules4Ast.Statements[3] -isnot [AddToStmt] -or $rules4Ast.Statements[3].Target -ne 'score' -or $rules4Ast.Statements[3].Amount.Value -ne 5) { throw 'Increase by must produce AddToStmt with its amount.' }
if ($rules4Ast.Statements[4] -isnot [AddToStmt] -or $rules4Ast.Statements[4].Amount.Value -ne 1) { throw 'Bare increase must synthesize one.' }
if ($rules4Ast.Statements[5] -isnot [RemoveFromStmt] -or $rules4Ast.Statements[5].Amount.Value -ne 1) { throw 'Bare decrease must synthesize one.' }
if ($rules4Ast.Statements[6] -isnot [RemoveFromStmt] -or $rules4Ast.Statements[6].Amount -isnot [VariableExpr] -or $rules4Ast.Statements[6].Amount.Name -ne 'damage') { throw 'Decrease by must retain its expression.' }
if ($rules4Ast.Statements[7] -isnot [ForEachStmt] -or $rules4Ast.Statements[7].VariableName -ne 'product') { throw 'Bare each must produce ForEachStmt.' }
if ($rules4Ast.Statements[8] -isnot [ForEachStmt]) { throw 'For each must remain valid.' }
if ($rules4Ast.Statements[9].Body[0] -isnot [ReturnStmt] -or $null -ne $rules4Ast.Statements[9].Body[0].Value) { throw 'Stop must produce a valueless ReturnStmt.' }

$hasAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
legacy is a thing
    name is "Jeff"
.
person has
    name is "Jeff"
    age is 29
.
a Person has
    name
    age
.
'@)
if ($hasAst.Statements[0] -isnot [ObjectDefStmt] -or $hasAst.Statements[0].TypeName -ne 'thing') { throw 'is a thing must remain valid.' }
if ($hasAst.Statements[1] -isnot [ObjectDefStmt] -or $hasAst.Statements[1].TypeName -ne 'thing' -or $hasAst.Statements[1].Properties.Count -ne 2) { throw 'person has must construct an untyped object.' }
if ($hasAst.Statements[2] -isnot [TypeDefStmt] -or $hasAst.Statements[2].FieldNames.Count -ne 2) { throw 'a Person has must remain a type definition.' }

$dynamicSource = @'
person has
    name is "Jeff"
.
get "nickname" from person into nickname
set "nickname" to "Jeffrey" in person
get name of person from person into copied
get files in "." into files
for each file in files
    set "size" to 0 in file
.
'@
$dynamicAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $dynamicSource)
if ($dynamicAst.Statements[0] -isnot [ObjectDefStmt] -or $dynamicAst.Statements[0].Properties.Count -ne 1) { throw 'D41 object setup must remain an object definition.' }
if ($dynamicAst.Statements[1] -isnot [GetKeyStmt] -or $dynamicAst.Statements[1].ResultTarget -ne 'nickname') { throw 'Dynamic get must capture its result target.' }
if ($dynamicAst.Statements[2] -isnot [SetKeyStmt] -or $dynamicAst.Statements[2].Target.Name -ne 'person') { throw 'Dynamic set must retain its target expression.' }
if ($dynamicAst.Statements[3] -isnot [GetKeyStmt] -or $dynamicAst.Statements[3].Key -isnot [PropertyAccessExpr]) { throw 'Dynamic get keys must accept full expressions.' }
if ($dynamicAst.Statements[5].Body[0] -isnot [SetKeyStmt] -or $dynamicAst.Statements[5].Body[0].Target.Name -ne 'file') { throw 'Dynamic set in a file loop must retain the file target for runtime guarding.' }

$continuationSource = @'
get files in "Pictures" and subfolders
    into pictures
get folders in "Documents"
    into folders
'@
$continuationAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $continuationSource)
if ($continuationAst.Statements[0] -isnot [GetFilesStmt] -or -not $continuationAst.Statements[0].IncludeSubfolders -or $continuationAst.Statements[0].Target -ne 'pictures') { throw 'D38A continued get files must preserve discovery fields.' }
if ($continuationAst.Statements[1] -isnot [GetFoldersStmt] -or $continuationAst.Statements[1].IncludeSubfolders -or $continuationAst.Statements[1].Target -ne 'folders') { throw 'D38A continued get folders must preserve discovery fields.' }
$singleLineDiscovery = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source ('get files in "Pictures" and subfolders into pictures' + "`n"))
if ($singleLineDiscovery.Statements[0] -isnot [GetFilesStmt] -or -not $singleLineDiscovery.Statements[0].IncludeSubfolders) { throw 'Single-line discovery must remain valid.' }

$emptyObjects = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
emptyOne has
emptyTwo is a thing
say "still a program"
'@)
if ($emptyObjects.Statements[0].Properties.Count -ne 0 -or $emptyObjects.Statements[1].Properties.Count -ne 0) { throw 'Empty has and is-a-thing objects must have zero properties.' }
$terminatedEmptyObjects = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
settings has
.
config is a thing
.
'@)
if ($terminatedEmptyObjects.Statements[0] -isnot [ObjectDefStmt] -or $terminatedEmptyObjects.Statements[0].Properties.Count -ne 0) { throw 'Empty has with a period must produce zero properties.' }
if ($terminatedEmptyObjects.Statements[1] -isnot [ObjectDefStmt] -or $terminatedEmptyObjects.Statements[1].Properties.Count -ne 0) { throw 'Empty is-a-thing with a period must produce zero properties.' }
$createAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
create folder "Backup"
create button into helloButton
create text box into nameBox
create window into app
create sprocket into x
'@)
if ($createAst.Statements[0] -isnot [CreateFolderStmt]) { throw 'create folder must retain its existing parser branch.' }
if ($createAst.Statements[1] -isnot [CreateUiResourceStmt] -or $createAst.Statements[1].TypeName -ne 'button' -or $createAst.Statements[1].Target -ne 'helloButton') { throw 'create button must produce a UI resource statement.' }
if ($createAst.Statements[2].TypeName -ne 'text box' -or $createAst.Statements[2].Target -ne 'nameBox') { throw 'create text box must preserve its two-word type name.' }
if ($createAst.Statements[3].TypeName -ne 'window' -or $createAst.Statements[4].TypeName -ne 'sprocket') { throw 'create must pass unknown resource kinds through to runtime.' }
$whenAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
when helloButton is clicked
    say "Hello"
.
when nameBox is changed
    say "Changed"
.
'@)
if ($whenAst.Statements[0] -isnot [WhenStmt] -or $whenAst.Statements[0].Target.Name -ne 'helloButton' -or $whenAst.Statements[0].EventName -ne 'clicked') { throw 'D46 clicked handler must preserve target and event.' }
if ($whenAst.Statements[1] -isnot [WhenStmt] -or $whenAst.Statements[1].EventName -ne 'changed' -or $whenAst.Statements[1].Body.Count -ne 1) { throw 'D46 changed handler must parse its body.' }
$d47Ast = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
put helloButton in app
show app
'@)
if ($d47Ast.Statements[0] -isnot [PutInStmt] -or $d47Ast.Statements[0].Item.Name -ne 'helloButton' -or $d47Ast.Statements[0].Container.Name -ne 'app') { throw 'D47 put must preserve item and container.' }
if ($d47Ast.Statements[1] -isnot [ShowStmt] -or $d47Ast.Statements[1].Target.Name -ne 'app') { throw 'D47 show must preserve its target.' }
$inlineHasSource = 'addButton has text "Add", width 120, height 40, background "#2563EB", foreground "white"' + "`n"
$inlineHasAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $inlineHasSource)
if ($inlineHasAst.Statements[0] -isnot [ObjectDefStmt] -or $inlineHasAst.Statements[0].Properties.Count -ne 5 -or $inlineHasAst.Statements[0].Properties[0].Target.Name -ne 'text' -or $inlineHasAst.Statements[0].Properties[4].Target.Name -ne 'foreground') { throw 'Inline has must produce ordered property assignments.' }
$compactHasSource = 'panel has width windowWidth minus 40, height 300, text "Ready"' + "`n"
$compactHasAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $compactHasSource)
if ($compactHasAst.Statements[0] -isnot [ObjectDefStmt] -or $compactHasAst.Statements[0].Properties.Count -ne 3 -or $compactHasAst.Statements[0].Properties[0].Target.Name -ne 'width' -or $compactHasAst.Statements[0].Properties[2].Target.Name -ne 'text') { throw 'Inline has without is must parse ordered properties and expressions.' }
$mixedHasSource = 'panel has width is windowWidth minus 40, height 300, text is "Ready"' + "`n"
$mixedHasAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $mixedHasSource)
if ($mixedHasAst.Statements[0].Properties.Count -ne 3) { throw 'Inline has should allow independently optional is markers.' }
foreach ($invalidHas in @('addButton has text is "Add",', 'addButton has , width 120', 'addButton has text is, width 120', 'addButton has text "Add" width 120')) {
    $rejected = $false
    try { ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source ($invalidHas + "`n")) | Out-Null } catch [OtterError] { $rejected = $true }
    if (-not $rejected) { throw "Malformed inline has should be rejected: $invalidHas" }
}
$multiPutAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "put firstLabel, firstBox, addButton in app`n")
if ($multiPutAst.Statements.Count -ne 3 -or $multiPutAst.Statements[0] -isnot [PutInStmt] -or $multiPutAst.Statements[0].Item.Name -ne 'firstLabel' -or $multiPutAst.Statements[1].Item.Name -ne 'firstBox' -or $multiPutAst.Statements[2].Item.Name -ne 'addButton') { throw 'Multi-put must desugar in left-to-right order.' }
foreach ($invalidPut in @('put a, in app', 'put , a in app', 'put a b in app')) {
    $rejected = $false
    try { ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source ($invalidPut + "`n")) | Out-Null } catch [OtterError] { $rejected = $true }
    if (-not $rejected) { throw "Malformed multi-put should be rejected: $invalidPut" }
}
$theAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
say width of button
say the width of button
width of button is 120
the width of button is 120
say the city of address of user
say "The Otter"
'@)
if ($theAst.Statements[0].Parts[0].GetType().Name -ne $theAst.Statements[1].Parts[0].GetType().Name -or $theAst.Statements[0].Parts[0].Property -ne $theAst.Statements[1].Parts[0].Property) { throw 'Optional the must preserve property-access AST shape.' }
if ($theAst.Statements[2].Target.GetType().Name -ne 'PropertyAccessExpr' -or $theAst.Statements[3].Target.GetType().Name -ne 'PropertyAccessExpr') { throw 'Optional the must preserve property-assignment AST shape.' }
if ($theAst.Statements[4].Parts[0].Property -ne 'city' -or $theAst.Statements[4].Parts[0].Target.Property -ne 'address') { throw 'Optional the must preserve nested property access.' }
if ($theAst.Statements[5].Parts[0].Value -ne 'The Otter') { throw 'the inside a string must remain unchanged.' }
$theRejected = $false
try { ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "say the of`n") | Out-Null } catch [OtterError] { $theRejected = $true }
if (-not $theRejected) { throw 'the must not be accepted as arbitrary filler.' }
$propertyTheAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
say text of nameBox
say the text of nameBox
say text of the nameBox
say the text of the nameBox
say the city of the address of the user
name is the text of the nameBox
if the text of the nameBox is "Jeff"
    say "the property matched"
.
say "the"
the is "named the"
'@)
$propertyParts = $propertyTheAst.Statements[0..3] | ForEach-Object { $_.Parts[0] }
foreach ($part in $propertyParts) {
    if ($part.GetType().Name -ne 'PropertyAccessExpr' -or $part.Property -ne 'text' -or $part.Target.Name -ne 'nameBox') { throw 'All direct optional-the property forms must produce the same AST.' }
}
$nestedThe = $propertyTheAst.Statements[4].Parts[0]
if ($nestedThe.Property -ne 'city' -or $nestedThe.Target.Property -ne 'address' -or $nestedThe.Target.Target.Name -ne 'user') { throw 'Optional the must compose through nested property access.' }
if ($propertyTheAst.Statements[5].Value.GetType().Name -ne 'PropertyAccessExpr' -or $propertyTheAst.Statements[6].Branches[0].Condition.Left.GetType().Name -ne 'PropertyAccessExpr') { throw 'Optional-the property targets must work in assignments and conditions.' }
if ($propertyTheAst.Statements[7].Parts[0].Value -ne 'the' -or $propertyTheAst.Statements[8].Target.Name -ne 'the') { throw 'the inside strings and identifier positions must remain unchanged.' }
$articleAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
create window into app
create the window into the app
put the window in the app
show the app
the is "named the"
'@)
if ($articleAst.Statements[0].TypeName -ne $articleAst.Statements[1].TypeName -or $articleAst.Statements[0].Target -ne $articleAst.Statements[1].Target) { throw 'create with the must preserve the canonical AST shape.' }
if ($articleAst.Statements[2].Item.Name -ne 'window' -or $articleAst.Statements[2].Container.Name -ne 'app' -or $articleAst.Statements[3].Target.Name -ne 'app') { throw 'put/show with the must preserve resource names.' }
if ($articleAst.Statements[4].Target.Name -ne 'the') { throw 'the must remain usable as an ordinary identifier.' }
$rawTheCreate = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "create the into x`n")
if ($rawTheCreate.Statements[0].TypeName -ne 'the') { throw 'create the into x must preserve the resource kind named the.' }
$whenTheRejected = $false
$whenTheSource = "when the helloButton is clicked`n    say `"Hi`"`n.`n"
try { ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $whenTheSource) | Out-Null } catch [OtterError] {
    $whenTheRejected = $_.Exception.Message -like '*Event targets do not use*'
}
if (-not $whenTheRejected) { throw 'when the <resource> should explain that the is not supported there.' }
foreach ($invalid in @('put in app', 'put helloButton app', 'show')) {
    $rejected = $false
    try { ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source ($invalid + "`n")) | Out-Null }
    catch [OtterError] { $rejected = $true }
    if (-not $rejected) { throw "Malformed D47 statement should be rejected: $invalid" }
}
try {
    ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "if true`n") | Out-Null
    throw 'An empty if block must remain invalid.'
}
catch [OtterError] { }

# D49 HTTP requests & web data tests
$httpSource = @"
get "https://api.example.com/status" into statusText
get json from "https://api.example.com/users" into users
get "https://api.example.com/items" as json into items
post user to "https://api.example.com/users"
post user to "https://api.example.com/users" into createdUser
post user as json to "https://api.example.com/users" into createdJson
put user to "https://api.example.com/users/5" into updatedUser
delete from "https://api.example.com/users/5" into deleteResult
put helloButton in app
get "Jeff" from scores into score
delete file "notes.txt"
"@
$httpAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $httpSource)
if ($httpAst.Statements[0] -isnot [HttpGetStmt] -or $httpAst.Statements[0].AsJson -ne $false -or $httpAst.Statements[0].Target -ne 'statusText') {
    throw 'get <url> into <target> must parse as HttpGetStmt with AsJson false.'
}
if ($httpAst.Statements[1] -isnot [HttpGetStmt] -or $httpAst.Statements[1].AsJson -ne $true -or $httpAst.Statements[1].Target -ne 'users') {
    throw 'get json from <url> into <target> must parse as HttpGetStmt with AsJson true.'
}
if ($httpAst.Statements[2] -isnot [HttpGetStmt] -or $httpAst.Statements[2].AsJson -ne $true -or $httpAst.Statements[2].Target -ne 'items') {
    throw 'get <url> as json into <target> must parse as HttpGetStmt with AsJson true.'
}
if ($httpAst.Statements[3] -isnot [HttpPostStmt] -or (-not [string]::IsNullOrEmpty($httpAst.Statements[3].Target))) {
    throw 'post <data> to <url> must parse as HttpPostStmt with empty target.'
}
if ($httpAst.Statements[4] -isnot [HttpPostStmt] -or $httpAst.Statements[4].Target -ne 'createdUser') {
    throw 'post <data> to <url> into <target> must parse as HttpPostStmt.'
}
if ($httpAst.Statements[5] -isnot [HttpPostStmt] -or $httpAst.Statements[5].AsJson -ne $true) {
    throw 'post <data> as json to <url> into <target> must parse as HttpPostStmt with AsJson true.'
}
if ($httpAst.Statements[6] -isnot [HttpPutStmt] -or $httpAst.Statements[6].Target -ne 'updatedUser') {
    throw 'put <data> to <url> into <target> must parse as HttpPutStmt.'
}
if ($httpAst.Statements[7] -isnot [HttpDeleteStmt] -or $httpAst.Statements[7].Target -ne 'deleteResult') {
    throw 'delete from <url> into <target> must parse as HttpDeleteStmt.'
}
if ($httpAst.Statements[8] -isnot [PutInStmt]) {
    throw 'put <resource> in <container> must remain PutInStmt.'
}
if ($httpAst.Statements[9] -isnot [GetKeyStmt]) {
    throw 'get <key> from <thing> into <result> must remain GetKeyStmt.'
}
if ($httpAst.Statements[10] -isnot [DeleteFileStmt]) {
    throw 'delete file <path> must remain DeleteFileStmt.'
}

# HTTP soft continuation test
$contHttpSource = "get `"https://api.example.com/status`"`n    into statusText`n"
$contHttpAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $contHttpSource)
if ($contHttpAst.Statements[0] -isnot [HttpGetStmt] -or $contHttpAst.Statements[0].Target -ne 'statusText') {
    throw 'get with multiline continuation into must parse correctly.'
}

# D51 Web Server & API route tests
$webServerSource = @'
api is a web server
    port is 5000
    host is "localhost"
.

when api receives GET at "/users"
    respond with users as json
.

when api receives POST at "/users" into req
    respond with user as json and status 201
.

when server receives a request at "/hello"
    respond with "Hello from Otter!"
.

when api receives GET at "/health"
    respond with status 200
.

start api
listen on port 8080
'@

$serverAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $webServerSource)

# 1. Object definition
if ($serverAst.Statements[0] -isnot [ObjectDefStmt] -or $serverAst.Statements[0].TypeName -ne 'web server') {
    throw 'Expected web server object definition.'
}
# 2. GET route
if ($serverAst.Statements[1] -isnot [WebRouteStmt] -or $serverAst.Statements[1].Method -ne 'GET' -or $serverAst.Statements[1].Path.Value -ne '/users') {
    throw 'Expected GET WebRouteStmt.'
}
if ($serverAst.Statements[1].Body[0] -isnot [RespondStmt] -or $serverAst.Statements[1].Body[0].AsJson -ne $true) {
    throw 'Expected RespondStmt with AsJson in GET route.'
}
# 3. POST route with into req
if ($serverAst.Statements[2] -isnot [WebRouteStmt] -or $serverAst.Statements[2].Method -ne 'POST' -or $serverAst.Statements[2].RequestTarget -ne 'req') {
    throw 'Expected POST WebRouteStmt with RequestTarget.'
}
if ($serverAst.Statements[2].Body[0] -isnot [RespondStmt] -or $serverAst.Statements[2].Body[0].Status.Value -ne 201) {
    throw 'Expected RespondStmt with status 201.'
}
# 4. "a request" open route
if ($serverAst.Statements[3] -isnot [WebRouteStmt] -or $serverAst.Statements[3].Method -ne 'ALL' -or $serverAst.Statements[3].Path.Value -ne '/hello') {
    throw 'Expected ALL WebRouteStmt from "a request".'
}
# 5. Status-only response
if ($serverAst.Statements[4].Body[0] -isnot [RespondStmt] -or $null -ne $serverAst.Statements[4].Body[0].Value -or $serverAst.Statements[4].Body[0].Status.Value -ne 200) {
    throw 'Expected status-only RespondStmt.'
}
# 6. Start server
if ($serverAst.Statements[5] -isnot [StartServerStmt] -or $serverAst.Statements[5].Server.Name -ne 'api') {
    throw 'Expected StartServerStmt.'
}
# 7. Listen server
if ($serverAst.Statements[6] -isnot [ListenServerStmt] -or $serverAst.Statements[6].Port.Value -ne 8080) {
    throw 'Expected ListenServerStmt.'
}
# ===============================================================
# Core 'with' syntax tests (name is a Type with ...)
# ===============================================================

# 1. Core untyped object ('thing') in compact form
$withThingAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'person is a thing with name "Jeff", age 29')
if ($withThingAst.Statements[0] -isnot [ObjectDefStmt] -or $withThingAst.Statements[0].TypeName -ne 'thing' -or $withThingAst.Statements[0].Name -ne 'person') {
    throw 'Expected ObjectDefStmt with type thing and name person.'
}
if ($withThingAst.Statements[0].Properties.Count -ne 2) {
    throw 'Expected 2 properties in with thing.'
}
if ($withThingAst.Statements[0].Properties[0].Target.Name -ne 'name' -or $withThingAst.Statements[0].Properties[0].Value.Value -ne 'Jeff') {
    throw 'Expected name property assignment.'
}
if ($withThingAst.Statements[0].Properties[1].Target.Name -ne 'age' -or $withThingAst.Statements[0].Properties[1].Value.Value -ne 29) {
    throw 'Expected age property assignment.'
}

# 2. Explicit 'is' form produces identical AST
$withExplicitIsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'person is a thing with name is "Jeff", age is 29')
if ($withExplicitIsAst.Statements[0].Properties[0].Target.Name -ne $withThingAst.Statements[0].Properties[0].Target.Name -or
    $withExplicitIsAst.Statements[0].Properties[0].Value.Value -ne $withThingAst.Statements[0].Properties[0].Value.Value -or
    $withExplicitIsAst.Statements[0].Properties[1].Target.Name -ne $withThingAst.Statements[0].Properties[1].Target.Name -or
    $withExplicitIsAst.Statements[0].Properties[1].Value.Value -ne $withThingAst.Statements[0].Properties[1].Value.Value) {
    throw 'Explicit is form must produce identical AST to compact form.'
}

# 3. Equivalence between multi-line block and inline with
$multilineThingAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
person is a thing
    name is "Jeff"
    age is 29
.
'@)
if ($multilineThingAst.Statements[0].Properties.Count -ne $withThingAst.Statements[0].Properties.Count -or
    $multilineThingAst.Statements[0].Properties[0].Target.Name -ne $withThingAst.Statements[0].Properties[0].Target.Name -or
    $multilineThingAst.Statements[0].Properties[0].Value.Value -ne $withThingAst.Statements[0].Properties[0].Value.Value) {
    throw 'Multi-line block and inline with must produce equivalent AST.'
}

# 4. Custom type with inline with
$customTypeWithAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
a Point has
    x
    y
.
coord is a Point with x 10, y 20
'@)
if ($customTypeWithAst.Statements[1] -isnot [ObjectDefStmt] -or $customTypeWithAst.Statements[1].TypeName -ne 'Point' -or $customTypeWithAst.Statements[1].Properties.Count -ne 2) {
    throw 'Custom type with inline with must produce ObjectDefStmt with properties.'
}

# 5. Web resource kinds with single and multiple words
$webKindsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
saveBtn is a button with text "Save", width 120
brandName is a text with text "Jeffrey Macy", size 16, weight 700
nameInput is a text box with text "hello", width 200
heroRow is a row with spacing 48, width "100%"
'@)
if ($webKindsAst.Statements[0].TypeName -ne 'button' -or $webKindsAst.Statements[0].Properties.Count -ne 2) {
    throw 'Expected button with 2 properties.'
}
if ($webKindsAst.Statements[1].TypeName -ne 'text' -or $webKindsAst.Statements[1].Properties.Count -ne 3) {
    throw 'Expected text with 3 properties.'
}
if ($webKindsAst.Statements[2].TypeName -ne 'text box' -or $webKindsAst.Statements[2].Properties.Count -ne 2) {
    throw 'Expected text box with 2 properties.'
}
if ($webKindsAst.Statements[3].TypeName -ne 'row' -or $webKindsAst.Statements[3].Properties.Count -ne 2) {
    throw 'Expected row with 2 properties.'
}

# 6. Interaction with existing replace...with and join...with
$replaceJoinAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
replace "cat" with "dog" in sentence
join items with ", " into result
item is a thing with name "gadget"
'@)
if ($replaceJoinAst.Statements[0] -isnot [ReplaceStmt] -or $replaceJoinAst.Statements[0].Replacement.Value -ne 'dog') {
    throw 'replace ... with ... must remain intact.'
}
if ($replaceJoinAst.Statements[1] -isnot [JoinStmt] -or $replaceJoinAst.Statements[1].Separator.Value -ne ', ') {
    throw 'join ... with ... must remain intact.'
}
if ($replaceJoinAst.Statements[2] -isnot [ObjectDefStmt] -or $replaceJoinAst.Statements[2].Properties[0].Target.Name -ne 'name') {
    throw 'object with following replace/join must parse correctly.'
}

# 7. Malformed cases error checking
# 7a. Missing property after with
$caughtMissingProp = $false
try {
    [void](ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "item is a thing with`n"))
} catch {
    $caughtMissingProp = $true
}
if (-not $caughtMissingProp) { throw 'Expected error for missing property after with.' }

# 7b. Trailing comma
$caughtTrailingComma = $false
try {
    [void](ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "item is a thing with name `"Jeff`",`n"))
} catch {
    $caughtTrailingComma = $true
}
if (-not $caughtTrailingComma) { throw 'Expected error for trailing comma after property.' }

# 7c. Missing comma between properties
$caughtMissingComma = $false
try {
    [void](ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "item is a thing with name `"Jeff`" age 29`n"))
} catch {
    $caughtMissingComma = $true
}
# ===============================================================
# Multi-line object block tests with optional 'is'
# ===============================================================

# 1. Compact multi-line property lines (no 'is')
$compactBlockAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
card is a card
    width 400
    padding 20
.
'@)
if ($compactBlockAst.Statements[0] -isnot [ObjectDefStmt] -or $compactBlockAst.Statements[0].Properties.Count -ne 2) {
    throw 'Expected ObjectDefStmt with 2 properties in compact block.'
}
if ($compactBlockAst.Statements[0].Properties[0].Target.Name -ne 'width' -or $compactBlockAst.Statements[0].Properties[0].Value.Value -ne 400) {
    throw 'Expected width 400 in compact block.'
}
if ($compactBlockAst.Statements[0].Properties[1].Target.Name -ne 'padding' -or $compactBlockAst.Statements[0].Properties[1].Value.Value -ne 20) {
    throw 'Expected padding 20 in compact block.'
}

# 2. Explicit 'is' in multi-line block
$explicitBlockAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
card is a card
    width is 400
    padding is 20
.
'@)
if ($explicitBlockAst.Statements[0].Properties[0].Target.Name -ne $compactBlockAst.Statements[0].Properties[0].Target.Name -or
    $explicitBlockAst.Statements[0].Properties[0].Value.Value -ne $compactBlockAst.Statements[0].Properties[0].Value.Value -or
    $explicitBlockAst.Statements[0].Properties[1].Target.Name -ne $compactBlockAst.Statements[0].Properties[1].Target.Name -or
    $explicitBlockAst.Statements[0].Properties[1].Value.Value -ne $compactBlockAst.Statements[0].Properties[1].Value.Value) {
    throw 'Explicit is and compact multi-line blocks must produce identical AssignStmt nodes.'
}

# 3. Mixed form in same block
$mixedBlockAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
navbar is a row
    justify "space-between"
    alignitems is "center"
    spacing 16
    width is "100%"
.
'@)
if ($mixedBlockAst.Statements[0].Properties.Count -ne 4 -or
    $mixedBlockAst.Statements[0].Properties[0].Target.Name -ne 'justify' -or
    $mixedBlockAst.Statements[0].Properties[1].Target.Name -ne 'alignitems' -or
    $mixedBlockAst.Statements[0].Properties[2].Target.Name -ne 'spacing' -or
    $mixedBlockAst.Statements[0].Properties[3].Target.Name -ne 'width') {
    throw 'Mixed compact and explicit is in multi-line block must parse all properties.'
}

# 4. Expressions, arithmetic, strings, booleans inside multi-line blocks
$exprBlockAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
cart is a thing
    total price plus tax
    label "Special Offer"
    active true
.
'@)
if ($exprBlockAst.Statements[0].Properties[0].Value -isnot [MathExpr] -or $exprBlockAst.Statements[0].Properties[0].Value.Op -ne [MathOp]::Add) {
    throw 'Arithmetic expressions must parse inside compact multi-line blocks.'
}
if ($exprBlockAst.Statements[0].Properties[1].Value.Value -ne 'Special Offer') {
    throw 'Strings must parse inside compact multi-line blocks.'
}
if ($exprBlockAst.Statements[0].Properties[2].Value.Value -ne $true) {
    throw 'Booleans must parse inside compact multi-line blocks.'
}

# 5. Bare properties are boolean flags (D54), including otherwise-valued names.
$bareWidthAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
card is a card
    width
.
'@)
if ($bareWidthAst.Statements[0].Properties[0].Value.Value -ne $true) { throw 'Bare properties in a multi-line block must desugar to true.' }

# 6. Disallowed statements inside object block
# 6a. Disallowed say
$caughtSayInBlock = $false
try {
    [void](ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
card is a card
    say "invalid"
.
'@))
} catch {
    $caughtSayInBlock = $true
}
if (-not $caughtSayInBlock) { throw 'Expected error for say inside object block.' }

# 6b. Disallowed if
$caughtIfInBlock = $false
try {
    [void](ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
card is a card
    if active
        width 100
    .
.
'@))
} catch {
    $caughtIfInBlock = $true
}
if (-not $caughtIfInBlock) { throw 'Expected error for if inside object block.' }

# 6c. Disallowed while loop
$caughtWhileInBlock = $false
try {
    [void](ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
card is a card
    while true
        width 100
    .
.
'@))
} catch {
    $caughtWhileInBlock = $true
}
if (-not $caughtWhileInBlock) { throw 'Expected error for while inside object block.' }

# 7. Top-level assignment STILL requires 'is'
$topLevelNoIsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "foo `"bar`"`n")
if ($topLevelNoIsAst.Statements[0] -isnot [CallStmt]) {
    throw 'Top-level statements without is must remain function calls, never assignments.'
}
$topLevelWithIsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "foo is `"bar`"`n")
if ($topLevelWithIsAst.Statements[0] -isnot [AssignStmt]) {
    throw 'Top-level assignment requires is.'
}

# ===============================================================
# Flag properties (round, spread) and width full
# ===============================================================

# 1. Bare flag property in multiline block
$flagBlockAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
btn is a button
    text "Submit"
    round
    padding 10
.
'@)
if ($flagBlockAst.Statements[0].Properties[1].Target.Name -ne 'round' -or $flagBlockAst.Statements[0].Properties[1].Value.Value -ne $true) {
    throw 'Expected bare flag property in block to evaluate to literal true.'
}

# 2. Bare flag property inline with `with`
$flagInlineAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "pill is a badge with round, padding 6`n")
if ($flagInlineAst.Statements[0].Properties[0].Target.Name -ne 'round' -or $flagInlineAst.Statements[0].Properties[0].Value.Value -ne $true) {
    throw 'Expected bare flag property inline to evaluate to literal true.'
}
$bareBooleanAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "thing has enabled, visible`n")
if ($bareBooleanAst.Statements[0].Properties[0].Target.Name -ne 'enabled' -or $bareBooleanAst.Statements[0].Properties[0].Value.Value -ne $true -or $bareBooleanAst.Statements[0].Properties[1].Value.Value -ne $true) {
    throw 'Bare inline has properties must desugar to true.'
}
$bareBooleanBlockAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @'
thing has
    enabled
    visible
.
'@)
if ($bareBooleanBlockAst.Statements[0].Properties[0].Value.Value -ne $true -or $bareBooleanBlockAst.Statements[0].Properties[1].Value.Value -ne $true) {
    throw 'Bare block has properties must desugar to true.'
}

# 3. width full and height full parse as contextual LiteralExpr('full')
$widthFullAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "bar is a row with width full, height full`n")
if ($widthFullAst.Statements[0].Properties[0].Target.Name -ne 'width' -or 
    $widthFullAst.Statements[0].Properties[0].Value -isnot [LiteralExpr] -or 
    $widthFullAst.Statements[0].Properties[0].Value.Value -ne 'full') {
    throw 'Expected width full to parse as property width with literal full.'
}
if ($widthFullAst.Statements[0].Properties[1].Target.Name -ne 'height' -or 
    $widthFullAst.Statements[0].Properties[1].Value -isnot [LiteralExpr] -or 
    $widthFullAst.Statements[0].Properties[1].Value.Value -ne 'full') {
    throw 'Expected height full to parse as property height with literal full.'
}

# 4. Ordinary variable named full behaves normally outside dimension position
$varFullAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "full is 500`nsay full`n")
if ($varFullAst.Statements[0] -isnot [AssignStmt] -or $varFullAst.Statements[0].Target.Name -ne 'full' -or $varFullAst.Statements[0].Value.Value -ne 500) {
    throw 'Variable full must remain ordinary assignment.'
}
if ($varFullAst.Statements[1] -isnot [SayStmt] -or $varFullAst.Statements[1].Parts[0] -isnot [VariableExpr] -or $varFullAst.Statements[1].Parts[0].Name -ne 'full') {
    throw 'Saying full must remain ordinary variable reference.'
}

# 5. Numeric width and height remain unchanged
$numWidthAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "bar is a row with width 400, height 300`n")
if ($numWidthAst.Statements[0].Properties[0].Value.Value -ne 400 -or $numWidthAst.Statements[0].Properties[1].Value.Value -ne 300) {
    throw 'Numeric width and height must remain ordinary numbers.'
}

# 6. align preserves the provider-neutral property name and literal direction
$alignAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source "nav is a row with spread, align middle`n")
$navProps = $alignAst.Statements[0].Properties
if ($navProps[0].Target.Name -ne 'spread' -or $navProps[0].Value.Value -ne $true) {
    throw 'Expected spread flag to parse as boolean true.'
}
if ($navProps[1].Target.Name -ne 'align' -or $navProps[1].Value.Value -ne 'middle') {
    throw 'Expected align middle to remain align with a literal direction.'
}

# 7. Multiline align top and align center
$multiAlignAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @"
panel is a column
    align top
    align center
.
"@)
$panelProps = $multiAlignAst.Statements[0].Properties
if ($panelProps[0].Target.Name -ne 'align' -or $panelProps[0].Value.Value -ne 'top') {
    throw 'Expected align top to remain align with a literal direction.'
}
if ($panelProps[1].Target.Name -ne 'align' -or $panelProps[1].Value.Value -ne 'center') {
    throw 'Expected align center to remain align with a literal direction.'
}

# 8. Every physical direction remains plain align, even when the resource is
# created separately and its type is unavailable to the parser.
$directionSource = @'
create row into toolbar
toolbar has align "top"
create column into sidebar
sidebar has align "middle"
row has align "bottom"
column has align "left"
panel has align "center"
stack has align "right"
'@
$directionAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $directionSource)
foreach ($index in 1, 3, 4, 5, 6, 7) {
    $props = $directionAst.Statements[$index].Properties
    if ($props[0].Target.Name -ne 'align') { throw 'All directions must preserve the align property name.' }
}

# 11. Ordinary variables named top, bottom, left, right behave normally
$dirVarsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @"
top is 100
left is 50
say top
say left
"@)
if ($dirVarsAst.Statements[0].Target.Name -ne 'top' -or $dirVarsAst.Statements[0].Value.Value -ne 100) {
    throw 'Variable top must remain ordinary assignment.'
}
if ($dirVarsAst.Statements[1].Target.Name -ne 'left' -or $dirVarsAst.Statements[1].Value.Value -ne 50) {
    throw 'Variable left must remain ordinary assignment.'
}

# 12. Improved error diagnostics and suggestions for inline property lists
$missingCommaCaught = $false
try {
    ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'b is a badge with text "JM" weight 700')
} catch [OtterError] {
    $missingCommaCaught = $true
    if ($_.Exception.Message -notlike "*I expected a comma between properties in this inline list, but found 'weight'*") {
        throw "Expected missing-comma diagnostic, got: $($_.Exception.Message)"
    }
    if ($_.Exception.Suggestion -notlike "*Separate each property with a comma*") {
        throw "Expected comma-separation suggestion, got: $($_.Exception.Suggestion)"
    }
}
if (-not $missingCommaCaught) { throw 'Expected missing comma in inline properties to fail.' }

# 13. Missing comma after boolean flag
$missingCommaFlagCaught = $false
try {
    ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'b is a badge with round weight 700')
} catch [OtterError] {
    $missingCommaFlagCaught = $true
    if ($_.Exception.Message -notlike "*I expected a comma between properties in this inline list, but found 'weight'*") {
        throw "Expected missing-comma diagnostic after flag, got: $($_.Exception.Message)"
    }
}
if (-not $missingCommaFlagCaught) { throw 'Expected missing comma after flag to fail.' }

# 14. Multiple properties on single block line
$multiPropLineCaught = $false
try {
    ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @"
c is a card
    width full height full
.
"@)
} catch [OtterError] {
    $multiPropLineCaught = $true
    if ($_.Exception.Message -notlike "*I expected each property on its own line, but found 'height' on the same line*") {
        throw "Expected multi-prop line diagnostic, got: $($_.Exception.Message)"
    }
    if ($_.Exception.Suggestion -notlike "*Place 'height' on a new indented line*") {
        throw "Expected multi-prop suggestion, got: $($_.Exception.Suggestion)"
    }
}
if (-not $multiPropLineCaught) { throw 'Expected multiple properties on one line in block to fail.' }

# 15. Bare property in inline properties is boolean true (D54)
$bareInlineValueAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'b is a badge with text, weight 700')
if ($bareInlineValueAst.Statements[0].Properties[0].Value.Value -ne $true -or $bareInlineValueAst.Statements[0].Properties[1].Value.Value -ne 700) {
    throw 'Bare inline properties must desugar to true while valued properties remain unchanged.'
}

# 16. Optional 'is' in when statement (D55)
$whenWithoutIsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @"
when addButton clicked
    say "Clicked"
.
"@)
$whenWithIsAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @"
when addButton is clicked
    say "Clicked"
.
"@)
if ($whenWithoutIsAst.Statements[0].EventName -ne 'clicked' -or $whenWithIsAst.Statements[0].EventName -ne 'clicked') {
    throw 'Both forms of when statement must parse the same event name.'
}

# 17. Declarative UI & Layout (D56)
$uiSource = @"
window "My App"
    heading "Welcome"
    text "Hello from Otter"
    primary button "Continue"
.
page
    layout split
    stack on small

    section
        layout cards
        gap 20
        card
            heading "Product One"
        .
    .
.
"@
$uiAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $uiSource)
if ($uiAst.Statements.Count -ne 2) { throw "Expected 2 UI elements, got $($uiAst.Statements.Count)" }
if ($uiAst.Statements[0].Tag -ne 'window' -or $uiAst.Statements[0].Children.Count -ne 3) { throw "Expected window with 3 children." }
if ($uiAst.Statements[0].Children[2].Variant -ne 'primary' -or $uiAst.Statements[0].Children[2].Tag -ne 'button') { throw "Expected primary button." }
if ($uiAst.Statements[1].Layout.Mode -ne 'split' -or $uiAst.Statements[1].Layout.Responsive.Count -ne 1) { throw "Expected layout split with responsive rule." }

# 18. Reactive State, Derive, Memo, Watch, Lifecycle (D56)
$reactiveSource = @"
state count is 0
derive doubled is count * 2
memo sortedItems
    return items
.
when count changes
    say count
.
on start
    say "Starting"
.
"@
$reactiveAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $reactiveSource)
if ($reactiveAst.Statements[0] -isnot [StateDefStmt] -or $reactiveAst.Statements[0].Name -ne 'count') { throw "Expected StateDefStmt." }
if ($reactiveAst.Statements[1] -isnot [DeriveDefStmt] -or $reactiveAst.Statements[1].Name -ne 'doubled') { throw "Expected DeriveDefStmt." }
if ($reactiveAst.Statements[2] -isnot [MemoDefStmt] -or $reactiveAst.Statements[2].Name -ne 'sortedItems') { throw "Expected MemoDefStmt." }
if ($reactiveAst.Statements[3] -isnot [WatchStmt] -or $reactiveAst.Statements[3].TargetName -ne 'count') { throw "Expected WatchStmt." }
if ($reactiveAst.Statements[4] -isnot [LifecycleStmt] -or $reactiveAst.Statements[4].Stage -ne 'start') { throw "Expected LifecycleStmt." }

# 19. First-Class Animation Blocks (D56)
$animSource = @"
card
    enter
        fade in
        move up 20
        animate 300ms ease-out
    .
    leave
        fade out
        shrink 0.95
        animate 200ms
    .
    primary button "Save"
        hover
            grow 1.05
            animate 150ms
        .
        click
            count is count + 1
        .
    .
.
"@
$animAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $animSource)
if ($animAst.Statements[0].Animations.Count -ne 2) { throw "Expected 2 animations on card." }
$enterAnim = $animAst.Statements[0].Animations[0]
if ($enterAnim.Trigger -ne 'enter' -or $enterAnim.DurationMs -ne 300.0 -or $enterAnim.Easing -ne 'ease-out') { throw "Expected enter animation with 300ms ease-out." }
if ($enterAnim.Steps.Count -ne 2 -or $enterAnim.Steps[0].Operation -ne 'fade' -or $enterAnim.Steps[0].Direction -ne 'in') { throw "Expected fade in step." }
$btn = $animAst.Statements[0].Children[0]
if ($btn.Animations.Count -ne 1 -or $btn.Animations[0].Trigger -ne 'hover') { throw "Expected hover animation on button." }
if ($btn.Events.Count -ne 1 -or $btn.Events[0].EventName -ne 'click') { throw "Expected click event on button." }

# 20. Async / Await, Shared State, UI Action, Modules (D56)
$asyncSource = @"
shared theme is "dark"
use ui
to loadProducts
    products is await get "/api/products"
.
focus searchBox
hide sidebar
"@
$asyncAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $asyncSource)
if ($asyncAst.Statements[0] -isnot [SharedStateStmt] -or $asyncAst.Statements[0].Name -ne 'theme') { throw "Expected SharedStateStmt." }
if ($asyncAst.Statements[1] -isnot [UseModuleStmt] -or $asyncAst.Statements[1].Module -ne 'ui') { throw "Expected UseModuleStmt." }
if ($asyncAst.Statements[2].Body[0].Value -isnot [AwaitExpr]) { throw "Expected AwaitExpr." }
if ($asyncAst.Statements[3] -isnot [UiActionStmt] -or $asyncAst.Statements[3].Action -ne 'focus') { throw "Expected focus action." }
if ($asyncAst.Statements[4] -isnot [UiActionStmt] -or $asyncAst.Statements[4].Action -ne 'hide') { throw "Expected hide action." }

# 21. Section 29 Acceptance Program Parses Completely
$acceptanceSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\examples\experimental\counter.ot'))
$acceptanceAst = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $acceptanceSource)
if ($acceptanceAst.Statements.Count -ne 6) { throw "Expected 6 statements in acceptance program, got $($acceptanceAst.Statements.Count)." }

# 22. Quality Diagnostic for '=' assignment
$diagEqCaught = $false
try {
    ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'state count = 0')
} catch [OtterError] {
    $diagEqCaught = $true
    if ($_.Exception.Message -notlike "*Otter does not use '=' to assign values*") {
        throw "Expected '=' diagnostic, got: $($_.Exception.Message)"
    }
    if ($_.Exception.Suggestion -notlike "*state count is 0*") {
        throw "Expected 'state count is 0' suggestion, got: $($_.Exception.Suggestion)"
    }
}
if (-not $diagEqCaught) { throw "Expected '=' assignment to fail with diagnostic." }

# 23. Quality Diagnostic for invalid animation duration/easing
$diagAnimCaught = $false
try {
    ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source @"
button "Save"
    hover
        animate fast
    .
.
"@)
} catch [OtterError] {
    $diagAnimCaught = $true
    if ($_.Exception.Message -notlike "*Otter expected a duration*after 'animate'*") {
        throw "Expected invalid animate diagnostic, got: $($_.Exception.Message)"
    }
}
if (-not $diagAnimCaught) { throw "Expected 'animate fast' to fail with diagnostic." }

Write-Output 'Parser tests passed.'
