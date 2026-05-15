$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$stateDir = Join-Path $PSScriptRoot "state"
$statePath = Join-Path $stateDir "lightweight-status.json"
$policyPath = Join-Path $PSScriptRoot "lightweight-codex-policy.json"

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
            toolchainHint = ""
            memoryRoute = ""
            changedSurfaces = @()
            checksRun = @()
            requiredReminders = @()
            toolEvents = @()
            userAuthorizations = @()
            lastUpdated = ""
        }
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        return [ordered]@{
            currentGoal = [string]$state.currentGoal
            workflow = [string]$state.workflow
            toolchainHint = [string]$state.toolchainHint
            memoryRoute = [string]$state.memoryRoute
            changedSurfaces = @($state.changedSurfaces | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 120 })
            checksRun = @($state.checksRun | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 240 })
            requiredReminders = @($state.requiredReminders | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 240 })
            toolEvents = @($state.toolEvents | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 120 })
            userAuthorizations = @($state.userAuthorizations | ForEach-Object { Get-StateSummaryText -Value ([string]$_) -Limit 120 })
            lastUpdated = [string]$state.lastUpdated
        }
    } catch {
        return [ordered]@{
            currentGoal = ""
            workflow = ""
            toolchainHint = ""
            memoryRoute = ""
            changedSurfaces = @()
            checksRun = @()
            requiredReminders = @("Hook state could not be parsed; refresh evidence before finalizing.")
            toolEvents = @()
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

function Select-Workflow {
    param([string]$Prompt)

    $p = $Prompt.ToLowerInvariant()
    $isKoreanReview = Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xB9AC, [int]0xBDF0),
        @([int]0xAC80, [int]0xD1A0),
        @([int]0xC810, [int]0xAC80)
    )
    if ($p -match "debug|bug|fail|error|regression|broken") { return "debug" }
    if ($p -match "migrat|upgrade|move|replace|restructure|cleanup|rename") { return "migration" }
    if ($p -match "security|secret|credential|auth|token|permission|policy") { return "security" }
    if ($p -match "research|docs|document|official|lookup|source") { return "research" }
    if ($p -match "frontend|backend|api|db|full.?stack") { return "full-stack" }
    if ($p -match "review|audit|inspect" -or $isKoreanReview) { return "review" }
    if ($p -match "implement|build|fix|change|edit|create|add|feature|multi-file") { return "feature" }
    return "feature"
}

function Select-LifecyclePhase {
    param([string]$Prompt)

    $p = $Prompt.ToLowerInvariant()
    $isKoreanShip = Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xCEE4, [int]0xBC0B),
        @([int]0xD478, [int]0xC2DC),
        @([int]0xC138, [int]0xC774, [int]0xBE0C)
    )
    $isKoreanReview = Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xB9AC, [int]0xBDF0),
        @([int]0xAC80, [int]0xD1A0),
        @([int]0xC810, [int]0xAC80)
    )
    $isKoreanBuild = Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xC218, [int]0xC815),
        @([int]0xC801, [int]0xC6A9)
    )
    if ($p -match "ship|deploy|release|pr|commit|push") { return "ship" }
    if ($isKoreanShip) { return "ship" }
    if ($p -match "implement|build|fix|change|edit|create|add") { return "build" }
    if ($isKoreanBuild) { return "build" }
    if ($p -match "test|verify|prove|validation|check") { return "verify" }
    if ($p -match "review|audit|inspect|quality") { return "review" }
    if ($isKoreanReview) { return "review" }
    if ($p -match "plan|breakdown|tasks|roadmap") { return "plan" }
    if ($p -match "spec|requirements|scope|acceptance|define") { return "define" }
    return "define-plan-build-verify-review-ship"
}

function Get-SkillRoute {
    param([string]$Prompt)

    $p = $Prompt.ToLowerInvariant()
    $routes = @()
    $isKoreanReview = Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xB9AC, [int]0xBDF0),
        @([int]0xAC80, [int]0xD1A0),
        @([int]0xC810, [int]0xAC80)
    )
    $isKoreanBuild = Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xC218, [int]0xC815),
        @([int]0xC801, [int]0xC6A9)
    )
    $isKoreanGit = Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xCEE4, [int]0xBC0B),
        @([int]0xD478, [int]0xC2DC),
        @([int]0xC138, [int]0xC774, [int]0xBE0C)
    )

    if ($p -match "vague|idea|brainstorm|unclear|ambiguous") {
        $routes += "idea/spec refinement"
    }
    if ($p -match "new feature|feature|architecture|significant|project|spec|requirements") {
        $routes += "spec-driven workflow"
    }
    if ($p -match "plan|breakdown|tasks|roadmap") {
        $routes += "planning/task breakdown"
    }
    if ($p -match "implement|build|fix|change|edit|create|add|multi-file" -or $isKoreanBuild) {
        $routes += "incremental implementation"
    }
    if ($p -match "bug|fail|error|regression|behavior|test") {
        $routes += "test-driven/prove-it workflow"
    }
    if ($p -match "api|sdk|library|framework|official|docs|version") {
        $routes += "source-backed documentation lookup"
    }
    if ($p -match "security|secret|credential|auth|token|permission|irreversible|destructive") {
        $routes += "security/doubt review"
    }
    if ($p -match "ui|browser|frontend|css|layout|visual") {
        $routes += "browser/runtime verification"
    }
    if ($p -match "review|merge|ship|commit|pr" -or $isKoreanReview -or $isKoreanGit) {
        $routes += "code review / ship workflow"
    }

    if ($routes.Count -eq 0) {
        return "none selected yet; keep simple and route only if the task grows"
    }

    return ($routes | Select-Object -Unique) -join ", "
}

