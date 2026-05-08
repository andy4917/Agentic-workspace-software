param(
  [string]$CodexHome = '',
  [string]$Root = '',
  [string]$DesktopPackageRoot = '',
  [string]$DesktopLogRoot = '',
  [string]$HookLogPath = '',
  [string]$ReceiptPath = '',
  [string]$TargetThreadId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
  $CodexHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
}
if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($DesktopPackageRoot)) {
  $packageRoot = Get-ChildItem -LiteralPath 'C:\Program Files\WindowsApps' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'OpenAI.Codex_*' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($packageRoot) {
    $DesktopPackageRoot = Join-Path $packageRoot.FullName 'app'
  }
}
if ([string]::IsNullOrWhiteSpace($DesktopLogRoot)) {
  $packageLocal = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\Logs'
  if (Test-Path -LiteralPath $packageLocal -PathType Container) {
    $DesktopLogRoot = $packageLocal
  }
}
if ([string]::IsNullOrWhiteSpace($HookLogPath)) {
  $HookLogPath = Join-Path $Root 'Maintenance\hook_invocations.jsonl'
}
if ([string]::IsNullOrWhiteSpace($ReceiptPath)) {
  $ReceiptPath = Join-Path $Root 'Settings\Codex_App_RUNTIME\codex_hook_ui_surface_receipt.json'
}

function Get-ObjectProperty {
  param(
    [object]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  $property.Value
}

function Read-TextFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), $utf8NoBom)
}

