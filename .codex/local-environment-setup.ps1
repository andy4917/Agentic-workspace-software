param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" })
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$projectMaintenanceScripts = Join-Path $projectRoot "maintenance\scripts"
$homeMaintenanceScripts = Join-Path $CodexHome "maintenance\scripts"
$projectCleanupScript = Join-Path $projectRoot "maintenance\scripts\codex-runtime-process-cleanup.ps1"
$homeCleanupScript = Join-Path $CodexHome "maintenance\scripts\codex-runtime-process-cleanup.ps1"
$cleanupScript = if (Test-Path -LiteralPath $projectCleanupScript) {
    $projectCleanupScript
} else {
    $homeCleanupScript
}

function Resolve-MaintenanceScript {
    param([Parameter(Mandatory = $true)][string]$Name)

    $projectScript = Join-Path $projectMaintenanceScripts $Name
    if (Test-Path -LiteralPath $projectScript -PathType Leaf) {
        return $projectScript
    }
    return (Join-Path $homeMaintenanceScripts $Name)
}

function Invoke-RepairIfNeeded {
    param([Parameter(Mandatory = $true)][string]$ScriptPath)

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Required setup script not found: $ScriptPath"
    }

    $global:LASTEXITCODE = 0
    & $ScriptPath -Mode status -CodexHome $CodexHome | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $global:LASTEXITCODE = 0
        & $ScriptPath -Mode repair -CodexHome $CodexHome | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Repair failed: $ScriptPath"
        }
    }
}

if (-not (Test-Path -LiteralPath $cleanupScript)) {
    Write-Warning "Codex runtime cleanup script not found: $cleanupScript"
    exit 1
}

try {
    Invoke-RepairIfNeeded -ScriptPath (Resolve-MaintenanceScript -Name "ensure-openai-bundled-marketplace.ps1")
    Invoke-RepairIfNeeded -ScriptPath (Resolve-MaintenanceScript -Name "repair-chrome-plugin-runtime.ps1")
    & $cleanupScript -Mode ensure-watch -CodexHome $CodexHome -StopAppServerOnOwnerExit
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "Codex runtime cleanup setup exited with code $LASTEXITCODE"
    }
} catch {
    Write-Warning ("Codex runtime cleanup setup failed: " + $_.Exception.Message)
    exit 1
}

exit 0
