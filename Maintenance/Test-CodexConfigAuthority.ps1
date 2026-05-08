param(
  [string]$CodexHome = '',
  [string]$Root = '',
  [string]$DesktopPackageRoot = '',
  [string]$DesktopLogRoot = '',
  [string]$ReceiptPath = '',
  [datetime]$BackupCutoff = [datetime]'2026-05-07T00:00:00',
  [switch]$IncludeHistoricalState,
  [switch]$SkipDesktopPackageScan,
  [switch]$SkipDesktopLogScan
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

function Read-TextFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), $utf8NoBom)
}

function Get-TomlTableBody {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$TableName
  )

  $pattern = "(?ms)^\s*\[$([regex]::Escape($TableName))\]\s*(?<body>.*?)(?=^\s*\[|\z)"
  $match = [regex]::Match($Text, $pattern)
  if (-not $match.Success) {
    return ''
  }
  $match.Groups['body'].Value
}

function Get-TomlBool {
  param(
    [Parameter(Mandatory = $true)][string]$Body,
    [Parameter(Mandatory = $true)][string]$Key
  )

  $match = [regex]::Match($Body, "(?m)^\s*$([regex]::Escape($Key))\s*=\s*(?<value>true|false)\s*(#.*)?$")
  if (-not $match.Success) {
    return $null
  }
  [string]$match.Groups['value'].Value -eq 'true'
}

function Get-TrustedProjectRoots {
  param([Parameter(Mandatory = $true)][string]$UserConfigText)

  $roots = @()
  foreach ($match in [regex]::Matches($UserConfigText, "(?ms)^\[projects\.'(?<path>[^']+)'\]\s*(?<body>.*?)(?=^\[|\z)")) {
    $body = $match.Groups['body'].Value
    if ($body -match '(?m)^\s*trust_level\s*=\s*"trusted"\s*$') {
      $roots += $match.Groups['path'].Value
    }
  }
  foreach ($match in [regex]::Matches($UserConfigText, '(?ms)^\[projects\."(?<path>[^"]+)"\]\s*(?<body>.*?)(?=^\[|\z)')) {
    $body = $match.Groups['body'].Value
    if ($body -match '(?m)^\s*trust_level\s*=\s*"trusted"\s*$') {
      $roots += $match.Groups['path'].Value
    }
  }
  $roots | Select-Object -Unique
}

function Expand-ConfigPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ($Path.StartsWith('~')) {
    return (Join-Path ([Environment]::GetFolderPath('UserProfile')) $Path.Substring(1).TrimStart('\', '/'))
  }
  $Path
}

function Find-ProjectConfigFiles {
  param(
    [AllowEmptyCollection()][string[]]$Roots = @(),
    [Parameter(Mandatory = $true)][string]$CodexHomePath
  )

  $files = @()
  foreach ($rootPath in @($Roots)) {
    if ([string]::IsNullOrWhiteSpace($rootPath)) {
      continue
    }
    $expanded = Expand-ConfigPath -Path $rootPath
    if (-not (Test-Path -LiteralPath $expanded -PathType Container)) {
      continue
    }
    $resolvedRoot = (Resolve-Path -LiteralPath $expanded).Path
    if ($resolvedRoot.TrimEnd('\') -ieq $CodexHomePath.TrimEnd('\')) {
      continue
    }
    $files += @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force -File -Filter 'config.toml' -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '(?i)\\\.codex\\config\.toml$' } |
      Select-Object -ExpandProperty FullName)
  }
  $files | Select-Object -Unique
}

function Test-ConfigFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Layer
  )

  $text = Read-TextFile -Path $Path
  $featuresBody = Get-TomlTableBody -Text $text -TableName 'features'
  $hooks = Get-TomlBool -Body $featuresBody -Key 'hooks'
  $legacyHooks = Get-TomlBool -Body $featuresBody -Key 'codex_hooks'
  $goals = Get-TomlBool -Body $featuresBody -Key 'goals'
  $nonFeatureGoalCommand = Get-TomlBool -Body $featuresBody -Key 'goal_command_enabled'
  $hasLegacyKey = $null -ne $legacyHooks
  $hasNonFeatureGoalCommandKey = $null -ne $nonFeatureGoalCommand

  [ordered]@{
    layer = $Layer
    path = $Path
    features_table_present = -not [string]::IsNullOrWhiteSpace($featuresBody)
    hooks = $hooks
    codex_hooks = $legacyHooks
    goals = $goals
    goal_command_enabled = $nonFeatureGoalCommand
    has_deprecated_codex_hooks_key = $hasLegacyKey
    has_non_feature_goal_command_enabled_key = $hasNonFeatureGoalCommandKey
    ok = (-not $hasLegacyKey) -and (-not $hasNonFeatureGoalCommandKey) -and (($Layer -ne 'user') -or (($hooks -eq $true) -and ($goals -eq $true)))
  }
}