function Read-SharedTextLines {
  param([Parameter(Mandatory = $true)][string]$Path)

  $fs = [System.IO.File]::Open((Resolve-Path -LiteralPath $Path), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  $reader = New-Object System.IO.StreamReader($fs, $utf8NoBom, $true)
  try {
    while (-not $reader.EndOfStream) {
      $reader.ReadLine()
    }
  } finally {
    $reader.Dispose()
    $fs.Dispose()
  }
}

function Read-AsarTextFile {
  param(
    [Parameter(Mandatory = $true)][string]$AsarPath,
    [Parameter(Mandatory = $true)][string]$EntryPath
  )

  $fs = [System.IO.File]::Open((Resolve-Path -LiteralPath $AsarPath), [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  try {
    $prefix = New-Object byte[] 16
    [void]$fs.Read($prefix, 0, $prefix.Length)
    $headerSize = [BitConverter]::ToUInt32($prefix, 4)
    $jsonLength = [BitConverter]::ToUInt32($prefix, 12)
    $headerBytes = New-Object byte[] $jsonLength
    [void]$fs.Read($headerBytes, 0, $headerBytes.Length)
    $header = ([System.Text.Encoding]::UTF8.GetString($headerBytes) | ConvertFrom-Json)
    $node = $header
    foreach ($part in @($EntryPath -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
      $files = Get-ObjectProperty -Object $node -Name 'files'
      $node = Get-ObjectProperty -Object $files -Name $part
      if ($null -eq $node) {
        throw "Missing ASAR entry: $EntryPath"
      }
    }

    $size = [int](Get-ObjectProperty -Object $node -Name 'size')
    $offset = [int64](Get-ObjectProperty -Object $node -Name 'offset')
    $dataOffset = [int64](8 + $headerSize) + $offset
    $buffer = New-Object byte[] $size
    $fs.Position = $dataOffset
    $read = 0
    while ($read -lt $size) {
      $chunk = $fs.Read($buffer, $read, $size - $read)
      if ($chunk -le 0) {
        throw "Unexpected EOF while reading ASAR entry: $EntryPath"
      }
      $read += $chunk
    }

    [System.Text.Encoding]::UTF8.GetString($buffer)
  } finally {
    $fs.Dispose()
  }
}

function Test-Contains {
  param(
    [string]$Text,
    [string]$Needle
  )

  -not [string]::IsNullOrEmpty($Text) -and $Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0
}

function Get-HookConfigSnapshot {
  param([Parameter(Mandatory = $true)][string]$HooksPath)

  if (-not (Test-Path -LiteralPath $HooksPath -PathType Leaf)) {
    return [ordered]@{
      path = $HooksPath
      present = $false
      ok = $false
      events = @()
    }
  }

  $config = Read-TextFile -Path $HooksPath | ConvertFrom-Json
  $rootHooks = Get-ObjectProperty -Object $config -Name 'hooks'
  $eventSnapshots = @()
  foreach ($eventName in @('SessionStart','UserPromptSubmit','PreToolUse','PostToolUse','Stop')) {
    $groups = @(Get-ObjectProperty -Object $rootHooks -Name $eventName)
    $handlerSnapshots = @()
    foreach ($group in $groups) {
      foreach ($handler in @(Get-ObjectProperty -Object $group -Name 'hooks')) {
        $names = @($handler.PSObject.Properties.Name)
        $handlerSnapshots += [ordered]@{
          type = [string](Get-ObjectProperty -Object $handler -Name 'type')
          has_timeout = $names -contains 'timeout'
          timeout = Get-ObjectProperty -Object $handler -Name 'timeout'
          has_statusMessage = $names -contains 'statusMessage'
          has_legacy_timeout_sec = $names -contains 'timeout_sec'
          has_legacy_status_message = $names -contains 'status_message'
        }
      }
    }
    $eventSnapshots += [ordered]@{
      event_name = $eventName
      group_count = $groups.Count
      handler_count = $handlerSnapshots.Count
      handlers = $handlerSnapshots
      status_message_expected = $eventName -in @('SessionStart','Stop')
    }
  }

  $misconfigured = @($eventSnapshots | Where-Object {
    $event = $_
    [int]$event['handler_count'] -eq 0 -or
      @($event['handlers'] | Where-Object {
        -not [bool]$_['has_timeout'] -or
          [bool]$_['has_legacy_timeout_sec'] -or
          [bool]$_['has_legacy_status_message'] -or
          ([bool]$event['status_message_expected'] -and -not [bool]$_['has_statusMessage'])
      }).Count -gt 0
  })

  [ordered]@{
    path = $HooksPath
    present = $true
    ok = ($misconfigured.Count -eq 0)
    events = $eventSnapshots
    misconfigured_events = $misconfigured
  }
}

function Get-HookInvocationSnapshot {
  param([Parameter(Mandatory = $true)][string]$Path)

  $counts = @{}
  $lastActual = @{}
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    foreach ($line in Read-SharedTextLines -Path $Path) {
      if ([string]::IsNullOrWhiteSpace($line)) {
        continue
      }
      try {
        $event = $line | ConvertFrom-Json
      } catch {
        continue
      }
      if ([bool](Get-ObjectProperty -Object $event -Name 'dry_run')) {
        continue
      }
      $eventName = [string](Get-ObjectProperty -Object $event -Name 'hook_event_name')
      if ([string]::IsNullOrWhiteSpace($eventName)) {
        $eventName = [string](Get-ObjectProperty -Object $event -Name 'hook')
      }
      if (-not $counts.ContainsKey($eventName)) {
        $counts[$eventName] = 0
      }
      $counts[$eventName] += 1
      $lastActual[$eventName] = [ordered]@{
        observed_at_utc = [string](Get-ObjectProperty -Object $event -Name 'observed_at_utc')
        hook = [string](Get-ObjectProperty -Object $event -Name 'hook')
        decision = [string](Get-ObjectProperty -Object $event -Name 'decision')
        reason = [string](Get-ObjectProperty -Object $event -Name 'reason')
      }
    }
  }

  [ordered]@{
    path = $Path
    present = (Test-Path -LiteralPath $Path -PathType Leaf)
    actual_non_dry_run_counts = $counts
    latest_actual_by_event = $lastActual
    session_start_observed = ($counts.ContainsKey('SessionStart') -and $counts['SessionStart'] -gt 0)
    stop_observed = ($counts.ContainsKey('Stop') -and $counts['Stop'] -gt 0)
  }
}

function Get-DesktopLogSnapshot {
  param([string]$LogRoot)

  $patterns = [ordered]@{
    unknown_hook_started = 'Received hook/started for unknown conversation'
    unknown_hook_completed = 'Received hook/completed for unknown conversation'
    unknown_turn_started = 'Received turn/started for unknown conversation'
    unknown_turn_completed = 'Received turn/completed for unknown conversation'
    deprecation_notice = 'Deprecation notice'
  }
  $counts = [ordered]@{}
  $latest = [ordered]@{}
  foreach ($name in $patterns.Keys) {
    $counts[$name] = 0
    $latest[$name] = $null
  }

  if (-not [string]::IsNullOrWhiteSpace($LogRoot) -and (Test-Path -LiteralPath $LogRoot -PathType Container)) {
    $files = @(Get-ChildItem -LiteralPath $LogRoot -Recurse -Force -File -Filter '*.log' -ErrorAction SilentlyContinue)
    if ($files.Count -gt 0) {
      $logPaths = @($files | Select-Object -ExpandProperty FullName)
      foreach ($name in $patterns.Keys) {
        $hits = @(Select-String -LiteralPath $logPaths -Pattern $patterns[$name] -SimpleMatch -ErrorAction SilentlyContinue)
        $counts[$name] = $hits.Count
        if ($hits.Count -gt 0) {
          $last = $hits | Select-Object -Last 1
          $latest[$name] = [ordered]@{
            path = $last.Path
            line_number = $last.LineNumber
            line = $last.Line
          }
        }
      }
    }
  }

  [ordered]@{
    log_root = $LogRoot
    counts = $counts
    latest = $latest
  }
}

function Get-TargetSessionSnapshot {
  param(
    [string]$CodexHomePath,
    [string]$ThreadId
  )

  if ([string]::IsNullOrWhiteSpace($ThreadId)) {
    return [ordered]@{
      requested = $false
    }
  }

  $sessionRoot = Join-Path $CodexHomePath 'sessions'
  $sessionFile = Get-ChildItem -LiteralPath $sessionRoot -Recurse -Force -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "*$ThreadId*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $sessionFile) {
    return [ordered]@{
      requested = $true
      thread_id = $ThreadId
      present = $false
      non_tool_output_hook_hits = 0
    }
  }

  $hits = 0
  foreach ($line in Read-SharedTextLines -Path $sessionFile.FullName) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $event = $line | ConvertFrom-Json
    } catch {
      continue
    }
    $payload = Get-ObjectProperty -Object $event -Name 'payload'
    if ([string](Get-ObjectProperty -Object $payload -Name 'type') -eq 'function_call_output') {
      continue
    }
    $payloadText = $payload | ConvertTo-Json -Depth 20 -Compress
    if ($payloadText -match '(?i)hook/started|hook/completed|HookStarted|HookCompleted|"type":"hook"|statusMessage') {
      $hits += 1
    }
  }

  [ordered]@{
    requested = $true
    thread_id = $ThreadId
    present = $true
    path = $sessionFile.FullName
    non_tool_output_hook_hits = $hits
    hook_items_persisted_in_session_jsonl = ($hits -gt 0)
  }
}

