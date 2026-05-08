param(
  [string]$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hookPath = Join-Path $Root 'Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1'
$schemaPath = Join-Path $Root 'Settings\Codex_App_RUNTIME\runtime_state.schema.json'
$routesPath = Join-Path $Root 'Settings\Codex_App_DECLARATIVE\required-tool-routes.json'
$codexConfigPath = Join-Path $HOME '.codex\config.toml'

$hook = [System.IO.File]::ReadAllText($hookPath)
$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
$routes = Get-Content -LiteralPath $routesPath -Raw | ConvertFrom-Json
$codexConfig = if (Test-Path -LiteralPath $codexConfigPath -PathType Leaf) { [System.IO.File]::ReadAllText($codexConfigPath) } else { '' }

$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($hookPath, [ref]$null, [ref]$parseErrors)

function Get-FunctionText {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $match = [regex]::Match($Text, "(?ms)^function\s+$([regex]::Escape($Name))\s*\{(?<body>.*?)(?=^function\s+\S+\s*\{|^switch\s*\(|\z)")
  if ($match.Success) { return $match.Value }
  ''
}

$workerSpawnFunction = Get-FunctionText -Text $hook -Name 'Test-WorkerSpawnObserved'
$inspectorSpawnFunction = Get-FunctionText -Text $hook -Name 'Test-SubagentSpawnObserved'
$completionGateFunction = Get-FunctionText -Text $hook -Name 'Test-CompletionGate'
$acceptanceRunnerPath = Join-Path $Root 'Maintenance\harness-v2\Invoke-HarnessV2Acceptance.ps1'
$acceptanceRunner = [System.IO.File]::ReadAllText($acceptanceRunnerPath)

$workerRouteConfig = @($routes.worker_routes.routes)
$workerRouteSchemaText = [string]$schema.subagent_worker_job_schema.route_id
$requiredWorkerRoutes = @('implementation_worker','control_plane_worker','frontend_worker','backend_worker')
$missingWorkerRoutes = @($requiredWorkerRoutes | Where-Object { $workerRouteConfig -notcontains $_ -or $workerRouteSchemaText -notmatch [regex]::Escape($_) })

$lifecycleRecordTypes = [string]$schema.subagent_lifecycle_event_schema.record_type
$canonicalRecordTypesPresent = @(
  'subagent_spawn_event',
  'inspector_spawn_event',
  'subagent_report_event',
  'worker_spawn_event',
  'worker_report_event'
) | Where-Object { $lifecycleRecordTypes -match [regex]::Escape($_) }

$checks = [ordered]@{
  hook_ast_parse_ok = @($parseErrors).Count -eq 0
  worker_spawn_observed_requires_lifecycle_event = $workerSpawnFunction.Contains("Name 'record_type') -eq 'worker_spawn_event'") -and $workerSpawnFunction.Contains("Name 'event_type') -eq 'worker_spawn_event'") -and $workerSpawnFunction.Contains("Name 'parent_turn_id') -eq `$TurnFingerprint") -and $workerSpawnFunction.Contains("Name 'agent_role') -eq 'worker'") -and $workerSpawnFunction -notmatch "spawn_event_id"
  inspector_spawn_observed_requires_lifecycle_event = $inspectorSpawnFunction.Contains("Name 'record_type') -eq 'inspector_spawn_event'") -and $inspectorSpawnFunction.Contains("Name 'agent_role') -eq 'inspector'") -and $inspectorSpawnFunction -notmatch "spawn_event_id"
  textual_worker_spawn_claim_rejected = $hook -notmatch '\$isCanonicalWorkerSpawn\s*=' -and $hook -notmatch "record_type\\s\*.*worker_spawn_event"
  textual_inspector_spawn_claim_rejected = $hook -notmatch "record_type\\s\*.*subagent_spawn_event\|event\\s\*.*subagent_spawn"
  codex_app_subagent_spawn_bridge_reads_session_meta = $hook -match 'thread_source' -and $hook -match 'Get-CodexAppRecentSubagentSessions' -and $hook -match 'source_thread_id'
  codex_app_subagent_spawn_bridge_requires_matching_job = $hook -match 'Find-CodexAppSubagentSpawnJobMatch' -and $hook -match 'matched_prescheduled_job' -and $hook -match 'unmatched_subagent_spawn_observed'
  unmatched_codex_app_spawn_never_becomes_worker_spawn = $hook -match "eventType = if \(\`$matched\)" -and $hook -match "'unmatched_subagent_spawn_observed'" -and $hook -match "recordType = if \(\`$matched -and \`$role -eq 'worker'\)"
  runtime_identity_receipt_writer_present = $hook -match 'function Write-RuntimeIdentityReceipt' -and $hook -match 'runtime_identity_receipts\.jsonl' -and $hook -match 'Resolve-EffectiveProjectRoot'
  hook_surface_probe_writer_present = $hook -match 'function Write-HookSurfaceProbe' -and $hook -match 'hook_surface_probe\.jsonl' -and $hook -match 'stdout_hash'
  runtime_identity_schema_registered = [string]$schema.state_files.runtime_identity_receipts -match 'runtime_identity_receipts\.jsonl' -and [string]$schema.runtime_identity_receipt_schema.schema_version -eq 'runtime_identity_receipt.v1'
  hook_surface_probe_schema_registered = [string]$schema.state_files.hook_surface_probe -match 'hook_surface_probe\.jsonl' -and [string]$schema.hook_surface_probe_schema.schema_version -eq 'hook_surface_probe.v1'
  worker_report_without_job_id_rejected = $hook -match "if \(\`$isWorkerReport -and \[string\]::IsNullOrWhiteSpace\(\`$jobId\)\)"
  worker_report_spawn_match_requires_same_job_id = $hook -match 'Test-WorkerSpawnObserved .* -JobId \$jobId' -and $workerSpawnFunction -match '\$JobId' -and $workerSpawnFunction -match "Name 'job_id'\) -eq \`$JobId"
  inspector_report_without_job_id_rejected = $hook -match "if \(\`$event -in @\('subagent_spawn','subagent_report'\) -and \[string\]::IsNullOrWhiteSpace\(\`$jobId\)\)"
  pm_decision_ledger_required = $hook -match 'Read-PmDecisionEvents -Root \$Root -TurnFingerprint \$turn' -and $hook -match "reason = 'pm_decision_missing'"
  stop_orchestration_failures_precede_direct_evidence = $completionGateFunction.IndexOf('Test-TaskClassificationAndNeedForCompletion') -ge 0 -and $completionGateFunction.IndexOf('Test-TaskClassificationAndNeedForCompletion') -lt $completionGateFunction.IndexOf("reason = 'direct_evidence_missing'") -and $completionGateFunction.IndexOf('Test-PmAccountabilityForCompletion') -ge 0 -and $completionGateFunction.IndexOf('Test-PmAccountabilityForCompletion') -lt $completionGateFunction.IndexOf("reason = 'direct_evidence_missing'")
  configured_skill_not_evidence = $hook -match 'installed_skill_not_evidence' -and $hook -match 'skill_usage_event\|explicit_unavailable\|explicit_not_applicable'
  configured_tool_route_not_evidence = $hook -notmatch '\$corpusParts \+= \$routesDoc\.evidence' -and $hook -match 'tool_usage_event\|skill_usage_event\|subagent_spawn_event\|worker_spawn_event'
  canonical_lifecycle_schema_has_spawn_and_report = $canonicalRecordTypesPresent.Count -eq 5 -and ([string]$schema.subagent_lifecycle_event_schema.event_type -match 'unmatched_subagent_spawn_observed')
  worker_routes_aligned_in_config_and_schema = $missingWorkerRoutes.Count -eq 0
  max_threads_depth_semantics = $codexConfig -match '(?ms)\[agents\].*?max_threads\s*=\s*8' -and $codexConfig -match '(?ms)\[agents\].*?max_depth\s*=\s*1'
  acceptance_result_written_atomically = $acceptanceRunner -match 'final_acceptance_result\.json' -and $acceptanceRunner -match 'command_run_timestamp_utc' -and $acceptanceRunner -match 'test_count' -and $acceptanceRunner -match 'pass_count' -and $acceptanceRunner -match 'fail_count' -and $acceptanceRunner -match 'Move-Item'
}

$failed = @($checks.GetEnumerator() | Where-Object { -not [bool]$_.Value })
$result = [ordered]@{
  schema_version = 'pm_orchestration_runtime_evidence_test.v1'
  status = if ($failed.Count -eq 0) { 'passed' } else { 'failed' }
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  root = $Root
  checks = $checks
  missing_worker_routes = $missingWorkerRoutes
  parse_errors = @($parseErrors | ForEach-Object { $_.Message })
}

$result | ConvertTo-Json -Depth 8
if ($failed.Count -gt 0) {
  exit 1
}
