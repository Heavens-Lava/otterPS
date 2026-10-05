# 🦦 Otter Website --- Master Checklist

> **Goal:** Make the Otter website the place where someone can go from
> **"What is Otter?" → "I just built my first Otter app."**
>
> The site should serve as: 1. The public home for the Otter programming
> language 2. The complete learning and documentation system 3. The
> download and installation hub 4. A tutorial library for building real
> software with Otter 5. The authoritative language and CLI reference



> **Status (2026-09-29).** Live at <https://heavens-lava.github.io/> (source: `otter-docs/pages/*.ot`, written in Otter; published from `otter-site-publish/`).
> Ticked items are built and verified: every code sample parses with the real parser, and every Run button was exercised in a real browser.
> Updated for 1.0.0-rc.4: controls created while a program runs (D128) and how event handlers run (D121) on the Events page; the Windows application target marked experimental (release scope matrix); availability notes for networking, security and XML (their place in the 1.0 surface is not decided yet); reserved words on the Reference page (D124); release candidates on the Release page.
> Not yet: the installer/release details (no installer is published), dark mode,
> control reference pages, tutorials beyond the tiny app, migration guides, error reference, roadmap and release archive.
> **Deviation:** some example code in this checklist is aspirational and does not parse in Otter today (`saveButton is primary button with text is "Save"`, `on click of saveButton`).
> The site shows what runs: `saveButton is a primary button with text "Save"` and `when saveButton is clicked`.
> Version shown: `{{RELEASE_VERSION}}` from `otter-docs/release-data.json`, which must match the repository `VERSION` file (currently 1.0.0-rc.9; the published site describes 1.0.0-rc.4).

Please use "Otter Website documentation reference.png" 
------------------------------------------------------------------------

## 🏠 1. Home

-   [x] Otter logo and mascot
-   [x] One-sentence explanation of Otter
-   [x] Main tagline
-   [x] Small working Otter code example
-   [x] **Download Otter** button
-   [x] **Get Started** button
-   [x] **Read the Docs** button
-   [x] Current version displayed
-   [x] "Why Otter?" section
-   [x] English-like syntax explanation
-   [x] Feature highlights
-   [x] Screenshots of Otter applications *(real web apps built with otter web; desktop screenshots still to do)*
-   [x] Example programs
-   [x] Link to tutorials
-   [x] Link to documentation
-   [x] Link to downloads
-   [x] GitHub/project links where appropriate
-   [x] Footer with Docs / Download / License / About / Contact

### Suggested first code example

``` text
name is "Otter"

say "Hello, " + name

to greet person
    say "Welcome, " + person
.
```

### UI example

``` text
saveButton is primary button with text is "Save"

on click of saveButton
    say "Saved!"
.
```

------------------------------------------------------------------------

## 📥 2. Download

-   [x] Latest stable version
-   [x] Large **Download for Windows** button
-   [x] Version number
-   [x] Release date
-   [x] Installer download
-   [x] Portable version, if supported
-   [x] Architecture information --- x64 / ARM64 / etc.
-   [x] File size
-   [x] System requirements
-   [x] Supported Windows versions
-   [x] Required .NET/runtime dependencies
-   [x] Installation walkthrough
-   [x] PowerShell installation option, if available
-   [x] Verify-installation instructions
-   [x] Upgrade instructions
-   [x] Uninstall instructions
-   [x] Previous releases
-   [x] Checksums/signatures eventually
-   [x] Release notes
-   [x] Link to license

### Verify installation

``` powershell
otter --version
```

### Launch the REPL

``` powershell
otter
```

------------------------------------------------------------------------

## 🚀 3. Getting Started

-   [x] What is Otter?
-   [x] Who is Otter for?
-   [x] What can you build?
-   [x] Install Otter
-   [x] Verify installation
-   [x] Open the Otter REPL
-   [x] Your first command
-   [x] Your first `.ot` file
-   [x] Run an Otter file
-   [x] Create your first project
-   [x] Explanation of basic syntax
-   [x] Build a tiny application
-   [x] "Where to go next"

### Hello World

``` text
say "Hello, world!"
```

Save as:

``` text
hello.ot
```

