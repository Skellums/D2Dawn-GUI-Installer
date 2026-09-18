@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Download-DestinyBuild.ps1" %*
if errorlevel 1 echo Download did not complete. Read the message above.
pause
