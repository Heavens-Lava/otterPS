using module ..\Otter.Contract.psm1
using module ..\src\Otter.Runtime.psm1
using module ..\src\Otter.Database.psm1

# tests/Query.Tests.ps1
#
# Comprehensive test suite for D99: Otter Query Language (OQL).

$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

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
    $tmpFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "otter_query_test_$([System.Guid]::NewGuid().ToString('N')).ot")
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
# 1. Basic query with projection & ordering
# -----------------------------------------------------------------------------
$basicQuerySrc = @'
config has
    provider is "sqlite"
    connection is ":memory:"
.
connect config into db

execute db with "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, price REAL)"
execute db with "INSERT INTO items (name, price) VALUES ('Pen', 1.50)"
execute db with "INSERT INTO items (name, price) VALUES ('Notebook', 4.00)"
execute db with "INSERT INTO items (name, price) VALUES ('Backpack', 25.00)"

get all from items in db into allItems
say "Count:" length of allItems

get name and price from items in db with
    order by price descending
into sortedItems

each item in sortedItems
    n is name of item
    p is price of item
    say n p
.

disconnect db
'@
$out = Invoke-OtterSource $basicQuerySrc
Assert-True ($out -contains "Count: 3") "All items count is 3"
Assert-True ($out -contains "Backpack 25") "Highest price item is Backpack"
Assert-True ($out -contains "Notebook 4") "Second item is Notebook"
Assert-True ($out -contains "Pen 1.5") "Third item is Pen"

# -----------------------------------------------------------------------------
# 2. Filtering with where clause: comparisons, boolean and/or/not
# -----------------------------------------------------------------------------
$whereQuerySrc = @'
config has
    provider is "sqlite"
    connection is ":memory:"
.
connect config into db

execute db with "CREATE TABLE users (id INTEGER, name TEXT, age INTEGER, active INTEGER)"
execute db with "INSERT INTO users VALUES (1, 'Alice', 30, 1)"
execute db with "INSERT INTO users VALUES (2, 'Bob', 17, 1)"
execute db with "INSERT INTO users VALUES (3, 'Charlie', 45, 0)"
execute db with "INSERT INTO users VALUES (4, 'David', 15, 0)"

minAge is 18
get all from users in db with
    where age is at least minAge and active is 1
into adultActives

say "Adult actives count:" length of adultActives
each u in adultActives
    n is name of u
    say "Active adult:" n
.

get all from users in db with
    where age is less than 18 or active is 0
    order by id ascending
into others

say "Others count:" length of others

disconnect db
'@
$out = Invoke-OtterSource $whereQuerySrc
Assert-True ($out -contains "Adult actives count: 1") "One adult active user"
Assert-True ($out -contains "Active adult: Alice") "Active adult is Alice"
Assert-True ($out -contains "Others count: 3") "Others count is 3"

# -----------------------------------------------------------------------------
# 3. Pattern matching with 'contains' and list membership with 'is in'
# -----------------------------------------------------------------------------
$likeInSrc = @'
config has
    provider is "sqlite"
    connection is ":memory:"
.
connect config into db

execute db with "CREATE TABLE products (sku TEXT, name TEXT, category TEXT)"
execute db with "INSERT INTO products VALUES ('A1', 'Apple Crisp', 'Snacks')"
execute db with "INSERT INTO products VALUES ('A2', 'Pineapple Juice', 'Beverages')"
execute db with "INSERT INTO products VALUES ('B1', 'Banana Bread', 'Bakery')"
execute db with "INSERT INTO products VALUES ('B2', 'Orange Soda', 'Beverages')"

term is "Apple"
get all from products in db with
    where name contains term
    order by sku ascending
into appleProducts

say "Apple products:" length of appleProducts
each p in appleProducts
    n is name of p
    say "Match:" n
.

targetCats are
    "Snacks"
    "Bakery"
.

get all from products in db with
    where category is in targetCats
    order by sku ascending
into catProducts

say "Cat products:" length of catProducts
each p in catProducts
    s is sku of p
    say "Cat item:" s
.

disconnect db
'@
$out = Invoke-OtterSource $likeInSrc
Assert-True ($out -contains "Apple products: 2") "Found 2 apple products"
Assert-True ($out -contains "Match: Apple Crisp") "Found Apple Crisp"
Assert-True ($out -contains "Match: Pineapple Juice") "Found Pineapple Juice"
Assert-True ($out -contains "Cat products: 2") "Found 2 category items in targetCats"
Assert-True ($out -contains "Cat item: A1") "Cat item A1 found"
Assert-True ($out -contains "Cat item: B1") "Cat item B1 found"

# -----------------------------------------------------------------------------
# 4. Limit and Offset pagination
# -----------------------------------------------------------------------------
$pagingSrc = @'
config has
    provider is "sqlite"
    connection is ":memory:"
.
connect config into db

execute db with "CREATE TABLE num_seq (val INTEGER)"
execute db with "INSERT INTO num_seq VALUES (1),(2),(3),(4),(5),(6),(7),(8),(9),(10)"

pageSize is 3
pageOffset is 3

get all from num_seq in db with
    order by val ascending
    limit pageSize
    offset pageOffset
into page2

say "Page 2 count:" length of page2
each row in page2
    v is val of row
    say "Val:" v
.

