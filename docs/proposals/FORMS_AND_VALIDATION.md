# Forms that check themselves

**Status:** approved by Jeff, 2026-09-30. He chose all four recommendations
under "Questions for Jeff" below: a `form` container with
`when <form> is sent`, `format "email"`, messages drawn by Otter under each
field, and no `clear` for now. It will get a D-number in SPEC-DECISIONS.md
when the Studio line and the release line merge.

**Built:** `src/Otter.Web.psm1` (tests/Web.Tests.ps1 35) and Otter Studio
(Form component, Validation section, Sent event). It was checked end to end in
Studio friction-log pass 11: made in the Designer, used in Live App and in the
built site on a phone.

**Two refinements found while building (for Jeff to confirm):**

1. **Which buttons send.** Any button in a form sends it except secondary
   and danger buttons, not only primary buttons. A plain Button dragged into
   a form from Components should send it; a secondary "Cancel" or a danger
   "Delete" never does.
2. **"Both targets" means web and desktop apps, and both are one compiler.**
   `otter desktop` and the Electron export run the page the web compiler
   makes (`Export-OtterWebApplication`), so forms work there as they do in a
   browser. The WPF provider behind `otter run` does not build programs
   written as `app is a window with ...` / `put ... in ...` at all on this
   line ("I can only put a UI resource somewhere"). It has no forms, and
   none were added.

## Problem

Every rule a form has is written by hand in a click handler today. The
contact form from Studio friction-log pass 8:

```otter
nameBox is a text box with placeholder "Your name"
emailBox is a text box with placeholder "you@example.com"
messageBox is a text area with placeholder "How can we help?"
sendButton is a primary button with text "Send"
status is a text
put nameBox, emailBox, messageBox, sendButton, status in contactColumn

when sendButton is clicked
    if text of nameBox is ""
        text of status is "Please tell us your name."
    otherwise
        if text of emailBox is ""
            text of status is "Please give us your email."
        otherwise
            text of status is "Thanks! We'll be in touch."
        .
    .
.
```

- Each rule is an `if`, nested one deeper per field.
- Checking that an email address is well formed is out of reach for most
  authors.
- One status line serves every field, so the message is not next to the
  field that is wrong.
- Pressing Enter in a box does nothing.
- None of it can be set up in the Designer. The Properties panel can't say
  "required".

## Proposal

A form states its rules on its fields. Otter checks them, shows each
message under its field, and runs your code only when everything passes.

```otter
contactForm is a form with spacing 12
nameBox is a text box with label "Name", required true
emailBox is a text box with label "Email", format "email", required true
messageBox is a text area with label "Message", required true, minlength 10
sendButton is a primary button with text "Send"
status is a text
put nameBox, emailBox, messageBox, sendButton, status in contactForm

when contactForm is sent
    text of status is "Thanks! We'll be in touch."
.
```

### 1. `form`: a column that knows its fields

- `x is a form` lays out like a column. It holds the fields, which can sit
  directly inside it or in rows and columns within it.
- These **send** the form:
  - clicking a primary button inside it;
  - pressing Enter in one of its text boxes (not in a text area, where Enter
    is a new line).
- Sending checks every field in the form:
  - If any rule fails, each failing field shows its message, the first one
    gets focus, and **no code runs**.
  - If all pass, `when <form> is sent` runs.
- Other buttons in a form (secondary, danger) do not send it. They keep their
  own `when ... is clicked`.

### 2. Rules are properties of the field

| Property | On | Means |
|---|---|---|
| `required true` | text box, text area, dropdown, checkbox | must not be empty (a checkbox: must be ticked, "I agree") |
| `format "email"` | text box | an email address (`name@place.tld`) |
| `format "number"` | text box | a number; `text of` still gives text, and `number of` gives the number |
| `format "phone"` / `"url"` | text box | a phone number (digits, spaces, `+ - ( )`) / a web address |
| `minlength N` / `maxlength N` | text box, text area | at least / at most N characters |
| `minimum N` / `maximum N` | text box with `format "number"` | the number's range |
| `message "..."` | any field | your own wording, replacing Otter's |

