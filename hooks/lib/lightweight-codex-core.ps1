# Shared core helpers for lightweight-codex-hook.ps1.
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$hookRoot = if (-not [string]::IsNullOrWhiteSpace($script:HookScriptRoot)) {
    $script:HookScriptRoot
} elseif ((Split-Path -Leaf $PSScriptRoot) -eq "lib") {
    Split-Path -Parent $PSScriptRoot
} else {
    $PSScriptRoot
}
$stateDir = Join-Path $hookRoot "state"
$statePath = Join-Path $stateDir "lightweight-status.json"
$policyPath = Join-Path $hookRoot "lightweight-codex-policy.json"

function Get-UserProfilePath {
    return [Environment]::GetFolderPath("UserProfile")
}

function Get-CodexHomePath {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }
    return (Join-Path (Get-UserProfilePath) ".codex")
}

function Get-AgentsHomePath {
    if (-not [string]::IsNullOrWhiteSpace($env:AGENTS_HOME)) {
        return $env:AGENTS_HOME
    }
    return (Join-Path (Get-UserProfilePath) ".agents")
}

function Write-HookJson {
    param([hashtable]$Object)
    $Object | ConvertTo-Json -Depth 12 -Compress
}

function Read-HookInput {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ hook_event_name = "Unknown" }
    }
    return $raw | ConvertFrom-Json
}

function Get-PromptText {
    param($InputObject)

    $promptValue = $null
    if ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains "prompt") {
        $promptValue = $InputObject.prompt
    } elseif ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains "user_prompt") {
        $promptValue = $InputObject.user_prompt
    } elseif ($null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains "message") {
        $promptValue = $InputObject.message
    }

    if ($null -eq $promptValue) {
        return ""
    }
    if ($promptValue -is [string]) {
        return $promptValue
    }
    if ($promptValue -is [array]) {
        $parts = @()
        foreach ($item in $promptValue) {
            if ($null -eq $item) {
                continue
            }
            if ($item -is [string]) {
                $parts += $item
            } elseif ($item.PSObject.Properties.Name -contains "text") {
                $parts += [string]$item.text
            } else {
                $parts += ($item | ConvertTo-Json -Depth 8 -Compress)
            }
        }
        return ($parts -join "`n")
    }
    if ($promptValue.PSObject.Properties.Name -contains "text") {
        return [string]$promptValue.text
    }

    return ($promptValue | ConvertTo-Json -Depth 8 -Compress)
}

function Get-PromptSummary {
    param([string]$Prompt)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Prompt)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $digestBytes = $sha.ComputeHash($bytes)
    $digest = ([System.BitConverter]::ToString($digestBytes)).Replace("-", "").ToLowerInvariant()
    $hasNonAscii = $false
    foreach ($ch in $Prompt.ToCharArray()) {
        if ([int][char]$ch -gt 127) {
            $hasNonAscii = $true
            break
        }
    }
    return "prompt_length=$($Prompt.Length); prompt_sha256=$digest; contains_non_ascii=$hasNonAscii"
}

function Test-PromptSecretLeak {
    param([string]$Prompt)

    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        return $false
    }

    $patterns = @(
        "sk-[A-Za-z0-9_-]{20,}",
        "github_pat_[A-Za-z0-9_]{20,}",
        "gh[pousr]_[A-Za-z0-9_]{20,}",
        "xox[baprs]-[A-Za-z0-9-]{20,}",
        "AKIA[0-9A-Z]{16}",
        "(?i)\b(api[_-]?key|secret|password|token|credential)\b\s*[:=]\s*['""]?[A-Za-z0-9_./+=:-]{12,}"
    )

    foreach ($pattern in $patterns) {
        if ($Prompt -match $pattern) {
            return $true
        }
    }

    return $false
}

function Read-Policy {
    $defaultPolicy = @'
{
  "profile": "anti_reward_pm_workflow_v1",
  "subagents": {
    "max_parallel": 8,
    "max_depth": 1,
    "default_spawn_policy": "conditional"
  },
  "work_size": {
    "large_files": 4,
    "large_changed_lines": 150,
    "multi_surface_threshold": 3
  },
  "hooks": {
    "missing_final_evidence": "not_ready",
    "required_validation_missing": "not_ready",
    "fake_success_insertion": "hard_block",
    "safe_git_status_diff_add_commit": "allow"
  }
}
'@

    try {
        if (Test-Path -LiteralPath $policyPath) {
            return Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
        }
        return $defaultPolicy | ConvertFrom-Json
    } catch {
        return $defaultPolicy | ConvertFrom-Json
    }
}

function Get-ToolText {
    param($InputObject)

    if ($null -eq $InputObject.tool_input) {
        return ""
    }

    $toolInput = $InputObject.tool_input
    if ($toolInput.PSObject.Properties.Name -contains "command") {
        return [string]$toolInput.command
    }

    return ($toolInput | ConvertTo-Json -Depth 16 -Compress)
}

