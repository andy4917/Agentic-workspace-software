@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "CODEX_BIN=%LOCALAPPDATA%\OpenAI\Codex\bin"

call :resolve_tool node_repl
if errorlevel 1 exit /b 1
set "NODE_REPL_EXE=%RESOLVED_TOOL%"

call :resolve_tool node
if errorlevel 1 exit /b 1
set "RESOLVED_NODE_EXE=%RESOLVED_TOOL%"

call :resolve_tool codex
if errorlevel 1 exit /b 1
set "RESOLVED_CODEX_EXE=%RESOLVED_TOOL%"

if not defined CODEX_HOME set "CODEX_HOME=%USERPROFILE%\.codex"
if not defined NODE_REPL_NODE_PATH set "NODE_REPL_NODE_PATH=%RESOLVED_NODE_EXE%"
if not defined CODEX_CLI_PATH set "CODEX_CLI_PATH=%RESOLVED_CODEX_EXE%"
if not defined NODE_REPL_TRUSTED_CODE_PATHS set "NODE_REPL_TRUSTED_CODE_PATHS=%CODEX_HOME%"

"%NODE_REPL_EXE%" %*
exit /b %ERRORLEVEL%

:resolve_tool
set "TOOL_NAME=%~1"
set "RESOLVED_TOOL=%CODEX_BIN%\%TOOL_NAME%.exe"
if exist "%RESOLVED_TOOL%" exit /b 0
for /f "delims=" %%D in ('dir /b /a:d /o:-d "%CODEX_BIN%" 2^>nul') do (
  if exist "%CODEX_BIN%\%%D\%TOOL_NAME%.exe" (
    set "RESOLVED_TOOL=%CODEX_BIN%\%%D\%TOOL_NAME%.exe"
    exit /b 0
  )
)
echo Codex bundled %TOOL_NAME%.exe not found. Restart or update Codex Desktop. 1>&2
exit /b 1
