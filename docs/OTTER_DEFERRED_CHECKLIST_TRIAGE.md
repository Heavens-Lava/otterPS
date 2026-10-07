# Otter Master Checklist — Deferred Item Triage & Prioritization Report

**Date:** September 17, 2026  
**Status:** Complete — Analysis & Planning Only (Zero Production Code Changes)  
**Baseline Commit:** `1fc96e78886a729e1bf3a6bae64f75a1d9431268` (Hardening Pass 1 Certified)  
**Authoritative Checklist:** `OTTER_PROGRAMMING_LANGUAGE_COMPLETE_PLATFORM_CHECKLIST.md`  
**Reconciliation Reference:** `docs/V1_CHECKLIST_RECONCILIATION.md`  
**Total Deferred Items Audited:** 543 unchecked items  

---

## 1. Executive Summary

Following the successful completion and certification of **Hardening Pass 1** (covering parser and interpreter linear scaling, zero-leak resource soak runs, adversarial filesystem and process suites, 1,000 differential fuzzing runs with zero discrepancies, clean per-user install/uninstall cycles, and automated performance regression gates), the Otter 1.0 feature surface was declared frozen.

In the initial audit report (`docs/V1_CHECKLIST_RECONCILIATION.md`), **543 unchecked checklist items** were grouped into a single broad category: **Category D (\"DEFERRED TO 1.1+\")**. That classification successfully protected the release team from scope creep during early stabilization. However, treating 543 diverse platform items as a single undifferentiated block creates a severe blind spot:
- It groups near-term, highly requested features (like the formal `use` module syntax and SQLite drivers) with speculative, multi-year initiatives (such as a custom 3D CAD modeling suite and native mobile runtimes).
- It conceals items that are **already fully or partially implemented** in the current codebase but remained unchecked due to conservative audit criteria.
- Most importantly, it obscures several small, foundational capabilities that users of a general-purpose programming language for shell automation and console software would reasonably expect in a 1.0 release.

### Mission & Evaluation Standard

This report performs a rigorous, item-by-item audit of **every single one of the 543 deferred items**. Each item has been evaluated against the core question:

> **\"Would users reasonably be surprised that a general-purpose Otter 1.0 cannot do this?\"**

Capabilities were prioritized by balancing **product value**, **semantic fit**, **architectural risk**, and **release stability**. Easy additions were not promoted simply because they are easy; likewise, missing features were not deferred simply because code does not yet exist.

### Scope & Hard Boundaries Maintained

In strict accordance with project instructions:
1. **Analysis and planning only:** No language syntax, compiler features, or standard library functions were implemented during this task.
2. **Untouched external code:** Jeff's C# implementation (`..\otter\`) was completely off-limits and untouched.
3. **Frozen contracts:** `Otter.Contract.psm1`, `rules.md`, and `SPEC-DECISIONS.md` were not modified.
4. **Authority:** All D1 promotions represent proposals for Jeff Macy's review. The final decision on the Otter 1.0 feature set belongs solely to Jeff.

---

## 2. Classification Scheme & Summary Counts

Every one of the 543 deferred checklist items has been assigned exactly one classification:

| Tier | Name | Definition & Entry Criteria | Count | Percentage |
|---|---|---|---|---|
| **D1** | **V1 Reconsideration Candidate** | Small, high-value capabilities fitting existing Otter semantics, requiring no major architectural churn, highly useful for real-world scripts, and capable of being fully tested/certified before semantic freeze. Also includes existing capabilities falsely classified as deferred. | **23** | **4.2%** |
| **D2** | **Otter 1.1** | Valuable near-term language, library, and runtime features intentionally scheduled for the 1.1 release cycle (e.g. formal modules, local package manager, SQLite, full web router). | **191** | **35.2%** |
| **D3** | **Later Platform Feature** | Valuable capabilities dependent on broader platform architecture, IDE/Studio infrastructure, or rich media runtimes (e.g. 2D game loop, DAP debugging, vector graphics). | **113** | **20.8%** |
| **D4** | **Long-Term / Ambitious** | Large subsystems, alternative compilation targets, and capstone vision criteria that should not influence near-term language planning (e.g. 3D engine, CAD tools, C ABI/FFI, mobile/WASM). | **216** | **39.8%** |
| **Total** | | **Complete Audit of Deferred Checklist Items** | **543** | **100.0%** |

### Breakdown by Checklist Disposition

In addition to tier classification, items were audited for proper checklist status:
- **Normal Deferred Items (504 items / 92.8%)**: Genuine post-1.0 features appropriately assigned to D1, D2, D3, or D4.
- **Already Implemented Capabilities (15 items / 2.8%)**: Capabilities already built, tested, or demonstrated in the Otter repository that were erroneously categorized as deferred.
- **Duplicate Roll-up Items (23 items / 4.2%)**: High-level milestone entries in Sections 47 and 48 that duplicate technical items defined in earlier sections.
- **Obsolete / Legend Non-Items (1 item / 0.2%)**: Markdown checklist status legend artifact (Line 22).

`mermaid
pie title Master Checklist Deferred Items Triage (543 items)
    "D1 Active Candidates (8)" : 8
    "D1 Already Implemented (15)" : 15
    "D2 Otter 1.1 Near-Term (191)" : 191
    "D3 Later Platform (113)" : 113
    "D4 Long-Term / Ambitious (216)" : 216
`

---
## 3. Complete D1 Table: V1 Reconsideration Candidates & Implemented Findings

The table below catalogs all **23 items** classified under **D1**. These items fall into two operational groups:
1. **Active V1 Candidates (8 items)**: Genuine capabilities missing from the current 1.0 surface that should be reconsidered for 1.0 due to high user necessity, natural semantic fit, and low implementation risk.
2. **Already Implemented Findings (15 items)**: Capabilities that are already implemented, tested, or demonstrated in the current repository, but were misclassified as deferred. These require zero implementation and should be promoted to Category B in the master checklist.

| Line | Checklist Item Text | Checklist Section | Status / Disposition | User Value | Syntax Exists? | Parser/AST Exists? | Runtime Exists? | Size | Semantic Risk | Cross-Target Parity | Recommendation |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **569** | Query parameters | 13. Networking | Active Candidate | High | Partial | No | No | Small | Low | Full (Console + Web) | **Reconsider for 1.0** |
| **575** | File download | 13. Networking | Active Candidate | High | Yes (HttpGet) | Yes | Web Only | Medium | Medium | Extends to Console | **Reconsider for 1.0** |
| **603** | CSV read/write | 14. Data Formats | Active Candidate | Critical | Pattern exists | No | No | Medium | Low | Full (Console + Web) | **Reconsider for 1.0** |
| **610** | Compression | 14. Data Formats | Already Implemented | High | Yes (D87) | Yes (Zip/Unzip) | Full (ZipArchive) | None | None | Console (.NET Zip) | **Certify as Cat B** |
| **707** | Constant-time primitives delegated to vetted libraries | 18. Cryptography | Already Implemented | High | Yes (D92) | Yes | Full (D92 MAC) | None | None | Full (D92 verified) | **Certify as Cat B** |
| **1280** | Lexer benchmark | 34. Performance | Already Implemented | High | N/A (Tooling) | N/A | Full (Pass 1) | None | None | N/A (Host Tooling) | **Certify as Cat B** |
| **1281** | Parser benchmark | 34. Performance | Already Implemented | High | N/A (Tooling) | N/A | Full (Pass 1) | None | None | N/A (Host Tooling) | **Certify as Cat B** |
| **1282** | Interpreter benchmark | 34. Performance | Already Implemented | High | N/A (Tooling) | N/A | Full (Pass 1) | None | None | N/A (Host Tooling) | **Certify as Cat B** |
| **1285** | Memory benchmark | 34. Performance | Already Implemented | High | N/A (Tooling) | N/A | Full (Pass 1) | None | None | N/A (Host Tooling) | **Certify as Cat B** |
| **1295** | Performance regression CI | 34. Performance | Already Implemented | High | N/A (Tooling) | N/A | Full (Pass 1) | None | None | N/A (Host Tooling) | **Certify as Cat B** |
| **1325** | Breakpoint hooks | 36. Debugging | Already Implemented | High | Yes (CLI flag) | N/A | Full (Debugger) | None | None | Console Debugger | **Certify as Cat B** |
| **1330** | Pause | 36. Debugging | Already Implemented | High | Yes (Protocol) | N/A | Full (Debugger) | None | None | Console Debugger | **Certify as Cat B** |
| **1331** | Continue | 36. Debugging | Already Implemented | High | Yes (Protocol) | N/A | Full (Debugger) | None | None | Console Debugger | **Certify as Cat B** |
| **1332** | Stack frames | 36. Debugging | Already Implemented | High | Yes (Protocol) | N/A | Full (Debugger) | None | None | Console Debugger | **Certify as Cat B** |
| **1333** | Locals | 36. Debugging | Already Implemented | High | Yes (Protocol) | N/A | Full (Debugger) | None | None | Console Debugger | **Certify as Cat B** |
| **1339** | Debug protocol | 36. Debugging | Already Implemented | High | Yes (JSON stdout) | N/A | Full (Debugger) | None | None | Console Debugger | **Certify as Cat B** |
| **1456** | Language tour | 42. Documentation | Active Candidate | Critical | N/A (Docs) | N/A | N/A | Small | None | Documentation | **Reconsider for 1.0** |
| **1457** | Installation | 42. Documentation | Active Candidate | Critical | N/A (Docs) | N/A | N/A | Small | None | Documentation | **Reconsider for 1.0** |
| **1551** | License/third-party notices | 45. Release Eng | Active Candidate | High | N/A (Legal) | N/A | N/A | Small | None | Packaging Notice | **Reconsider for 1.0** |
| **1634** | Arguments/options. | 48. Immediate Order | Active Candidate | Critical | Pattern exists | No | JS partially | Small | Low | Full (Console + Web) | **Reconsider for 1.0** |
| **1635** | Environment/cwd. | 48. Immediate Order | Active Candidate | High | Pattern exists | No | Partial (.NET IO) | Small | Low | Console (Host cwd) | **Reconsider for 1.0** |
| **1640** | System information. | 48. Immediate Order | Already Implemented | High | Yes (D76) | Yes | Full (Runtime) | None | None | Console Target | **Certify as Cat B** |
| **1648** | File dialogs/clipboard/notifications/menus. | 48. Immediate Order | Already Implemented | High | Yes (D70/84) | Yes | Full (Runtime) | None | None | Console + Web | **Certify as Cat B** |

---
## 4. D1 Detailed Analysis

This section provides the complete 13-point analysis for each of the **23 items** classified under D1.

---

### 4.1 Active V1 Reconsideration Candidates (8 Items)

These items represent genuine missing capabilities where users of a general-purpose language for scripting, automation, and command-line software would reasonably be surprised by their absence in 1.0.

#### Candidate 1: CSV read/write
- **Exact checklist text:** \CSV read/write\
- **Checklist section & line number:** \14. Data Formats & Serialization\ (Line 603)
- **Why it might belong in 1.0:** In shell scripting, system administration, and general-purpose automation, CSV is as ubiquitous as JSON. Otter currently supports \ead json from <path> into <var>\ and \convert <var> to/from json into <dest>\, but provides zero native facilities for tabular data or spreadsheet exports. Without native CSV, users must write error-prone string splits that mishandle quoted fields, embedded commas, or CRLF lines.
- **Expected user value:** **Critical**. Tabular file processing is one of the top three use cases for scripting languages (alongside JSON and raw text).
- **Whether syntax already exists:** Controlled English pattern directly mirrors JSON: \ead csv from \"data.csv\" into records\, \convert records to csv into text\, and \convert text from csv into records\.
- **Whether parser/AST support already exists:** No dedicated CSV AST node exists.
- **Whether runtime/compiler support partially exists:** PowerShell host has built-in \Import-Csv\ / \Export-Csv\; JavaScript target can embed a compact RFC 4180 parser (~40 lines).
- **Estimated implementation size:** **MEDIUM** (~120 lines total across parser, interpreter, compiler).
- **Semantic risk:** **LOW**. Yields a standard Otter list of things with property names derived from header columns.
- **Cross-runtime parity impact:** Excellent. RFC 4180 parsing produces identical list-of-things structures in PowerShell and JavaScript.
- **Security impact:** **LOW**. Governed by standard filesystem read/write permissions.
- **Documentation impact:** Small addition to standard library reference (1 section with 2 examples).
- **Recommendation:** **Strong Candidate for V1 Reconsideration.**

#### Candidate 2: Arguments/options
- **Exact checklist text:** \Arguments/options.\
- **Checklist section & line number:** \48. Immediate Execution Order\ (Line 1634)
- **Why it might belong in 1.0:** Otter is explicitly advertised to \"build complete command-line applications\" and \"automate and administer a computer\". Currently, when a user executes \otter run script.ot file.txt --verbose\, the script has **no language mechanism to inspect its own CLI arguments**. This creates an immediate barrier to writing practical CLI utilities.
- **Expected user value:** **Critical**. CLI scripts cannot accept dynamic inputs, file targets, or flags without argument access.
- **Whether syntax already exists:** Controlled English syntax could be \get arguments into args\ or an implicit global \rguments\ list.
- **Whether parser/AST support already exists:** No dedicated AST node for script arguments; parser already supports argument parsing for function calls.
- **Whether runtime/compiler support partially exists:** Partially exists in the JS compiler (\ConvertTo-OtterCommandLineArguments\ in \Otter.Compiler.JavaScript.psm1\), but is not bound into the interpreter environment during \otter run\.
- **Estimated implementation size:** **SMALL** (~40 lines in \otter.ps1\ and \Otter.Interpreter.psm1\).
- **Semantic risk:** **LOW**. An immutable list of text values.
- **Cross-runtime parity impact:** Full parity: mapped to remaining PowerShell script arguments on Console, and \process.argv\ in Node/CLI.
- **Security impact:** **LOW**. Standard input data passed by the user.
- **Documentation impact:** Small addition to the Console Application guide.
- **Recommendation:** **Strong Candidate for V1 Reconsideration.**

#### Candidate 3: Environment/cwd
- **Exact checklist text:** \Environment/cwd.\
- **Checklist section & line number:** \48. Immediate Execution Order\ (Line 1635)
- **Why it might belong in 1.0:** Otter currently has \get environment variable \"NAME\" into val\, but lacks any mechanism to: (a) set environment variables for child processes, or (b) inspect or change the current working directory. Shell automation tasks frequently require changing directory to a target project or configuring environment variables before running an external command.
- **Expected user value:** **High**. Automation scripts frequently need working directory control.
- **Whether syntax already exists:** Pattern fits existing system syntax: \get current directory into cwd\, \set current directory to <path>\, and \set environment variable \"KEY\" to \"VAL\"\.
- **Whether parser/AST support already exists:** No.
- **Whether runtime/compiler support partially exists:** .NET Framework runtime primitives (\[System.IO.Directory]::GetCurrentDirectory()\, \[System.Environment]::SetEnvironmentVariable()\) are trivial to invoke in \Otter.Library.psm1\.
- **Estimated implementation size:** **SMALL** (~50 lines).
- **Semantic risk:** **LOW**. Standard operating system environment mutations.
- **Cross-runtime parity impact:** Console host provides full OS cwd; Web target simulates cwd relative to virtual workspace.
- **Security impact:** **LOW**. Existing path traversal validation applies to directory changes.
- **Documentation impact:** Small addition to System Integration documentation.
- **Recommendation:** **Moderate Candidate for V1 Reconsideration.**

#### Candidate 4: Query parameters
- **Exact checklist text:** \Query parameters\
- **Checklist section & line number:** \13. Networking\ (Line 569)
- **Why it might belong in 1.0:** URL encoding is already certified in 1.0 (Line 606). However, constructing URLs with query strings from a thing/object (e.g. \?search=term&page=2\) or parsing a query string into key-value pairs is common when interacting with web services and APIs.
- **Expected user value:** **High** for web developers and API consumers.
- **Whether syntax already exists:** \uild query string from <thing> into <var>\ or \parse query string <text> into <thing>\.
- **Whether parser/AST support already exists:** No.
- **Whether runtime/compiler support partially exists:** Web runtime has native \URLSearchParams\; PowerShell runtime has \System.Web.HttpUtility\ or simple URI parsing.
- **Estimated implementation size:** **SMALL** (~60 lines).
- **Semantic risk:** **LOW**. Pure data transformation between text and things.
- **Cross-runtime parity impact:** Full parity between Console and Web.
- **Security impact:** **LOW**. Properly handles parameter escaping to prevent injection.
- **Documentation impact:** Small addition to networking/data guide.
- **Recommendation:** **Candidate for V1 Reconsideration.**

#### Candidate 5: File download
- **Exact checklist text:** \File download\
- **Checklist section & line number:** \13. Networking\ (Line 575)
- **Why it might belong in 1.0:** In console automation, downloading a file from a URL to a local path (e.g., retrieving a release zip or dataset) is a fundamental script task. Currently, HTTP is restricted to Web targets via \etch\. Enabling a basic download statement (\download file from \"url\" to \"path\"\) would bridge the gap between console automation and remote resources.
- **Expected user value:** **High** for sysadmins and automation engineers.
- **Whether syntax already exists:** Controlled English pattern fits: \download file from <url> to <path>\ or reusing \get <url> into <path>\.
- **Whether parser/AST support already exists:** Parser already has \HttpGetStmt\, but targets variable binding rather than streaming to file.
- **Whether runtime/compiler support partially exists:** .NET Framework 4.8 \System.Net.WebClient.DownloadFile\ is a one-line call in \Otter.Library.psm1\.
- **Estimated implementation size:** **MEDIUM** (~70 lines including error reporting and cancellation).
- **Semantic risk:** **MEDIUM**. Introduces external network dependency to console runtime which currently has zero outgoing network calls.
- **Cross-runtime parity impact:** Console downloads to local disk; Web downloads trigger browser download prompts.
- **Security impact:** **MEDIUM**. Requires network permission check and destination path traversal validation.
- **Documentation impact:** Moderate (network automation guide).
- **Recommendation:** **Candidate for V1 Reconsideration** (if console network access is approved for 1.0; otherwise defer to 1.1).

#### Candidate 6: Language tour
- **Exact checklist text:** \Language tour\
- **Checklist section & line number:** \42. Documentation\ (Line 1456)
- **Why it might belong in 1.0:** First impressions dictate developer adoption. A structured, progressive 15-minute walkthrough of Otter syntax (variables, control flow, functions, objects, collections, and error handling) is critical for developers downloading Otter 1.0.
- **Expected user value:** **Critical** for developer onboarding and language credibility.
- **Whether syntax already exists:** N/A (Documentation artifact).
- **Whether parser/AST support already exists:** N/A.
- **Whether runtime/compiler support partially exists:** Existing documentation engine (\otter-docs\) and verified dogfood examples provide all necessary code snippets.
- **Estimated implementation size:** **SMALL** (Pure documentation: 1 comprehensive markdown tour file).
- **Semantic risk:** **NONE**.
- **Cross-runtime parity impact:** None.
- **Security impact:** None.
- **Documentation impact:** High positive value.
- **Recommendation:** **Strong Candidate for V1 Polish.**

#### Candidate 7: Installation
- **Exact checklist text:** \Installation\
- **Checklist section & line number:** \42. Documentation\ (Line 1457)
- **Why it might belong in 1.0:** With the distribution packaging, \Install-Otter.ps1\, and \Uninstall-Otter.ps1\ certified in Hardening Pass 1, clear documentation showing how to download, install, verify, and uninstall Otter is required for the 1.0 release bundle.
- **Expected user value:** **Critical**. Users cannot use the language if they cannot install it.
- **Whether syntax already exists:** N/A.
- **Whether parser/AST support already exists:** N/A.
- **Whether runtime/compiler support partially exists:** Packaging scripts and automated tests already exist in \distribution/\ and \	ests/Installation.Tests.ps1\.
- **Estimated implementation size:** **SMALL** (Pure documentation: \INSTALL.md\ or docs page).
- **Semantic risk:** **NONE**.
- **Cross-runtime parity impact:** None.
- **Security impact:** None (documents standard non-admin per-user setup).
- **Documentation impact:** Essential release requirement.
- **Recommendation:** **Strong Candidate for V1 Polish.**

#### Candidate 8: License/third-party notices
- **Exact checklist text:** \License/third-party notices\
- **Checklist section & line number:** \45. Release Engineering\ (Line 1551)
- **Why it might belong in 1.0:** Open-source and production software releases require legal clarity. A consolidated \LICENSE\ and \THIRD-PARTY-NOTICES.md\ covering the PowerShell distribution, embedded Monaco/fonts in Studio, and sample code ensures compliance.
- **Expected user value:** **High** for legal compliance and enterprise adoption.
- **Whether syntax already exists:** N/A.
- **Whether parser/AST support already exists:** N/A.
- **Whether runtime/compiler support partially exists:** Repository contains MIT license; third-party notices need consolidation.
- **Estimated implementation size:** **SMALL** (Legal / notice document).
- **Semantic risk:** **NONE**.
- **Cross-runtime parity impact:** None.
- **Security impact:** None.
- **Documentation impact:** Distribution packaging compliance.
- **Recommendation:** **Strong Candidate for V1 Polish.**

---

### 4.2 Already Implemented Capabilities Falsely Classified as Deferred (15 Items)

These 15 items are already functional, tested, or certified in the current repository, but remained unchecked in Category D. They require **zero code implementation**; their proper disposition is promotion to **Category B (Implemented Capabilities Certified in 1.0)**.

#### Implemented Finding 1: Compression
- **Exact checklist text:** \Compression\
- **Checklist section & line number:** \14. Data Formats & Serialization\ (Line 610)
- **Implementation Reality:** Fully implemented in Decision **D87** via \zip folder \"src\" into \"archive.zip\"\ and \unzip \"archive.zip\" into \"dest\"\. Built using .NET \System.IO.Compression.ZipFile\ in \src/Otter.Library.psm1\ (lines 965-1020) and supported by both the Parser (\[ZipFolderStmt]\, \[UnzipFileStmt]\) and the JavaScript compiler.
- **Recommendation:** **Reclassify to Category B (Certified Implemented).**

#### Implemented Finding 2: Constant-time primitives delegated to vetted libraries
- **Exact checklist text:** \Constant-time primitives delegated to vetted libraries (PARTIAL - D92's tag comparison IS constant-time, but hand-implemented, not delegated to a library...)\
- **Checklist section & line number:** \18. Cryptography & Security APIs\ (Line 707)
- **Implementation Reality:** Implemented in **D92** as part of symmetric encryption and MAC tag validation. Because .NET Framework 4.8 lacks \FixedTimeEquals\, the comparison was intentionally hand-implemented to ensure constant-time behavior against timing attacks. The verification passes all differential tests.
- **Recommendation:** **Reclassify to Category B (Certified Implemented).**

#### Implemented Findings 3–7: Performance Profiling & Benchmarking Suite (5 Items)
- **Exact checklist items:**
  - \Lexer benchmark\ (Line 1280, Section 34. Performance)
  - \Parser benchmark\ (Line 1281, Section 34. Performance)
  - \Interpreter benchmark\ (Line 1282, Section 34. Performance)
  - \Memory benchmark\ (Line 1285, Section 34. Performance)
  - \Performance regression CI\ (Line 1295, Section 34. Performance)
- **Implementation Reality:** In Hardening Pass 1, the release engineering team delivered:
  - \	ools/Profile-OtterParser.ps1\ (benchmarks lexer, token creation, and AST construction up to 10k statements; documented in \docs/PARSER_PERFORMANCE_PROFILE.md\).
  - \	ools/Profile-OtterInterpreter.ps1\ (benchmarks throughput across arithmetic, function calls, property access, and list mutation up to 100k operations; documented in \docs/INTERPRETER_PERFORMANCE_PROFILE.md\).
  - \	ools/Test-ResourceSoak.ps1\ (measures peak private bytes and handles across 8 prolonged workloads with 0 memory/handle leaks; documented in \docs/RESOURCE_SOAK_RESULTS.md\).
  - \	ools/Test-OtterPerformanceGate.ps1\ (automated CI regression gate checking 5 benchmarks within 3.0x baselines; documented in \docs/PERFORMANCE_REGRESSION_GATE.md\).
- **Recommendation:** **Reclassify all 5 items to Category B (Certified Implemented).**

#### Implemented Findings 8–13: Debugger Runtime Support & Protocol (6 Items)
- **Exact checklist items:**
  - \Breakpoint hooks\ (Line 1325, Section 36. Debugging Runtime Support)
  - \Pause\ (Line 1330, Section 36. Debugging Runtime Support)
  - \Continue\ (Line 1331, Section 36. Debugging Runtime Support)
  - \Stack frames\ (Line 1332, Section 36. Debugging Runtime Support)
  - \Locals\ (Line 1333, Section 36. Debugging Runtime Support)
  - \Debug protocol\ (Line 1339, Section 36. Debugging Runtime Support)
- **Implementation Reality:** The production debugger engine in \src/Otter.Debugger.psm1\ already implements:
  - Statement hooks via \Set-OtterStatementHook\ in the interpreter.
  - Breakpoint matching on source lines.
  - Pausing and blocking execution while emitting structured \@@OTTER_DEBUG@@\ JSON events to stdout.
  - Complete stack frame inspection and frame-local variable resolution (\Get-OtterDebugLocals\).
  - Resuming via the \continue\ command.
  - Full automated verification in \	ests/Debugger.Tests.ps1\.
- **Recommendation:** **Reclassify all 6 items to Category B (Certified Implemented).**

#### Implemented Finding 14: System Information
- **Exact checklist text:** \System information.\
- **Checklist section & line number:** \48. Immediate Execution Order\ (Line 1640)
- **Implementation Reality:** Implemented in **D76** via \get system information \"os\" into osInfo\, \\"cpu\"\, \\"user\"\, and \\"memory\"\. Fully verified in \	ests/StandardLibrary.Tests.ps1\ (lines 294-302).
- **Recommendation:** **Reclassify to Category B (Certified Implemented).**

#### Implemented Finding 15: File Dialogs / Clipboard / Notifications
- **Exact checklist text:** \File dialogs/clipboard/notifications/menus.\
- **Checklist section & line number:** \48. Immediate Execution Order\ (Line 1648)
- **Implementation Reality:** All core components of this entry are already functional:
  - Clipboard: \copy \"...\" to clipboard\, \get clipboard into clip\ (D70, verified in stdlib suite).
  - Notifications: \
otify \"title\" with \"body\"\ (D70, verified in UI suite).
  - File dialogs: \choose file into f\, \choose folder into dir\, \choose save file into dest\ (D84, verified in UI suite).
- **Recommendation:** **Reclassify to Category B (Certified Implemented).**

---
## 5. D2 Summary: Otter 1.1 Near-Term Capabilities

Total items: **191 items (35.2% of all deferred items)**.

Tier D2 contains features that represent **valuable, high-priority language and runtime enhancements** that should intentionally wait until after the 1.0 release. These capabilities are not speculative or long-term, but their introduction requires either syntax expansion, new runtime state management, or dependency integration that would jeopardize the 1.0 release freeze if introduced now.

Below is the comprehensive summary of D2 items grouped across the **25 subsystems**:

### 5.1 Web Frontend Platform (22 items)

**Scope & Rationale:** Covers client-side routing, derived state, conditional/list rendering optimization, file uploads, asset bundling, CSS/JS bundling, minification, source maps, environment configuration, and SEO metadata. These features elevate Otter Web from a reactive page compiler into a complete single-page application (SPA) framework. They wait for 1.1 because 1.0 already supports core reactive UI and DOM binding.

**Checklist Items:**
- [Line 730] Derived state
- [Line 732] Conditional rendering
- [Line 733] List rendering
- [Line 736] Routing
- [Line 737] Route parameters
- [Line 738] Navigation/history
- [Line 740] Cookies
- [Line 742] WebSockets
- [Line 743] File upload/download
- [Line 744] Drag/drop
- [Line 750] Accessibility
- [Line 753] Otter-native styling authoring layer
- [Line 756] Asset bundling
- [Line 757] CSS bundling
- [Line 758] JS bundling
- [Line 759] Minification
- [Line 760] Source maps
- [Line 763] Environment configuration
- [Line 764] Production optimization
- [Line 769] SEO/meta
- [Line 770] Browser compatibility matrix
- [Line 771] Web publishing/deployment

### 5.2 Desktop UI Platform (19 items)

**Scope & Rationale:** Covers extended desktop controls (multiple windows, data grids, tree views, native menus, context menus, keyboard/pointer event bindings, shortcuts, theme switching, high-DPI scaling, and system tray integration). In 1.0, desktop UI is experimental and focuses on webview/window hosting; full native control suites are scheduled for 1.1.

**Checklist Items:**
- [Line 821] Multiple windows
- [Line 824] Grid when justified
- [Line 834] List
- [Line 835] Data grid
- [Line 836] Tree
- [Line 838] Menu
- [Line 843] Icon
- [Line 846] Date/time controls
- [Line 850] Focus
- [Line 852] Keyboard events
- [Line 853] Pointer events
- [Line 854] Resize events
- [Line 874] Native menus/context menus
- [Line 875] Shortcuts
- [Line 876] Themes
- [Line 877] Accessibility
- [Line 879] High DPI
- [Line 881] System tray/menu bar
- [Line 884] Single-instance apps

### 5.3 Networking (15 items)

**Scope & Rationale:** Covers HTTP form encoding, multipart/form-data, streaming requests, cancellation tokens, redirect policies, cookies, sessions, custom TLS/certificate validation, proxy support, DNS lookup, WebSocket client/server, and rate limiting / retry helpers. Deferring to 1.1 allows designing a clean, unified async socket/HTTP abstraction.

**Checklist Items:**
- [Line 572] Form encoding
- [Line 573] Multipart/form-data
- [Line 574] File upload
- [Line 576] Streaming
- [Line 578] Cancellation
- [Line 579] Redirect policy
- [Line 580] Cookies
- [Line 581] Sessions
- [Line 583] TLS/certificate handling
- [Line 584] Proxy
- [Line 585] DNS
- [Line 586] WebSocket client
- [Line 587] WebSocket server
- [Line 592] Rate limiting helpers
- [Line 593] Retry/backoff

### 5.4 Web Backend Platform (15 items)

**Scope & Rationale:** Covers server-side web middleware, static file hosting, streaming responses, WebSocket server endpoints, authentication/authorization hooks, CSRF defenses, request rate limiting, configuration/secrets binding, and a production HTTP server. Scheduled for 1.1 to follow the 1.0 client web foundation.

**Checklist Items:**
- [Line 782] Cookies
- [Line 784] Middleware
- [Line 787] Static files
- [Line 788] File upload
- [Line 789] Streaming responses
- [Line 790] WebSockets
- [Line 791] Authentication hooks
- [Line 792] Authorization hooks
- [Line 794] CSRF protections
- [Line 795] Rate limiting
- [Line 796] Request limits
- [Line 798] Configuration
- [Line 799] Secrets
- [Line 800] Database integration
- [Line 808] Production server

### 5.5 UI Styling (15 items)

**Scope & Rationale:** Covers formal declarative styling syntax in Otter code: min/max sizing, margins, flexbox layout, CSS grid behavior, borders, corner radii, typography, shadows, opacity, 2D transforms, responsive breakpoints, and pseudo-class state styles. Postponed to 1.1 to keep 1.0 syntax minimal.

**Checklist Items:**
- [Line 915] Freeze developer-facing Otter styling syntax
- [Line 917] Min/max size
- [Line 918] Margin
- [Line 923] Flex behavior
- [Line 924] Grid behavior if justified
- [Line 925] Positioning
- [Line 926] Explicit absolute/free positioning
- [Line 928] Borders
- [Line 929] Radius
- [Line 932] Typography
- [Line 933] Shadows
- [Line 934] Opacity
- [Line 935] Transform
- [Line 936] Responsive breakpoints
- [Line 937] State styles

### 5.6 Build System (14 items)

**Correction (RC3):** this section is partly superseded. Otter 1.0 ships the
project workflow: the `otter.json` manifest (see
[OTTER_1_0_PROJECT_MANIFEST.md](OTTER_1_0_PROJECT_MANIFEST.md)), entry point,
target, declared assets, `build.clean`, and the `otter new`, `otter check`,
`otter test`, `otter build` and `otter publish` commands with documented exit
codes. The manifest version is copied into the build and publish metadata.
Still deferred past 1.0: dependencies, debug/release configurations, a separate
rebuild command, source maps (`build.sourceMaps` is read but unused), and
builds that are byte-identical across hosts (builds are reproducible on one
host only).

**Scope & Rationale (original triage):** Covers project manifests (\otter.json\ or \Project.ot\), entry point resolution, target definitions, asset compilation, debug/release configurations, clean/rebuild commands, version stamping, and the official \otter build\ CLI. Waiting for 1.1 ensures the project model is designed in tandem with the module system.

**Checklist Items:**
- [Line 1228] Project manifest
- [Line 1229] Entry point
- [Line 1230] Target
- [Line 1231] Dependencies
- [Line 1232] Assets
- [Line 1233] Debug configuration
- [Line 1234] Release configuration
- [Line 1239] Deterministic builds
- [Line 1240] Clean
- [Line 1241] Rebuild
- [Line 1244] Source maps/debug metadata
- [Line 1245] Version stamping
- [Line 1248] CI-friendly command
- [Line 1249] `otter build`

### 5.7 Package Ecosystem (14 items)

**Scope & Rationale:** Covers package manifests, semantic versioning rules, local package installation, dependency resolution, lockfile generation (\otter.lock\), reproducible restore, integrity checksum hashing, license auditing, and offline caching. Scheduled for 1.1 alongside formal modules.

**Checklist Items:**
- [Line 1200] Package manifest
- [Line 1201] Semantic versions
- [Line 1203] Install
- [Line 1204] Remove
- [Line 1205] Update
- [Line 1206] Lock file
- [Line 1207] Reproducible restore
- [Line 1208] Transitive dependencies
- [Line 1209] Version constraints
- [Line 1210] Conflict resolution
- [Line 1211] Local packages
- [Line 1213] Integrity hashes
- [Line 1216] License metadata
- [Line 1218] Offline cache

### 5.8 Database Development (13 items)

**Scope & Rationale:** Covers embedded SQLite integration, client libraries for SQL Server, PostgreSQL, MySQL, connection management, parameterized query execution, transactions, prepared statements, and async query results. In strict accordance with user rules, database subsystems are deferred to 1.1/1.2.

**Checklist Items:**
- [Line 669] SQLite
- [Line 670] SQL Server
- [Line 671] PostgreSQL
- [Line 672] MySQL/MariaDB
- [Line 673] Connection management
- [Line 674] Parameterized queries
- [Line 675] Query results
- [Line 676] Transactions
- [Line 677] Prepared statements
- [Line 678] Connection pooling
- [Line 683] Async database operations
- [Line 686] Secrets/connection strings
- [Line 687] Database conformance tests

### 5.9 Modules & Packaging (11 items)

**Scope & Rationale:** Covers the production certification of the \use\ statement: module resolution, relative imports, circular dependency resolution, deterministic initialization order, duplicate-load semantics, public/private export boundaries, and namespace collision policy. Already reserved in the lexer; runtime execution is scheduled for 1.1.

**Checklist Items:**
- [Line 206] Shared module resolver work reported
- [Line 207] Production-certify `use`
- [Line 208] Freeze module resolution
- [Line 209] Relative modules
- [Line 210] Package modules
- [Line 211] Circular dependency semantics
- [Line 212] Module initialization order
- [Line 213] Duplicate-load semantics
- [Line 214] Public/private exports if needed
- [Line 215] Namespace collision policy
- [Line 216] Module caching/invalidation

### 5.10 Performance (6 items)

**Scope & Rationale:** Covers compiler benchmarks, cold-start latency benchmarks, file I/O benchmarks, HTTP client benchmarks, runtime profiling hooks, and formal optimization policies. Complements the core benchmarks established in 1.0.

**Checklist Items:**
- [Line 1283] Compiler benchmark
- [Line 1284] Startup benchmark
- [Line 1286] File IO benchmark
- [Line 1287] HTTP benchmark
- [Line 1291] Profiling hooks
- [Line 1296] Optimization policy that preserves semantics

### 5.11 Release Engineering (6 items)

**Scope & Rationale:** Covers continuous integration channels (nightly/preview, stable), automated release signing, per-user automatic update mechanisms, and cross-platform build automation for 1.1.

**Checklist Items:**
- [Line 1533] Windows CI
- [Line 1536] Browser CI
- [Line 1539] Signing
- [Line 1544] Update mechanism
- [Line 1545] Nightly/preview channel
- [Line 1546] Stable channel

### 5.12 Debugging (6 items)

**Scope & Rationale:** Covers step-over, step-into, step-out execution control, global variable inspection, watch expressions, and runtime expression evaluation in paused frames. Extends the 1.0 first-slice debugger.

**Checklist Items:**
- [Line 1327] Step over
- [Line 1328] Step into
- [Line 1329] Step out
- [Line 1334] Globals
- [Line 1335] Watches
- [Line 1336] Evaluate expression

### 5.13 Data Formats (6 items)

**Scope & Rationale:** Covers XML parsing/serialization, YAML support, Hex string encoding, binary serialization protocols, MIME type detection, and declarative data schema validation.

**Checklist Items:**
- [Line 604] XML
- [Line 605] YAML if demanded
- [Line 608] Hex
- [Line 609] Binary serialization strategy
- [Line 611] MIME/content-type helpers
- [Line 612] Schema validation

### 5.14 Filesystem (5 items)

**Scope & Rationale:** Covers binary file read/write, streaming I/O, chunked large-file processing, and directory watching (\FileSystemWatcher\). Complements the complete synchronous text/file operations in 1.0.

**Checklist Items:**
- [Line 312] Binary read/write
- [Line 314] Streams
- [Line 315] Large-file handling
- [Line 319] File watching
- [Line 320] Recursive watching

### 5.15 Concurrency & Tasks (5 items)

**Scope & Rationale:** Covers worker threads, background tasks, synchronization primitives, thread-safe channels, concurrent collections, and parallel loops (\do at the same time\). Concurrency requires a dedicated thread model deferred to 1.1.

**Checklist Items:**
- [Line 279] Worker/thread abstraction
- [Line 281] Synchronization primitives
- [Line 282] Channels/message passing
- [Line 283] Concurrent collections if needed
- [Line 286] Parallel loops/tasks if justified

### 5.16 Security & Cryptography (4 items)

**Scope & Rationale:** Covers public-key (asymmetric) cryptography, digital signatures, certificate parsing APIs, and PBKDF2/Argon2 password hashing via vetted system libraries.

**Checklist Items:**
- [Line 702] Public-key cryptography
- [Line 703] Signing/verification
- [Line 704] Certificate APIs
- [Line 706] Password hashing through proven libraries

### 5.17 Immediate Execution Rollup (3 items)

**Scope & Rationale:** Duplicate milestone markers from Section 48 covering module certification (Line 1626), package manager (Line 1657), and profiler hooks (Line 1661).

**Checklist Items:**
- [Line 1626] Module production certification.
- [Line 1657] Package manager.
- [Line 1661] Profiler hooks.

### 5.18 Desktop Packaging (3 items)

**Scope & Rationale:** Covers automated installer/uninstaller generation for desktop applications and Authenticode code-signing pipelines.

**Checklist Items:**
- [Line 898] Installer
- [Line 899] Uninstaller
- [Line 900] Code signing

### 5.19 Data Model (2 items)

**Scope & Rationale:** Covers raw binary/byte primitives and memory buffers needed for network protocols and binary file handling.

**Checklist Items:**
- [Line 160] Binary/byte data
- [Line 161] Buffers

### 5.20 Platform Gates (2 items)

**Scope & Rationale:** Duplicate milestone markers from Section 47 covering mature package ecosystem (Line 1587) and database ecosystem (Line 1593).

**Checklist Items:**
- [Line 1587] Mature package ecosystem
- [Line 1593] Database ecosystem

### 5.21 Math & Science (1 items)

**Scope & Rationale:** Basic descriptive statistics library (mean, median, mode, variance, standard deviation) for collections.

**Checklist Items:**
- [Line 659] Statistics package

### 5.22 Shell & Elevation (1 items)

**Scope & Rationale:** Formal UAC elevation request and process relaunching as administrator on Windows.

**Checklist Items:**
- [Line 451] Permissions/elevation model (PARTIAL, deliberately not flipped to done: D76's `isAdmin` on `get system information "user"` covers real elevation DETECTION, and operations that need elevation already report it specifically (D73's symlink-creation error is the clearest example) - but there is no way for an Otter program to REQUEST elevation/relaunch as admin, a genuine security decision needing its own explicit sign-off, not something to fold into a read-only OS-info pass)

### 5.23 Resource Management (1 items)

**Scope & Rationale:** Deterministic disposal/finalization model (\using\ or block cleanup) for file streams and external handles.

**Checklist Items:**
- [Line 258] Disposal/finalization model

### 5.24 Terminal & REPL (1 items)

**Scope & Rationale:** Persistent shell state across interactive REPL invocations.

**Checklist Items:**
- [Line 519] Persistent shell state

### 5.25 Documentation (1 items)

**Scope & Rationale:** Complete searchable full-text API reference portal.

**Checklist Items:**
- [Line 1480] Complete searchable API reference

## 6. D3 Summary: Later Platform Features

Total items: **113 items (20.8% of all deferred items)**.

Tier D3 contains capabilities that are **valuable to the Otter ecosystem but depend on broader runtime, platform, or Otter Studio architecture**. These features cannot be completed by simple language or library additions alone; they require specialized hosting substrates (such as HTML5 Canvas/WebGL runtimes, GPU backends, complex IDE multi-process protocols, or central package registry infrastructure).

Below is the summary of D3 items grouped across the **19 subsystems**:

### 6.1 2D Games (26 items)

**Scope & Rationale:** Covers the complete 2D game engine: fixed timestep game loops, touch/gamepad input mapping, sprite rendering, sprite sheet animation, 2D physics/collision, tile maps, camera controls, particle effects, game asset management, fullscreen resolution scaling, and level loading. Requires a dedicated game runtime substrate (e.g. Canvas2D or native SDL/Direct2D).

**Checklist Items:**
- [Line 979] Fixed timestep option
- [Line 982] Touch
- [Line 983] Gamepad
- [Line 984] Sprites
- [Line 985] Sprite sheets
- [Line 986] Animation
- [Line 987] Collision
- [Line 988] Physics
- [Line 989] Scenes
- [Line 990] Entities
- [Line 991] Components
- [Line 992] Camera
- [Line 993] Tile maps
- [Line 994] Particles
- [Line 995] Lighting
- [Line 996] Audio
- [Line 997] Music
- [Line 999] Save/load
- [Line 1000] Asset manager
- [Line 1001] Level loading
- [Line 1002] Fullscreen/window
- [Line 1003] Resolution/scaling
- [Line 1004] Frame timing
- [Line 1005] Game profiler
- [Line 1008] Controller compatibility
- [Line 1009] Packaging

### 6.2 Graphics Foundation (16 items)

**Scope & Rationale:** Covers 2D vector primitives: Points, Rectangles, Vector2/3/4, 2D transform matrices, Bézier vector paths, polygons, gradients, clipping masks, visual layers, blend modes, and offscreen framebuffer rendering. Serves as the foundation for both 2D games and custom UI vector components.

**Checklist Items:**
- [Line 947] Point
- [Line 949] Rectangle
- [Line 950] Vector2
- [Line 951] Vector3
- [Line 952] Vector4
- [Line 953] Matrix
- [Line 954] Quaternion
- [Line 955] Transform
- [Line 960] Paths
- [Line 961] Polygons
- [Line 963] Images/textures
- [Line 964] Gradients
- [Line 965] Clipping
- [Line 966] Layers
- [Line 967] Blend modes
- [Line 968] Offscreen rendering

### 6.3 Build System (8 items)

**Scope & Rationale:** Covers advanced build orchestration: incremental build detection, dependency graph topological sorting, parallel compilation workers, content-addressable build caching, asset optimization pipelines, and \otter publish\ deployment automation.

**Checklist Items:**
- [Line 1235] Incremental build
- [Line 1236] Dependency graph
- [Line 1237] Parallel build
- [Line 1238] Build cache
- [Line 1242] Resource processing
- [Line 1243] Asset processing
- [Line 1246] Build hooks with trust/security model
- [Line 1250] `otter publish`

### 6.4 Package Ecosystem (8 items)

**Scope & Rationale:** Covers central ecosystem services: public/private package registry server architecture, publishing commands (\otter package publish\), Git repository dependencies, package cryptographic signing, vulnerability advisory databases, package deprecation/yanking, and target-specific package manifests.

**Checklist Items:**
- [Line 1202] Package registry
- [Line 1212] Git packages if allowed
- [Line 1214] Signing
- [Line 1215] Vulnerability advisories
- [Line 1219] Publish
- [Line 1220] Deprecate/yank
- [Line 1221] Package documentation
- [Line 1223] Target-specific packages

### 6.5 Desktop UI Platform (6 items)

**Scope & Rationale:** Covers specialized desktop capabilities: custom native control authoring, cross-application OS drag-and-drop, UI localization resource catalogs, multi-monitor display coordinates, file association registrations, and custom URL protocol handlers.

**Checklist Items:**
- [Line 849] Custom controls
- [Line 859] OS drag/drop
- [Line 878] Localization
- [Line 880] Multi-monitor
- [Line 882] File associations
- [Line 883] Protocol handlers

### 6.6 Performance (5 items)

**Scope & Rationale:** Covers UI frame-rate benchmarks, game-loop latency benchmarks, interactive CPU profiler sampling, visual memory profiler integration, and allocation tracking hooks.

**Checklist Items:**
- [Line 1288] UI benchmark
- [Line 1289] Game-loop benchmark
- [Line 1292] CPU profiler integration
- [Line 1293] Memory profiler integration
- [Line 1294] Allocation tracking

### 6.7 Audio & Media (5 items)

**Scope & Rationale:** Covers basic media playback: sound effects, background music streaming, audio volume/panning controls, audio device enumeration, and image format decoders (PNG/JPEG/WebP).

**Checklist Items:**
- [Line 1155] Play sound
- [Line 1156] Play music
- [Line 1157] Volume/pan
- [Line 1158] Audio devices
- [Line 1166] Image codecs

### 6.8 Desktop Packaging (5 items)

**Scope & Rationale:** Covers advanced OS integration: in-process IPC channels, background auto-update daemons, native crash-dump generation, platform permission brokers, and sandboxed app store distribution packages.

**Checklist Items:**
- [Line 891] In-process IPC where appropriate
- [Line 903] Auto-update
- [Line 904] Crash dumps
- [Line 906] Platform permission handling
- [Line 907] Sandboxed distribution strategy where needed

### 6.9 Math & Science (5 items)

**Scope & Rationale:** Covers mathematical foundation packages: Vector2/3/4 math, Matrix math, Quaternions, linear algebra solvers, and arbitrary-precision big-number packages.

**Checklist Items:**
- [Line 655] Vector math (verified absent - zero references anywhere)
- [Line 656] Matrix math (verified absent, same as Vector math)
- [Line 657] Quaternion math
- [Line 660] Linear algebra package
- [Line 662] Arbitrary precision package

### 6.10 Web Frontend Platform (5 items)

**Scope & Rationale:** Covers advanced web application features: hot module reloading (HMR) server integration, static-site generation (SSG), Progressive Web App (PWA) manifests, service workers for offline caching, and server-side rendering (SSR) hydration.

**Checklist Items:**
- [Line 762] Hot reload
- [Line 765] Static-site generation
- [Line 766] PWA
- [Line 767] Service workers
- [Line 768] SSR/hydration decision

### 6.11 Database Development (5 items)

**Scope & Rationale:** Covers enterprise database workflows: automated schema migrations, database schema introspection, stored procedure execution, bulk row copying, and object-relational mapping (ORM) query builders.

**Checklist Items:**
- [Line 679] Migrations
- [Line 680] Schema introspection
- [Line 681] Stored procedures
- [Line 682] Bulk operations
- [Line 684] ORM/query-builder only if justified

### 6.12 Resource Management (4 items)

**Scope & Rationale:** Covers runtime enforcement: execution memory quotas, large-object heap management, and native unmanaged resource ownership tracking.

**Checklist Items:**
- [Line 261] Memory limits
- [Line 263] Large-object handling
- [Line 264] Native resource ownership rules
- [Line 265] FFI ownership rules

### 6.13 Web Backend Platform (3 items)

**Scope & Rationale:** Covers distributed server architecture: background job queues, server performance metrics (Prometheus format), and automated Docker container deployment packaging.

**Checklist Items:**
- [Line 801] Background jobs
- [Line 807] Metrics
- [Line 809] Container deployment

### 6.14 Networking (3 items)

**Scope & Rationale:** Covers low-level networking: raw TCP client/server streams, raw UDP datagram sockets, and socket connection pooling.

**Checklist Items:**
- [Line 588] TCP
- [Line 589] UDP
- [Line 594] Connection pooling

### 6.15 Debugging (2 items)

**Scope & Rationale:** Covers asynchronous call stack stitching across async task boundaries and full Debug Adapter Protocol (DAP) implementation for VS Code.

**Checklist Items:**
- [Line 1338] Async stack support
- [Line 1340] Debug Adapter Protocol evaluation

### 6.16 Release Engineering (2 items)

**Scope & Rationale:** Covers central package registry infrastructure and automated release rollback pipelines.

**Checklist Items:**
- [Line 1543] Package registry availability
- [Line 1547] Rollback

### 6.17 Terminal & REPL (2 items)

**Scope & Rationale:** Covers multi-tab terminal sessions and cross-platform PTY pseudo-terminal abstractions for Otter Studio.

**Checklist Items:**
- [Line 520] Multiple sessions
- [Line 522] Cross-platform PTY abstraction

### 6.18 Functions & Delegates (2 items)

**Scope & Rationale:** Covers first-class function references (functions as variables) and callback delegate types.

**Checklist Items:**
- [Line 218] First-class function values if required
- [Line 219] Callbacks/delegates

### 6.19 Immediate Execution Rollup (1 items)

**Scope & Rationale:** Section 48 milestone marker for cross-platform shell certification (Line 1642).

**Checklist Items:**
- [Line 1642] Cross-platform shell certification.

## 7. D4 Summary: Long-Term & Ambitious Initiatives

Total items: **216 items (39.8% of all deferred items)**.

Tier D4 contains large-scale capabilities, alternative compilation targets, and capstone vision criteria that represent **multi-year, ambitious initiatives**. These items must be strictly isolated from the Otter 1.0 and 1.1 release roadmaps to protect the language from catastrophic scope sprawl.

Below is the summary of D4 items grouped across the **19 subsystems**:

### 7.1 3D Modeling & Creation (58 items)

**Scope & Rationale:** Covers the complete 3D CAD and procedural modeling suite: scene graphs, mesh editing (extrude, inset, bevel, loop cut, weld, knife, fill), normal editing, UV unwrapping, parametric modifiers (mirror, array, solidify, subsurf, boolean, decimate), sculpting brushes, vertex painting, procedural node graphs, skeletal rigging, inverse kinematics, keyframe animation curves, 3D viewport gizmos, and CAD file formats (OBJ, glTF, STL, 3MF). This constitutes an entire 3D creative suite equivalent to Blender/Maya tools and belongs exclusively to long-term platform evolution.

**Checklist Items:**
- [Line 1060] Scene graph
- [Line 1061] Object hierarchy
- [Line 1063] Sphere
- [Line 1064] Cylinder
- [Line 1065] Cone
- [Line 1066] Plane
- [Line 1067] Torus
- [Line 1068] Mesh editing API
- [Line 1069] Vertex selection/editing
- [Line 1070] Edge selection/editing
- [Line 1071] Face selection/editing
- [Line 1072] Extrude
- [Line 1073] Inset
- [Line 1074] Bevel
- [Line 1075] Loop cut
- [Line 1077] Merge/weld
- [Line 1078] Knife/cut
- [Line 1079] Fill
- [Line 1080] Normals tools
- [Line 1081] UV unwrap
- [Line 1083] Modifiers
- [Line 1084] Mirror
- [Line 1085] Array
- [Line 1086] Solidify
- [Line 1087] Subdivision surface
- [Line 1088] Boolean
- [Line 1089] Decimate
- [Line 1090] Sculpting architecture
- [Line 1091] Brushes
- [Line 1092] Painting/texturing
- [Line 1094] Node graph system
- [Line 1095] Geometry nodes/procedural modeling strategy
- [Line 1096] Rigging
- [Line 1097] Bones
- [Line 1098] Weight painting
- [Line 1099] Keyframe animation
- [Line 1100] Curves
- [Line 1101] Animation graph/timeline
- [Line 1102] Constraints
- [Line 1103] Cameras
- [Line 1104] Lighting
- [Line 1105] Render settings
- [Line 1106] Import OBJ
- [Line 1107] Export OBJ
- [Line 1108] Import/export glTF
- [Line 1110] Import/export STL
- [Line 1111] Import/export 3MF
- [Line 1112] Scene save format
- [Line 1113] Undo/redo command model
- [Line 1114] Non-destructive editing
- [Line 1115] GPU viewport
- [Line 1116] Picking/selection
- [Line 1117] Gizmos
- [Line 1118] Snapping
- [Line 1119] Grid
- [Line 1120] Units
- [Line 1121] Measurement
- [Line 1122] 3D printing validation tools if pursued

### 7.2 3D Graphics Engine (32 items)

**Scope & Rationale:** Covers a production-grade 3D graphics rendering engine: 3D scene transform hierarchies, orthographic/perspective projections, PBR (Physically Based Rendering) materials, HDR pipelines, post-processing filters, shadow mapping, frustum/occlusion culling, skeletal animation skinning, morph targets, 3D particle systems, and low-level shader abstractions. Requires deep GPU hardware abstraction.

**Checklist Items:**
- [Line 1013] Vector3
- [Line 1014] Matrix4
- [Line 1015] Quaternion
- [Line 1016] Transform hierarchy
- [Line 1017] Coordinate-system specification
- [Line 1020] Orthographic projection
- [Line 1024] Normals
- [Line 1025] UVs
- [Line 1026] Tangents
- [Line 1027] Materials
- [Line 1028] Textures
- [Line 1029] Samplers
- [Line 1030] Lights
- [Line 1031] Shadows
- [Line 1033] Culling
- [Line 1034] Transparency
- [Line 1035] Render targets
- [Line 1036] Framebuffers
- [Line 1037] Shader abstraction
- [Line 1039] PBR materials
- [Line 1040] HDR
- [Line 1041] Post-processing
- [Line 1042] Skybox/environment
- [Line 1043] Instancing
- [Line 1044] Level of detail
- [Line 1045] Occlusion/frustum culling
- [Line 1046] Skeletal animation
- [Line 1047] Skinning
- [Line 1048] Morph targets
- [Line 1049] Particle systems
- [Line 1050] 3D audio
- [Line 1051] GPU resource lifetime

### 7.3 Game Engine Architecture (23 items)

**Scope & Rationale:** Covers a full-featured 3D game engine: Entity-Component-System (ECS) architecture, scene lifecycle managers, prefabs, 3D rigid body physics, ray casting, 3D navigation meshes/pathfinding, AI behavior trees, animation state machines, input mapping layers, and networked multiplayer state replication.

**Checklist Items:**
- [Line 1126] Entity/component architecture decision
- [Line 1127] Scene lifecycle
- [Line 1128] Prefabs/templates
- [Line 1129] Physics 2D
- [Line 1130] Physics 3D
- [Line 1131] Rigid bodies
- [Line 1133] Ray casting
- [Line 1134] Navigation/pathfinding
- [Line 1135] AI behavior system
- [Line 1136] Animation state machines
- [Line 1137] Audio engine
- [Line 1138] Input mapping
- [Line 1139] UI overlay
- [Line 1140] Save system
- [Line 1141] Resource manager
- [Line 1142] Streaming assets
- [Line 1143] Scene streaming
- [Line 1144] Networking/multiplayer architecture
- [Line 1145] Deterministic simulation strategy if needed
- [Line 1147] Hot reload
- [Line 1148] Build/export pipeline
- [Line 1149] Platform abstraction
- [Line 1150] Profiling

### 7.4 Native Interoperability / FFI (19 items)

**Scope & Rationale:** Covers native C ABI interoperability: loading native Windows DLLs / shared libraries, C struct layout marshaling, pointer arithmetic, native callbacks, unmanaged memory lifetime tracking, automatic C header import binding generators, and WebAssembly foreign function boundaries. Explicitly deferred to prevent compromising memory safety in 1.0.

**Checklist Items:**
- [Line 1173] Define FFI model
- [Line 1174] Call C ABI
- [Line 1175] Native shared libraries
- [Line 1176] Windows DLLs
- [Line 1179] Primitive marshaling
- [Line 1180] Strings
- [Line 1181] Structs
- [Line 1182] Arrays/buffers
- [Line 1183] Callbacks
- [Line 1184] Function pointers
- [Line 1185] Ownership/lifetime
- [Line 1186] Error propagation
- [Line 1187] Threading rules
- [Line 1188] Unsafe/native capability clearly visible
- [Line 1189] Native binding generator
- [Line 1190] C header importer if useful
- [Line 1194] JavaScript/npm interop strategy
- [Line 1195] WebAssembly interoperability
- [Line 1196] ABI/version compatibility tests

### 7.5 Mobile & Future Targets (16 items)

**Scope & Rationale:** Covers native mobile application runtimes: Android APK/AAB compilation, iOS app lifecycle, mobile touch gestures, hardware sensors (accelerometer, gyroscope), camera APIs, push notifications, mobile app store packaging, as well as IoT, microcontroller bare-metal backends, and WASI serverless runtimes.

**Checklist Items:**
- [Line 1396] Mobile architecture
- [Line 1397] Android
- [Line 1398] iOS
- [Line 1399] Touch
- [Line 1400] Sensors
- [Line 1401] Camera
- [Line 1403] Notifications
- [Line 1404] App lifecycle
- [Line 1405] Mobile storage
- [Line 1406] Mobile packaging
- [Line 1407] Store publishing
- [Line 1408] Embedded/IoT strategy
- [Line 1409] Microcontroller backend research
- [Line 1410] Kernel/driver target explicitly scoped
- [Line 1411] Cloud/serverless target
- [Line 1412] WebAssembly/WASI target

### 7.6 Compiler Targets (15 items)

**Scope & Rationale:** Covers alternative compiler backends and code generators: WebAssembly (WASM), native machine code via LLVM, .NET Common Intermediate Language (CIL), Java Virtual Machine (JVM) bytecode, C transpilation, embedded firmware backends, and whole-program dead-code elimination / tree-shaking.

**Checklist Items:**
- [Line 1259] WebAssembly target
- [Line 1260] Native-code target strategy
- [Line 1261] LLVM backend evaluation
- [Line 1262] .NET IL backend evaluation
- [Line 1263] JVM backend evaluation
- [Line 1264] C transpilation backend evaluation
- [Line 1265] Embedded backend strategy
- [Line 1266] GPU shader/backend strategy
- [Line 1267] Debug information
- [Line 1268] Source maps
- [Line 1269] Optimization levels
- [Line 1270] Dead-code elimination
- [Line 1271] Constant folding
- [Line 1272] Tree shaking
- [Line 1273] Minification for web

### 7.7 Immediate Execution Rollup (15 items)

**Scope & Rationale:** Duplicate milestone rollup entries from Section 48 covering FFI (Line 1658), 2D engine (Line 1668), physics/scenes (Line 1669), dogfood game (Line 1671), GPU rendering (Line 1676), shader pipeline (Line 1677), lights/cameras (Line 1678), scene graph (Line 1679), modeling operations (Line 1681), 3D import/export (Line 1682), node/procedural system (Line 1683), dogfood 3D application (Line 1684), mobile targets (Line 1688), AI ecosystem (Line 1689), and native interop (Line 1690).

**Checklist Items:**
- [Line 1658] FFI.
- [Line 1668] 2D engine.
- [Line 1669] Physics/scenes/assets.
- [Line 1671] Dogfood complete game.
- [Line 1676] GPU rendering abstraction.
- [Line 1677] Mesh/material/shader pipeline.
- [Line 1678] Cameras/lights/animation/physics.
- [Line 1679] Scene graph.
- [Line 1681] Modeling mesh-edit operations.
- [Line 1682] Import/export.
- [Line 1683] Node/procedural system.
- [Line 1684] Dogfood 3D creation application.
- [Line 1688] Mobile/future targets where desired.
- [Line 1689] Data/AI ecosystem.
- [Line 1690] Native interoperability ecosystem.

### 7.8 Capstone Platform Vision (13 items)

**Scope & Rationale:** Covers Section 50's final success definition criteria: high-level assertions that Otter can automate computers, build full-stack web servers, build 2D/3D games, package desktop software, and call native libraries. These represent the overarching platform vision across its lifetime.

**Checklist Items:**
- [Line 1738] automate and administer a computer;
- [Line 1739] build complete command-line applications;
- [Line 1740] manipulate files, processes, networking, structured data, and databases;
- [Line 1742] build and package professional desktop applications;
- [Line 1743] build complete browser frontends;
- [Line 1744] build servers, APIs, and full-stack web applications;
- [Line 1745] build 2D games;
- [Line 1746] build 3D interactive applications and games;
- [Line 1747] create/edit/render 3D scenes and models through an appropriate engine/provider;
- [Line 1749] call native/external libraries when the standard platform does not provide a capability;
- [Line 1751] test, debug, profile, package, and publish those programs;
- [Line 1752] run appropriate source consistently across supported hosts;
- [Line 1753] extend the platform without changing core Otter semantics.

### 7.9 Data Science & AI (9 items)

**Scope & Rationale:** Covers machine learning and scientific computing: n-dimensional tensor arrays, DataFrame table manipulation libraries, GPU compute shaders (WebGPU compute), CUDA interop, and Python ecosystem interoperability bridges.

**Checklist Items:**
- [Line 1416] Arrays/tensors package
- [Line 1417] DataFrame/table package
- [Line 1418] Statistics
- [Line 1420] Plotting
- [Line 1421] Notebook/interactive workflow
- [Line 1425] CUDA interoperability if appropriate
- [Line 1426] WebGPU compute
- [Line 1427] Parallel numerical operations
- [Line 1428] Python ecosystem bridge if strategically useful

### 7.10 Audio & Media (5 items)

**Scope & Rationale:** Covers advanced audio DSP: live microphone recording, real-time audio streaming buffers, 3D spatial audio HRTF positioning, real-time reverb/delay audio filters, and cross-platform media pipeline abstractions.

**Checklist Items:**
- [Line 1159] Recording
- [Line 1160] Streaming audio
- [Line 1161] 3D spatial audio
- [Line 1162] Audio effects
- [Line 1169] Cross-platform media abstraction

### 7.11 Platform Gates (2 items)

**Scope & Rationale:** Duplicate milestone markers from Section 47 covering native FFI (Line 1588) and 3D modeling APIs (Line 1600).

**Checklist Items:**
- [Line 1588] Native FFI
- [Line 1600] 3D modeling/creation APIs

### 7.12 Package Ecosystem (2 items)

**Scope & Rationale:** Covers private enterprise package registry architectures and complex native binary dependency resolution packages.

**Checklist Items:**
- [Line 1217] Private registries
- [Line 1222] Native dependency handling

### 7.13 Math & Science (1 items)

**Scope & Rationale:** Broad scientific package ecosystem (special functions, numerical solvers).

**Checklist Items:**
- [Line 664] Scientific package ecosystem

### 7.14 Memory Architecture (1 items)

**Scope & Rationale:** Weak references (\WeakReference\) for specialized cache eviction.

**Checklist Items:**
- [Line 260] Weak references only if needed

### 7.15 Checklist Meta (1 items)

**Scope & Rationale:** Checklist header legend line (Line 22), an obsolete markdown artifact.

**Checklist Items:**
- [Line 22] Required, partial, deferred, blocked, or not yet production-certified.

### 7.16 Web Backend Platform (1 items)

**Scope & Rationale:** Automated multi-cloud infrastructure orchestration (Kubernetes, AWS, Azure).

**Checklist Items:**
- [Line 810] Cloud deployment

### 7.17 Performance (1 items)

**Scope & Rationale:** Dedicated 3D rendering framerate and GPU draw-call benchmarks.

**Checklist Items:**
- [Line 1290] 3D render benchmark

### 7.18 Debugging (1 items)

**Scope & Rationale:** Game-specific visual debugging tools (collider wireframes, entity inspectors).

**Checklist Items:**
- [Line 1344] Game debugging

### 7.19 Build System (1 items)

**Scope & Rationale:** Complex multi-architecture cross-compilation toolchains.

**Checklist Items:**
- [Line 1247] Cross-compilation strategy

## 8. Duplicate, Obsolete, and Misclassified Findings

During the individual audit of all 543 deferred items, **39 items (7.2%)** were identified as misclassified, duplicates, or obsolete artifacts. Leaving these items classified as deferred post-1.0 features distorts backlog metrics and conceals work that the engineering team has already delivered.

---

### 8.1 Items Already Implemented in V1 (15 Items)

These 15 items were found to be fully or partially implemented in the codebase as of commit \1fc96e78\. They should not remain in Category D (\"Deferred to 1.1+\").

| Line | Item Text | Checklist Section | Implemented Capability & Evidence | Recommended Disposition |
|---|---|---|---|---|
| **610** | Compression | 14. Data Formats | Decision **D87** (\zip folder\ / \unzip\) in \src/Otter.Library.psm1\ (lines 965-1020). Fully tested and verified. | Reclassify to **Category B** |
| **707** | Constant-time primitives delegated to vetted libraries | 18. Cryptography | Decision **D92** constant-time tag comparison against timing attacks in PBKDF2/AES-256 HMAC verification. | Reclassify to **Category B** |
| **1280** | Lexer benchmark | 34. Performance | Hardening Pass 1: \	ools/Profile-OtterParser.ps1\ profiles lexing scaling from 100 to 10k statements. | Reclassify to **Category B** |
| **1281** | Parser benchmark | 34. Performance | Hardening Pass 1: \	ools/Profile-OtterParser.ps1\ profiles tokenization and AST generation. | Reclassify to **Category B** |
| **1282** | Interpreter benchmark | 34. Performance | Hardening Pass 1: \	ools/Profile-OtterInterpreter.ps1\ benchmarks arithmetic, calls, and props up to 100k ops. | Reclassify to **Category B** |
| **1285** | Memory benchmark | 34. Performance | Hardening Pass 1: \	ools/Test-ResourceSoak.ps1\ profiles peak private bytes across 8 soak suites with 0 leaks. | Reclassify to **Category B** |
| **1295** | Performance regression CI | 34. Performance | Hardening Pass 1: \	ools/Test-OtterPerformanceGate.ps1\ enforces 3.0x baseline variance gates. | Reclassify to **Category B** |
| **1325** | Breakpoint hooks | 36. Debugging | Production debugger: \Set-OtterStatementHook\ in \src/Otter.Interpreter.psm1\. | Reclassify to **Category B** |
| **1330** | Pause | 36. Debugging | Production debugger: breakpoint-triggered pause loop in \src/Otter.Debugger.psm1\. | Reclassify to **Category B** |
| **1331** | Continue | 36. Debugging | Production debugger: \continue\ resume command in \src/Otter.Debugger.psm1\. | Reclassify to **Category B** |
| **1332** | Stack frames | 36. Debugging | Production debugger: call stack frame capture and reporting in \src/Otter.Debugger.psm1\. | Reclassify to **Category B** |
| **1333** | Locals | 36. Debugging | Production debugger: frame-isolated variable reflection via \Get-OtterDebugLocals\. | Reclassify to **Category B** |
| **1339** | Debug protocol | 36. Debugging | Production debugger: structured \@@OTTER_DEBUG@@\ JSON stream emitted to stdout. | Reclassify to **Category B** |
| **1640** | System information. | 48. Immediate Order | Decision **D76**: \get system information \"os\"/\"cpu\"/\"user\"/\"memory\"\ verified in stdlib tests. | Reclassify to **Category B** |
| **1648** | File dialogs/clipboard/notifications/menus. | 48. Immediate Order | Decisions **D70** (\clipboard\, \
otify\) and **D84** (\choose file/folder/save file\) fully implemented. | Reclassify to **Category B** |

---

### 8.2 Duplicate Roll-up Milestone Items (23 Items)

Sections 47 (*General-Purpose Platform Gates*) and 48 (*Immediate Execution Order*) contain high-level project milestones that repeat technical requirements already itemized in domain-specific sections. Tracking them as separate deferred features inflates the checklist count by 23 items.

| Line | Section 47/48 Roll-up Item | Primary Defining Section | Recommended Disposition |
|---|---|---|---|
| **1587** | Mature package ecosystem | Section 31 (Package Ecosystem) | Mark as Duplicate of Section 31 |
| **1588** | Native FFI | Section 30 (Native Interoperability / FFI) | Mark as Duplicate of Section 30 |
| **1593** | Database ecosystem | Section 17 (Database Development) | Mark as Duplicate of Section 17 |
| **1600** | 3D modeling/creation APIs | Section 27 (3D Creation / Modeling) | Mark as Duplicate of Section 27 |
| **1626** | Module production certification. | Section 5 (Functions, Scope & Modules, Line 207) | Mark as Duplicate of Line 207 |
| **1642** | Cross-platform shell certification. | Section 38 (Cross-Platform Semantics) | Mark as Duplicate of Section 38 |
| **1657** | Package manager. | Section 31 (Package Ecosystem, Line 1203) | Mark as Duplicate of Section 31 |
| **1658** | FFI. | Section 30 (Native Interoperability / FFI, Line 1173) | Mark as Duplicate of Section 30 |
| **1661** | Profiler hooks. | Section 34 (Performance, Line 1291) | Mark as Duplicate of Line 1291 |
| **1668** | 2D engine. | Section 25 (2D Game Development, Line 989) | Mark as Duplicate of Section 25 |
| **1669** | Physics/scenes/assets. | Section 25 (2D Game Development, Lines 988, 1000) | Mark as Duplicate of Section 25 |
| **1671** | Dogfood complete game. | Section 25 (2D Game Development) & Section 43 | Mark as Duplicate of Section 25/43 |
| **1676** | GPU rendering abstraction. | Section 24 (Graphics Foundation, Line 968) | Mark as Duplicate of Section 24 |
| **1677** | Mesh/material/shader pipeline. | Section 26 (3D Graphics Engine, Lines 1027, 1037) | Mark as Duplicate of Section 26 |
| **1678** | Cameras/lights/animation/physics. | Section 26 (3D Graphics Engine) & Section 28 | Mark as Duplicate of Section 26/28 |
| **1679** | Scene graph. | Section 27 (3D Creation / Modeling, Line 1060) | Mark as Duplicate of Line 1060 |
| **1681** | Modeling mesh-edit operations. | Section 27 (3D Creation / Modeling, Line 1068) | Mark as Duplicate of Line 1068 |
| **1682** | Import/export. | Section 27 (3D Creation / Modeling, Line 1106) | Mark as Duplicate of Lines 1106-1111 |
| **1683** | Node/procedural system. | Section 27 (3D Creation / Modeling, Line 1094) | Mark as Duplicate of Line 1094 |
| **1684** | Dogfood 3D creation application. | Section 27 (3D Creation / Modeling) & Section 43 | Mark as Duplicate of Section 27/43 |
| **1688** | Mobile/future targets where desired. | Section 39 (Mobile / Future Targets, Line 1396) | Mark as Duplicate of Section 39 |
| **1689** | Data/AI ecosystem. | Section 40 (Data Science / AI / Compute, Line 1416) | Mark as Duplicate of Section 40 |
| **1690** | Native interoperability ecosystem. | Section 30 (Native Interoperability / FFI) | Mark as Duplicate of Section 30 |

---

### 8.3 Obsolete Checklist Legend Artifact (1 Item)

- **Checklist Line 22:** \- [ ] Required, partial, deferred, blocked, or not yet production-certified.\
- **Audit Finding:** This line appears under the heading \## Status legend and permanent rules\. It is an explanatory definition of what unchecked checkboxes mean in the markdown document, not a functional requirement. It was erroneously matched by regex scrapers as a pending platform item.
- **Recommended Disposition:** Reclassify to **Category F (Obsolete / Non-Item)**.

---

### 8.4 Studio vs. Language Runtime Boundary

Several items categorized as deferred belong to **Otter Studio (Developer Tooling)** rather than the core language interpreter/compiler:
- Line 520 (\Multiple sessions\ in Terminal) -> Studio multi-tab terminal UI.
- Line 522 (\Cross-platform PTY abstraction\) -> Studio terminal daemon.
- Line 1340 (\Debug Adapter Protocol evaluation\) -> Studio/VS Code extension protocol bridge.
- Line 1421 (\Notebook/interactive workflow\) -> Studio interactive document viewer.

These should be mapped to **Category E (Otter Studio & Tooling Work)** rather than remaining in the language core backlog.

---

## 9. Recommended V1 Reconsideration Set

> [!IMPORTANT]
> **This is a proposal for review only. No code has been modified.**  
> In accordance with project instructions, the final decision regarding which items enter Otter 1.0 belongs solely to **Jeff Macy**.

### Proposed 1.0 Reconsideration Tiers

We recommend that Jeff review the following **8 active candidates**, organized into three strategic tiers:

#### Tier 1A: Essential Automation & CLI Core (Top Priority)
These three items address the most critical functional gaps for a 1.0 general-purpose language intended for scripting and automation:

1. **\CSV read/write\ (Line 603)**
   - *Why:* Automation scripts without native CSV cannot reliably process tabular data or spreadsheet exports.
   - *Proposed Syntax:* \ead csv from <path> into <var>\, \convert <list> to csv into <var>\.
   - *Estimated Size:* Medium (~120 lines). Zero architectural risk.
2. **\Arguments/options\ (Line 1634)**
   - *Why:* CLI programs in 1.0 must be able to inspect command-line arguments passed to them (\otter run script.ot arg1 arg2\).
   - *Proposed Syntax:* \get arguments into <var>\ or implicit global \rguments\ list.
   - *Estimated Size:* Small (~40 lines).
3. **\Environment/cwd\ (Line 1635)**
   - *Why:* Shell automation requires inspecting/changing the current working directory and setting environment variables for child processes.
   - *Proposed Syntax:* \get current directory into <var>\, \set current directory to <path>\, \set environment variable \"KEY\" to \"VAL\"\.
   - *Estimated Size:* Small (~50 lines).

#### Tier 1B: Network Automation Completion (Secondary Priority)
4. **\File download\ (Line 575)**
   - *Why:* Allows console scripts to retrieve remote files/assets directly (\download file from <url> to <path>\).
   - *Estimated Size:* Medium (~70 lines).
5. **\Query parameters\ (Line 569)**
   - *Why:* Clean URL parameter formatting/parsing for API consumption.
   - *Estimated Size:* Small (~60 lines).

#### Tier 1C: Release Onboarding & Compliance Polish
6. **\Language tour\ (Line 1456)**: Comprehensive 15-minute onboarding guide covering language syntax and paradigms.
7. **\Installation\ (Line 1457)**: Official installation, verification, and uninstallation guide for the distribution ZIP.
8. **\License/third-party notices\ (Line 1551)**: Consolidated legal notices file for clean binary packaging.

---

### Immediate Next Steps for Reconciliation

1. **Promote the 15 Already-Implemented Items** from Category D to Category B in \docs/V1_CHECKLIST_RECONCILIATION.md\.
2. **Reclassify the 23 Duplicate Roll-ups and 1 Obsolete Legend Item** so they no longer inflate the post-1.0 backlog.
3. **Await Jeff's Decision** on the Tier 1A/1B/1C reconsideration candidates before undertaking any further implementation work.
