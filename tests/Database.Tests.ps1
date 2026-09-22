using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Database.psm1

# tests/Database.Tests.ps1
#
# Comprehensive test suite for D97: Database Provider Architecture & SQLite Reference Provider.

$ErrorActionPreference = 'Stop'

# This file captures another otter.ps1 process's stdout via `&` (see
# Invoke-OtterSource below). PowerShell 5.1 decodes a captured external
# process's output using the CALLING process's own [Console]::OutputEncoding,
# not the child's - so even though otter.ps1 now writes real UTF-8 bytes,
# this process must also expect UTF-8 or the Unicode round-trip test below
# corrupts on the way back in. (Isolated by comparing raw UTF-16 code points
# on both sides, independent of terminal display, which mangles either way
# on a non-UTF-8 console code page such as the Windows default of 437.)
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # A non-interactive/redirected host may refuse this - not fatal here
    # either, for the same reason it isn't fatal in otter.ps1.
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "Assertion failed ($Message): expected '$Expected', but got '$Actual'."
    }
}

function Invoke-OtterSource {
    param([string]$Source)
    $tmpFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "otter_test_$([System.Guid]::NewGuid().ToString('N')).ot")
    try {
        [System.IO.File]::WriteAllText($tmpFile, $Source, [System.Text.Encoding]::UTF8)
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\otter.ps1') $tmpFile
        $lines = @()
        if ($null -ne $output) {
            foreach ($line in $output) { $lines += [string]$line }
        }
        Write-Output -NoEnumerate $lines
    } finally {
        if ([System.IO.File]::Exists($tmpFile)) {
            [System.IO.File]::Delete($tmpFile)
        }
    }
}

# -----------------------------------------------------------------------------
# 1. Provider contract & capability registry
# -----------------------------------------------------------------------------
$provider = Get-OtterDatabaseProvider -Name "sqlite"
Assert-True ($null -ne $provider) "Get-OtterDatabaseProvider returned null"
Assert-Equal $provider.Name "sqlite" "Provider name should be sqlite"

$caps = $provider.GetCapabilities()
Assert-True ($caps.SupportsTransactions) "SQLite provider must support transactions"
Assert-True ($caps.SupportsLastInsertedId) "SQLite provider must support last inserted id"

# Requesting unknown provider throws clean OtterError
$unknownFailed = $false
try {
    Get-OtterDatabaseProvider -Name "nonexistent_db"
} catch [OtterError] {
    $unknownFailed = $true
    Assert-True ($_.Exception.Message -like '*I do not know a database provider called "nonexistent_db"*') "Unknown provider error message"
}
Assert-True $unknownFailed "Expected unknown provider to throw OtterError"

# -----------------------------------------------------------------------------
# 2. Connection lifecycle (memory and file)
# -----------------------------------------------------------------------------
$memConfig = @{ provider = 'sqlite'; connection = ':memory:' }
$memConn = $provider.OpenConnection($memConfig, 1)
Assert-True $memConn.IsOpen "Memory connection should be open"
$provider.CloseConnection($memConn, 1)
Assert-True (-not $memConn.IsOpen) "Memory connection should be closed after CloseConnection"

# Operating on closed connection throws
$closedQueryFailed = $false
try {
    $provider.ExecuteQuery($memConn, "SELECT 1", @{}, 1)
} catch [OtterError] {
    $closedQueryFailed = $true
    Assert-True ($_.Exception.Message -like '*closed*') "Query on closed connection should mention closed"
}
Assert-True $closedQueryFailed "Expected query on closed connection to fail"

# Duplicate close throws clean error
$duplicateCloseFailed = $false
try {
    $provider.CloseConnection($memConn, 1)
} catch [OtterError] {
    $duplicateCloseFailed = $true
    Assert-True ($_.Exception.Message -like '*already closed*') "Duplicate close error message"
}
Assert-True $duplicateCloseFailed "Expected duplicate close to fail"

# Missing database folder throws
$missingFolderFailed = $false
try {
    $provider.OpenConnection(@{ provider = 'sqlite'; connection = 'Z:\non_existent_folder_9999\db.sqlite' }, 1)
} catch [OtterError] {
    $missingFolderFailed = $true
    Assert-True ($_.Exception.Message -like '*does not exist*') "Missing folder error message"
}
Assert-True $missingFolderFailed "Expected missing folder to fail"

