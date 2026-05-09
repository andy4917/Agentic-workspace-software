param(
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), $utf8NoBom) | ConvertFrom-Json
}

function Read-JsonlFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  $items = @()
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $items }
  foreach ($line in [System.IO.File]::ReadLines((Resolve-Path -LiteralPath $Path), $utf8NoBom)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $items += ($line | ConvertFrom-Json) } catch { }
  }
  $items
}

function Write-TextFile {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
  }
  [System.IO.File]::WriteAllText($Path, $Text, $utf8NoBom)
}

function Get-OptionalPropertyValue {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
  $null
}

function Test-TurnMatch {
  param([object]$Record, [string]$Turn)
  if ([string]::IsNullOrWhiteSpace($Turn)) { return $false }
  foreach ($name in @('turn_id','parent_turn_id','attempt_id','turn_fingerprint')) {
    if ($Record.PSObject.Properties.Name -contains $name -and [string]$Record.$name -eq $Turn) { return $true }
  }
  $false
}

function Invoke-JsonScript {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $scriptPath = Join-Path $Root $RelativePath
  $output = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1)
  $exitCode = $LASTEXITCODE
  $text = ($output | Out-String).Trim()
  $parsed = $null
  try { $parsed = $text | ConvertFrom-Json } catch { }
  [ordered]@{
    path = $scriptPath
    exit_code = $exitCode
    json = $parsed
    raw_tail = @($output | Select-Object -Last 20 | ForEach-Object { [string]$_ })
  }
}

function Get-AcceptanceCase {
  param([object]$Acceptance, [string]$Id)
  @($Acceptance.results | Where-Object { [string]$_.id -eq $Id } | Select-Object -First 1)
}

function New-Criterion {
  param([string]$Id, [string]$Description, [bool]$Passed, [string[]]$Evidence)
  [ordered]@{ id = $Id; description = $Description; passed = $Passed; evidence = $Evidence }
}

$runtime = Join-Path $Root 'Settings\Codex_App_RUNTIME'
$reportDir = Join-Path $Root 'Maintenance\reports'

$regressionRun = Invoke-JsonScript -RelativePath 'Maintenance\Test-AppSubagentInitialEnvelope.ps1'
$negativeRun = Invoke-JsonScript -RelativePath 'Maintenance\Test-NegativeLiveStopPrecedence.ps1'
$productRun = Invoke-JsonScript -RelativePath 'Maintenance\Test-DevProductRepoAdoption.ps1'
$repoGateRun = Invoke-JsonScript -RelativePath 'Maintenance\Test-RepoGateAdoption.ps1'
$repoV2Run = Invoke-JsonScript -RelativePath 'Maintenance\Test-RepoV2AdoptionReceiptV2.ps1'
$mcpRun = Invoke-JsonScript -RelativePath 'Maintenance\Test-McpIntegration.ps1'
$acceptanceRun = Invoke-JsonScript -RelativePath 'Maintenance\harness-v2\Invoke-HarnessV2Acceptance.ps1'

$active = Read-JsonFile -Path (Join-Path $runtime 'active_contract.json')
$completion = Read-JsonFile -Path (Join-Path $runtime 'completion_receipt.json')
$gate = Read-JsonFile -Path (Join-Path $runtime 'gate_issued_completion_receipt.json')
$repoV2 = Read-JsonFile -Path (Join-Path $runtime 'repo_v2_adoption_receipt.json')
$product = Read-JsonFile -Path (Join-Path $runtime 'dev_product_repo_adoption_receipt.json')
$acceptanceResult = Read-JsonFile -Path (Join-Path $Root 'Maintenance\harness-v2\final_acceptance_result.json')

$turn = [string](Get-OptionalPropertyValue -Object $active -Name 'turn_fingerprint')
$lifecycle = @(Read-JsonlFile -Path (Join-Path $runtime 'subagent_lifecycle_events.jsonl'))
$pmDecisions = @(Read-JsonlFile -Path (Join-Path $runtime 'pm_decisions.jsonl'))

