@echo off
set "CODEX_TOOL=%LOCALAPPDATA%\OpenAI\Codex\bin\codex.exe"
if not exist "%CODEX_TOOL%" (
  echo Codex bundled codex.exe not found. Restart or update Codex Desktop. 1>&2
  exit /b 1
)
"%CODEX_TOOL%" %*
