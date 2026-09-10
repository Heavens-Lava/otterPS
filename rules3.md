# Otter Language Rules — Part 3

> **Readable like English. Precise like code.**

Part 3 extends Otter with language features needed for larger, safer, and more capable programs.

This part covers:

* absence values with `gone`
* file and folder discovery
* folder safety
* error handling
* string operations
* collection operations
* searching collections
* JSON and data conversion
* variable scope
* modules and reusable files
* dates and time
* random values
* testing
* logging and debugging
* command-line arguments
* configuration and secrets
* future concurrency rules

Otter should continue to prefer readable intent over programming ceremony.

---

# 1. Gone — Absence of a Value

Otter uses:

```otter
gone
```

to represent the absence of a value.

`gone` is Otter's equivalent of concepts such as `null`, `nil`, or `None` in other programming languages.

Example:

```otter
user is gone
```

Check for an absent value:

```otter
if user is gone
    say "User was not found."
.
```

Check that a value exists:

```otter
if user is not gone
    say "Welcome" name of user
.
```

`gone` is a literal value.

It does not require special assignment syntax.

```otter
user is gone
```

uses the same assignment rules as:

```otter
user is "Jeff"
```

---

# 2. Gone Is Different From Empty and False

These values are not equivalent:

```otter
user is gone
name is ""
score is 0
games are empty
ready is false
```

They mean:

```text
gone       no value exists
""         a string exists but contains no characters
0          a number exists and is zero
empty      a collection exists but contains no items
false      a boolean exists and is false
```

Otter must not automatically treat these values as interchangeable.

---

# 3. Gone Is the Only Absence Keyword

Otter uses only:

```otter
gone
```

for absence.

Do not introduce aliases such as:

```text
null
nil
None
nothing
NA
```

This keeps the language consistent and prevents multiple words from representing the same concept.

---

# 4. File Discovery

Files can be discovered from a folder:

```otter
get files in "Pictures" into files
```

The result is a list of file objects.

Example:

```otter
get files in "Documents" into files

for each file in files
    say name of file
.
```

---

# 5. Folder Discovery

Folders can be discovered the same way:

```otter
get folders in "Documents" into folders
```

Example:

```otter
for each folder in folders
    say name of folder
.
```

---

# 6. Discovery Does Not Recurse By Default

This:

```otter
get files in "Pictures" into files
```

only retrieves files directly inside `Pictures`.

It does not automatically search subfolders.

Recursive discovery must be requested explicitly:

```otter
get files in "Pictures" and subfolders into files
```

Likewise:

```otter
get folders in "Documents" and subfolders into folders
```

The phrase:

```text
and subfolders
```

is the only recursion switch for discovery.

---

# 7. `and subfolders` Is Structural Grammar

Otter already uses `and` in other contexts.

Arithmetic:

```otter
5 and 10 make total
```

Boolean:

```otter
if ready and connected
```

Discovery:

```otter
get files in "Pictures" and subfolders into files
```

In discovery syntax, `and subfolders` must be recognized as one structural phrase.

It does not mean arithmetic addition or boolean AND.

---

# 8. File Objects

A discovered file is an object.

Common file properties include:

```otter
name of file
path of file
extension of file
size of file
created of file
modified of file
```

Example:

```otter
get files in "Pictures" into files

for each file in files
    say name of file
    say extension of file
    say size of file
.
```

File operations may accept either a path or a file object.

Path:

```otter
move "photo.jpg" to "Pictures"
```

Object:

```otter
move file to "Pictures"
```

---

# 9. Folder Objects

A discovered folder is also an object.

Folder properties include:

```otter
name of folder
path of folder
created of folder
modified of folder
```

A folder does not expose:

```otter
size of folder
```

as a normal property.

Determining the total size of a folder may require recursively examining many files and subfolders.

Otter should not hide an expensive operation behind a property that appears inexpensive.

---

# 10. Measuring Folder Size

If folder size is supported later, it should require an explicit operation.

Preferred form:

```otter
measure folder "Pictures" into size
```

or:

```otter
measure folder folder into size
```

The word `measure` makes it clear that Otter must perform work to determine the value.

---

# 11. Creating Folders

```otter
create folder "Backup"
```

---

# 12. Copying Folders

```otter
copy folder "Work" to "Backup"
```

A folder object may also be used:

```otter
copy folder to "Backup"
```

when `folder` refers to a folder object.

---

# 13. Moving Folders

```otter
move folder "Work" to "Archive"
```

Or with a folder object:

```otter
move folder to "Archive"
```

---

# 14. Deleting Folders Safely