function Find-PreCutoffBackupFiles {
  param(
    [Parameter(Mandatory = $true)][string]$CodexHomePath,
    [Parameter(Mandatory = $true)][datetime]$Cutoff
  )

  $backupFileNamePattern = '(?i)(\.bak($|[._-])|\.backup($|[._-])|\.old$|\.orig$|\.tmp-)'
  @(Get-ChildItem -LiteralPath $CodexHomePath -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.LastWriteTime -lt $Cutoff -and
      $_.FullName -notmatch '(?i)\\sessions\\|\\archived_sessions\\|\\logs_2\.sqlite|\\state_5\.sqlite' -and
      $_.Name -match $backupFileNamePattern
    } |
    ForEach-Object {
      [ordered]@{
        path = $_.FullName
        last_write_time = $_.LastWriteTime.ToString('o')
        length = $_.Length
      }
    })
}

function Find-HistoricalLegacyMentions {
  param([Parameter(Mandatory = $true)][string]$CodexHomePath)

  $historyPatterns = @(
    '.codex-global-state.json',
    'memories\MEMORY.md',
    'Dev_Codex_App_GlobalSSOT\Settings\Codex_App_RUNTIME\*.jsonl',
    'sessions\*.jsonl',
    'archived_sessions\*.jsonl'
  )
  $mentions = @()
  foreach ($pattern in $historyPatterns) {
    $pathPattern = Join-Path $CodexHomePath $pattern
    $files = @(Get-ChildItem -Path $pathPattern -Recurse -Force -File -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
      try {
        $hit = Select-String -LiteralPath $file.FullName -Pattern 'codex_hooks' -SimpleMatch -List -ErrorAction Stop
        if ($hit) {
          $mentions += [ordered]@{
            path = $file.FullName
            source_class = 'historical_non_authority'
          }
        }
      } catch {
      }
    }
  }
  $mentions
}

function Find-DesktopPackageLegacyOverrides {
  param([string]$PackageRoot)

  if ([string]::IsNullOrWhiteSpace($PackageRoot) -or -not (Test-Path -LiteralPath $PackageRoot -PathType Container)) {
    return @()
  }

  $hits = @()
  $candidateFiles = @(
    (Join-Path $PackageRoot 'resources\app.asar'),
    (Join-Path $PackageRoot 'resources\codex.exe'),
    (Join-Path $PackageRoot 'resources\codex')
  )
  foreach ($file in $candidateFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
      continue
    }
    try {
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $text = [System.Text.Encoding]::UTF8.GetString($bytes)
      foreach ($pattern in @('features.codex_hooks', 'codex_hooks')) {
        $index = $text.IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase)
        if ($index -ge 0) {
          $start = [Math]::Max(0, $index - 160)
          $length = [Math]::Min(420, $text.Length - $start)
          $hits += [ordered]@{
            path = $file
            pattern = $pattern
            index = $index
            source_class = if ($file -match 'app\.asar$' -and $pattern -eq 'features.codex_hooks') { 'desktop_internal_legacy_override' } else { 'binary_legacy_alias_catalog_or_code' }
            context = $text.Substring($start, $length)
          }
        }
      }
    } catch {
      $hits += [ordered]@{
        path = $file
        pattern = ''
        index = -1
        source_class = 'scan_error'
        context = $_.Exception.Message
      }
    }
  }
  $hits
}

