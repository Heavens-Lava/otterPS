@echo off
REM Launcher shim so you can type "otter hello.ot" from any folder,
REM the same way you type "python hello.py".
REM
REM %~dp0 is the folder this .cmd file lives in, so otter.ps1 is
REM always found no matter where you run otter from.
REM %* passes along whatever arguments you typed.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0otter.ps1" %*
exit /b %ERRORLEVEL%
