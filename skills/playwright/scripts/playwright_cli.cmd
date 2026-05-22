@echo off
setlocal

if not defined CODEX_HOME set "CODEX_HOME=%USERPROFILE%\.codex"
set "NPX_TOOL=%CODEX_HOME%\toolchains\shims\npx.cmd"
if not exist "%NPX_TOOL%" set "NPX_TOOL=npx"

set "HAS_SESSION="
for %%A in (%*) do (
  if /I "%%~A"=="--session" set "HAS_SESSION=1"
  echo %%~A | findstr /B /C:"--session=" >nul && set "HAS_SESSION=1"
)

if defined PLAYWRIGHT_CLI_SESSION if not defined HAS_SESSION goto with_session
goto without_session

:with_session
call "%NPX_TOOL%" --yes --package @playwright/cli playwright-cli --session "%PLAYWRIGHT_CLI_SESSION%" %*
exit /b %ERRORLEVEL%

:without_session
call "%NPX_TOOL%" --yes --package @playwright/cli playwright-cli %*
exit /b %ERRORLEVEL%
