# Otter's Windows installer (MSI) and winget

Status (2026-10-15): **built and tested, not published.** Publishing the MSI
and submitting the winget manifest wait for Jeff's approval; code signing is
the distribution milestone before broad publication. The release ZIP with
`Install-Otter.ps1` stays the verified way to install Otter.

## What it is

`distribution/msi/Otter.wxs`, built by `tools/New-OtterMsi.ps1` (WiX 5.0.2)
from a release ZIP:

- exactly the release ZIP's files - no executable of its own (42 files:
  `.ps1`, `.psm1`, `.cmd`, `.md`, `.ot`, `.json`, one `.cs` source);
- installed for the current user only, no administrator rights, into
  `%LOCALAPPDATA%\Programs\Otter`;
- that folder added to the user's PATH, so `otter` (`otter.cmd`) works in any
  new terminal;
- an entry in Settings > Apps; uninstalling removes the files, the folders,
  the PATH entry and `HKCU\Software\Otter`;
- a fixed UpgradeCode, so each newer MSI replaces the older one.

Windows Installer validation (`wix msi validate`): 0 errors; 42 ICE91
warnings, one per file - per-user files are not copied into other users'
profiles on a per-machine install, which does not apply to this per-user-only
package.

## Tested on a clean Windows

`tools/Test-OtterMsi.ps1`, run by `.github/workflows/msi-test.yml` on a fresh
GitHub Actions Windows runner (run 38843293605, 2026-10-15): **26 of 26
checks passed.**

1. Install 1.0.0: files, PATH, `otter --version` in a new shell, one Apps entry.
2. Upgrade to 1.0.1: replaced, still one Apps entry and one PATH entry.
3. The installed `otter` and the certified release ZIP's `otter` give the
   same output and exit code on the same programs (exit codes 0, 2 and 3),
   and on `check` and `help`.
4. Uninstall: everything removed; a new shell no longer finds `otter`.

The workflow keeps only msiexec logs - artifacts of a public repository can
be downloaded by anyone signed in, so the MSIs are not uploaded.

## winget

`tools/New-OtterWingetManifest.ps1` writes the manifest for one exact MSI:
`JeffreyMacy.Otter`, moniker `otter` (free in the winget repository on
2026-10-15; "Otter Browser" does not claim it), per-user scope, command
`otter`, ProductCode and SHA-256 read from the MSI. `winget validate`:
succeeded. MSI builds are not byte-identical between runs, so the manifest
must be generated from the very MSI attached to the GitHub release.

To publish, after approval: build the MSI from the release ZIP, attach it to
the release, generate the manifest from that file, and propose it to
`microsoft/winget-pkgs`. Microsoft's pipeline validates and scans it, and a
reviewer merges it (typically days).

## Antivirus findings (2026-10-15)

Symantec Endpoint Protection on Jeff's machine quarantined two new unsigned
executables as `Heur.AdvML.D` (a machine-learning heuristic, not a known
threat):

1. otter-net's first Native AOT `otter.exe`;
2. a launcher `otter.exe` for a winget ZIP package (the Store package's
   `OtterLauncher.cs`, compiled loose; it starts `powershell
   -ExecutionPolicy Bypass`).

Response: no further `.exe` launchers are built; the winget ZIP approach was
dropped for this MSI, which contains none; otter-net builds without an app
host and runs as `dotnet otter.dll` locally. Nothing was excluded or worked
around in the security software. The MSI was not installed on Jeff's machine;
it was tested on the disposable runner. An MSI is still an installation
package that antivirus products can inspect, so it may still draw warnings
until it is signed.

The Store package (same launcher inside) is signed by Microsoft and installed
and ran normally.

## Code signing - the milestone before broad distribution

What needs signing: the MSI; later otter-net's native `otter`, the 1.1
fast-start launcher, and optionally the PowerShell scripts (Authenticode).
One certificate covers them all - it names the publisher, not a product - and
reputation with SmartScreen and antivirus builds up per certificate.

Options (to confirm current prices and terms before buying):

- **Azure Trusted Signing** - a Microsoft service, roughly US$10 a month,
  signing from GitHub Actions; open to individual developers after identity
  validation (initially US and Canada).
- **A traditional OV certificate** from a certificate authority (Sectigo,
  DigiCert, SSL.com ...), roughly US$100-400 a year; since 2023 the key must
  be in hardware (a USB token, or the authority's cloud signing service).
- **Free signing for open source** (SignPath Foundation; Certum's cheap
  open-source certificate) requires an OSI-approved open-source license.
  Otter's license, the Otter Free Use License 1.1, is source-available, not
  open source, so it does not qualify unless the license changes - a decision
  for Jeff, not a cost question.
