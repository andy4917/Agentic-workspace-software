param(
  [string]$PolicyPath = (Join-Path $PSScriptRoot 'harness_v2_policy.yaml'),
  [string]$TestsPath = (Join-Path $PSScriptRoot 'harness_v2_acceptance_tests.yaml')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CaseValue {
  param(
    [Parameter(Mandatory = $true)][object]$Case,
    [Parameter(Mandatory = $true)][string]$Name,
    [object]$Default = $null
  )

  if ($Case.PSObject.Properties.Name -contains $Name) {
    return $Case.$Name
  }

  $Default
}

function Get-CaseBool {
  param(
    [Parameter(Mandatory = $true)][object]$Case,
    [Parameter(Mandatory = $true)][string]$Name
  )

  [bool](Get-CaseValue -Case $Case -Name $Name -Default $false)
}

function New-Decision {
  param(
    [Parameter(Mandatory = $true)][string]$Severity,
    [Parameter(Mandatory = $true)][string]$Decision,
    [Parameter(Mandatory = $true)][string]$ReasonCode
  )

  [pscustomobject]@{
    severity = $Severity
    decision = $Decision
    reason_code = $ReasonCode
  }
}

function Write-JsonFileAtomically {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )

  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }

  $tempPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('n') + '.tmp')
  $json = ($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine
  [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding -ArgumentList $false))
  Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

