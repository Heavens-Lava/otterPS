Otter Language Rules --- Part 2

Readable like English. Precise like code.

This document extends the core Otter language rules with frontend/UI
syntax, natural property access, optional natural-language filler words,
networking, web servers, APIs, CRUD, databases, HTTP, ports, processes,
and related application features.

These rules are design targets for Otter. They should remain consistent
with the core philosophy: prefer syntax that can be understood when read
aloud.

1. Named Frontend Controls

Frontend controls should have ordinary Otter variable names.

nameBox is a text box
    placeholder is "Enter your name"
.

helloButton is a button
    text is "Say Hello"
.

message is a text
    value is ""
.

Names such as nameBox, helloButton, and message identify the
control so it can be referenced later.

The name belongs to the programmer. The type comes after is a.

Examples:

emailBox is a text box
passwordBox is a password box
saveButton is a button
gameList is a list
mainWindow is a window

This keeps UI code readable while still giving every control a stable
programmatic identity.

2. Property Access Uses of

Otter does not use a period for member/property access.

Do not write:

nameBox.text
person.name
file.extension
window.width

Write:

text of nameBox
name of person
extension of file
width of window

Properties can also be assigned:

text of message is "Hello"
width of mainWindow is 800
background of helloButton is blue
visible of menu is false

Example:

nameBox is a text box
    placeholder is "Enter your name"
.

helloButton is a button
    text is "Say Hello"
.

when helloButton is clicked
    text of message is "Hello" text of nameBox
.

Nested properties continue naturally:

city of address of user

3. Period Rule

A period is reserved for ending a block, function, condition, event,
process, object definition, or other multi-line instruction.

It is not property-access punctuation.

Condition:

if age is at least 18
    say "Adult"
.

Function:

to greet name
    say "Hello" name
.

Event:

when helloButton is clicked
    say "Hello" text of nameBox
.

Nested blocks use one period for each block being closed:

when loginButton is clicked
    if text of usernameBox is empty
        say "Enter your username."
    otherwise
        say "Welcome" text of usernameBox
    .
.

A period inside quoted text remains ordinary text:

say "Hello."

4. Optional Natural-Language Filler Words

Otter may allow carefully defined optional words that improve
readability without changing program behavior.

Possible filler words include:

the
a
an
then
called
value

They must only be optional where the grammar explicitly permits them.

The following words are STRUCTURAL GRAMMAR, not filler. They carry
meaning and must never be discarded:

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

In particular, `of` establishes property ownership:

name of person

Removing `of` would destroy the expression. A preprocessing pass that
strips filler words must never touch a structural word.

For example, these may be equivalent:

if age is at least 18
    say "Adult"
.

if the age is at least 18
    say "Adult"
.

Another example:

add 5 to score

add the value 5 to score

The parser should not globally delete filler words. It should recognize
them only in grammar positions where they are allowed.

Rule: Removing an optional filler word must not change the meaning
of the program.

5. Frontend Windows and Pages

app is a window
    title is "My Otter App"
    width is 500
    height is 300
.

Pages can use the same model:

homePage is a page
    title is "Home"
.

Common frontend types may include:

window
page
text
button
text box
password box
image
list
table
panel
row
column
menu
checkbox
switch

6. Frontend Properties

Common properties may include:

text
value
title
placeholder
width
height
size
background
text color
padding
margin
visible
enabled

Example:

helloButton is a button
    text is "Say Hello"
    background is blue
    text color is white
    width is 150
    height is 40
    corners are rounded
.

7. Frontend Layout

Layout should describe intent naturally.

put heading at the top
put nameBox below heading
put helloButton below nameBox
put message below helloButton

Other possible forms:

put sidebar on the left
put content beside sidebar
put saveButton in the center

Responsive behavior can use ordinary Otter conditions/events:

when screen is smaller than 700
    put sidebar above content
.

8. Frontend Events

Events use when.

when helloButton is clicked
    say "Hello" text of nameBox
.

Possible events include:

when button is clicked
when text box changes
when page opens
when mouse enters
when key is pressed

Example:

when clearButton is clicked
    text of nameBox is ""
    focus nameBox
.

9. Complete Frontend Example

app is a window
    title is "Otter Greeting App"
    width is 500
    height is 300
.

heading is a text
    value is "Welcome to Otter"
    size is 28
.

nameBox is a text box
    placeholder is "Enter your name"
.

helloButton is a button
    text is "Say Hello"
.

message is a text
    value is ""
.

put heading at the top
put nameBox below heading
put helloButton below nameBox
put message below helloButton

when helloButton is clicked
    text of message is "Hello" text of nameBox
.

The control name comes first when defining the control
(nameBox is a text box), while properties are read naturally
(text of nameBox).

10. Web Servers and Ports

A web server may be described as an Otter object:

server is a web server
    port is 8080
    host is "localhost"
.

A shorter server form may also be supported:

listen on port 8080

Routes can be event-like:

when server receives a request at "/hello"
    respond with "Hello from Otter!"
.

Otter should keep networking syntax readable while the runtime handles
the underlying sockets/server implementation.

11. Port Utilities

Otter should make common port operations approachable.

if port 8080 is in use
    say "Port 8080 is busy."
.

Find the process using a port:

process on port 8080 becomes serverProcess

Stop it:

stop serverProcess

Find an available port:

find an open port from 8000 to 9000 into port

say "Using port" port

12. HTTP Requests

Simple HTTP operations should use familiar verbs.

get "https://example.com/api/users" into users

post user to "https://example.com/api/users" into response