$codexHomeResolved = (Resolve-Path -LiteralPath $CodexHome).Path
$hooksPath = Join-Path $codexHomeResolved 'hooks.json'
$asarPath = if ([string]::IsNullOrWhiteSpace($DesktopPackageRoot)) { '' } else { Join-Path $DesktopPackageRoot 'resources\app.asar' }

$hookConfig = Get-HookConfigSnapshot -HooksPath $hooksPath
$hookInvocations = Get-HookInvocationSnapshot -Path $HookLogPath
$desktopLogs = Get-DesktopLogSnapshot -LogRoot $DesktopLogRoot
$targetSession = Get-TargetSessionSnapshot -CodexHomePath $codexHomeResolved -ThreadId $TargetThreadId

$localConversationThreadJs = ''
$appServerSignalsJs = ''
$asarRawText = ''
$packageReadError = ''
try {
  if (-not [string]::IsNullOrWhiteSpace($asarPath) -and (Test-Path -LiteralPath $asarPath -PathType Leaf)) {
    $localConversationThreadJs = Read-AsarTextFile -AsarPath $asarPath -EntryPath '/webview/assets/local-conversation-thread-CtMlGbxV.js'
    $appServerSignalsJs = Read-AsarTextFile -AsarPath $asarPath -EntryPath '/webview/assets/app-server-manager-signals-D5SENExw.js'
    $asarRawText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $asarPath)))
  }
} catch {
  $packageReadError = $_.Exception.Message
  if (-not [string]::IsNullOrWhiteSpace($asarPath) -and (Test-Path -LiteralPath $asarPath -PathType Leaf)) {
    try {
      $asarRawText = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $asarPath)))
    } catch {
    }
  }
}

