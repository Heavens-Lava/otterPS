# Otter Installation Guide

Welcome to the Otter programming language! This guide covers everything you need to install, configure, verify, and uninstall Otter on your machine.

---

## Table of Contents

1. [System Requirements](#1-system-requirements)
2. [Quick Install (Recommended)](#2-quick-install-recommended)
3. [Alternative Installation Options](#3-alternative-installation-options)
   - [Custom Installation Directory](#custom-installation-directory)
   - [Portable / Zero-Install Usage](#portable--zero-install-usage)
   - [Linux and macOS (PowerShell 7)](#linux-and-macos-powershell-7)
   - [Developer Setup (From Source)](#developer-setup-from-source)
4. [Verifying Your Installation](#4-verifying-your-installation)
5. [Running Your First Program](#5-running-your-first-program)
6. [Command-Line Reference](#6-command-line-reference)
7. [Uninstalling Otter](#7-uninstalling-otter)
8. [Troubleshooting & FAQ](#8-troubleshooting--faq)

---

## 1. System Requirements

Otter 1.0 runs on Windows, Linux and macOS. One release ZIP serves all three.

| Requirement | Windows | Linux and macOS |
|---|---|---|
| **Operating System** | Windows 11 or Windows 10 (64-bit) | A current 64-bit Linux distribution, or macOS |
| **Runtime Engine** | **Windows PowerShell 5.1** (`powershell.exe`), included with Windows | **PowerShell 7** (`pwsh`), installed from <https://aka.ms/install-powershell> |
| **Launcher** | `otter.cmd` | `otter` |
| **Privileges** | Standard user account (no administrator rights) | Standard user account (no `sudo`) |
| **Web Browser (Optional)** | Edge, Chrome or Firefox, for `otter web` applications | Any current browser, for `otter web` applications |

> [!IMPORTANT]
> **Windows PowerShell 5.1 vs. PowerShell 7 (pwsh):**
> On Windows, the `otter.cmd` launcher always runs Otter on **Windows PowerShell 5.1** (`powershell.exe`), so you do not need to manage this. On Linux and macOS, the `otter` launcher runs Otter on PowerShell 7 (`pwsh`). Desktop windows and other features built on Windows itself need Windows; see [Linux and macOS (PowerShell 7)](#linux-and-macos-powershell-7).

---

## 2. Quick Install (Recommended)

The easiest way to install Otter is using the automated per-user installer.
These steps are for Windows; for Linux and macOS see
[Linux and macOS (PowerShell 7)](#linux-and-macos-powershell-7).

### Step 1: Download & Extract

Download the latest versioned release archive:
`otter-1.0.0-rc.12.zip`

Extract the ZIP contents into a temporary directory or your Downloads folder.

### Step 2: Run the Installer

Open Windows PowerShell (`powershell.exe`) in the extracted directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-Otter.ps1 -AddToUserPath
```

#### What the installer does:
- Copies the complete Otter runtime, modules, and `otter.cmd` launcher to `%LOCALAPPDATA%\Otter\1.0.0-rc.12\`.
- Adds that directory to your User `PATH` environment variable.
- Runs an automated health check (`otter.cmd --version`) to confirm successful installation.
- Requires zero administrative rights and will not alter system-wide configurations.

### Step 3: Open a New Terminal

Close your current terminal and open a **new** PowerShell or Command Prompt window so the updated `PATH` takes effect.

Verify Otter is available:

```powershell
otter --version
```

Expected output:
```text
Otter 1.0.0-rc.12
```

---

## 3. Alternative Installation Options

### Custom Installation Directory

If you prefer to install Otter into a specific directory (for example, `C:\Tools\Otter`), provide the `-Destination` parameter:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-Otter.ps1 -Destination "C:\Tools\Otter" -AddToUserPath
```

To overwrite an existing installation at that path, add the `-Force` flag:

```powershell
.\Install-Otter.ps1 -Destination "C:\Tools\Otter" -AddToUserPath -Force
```

---

### Portable / Zero-Install Usage

Otter requires no separate runtime installation beyond the Windows PowerShell 5.1 engine already included with Windows. If you cannot modify your user environment or prefer portable operation from a USB drive:

1. Extract the release ZIP to any directory of your choice.
2. Run Otter directly using the full path to `otter.cmd`:

```powershell
& "D:\Otter\otter.cmd" --version
& "D:\Otter\otter.cmd" run script.ot
```

No registry changes, environment variables, or background services are created.

---

### Linux and macOS (PowerShell 7)

Otter runs on Linux and macOS with PowerShell 7 (`pwsh`). The release ZIP is
the same one Windows uses: it carries an `otter` command for Linux and macOS
next to `otter.cmd` for Windows.

1. Install PowerShell 7: <https://aka.ms/install-powershell>.
2. Extract the release ZIP and open a terminal in the extracted folder.
3. Run the installer with `pwsh`:

```sh
pwsh -NoProfile -File ./Install-Otter.ps1 -AddToUserPath
```

The installer copies Otter to `~/.local/share/otter/1.0.0-rc.12/` (or under
`$XDG_DATA_HOME` when that is set) and, with `-AddToUserPath`, writes a small
`otter` command to `~/.local/bin`. If `~/.local/bin` is not on your `PATH` yet,
the installer prints the line to add to `~/.zshrc` or `~/.bashrc`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Open a new terminal and check:

```sh
otter --version
```

To run Otter without installing it, call the `otter` command in the extracted
folder directly: `./otter run hello.ot`.

**What works on Linux and macOS:** console programs, files, folders, JSON, CSV,
dates, text, HTTP requests, running commands, modules, projects and tests, and
web applications (`otter web`, `otter serve`).

**What needs Windows:** desktop windows (`otter desktop`), the registry, the
event log, stored credentials, printing, notifications, file dialogs, file
owners and power actions (lock, sign out, restart, shut down). On Linux and
macOS these stop with a clear message, for example:

```text
Otter Runtime Error

Line 1:
    get registry value "Theme" from "HKCU:\Software\MyApp" into theme

The registry is only available on Windows, and this program is running on Linux.
```

The clipboard needs a clipboard program (`pbcopy` on macOS; `xclip`, `xsel` or
`wl-copy` on Linux) and a desktop session. Without one, copying stops with an
error that says so. `run command` runs commands with the system shell, so a
Windows command such as `cmd /c ...` does not exist there.

---

### Developer Setup (From Source)

To run or contribute to Otter directly from the Git repository:

1. Clone the repository:
   ```powershell
   git clone https://github.com/Heavens-Lava/otterPS.git
   cd otterPS
   ```

2. Add the repository root directory to your User `PATH`, or invoke `.\otter.cmd` directly
   (`./otter` on Linux and macOS):
   ```powershell
   .\otter.cmd --version
   ```

3. (Optional) Build a standalone distribution package:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\New-OtterDistribution.ps1
   ```
   This creates a versioned ZIP package and SHA-256 checksum inside the `dist\` directory.

---

## 4. Verifying Your Installation

Confirm your Otter installation with these three quick verification checks:

### Check 1: Version Check

```powershell
otter --version
```
Expected output:
```text
Otter 1.0.0-rc.12
```

### Check 2: Interactive REPL

Start the Otter interactive session:

```powershell
otter
```

Type a calculation and press Enter:
```text
otter> say 2 and 2
4
otter> exit
```

### Check 3: Syntax Validator

Validate an Otter file without running it:

```powershell
otter check hello.ot
```

---

## 5. Running Your First Program

Create a file named `hello.ot` in any text editor:

```otter
name is "Otter Explorer"
say "Hello," name "! Welcome to Otter."
```

Execute the program using `otter run`:

```powershell
otter run hello.ot
```

Or using the canonical shorthand:

```powershell
otter hello.ot
```

Output:
```text
Hello, Otter Explorer ! Welcome to Otter.
```

---

## 6. Command-Line Reference

The `otter` launcher supports the following commands and arguments:

| Command | Description |
|---|---|
| `otter` | Starts the interactive REPL. Type `exit` to leave (`quit` is not a command). |
| `otter <script.ot> [args...]` | Runs an Otter script (shorthand form). The words after the file name are passed to the script's `arguments` list, except the flags Otter itself uses (see below). |
| `otter run <script.ot> [args...]` | Runs an Otter script explicitly. |
| `otter check <script.ot>` | Validates syntax and parses the script without executing it. Returns exit code `0` on success. |
| `otter web <script.ot>` | Compiles an Otter script into a standalone HTML/JS web application and opens it in your default browser. |
| `otter web <script.ot> -NoOpen` | Compiles an Otter script into HTML/JS without launching the browser. |
| `otter --version` or `otter -v` | Displays the Otter version. |
| `otter help` or `otter --help` | Displays the built-in help guide. |

Project commands (`otter new`, `otter test`, `otter build`, `otter publish`)
and `otter serve` for web server programs are described on the documentation
site's Command line and Projects pages.

### Arguments and Otter's own flags

Otter reads its own flags before your program sees its arguments, so these
never reach the `arguments` list: `-Port`, `-NoOpen`, `-Open`, `-ParseOnly`,
`-DebugTokens`, `-DebugAst`, `-DebugErrors`, `-Breakpoints`, `-h`, `-help`,
`--help`, `-v`, `-version` and `--version`. For example,
`otter run tool.ot --help` prints Otter's help instead of running `tool.ot`.
Short flags that could be the start of more than one PowerShell parameter
name, such as `-p`, `-e`, `-i`, `-w`, `-D` and `-Out`, stop with an error that
the parameter name is ambiguous. `--` is not an escape and stops with the same
error. Plain words and double-dash options such as `--name=bob` or
`--port 8080` are passed through unchanged.

### Using the REPL

The REPL runs one line at a time and keeps your variables and functions until
you leave. `reset` clears them, and `exit` leaves.

A line that starts with `if`, `otherwise`, `while`, `repeat`, `count`, `for` or
`to`, or that ends with `are`, starts a block: the prompt changes to `.....`
and keeps collecting lines until you enter a **blank line**, which runs the
whole block. Indent the body as you would in a file, and type `otherwise`
lines before the blank line:

```text
otter> x is 5
otter> if x is 4
.....     say "four"
..... otherwise
.....     say "not four"
.....
not four
```

Other blocks do not continue onto the next line in the REPL: write
`for each ... in` instead of `each ... in`, and put `try` blocks and indented
`has` blocks in a `.ot` file and run it with `otter run`.

---

## 7. Uninstalling Otter

To cleanly uninstall Otter:

### Method 1: Using the Uninstaller (Recommended)

Run `Uninstall-Otter.ps1` from your installation directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "$env:LOCALAPPDATA\Otter\1.0.0-rc.12\Uninstall-Otter.ps1"
```

The uninstaller will:
1. Safely remove all installed Otter files from the directory.
2. Remove the empty parent folder if no other versions exist.
3. Remove the Otter directory from your User `PATH`.

On Linux and macOS, run the uninstaller with `pwsh`. It also removes the
`otter` command from `~/.local/bin` when the installer wrote it:

```sh
pwsh -NoProfile -File ~/.local/share/otter/1.0.0-rc.12/Uninstall-Otter.ps1
```

### Method 2: Manual Removal

If you installed manually:
1. Delete the Otter folder (e.g. `%LOCALAPPDATA%\Otter`).
2. Open Windows Start, search for **Edit environment variables for your account**, select `Path` under **User variables**, and delete the Otter entry.

---

## 8. Troubleshooting & FAQ

### Issue: "Running scripts is disabled on this system"

**Cause**: Windows PowerShell restricts running unsigned scripts by default.

**Solution**: Allow script execution for your current terminal session using the narrowest required scope:
```powershell
Set-ExecutionPolicy -Scope Process Bypass
```
This per-process bypass applies strictly to the current terminal window and automatically expires when closed, avoiding any permanent or persistent system policy changes.

---

### Issue: "'otter' is not recognized as an internal or external command"

**Causes & Solutions**:
1. **Terminal not refreshed**: When environment variables are updated, currently open terminal windows do not inherit the change. Close your command window and open a fresh terminal.
2. **Missing from PATH**: Verify your User PATH includes the installation directory:
   ```powershell
   [Environment]::GetEnvironmentVariable('Path', 'User')
   ```
   If it is missing, reinstall with the `-AddToUserPath` flag, or add it manually.

---

### Issue: Can I run Otter under PowerShell 7 (`pwsh`)?

**Answer**: Yes. When you use the installed `otter` command, the `otter.cmd` launcher is a Windows command script that automatically launches the correct `powershell.exe` runtime. You can invoke `otter run app.ot` directly from PowerShell 7, Command Prompt (`cmd.exe`), Git Bash, or Windows Terminal without any manual switching.

---

## Next Steps

Now that Otter is installed, continue to:
- [A 15-Minute Tour of Otter](TOUR.md) — Learn Otter's syntax, control flow, functions, objects, CSV parsing, and network downloads.
- [Examples](examples/) — Explore complete applications, including CLI tools and interactive web apps.