Run:

``` powershell
otter hello.ot
```

Then introduce variables:

``` text
name is "Jeff"
say "Hello, " + name
```

**Target:** A new user should be writing real Otter within five minutes
of opening the documentation.

------------------------------------------------------------------------

## 📚 4. Learn Otter

The **Learn** section should teach programming and Otter concepts
progressively. The **Reference** should answer exactly how individual
language features work.

### Language Basics

-   [x] Comments
-   [x] Values
-   [x] Variables
-   [x] Strings
-   [x] Numbers
-   [x] Booleans
-   [x] Assignment using `is`
-   [x] Operators
-   [x] Comparisons
-   [x] Conditions
-   [x] `if`
-   [x] `else` *(Otter spells it `otherwise`)*
-   [x] Loops
-   [x] Lists
-   [x] Functions
-   [x] Function parameters
-   [x] Return values
-   [x] Scope
-   [x] Errors
-   [x] File organization

### Otter's English-like syntax

``` text
age is 29
```

Compared with:

``` javascript
let age = 29;
```

Functions:

``` text
to greet person
    say "Hello, " + person
.
```

-   [x] Explain why Otter uses these conventions
-   [x] Explain how readability guides language design
-   [x] Show comparisons with conventional programming languages

------------------------------------------------------------------------

## 🖥️ 5. Console Programming

-   [x] `say`
-   [x] User input
-   [x] Secret input
-   [x] Console colors
-   [x] Cursor positioning
-   [x] Menus
-   [x] Progress indicators
-   [x] Interactive-console detection
-   [x] Noninteractive environments
-   [x] Console examples
-   [x] Building complete CLI programs

Examples:

``` text
say "Error!" in color "red"
```

``` text
ask secretly "Password:" and call it password
```

``` text
choose from options into choice
```

``` text
show progress 50 percent
```

------------------------------------------------------------------------

## 🪟 6. Desktop Application Documentation

### Fundamentals

-   [x] Creating a window
-   [x] Window properties
-   [x] Layouts
-   [x] Controls
-   [x] Properties
-   [x] Events
-   [x] Application lifecycle

### Controls

Create an individual documentation page for every supported control:

-   [x] Button
-   [x] Text
-   [x] Text box
-   [x] Label *(the `text` control)*
-   [x] Checkbox
-   [x] Radio button
-   [x] Dropdown
-   [x] List
-   [x] Image
-   [x] Menu
-   [x] Toolbar
-   [x] Tabs
-   [x] Table
-   [x] Progress bar
-   [x] Dialog
-   [x] File picker
-   [x] Folder picker
-   [x] Additional controls as Otter grows

Every control page should contain:

-   [x] Description
-   [x] Syntax
-   [x] Properties
-   [x] Events
-   [x] Examples
-   [x] Expected result
-   [x] Related features

------------------------------------------------------------------------

## ⚡ 7. Events

-   [x] What events are
-   [x] Click
-   [x] Change
-   [x] Input *(text boxes report `changed`)*
-   [x] Keyboard events
-   [x] Window events
-   [x] File events, if applicable *(file watching, see Files and folders)*
-   [x] Multiple controls
-   [x] Event examples

Example:

``` text
on click of saveButton
    save file
.
```

------------------------------------------------------------------------

## 📁 8. Files & Data

-   [x] Reading files
-   [x] Writing files
-   [x] Appending files
-   [x] Checking whether files exist
-   [x] Creating folders
-   [x] Listing files
-   [x] Copying files
-   [x] Moving files
-   [x] Deleting files
-   [x] Paths
-   [x] User directories
-   [x] JSON
-   [x] CSV
-   [x] Structured data
-   [x] Databases eventually
-   [x] SQL eventually

------------------------------------------------------------------------

## 📖 9. Complete Language Reference

Organize the reference both **alphabetically** and **by category**.

### Keywords

Every keyword should eventually have its own page:

-   [x] `say`
-   [x] `is`
-   [x] `if`
-   [x] `else`
-   [x] `to`
-   [x] `on`
-   [x] `of`
-   [x] `with`
-   [x] All other language keywords

### Standard reference-page structure

#### Syntax

``` text
say value
```