$packageSearchText = "$localConversationThreadJs`n$appServerSignalsJs`n$asarRawText"
$packageSnapshot = [ordered]@{
  package_root = $DesktopPackageRoot
  asar_path = $asarPath
  package_read_error = $packageReadError
  used_raw_asar_scan = (-not [string]::IsNullOrWhiteSpace($asarRawText))
  has_hook_signal_handler = (Test-Contains -Text $packageSearchText -Needle 'case`hook/started`:case`hook/completed`')
  has_hook_completed_signal = (Test-Contains -Text $packageSearchText -Needle 'hook/completed')
  has_hook_renderer_component = (Test-Contains -Text $packageSearchText -Needle 'localConversation.hookItem.hookLabel')
  hook_renderer_default_icon_enabled = (Test-Contains -Text $packageSearchText -Needle 'showIcon:r') -and (Test-Contains -Text $packageSearchText -Needle 'r===void 0?!0:r')
  has_status_message_summary_formatter = (Test-Contains -Text $packageSearchText -Needle 'localConversation.hookItem.summary.withStatusMessage')
  compact_or_latest_summary_suppresses_hook_icon = (Test-Contains -Text $packageSearchText -Needle 'showHookSummaryIcon:!1')
  hook_icon_class_present = (Test-Contains -Text $packageSearchText -Needle 'icon-2xs flex-shrink-0 text-token-foreground/30')
}

$uiPipelinePresent = [bool]$packageSnapshot['has_hook_signal_handler'] -and [bool]$packageSnapshot['has_hook_renderer_component'] -and [bool]$packageSnapshot['has_status_message_summary_formatter']
$runtimeObserved = [bool]$hookInvocations['session_start_observed'] -and [bool]$hookInvocations['stop_observed']
$unknownHookCompletedCount = [int]$desktopLogs['counts']['unknown_hook_completed']
$uiSuppressionObserved = [bool]$packageSnapshot['compact_or_latest_summary_suppresses_hook_icon'] -or ($unknownHookCompletedCount -gt 0)
$status = if ([bool]$hookConfig['ok'] -and $runtimeObserved -and $uiPipelinePresent) {
  if ($uiSuppressionObserved) { 'verified_ui_surface_issue_observed' } else { 'verified' }
} else {
  'blocked'
}

$receipt = [ordered]@{
  schema_version = 'codex_hook_ui_surface_audit.v1'
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  status = $status
  codex_home = $codexHomeResolved
  root = (Resolve-Path -LiteralPath $Root).Path
  hook_config = $hookConfig
  hook_invocations = $hookInvocations
  desktop_package = $packageSnapshot
  desktop_logs = $desktopLogs
  target_session = $targetSession
  conclusion = [ordered]@{
    hook_runner_is_working = $runtimeObserved
    desktop_webview_has_hook_renderer = $uiPipelinePresent
    compact_or_latest_result_surface_hides_hook_icon_in_package = [bool]$packageSnapshot['compact_or_latest_summary_suppresses_hook_icon']
    desktop_message_handler_lost_a_hook_completed_event = ($unknownHookCompletedCount -gt 0)
    session_jsonl_is_not_hook_ui_history_authority = ([bool]$targetSession['requested'] -and [bool]$targetSession['present'] -and -not [bool]$targetSession['hook_items_persisted_in_session_jsonl'])
    local_config_can_fix_runner_but_not_packaged_ui_icon_suppression = $true
  }
  evidence = @(
    if ([bool]$hookConfig['ok']) { 'hooks_json:documented_handler_keys_ok' } else { 'hooks_json:misconfigured' }
    if ($runtimeObserved) { 'hook_invocations:session_start_and_stop_observed' } else { 'hook_invocations:missing_session_start_or_stop' }
    if ($uiPipelinePresent) { 'desktop_package:hook_signal_and_renderer_present' } else { 'desktop_package:hook_signal_or_renderer_missing' }
    if ([bool]$packageSnapshot['compact_or_latest_summary_suppresses_hook_icon']) { 'desktop_package:showHookSummaryIcon_false_observed' } else { 'desktop_package:no_icon_suppression_marker_observed' }
    if ($unknownHookCompletedCount -gt 0) { 'desktop_logs:unknown_hook_completed_observed' } else { 'desktop_logs:no_unknown_hook_completed_observed' }
  )
}

$receiptDir = Split-Path -Parent $ReceiptPath
if (-not [string]::IsNullOrWhiteSpace($receiptDir) -and -not (Test-Path -LiteralPath $receiptDir -PathType Container)) {
  New-Item -ItemType Directory -Path $receiptDir -Force | Out-Null
}
[System.IO.File]::WriteAllText($ReceiptPath, (($receipt | ConvertTo-Json -Depth 20) + [Environment]::NewLine), $utf8NoBom)

$receipt | ConvertTo-Json -Depth 20
if ($status -eq 'blocked') {
  exit 1
}
