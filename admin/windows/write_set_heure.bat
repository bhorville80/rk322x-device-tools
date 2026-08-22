@echo off
rem write_set_heure.bat - depose SET_HEURE (heure UTC du PC) sur la cle USB
rem (double-clic possible ; la cle est auto-detectee)
setlocal
set "SCRIPT_DIR=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%write_set_heure.ps1" %*
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%
