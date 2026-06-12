@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "NO_MISTAKES_PS1=%~dp0no-mistakes.ps1"
if not exist "%NO_MISTAKES_PS1%" (
  echo no-mistakes.ps1 not found next to %~nx0. 1>&2
  exit /b 1
)

set "WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%WINDOWS_POWERSHELL%" (
  echo Windows PowerShell not found at %WINDOWS_POWERSHELL%. 1>&2
  exit /b 1
)

"%WINDOWS_POWERSHELL%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%NO_MISTAKES_PS1%" %*
exit /b %ERRORLEVEL%
