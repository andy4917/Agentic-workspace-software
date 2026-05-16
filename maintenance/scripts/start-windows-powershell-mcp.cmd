@echo off
setlocal

set "CODEX_SHIMS=C:\Users\anise\.codex\toolchains\shims"
set "CODEX_BIN=C:\Users\anise\AppData\Local\OpenAI\Codex\bin"
set "PWSH_MCP_PROXY=C:\Users\anise\Documents\PowerShell\Modules\PowerShell.MCP\1.8.0\bin\win-x64\PowerShell.MCP.Proxy.exe"

set "PATH=%CODEX_SHIMS%;%CODEX_BIN%;%PATH%"

"%PWSH_MCP_PROXY%" %*
