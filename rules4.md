Otter Language Rules — Part 4

Readable like English. Precise like code.

Part 4 records language-design refinements discovered while using Otter in larger programs, especially arithmetic, iteration, result flow, filesystem scripting, web development, and control flow.

Where Part 4 explicitly conflicts with an older design note, Part 4 is the newer rule. Syntax marked Under Review is not yet canonical and must not be implemented as a breaking change without a separate design decision.

1. Otter Uses Controlled English

Otter should read naturally, but it is not unrestricted natural language.

Every valid statement must have a deterministic grammatical meaning.

Good:

each file in files
    if extension of file is ".jpg"
        copy file to "Backup"
    .
.

Do not add many equivalent phrasings such as:

for every file
for all the files
go through every file
loop through the files
do this for the files

when one canonical form is enough.

Rule

A beginner should be able to read Otter aloud and understand the intent, while the parser should be able to interpret it exactly one way.

2. PowerShell Is an Implementation, Not the Language

Otter may currently run through PowerShell, but Otter syntax and semantics must never depend on PowerShell behavior.

A valid Otter program should have the same defined meaning when implemented by PowerShell, .NET, JavaScript/Web, or another future backend.

PowerShell commands such as mkdir, Get-ChildItem, New-Item, and Get-Random are implementation details.

Otter programmers should use Otter:

create folder "Backup"
get files in "Pictures" into pictures
random number from 1 to 6 into roll

3. One Obvious Canonical Way

When two syntaxes do the same thing, prefer one canonical form.

Do not accumulate synonyms merely because they are valid English.

Examples:

create creates something that did not exist.

is assigns or calculates a value.

into names a destination for an operation result.

increase / decrease mutate numeric values.

each iterates over a collection.

4. is Assigns the Value of an Expression

is should work for both literal assignment and calculated expressions.

name is "Jeff"
age is 29
loggedIn is true

Arithmetic expressions use the same rule:

number is number1 plus 5
total is price plus tax
remaining is balance minus payment
area is width times height
average is total divided by count

Equivalent C#:

int number = number1 + 5;

Otter:

number is number1 plus 5

New direction

For ordinary arithmetic assignment, prefer:

total is price plus tax

over the older:

price and tax make total

The older arithmetic use of make should be reviewed for deprecation before Otter 1.0.

5. Arithmetic Vocabulary

Canonical readable arithmetic operators should include:

total is number1 plus number2
difference is number1 minus number2
product is number1 times number2
result is number1 divided by number2

Potential extended math should follow the same readable principle:

amount is 20 percent of price
result is 2 to the power of 8

Advanced mathematical operations may be library/runtime functions when that is clearer than adding grammar.

6. Mutation Uses Action Words

Calculating a value and changing a value are different ideas.

Calculation:

newScore is score plus 5

Mutation:

increase score by 5

Increment by one:

increase score

Equivalent to score++.

Decrement by one:

decrease lives

Larger changes:

increase score by 10
decrease health by damage

Rule

Expressions describe values. Action words describe mutation.

Do not use:

number is increase number

because increase is an action, not a value-producing expression.

7. Do Not Inherit Operator Tricks From Other Languages

Otter should not reproduce confusing behaviors merely because another language has them.

Otter does not need separate prefix/postfix increment semantics.

Use:

increase number

instead of concepts equivalent to:

++number
number++
number = number++

One readable instruction should have one obvious effect.

8. each Is the Canonical Collection Loop

The preferred Otter iteration form is:

each product in products
    say name of product
.

Filesystem example:

each file in files
    if extension of file is ".jpg"
        copy file to "Backup"
    .
.

This is preferred over the older:

for each product in products

Rule

each <item> in <collection> means:

Run the following block once for every item in the collection.

product in products alone is not sufficient because it does not clearly communicate repetition.

9. into Means “Put the Result Here”

into has one protected meaning across Otter:

Store the result of this operation in the named destination.

Examples:

get files in "Pictures" into pictures
split sentence by " " into words
random number from 1 to 10 into number
replace "Jeff" with "Jeffrey" in name into fullName

10. into May Begin a Continuation Line

Simple operations may stay on one line:

get files in "Pictures" into pictures

Long operations should be allowed to wrap at grammatical continuation points:

get files in "Pictures" and subfolders
    into pictures

Future filtering syntax may read:

get files in "Pictures" and subfolders
    where extension of file is ".jpg"
    and size of file is greater than 5000000
    into pictures

The one-line and multiline forms must have the same meaning.

Potential continuation words include where, and, with, by, in, and into, but only when the active grammar expects them.

11. create Creates External Resources

Use create when an instruction causes a real external or domain resource to exist through a provider or runtime action — a file, a folder, a database row, an account with a service. create is not how ordinary in-memory objects are built.

create folder "Backup"
create file "notes.txt"

A future database/API example, once that grammar exists:

create user in database
    name is "Jeff"
    age is 29
.

That is genuinely creating something outside the program. An ordinary structured value that only exists in memory still uses is a thing:

registration is a thing
    name is "Jeff"
    age is 29
.

Do not overload make for this purpose, and do not use create as a second way to build an ordinary object — that is what is a thing already does.

Rule

create causes an external/domain resource to exist through a provider or runtime action.
is a thing builds an ordinary in-memory object.
is assigns/calculates a value.
into receives an operation result.

12. Filesystem Syntax Must Hide Shell Plumbing

Otter filesystem programs should never require users to know shell or PowerShell commands.

PowerShell:

New-Item -ItemType Directory -Path "Backup"

Otter:

create folder "Backup"

PowerShell or .NET APIs may implement the behavior underneath, but they are not Otter syntax.

13. Destructive and Expensive Behavior Must Be Visible

A harmless-looking instruction must not conceal unusually destructive work.

delete folder "Photos"

must not silently mean recursive deletion.

If recursive deletion is later supported, the destructive intent should be explicit:

delete folder "Photos" and everything in it

Recursion in discovery is likewise explicit:

get files in "Pictures" and subfolders into pictures

14. stop Ends the Current Executing Process Without a Value

For functions, event handlers, routes, and similar executable blocks, stop should mean:

Stop executing the current callable/process immediately without producing a return value.

Example:

when loginButton is clicked
    if text of usernameBox is empty
        text of message is "Enter your username."
        stop
    .
.

Returning a value still uses return:

to double number
    answer is number times 2
    return answer
.

Rule

stop = finish now, no returned value.

return value = finish and give a value back.

The exact scope targeted by stop must be specified before implementation so it never ambiguously means “stop the entire application.”

15. No Invisible Mutation

Operations that appear to inspect or calculate must not secretly alter their source.

uppercase of name

must not mutate name.

Explicit mutation should read like an action:

replace "Jeff" with "Jeffrey" in name
increase score
decrease health by 10

With an into destination, the original should remain unchanged unless explicitly defined otherwise:

replace "Jeff" with "Jeffrey" in name into fullName

16. Structural Words Are Not Global Filler

Earlier Otter design notes considered words such as of, to, from, and with as possible filler.

Part 4 supersedes that idea.

Structural relationship words include:

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
by

These words may carry grammar and meaning and must never be globally removed as filler.

Optional filler may include carefully controlled words such as:

the
a
an
then
called
value

only where removing the word cannot change meaning.

17. Prefer Contextual Keywords Over Unnecessary Reserved Words

As Otter grows, ordinary English words should not automatically become permanently forbidden variable names merely because they appear in one grammar production.

If grammatical position can safely disambiguate a word, contextual treatment is preferred.

Example:

day is 7
say day

add 7 days to date

Rule

Reserve a word globally only when doing so is necessary to prevent real ambiguity.

18. Property Access Remains property of object for Now

The current canonical property syntax remains:

name of person
text of nameBox
extension of file
city of address of user

Assignment:

text of message is "Hello!"

The period remains reserved for ending blocks.

Under Review: possessive property access

The following syntax is attractive:

person's name
nameBox's text
user's address's city

But possessive access introduces apostrophe tokenization, chaining rules, naming edge cases, and possible duplication with of.

Therefore 's property access is not canonical yet.

Otter should ultimately prefer one canonical property-access model rather than permanently supporting two equivalent styles.

19. Objects / Structured Values Remain is a thing for Now

Current form:

registration is a thing
    name is text of nameBox
    email is text of emailBox
.

Under Review

A future syntax such as:

registration has
    name is text of nameBox
    email is text of emailBox
.

may read more naturally, but it should not replace is a thing without a dedicated design review.

Do not add both permanently merely as synonyms.

20. Otter Web Should Express Intent, Not Browser Plumbing

