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

try {
    ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source 'double 5 make result') | Out-Null
    throw 'Expected an undefined call to fail.'
}
catch [OtterError] {
    if (-not $_.Exception.SourceLine -or -not $_.Exception.Suggestion) { throw 'Parser errors must include source text and a suggestion.' }
}
Write-Output 'Parser tests passed.'