# File database creation and persistence
$tempDbPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "otter_test_$([System.Guid]::NewGuid().ToString('N')).db")
try {
    $fileConn = $provider.OpenConnection(@{ provider = 'sqlite'; connection = $tempDbPath }, 1)
    Assert-True ([System.IO.File]::Exists($tempDbPath)) "Database file should be created on disk"
    $provider.ExecuteCommand($fileConn, "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT)", @{}, 1) | Out-Null
    $provider.CloseConnection($fileConn, 1)

    # Re-open and verify table exists
    $fileConn2 = $provider.OpenConnection(@{ provider = 'sqlite'; connection = $tempDbPath }, 1)
    $fileRows = $provider.ExecuteQuery($fileConn2, "SELECT count(*) as c FROM items", @{}, 1)
    Assert-Equal ($fileRows[0].ReadProperty('c')) 0 "Table should exist in re-opened database"
    $provider.CloseConnection($fileConn2, 1)
} finally {
    if ([System.IO.File]::Exists($tempDbPath)) {
        [System.IO.File]::Delete($tempDbPath)
    }
}

# -----------------------------------------------------------------------------
# 3. SELECT, INSERT, UPDATE, DELETE & Result Properties through Otter Script
# -----------------------------------------------------------------------------
$script1 = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db

execute db with
    "create table users (id integer primary key autoincrement, name text, email text, age integer, bio text)"

execute db with
    "insert into users (name, email, age, bio) values (@name, @email, @age, @bio)"
    parameter "name" is "Alice"
    parameter "email" is "alice@example.com"
    parameter "age" is 30
    parameter "bio" is "Engineer"
into r1

say rows affected of r1
say last inserted id of r1

execute db with
    "insert into users (name, email, age, bio) values (@name, @email, @age, @bio)"
    parameter "name" is "Bob"
    parameter "email" is "bob@example.com"
    parameter "age" is 25
    parameter "bio" is gone
into r2

say last inserted id of r2

query db with
    "select id, name, email, age, bio from users order by id"
into users

each u in users
    say name of u
    say age of u
    if bio of u is gone
        say "no bio"
    otherwise
        say bio of u
    .
.

execute db with
    "update users set age = 31 where name = @name"
    parameter "name" is "Alice"
into updateRes

say rows affected of updateRes

execute db with
    "delete from users where name = @name"
    parameter "name" is "Bob"
into delRes

say rows affected of delRes

query db with "select count(*) as remaining from users" into remainingList
each r in remainingList
    say remaining of r
.

disconnect db
'@

$out1 = Invoke-OtterSource $script1

$expectedLines = @(
    '1',            # rows affected of r1
    '1',            # last inserted id of r1
    '2',            # last inserted id of r2
    'Alice',        # name of u
    '30',           # age of u
    'Engineer',     # bio of u
    'Bob',          # name of u
    '25',           # age of u
    'no bio',       # if bio of u is gone
    '1',            # rows affected of updateRes
    '1',            # rows affected of delRes
    '1'             # remaining of r
)

Assert-Equal ($out1.Count) ($expectedLines.Count) "Output line count for CRUD script"
for ($i = 0; $i -lt $expectedLines.Count; $i++) {
    Assert-Equal ($out1[$i].Trim()) ($expectedLines[$i]) "Line $i of CRUD script output"
}

# -----------------------------------------------------------------------------
# 4. SQL Injection Resistance & Parameter Isolation
# -----------------------------------------------------------------------------
$scriptInjection = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
execute db with "create table secret_records (id integer primary key, secret text)"
execute db with "insert into secret_records (secret) values ('Alpha')"
execute db with "insert into secret_records (secret) values ('Beta')"

injectionPayload is "' OR '1'='1"

query db with
    "select secret from secret_records where secret = @search"
    parameter "search" is injectionPayload
into matchedRecords

say length of matchedRecords
disconnect db
'@

$outInj = Invoke-OtterSource $scriptInjection
Assert-Equal ($outInj[0].Trim()) '0' "SQL injection payload should match 0 records"

# -----------------------------------------------------------------------------
# 5. Unicode / Text Encoding Round-Trip
# -----------------------------------------------------------------------------
$scriptUnicode = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
execute db with "create table notes (id integer, content text)"

unicodeText is "Hello 世界! 🦦 'single' and \"double\" and `backticks`"

execute db with
    "insert into notes (id, content) values (1, @content)"
    parameter "content" is unicodeText

query db with "select content from notes where id = 1" into rows
each r in rows
    say content of r
.
disconnect db
'@