function Find-DesktopDeprecationLogEvents {
  param([string]$LogRoot)

  if ([string]::IsNullOrWhiteSpace($LogRoot) -or -not (Test-Path -LiteralPath $LogRoot -PathType Container)) {
    return @()
  }

  $events = @()
  $files = @(Get-ChildItem -LiteralPath $LogRoot -Recurse -Force -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^codex-desktop-.*\.log$' })
  foreach ($file in $files) {
    try {
      foreach ($hit in @(Select-String -LiteralPath $file.FullName -Pattern 'codex_hooks.*deprecated|Deprecation notice' -CaseSensitive:$false -ErrorAction Stop)) {
        $timestamp = ''
        $local = ''
        if ($hit.Line -match '^(?<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)') {
          $timestamp = $Matches.ts
          try {
            $utc = [datetime]::ParseExact($timestamp, 'yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
            $local = $utc.ToUniversalTime().AddHours(9).ToString('yyyy-MM-dd HH:mm:ss')
          } catch {
            $local = ''
          }
        }
        $events += [ordered]@{
          path = $file.FullName
          line_number = $hit.LineNumber
          utc = $timestamp
          kst = $local
          line = $hit.Line
        }
      }
    } catch {
    }
  }
  $events | Sort-Object { $_['utc'] }
}

function Get-DesktopProcessSnapshot {
  $items = @()
  foreach ($process in @(Get-Process -Name 'Codex' -ErrorAction SilentlyContinue)) {
    $startUtc = ''
    $startKst = ''
    $processPath = ''
    try {
      $start = $process.StartTime
      $startUtc = $start.ToUniversalTime().ToString('o')
      $startKst = $start.ToUniversalTime().AddHours(9).ToString('yyyy-MM-dd HH:mm:ss')
    } catch {
    }
    try {
      $processPath = [string]$process.Path
    } catch {
      $processPath = ''
    }
    $items += [ordered]@{
      id = $process.Id
      process_name = $process.ProcessName
      path = $processPath
      start_time_utc = $startUtc
      start_time_kst = $startKst
    }
  }
  $items | Sort-Object { $_['start_time_utc'] }
}

function Get-GlobalStateLegacySnapshot {
  param(
    [Parameter(Mandatory = $true)][string]$CodexHomePath,
    [Parameter(Mandatory = $true)][string]$UserConfigPath
  )

  $statePath = Join-Path $CodexHomePath '.codex-global-state.json'
  if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    return [ordered]@{
      path = $statePath
      present = $false
      contains_codex_hooks = $false
      source_class = 'absent'
    }
  }

  $stateItem = Get-Item -LiteralPath $statePath
  $configItem = Get-Item -LiteralPath $UserConfigPath
  $text = Read-TextFile -Path $statePath
  $contains = $text.IndexOf('codex_hooks', [StringComparison]::OrdinalIgnoreCase) -ge 0
  $promptHistoryOnly = $contains -and
    ($text.IndexOf('prompt-history', [StringComparison]::OrdinalIgnoreCase) -ge 0) -and
    ($text.IndexOf('latestConfigNotice', [StringComparison]::OrdinalIgnoreCase) -lt 0) -and
    ($text.IndexOf('configNotice', [StringComparison]::OrdinalIgnoreCase) -lt 0)

  [ordered]@{
    path = $statePath
    present = $true
    last_write_time = $stateItem.LastWriteTime.ToString('o')
    user_config_last_write_time = $configItem.LastWriteTime.ToString('o')
    state_newer_than_user_config = ($stateItem.LastWriteTime -gt $configItem.LastWriteTime)
    contains_codex_hooks = $contains
    prompt_history_only = $promptHistoryOnly
    source_class = if ($promptHistoryOnly) { 'historical_prompt_history_non_authority' } elseif ($contains) { 'app_state_legacy_mention_needs_review' } else { 'no_legacy_mention' }
  }
}

$codexHomeResolved = (Resolve-Path -LiteralPath $CodexHome).Path
$configPath = Join-Path $codexHomeResolved 'config.toml'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
  throw "Missing Codex user config: $configPath"
}

$userConfigText = Read-TextFile -Path $configPath
$trustedRoots = @(Get-TrustedProjectRoots -UserConfigText $userConfigText)
$projectConfigFiles = @(Find-ProjectConfigFiles -Roots $trustedRoots -CodexHomePath $codexHomeResolved)
$configChecks = @()
$configChecks += Test-ConfigFile -Path $configPath -Layer 'user'
foreach ($projectConfig in $projectConfigFiles) {
  $configChecks += Test-ConfigFile -Path $projectConfig -Layer 'trusted_project'
}

