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

function Select-Workflow {
    param([string]$Prompt)

    $p = $Prompt.ToLowerInvariant()
    $hasRootCauseSignal = Test-RootCauseOrIncidentSignal -Prompt $Prompt
    $isKoreanReview = Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xB9AC, [int]0xBDF0),
        @([int]0xAC80, [int]0xD1A0),
        @([int]0xC810, [int]0xAC80)
    )
    if ($p -match "debug|bug|fail|failure|error|regression|broken|root cause|incident|\bp0\b" -or $hasRootCauseSignal) { return "debug" }
    if ($p -match "migrat|upgrade|move|replace|restructure|cleanup|rename") { return "migration" }
    if ($p -match "(?i)(\bsecurity\b|\bsecret\b|\bcredential\b|\bauth\b|\bauthentication\b|\btoken\b|\bpermission\b|policy)") { return "security" }
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
    $hasRootCauseSignal = Test-RootCauseOrIncidentSignal -Prompt $Prompt
    $hasWorkflowGovernanceSignal = Test-WorkflowGovernanceSignal -Prompt $Prompt
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
    if ($hasRootCauseSignal) {
        $routes += "resolve-agent-incidents"
        $routes += "debugging/error recovery"
    }
    if ($hasWorkflowGovernanceSignal) {
        $routes += "agent-harness-construction"
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
    if ($p -match "bug|fail|failure|error|regression|behavior|test|root cause|\bp0\b" -or $hasRootCauseSignal) {
        $routes += "test-driven/prove-it workflow"
    }
    if ($p -match "api|sdk|library|framework|official|docs|version") {
        $routes += "source-backed documentation lookup"
    }
    if ($p -match "(?i)(\bsecurity\b|\bsecret\b|\bcredential\b|\bauth\b|\bauthentication\b|\btoken\b|\bpermission\b|irreversible|destructive)") {
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
    if (Test-WorkflowGovernanceSignal -Prompt $Prompt) {
        return "Codex workflow/harness: inspect scoped policy, hooks, harness smoke tests, and logs; patch the smallest enforceable surface and verify with synthetic hook samples"
    }
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
    if ($p -match "previous|before|again|regression|error|fail|failure|hook|mcp|toolchain|memory|memento|configuration|config|runtime|install|upgrade" -or (Test-RootCauseOrIncidentSignal -Prompt $Prompt) -or (Test-WorkflowGovernanceSignal -Prompt $Prompt)) {
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

    $codexHome = Get-CodexHomePath
    $skillPath = Join-Path (Get-AgentsHomePath) "skills\vowline\SKILL.md"
    if ($null -ne $Policy.subagents -and -not [string]::IsNullOrWhiteSpace([string]$Policy.subagents.required_start_skill_path)) {
        $skillPath = [Environment]::ExpandEnvironmentVariables([string]$Policy.subagents.required_start_skill_path)
    }
    $agentsPath = Join-Path $codexHome "AGENTS.md"
    $toolRequirementsPath = Join-Path $codexHome "maintenance\AGENT_TOOL_REQUIREMENTS.md"
    $charterPath = Join-Path $codexHome "maintenance\SUBAGENT_DELEGATION_CHARTER.md"

    return @"
Subagent startup requirement:
- Apply the Vowline operating skill for this subagent: $skillPath
- Workspace scope: $codexHome. Follow $agentsPath before lower-priority agent.md or recalled memory.
- Workflow fixture: DEFINE -> PLAN -> BUILD -> VERIFY -> REVIEW -> SHIP, scaled to the delegated subgoal.
- Toolchain fixture: use explicit wrappers and source policy from $toolRequirementsPath; do not read secrets unless the user requested that exact file.
- Memento fixture: support-only memory. When memento tools are exposed, use context(workspace='global_pm') and recall for hook/MCP/toolchain prior-state work, never as completion authority.
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

    if ($Prompt -match "(?i)(subagents?|sub[-_ ]?agent|multi[-_ ]?agent|spawn_agent|parallel agent|role separation|\bdelegate\b|\bdelegation\b|\bdelegated\b)") {
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

function Test-RootCauseOrIncidentSignal {
    param([string]$Prompt)

    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        return $false
    }

    if ($Prompt -match "(?i)(\bp0\b|root cause|failure|failed|regression|incident|skipped workflow|cognitive debt|design defect|harness weakness|workflow skip)") {
        return $true
    }

    return (Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xC2E4, [int]0xD328),
        @([int]0xC624, [int]0xB958),
        @([int]0xBB38, [int]0xC81C),
        @([int]0xADFC, [int]0xBCF8),
        @([int]0xC6D0, [int]0xC778),
        @([int]0xACB0, [int]0xD568),
        @([int]0xCDE8, [int]0xC57D)
    ))
}

function Test-WorkflowGovernanceSignal {
    param([string]$Prompt)

    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        return $false
    }

    if ($Prompt -match "(?i)(hook|hooks|harness|workflow|toolchain|debugger|debugging tool|level escalation|task level|subagents?|sub[-_ ]?agent|multi[-_ ]?agent|spawn_agent|watcher|worker|delegate|delegation|goal integrity|codex goal|l1/l2/l3/l4|task_class|classification)") {
        return $true
    }

    return (Test-PromptContainsAnyCodepointSignal -Prompt $Prompt -Signals @(
        @([int]0xD6C5),
        @([int]0xD558, [int]0xB124, [int]0xC2A4),
        @([int]0xC6CC, [int]0xD06C, [int]0xD50C, [int]0xB85C),
        @([int]0xC11C, [int]0xBE0C, [int]0xC5D0, [int]0xC774, [int]0xC804, [int]0xD2B8),
        @([int]0xAC10, [int]0xC2DC),
        @([int]0xBAA9, [int]0xD45C),
        @([int]0xBD84, [int]0xB958)
    ))
}