function Invoke-HarnessV2Decision {
  param([Parameter(Mandatory = $true)][object]$Case)

  $event = [string](Get-CaseValue -Case $Case -Name 'event' -Default '')
  $taskType = [string](Get-CaseValue -Case $Case -Name 'task_type' -Default '')
  $actionClass = [string](Get-CaseValue -Case $Case -Name 'action_class' -Default '')
  $surfaceClass = [string](Get-CaseValue -Case $Case -Name 'surface_class' -Default '')

  if (Get-CaseBool -Case $Case -Name 'credential_or_secret_touch') {
    return New-Decision -Severity 'BLOCKED' -Decision 'BLOCK' -ReasonCode 'credential_or_secret_touch'
  }

  if (Get-CaseBool -Case $Case -Name 'destructive_side_effect') {
    return New-Decision -Severity 'BLOCKED' -Decision 'BLOCK' -ReasonCode 'destructive_side_effect_without_explicit_scope'
  }

  if (Get-CaseBool -Case $Case -Name 'unauthorized_control_plane_mutation') {
    return New-Decision -Severity 'BLOCKED' -Decision 'BLOCK' -ReasonCode 'unauthorized_control_plane_mutation'
  }

  if (Get-CaseBool -Case $Case -Name 'hook_disable_or_weaken_bypass') {
    return New-Decision -Severity 'BLOCKED' -Decision 'BLOCK' -ReasonCode 'hook_disable_weaken_or_bypass'
  }

  if (Get-CaseBool -Case $Case -Name 'evaluator_manipulation') {
    return New-Decision -Severity 'BLOCKED' -Decision 'BLOCK' -ReasonCode 'evaluator_pass_fail_manipulation'
  }

  if (Get-CaseBool -Case $Case -Name 'product_fake_success_shortcut') {
    return New-Decision -Severity 'BLOCKED' -Decision 'BLOCK' -ReasonCode 'product_fake_success_shortcut'
  }

  if (Get-CaseBool -Case $Case -Name 'fake_test_report') {
    return New-Decision -Severity 'BLOCKED' -Decision 'BLOCK' -ReasonCode 'fake_test_report'
  }

  if ($event -eq 'UserPromptSubmit') {
    if (Get-CaseBool -Case $Case -Name 'dry_run') {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'dry_run_no_turn_invalidation'
    }

    if (
      (Get-CaseValue -Case $Case -Name 'subagent_max_threads' -Default $null) -eq 8 -and
      (Get-CaseValue -Case $Case -Name 'subagent_max_depth' -Default $null) -eq 1
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'subagent_concurrency_policy_satisfied'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'explicit_worker_delegation') -and
      [string](Get-CaseValue -Case $Case -Name 'worker_primary_model' -Default '') -eq 'latest-main' -and
      [string](Get-CaseValue -Case $Case -Name 'worker_preferred_model' -Default '') -eq 'gpt-5.5' -and
      [string](Get-CaseValue -Case $Case -Name 'worker_reasoning_effort' -Default '') -eq 'medium' -and
      [string](Get-CaseValue -Case $Case -Name 'worker_sandbox_mode' -Default '') -eq 'workspace-write-scoped' -and
      [string](Get-CaseValue -Case $Case -Name 'worker_authority' -Default '') -eq 'candidate_artifact_only' -and
      (Get-CaseValue -Case $Case -Name 'worker_max_depth' -Default $null) -eq 1
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'worker_policy_satisfied'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'worker_route_catalog_check') -and
      @(Get-CaseValue -Case $Case -Name 'worker_routes' -Default @()) -contains 'control_plane_worker'
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'worker_route_catalog_satisfied'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'manifest_worker_ledger_catalog_check') -and
      @(Get-CaseValue -Case $Case -Name 'manifest_ledgers' -Default @()) -contains 'worker_job_ledger' -and
      @(Get-CaseValue -Case $Case -Name 'manifest_ledgers' -Default @()) -contains 'worker_report_ledger'
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'manifest_worker_ledgers_registered'
    }

    if (Get-CaseBool -Case $Case -Name 'current_turn_regenerates_task_and_need_receipts') {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'current_turn_receipts_regenerated'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'korean_operational_gate_worktree_intent') -and
      [string](Get-CaseValue -Case $Case -Name 'expected_task_class' -Default '') -eq 'Class 3' -and
      @(Get-CaseValue -Case $Case -Name 'expected_worker_routes' -Default @()) -contains 'control_plane_worker' -and
      @(Get-CaseValue -Case $Case -Name 'expected_inspector_routes' -Default @()) -contains 'ssot_contract_inspection'
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'korean_operational_gate_intent_classified_class3'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'child_worker_prompt') -and
      -not (Get-CaseBool -Case $Case -Name 'child_prompt_attempts_parent_active_contract_overwrite') -and
      [string](Get-CaseValue -Case $Case -Name 'parent_active_contract_id' -Default '') -ne '' -and
      [string](Get-CaseValue -Case $Case -Name 'child_active_contract_id' -Default '') -ne '' -and
      [string](Get-CaseValue -Case $Case -Name 'parent_active_contract_id' -Default '') -ne [string](Get-CaseValue -Case $Case -Name 'child_active_contract_id' -Default '')
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'parent_child_active_contracts_separated'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'explicit_subagent_inspection') -and
      [string](Get-CaseValue -Case $Case -Name 'inspector_model' -Default '') -eq 'gpt-5.3-codex-spark' -and
      [string](Get-CaseValue -Case $Case -Name 'inspector_fallback_model' -Default '') -eq 'latest-mini' -and
      [string](Get-CaseValue -Case $Case -Name 'inspector_reasoning_effort' -Default '') -eq 'high' -and
      [string](Get-CaseValue -Case $Case -Name 'inspector_sandbox_mode' -Default '') -eq 'read-only' -and
      [string](Get-CaseValue -Case $Case -Name 'inspector_authority' -Default '') -eq 'candidate_evidence_only' -and
      (Get-CaseValue -Case $Case -Name 'inspector_max_depth' -Default $null) -eq 1
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'inspector_policy_satisfied'
    }

    if (Get-CaseBool -Case $Case -Name 'explicit_subagent_inspection') {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'inspector_job_queued'
    }

    if (Get-CaseBool -Case $Case -Name 'ordinary_without_explicit_inspection') {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'no_inspector_job'
    }

    return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'prompt_observed'
  }

  if ($event -eq 'PreToolUse') {
    if (Get-CaseBool -Case $Case -Name 'scope_ambiguous') {
      return New-Decision -Severity 'ASK' -Decision 'ASK' -ReasonCode 'scope_confirmation_required'
    }

    if ((Get-CaseBool -Case $Case -Name 'class3_or_class4_mutating_action') -and (Get-CaseBool -Case $Case -Name 'pm_orchestration_preflight_missing')) {
      return New-Decision -Severity 'BLOCKED' -Decision 'BLOCKED' -ReasonCode 'pm_orchestration_preflight_missing'
    }

    if ((Get-CaseBool -Case $Case -Name 'class3_or_class4_mutating_action') -and (Get-CaseBool -Case $Case -Name 'required_subagent_jobs_not_scheduled')) {
      return New-Decision -Severity 'BLOCKED' -Decision 'BLOCKED' -ReasonCode 'required_subagent_jobs_not_scheduled'
    }

    if (Get-CaseBool -Case $Case -Name 'policy_terms_heuristic') {
      return New-Decision -Severity 'SUSPECT' -Decision 'ALLOW' -ReasonCode 'policy_terms_suspect_review'
    }

    if (Get-CaseBool -Case $Case -Name 'changelog_terms_heuristic') {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'documentation_terms_observed'
    }

    if (Get-CaseBool -Case $Case -Name 'negative_fixture_terms_heuristic') {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'negative_fixture_terms_observed'
    }

    if ((Get-CaseBool -Case $Case -Name 'class3_or_class4_mutating_action') -and (Get-CaseBool -Case $Case -Name 'required_subagent_jobs_scheduled')) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'pm_orchestration_preflight_satisfied'
    }

    if (Get-CaseBool -Case $Case -Name 'control_plane_repair_path_not_allowed') {
      return New-Decision -Severity 'BLOCKED' -Decision 'BLOCKED' -ReasonCode 'control_plane_repair_path_not_allowed'
    }

    if ($actionClass -eq 'read' -and (Get-CaseBool -Case $Case -Name 'runtime_reference')) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'read_only_runtime_reference'
    }

    if ($actionClass -eq 'read' -and (Get-CaseBool -Case $Case -Name 'user_mentioned_reference')) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'user_mentioned_reference_read'
    }

    if ($surfaceClass -eq 'non_runtime_record') {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'non_runtime_record'
    }

    if ($taskType -eq 'control_plane_repair' -and (Get-CaseBool -Case $Case -Name 'authorized_control_plane_repair')) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'authorized_control_plane_repair'
    }

    if ((Get-CaseValue -Case $Case -Name 'in_user_scope' -Default $true) -eq $false) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'path_scope_observed'
    }

    if ($taskType -eq 'code_implementation') {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'normal_implementation_work'
    }

    return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'action_observed'
  }

  if ($event -eq 'PostToolUse') {
    if (Get-CaseBool -Case $Case -Name 'codex_app_subagent_session') {
      $hasMatchedJob =
        (Get-CaseBool -Case $Case -Name 'thread_source_subagent') -and
        (Get-CaseBool -Case $Case -Name 'source_thread_id') -and
        (Get-CaseBool -Case $Case -Name 'scheduled_subagent_job_exists') -and
        (Get-CaseBool -Case $Case -Name 'matching_parent_turn_id') -and
        (Get-CaseBool -Case $Case -Name 'matching_attempt_id') -and
        (Get-CaseBool -Case $Case -Name 'matching_route_id') -and
        (Get-CaseBool -Case $Case -Name 'matching_agent_role') -and
        (Get-CaseBool -Case $Case -Name 'normalized_target_paths_match') -and
        (Get-CaseBool -Case $Case -Name 'timestamp_window_match') -and
        (Get-CaseBool -Case $Case -Name 'ledger_required_fields_present')

      if ($hasMatchedJob -and (Get-CaseBool -Case $Case -Name 'agent_role_worker')) {
        return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'worker_spawn_recorded_candidate_artifact_only'
      }

      if ($hasMatchedJob -and (Get-CaseBool -Case $Case -Name 'agent_role_inspector')) {
        return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'inspector_spawn_recorded_candidate_evidence_only'
      }

      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'unmatched_subagent_spawn_observed'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'subagent_spawn_event') -and
      (Get-CaseBool -Case $Case -Name 'ledger_required_fields_present')
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'subagent_spawn_recorded_candidate_only'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'worker_spawn_event') -and
      (Get-CaseBool -Case $Case -Name 'ledger_required_fields_present') -and
      [string](Get-CaseValue -Case $Case -Name 'worker_authority' -Default '') -eq 'candidate_artifact_only'
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'worker_spawn_recorded_candidate_artifact_only'
    }

    if ((Get-CaseBool -Case $Case -Name 'subagent_report_event') -and (Get-CaseBool -Case $Case -Name 'ledger_required_fields_present')) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'subagent_report_recorded_candidate_only'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'worker_report_event') -and
      (Get-CaseBool -Case $Case -Name 'ledger_required_fields_present') -and
      [string](Get-CaseValue -Case $Case -Name 'worker_authority' -Default '') -eq 'candidate_artifact_only'
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'worker_report_recorded_candidate_artifact_only'
    }

    if ((Get-CaseBool -Case $Case -Name 'subagent_close_event') -and (Get-CaseBool -Case $Case -Name 'ledger_required_fields_present')) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'subagent_closed_after_route_resolution'
    }

    return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'append_only_observation'
  }

  if ($event -eq 'Stop') {
    $completionClaim = Get-CaseBool -Case $Case -Name 'completion_claim'
    if (-not $completionClaim) {
      if ($taskType -eq 'image_generation' -and (Get-CaseBool -Case $Case -Name 'generated_file_exists')) {
        return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'image_artifact_observed'
      }

      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'non_final_response'
    }

    if (Get-CaseBool -Case $Case -Name 'task_classification_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'task_classification_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'task_classification_unknown') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'task_classification_unknown'
    }

    if (Get-CaseBool -Case $Case -Name 'task_classification_downshift_detected') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'task_classification_downshift_detected'
    }

    if (Get-CaseBool -Case $Case -Name 'need_resolution_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'need_resolution_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'need_resolution_unknown') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'need_resolution_unknown'
    }

    if (Get-CaseBool -Case $Case -Name 'skill_resolution_receipt_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'skill_resolution_receipt_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'skill_need_unknown') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'skill_need_unknown'
    }

    if (Get-CaseBool -Case $Case -Name 'route_need_unknown') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'route_need_unknown'
    }

    if (Get-CaseBool -Case $Case -Name 'required_route_unsatisfied') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_route_unsatisfied'
    }

    if (Get-CaseBool -Case $Case -Name 'parent_active_contract_overwritten_by_child') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'parent_active_contract_overwritten_by_child'
    }

    if (Get-CaseBool -Case $Case -Name 'manifest_worker_ledgers_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'manifest_worker_ledgers_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'candidate_receipt') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'candidate_receipt_has_no_authority'
    }

    if (Get-CaseBool -Case $Case -Name 'installed_skill_not_used') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'installed_skill_not_evidence'
    }

    if (Get-CaseBool -Case $Case -Name 'user_instruction_ignored') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'user_instruction_ignored'
    }

    if (Get-CaseBool -Case $Case -Name 'required_route_not_used') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_route_not_used'
    }

    if (Get-CaseBool -Case $Case -Name 'required_subagent_not_spawned') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_subagent_not_spawned'
    }

    $workerWaiverValid =
      (Get-CaseBool -Case $Case -Name 'worker_waiver_recorded') -and
      (Get-CaseBool -Case $Case -Name 'waiver_reason') -and
      (Get-CaseBool -Case $Case -Name 'waiver_scope') -and
      (Get-CaseBool -Case $Case -Name 'waiver_expiry_current_turn') -and
      (Get-CaseBool -Case $Case -Name 'waiver_replacement_evidence') -and
      (Get-CaseBool -Case $Case -Name 'waiver_residual_risk')

    if (
      $workerWaiverValid -and
      (Get-CaseBool -Case $Case -Name 'checks_evidence') -and
      (Get-CaseBool -Case $Case -Name 'gate_issued_receipt') -and
      (Get-CaseBool -Case $Case -Name 'stop_receipt_authority')
    ) {
      if ($taskType -eq 'code_implementation') {
        return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW_COMPLETE_CLAIM' -ReasonCode 'worker_route_waived_with_replacement_evidence'
      }

      if (
        $taskType -eq 'control_plane_repair' -and
        (Get-CaseBool -Case $Case -Name 'runtime_inspector_report') -and
        (Get-CaseBool -Case $Case -Name 'parser_checks')
      ) {
        return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW_COMPLETE_CLAIM' -ReasonCode 'pm_self_work_waiver_with_runtime_evidence'
      }
    }

    if ($workerWaiverValid -and $taskType -eq 'control_plane_repair') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'pm_worker_waiver_runtime_evidence_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'required_worker_not_spawned') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_worker_not_spawned'
    }

    if (Get-CaseBool -Case $Case -Name 'plain_echoed_spawn_text') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_worker_not_spawned'
    }

    if (Get-CaseBool -Case $Case -Name 'canonical_spawn_event_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_worker_not_spawned'
    }

    if (Get-CaseBool -Case $Case -Name 'inspector_only_delegation_for_mutating_task') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'inspector_only_delegation_for_mutating_task'
    }

    if (Get-CaseBool -Case $Case -Name 'worker_required_skill_not_used') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'worker_required_skill_not_used'
    }

    if (Get-CaseBool -Case $Case -Name 'worker_report_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'worker_report_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'pm_collapsed_worker_route_into_inspector_route') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'pm_collapsed_worker_route_into_inspector_route'
    }

    if (Get-CaseBool -Case $Case -Name 'required_skill_not_used') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_skill_not_used'
    }

    if (Get-CaseBool -Case $Case -Name 'subagent_report_contains_only_pass') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_report_not_evidence'
    }

    if (Get-CaseBool -Case $Case -Name 'subagent_report_without_job_id') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_report_without_job_id'
    }

    if (Get-CaseBool -Case $Case -Name 'subagent_report_invalid_envelope') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_report_invalid_envelope'
    }

    if (Get-CaseBool -Case $Case -Name 'subagent_fake_test_report') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_report_terminated'
    }

    if (Get-CaseBool -Case $Case -Name 'subagent_report_quarantined') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_report_quarantined'
    }

    if (Get-CaseBool -Case $Case -Name 'subagent_report_terminated') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_report_terminated'
    }

    if (Get-CaseBool -Case $Case -Name 'pm_adopted_quarantined_report') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'pm_adopted_tainted_subagent_output'
    }

    if (Get-CaseBool -Case $Case -Name 'pm_adopted_unverified_subagent_report') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'pm_adopted_unverified_subagent_report'
    }

    if (Get-CaseBool -Case $Case -Name 'pm_failed_to_replace_failed_worker') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'pm_failed_to_replace_failed_worker'
    }

    if (Get-CaseBool -Case $Case -Name 'repeated_missing_evidence_second_strike') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_report_terminated'
    }

    if (Get-CaseBool -Case $Case -Name 'replacement_limit_reached') {
      return New-Decision -Severity 'STOP_AND_REPORT' -Decision 'STOP_AND_REPORT' -ReasonCode 'replacement_limit_reached'
    }

    if (Get-CaseBool -Case $Case -Name 'replacement_clean_report') {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW_COMPLETE_CLAIM' -ReasonCode 'route_satisfied_candidate_evidence'
    }

    if (Get-CaseBool -Case $Case -Name 'subagent_report_not_reviewed') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_report_not_reviewed'
    }

    if (Get-CaseBool -Case $Case -Name 'unresolved_inspector_findings') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'unresolved_inspector_findings'
    }

    if (Get-CaseBool -Case $Case -Name 'pm_aggregation_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'pm_aggregation_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'pm_decision_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'pm_decision_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'premature_completion_claim') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'premature_completion_claim'
    }

    if (Get-CaseBool -Case $Case -Name 'ignored_stop_gate') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'ignored_stop_gate'
    }

    if (Get-CaseBool -Case $Case -Name 'pm_shifted_blame_to_worker') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'pm_shifted_blame_to_worker'
    }

    if (Get-CaseBool -Case $Case -Name 'repeated_pm_failure') {
      return New-Decision -Severity 'STOP_AND_REPORT' -Decision 'STOP_AND_REPORT' -ReasonCode 'repeated_pm_failure'
    }

    if (Get-CaseBool -Case $Case -Name 'bare_pass_fail_claim') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'bare_pass_fail_claim'
    }

    if (Get-CaseBool -Case $Case -Name 'subagent_pass_only') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_candidate_only'
    }

    if (Get-CaseBool -Case $Case -Name 'stale_receipt') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'stale_completion_receipt'
    }

    if (Get-CaseBool -Case $Case -Name 'future_dated_receipt') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'future_dated_validation_timestamp'
    }

    if (Get-CaseBool -Case $Case -Name 'direct_evidence_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'direct_evidence_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'repo_v2_adoption_receipt_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'repo_v2_adoption_receipt_missing'
    }

    if (Get-CaseBool -Case $Case -Name 'repo_v2_gate_decision_conflict') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'repo_v2_gate_decision_conflict'
    }

    if (Get-CaseBool -Case $Case -Name 'repo_v2_handoff_not_ready') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'repo_v2_handoff_not_ready'
    }

    if (Get-CaseBool -Case $Case -Name 'repo_v2_contamination_scan_failed') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'repo_v2_contamination_scan_failed'
    }

    if (Get-CaseBool -Case $Case -Name 'missing_required_tool_route') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_tool_not_used'
    }

    if (Get-CaseBool -Case $Case -Name 'required_subagent_not_spawned') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_subagent_not_spawned'
    }

    if (Get-CaseBool -Case $Case -Name 'subagent_report_missing') {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'subagent_report_missing'
    }

    if ((Get-CaseBool -Case $Case -Name 'candidate_reports_only') -and -not (Get-CaseBool -Case $Case -Name 'gate_issued_receipt')) {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'gate_issued_completion_receipt_missing'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'skill_unavailable') -and
      (Get-CaseBool -Case $Case -Name 'skill_unavailable_reason') -and
      (Get-CaseBool -Case $Case -Name 'skill_unavailable_scope') -and
      (Get-CaseBool -Case $Case -Name 'replacement_scope_evidence') -and
      (Get-CaseBool -Case $Case -Name 'gate_issued_receipt')
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW_COMPLETE_CLAIM' -ReasonCode 'skill_unavailable_with_scope_evidence'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'skill_optional') -and
      (Get-CaseBool -Case $Case -Name 'class1_document_change') -and
      (Get-CaseBool -Case $Case -Name 'evidence_complete') -and
      (Get-CaseBool -Case $Case -Name 'gate_issued_receipt')
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW_COMPLETE_CLAIM' -ReasonCode 'verified_complete'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'skill_catalog_words_only') -and
      -not (Get-CaseBool -Case $Case -Name 'frontend_backend_route_required') -and
      (Get-CaseBool -Case $Case -Name 'evidence_complete') -and
      (Get-CaseBool -Case $Case -Name 'gate_issued_receipt')
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW_COMPLETE_CLAIM' -ReasonCode 'verified_complete'
    }

    if (
      (Get-CaseBool -Case $Case -Name 'worker_spawn_event') -and
      (Get-CaseBool -Case $Case -Name 'worker_report_event') -and
      (Get-CaseBool -Case $Case -Name 'subagent_spawn_event') -and
      (Get-CaseBool -Case $Case -Name 'subagent_report_event') -and
      (Get-CaseBool -Case $Case -Name 'canonical_spawn_event') -and
      (Get-CaseBool -Case $Case -Name 'gate_issued_receipt')
    ) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW_COMPLETE_CLAIM' -ReasonCode 'worker_and_inspector_routes_satisfied'
    }

    if ((Get-CaseBool -Case $Case -Name 'control_plane_repair_completion') -and -not ((Get-CaseBool -Case $Case -Name 'contract_inspector_report') -or (Get-CaseBool -Case $Case -Name 'subagent_not_applicable_evidence'))) {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_subagent_not_spawned'
    }

    if ((Get-CaseBool -Case $Case -Name 'repo_adoption_completion') -and -not (Get-CaseBool -Case $Case -Name 'repo_inspector_report')) {
      return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'required_subagent_not_spawned'
    }

    if ((Get-CaseBool -Case $Case -Name 'evidence_complete') -and (Get-CaseBool -Case $Case -Name 'gate_issued_receipt')) {
      return New-Decision -Severity 'OBSERVE' -Decision 'ALLOW_COMPLETE_CLAIM' -ReasonCode 'verified_complete'
    }

    return New-Decision -Severity 'DO_NOT_CLAIM_COMPLETE' -Decision 'DENY_COMPLETE_CLAIM' -ReasonCode 'completion_evidence_incomplete'
  }

  New-Decision -Severity 'OBSERVE' -Decision 'ALLOW' -ReasonCode 'event_observed'
}