function Get-StateDigest {
    param([string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $digestBytes = $sha.ComputeHash($bytes)
    return ([System.BitConverter]::ToString($digestBytes)).Replace("-", "").ToLowerInvariant()
}

function Get-StateSummaryText {
    param(
        [string]$Value,
        [int]$Limit = 240
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $singleLine = ($Value -replace "\s+", " ").Trim()
    if ($singleLine.Length -le $Limit) {
        return $singleLine
    }

    $digest = Get-StateDigest -Text $Value
    return ($singleLine.Substring(0, $Limit) + " ... sha256:" + $digest)
}

function Get-ToolEvidenceSummary {
    param(
        [string]$ToolName,
        [string]$Text
    )

    $signals = @()
    if ($Text -match "(?i)(pytest|cargo test|npm test|pnpm test|yarn test|typecheck|lint|build|py_compile|doctor|audit|eval)") {
        $signals += "validation"
    }
    if ($Text -match "(?i)(apply_patch|Edit|Write|\*\*\* (Add|Update|Delete) File:)") {
        $signals += "file_edit"
    }
    if ($signals.Count -eq 0) {
        $signals += "tool_use"
    }

    $digest = Get-StateDigest -Text $Text
    return "${ToolName}:$($signals -join ','); sha256:$digest"
}

function Read-State {
    if (-not (Test-Path -LiteralPath $statePath)) {
        return [ordered]@{
            currentGoal = ""
            workflow = ""
            taskClass = ""
            classificationReason = ""
            delegationAuthorized = $false
            goalRequired = $false
            watcherExpected = $false
            anomalyPauseExpected = $false
            subagentDecisionRequired = $false
            intentFrame = [ordered]@{}
            toolchainHint = ""
            memoryRoute = ""
            changedSurfaces = @()
            checksRun = @()
            requiredReminders = @()
            toolEvents = @()
            subagentEvents = @()
            userAuthorizations = @()
            lastUpdated = ""
        }
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        return [ordered]@{
            currentGoal = [string]$state.currentGoal
            workflow = [string]$state.workflow
            taskClass = [string]$state.taskClass
            classificationReason = [string]$state.classificationReason
            delegationAuthorized = [bool]$state.delegationAuthorized
            goalRequired = [bool]$state.goalRequired
            watcherExpected = [bool]$state.watcherExpected
            anomalyPauseExpected = [bool]$state.anomalyPauseExpected
            subagentDecisionRequired = [bool]$state.subagentDecisionRequired
            intentFrame = $state.intentFrame
            toolchainHint = [string]$state.toolchainHint
            memoryRoute = [string]$state.memoryRoute
            changedSurfaces = @($state.changedSurfaces | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 120 })
            checksRun = @($state.checksRun | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 240 })
            requiredReminders = @($state.requiredReminders | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 240 })
            toolEvents = @($state.toolEvents | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 120 })
            subagentEvents = @($state.subagentEvents | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 180 })
            userAuthorizations = @($state.userAuthorizations | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 120 })
            lastUpdated = [string]$state.lastUpdated
        }
    } catch {
        return [ordered]@{
            currentGoal = ""
            workflow = ""
            taskClass = ""
            classificationReason = ""
            delegationAuthorized = $false
            goalRequired = $false
            watcherExpected = $false
            anomalyPauseExpected = $false
            subagentDecisionRequired = $false
            intentFrame = [ordered]@{}
            toolchainHint = ""
            memoryRoute = ""
            changedSurfaces = @()
            checksRun = @()
            requiredReminders = @("Hook state could not be parsed; refresh evidence before finalizing.")
            toolEvents = @()
            subagentEvents = @()
            userAuthorizations = @()
            lastUpdated = ""
        }
    }
}

function Save-State {
    param($State)

    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    $State.lastUpdated = (Get-Date).ToString("o")
    $json = ($State | ConvertTo-Json -Depth 16) + "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($statePath, $json, $utf8NoBom)
}

function Add-Unique {
    param(
        [object[]]$Items,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @($Items)
    }
    if ($Items -contains $Value) {
        return @($Items)
    }
    return @($Items + $Value)
}

function Write-CodexStructuredLog {
    param(
        [string]$EventName,
        [string]$Outcome = "observed",
        [string]$Reason = "",
        [string]$ToolName = "",
        [string[]]$ChangedSurface = @(),
        [string[]]$ValidationResult = @(),
        [string[]]$SubagentResult = @(),
        [string[]]$UserApproval = @(),
        [string]$NotReadyReason = "",
        [string]$PromptSummary = ""
    )

    $toolPath = Join-Path (Get-CodexHomePath) "tools\codex-log-maintenance.ps1"
    if (-not (Test-Path -LiteralPath $toolPath)) {
        return $false
    }

    $args = @(
        "record-event",
        "--event", $EventName,
        "--source", "lightweight-codex-hook",
        "--outcome", $Outcome
    )
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        $args += @("--reason", (Get-StateSummaryText -Value $Reason -Limit 240))
    }
    if (-not [string]::IsNullOrWhiteSpace($ToolName)) {
        $args += @("--tool-name", (Get-StateSummaryText -Value $ToolName -Limit 120))
    }
    if (-not [string]::IsNullOrWhiteSpace($NotReadyReason)) {
        $args += @("--not-ready-reason", (Get-StateSummaryText -Value $NotReadyReason -Limit 240))
    }
    if ($PromptSummary -match "prompt_length=(\d+);\s*prompt_sha256=([0-9a-f]+);\s*contains_non_ascii=(True|False)") {
        $args += @("--prompt-length", $matches[1], "--prompt-sha256", $matches[2])
        if ($matches[3] -eq "True") {
            $args += "--contains-non-ascii"
        } else {
            $args += "--no-contains-non-ascii"
        }
    }
    foreach ($item in $ChangedSurface) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $args += @("--changed-surface", (Get-StateSummaryText -Value $item -Limit 120))
        }
    }
    foreach ($item in $ValidationResult) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $args += @("--validation-result", (Get-StateSummaryText -Value $item -Limit 240))
        }
    }
    foreach ($item in $SubagentResult) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $args += @("--subagent-result", (Get-StateSummaryText -Value $item -Limit 240))
        }
    }
    foreach ($item in $UserApproval) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $args += @("--user-approval", (Get-StateSummaryText -Value $item -Limit 240))
        }
    }

    try {
        $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $toolPath @args 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}
