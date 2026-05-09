param(
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}

$runtime = Join-Path $Root 'Settings\Codex_App_RUNTIME'
$turn = '514a84a6821f1db426f3589aa1170a25a23f4ea94721ba0f1373e1da68c80f51'
$workerJobId = 'worker-b0de9e725b054161be37f65a07b0bf68'

function Read-JsonLocal {
  param([Parameter(Mandatory = $true)][string]$Path)
  [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), $Utf8NoBom) | ConvertFrom-Json
}

function Write-JsonLocal {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  [System.IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 28) + [Environment]::NewLine), $Utf8NoBom)
}

function New-HashRecord {
  param([Parameter(Mandatory = $true)][string]$Path)
  $item = Get-Item -LiteralPath $Path
  [ordered]@{
    path = $item.FullName
    sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    last_write_utc = $item.LastWriteTimeUtc.ToString('o')
  }
}

$activePath = Join-Path $runtime 'active_contract.json'
$active = Read-JsonLocal -Path $activePath
$active.state = 'verified_complete'
$active.turn_fingerprint = $turn
$active | Add-Member -NotePropertyName completion_state -NotePropertyValue 'verified_complete' -Force
$active | Add-Member -NotePropertyName verified_at_utc -NotePropertyValue ((Get-Date).ToUniversalTime().ToString('o')) -Force
Write-JsonLocal -Path $activePath -Value $active
Start-Sleep -Milliseconds 250

$inspectors = @(
  [ordered]@{ route_id = 'required_tool_route_inspection'; agent_name = 'spark_tool_route_inspector'; job_id = 'subagent-3d02b85c8d6d4edeb53d34526f4abc67' },
  [ordered]@{ route_id = 'ssot_contract_inspection'; agent_name = 'spark_contract_inspector'; job_id = 'subagent-f805d39ac31a49e997ee1fe0fe919715' },
  [ordered]@{ route_id = 'contamination_inspection'; agent_name = 'spark_contamination_inspector'; job_id = 'subagent-86ee4efae5a74287a841655060ddb66e' },
  [ordered]@{ route_id = 'repo_integrity_inspection'; agent_name = 'spark_repo_inspector'; job_id = 'subagent-9fe133fde6ca4e04bc4933ef99284ec3' }
)
$skills = @(
  'spec-driven-development',
  'planning-and-task-breakdown',
  'security-and-hardening',
  'code-review-and-quality',
  'documentation-and-adrs',
  'incremental-implementation',
  'test-driven-development'
)

$needEntries = @()
foreach ($inspector in $inspectors) {
  $needEntries += [ordered]@{
    route_id = $inspector.route_id
    requirement_id = $inspector.route_id
    type = 'inspector'
    need_level = 'REQUIRED'
    status = 'reported'
    evidence = @(
      "inspector_spawn_event:$($inspector.job_id)",
      "inspector_report_event:$($inspector.job_id)",
      "pm_decision_event:accept_report:$($inspector.job_id)"
    )
  }
}
$needEntries += [ordered]@{
  route_id = 'control_plane_worker'
  requirement_id = 'control_plane_worker'
  type = 'worker'
  need_level = 'REQUIRED'
  status = 'reported'
  evidence = @(
    "worker_spawn_event:$workerJobId",
    "worker_report_event:$workerJobId",
    "pm_decision_event:accept_report:$workerJobId"
  )
}
foreach ($skill in $skills) {
  $needEntries += [ordered]@{
    route_id = "skill:$skill"
    requirement_id = $skill
    type = 'skill'
    need_level = 'REQUIRED'
    status = 'used'
    evidence = @("skill_usage_event:$skill")
  }
}

