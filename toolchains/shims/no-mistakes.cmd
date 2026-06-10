@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "NO_MISTAKES_TELEMETRY=0"
set "NO_MISTAKES_NO_UPDATE_CHECK=1"
set "NO_MISTAKES_EXE=%LOCALAPPDATA%\no-mistakes\no-mistakes.exe"
set "CODEX_SHIM_DIR=%~dp0"
if "%CODEX_SHIM_DIR:~-1%"=="\" set "CODEX_SHIM_DIR=%CODEX_SHIM_DIR:~0,-1%"
set "NM_ORIGINAL_PATH=%PATH%"
set "PATH="
for %%P in ("%NM_ORIGINAL_PATH:;=" "%") do (
  call :AppendPathEntry "%%~P"
)
goto :RunNoMistakes

:AppendPathEntry
set "NM_PATH_ENTRY_ORIGINAL=%~1"
if not defined NM_PATH_ENTRY_ORIGINAL exit /b 0
set "NM_PATH_ENTRY_NORMALIZED=%NM_PATH_ENTRY_ORIGINAL:/=\%"
if "%NM_PATH_ENTRY_NORMALIZED:~-1%"=="\" set "NM_PATH_ENTRY_NORMALIZED=%NM_PATH_ENTRY_NORMALIZED:~0,-1%"
if /I "%NM_PATH_ENTRY_NORMALIZED%"=="%CODEX_SHIM_DIR%" exit /b 0
if defined PATH (set "PATH=%PATH%;%NM_PATH_ENTRY_ORIGINAL%") else set "PATH=%NM_PATH_ENTRY_ORIGINAL%"
exit /b 0

:RunNoMistakes
if not exist "%NO_MISTAKES_EXE%" (
  echo no-mistakes.exe not found at %NO_MISTAKES_EXE%. Install the official kunchenguid/no-mistakes release first. 1>&2
  exit /b 1
)
"%NO_MISTAKES_EXE%" %*
exit /b %ERRORLEVEL%