Otter Web should cover the three jobs commonly split between HTML, CSS, and JavaScript:

what exists

how it looks

what it does

Example:

helloButton is a button
    text is "Say Hello"
.

message is a text
    value is ""
.

when helloButton is clicked
    text of message is "Hello!"
.

A web backend may generate DOM/event code, but Otter programmers should not have to write DOM selectors, event-listener plumbing, callbacks, or framework ceremony for ordinary behavior.

Rule

Do not make the programmer explain how platform plumbing works when the intent can be represented precisely in Otter.

21. Web State Should Remain Ordinary Otter State

Web development should not require a separate dialect for normal variables, conditions, loops, functions, lists, or objects.

count is 0

when addButton is clicked
    increase count
    text of counter is count
.

A web runtime may implement reactive updates internally.

22. Web Collections Should Reuse each

Rendering collections should use ordinary Otter iteration.

each product in products
    card is a card
        title is a text
            value is name of product
        .
    .

    put card in productGrid
.

Do not invent a separate .map()-style construct merely because a JavaScript backend uses one.

23. Async Plumbing Should Be Hidden When Sequential Intent Is Clear

An Otter programmer should be able to write:

get json from "/api/users"
    into users

without requiring Promise, callback, async, or await syntax for ordinary use.

The runtime must still define failure, ordering, concurrency, and cancellation precisely.

24. Same Otter Across Targets

Core language behavior should remain consistent across targets such as:

otter run
otter build web
otter build desktop
otter build android

Targets may expose additional libraries, but core Otter concepts must not silently change meaning.

25. Small Programs Require No Project Ceremony

A single-file program remains first class:

otter hello.ot

Recommended project creation:

otter new console World

Potential templates:

otter new console World
otter new automation FileOrganizer
otter new web MyWebsite
otter new desktop MyApp
otter new mobile MyApp
otter new game MyGame

Avoid unnecessary flags when a positional argument is clear.

26. Project Metadata Is Tooling, Not Language Syntax

A project may eventually contain:

World/
├── main.ot
├── otter.json
└── README.md

Potential otter.json:

{
    "name": "World",
    "version": "0.1.0",
    "entry": "main.ot"
}

The exact manifest belongs to CLI/tooling design and should not complicate ordinary .ot source files.

27. Errors Must Speak Otter

Compiler/runtime diagnostics should explain problems in Otter terms.

Avoid exposing implementation internals such as parser class names, AST node names, PowerShell $null, or JavaScript Promise errors when a useful Otter explanation can be produced.

28. A Feature Is Not Shipped Until It Works End to End

A language feature is complete only when the whole path exists:

Decision / specification
        ↓
Contract
        ↓
Lexer / parser
        ↓
Runtime
        ↓
Tests
        ↓
Real .ot acceptance example
        ↓
Official documentation

Do not call a runtime-only or parser-only capability implemented.

29. Prefer Real-Program Pressure Over Speculative Syntax

Use real programs to discover missing language features.

Good milestone programs include:

File Inspector

File Organizer

Backup utility

JSON-configured automation

Small console game

Simple web page

Do not add syntax merely because another language has it.

30. Part 4 Core Rules

Otter is controlled English, not natural-language guessing.

PowerShell is an implementation detail, not the definition of Otter.

Prefer one canonical syntax for one common operation.

is assigns/calculates the value of an expression.

Prefer number is number1 plus 5 over arithmetic make.

Mutation uses explicit action words.

increase number is the readable increment operation.

decrease number is the readable decrement operation.

each item in items is the preferred collection loop.

into always identifies where an operation result is stored.

Long statements may place into and other defined continuations on following lines.

create causes a resource/entity to exist.

Destructive, recursive, or consequential behavior must be visible in source.

stop exits the current callable/process without a value; return value returns a value.

Inspection/calculation must not secretly mutate values.

Structural words are never globally stripped as filler.

Prefer contextual keywords when grammar can disambiguate safely.

property of object remains canonical until possessive access is separately approved.

is a thing remains canonical until an object syntax change is separately approved.

Web syntax should express interface and application intent instead of DOM/framework plumbing.

Core Otter semantics remain consistent across runtime targets.

Tiny programs must remain runnable without project ceremony.

Errors should describe Otter, not implementation internals.

A feature is shipped only when it is reachable, tested, exemplified, and documented.

Real Otter programs should drive future syntax decisions.

Readable like English. Precise like code.