put user to "https://example.com/api/users/5"

delete from "https://example.com/api/users/5"

A more explicit form may be available when needed:

send GET to "/users"
send POST to "/users" with user
send PUT to "/users/5" with user
send DELETE to "/users/5"

13. Web API Routes

api is a web server
    port is 5000
.

when api receives GET at "/users"
    get all users from database into users
    respond with users as json
.

POST example:

when api receives POST at "/users"
    body of request as json becomes user

    create user in database
        name is name of user
        email is email of user
    .

    respond with user as json and status 201
.

14. CRUD Vocabulary

Otter CRUD uses the ordinary verbs:

create
get
update
delete

Create:

create user with
    name is "Jeff"
    age is 29
.

Read:

get user where id is 5 into user

Update:

update user where id is 5
    name is "Jeffrey"
.

Delete:

delete user where id is 5

The same vocabulary should work across supported data providers where
practical.

15. Databases

Example SQLite configuration:

database is a sqlite database
    file is "app.db"
.

Example SQL Server configuration:

database is a sql server database
    server is "localhost"
    database name is "OtterApp"
.

Database providers may differ internally, but ordinary CRUD syntax
should remain as consistent as possible.

16. Database CRUD

Create:

create user in database
    name is "Jeff"
    age is 29
.

Get all:

get users from database into users

Get one:

get user from database where id is 5 into user

Update:

update user in database where id is 5
    age is 30
.

Delete:

delete user from database where id is 5

17. Database Tables

A table may eventually be described naturally:

users is a database table
    id is an automatic number
    name is text
    email is text
.

The language should avoid forcing SQL syntax for ordinary application
development.

Advanced SQL access may still be exposed by a library when necessary.

18. Transactions

begin transaction in database

try
    create order in database
    update inventory in database
    commit transaction
otherwise
    rollback transaction
.

Transaction behavior must be deterministic and should never silently
commit failed operations.

19. Request Data

Request properties follow the same of rule.

body of request
authorization of request
method of request
path of request

JSON request body:

body of request as json becomes user

Query values:

search is query "search" of request

The same property grammar used by UI objects should apply to web/request
objects.

20. Responses

Basic response:

respond with "Hello!"

JSON:

respond with users as json

Status:

respond with user as json and status 201

Error:

respond with "Not Found" and status 404

21. Environment Values

port is environment value "PORT"

A fallback may be expressed naturally:

port is environment value "PORT" or 8080

Secrets should not be printed automatically or exposed in normal error
output.

22. Processes

Run a program:

run "notepad.exe"

Capture a process:

run "myserver.exe" as serverProcess

Stop it:

stop serverProcess

Process properties use of:

id of serverProcess
name of serverProcess
status of serverProcess

23. Network Connections

Lower-level networking may eventually use:

connect to "192.168.1.20" on port 5000 as connection

send "Hello" through connection

message is received from connection

close connection

This should be implemented as a library/runtime capability rather than
complicating the core language grammar unnecessarily.

24. Authentication Example

when request arrives
    token is authorization token of request

    if token is not valid
        respond with "Unauthorized" and status 401
        stop
    .
.

Authentication mechanisms should come from libraries/providers rather
than hard-coding one authentication system into the core grammar.

25. Core Application Vocabulary

Otter should prefer a small reusable vocabulary instead of inventing
unrelated syntax for every technology.

Important verbs include:

create
get
update
delete
add
remove
send
receive
listen
connect
respond
read
write
run
start
stop
open
close
show
hide
put
move
focus
refresh

Important relationship words include:

from
to
with
where
into
on
at
of
in
as

Libraries should reuse this vocabulary wherever the meaning remains
clear.

26. Property IntelliSense Consideration

Property-first syntax such as:

text of nameBox

is intentionally different from conventional:

nameBox.text

The tradeoff is that traditional object. IntelliSense cannot be
triggered in exactly the same way.

An Otter-aware editor should compensate.

When the cursor is on nameBox, completion can show:

Properties
    text
    placeholder
    width
    height
    visible
    enabled

Actions
    focus
    show
    hide
    clear

Typing:

background of

could suggest only objects that support a background property.

This keeps the language readable without giving up intelligent editor
assistance.

27. Design Rule for Advanced Features

Advanced functionality must not automatically mean complicated syntax.

The runtime and libraries may be complex internally while Otter remains
readable externally.

For example:

if port 8080 is in use
    process on port 8080 becomes process
    stop process
.

should be allowed to hide the platform-specific networking/process APIs
required to perform those operations.

Likewise:

get users from database into users

may internally require connections, commands, parameters, readers,
serialization, and error handling.

Otter's job is to express the programmer's intent clearly.

28. Part 2 Core Rules

Frontend controls receive normal programmer-defined names such as
nameBox, helloButton, and mainWindow.

Properties use property of object, not object.property.

A period is reserved for closing a block/process and is not used for
property access.

Optional filler words may improve readability but must never alter
meaning.

UI uses named controls, natural properties, layout instructions, and
when events.

Networking should use readable concepts such as listen, port,
connect, send, and receive.

CRUD uses create, get, update, and delete.

Database providers should share common Otter syntax where practical.

HTTP and APIs should use familiar HTTP verbs without requiring
low-level boilerplate.

Advanced platform behavior belongs in the runtime or libraries
rather than making the language syntax complicated.

Otter-aware IntelliSense should understand Otter grammar instead of
requiring conventional dot notation.

When choosing between equivalent syntaxes, prefer the version that
is easiest to understand when read aloud.

Readable like English. Precise like code.