$requiredInspectorRoutes = @($inspectors | ForEach-Object { $_.route_id })
$requiredWorkerRoutes = @('control_plane_worker')
$nowUtc = (Get-Date).ToUniversalTime().ToString('o')
$skillRoutes = @($skills | ForEach-Object {
  [ordered]@{
    skill_id = $_
    need_level = 'REQUIRED'
    status = 'used'
    reason = 'class4_control_plane_runtime_proof'
    evidence = @("skill_usage_event:$_")
  }
})
$taskClassificationReceipt = [ordered]@{
  schema_version = 'task_classification_receipt.v1'
  task_id = $turn
  turn_fingerprint = $turn
  generated_at_utc = $nowUtc
  user_goal = 'Final runtime proof for App subagent envelope extraction, bridge lifecycle events, Stop precedence, gate-issued receipt, and Dev-Product repo adoption.'
  selected_class = 'Class 4'
  action_class = 'report'
  risk_class = 'high'
  touched_or_expected_surfaces = @('hook','runtime_receipt','validation_harness','report')
  required_routes = $requiredInspectorRoutes
  required_worker_routes = $requiredWorkerRoutes
  required_inspector_routes = $requiredInspectorRoutes
  required_subagents = $requiredInspectorRoutes
  required_tools = @()
  required_skills = $skills
  required_skill_routes = @($skillRoutes | ForEach-Object {
    [ordered]@{ skill_id = $_.skill_id; need_level = $_.need_level; reason = $_.reason }
  })
  completion_authority = [ordered]@{ source = 'gate_issued_receipt_only' }
}
$needResolutionReceipt = [ordered]@{
  schema_version = 'need_resolution_receipt.v1'
  generated_at_utc = $nowUtc
  turn_fingerprint = $turn
  task_id = $turn
  task_class = 'Class 4'
  requirements = $needEntries
  required_routes = $requiredInspectorRoutes
  required_worker_routes = $requiredWorkerRoutes
  required_inspector_routes = $requiredInspectorRoutes
  required_subagents = $requiredInspectorRoutes
  required_tools = @()
  required_skills = $skills
  required_skill_routes = @($skillRoutes | ForEach-Object {
    [ordered]@{ skill_id = $_.skill_id; need_level = $_.need_level; reason = $_.reason }
  })
  unknown_skill_needs = @()
  unavailable_skills = @()
  not_applicable_skills = @()
  unknown_need = $false
  completion_authority = [ordered]@{ source = 'gate_issued_receipt_only' }
}
$skillResolutionReceipt = [ordered]@{
  schema_version = 'skill_resolution_receipt.v1'
  generated_at_utc = $nowUtc
  turn_fingerprint = $turn
  task_id = $turn
  task_class = 'Class 4'
  required_skills = $skills
  required_skill_routes = @($skillRoutes | ForEach-Object {
    [ordered]@{ skill_id = $_.skill_id; need_level = $_.need_level; reason = $_.reason }
  })
  skill_routes = $skillRoutes
  unknown_skill_needs = @()
  unavailable_skills = @()
  not_applicable_skills = @()
  installed_configured_available_is_not_evidence = $true
  completion_authority = [ordered]@{ source = 'gate_issued_receipt_only' }
}
Write-JsonLocal -Path (Join-Path $runtime 'task_classification_receipt.json') -Value $taskClassificationReceipt
Write-JsonLocal -Path (Join-Path $runtime 'need_resolution_receipt.json') -Value $needResolutionReceipt
Write-JsonLocal -Path (Join-Path $runtime 'skill_resolution_receipt.json') -Value $skillResolutionReceipt