```otter
delete folder "Backup"
```

must only delete an empty folder.

If the folder contains files or folders, Otter must refuse the operation and report why.

Example error:

```text
Otter Runtime Error

Could not delete folder "Backup".

The folder is not empty.
It contains 12 items.
```

Otter must not silently delete an entire folder tree when the programmer only wrote:

```otter
delete folder "Backup"
```

---

# 15. Recursive Folder Deletion

Deleting a folder and everything inside it must use deliberately explicit wording.

Proposed syntax:

```otter
delete folder "Backup" and everything in it
```

This operation is intentionally different from:

```otter
delete folder "Backup"
```

The destructive behavior must be visible when reading the source.

This syntax should remain reserved until its safety rules are fully specified.

---

# 16. Try and Otherwise

Otter uses:

```otter
try
    ...
otherwise
    ...
.
```

for error handling.

Example:

```otter
try
    read "settings.json" into settings
otherwise
    say "Could not load settings."
.
```

If the `try` body completes normally, the `otherwise` body does not run.

If an operation in the `try` body fails, Otter runs the `otherwise` body.

---

# 17. Otherwise Is Optional for Try

A `try` block may exist without an `otherwise` body when the runtime or surrounding code handles the failure.

```otter
try
    read "settings.json" into settings
.
```

The exact propagation behavior should follow Otter's runtime error rules.

---

# 18. Normal Control Flow Is Not Failure

Statements such as:

```otter
return
```

must pass through `try` normally.

Example:

```otter
to find user
    try
        return user
    otherwise
        say "Could not find user."
    .
.
```

If `return user` executes successfully, the function returns `user`.

The `otherwise` body must not run.

Normal control-flow changes are not runtime errors.

This rule should also apply to future control-flow features such as:

```text
break
continue
```

---

# 19. String Length

```otter
length of name
```

Example:

```otter
name is "Jeff"

say length of name
```

Output:

```text
4
```

---

# 20. Collection Length

The same readable syntax works with collections:

```otter
length of games
```

Example:

```otter
games are
    "Zelda"
    "Mario"
    "Pokemon"
.

say length of games
```

Output:

```text
3
```

---

# 21. First and Last

```otter
first of games
last of games
```

Example:

```otter
say first of games
say last of games
```

If the collection is empty:

```otter
first of games
```

returns:

```otter
gone
```

The same applies to:

```otter
last of games
```

---

# 22. Uppercase and Lowercase

```otter
uppercase of name
lowercase of name
```

Example:

```otter
name is "Jeff"

say uppercase of name
say lowercase of name
```

Output:

```text
JEFF
jeff
```

These operations return new values.

They do not automatically modify the original variable.

---

# 23. Contains

Strings can be checked for text:

```otter
if name contains "Jeff"
    say "Found Jeff."
.
```

Collections can be checked for an item:

```otter
if games contains "Zelda"
    say "Zelda is in the list."
.
```

The parser/runtime determines whether the target is text or a collection.

---

# 24. Starts With

```otter
if name starts with "J"
    say "Starts with J."
.
```

---

# 25. Ends With

```otter
if name ends with "rey"
    say "Ends with rey."
.
```

---

# 26. Replace Text

```otter
replace "Jeff" with "Jeffrey" in name
```

For operations where the result must be retained, Otter should make the destination explicit.

Preferred form:

```otter
replace "Jeff" with "Jeffrey" in name into updatedName
```

Then:

```otter
say updatedName
```

The original value should not be mutated unless the syntax explicitly requests mutation.

---

# 27. Split Text

```otter
split "red,green,blue" by "," into colors
```

This creates a list.

Equivalent example using a variable:

```otter
text is "red,green,blue"

split text by "," into colors
```

---

# 28. Join Text

```otter
join colors with ", " into text
```

Example:

```otter
colors are
    "red"
    "green"
    "blue"
.

join colors with " | " into text

say text
```

Output:

```text
red | green | blue
```

---

# 29. Sort Collections

```otter
sort games
```

The default behavior is ascending natural order.

Example:

```otter
games are
    "Zelda"
    "Mario"
    "Pokemon"
.

sort games
```

More advanced syntax such as:

```otter
sort files by name
```

should be designed separately because it introduces selector and comparison rules.

---

# 30. Reverse Collections

```otter
reverse games
```

This reverses the current order of the collection.

---

# 31. Find One Item

Otter uses `find` when the programmer wants one matching item.

```otter
find game in games where game is "Mario" into result
```

The first matching item is placed into `result`.

If nothing matches:

```otter
result is gone
```

This allows:

```otter
find game in games where game is "Mario" into result

if result is gone
    say "Mario was not found."
otherwise
    say "Found" result
.
```

---

# 32. Find With Object Properties

`find` becomes especially useful with objects:

```otter
find file in files where extension of file is ".pdf" into result
```

Then:

```otter
if result is gone
    say "No PDF found."
otherwise
    say "Found" name of result
.
```

---

# 33. Singular Find vs Multiple Get

Otter should preserve the distinction between singular and plural intent.

```otter
find file in files where extension of file is ".pdf" into result
```

means:

> Return the first matching file or `gone`.

A future form such as:

```otter
get files from files where extension of file is ".pdf" into pdfs
```

would mean:

> Return all matching files as a collection.

This distinction should remain deliberate.

---

# 34. Derived Operations and Object Properties

Not every expression using `of` represents a stored property.

These are object properties:

```otter
name of file
extension of file
age of person
```

These are operations:

```otter
length of games
uppercase of name
first of games
```

They share readable surface grammar, but the parser may represent them differently internally.

The runtime object model should not pretend every derived operation is a stored property.

---

# 35. JSON

Otter should support JSON directly because APIs and configuration commonly use it.

Read JSON from a file:

```otter
read json from "settings.json" into settings
```

Convert JSON text:

```otter
convert text from json into user
```

Convert an object to JSON:

```otter
convert user to json into text
```

HTTP request bodies may use:

```otter
body of request as json becomes user
```

---

# 36. JSON Objects Use Ordinary Property Access

After JSON is converted into an Otter object:

```otter
say name of user
say email of user
```

Nested JSON works naturally:

```otter
city of address of user
```

Otter should not require separate JSON-navigation syntax.

---

# 37. Variable Scope

Otter must define where variables can be accessed.

Example:

```otter
name is "Jeff"

to greet
    message is "Hello"
    say name
.
```

The language must specify:

* whether functions can read variables outside themselves
* whether local variables disappear when the function ends
* whether nested blocks create new scopes
* how outer variables are changed deliberately

The preferred rule is:

> Variables created inside a function belong to that function unless explicitly exposed.

---

# 38. Function Local Variables

Example:

```otter
to greet name
    message is "Hello"
    say message name
.
```

`message` exists only while `greet` is running.

After the function finishes, `message` should no longer be available outside that function.

---

# 39. Block Scope

Simple control-flow blocks should not automatically hide ordinary variables unless Otter later chooses strict lexical block scope.

Example:

```otter
if ready
    message is "Starting"
.

say message
```

This behavior needs one consistent rule across:

```text
if
while
for each
count
try
```

The exact rule should be frozen before more advanced closures or concurrency are added.

---

# 40. Modules

Large programs need multiple source files.

Otter should use a simple keyword:

```otter
use
```

Example:

```otter
use "helpers.ot"
```

Built-in or installed libraries may use:

```otter
use web
use database
use json
```

---

# 41. Packages

A future Otter package command may look like:

```text
otter add sqlite
otter add web
otter add testing
```

Then source code can use:

```otter
use sqlite
```

Packages should extend runtime capabilities without forcing new core language syntax for every library.

---

# 42. Dates

```otter
today
```

represents the current date.

Example:

```otter
date is today
```

---

# 43. Current Time

```otter
now
```

represents the current date and time.

Example:

```otter
started is now
```

---

# 44. Date Arithmetic

```otter
add 7 days to date
```

```otter
remove 1 day from date
```

Date operations should continue to use ordinary Otter verbs where the meaning is clear.

---

# 45. Difference Between Dates

```otter
days between startDate and endDate make days
```

Example:

```otter
say days
```

---

# 46. Date Formatting

```otter
format date as "MM/dd/yyyy" into text
```

Formatting strings may follow common date-format conventions provided they are documented clearly.

---

# 47. Random Numbers

```otter
random number from 1 to 10 into number
```

---

# 48. Random Collection Items

```otter
random item from games into game
```

If the collection is empty, the result should be:

```otter
gone
```

---

# 49. Logging

Application logging should be distinct from ordinary user output.

```otter
log "Server started."
```

Warnings:

```otter
warn "Connection is slow."
```

Errors:

```otter
error "Could not connect."
```

`log`, `warn`, and `error` should represent diagnostic output rather than normal application-facing output.

---

# 50. Debugging

A debug operation may display detailed runtime information:

```otter
debug user
```

Otter's command-line runtime may later support:

```text
otter run app.ot --debug
```

Debug mode may expose:

* tokens
* parsed syntax
* AST
* variable values
* runtime errors
* stack information

