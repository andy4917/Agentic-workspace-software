@echo off
setlocal
set "CODEX_TOOL=%LOCALAPPDATA%\OpenAI\Codex\bin\rg.exe"
if not exist "%CODEX_TOOL%" (
  echo Codex bundled rg.exe not found. Restart or update Codex Desktop. 1>&2
  exit /b 1
)
set "CODEX_ARGS=%*"
set "CODEX_ARGS=%CODEX_ARGS:^=^^%"
set "CODEX_ARGS=%CODEX_ARGS:&=^&%"
set "CODEX_ARGS=%CODEX_ARGS:|=^|%"
set "CODEX_ARGS=%CODEX_ARGS:<=^<%"
set "CODEX_ARGS=%CODEX_ARGS:>=^>%"
"%CODEX_TOOL%" %CODEX_ARGS%
exit /b %ERRORLEVEL%