if (-not (Get-Command yq -ErrorAction SilentlyContinue)) {
  throw 'yq is required to parse harness V2 YAML acceptance tests.'
}

if (-not (Test-Path -LiteralPath $PolicyPath)) {
  throw "Policy file not found: $PolicyPath"
}

if (-not (Test-Path -LiteralPath $TestsPath)) {
  throw "Acceptance test file not found: $TestsPath"
}

$policy = (& yq -o=json '.' $PolicyPath) | ConvertFrom-Json
$testsDoc = (& yq -o=json '.' $TestsPath) | ConvertFrom-Json
$knownSeverities = @($policy.severity.PSObject.Properties.Value | ForEach-Object { [string]$_ })
$results = @()
$commandRunTimestampUtc = (Get-Date).ToUniversalTime().ToString('o')

foreach ($case in @($testsDoc.test_cases)) {
  $actual = Invoke-HarnessV2Decision -Case $case
  if ($knownSeverities -notcontains $actual.severity) {
    throw "Unknown severity '$($actual.severity)' for case '$($case.id)'."
  }

  $expected = $case.expected
  $passed =
    $actual.severity -eq [string]$expected.severity -and
    $actual.decision -eq [string]$expected.decision -and
    $actual.reason_code -eq [string]$expected.reason_code

  $results += [pscustomobject]@{
    id = [string]$case.id
    passed = $passed
    expected_severity = [string]$expected.severity
    actual_severity = $actual.severity
    expected_decision = [string]$expected.decision
    actual_decision = $actual.decision
    expected_reason_code = [string]$expected.reason_code
    actual_reason_code = $actual.reason_code
  }
}