disconnect db
'@
$out = Invoke-OtterSource $pagingSrc
Assert-True ($out -contains "Page 2 count: 3") "Page 2 has 3 items"
Assert-True ($out -contains "Val: 4") "Val 4 present"
Assert-True ($out -contains "Val: 5") "Val 5 present"
Assert-True ($out -contains "Val: 6") "Val 6 present"

# -----------------------------------------------------------------------------
# 5. Null handling: is gone and is not gone
# -----------------------------------------------------------------------------
$nullCheckSrc = @'
config has
    provider is "sqlite"
    connection is ":memory:"
.
connect config into db

execute db with "CREATE TABLE tasks (id INTEGER, title TEXT, due_date TEXT)"
execute db with "INSERT INTO tasks VALUES (1, 'Call mom', NULL)"
execute db with "INSERT INTO tasks VALUES (2, 'Pay taxes', '2026-04-15')"
execute db with "INSERT INTO tasks VALUES (3, 'Clean desk', NULL)"

get all from tasks in db with
    where due_date is gone
into unscheduled

say "Unscheduled:" length of unscheduled

get all from tasks in db with
    where due_date is not gone
into scheduled

say "Scheduled:" length of scheduled
firstTask is first of scheduled
taskTitle is title of firstTask
say "Scheduled title:" taskTitle

disconnect db
'@
$out = Invoke-OtterSource $nullCheckSrc
Assert-True ($out -contains "Unscheduled: 2") "2 unscheduled tasks"
Assert-True ($out -contains "Scheduled: 1") "1 scheduled task"
Assert-True ($out -contains "Scheduled title: Pay taxes") "Scheduled task is Pay taxes"

# -----------------------------------------------------------------------------
# 6. Aggregate Queries: count, sum, total, average, minimum, maximum
# -----------------------------------------------------------------------------
$aggSrc = @'
config has
    provider is "sqlite"
    connection is ":memory:"
.
connect config into db

execute db with "CREATE TABLE scores (student TEXT, score REAL, pass INTEGER)"
execute db with "INSERT INTO scores VALUES ('Alice', 90, 1)"
execute db with "INSERT INTO scores VALUES ('Bob', 80, 1)"
execute db with "INSERT INTO scores VALUES ('Charlie', 70, 1)"
execute db with "INSERT INTO scores VALUES ('Dave', 40, 0)"

count all from scores in db into allCount
count of student from scores in db into studentCount
sum of score from scores in db into sumScores
total of score from scores in db into totalScores
average of score from scores in db into avgScores
minimum of score from scores in db into minScore
maximum of score from scores in db into maxScore

say "All count:" allCount
say "Student count:" studentCount
say "Sum:" sumScores
say "Total:" totalScores
say "Avg:" avgScores
say "Min:" minScore
say "Max:" maxScore

# Aggregate with where clause
sum of score from scores in db with
    where pass is 1
into passingSum
say "Passing sum:" passingSum

count all from scores in db with
    where pass is 0
into failCount
say "Fail count:" failCount

disconnect db
'@
$out = Invoke-OtterSource $aggSrc
Assert-True ($out -contains "All count: 4") "All count is 4"
Assert-True ($out -contains "Student count: 4") "Student count is 4"
Assert-True ($out -contains "Sum: 280") "Sum is 280"
Assert-True ($out -contains "Total: 280") "Total is 280"
Assert-True ($out -contains "Avg: 70") "Avg is 70"
Assert-True ($out -contains "Min: 40") "Min is 40"
Assert-True ($out -contains "Max: 90") "Max is 90"
Assert-True ($out -contains "Passing sum: 240") "Passing sum is 240"
Assert-True ($out -contains "Fail count: 1") "Fail count is 1"

# -----------------------------------------------------------------------------
# 7. SQL Injection & Parameterization Security
# -----------------------------------------------------------------------------
$injectionSrc = @'
config has
    provider is "sqlite"
    connection is ":memory:"
.
connect config into db

execute db with "CREATE TABLE accounts (id INTEGER, username TEXT, balance REAL)"
execute db with "INSERT INTO accounts VALUES (1, 'alice', 1000)"
execute db with "INSERT INTO accounts VALUES (2, 'bob', 500)"

maliciousInput is "' OR '1'='1"
get all from accounts in db with
    where username is maliciousInput
into matchedAccounts

say "Matched accounts count:" length of matchedAccounts

disconnect db
'@
$out = Invoke-OtterSource $injectionSrc
Assert-True ($out -contains "Matched accounts count: 0") "SQL injection safely escaped via parameterized value"

# -----------------------------------------------------------------------------
# 8. Error handling and clean Otter diagnostics
# -----------------------------------------------------------------------------
$closedConnSrc = @'
config has
    provider is "sqlite"
    connection is ":memory:"
.
connect config into db
disconnect db

get all from items in db into res
'@
$out = Invoke-OtterSource $closedConnSrc
Assert-True ($out -join "`n" -like '*connection is closed*') "Querying on closed connection produces clean error"

$invalidTableSrc = @'
config has
    provider is "sqlite"
    connection is ":memory:"
.
connect config into db
get all from nonexistent_table_404 in db into res
disconnect db
'@
$out = Invoke-OtterSource $invalidTableSrc
Assert-True ($out -join "`n" -like '*no such table: nonexistent_table_404*') "Missing table produces clean database error"

Write-Output 'Otter Query Language (OQL) tests passed.'
