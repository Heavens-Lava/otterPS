# Otter 1.0 RC for Windows

## Requirements

- Windows with **Windows PowerShell 5.1** (`powershell.exe`). It is included
  with supported Windows 10 and Windows 11 installations.
- No administrator rights are required for a per-user installation.

## Install

Extract the ZIP, open Windows PowerShell in the extracted folder, then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Install-Otter.ps1 -AddToUserPath
```

Open a new terminal and verify:

```powershell
otter --version
```

Or run without changing PATH:

```powershell
& "$env:LOCALAPPDATA\Otter\1.0.0-rc.1\otter.cmd" --version
```

## First program

Create `hello.ot`:

```otter
say "Hello from Otter"
```

Run it:

```powershell
otter run hello.ot
```

## RC scope

The console interpreter is the portable Otter 1.0 core. The `web` command is
a separately certified compiler target. HTTP statements are web-only; `use`
modules are deferred and produce a clear runtime diagnostic. Desktop/server
hosting, installers beyond this per-user script, and package management are
not part of this RC.