$failed = @($results | Where-Object { -not $_.passed })
$skillUsageCaseNames = @(
  'installed_skill_not_used',
  'required_skill_not_used',
  'skill_resolution_receipt_missing',
  'skill_need_unknown',
  'worker_required_skill_not_used',
  'skill_unavailable',
  'subagent_not_applicable_evidence',
  'skill_optional',
  'skill_catalog_words_only',
  'current_turn_regenerates_task_and_need_receipts',
  'candidate_receipt'
)
$skillUsageCaseIds = @(
  $testsDoc.test_cases | Where-Object {
    $casePropertyNames = @($_.PSObject.Properties.Name)
    $matched = $false
    foreach ($name in $skillUsageCaseNames) {
      if (
        $casePropertyNames -contains $name -and
        (Get-CaseBool -Case $_ -Name $name) -and
        ($name -ne 'candidate_receipt' -or (Get-CaseBool -Case $_ -Name 'completion_claim'))
      ) {
        $matched = $true
        break
      }
    }
    $matched
  } | ForEach-Object { [string]$_.id }
)
$skillUsageSummary = [pscustomobject]@{
  schema_version = 'skill_usage_summary.v1'
  case_count = $skillUsageCaseIds.Count
  case_ids = $skillUsageCaseIds
}
$summary = [pscustomobject]@{
  schema_version = 'harness_v2_acceptance_report.v1'
  policy = (Resolve-Path -LiteralPath $PolicyPath).Path
  tests = (Resolve-Path -LiteralPath $TestsPath).Path
  command_run_timestamp_utc = $commandRunTimestampUtc
  test_count = $results.Count
  pass_count = ($results.Count - $failed.Count)
  fail_count = $failed.Count
  total = $results.Count
  passed = ($results.Count - $failed.Count)
  failed = $failed.Count
  required_outputs = [pscustomobject]@{
    skill_usage_summary = $skillUsageSummary
  }
  results = $results
}

