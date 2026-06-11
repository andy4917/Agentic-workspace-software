$ErrorActionPreference = "Stop"

$env:NO_MISTAKES_TELEMETRY = "0"
$env:NO_MISTAKES_NO_UPDATE_CHECK = "1"

$NO_MISTAKES_EXE = Join-Path $env:LOCALAPPDATA "no-mistakes\no-mistakes.exe"
$CODEX_SHIM_DIR = Split-Path -Parent $PSCommandPath
$NM_ORIGINAL_PATH = [string]$env:PATH
$retainedPathEntries = New-Object System.Collections.Generic.List[string]
$normalizedShimDir = ($CODEX_SHIM_DIR -replace "/", "\").TrimEnd("\")

foreach ($entry in ($NM_ORIGINAL_PATH -split ";")) {
    if ([string]::IsNullOrWhiteSpace($entry)) {
        continue
    }
    $NM_PATH_ENTRY_ORIGINAL = $entry
    $NM_PATH_ENTRY_NORMALIZED = ($NM_PATH_ENTRY_ORIGINAL -replace "/", "\").TrimEnd("\")
    if ($NM_PATH_ENTRY_NORMALIZED -ieq $normalizedShimDir) {
        continue
    }
    $retainedPathEntries.Add($NM_PATH_ENTRY_ORIGINAL) | Out-Null
}

$env:PATH = ($retainedPathEntries.ToArray() -join ";")

if (-not (Test-Path -LiteralPath $NO_MISTAKES_EXE -PathType Leaf)) {
    Write-Error "no-mistakes.exe not found at $NO_MISTAKES_EXE. Install the official kunchenguid/no-mistakes release first."
    exit 1
}

& $NO_MISTAKES_EXE @args
exit $LASTEXITCODE