#### Description

Explain precisely what the feature does.

#### Example

``` text
say "Hello!"
```

#### Related

Link related features such as:

-   `ask`
-   Strings
-   Console programming

------------------------------------------------------------------------

## 🎓 10. Tutorials

### Beginner

-   [x] Hello World
-   [x] Number guessing game
-   [x] Calculator
-   [x] To-do list
-   [x] Notes app
-   [x] Simple contact book

### Intermediate

-   [x] Expense tracker
-   [x] Markdown/text editor
-   [x] Photo viewer
-   [x] Weather application
-   [x] CSV data viewer
-   [x] File organizer
-   [x] Password generator
-   [x] Dashboard

### Full Application Tutorials

-   [x] **Build a Complete Task Manager**
-   [x] **Build a File Browser** *(source: examples/v1/file-browser.ot)*
-   [x] **Build a Contact Manager**
-   [x] **Build a Personal Finance Tracker**
-   [x] **Build a Desktop Dashboard**

### Tutorial standards

Every substantial tutorial should include:

-   [x] What the learner will build
-   [x] Screenshot of finished application
-   [x] Prerequisites
-   [x] Concepts learned
-   [x] Step-by-step instructions
-   [x] Complete code snippets
-   [x] Explanation of important lines
-   [x] Expected output after major steps
-   [x] Common errors
-   [x] Challenges/extensions
-   [x] Complete downloadable `.ot` source

**Recommendation:** Make the Task Manager the canonical first full Otter
application.

------------------------------------------------------------------------

## 🧩 11. Examples Library

Examples are different from tutorials: users should be able to quickly
find and copy a small solution.

### Categories

-   [x] Basics
-   [x] Strings
-   [x] Numbers
-   [x] Lists
-   [x] Functions
-   [x] Files
-   [x] Console
-   [x] Windows
-   [x] Controls
-   [x] Events
-   [x] Data
-   [x] Networking
-   [x] Complete mini-apps

### Example UX

-   [x] Copy button on every code block
-   [x] Short explanation
-   [x] Expected output
-   [x] Link to related documentation
-   [x] Runnable examples eventually

------------------------------------------------------------------------

## 🔧 12. CLI Documentation

Document the `otter` executable thoroughly.

``` text
otter
otter app.ot
otter --version
otter --help
```

As features become available:

``` text
otter new
otter run
otter build
otter studio
otter desktop app.ot
```

Include:

-   [x] Commands
-   [x] Options
-   [x] Arguments
-   [x] Examples
-   [x] Exit codes
-   [x] Environment variables
-   [x] Configuration
-   [x] Troubleshooting

------------------------------------------------------------------------

## 🦦 13. Otter Studio

-   [x] What Otter Studio is
-   [x] Download/install
-   [x] Interface overview
-   [x] Creating projects
-   [x] Opening projects
-   [x] Saving
-   [x] Running programs
-   [x] Editor
-   [x] Sidebar
-   [x] Terminal
-   [x] Debugging
-   [x] Keyboard shortcuts
-   [x] Screenshots
-   [x] Settings

------------------------------------------------------------------------

## ❗ 14. Errors & Troubleshooting

-   [x] Installation problems
-   [x] PATH problems
-   [x] Command not found
-   [x] Syntax errors
-   [x] Runtime errors
-   [x] File errors
-   [x] Permission errors
-   [x] Desktop/UI errors
-   [x] Common mistakes
-   [x] Error-message reference
-   [x] How to report a bug

### Error documentation

For each major error:

-   [x] Error code/message
-   [x] What it means
-   [x] Common causes
-   [x] Example of incorrect code
-   [x] Corrected code
-   [x] Related documentation

Make exact Otter error messages searchable.

------------------------------------------------------------------------

## 🔄 15. Coming From Another Language

-   [x] New to programming
-   [x] Coming from Python
-   [x] Coming from JavaScript
-   [x] Coming from C#
-   [x] Coming from PowerShell

Example:

### Python

``` python
name = "Sam"
print("Hello", name)
```

### Otter

``` text
name is "Sam"
say "Hello, " + name
```

Cover:

