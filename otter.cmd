@echo off
REM Launcher shim so you can type "otter hello.ot" from any folder,
REM the same way you type "python hello.py".
REM
REM %~dp0 is the folder this .cmd file lives in, so otter.ps1 is
REM always found no matter where you run otter from.
REM %* passes along whatever arguments you typed.
REM
REM otter.exe (tools/Build-OtterLauncher.ps1), when present, runs programs
REM that were already compiled without starting PowerShell, and hands
REM everything else to otter.ps1 exactly as the line below does.
if not exist "%~dp0otter.exe" goto powershell
"%~dp0otter.exe" %*
exit /b %ERRORLEVEL%
:powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0otter.ps1" %*
exit /b %ERRORLEVEL%
