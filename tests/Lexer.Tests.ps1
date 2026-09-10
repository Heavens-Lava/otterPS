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
try {
    ConvertTo-OtterTokens -Source 'say person.name' | Out-Null
    throw 'Expected property access with a period to fail.'
}
catch [OtterError] {
    if ($_.Exception.Message -notlike '*does not use periods*' -or $_.Exception.Suggestion -notlike '*name of person*') {
        throw 'Period property errors should explain the property-first syntax.'
    }
}
$part3Tokens = ConvertTo-OtterTokens -Source 'get files in "Pictures" and subfolders into files'
if ((@($part3Tokens | ForEach-Object Kind) -join ',') -ne 'Get,Files,In,String,And,Subfolders,Into,Files,Newline,EndOfFile') {
    throw 'Expected discovery keywords to have their dedicated tokens.'
}
$goneTokens = ConvertTo-OtterTokens -Source 'user is gone'
if ($goneTokens[2].Kind -ne [TokenKind]::Gone) { throw 'Gone must be a literal token.' }
$operationTokens = ConvertTo-OtterTokens -Source 'length of files'
if ((@($operationTokens | ForEach-Object Kind) -join ',') -ne 'Length,Of,Files,Newline,EndOfFile') { throw 'Length must become an operation only before of.' }
$identifierTokens = ConvertTo-OtterTokens -Source 'first is "Jeff"'
if ($identifierTokens[0].Kind -ne [TokenKind]::Identifier) { throw 'First must remain an ordinary identifier outside an operation.' }
$startsTokens = ConvertTo-OtterTokens -Source 'if name starts with "J"'
if ($startsTokens[2].Kind -ne [TokenKind]::StartsWith) { throw 'Starts with must be one token.' }
$endsTokens = ConvertTo-OtterTokens -Source 'if name ends with "Macy"'
if ($endsTokens[2].Kind -ne [TokenKind]::EndsWith) { throw 'Ends with must be one token.' }

# D49 HTTP tests
$postTokens = ConvertTo-OtterTokens -Source 'post user to "https://example.com" into response'
if ((@($postTokens | ForEach-Object Kind) -join ',') -ne 'Post,Identifier,To,String,Into,Identifier,Newline,EndOfFile') {
    throw 'Post at statement head must emit TokenKind::Post.'
}
$postIdentTokens = ConvertTo-OtterTokens -Source 'say post'
if ($postIdentTokens[1].Kind -ne [TokenKind]::Identifier) {
    throw 'Post outside statement head must remain an ordinary identifier.'
}
$getJsonTokens = ConvertTo-OtterTokens -Source 'get json from "https://example.com" into data'
if ((@($getJsonTokens | ForEach-Object Kind) -join ',') -ne 'Get,Json,From,String,Into,Identifier,Newline,EndOfFile') {
    throw 'Json after get must emit TokenKind::Json.'
}

# D51 Web Server tests
$routeTokens = ConvertTo-OtterTokens -Source 'when api receives GET at "/users"'
if ((@($routeTokens | ForEach-Object Kind) -join ',') -ne 'When,Identifier,Receives,Identifier,At,String,Newline,EndOfFile') {
    throw 'Expected when/receives/at route tokens.'
}
$respondTokens = ConvertTo-OtterTokens -Source 'respond with "hello" as json and status 200'
if ((@($respondTokens | ForEach-Object Kind) -join ',') -ne 'Respond,With,String,As,Json,And,Identifier,Number,Newline,EndOfFile') {
    throw 'Expected respond with tokens.'
}
$startTokens = ConvertTo-OtterTokens -Source 'start api'
if ($startTokens[0].Kind -ne [TokenKind]::Start) { throw 'Start at statement head must emit TokenKind::Start.' }
$listenTokens = ConvertTo-OtterTokens -Source 'listen on port 8080'
if ($listenTokens[0].Kind -ne [TokenKind]::Listen) { throw 'Listen at statement head must emit TokenKind::Listen.' }

Write-Output 'Lexer tests passed.'
