@echo off
setlocal
set "CODEX_TOOL="
for /f "usebackq delims=" %%I in (`powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$pkg = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1; if ($pkg) { $candidate = Join-Path $pkg.InstallLocation 'app\resources\codex.exe'; if (Test-Path -LiteralPath $candidate) { [Console]::WriteLine($candidate) } }" 2^>nul`) do set "CODEX_TOOL=%%I"
if defined CODEX_TOOL goto run_codex
if not defined CODEX_TOOL set "CODEX_TOOL=%LOCALAPPDATA%\OpenAI\Codex\bin\codex.exe"
if exist "%CODEX_TOOL%" goto run_codex
if exist "%USERPROFILE%\scoop\apps\codex\current\codex.exe" set "CODEX_TOOL=%USERPROFILE%\scoop\apps\codex\current\codex.exe"
if not exist "%CODEX_TOOL%" (
  echo Codex bundled codex.exe not found. Restart or update Codex Desktop. 1>&2
  exit /b 1
)
:run_codex
"%CODEX_TOOL%" %*
exit /b %ERRORLEVEL%
