param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$mementoCheck = Join-Path $resolvedRoot "maintenance\scripts\memento-mcp-runtime.ps1"

Write-Output "status=legacy; active=false"
Write-Output "detail=memory_rag=retired"
Write-Output "detail=memsearch=not_active_fallback"
Write-Output "detail=raw_memories=historical_data_not_runtime_authority"
Write-Output ("detail=use=" + $mementoCheck + " verify")
exit 2