function Get-TeamPresetHint {
    param([string]$Workflow)

    switch ($Workflow) {
        "review" { return "optional multi-reviewer preset by dimension; PM deduplicates findings" }
        "debug" { return "optional competing-hypothesis investigators; PM confirms root cause" }
        "feature" { return "optional bounded implementers with explicit file ownership and dependency ordering" }
        "full-stack" { return "split by surface with non-overlapping ownership and integration review" }
        "research" { return "source-backed researcher gathers facts; PM applies them" }
        "security" { return "security reviewer inspects protected assets and approval boundaries" }
        "migration" { return "bounded migration tracks with rollback/quarantine notes" }
        default { return "keep single-agent unless delegation clearly improves outcome" }
    }
}

function Get-PurposeToolchainHint {
    param([string]$Prompt)

    $p = $Prompt.ToLowerInvariant()
    $isKoreanGit = Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xCEE4, [int]0xBC0B),
        @([int]0xD478, [int]0xC2DC),
        @([int]0xC138, [int]0xC774, [int]0xBE0C)
    )
    if ($p -match "memento|memory|memrag|rag|recall|remember") {
        return "memory/Memento: use MCP tools when exposed; support-only evidence; no legacy Memory/RAG fallback"
    }
    if ($p -match "mcp|toolchain|cli|install|uninstall|upgrade|npm|npx|node|postgres|database|runtime") {
        return "workstation toolchain/MCP: inspect source/config first, prefer managed shims or official bundle, record rollback"
    }
    if ($p -match "api|sdk|library|framework|official|docs|version") {
        return "documentation: use source-backed docs for version-sensitive claims"
    }
    if ($p -match "ui|browser|frontend|css|layout|visual") {
        return "frontend/runtime: use project UI contract and rendered verification when practical"
    }
    if ($p -match "git|github|commit|push|pull|merge|pr" -or $isKoreanGit) {
        return "git/GitHub: inspect status first; scope staging to requested changes"
    }
    return "local workspace: use the smallest direct toolchain that can produce verifiable evidence"
}

function Get-MementoMemoryRoute {
    param([string]$Prompt)

    $p = $Prompt.ToLowerInvariant()
    $routes = @()

    $routes += "context at session start when memento tools are exposed"
    if ($p -match "previous|before|again|regression|error|fail|hook|mcp|toolchain|memory|memento|configuration|config|runtime|install|upgrade") {
        $routes += "recall before acting with topic/workspace/case filters"
    }
    if ($p -match "decide|decision|verified|fixed|resolved|procedure|preference|rollback|handoff|final|complete") {
        $routes += "remember only durable verified facts through the PM write gate"
    }
    if ($p -match "final|complete|handoff|summary|ship|done") {
        $routes += "reflect durable decisions/procedures/open risks at final handoff"
    }

    return ($routes | Select-Object -Unique) -join "; "
}

function Test-SubagentSessionStart {
    param($InputObject)

    $json = ""
    try {
        $json = $InputObject | ConvertTo-Json -Depth 20 -Compress
    } catch {
        $json = ""
    }

    $signals = @(
        "(?i)subagent",
        "(?i)sub-agent",
        "(?i)child_agent",
        "(?i)child-agent",
        "(?i)spawn_agent",
        "(?i)agent_type",
        "(?i)parent_agent",
        "(?i)fork_context"
    )

    foreach ($signal in $signals) {
        if ($json -match $signal) {
            return $true
        }
    }

    return $false
}

