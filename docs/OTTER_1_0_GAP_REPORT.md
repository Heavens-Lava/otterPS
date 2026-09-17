# Otter 1.0 Gap Report

Companion to `docs/OTTER_1_0_LANGUAGE_AND_RUNTIME_INVENTORY.md`. That
document says what exists and what was verified; this one says what to
do about it before calling it Otter 1.0. Nothing here should be read as
"add more features" - the point of this report is the opposite: to
separate what actually blocks a dependable 1.0 from what doesn't, so V1
stays finishable.

---

## A. V1 RELEASE BLOCKERS

Things that, left as they are, would mean shipping "Otter 1.0" while its
own documentation and a user's mental model disagree with what the
software does.

### A1. `use` (modules) is fully, deliberately disabled - not "needs one more pass"

Jeff's own roadmap message assumed the module resolver was implemented
and only needed final certification (Gate 2). It is not implemented -
it is **explicitly rejected** at runtime with `'use' is not supported in
Otter 1.0.`, unconditionally, confirmed by real execution. This isn't a
blocker because modules are missing - a language can ship v1 without
modules. It's a blocker because **the roadmap's own picture of what's
already built is wrong on this point**, and Gate 2 as written cannot be
completed (there is nothing to certify). Decision needed: either build
modules for real before 1.0, or formally cut them from the 1.0 scope and
correct the roadmap. Given this project's own stated bias ("I would not
delay Otter 1.0 for..." + "the default answer should now be: post-V1"),
cutting `use` from 1.0 and shipping it as a clearly-documented "not yet"
is the consistent choice - but that is Jeff's call, not mine to make
unilaterally.

### A2. HTTP only works through `otter web`, not `otter run`

Also listed in Jeff's roadmap as an already-solid part of the V1
runtime, alongside file operations. It is not - `HttpGet`/`HttpPost`/
`HttpPut`/`HttpDelete` have **zero** implementation in
`Otter.Interpreter.psm1` (confirmed: zero grep matches) and throw "I do
not know how to run a HttpGet statement yet." on every attempt via
`otter run`. The JS compiler backend does implement all four, verified
by successfully compiling a real `.ot` file with all four HTTP verbs via
`otter web`. This is a blocker for the same reason as A1: a user writing
an ordinary command-line Otter program (the CLI use case Jeff's own "boringly
reliable" release vision centers on) cannot use HTTP at all, despite it
reading like normal Otter syntax and parsing without complaint. Decision
needed: implement HTTP in the interpreter (real, scoped work -
`Invoke-WebRequest`/`Invoke-RestMethod` map directly), or explicitly
document HTTP as web-target-only for 1.0 and correct anywhere that
implies otherwise.

### Resolved: condition-only `and` / `or`

Source-word `and` no longer silently lowers to arithmetic in ordinary
expressions outside `if`/`while`; both connectives now issue an Otter syntax
diagnostic naming their valid context. The historical
`left and right make result` form remains supported for compatibility.
Numeric addition uses `plus` or `+`. The negative
fixture `conformance/negative/boolean_operators_outside_conditions.ot` is
verified through the real `otter check` entry point.

### Resolved: function values

A declared function can now be used as an expression: `result is myFunc
arg1`. Existing statement calls and `... make result` capture remain valid.
`conformance/core/function_return_expression.ot` was run through `otter run`,
and differential interpreter/JavaScript parity covers the expression form.

---

## B. V1 SHOULD-HAVE (real gaps, not release-blocking on their own)

- **`run "x"` vs `run command "x"` return genuinely different result
  shapes**, and nothing in the surface syntax hints at this. Should be
  stated as an explicit, named rule in the 1.0 spec (Gate 4), not left
  implicit.
- **`delete "path"` (no `file` keyword) is a syntax error; `delete file
  "path"` is required.** Low severity (a clear error, not silent
  wrongness), but this exact point was gotten wrong in this very
  conversation's own earlier informal cheat-sheet before this audit
  caught it - a sign it's a natural, likely mistake for real users too.
  Worth a line in the spec's filesystem section calling it out
  explicitly.

The typed-object initializer and literal-name collision findings are resolved
by the V1 semantic-correction pass; their negative fixtures now protect the
diagnostics from regression.

---

## C. POST-V1 (explicitly not release-blocking; noted only so they aren't
accidentally treated as gaps)

- The entire UI/declarative-reactivity/web-server surface
  (`CreateUiResource`, `When`, `PutIn`, `Show`, `WebRoute`, `Respond`,
  `StartServer`, `ListenServer`, `UiElement`, `UiLayout`, `StateDef`,
  `DeriveDef`, `Watch`) - out of scope for this sweep by design, has its
  own coverage, not touched here.
- `MemoDef`, `Lifecycle` (`on start`/`on close`), `SharedState`
  (`shared`), `UiAction` (`focus`/`hide`), `UiEvent`, `UiAnimation`,
  `Await` - all **already, deliberately** rejected with "not supported
  in Otter 1.0" messages. These are not gaps to close; they are
  decisions already on record in the source. Listed here only so a
  future pass doesn't mistake a confirmed decision for an oversight.
  (Note: `Await`'s parser grammar has uncommitted, in-progress work as
  of this sweep - see the inventory's caveat under A12 - which will need
  its own decision when it lands, separate from this report.)