$staleBackups = @(Find-PreCutoffBackupFiles -CodexHomePath $codexHomeResolved -Cutoff $BackupCutoff)
$historicalMentions = @()
if ($IncludeHistoricalState) {
  $historicalMentions = @(Find-HistoricalLegacyMentions -CodexHomePath $codexHomeResolved)
}
$desktopPackageLegacyOverrides = @()
if (-not $SkipDesktopPackageScan) {
  $desktopPackageLegacyOverrides = @(Find-DesktopPackageLegacyOverrides -PackageRoot $DesktopPackageRoot)
}
$desktopDeprecationLogEvents = @()
if (-not $SkipDesktopLogScan) {
  $desktopDeprecationLogEvents = @(Find-DesktopDeprecationLogEvents -LogRoot $DesktopLogRoot)
}
$desktopProcesses = @(Get-DesktopProcessSnapshot)
$globalStateLegacySnapshot = Get-GlobalStateLegacySnapshot -CodexHomePath $codexHomeResolved -UserConfigPath $configPath

$earliestDesktopProcessStartUtc = ''
$desktopProcessStartUtcValues = @()
foreach ($process in $desktopProcesses) {
  if (-not [string]::IsNullOrWhiteSpace([string]$process.start_time_utc)) {
    try {
      $desktopProcessStartUtcValues += [datetime]::Parse([string]$process.start_time_utc).ToUniversalTime()
    } catch {
    }
  }
}
if ($desktopProcessStartUtcValues.Count -gt 0) {
  $earliestDesktopProcessStartUtc = ($desktopProcessStartUtcValues | Sort-Object | Select-Object -First 1).ToString('o')
}
$desktopDeprecationsAfterProcessStart = @()
if (-not [string]::IsNullOrWhiteSpace($earliestDesktopProcessStartUtc)) {
  try {
    $processStartUtc = [datetime]::Parse($earliestDesktopProcessStartUtc).ToUniversalTime()
    $desktopDeprecationsAfterProcessStart = @($desktopDeprecationLogEvents | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string]$_.utc) -and
        ([datetime]::ParseExact([string]$_.utc, 'yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime() -ge $processStartUtc)
    })
  } catch {
    $desktopDeprecationsAfterProcessStart = @()
  }
}

$failedConfigChecks = @($configChecks | Where-Object { -not $_.ok })
$status = if ($failedConfigChecks.Count -eq 0 -and $staleBackups.Count -eq 0) { 'verified' } else { 'blocked' }
$hasDesktopInternalLegacyOverride = (@($desktopPackageLegacyOverrides | Where-Object { $_.source_class -eq 'desktop_internal_legacy_override' }).Count -gt 0)
$hasCurrentProcessDeprecation = ($desktopDeprecationsAfterProcessStart.Count -gt 0)
$desktopDeprecationSource = if ($failedConfigChecks.Count -gt 0) {
  'active_config_layer'
} elseif ($hasCurrentProcessDeprecation -and $hasDesktopInternalLegacyOverride) {
  'desktop_internal_legacy_override'
} elseif ($hasCurrentProcessDeprecation) {
  'desktop_notice_cache_or_unclassified_runtime_path'
} elseif ($desktopDeprecationLogEvents.Count -gt 0) {
  'historical_or_in_memory_notice_cache'
} else {
  'none_observed'
}