function Get-VowlineSubagentContext {
    param($Policy)

    $skillPath = Join-Path (Get-AgentsHomePath) "skills\vowline\SKILL.md"
    if ($null -ne $Policy.subagents -and -not [string]::IsNullOrWhiteSpace([string]$Policy.subagents.required_start_skill_path)) {
        $skillPath = [Environment]::ExpandEnvironmentVariables([string]$Policy.subagents.required_start_skill_path)
    }
    $charterPath = Join-Path (Get-CodexHomePath) "maintenance\SUBAGENT_DELEGATION_CHARTER.md"

    return @"
Subagent startup requirement:
- Apply the Vowline operating skill for this subagent: $skillPath
- State the bounded subgoal and authority boundary before work: evidence only, no PM parent-goal completion authority.
- Treat Vowline as a required operating skill alongside task-specific skills; if the full skill cannot be loaded, apply its operating contract to decomposition, evidence, validation, safety, and reporting.
- The delegated task must include Goal, Purpose, PM Context, Owned Surface, Expected Evidence, Anti-Reward-Hacking Rules, Mid-Report, Exit Criteria, and Not Checked.
- Do not optimize for reassuring completion. Produce verifiable evidence, blockers, not-run reasons, and PM verification suggestions.
- A real blocker with evidence is a useful outcome. Unsupported PASS, stale reports, skipped checks counted as success, hidden fallback, or omitted uncertainty invalidates the handoff.
- Use the local charter when relevant: $charterPath
"@
}

function Test-DelegationAuthorized {
    param([string]$Prompt)

    if ($Prompt -match "(?i)(subagents?|sub[-_ ]?agent|multi[-_ ]?agent|delegate|delegation|PM-led|team preset|role separation|parallel agent)") {
        return $true
    }

    $compact = $Prompt -replace "\s+", ""
    $koreanSignals = @(
        (([string][char]0xBA40) + ([string][char]0xD2F0) + ([string][char]0xC5D0) + ([string][char]0xC774) + ([string][char]0xC804) + ([string][char]0xD2B8)),
        (([string][char]0xC11C) + ([string][char]0xBE0C) + ([string][char]0xC5D0) + ([string][char]0xC774) + ([string][char]0xC804) + ([string][char]0xD2B8)),
        (([string][char]0xBCD1) + ([string][char]0xB82C) + ([string][char]0xC5D0) + ([string][char]0xC774) + ([string][char]0xC804) + ([string][char]0xD2B8)),
        (([string][char]0xC5ED) + ([string][char]0xD560) + ([string][char]0xBD84) + ([string][char]0xB9AC))
    )
    foreach ($signal in $koreanSignals) {
        if ($compact.Contains($signal)) {
            return $true
        }
    }

    return $false
}

function Test-HookMaintenanceAuthorized {
    param([string]$Prompt)

    if ($Prompt -match "(?i)(hook|hooks|PreToolUse|PermissionRequest|lightweight-codex-hook|hooks\.json|block|deny|permissionDecision)") {
        return $true
    }

    $compact = $Prompt -replace "\s+", ""
    $signals = @(
        (([string][char]0xD6C5)),
        (([string][char]0xCC28) + ([string][char]0xB2E8)),
        (([string][char]0xCC28) + ([string][char]0xB2E8) + ([string][char]0xC744))
    )
    foreach ($signal in $signals) {
        if ($compact.Contains($signal)) {
            return $true
        }
    }

    return $false
}

function Test-ToolchainMaintenanceAuthorized {
    param([string]$Prompt)

    if ($Prompt -match "(?i)(toolchain|mcp|cli|npm|npx|pnpm|yarn|pip|uv|cargo|install|uninstall|upgrade|storybook|shadcn)") {
        return $true
    }

    $compact = $Prompt -replace "\s+", ""
    $signals = @(
        (([string][char]0xD234) + ([string][char]0xCCB4) + ([string][char]0xC778)),
        (([string][char]0xC124) + ([string][char]0xCE58)),
        (([string][char]0xD234) + ([string][char]0xCCB4) + ([string][char]0xC778) + ([string][char]0xC0AC) + ([string][char]0xC6A9)),
        (([string][char]0xBE4C) + ([string][char]0xB4DC)),
        (([string][char]0xB7F0) + ([string][char]0xD0C0) + ([string][char]0xC784))
    )
    foreach ($signal in $signals) {
        if ($compact.Contains($signal)) {
            return $true
        }
    }

    return $false
}

function Test-StateAuthorization {
    param(
        $State,
        [string]$Authorization
    )

    return (@($State.userAuthorizations) -contains $Authorization)
}

