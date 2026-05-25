$ErrorActionPreference = "Stop"
$script:HookScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $script:HookScriptRoot "lib\lightweight-codex-core.ps1")
. (Join-Path $script:HookScriptRoot "lib\lightweight-codex-workflow.ps1")
. (Join-Path $script:HookScriptRoot "lib\lightweight-codex-guards.ps1")

$policy = Read-Policy
$inputObject = Read-HookInput
$eventName = [string]$inputObject.hook_event_name
$state = Normalize-WorkflowState -State (Read-State)

try {
switch ($eventName) {
    "SessionStart" {
        $context = "Use the lightweight PM + skill workflow: DEFINE -> PLAN -> BUILD -> VERIFY -> REVIEW -> SHIP. Choose the smallest workflow preset, activate only matching skill workflows, use PM-selected team presets only when useful, preserve file ownership/work tracks, and finish with evidence. Calibration source: CALIBRATION.md. Treat selected answers, diagnoses, plans, and patch rationales as candidate until direct evidence supports them; do not imply unchecked claims are verified. Subagents require user authorization; AGENTS.md records standing authorization mirrored by config.toml developer_instructions, and prompt phrases can also authorize a current goal. Use subagents only for bounded non-blocking sidecar work. Goal is a long-running tracking marker only; PM owns parent-goal completion, and subagents produce evidence only. Hooks are reminders and narrow safety checks, not completion authority. When memento MCP tools are exposed, call context(workspace='global_pm') at session start, read get_skill_guide when tool behavior is unclear, use recall before hook/MCP/toolchain or prior-state work, send tool_feedback for recall results, and write only durable verified atomic memory through the PM write gate. Memento is support-only and legacy Memory/RAG paths are not active fallback."
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
        $state.skillRoute = $skillRoute
        $state.skillEvidenceRequired = Test-SkillEvidenceRequired -SkillRoute $skillRoute
        $state.toolchainHint = $toolchainHint
        $state.memoryRoute = $memoryRoute
        $state.changedSurfaces = @()
        $state.checksRun = @()
        $state.autonomousHarnessChecks = @()
        $state.skillEvents = @()
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
        if ([bool]$state.skillEvidenceRequired) {
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Skill workflow evidence required: record SKILL_EVIDENCE used/not_used with reason, direct evidence, and residual risk."
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

        $preChangedFileCount = Get-ChangedFileCount -Text $text
        $preChangedLineCount = Get-ChangedLineCount -Text $text
        $preAdjustment = Get-ToolTaskAdjustment -Stage "PreToolUse" -ToolName $toolName -Text $text -ChangedFileCount $preChangedFileCount -ChangedLineCount $preChangedLineCount -Policy $policy
        $preAdjusted = Apply-TaskLevelAdjustment -State $state -Adjustment $preAdjustment
        if ($preAdjusted) {
            Save-State -State $state
            Write-CodexStructuredLog -EventName "PreToolUse" -Outcome "level_adjusted" -Reason "$($state.taskClass);$($preAdjustment.reason)" -ToolName $toolName | Out-Null
        }

        Write-CodexStructuredLog -EventName "PreToolUse" -Outcome "observed" -ToolName $toolName | Out-Null
        if ($preAdjusted) {
            Write-HookJson @{ systemMessage = "Task level adjusted to $($state.taskClass) from PreToolUse evidence; include compatibility impact review in final verification." }
        } else {
            Write-HookJson @{ systemMessage = "" }
        }
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
        $skillEvidence = Get-SkillEvidenceSummary -ToolName $toolName -Text $text -SkillRoute ([string]$state.skillRoute)
        if (-not [string]::IsNullOrWhiteSpace($skillEvidence)) {
            $state.skillEvents = Add-Unique -Items $state.skillEvents -Value $skillEvidence
            $additional += "Skill workflow evidence observed: final audit must accept this evidence or record SKILL_EVIDENCE not_used with reason, direct evidence, and residual risk."
        }
        $isSubagentTool = $toolName -match "(?i)(^|\.)(spawn_agent|wait_agent|send_input|close_agent|resume_agent)$"
        if ($isSubagentTool) {
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
        $postAdjustment = Get-ToolTaskAdjustment -Stage "PostToolUse" -ToolName $toolName -Text $text -ChangedFileCount $changedFileCount -ChangedLineCount $changedLineCount -Policy $policy
        if (Apply-TaskLevelAdjustment -State $state -Adjustment $postAdjustment) {
            $additional += "Task level adjusted to $($state.taskClass) from PostToolUse evidence; include compatibility impact review."
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

        if (Test-AutonomousHarnessCheckRequired -ToolName $toolName -Text $text) {
            $state.changedSurfaces = Add-Unique -Items $state.changedSurfaces -Value "control-plane"
            $logChangedSurfaces += "control-plane"
            $state.requiredReminders = Add-Unique -Items $state.requiredReminders -Value "Autonomous harness checks invoked for control-plane edits; confirm doctor/verify evidence before finalizing."

            $doctorEvidence = Invoke-AutonomousHarnessCheck -Mode "doctor" -TimeoutSeconds 45
            $verifyEvidence = Invoke-AutonomousHarnessCheck -Mode "verify" -TimeoutSeconds 600
            foreach ($evidence in @($doctorEvidence, $verifyEvidence)) {
                $state.checksRun = Add-Unique -Items $state.checksRun -Value $evidence
                $state.autonomousHarnessChecks = Add-Unique -Items $state.autonomousHarnessChecks -Value $evidence
                $logValidationResults += $evidence
            }
            $additional += "Autonomous harness checks invoked for control-plane edit: doctor plus bounded verify. Use recorded logs or rerun verify directly if the autonomous verify timed out."
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
        $mustEnforceWorkflowEvidence = $hasSubstantiveActivity -or [bool]$state.anomalyPauseExpected -or [bool]$state.subagentDecisionRequired -or [bool]$state.watcherExpected
        $auditReady = Test-FinalAuditReady -Message $lastMessage
        $watcherReady = Test-WatcherCoverageReady -State $state -Message $lastMessage
        $anomalyTraceReady = Test-AnomalyTraceReady -State $state -Message $lastMessage
        $subagentDecisionReady = Test-SubagentDecisionReady -State $state -Message $lastMessage
        $skillEvidenceReady = Test-SkillEvidenceReady -State $state -Message $lastMessage

        if ($mustEnforceWorkflowEvidence -and -not $anomalyTraceReady -and -not [bool]$inputObject.stop_hook_active) {
            $reason = "Anomaly pause/trace evidence missing for an L4 workflow incident."
            Write-CodexStructuredLog -EventName "Stop" -Outcome "not_ready" -Reason $reason -NotReadyReason $reason -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) -SubagentResult @($state.subagentEvents) | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: an anomaly-calibration workflow was active. Before finalizing, state the pause/trace trigger, first mismatch/root cause, verification or blocked/continue status, and residual risk."
            }
            break
        }

        if ($mustEnforceWorkflowEvidence -and -not $subagentDecisionReady -and -not [bool]$inputObject.stop_hook_active) {
            $reason = "Subagent call declaration missing after explicit subagent authorization."
            Write-CodexStructuredLog -EventName "Stop" -Outcome "not_ready" -Reason $reason -NotReadyReason $reason -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) -SubagentResult @($state.subagentEvents) | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: subagent use was explicitly authorized or a subagent tool event was observed. Before finalizing, include SUBAGENT_CALL used/not_used with reason, direct evidence, and residual risk, even if task_class was unavailable."
            }
            break
        }

        if ($mustEnforceWorkflowEvidence -and -not $watcherReady -and -not [bool]$inputObject.stop_hook_active) {
            $reason = "Watcher or subagent evidence missing for an L4 delegated workflow incident."
            Write-CodexStructuredLog -EventName "Stop" -Outcome "not_ready" -Reason $reason -NotReadyReason $reason -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) -SubagentResult @($state.subagentEvents) | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: this prompt was classified as L4 with delegation authorized. Before finalizing, include accepted/rejected subagent evidence plus WATCHER_REPORT, or record WATCHER_NOT_USED with reason, risk, substitute check, and confidence impact."
            }
            break
        }

        if (([bool]$state.skillEvidenceRequired -or @($state.skillEvents).Count -gt 0) -and -not $skillEvidenceReady -and -not [bool]$inputObject.stop_hook_active) {
            $reason = "Skill workflow evidence missing after routed skill workflow."
            Write-CodexStructuredLog -EventName "Stop" -Outcome "not_ready" -Reason $reason -NotReadyReason $reason -ChangedSurface @($state.changedSurfaces) -ValidationResult @($state.checksRun) -SubagentResult @($state.subagentEvents) | Out-Null
            Write-HookJson @{
                decision = "block"
                reason = "Final preflight: skill workflow evidence missing after matching skill workflows were routed or observed. Before finalizing, include SKILL_EVIDENCE used/not_used with reason, direct evidence, and residual risk."
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