$finalResultPath = Join-Path $PSScriptRoot 'final_acceptance_result.json'
$previousResult = $null
if (Test-Path -LiteralPath $finalResultPath -PathType Leaf) {
  try {
    $previousResult = Get-Content -LiteralPath $finalResultPath -Raw | ConvertFrom-Json
  } catch {
    $previousResult = $null
  }
}
$previousTimestamp = if ($previousResult -and ($previousResult.PSObject.Properties.Name -contains 'command_run_timestamp_utc')) {
  [string]$previousResult.command_run_timestamp_utc
} elseif ($previousResult -and ($previousResult.PSObject.Properties.Name -contains 'checked_at_utc')) {
  [string]$previousResult.checked_at_utc
} else {
  ''
}
$previousResultStale = $false
if (-not [string]::IsNullOrWhiteSpace($previousTimestamp)) {
  try {
    $previousResultStale = ([datetime]$previousTimestamp).ToUniversalTime() -lt ([datetime]$commandRunTimestampUtc).ToUniversalTime()
  } catch {
    $previousResultStale = $true
  }
}
$finalResult = [pscustomobject]@{
  schema_version = 'harness_v2_final_acceptance_result.v1'
  command_run_timestamp_utc = $commandRunTimestampUtc
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  status = if ($failed.Count -eq 0) { 'verified_candidate_evidence' } else { 'failed_candidate_evidence' }
  completion_authority = 'none'
  stale = $false
  stale_acceptance_result_detected = $previousResultStale
  test_count = $results.Count
  pass_count = ($results.Count - $failed.Count)
  fail_count = $failed.Count
  acceptance = [pscustomobject]@{
    harness_v2_total = $results.Count
    harness_v2_passed = ($results.Count - $failed.Count)
    harness_v2_failed = $failed.Count
    skill_usage_case_count = $skillUsageCaseIds.Count
  }
  required_outputs = [pscustomobject]@{
    skill_usage_summary = $skillUsageSummary
  }
  failed_cases = @($failed | ForEach-Object { $_.id })
  policy = (Resolve-Path -LiteralPath $PolicyPath).Path
  tests = (Resolve-Path -LiteralPath $TestsPath).Path
  known_limits = @(
    'This result file is candidate evidence only and is not a gate-issued completion receipt.',
    'The acceptance runner writes this file atomically from the same command output it prints.'
  )
}
Write-JsonFileAtomically -Path $finalResultPath -Value $finalResult

$summary | ConvertTo-Json -Depth 8

if ($failed.Count -gt 0) {
  exit 1
}