function Get-PromptReminder {
    param(
        [string]$Workflow,
        [string]$Prompt,
        [string]$Phase,
        [string]$SkillRoute,
        [string]$TeamPreset,
        [string]$ToolchainHint,
        [string]$MemoryRoute,
        $Policy
    )

    $goal = Get-PromptSummary -Prompt $Prompt

    $delegationAuthorization = "No subagent authorization detected; keep work local unless the user explicitly asks for delegation."
    if (Test-DelegationAuthorized -Prompt $Prompt) {
        $delegationAuthorization = "Delegation authorized; spawn only bounded non-blocking sidecar agents, then verify outputs."
    }

    return @"
Lightweight Codex workflow reminder:
- Profile: $($Policy.profile); goal: $goal; preset: $Workflow; phase: $Phase.
- Skill route: $SkillRoute; team preset: $TeamPreset.
- Internal intent frame: normalize in English before acting as goal, task_type, authority_boundary, toolchain_purpose, evidence_target, memory_action.
- Purpose toolchain: $ToolchainHint
- Memento memory: $MemoryRoute; memory is support-only, never completion authority. Use tool_feedback after useful or insufficient recall.
- PM owns scope, integration, verification, and final status; user remains reviewer, not operator.
- Subagents: max parallel $($Policy.subagents.max_parallel), max depth $($Policy.subagents.max_depth). $delegationAuthorization
- Delegate only bounded non-blocking side work with owned surfaces and evidence; keep the immediate blocker local.
- Completion requires changed/inspected surfaces, direct checks run, checks not run with reasons, PM independent verification, residual risks, rollback notes, and status complete|blocked|continue.
- Block only real risk: secret content access, irreversible destructive action, hook weakening without explicit user scope, evaluator/pass manipulation, or out-of-scope mutation. Toolchain, MCP, CLI use/install, and read-only inspection should be observed unless they actually perform a blocked action.
"@
}

function Test-FinalAuditReady {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $hasAuditSignal = $Message -match "(?i)(FINAL_GOAL_AUDIT|final goal audit|goal audit|completion audit)"
    $hasChecked = $Message -match "(?i)(checked|checks? run|verified|verification|test|lint|typecheck|build|direct checks?)"
    $hasNotRun = $Message -match "(?i)(not[-_ ]?run|checks? not run|not checked|unable to run|skipped)"
    $hasRisks = $Message -match "(?i)(risk|risks|residual|remaining)"
    $hasStatus = $Message -match "(?i)(status|decision|complete|blocked|continue|current status)"
    $hasPmVerification = $Message -match "(?i)(PM independent|independent verification)"

    return ($hasAuditSignal -and $hasChecked -and $hasNotRun -and $hasRisks -and $hasStatus -and $hasPmVerification)
}

function Deny-PreTool {
    param([string]$Reason)
    Write-HookJson @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "deny"
            permissionDecisionReason = $Reason
        }
    }
}

function Deny-Permission {
    param([string]$Reason)
    Write-HookJson @{
        hookSpecificOutput = @{
            hookEventName = "PermissionRequest"
            decision = @{
                behavior = "deny"
                message = $Reason
            }
        }
    }
}

function Test-StagedDiffSensitiveValidation {
    param([string]$Text)

    if ($Text -notmatch "(?i)\bgit\b" -or
        $Text -notmatch "(?i)\bdiff\b" -or
        $Text -notmatch "(?i)(--cached|--staged)") {
        return $false
    }

    $directReadVerb = "(?i)(?:^|[;&|]\s*|\s)(Get-Content|gc|type|cat|more)(?:\.exe)?(?=\s|$)"
    if ($Text -match $directReadVerb -or $Text -match "(?i)\bSelect-String\b.*\s-(LiteralPath|Path)\b") {
        return $false
    }

    if ($Text -notmatch "(?i)(Select-String|grep|rg|findstr|check-staged-sensitive-diff|password|secret|token|credential|api[_-]?key|api\[_-\]\?key|private key)") {
        return $false
    }

    $directSensitiveFile = "(?i)(auth\.json|\.env(\.|$|\s)|id_rsa|id_ed25519|\.pem\b)"
    if ($Text -match $directSensitiveFile) {
        return $false
    }

    return $true
}

function Test-SecretContentAccess {
    param([string]$Text)

    if (Test-StagedDiffSensitiveValidation -Text $Text) {
        return $false
    }

    $readVerb = "(?i)(?:^|[;&|]\s*|\s)(Get-Content|gc|type|cat|Select-String|more)(?:\.exe)?(?=\s|$)"
    $sensitivePath = "(?i)(auth\.json|\.env(\.|$)|id_rsa|id_ed25519|\.pem\b|(^|[\\/._-])(token|secret|credential|password|api[_-]?key|cookie)([\\/._-]|$))"
    return ($Text -match $readVerb -and $Text -match $sensitivePath)
}

