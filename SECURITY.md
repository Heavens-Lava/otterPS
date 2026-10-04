# Security Policy & Threat Model

This document outlines the security architecture, threat model, vulnerability reporting process, and mitigation controls for **Otter** and **Otter Studio**.

---

## 1. Supported Versions

| Version | Supported |
|---|---|
| 1.0.x (Current Release Candidate) | :white_check_mark: |
| < 1.0 | :x: |

---

## 2. Threat Model & Security Architecture

Otter Studio is a hybrid visual IDE and development environment designed to run locally. Because developer tools possess capabilities to read source files and spawn child processes, strict defense-in-depth boundaries are enforced.

### Threat Model Boundaries

```
[ External Web Pages ]
        │  (Untrusted)
        ▼  403 Forbidden (Origin / CSRF Protection)
┌────────────────────────────────────────────────────────┐
│  Otter Studio Backend (127.0.0.1:4200 - Loopback Only) │
│  - CSP: default-src 'self'                             │
│  - Path Containment & Symlink Escape Defense           │
│  - Argument Parameterization (BatBadBut Defense)       │
│  - Request Body Limit (10 MB Ceiling)                  │
└───────────────────────┬────────────────────────────────┘
                        │
      ┌─────────────────┴─────────────────┐
      ▼                                   ▼
┌───────────────────────────┐   ┌───────────────────────────┐
│ Preview Sandbox (Iframe)  │   │ Child Processes           │
│ - sandbox="allow-scripts" │   │ - Parameterized execFile  │
│ - NO allow-same-origin    │   │ - No raw shell expansion  │
│ - Opaque origin ("null")  │   │ - Workspace trust check   │
│ - Zero native bridge access│  │ - Secret redaction in logs│
└───────────────────────────┘   └───────────────────────────┘
```

### Security Controls

1. **Loopback-Only Binding & Origin Validation:**
   - Otter Studio server binds strictly to IPv4 loopback `127.0.0.1`.
   - All HTTP endpoints validate the `Origin` and `Referer` headers. Cross-origin requests from untrusted external domains (e.g. `https://malicious.example.com`) are rejected with `403 Forbidden`.
   - Ephemeral session token (`X-Otter-Session-Token`) validates mutating API actions.

2. **Preview Sandbox Isolation:**
   - Application previews run inside an `<iframe>` configured strictly with `sandbox="allow-scripts allow-modals"`.
   - The `allow-same-origin` token is explicitly omitted, creating a distinct opaque origin (`"null"`).
   - The previewed code cannot read `window.parent.localStorage`, access the IDE DOM, or invoke native backend APIs.

3. **Path Traversal & Symlink Escape Prevention:**
   - Every file access endpoint validates paths using canonical path resolution (`path.resolve`).
   - String traversal attacks (e.g. `../../etc/passwd` or `C:\Windows`) are rejected with `403 Forbidden`.
   - Path prefix confusion attacks (e.g. `otterPS-other` against `otterPS`) are rejected.
   - Symlink escape validation verifies `fs.realpathSync` to guarantee symlinks cannot escape the project repository root.

4. **Command Injection Hardening (BatBadBut / CVE-2024-24576 class):**
   - Execution commands are passed via parameterized argument arrays (`execFile` and `spawn`), bypassing shell interpolation.
   - Any user-provided command-line arguments are validated and sanitized to refuse shell meta-characters (`&`, `|`, `<`, `>`, `^`, `%`, `!`, `\r`, `\n`, `\0`).

5. **Request Body Size & DoS Protection:**
   - HTTP request bodies are subject to a strict 10 MB ceiling. Requests exceeding 10 MB are terminated immediately with `413 Payload Too Large`.

6. **Workspace Trust:**
   - Projects opened outside trusted workspaces are flagged as untrusted. Otter Studio warns before executing programs, running build hooks, or launching debug sessions in untrusted workspaces.

7. **Secret Redaction:**
   - Terminal outputs, diagnostic logs, and error traces automatically mask sensitive tokens, AWS keys, GitHub credentials, private keys, and passwords using pattern-based redaction (`[REDACTED_SECRET]`).

---

## 3. Reporting a Vulnerability

If you discover a security vulnerability in Otter or Otter Studio, please report it responsibly:

1. **Do not create a public GitHub issue.**
2. Send an email with reproduction details, impact analysis, and proof-of-concept code to:
   **security@otter-lang.org** (or file a private GitHub Advisory).
3. **Response Timeline SLA:**
   - **Acknowledgment:** Within 24 hours of receipt.
   - **Triage & Reproduction:** Within 72 hours.
   - **Patch Release:** Target of 7 to 14 business days depending on severity.
   - **Public Advisory:** Published in coordination with the reporter after patch deployment.

---

## 4. Software Bill of Materials (SBOM) & Dependencies

Otter Studio maintains a strict zero-bloat dependency policy.
- Runtime backend has **zero third-party npm dependencies** (uses Node.js built-in standard modules: `http`, `fs`, `os`, `path`, `crypto`, `child_process`).
- Frontend is pure Vanilla HTML, CSS, and modern ECMAScript standard modules.
