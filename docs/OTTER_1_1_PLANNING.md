# Otter 1.1 planning — the OtterBoard proposals

Status: **for Jeff's decisions** (2026-09-30). Nothing here is decided until it
is recorded in `SPEC-DECISIONS.md` with a D-number.

Source: `docs/UI_RUNTIME_AND_PHRASES.md` (proposals P1–P9) on the
`proposal/1.1-otterboard` branch (pushed; based on `v1.0.0-rc.4`) and its local
successor `proposal/1.1-otterboard-next`, written while building OtterBoard,
the planned 1.1 flagship application. Already decided: D56 stands for 1.0 and
`hide`, `show` (as a UI action), `focus` and `clear` are planned for 1.1, on the
console and the web together (D56 affirmation, 2026-09-29).

---

## 1. Two of the proposals describe 1.0 bugs — verified on rc.7

P7 and P8 are written as 1.1 fixes, but they describe silent wrong results in
the 1.0 web target, which Otter forbids. Checked against rc.7 (`85227ab`) by
compiling small programs with `otter web` and running them in headless
Chromium:

| Claim | rc.7 result |
|---|---|
| P7: a handler registered inside a loop sees that iteration's values | **Reproduced.** Three buttons created in `for each n in numbers`, each setting a text to `n` when clicked: all three show `3`. Same at the top level and inside a function. |
| P8: in a plain browser tab, `read` of a file returns `""` | **Reproduced.** `read "nothing-here.txt" into content` inside `try` sets `content` to `""`; the `otherwise` branch does not run; the only sign is a browser-console warning. |
| P7: async calls are not awaited, so failures escape `try ... otherwise` | **Not reproduced with HTTP.** A function doing a failing `get` is caught by the caller's `try` on the web and the console; the web page also logs an uncaught "Failed to fetch". The file-read case needs the desktop bridge and was not tested. |

**Recommendation:** fix the loop capture, and make browser file operations
fail loudly ("… needs the desktop application"), in 1.0 as rc.8, rather than
publishing them. P8's browser-storage feature (files persisting in the page's
storage) is new behaviour and stays 1.1. The console's behaviour for handlers
registered in a loop should be checked first, since it is the reference.

## 2. The proposals

| | Proposal | Recommendation | Needs |
|---|---|---|---|
| P1 | Runtime UI: elements are values; component functions; `remove`, `clear`, `show`/`hide`/`focus` on console and web | **Accept.** This is the D56 1.1 plan; it builds on D128. | console (WPF) parity certified with the web |
| P2 | Shared properties: `style`, `hidden`, `enabled`, `tooltip`, `label`, `shortcut`, `icon`; the `icon` kind and page `icons` sprite; `submitted` event; computed and bare declarations; the three-level look rule; stylesheet can change row/column layout; `otter-drop-over` | **Accept**, except: pick one spelling — `style` — and keep `class` only if a 1.0 program can already use it. | Codex (new words, event) |
| P3 | Phrase functions (prepositions introduce parameters) | **Accept in principle; Codex designs the grammar.** `with`, `for`, `to`, `in`, `from` already carry meaning (`x is a text with …`, `for each`, `to name`, `put a in b`, `read … from`); every combination needs a parse test. | Codex |
| P4 | `into` for a call's result; `make` stays | **Accept** (matches `read … into`, `split … into`). | Codex |
| P5 | `its` inside `each`/`find`; `find` without `into`; `return x in xs where …` | **Accept `its` and `find` without `into`; rethink `return x in xs where`**, which reads like returning a membership test. | Codex |
| P6 | Smaller gaps: `an`; computed call arguments separated by `and`; `return` a comparison; computed date moves; `weekday of`; `text of number`; duplicate function names an error; `wait` on web/desktop | **Accept all but one; hold `and` as an argument separator.** `and` already means addition (`say 2 and 2` prints 4), so `label "Due " plus day and count times 2` has two readings. | Codex |
| P7 | JavaScript compiler fixes: await async calls; per-iteration loop variables for handlers; `replace … in x` inside a function | **Fix the loop capture in 1.0** (section 1); the other two in 1.0 as well if they reproduce. | — |
| P8 | Files in a plain browser tab use the page's storage | **1.0: fail loudly. 1.1: accept the storage feature.** | — |
| P9 | Desktop: window size from the page; `otter web -SourceDir`; `otter run` opens page programs in the desktop host; startup grace | **Accept**, with D129: on macOS and Linux `otter run` of a page program must refuse like `otter desktop` does. | — |

## 3. How it lands

1. **Finish 1.0 first.** rc.7 needs its macOS hands-on test; section 1 may add
   an rc.8. Nothing from the proposal branch merges before 1.0.0.
2. **Rebase the proposal onto the 1.0 line.** It starts from rc.4 and lacks
   rc.5–rc.7, including D129's changes to `otter.ps1` and the interpreter.
3. **Codex reviews and owns the parser changes** (P2 words, P3–P6). The
   proposal branch edited `src/Otter.Parser.psm1` directly; those edits become
   Codex's to accept, rewrite or reject.
4. **Each accepted proposal becomes a D-number** in `SPEC-DECISIONS.md`, with
   the release-surface record updated (the branch's `ReleaseSurface` failure is
   this missing step).
5. **Previews:** after 1.0.0, tag `v1.1.0-preview.N` from the 1.1 line so
   OtterBoard can be tried; certification rules as for 1.0 RCs.
6. **Studio and Electron** (window settings in the Electron export, `otter
   studio <folder>`, multi-file Designer renders) stay on their own preview
   branch and are not part of this proposal.

## 4. Decisions needed from Jeff

1. Fix the rc.7 web bugs in section 1 before 1.0 (rc.8), or ship 1.0 with them
   as known issues and fix in 1.1?
2. Accept P1, P2, P7, P8 (storage), P9 for 1.1 in principle?
3. Send P3–P6 (and P2's new words) to Codex for grammar review, with the
   concerns above?

## 5. Decisions made (2026-09-30)

1. The rc.7 web bugs were fixed before 1.0, as rc.8: the loop rule became D130
   (on the console and the web - the console behaved the same way), browser
   file operations became errors (D131), and the top-level `has` fix followed.
2. P1, P2, P8 (browser storage) and P9 are accepted for 1.1 in principle.
3. P3-P6 go to Codex for grammar review, with the concerns in section 2.
4. The checklist for all of 1.1 is `OTTER_1_1_CHECKLIST.md` (repository root);
   its section 2 holds the decided OtterBoard work.
