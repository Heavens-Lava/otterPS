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
if ($fileAst.Statements[1] -isnot [ReadFileStmt] -or $fileAst.Statements[1].Target -ne 'notes') { throw 'Expected read file statement.' }
if ($fileAst.Statements[2] -isnot [CopyFileStmt] -or $fileAst.Statements[3] -isnot [MoveFileStmt]) { throw 'Expected copy and move statements.' }
if ($fileAst.Statements[4] -isnot [DeleteFileStmt]) { throw 'Expected delete file statement.' }
if ($fileAst.Statements[5].Branches[0].Condition -isnot [FileExistsExpr]) { throw 'Expected file exists condition.' }
if (-not $fileAst.Statements[6].IsCommand -and $fileAst.Statements[7].IsCommand -and $fileAst.Statements[7].ResultTarget -eq 'status') { } else { throw 'Expected run forms to preserve command and capture flags.' }

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
Write-Output 'Parser tests passed.'
