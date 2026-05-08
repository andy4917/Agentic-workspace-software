param(
  [string]$Root = '',
  [string]$HooksJson = '',
  [string]$ConfigPath = '',
  [switch]$NoWrite
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($HooksJson)) {
  $HooksJson = Join-Path $HOME '.codex\hooks.json'
}
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $Root 'Settings\Codex_App_DECLARATIVE\repo-gate-adoption.agent.config.yaml'
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), $utf8NoBom) | ConvertFrom-Json
}

function Write-JsonFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )

  $json = ($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine
  [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Convert-ToGuardPathText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ''
  }
  ([string]$Text).ToLowerInvariant().Replace('\', '/') -replace '/+', '/'
}

function Get-HookCommandsForEvent {
  param(
    [Parameter(Mandatory = $true)][object]$HooksDocument,
    [Parameter(Mandatory = $true)][string]$EventName
  )

  $commands = @()
  $eventEntries = $HooksDocument.hooks.$EventName
  foreach ($entry in @($eventEntries)) {
    foreach ($hook in @($entry.hooks)) {
      $command = [string]$hook.command
      if (-not [string]::IsNullOrWhiteSpace($command)) {
        $commands += $command
      }
    }
  }
  $commands
}

function Test-HookHandlerConfigShape {
  param(
    [Parameter(Mandatory = $true)][object]$HooksDocument,
    [Parameter(Mandatory = $true)][string]$EventName
  )

  $results = @()
  $eventEntries = $HooksDocument.hooks.$EventName
  $groupIndex = 0
  foreach ($entry in @($eventEntries)) {
    $handlerIndex = 0
    foreach ($hook in @($entry.hooks)) {
      $properties = @($hook.PSObject.Properties.Name)
      $handlerType = [string]$hook.type
      $hasTimeout = $properties -contains 'timeout'
      $hasStatusMessage = $properties -contains 'statusMessage'
      $hasLegacyTimeout = $properties -contains 'timeout_sec'
      $hasLegacyStatusMessage = $properties -contains 'status_message'
      $expectedStatusMessage = $EventName -in @('SessionStart','Stop')
      $timeoutValue = if ($hasTimeout) { [int]$hook.timeout } else { $null }

      $results += [ordered]@{
        event = $EventName
        group_index = $groupIndex
        handler_index = $handlerIndex
        type = $handlerType
        has_timeout = $hasTimeout
        timeout = $timeoutValue
        has_statusMessage = $hasStatusMessage
        has_legacy_timeout_sec = $hasLegacyTimeout
        has_legacy_status_message = $hasLegacyStatusMessage
        expected_statusMessage = $expectedStatusMessage
        ok = (
          ($handlerType -eq 'command') -and
          $hasTimeout -and
          ($timeoutValue -eq 10) -and
          (-not $hasLegacyTimeout) -and
          (-not $hasLegacyStatusMessage) -and
          ($hasStatusMessage -eq $expectedStatusMessage)
        )
      }
      $handlerIndex += 1
    }
    $groupIndex += 1
  }
  $results
}

$requiredEvents = @(
  @{ event = 'SessionStart'; hook_name = 'session_start' },
  @{ event = 'UserPromptSubmit'; hook_name = 'user_prompt_submit' },
  @{ event = 'PreToolUse'; hook_name = 'pre_command_guard' },
  @{ event = 'PostToolUse'; hook_name = 'post_tool_use' },
  @{ event = 'Stop'; hook_name = 'stop_checks' }
)

$hookRunner = Join-Path $Root 'Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1'
$hookRunnerNorm = Convert-ToGuardPathText -Text $hookRunner
$hooksJsonNorm = Convert-ToGuardPathText -Text $HooksJson

$hooksDocument = if (Test-Path -LiteralPath $HooksJson -PathType Leaf) { Read-JsonFile -Path $HooksJson } else { $null }
$checks = @()
$shapeChecks = @()
foreach ($required in $requiredEvents) {
  $commands = if ($hooksDocument) { @(Get-HookCommandsForEvent -HooksDocument $hooksDocument -EventName $required.event) } else { @() }
  if ($hooksDocument) {
    $shapeChecks += @(Test-HookHandlerConfigShape -HooksDocument $hooksDocument -EventName $required.event)
  }
  $runnerMatched = $false
  $hookNameMatched = $false
  foreach ($command in $commands) {
    $normalized = Convert-ToGuardPathText -Text $command
    if ($normalized.Contains($hookRunnerNorm)) {
      $runnerMatched = $true
    }
    if ($normalized -match ("-hookname\s+" + [regex]::Escape($required.hook_name) + "(\s|$)")) {
      $hookNameMatched = $true
    }
  }
  $commandCount = @($commands).Count
  $checks += [ordered]@{
    event = $required.event
    required_hook_name = $required.hook_name
    commands = $commands
    event_present = ($commandCount -gt 0)
    hook_runner_matched = $runnerMatched
    hook_name_matched = $hookNameMatched
    ok = (($commandCount -gt 0) -and $runnerMatched -and $hookNameMatched)
  }
}

$missing = @($checks | Where-Object { -not $_.ok } | ForEach-Object { $_.event })
$misconfiguredHookHandlers = @($shapeChecks | Where-Object { -not $_.ok })
$configPresent = Test-Path -LiteralPath $ConfigPath -PathType Leaf
$runnerPresent = Test-Path -LiteralPath $hookRunner -PathType Leaf
$status = if ($hooksDocument -and $configPresent -and $runnerPresent -and $missing.Count -eq 0 -and $misconfiguredHookHandlers.Count -eq 0) { 'verified' } else { 'blocked' }

$receipt = [ordered]@{
  schema_version = 'repo_gate_adoption_receipt.v1'
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  status = $status
  project_root = $Root
  global_hook_config = $HooksJson
  global_hook_config_normalized = $hooksJsonNorm
  hook_runner = $hookRunner
  config_path = $ConfigPath
  config_present = $configPresent
  hook_runner_present = $runnerPresent
  required_events = $checks
  missing_or_unwired_events = $missing
  hook_config_shape = $shapeChecks
  misconfigured_hook_handlers = $misconfiguredHookHandlers
  targets = @(
    [ordered]@{
      id = 'Dev_Codex_App_GlobalSSOT'
      root = $Root
      adoption = 'global_codex_hooks'
      status = $status
    }
  )
  evidence = @(
    if ($hooksDocument) { 'hooks_json_parse:ok' } else { 'hooks_json_parse:missing' }
    if ($configPresent) { 'repo_gate_adoption_config_present:ok' } else { 'repo_gate_adoption_config_present:missing' }
    if ($runnerPresent) { 'hook_runner_present:ok' } else { 'hook_runner_present:missing' }
    if ($missing.Count -eq 0) { 'repo_gate_adoption_verified:ok' } else { 'repo_gate_adoption_verified:blocked' }
    if ($misconfiguredHookHandlers.Count -eq 0) { 'hooks_json_canonical_handler_keys:ok' } else { 'hooks_json_canonical_handler_keys:blocked' }
  )
  note = 'Verified adoption requires actual hook wiring; pattern classification or dirty read-only audit is candidate evidence only.'
}

if (-not $NoWrite) {
  $runtimePath = Join-Path $Root 'Settings\Codex_App_RUNTIME\repo_gate_adoption_receipt.json'
  Write-JsonFile -Path $runtimePath -Value $receipt
}

$receipt | ConvertTo-Json -Depth 12
if ($status -ne 'verified') {
  exit 1
}