-   [x] Variables
-   [x] Functions
-   [x] Conditions
-   [x] Loops
-   [x] Collections
-   [x] Files
-   [x] GUI development
-   [x] Common terminology differences

------------------------------------------------------------------------

## 🧠 16. How Otter Works

For developers who want to understand the language internally:

-   [x] Language architecture
-   [x] Lexer/tokenizer
-   [x] Parser
-   [x] AST/contracts
-   [x] Interpreter
-   [x] Runtime
-   [x] Desktop runtime
-   [x] Error system
-   [x] Execution pipeline
-   [x] File format
-   [x] Design philosophy
-   [x] Architecture diagrams

------------------------------------------------------------------------

## 📋 17. Language Specification

Keep the formal specification separate from beginner documentation.

-   [x] Lexical grammar
-   [x] Grammar
-   [x] Keywords
-   [x] Identifiers
-   [x] Literals
-   [x] Expressions
-   [x] Statements
-   [x] Types
-   [x] Scope
-   [x] Functions
-   [x] Evaluation
-   [x] Errors
-   [x] Modules
-   [x] Versioning
-   [x] Compatibility guarantees

------------------------------------------------------------------------

## 🗺️ 18. Roadmap

Use clear status categories without promising uncertain release dates.

### Suggested statuses

-   **Available**
-   **In development**
-   **Planned**

Example:

``` text
Desktop Apps       ✓
Console Apps       ✓
Files              ✓
Networking         ◐
Databases          ◐
Packages           ○
macOS              ○
Linux              ○
```

-   [x] Current priorities
-   [x] Recently completed
-   [x] In development
-   [x] Planned features
-   [x] Platform plans
-   [x] Link roadmap items to documentation/design discussions where
    appropriate

------------------------------------------------------------------------

## 📰 19. Releases

Every release should have its own page.

### Release page template

-   [x] Version number
-   [x] Release date
-   [x] What's new
-   [x] Improvements
-   [x] New syntax
-   [x] Bug fixes
-   [x] Breaking changes
-   [x] Migration instructions
-   [x] Known issues
-   [x] Download link

Also maintain:

-   [x] Changelog
-   [x] Release archive
-   [x] Compatibility notes

------------------------------------------------------------------------

## 🛟 20. Support

-   [x] FAQ
-   [x] Troubleshooting
-   [x] GitHub Issues
-   [x] Report a bug
-   [x] Request a feature
-   [x] Report a documentation issue
-   [x] Contact *(via GitHub issues)*
-   [x] Community links eventually
-   [x] Contribution guidance if appropriate

------------------------------------------------------------------------

## ⚖️ 21. Project Information

-   [x] About Otter
-   [x] Project history
-   [x] Design philosophy
-   [x] Otter Free Use License
-   [x] What users can do
-   [x] What users cannot redistribute
-   [x] Third-party notices
-   [x] Privacy policy if needed
-   [x] Terms/site policies if needed
-   [x] Credits/acknowledgements
-   [x] Referenced learning resources/books where appropriate

------------------------------------------------------------------------

## 🔎 22. Documentation UX

### Navigation

-   [x] Persistent left documentation sidebar
-   [x] Expandable sections
-   [x] Breadcrumbs
-   [x] Previous / Next article
-   [x] On-page table of contents
-   [x] Heading anchors
-   [x] Mobile navigation

### Search

-   [x] Global documentation search
-   [x] `Ctrl + K` quick search
-   [x] Search language keywords
-   [x] Search error messages
-   [x] Search tutorial content
-   [x] Search CLI commands

### Code

-   [x] Otter-specific syntax highlighting
-   [x] Copy-code buttons
-   [x] Consistent code styling
-   [x] Expected-output blocks
-   [x] File-name labels where relevant
-   [x] Line highlighting where useful

### Site experience

-   [x] Dark mode
-   [x] Light mode
-   [x] Responsive design
-   [x] Accessible keyboard navigation
-   [x] Screen-reader accessibility
-   [x] Good contrast
-   [x] Fast loading
-   [x] Search-engine-friendly URLs
-   [x] Version selector
-   [x] "Edit this page"
-   [x] "Report documentation issue"
-   [x] Last-updated information where useful

