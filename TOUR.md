# A 15-Minute Tour of Otter

> **Readable like English. Precise like code.**

Welcome to the Otter programming language! Otter is designed to be natural to read and write without sacrificing determinism, safety, or speed. Programs use everyday words and structured indentation instead of punctuation-heavy syntax.

This tour takes you from zero knowledge to understanding Otter's complete core model in approximately 15 minutes.

---

## Table of Contents

1. [Hello World & Output (`say`)](#1-hello-world--output-say)
2. [Variables with `is`](#2-variables-with-is)
3. [Arithmetic Expressions](#3-arithmetic-expressions)
4. [User Input with `ask`](#4-user-input-with-ask)
5. [Conditions (`if` / `otherwise`)](#5-conditions-if--otherwise)
6. [Loops (`repeat`, `while`, `count`, `each`)](#6-loops-repeat-while-count-each)
7. [Lists](#7-lists)
8. [Functions](#8-functions)
9. [Return Values](#9-return-values)
10. [Objects & Properties (`has` and `of`)](#10-objects--properties-has-and-of)
11. [Files & Folders](#11-files--folders)
12. [CLI Arguments & System Environment](#12-cli-arguments--system-environment)
13. [Working with CSV](#13-working-with-csv)
14. [Downloading Files from the Web](#14-downloading-files-from-the-web)
15. [Putting It All Together: A Complete Automation Script](#15-putting-it-all-together-a-complete-automation-script)

---

## 1. Hello World & Output (`say`)

Output in Otter uses the word `say`. It prints text to standard output followed by a newline:

```otter
say "Hello, Otter!"
```

Output:
```text
Hello, Otter!
```

Calling `say` with no arguments prints a blank line:

```otter
say
```

You can output multiple values on a single line. Otter automatically separates each value with a single space:

```otter
name is "Jeff"
say "Welcome," name "to Otter!"
```

Output:
```text
Welcome, Jeff to Otter!
```

---

## 2. Variables with `is`

In Otter, `is` is the universal assignment operator at the statement level. Variable types are determined automatically:

```otter
name is "Alice"
age is 29
ratio is 3.14
active is true
```

Variable rules:
- Variable names start with a lowercase letter and use camelCase (e.g. `totalRevenue`, `userEmail`).
- Variable names are case-sensitive (`loggedIn` and `loggedin` are different variables).
- Text literals use double quotes (`"..."`).
- Booleans are `true` and `false`.

---

## 3. Arithmetic Expressions

Otter performs calculations using everyday words:

```otter
number1 is 10
number2 is 5

# Addition
number1 and number2 make total
say "Total:" total

# Subtraction
number1 minus number2 make difference
say "Difference:" difference

# Multiplication
number1 times number2 make product
say "Product:" product

# Division
number1 divided by number2 make quotient
say "Quotient:" quotient
```

Output:
```text
Total: 15
Difference: 5
Product: 50
Quotient: 2
```

### In-Place Modification

To modify an existing numeric variable directly, use `add` or `remove`:

```otter
score is 100

add 15 to score
remove 30 from score

say "Final score:" score
```

Output:
```text
Final score: 85
```

---

## 4. User Input with `ask`

To prompt a user for input from the terminal, use `ask`:

```otter
ask "What is your name? " and call it userName
say "Hello" userName
```

Otter automatically converts typed input into numbers or booleans when applicable:
- Typing `42` stores the number `42`.
- Typing `true` stores the boolean `true`.
- Everything else remains text.

```otter
ask "Enter your age: " and call it age
age and 5 make futureAge
say "In 5 years you will be:" futureAge
```

If the user enters `25`, `futureAge` computes `30`.

---

## 5. Conditions (`if` / `otherwise`)

Otter uses indentation to define code blocks. There are no curly braces (`{}`) or `end` keywords.

```otter
age is 20

if age is at least 18
    say "Adult"
otherwise
    say "Minor"
.
```

Output:
```text
Adult
```

### Comparison Words

Otter uses clear multi-word phrases for comparisons:

| Otter Phrasing | Meaning |
|---|---|
| `is` | Equal to |
| `is not` | Not equal to |
| `is greater than` | Greater than (`>`) |
| `is at least` | Greater than or equal to (`>=`) |
| `is less than` | Less than (`<`) |
| `is at most` | Less than or equal to (`<=`) |

### Chaining Conditions

To test multiple branches, use `otherwise if`:

```otter
score is 85

if score is at least 90
    say "Grade: A"
otherwise if score is at least 80
    say "Grade: B"
otherwise
    say "Grade: C"
.
```

Output:
```text
Grade: B
```

### The Period `.`

Notice the period `.` at the end of the `if` statement above. In Otter, the period has one primary structural meaning:
> **A period explicitly finishes a block or process.**

Indentation tells Otter which lines belong inside the condition, while the optional period makes nested code unambiguous. The period is **never** used for property access.

---

## 6. Loops (`repeat`, `while`, `count`, `each`)

Otter provides four distinct, readable ways to loop:

### Fixed Repetition (`repeat`)

Run a block a fixed number of times:

```otter
repeat 3 times
    say "Hip hip hooray!"
.
```

### Conditional Loop (`while`)

Run a block as long as a condition remains true:

```otter
counter is 1

while counter is at most 3
    say "While counter:" counter
    add 1 to counter
.
```

### Range Loop (`count`)

Count through a numeric range. Both the start and end values are **inclusive**:

```otter
count from 1 to 4 as n
    say "Counted:" n
.
```

Output:
```text
Counted: 1
Counted: 2
Counted: 3
Counted: 4
```

---

## 7. Lists

A list is an ordered collection of values. Multi-line lists begin with `are` and end with a period `.`:

```otter
games are
    "Zelda"
    "Metroid"
    "Mario"
.
```

### Traversing a List
 
Use `each` to walk through items in order:
 
```otter
each game in games
    say "Game:" game
.
```

> [!NOTE]
> `each item in items` is Otter's canonical syntax for list iteration (D36). The phrase `for each` is also accepted as older compatibility syntax.

Output:
```text
Game: Zelda
Game: Metroid
Game: Mario
```

### List Utilities

```otter
# Check item count
say "Total games:" length of games

# Membership check
if games contains "Zelda"
    say "Found Zelda in collection!"
.

# Add and remove items
add "Pokemon" to games
say "After add, count is:" length of games

remove "Metroid" from games
say "After remove, count is:" length of games
```

---

## 8. Functions

Define functions with `to`, followed by the function name, its parameters, and an indented body:

```otter
to greet person
    say "Hello," person
.
```

Call the function naturally:

```otter
greet "Ada"
greet "Linus"
```

Output:
```text
Hello, Ada
Hello, Linus
```

---

## 9. Return Values

Use `return` inside a function to return a value:

```otter
to calculateTax subtotal and rate
    subtotal times rate make tax
    return tax
.
```

You can capture a function's return value using either `make` or direct assignment with `is`:

```otter
# Option A: using make
calculateTax 100 and 0.08 make taxAmount
say "Tax on $100:" taxAmount

# Option B: using is
taxAmount2 is calculateTax 200 and 0.05
say "Tax on $200:" taxAmount2
```

Output:
```text
Tax on $100: 8
Tax on $200: 10
```

---

## 10. Objects & Properties (`has` and `of`)

In Otter, structured objects are created canonically using `has`:

```otter
developer has
    name is "Alice"
    role is "Architect"
    level is 3
.
```

> [!NOTE]
> `has` is the canonical syntax for object literals (D40). Older Otter code may use `developer is a thing`, which remains supported for backward compatibility.

### Property Access with `of`

Otter uses the English preposition `of` to read properties:

```otter
say "Developer:" name of developer
say "Role:" role of developer
say "Level:" level of developer
```

Output:
```text
Developer: Alice
Role: Architect
Level: 3
```

> [!IMPORTANT]
> **Why `of` instead of `.`?**
> In traditional languages, `.` is overloaded to mean decimal numbers (`3.14`), method invocation (`obj.method()`), namespace resolution, and property access. In Otter, the period `.` has exactly one structural meaning: **finish a block**. Properties are always accessed with `property of object`.

### Modifying Properties

To update an object's property, assign to it directly:

```otter
level of developer is 4
say "Updated level:" level of developer
```

Output:
```text
Updated level: 4
```

---

## 11. Files & Folders

Otter provides native, sandboxed file operations:

```otter
notePath is "status.txt"

# Writing text to a file
write "Otter system: online and verified." to notePath

# Checking file existence
if file notePath exists
    say "Note file exists on disk."
.

# Reading file contents
read notePath into content
say "File content:" content

# Copying and deleting files
backupPath is "status-backup.txt"
copy notePath to backupPath

delete file notePath
delete file backupPath
say "Temporary files cleaned up."
```

Output:
```text
Note file exists on disk.
File content: Otter system: online and verified.
Temporary files cleaned up.
```

---

## 12. CLI Arguments & System Environment

Otter scripts can inspect command-line arguments and interact with the host environment.

### Command-Line Arguments

The built-in `arguments` list gives access to parameters passed to the script:

```otter
say "Arguments received:" length of arguments

each arg in arguments
    say "  Arg:" arg
.
```

Running `otter run script.ot deploy staging preview` outputs:
```text
Arguments received: 3
  Arg: deploy
  Arg: staging
  Arg: preview
```

### Current Working Directory & Environment Variables

```otter
# Current Directory
get current directory into cwd
say "Running inside:" cwd

# Environment Variables
set environment variable "APP_ENV" to "production"
get environment variable "APP_ENV" into currentEnv
say "Environment setting:" currentEnv
```

Output:
```text
Running inside: C:\Projects\MyProject
Environment setting: production
```

---

## 13. Working with CSV

Otter includes native support for RFC 4180 CSV documents. Tabular data automatically converts into a list of objects, where each column header becomes a property name:

```otter
rawCsv is "id,city,temp\n101,Seattle,68\n102,Portland,72\n103,Spokane,75"

# Parse CSV text directly into structured Otter objects
convert rawCsv from csv into records

say "Loaded" length of records "weather records:"
each row in records
    say "  City:" city of row "High:" temp of row
.
```

Output:
```text
Loaded 3 weather records:
  City: Seattle High: 68
  City: Portland High: 72
  City: Spokane High: 75
```

### Reading and Writing CSV Files

```otter
filePath is "weather.csv"

# Write records directly to disk as CSV
write csv records to filePath

# Read CSV from disk back into structured objects
read csv from filePath into loadedData
say "Verified" length of loadedData "rows read from disk."

delete file filePath
```

Output:
```text
Verified 3 rows read from disk.
```

---

## 14. Downloading Files from the Web

Otter can stream files directly from any HTTP or HTTPS URL to a local destination:

```otter
url is "https://httpbin.org/robots.txt"
dest is "robots.txt"

say "Downloading file..."
download file from url to dest

if file dest exists
    read dest into text
    say "Downloaded" length of text "bytes."
    delete file dest
    say "Cleaned up."
.
```

Output:
```text
Downloading file...
Downloaded 30 bytes.
Cleaned up.
```

### Built-in Download Safety
- **No Overwriting**: Otter will never silently overwrite an existing file. If the destination exists, download aborts before making any network requests.
- **Atomic Promotion**: Downloads stream directly into a hidden temporary file in the destination directory (`.otter-dl-*.tmp`) and are atomically renamed only upon complete byte transfer.
- **Automatic Cleanup**: If the network connection drops, the server reports an error, or the transfer is truncated, the partial temp file is removed immediately.

---

## 15. Putting It All Together: A Complete Automation Script

Here is an end-to-end automation script combining functions, CSV parsing, data calculations, file output, and summary reporting:

```otter
# sales_report.ot - Process sales orders, calculate totals, and export archive

to calculateSubtotal qty and price
    qty times price make subtotal
    return subtotal
.

# 1. Parse incoming CSV sales data
csvData is "orderId,item,qty,price\n1001,Laptop,2,1200\n1002,Monitor,3,300\n1003,Keyboard,5,80"
convert csvData from csv into orders

totalItems is 0
totalRevenue is 0

say "=== Processing Sales Orders ==="
each order in orders
    qty is qty of order
    price is price of order
    
    orderTotal is calculateSubtotal qty and price
    orderTotal and totalRevenue make totalRevenue
    qty and totalItems make totalItems

    say "Order" orderId of order ":" item of order "(Qty:" qty ", Total: $" orderTotal ")"
.

say ""
say "=== Summary ==="
say "Orders processed:" length of orders
say "Total items sold:" totalItems
say "Total revenue: $" totalRevenue

# 2. Archive orders to a CSV file on disk
reportPath is "sales_archive.csv"
write csv orders to reportPath

if file reportPath exists
    read csv from reportPath into verifiedOrders
    say "Archive verified:" length of verifiedOrders "records written to" reportPath
    delete file reportPath
    say "Cleaned up temporary archive."
.
```

Run this program using the Otter command line:

```powershell
otter run sales_report.ot
```

Output:
```text
=== Processing Sales Orders ===
Order 1001 : Laptop (Qty: 2 , Total: $ 2400 )
Order 1002 : Monitor (Qty: 3 , Total: $ 900 )
Order 1003 : Keyboard (Qty: 5 , Total: $ 400 )

=== Summary ===
Orders processed: 3
Total items sold: 10
Total revenue: $ 3700
Archive verified: 3 records written to sales_archive.csv
Cleaned up temporary archive.
```

---

## Next Steps

Congratulations! You now understand the core foundations of the Otter programming language:
- Variables (`is`) and readable arithmetic (`and`, `minus`, `times`, `divided by`).
- Block indentation and process completion (`.`).
- Property access with `of` (`property of object`).
- Native files, CSV data, and streaming file downloads.

To learn more:
- Read [INSTALL.md](INSTALL.md) to set up Otter on your system.
- Explore the [examples/](examples/) directory for complete, runnable applications.
- Build web applications with `otter web <app.ot>`.