$outUni = Invoke-OtterSource $scriptUnicode
Assert-Equal ($outUni[0].Trim()) "Hello 世界! 🦦 'single' and `"double`" and ``backticks``" "Unicode content round-trip"

# -----------------------------------------------------------------------------
# 6. Empty Result Sets & Multiple Rows
# -----------------------------------------------------------------------------
$scriptMulti = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
execute db with "create table nums (n integer)"

query db with "select n from nums" into emptyList
say length of emptyList

count from 1 to 5 as i
    execute db with
        "insert into nums (n) values (@n)"
        parameter "n" is i
.

query db with "select n from nums order by n" into fullList
say length of fullList

each row in fullList
    say n of row
.
disconnect db
'@

$outMulti = Invoke-OtterSource $scriptMulti
Assert-Equal ($outMulti[0].Trim()) '0' "Empty query returns length 0"
Assert-Equal ($outMulti[1].Trim()) '5' "Full query returns length 5"
Assert-Equal ($outMulti[2].Trim()) '1' "Row 1 is 1"
Assert-Equal ($outMulti[6].Trim()) '5' "Row 5 is 5"

# -----------------------------------------------------------------------------
# 7. Transactions: Commit and Rollback
# -----------------------------------------------------------------------------
$scriptTx = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
execute db with "create table ledger (id integer primary key, amount integer)"

begin transaction on db into tx1
execute tx1 with "insert into ledger (amount) values (100)"
execute tx1 with "insert into ledger (amount) values (200)"
commit tx1

query db with "select sum(amount) as total from ledger" into r1
each r in r1
    say total of r
.

begin transaction on db into tx2
execute tx2 with "insert into ledger (amount) values (500)"
rollback tx2

query db with "select count(*) as c from ledger" into r2
each r in r2
    say c of r
.

disconnect db
'@

$outTx = Invoke-OtterSource $scriptTx
Assert-Equal ($outTx[0].Trim()) '300' "Sum of amounts committed is 300"
Assert-Equal ($outTx[1].Trim()) '2' "Count after rollback remains 2"

# -----------------------------------------------------------------------------
# 8. Diagnostics: Invalid SQL, Closed Connection, Secret Masking
# -----------------------------------------------------------------------------
$scriptBadSql = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
query db with "SELECT FROM invalid syntax" into bad
disconnect db
'@

$outBadSql = Invoke-OtterSource $scriptBadSql
Assert-True ($outBadSql -join "`n" -like '*Database query error:*') "Invalid SQL reports clean diagnostic"

$scriptMasking = @'
database has
    provider is "sqlite"
    connection is ":memory:;Password=SuperSecretPass123;"
.
connect database into db
say connection of db
disconnect db
'@

$outMask = Invoke-OtterSource $scriptMasking
Assert-True ($outMask -join "`n" -notlike '*SuperSecretPass123*') "Secret password must not appear in output"
Assert-True ($outMask -join "`n" -like '*Password=****') "Secret password must be masked"

# -----------------------------------------------------------------------------
# 9. Adversarial: Double Commit, Double Rollback, Using Completed Transaction
# -----------------------------------------------------------------------------
$scriptDoubleCommit = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
begin transaction on db into tx
commit tx
commit tx
disconnect db
'@
$outDoubleCommit = Invoke-OtterSource $scriptDoubleCommit
Assert-True ($outDoubleCommit -join "`n" -like '*already been completed*') "Committing twice throws clean error"

$scriptDoubleRollback = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
begin transaction on db into tx
rollback tx
rollback tx
disconnect db
'@
$outDoubleRollback = Invoke-OtterSource $scriptDoubleRollback
Assert-True ($outDoubleRollback -join "`n" -like '*already been completed*') "Rolling back twice throws clean error"

$scriptUseClosedTx = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
begin transaction on db into tx
commit tx
execute tx with "select 1"
disconnect db
'@
$outUseClosedTx = Invoke-OtterSource $scriptUseClosedTx
Assert-True ($outUseClosedTx -join "`n" -like '*already been completed*') "Using completed transaction throws clean error"

