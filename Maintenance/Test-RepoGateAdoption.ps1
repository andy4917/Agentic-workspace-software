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
foreach ($required in $requiredEvents) {
  $commands = if ($hooksDocument) { @(Get-HookCommandsForEvent -HooksDocument $hooksDocument -EventName $required.event) } else { @() }
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
$configPresent = Test-Path -LiteralPath $ConfigPath -PathType Leaf
$runnerPresent = Test-Path -LiteralPath $hookRunner -PathType Leaf
$status = if ($hooksDocument -and $configPresent -and $runnerPresent -and $missing.Count -eq 0) { 'verified' } else { 'blocked' }

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