function Test-DestructiveAction {
    param([string]$Text)

    if (Test-ScopedGeneratedCacheCleanup -Text $Text) {
        return $false
    }
    if (Test-ScopedTemporaryRootCleanup -Text $Text) {
        return $false
    }

    $patterns = @(
        "(?i)\bgit\s+reset\s+--hard\b",
        "(?i)\bgit\s+clean\s+-[^\s]*f[^\s]*d",
        "(?i)\bgit\s+push\b.*--force",
        "(?i)\bRemove-Item\b.*\s-(Recurse|r)\b.*\s-(Force|f)\b",
        "(?i)\brmdir\b.*\s/s\b",
        "(?i)\bdel\b.*\s/s\b",
        "(?i)\bformat\b\s+[A-Z]:"
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }
    return $false
}

function Test-ScopedGeneratedCacheCleanup {
    param([string]$Text)

    if ($Text -notmatch "(?i)\bRemove-Item\b" -or
        $Text -notmatch "(?i)\s-(Recurse|r)\b" -or
        $Text -notmatch "(?i)\s-(Force|f)\b") {
        return $false
    }

    $codexRootPattern = [regex]::Escape((Get-CodexHomePath).TrimEnd("\"))
    $allowedRootPattern = "(?i)$codexRootPattern\\(tools|maintenance\\scripts)\\__pycache__(['`"\s;]|$)"
    if ($Text -notmatch $allowedRootPattern) {
        return $false
    }

    $guardSignals = @(
        "Resolve-Path",
        "StartsWith",
        "Refusing to remove outside CODEX_HOME"
    )
    foreach ($signal in $guardSignals) {
        if ($Text -notmatch $signal) {
            return $false
        }
    }

    return $true
}

function Test-ScopedTemporaryRootCleanup {
    param([string]$Text)

    if ($Text -notmatch "(?i)\bRemove-Item\b" -or
        $Text -notmatch "(?i)\s-(Recurse|r)\b" -or
        $Text -notmatch "(?i)\s-(Force|f)\b") {
        return $false
    }

    $codexRootPattern = [regex]::Escape((Get-CodexHomePath).TrimEnd("\"))
    $allowedRootPattern = "(?i)$codexRootPattern\\(\.tmp|tmp|vendor_imports)(['`"\s;]|$)"
    if ($Text -notmatch $allowedRootPattern) {
        return $false
    }

    $guardSignals = @(
        "Resolve-Path",
        "Split-Path\s+-Parent",
        "Refusing unexpected target",
        "Resolved path mismatch"
    )
    foreach ($signal in $guardSignals) {
        if ($Text -notmatch $signal) {
            return $false
        }
    }

    return $true
}

function Test-HookWeakening {
    param([string]$Text)

    $patterns = @(
        "(?i)hooks\s*=\s*false",
        "(?i)codex_hooks\s*=\s*false",
        "(?i)multi_agent\s*=\s*false",
        "(?i)(Remove-Item|rm|del)\b.*(\.codex[\\/]+hooks|hooks\.json|lightweight-codex-hook\.ps1)",
        '(?i)permissionDecision\s*=\s*[''"]allow[''"]',
        '(?i)decision\s*=\s*[''"]approve[''"]'
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }
    return $false
}

function Test-BlockedAppConnectorTool {
    param(
        $InputObject,
        $Policy
    )

    $toolName = [string]$InputObject.tool_name
    if ([string]::IsNullOrWhiteSpace($toolName)) {
        return $false
    }

    $patterns = @(
        "^mcp__codex_apps__supabase($|[._])",
        "^mcp__codex_apps__hugging_face($|[._])"
    )

    if ($null -ne $Policy.toolchain_integrity -and $null -ne $Policy.toolchain_integrity.blocked_app_connector_tool_patterns) {
        $patterns = @($Policy.toolchain_integrity.blocked_app_connector_tool_patterns)
    }

    foreach ($pattern in $patterns) {
        if ($toolName -match $pattern) {
            return $true
        }
    }

    return $false
}

function Test-PolicyOrFixtureEdit {
    param([string]$Text)

    return ($Text -match "(?i)(CODEX_WORKFLOW|FULL_TREE_SCAN|lightweight-codex-policy\.json|\.md\b|fixtures?[\\/]|negative[\\/]|tests?[\\/]|__tests__|spec[\\/])")
}

function Test-FakeSuccessInsertion {
    param([string]$Text)

    $editSignal = $Text -match "(?s)(\*\*\* (Add|Update) File:|new_str|old_str|content|Set-Content|Add-Content|Out-File)"
    if (-not $editSignal) {
        return $false
    }

    if (Test-PolicyOrFixtureEdit -Text $Text) {
        return $false
    }

    $patterns = @(
        "(?i)(\\n|`r?`n|\A)\+?\s*(exit\s+0|sys\.exit\(0\)|process\.exit\(0\))\b",
        "(?im)^\+\s*(exit\s+0|sys\.exit\(0\)|process\.exit\(0\))\b",
        "(?i)(hardcoded\s+pass|fake\s+success|force\s+pass|always\s+pass|skip\s+validation|suppress\s+warnings?)",
        "(?i)(\\n|`r?`n|\A)\+?\s*(return\s+true|return\s+0)\s*(#|//)?\s*(pass|success|valid|ok)",
        "(?im)^\+\s*(return\s+true|return\s+0)\s*(#|//)?\s*(pass|success|valid|ok)",
        "(?is)catch\s*\{[^}]*?(return\s+true|return\s+0|exit\s+0|process\.exit\(0\))"
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }
    return $false
}