# -----------------------------------------------------------------------------
# 10. Connection Close During Active Transaction Automatically Rolls Back
# -----------------------------------------------------------------------------
$tempDbAutoRollback = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "otter_rollback_$([System.Guid]::NewGuid().ToString('N')).db")
try {
    $scriptAutoRollback = @"
database has
    provider is "sqlite"
    connection is "$($tempDbAutoRollback.Replace('\', '/'))"
.
connect database into db
execute db with "create table items (name text)"
execute db with "insert into items (name) values ('Committed Item')"
begin transaction on db into tx
execute tx with "insert into items (name) values ('Uncommitted Item')"
disconnect db
"@
    $null = Invoke-OtterSource $scriptAutoRollback

    # Reconnect and verify uncommitted item was rolled back
    $scriptVerifyRollback = @"
database has
    provider is "sqlite"
    connection is "$($tempDbAutoRollback.Replace('\', '/'))"
.
connect database into db
query db with "select count(*) as c from items" into rows
each r in rows
    say c of r
.
disconnect db
"@
    $outVerify = Invoke-OtterSource $scriptVerifyRollback
    Assert-Equal ($outVerify[0].Trim()) '1' "Uncommitted item in disconnected transaction was automatically rolled back"
} finally {
    if ([System.IO.File]::Exists($tempDbAutoRollback)) {
        [System.IO.File]::Delete($tempDbAutoRollback)
    }
}

# -----------------------------------------------------------------------------
# 11. Database Path Containing Spaces
# -----------------------------------------------------------------------------
$spaceFolder = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "otter test folder $([System.Guid]::NewGuid().ToString('N'))")
[System.IO.Directory]::CreateDirectory($spaceFolder) | Out-Null
$spaceDbPath = [System.IO.Path]::Combine($spaceFolder, "space test.db")
try {
    $scriptSpace = @"
database has
    provider is "sqlite"
    connection is "$($spaceDbPath.Replace('\', '/'))"
.
connect database into db
execute db with "create table greeting (msg text)"
execute db with "insert into greeting (msg) values ('Hello from spaced path')"
query db with "select msg from greeting" into rows
each r in rows
    say msg of r
.
disconnect db
"@
    $outSpace = Invoke-OtterSource $scriptSpace
    Assert-Equal ($outSpace[0].Trim()) 'Hello from spaced path' "Database with spaces in path operates correctly"
} finally {
    if ([System.IO.Directory]::Exists($spaceFolder)) {
        [System.IO.Directory]::Delete($spaceFolder, $true)
    }
}

# -----------------------------------------------------------------------------
# 12. D98: Schema Introspection (Tables, Views, Columns, Keys, Defaults, Safety)
# -----------------------------------------------------------------------------

# 12.1 Empty database returns empty list
$scriptEmptyDb = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
get tables from db into tables
say length of tables
disconnect db
'@
$outEmptyDb = Invoke-OtterSource $scriptEmptyDb
Assert-Equal ($outEmptyDb[0].Trim()) '0' "Empty database has 0 tables"

# 12.2 Tables and Views listing, schema and kind
$scriptTablesViews = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
execute db with "create table users (id integer primary key, name text not null)"
execute db with "create table orders (id integer primary key, user_id integer, total real)"
execute db with "create view active_users as select id, name from users"
get tables from db into tables
each t in tables
    say name of t
    say schema of t
    say kind of t
.
disconnect db
'@
$outTablesViews = Invoke-OtterSource $scriptTablesViews
Assert-Equal $outTablesViews[0].Trim() "active_users" "View active_users listed"
Assert-Equal $outTablesViews[1].Trim() "main" "Schema of view is main"
Assert-Equal $outTablesViews[2].Trim() "view" "Kind of active_users is view"
Assert-Equal $outTablesViews[3].Trim() "orders" "Table orders listed"
Assert-Equal $outTablesViews[4].Trim() "main" "Schema of orders is main"
Assert-Equal $outTablesViews[5].Trim() "table" "Kind of orders is table"
Assert-Equal $outTablesViews[6].Trim() "users" "Table users listed"
Assert-Equal $outTablesViews[7].Trim() "main" "Schema of users is main"
Assert-Equal $outTablesViews[8].Trim() "table" "Kind of users is table"

# 12.3 Column metadata: portable types, database types, nullable, defaults, primary keys
$scriptColumns = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
execute db with "create table products (id integer primary key, title text not null, price real default 9.99, is_active boolean default 1, created_at text default CURRENT_TIMESTAMP, raw_blob blob)"
get columns from "products" in db into cols
each c in cols
    say name of c
    say type of c
    say database type of c
    if nullable of c is true
        say "optional"
    otherwise
        say "required"
    .
    if primary key of c is true
        say "pk"
        say primary key position of c
    otherwise
        say "not pk"
    .
    if default expression of c is not gone
        say default expression of c
    otherwise
        say "no default"
    .
.
disconnect db
'@
$outCols = Invoke-OtterSource $scriptColumns
Assert-Equal $outCols[0].Trim() "id" "Column name id"
Assert-Equal $outCols[1].Trim() "number" "Portable type of id is number"
Assert-Equal ($outCols[2].Trim().ToLowerInvariant()) "integer" "Database type of id is integer"
Assert-Equal $outCols[4].Trim() "pk" "id is primary key"
Assert-Equal $outCols[5].Trim() "1" "id pk position is 1"