function Get-TaskClassification {
    param(
        [string]$Prompt,
        [string]$Workflow,
        [string]$Phase
    )

    $reasons = @()
    $delegationAuthorized = Test-DelegationAuthorized -Prompt $Prompt
    $hasRootCauseSignal = Test-RootCauseOrIncidentSignal -Prompt $Prompt
    $hasWorkflowGovernanceSignal = Test-WorkflowGovernanceSignal -Prompt $Prompt
    $p = $Prompt.ToLowerInvariant()

    if ($Prompt.Length -gt 1200) {
        $reasons += "long prompt"
    }
    if ($delegationAuthorized) {
        $reasons += "explicit delegation authorization"
    }
    if ($hasRootCauseSignal) {
        $reasons += "P0/repeated-failure/root-cause signal"
    }
    if ($hasWorkflowGovernanceSignal) {
        $reasons += "workflow/harness/subagent governance surface"
    }
    if ($p -match "(?i)(\bsecurity\b|\bsecret\b|\bcredential\b|\bauth\b|\bauthentication\b|\bpermission\b|irreversible|destructive)") {
        $reasons += "sensitive or high-risk boundary"
    }
    if ($p -match "(?i)(test|verify|validation|lint|build|commit|push|ship|deploy)") {
        $reasons += "verification or ship requirement"
    }

    $level = "L2"
    if ($hasRootCauseSignal -and ($hasWorkflowGovernanceSignal -or $delegationAuthorized)) {
        $level = "L4"
    } elseif ($hasWorkflowGovernanceSignal -or $delegationAuthorized -or $Prompt.Length -gt 1200) {
        $level = "L3"
    } elseif ($p -match "(?i)(explain|question|simple|one file|tiny)") {
        $level = "L1"
    }

    if ($reasons.Count -eq 0) {
        $reasons += "bounded implementation or review"
    }

    return [pscustomobject]@{
        level = $level
        reason = (($reasons | Select-Object -Unique) -join "; ")
        workflow = $Workflow
        phase = $Phase
        delegationAuthorized = $delegationAuthorized
        goalActionRequired = ($level -in @("L3", "L4"))
        watcherCoverageRequired = ($delegationAuthorized -and $level -eq "L4")
        anomalyPauseExpected = ($level -eq "L4" -and $hasRootCauseSignal -and ($hasWorkflowGovernanceSignal -or $delegationAuthorized))
        subagentDecisionRequired = $delegationAuthorized
    }
}

