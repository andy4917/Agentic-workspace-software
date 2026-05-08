param(
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}

$hookPath = Join-Path $Root 'Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1'
$fixturePath = Join-Path $Root 'Maintenance\harness-v2\fixtures\app_subagent_initial_envelope.required_tool_route_inspection.jsonl'

$payloadJson = (@{
  cwd = $Root
  tool_name = 'app_subagent_initial_envelope_regression'
  output = 'load hook functions without writing ledgers'
} | ConvertTo-Json -Compress)

$null = . $hookPath -HookName 'post_tool_use' -DryRun -NoLog -PayloadJson $payloadJson

$envelope = Get-CodexAppSubagentInitialRequestEnvelope -Path $fixturePath -Root $Root -AgentRole 'inspector' -RawAgentRole 'spark_tool_route_inspector'

$expected = [ordered]@{
  job_id = 'subagent-3d02b85c8d6d4edeb53d34526f4abc67'
  parent_turn_id = '514a84a6821f1db426f3589aa1170a25a23f4ea94721ba0f1373e1da68c80f51'
  attempt_id = '514a84a6821f1db426f3589aa1170a25a23f4ea94721ba0f1373e1da68c80f51'
  route_id = 'required_tool_route_inspection'
  agent_name = 'spark_tool_route_inspector'
}

$failures = @()
foreach ($key in $expected.Keys) {
  $actual = [string](Get-OptionalPropertyValue -Object $envelope -Name $key)
  if ($actual -ne [string]$expected[$key]) {
    $failures += "$key expected '$($expected[$key])' got '$actual'"
  }
}

if ([bool](Get-OptionalPropertyValue -Object $envelope -Name 'matched_complete_envelope') -ne $true) {
  $failures += 'matched_complete_envelope expected true'
}

$rejected = @(Get-OptionalPropertyValue -Object $envelope -Name 'rejected_partial_values')
if ($rejected -contains 'job_id:subagent-f') {
  $failures += 'partial job_id from later output was inspected; extractor must stay inside the initial request envelope'
}

if ($failures.Count -gt 0) {
  throw ($failures -join '; ')
}

[ordered]@{
  schema_version = 'app_subagent_initial_envelope_regression.v1'
  status = 'PASS'
  fixture = $fixturePath
  extracted = [ordered]@{
    job_id = [string](Get-OptionalPropertyValue -Object $envelope -Name 'job_id')
    parent_turn_id = [string](Get-OptionalPropertyValue -Object $envelope -Name 'parent_turn_id')
    attempt_id = [string](Get-OptionalPropertyValue -Object $envelope -Name 'attempt_id')
    route_id = [string](Get-OptionalPropertyValue -Object $envelope -Name 'route_id')
    agent_name = [string](Get-OptionalPropertyValue -Object $envelope -Name 'agent_name')
    extraction_mode = [string](Get-OptionalPropertyValue -Object $envelope -Name 'extraction_mode')
    envelope_source_line = Get-OptionalPropertyValue -Object $envelope -Name 'envelope_source_line'
  }
} | ConvertTo-Json -Depth 6