Assert-Equal $outCols[7].Trim() "title" "Column name title"
Assert-Equal $outCols[8].Trim() "text" "Portable type of title is text"
Assert-Equal ($outCols[9].Trim().ToLowerInvariant()) "text" "Database type of title is text"
Assert-Equal $outCols[10].Trim() "required" "title is not null (required)"
Assert-Equal $outCols[11].Trim() "not pk" "title is not pk"
Assert-Equal $outCols[12].Trim() "no default" "title has no default"

Assert-Equal $outCols[13].Trim() "price" "Column name price"
Assert-Equal $outCols[14].Trim() "number" "Portable type of price is number"
Assert-Equal ($outCols[15].Trim().ToLowerInvariant()) "real" "Database type of price is real"
Assert-Equal $outCols[18].Trim() "9.99" "price default expression is 9.99"
Assert-True ($outCols -contains "CURRENT_TIMESTAMP") "default expression preserved CURRENT_TIMESTAMP"

# 12.4 Composite Primary Key ordering
$scriptCompositePk = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
execute db with "create table order_items (order_id integer, item_id integer, qty integer, primary key (order_id, item_id))"
get columns from "order_items" in db into cols
each c in cols
    if primary key of c is true
        say name of c
        say primary key position of c
    .
.
disconnect db
'@
$outComposite = Invoke-OtterSource $scriptCompositePk
Assert-Equal $outComposite[0].Trim() "order_id" "First pk column is order_id"
Assert-Equal $outComposite[1].Trim() "1" "order_id position is 1"
Assert-Equal $outComposite[2].Trim() "item_id" "Second pk column is item_id"
Assert-Equal $outComposite[3].Trim() "2" "item_id position is 2"

# 12.5 Passing table object directly into get columns
$scriptTableObject = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
execute db with "create table customers (id integer primary key, name text)"
get tables from db into tables
each t in tables
    get columns from t in db into cols
    each c in cols
        say name of c
    .
.
disconnect db
'@
$outTblObj = Invoke-OtterSource $scriptTableObject
Assert-Equal $outTblObj[0].Trim() "id" "Retrieved id column using table object"
Assert-Equal $outTblObj[1].Trim() "name" "Retrieved name column using table object"

# 12.6 Spaces and Unicode in table names
$scriptSpecialNames = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
execute db with "create table `Order Details` (detail_id integer primary key, info text)"
execute db with "create table `utilisateurs_éventuels` (user_id integer primary key, nom text)"
get tables from db into tables
each t in tables
    say name of t
.
get columns from "Order Details" in db into cols1
say length of cols1
get columns from "utilisateurs_éventuels" in db into cols2
say length of cols2
disconnect db
'@
$outSpecial = Invoke-OtterSource $scriptSpecialNames
Assert-True ($outSpecial -contains "Order Details") "Tables list contains table with spaces"
Assert-True ($outSpecial -contains "utilisateurs_éventuels") "Tables list contains table with unicode"
Assert-True ($outSpecial -contains "2") "Retrieved columns from table with spaces and unicode"

# 12.7 Adversarial: Nonexistent table throws clean Otter diagnostic
$scriptNonexistentTable = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
get columns from "nonexistent_table_99" in db into cols
disconnect db
'@
$outNonexistentTable = Invoke-OtterSource $scriptNonexistentTable
Assert-True ($outNonexistentTable -join "`n" -like '*could not find a table or view called "nonexistent_table_99"*') "Nonexistent table throws clean Otter error"

# 12.8 Adversarial: SQL Injection in table name safely rejected
$scriptTableInjection = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
get columns from "users`; DROP TABLE users; --" in db into cols
disconnect db
'@
$outInjection = Invoke-OtterSource $scriptTableInjection
Assert-True ($outInjection -join "`n" -like '*could not find a table or view*') "Malicious table name safely rejected without executing SQL"

# 12.9 Adversarial: Introspection on closed connection throws clean diagnostic
$scriptClosedIntrospect = @'
database has
    provider is "sqlite"
    connection is ":memory:"
.
connect database into db
disconnect db
get tables from db into tables
'@
$outClosed = Invoke-OtterSource $scriptClosedIntrospect
Assert-True ($outClosed -join "`n" -like '*connection is closed*') "Introspection on closed connection throws clean error"

Write-Output 'Database tests passed.'

