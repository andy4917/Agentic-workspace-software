@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "NO_MISTAKES_TELEMETRY=0"
set "NO_MISTAKES_NO_UPDATE_CHECK=1"
set "NO_MISTAKES_EXE=%LOCALAPPDATA%\no-mistakes\no-mistakes.exe"
set "CODEX_SHIM_DIR=%USERPROFILE%\.codex\toolchains\shims"
set "NM_ORIGINAL_PATH=%PATH%"
set "PATH="
for %%P in ("%NM_ORIGINAL_PATH:;=" "%") do (
  set "NM_PATH_ENTRY=%%~P"
  set "NM_PATH_ENTRY=!NM_PATH_ENTRY:/=\!"
  if "!NM_PATH_ENTRY:~-1!"=="\" set "NM_PATH_ENTRY=!NM_PATH_ENTRY:~0,-1!"
  if defined NM_PATH_ENTRY if /I not "!NM_PATH_ENTRY!"=="%CODEX_SHIM_DIR%" (
    if defined PATH (set "PATH=!PATH!;!NM_PATH_ENTRY!") else set "PATH=!NM_PATH_ENTRY!"
  )
)
if not exist "%NO_MISTAKES_EXE%" (
  echo no-mistakes.exe not found at %NO_MISTAKES_EXE%. Install the official kunchenguid/no-mistakes release first. 1>&2
  exit /b 1
)
setlocal DisableDelayedExpansion
"%NO_MISTAKES_EXE%" %*
exit /b %ERRORLEVEL%