function Get-ChangedFileCount {
    param([string]$Text)

    $matches = [regex]::Matches($Text, "\*\*\* (Add|Update|Delete) File:")
    if ($matches.Count -gt 0) {
        return $matches.Count
    }
    return 0
}

function Get-ChangedLineCount {
    param([string]$Text)

    $count = 0
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match "^[+-]" -and $line -notmatch "^(\+\+\+|---|\*\*\*)") {
            $count += 1
        }
    }
    return $count
}

function Invoke-ChromeExtensionOriginRepair {
    $scriptPath = Join-Path (Get-CodexHomePath) "maintenance\scripts\ensure-chrome-extension-origin.ps1"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        return ""
    }

    try {
        $results = @(& $scriptPath -NoNodeCheck 2>&1)
        $important = @($results | Where-Object { [string]$_ -match "^(patched|failed|error):" })
        if ($important.Count -gt 0) {
            return "Chrome extension origin repair: $($important -join '; ')"
        }
    } catch {
        return "Chrome extension origin repair failed: $($_.Exception.Message)"
    }

    return ""
}

function Join-CodepointSignal {
    param([int[]]$Codepoints)

    $chars = foreach ($codepoint in $Codepoints) {
        [string][char]$codepoint
    }
    return ($chars -join "")
}

function Test-PromptContainsAnyCodepointSignal {
    param(
        [string]$Prompt,
        [object[]]$Signals
    )

    $compact = $Prompt -replace "\s+", ""
    foreach ($signal in $Signals) {
        $word = Join-CodepointSignal -Codepoints @($signal)
        if (-not [string]::IsNullOrWhiteSpace($word) -and $compact.Contains($word)) {
            return $true
        }
    }
    return $false
}

$policy = Read-Policy
$inputObject = Read-HookInput
$eventName = [string]$inputObject.hook_event_name
$state = Read-State

