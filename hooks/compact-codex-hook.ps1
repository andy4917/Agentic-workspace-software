param()

$ErrorActionPreference = "Stop"

function Get-CodexHome {
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return (Join-Path $env:USERPROFILE ".codex")
}

function Read-HookPayload {
    param([string]$Raw)
    $raw = $Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ hook_event_name = "unknown"; _raw = "" }
    }
    try {
        return ($raw | ConvertFrom-Json -Depth 32)
    } catch {
        return [pscustomobject]@{ hook_event_name = "unknown"; _raw = $raw }
    }
}

function Ensure-RuntimeCleanupWatch {
    param([string]$CodexHome)

    $cleanupScript = Join-Path $CodexHome "maintenance\scripts\codex-runtime-process-cleanup.ps1"
    if (-not (Test-Path -LiteralPath $cleanupScript -PathType Leaf)) {
        return [ordered]@{
            attempted = $false
            status = "missing_cleanup_script"
            script = $cleanupScript
        }
    }

    $output = & $cleanupScript -Mode ensure-watch -CodexHome $CodexHome -StopAppServerOnOwnerExit -StopAppServerOnOwnerNoVisibleWindow 2>&1
    $text = (($output | Out-String) -replace "\s+", " ").Trim()
    return [ordered]@{
        attempted = $true
        status = "ok"
        script = $cleanupScript
        output = $text
    }
}

$stdinRaw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($stdinRaw) -and $MyInvocation.ExpectingInput) {
    $stdinRaw = ($input | Out-String)
}

$payload = Read-HookPayload -Raw $stdinRaw
$event = if ($payload.hook_event_name) { [string]$payload.hook_event_name } elseif ($payload.hookEventName) { [string]$payload.hookEventName } else { "unknown" }
$tool = if ($payload.tool_name) { [string]$payload.tool_name } else { $null }
$codexHome = Get-CodexHome
$stateDir = Join-Path $codexHome "state"
$ledger = Join-Path $stateDir "hook-ledger.jsonl"

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$runtimeCleanupWatch = $null
if ($event -eq "SessionStart" -or $event -eq "UserPromptSubmit") {
    try {
        $runtimeCleanupWatch = Ensure-RuntimeCleanupWatch -CodexHome $codexHome
    } catch {
        $runtimeCleanupWatch = [ordered]@{
            attempted = $true
            status = "error"
            error = $_.Exception.Message
        }
    }
}

$record = [ordered]@{
    ts = (Get-Date).ToUniversalTime().ToString("o")
    runner = "compact-codex-hook"
    version = 2
    event = $event
    tool = $tool
    cwd = if ($payload.cwd) { [string]$payload.cwd } else { $null }
    action = "continue"
    runtime_cleanup_watch = $runtimeCleanupWatch
}
($record | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $ledger -Encoding UTF8

$out = [ordered]@{}

if ($event -eq "PreToolUse") {
    $out["hookSpecificOutput"] = [ordered]@{
        hookEventName = "PreToolUse"
        permissionDecision = "allow"
        permissionDecisionReason = "compact scaffold hook records evidence only"
    }
} elseif ($event -eq "SessionStart") {
    $out["hookSpecificOutput"] = [ordered]@{
        hookEventName = "SessionStart"
        additionalContext = "Minimal scaffold active: use current evidence, keep runtime cleanup watcher active, avoid stale runtime state, and verify before completion."
    }
}

if ($out.Count -gt 0) {
    $out | ConvertTo-Json -Compress -Depth 8
}
