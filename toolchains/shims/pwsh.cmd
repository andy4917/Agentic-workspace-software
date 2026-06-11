@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PWSH_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PWSH_EXE%" (
  "%PWSH_EXE%" %*
  exit /b %ERRORLEVEL%
)
for /f "delims=" %%P in ('dir /b /ad "%ProgramFiles%\WindowsApps\Microsoft.PowerShell_*__8wekyb3d8bbwe" 2^>nul') do (
  if exist "%ProgramFiles%\WindowsApps\%%P\pwsh.exe" (
    "%ProgramFiles%\WindowsApps\%%P\pwsh.exe" %*
    exit /b %ERRORLEVEL%
  )
)
set "PWSH_EXE=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
"%PWSH_EXE%" %*
exit /b %ERRORLEVEL%