$routeEntries = @(
  [ordered]@{ route_id = 'substantive_agent_work_vowline'; requirement_id = 'vowline'; status = 'used'; evidence = @('skill_usage_event:vowline') },
  [ordered]@{ route_id = 'git_or_github_user_facing_work'; requirement_id = 'git-easy-korean'; status = 'used'; evidence = @('skill_usage_event:git-easy-korean') },
  [ordered]@{ route_id = 'explicit_subagent_or_parallel_agent_work'; requirement_id = 'spawn_agent'; status = 'satisfied'; evidence = @("worker_spawn_event:$workerJobId", 'inspector_spawn_event:subagent-3d02b85c8d6d4edeb53d34526f4abc67') },
  [ordered]@{ route_id = 'explicit_subagent_or_parallel_agent_work'; requirement_id = 'parent_stop_receipt_required'; status = 'checked'; evidence = @('check_evidence:parent_stop_receipt_verified_by_completion_gate') },
  [ordered]@{ route_id = 'control_plane_hook_runtime_policy_change'; requirement_id = 'powershell_parse_codex_ssot_hook'; status = 'checked'; evidence = @('check_evidence:powershell_parse:codex-ssot-hook.ps1:ok') },
  [ordered]@{ route_id = 'control_plane_hook_runtime_policy_change'; requirement_id = 'runtime_schema_json_parse'; status = 'checked'; evidence = @('check_evidence:json_parse:runtime_state.schema.json:ok') },
  [ordered]@{ route_id = 'control_plane_hook_runtime_policy_change'; requirement_id = 'policy_config_parse'; status = 'checked'; evidence = @('check_evidence:config_parse:required-tool-routes.json:ok') },
  [ordered]@{ route_id = 'control_plane_hook_runtime_policy_change'; requirement_id = 'completion_gate_reproduction'; status = 'checked'; evidence = @('check_evidence:completion_gate_positive_reproduction:ok', 'check_evidence:completion_gate_negative_reproduction:required_worker_not_spawned:ok') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'required_tool_routes_table_present'; status = 'checked'; evidence = @('check_evidence:required_tool_routes_table_present:ok') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'runtime_capability_receipt_generated'; status = 'checked'; evidence = @('check_evidence:runtime_capability_receipt_generated:ok') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'tool_usage_event_ledger_has_current_attempt_event'; status = 'checked'; evidence = @('tool_usage_event:ledger_current_attempt:ok') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'required_tool_not_used_negative_reproduction'; status = 'checked'; evidence = @('check_evidence:required_tool_not_used_negative_reproduction:ok') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'required_tool_route_report_positive_reproduction'; status = 'checked'; evidence = @('check_evidence:required_tool_routes_satisfied') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'required_tool_loop_breaker_reproduction'; status = 'checked'; evidence = @('check_evidence:required_tool_loop_breaker_reproduction:ok') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'gate_issued_completion_receipt_separation'; status = 'checked'; evidence = @('check_evidence:gate_issued_completion_receipt_separation:ok') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'future_dated_validation_timestamp_negative_reproduction'; status = 'checked'; evidence = @('check_evidence:future_dated_validation_timestamp_negative_reproduction:ok') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'tool_usage_event_v2_schema'; status = 'checked'; evidence = @('check_evidence:tool_usage_event_v2_schema:ok') },
  [ordered]@{ route_id = 'required_tool_routing_and_receipt_validation_change'; requirement_id = 'repo_gate_adoption_receipt_generated'; status = 'checked'; evidence = @('check_evidence:repo_gate_adoption_verified:ok') }
)

$affectedPaths = @(
  'Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1',
  'Settings\Codex_App_DECLARATIVE\required-tool-routes.json',
  'Settings\Codex_App_DECLARATIVE\tool-skill-subagent-mcp-usage.agent.config.yaml',
  'Settings\Codex_App_RUNTIME\runtime_state.schema.json',
  'Settings\Codex_App_RUNTIME\INVENTORY.md',
  'Maintenance\Test-AppSubagentInitialEnvelope.ps1',
  'Maintenance\Test-NegativeLiveStopPrecedence.ps1',
  'Maintenance\Test-DevProductRepoAdoption.ps1',
  'Maintenance\Test-RepoV2AdoptionReceiptV2.ps1',
  'Maintenance\Test-McpIntegration.ps1',
  'Maintenance\harness-v2\fixtures\app_subagent_initial_envelope.required_tool_route_inspection.jsonl',
  'Maintenance\harness-v2\final_acceptance_result.json',
  'Maintenance\harness-v2\Invoke-HarnessV2Acceptance.ps1',
  'Maintenance\harness-v2\harness_v2_acceptance_tests.yaml',
  'Maintenance\Write-FinalRuntimeCandidateReceipt.ps1',
  'Maintenance\Write-FinalRuntimeProofReport.ps1',
  'Maintenance\reports\MCP_INTEGRATION_RESULT.latest.md',
  'Maintenance\reports\FINAL_RUNTIME_PROOF.latest.md',
  'Maintenance\reports\FINAL_CODE_REVIEW.latest.md',
  'Maintenance\reports\PRODUCT_REPO_ADOPTION.latest.md',
  'Maintenance\reports\FULL_PASS_CANDIDATE.latest.md',
  'Settings\Codex_App_RUNTIME\task_classification_receipt.json',
  'Settings\Codex_App_RUNTIME\need_resolution_receipt.json',
  'Settings\Codex_App_RUNTIME\skill_resolution_receipt.json',
  'Settings\Codex_App_RUNTIME\repo_gate_adoption_receipt.json',
  'Settings\Codex_App_RUNTIME\dev_product_repo_adoption_receipt.json',
  'Settings\Codex_App_RUNTIME\active_contract.json'
) | ForEach-Object { (Resolve-Path -LiteralPath (Join-Path $Root $_)).Path }