function Get-IntentFrame {
    param(
        [string]$Prompt,
        [string]$Workflow,
        [string]$Phase,
        [string]$ToolchainHint,
        [string]$MemoryRoute,
        $Classification
    )

    $goal = "Satisfy the current user request with the selected workflow and direct evidence."
    if (Test-WorkflowGovernanceSignal -Prompt $Prompt) {
        $goal = "Investigate and repair the Codex workflow or harness control-plane behavior described by the user."
    }
    if ((Test-RootCauseOrIncidentSignal -Prompt $Prompt) -and (Test-WorkflowGovernanceSignal -Prompt $Prompt)) {
        $goal = "Find the root cause of the reported Codex workflow/harness incident, patch confirmed enforcement gaps, and verify regression coverage."
    }

    $evidenceTarget = "Direct inspection plus the smallest relevant command or runtime check."
    if ($Classification.level -eq "L4") {
        $evidenceTarget = "Hook sample output, persisted hook state, Stop-hook negative behavior, harness/eval result, subagent/watcher evidence or WATCHER_NOT_USED, and rollback notes."
    } elseif ($Classification.level -eq "L3") {
        $evidenceTarget = "Structured plan, direct file/runtime evidence, relevant tests or not-run reason, and final goal audit if surfaces changed."
    }

    $subagentPolicy = "No delegation unless the user explicitly authorizes it."
    if ([bool]$Classification.delegationAuthorized) {
        $subagentPolicy = "Delegation is authorized by the user; spawn only bounded non-blocking sidecar agents and independently verify candidate evidence."
    }

    return [ordered]@{
        english_normalized_goal = $goal
        task_type = "$($Classification.level) $Workflow/$Phase"
        authority_boundary = "Main PM owns scope, integration, verification, and parent-goal status; subagents produce candidate evidence only."
        toolchain_purpose = $ToolchainHint
        evidence_target = $evidenceTarget
        memory_action = $MemoryRoute
        subagent_policy = $subagentPolicy
        subagent_call_declaration = "If the user explicitly authorizes subagents or a subagent tool is used, final evidence must repeat SUBAGENT_CALL used/not_used with reason, direct evidence, and residual risk, regardless of task-class reminder availability."
        calibration_action = "If hook state, tool output, validation, or final preflight contradicts the current workflow, pause the active path, preserve evidence, trace the anomaly, and resume only with direct verification or an explicit blocked/continue decision."
    }
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
    $classification = Get-TaskClassification -Prompt $Prompt -Workflow $Workflow -Phase $Phase

    $delegationAuthorization = "No subagent authorization detected; keep work local unless the user explicitly asks for delegation."
    if (Test-DelegationAuthorized -Prompt $Prompt) {
        $delegationAuthorization = "Delegation authorized: user has instructed subagent calls as needed. Spawn bounded non-blocking sidecar agents when they reduce risk, then verify outputs."
    }

    $subagentDecisionAction = "Subagent call declaration: not required unless the user explicitly authorizes subagents."
    if ([bool]$classification.subagentDecisionRequired) {
        $subagentDecisionAction = "Subagent call declaration required: after this user instruction, final evidence must repeat SUBAGENT_CALL used or SUBAGENT_CALL not_used with reason, direct evidence, and residual risk even if task_class is unavailable."
    }

    $goalAction = "Goal action: no persisted Codex Goal required unless the task becomes long-running or stateful."
    if ([bool]$classification.goalActionRequired) {
        $goalAction = "Goal action required: create or update one Codex Goal before build/repair work, then keep it as tracking only."
    }

    $watcherAction = "Watcher action: use only if a non-trivial delegated worker or pre-ship integrity risk exists."
    if ([bool]$classification.watcherCoverageRequired) {
        $watcherAction = "Watcher action required by default for this L4 delegated incident: spawn an OBS/REV read-only watcher for inspect/adversarial review; if omitted, record WATCHER_NOT_USED with reason, risk, substitute check, and confidence impact."
    }

    $calibrationAction = "Calibration: if an unexpected mismatch appears, preserve evidence and switch to debug trace before continuing."
    if ([bool]$classification.anomalyPauseExpected) {
        $calibrationAction = "Calibration action required: anomaly signal detected; pause build/ship, preserve evidence, trace the first mismatch, check overlap with existing gates, then resume only with verification or blocked/continue status."
    }

    return @"
Lightweight Codex workflow reminder:
- Core brief: task_class=$($classification.level); goal=$goal; preset=$Workflow; phase=$Phase.
- Output rule: user text should include only request summary, objective, task level, current status/action, direct evidence, and material blockers/risks; keep reasoning and internal frames private.
- Route: skills=$SkillRoute; team=$TeamPreset; toolchain=$ToolchainHint.
- $goalAction
- Memory: $MemoryRoute; support-only, never completion authority.
- Subagents: max=$($Policy.subagents.max_parallel), depth=$($Policy.subagents.max_depth). $delegationAuthorization
- $subagentDecisionAction
- $watcherAction
- $calibrationAction
- Completion: changed surfaces, direct checks, not-run reasons, PM verification, residual risks, rollback, status.
- Hard blocks: secret access, irreversible destructive action, hook weakening without scope, evaluator/pass manipulation, out-of-scope mutation.
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

function Test-WatcherCoverageReady {
    param(
        $State,
        [string]$Message
    )

    if (-not [bool]$State.watcherExpected) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $hasWatcherReport = $Message -match "(?i)(WATCHER_REPORT|OBS-|REV-|watcher report|watcher evidence|adversarial review)"
    $hasWatcherNotUsed = $Message -match "(?i)(WATCHER_NOT_USED|watcher not used)"
    $hasAcceptedRejectedEvidence = $Message -match "(?i)(accepted and rejected subagent evidence|accepted/rejected subagent evidence|accepted subagent evidence|rejected subagent evidence|subagent evidence)"

    return ($hasWatcherReport -or $hasWatcherNotUsed -or $hasAcceptedRejectedEvidence)
}

function Test-AnomalyTraceReady {
    param(
        $State,
        [string]$Message
    )

    if (-not [bool]$State.anomalyPauseExpected) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $hasPause = $Message -match "(?i)(pause|paused|stop-the-line|anomaly pause|stop active path)"
    $hasTrace = $Message -match "(?i)(trace|traced|root cause|first mismatch|failure point|mismatch)"
    $hasOutcome = $Message -match "(?i)(verified|verification|blocked|continue|complete|risk|residual)"

    return ($hasPause -and $hasTrace -and $hasOutcome)
}

function Test-SubagentDecisionReady {
    param(
        $State,
        [string]$Message
    )

    $hasSubagentEvent = @($State.subagentEvents).Count -gt 0
    if (-not ([bool]$State.subagentDecisionRequired -or $hasSubagentEvent)) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $hasMarker = $Message -match "(?i)SUBAGENT_CALL\s+(used|not_used|not used)"
    $hasReason = $Message -match "(?i)(reason|because)"
    $hasEvidence = $Message -match "(?i)(evidence|verified|direct evidence|substitute check)"
    $hasRisk = $Message -match "(?i)(risk|residual)"

    return ($hasMarker -and $hasReason -and $hasEvidence -and $hasRisk)
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
        $promptSummary = Get-PromptSummary -Prompt $prompt
        if (Test-PromptSecretLeak -Prompt $prompt) {
            $reason = "Prompt appears to contain a secret-like value. Remove the credential from the prompt and reference only metadata, variable names, or a redacted placeholder."
            Write-CodexStructuredLog -EventName "UserPromptSubmit" -Outcome "hard_block" -Reason $reason -PromptSummary $promptSummary | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = $reason
            }
            break
        }
        $workflow = Select-Workflow -Prompt $prompt
        $phase = Select-LifecyclePhase -Prompt $prompt
        $skillRoute = Get-SkillRoute -Prompt $prompt
        $teamPreset = Get-TeamPresetHint -Workflow $workflow
        $toolchainHint = Get-PurposeToolchainHint -Prompt $prompt
        $memoryRoute = Get-MementoMemoryRoute -Prompt $prompt
        $classification = Get-TaskClassification -Prompt $prompt -Workflow $workflow -Phase $phase
        $intentFrame = Get-IntentFrame -Prompt $prompt -Workflow $workflow -Phase $phase -ToolchainHint $toolchainHint -MemoryRoute $memoryRoute -Classification $classification
        $state.currentGoal = $promptSummary
        $state.workflow = $workflow
        $state.taskClass = [string]$classification.level
        $state.classificationReason = [string]$classification.reason
        $state.delegationAuthorized = [bool]$classification.delegationAuthorized
        $state.goalRequired = [bool]$classification.goalActionRequired
        $state.watcherExpected = [bool]$classification.watcherCoverageRequired
        $state.anomalyPauseExpected = [bool]$classification.anomalyPauseExpected
        $state.subagentDecisionRequired = [bool]$classification.subagentDecisionRequired
        $state.intentFrame = $intentFrame
        $state.toolchainHint = $toolchainHint
        $state.memoryRoute = $memoryRoute
        $state.changedSurfaces = @()
        $state.checksRun = @()
        $state.requiredReminders = @()
        $state.toolEvents = @()
        $state.subagentEvents = @()
        $state.userAuthorizations = @()
        $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "PM startup packet required: L1/L2/L3/L4 class, English intent frame, workflow continuation, evidence target."
        if ([bool]$classification.goalActionRequired) {
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Codex Goal required before build/repair work; Goal is tracking only, not completion authority."
        }
        if ([bool]$classification.watcherCoverageRequired) {
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Watcher coverage required by default; provide WATCHER_REPORT/subagent evidence or WATCHER_NOT_USED before finalization."
        }
        if ([bool]$classification.subagentDecisionRequired) {
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Subagent call declaration required: record SUBAGENT_CALL used/not_used with reason, direct evidence, and residual risk."
        }
        if ([bool]$classification.anomalyPauseExpected) {
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Anomaly pause/trace required: preserve the first mismatch, stop the original path, and resume only with verified correction or blocked/continue status."
        }
        if (Test-HookMaintenanceAuthorized -Prompt $prompt) {
            $state.userAuthorizations = Add-Unique -Items $state.userAuthorizations -Value "hook_policy_change"
        }
        if (Test-ToolchainMaintenanceAuthorized -Prompt $prompt) {
            $state.userAuthorizations = Add-Unique -Items $state.userAuthorizations -Value "toolchain_mcp_cli_maintenance"
        }
        if ([bool]$classification.delegationAuthorized) {
            $state.userAuthorizations = Add-Unique -Items $state.userAuthorizations -Value "delegation_authorized"
        }
        Save-State -State $state

        Write-CodexStructuredLog -EventName "UserPromptSubmit" -Outcome "observed" -Reason "$workflow;$($classification.level);$($classification.reason)" -ChangedSurface @("hooks.state") -PromptSummary $promptSummary -UserApproval @($state.userAuthorizations) | Out-Null
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
        $logSubagentResults = @()
        if ($toolName -match "(?i)(spawn_agent|wait_agent|send_input|close_agent|resume_agent)" -or $text -match "(?i)(agent_id|agent_type|WATCHER_REPORT|WATCHER_NOT_USED|NORMALIZED_WORKER_PACKET)") {
            $evidence = Get-ToolEvidenceSummary -ToolName $toolName -Text $text
            $state.subagentEvents = Add-Unique -Items $state.subagentEvents -Value $evidence
            $logSubagentResults += $evidence
            if ([bool]$state.watcherExpected) {
                $additional += "Subagent-related activity observed: final audit must accept/reject this evidence and include watcher coverage or WATCHER_NOT_USED."
            }
        }
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
        Write-CodexStructuredLog -EventName "PostToolUse" -Outcome "observed" -ToolName $toolName -ChangedSurface $logChangedSurfaces -ValidationResult $logValidationResults -SubagentResult $logSubagentResults | Out-Null

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
        $hasSubstantiveActivity = $hasChanged -or @($state.toolEvents).Count -gt 0
        $auditReady = Test-FinalAuditReady -Message $lastMessage
        $watcherReady = Test-WatcherCoverageReady -State $state -Message $lastMessage
        $anomalyTraceReady = Test-AnomalyTraceReady -State $state -Message $lastMessage
        $subagentDecisionReady = Test-SubagentDecisionReady -State $state -Message $lastMessage

        if ($hasSubstantiveActivity -and -not $anomalyTraceReady -and -not [bool]$inputObject.stop_hook_active) {
            $reason = "Anomaly pause/trace evidence missing for an L4 workflow incident."
            Write-CodexStructuredLog -EventName "Stop" -Outcome "not_ready" -Reason $reason -NotReadyReason $reason -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) -SubagentResult @($state.subagentEvents) | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: an anomaly-calibration workflow was active. Before finalizing, state the pause/trace trigger, first mismatch/root cause, verification or blocked/continue status, and residual risk."
            }
            break
        }

        if ($hasSubstantiveActivity -and -not $subagentDecisionReady -and -not [bool]$inputObject.stop_hook_active) {
            $reason = "Subagent call declaration missing after explicit subagent authorization."
            Write-CodexStructuredLog -EventName "Stop" -Outcome "not_ready" -Reason $reason -NotReadyReason $reason -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) -SubagentResult @($state.subagentEvents) | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: subagent use was explicitly authorized or a subagent tool event was observed. Before finalizing, include SUBAGENT_CALL used/not_used with reason, direct evidence, and residual risk, even if task_class was unavailable."
            }
            break
        }

        if ($hasSubstantiveActivity -and -not $watcherReady -and -not [bool]$inputObject.stop_hook_active) {
            $reason = "Watcher or subagent evidence missing for an L4 delegated workflow incident."
            Write-CodexStructuredLog -EventName "Stop" -Outcome "not_ready" -Reason $reason -NotReadyReason $reason -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) -SubagentResult @($state.subagentEvents) | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: this prompt was classified as L4 with delegation authorized. Before finalizing, include accepted/rejected subagent evidence plus WATCHER_REPORT, or record WATCHER_NOT_USED with reason, risk, substitute check, and confidence impact."
            }
            break
        }

        if ($hasChanged -and -not $auditReady -and -not [bool]$inputObject.stop_hook_active) {
            $reason = "Final evidence missing after changed surfaces were observed."
            Write-CodexStructuredLog -EventName "Stop" -Outcome "not_ready" -Reason $reason -NotReadyReason $reason -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) -SubagentResult @($state.subagentEvents) | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: changed surfaces were observed. Before finalizing, produce a goal audit with checked items, not-run reasons, residual risks, current status complete|blocked|continue, and PM independent verification."
            }
            break
        }

        Write-CodexStructuredLog -EventName "Stop" -Outcome "observed" -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) -SubagentResult @($state.subagentEvents) | Out-Null
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
