@echo off
setlocal
set "CODEX_BIN=%LOCALAPPDATA%\OpenAI\Codex\bin"
set "CODEX_TOOL=%CODEX_BIN%\rg.exe"
if exist "%CODEX_TOOL%" goto run
for /f "delims=" %%D in ('dir /b /a:d /o:-d "%CODEX_BIN%" 2^>nul') do (
  if exist "%CODEX_BIN%\%%D\rg.exe" (
    set "CODEX_TOOL=%CODEX_BIN%\%%D\rg.exe"
    goto run
  )
)
if not exist "%CODEX_TOOL%" (
  echo Codex bundled rg.exe not found. Restart or update Codex Desktop. 1>&2
  exit /b 1
)
:run
set "CODEX_ARGS=%*"
set "CODEX_ARGS=%CODEX_ARGS:^=^^%"
set "CODEX_ARGS=%CODEX_ARGS:&=^&%"
set "CODEX_ARGS=%CODEX_ARGS:|=^|%"
set "CODEX_ARGS=%CODEX_ARGS:<=^<%"
set "CODEX_ARGS=%CODEX_ARGS:>=^>%"
"%CODEX_TOOL%" %CODEX_ARGS%
exit /b %ERRORLEVEL%
