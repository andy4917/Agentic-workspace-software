param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" })
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$projectCleanupScript = Join-Path $projectRoot "maintenance\scripts\codex-runtime-process-cleanup.ps1"
$homeCleanupScript = Join-Path $CodexHome "maintenance\scripts\codex-runtime-process-cleanup.ps1"
$cleanupScript = if (Test-Path -LiteralPath $projectCleanupScript) {
    $projectCleanupScript
} else {
    $homeCleanupScript
}

if (-not (Test-Path -LiteralPath $cleanupScript)) {
    Write-Warning "Codex runtime cleanup script not found: $cleanupScript"
    exit 0
}

try {
    & $cleanupScript -Mode ensure-watch -CodexHome $CodexHome
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        Write-Warning "Codex runtime cleanup setup exited with code $LASTEXITCODE"
    }
} catch {
    Write-Warning ("Codex runtime cleanup setup failed: " + $_.Exception.Message)
}

exit 0