try {
switch ($eventName) {
    "SessionStart" {
        $context = "Use the lightweight PM + skill workflow: DEFINE -> PLAN -> BUILD -> VERIFY -> REVIEW -> SHIP. Choose the smallest workflow preset, activate only matching skill workflows, use PM-selected team presets only when useful, preserve file ownership/work tracks, and finish with evidence. Subagents require explicit user authorization by prompt, then should be used only for bounded non-blocking sidecar work. Goal is a long-running tracking marker only; PM owns parent-goal completion, and subagents produce evidence only. Hooks are reminders and narrow safety checks, not completion authority. When memento MCP tools are exposed, call context(workspace='global_pm') at session start, read get_skill_guide when tool behavior is unclear, use recall before hook/MCP/toolchain or prior-state work, send tool_feedback for recall results, and write only durable verified atomic memory through the PM write gate. Memento is support-only and legacy Memory/RAG paths are not active fallback."
        $repairContext = Invoke-ChromeExtensionOriginRepair
        if (-not [string]::IsNullOrWhiteSpace($repairContext)) {
            $context = $context + "`n`n" + $repairContext
        }
        if (Test-SubagentSessionStart -InputObject $inputObject) {
            $context = $context + "`n`n" + (Get-VowlineSubagentContext -Policy $policy)
        }
        Write-CodexStructuredLog -EventName "SessionStart" -Outcome "observed" -Reason "session context injected" | Out-Null
        Write-HookJson @{
            continue = $true
            hookSpecificOutput = @{
                hookEventName = "SessionStart"
                additionalContext = $context
            }
        }
        break
    }

    "UserPromptSubmit" {
        $prompt = Get-PromptText -InputObject $inputObject
        $workflow = Select-Workflow -Prompt $prompt
        $phase = Select-LifecyclePhase -Prompt $prompt
        $skillRoute = Get-SkillRoute -Prompt $prompt
        $teamPreset = Get-TeamPresetHint -Workflow $workflow
        $toolchainHint = Get-PurposeToolchainHint -Prompt $prompt
        $memoryRoute = Get-MementoMemoryRoute -Prompt $prompt
        $promptSummary = Get-PromptSummary -Prompt $prompt
        $state.currentGoal = $promptSummary
        $state.workflow = $workflow
        $state.toolchainHint = $toolchainHint
        $state.memoryRoute = $memoryRoute
        $state.changedSurfaces = @()
        $state.checksRun = @()
        $state.requiredReminders = @()
        $state.toolEvents = @()
        $state.userAuthorizations = @()
        if (Test-HookMaintenanceAuthorized -Prompt $prompt) {
            $state.userAuthorizations = Add-Unique -Items $state.userAuthorizations -Value "hook_policy_change"
        }
        if (Test-ToolchainMaintenanceAuthorized -Prompt $prompt) {
            $state.userAuthorizations = Add-Unique -Items $state.userAuthorizations -Value "toolchain_mcp_cli_maintenance"
        }
        Save-State -State $state

        Write-CodexStructuredLog -EventName "UserPromptSubmit" -Outcome "observed" -Reason $workflow -ChangedSurface @("hooks.state") -PromptSummary $promptSummary | Out-Null
        $reminder = Get-PromptReminder -Workflow $workflow -Prompt $prompt -Phase $phase -SkillRoute $skillRoute -TeamPreset $teamPreset -ToolchainHint $toolchainHint -MemoryRoute $memoryRoute -Policy $policy
        Write-HookJson @{
            continue = $true
            hookSpecificOutput = @{
                hookEventName = "UserPromptSubmit"
                additionalContext = $reminder
            }
        }
        break
    }

    "PreToolUse" {
        $toolName = [string]$inputObject.tool_name
        $text = Get-ToolText -InputObject $inputObject

        if (Test-BlockedAppConnectorTool -InputObject $inputObject -Policy $policy) {
            $reason = "Unintended Codex Apps connector tool is blocked. Remove or re-authorize the connector intentionally before use."
            if ($null -ne $policy.toolchain_integrity -and -not [string]::IsNullOrWhiteSpace([string]$policy.toolchain_integrity.blocked_app_connector_reason)) {
                $reason = [string]$policy.toolchain_integrity.blocked_app_connector_reason
            }
            Write-CodexStructuredLog -EventName "PreToolUse" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-PreTool -Reason $reason
            break
        }
        if (Test-SecretContentAccess -Text $text) {
            $reason = "Secret or credential content access is blocked. Use metadata-only inspection unless the user explicitly requested that exact file."
            Write-CodexStructuredLog -EventName "PreToolUse" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-PreTool -Reason $reason
            break
        }
        if (Test-DestructiveAction -Text $text) {
            $reason = "Irreversible destructive action is blocked by the lightweight hook. Ask the user explicitly before proceeding."
            Write-CodexStructuredLog -EventName "PreToolUse" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-PreTool -Reason $reason
            break
        }
        if ((Test-HookWeakening -Text $text) -and -not (Test-StateAuthorization -State $state -Authorization "hook_policy_change")) {
            $reason = "Hook, multi-agent, or completion-safety weakening is blocked unless the user explicitly requests that exact change."
            Write-CodexStructuredLog -EventName "PreToolUse" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-PreTool -Reason $reason
            break
        }
        if (Test-FakeSuccessInsertion -Text $text) {
            $reason = "Fake-success or evaluator/exit-code manipulation is blocked for product and control-code edits. Use real validation or document a not-run reason."
            Write-CodexStructuredLog -EventName "PreToolUse" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-PreTool -Reason $reason
            break
        }

        Write-CodexStructuredLog -EventName "PreToolUse" -Outcome "observed" -ToolName $toolName | Out-Null
        Write-HookJson @{ systemMessage = "" }
        break
    }

    "PermissionRequest" {
        $toolName = [string]$inputObject.tool_name
        $text = Get-ToolText -InputObject $inputObject

        if (Test-BlockedAppConnectorTool -InputObject $inputObject -Policy $policy) {
            $reason = "Unintended Codex Apps connector tool is blocked. Remove or re-authorize the connector intentionally before use."
            if ($null -ne $policy.toolchain_integrity -and -not [string]::IsNullOrWhiteSpace([string]$policy.toolchain_integrity.blocked_app_connector_reason)) {
                $reason = [string]$policy.toolchain_integrity.blocked_app_connector_reason
            }
            Write-CodexStructuredLog -EventName "PermissionRequest" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-Permission -Reason $reason
            break
        }
        if (Test-SecretContentAccess -Text $text) {
            $reason = "Secret or credential content access is blocked. Use metadata-only inspection unless the user explicitly requested that exact file."
            Write-CodexStructuredLog -EventName "PermissionRequest" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-Permission -Reason $reason
            break
        }
        if (Test-DestructiveAction -Text $text) {
            $reason = "Irreversible destructive action requires an explicit user request."
            Write-CodexStructuredLog -EventName "PermissionRequest" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-Permission -Reason $reason
            break
        }
        if ((Test-HookWeakening -Text $text) -and -not (Test-StateAuthorization -State $state -Authorization "hook_policy_change")) {
            $reason = "Hook or multi-agent workflow weakening requires an explicit user request."
            Write-CodexStructuredLog -EventName "PermissionRequest" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-Permission -Reason $reason
            break
        }
        if (Test-FakeSuccessInsertion -Text $text) {
            $reason = "Fake-success or evaluator/exit-code manipulation requires explicit user scope and real validation evidence."
            Write-CodexStructuredLog -EventName "PermissionRequest" -Outcome "hard_block" -Reason $reason -ToolName $toolName | Out-Null
            Deny-Permission -Reason $reason
            break
        }

        Write-CodexStructuredLog -EventName "PermissionRequest" -Outcome "observed" -ToolName $toolName | Out-Null
        Write-HookJson @{ systemMessage = "" }
        break
    }

    "PostToolUse" {
        $toolName = [string]$inputObject.tool_name
        $text = Get-ToolText -InputObject $inputObject
        $state.toolEvents = Add-Unique -Items $state.toolEvents -Value $toolName

        $additional = @()
        $logChangedSurfaces = @()
        $logValidationResults = @()
        $changedFileCount = Get-ChangedFileCount -Text $text
        $changedLineCount = Get-ChangedLineCount -Text $text
        if ($toolName -match "apply_patch|Edit|Write") {
            $state.changedSurfaces = Add-Unique -Items $state.changedSurfaces -Value "files"
            $logChangedSurfaces += "files"
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Run relevant checks or record a precise not-run reason before finalizing."
            $additional += "File edits detected: verify with direct checks or record why checks could not run."
        }
        if ($changedFileCount -ge [int]$policy.work_size.large_files -or $changedLineCount -ge [int]$policy.work_size.large_changed_lines) {
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Large or multi-surface change detected; use a visible work-track/status summary and evidence before finalizing."
            $additional += "Large-change threshold reached: summarize work tracks, validation, not-run reasons, and risks before finalizing."
        }
        if ($text -match "(?i)(package\.json|pyproject\.toml|Cargo\.toml|requirements\.txt|uv\.lock|package-lock\.json|pnpm-lock\.yaml|Cargo\.lock)") {
            $state.changedSurfaces = Add-Unique -Items $state.changedSurfaces -Value "dependencies"
            $logChangedSurfaces += "dependencies"
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Dependency metadata changed; align lockfile or record why no sync is needed."
            $additional += "Dependency/config sync may be required."
        }
        if ($text -match "(?i)(test|pytest|cargo test|npm test|pnpm test|yarn test|typecheck|lint|build)") {
            $evidence = Get-ToolEvidenceSummary -ToolName $toolName -Text $text
            $state.checksRun = Add-Unique -Items $state.checksRun -Value $evidence
            $logValidationResults += $evidence
        }
        if ($text -match "(?i)(hardcoded pass|fake success|exit 0|PASS)") {
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Review changed product/control surfaces for hardcoded or fake-success contamination."
        }

        Save-State -State $state
        Write-CodexStructuredLog -EventName "PostToolUse" -Outcome "observed" -ToolName $toolName -ChangedSurface $logChangedSurfaces -ValidationResult $logValidationResults | Out-Null

        if ($additional.Count -gt 0) {
            Write-HookJson @{
                hookSpecificOutput = @{
                    hookEventName = "PostToolUse"
                    additionalContext = ($additional -join " ")
                }
            }
        } else {
            Write-HookJson @{ systemMessage = "" }
        }
        break
    }

    "Stop" {
        $lastMessage = [string]$inputObject.last_assistant_message
        $hasChanged = @($state.changedSurfaces).Count -gt 0
        $auditReady = Test-FinalAuditReady -Message $lastMessage

        if ($hasChanged -and -not $auditReady -and -not [bool]$inputObject.stop_hook_active) {
            $reason = "Final evidence missing after changed surfaces were observed."
            Write-CodexStructuredLog -EventName "Stop" -Outcome "not_ready" -Reason $reason -NotReadyReason $reason -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: changed surfaces were observed. Before finalizing, produce a goal audit with checked items, not-run reasons, residual risks, current status complete|blocked|continue, and PM independent verification."
            }
            break
        }

        Write-CodexStructuredLog -EventName "Stop" -Outcome "observed" -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) | Out-Null
        Write-HookJson @{
            continue = $true
            systemMessage = ""
        }
        break
    }

    default {
        Write-HookJson @{ continue = $true }
        break
    }
}
} catch {
    Write-HookJson @{
        continue = $true
        systemMessage = "Lightweight hook internal error in event '$eventName': $($_.Exception.Message). Continue, but verify hook behavior before relying on hook evidence."
    }
}
