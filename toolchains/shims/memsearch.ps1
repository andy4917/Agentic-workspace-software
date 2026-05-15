param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mementoCheck = Join-Path $root "maintenance\scripts\memento-mcp-runtime.ps1"

Write-Output @"
memsearch is retired legacy Memory/RAG surface and is not an active fallback.
Use the configured Memento MCP server instead. For runtime evidence run:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$mementoCheck" verify
"@
exit 2