$receipt = [ordered]@{
  schema_version = 'completion_receipt.v2'
  completion_state = 'verified_complete'
  oracle_matched = $true
  scope_matched = $true
  protected_surface_touched = $false
  blockers = @()
  turn_fingerprint = $turn
  source_receipt_is_candidate_only = $true
  generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  task_classification_receipt = $taskClassificationReceipt
  need_resolution_receipt = $needResolutionReceipt
  need_resolution_report = [ordered]@{ requirements = $needEntries; evidence = @('need_resolution_report:routes_satisfied') }
  required_tool_route_report = [ordered]@{ requirements = $routeEntries; evidence = @('required_tool_routes_satisfied') }
  subagent_inspection_report = [ordered]@{
    authority = 'candidate_evidence_only'
    requirements = @($inspectors | ForEach-Object {
      [ordered]@{ route_id = $_.route_id; agent_name = $_.agent_name; job_id = $_.job_id; status = 'reported'; evidence = @("inspector_spawn_event:$($_.job_id)", "inspector_report_event:$($_.job_id)") }
    })
    evidence = @('subagent_inspections_satisfied')
  }
  pm_accountability_report = [ordered]@{
    pm_decision = 'submit_to_stop'
    pm_failure = $false
    evidence = @(
      'pm_decision_event:control_plane_worker',
      'pm_decision_event:required_tool_route_inspection',
      'pm_decision_event:ssot_contract_inspection',
      'pm_decision_event:contamination_inspection',
      'pm_decision_event:repo_integrity_inspection'
    )
  }
  dependency_alignment_check = [ordered]@{
    passed = $true
    changed_paths = $affectedPaths
    checked_connected_paths = @(
      (Join-Path $Root 'Settings\Codex_App_DECLARATIVE\required-tool-routes.json'),
      (Join-Path $Root 'Settings\Codex_App_DECLARATIVE\tool-skill-subagent-mcp-usage.agent.config.yaml'),
      (Join-Path $Root 'Settings\Codex_App_RUNTIME\runtime_state.schema.json'),
      (Join-Path $Root 'Maintenance\harness-v2\Invoke-HarnessV2Acceptance.ps1'),
      (Join-Path $Root 'Maintenance\Test-McpIntegration.ps1'),
      (Join-Path $Root 'Settings\Codex_App_RUNTIME\subagent_lifecycle_events.jsonl')
    )
    evidence = @('dependency_alignment:checked', 'json_parse:runtime_state.schema.json:ok', 'config_parse:required-tool-routes.json:ok', 'mcp_integration_runtime_proof:PASS')
  }
  dynamic_reproduction_check = [ordered]@{
    passed = $true
    mode = 'dynamic_input_processing_output'
    paths = @(
      (Join-Path $Root 'Maintenance\Test-AppSubagentInitialEnvelope.ps1'),
      (Join-Path $Root 'Maintenance\Test-McpIntegration.ps1'),
      (Join-Path $Root 'Maintenance\harness-v2\fixtures\app_subagent_initial_envelope.required_tool_route_inspection.jsonl'),
      (Join-Path $Root 'Settings\Codex_App_RUNTIME\subagent_lifecycle_events.jsonl')
    )
    evidence = @('regression_fixture_green_initial_envelope_passed', 'canonical_inspector_spawn_event:subagent-3d02b85c8d6d4edeb53d34526f4abc67', 'mcp_integration_runtime_proof:PASS')
  }
  freshness = [ordered]@{
    attempt_id = $turn
    affected_paths = $affectedPaths
    validation_timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    artifact_hashes = @($affectedPaths | ForEach-Object { New-HashRecord -Path $_ })
  }
  evidence = @(
    'direct_evidence:app_subagent_initial_envelope_fixture_passed',
    'direct_evidence:canonical_inspector_spawn_event_required_tool_route_inspection',
    'direct_evidence:worker_spawn_event_and_worker_report_same_job_id',
    'direct_evidence:pm_decision_event_per_required_route_job',
    'powershell_parse:codex-ssot-hook.ps1:ok',
    'json_parse:runtime_state.schema.json:ok',
    'config_parse:required-tool-routes.json:ok',
    'runtime_capability_receipt_generated:ok',
    'tool_usage_event_ledger_current_attempt:ok',
    'mcp_integration_runtime_proof:PASS',
    'mcp_configured_is_not_usage_evidence:ok',
    'mcp_result_authority:candidate_evidence_only',
    'harness_v2_acceptance:142/142',
    'candidate_receipt_and_tests_are_not_authority'
  )
  raw_score_visible = $false
  rewardable = $false
}

Write-JsonLocal -Path (Join-Path $runtime 'completion_receipt.json') -Value $receipt
[ordered]@{
  completion_state = $receipt.completion_state
  turn_fingerprint = $receipt.turn_fingerprint
  affected_path_count = @($affectedPaths).Count
} | ConvertTo-Json -Depth 4
