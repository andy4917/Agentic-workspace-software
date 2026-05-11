$ErrorActionPreference = "Stop"

$stateDir = Join-Path $PSScriptRoot "state"
$statePath = Join-Path $stateDir "lightweight-status.json"
$policyPath = Join-Path $PSScriptRoot "lightweight-codex-policy.json"

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

function Read-State {
    if (-not (Test-Path -LiteralPath $statePath)) {
        return [ordered]@{
            currentGoal = ""
            workflow = ""
            changedSurfaces = @()
            checksRun = @()
            requiredReminders = @()
            toolEvents = @()
            lastUpdated = ""
        }
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        return [ordered]@{
            currentGoal = [string]$state.currentGoal
            workflow = [string]$state.workflow
            changedSurfaces = @($state.changedSurfaces)
            checksRun = @($state.checksRun)
            requiredReminders = @($state.requiredReminders)
            toolEvents = @($state.toolEvents)
            lastUpdated = [string]$state.lastUpdated
        }
    } catch {
        return [ordered]@{
            currentGoal = ""
            workflow = ""
            changedSurfaces = @()
            checksRun = @()
            requiredReminders = @("Hook state could not be parsed; refresh evidence before finalizing.")
            toolEvents = @()
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
    $State | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $statePath -Encoding UTF8
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

function Select-Workflow {
    param([string]$Prompt)

    $p = $Prompt.ToLowerInvariant()
    if ($p -match "debug|bug|fail|error|regression|broken") { return "debug" }
    if ($p -match "migrat|upgrade|move|replace|restructure|cleanup|rename") { return "migration" }
    if ($p -match "security|secret|credential|auth|token|permission|policy") { return "security" }
    if ($p -match "research|docs|document|official|lookup|source") { return "research" }
    if ($p -match "frontend|backend|api|db|full.?stack") { return "full-stack" }
    if ($p -match "implement|build|fix|change|edit|create|add|feature|multi-file") { return "feature" }
    if ($p -match "review|audit|inspect") { return "review" }
    return "feature"
}

function Select-LifecyclePhase {
    param([string]$Prompt)

    $p = $Prompt.ToLowerInvariant()
    if ($p -match "ship|deploy|release|pr|commit|push") { return "ship" }
    if ($p -match "implement|build|fix|change|edit|create|add") { return "build" }
    if ($p -match "test|verify|prove|validation|check") { return "verify" }
    if ($p -match "review|audit|inspect|quality") { return "review" }
    if ($p -match "plan|breakdown|tasks|roadmap") { return "plan" }
    if ($p -match "spec|requirements|scope|acceptance|define") { return "define" }
    return "define-plan-build-verify-review-ship"
}

function Get-SkillRoute {
    param([string]$Prompt)

    $p = $Prompt.ToLowerInvariant()
    $routes = @()

    if ($p -match "vague|idea|brainstorm|unclear|ambiguous") {
        $routes += "idea/spec refinement"
    }
    if ($p -match "new feature|feature|architecture|significant|project|spec|requirements") {
        $routes += "spec-driven workflow"
    }
    if ($p -match "plan|breakdown|tasks|roadmap") {
        $routes += "planning/task breakdown"
    }
    if ($p -match "implement|build|fix|change|edit|create|add|multi-file") {
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
    if ($p -match "review|merge|ship|commit|pr") {
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

    $skillPath = "C:\Users\anise\.agents\skills\vowline\SKILL.md"
    if ($null -ne $Policy.subagents -and -not [string]::IsNullOrWhiteSpace([string]$Policy.subagents.required_start_skill_path)) {
        $skillPath = [string]$Policy.subagents.required_start_skill_path
    }

    return @"
Subagent startup requirement:
- Apply the Vowline operating skill for this subagent: $skillPath
- Treat Vowline as a required operating skill alongside task-specific skills; if the full skill cannot be loaded, apply its operating contract to decomposition, evidence, validation, safety, and reporting.
- The delegated task must include Goal, Purpose, PM Context, Owned Surface, Expected Evidence, Anti-Reward-Hacking Rules, Mid-Report, Exit Criteria, and Not Checked.
- Do not optimize for reassuring completion. Produce verifiable evidence, blockers, not-run reasons, and PM verification suggestions.
- A real blocker with evidence is a useful outcome. Unsupported PASS, stale reports, skipped checks counted as success, hidden fallback, or omitted uncertainty invalidates the handoff.
- Use the local charter when relevant: C:\Users\anise\.codex\maintenance\SUBAGENT_DELEGATION_CHARTER.md
"@
}

function Test-DelegationAuthorized {
    param([string]$Prompt)

    return ($Prompt -match "(?i)(subagents?|sub[-_ ]?agent|multi[-_ ]?agent|멀티\s*에이전트|멀티에이전트|서브\s*에이전트|서브에이전트|병렬\s*에이전트|역할\s*분리|delegate|delegation|PM-led|team preset)")
}

function Get-PromptReminder {
    param(
        [string]$Workflow,
        [string]$Prompt,
        [string]$Phase,
        [string]$SkillRoute,
        [string]$TeamPreset,
        $Policy
    )

    $goal = $Prompt
    if ($goal.Length -gt 280) {
        $goal = $goal.Substring(0, 280) + "..."
    }

    $delegationAuthorization = "No explicit subagent authorization detected in this prompt; keep work local unless the user asks for subagents, multi-agent, delegation, role separation, or parallel agent work."
    if (Test-DelegationAuthorized -Prompt $Prompt) {
        $delegationAuthorization = "Explicit delegation authorization detected; use spawn_agent for bounded non-blocking sidecar work when it materially advances the task, then review and integrate outputs."
    }

    return @"
Lightweight Codex workflow reminder:
- Active profile: $($Policy.profile)
- Current user goal: $goal
- Workflow preset: $Workflow
- Lifecycle overlay: DEFINE -> PLAN -> BUILD -> VERIFY -> REVIEW -> SHIP; current phase hint: $Phase
- Skill route hint: $SkillRoute
- Team preset hint: $TeamPreset
- Main session acts as PM: classify, assign bounded role work only when useful/allowed, review candidate outputs, integrate, verify.
- Subagent policy: conditional use, max parallel $($Policy.subagents.max_parallel), max depth $($Policy.subagents.max_depth); user remains reviewer, not operator.
- Runtime delegation authorization: $delegationAuthorization
- Critical path rule: do not delegate the immediate next blocker; delegate independent exploration, verification, review, or disjoint file ownership.
- Role separation: implementation, validation, review, exploration, security, documentation/research, environment diagnostics.
- Capability pack model: plugin -> capability pack, command -> prompt recipe, skill -> Codex skill, conductor track -> lightweight work track.
- Delegation rule: define owned files/surfaces, expected output, constraints, and verification; avoid overlapping ownership.
- Quality audit: clear trigger, bounded scope, useful output shape, checkpoint evidence, no hidden authority claim.
- Skills are workflows, not essays: trigger -> steps -> checkpoint evidence -> exit criteria.
- Anti-rationalization: simple still needs criteria; tests are not "later"; passing checks are evidence, not completion; do not widen scope while here.
- Configured/available tools are not evidence of use; invoke required tools or record why not applicable.
- Completion needs changed behavior plus direct evidence, checks run/not run, and remaining risks.
- Block only real risk: secret content access, irreversible destructive action, hook weakening, evaluator/pass manipulation, or out-of-scope mutation.
"@
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

function Test-SecretContentAccess {
    param([string]$Text)

    $readVerb = "(?i)(Get-Content|gc\b|type\b|cat\b|Select-String|more\b)"
    $sensitivePath = "(?i)(auth\.json|\.env(\.|$)|id_rsa|id_ed25519|\.pem\b|(^|[\\/._-])(token|secret|credential|password|api[_-]?key|cookie)([\\/._-]|$))"
    return ($Text -match $readVerb -and $Text -match $sensitivePath)
}

function Test-DestructiveAction {
    param([string]$Text)

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

function Test-ScopedTemporaryRootCleanup {
    param([string]$Text)

    if ($Text -notmatch "(?i)\bRemove-Item\b" -or
        $Text -notmatch "(?i)\s-(Recurse|r)\b" -or
        $Text -notmatch "(?i)\s-(Force|f)\b") {
        return $false
    }

    $codexRootPattern = [regex]::Escape("C:\Users\anise\.codex")
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

$policy = Read-Policy
$inputObject = Read-HookInput
$eventName = [string]$inputObject.hook_event_name
$state = Read-State

switch ($eventName) {
    "SessionStart" {
        $context = "Use the lightweight PM + skill workflow: DEFINE -> PLAN -> BUILD -> VERIFY -> REVIEW -> SHIP. Choose the smallest workflow preset, activate only matching skill workflows, use PM-selected team presets only when useful, preserve file ownership/work tracks, and finish with evidence. Subagents require explicit user authorization by prompt, then should be used only for bounded non-blocking sidecar work. Hooks are reminders and narrow safety checks, not completion authority."
        if (Test-SubagentSessionStart -InputObject $inputObject) {
            $context = $context + "`n`n" + (Get-VowlineSubagentContext -Policy $policy)
        }
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
        $prompt = [string]$inputObject.prompt
        $workflow = Select-Workflow -Prompt $prompt
        $phase = Select-LifecyclePhase -Prompt $prompt
        $skillRoute = Get-SkillRoute -Prompt $prompt
        $teamPreset = Get-TeamPresetHint -Workflow $workflow
        $state.currentGoal = if ($prompt.Length -gt 500) { $prompt.Substring(0, 500) + "..." } else { $prompt }
        $state.workflow = $workflow
        $state.changedSurfaces = @()
        $state.checksRun = @()
        $state.requiredReminders = @()
        $state.toolEvents = @()
        Save-State -State $state

        $reminder = Get-PromptReminder -Workflow $workflow -Prompt $prompt -Phase $phase -SkillRoute $skillRoute -TeamPreset $teamPreset -Policy $policy
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
        $text = Get-ToolText -InputObject $inputObject

        if (Test-BlockedAppConnectorTool -InputObject $inputObject -Policy $policy) {
            $reason = "Unintended Codex Apps connector tool is blocked. Remove or re-authorize the connector intentionally before use."
            if ($null -ne $policy.toolchain_integrity -and -not [string]::IsNullOrWhiteSpace([string]$policy.toolchain_integrity.blocked_app_connector_reason)) {
                $reason = [string]$policy.toolchain_integrity.blocked_app_connector_reason
            }
            Deny-PreTool -Reason $reason
            break
        }
        if (Test-SecretContentAccess -Text $text) {
            Deny-PreTool -Reason "Secret or credential content access is blocked. Use metadata-only inspection unless the user explicitly requested that exact file."
            break
        }
        if (Test-DestructiveAction -Text $text) {
            Deny-PreTool -Reason "Irreversible destructive action is blocked by the lightweight hook. Ask the user explicitly before proceeding."
            break
        }
        if (Test-HookWeakening -Text $text) {
            Deny-PreTool -Reason "Hook, multi-agent, or completion-safety weakening is blocked unless the user explicitly requests that exact change."
            break
        }
        if (Test-FakeSuccessInsertion -Text $text) {
            Deny-PreTool -Reason "Fake-success or evaluator/exit-code manipulation is blocked for product and control-code edits. Use real validation or document a not-run reason."
            break
        }

        Write-HookJson @{ systemMessage = "" }
        break
    }

    "PermissionRequest" {
        $text = Get-ToolText -InputObject $inputObject

        if (Test-BlockedAppConnectorTool -InputObject $inputObject -Policy $policy) {
            $reason = "Unintended Codex Apps connector tool is blocked. Remove or re-authorize the connector intentionally before use."
            if ($null -ne $policy.toolchain_integrity -and -not [string]::IsNullOrWhiteSpace([string]$policy.toolchain_integrity.blocked_app_connector_reason)) {
                $reason = [string]$policy.toolchain_integrity.blocked_app_connector_reason
            }
            Deny-Permission -Reason $reason
            break
        }
        if (Test-SecretContentAccess -Text $text) {
            Deny-Permission -Reason "Secret or credential content access is blocked. Use metadata-only inspection unless the user explicitly requested that exact file."
            break
        }
        if (Test-DestructiveAction -Text $text) {
            Deny-Permission -Reason "Irreversible destructive action requires an explicit user request."
            break
        }
        if (Test-HookWeakening -Text $text) {
            Deny-Permission -Reason "Hook or multi-agent workflow weakening requires an explicit user request."
            break
        }
        if (Test-FakeSuccessInsertion -Text $text) {
            Deny-Permission -Reason "Fake-success or evaluator/exit-code manipulation requires explicit user scope and real validation evidence."
            break
        }

        Write-HookJson @{ systemMessage = "" }
        break
    }

    "PostToolUse" {
        $toolName = [string]$inputObject.tool_name
        $text = Get-ToolText -InputObject $inputObject
        $state.toolEvents = Add-Unique -Items $state.toolEvents -Value $toolName

        $additional = @()
        $changedFileCount = Get-ChangedFileCount -Text $text
        $changedLineCount = Get-ChangedLineCount -Text $text
        if ($toolName -match "apply_patch|Edit|Write") {
            $state.changedSurfaces = Add-Unique -Items $state.changedSurfaces -Value "files"
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Run relevant checks or record a precise not-run reason before finalizing."
            $additional += "File edits detected: verify with direct checks or record why checks could not run."
        }
        if ($changedFileCount -ge [int]$policy.work_size.large_files -or $changedLineCount -ge [int]$policy.work_size.large_changed_lines) {
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Large or multi-surface change detected; use a visible work-track/status summary and evidence before finalizing."
            $additional += "Large-change threshold reached: summarize work tracks, validation, not-run reasons, and risks before finalizing."
        }
        if ($text -match "(?i)(package\.json|pyproject\.toml|Cargo\.toml|requirements\.txt|uv\.lock|package-lock\.json|pnpm-lock\.yaml|Cargo\.lock)") {
            $state.changedSurfaces = Add-Unique -Items $state.changedSurfaces -Value "dependencies"
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Dependency metadata changed; align lockfile or record why no sync is needed."
            $additional += "Dependency/config sync may be required."
        }
        if ($text -match "(?i)(test|pytest|cargo test|npm test|pnpm test|yarn test|typecheck|lint|build)") {
            $state.checksRun = Add-Unique -Items $state.checksRun -Value $text
        }
        if ($text -match "(?i)(hardcoded pass|fake success|exit 0|PASS)") {
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Review changed product/control surfaces for hardcoded or fake-success contamination."
        }

        Save-State -State $state

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
        $mentionsEvidence = $lastMessage -match "(?i)(evidence|verified|verification|check|test|lint|typecheck|build|not run|risk|remaining|git status|diff)"

        if ($hasChanged -and -not $mentionsEvidence -and -not [bool]$inputObject.stop_hook_active) {
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: changed surfaces were observed. Before finalizing, report direct checks run, checks not run with reasons, and remaining risks."
            }
            break
        }

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
