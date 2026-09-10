using module ..\Otter.Contract.psm1
Import-Module (Join-Path $PSScriptRoot '..\src\Otter.Lexer.psm1') -Force

$tokens = ConvertTo-OtterTokens -Source "say `"Hello`"`nname is `"Jeff`"`nif age is at least 18`n`tsay age"
$kinds = @($tokens | ForEach-Object Kind)
$expected = @('Say','String','Newline','Identifier','Is','String','Newline','If','Identifier','IsAtLeast','Number','Newline','Indent','Say','Identifier','Newline','Dedent','EndOfFile')
if (($kinds -join ',') -ne ($expected -join ',')) { throw "Unexpected token kinds: $($kinds -join ',')" }
if ($tokens[1].Value -ne 'Hello') { throw 'String values should not include quotes.' }
if ($tokens[-1].Kind -ne [TokenKind]::EndOfFile) { throw 'The token stream must end with EndOfFile.' }

$mathTokens = ConvertTo-OtterTokens -Source '10 divided by 5 makes answer'
$mathKinds = @($mathTokens | ForEach-Object Kind)
if (($mathKinds -join ',') -ne 'Number,DividedBy,Number,Make,Identifier,Newline,EndOfFile') {
    throw "Unexpected math token kinds: $($mathKinds -join ',')"
}
$reservedTokens = ConvertTo-OtterTokens -Source 'read "notes.txt" into notes'
if ((@($reservedTokens | ForEach-Object Kind) -join ',') -ne 'Read,String,Into,Identifier,Newline,EndOfFile') {
    throw 'Deferred language keywords must remain reserved.'
}
Write-Output 'Lexer tests passed.'
