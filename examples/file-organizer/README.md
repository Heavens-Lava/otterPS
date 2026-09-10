# File Organizer — dogfooding program 1 of 3

Run it:

```
otter examples\file-organizer\organizer.ot
```

## Status: runs correctly, one finding

**BLOCKER — D38 (statement continuation across lines), already known and
deferred.** The program as originally drafted split its `if` condition
across two lines:

```otter
if extension of file is ".jpg" or
   extension of file is ".png"
```

That does not parse. Otter has no line-continuation grammar yet — this is
exactly the gap D38 already names in `SPEC-DECISIONS.md`, not a new one.
Rewritten onto one line, which is already valid syntax and changes nothing
about what the program does:

```otter
if extension of file is ".jpg" or extension of file is ".png"
```

## Verified, not assumed

- Ran end to end against a real folder with `.jpg`, `.png`, `.txt`, and
  `.pdf` files. Exactly the two pictures were copied into
  `Organized Pictures`; the other two files were left untouched.
- Ran a **second time** against the already-organized folder: no error, no
  double-organizing, the count stayed correct. `create folder` on a folder
  that already exists is a no-op (D21); non-recursive discovery (D21)
  correctly leaves the `Organized Pictures` subfolder out of the second
  pass, so its contents are never re-counted.
- `ask` was verified separately — it needs a real interactive terminal
  (`Read-Host` cannot read through a pipe even non-interactively), which is
  a testing-environment limitation, not a language finding; this was
  already established the first time this project touched `ask`/the REPL.

## Classification

| Finding | Class |
|---|---|
| Multi-line condition continuation | BLOCKER (= D38, already known) |
| Everything else | works as written |
