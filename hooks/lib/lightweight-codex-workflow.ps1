# Workflow classification and final-evidence helpers for lightweight-codex-hook.ps1.
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

function Get-TaskLevelRank {
    param([string]$Level)

    switch ($Level) {
        "L1" { return 1 }
        "L2" { return 2 }
        "L3" { return 3 }
        "L4" { return 4 }
        default { return 0 }
    }
}

function Get-ToolTaskAdjustment {
    param(
        [string]$Stage,
        [string]$ToolName,
        [string]$Text,
        [int]$ChangedFileCount = 0,
        [int]$ChangedLineCount = 0,
        $Policy
    )

    $reasons = @()
    $level = ""
    $largeFiles = [int]$Policy.work_size.large_files
    $largeLines = [int]$Policy.work_size.large_changed_lines
    $governancePattern = "(?i)(hook|workflow|harness|toolchain|debugger|mcp|plugins?[\\/]+cache|skills?[\\/].*scripts?|agents\.md|project_workflow_chain|codex_agent_harness|lightweight-codex)"
    $incidentPattern = "(?i)(root cause|failure|failed|regression|false[- ]?pass|fake success|hidden fallback|stale state|unsupported success|bypass)"

    if ($Text -match $governancePattern) {
        $level = "L3"
        $reasons += "$Stage observed workflow/harness/toolchain or skill/plugin-cache surface"
    }
    if ($ChangedFileCount -ge $largeFiles -or $ChangedLineCount -ge $largeLines) {
        $level = "L3"
        $reasons += "$Stage observed large or multi-surface change"
    }
    if (($Text -match $governancePattern) -and ($Text -match $incidentPattern)) {
        $level = "L4"
        $reasons += "$Stage observed incident signal intersecting workflow/governance surface"
    }
    if ($ToolName -match "(?i)(spawn_agent|send_input|wait_agent|close_agent|resume_agent)") {
        $level = "L3"
        $reasons += "$Stage observed subagent tool surface"
    }

    return [pscustomobject]@{
        level = $level
        reason = (($reasons | Select-Object -Unique) -join "; ")
        compatibilityReviewRequired = ($Text -match $governancePattern -or $ChangedFileCount -gt 1 -or $ChangedLineCount -ge $largeLines)
        anomalyPauseExpected = (($Text -match $governancePattern) -and ($Text -match $incidentPattern))
    }
}

function Apply-TaskLevelAdjustment {
    param(
        $State,
        $Adjustment
    )

    if ($null -eq $Adjustment -or [string]::IsNullOrWhiteSpace([string]$Adjustment.level)) {
        return $false
    }

    $changed = $false
    if ((Get-TaskLevelRank -Level ([string]$Adjustment.level)) -gt (Get-TaskLevelRank -Level ([string]$State.taskClass))) {
        $State.taskClass = [string]$Adjustment.level
        $State.classificationReason = [string]$Adjustment.reason
        if ($State.taskClass -in @("L3", "L4")) {
            $State.goalRequired = $true
        }
        if ([bool]$Adjustment.anomalyPauseExpected) {
            $State.anomalyPauseExpected = $true
        }
        $changed = $true
    }

    if ([bool]$Adjustment.compatibilityReviewRequired) {
        $State.requiredReminders = Add-Unique -Items $State.requiredReminders -Value "Compatibility review required: identify affected hooks, workflows, toolchains, MCPs, skills/plugin cache, overlapping gates, verification, and rollback before finalizing."
        $changed = $true
    }

    return $changed
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
