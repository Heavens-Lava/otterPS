# Otter Programming Language

> **Readable like English. Precise like code.**

Otter uses indentation to understand blocks. There is no `end` keyword.

A period `.` can explicitly finish a block, function, condition, event, object definition, or other multi-line process.

A period is **not** used for property access.

---

# Variables

```otter
name is "Jeff"
age is 29
score is 100
loggedIn is true
```

---

# Output

```otter
say "Hello"
```

Variables can be placed directly beside text:

```otter
name is "Jeff"

say "Hello" name
```

Output:

```text
Hello Jeff
```

Multiple values:

```otter
name is "Jeff"
age is 29

say name "is" age "years old."
```

Output:

```text
Jeff is 29 years old.
```

---

# Math

Addition:

```otter
number1 is 5
number2 is 5

number1 and number2 make total

say total
```

Output:

```text
10
```

Subtraction:

```otter
10 minus 5 make answer
```

Multiplication:

```otter
10 times 5 make answer
```

Division:

```otter
10 divided by 5 make answer
```

Modify an existing variable:

```otter
score is 10

add 5 to score
remove 2 from score

say score
```

Output:

```text
13
```

---

# User Input

```otter
ask "What is your name?" and call it name

say "Hello" name
```

Output:

```text
What is your name? Jeff
Hello Jeff
```

---

# If Statements

Indentation determines what belongs to the condition:

```otter
age is 29

if age is at least 18
    say "You are an adult."

say "Program finished."
```

Otter understands that:

```otter
    say "You are an adult."
```

belongs to the `if` because it is indented.

The following:

```otter
say "Program finished."
```

is no longer indented, so the `if` is finished.

---

# Period Block Ending

A period can explicitly finish a block:

```otter
if age is at least 18
    say "You are an adult."
.
```

This becomes useful when code gets more complicated.

Both forms are valid:

```otter
if score is greater than 100
    say "High score!"

say "Finished."
```

and:

```otter
if score is greater than 100
    say "High score!"
.

say "Finished."
```

The period has one structural meaning outside quoted strings:

> **Finish the current block or process.**

It is never used for accessing properties.

---

# Otherwise

```otter
if age is at least 18
    say "Adult"
otherwise
    say "Minor"
```

Multiple conditions:

```otter
if score is at least 90
    say "A"
otherwise if score is at least 80
    say "B"
otherwise if score is at least 70
    say "C"
otherwise
    say "F"
```

---

# Nested Conditions

Indentation makes the relationship clear:

```otter
if loggedIn
    say "Welcome!"

    if admin
        say "Administrator controls enabled."

    say "Login successful."

say "Program finished."
```

The indentation tells Otter exactly which statements belong to which condition.

The same program with explicit periods:

```otter
if loggedIn
    say "Welcome!"

    if admin
        say "Administrator controls enabled."
    .

    say "Login successful."
.

say "Program finished."
```

---

# Functions

Functions also use indentation:

```otter
to greet name
    say "Hello" name
```

Call it naturally:

```otter
greet "Jeff"
```

Output:

```text
Hello Jeff
```

Or explicitly finish the function:

```otter
to greet name
    say "Hello" name
.
```

---

# Functions Returning Values

```otter
to add number1 and number2
    number1 and number2 make result
    return result

add 5 and 10 make total

say total
```

Output:

```text
15
```

---

# Repeat

```otter
repeat 3 times
    say "Hello"

say "Finished!"
```

Output:

```text
Hello
Hello
Hello
Finished!
```

---

# While

```otter
number is 1

while number is less than 5
    say number
    add 1 to number

say "Finished."
```

---

# Lists

```otter
games are
    "Zelda"
    "Mario"
    "Pokemon"
.
```

Loop through them:

```otter
for each game in games
    say game
```

Output:

```text
Zelda
Mario
Pokemon
```

---

# Objects

Objects follow the same indentation rules:

```otter
person is a thing
    name is "Jeff"
    age is 29
    programmer is true
.
```

Properties use the word `of`.

Do not write:

```text
person.name
person.age
```

Write:

```otter
say name of person
say age of person
```

Output:

```text
Jeff
29
```

Properties can also be changed:

```otter
age of person is 30

say age of person
```

Output:

```text
30
```

---

# Property Access

Otter uses:

```text
property of object
```

instead of:

```text
object.property
```

Examples:

```otter
name of person
age of person
text of nameBox
width of window
extension of file
```

Properties can appear anywhere another value or expression can appear:

```otter
say "Hello" name of person
```

```otter
if age of person is at least 18
    say name of person "is an adult."
.
```

Assignment:

```otter
text of message is "Hello"
width of window is 800
age of person is 30
```

Nested property access:

```otter
city of address of user
```

This means the `city` property belonging to the `address` property belonging to `user`.

The word `of` is a **structural language keyword**.

It is not a disposable filler word.

---

# Custom Types

```otter
a Person has
    name
    age
.
```

Create one:

```otter
jeff is a Person

name of jeff is "Jeff"
age of jeff is 29

say "Hello" name of jeff
```

---

# Files

```otter
read "notes.txt" into notes
say notes
```

Write:

```otter
write "Hello!" to "hello.txt"
```

Copy:

```otter
copy "hello.txt" to "backup/hello.txt"
```

Move:

```otter
move "hello.txt" to "Documents"
```

Delete:

```otter
delete file "hello.txt"
```

Check:

```otter
if file "hello.txt" exists
    say "The file exists."
```

File properties also use `of`:

```otter
say name of file
say extension of file
say size of file
```

Example:

```otter
for each file in files
    if extension of file is ".jpg"
        move file to "Pictures"
    .
.
```

---

# Running Programs

```otter
run "notepad.exe"
```

Run commands:

```otter
run command "git status"
```

Capture output:

```otter
run command "git status" into result

say result
```

---

# Lists and Loops

```otter
games are
    "Zelda"
    "Mario"
    "Pokemon"
.

for each game in games
    say "I like" game
```

Output:

```text
I like Zelda
I like Mario
I like Pokemon
```

---

# Count

```otter
count from 1 to 5 as number
    say number
.
```

Output:

```text
1
2
3
4
5
```

The ending value is included.

Variables can also be used:

```otter
start is 5
finish is 10

count from start to finish as number
    say number
.
```

---

# Optional Natural-Language Words

Otter may allow selected optional words to make statements easier to read.

Examples of possible optional words include:

```text
the
a
an
value
called
then
```

For example:

```otter
if age is at least 18
    say "Adult"
.
```

and:

```otter
if the age is at least 18
    say "Adult"
.
```

may mean the same thing.

Likewise:

```otter
add 5 to score
```

and:

```otter
add the value 5 to score
```

may mean the same thing.

However, Otter does **not** globally ignore words.

Some English words carry real grammatical meaning.

Structural words include:

```text
of
to
from
with
where
into
in
as
at
on
```

For example:

```otter
name of person
```

requires `of`.

Removing it would change the structure of the expression.

Optional words must only be ignored in grammar locations where the language explicitly allows them.

**Rule: An optional filler word may improve readability, but removing it must never change the meaning of the program.**

---

# Complete Example

```otter
say "Welcome to Otter!"

ask "What is your name?" and call it name
ask "How old are you?" and call it age

say "Hello" name

if age is at least 18
    say "You are an adult."
otherwise
    say "You are under 18."
.

say "Let's count!"

count from 1 to 5 as number
    say number
.

say "Goodbye" name
```

The structure is visible from indentation, and periods can explicitly close blocks.

---

# Otter Syntax Philosophy

C#:

```text
if (age >= 18)
{
    Console.WriteLine($"Hello {name}, you are an adult.");
}
```

Otter:

```otter
if age is at least 18
    say "Hello" name "you are an adult."
.
```

Python:

```text
def greet(name):
    print(f"Hello {name}")
```

Otter:

```otter
to greet name
    say "Hello" name
.
```

C#:

```text
foreach (var game in games)
{
    Console.WriteLine(game);
}
```

Otter:

```otter
for each game in games
    say game
.
```

C#:

```text
person.Name
```

Otter:

```otter
name of person
```

C#:

```text
nameBox.Text
```

Otter:

```otter
text of nameBox
```

---

## Core Rules

Otter should require as little programming punctuation as possible.

```otter
name is "Jeff"
```

not:

```text
string name = "Jeff";
```

Use natural words:

```otter
if age is at least 18
```

instead of:

```text
if (age >= 18)
```

Use indentation for structure:

```otter
if ready
    say "Starting..."
    run program
```

A period can explicitly close a block:

```otter
if ready
    say "Starting..."
    run program
.
```

Use `of` for properties:

```otter
text of nameBox
name of person
extension of file
```

not:

```text
nameBox.text
person.name
file.extension
```

Variables combine naturally with output:

```otter
say "Hello" name
```

rather than:

```text
Console.WriteLine($"Hello {name}");
```

---

# Period Rule

Outside quoted strings, a period is reserved for ending the current block or multi-line process.

```otter
if ready
    say "Ready!"
.
```

```otter
to greet name
    say "Hello" name
.
```

```otter
when button is clicked
    say "Clicked!"
.
```

A period inside a quoted string is ordinary text:

```otter
say "Finished."
```

A period is never used for member or property access.

---

# Property Rule

Property access always follows:

```text
property of target
```

Examples:

```otter
name of person
text of nameBox
extension of file
status of server
port of application
```

Nested properties:

```otter
city of address of user
```

Property assignment:

```otter
age of person is 30
text of message is "Hello"
width of window is 800
```

`of` is structural grammar and must not be treated as optional filler.

---

**No braces.**

**No semicolons.**

**No required `end`.**

**No interpolation symbols.**

**No dot-style property access.**

**Indentation defines structure.**

**Periods explicitly finish blocks and processes.**

**Properties use `property of object`.**

**Readable like English. Precise like code.**