Normal users should not receive raw PowerShell or host-language stack traces unless debug mode is enabled.

---

# 51. Testing

Testing should be readable without a separate assertion language.

```otter
test "addition works"
    5 and 5 make result

    expect result to be 10
.
```

Another example:

```otter
test "user has a name"
    user is a thing
        name is "Jeff"
    .

    expect name of user to be "Jeff"
.
```

---

# 52. Testing Gone Values

```otter
test "missing user is gone"
    get user where id is 999 into user

    expect user to be gone
.
```

---

# 53. Expected Errors

A future testing feature may support:

```otter
expect error when
    delete folder "NonEmptyFolder"
.
```

This should be designed separately before implementation.

---

# 54. Command-Line Arguments

Programs should be able to access command-line arguments.

Possible simple syntax:

```otter
arguments become args
```

Then:

```otter
say first of args
```

A more descriptive argument system may be added later for named arguments and required values.

---

# 55. Environment Values

```otter
port is environment value "PORT"
```

Fallback:

```otter
port is environment value "PORT" or 8080
```

---

# 56. Secrets

Secrets should not automatically appear in normal logs or error output.

A future explicit form may be:

```otter
secret "API_KEY" becomes apiKey
```

The runtime may retrieve the value from environment variables, a secure store, or another provider.

The exact secret-provider system belongs to runtime libraries rather than core grammar.

---

# 57. Custom Type Methods — Reserved

Otter custom types will eventually need behavior as well as properties.

Example type:

```otter
a Person has
    name
    age
.
```

Method-call syntax is not yet frozen.

Do not assume:

```otter
greet jeff
```

means a method call because it is indistinguishable from calling a normal function named `greet` with `jeff` as an argument.

Do not reuse:

```otter
ask
```

for methods because `ask` already means user input.

Possible future syntax includes:

```otter
tell jeff to greet
```

but method syntax must be designed deliberately before implementation.

---

# 58. Concurrent Work — Reserved

Otter may eventually allow:

```otter
do at the same time
    download file1
    download file2
.
```

This syntax expresses concurrent intent.

However, concurrency requires rules for:

* variable sharing
* mutation
* errors
* return values
* cancellation
* execution order
* runtime isolation

Because the current PowerShell runtime may require runspaces or other concurrency mechanisms, this feature should have its own milestone.

Do not implement concurrency merely as a parser feature.

---

# 59. Waiting

Simple waiting may eventually use:

```otter
wait 2 seconds
```

Waiting for a task may later use:

```otter
wait for downloadTask
```

These forms should not be confused with concurrent execution semantics.

---

# 60. Advanced Feature Rule

Advanced functionality does not require complicated surface syntax.

Internally:

```otter
find file in files where extension of file is ".pdf" into result
```

may require iteration, property lookup, comparison, and early termination.

The Otter programmer should only need to express the intent.

Likewise:

```otter
read json from "settings.json" into settings
```

may require file access, decoding, parsing, object construction, and error handling.

The runtime handles the machinery.

Otter describes the goal.

---

# Part 3 Core Rules

1. `gone` is the only Otter value representing absence.
2. `gone`, empty collections, empty strings, zero, and `false` are different values.
3. File and folder discovery use `get`.
4. Discovery is non-recursive by default.
5. `and subfolders` explicitly enables recursive discovery.
6. Files and folders are runtime objects.
7. File objects may expose `name`, `path`, `extension`, `size`, `created`, and `modified`.
8. Folder objects expose `name`, `path`, `created`, and `modified`.
9. Folder size is not a normal property because calculating it may require traversal.
10. `delete folder` refuses to delete a non-empty folder.
11. Recursive destruction must require explicitly destructive wording.
12. `try` / `otherwise` handles runtime failures.
13. Normal control flow such as `return` is not a failure.
14. Strings and collections share natural operations such as `length of`.
15. `first of` and `last of` return `gone` for empty collections.
16. `find` returns the first match or `gone`.
17. Singular `find` and plural `get` should preserve their different meanings.
18. JSON objects use ordinary Otter property access.
19. Scope rules must remain predictable.
20. Large programs may use `use` for modules and libraries.
21. Testing should read as normal Otter.
22. Debugging information must not leak host-language implementation details during normal execution.
23. Methods on custom types remain deliberately unresolved until ambiguity is settled.
24. Concurrency receives its own design and runtime milestone.
25. New features should reuse existing vocabulary whenever doing so remains unambiguous.

> **Otter should read like English, but it should not attempt to understand all English.**

> **Readable like English. Precise like code.**
