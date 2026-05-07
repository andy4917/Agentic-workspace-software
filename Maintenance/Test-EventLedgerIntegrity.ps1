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
$ToolLedger = Join-Path $Root 'Settings/Codex_App_RUNTIME/tool_usage_events.jsonl'
$HookLedger = Join-Path $Root 'Maintenance/hook_invocations.jsonl'

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

function Invoke-Hook {
  param(
    [Parameter(Mandatory = $true)][string]$HookName,
    [Parameter(Mandatory = $true)][hashtable]$Payload
  )

  $json = $Payload | ConvertTo-Json -Depth 8 -Compress
  $output = & $Hook -HookName $HookName -PayloadJson $json
  @{
    hook = $HookName
    output = ($output -join [Environment]::NewLine)
  }
}

function Get-NestedValue {
  param(
    [object]$Object,
    [string[]]$Names
  )

  $current = $Object
  foreach ($name in $Names) {
    if ($null -eq $current) {
      return $null
    }
    $property = $current.PSObject.Properties[$name]
    if ($null -eq $property) {
      return $null
    }
    $current = $property.Value
  }
  $current
}

$beforeToolLines = Read-Lines -Path $ToolLedger
$beforeHookLines = Read-Lines -Path $HookLedger

$lineage = @{
  thread_id = 'thread-ledger-integrity'
  parent_thread_id = 'parent-thread-ledger-integrity'
  agent_id = 'agent-ledger-integrity'
  parent_agent_id = 'parent-agent-ledger-integrity'
  invocation_id = [guid]::NewGuid().ToString('n')
}

$common = @{
  tool_name = 'shell_command'
  cwd = $Root
  thread_id = $lineage.thread_id
  parent_thread_id = $lineage.parent_thread_id
  agent_id = $lineage.agent_id
  parent_agent_id = $lineage.parent_agent_id
  invocation_id = $lineage.invocation_id
}

$prePayload = $common.Clone()
$prePayload.command = "Get-ChildItem -LiteralPath '$Root' -Force"

$postPayload = $common.Clone()
$postPayload.command = "Get-ChildItem -LiteralPath '$Root' -Force"

$stopPayload = @{
  last_assistant_message = 'Analysis is still in progress; not complete.'
  cwd = $Root
  thread_id = $lineage.thread_id
  parent_thread_id = $lineage.parent_thread_id
  agent_id = $lineage.agent_id
  parent_agent_id = $lineage.parent_agent_id
  invocation_id = $lineage.invocation_id
}

$blockedStopPayload = $stopPayload.Clone()
$blockedStopPayload.last_assistant_message = 'Completed. Tests pass.'
$blockedStopPayload.completion_state = 'verified_complete'

$invocations = @(
  Invoke-Hook -HookName 'pre_command_guard' -Payload $prePayload
  Invoke-Hook -HookName 'post_tool_use' -Payload $postPayload
  Invoke-Hook -HookName 'stop_checks' -Payload $stopPayload
  Invoke-Hook -HookName 'stop_checks' -Payload $blockedStopPayload
)

$afterToolLines = Read-Lines -Path $ToolLedger
$afterHookLines = Read-Lines -Path $HookLedger

$newToolLines = @($afterToolLines | Select-Object -Skip $beforeToolLines.Count)
$newHookLines = @($afterHookLines | Select-Object -Skip $beforeHookLines.Count)
$newToolEvents = @(Read-JsonLines -Lines $newToolLines)
$newHookEvents = @(Read-JsonLines -Lines $newHookLines)

$checks = [ordered]@{}
$checks.tool_ledger_append_only = ($afterToolLines.Count -ge $beforeToolLines.Count) -and ((@($afterToolLines | Select-Object -First $beforeToolLines.Count) -join "`n") -eq ($beforeToolLines -join "`n"))
$checks.hook_ledger_append_only = ($afterHookLines.Count -ge $beforeHookLines.Count) -and ((@($afterHookLines | Select-Object -First $beforeHookLines.Count) -join "`n") -eq ($beforeHookLines -join "`n"))
$checks.tool_usage_event_v2_written = @($newToolEvents | Where-Object { $_.schema_version -eq 'tool_usage_event.v2' -and $_.event_id -and $_.hook_event_name }).Count -ge 2
$checks.pretooluse_equivalent_observation_written = @($newToolEvents | Where-Object { $_.hook_event_name -eq 'PreToolUse' -and $_.observation_layer -eq 'PreToolUse equivalent observation' }).Count -ge 1
$checks.posttooluse_observation_written = @($newToolEvents | Where-Object { $_.hook_event_name -eq 'PostToolUse' -and $_.observation_layer -eq 'PostToolUse' }).Count -ge 1

$allEventIds = @()
$allEventIds += @($newToolEvents | ForEach-Object { [string]$_.event_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$allEventIds += @($newHookEvents | ForEach-Object { [string]$_.event_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$checks.event_id_present = $allEventIds.Count -ge 6
$checks.event_id_no_collision = $allEventIds.Count -eq @($allEventIds | Select-Object -Unique).Count

$hookEventNames = @($newHookEvents | ForEach-Object { [string]$_.hook_event_name })
$checks.pre_post_stop_hook_events_recorded = ($hookEventNames -contains 'PreToolUse') -and ($hookEventNames -contains 'PostToolUse') -and ($hookEventNames -contains 'Stop')

$lineageEvents = @($newToolEvents + $newHookEvents | Where-Object {
  (Get-NestedValue -Object $_ -Names @('parent_lineage','parent_thread_id')) -eq $lineage.parent_thread_id -or
  (Get-NestedValue -Object $_ -Names @('agent_lineage','parent_thread_id')) -eq $lineage.parent_thread_id
})
$checks.parent_lineage_preserved = $lineageEvents.Count -ge 3

$blockedEvents = @($newToolEvents + $newHookEvents | Where-Object { [string]$_.outcome -eq 'blocked' -or [string]$_.decision -eq 'BLOCKED' -or [string]$_.decision -eq 'DO_NOT_CLAIM_COMPLETE' })
$checks.blocked_or_failed_event_recorded = $blockedEvents.Count -ge 1

$failed = @()
foreach ($property in $checks.Keys) {
  if (-not [bool]$checks[$property]) {
    $failed += $property
  }
}

$summary = [ordered]@{
  schema_version = 'event_ledger_integrity.v1'
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  root = $Root
  tool_ledger = $ToolLedger
  hook_ledger = $HookLedger
  invocations = $invocations
  before = [ordered]@{
    tool_lines = $beforeToolLines.Count
    hook_lines = $beforeHookLines.Count
  }
  after = [ordered]@{
    tool_lines = $afterToolLines.Count
    hook_lines = $afterHookLines.Count
  }
  new_events = [ordered]@{
    tool_usage = $newToolEvents.Count
    hook_invocation = $newHookEvents.Count
  }
  checks = $checks
  failed = $failed
  status = if ($failed.Count -eq 0) { 'verified' } else { 'blocked' }
}

$summary | ConvertTo-Json -Depth 10
if ($failed.Count -gt 0) {
  exit 1
}
