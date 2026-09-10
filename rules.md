# Otter Programming Language

> **Readable like English. Precise like code.**

Otter uses indentation to understand blocks. There is no `end` keyword.

A period `.` can optionally make the end of a block explicit.

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
10 minus 5 makes answer
```

Multiplication:

```otter
10 times 5 makes answer
```

Division:

```otter
10 divided by 5 makes answer
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

A period can explicitly finish the block:

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

add 5 and 10 makes total

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

Objects can follow the same indentation rules:

```otter
person is a thing
    name is "Jeff"
    age is 29
    programmer is true
.
```

Then:

```otter
say person.name
say person.age
```

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
jeff.name is "Jeff"
jeff.age is 29

say "Hello" jeff.name
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

say "Let's count!"

count from 1 to 5 as number
    say number

say "Goodbye" name
```

The structure is visible from the indentation alone.

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
```

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

A period can explicitly close a block when useful:

```otter
if ready
    say "Starting..."
    run program
.
```

And variables combine naturally with output:

```otter
say "Hello" name
```

rather than:

```text
Console.WriteLine($"Hello {name}");
```

**No braces.**

**No semicolons.**

**No required `end`.**

**No interpolation symbols.**

**Indentation defines structure.**

**Periods optionally make structure explicit.**

**Readable like English. Precise like code.**
