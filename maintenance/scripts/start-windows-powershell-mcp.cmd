@echo off
setlocal

set "CODEX_SHIMS=%USERPROFILE%\.codex\toolchains\shims"
set "CODEX_BIN=%LOCALAPPDATA%\OpenAI\Codex\bin"
set "PWSH_MCP_PROXY="

for /f "usebackq delims=" %%P in (`powershell.exe -NoProfile -Command "$m = Get-Module -ListAvailable PowerShell.MCP | Sort-Object Version -Descending | Select-Object -First 1; if ($m) { Join-Path $m.ModuleBase 'bin\win-x64\PowerShell.MCP.Proxy.exe' }"`) do (
  set "PWSH_MCP_PROXY=%%P"
)

if not exist "%PWSH_MCP_PROXY%" (
  echo PowerShell.MCP.Proxy.exe not found. Install or update the PowerShell.MCP module. 1>&2
  exit /b 1
)

set "PATH=%CODEX_SHIMS%;%CODEX_BIN%;%PATH%"

"%PWSH_MCP_PROXY%" %*