$receipt = [ordered]@{
  schema_version = 'codex_config_authority_audit.v1'
  checked_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  status = $status
  codex_home = $codexHomeResolved
  user_config = $configPath
  local_authority = [ordered]@{
    current_feature_key = 'features.hooks'
    deprecated_feature_key = 'features.codex_hooks'
    current_goal_feature_key = 'features.goals'
    non_feature_goal_command_key = 'features.goal_command_enabled'
    user_config_must_set_hooks_true = $true
    user_config_must_set_goals_true = $true
    project_configs_must_not_set_codex_hooks = $true
    project_configs_must_not_set_goal_command_enabled = $true
    historical_state_is_not_config_authority = $true
  }
  official_docs_observation = [ordered]@{
    config_basic_url = 'https://developers.openai.com/codex/config-basic'
    config_reference_url = 'https://developers.openai.com/codex/config-reference'
    hooks_url = 'https://developers.openai.com/codex/hooks'
    note = 'Current public docs still mention features.codex_hooks. This audit follows the local app warning and GlobalSSOT policy: use features.hooks in active config.'
  }
  config_checks = $configChecks
  failed_config_checks = $failedConfigChecks
  trusted_project_roots_scanned = $trustedRoots
  trusted_project_config_files_scanned = $projectConfigFiles
  backup_cutoff_local = $BackupCutoff.ToString('o')
  stale_pre_cutoff_backup_files = $staleBackups
  historical_legacy_mentions = $historicalMentions
  app_global_state_legacy_snapshot = $globalStateLegacySnapshot
  desktop_processes = $desktopProcesses
  earliest_desktop_process_start_utc = $earliestDesktopProcessStartUtc
  desktop_package_root = $DesktopPackageRoot
  desktop_internal_legacy_overrides = $desktopPackageLegacyOverrides
  desktop_deprecation_log_events = $desktopDeprecationLogEvents
  desktop_deprecation_log_events_after_current_process_start = $desktopDeprecationsAfterProcessStart
  desktop_cache_sync_assessment = [ordered]@{
    deprecation_source = $desktopDeprecationSource
    likely_in_memory_notice_cache = (($desktopDeprecationLogEvents.Count -gt 0) -and (-not $hasCurrentProcessDeprecation) -and ($failedConfigChecks.Count -eq 0))
    in_memory_notice_cache_clears_on_config_fix = 'not_observed_in_packaged_app_code'
    package_contains_internal_features_codex_hooks_override = $hasDesktopInternalLegacyOverride
    current_process_deprecation_explained_by_internal_override = ($hasCurrentProcessDeprecation -and $hasDesktopInternalLegacyOverride -and ($failedConfigChecks.Count -eq 0))
    deprecation_events_after_current_process_start = $desktopDeprecationsAfterProcessStart.Count
    app_global_state_legacy_mention_is_prompt_history_only = ([string]$globalStateLegacySnapshot.source_class -eq 'historical_prompt_history_non_authority')
    user_config_is_not_root_cause_when_active_config_checks_pass = ($failedConfigChecks.Count -eq 0)
  }
  evidence = @(
    if ($failedConfigChecks.Count -eq 0) { 'active_config_layers:no_deprecated_codex_hooks' } else { 'active_config_layers:deprecated_codex_hooks_found' }
    if ($configChecks[0].hooks -eq $true) { 'user_config:features_hooks_true' } else { 'user_config:features_hooks_missing_or_false' }
    if ($configChecks[0].goals -eq $true) { 'user_config:features_goals_true' } else { 'user_config:features_goals_missing_or_false' }
    if (@($configChecks | Where-Object { $_.has_non_feature_goal_command_enabled_key }).Count -eq 0) { 'active_config_layers:no_non_feature_goal_command_enabled' } else { 'active_config_layers:non_feature_goal_command_enabled_found' }
    if ($staleBackups.Count -eq 0) { 'pre_cutoff_backups:none' } else { 'pre_cutoff_backups:found' }
    if ([string]$globalStateLegacySnapshot.source_class -eq 'historical_prompt_history_non_authority') { 'app_global_state:legacy_mention_prompt_history_only' } elseif ($globalStateLegacySnapshot.contains_codex_hooks) { 'app_global_state:legacy_mention_needs_review' } else { 'app_global_state:no_legacy_mention' }
    if ($hasDesktopInternalLegacyOverride) { 'desktop_package:internal_legacy_override_found' } else { 'desktop_package:no_internal_legacy_override_found' }
    if ($desktopDeprecationLogEvents.Count -gt 0) { 'desktop_logs:deprecation_notice_observed' } else { 'desktop_logs:no_deprecation_notice_observed' }
    if ($desktopDeprecationsAfterProcessStart.Count -eq 0) { 'desktop_logs:no_deprecation_after_current_process_start' } else { 'desktop_logs:deprecation_after_current_process_start' }
    "desktop_logs:deprecation_source:$desktopDeprecationSource"
  )
}

if (-not [string]::IsNullOrWhiteSpace($ReceiptPath)) {
  $receiptDir = Split-Path -Parent $ReceiptPath
  if (-not [string]::IsNullOrWhiteSpace($receiptDir) -and -not (Test-Path -LiteralPath $receiptDir -PathType Container)) {
    New-Item -ItemType Directory -Path $receiptDir -Force | Out-Null
  }
  [System.IO.File]::WriteAllText($ReceiptPath, (($receipt | ConvertTo-Json -Depth 10) + [Environment]::NewLine), $utf8NoBom)
}

$receipt | ConvertTo-Json -Depth 10
if ($status -ne 'verified') {
  exit 1
}
