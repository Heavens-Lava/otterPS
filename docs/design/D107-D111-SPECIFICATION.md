# D107–D111 Specification (as approved)

Recorded verbatim from the specification Jeff supplied on 2026-09-23 (designed with ChatGPT),
from which D107 (TCP), D108 (UDP), D109 (cryptography), D110 (drag and drop) and D111
(credential vault) were implemented. It is the design source cited by those entries in
`SPEC-DECISIONS.md`. It is kept as supplied; where the implementation differs, the
ledger entry says so.

```text
D107–D111 — REMAINING LANGUAGE GRAMMAR
TCP, UDP, CRYPTO, DRAG/DROP, CREDENTIAL VAULT

These syntax decisions are authoritative unless an existing Otter grammar
rule conflicts with them.

GENERAL DESIGN RULES

1. Prefer normal English.
2. Reuse existing Otter vocabulary.
3. Do not expose runtime/framework-specific objects.
4. bytes remains the standard binary type.
5. Networking uses the event system where appropriate.
6. Unsupported platform behavior must fail clearly, never silently no-op.
7. Security-sensitive operations must use safe defaults.
8. Do not silently convert between text and bytes.


============================================================
D107 — TCP
============================================================

GOAL

First-class TCP client connections.

TCP is a byte stream, not a message protocol.

Do NOT pretend TCP has WebSocket-style message boundaries.


------------------------------------------------------------
1. CONNECT
------------------------------------------------------------

Canonical syntax:

    connect to tcp "example.com" on port 8080 and call it connection

Variables:

    host is "example.com"
    port is 8080

    connect to tcp host on port port and call it connection


------------------------------------------------------------
2. CONNECT EVENT
------------------------------------------------------------

    on connect of connection
        say "Connected"
    .


------------------------------------------------------------
3. RECEIVE DATA
------------------------------------------------------------

Because TCP is a byte stream:

    on data from connection
        data is received data
        say count of data
    .

`received data` is always D102 bytes.

Do NOT call this:

    received message

TCP does not preserve application message boundaries.


------------------------------------------------------------
4. SEND BYTES
------------------------------------------------------------

    data is bytes from text "Hello"

    send data through connection


------------------------------------------------------------
5. SEND TEXT
------------------------------------------------------------

Do NOT silently convert text into bytes.

Require:

    send bytes from text "Hello" through connection

or:

    message is bytes from text "Hello"
    send message through connection

This keeps the text/binary boundary explicit.


------------------------------------------------------------
6. CLOSE
------------------------------------------------------------

    close tcp connection


------------------------------------------------------------
7. CLOSE EVENT
------------------------------------------------------------

    on close of connection
        say "Connection closed"
    .


------------------------------------------------------------
8. ERROR EVENT
------------------------------------------------------------

    on error of connection
        say network error
    .


------------------------------------------------------------
9. STATE
------------------------------------------------------------

Support:

    connection is connecting
    connection is connected
    connection is closed

And:

    state of connection

returns:

    "connecting"
    "connected"
    "closed"


------------------------------------------------------------
10. REMOTE INFORMATION
------------------------------------------------------------

Provide:

    remote address of connection
    remote port of connection


------------------------------------------------------------
11. TLS
------------------------------------------------------------

TCP itself remains TCP.

Do NOT overload D107 with TLS grammar.

Secure stream/TLS support can receive its own design later.


------------------------------------------------------------
12. TCP SERVER
------------------------------------------------------------

Reserve server grammar now:

    listen for tcp on port 8080 and call it server

    on connection to server
        connection is incoming connection
    .

But unless TCP servers are explicitly part of D107's implementation scope,
client support may ship first.

Do NOT implement an incompatible server syntax later.


------------------------------------------------------------
13. TCP CORE GRAMMAR
------------------------------------------------------------

    connect to tcp <host-expression>
        on port <port-expression>
        and call it <identifier>

    on connect of <connection>
        <statements>
    .

    on data from <connection>
        <statements>
    .

    send <bytes-expression> through <connection>

    close tcp <connection>

    on close of <connection>
        <statements>
    .

    on error of <connection>
        <statements>
    .

Context:

    received data
    network error

Properties:

    state of <connection>
    remote address of <connection>
    remote port of <connection>


------------------------------------------------------------
14. TCP EXAMPLE
------------------------------------------------------------

    connect to tcp "localhost" on port 9000 and call it connection

    on connect of connection
        message is bytes from text "Hello from Otter"
        send message through connection
    .

    on data from connection
        data is received data
        say text from bytes data
    .

    on error of connection
        say network error
    .

    on close of connection
        say "Disconnected"
    .


============================================================
D108 — UDP
============================================================

GOAL

First-class UDP datagram communication.

Unlike TCP, UDP preserves datagram boundaries.


------------------------------------------------------------
1. OPEN UDP
------------------------------------------------------------

UDP does not establish a connection in the same sense as TCP.

Use:

    open udp on port 9000 and call it socket

For an automatically assigned local port:

    open udp and call it socket


------------------------------------------------------------
2. RECEIVE DATAGRAM
------------------------------------------------------------

    on data from socket
        data is received data
    .

`received data` is bytes.


------------------------------------------------------------
3. SENDER INFORMATION
------------------------------------------------------------

Inside a UDP data event:

    sender address
    sender port


------------------------------------------------------------
4. SEND DATAGRAM
------------------------------------------------------------

    data is bytes from text "Hello"

    send data through socket
        to "127.0.0.1"
        on port 9000


------------------------------------------------------------
5. CLOSE UDP
------------------------------------------------------------

    close udp socket


------------------------------------------------------------
6. ERROR
------------------------------------------------------------

    on error of socket
        say network error
    .


------------------------------------------------------------
7. STATE
------------------------------------------------------------

    socket is open
    socket is closed

    state of socket


------------------------------------------------------------
8. UDP CORE GRAMMAR
------------------------------------------------------------

    open udp and call it <identifier>

    open udp on port <expression>
        and call it <identifier>

    send <bytes-expression>
        through <udp-expression>
        to <host-expression>
        on port <port-expression>

    on data from <udp-expression>
        <statements>
    .

    close udp <udp-expression>

Context:

    received data
    sender address
    sender port
    network error


------------------------------------------------------------
9. UDP EXAMPLE
------------------------------------------------------------

    open udp on port 9000 and call it socket

    on data from socket
        say "Received from " + sender address

        response is bytes from text "Hello"
        send response through socket
            to sender address
            on port sender port
    .


------------------------------------------------------------
10. PLATFORM RULE
------------------------------------------------------------

Console/Desktop:
    Full UDP support.

Normal browser Web runtime:
    TCP/UDP are unsupported.

Attempting them must produce an unsupported-platform diagnostic.

Do NOT emulate TCP/UDP using WebSockets.


============================================================
D109 — CRYPTOGRAPHY
============================================================

GOAL

Provide safe, high-level cryptographic primitives.

Do NOT make Otter programmers choose low-level cryptographic parameters
for ordinary tasks.


------------------------------------------------------------
1. RANDOM BYTES
------------------------------------------------------------

    data is secure random bytes 32

This MUST use a cryptographically secure random source.

This is different from Otter's seeded/general random feature.


------------------------------------------------------------
2. HASHING
------------------------------------------------------------

Canonical syntax:

    digest is sha256 of data

`data` must be bytes.

Result is bytes.

Also support:

    digest is sha384 of data
    digest is sha512 of data

Do NOT include obsolete hashes such as MD5 or SHA-1 in the recommended
D109 grammar.


------------------------------------------------------------
3. HASH EXAMPLE
------------------------------------------------------------

    data is bytes from text "Hello"

    digest is sha256 of data

    say hex from bytes digest


------------------------------------------------------------
4. HMAC
------------------------------------------------------------

    signature is hmac sha256 of data using key

Both `data` and `key` are bytes.

Also:

    hmac sha384 ...
    hmac sha512 ...


------------------------------------------------------------
5. PASSWORD HASHING
------------------------------------------------------------

Password hashing is NOT ordinary SHA hashing.

Provide a dedicated operation:

    hash password password and call it passwordHash

Verification:

    password password matches hash passwordHash

Example:

    password is "correct horse battery staple"

    hash password password and call it storedHash

    if password password matches hash storedHash
        say "Correct"
    .

The runtime chooses the approved password-hashing algorithm and parameters.

Do NOT expose raw password-hashing internals unless a later advanced
crypto design requires them.


------------------------------------------------------------
6. ENCRYPTION
------------------------------------------------------------

Use authenticated encryption only.

High-level syntax:

    encrypt data using key and call it encrypted

Decrypt:

    decrypt encrypted using key and call it decrypted

Inputs:
    data = bytes
    key = bytes

Outputs:
    encrypted = bytes
    decrypted = bytes

The runtime must use an approved authenticated encryption construction.

Do NOT expose insecure ECB/CBC-style convenience APIs.


------------------------------------------------------------
7. KEY GENERATION
------------------------------------------------------------

Provide:

    generate encryption key and call it key

The key is bytes suitable for Otter's default authenticated encryption.


------------------------------------------------------------
8. ENCRYPTION METADATA
------------------------------------------------------------

Nonce/IV/authentication metadata required by the selected construction
should be encoded into Otter's encrypted payload representation.

The programmer should NOT manually manage nonces for the normal API.

This avoids catastrophic nonce-reuse mistakes.


------------------------------------------------------------
9. ENCODED STORAGE
------------------------------------------------------------

Existing D102 handles representation:

    encoded is base64 from bytes encrypted

and:

    encrypted is bytes from base64 encoded


------------------------------------------------------------
10. CONSTANT-TIME SECRET COMPARISON
------------------------------------------------------------

Provide:

    first securely equals second

for bytes.

Example:

    if expected securely equals actual
        say "Valid"
    .


------------------------------------------------------------
11. CRYPTO CORE GRAMMAR
------------------------------------------------------------

    secure random bytes <number-expression>

    sha256 of <bytes-expression>
    sha384 of <bytes-expression>
    sha512 of <bytes-expression>

    hmac sha256 of <bytes-expression> using <bytes-expression>
    hmac sha384 of <bytes-expression> using <bytes-expression>
    hmac sha512 of <bytes-expression> using <bytes-expression>

    generate encryption key and call it <identifier>

    encrypt <bytes-expression>
        using <key-expression>
        and call it <identifier>

    decrypt <bytes-expression>
        using <key-expression>
        and call it <identifier>

    hash password <text-expression>
        and call it <identifier>

    password <text-expression>
        matches hash <hash-expression>

    <bytes-expression> securely equals <bytes-expression>


------------------------------------------------------------
12. CRYPTO SAFETY RULE
------------------------------------------------------------

Safe algorithms and parameters are runtime policy.

Otter source should express intent:

    hash password
    encrypt
    secure random

rather than forcing beginners to choose dangerous primitives.


============================================================
D110 — DRAG AND DROP
============================================================

GOAL

Make drag/drop behave like every other Otter UI event.


------------------------------------------------------------
1. DRAGGABLE CONTROLS
------------------------------------------------------------

Use a property:

    card is panel with draggable is true


------------------------------------------------------------
2. DRAG START
------------------------------------------------------------

    on drag of card
        say "Dragging"
    .


------------------------------------------------------------
3. DROP TARGET
------------------------------------------------------------

Use:

    dropZone is panel with accepts drops is true


------------------------------------------------------------
4. DROP EVENT
------------------------------------------------------------

    on drop on dropZone
        say "Dropped"
    .


------------------------------------------------------------
5. DRAGGED ITEM
------------------------------------------------------------

Inside a drop event:

    dragged item

Example:

    on drop on dropZone
        item is dragged item
    .


------------------------------------------------------------
6. FILE DROP
------------------------------------------------------------

Desktop/web applications commonly receive files.

Provide:

    on files dropped on dropZone
        files is dropped files
    .

`dropped files` is an Otter list of file values appropriate to the
runtime's existing file abstraction.


------------------------------------------------------------
7. LOOP THROUGH DROPPED FILES
------------------------------------------------------------

    on files dropped on dropZone
        for each file in dropped files
            say name of file
        .
    .


------------------------------------------------------------
8. DRAG DATA
------------------------------------------------------------

Allow application data to be attached explicitly:

    on drag of card
        set drag data to cardId
    .

Then:

    on drop on dropZone
        id is drag data
    .


------------------------------------------------------------
9. DROP POSITION
------------------------------------------------------------

Inside drop events expose:

    drop x
    drop y

These are coordinates relative to the receiving control/content area,
using Otter's established UI coordinate convention.


------------------------------------------------------------
10. DRAG/DROP CORE GRAMMAR
------------------------------------------------------------

Properties:

    draggable is true|false
    accepts drops is true|false

Events:

    on drag of <control>
        <statements>
    .

    on drop on <control>
        <statements>
    .

    on files dropped on <control>
        <statements>
    .

Context:

    dragged item
    dropped files
    drag data
    drop x
    drop y

Mutation:

    set drag data to <expression>


------------------------------------------------------------
11. EXAMPLE
------------------------------------------------------------

    card is panel with draggable is true
    board is panel with accepts drops is true

    on drag of card
        set drag data to "task-42"
    .

    on drop on board
        say drag data
        say drop x
        say drop y
    .


------------------------------------------------------------
12. FILE EXAMPLE
------------------------------------------------------------

    canvas is panel with accepts drops is true

    on files dropped on canvas
        for each file in dropped files
            say name of file
        .
    .


============================================================
D111 — CREDENTIAL VAULT
============================================================

GOAL

Provide secure application-secret storage without encouraging developers
to save passwords, API tokens, or credentials in plain text files.

The vault should use the operating system/platform's secure credential
storage where available.


------------------------------------------------------------
1. STORE A SECRET
------------------------------------------------------------

Canonical syntax:

    store secret "api-token" with value token

Example:

    token is "abc123"

    store secret "api-token" with value token


------------------------------------------------------------
2. READ A SECRET
------------------------------------------------------------

    token is secret "api-token"

Example:

    token is secret "github-token"


------------------------------------------------------------
3. CHECK FOR A SECRET
------------------------------------------------------------

    secret "api-token" exists

Example:

    if secret "api-token" exists
        token is secret "api-token"
    .


------------------------------------------------------------
4. DELETE A SECRET
------------------------------------------------------------

    delete secret "api-token"


------------------------------------------------------------
5. BYTES SECRETS
------------------------------------------------------------

Secrets may contain either:

    text
    bytes

Do NOT silently convert one to the other.


------------------------------------------------------------
6. VAULT NAMESPACE
------------------------------------------------------------

Secrets should automatically be scoped to the current Otter application.

Two unrelated Otter applications storing:

    "api-token"

must not automatically access each other's values.

The application identity should be part of the secure-storage namespace.


------------------------------------------------------------
7. NAMED VAULTS
------------------------------------------------------------

Do NOT require programmers to create/manage vault objects for ordinary
usage.

Keep:

    secret "name"

simple.

If named/shared vaults are ever needed, design them separately.


------------------------------------------------------------
8. SECRET DISPLAY
------------------------------------------------------------

Secret values must not automatically appear in:

- logs
- diagnostics
- debugger previews
- exception messages
- serialization
- crash reports

when the runtime can reasonably prevent it.

Do not implement a custom string representation that casually exposes
stored credentials.


------------------------------------------------------------
9. MISSING SECRET
------------------------------------------------------------

Reading a nonexistent secret must follow Otter's established missing-value
semantics.

If Otter does not have a suitable missing value, fail with a clear
diagnostic.

Never return an empty string and pretend the secret existed.


------------------------------------------------------------
10. UPDATE SECRET
------------------------------------------------------------

Storing the same name again replaces the existing secret:

    store secret "api-token" with value newToken


------------------------------------------------------------
11. CREDENTIAL VAULT CORE GRAMMAR
------------------------------------------------------------

    store secret <name-expression>
        with value <text-or-bytes-expression>

    secret <name-expression>

    secret <name-expression> exists

    delete secret <name-expression>


------------------------------------------------------------
12. CREDENTIAL EXAMPLE
------------------------------------------------------------

    if secret "service-token" exists
        token is secret "service-token"
    else
        ask secretly "API token:" and call it token
        store secret "service-token" with value token
    .

    use token

The actual consumer of `token` depends on the application.


------------------------------------------------------------
13. PLATFORM SECURITY
------------------------------------------------------------

Desktop/Console:

Use appropriate OS-backed credential protection where supported.

Do NOT implement the vault as:

    secrets.json
    .env
    plaintext configuration
    reversible hard-coded application key

Web:

Browser security/storage has materially different guarantees.

Do not claim ordinary localStorage is a secure credential vault.

If D111 cannot provide equivalent secure semantics in a normal browser,
the web runtime should report the feature as unsupported rather than
pretending localStorage is secure.


============================================================
IMPLEMENTATION ORDER
============================================================

Recommended order:

    D107 TCP
    D108 UDP
    D109 Crypto
    D110 Drag/Drop
    D111 Credential Vault

However:

- TCP and UDP must remain distinct abstractions.
- Crypto must build on D102 bytes.
- Credential Vault should use platform security, not home-grown encryption.
- Drag/drop belongs to UI runtimes and should reuse existing event syntax.


============================================================
CROSS-FEATURE EXAMPLE
============================================================

The features should compose naturally.

For example:

    if secret "server-key" exists
        key is secret "server-key"
    else
        generate encryption key and call it key
        store secret "server-key" with value key
    .

    connect to tcp "localhost" on port 9000 and call it connection

    on connect of connection
        message is bytes from text "Hello from Otter"

        encrypt message using key and call it encrypted

        send encrypted through connection
    .

    on data from connection
        encrypted is received data

        decrypt encrypted using key and call it message

        say text from bytes message
    .
```

## Accompanying note (same message)

For TCP, I would absolutely use on data from rather than on message from. TCP doesn't have messages; it's a stream of bytes. Teaching that distinction through the language itself is a good feature.

For UDP, I prefer:

send data through socket
    to "192.168.1.20"
    on port 9000

rather than pretending UDP “connects” the way TCP does.

For crypto, I'd intentionally make the easy syntax the safe syntax:

generate encryption key and call it key
encrypt data using key and call it encrypted
decrypt encrypted using key and call it original

That is much more aligned with Otter than forcing someone to understand AES modes, nonce sizes, tags, padding, and key lengths before they can safely encrypt something.

And the credential vault becomes wonderfully simple:

ask secretly "API key:" and call it key
store secret "api-key" with value key

then next launch:

key is secret "api-key"

Those five specs also fit the direction you've been taking Otter: the language stays approachable while the runtime handles the ugly platform-specific machinery underneath.