- Symbolic links, remote administration (WinRM), SSH, printing, and
  power actions all have real, working command-construction and error
  paths, verified as far as this environment safely allows (no admin
  privileges/Developer Mode, no WinRM-enabled target, no real
  printer/SSH host, and a deliberate choice never to execute a real
  shutdown/restart). Their success paths are unverified **in this
  environment**, not unimplemented - this is category D below, not a
  release blocker, and not something to chase down by relaxing this
  project's own established safety practices.
- Password hashing via a dedicated, purpose-built algorithm (PBKDF2/
  bcrypt-shaped, distinct from D91's general-purpose hashing),
  public-key cryptography, signing/verification, certificate APIs, TLS
  provider, OS keychain/Credential-Manager-style providers - real,
  legitimate future work, explicitly out of the "reduced roadmap" Jeff
  already proposed for 1.0.
- Everything in the original 758-item platform checklist not already
  covered above - unchanged from Jeff's own framing: that list is the
  long-term destination, not the V1 release checklist.

---

## D. IMPLEMENTED BUT NEEDS PRODUCTION CERTIFICATION

Real, working code paths that this sweep either didn't re-exercise fresh
(because this project's own committed regression suite already covers
them thoroughly, D-numbered, with real verification at the time) or
couldn't safely exercise in this specific environment:

| Capability | Why not fresh-verified here | Where it *was* verified |
|---|---|---|
| `kill process` / `set priority of process` / `wait for process` | destructive/would disturb a real running process | D70/D71 regression suite |
| Symbolic link creation, ownership/permissions checks | this sandbox lacks Administrator/Developer Mode (confirmed: the real, friendly privilege error fired correctly) | D73/D74 regression suite, on a privileged machine |
| Event log reads | not re-run fresh, no reason to expect regression | D79 regression suite |
| HMAC (`hash ... with key ...`) | plain hash path was re-verified fresh; HMAC path uses the identical dispatch, not re-run separately | D91 regression suite |
| `atomically`-qualified writes, file-lock checks | not re-run fresh | D72 regression suite |
| `get folders in`, `and subfolders` | shares the identical grammar/dispatch path as `get files in`, which *was* re-verified fresh | D20/D21-era work |
| Power actions (lock/sign out/restart/shut down) | command construction verified at D82; real execution deliberately never attempted, including this pass, to avoid disrupting the working session | D82 |
| Printing | real print-job completion never verified against a physical/virtual printer | D83 |
| Remote administration (WinRM) | WinRM confirmed disabled in this environment | D84 |
| SSH command execution | no real SSH target available | D85 |
| Interactive file/folder/save dialogs (`choose file`/`choose folder`/`choose file to save`) | blocking, interactive OS dialogs - cannot run in a non-interactive sweep | parses correctly; runtime never exercised in any automated pass |

None of these are new findings of instability - they are exactly what
this project's own SPEC-DECISIONS.md already says about each of them.
Listed here so the certification status is in one place rather than
scattered across ninety D-number entries.

---

## E. IMPLEMENTATION EXISTS BUT IS CURRENTLY UNREACHABLE

- **HTTP GET/POST/PUT/DELETE** - fully implemented in
  `Otter.Compiler.JavaScript.psm1`, completely absent from
  `Otter.Interpreter.psm1`. (Also listed as A2 above, since the
  contradiction with the roadmap's assumption makes it a blocker-level
  finding, not merely a reachability gap.)

No other cases of this category were found in the in-scope surface
during this sweep - everything else that parses either runs through the
interpreter for real or is one of the explicit, documented exclusions in
Section C.

---

## Summary counts

| | Count |
|---|---|
| Total parser statement/expression kinds (`NodeKind`) | 127 |
| Total distinct token kinds (`TokenKind`) | 152 |
| In scope for this sweep (excludes UI/web-server surface) | 114 |
| PRODUCTION VERIFIED this sweep (fresh, real `otter run`) | ~55 |
| Verified via this project's own prior committed regression tests, not re-run fresh | ~35 |
| PARSES BUT RUNTIME UNVERIFIED (interactive/environment-limited) | ~12 |
| EXPLICITLY NOT SUPPORTED IN V1 (confirmed decisions already made) | 8 |
| TARGET-SPECIFIC (web-only, absent from interpreter) | 4 |
| Semantic inconsistencies fixed in the V1 correction pass | 4 (`and`/`or`, function values, literal bindings, typed blocks) |
| Remaining V1 release decisions | 2 (`use` scope and HTTP target classification) |

**Bottom line:** the language core is in a genuinely frozen-ready shape. The
audited semantic traps are fixed and covered through parser tests, real CLI
fixtures, and function-call parity. The remaining V1 work is product
classification, not casual feature growth: formally exclude modules or
implement them, and explicitly retain HTTP as web-target-only or design a
portable provider contract.
