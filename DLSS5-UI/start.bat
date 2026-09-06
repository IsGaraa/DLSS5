@echo off
cd /d "%~dp0"
if not exist "%~dp0node_modules\electron\dist\electron.exe" call npm install
start "" "%~dp0node_modules\electron\dist\electron.exe" "%~dp0."