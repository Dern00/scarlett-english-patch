@echo off
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore.ps1" %*
set "scarlett_patch_exit=%ERRORLEVEL%"
echo.
pause
exit /b %scarlett_patch_exit%
