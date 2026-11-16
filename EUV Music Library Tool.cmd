@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\EUV-Music-Library.ps1" %*
set "EUV_TOOL_EXIT=%ERRORLEVEL%"
if not "%EUV_TOOL_EXIT%"=="0" (
    echo.
    echo EUV Music Library Tool stopped with an error.
    pause
)
exit /b %EUV_TOOL_EXIT%
