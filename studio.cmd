@echo off
setlocal
REM studio.cmd - Launches Otter Studio in native desktop app mode backed by authenticated terminal bridge
powershell -NoProfile -ExecutionPolicy Bypass -Command "Import-Module '%~dp0src\Otter.Desktop.psm1' -Force; Start-OtterStudio"
endlocal
