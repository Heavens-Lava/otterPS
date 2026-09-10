using module ..\Otter.Contract.psm1
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Parser.psm1') -Force
$source = @'
if name ends with "Macy"
    say "Ends"
'@
foreach ($token in (ConvertTo-OtterTokens -Source $source)) { Write-Output "$($token.Kind) [$($token.Text)]" }
$program = ConvertTo-OtterAst -Tokens (ConvertTo-OtterTokens -Source $source)
Write-Output $program.Statements[0].Branches[0].Condition.Kind