- A field's rules are checked only when its form is sent. Once a field has
  shown a message, that message updates as you type.
- A field outside a form never checks itself.

### 3. `label`: the field's name, shown and used in messages

- `label "Email"` shows a label above the field. It is the element's
  accessible name, and clicking it focuses the field.
- Otter's messages use it: "Please fill in Email.", "Email needs to be an
  email address, like name@example.com.", "Message needs at least 10
  characters."
- Without a label, the message names the placeholder, and failing that says
  "this field".

### 4. Reading and setting from code

- `valid of contactForm` / `valid of emailBox` is `true` or `false`. It
  checks without showing messages, for an `if` of your own.
- `error of emailBox` is the message on that field, or `""`.
- `error of emailBox is "That address is already registered."` shows a
  message of your own. `error of emailBox is ""` clears it. Use this for
  rules Otter can't know, such as an answer from a server.
- `clear contactForm` empties every field and message after a send. This
  is optional; see question 4.

### 5. Both targets

- **Web:** a `<form novalidate>` with Otter's own messages, not the
  browser's bubbles. That way they look the same in every browser and match
  the page's stylesheet: `.otter-field-error` and `.otter-invalid` are ordinary
  CSS classes a site can restyle.
- **Desktop apps** (`otter desktop`, the Electron export) run the same
  compiled page, so they behave exactly as the web does. See refinement 2
  at the top: the WPF provider behind `otter run` does not build these
  programs at all.
- **Free layout:** a field placed at x / y keeps its label just above it and
  its message just under it.

### 6. Studio

- `Form` is in Components (Containers).
- Properties has a **Validation** section on fields: Required, Format (a
  dropdown), Min/Max length, Min/Max value, Message, and Label in General.
- Events on a form offers **Sent**, and Add handler opens it in Split view as
  usual.
- The Website starter's New Page… could offer a "Contact page" that uses all
  of this.

## What changes where

| Where | Change | Owner |
|---|---|---|
| Parser | **none, verified 2026-09-30** with the current parser. `when contactForm is sent` parses as a WhenStmt with EventName `sent`. `format`, `minimum`, `maximum` and `message` arrive as ordinary `with` properties, although `format`, `minimum` and `maximum` are lexer keywords. `error of emailBox is "..."` is a property assignment, and `if valid of contactForm` is a property read. Only `clear contactForm` would need parser work: today it parses as a call to a function named `clear`. | Codex (only if `clear` is kept) |
| `Otter.Web.psm1` | **done.** The `form` kind, label and message markup, the check-and-send runtime, and `valid of` / `error of`, all in the web runtime. `Otter.Compiler.JavaScript.psm1` needed no change: an unknown event word and an unknown property already go to the runtime. | back end |
| `Otter.UI.psm1` (WPF) | none; see refinement 2 | - |
| Otter Studio | **done.** Form component, Validation section, Sent event, field labels on the canvas, and Live App allows forms | Studio |
| `rules.md` / SPEC-DECISIONS | a decision entry; possibly a short "Forms" section in rules.md | Jeff |

Existing programs are unaffected. Nothing here changes a program that has
no `form`, and `when button is clicked` handlers keep working as they are.

## Not in this proposal

- Sending a form to a server (`post contactForm to "https://..."`). That
  is web requests, and a separate decision.
- Regular-expression patterns (`pattern "..."`). A named `format` covers
  the common cases without asking authors to write regexes; add a pattern
  later only if a real form needs one.
- Checking one field against another ("confirm password"). Use
  `error of` from code for now.

## Questions for Jeff

1. **A `form` container with `when <form> is sent`** (recommended), or no
   new kind: any button with `checks contactColumn` validates that
   container before its click handler runs?
2. **`format "email"` on a text box** (recommended: one kind, a dropdown in
   the Designer, the same WPF control), or new kinds such as `email box` and
   `number box`?
3. **Otter-drawn messages under each field** (recommended: the same in every
   browser and on the desktop, styleable), or the browser's own validation
   bubbles on the web?
4. **Leave `clear contactForm` out for now** (recommended: it is the one part
   that needs parser work, and authors can set each `text of ... is ""`), or
   include it, with Codex adding the statement?
