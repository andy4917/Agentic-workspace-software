@echo off
setlocal
set "CODEX_BIN=%LOCALAPPDATA%\OpenAI\Codex\bin"
set "CODEX_TOOL=%CODEX_BIN%\codex.exe"
if exist "%CODEX_TOOL%" goto run
for /f "delims=" %%D in ('dir /b /a:d /o:-d "%CODEX_BIN%" 2^>nul') do (
  if exist "%CODEX_BIN%\%%D\codex.exe" (
    set "CODEX_TOOL=%CODEX_BIN%\%%D\codex.exe"
    goto run
  )
)
if not exist "%CODEX_TOOL%" (
  echo Codex bundled codex.exe not found. Restart or update Codex Desktop. 1>&2
  exit /b 1
)
:run
"%CODEX_TOOL%" %*
exit /b %ERRORLEVEL%
