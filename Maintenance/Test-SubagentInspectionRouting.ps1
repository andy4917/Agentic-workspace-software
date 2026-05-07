param(
  [string]$Root = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}

$Hook = Join-Path $Root 'Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1'
$JobsPath = Join-Path $Root 'Settings/Codex_App_RUNTIME/subagent_inspection_jobs.jsonl'
$ToolLedger = Join-Path $Root 'Settings/Codex_App_RUNTIME/tool_usage_events.jsonl'

function Read-Lines {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return @()
  }
  @(Get-Content -LiteralPath $Path -ErrorAction Stop)
}

function Read-JsonLines {
  param([string[]]$Lines)
  $items = @()
  foreach ($line in @($Lines)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $items += ($line | ConvertFrom-Json)
    } catch {
    }
  }
  $items
}

function Invoke-HookJson {
  param(
    [Parameter(Mandatory = $true)][string]$HookName,
    [Parameter(Mandatory = $true)][hashtable]$Payload
  )

  $json = $Payload | ConvertTo-Json -Depth 10 -Compress
  $output = & $Hook -HookName $HookName -PayloadJson $json
  @{
    hook = $HookName
    output = ($output -join [Environment]::NewLine)
  }
}

function Test-CleanTargetPaths {
  param([object]$TargetPaths)

  $paths = @($TargetPaths)
  if ($paths.Count -eq 0) {
    return $false
  }

  foreach ($path in $paths) {
    $value = [string]$path
    if ([string]::IsNullOrWhiteSpace($value)) {
      return $false
    }
    if ($value.Contains('`') -or $value.Contains("`r") -or $value.Contains("`n") -or $value.Contains(',')) {
      return $false
    }
    if ($value -notmatch '^[A-Za-z]:\\') {
      return $false
    }
    if (-not (Test-Path -LiteralPath $value)) {
      return $false
    }
  }

  return $true
}

$beforeJobLines = Read-Lines -Path $JobsPath
$beforeLedgerLines = Read-Lines -Path $ToolLedger

$runId = [guid]::NewGuid().ToString('n')
$promptPayload = @{
  prompt = "Explicit ssot_contract_inspection and required_tool_route_inspection request for hook-routed Spark inspector validation. Repro target_paths contamination: test/build,`, Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1, required-tool-route. run_id=$runId"
  cwd = $Root
  thread_id = 'thread-subagent-inspection-routing'
}
$promptResult = Invoke-HookJson -HookName 'user_prompt_submit' -Payload $promptPayload

$afterPromptJobLines = Read-Lines -Path $JobsPath
$newPromptJobs = @(Read-JsonLines -Lines @($afterPromptJobLines | Select-Object -Skip $beforeJobLines.Count))
$contractJob = @($newPromptJobs | Where-Object {
  [string]$_.route_id -eq 'ssot_contract_inspection' -and
  [string]$_.agent_name -eq 'spark_contract_inspector' -and
  [string]$_.sandbox_mode -eq 'read-only' -and
  [int]$_.max_depth -eq 1 -and
  [string]$_.authority -eq 'candidate_evidence_only'
} | Select-Object -Last 1)

if ($contractJob.Count -eq 0) {
  throw 'Expected ssot_contract_inspection job was not queued.'
}

$toolRouteJob = @($newPromptJobs | Where-Object {
  [string]$_.route_id -eq 'required_tool_route_inspection' -and
  [string]$_.agent_name -eq 'spark_tool_route_inspector' -and
  [string]$_.sandbox_mode -eq 'read-only' -and
  [int]$_.max_depth -eq 1 -and
  [string]$_.authority -eq 'candidate_evidence_only'
} | Select-Object -Last 1)

if ($toolRouteJob.Count -eq 0) {
  throw 'Expected required_tool_route_inspection job was not queued.'
}

$job = $contractJob[0]
$spawnPayload = @{
  tool_name = 'spawn_agent'
  command = "spawn_agent spark_contract_inspector job_id=$($job.job_id) route_id=ssot_contract_inspection authority=candidate_evidence_only"
  cwd = $Root
  thread_id = 'thread-subagent-inspection-routing'
}
$spawnResult = Invoke-HookJson -HookName 'post_tool_use' -Payload $spawnPayload

$reportPayload = @{
  tool_name = 'spawn_agent'
  command = "subagent_inspection_report.v1 job_id=$($job.job_id) route_id=ssot_contract_inspection agent_name=spark_contract_inspector status=reported authority=candidate_evidence_only"
  cwd = $Root
  thread_id = 'thread-subagent-inspection-routing'
}
$reportResult = Invoke-HookJson -HookName 'post_tool_use' -Payload $reportPayload

