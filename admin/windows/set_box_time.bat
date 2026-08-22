@echo off
rem set_box_time.bat - force la mise a l'heure de la box via adb (double-clic possible)
rem Tous les arguments sont passes au script PowerShell jumeau :
rem   set_box_time.bat [-Target 192.168.50.20:5555]
setlocal
set "SCRIPT_DIR=%~dp0"

where adb >nul 2>nul || set "PATH=%PATH%;%LOCALAPPDATA%\Android\Sdk\platform-tools"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%set_box_time.ps1" %*
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%