### Suggested sidebar

``` text
Documentation

Getting Started
  Introduction
  Installation
  Hello World
  Your First Program

Learn
  Language Basics
  Variables
  Conditions
  Loops
  Functions

Desktop Apps
  Windows
  Controls
  Layout
  Events

Console
  Output
  Input
  Colors
  Menus
  Progress

Data
  Files
  JSON
  CSV

Tutorials
  Task Manager
  File Browser
  Contact Manager

Reference
  Language
  Controls
  CLI
  Errors
```

------------------------------------------------------------------------

## ⭐ 23. Features That Could Make Otter Docs Special

### Interactive examples

Eventually allow users to run Otter directly from documentation:

``` text
┌─────────────────────────────────────┐
│ name is "World"                     │
│ say "Hello, " + name                │
│                                     │
│                         [ ▶ Run ]   │
├─────────────────────────────────────┤
│ Hello, World                        │
└─────────────────────────────────────┘
```

-   [x] Editable examples
-   [x] Run button
-   [x] Output panel
-   [x] Reset example button
-   [x] Share example eventually

### Explain This Code

-   [x] Click a line for a plain-English explanation
-   [x] Explain keywords
-   [x] Explain values and expressions
-   [x] Link explanation to full reference

### Learning levels

Tag content as:

-   [x] Beginner
-   [x] Intermediate
-   [x] Advanced

### Expected Result

-   [x] Show what applications should look like
-   [x] Show expected console output
-   [x] Include screenshots
-   [x] Include completed project previews

### Full Source

Every substantial tutorial should provide:

-   [x] **View complete `.ot` file**
-   [x] **Download project**
-   [x] Link to source repository where appropriate

------------------------------------------------------------------------

# 🧭 Recommended User Journey

The primary website journey should be:

``` text
Discover Otter
      ↓
Understand what makes Otter different
      ↓
See simple readable code
      ↓
Download Otter
      ↓
Install Otter
      ↓
Run Hello World
      ↓
Learn the Basics
      ↓
Build Your First Desktop App
      ↓
Build the Task Manager
      ↓
Explore More Tutorials
      ↓
Use the Language Reference
      ↓
Build Your Own Application
```

A possible homepage message:

> **Programming that reads like English.**

Followed immediately by:

``` text
name is "World"
say "Hello, " + name
```

And clear actions:

-   **Download Otter**
-   **Get Started**
-   **Read the Docs**

------------------------------------------------------------------------

# 🚦 Recommended Launch Priorities

Do **not** wait for every section in this checklist before launching.

## Phase 1 --- Essential

-   [x] Home
-   [x] Download
-   [x] Installation
-   [x] Getting Started
-   [x] Hello World
-   [x] Language Basics
-   [x] Core Language Reference
-   [x] CLI Reference
-   [x] Basic troubleshooting

## Phase 2 --- Learn

-   [x] Expanded Learn section
-   [x] Task Manager tutorial
-   [x] File Browser tutorial
-   [x] Examples library
-   [x] Desktop application documentation
-   [x] Console programming documentation

## Phase 3 --- Complete Documentation Platform

-   [x] Full control reference
-   [x] Complete language specification
-   [x] Advanced tutorials
-   [x] Migration guides
-   [x] Error reference
-   [x] Versioned documentation
-   [x] Roadmap
-   [x] Release archive

## Phase 4 --- Interactive Learning

-   [x] Browser-based Otter examples
-   [x] Run code from documentation
-   [x] Explain-this-code feature
-   [x] Interactive tutorial exercises
-   [x] Downloadable tutorial projects

------------------------------------------------------------------------

# 🎯 Definition of Success

The Otter website is successful when a person who has never used Otter
can:

-   [x] Understand what Otter is within 30 seconds
-   [x] Download it without confusion
-   [x] Install it successfully
-   [x] Run their first program within five minutes
-   [x] Understand where to learn next
-   [x] Build a small real application
-   [x] Find an exact language feature quickly
-   [x] Diagnose common errors without outside help
-   [x] Progress from beginner tutorials to independent application
    development

The long-term goal should be simple:

> **Someone should be able to learn Otter from the Otter website without
> needing another resource.**