$koPass = ([string][char]0xD1B5) + ([string][char]0xACFC)
$bareReportPayload = @{
  tool_name = 'spawn_agent'
  command = "subagent_inspection_report.v1 job_id=subagent-$runId route_id=ssot_contract_inspection agent_name=spark_contract_inspector status=reported authority=candidate_evidence_only $koPass"
  cwd = $Root
  thread_id = 'thread-subagent-inspection-routing'
}
$bareReportResult = Invoke-HookJson -HookName 'post_tool_use' -Payload $bareReportPayload

$prePayload = @{
  tool_name = 'shell_command'
  command = "Get-Content -LiteralPath '$Root\Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1' -TotalCount 1"
  cwd = $Root
  thread_id = 'thread-subagent-inspection-routing'
}
$preResult = Invoke-HookJson -HookName 'pre_command_guard' -Payload $prePayload

$afterLedgerLines = Read-Lines -Path $ToolLedger
$newLedgerEvents = @(Read-JsonLines -Lines @($afterLedgerLines | Select-Object -Skip $beforeLedgerLines.Count))

$subagentEvents = @($newLedgerEvents | Where-Object {
  [string]$_.record_type -eq 'subagent_inspection_event' -and
  [string]$_.job_id -eq [string]$job.job_id -and
  [string]$_.authority -eq 'candidate_evidence_only'
})

$spawnEvents = @($subagentEvents | Where-Object { [string]$_.event -eq 'subagent_spawn' })
$reportEvents = @($subagentEvents | Where-Object { [string]$_.event -eq 'subagent_report' })
$fieldCompleteEvents = @($subagentEvents | Where-Object {
  -not [string]::IsNullOrWhiteSpace([string]$_.job_id) -and
  -not [string]::IsNullOrWhiteSpace([string]$_.parent_turn_id) -and
  -not [string]::IsNullOrWhiteSpace([string]$_.agent_name) -and
  [string]$_.sandbox_mode -eq 'read-only' -and
  $null -ne $_.target_paths -and
  -not [string]::IsNullOrWhiteSpace([string]$_.status) -and
  [string]$_.authority -eq 'candidate_evidence_only'
})
$allNewJobsHaveCleanTargetPaths = (@($newPromptJobs | Where-Object {
  [string]$_.route_id -in @('ssot_contract_inspection','required_tool_route_inspection')
}).Count -ge 2) -and (@($newPromptJobs | Where-Object {
  [string]$_.route_id -in @('ssot_contract_inspection','required_tool_route_inspection') -and
  -not (Test-CleanTargetPaths -TargetPaths $_.target_paths)
}).Count -eq 0)
$allSubagentEventsHaveCleanTargetPaths = ($subagentEvents.Count -ge 2) -and (@($subagentEvents | Where-Object {
  -not (Test-CleanTargetPaths -TargetPaths $_.target_paths)
}).Count -eq 0)

$checks = [ordered]@{
  hook_user_prompt_submit_live_ok = $promptResult.output -match 'UserPromptSubmit'
  job_queued = $true
  job_has_required_fields = -not [string]::IsNullOrWhiteSpace([string]$job.job_id) -and -not [string]::IsNullOrWhiteSpace([string]$job.parent_turn_id) -and [string]$job.agent_name -eq 'spark_contract_inspector' -and [string]$job.sandbox_mode -eq 'read-only' -and $null -ne $job.target_paths -and [string]$job.status -eq 'queued' -and [string]$job.authority -eq 'candidate_evidence_only'
  required_tool_route_job_queued = $toolRouteJob.Count -ge 1
  jobs_have_clean_absolute_target_paths = $allNewJobsHaveCleanTargetPaths
  subagent_spawn_recorded = $spawnEvents.Count -ge 1
  subagent_report_recorded = $reportEvents.Count -ge 1
  bare_report_observation_no_hook_failure = $bareReportResult.output -eq '{}'
  subagent_events_have_required_fields = $fieldCompleteEvents.Count -ge 2
  subagent_events_have_clean_absolute_target_paths = $allSubagentEventsHaveCleanTargetPaths
  pretooluse_remains_action_safety_only = $preResult.output -eq '{}'
}

$failed = @()
foreach ($key in $checks.Keys) {
  if (-not [bool]$checks[$key]) {
    $failed += $key
  }
}

$summary = [ordered]@{
  schema_version = 'subagent_inspection_routing_check.v1'
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  root = $Root
  job_id = [string]$job.job_id
  checks = $checks
  failed = $failed
  status = if ($failed.Count -eq 0) { 'verified' } else { 'blocked' }
}

$summary | ConvertTo-Json -Depth 10
if ($failed.Count -gt 0) {
  exit 1
}