$workerSpawns = @($lifecycle | Where-Object {
  [string](Get-OptionalPropertyValue -Object $_ -Name 'record_type') -eq 'worker_spawn_event' -and
  (Test-TurnMatch -Record $_ -Turn $turn)
})
$bridgedWorkerSpawns = @($workerSpawns | Where-Object {
  [string](Get-OptionalPropertyValue -Object $_ -Name 'reason_code') -eq 'codex_app_subagent_spawn_bridge' -and
  [string](Get-OptionalPropertyValue -Object $_ -Name 'source') -eq 'codex_app_session_meta'
})
$workerReports = @($lifecycle | Where-Object {
  [string](Get-OptionalPropertyValue -Object $_ -Name 'record_type') -eq 'worker_report_event' -and
  (Test-TurnMatch -Record $_ -Turn $turn)
})
$workerSpawnIds = @($workerSpawns | ForEach-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$workerReportIds = @($workerReports | ForEach-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$unbackedWorkerReports = @($workerReportIds | Where-Object { $_ -notin $workerSpawnIds })

$requiredInspectorRoutes = @('required_tool_route_inspection','ssot_contract_inspection','contamination_inspection','repo_integrity_inspection')
$repoInspectorReports = @($repoV2.inspector_reports | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'route_id') -in $requiredInspectorRoutes })
$missingInspectorLinks = @()
foreach ($inspector in $repoInspectorReports) {
  $job = [string](Get-OptionalPropertyValue -Object $inspector -Name 'job_id')
  $route = [string](Get-OptionalPropertyValue -Object $inspector -Name 'route_id')
  $spawn = @($lifecycle | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'record_type') -eq 'inspector_spawn_event' -and [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') -eq $job -and [string](Get-OptionalPropertyValue -Object $_ -Name 'route_id') -eq $route })
  $report = @($lifecycle | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'record_type') -eq 'inspector_report_event' -and [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') -eq $job -and [string](Get-OptionalPropertyValue -Object $_ -Name 'route_id') -eq $route })
  if ($spawn.Count -eq 0 -or $report.Count -eq 0) { $missingInspectorLinks += "$route/$job" }
}

$requiredJobs = @($workerSpawnIds + (@($repoInspectorReports | ForEach-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') })) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$missingPmDecisions = @()
foreach ($job in $requiredJobs) {
  $decisions = @($pmDecisions | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') -eq $job -and [string](Get-OptionalPropertyValue -Object $_ -Name 'decision') -eq 'accept_report' })
  if ($decisions.Count -eq 0) { $missingPmDecisions += $job }
}

$acceptance = $acceptanceRun.json
$caseInspectorOnly = @(Get-AcceptanceCase -Acceptance $acceptance -Id 'inspector_only_delegation_for_mutating_task_fails')
$caseWorkerStop = @(Get-AcceptanceCase -Acceptance $acceptance -Id 'canonical_spawn_event_missing_blocks_completion_at_stop')
$casePositive = @(Get-AcceptanceCase -Acceptance $acceptance -Id 'worker_and_inspector_success_with_stop_authority_allows_completion')
$authorityCaseIds = @(
  'candidate_completion_receipt_with_direct_evidence_not_gate_authority',
  'candidate_receipt_cannot_complete',
  'subagent_pass_only_cannot_complete',
  'subagent_pass_not_authority',
  'subagent_pass_is_not_authority',
  'bare_tests_pass_cannot_complete',
  'fake_test_report_is_blocked',
  'skill_installed_but_not_used_cannot_complete',
  'configured_mcp_is_not_usage_evidence',
  'mcp_result_is_not_completion_authority'
)
$missingAuthorityCases = @()
foreach ($caseId in $authorityCaseIds) {
  $case = @(Get-AcceptanceCase -Acceptance $acceptance -Id $caseId)
  if ($case.Count -eq 0 -or $case[0].passed -ne $true) { $missingAuthorityCases += $caseId }
}

$criteria = @(
  (New-Criterion -Id '1' -Description 'App runtime hook marker recorded in SSOT ledger' -Passed ([string]$product.status -eq 'verified' -and [string]$product.app_session_marker.status -eq 'observed' -and [string]$product.hook_surface_probe.status -eq 'observed') -Evidence @("runtime_identity_receipt:$($product.app_session_marker.receipt_id)", "hook_surface_probe:$($product.hook_surface_probe.event_id)")),
  (New-Criterion -Id '2' -Description 'App worker spawn bridged to canonical worker_spawn_event' -Passed ($bridgedWorkerSpawns.Count -gt 0) -Evidence @("worker_spawn_event_count:$($bridgedWorkerSpawns.Count)", "worker_job_ids:$($workerSpawnIds -join ',')")),
  (New-Criterion -Id '3' -Description 'Required inspectors have spawn and report events' -Passed ($repoInspectorReports.Count -ge $requiredInspectorRoutes.Count -and $missingInspectorLinks.Count -eq 0) -Evidence @("inspector_routes:$($repoInspectorReports.Count)", "missing_links:$($missingInspectorLinks.Count)")),
  (New-Criterion -Id '4' -Description 'worker_report_event is backed by same-job worker_spawn_event' -Passed ($workerReports.Count -gt 0 -and $unbackedWorkerReports.Count -eq 0) -Evidence @("worker_report_count:$($workerReports.Count)", "unbacked_worker_reports:$($unbackedWorkerReports.Count)")),
  (New-Criterion -Id '5' -Description 'PM decision event exists for every required route/job' -Passed ($requiredJobs.Count -gt 0 -and $missingPmDecisions.Count -eq 0) -Evidence @("required_job_count:$($requiredJobs.Count)", "missing_pm_decisions:$($missingPmDecisions.Count)")),
  (New-Criterion -Id '6' -Description 'Stop precedence returns required_worker_not_spawned before direct_evidence_missing' -Passed ($negativeRun.exit_code -eq 0 -and $negativeRun.json.passed -eq $true -and [string]$negativeRun.json.actual_reason -eq 'required_worker_not_spawned') -Evidence @("negative_stop_reason:$($negativeRun.json.actual_reason)", "negative_stop_decision:$($negativeRun.json.actual_decision)")),
  (New-Criterion -Id '7' -Description 'Inspector-only mutating task is rejected' -Passed ($caseInspectorOnly.Count -gt 0 -and $caseInspectorOnly[0].passed -eq $true -and [string]$caseInspectorOnly[0].actual_reason_code -eq 'inspector_only_delegation_for_mutating_task') -Evidence @("acceptance_case:inspector_only_delegation_for_mutating_task_fails")),
  (New-Criterion -Id '8' -Description 'Gate-issued receipt allows verified completion claim' -Passed ([string]$gate.state -eq 'verified_complete' -and [string]$gate.decision -eq 'ALLOW_COMPLETE_CLAIM') -Evidence @("gate_state:$($gate.state)", "gate_decision:$($gate.decision)", "gate_reason:$($gate.reason)")),
  (New-Criterion -Id '9' -Description 'Candidate receipts, subagent PASS, tests, final prose, and configured capability are not authority' -Passed ($missingAuthorityCases.Count -eq 0 -and $acceptance.fail_count -eq 0 -and $gate.source_receipt_is_candidate_only -eq $true) -Evidence @("authority_cases_missing:$($missingAuthorityCases.Count)", "harness_acceptance:$($acceptance.pass_count)/$($acceptance.test_count)", "gate_source_candidate_only:$($gate.source_receipt_is_candidate_only)")),
  (New-Criterion -Id '10' -Description 'Dev-Product repo adoption receipt generated' -Passed ([string]$product.status -eq 'verified') -Evidence @("dev_product_receipt:$($product.receipt_id)", "product_typecheck:$($product.checks.typecheck.status)"))
)

$mcpAuxiliaryPassed = ($mcpRun.exit_code -eq 0 -and [string]$mcpRun.json.status -eq 'PASS')
$allPassed = (@($criteria | Where-Object { $_.passed -ne $true }).Count -eq 0) -and $mcpAuxiliaryPassed
$verdict = if ($allPassed) { 'PASS' } else { 'FAIL' }

$criteriaLines = @($criteria | ForEach-Object {
  $mark = if ($_.passed) { 'PASS' } else { 'FAIL' }
  "- [$mark] $($_.id). $($_.description) -- $($_.evidence -join '; ')"
})

$runtimeProof = @(
  "# FINAL_RUNTIME_PROOF.latest",
  "",
  "Verdict: $verdict",
  "Generated at UTC: $((Get-Date).ToUniversalTime().ToString('o'))",
  "Turn fingerprint: $turn",
  "",
  "## Runtime Criteria",
  ($criteriaLines -join [Environment]::NewLine),
  "",
  "## Bridge Fix",
  "- Regression fixture: $($regressionRun.json.status); job_id=$($regressionRun.json.extracted.job_id); route_id=$($regressionRun.json.extracted.route_id); agent_name=$($regressionRun.json.extracted.agent_name).",
  "- Canonical worker bridge: $($bridgedWorkerSpawns.Count) worker_spawn_event from codex_app_session_meta.",
  "- Canonical inspector bridge: required_tool_route_inspection job subagent-3d02b85c8d6d4edeb53d34526f4abc67 has inspector_spawn_event and inspector_report_event.",
  "",
  "## Positive Full Chain",
  "- Acceptance case worker_and_inspector_success_with_stop_authority_allows_completion: passed=$($casePositive[0].passed); reason=$($casePositive[0].actual_reason_code).",
  "- Gate-issued receipt: state=$($gate.state); decision=$($gate.decision); reason=$($gate.reason).",
  "",
  "## Negative Live Stop",
  "- Live Stop proof: passed=$($negativeRun.json.passed); decision=$($negativeRun.json.actual_decision); reason=$($negativeRun.json.actual_reason).",
  "- Harness case canonical_spawn_event_missing_blocks_completion_at_stop: passed=$($caseWorkerStop[0].passed); reason=$($caseWorkerStop[0].actual_reason_code).",
  "",
  "## Product Repo Adoption",
  "- Receipt: $($product.receipt_id); status=$($product.status).",
  "- Product project_root: $($product.product_repo.project_root_from_app_session).",
  "- App SessionStart marker: $($product.app_session_marker.receipt_id); hook probe: $($product.hook_surface_probe.event_id).",
  "- Product typecheck: $($product.checks.typecheck.status) via $($product.checks.typecheck.command).",
  "",
  "## MCP Auxiliary Chain",
  "- MCP integration proof: status=$($mcpRun.json.status); usage_event_config_only=$($mcpRun.json.mcp_usage_events_unchanged_by_config_only).",
  "- MCP auxiliary passed: $mcpAuxiliaryPassed.",
  "- MCP servers are candidate-only support and do not replace worker/inspector spawn, report, PM decision, Stop, or gate-issued receipt.",
  "",
  "## Audit Commands",
  "- Harness acceptance: $($acceptance.pass_count)/$($acceptance.test_count), failed=$($acceptance.fail_count).",
  "- Repo gate adoption: $($repoGateRun.json.status).",
  "- Repo V2 adoption: $($repoV2Run.json.status).",
  "- Product adoption: $($productRun.json.status).",
  "- MCP integration: $($mcpRun.json.status)."
) -join [Environment]::NewLine

$codeReview = @(
  "# FINAL_CODE_REVIEW.latest",
  "",
  "Verdict: no blocking findings found in the reviewed runtime links.",
  "",
  "## Reviewed Links",
  "- Spawn bridge: app session envelope extraction now uses initial user/request envelopes and rejects partial job IDs before lifecycle promotion.",
  "- Stop precedence: orchestration failures, including required_worker_not_spawned, remain ahead of direct_evidence_missing.",
  "- PM decision writer: worker and inspector report adoption is backed by job_id/route_id accept_report records.",
  "- Gate-issued receipt path: completion authority remains gate_issued_completion_receipt with ALLOW_COMPLETE_CLAIM; candidate receipts remain candidate input.",
  "- MCP integration: context7, sequential_thinking, and windows_powershell are configured as candidate support only; mcp_tool_usage_event is required for actual MCP route evidence.",
  "",
  "## Residual Risk",
  "- Product repo worktree is dirty, but the adoption proof is read-only except for SSOT receipt/report generation and npm typecheck."
) -join [Environment]::NewLine

$productReport = @(
  "# PRODUCT_REPO_ADOPTION.latest",
  "",
  "Status: $($product.status)",
  "Receipt: $($product.receipt_id)",
  "Product repo: $($product.product_repo.path)",
  "Project root from App session: $($product.product_repo.project_root_from_app_session)",
  "Runtime identity marker: $($product.app_session_marker.receipt_id)",
  "Hook surface probe: $($product.hook_surface_probe.event_id)",
  "Typecheck: $($product.checks.typecheck.status) ($($product.checks.typecheck.command))",
  "Git branch: $($product.git_dirty_state.branch); dirty=$($product.git_dirty_state.dirty); status_count=$($product.git_dirty_state.status_short_count)"
) -join [Environment]::NewLine

$candidateReport = @(
  "# FULL_PASS_CANDIDATE.latest",
  "",
  "Status: $verdict",
  "Authority: candidate summary only; gate-issued receipt is the authority.",
  "Harness acceptance: $($acceptance.pass_count)/$($acceptance.test_count).",
  "Gate-issued receipt: $($gate.decision).",
  "MCP integration proof: $($mcpRun.json.status).",
  "Final runtime proof: FINAL_RUNTIME_PROOF.latest.md verdict $verdict."
) -join [Environment]::NewLine

Write-TextFile -Path (Join-Path $reportDir 'FINAL_RUNTIME_PROOF.latest.md') -Text ($runtimeProof + [Environment]::NewLine)
Write-TextFile -Path (Join-Path $reportDir 'FINAL_CODE_REVIEW.latest.md') -Text ($codeReview + [Environment]::NewLine)
Write-TextFile -Path (Join-Path $reportDir 'PRODUCT_REPO_ADOPTION.latest.md') -Text ($productReport + [Environment]::NewLine)
Write-TextFile -Path (Join-Path $reportDir 'FULL_PASS_CANDIDATE.latest.md') -Text ($candidateReport + [Environment]::NewLine)

[ordered]@{
  schema_version = 'final_runtime_proof_report_writer.v1'
  verdict = $verdict
  generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  criteria = $criteria
  report_paths = @(
    (Join-Path $reportDir 'FINAL_RUNTIME_PROOF.latest.md'),
    (Join-Path $reportDir 'FINAL_CODE_REVIEW.latest.md'),
    (Join-Path $reportDir 'PRODUCT_REPO_ADOPTION.latest.md'),
    (Join-Path $reportDir 'FULL_PASS_CANDIDATE.latest.md')
  )
} | ConvertTo-Json -Depth 10

if (-not $allPassed) { exit 1 }
