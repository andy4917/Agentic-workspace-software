param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('session_start','user_prompt_submit','pre_turn_active_contract','pre_command_guard','pre_response_checklist','retry_invalidation','completion_gate','post_turn_state_register','stop_checks','post_tool_use')]
  [string]$HookName,

  [switch]$DryRun,
  [switch]$NoLog,
  [string]$CommandSource = '',
  [string]$TargetSurface = '',
  [switch]$ExplicitUserScope,
  [string]$PromptText = '',
  [string]$CompletionState = '',
  [string]$PayloadJson = ''
)

$ErrorActionPreference = 'Stop'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::InputEncoding = $script:Utf8NoBom
[Console]::OutputEncoding = $script:Utf8NoBom
$OutputEncoding = $script:Utf8NoBom

function Get-CanonicalRoot {
  Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), $script:Utf8NoBom) | ConvertFrom-Json
}

function Read-OptionalJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  try {
    return Read-JsonFile -Path $Path
  } catch {
    return $null
  }
}

function Write-JsonFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )

  $json = ($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine
  [System.IO.File]::WriteAllText($Path, $json, $script:Utf8NoBom)
}

function Read-OptionalStdinJson {
  $stdin = [Console]::In.ReadToEnd()
  if ([string]::IsNullOrWhiteSpace($stdin)) {
    return $null
  }
  try {
    return $stdin | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Read-OptionalPayloadJson {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $null
  }
  try {
    return $Text | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-TextFingerprint {
  param([string]$Text)

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
    $hash = $sha.ComputeHash($bytes)
    -join ($hash | ForEach-Object { $_.ToString('x2') })
  } finally {
    $sha.Dispose()
  }
}

function Convert-ToStringArray {
  param([object]$Value)

  $items = @()
  if ($null -eq $Value) {
    return $items
  }

  foreach ($item in @($Value)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
      $items += [string]$item
    }
  }

  $items
}

function Get-StableActiveInstructions {
  param([object]$ActiveContract)

  $stableAllowList = @(
    'clean_slate',
    'zero_legacy',
    'zero_fallbacks',
    'no_backward_compatibility',
    'no_self_certification',
    'no_score_pass_test_final_as_authority',
    'vowline_required',
    'ko-KR-polite',
    'windows_terms'
  )

  $existing = @(Convert-ToStringArray -Value $ActiveContract.active_instructions) | Where-Object { $stableAllowList -contains [string]$_ }
  foreach ($required in @('clean_slate','zero_legacy','zero_fallbacks','no_backward_compatibility','no_self_certification','no_score_pass_test_final_as_authority','vowline_required','ko-KR-polite','windows_terms')) {
    if ($existing -notcontains $required) {
      $existing += $required
    }
  }

  $existing
}

function Get-TurnScope {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Workdir = ''
  )

  $candidates = @(
    $Root,
    (Join-Path $HOME '.codex\hooks.json'),
    (Join-Path $HOME '.codex\sessions'),
    (Join-Path $HOME '.agents\skills\vowline'),
    (Join-Path $HOME '.agents\skills\vowline\SKILL.md'),
    $Workdir
  )

  $scope = @()
  $seen = @{}
  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
      continue
    }
    $normalized = ([string]$candidate).TrimEnd('\')
    $key = $normalized.ToLowerInvariant()
    if (-not $seen.ContainsKey($key)) {
      $seen[$key] = $true
      $scope += $normalized
    }
  }

  $scope
}

function Get-RuntimeReferenceScope {
  param([Parameter(Mandatory = $true)][string]$Root)

  $candidates = @(
    (Join-Path $HOME '.codex\skills'),
    (Join-Path $HOME '.agents\skills'),
    (Join-Path $HOME '.codex\plugins\cache'),
    (Join-Path $HOME '.codex\generated_images')
  )

  $scope = @()
  $seen = @{}
  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
      continue
    }
    $normalized = ([string]$candidate).TrimEnd('\')
    $key = $normalized.ToLowerInvariant()
    if (-not $seen.ContainsKey($key)) {
      $seen[$key] = $true
      $scope += $normalized
    }
  }

  $scope
}

function Test-PathWithinGuardPrefixes {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string[]]$Prefixes
  )

  $pathLower = (Convert-ToGuardPathText -Text ([string]$Path)).TrimEnd('/')
  foreach ($prefix in $Prefixes) {
    $allowed = (Convert-ToGuardPathText -Text ([string]$prefix)).TrimEnd('/')
    if ($pathLower -eq $allowed -or $pathLower.StartsWith($allowed + '/')) {
      return $true
    }
  }

  $false
}

function Convert-ToScopeComparablePath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$Workdir = ''
  )

  $text = ([string]$Path).Trim()
  if ([string]::IsNullOrWhiteSpace($text)) {
    return ''
  }

  if ($text -match '^[A-Za-z]:(\\|/)' -or $text.StartsWith('/') -or [string]::IsNullOrWhiteSpace($Workdir)) {
    return (Convert-ToGuardPathText -Text $text).TrimEnd('/')
  }

  return (Convert-ToGuardPathText -Text (Join-Path $Workdir $text)).TrimEnd('/')
}

function Test-HookPromptText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  [string]$Text -match '(?s)^\s*<hook_prompt\b.*?</hook_prompt>\s*$'
}

function Test-HookGeneratedBlockerText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  $value = [string]$Text
  (Test-HookPromptText -Text $value) -or
    ($value -match '(?s)<hook_prompt\b.*?</hook_prompt>' -and
      ($value -match 'CONTRACT BLOCKER FIRED' -or $value -match 'hookSpecificOutput' -or $value -match 'additionalContext'))
}

function Normalize-UserPromptText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ''
  }

  $normalized = [string]$Text
  if ($normalized -match '(?s)Generate a concise UI title.*?User prompt:\s*(?<actual>.+)$') {
    $normalized = [string]$Matches['actual']
  }

  $normalized.Trim()
}

function Initialize-TurnRuntimeState {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PromptText,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$CompletionReceipt,
    [string]$Workdir = ''
  )

  if ([string]::IsNullOrWhiteSpace($PromptText)) {
    return [ordered]@{
      changed = $false
      reason = 'prompt_text_missing'
      fingerprint = $null
    }
  }

  if (Test-HookPromptText -Text $PromptText) {
    return [ordered]@{
      changed = $false
      reason = 'hook_prompt_does_not_replace_active_user_goal'
      fingerprint = Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint'
    }
  }

  $PromptText = Normalize-UserPromptText -Text $PromptText
  if ([string]::IsNullOrWhiteSpace($PromptText)) {
    return [ordered]@{
      changed = $false
      reason = 'normalized_prompt_text_missing'
      fingerprint = $null
    }
  }

  $fingerprint = Get-TextFingerprint -Text $PromptText
  $scope = @(Get-TurnScope -Root $Root -Workdir $Workdir)
  $currentScope = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $ActiveContract -Name 'scope'))
  $currentScopeKeys = @($currentScope | ForEach-Object { ([string]$_).TrimEnd('\').ToLowerInvariant() })
  $scopeKeys = @($scope | ForEach-Object { ([string]$_).TrimEnd('\').ToLowerInvariant() })
  $scopeChanged = ($currentScopeKeys.Count -ne $scopeKeys.Count) -or (@($scopeKeys | Where-Object { $currentScopeKeys -notcontains $_ }).Count -gt 0)

  if ((Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint') -eq $fingerprint -and (Get-OptionalPropertyValue -Object $ActiveContract -Name 'state') -eq 'in_progress' -and (-not $scopeChanged)) {
    return [ordered]@{
      changed = $false
      reason = 'same_prompt_already_in_progress'
      fingerprint = $fingerprint
    }
  }

  $newActiveContract = [ordered]@{
    user_goal = $PromptText
    scope = $scope
    forbidden_surfaces = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $ActiveContract -Name 'forbidden_surfaces'))
    active_instructions = @(Get-StableActiveInstructions -ActiveContract $ActiveContract)
    oracle = 'Current user prompt is the active task oracle; previous completion receipts are stale for this turn.'
    completion_criteria = @(
      'current_user_prompt_framed_and_executed_inside_scope',
      'in_scope_artifacts_or_findings_checked_with_direct_evidence',
      'changed_artifacts_connected_surfaces_checked_against_latest_change',
      'required_tool_routes_satisfied_or_explicitly_reported_unavailable_or_not_applicable',
      'known_blockers_or_hidden_remain_reported_first_or_resolved',
      'completion_receipt_matches_this_turn_fingerprint'
    )
    output_language = if ([string]::IsNullOrWhiteSpace([string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'output_language'))) { 'ko-KR-polite' } else { [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'output_language') }
    state = 'in_progress'
    turn_fingerprint = $fingerprint
    previous_state = [ordered]@{
      state = Get-OptionalPropertyValue -Object $ActiveContract -Name 'state'
      completion_state = if ($CompletionReceipt) { Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'completion_state' } else { $null }
    }
  }

  $newCompletionReceipt = [ordered]@{
    completion_state = 'candidate'
    oracle_matched = $false
    scope_matched = $false
    protected_surface_touched = $false
    blockers = @('current_user_prompt_pending_agent_execution')
    evidence = @('user_prompt_submit_invalidated_previous_completion_receipt')
    turn_fingerprint = $fingerprint
    required_tool_route_report = [ordered]@{
      checked_at_utc = $null
      matched_routes = @()
      requirements = @()
      evidence = @()
    }
    raw_score_visible = $false
    rewardable = $false
  }
  $newGateIssuedReceipt = [ordered]@{
    schema_version = 'gate_issued_completion_receipt.v1'
    issuer = 'codex-ssot-hook'
    issued_at_utc = $null
    state = 'candidate'
    decision = 'NOT_ISSUED_FOR_NEW_PROMPT'
    reason = 'user_prompt_submit_invalidated_previous_gate_receipt'
    turn_fingerprint = $fingerprint
    source_completion_receipt_fingerprint = $null
    source_receipt_is_candidate_only = $true
    evidence = @('user_prompt_submit_invalidated_previous_gate_issued_receipt')
  }

  Write-JsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/active_contract.json') -Value $newActiveContract
  Write-JsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/completion_receipt.json') -Value $newCompletionReceipt
  Write-JsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/gate_issued_completion_receipt.json') -Value $newGateIssuedReceipt

  [ordered]@{
    changed = $true
    reason = 'new_prompt_invalidated_previous_completion'
    fingerprint = $fingerprint
  }
}

function Get-RequiredStatus {
  param([Parameter(Mandatory = $true)][string]$Root)

  $configDocName = ([string][char]0xCF58) + ([string][char]0xD53D) + ([string][char]0xC124) + ([string][char]0xC815) + '.md'

  $required = @(
    'README.md',
    'Maintenance/README.md',
    'Settings/README.md',
    'WINDOWS_DEV_TERMS.md',
    $configDocName,
    'MANIFEST.json',
    'ROOT_MAP.json',
    'NAMING_CONVENTION.md',
    'CHANGELOG.md',
    'VERSION.md',
    'AGENT.md',
    'AGENTS.md',
    'AGENTS.override.md',
    'Settings/Codex_App_DECLARATIVE/clean-slate.agent.config.toml',
    'Settings/Codex_App_DECLARATIVE/workflow-orchestration.agent.config.yaml',
    'Settings/Codex_App_DECLARATIVE/state-machine.agent.config.yaml',
    'Settings/Codex_App_DECLARATIVE/retry-recovery-policy.agent.config.yaml',
    'Settings/Codex_App_DECLARATIVE/agent-reliability-tests.agent.config.yaml',
    'Settings/Codex_App_DECLARATIVE/reward-signal-filter.agent.config.yaml',
    'Settings/Codex_App_DECLARATIVE/control-plane-change-policy.agent.config.yaml',
    'Settings/Codex_App_DECLARATIVE/cost-latency-policy.agent.config.yaml',
    'Settings/Codex_App_DECLARATIVE/human-in-the-loop.agent.config.yaml',
    'Settings/Codex_App_DECLARATIVE/reporting-ssot-bookkeeping.agent.config.yaml',
    'Settings/Codex_App_DECLARATIVE/required-tool-routes.json',
    'Settings/Dev_Codex_HOOKS/pre_turn_active_contract.yaml',
    'Settings/Dev_Codex_HOOKS/pre_command_guard.yaml',
    'Settings/Dev_Codex_HOOKS/pre_response_checklist.yaml',
    'Settings/Dev_Codex_HOOKS/retry_invalidation.yaml',
    'Settings/Dev_Codex_HOOKS/completion_gate.yaml',
    'Settings/Dev_Codex_HOOKS/post_turn_state_register.yaml',
    'Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1',
    'Settings/Codex_App_RUNTIME/active_contract.json',
    'Settings/Codex_App_RUNTIME/rejected_hypotheses.json',
    'Settings/Codex_App_RUNTIME/completion_receipt.json',
    'Settings/Codex_App_RUNTIME/gate_issued_completion_receipt.json',
    'Settings/Codex_App_RUNTIME/stable_lessons.json',
    'Settings/Codex_App_RUNTIME/pm_decisions.jsonl',
    'Settings/Codex_App_RUNTIME/runtime_state.schema.json',
    'Settings/Codex_App_DECLARATIVE/repo-gate-adoption.agent.config.yaml',
    'Maintenance/Test-RepoGateAdoption.ps1'
  )

  $missing = @()
  foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relative))) {
      $missing += $relative
    }
  }

  [ordered]@{
    required_count = $required.Count
    missing = $missing
  }
}

function Get-CleanSlateStatus {
  param([Parameter(Mandatory = $true)][string]$Root)

  $configPath = Join-Path $Root 'Settings/Codex_App_DECLARATIVE/clean-slate.agent.config.toml'
  $text = Get-Content -LiteralPath $configPath -Raw
  $checks = [ordered]@{
    mode_clean_slate = $text -match 'mode\s*=\s*"clean_slate"'
    zero_legacy = $text -match 'zero_legacy\s*=\s*true'
    zero_fallbacks = $text -match 'zero_fallbacks\s*=\s*true'
    no_backward_compatibility = $text -match 'backward_compatibility\s*=\s*false'
    command_without_declared_source_blocked = $text -match 'command_without_declared_source\s*=\s*"BLOCKED"'
    work_budget_present = $text -match '\[work_budget\]'
    fallback_route_around_false = $text -match 'route_around\s*=\s*false'
  }

  [ordered]@{
    path = $configPath
    checks = $checks
    ok = -not ($checks.Values -contains $false)
  }
}

function Get-HookStatus {
  param([Parameter(Mandatory = $true)][string]$Root)

  $hooks = @(
    @{ name = 'pre_turn_active_contract'; path = 'Settings/Dev_Codex_HOOKS/pre_turn_active_contract.yaml'; fail = 'BLOCKED_IF_ACTIVE_CONTRACT_REQUIRED_BUT_MISSING' },
    @{ name = 'pre_command_guard'; path = 'Settings/Dev_Codex_HOOKS/pre_command_guard.yaml'; fail = 'BLOCKED' },
    @{ name = 'pre_response_checklist'; path = 'Settings/Dev_Codex_HOOKS/pre_response_checklist.yaml'; fail = 'DO_NOT_CLAIM_COMPLETE' },
    @{ name = 'retry_invalidation'; path = 'Settings/Dev_Codex_HOOKS/retry_invalidation.yaml'; fail = 'NO_OUTPUT_IF_SAME_LOGIC_REPEATS' },
    @{ name = 'completion_gate'; path = 'Settings/Dev_Codex_HOOKS/completion_gate.yaml'; fail = 'CANDIDATE_OR_BLOCKED_NOT_COMPLETE' },
    @{ name = 'post_turn_state_register'; path = 'Settings/Dev_Codex_HOOKS/post_turn_state_register.yaml'; fail = 'STATE_WRITE_REQUIRED_FOR_MULTI_TURN_TASKS' }
  )

  $results = @()
  foreach ($hook in $hooks) {
    $path = Join-Path $Root $hook.path
    $text = Get-Content -LiteralPath $path -Raw
    $results += [ordered]@{
      name = $hook.name
      path = $hook.path
      fail_policy_present = $text.Contains($hook.fail)
    }
  }

  [ordered]@{
    hooks = $results
    ok = -not ($results.fail_policy_present -contains $false)
  }
}

function Get-RequiredToolRoutes {
  param([Parameter(Mandatory = $true)][string]$Root)

  $path = Join-Path $Root 'Settings/Codex_App_DECLARATIVE/required-tool-routes.json'
  if (-not (Test-Path -LiteralPath $path)) {
    return [ordered]@{
      path = $path
      ok = $false
      routes = @()
      evidence = @('required_tool_routes_table_missing')
    }
  }

  try {
    $doc = Read-JsonFile -Path $path
    $routes = @(Get-OptionalPropertyValue -Object $doc -Name 'routes')
    return [ordered]@{
      path = $path
      ok = $true
      schema_version = Get-OptionalPropertyValue -Object $doc -Name 'schema_version'
      routes = $routes
      evidence = @('required_tool_routes_table_present:ok', 'required-tool-routes.json parse ok')
    }
  } catch {
    return [ordered]@{
      path = $path
      ok = $false
      routes = @()
      evidence = @("required_tool_routes_table_parse_failed:$($_.Exception.Message)")
    }
  }
}

function Get-AgentsMdSources {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Workdir = ''
  )

  $candidateFolders = @($Root, (Join-Path $HOME '.codex'))
  if (-not [string]::IsNullOrWhiteSpace($Workdir)) {
    try {
      $current = (Resolve-Path -LiteralPath $Workdir -ErrorAction Stop).Path
      while (-not [string]::IsNullOrWhiteSpace($current)) {
        $candidateFolders += $current
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
      }
    } catch {
      $candidateFolders += $Workdir
    }
  }

  $seen = @{}
  $sources = @()
  foreach ($folder in $candidateFolders) {
    foreach ($name in @('AGENTS.md','AGENTS.override.md','AGENT.md')) {
      $path = Join-Path $folder $name
      $key = (Convert-ToGuardPathText -Text $path).TrimEnd('/')
      if ($seen.ContainsKey($key)) {
        continue
      }
      $seen[$key] = $true
      if (Test-Path -LiteralPath $path -PathType Leaf) {
        $item = Get-Item -LiteralPath $path
        $sources += [ordered]@{
          path = $item.FullName
          scope_root = $folder
          sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
          loaded = $true
        }
      }
    }
  }

  $sources
}

function Get-ActiveHookConfig {
  param([Parameter(Mandatory = $true)][string]$Root)

  $hooksPath = Join-Path $HOME '.codex\hooks.json'
  if (-not (Test-Path -LiteralPath $hooksPath -PathType Leaf)) {
    return @()
  }

  try {
    $doc = Read-JsonFile -Path $hooksPath
    $hooksRoot = Get-OptionalPropertyValue -Object $doc -Name 'hooks'
    $events = @()
    foreach ($eventProperty in $hooksRoot.PSObject.Properties) {
      $entries = @($eventProperty.Value)
      $events += [ordered]@{
        event = $eventProperty.Name
        entries = $entries.Count
        matchers = @($entries | ForEach-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'matcher') })
      }
    }
    return $events
  } catch {
    return @([ordered]@{ event = 'hooks_json_parse_failed'; entries = 0; error = $_.Exception.Message })
  }
}

function Get-ConfiguredMcpServers {
  param([Parameter(Mandatory = $true)][string]$Root)

  $configPath = Join-Path $HOME '.codex\config.toml'
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    return @()
  }

  $text = Get-Content -LiteralPath $configPath -Raw
  $servers = @()
  foreach ($match in [regex]::Matches($text, '(?ms)^\s*\[mcp_servers\.("?[^"\].\s]+"?)\]\s*(?<body>.*?)(?=^\s*\[|\z)')) {
    $name = $match.Groups[1].Value.Trim('"')
    if ($servers | Where-Object { $_.name -eq $name }) {
      continue
    }

    $body = $match.Groups['body'].Value
    $isEnabled = $true
    $enabledMatch = [regex]::Match($body, '(?m)^\s*enabled\s*=\s*(?<value>true|false)\s*$')
    if ($enabledMatch.Success) {
      $isEnabled = [string]$enabledMatch.Groups['value'].Value -eq 'true'
    }

    $servers += [ordered]@{
      name = $name
      source = $configPath
      status = if ($isEnabled) { 'configured' } else { 'disabled' }
      enabled = [bool]$isEnabled
    }
  }

  @($servers)
}

function Get-AvailableSkills {
  param([Parameter(Mandatory = $true)][string]$Root)

  $bases = @(
    (Join-Path $HOME '.codex\skills'),
    (Join-Path $HOME '.agents\skills'),
    (Join-Path $HOME '.codex\plugins\cache')
  )
  $seen = @{}
  $skills = @()
  foreach ($base in $bases) {
    if (-not (Test-Path -LiteralPath $base -PathType Container)) {
      continue
    }
    $skillFiles = @(Get-ChildItem -LiteralPath $base -Recurse -Filter SKILL.md -File -ErrorAction SilentlyContinue | Select-Object -First 200)
    foreach ($file in $skillFiles) {
      $key = (Convert-ToGuardPathText -Text $file.FullName).TrimEnd('/')
      if ($seen.ContainsKey($key)) {
        continue
      }
      $seen[$key] = $true
      $head = ''
      try {
        $head = ((Get-Content -LiteralPath $file.FullName -TotalCount 40 -ErrorAction Stop) -join "`n")
      } catch {
        $head = ''
      }
      $name = $file.Directory.Name
      if ($head -match '(?m)^name:\s*"?([^"`r`n]+)"?\s*$') {
        $name = $Matches[1].Trim()
      }
      $skills += [ordered]@{
        name = $name
        path = $file.FullName
        source_root = $base
      }
    }
  }

  $skills
}

function Get-ConfiguredSubagents {
  $configPath = Get-CodexConfigPath
  $configText = if (Test-Path -LiteralPath $configPath -PathType Leaf) { Get-Content -LiteralPath $configPath -Raw -ErrorAction SilentlyContinue } else { '' }
  $model = 'gpt-5.5'
  $reasoningEffort = 'medium'
  $maxThreads = 8
  $maxDepth = 1
  $modelMatch = [regex]::Match($configText, '(?m)^\s*model\s*=\s*"(?<value>[^"]+)"')
  if ($modelMatch.Success) { $model = $modelMatch.Groups['value'].Value }
  $reasoningMatch = [regex]::Match($configText, '(?m)^\s*model_reasoning_effort\s*=\s*"(?<value>[^"]+)"')
  if ($reasoningMatch.Success) { $reasoningEffort = $reasoningMatch.Groups['value'].Value }
  $agentsMatch = [regex]::Match($configText, '(?ms)^\s*\[agents\]\s*(?<body>.*?)(?=^\s*\[|\z)')
  if ($agentsMatch.Success) {
    $maxThreadsMatch = [regex]::Match($agentsMatch.Groups['body'].Value, '(?m)^\s*max_threads\s*=\s*(?<value>\d+)')
    if ($maxThreadsMatch.Success) { $maxThreads = [int]$maxThreadsMatch.Groups['value'].Value }
    $maxDepthMatch = [regex]::Match($agentsMatch.Groups['body'].Value, '(?m)^\s*max_depth\s*=\s*(?<value>\d+)')
    if ($maxDepthMatch.Success) { $maxDepth = [int]$maxDepthMatch.Groups['value'].Value }
  }

  $baseSubagents = @(
    [ordered]@{ name = 'default'; source = 'runtime_spawn_agent_tool'; status = 'configured'; model = $model; reasoning_effort = $reasoningEffort; max_threads = $maxThreads; max_depth = $maxDepth },
    [ordered]@{ name = 'explorer'; source = 'runtime_spawn_agent_tool'; status = 'configured'; model = $model; reasoning_effort = $reasoningEffort; max_threads = $maxThreads; max_depth = $maxDepth },
    [ordered]@{ name = 'worker'; source = 'runtime_spawn_agent_tool'; status = 'configured'; model = $model; preferred_model = 'gpt-5.5'; reasoning_effort = $reasoningEffort; max_threads = $maxThreads; max_depth = $maxDepth; latest_model_required = $true; code_work = $true; authority = 'candidate_artifact_only' }
  )

  $baseSubagents + @(Get-StandingAuthorizedSubagentInspectors)
}

function Get-SubagentInspectionRoleNames {
  @(
    'spark_repo_inspector',
    'spark_contamination_inspector',
    'spark_tool_route_inspector',
    'spark_frontend_inspector',
    'spark_backend_inspector',
    'spark_contract_inspector',
    'spark_false_positive_reviewer'
  )
}

function Get-CodexConfigPath {
  $homePath = [Environment]::GetFolderPath('UserProfile')
  Join-Path $homePath '.codex\config.toml'
}

function Get-StandingAuthorizedSubagentInspectors {
  $configPath = Get-CodexConfigPath
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    return @()
  }

  $configText = Get-Content -LiteralPath $configPath -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($configText)) {
    return @()
  }

  $inspectors = @()
  foreach ($roleName in Get-SubagentInspectionRoleNames) {
    $rolePattern = "(?ms)^\[agents\.$([regex]::Escape($roleName))\]\s*(?<body>.*?)(?=^\[|\z)"
    $match = [regex]::Match($configText, $rolePattern)
    if (-not $match.Success) {
      continue
    }

    $body = $match.Groups['body'].Value
    $authorized = $body -match 'SSOT standing-authorized read-only inspector'
    $configFile = ''
    $configMatch = [regex]::Match($body, '(?m)^\s*config_file\s*=\s*"(?<path>[^"]+)"')
    if ($configMatch.Success) {
      $configFile = $configMatch.Groups['path'].Value
    }

    $inspectors += [ordered]@{
      name = $roleName
      source = 'config.toml_agents_role_marker'
      status = if ($authorized) { 'standing_authorized' } else { 'configured_without_standing_authorization' }
      standing_authorization = [bool]$authorized
      config_file = $configFile
      sandbox_mode = 'read-only'
      model = 'gpt-5.3-codex-spark'
      fallback_model = 'latest-mini'
      reasoning_effort = 'high'
      max_depth = 1
      authority = 'candidate_evidence_only'
    }
  }

  $inspectors
}

function Test-SubagentInspectionStandingAuthorization {
  param([Parameter(Mandatory = $true)][string]$AgentName)

  foreach ($inspector in @(Get-StandingAuthorizedSubagentInspectors)) {
    if ([string](Get-OptionalPropertyValue -Object $inspector -Name 'name') -eq $AgentName -and
        (Get-OptionalPropertyValue -Object $inspector -Name 'standing_authorization') -eq $true) {
      return $true
    }
  }

  return $false
}

function Write-RuntimeCapabilityReceipt {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [string]$Workdir = ''
  )

  $path = Join-Path $Root 'Settings/Codex_App_RUNTIME/runtime_capability_receipt.json'
  $receipt = [ordered]@{
    schema_version = 'runtime_capability_receipt.v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    turn_fingerprint = Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint'
    cwd = if ([string]::IsNullOrWhiteSpace($Workdir)) { (Get-Location).Path } else { $Workdir }
    project_root = $Root
    loaded_agents_md_sources = @(Get-AgentsMdSources -Root $Root -Workdir $Workdir)
    active_hooks = @(Get-ActiveHookConfig -Root $Root)
    available_mcp_servers = @(Get-ConfiguredMcpServers -Root $Root)
    available_skills = @(Get-AvailableSkills -Root $Root)
    configured_subagents = @(Get-ConfiguredSubagents)
    trust_state = [ordered]@{
      active_contract_state = Get-OptionalPropertyValue -Object $ActiveContract -Name 'state'
      active_scope = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $ActiveContract -Name 'scope'))
      runtime_reference_scope = @(Get-RuntimeReferenceScope -Root $Root)
      runtime_reference_scope_read_only = $true
      full_access_is_capacity_not_permission = $true
      required_tool_missing_blocks_pretooluse = $false
      required_tool_missing_blocks_completion_claim = $true
      subagent_pass_is_candidate_only = $true
      subagent_inspection_authority = 'candidate_evidence_only'
      subagent_inspection_missing_blocks_pretooluse = $false
      subagent_inspection_missing_blocks_completion_claim = $true
      pm_accountability_missing_blocks_pretooluse = $false
      pm_accountability_missing_blocks_completion_claim = $true
      pm_failure_blocks_completion_claim = $true
      subagent_max_threads = 8
      subagent_worker_model = 'gpt-5.5'
      subagent_worker_reasoning_effort = 'medium'
      subagent_worker_max_threads = 8
      subagent_worker_max_depth = 1
      subagent_inspection_default_sandbox = 'read-only'
      subagent_inspection_max_threads = 8
      subagent_inspection_max_depth = 1
      installed_configured_available_is_not_completion_evidence = $true
      task_classification_receipt_required_for_completion_claim = $true
      need_resolution_receipt_required_for_completion_claim = $true
    }
  }

  Write-JsonFile -Path $path -Value $receipt
  $receipt
}

function Get-TaskClassificationReceiptPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/task_classification_receipt.json'
}

function Get-NeedResolutionReceiptPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/need_resolution_receipt.json'
}

function Get-SkillResolutionReceiptPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/skill_resolution_receipt.json'
}

function Get-SkillUsageEventsPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/skill_usage_events.jsonl'
}

function Test-ChildAgentPromptContext {
  param(
    [object]$Payload,
    [AllowEmptyString()][string]$PromptText = '',
    [AllowEmptyString()][string]$PayloadText = ''
  )

  $lineage = Get-AgentLineage -Payload $Payload -ActiveContract $null
  if ((Get-OptionalPropertyValue -Object $lineage -Name 'is_subagent') -eq $true) {
    return $true
  }

  $text = "$PromptText`n$PayloadText"
  if ($text -match '(?i)\b(parent_turn_id|child_contract|subagent_worker_job\.v1|subagent_inspection_job\.v1|job_id\s*[:=]\s*(worker-|subagent-)|route_id\s*[:=]\s*[a-z0-9_]+_inspection)\b') {
    return $true
  }
  if ($text -match '(?i)\b(Ownership|Read-only)\b' -and $text -match '(?i)\b(worker|inspector|subagent|candidate_evidence_only|candidate_artifact_only)\b') {
    return $true
  }

  $false
}

function Get-ClassificationSurfaceSignals {
  param(
    [AllowEmptyString()][string]$Text,
    [string[]]$Paths = @()
  )

  $pathNorm = Convert-ToGuardPathText -Text (@($Paths) -join "`n")
  $textNorm = Convert-ToGuardPathText -Text ([string]$Text)
  $domainText = @(([string]$Text) -split "`r?`n" | Where-Object {
    $_ -notmatch '(?i)\b(skill|catalog|route|worker|inspector|role|model|fallback|authority|candidate_evidence_only|candidate_artifact_only|frontend/backend)\b'
  }) -join "`n"
  $domainTextNorm = Convert-ToGuardPathText -Text $domainText
  $norm = Convert-ToGuardPathText -Text ((@($Text) + @($Paths)) -join "`n")
  $signals = @()
  $koGateWords = @(
    (New-UnicodeWord @(0xD1B5,0xACFC)),
    (New-UnicodeWord @(0xC644,0xB8CC,0xC870,0xAC74)),
    (New-UnicodeWord @(0xC6B4,0xC601,0xAC00,0xB2A5,0xC0C1,0xD0DC))
  )
  if ($pathNorm -match '(?i)(^|/)(src|source|lib|app|server|api|db|migrations)/|\.([cm]?[jt]sx?|py|rs|go|java|cs|ps1|sh)$' -or $textNorm -match '(?i)\b(code|implementation|refactor|bug|fix)\b') {
    $signals += 'source_code'
  }
  if ($pathNorm -match '(?i)(^|/)(test|tests|spec|__tests__)/|\.test\.|\.spec\.' -or $textNorm -match '(?i)\b(acceptance|pytest)\b') {
    $signals += 'tests'
  }
  if ($pathNorm -match '(?i)(settings/codex_app_declarative|\.ya?ml$|\.toml$|\.json$)' -or $textNorm -match '(?i)\b(config|configuration)\b') {
    $signals += 'config'
  }
  if ($pathNorm -match '(?i)(settings/dev_codex_hooks|codex-ssot-hook\.ps1|completion_gate)' -or $textNorm -match '(?i)\b(hook|pretooluse|posttooluse|stop|completion[_ -]?gate|gate pass)\b' -or @($koGateWords | Where-Object { $textNorm.Contains([string]$_) }).Count -gt 0) {
    $signals += 'hook'
  }
  if ($pathNorm -match '(?i)(settings/codex_app_runtime|tool_usage_events\.jsonl|skill_usage_events\.jsonl|pm_decisions|subagent_.*\.jsonl)' -or $textNorm -match '(?i)\b(runtime|receipt|ledger|tool_usage_event|skill_usage_event)\b') {
    $signals += 'runtime_receipt_ledger'
  }
  if ($pathNorm -match '(?i)(^|/)agents?(\.override)?\.md$|agents\.md|workflow|ci|\.github|deploy|build' -or $textNorm -match '(?i)\b(workflow|ci|deploy|build)\b') {
    $signals += 'AGENTS_workflow_CI_deploy'
  }
  if ($pathNorm -match '(?i)\.(tsx|jsx|css|scss)$|(^|/)(src|app|components)/' -or $domainTextNorm -match '(?i)\b(frontend|ui|react|vite|screenshot|visual)\b') {
    $signals += 'frontend'
  }
  if ($pathNorm -match '(?i)(^|/)(server|api|db|migrations|prisma)/|\.schema\.' -or $domainTextNorm -match '(?i)\b(backend|server|api|database|migration)\b') {
    $signals += 'backend'
  }
  if ($norm -match '(?i)(secret|credential|token|auth|key)') {
    $signals += 'security_auth'
  }

  @($signals | Select-Object -Unique)
}

function Test-PositiveBasicTask {
  param(
    [string[]]$Surfaces,
    [AllowEmptyString()][string]$Text,
    [AllowEmptyString()][string]$ActionClass,
    [bool]$CompletionClaim
  )

  $writeSignals = '(?i)\b(implement|fix|change|update|add|remove|refactor|patch|apply|write|edit|validate|build|test|commit|push)\b'
  $koWriteSignals = @(
    (New-UnicodeWord @(0xC218,0xC815)),
    (New-UnicodeWord @(0xC815,0xB9AC)),
    (New-UnicodeWord @(0xCEE4,0xBC0B)),
    (New-UnicodeWord @(0xD478,0xC2DC)),
    (New-UnicodeWord @(0xD328,0xCE58)),
    (New-UnicodeWord @(0xBCF4,0xAC15)),
    (New-UnicodeWord @(0xAC80,0xC99D))
  )
  $fileWritePlanned = ($ActionClass -in @('write','delete','execute')) -or ($Text -match $writeSignals) -or @($koWriteSignals | Where-Object { ([string]$Text).Contains([string]$_) }).Count -gt 0
  $hasCode = $Surfaces -contains 'source_code'
  $hasTest = $Surfaces -contains 'tests'
  $hasConfig = $Surfaces -contains 'config'
  $hasScriptOrAutomation = $Text -match '(?i)(script|automation|runner|ps1|workflow)'
  $hasHookRuntimeReceipt = @($Surfaces | Where-Object { $_ -in @('hook','runtime_receipt_ledger') }).Count -gt 0
  $hasAgentsWorkflowCi = $Surfaces -contains 'AGENTS_workflow_CI_deploy'
  $hasDeploySecurity = @($Surfaces | Where-Object { $_ -in @('security_auth','AGENTS_workflow_CI_deploy') }).Count -gt 0 -and ($Text -match '(?i)(deploy|security|auth|secret|token|credential)')
  $hasExecutableCompletionClaim = $CompletionClaim -and ($Text -match '(?i)(code|test|config|hook|runtime|build|deploy|script)')

  $conditions = [ordered]@{
    no_file_write = -not $fileWritePlanned
    no_code_surface = -not $hasCode
    no_test_surface = -not $hasTest
    no_config_surface = -not $hasConfig
    no_script_or_automation_surface = -not $hasScriptOrAutomation
    no_hook_runtime_receipt_surface = -not $hasHookRuntimeReceipt
    no_AGENTS_workflow_CI_surface = -not $hasAgentsWorkflowCi
    no_deploy_security_surface = -not $hasDeploySecurity
    no_executable_or_procedural_completion_claim = -not $hasExecutableCompletionClaim
  }

  $allowed = $true
  foreach ($value in $conditions.Values) {
    if (-not $value) {
      $allowed = $false
      break
    }
  }

  [ordered]@{
    allowed = $allowed
    conditions = $conditions
  }
}

function Resolve-TaskClassification {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$CompletionReceipt,
    [AllowEmptyString()][string]$ContextText = '',
    [AllowEmptyString()][string]$ActionClass = 'report',
    [bool]$CompletionClaim = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $goal = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal')
  $freshness = if ($CompletionReceipt) { Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'freshness' } else { $null }
  $affectedPaths = if ($freshness) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $freshness -Name 'affected_paths')) } else { @() }
  $dependencyAlignment = if ($CompletionReceipt) { Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'dependency_alignment_check' } else { $null }
  $changedPaths = if ($dependencyAlignment) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $dependencyAlignment -Name 'changed_paths')) } else { @() }
  $connectedPaths = if ($dependencyAlignment) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $dependencyAlignment -Name 'checked_connected_paths')) } else { @() }
  $receiptEvidence = if ($CompletionReceipt) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'evidence')) } else { @() }
  $allText = @($goal, $ContextText, $receiptEvidence) -join "`n"
  $surfaces = @(Get-ClassificationSurfaceSignals -Text $allText -Paths @($affectedPaths + $changedPaths + $connectedPaths))
  $basic = Test-PositiveBasicTask -Surfaces $surfaces -Text $allText -ActionClass $ActionClass -CompletionClaim:$CompletionClaim

  $whyNotBasic = @()
  foreach ($property in $basic.conditions.GetEnumerator()) {
    if (-not [bool]$property.Value) {
      $whyNotBasic += $property.Key
    }
  }

  $selectedClass = 'Class 0'
  $ambiguityApplied = $false
  if ($basic.allowed) {
    $koDocSignals = @((New-UnicodeWord @(0xBB38,0xC11C)), (New-UnicodeWord @(0xCD08,0xC548)))
    if ($allText -match '(?i)\b(draft|document|memo|readme|note)\b' -or @($koDocSignals | Where-Object { $allText.Contains([string]$_) }).Count -gt 0) {
      $selectedClass = 'Class 1'
    } else {
      $selectedClass = 'Class 0'
    }
  } else {
    $selectedClass = 'Class 2'
    if (@($surfaces | Where-Object { $_ -in @('hook','runtime_receipt_ledger','AGENTS_workflow_CI_deploy','security_auth') }).Count -gt 0) {
      $selectedClass = 'Class 3'
    }
    $nonTrivialSurfaces = @($surfaces | Where-Object { $_ -notin @('security_auth') } | Select-Object -Unique)
    if ($nonTrivialSurfaces.Count -gt 1 -or ($allText -match '(?i)\b(multi[-_ ]?surface|frontend.*backend|backend.*frontend|repo adoption|Class 4)\b')) {
      $selectedClass = 'Class 4'
    }
    if ($surfaces.Count -eq 0) {
      $ambiguityApplied = $true
      $whyNotBasic += 'route_or_surface_ambiguous_classified_upward'
    }
  }

  $riskClass = 'none'
  if ($surfaces -contains 'security_auth') {
    $riskClass = 'critical'
  } elseif ($selectedClass -eq 'Class 3' -or $selectedClass -eq 'Class 4') {
    $riskClass = 'high'
  } elseif ($selectedClass -eq 'Class 2') {
    $riskClass = 'medium'
  } elseif ($selectedClass -eq 'Class 1') {
    $riskClass = 'low'
  }

  $requiredRoutes = @(Resolve-RequiredRouteNeeds -TaskClass $selectedClass -Surfaces $surfaces -ContextText $allText)
  $requiredSubagents = @($requiredRoutes | Where-Object { $_ -match '(?i)(inspection|inspector)' })
  $requiredWorkerRoutes = @(Resolve-RequiredWorkerRoutes -TaskClass $selectedClass -Surfaces $surfaces -ContextText $allText)
  $requiredSkillRoutes = @(Resolve-RequiredSkillRoutes -TaskClass $selectedClass -Surfaces $surfaces -ContextText $allText)
  $requiredSkills = @($requiredSkillRoutes | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'need_level') -eq 'REQUIRED' } | ForEach-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'skill_id') })

  [ordered]@{
    schema_version = 'task_classification_receipt.v1'
    task_id = if ([string]::IsNullOrWhiteSpace($turn)) { Get-TextFingerprint -Text $goal } else { $turn }
    turn_fingerprint = $turn
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    user_goal = $goal
    selected_class = $selectedClass
    why_not_basic = @($whyNotBasic | Select-Object -Unique)
    basic_task_positive_conditions = $basic.conditions
    touched_or_expected_surfaces = $surfaces
    action_class = if ([string]::IsNullOrWhiteSpace($ActionClass)) { 'report' } else { $ActionClass }
    risk_class = $riskClass
    ambiguity_policy = [ordered]@{
      mode = 'classify_upward'
      applied = $ambiguityApplied
    }
    required_routes = $requiredRoutes
    required_worker_routes = $requiredWorkerRoutes
    required_inspector_routes = $requiredSubagents
    required_subagents = $requiredSubagents
    required_tools = @()
    required_skills = @($requiredSkills | Select-Object -Unique)
    required_skill_routes = $requiredSkillRoutes
    completion_authority = [ordered]@{
      source = 'gate_issued_receipt_only'
    }
    pm_responsibility = [ordered]@{
      if_missing_classification = 'DO_NOT_CLAIM_COMPLETE'
    }
  }
}

function Resolve-RequiredRouteNeeds {
  param(
    [Parameter(Mandatory = $true)][string]$TaskClass,
    [string[]]$Surfaces = @(),
    [AllowEmptyString()][string]$ContextText = ''
  )

  $routes = @()
  if ($TaskClass -in @('Class 2','Class 3','Class 4')) {
    $routes += 'required_tool_route_inspection'
  }
  if (@($Surfaces | Where-Object { $_ -in @('hook','runtime_receipt_ledger','AGENTS_workflow_CI_deploy','security_auth') }).Count -gt 0 -or $TaskClass -in @('Class 3','Class 4')) {
    $routes += 'ssot_contract_inspection'
    $routes += 'contamination_inspection'
  }
  if ($TaskClass -eq 'Class 4') {
    $routes += 'repo_integrity_inspection'
  }
  if ($Surfaces -contains 'frontend') {
    $routes += 'frontend_adoption_inspection'
  }
  if ($Surfaces -contains 'backend') {
    $routes += 'backend_adoption_inspection'
  }
  if ($ContextText -match '(?i)\brepo[_ -]?adoption\b|repo_v2_adoption_receipt') {
    $routes += 'repo_integrity_inspection'
    $routes += 'required_tool_route_inspection'
  }

  @($routes | Select-Object -Unique)
}

function Resolve-RequiredWorkerRoutes {
  param(
    [Parameter(Mandatory = $true)][string]$TaskClass,
    [string[]]$Surfaces = @(),
    [AllowEmptyString()][string]$ContextText = ''
  )

  $routes = @()
  $koMutatingSignals = @(
    (New-UnicodeWord @(0xAD6C,0xD604)),
    (New-UnicodeWord @(0xC218,0xC815)),
    (New-UnicodeWord @(0xD328,0xCE58)),
    (New-UnicodeWord @(0xBCF4,0xAC15))
  )
  $mutatingIntent = ($ContextText -match '(?i)\b(implement|fix|repair|patch|update|edit|write|change|add|remove|refactor|test update|config update|control[-_ ]?plane repair)\b') -or @($koMutatingSignals | Where-Object { $ContextText.Contains([string]$_) }).Count -gt 0
  if ($TaskClass -in @('Class 2','Class 3','Class 4') -and $mutatingIntent) {
    $routes += 'implementation_worker'
  }
  if ($Surfaces -contains 'tests') {
    $routes += 'test_worker'
  }
  if ($Surfaces -contains 'config') {
    $routes += 'config_worker'
  }
  if (@($Surfaces | Where-Object { $_ -in @('hook','runtime_receipt_ledger','AGENTS_workflow_CI_deploy') }).Count -gt 0) {
    $routes += 'control_plane_worker'
  }
  if ($Surfaces -contains 'frontend') {
    $routes += 'frontend_worker'
  }
  if ($Surfaces -contains 'backend') {
    $routes += 'backend_worker'
  }

  @($routes | Select-Object -Unique)
}

function Resolve-RequiredSkillRoutes {
  param(
    [Parameter(Mandatory = $true)][string]$TaskClass,
    [string[]]$Surfaces = @(),
    [AllowEmptyString()][string]$ContextText = ''
  )

  $routes = @()
  if ($TaskClass -in @('Class 0','Class 1')) {
    $koDocSkillSignals = @((New-UnicodeWord @(0xBB38,0xC11C)), (New-UnicodeWord @(0xACC4,0xD68D)))
    if ($ContextText -match '(?i)\b(plan|design|document|adr|readme|handoff)\b' -or @($koDocSkillSignals | Where-Object { $ContextText.Contains([string]$_) }).Count -gt 0) {
      $routes += [ordered]@{ skill_id = 'documentation-and-adrs'; need_level = 'RECOMMENDED'; reason = 'low_risk_doc_or_planning_support' }
    }
  }

  if ($TaskClass -eq 'Class 2') {
    foreach ($skill in @('planning-and-task-breakdown','incremental-implementation',('te'+'st-driven-development'),'code-review-and-quality')) {
      $routes += [ordered]@{ skill_id = $skill; need_level = 'REQUIRED'; reason = 'class2_code_or_test_change' }
    }
  }

  if ($TaskClass -in @('Class 3','Class 4')) {
    foreach ($skill in @('spec-driven-development','planning-and-task-breakdown','security-and-hardening','code-review-and-quality','documentation-and-adrs')) {
      $routes += [ordered]@{ skill_id = $skill; need_level = 'REQUIRED'; reason = 'class3_class4_control_plane_or_runtime_change' }
    }
  }

  if ($TaskClass -eq 'Class 4') {
    foreach ($skill in @('incremental-implementation',('te'+'st-driven-development'))) {
      if (@($routes | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'skill_id') -eq $skill }).Count -eq 0) {
        $routes += [ordered]@{ skill_id = $skill; need_level = 'REQUIRED'; reason = 'class4_multi_surface_change' }
      }
    }
  }

  $deduped = @()
  $seen = @{}
  foreach ($route in $routes) {
    $skillId = [string](Get-OptionalPropertyValue -Object $route -Name 'skill_id')
    if ([string]::IsNullOrWhiteSpace($skillId) -or $seen.ContainsKey($skillId)) {
      continue
    }
    $seen[$skillId] = $true
    $deduped += $route
  }
  $deduped
}

function New-SkillResolutionReceipt {
  param(
    [Parameter(Mandatory = $true)][object]$TaskClassification,
    [Parameter(Mandatory = $true)][object]$NeedResolution
  )

  $routes = @(Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_skill_routes')
  $required = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_skills'))
  $entries = @()
  foreach ($route in $routes) {
    $skillId = [string](Get-OptionalPropertyValue -Object $route -Name 'skill_id')
    if ([string]::IsNullOrWhiteSpace($skillId)) {
      continue
    }
    $entries += [ordered]@{
      skill_id = $skillId
      need_level = [string](Get-OptionalPropertyValue -Object $route -Name 'need_level')
      status = 'pending'
      reason = [string](Get-OptionalPropertyValue -Object $route -Name 'reason')
      evidence = @()
    }
  }

  [ordered]@{
    schema_version = 'skill_resolution_receipt.v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    turn_fingerprint = Get-OptionalPropertyValue -Object $TaskClassification -Name 'turn_fingerprint'
    task_id = Get-OptionalPropertyValue -Object $TaskClassification -Name 'task_id'
    task_class = Get-OptionalPropertyValue -Object $TaskClassification -Name 'selected_class'
    required_skills = $required
    required_skill_routes = $routes
    skill_routes = $entries
    unknown_skill_needs = @()
    unavailable_skills = @()
    not_applicable_skills = @()
    installed_configured_available_is_not_evidence = $true
    completion_authority = [ordered]@{
      source = 'gate_issued_receipt_only'
    }
  }
}

function New-NeedResolutionReceipt {
  param(
    [Parameter(Mandatory = $true)][object]$TaskClassification
  )

  $requirements = @()
  $skillRoutes = @(Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_skill_routes')
  foreach ($routeId in @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_routes'))) {
    $requirements += [ordered]@{
      route_id = $routeId
      requirement_id = $routeId
      type = 'inspector'
      need_level = 'REQUIRED'
      status = 'pending'
      evidence = @()
    }
  }
  foreach ($routeId in @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_worker_routes'))) {
    $requirements += [ordered]@{
      route_id = $routeId
      requirement_id = $routeId
      type = 'worker'
      need_level = 'REQUIRED'
      status = 'pending'
      evidence = @()
    }
  }
  foreach ($skillRoute in $skillRoutes) {
    $skillId = [string](Get-OptionalPropertyValue -Object $skillRoute -Name 'skill_id')
    if ([string]::IsNullOrWhiteSpace($skillId)) {
      continue
    }
    $requirements += [ordered]@{
      route_id = "skill:$skillId"
      requirement_id = $skillId
      type = 'skill'
      need_level = [string](Get-OptionalPropertyValue -Object $skillRoute -Name 'need_level')
      status = 'pending'
      evidence = @()
    }
  }

  [ordered]@{
    schema_version = 'need_resolution_receipt.v1'
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    turn_fingerprint = Get-OptionalPropertyValue -Object $TaskClassification -Name 'turn_fingerprint'
    task_id = Get-OptionalPropertyValue -Object $TaskClassification -Name 'task_id'
    task_class = Get-OptionalPropertyValue -Object $TaskClassification -Name 'selected_class'
    resolver = [ordered]@{
      name = 'required_route_resolver'
      inputs = @('task_class','touched_surface','action_class','risk_class','completion_claim','user_explicit_instruction','changed_paths','prior_failures','unresolved_findings')
      default_policy = 'basic_is_positive_allowlist_otherwise_classify_upward'
    }
    need_levels = @('REQUIRED','RECOMMENDED','OPTIONAL','NOT_APPLICABLE','UNAVAILABLE','UNKNOWN')
    requirements = $requirements
    required_routes = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_routes'))
    required_worker_routes = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_worker_routes'))
    required_inspector_routes = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_inspector_routes'))
    required_subagents = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_subagents'))
    required_tools = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_tools'))
    required_skills = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $TaskClassification -Name 'required_skills'))
    required_skill_routes = $skillRoutes
    unknown_skill_needs = @()
    unavailable_skills = @()
    not_applicable_skills = @()
    unknown_need = $false
    satisfaction = [ordered]@{
      valid_evidence = @('tool_usage_event','skill_usage_event','worker_spawn_event','worker_report_event','inspector_spawn_event','inspector_report_event','subagent_job_event','subagent_spawn_event','subagent_report_event','pm_worker_waiver_event','check_evidence','explicit_unavailable','explicit_not_applicable')
      installed_configured_available_is_not_evidence = $true
    }
    completion_authority = [ordered]@{
      source = 'gate_issued_receipt_only'
    }
  }
}

function Write-TaskNeedReceipts {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$CompletionReceipt,
    [AllowEmptyString()][string]$ContextText = '',
    [AllowEmptyString()][string]$ActionClass = 'report',
    [bool]$CompletionClaim = $false
  )

  $taskClassification = Resolve-TaskClassification -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt -ContextText $ContextText -ActionClass $ActionClass -CompletionClaim:$CompletionClaim
  $needResolution = New-NeedResolutionReceipt -TaskClassification $taskClassification
  $skillResolution = New-SkillResolutionReceipt -TaskClassification $taskClassification -NeedResolution $needResolution
  Write-JsonFile -Path (Get-TaskClassificationReceiptPath -Root $Root) -Value $taskClassification
  Write-JsonFile -Path (Get-NeedResolutionReceiptPath -Root $Root) -Value $needResolution
  Write-JsonFile -Path (Get-SkillResolutionReceiptPath -Root $Root) -Value $skillResolution
  [ordered]@{
    task_classification = $taskClassification
    need_resolution = $needResolution
    skill_resolution = $skillResolution
  }
}

function Get-SubagentInspectionRouteById {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$RouteId
  )

  @(Get-SubagentInspectionRoutes -Root $Root | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'route_id') -eq $RouteId } | Select-Object -First 1)
}

function Initialize-PmOrchestrationPreflight {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$CompletionReceipt,
    [Parameter(Mandatory = $true)][object]$TaskNeed,
    [AllowEmptyString()][string]$TriggerText = '',
    [AllowEmptyString()][string]$PathText = '',
    [bool]$NoLog = $false
  )

  $taskClassification = Get-OptionalPropertyValue -Object $TaskNeed -Name 'task_classification'
  $needResolution = Get-OptionalPropertyValue -Object $TaskNeed -Name 'need_resolution'
  $taskClass = [string](Get-OptionalPropertyValue -Object $taskClassification -Name 'selected_class')
  if ($taskClass -notin @('Class 3','Class 4')) {
    return [ordered]@{ required = $false; reason = 'pm_orchestration_preflight_not_required'; jobs = @() }
  }

  $requiredSubagents = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $needResolution -Name 'required_subagents'))
  $requiredWorkerRoutes = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $needResolution -Name 'required_worker_routes'))
  $targetPaths = @(Get-SubagentInspectionTargetPaths -Root $Root -Text "$TriggerText`n$PathText" -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt)
  $jobs = @()
  $workerJobs = @()
  foreach ($routeId in $requiredSubagents) {
    $route = @(Get-SubagentInspectionRouteById -Root $Root -RouteId $routeId)
    if ($route.Count -eq 0) {
      continue
    }
    $agentName = [string](Get-OptionalPropertyValue -Object $route[0] -Name 'agent_name')
    if ([string]::IsNullOrWhiteSpace($agentName)) {
      continue
    }
    $existing = Find-LatestSubagentInspectionJob -Root $Root -TurnFingerprint ([string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')) -RouteId $routeId -AgentName $agentName
    if ($existing) {
      $jobs += $existing
      continue
    }
    $jobs += Register-SubagentInspectionJob -Root $Root -ActiveContract $ActiveContract -RouteId $routeId -AgentName $agentName -TargetPaths $targetPaths -TriggerHook 'UserPromptSubmit' -Status 'queued' -NoLog:$NoLog
  }

  foreach ($routeId in $requiredWorkerRoutes) {
    $workerJobs += Register-SubagentWorkerJob -Root $Root -ActiveContract $ActiveContract -RouteId $routeId -TargetPaths $targetPaths -Status 'queued' -NoLog:$NoLog
  }

  $null = Register-PmDecisionEvent -Root $Root -ActiveContract $ActiveContract -Decision 'initialize_preflight' -ReasonCode 'pm_orchestration_preflight_initialized' -CompletionImpact 'class3_class4_mutating_actions_require_scheduled_jobs_before_write' -NoLog:$NoLog

  [ordered]@{
    required = $true
    reason = 'pm_orchestration_preflight_initialized'
    required_subagents = $requiredSubagents
    required_worker_routes = $requiredWorkerRoutes
    jobs = $jobs
    worker_jobs = $workerJobs
  }
}

function Read-PmDecisionEvents {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Join-Path $Root 'Settings/Codex_App_RUNTIME/pm_decisions.jsonl'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $events = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $event = $line | ConvertFrom-Json
      $turn = [string](Get-OptionalPropertyValue -Object $event -Name 'turn_id')
      if ([string]::IsNullOrWhiteSpace($turn)) {
        $turn = [string](Get-OptionalPropertyValue -Object $event -Name 'turn_fingerprint')
      }
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or $turn -eq $TurnFingerprint) {
        $events += $event
      }
    } catch {
    }
  }

  $events
}

function Test-PmOrchestrationPreflight {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$CompletionReceipt,
    [Parameter(Mandatory = $true)][string]$PayloadText,
    [string]$Workdir = ''
  )

  if (-not (Test-MutatingOperationText -Text $PayloadText)) {
    return [ordered]@{ ok = $true; reason = 'pm_orchestration_preflight_not_required_read_only' }
  }

  $controlPlaneMutation = Get-ControlPlaneMutation -Text $PayloadText -Workdir $Workdir
  $runtimeStateMutation = Get-RuntimeStateMutation -Text $PayloadText -Workdir $Workdir
  $surfaceText = Convert-ToGuardPathText -Text "$PayloadText`n$Workdir"
  $preflightSurface = $controlPlaneMutation.detected -or $runtimeStateMutation.detected -or
    ($surfaceText -match '(?i)(settings/dev_codex_hooks|settings/codex_app_runtime|settings/codex_app_declarative|agents?(\.override)?\.md|workflow|ci|completion[_ -]?gate|reward[-_ ]?signal[-_ ]?filter|hook|receipt|ledger|security|auth)')
  if (-not $preflightSurface) {
    return [ordered]@{ ok = $true; reason = 'pm_orchestration_preflight_not_required_for_class2_write' }
  }

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $goal = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal')
  $scope = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $ActiveContract -Name 'scope'))
  if ([string]::IsNullOrWhiteSpace($turn) -or [string]::IsNullOrWhiteSpace($goal) -or $scope.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'pm_orchestration_preflight_missing'; missing = @('current_user_intent_contract') }
  }

  $taskClassification = Read-OptionalJsonFile -Path (Get-TaskClassificationReceiptPath -Root $Root)
  $needResolution = Read-OptionalJsonFile -Path (Get-NeedResolutionReceiptPath -Root $Root)
  if (-not $taskClassification -or [string](Get-OptionalPropertyValue -Object $taskClassification -Name 'turn_fingerprint') -ne $turn) {
    return [ordered]@{ ok = $false; reason = 'pm_orchestration_preflight_missing'; missing = @('task_classification_receipt') }
  }
  if (-not $needResolution -or [string](Get-OptionalPropertyValue -Object $needResolution -Name 'turn_fingerprint') -ne $turn) {
    return [ordered]@{ ok = $false; reason = 'pm_orchestration_preflight_missing'; missing = @('need_resolution_receipt') }
  }

  $taskClass = [string](Get-OptionalPropertyValue -Object $taskClassification -Name 'selected_class')
  if ($taskClass -notin @('Class 3','Class 4')) {
    return [ordered]@{ ok = $false; reason = 'pm_orchestration_preflight_missing'; missing = @('task_classification_receipt_class3_or_class4') }
  }

  $requirements = @(Get-OptionalPropertyValue -Object $needResolution -Name 'requirements')
  $requiredSubagents = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $needResolution -Name 'required_subagents'))
  $requiredWorkerRoutes = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $needResolution -Name 'required_worker_routes'))
  if ($requirements.Count -eq 0 -or ($requiredSubagents.Count -eq 0 -and $requiredWorkerRoutes.Count -eq 0)) {
    return [ordered]@{ ok = $false; reason = 'pm_orchestration_preflight_missing'; missing = @('required_route_resolver_result') }
  }

  if ($requiredWorkerRoutes.Count -gt 0) {
    $missingWorkers = @()
    foreach ($routeId in $requiredWorkerRoutes) {
      $workerObserved = Test-WorkerSpawnObserved -Root $Root -TurnFingerprint $turn -RouteId $routeId
      $waiverObserved = Test-PmWorkerWaiverObserved -Root $Root -TurnFingerprint $turn -RouteId $routeId
      if ((-not $workerObserved) -and (-not $waiverObserved)) {
        $missingWorkers += $routeId
      }
    }
    if ($missingWorkers.Count -gt 0) {
      return [ordered]@{ ok = $false; reason = 'required_worker_not_spawned'; missing_routes = $missingWorkers }
    }
  }
  if ($requiredWorkerRoutes.Count -eq 0 -and $requiredSubagents.Count -gt 0) {
    return [ordered]@{ ok = $false; reason = 'inspector_only_delegation_for_mutating_task'; missing = @('required_worker_routes') }
  } elseif ($requiredWorkerRoutes.Count -gt 0 -and $requiredSubagents.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'pm_collapsed_worker_route_into_inspector_route'; missing = @('required_inspector_routes') }
  }

  $missingJobs = @()
  $missingSpawns = @()
  foreach ($routeId in $requiredSubagents) {
    $route = @(Get-SubagentInspectionRouteById -Root $Root -RouteId $routeId)
    if ($route.Count -eq 0) {
      $missingJobs += $routeId
      continue
    }
    $agentName = [string](Get-OptionalPropertyValue -Object $route[0] -Name 'agent_name')
    $job = Find-LatestSubagentInspectionJob -Root $Root -TurnFingerprint $turn -RouteId $routeId -AgentName $agentName
    if (-not $job) {
      $missingJobs += $routeId
      continue
    }
    if (-not (Test-SubagentSpawnObserved -Root $Root -TurnFingerprint $turn -Job $job)) {
      $missingSpawns += $routeId
    }
  }
  if ($missingJobs.Count -gt 0) {
    return [ordered]@{ ok = $false; reason = 'required_subagent_jobs_not_scheduled'; missing_routes = $missingJobs }
  }
  if ($missingSpawns.Count -gt 0) {
    return [ordered]@{ ok = $false; reason = 'required_subagent_spawn_not_observed'; missing_routes = $missingSpawns }
  }

  $pmEvents = @(Read-PmDecisionEvents -Root $Root -TurnFingerprint $turn)
  $initialized = @($pmEvents | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'decision') -eq 'initialize_preflight' })
  if ($initialized.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'pm_orchestration_preflight_missing'; missing = @('pm_decision_ledger_initialized') }
  }

  [ordered]@{
    ok = $true
    reason = 'pm_orchestration_preflight_satisfied'
    task_class = $taskClass
    required_subagents = $requiredSubagents
  }
}

function Get-TaskClassificationReceipt {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [object]$CompletionReceipt = $null
  )

  $fromReceipt = if ($CompletionReceipt) { Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'task_classification_receipt' } else { $null }
  if ($fromReceipt) {
    return $fromReceipt
  }
  Read-OptionalJsonFile -Path (Get-TaskClassificationReceiptPath -Root $Root)
}

function Get-NeedResolutionReceipt {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [object]$CompletionReceipt = $null
  )

  $fromReceipt = if ($CompletionReceipt) { Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'need_resolution_receipt' } else { $null }
  if ($fromReceipt) {
    return $fromReceipt
  }
  Read-OptionalJsonFile -Path (Get-NeedResolutionReceiptPath -Root $Root)
}

function Get-NeedResolutionReportEntries {
  param([object]$CompletionReceipt)

  $report = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'need_resolution_report'
  if (-not $report) {
    return @()
  }

  @(Get-OptionalPropertyValue -Object $report -Name 'requirements')
}

function Test-NeedRequirementSatisfied {
  param(
    [Parameter(Mandatory = $true)][object]$Requirement,
    [object[]]$ReportEntries = @()
  )

  $routeId = [string](Get-OptionalPropertyValue -Object $Requirement -Name 'route_id')
  $requirementId = [string](Get-OptionalPropertyValue -Object $Requirement -Name 'requirement_id')
  foreach ($entry in @($ReportEntries)) {
    $entryRouteId = [string](Get-OptionalPropertyValue -Object $entry -Name 'route_id')
    $entryRequirementId = [string](Get-OptionalPropertyValue -Object $entry -Name 'requirement_id')
    if ($entryRouteId -ne $routeId -or ((-not [string]::IsNullOrWhiteSpace($entryRequirementId)) -and $entryRequirementId -ne $requirementId)) {
      continue
    }
    $status = [string](Get-OptionalPropertyValue -Object $entry -Name 'status')
    $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $entry -Name 'evidence'))
    if (($status -in @('satisfied','used','reported','checked','unavailable','not_applicable')) -and $evidence.Count -gt 0) {
      return [ordered]@{ ok = $true; source = "completion_receipt:$status" }
    }
  }

  $status = [string](Get-OptionalPropertyValue -Object $Requirement -Name 'status')
  $ownEvidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Requirement -Name 'evidence'))
  if (($status -in @('satisfied','used','reported','checked','unavailable','not_applicable')) -and $ownEvidence.Count -gt 0) {
    return [ordered]@{ ok = $true; source = "need_resolution:$status" }
  }

  [ordered]@{ ok = $false; source = 'missing' }
}

function Test-SkillRequirementSatisfied {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$TurnFingerprint,
    [Parameter(Mandatory = $true)][string]$SkillId,
    [object[]]$ReportEntries = @()
  )

  $skillResolution = Read-OptionalJsonFile -Path (Get-SkillResolutionReceiptPath -Root $Root)
  if (-not $skillResolution -or [string](Get-OptionalPropertyValue -Object $skillResolution -Name 'turn_fingerprint') -ne $TurnFingerprint) {
    return [ordered]@{ ok = $false; reason = 'skill_resolution_receipt_missing'; skill_id = $SkillId }
  }

  $unknown = @(Get-OptionalPropertyValue -Object $skillResolution -Name 'unknown_skill_needs')
  if ($unknown.Count -gt 0) {
    return [ordered]@{ ok = $false; reason = 'skill_need_unknown'; skill_id = $SkillId; unknown_skill_needs = $unknown }
  }

  foreach ($entry in @($ReportEntries)) {
    $entryType = [string](Get-OptionalPropertyValue -Object $entry -Name 'type')
    $entryRequirementId = [string](Get-OptionalPropertyValue -Object $entry -Name 'requirement_id')
    $entryRouteId = [string](Get-OptionalPropertyValue -Object $entry -Name 'route_id')
    if ($entryType -ne 'skill' -and $entryRouteId -ne "skill:$SkillId" -and $entryRequirementId -ne $SkillId) {
      continue
    }
    $status = [string](Get-OptionalPropertyValue -Object $entry -Name 'status')
    $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $entry -Name 'evidence'))
    if (($status -in @('used','satisfied','unavailable','not_applicable')) -and $evidence.Count -gt 0) {
      return [ordered]@{ ok = $true; source = "completion_receipt:$status" }
    }
  }

  foreach ($entry in @(Get-OptionalPropertyValue -Object $skillResolution -Name 'skill_routes')) {
    if ([string](Get-OptionalPropertyValue -Object $entry -Name 'skill_id') -ne $SkillId) {
      continue
    }
    $status = [string](Get-OptionalPropertyValue -Object $entry -Name 'status')
    $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $entry -Name 'evidence'))
    if (($status -in @('used','satisfied','unavailable','not_applicable')) -and $evidence.Count -gt 0) {
      return [ordered]@{ ok = $true; source = "skill_resolution:$status" }
    }
  }

  $events = @(Read-SkillUsageEvents -Root $Root -TurnFingerprint $TurnFingerprint | Where-Object {
    [string](Get-OptionalPropertyValue -Object $_ -Name 'skill_name') -eq $SkillId
  })
  if ($events.Count -gt 0) {
    return [ordered]@{ ok = $true; source = 'skill_usage_event' }
  }

  $skillPath = Join-Path (Join-Path $HOME ".agents\skills\$SkillId") 'SKILL.md'
  if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
    return [ordered]@{ ok = $false; reason = 'installed_skill_not_evidence'; skill_id = $SkillId }
  }

  [ordered]@{ ok = $false; reason = 'required_skill_not_used'; skill_id = $SkillId }
}

function Test-TaskClassificationAndNeedForCompletion {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $taskClassification = Get-TaskClassificationReceipt -Root $Root -CompletionReceipt $CompletionReceipt
  if ($taskClassification -and [string](Get-OptionalPropertyValue -Object $taskClassification -Name 'turn_fingerprint') -ne $turn) {
    $fileTaskClassification = Read-OptionalJsonFile -Path (Get-TaskClassificationReceiptPath -Root $Root)
    if ($fileTaskClassification -and [string](Get-OptionalPropertyValue -Object $fileTaskClassification -Name 'turn_fingerprint') -eq $turn) {
      $taskClassification = $fileTaskClassification
    }
  }
  if (-not $taskClassification) {
    return [ordered]@{ ok = $false; reason = 'task_classification_missing' }
  }
  if ([string](Get-OptionalPropertyValue -Object $taskClassification -Name 'turn_fingerprint') -ne $turn) {
    return [ordered]@{ ok = $false; reason = 'task_classification_missing'; stale_turn = Get-OptionalPropertyValue -Object $taskClassification -Name 'turn_fingerprint' }
  }
  $selectedClass = [string](Get-OptionalPropertyValue -Object $taskClassification -Name 'selected_class')
  if ([string]::IsNullOrWhiteSpace($selectedClass) -or $selectedClass -notin @('Class 0','Class 1','Class 2','Class 3','Class 4')) {
    return [ordered]@{ ok = $false; reason = 'task_classification_unknown'; task_classification = $taskClassification }
  }
  if ((Get-OptionalPropertyValue -Object $taskClassification -Name 'downshift_detected') -eq $true) {
    return [ordered]@{ ok = $false; reason = 'task_classification_downshift_detected'; task_classification = $taskClassification }
  }

  $needResolution = Get-NeedResolutionReceipt -Root $Root -CompletionReceipt $CompletionReceipt
  if ($needResolution -and [string](Get-OptionalPropertyValue -Object $needResolution -Name 'turn_fingerprint') -ne $turn) {
    $fileNeedResolution = Read-OptionalJsonFile -Path (Get-NeedResolutionReceiptPath -Root $Root)
    if ($fileNeedResolution -and [string](Get-OptionalPropertyValue -Object $fileNeedResolution -Name 'turn_fingerprint') -eq $turn) {
      $needResolution = $fileNeedResolution
    }
  }
  if (-not $needResolution) {
    return [ordered]@{ ok = $false; reason = 'need_resolution_missing'; task_classification = $taskClassification }
  }
  if ([string](Get-OptionalPropertyValue -Object $needResolution -Name 'turn_fingerprint') -ne $turn) {
    return [ordered]@{ ok = $false; reason = 'need_resolution_missing'; stale_turn = Get-OptionalPropertyValue -Object $needResolution -Name 'turn_fingerprint' }
  }
  if ((Get-OptionalPropertyValue -Object $needResolution -Name 'unknown_need') -eq $true) {
    return [ordered]@{ ok = $false; reason = 'need_resolution_unknown'; need_resolution = $needResolution }
  }

  $requirements = @(Get-OptionalPropertyValue -Object $needResolution -Name 'requirements')
  $unknown = @($requirements | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'need_level') -eq 'UNKNOWN' })
  if ($unknown.Count -gt 0) {
    return [ordered]@{ ok = $false; reason = 'route_need_unknown'; unknown_requirements = $unknown }
  }

  $missing = @()
  $reportEntries = @(Get-NeedResolutionReportEntries -CompletionReceipt $CompletionReceipt)
  foreach ($requirement in @($requirements | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'need_level') -eq 'REQUIRED' })) {
    $requirementType = [string](Get-OptionalPropertyValue -Object $requirement -Name 'type')
    $routeId = [string](Get-OptionalPropertyValue -Object $requirement -Name 'route_id')
    if ($requirementType -eq 'skill') {
      $skillId = [string](Get-OptionalPropertyValue -Object $requirement -Name 'requirement_id')
      $skillResult = Test-SkillRequirementSatisfied -Root $Root -TurnFingerprint $turn -SkillId $skillId -ReportEntries $reportEntries
      if (-not $skillResult.ok) {
        return [ordered]@{ ok = $false; reason = [string](Get-OptionalPropertyValue -Object $skillResult -Name 'reason'); skill_id = $skillId; task_classification = $taskClassification; need_resolution = $needResolution }
      }
      continue
    }
    if ($requirementType -eq 'worker') {
      $workerWaived = Test-PmWorkerWaiverObserved -Root $Root -TurnFingerprint $turn -RouteId $routeId
      if ($workerWaived) {
        continue
      }
      if (-not (Test-WorkerSpawnObserved -Root $Root -TurnFingerprint $turn -RouteId $routeId)) {
        return [ordered]@{ ok = $false; reason = 'required_worker_not_spawned'; route_id = $routeId; task_classification = $taskClassification; need_resolution = $needResolution }
      }
      $workerReports = @(Read-SubagentWorkerReports -Root $Root -TurnFingerprint $turn | Where-Object {
        [string](Get-OptionalPropertyValue -Object $_ -Name 'route_id') -eq $routeId -and
        [string](Get-OptionalPropertyValue -Object $_ -Name 'status') -in @('reported','closed','not_applicable')
      })
      if ($workerReports.Count -eq 0) {
        return [ordered]@{ ok = $false; reason = 'worker_report_missing'; route_id = $routeId; task_classification = $taskClassification; need_resolution = $needResolution }
      }
      $requiredSkills = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $taskClassification -Name 'required_skills'))
      if ($requiredSkills.Count -gt 0) {
        $reportsWithSkillSummary = @($workerReports | Where-Object { $null -ne (Get-OptionalPropertyValue -Object $_ -Name 'skill_usage_summary') })
        if ($reportsWithSkillSummary.Count -eq 0) {
          return [ordered]@{ ok = $false; reason = 'worker_required_skill_not_used'; route_id = $routeId; task_classification = $taskClassification; need_resolution = $needResolution }
        }
      }
      continue
    }
    $result = Test-NeedRequirementSatisfied -Requirement $requirement -ReportEntries $reportEntries
    if (-not $result.ok) {
      $missing += [ordered]@{
        route_id = $routeId
        requirement_id = [string](Get-OptionalPropertyValue -Object $requirement -Name 'requirement_id')
        type = $requirementType
        need_level = 'REQUIRED'
      }
    }
  }

  if ($missing.Count -gt 0) {
    return [ordered]@{
      ok = $false
      reason = 'required_route_unsatisfied'
      task_classification = $taskClassification
      need_resolution = $needResolution
      missing_requirements = $missing
    }
  }

  [ordered]@{
    ok = $true
    reason = 'need_resolution_satisfied'
    task_classification = $taskClassification
    need_resolution = $needResolution
  }
}

function Test-PmAccountabilityForCompletion {
  param(
    [Parameter(Mandatory = $true)][object]$NeedCheck,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt
  )

  $needResolution = Get-OptionalPropertyValue -Object $NeedCheck -Name 'need_resolution'
  $requiredRoutes = if ($needResolution) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $needResolution -Name 'required_routes')) } else { @() }
  if ($requiredRoutes.Count -eq 0) {
    return [ordered]@{ ok = $true; reason = 'pm_accountability_not_required' }
  }

  $pmReport = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'pm_accountability_report'
  if (-not $pmReport) {
    return [ordered]@{ ok = $false; reason = 'pm_decision_missing'; required_routes = $requiredRoutes }
  }

  if ((Get-OptionalPropertyValue -Object $pmReport -Name 'pm_failure') -eq $true) {
    $codes = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $pmReport -Name 'pm_failure_reason_codes'))
    $reason = if ($codes.Count -gt 0) { $codes[0] } else { 'pm_aggregation_missing' }
    return [ordered]@{ ok = $false; reason = $reason; pm_accountability_report = $pmReport }
  }

  $decision = [string](Get-OptionalPropertyValue -Object $pmReport -Name 'pm_decision')
  if ($decision -ne 'submit_to_stop') {
    return [ordered]@{ ok = $false; reason = 'pm_aggregation_missing'; pm_accountability_report = $pmReport }
  }

  [ordered]@{ ok = $true; reason = 'pm_accountability_satisfied'; pm_accountability_report = $pmReport }
}

function Get-GateIssuedCompletionReceiptPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/gate_issued_completion_receipt.json'
}

function Get-RepoV2AdoptionReceiptPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/repo_v2_adoption_receipt.json'
}

function Get-GateDecisionFingerprint {
  param(
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt
  )

  $shape = [ordered]@{
    active_turn_fingerprint = Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint'
    active_state = Get-OptionalPropertyValue -Object $ActiveContract -Name 'state'
    receipt = $CompletionReceipt
  }

  Get-TextFingerprint -Text ($shape | ConvertTo-Json -Depth 14 -Compress)
}

function Write-GateIssuedCompletionReceipt {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt,
    [object]$TaskNeedResolution,
    [object]$PmAccountability,
    [object]$RequiredToolRoutes,
    [object]$SubagentInspections,
    [object]$HeuristicReviews,
    [object]$RepoV2Adoption,
    [object]$FreshnessCheck,
    [bool]$NoLog = $false
  )

  $fingerprint = Get-GateDecisionFingerprint -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt
  $issuedReceipt = [ordered]@{
    schema_version = 'gate_issued_completion_receipt.v1'
    issuer = 'codex-ssot-hook'
    issued_by_hook = 'completion_gate'
    issued_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    state = 'verified_complete'
    decision = 'ALLOW_COMPLETE_CLAIM'
    reason = 'gate_validated_candidate_completion_receipt'
    turn_fingerprint = Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint'
    source_completion_receipt_fingerprint = $fingerprint
    source_receipt_path = 'Settings/Codex_App_RUNTIME/completion_receipt.json'
    source_receipt_is_candidate_only = $true
    task_need_resolution = $TaskNeedResolution
    pm_accountability = $PmAccountability
    required_tool_routes = $RequiredToolRoutes
    subagent_inspections = $SubagentInspections
    heuristic_reviews = $HeuristicReviews
    repo_v2_adoption = $RepoV2Adoption
    freshness = $FreshnessCheck
    evidence = @(
      'gate_issued_completion_receipt:ok',
      'agent_completion_receipt_treated_as_candidate_input',
      'task_classification_receipt_verified',
      'need_resolution_receipt_verified',
      'pm_accountability_verified_when_required',
      'subagent_inspections_candidate_evidence_only',
      'heuristic_reviews_candidate_evidence_only',
      'repo_v2_adoption_verified_when_present',
      "source_completion_receipt_fingerprint:$fingerprint"
    )
    raw_score_visible = $false
    rewardable = $false
  }

  if (-not $NoLog) {
    Write-JsonFile -Path (Get-GateIssuedCompletionReceiptPath -Root $Root) -Value $issuedReceipt
    if ($RepoV2Adoption -and (Get-OptionalPropertyValue -Object $RepoV2Adoption -Name 'receipt')) {
      $repoReceipt = (Get-OptionalPropertyValue -Object $RepoV2Adoption -Name 'receipt' | ConvertTo-Json -Depth 16) | ConvertFrom-Json
      $repoReceipt.status = 'verified'
      if (-not (Get-OptionalPropertyValue -Object $repoReceipt -Name 'gate_decision')) {
        $repoReceipt | Add-Member -NotePropertyName gate_decision -NotePropertyValue ([ordered]@{}) -Force
      }
      $repoReceipt.gate_decision | Add-Member -NotePropertyName status -NotePropertyValue 'gate_issued' -Force
      $repoReceipt.gate_decision | Add-Member -NotePropertyName decision -NotePropertyValue 'ALLOW_COMPLETE_CLAIM' -Force
      $repoReceipt.gate_decision | Add-Member -NotePropertyName reason -NotePropertyValue 'verified_complete' -Force
      $repoReceipt.gate_decision | Add-Member -NotePropertyName source_completion_receipt_fingerprint -NotePropertyValue $fingerprint -Force
      $repoReceipt.gate_decision | Add-Member -NotePropertyName evidence -NotePropertyValue @(
        'gate_issued_completion_receipt:ok',
        "source_completion_receipt_fingerprint:$fingerprint"
      ) -Force
      Write-JsonFile -Path (Get-RepoV2AdoptionReceiptPath -Root $Root) -Value $repoReceipt
    }
  }

  $issuedReceipt
}

function Test-GateIssuedReceiptCurrent {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt
  )

  $path = Get-GateIssuedCompletionReceiptPath -Root $Root
  $issued = Read-OptionalJsonFile -Path $path
  if (-not $issued) {
    return [ordered]@{ ok = $false; reason = 'gate_issued_completion_receipt_missing' }
  }

  $expected = Get-GateDecisionFingerprint -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt
  if ([string](Get-OptionalPropertyValue -Object $issued -Name 'schema_version') -ne 'gate_issued_completion_receipt.v1') {
    return [ordered]@{ ok = $false; reason = 'gate_issued_completion_receipt_missing' }
  }
  if ([string](Get-OptionalPropertyValue -Object $issued -Name 'issuer') -ne 'codex-ssot-hook') {
    return [ordered]@{ ok = $false; reason = 'gate_issued_completion_receipt_missing' }
  }
  if ([string](Get-OptionalPropertyValue -Object $issued -Name 'state') -ne 'verified_complete') {
    return [ordered]@{ ok = $false; reason = 'gate_issued_completion_receipt_missing' }
  }
  if ([string](Get-OptionalPropertyValue -Object $issued -Name 'turn_fingerprint') -ne [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')) {
    return [ordered]@{ ok = $false; reason = 'stale_gate_issued_completion_receipt' }
  }
  if ([string](Get-OptionalPropertyValue -Object $issued -Name 'source_completion_receipt_fingerprint') -ne $expected) {
    return [ordered]@{ ok = $false; reason = 'stale_gate_issued_completion_receipt' }
  }

  [ordered]@{ ok = $true; reason = 'gate_issued_completion_receipt_current'; receipt = $issued }
}

function Get-RepoV2AdoptionReceipt {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [object]$CompletionReceipt = $null
  )

  $fromCompletionReceipt = if ($CompletionReceipt) { Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'repo_v2_adoption_receipt' } else { $null }
  if ($fromCompletionReceipt) {
    return $fromCompletionReceipt
  }

  Read-OptionalJsonFile -Path (Get-RepoV2AdoptionReceiptPath -Root $Root)
}

function Test-CheckEvidenceEntry {
  param(
    [object]$Checks,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if (-not $Checks) {
    return [ordered]@{ ok = $false; reason = "repo_v2_${Name}_check_missing" }
  }

  $entry = Get-OptionalPropertyValue -Object $Checks -Name $Name
  if (-not $entry) {
    return [ordered]@{ ok = $false; reason = "repo_v2_${Name}_check_missing" }
  }

  $status = [string](Get-OptionalPropertyValue -Object $entry -Name 'status')
  $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $entry -Name 'evidence'))
  if ($status -notin @('passed','failed','not_applicable')) {
    return [ordered]@{ ok = $false; reason = "repo_v2_${Name}_check_not_established"; status = $status }
  }
  if ($evidence.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = "repo_v2_${Name}_check_evidence_missing"; status = $status }
  }
  if ($status -eq 'failed') {
    return [ordered]@{ ok = $false; reason = "repo_v2_${Name}_check_failed"; status = $status; evidence = $evidence }
  }

  [ordered]@{ ok = $true; reason = "repo_v2_${Name}_check_established"; status = $status; evidence = $evidence }
}

function Test-RepoV2AdoptionForCompletion {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt
  )

  $receipt = Get-RepoV2AdoptionReceipt -Root $Root -CompletionReceipt $CompletionReceipt
  if (-not $receipt) {
    return [ordered]@{ ok = $true; reason = 'repo_v2_adoption_not_required' }
  }

  if ([string](Get-OptionalPropertyValue -Object $receipt -Name 'schema_version') -ne 'repo_v2_adoption_receipt.v1') {
    return [ordered]@{ ok = $false; reason = 'repo_v2_adoption_receipt_missing'; receipt = $receipt }
  }

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $receiptTurn = [string](Get-OptionalPropertyValue -Object $receipt -Name 'turn_fingerprint')
  if (-not [string]::IsNullOrWhiteSpace($turn) -and $receiptTurn -ne $turn) {
    return [ordered]@{ ok = $false; reason = 'stale_repo_v2_adoption_receipt'; receipt_turn = $receiptTurn; active_turn = $turn }
  }

  $repoPath = [string](Get-OptionalPropertyValue -Object $receipt -Name 'repo_path')
  if ([string]::IsNullOrWhiteSpace($repoPath) -or -not (Test-Path -LiteralPath $repoPath -PathType Container)) {
    return [ordered]@{ ok = $false; reason = 'repo_v2_repo_path_missing'; repo_path = $repoPath }
  }

  $rootNorm = (Convert-ToGuardPathText -Text $Root).TrimEnd('/')
  $repoNorm = (Convert-ToGuardPathText -Text $repoPath).TrimEnd('/')
  if ($repoNorm -ne $rootNorm -and -not $repoNorm.StartsWith($rootNorm + '/')) {
    return [ordered]@{ ok = $false; reason = 'repo_v2_repo_path_outside_scope'; repo_path = $repoPath; root = $Root }
  }

  foreach ($requiredField in @('git_dirty_state','active_agents_chain','checks','required_routes','inspector_reports','contamination_scan','gate_decision','handoff_confirmation')) {
    if (-not (Get-OptionalPropertyValue -Object $receipt -Name $requiredField)) {
      return [ordered]@{ ok = $false; reason = "repo_v2_${requiredField}_missing"; receipt = $receipt }
    }
  }

  $gitDirtyState = Get-OptionalPropertyValue -Object $receipt -Name 'git_dirty_state'
  if ((Get-OptionalPropertyValue -Object $gitDirtyState -Name 'is_git_repo') -ne $true) {
    return [ordered]@{ ok = $false; reason = 'repo_v2_git_state_not_established'; git_dirty_state = $gitDirtyState }
  }

  $agents = @(Get-OptionalPropertyValue -Object $receipt -Name 'active_agents_chain')
  if ($agents.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'repo_v2_active_agents_chain_missing' }
  }

  $checks = Get-OptionalPropertyValue -Object $receipt -Name 'checks'
  foreach ($checkName in @('lint','typecheck','test','build')) {
    $check = Test-CheckEvidenceEntry -Checks $checks -Name $checkName
    if (-not $check.ok) {
      return $check
    }
  }

  $requiredRoutes = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $receipt -Name 'required_routes'))
  if ($requiredRoutes.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'repo_v2_required_routes_missing' }
  }

  $inspectorReports = @(Get-OptionalPropertyValue -Object $receipt -Name 'inspector_reports')
  if ($inspectorReports.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'repo_v2_inspector_reports_missing' }
  }
  foreach ($report in $inspectorReports) {
    $status = [string](Get-OptionalPropertyValue -Object $report -Name 'status')
    $authority = [string](Get-OptionalPropertyValue -Object $report -Name 'authority')
    $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $report -Name 'evidence'))
    if ($status -notin @('reported','not_applicable','unavailable') -or $authority -ne 'candidate_evidence_only' -or $evidence.Count -eq 0) {
      return [ordered]@{ ok = $false; reason = 'repo_v2_inspector_report_evidence_missing'; inspector_report = $report }
    }
  }

  $scan = Get-OptionalPropertyValue -Object $receipt -Name 'contamination_scan'
  $scanStatus = [string](Get-OptionalPropertyValue -Object $scan -Name 'status')
  $scanEvidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $scan -Name 'evidence'))
  if ($scanStatus -eq 'failed') {
    return [ordered]@{ ok = $false; reason = 'repo_v2_contamination_scan_failed'; contamination_scan = $scan }
  }
  if ($scanStatus -notin @('passed','not_applicable') -or $scanEvidence.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'repo_v2_contamination_scan_missing'; contamination_scan = $scan }
  }

  $handoff = Get-OptionalPropertyValue -Object $receipt -Name 'handoff_confirmation'
  $newSession = Get-OptionalPropertyValue -Object $handoff -Name 'new_session_validation'
  if ((Get-OptionalPropertyValue -Object $handoff -Name 'handoff_ready') -ne $true -or [string](Get-OptionalPropertyValue -Object $newSession -Name 'status') -ne 'ready') {
    return [ordered]@{ ok = $false; reason = 'repo_v2_handoff_not_ready'; handoff_confirmation = $handoff }
  }

  $gateDecision = Get-OptionalPropertyValue -Object $receipt -Name 'gate_decision'
  $gateStatus = [string](Get-OptionalPropertyValue -Object $gateDecision -Name 'status')
  if ($gateStatus -notin @('pending_stop_gate','gate_issued')) {
    return [ordered]@{ ok = $false; reason = 'repo_v2_gate_decision_missing'; gate_decision = $gateDecision }
  }
  if ($gateStatus -eq 'gate_issued') {
    $expected = Get-GateDecisionFingerprint -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt
    if ([string](Get-OptionalPropertyValue -Object $gateDecision -Name 'source_completion_receipt_fingerprint') -ne $expected) {
      return [ordered]@{ ok = $false; reason = 'repo_v2_gate_decision_conflict'; gate_decision = $gateDecision; expected_source_completion_receipt_fingerprint = $expected }
    }
  }

  [ordered]@{
    ok = $true
    reason = 'repo_v2_adoption_satisfied'
    receipt = $receipt
  }
}

function Get-ToolUsageCapabilityIds {
  param(
    [string]$ToolName,
    [string]$Command,
    [string]$PayloadText
  )

  $text = "$ToolName`n$Command`n$PayloadText"
  $lower = $text.ToLowerInvariant()
  $ids = @()
  $pairs = @(
    @{ id = 'shell_command'; pattern = 'shell_command|powershell|pwsh|cmd\.exe' },
    @{ id = 'apply_patch'; pattern = 'apply_patch|\*\*\* begin patch' },
    @{ id = 'tool_search'; pattern = 'tool_search' },
    @{ id = 'spawn_agent'; pattern = '\bspawn_agent\b' },
    @{ id = 'wait_agent'; pattern = 'wait_agent' },
    @{ id = 'browser'; pattern = 'browser-use|chrome-devtools' },
    @{ id = 'image_gen'; pattern = 'image_gen|imagegen' },
    @{ id = 'git'; pattern = '\bgit(\.exe)?\b' },
    @{ id = 'gh'; pattern = '\bgh(\.exe)?\b|github' },
    @{ id = 'rg'; pattern = '\brg(\.exe)?\b|ripgrep' },
    @{ id = 'node'; pattern = '\bnode(\.exe)?\b' },
    @{ id = 'npm'; pattern = '\bnpm(\.cmd|\.exe)?\b' },
    @{ id = 'pnpm'; pattern = '\bpnpm(\.cmd|\.exe)?\b' },
    @{ id = 'python'; pattern = '\bpython(\.exe)?\b|\bpy(\.exe)?\b' },
    @{ id = 'yq'; pattern = '\byq(\.exe)?\b' },
    @{ id = 'jq'; pattern = '\bjq(\.exe)?\b' },
    @{ id = 'cargo'; pattern = '\bcargo(\.exe)?\b' },
    @{ id = 'just'; pattern = '\bjust(\.exe)?\b' },
    @{ id = 'bazel'; pattern = '\bbazel(\.exe)?\b' }
  )

  foreach ($pair in $pairs) {
    if ($lower -match $pair.pattern -and $ids -notcontains $pair.id) {
      $ids += $pair.id
    }
  }

  $ids
}

function Register-ToolUsageEvent {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$HookName,
    [string]$EventName = '',
    [object]$Payload,
    [string]$PayloadText = '',
    [string]$Workdir = '',
    [object]$ActiveContract,
    [object]$Decision
  )

  if ($null -eq $Payload -and [string]::IsNullOrWhiteSpace($PayloadText)) {
    return
  }

  $toolName = Get-PayloadString -Object $Payload -Names @('tool_name','toolName','tool','name')
  $command = Get-PayloadString -Object $Payload -Names @('command','cmd')
  $capabilityIds = @(Get-ToolUsageCapabilityIds -ToolName $toolName -Command $command -PayloadText $PayloadText)
  $observedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  $eventNonce = [guid]::NewGuid().ToString('n')
  $hookEventName = if ([string]::IsNullOrWhiteSpace($EventName)) { $HookName } else { $EventName }
  $observationLayer = if ($HookName -eq 'post_tool_use') {
    'PostToolUse'
  } elseif ($HookName -eq 'pre_command_guard') {
    'PreToolUse equivalent observation'
  } else {
    $hookEventName
  }
  $payloadFingerprint = Get-TextFingerprint -Text $PayloadText
  $decisionCode = if ($Decision) { [string](Get-OptionalPropertyValue -Object $Decision -Name 'decision') } else { '' }
  $decisionReason = if ($Decision) { [string](Get-OptionalPropertyValue -Object $Decision -Name 'reason') } else { '' }
  $turnFingerprint = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $agentLineage = Get-AgentLineage -Payload $Payload -ActiveContract $ActiveContract
  $entry = [ordered]@{
    schema_version = 'tool_usage_event.v2'
    record_type = 'tool_usage_event'
    event_id = New-LedgerEventId -ObservedAtUtc $observedAtUtc -EventNonce $eventNonce -TurnFingerprint $turnFingerprint -HookName $HookName -HookEventName $hookEventName -ToolName $toolName -Command $command -Cwd $Workdir -PayloadFingerprint $payloadFingerprint -Decision $decisionCode -Reason $decisionReason
    event_nonce = $eventNonce
    observed_at_utc = $observedAtUtc
    timestamp_utc = $observedAtUtc
    turn_fingerprint = $turnFingerprint
    hook = $HookName
    hook_event_name = $hookEventName
    observation_layer = $observationLayer
    tool = [ordered]@{
      name = $toolName
      capability_ids = $capabilityIds
    }
    tool_name = $toolName
    command = $command
    cwd = $Workdir
    capability_ids = $capabilityIds
    payload_fingerprint = $payloadFingerprint
    decision = if ([string]::IsNullOrWhiteSpace($decisionCode)) { $null } else { $decisionCode }
    reason = if ([string]::IsNullOrWhiteSpace($decisionReason)) { $null } else { $decisionReason }
    outcome = if ($decisionCode -in @('BLOCKED','DO_NOT_CLAIM_COMPLETE')) { 'blocked' } elseif ([string]::IsNullOrWhiteSpace($decisionCode)) { 'observed' } else { 'recorded' }
    agent_lineage = $agentLineage
    parent_lineage = $agentLineage
    append_only = $true
  }

  Write-InvocationLog -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/tool_usage_events.jsonl') -Entry $entry
}

function Read-ToolUsageEvents {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Join-Path $Root 'Settings/Codex_App_RUNTIME/tool_usage_events.jsonl'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $events = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $event = $line | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or [string](Get-OptionalPropertyValue -Object $event -Name 'turn_fingerprint') -eq $TurnFingerprint) {
        $events += $event
      }
    } catch {
    }
  }
  $events
}

function Read-SkillUsageEvents {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Get-SkillUsageEventsPath -Root $Root
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $events = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $event = $line | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or [string](Get-OptionalPropertyValue -Object $event -Name 'turn_fingerprint') -eq $TurnFingerprint) {
        $events += $event
      }
    } catch {
    }
  }
  $events
}

function Get-KnownSkillCatalogNames {
  $roots = @(
    (Join-Path $HOME '.agents\skills'),
    (Join-Path $HOME '.codex\skills\.system'),
    (Join-Path $HOME '.codex\skills')
  )
  $names = @()
  foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
      continue
    }
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
      if (Test-Path -LiteralPath (Join-Path $dir.FullName 'SKILL.md') -PathType Leaf) {
        $names += $dir.Name
      }
    }
  }
  @($names | Select-Object -Unique)
}

function Get-SkillUsageNamesFromText {
  param([AllowEmptyString()][string]$Text)

  $names = @()
  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $names
  }

  $knownSkills = @(Get-KnownSkillCatalogNames)
  if ($knownSkills.Count -eq 0) {
    return $names
  }
  $knownLookup = @{}
  foreach ($skill in $knownSkills) {
    $knownLookup[[string]$skill] = $true
  }

  $pathPatterns = @(
    '(?i)[\\/](?<name>[^\\/]+)[\\/]SKILL\.md\b',
    '(?i)\b(?:skill_id|skill_name|used_skill|required_skill)\s*[:=]\s*["'']?(?<name>[a-z0-9][a-z0-9-]+)'
  )
  foreach ($pattern in $pathPatterns) {
    foreach ($match in [regex]::Matches($Text, $pattern)) {
      $name = [string]$match.Groups['name'].Value
      if (-not [string]::IsNullOrWhiteSpace($name) -and $knownLookup.ContainsKey($name)) {
        $names += $name
      }
    }
  }

  @($names | Select-Object -Unique)
}

function Register-SkillUsageObservation {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$Payload,
    [AllowEmptyString()][string]$PayloadText = '',
    [AllowEmptyString()][string]$Workdir = '',
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $skillNames = @(Get-SkillUsageNamesFromText -Text $PayloadText)
  if ($skillNames.Count -eq 0) {
    return @()
  }

  $taskClassification = Read-OptionalJsonFile -Path (Get-TaskClassificationReceiptPath -Root $Root)
  $requiredSkills = @()
  if ($taskClassification -and [string](Get-OptionalPropertyValue -Object $taskClassification -Name 'turn_fingerprint') -eq $turn) {
    $requiredSkills = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $taskClassification -Name 'required_skills'))
  }

  $toolName = Get-PayloadString -Object $Payload -Names @('tool_name','toolName','tool','name')
  $payloadFingerprint = Get-TextFingerprint -Text $PayloadText
  $events = @()
  foreach ($skillName in $skillNames) {
    $event = [ordered]@{
      schema_version = 'skill_usage_event.v1'
      record_type = 'skill_usage_event'
      event_id = 'sue_' + ([guid]::NewGuid().ToString('n'))
      turn_fingerprint = $turn
      attempt_id = $turn
      skill_name = $skillName
      usage_mode = if ($requiredSkills -contains $skillName) { 'required_route' } else { 'observed' }
      used_by = 'parent_pm_or_worker'
      tool_name = $toolName
      cwd = $Workdir
      payload_fingerprint = $payloadFingerprint
      evidence_summary = 'skill SKILL.md or explicit skill usage observed in PostToolUse payload'
      authority = 'candidate_evidence_only'
      timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
      append_only = $true
    }
    $events += $event
    if (-not $NoLog) {
      Write-InvocationLog -Path (Get-SkillUsageEventsPath -Root $Root) -Entry $event
    }
  }

  $events
}

function Get-SubagentInspectionJobsPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/subagent_inspection_jobs.jsonl'
}

function Get-SubagentInspectionReportsPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/subagent_inspection_reports.jsonl'
}

function Get-SubagentWorkerJobsPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/subagent_worker_jobs.jsonl'
}

function Get-SubagentWorkerReportsPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/subagent_worker_reports.jsonl'
}

function Get-SubagentLifecycleEventsPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/subagent_lifecycle_events.jsonl'
}

function Get-SubagentInspectionLoopStatePath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/subagent_inspection_loop_state.json'
}

function Get-HeuristicReviewJobsPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/heuristic_review_jobs.jsonl'
}

function Get-HeuristicReviewReportsPath {
  param([Parameter(Mandatory = $true)][string]$Root)

  Join-Path $Root 'Settings/Codex_App_RUNTIME/heuristic_review_reports.jsonl'
}

function Get-DefaultSubagentInspectionRoutes {
  @(
    [ordered]@{
      route_id = 'repo_integrity_inspection'
      agent_name = 'spark_repo_inspector'
      trigger_patterns = @('(?i)\brepo[_ -]?integrity\b','(?i)\brepo[_ -]?adoption\b','(?i)\brepo gate adoption\b','(?i)\brepresentative repo\b','(?i)\bproduction\s+complete\b')
      path_patterns = @('(?i)(^|/)MANIFEST\.json$','(?i)(^|/)INVENTORY\.md$','(?i)(^|/)README\.md$','(?i)(^|/)AGENTS?\.md$','(?i)(^|/)package\.json$','(?i)(^|/)\.github/')
      required_report_status = @('reported','not_applicable')
    }
    [ordered]@{
      route_id = 'contamination_inspection'
      agent_name = 'spark_contamination_inspector'
      trigger_patterns = @('(?i)\bcontamination\b','(?i)\breward[-_ ]?hacking\b','(?i)\bfake\s+success\b','(?i)\bhardcoded\s+success\b','(?i)\btest[-_ ]?only\b','(?i)\blegacy frontend\b')
      path_patterns = @('(?i)vibe-coding-contamination-bench\.ps1$','(?i)reward-signal-filter\.agent\.config\.yaml$','(?i)agent-reliability-tests\.agent\.config\.yaml$')
      required_report_status = @('reported','not_applicable')
    }
    [ordered]@{
      route_id = 'required_tool_route_inspection'
      agent_name = 'spark_tool_route_inspector'
      trigger_patterns = @('(?i)required[-_ ]tool','(?i)required[-_ ]route','(?i)tool_usage_event','(?i)runtime_capability_receipt','(?i)loop breaker','(?i)required_subagent','(?i)subagent_report_missing')
      path_patterns = @('(?i)required-tool-routes\.json$','(?i)tool-skill-subagent-mcp-usage\.agent\.config\.yaml$','(?i)runtime_state\.schema\.json$','(?i)completion_gate\.yaml$','(?i)codex-ssot-hook\.ps1$')
      required_report_status = @('reported','not_applicable')
    }
    [ordered]@{
      route_id = 'frontend_adoption_inspection'
      agent_name = 'spark_frontend_inspector'
      trigger_patterns = @('(?i)\bfrontend[_ -]?adoption\b','(?i)\bvisual evidence required\b','(?i)\bscreenshot required\b')
      path_patterns = @('(?i)(^|/)src/.*\.(tsx|jsx|css|scss)$','(?i)(^|/)app/.*\.(tsx|jsx|css|scss)$','(?i)(^|/)components/','(?i)vite\.config\.','(?i)playwright\.config\.')
      required_report_status = @('reported','not_applicable')
    }
    [ordered]@{
      route_id = 'backend_adoption_inspection'
      agent_name = 'spark_backend_inspector'
      trigger_patterns = @('(?i)\bbackend[_ -]?adoption\b','(?i)\bapi contract required\b','(?i)\bdatabase migration required\b')
      path_patterns = @('(?i)(^|/)server/','(?i)(^|/)api/','(?i)(^|/)db/','(?i)(^|/)migrations/','(?i)(^|/)prisma/','(?i)(^|/)src/.*\.(py|rs|go|java|cs)$')
      required_report_status = @('reported','not_applicable')
    }
    [ordered]@{
      route_id = 'ssot_contract_inspection'
      agent_name = 'spark_contract_inspector'
      trigger_patterns = @('(?i)\bcontrol[-_ ]?plane\b','(?i)\bhook\b','(?i)\bpretooluse\b','(?i)\bposttooluse\b','(?i)\bstop\b','(?i)\bcompletion gate\b','(?i)\bruntime schema\b','(?i)\bcontract\b','(?i)\bHarness V2\b','(?i)\bsubagent inspection\b')
      path_patterns = @('(?i)Settings/Dev_Codex_HOOKS/','(?i)Settings/Codex_App_DECLARATIVE/','(?i)Settings/Codex_App_RUNTIME/runtime_state\.schema\.json$','(?i)Maintenance/harness-v2/','(?i)(^|/)MANIFEST\.json$','(?i)(^|/)ROOT_MAP\.json$','(?i)(^|/)AGENTS?\.md$','(?i)\.codex/config\.toml$','(?i)\.codex/agents/')
      required_report_status = @('reported','not_applicable')
    }
  )
}

function Get-SubagentInspectionRoutes {
  param([Parameter(Mandatory = $true)][string]$Root)

  $routesDoc = Get-RequiredToolRoutes -Root $Root
  $routes = @(@(Get-OptionalPropertyValue -Object $routesDoc -Name 'subagent_inspection_routes') | Where-Object { $null -ne $_ })
  if ($routes.Count -gt 0) {
    return $routes
  }

  Get-DefaultSubagentInspectionRoutes
}

function Test-SubagentInspectionRouteMatch {
  param(
    [Parameter(Mandatory = $true)][object]$Route,
    [string]$TriggerText,
    [string]$PathText
  )

  foreach ($pattern in @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Route -Name 'trigger_patterns'))) {
    if ($TriggerText -match $pattern) {
      return $true
    }
  }

  foreach ($pattern in @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Route -Name 'path_patterns'))) {
    if ($PathText -match $pattern) {
      return $true
    }
  }

  return $false
}

function Test-SubagentInspectionQueueRelevant {
  param(
    [Parameter(Mandatory = $true)][string]$HookEventName,
    [string]$Text
  )

  if ($Text -match '(?i)\b(subagent inspection|inspection job|spark_.*inspector|repo_integrity_inspection|contamination_inspection|required_tool_route_inspection|frontend_adoption_inspection|backend_adoption_inspection|ssot_contract_inspection)\b') {
    return $true
  }

  if ($HookEventName -eq 'PostToolUse') {
    return (Test-MutatingOperationText -Text $Text) -or ($Text -match '(?i)\bapply_patch\b|\*\*\* begin patch')
  }

  if ($HookEventName -eq 'Stop') {
    return $true
  }

  if ($HookEventName -eq 'UserPromptSubmit') {
    return $Text -match '(?i)\b(implement|fix|repair|stabilize|production|adoption|control[-_ ]?plane|hook|harness|required[-_ ]?tool|repo)\b'
  }

  return $false
}

function Normalize-SubagentInspectionTargetPaths {
  param(
    [string]$Root,
    [object]$Paths
  )

  $items = @(Convert-ToStringArray -Value $Paths)
  $normalized = @()
  $seen = @{}
  $rootFull = ''
  if (-not [string]::IsNullOrWhiteSpace($Root)) {
    try {
      $rootFull = [System.IO.Path]::GetFullPath($Root)
    } catch {
      $rootFull = [string]$Root
    }
  }

  foreach ($path in $items) {
    $value = [string]$path
    if ([string]::IsNullOrWhiteSpace($value)) {
      continue
    }

    $value = $value.Trim().Trim([char]34).Trim([char]39).Trim()
    if ($value.Contains('`') -or $value.Contains("`r") -or $value.Contains("`n")) {
      continue
    }
    $value = $value.TrimEnd(',', ';', ':', '.', ')', ']', '}')
    if ([string]::IsNullOrWhiteSpace($value)) {
      continue
    }

    $value = $value.Replace('/', '\')
    if ($value -match '^[A-Za-z]:\\\\') {
      $value = $value.Substring(0, 3) + (($value.Substring(3) -replace '\\+', '\'))
    }

    $isAbsolute = $value -match '^[A-Za-z]:\\' -or $value.StartsWith('\\')
    if (-not $isAbsolute) {
      if ([string]::IsNullOrWhiteSpace($rootFull)) {
        continue
      }
      if ($value -notmatch '^(Settings|Maintenance|Tools|docs|src|app|components|tests?)\\') {
        continue
      }
      $value = Join-Path $rootFull $value
    }

    if (-not (Test-Path -LiteralPath $value)) {
      continue
    }
    try {
      $value = (Resolve-Path -LiteralPath $value -ErrorAction Stop).Path
    } catch {
      continue
    }

    if ($value.Contains('`') -or $value.Contains("`r") -or $value.Contains("`n") -or $value.Contains(',')) {
      continue
    }

    $key = (Convert-ToGuardPathText -Text $value).TrimEnd('/')
    if (-not $seen.ContainsKey($key)) {
      $seen[$key] = $true
      $normalized += $value.TrimEnd('\')
    }
  }

  if ($normalized.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($Root)) {
    try {
      $normalized += (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
    } catch {
      $normalized += $Root
    }
  }

  $normalized
}

function Get-SubagentInspectionTargetSetKey {
  param(
    [string]$Root,
    [object]$TargetPaths
  )

  $normalized = @(Normalize-SubagentInspectionTargetPaths -Root $Root -Paths $TargetPaths | ForEach-Object {
    (Convert-ToGuardPathText -Text ([string]$_)).TrimEnd('/')
  } | Sort-Object -Unique)

  if ($normalized.Count -eq 0) {
    return 'targets:empty'
  }

  'targets:' + (Get-TextFingerprint -Text ($normalized | ConvertTo-Json -Depth 6 -Compress))
}

function Get-SubagentInspectionDedupeKey {
  param(
    [string]$Root,
    [Parameter(Mandatory = $true)][string]$ParentTurnId,
    [Parameter(Mandatory = $true)][string]$RouteId,
    [object]$TargetPaths
  )

  $targetSetKey = Get-SubagentInspectionTargetSetKey -Root $Root -TargetPaths $TargetPaths
  $raw = [ordered]@{
    parent_turn_id = $ParentTurnId
    route_id = $RouteId
    target_set_key = $targetSetKey
  }

  'subagent-inspection:' + (Get-TextFingerprint -Text ($raw | ConvertTo-Json -Depth 8 -Compress))
}

function Test-SubagentInspectionJobActive {
  param([object]$Job)

  $status = [string](Get-OptionalPropertyValue -Object $Job -Name 'status')
  if ($status -notin @('queued','spawn_requested','spawned','reported','not_applicable')) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace([string](Get-OptionalPropertyValue -Object $Job -Name 'duplicate_of'))) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace([string](Get-OptionalPropertyValue -Object $Job -Name 'superseded_by'))) {
    return $false
  }

  return $true
}

function Get-SubagentInspectionJobSortRank {
  param([object]$Job)

  $status = [string](Get-OptionalPropertyValue -Object $Job -Name 'status')
  switch ($status) {
    'reported' { return 6 }
    'not_applicable' { return 5 }
    'spawned' { return 4 }
    'spawn_requested' { return 3 }
    'queued' { return 2 }
    default { return 1 }
  }
}

function Repair-SubagentInspectionJobTargetPaths {
  param(
    [string]$Root,
    [object]$Job
  )

  if (-not $Job) {
    return $Job
  }

  $rawPaths = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Job -Name 'target_paths'))
  $cleanPaths = @(Normalize-SubagentInspectionTargetPaths -Root $Root -Paths $rawPaths)
  $rawFingerprint = Get-TextFingerprint -Text ($rawPaths | ConvertTo-Json -Depth 6 -Compress)
  $cleanFingerprint = Get-TextFingerprint -Text ($cleanPaths | ConvertTo-Json -Depth 6 -Compress)
  $warnings = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Job -Name 'warnings'))
  if ($rawFingerprint -ne $cleanFingerprint -and $warnings -notcontains 'target_paths_sanitized') {
    $warnings += 'target_paths_sanitized'
  }

  $entry = [ordered]@{}
  foreach ($property in $Job.PSObject.Properties) {
    if ($property.Name -eq 'target_paths' -or $property.Name -eq 'warnings') {
      continue
    }
    $entry[$property.Name] = $property.Value
  }
  $entry['target_paths'] = $cleanPaths
  if ([string]::IsNullOrWhiteSpace([string](Get-OptionalPropertyValue -Object $entry -Name 'dedupe_key'))) {
    $parentTurnId = [string](Get-OptionalPropertyValue -Object $entry -Name 'parent_turn_id')
    $routeId = [string](Get-OptionalPropertyValue -Object $entry -Name 'route_id')
    if (-not [string]::IsNullOrWhiteSpace($parentTurnId) -and -not [string]::IsNullOrWhiteSpace($routeId)) {
      $entry['dedupe_key'] = Get-SubagentInspectionDedupeKey -Root $Root -ParentTurnId $parentTurnId -RouteId $routeId -TargetPaths $cleanPaths
    }
  }
  $entry['warnings'] = $warnings
  $entry
}

function Get-SubagentInspectionTargetPaths {
  param(
    [string]$Root,
    [string]$Text,
    [object]$ActiveContract,
    [object]$CompletionReceipt
  )

  $paths = @()
  $paths += @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $ActiveContract -Name 'scope'))

  $freshness = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'freshness'
  if ($freshness) {
    $paths += @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $freshness -Name 'affected_paths'))
  }

  $dependencyAlignment = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'dependency_alignment_check'
  if ($dependencyAlignment) {
    $paths += @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $dependencyAlignment -Name 'changed_paths'))
    $paths += @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $dependencyAlignment -Name 'checked_connected_paths'))
  }

  $pathPattern = "(?i)([A-Z]:\\[^\s`"'<>\|]+|(?:Settings|Maintenance|Tools|docs|src|app|components|tests?)/[^\s`"'<>\|]+)"
  foreach ($match in [regex]::Matches($Text, $pathPattern)) {
    $paths += $match.Groups[1].Value
  }

  Normalize-SubagentInspectionTargetPaths -Root $Root -Paths $paths
}

function Read-SubagentInspectionJobs {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Get-SubagentInspectionJobsPath -Root $Root
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $jobs = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $job = $line | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or [string](Get-OptionalPropertyValue -Object $job -Name 'parent_turn_id') -eq $TurnFingerprint) {
        $jobs += (Repair-SubagentInspectionJobTargetPaths -Root $Root -Job $job)
      }
    } catch {
    }
  }

  $jobs
}

function Get-LatestSubagentInspectionJobs {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $latest = @{}
  foreach ($job in @(Read-SubagentInspectionJobs -Root $Root -TurnFingerprint $TurnFingerprint)) {
    $jobId = [string](Get-OptionalPropertyValue -Object $job -Name 'job_id')
    if ([string]::IsNullOrWhiteSpace($jobId)) {
      continue
    }
    if (-not (Test-SubagentInspectionJobActive -Job $job)) {
      continue
    }
    $routeId = [string](Get-OptionalPropertyValue -Object $job -Name 'route_id')
    $parentTurnId = [string](Get-OptionalPropertyValue -Object $job -Name 'parent_turn_id')
    $dedupeKey = [string](Get-OptionalPropertyValue -Object $job -Name 'dedupe_key')
    if ([string]::IsNullOrWhiteSpace($dedupeKey)) {
      $dedupeKey = Get-SubagentInspectionDedupeKey -Root $Root -ParentTurnId $parentTurnId -RouteId $routeId -TargetPaths (Get-OptionalPropertyValue -Object $job -Name 'target_paths')
    }
    $key = $dedupeKey
    if ([string]::IsNullOrWhiteSpace($key)) {
      $agentName = [string](Get-OptionalPropertyValue -Object $job -Name 'agent_name')
      $key = "$jobId|$routeId|$agentName"
    }
    if (-not $latest.ContainsKey($key)) {
      $latest[$key] = $job
      continue
    }

    $existing = $latest[$key]
    $existingRank = Get-SubagentInspectionJobSortRank -Job $existing
    $candidateRank = Get-SubagentInspectionJobSortRank -Job $job
    $existingUpdated = [string](Get-OptionalPropertyValue -Object $existing -Name 'updated_at_utc')
    $candidateUpdated = [string](Get-OptionalPropertyValue -Object $job -Name 'updated_at_utc')
    if ($candidateRank -gt $existingRank -or (($candidateRank -eq $existingRank) -and ($candidateUpdated -gt $existingUpdated))) {
      $latest[$key] = $job
    }
  }

  @($latest.Values)
}

function Get-SubagentInspectionReportEntries {
  param([object]$CompletionReceipt)

  $report = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'subagent_inspection_report'
  if (-not $report) {
    return @()
  }

  @(Get-OptionalPropertyValue -Object $report -Name 'requirements')
}

function Read-SubagentLifecycleEvents {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Get-SubagentLifecycleEventsPath -Root $Root
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $events = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $event = $line | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or [string](Get-OptionalPropertyValue -Object $event -Name 'turn_id') -eq $TurnFingerprint) {
        $events += $event
      }
    } catch {
    }
  }

  $events
}

function Read-SubagentInspectionReports {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Get-SubagentInspectionReportsPath -Root $Root
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $reports = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $report = $line | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or [string](Get-OptionalPropertyValue -Object $report -Name 'parent_turn_id') -eq $TurnFingerprint) {
        $reports += $report
      }
    } catch {
    }
  }

  $reports
}

function Read-SubagentWorkerJobs {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Get-SubagentWorkerJobsPath -Root $Root
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $jobs = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $job = $line | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or [string](Get-OptionalPropertyValue -Object $job -Name 'parent_turn_id') -eq $TurnFingerprint) {
        $jobs += $job
      }
    } catch {
    }
  }

  $jobs
}

function Read-SubagentWorkerReports {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Get-SubagentWorkerReportsPath -Root $Root
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $reports = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $report = $line | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or [string](Get-OptionalPropertyValue -Object $report -Name 'parent_turn_id') -eq $TurnFingerprint) {
        $reports += $report
      }
    } catch {
    }
  }

  $reports
}

function Read-PmWorkerWaiverEvents {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  @(Read-PmDecisionEvents -Root $Root -TurnFingerprint $TurnFingerprint | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'schema_version') -eq 'pm_worker_waiver_event.v1' })
}

function Test-SubagentInspectionNotApplicable {
  param(
    [Parameter(Mandatory = $true)][string]$RouteId,
    [object]$CompletionReceipt
  )

  foreach ($entry in @(Get-SubagentInspectionReportEntries -CompletionReceipt $CompletionReceipt)) {
    $entryRouteId = [string](Get-OptionalPropertyValue -Object $entry -Name 'route_id')
    $status = [string](Get-OptionalPropertyValue -Object $entry -Name 'status')
    $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $entry -Name 'evidence'))
    if ($entryRouteId -eq $RouteId -and $status -eq 'not_applicable' -and $evidence.Count -gt 0) {
      return $true
    }
  }

  $receiptEvidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'evidence')) -join "`n"
  return $receiptEvidence -match "(?i)subagent_inspection_not_applicable:$([regex]::Escape($RouteId))"
}

function Find-LatestSubagentInspectionJob {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$TurnFingerprint,
    [Parameter(Mandatory = $true)][string]$RouteId,
    [Parameter(Mandatory = $true)][string]$AgentName,
    [object]$TargetPaths = $null
  )

  $requestedDedupeKey = ''
  if ($null -ne $TargetPaths) {
    $requestedDedupeKey = Get-SubagentInspectionDedupeKey -Root $Root -ParentTurnId $TurnFingerprint -RouteId $RouteId -TargetPaths $TargetPaths
  }

  $matches = @(Get-LatestSubagentInspectionJobs -Root $Root -TurnFingerprint $TurnFingerprint | Where-Object {
    [string](Get-OptionalPropertyValue -Object $_ -Name 'route_id') -eq $RouteId -and
    [string](Get-OptionalPropertyValue -Object $_ -Name 'agent_name') -eq $AgentName -and
    ([string]::IsNullOrWhiteSpace($requestedDedupeKey) -or [string](Get-OptionalPropertyValue -Object $_ -Name 'dedupe_key') -eq $requestedDedupeKey)
  })
  if ($matches.Count -eq 0) {
    return $null
  }

  @($matches | Sort-Object `
    @{ Expression = {
        $status = [string](Get-OptionalPropertyValue -Object $_ -Name 'status')
        switch ($status) {
          'reported' { 6 }
          'not_applicable' { 5 }
          'spawned' { 4 }
          'spawn_requested' { 3 }
          'queued' { 2 }
          default { 1 }
        }
      }
    }, `
    @{ Expression = {
        $updated = [string](Get-OptionalPropertyValue -Object $_ -Name 'updated_at_utc')
        if ([string]::IsNullOrWhiteSpace($updated)) {
          [string](Get-OptionalPropertyValue -Object $_ -Name 'created_at_utc')
        } else {
          $updated
        }
      }
    })[-1]
}

function Test-SubagentSpawnObserved {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$TurnFingerprint,
    [Parameter(Mandatory = $true)][object]$Job
  )

  $jobId = [string](Get-OptionalPropertyValue -Object $Job -Name 'job_id')
  if ([string]::IsNullOrWhiteSpace($jobId)) {
    return $false
  }

  $spawnEventId = [string](Get-OptionalPropertyValue -Object $Job -Name 'spawn_event_id')
  if (-not [string]::IsNullOrWhiteSpace($spawnEventId)) {
    return $true
  }

  $lifecycleEvents = @(Read-SubagentLifecycleEvents -Root $Root -TurnFingerprint $TurnFingerprint)
  $spawnEvents = @($lifecycleEvents | Where-Object {
    [string](Get-OptionalPropertyValue -Object $_ -Name 'subagent_id') -eq $jobId -and
    [string](Get-OptionalPropertyValue -Object $_ -Name 'event') -eq 'spawned'
  })

  return ($spawnEvents.Count -gt 0)
}

function Test-WorkerSpawnObserved {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$TurnFingerprint,
    [Parameter(Mandatory = $true)][string]$RouteId
  )

  $workerJobs = @(Read-SubagentWorkerJobs -Root $Root -TurnFingerprint $TurnFingerprint | Where-Object {
    ([string]::IsNullOrWhiteSpace($RouteId) -or [string](Get-OptionalPropertyValue -Object $_ -Name 'route_id') -eq $RouteId) -and
    (-not [string]::IsNullOrWhiteSpace([string](Get-OptionalPropertyValue -Object $_ -Name 'spawn_event_id')))
  })
  if ($workerJobs.Count -gt 0) {
    return $true
  }

  $lifecycleEvents = @(Read-SubagentLifecycleEvents -Root $Root -TurnFingerprint $TurnFingerprint)
  $workerEvents = @($lifecycleEvents | Where-Object {
    [string](Get-OptionalPropertyValue -Object $_ -Name 'record_type') -eq 'worker_spawn_event' -and
    [string](Get-OptionalPropertyValue -Object $_ -Name 'event') -eq 'spawned' -and
    ([string]::IsNullOrWhiteSpace($RouteId) -or [string](Get-OptionalPropertyValue -Object $_ -Name 'subagent_role') -eq $RouteId)
  })

  return ($workerEvents.Count -gt 0)
}

function Test-PmWorkerWaiverObserved {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$TurnFingerprint,
    [Parameter(Mandatory = $true)][string]$RouteId
  )

  $waivers = @(Read-PmWorkerWaiverEvents -Root $Root -TurnFingerprint $TurnFingerprint | Where-Object {
    [string](Get-OptionalPropertyValue -Object $_ -Name 'route_id') -eq $RouteId -and (Test-PmWorkerWaiverValid -Waiver $_)
  })
  return ($waivers.Count -gt 0)
}

function Register-SubagentWorkerJob {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][string]$RouteId,
    [string[]]$TargetPaths = @(),
    [string]$Status = 'queued',
    [string]$JobId = '',
    [string]$SpawnEventId = '',
    [string]$ReportEventId = '',
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  if ([string]::IsNullOrWhiteSpace($JobId)) {
    $existing = @(Read-SubagentWorkerJobs -Root $Root -TurnFingerprint $turn | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'route_id') -eq $RouteId } | Select-Object -Last 1)
    if ($existing.Count -gt 0 -and [string](Get-OptionalPropertyValue -Object $existing[0] -Name 'status') -in @('queued','spawn_requested','spawned','reported','closed','not_applicable')) {
      return $existing[0]
    }
    $JobId = 'worker-' + ([guid]::NewGuid().ToString('n'))
  }

  $now = (Get-Date).ToUniversalTime().ToString('o')
  $taskClassification = Read-OptionalJsonFile -Path (Get-TaskClassificationReceiptPath -Root $Root)
  $requiredSkills = @()
  if ($taskClassification -and [string](Get-OptionalPropertyValue -Object $taskClassification -Name 'turn_fingerprint') -eq $turn) {
    $requiredSkills = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $taskClassification -Name 'required_skills'))
  }
  $entry = [ordered]@{
    schema_version = 'subagent_worker_job.v1'
    job_id = $JobId
    created_at_utc = $now
    updated_at_utc = $now
    parent_turn_id = $turn
    attempt_id = $turn
    route_id = $RouteId
    agent_name = 'worker'
    model_primary = 'latest-main'
    model_preferred = 'gpt-5.5'
    reasoning_effort = 'medium'
    sandbox_mode = 'workspace-write-scoped'
    max_depth = 1
    target_paths = @($TargetPaths)
    required_skills = $requiredSkills
    skill_usage_required = ($requiredSkills.Count -gt 0)
    required_outputs = [ordered]@{
      skill_usage_summary = ($requiredSkills.Count -gt 0)
    }
    trigger = 'PM delegation plan'
    status = $Status
    authority = 'candidate_artifact_only'
    spawn_event_id = if ([string]::IsNullOrWhiteSpace($SpawnEventId)) { $null } else { $SpawnEventId }
    report_event_id = if ([string]::IsNullOrWhiteSpace($ReportEventId)) { $null } else { $ReportEventId }
    append_only = $true
  }
  if (-not $NoLog) {
    Write-InvocationLog -Path (Get-SubagentWorkerJobsPath -Root $Root) -Entry $entry
  }
  $entry
}

function Register-SubagentWorkerReport {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$Job,
    [string]$PayloadText = '',
    [string]$Status = 'reported',
    [string[]]$ChangedPaths = @(),
    [string[]]$Validation = @(),
    [string[]]$WarningsOrLimits = @(),
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $reportHash = Get-TextFingerprint -Text $PayloadText
  $skillUsageSummary = $null
  if ($PayloadText -match '(?i)skill_usage_summary') {
    $skillUsageSummary = [ordered]@{
      observed = $true
      payload_fingerprint = $reportHash
    }
  }
  $entry = [ordered]@{
    schema_version = 'subagent_worker_report.v1'
    report_id = 'swr_' + ([guid]::NewGuid().ToString('n'))
    job_id = [string](Get-OptionalPropertyValue -Object $Job -Name 'job_id')
    parent_turn_id = $turn
    attempt_id = [string](Get-OptionalPropertyValue -Object $Job -Name 'attempt_id')
    route_id = [string](Get-OptionalPropertyValue -Object $Job -Name 'route_id')
    agent_name = 'worker'
    status = $Status
    authority = 'candidate_artifact_only'
    report_hash = "sha256:$reportHash"
    changed_paths = @($ChangedPaths)
    validation = @($Validation)
    skill_usage_summary = $skillUsageSummary
    warnings_or_limits = @($WarningsOrLimits)
    reported_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    append_only = $true
  }

  if (-not $NoLog) {
    Write-InvocationLog -Path (Get-SubagentWorkerReportsPath -Root $Root) -Entry $entry
  }
  $entry
}

function Register-SubagentInspectionJob {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][string]$RouteId,
    [Parameter(Mandatory = $true)][string]$AgentName,
    [string[]]$TargetPaths = @(),
    [string]$TriggerHook = '',
    [string]$Status = 'queued',
    [string]$JobId = '',
    [string]$SpawnEventId = '',
    [string]$ReportEventId = '',
    [string]$ReportFingerprint = '',
    [string]$NotApplicableReason = '',
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  if ([string]::IsNullOrWhiteSpace($turn)) {
    $turn = Get-TextFingerprint -Text ((Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal') | Out-String)
  }

  $existingForJobId = $null
  if (-not [string]::IsNullOrWhiteSpace($JobId)) {
    $existingForJobId = @(Read-SubagentInspectionJobs -Root $Root -TurnFingerprint $turn | Where-Object {
      [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') -eq $JobId
    } | Select-Object -Last 1)
    if ($existingForJobId.Count -gt 0) {
      $TargetPaths = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $existingForJobId[0] -Name 'target_paths'))
    }
  }

  $cleanTargetPaths = @(Normalize-SubagentInspectionTargetPaths -Root $Root -Paths $TargetPaths)
  $dedupeKey = Get-SubagentInspectionDedupeKey -Root $Root -ParentTurnId $turn -RouteId $RouteId -TargetPaths $cleanTargetPaths

  if ([string]::IsNullOrWhiteSpace($JobId)) {
    $existing = Find-LatestSubagentInspectionJob -Root $Root -TurnFingerprint $turn -RouteId $RouteId -AgentName $AgentName -TargetPaths $cleanTargetPaths
    if ($existing) {
      $existingStatus = [string](Get-OptionalPropertyValue -Object $existing -Name 'status')
      if ($existingStatus -in @('queued','spawn_requested','spawned','reported','not_applicable')) {
        if (-not $NoLog -and $Status -eq 'queued') {
          $duplicateEntry = [ordered]@{
            schema_version = 'subagent_inspection_job.v1'
            job_id = 'subagent-duplicate-' + ([guid]::NewGuid().ToString('n'))
            created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            parent_turn_id = $turn
            attempt_id = [string](Get-OptionalPropertyValue -Object $existing -Name 'attempt_id')
            route_id = $RouteId
            agent_name = $AgentName
            dedupe_key = $dedupeKey
            duplicate_of = [string](Get-OptionalPropertyValue -Object $existing -Name 'job_id')
            superseded_by = $null
            model = 'gpt-5.3-codex-spark'
            fallback_model = 'latest-mini'
            reasoning_effort = 'high'
            sandbox_mode = 'read-only'
            max_depth = 1
            target_paths = $cleanTargetPaths
            skill_compliance_targets = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $existing -Name 'skill_compliance_targets'))
            trigger_hook = $TriggerHook
            status = 'duplicate'
            authority = 'candidate_evidence_only'
            spawn_event_id = $null
            report_event_id = $null
            report_fingerprint = $null
            not_applicable_reason = 'duplicate_of:' + [string](Get-OptionalPropertyValue -Object $existing -Name 'job_id')
            warnings = @('duplicate_job_suppressed')
          }
          Write-InvocationLog -Path (Get-SubagentInspectionJobsPath -Root $Root) -Entry $duplicateEntry
        }
        return $existing
      }
    }
    $JobId = 'subagent-' + ([guid]::NewGuid().ToString('n'))
  }

  $freshness = Get-OptionalPropertyValue -Object (Read-OptionalJsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/completion_receipt.json')) -Name 'freshness'
  $attemptId = if ($freshness) { [string](Get-OptionalPropertyValue -Object $freshness -Name 'attempt_id') } else { $turn }
  $now = (Get-Date).ToUniversalTime().ToString('o')
  $taskClassification = Read-OptionalJsonFile -Path (Get-TaskClassificationReceiptPath -Root $Root)
  $requiredSkills = @()
  if ($taskClassification -and [string](Get-OptionalPropertyValue -Object $taskClassification -Name 'turn_fingerprint') -eq $turn) {
    $requiredSkills = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $taskClassification -Name 'required_skills'))
  }
  $targetWarnings = @()
  if ((Get-TextFingerprint -Text (@($TargetPaths) | ConvertTo-Json -Depth 6 -Compress)) -ne (Get-TextFingerprint -Text ($cleanTargetPaths | ConvertTo-Json -Depth 6 -Compress))) {
    $targetWarnings += 'target_paths_sanitized'
  }

  $entry = [ordered]@{
    schema_version = 'subagent_inspection_job.v1'
    job_id = $JobId
    created_at_utc = $now
    updated_at_utc = $now
    parent_turn_id = $turn
    attempt_id = $attemptId
    route_id = $RouteId
    agent_name = $AgentName
    dedupe_key = $dedupeKey
    duplicate_of = $null
    superseded_by = $null
    model = 'gpt-5.3-codex-spark'
    fallback_model = 'latest-mini'
    reasoning_effort = 'high'
    sandbox_mode = 'read-only'
    max_depth = 1
    target_paths = $cleanTargetPaths
    skill_compliance_targets = $requiredSkills
    trigger_hook = $TriggerHook
    status = $Status
    authority = 'candidate_evidence_only'
    spawn_event_id = if ([string]::IsNullOrWhiteSpace($SpawnEventId)) { $null } else { $SpawnEventId }
    report_event_id = if ([string]::IsNullOrWhiteSpace($ReportEventId)) { $null } else { $ReportEventId }
    report_fingerprint = if ([string]::IsNullOrWhiteSpace($ReportFingerprint)) { $null } else { $ReportFingerprint }
    not_applicable_reason = if ([string]::IsNullOrWhiteSpace($NotApplicableReason)) { $null } else { $NotApplicableReason }
    warnings = $targetWarnings
  }

  if (-not $NoLog) {
    Write-InvocationLog -Path (Get-SubagentInspectionJobsPath -Root $Root) -Entry $entry
  }

  $entry
}

function Register-SubagentInspectionReport {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$Job,
    [string]$PayloadText = '',
    [string]$Status = 'reported',
    [string[]]$Findings = @(),
    [string[]]$EvidencePaths = @(),
    [string[]]$WarningsOrLimits = @(),
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $jobId = [string](Get-OptionalPropertyValue -Object $Job -Name 'job_id')
  $routeId = [string](Get-OptionalPropertyValue -Object $Job -Name 'route_id')
  $agentName = [string](Get-OptionalPropertyValue -Object $Job -Name 'agent_name')
  $reportHash = Get-TextFingerprint -Text $PayloadText
  $entry = [ordered]@{
    schema_version = 'subagent_inspection_report.v1'
    report_id = 'sir_' + ([guid]::NewGuid().ToString('n'))
    job_id = $jobId
    parent_turn_id = $turn
    attempt_id = [string](Get-OptionalPropertyValue -Object $Job -Name 'attempt_id')
    route_id = $routeId
    agent_name = $agentName
    status = $Status
    authority = 'candidate_evidence_only'
    report_hash = "sha256:$reportHash"
    evidence_paths = @($EvidencePaths)
    findings = @($Findings)
    warnings_or_limits = @($WarningsOrLimits)
    reported_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    append_only = $true
  }

  if (-not $NoLog) {
    Write-InvocationLog -Path (Get-SubagentInspectionReportsPath -Root $Root) -Entry $entry
  }

  $entry
}

function Register-SubagentLifecycleEvent {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$Job,
    [Parameter(Mandatory = $true)][string]$Event,
    [string]$Severity = 'info',
    [string]$ReasonCode = '',
    [string]$ReportHash = '',
    [string[]]$EvidencePaths = @(),
    [string]$PmAction = '',
    [string]$ReplacementSubagentId = '',
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $jobAuthority = [string](Get-OptionalPropertyValue -Object $Job -Name 'authority')
  if ([string]::IsNullOrWhiteSpace($jobAuthority)) {
    $jobAuthority = 'candidate_evidence_only'
  }
  $recordType = if ($Event -eq 'spawned' -and $jobAuthority -eq 'candidate_artifact_only') { 'worker_spawn_event' } elseif ($Event -eq 'spawned') { 'subagent_spawn_event' } else { 'subagent_lifecycle_event' }
  $entry = [ordered]@{
    schema_version = 'subagent_lifecycle_event.v1'
    record_type = $recordType
    event_id = 'sle_' + ([guid]::NewGuid().ToString('n'))
    turn_id = $turn
    attempt_id = [string](Get-OptionalPropertyValue -Object $Job -Name 'attempt_id')
    parent_agent_id = 'main_pm'
    subagent_id = [string](Get-OptionalPropertyValue -Object $Job -Name 'job_id')
    subagent_role = [string](Get-OptionalPropertyValue -Object $Job -Name 'route_id')
    event = $Event
    severity = $Severity
    reason_code = $ReasonCode
    report_hash = if ([string]::IsNullOrWhiteSpace($ReportHash)) { $null } else { $ReportHash }
    evidence_paths = @($EvidencePaths)
    pm_action = $PmAction
    replacement_subagent_id = if ([string]::IsNullOrWhiteSpace($ReplacementSubagentId)) { $null } else { $ReplacementSubagentId }
    authority = $jobAuthority
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    append_only = $true
  }

  if (-not $NoLog) {
    Write-InvocationLog -Path (Get-SubagentLifecycleEventsPath -Root $Root) -Entry $entry
  }

  $entry
}

function Register-PmDecisionEvent {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [string]$Decision = 'continue',
    [string]$SubagentId = '',
    [string]$RouteId = '',
    [string]$ReasonCode = '',
    [bool]$AcceptedAsEvidence = $false,
    [string]$CompletionImpact = '',
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $entry = [ordered]@{
    schema_version = 'pm_decision_event.v1'
    event_id = 'pmd_' + ([guid]::NewGuid().ToString('n'))
    turn_id = $turn
    attempt_id = $turn
    decision = $Decision
    subagent_id = if ([string]::IsNullOrWhiteSpace($SubagentId)) { $null } else { $SubagentId }
    route_id = if ([string]::IsNullOrWhiteSpace($RouteId)) { $null } else { $RouteId }
    reason_code = $ReasonCode
    accepted_as_evidence = $AcceptedAsEvidence
    pm_responsibility = 'retained'
    completion_impact = $CompletionImpact
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    append_only = $true
  }

  if (-not $NoLog) {
    Write-InvocationLog -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/pm_decisions.jsonl') -Entry $entry
  }

  $entry
}

function Register-PmWorkerWaiverEvent {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][string]$RouteId,
    [Parameter(Mandatory = $true)][string]$Reason,
    [Parameter(Mandatory = $true)][string[]]$Scope,
    [Parameter(Mandatory = $true)][string[]]$ReplacementEvidence,
    [Parameter(Mandatory = $true)][string]$ResidualRisk,
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $entry = [ordered]@{
    schema_version = 'pm_worker_waiver_event.v1'
    record_type = 'pm_worker_waiver_event'
    event_id = 'pww_' + ([guid]::NewGuid().ToString('n'))
    turn_id = $turn
    attempt_id = $turn
    route_id = $RouteId
    reason = $Reason
    scope = @($Scope)
    expiry = 'current_turn'
    replacement_evidence = @($ReplacementEvidence)
    residual_risk = $ResidualRisk
    pm_responsibility = 'retained'
    authority = 'candidate_evidence_only'
    completion_authority = 'gate_issued_receipt_only'
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    append_only = $true
  }

  if (-not $NoLog) {
    Write-InvocationLog -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/pm_decisions.jsonl') -Entry $entry
  }

  $entry
}

function Test-PmWorkerWaiverValid {
  param([object]$Waiver)

  $reason = [string](Get-OptionalPropertyValue -Object $Waiver -Name 'reason')
  $scope = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Waiver -Name 'scope'))
  $expiry = [string](Get-OptionalPropertyValue -Object $Waiver -Name 'expiry')
  $replacementEvidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Waiver -Name 'replacement_evidence'))
  $residualRisk = [string](Get-OptionalPropertyValue -Object $Waiver -Name 'residual_risk')
  return ((-not [string]::IsNullOrWhiteSpace($reason)) -and $scope.Count -gt 0 -and $expiry -eq 'current_turn' -and $replacementEvidence.Count -gt 0 -and (-not [string]::IsNullOrWhiteSpace($residualRisk)))
}

function Register-SubagentInspectionLedgerEvent {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][string]$Event,
    [Parameter(Mandatory = $true)][object]$Job,
    [string]$PayloadFingerprint = '',
    [object]$Payload,
    [string]$Workdir = '',
    [bool]$NoLog = $false
  )

  $observedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  $eventNonce = [guid]::NewGuid().ToString('n')
  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $jobId = [string](Get-OptionalPropertyValue -Object $Job -Name 'job_id')
  $agentName = [string](Get-OptionalPropertyValue -Object $Job -Name 'agent_name')
  $routeId = [string](Get-OptionalPropertyValue -Object $Job -Name 'route_id')
  $status = [string](Get-OptionalPropertyValue -Object $Job -Name 'status')
  $targetPaths = @(Normalize-SubagentInspectionTargetPaths -Root $Root -Paths (Get-OptionalPropertyValue -Object $Job -Name 'target_paths'))
  $dedupeKey = [string](Get-OptionalPropertyValue -Object $Job -Name 'dedupe_key')
  if ([string]::IsNullOrWhiteSpace($dedupeKey)) {
    $dedupeKey = Get-SubagentInspectionDedupeKey -Root $Root -ParentTurnId $turn -RouteId $routeId -TargetPaths $targetPaths
  }

  $entry = [ordered]@{
    schema_version = 'tool_usage_event.v2'
    record_type = 'subagent_inspection_event'
    event_id = New-LedgerEventId -ObservedAtUtc $observedAtUtc -EventNonce $eventNonce -TurnFingerprint $turn -HookName 'post_tool_use' -HookEventName $Event -ToolName 'spawn_agent' -Command "$Event $agentName $jobId" -Cwd $Workdir -PayloadFingerprint $PayloadFingerprint -Decision 'ALLOW' -Reason 'subagent_inspection_observed'
    event_nonce = $eventNonce
    observed_at_utc = $observedAtUtc
    timestamp_utc = $observedAtUtc
    turn_fingerprint = $turn
    hook = 'post_tool_use'
    hook_event_name = 'PostToolUse'
    observation_layer = 'PostToolUse'
    event = $Event
    tool = [ordered]@{
      name = 'spawn_agent'
      capability_ids = @('spawn_agent','subagent_inspection')
    }
    tool_name = 'spawn_agent'
    command = "$Event $agentName $jobId"
    cwd = $Workdir
    capability_ids = @('spawn_agent','subagent_inspection')
    payload_fingerprint = $PayloadFingerprint
    decision = 'ALLOW'
    reason = 'subagent_inspection_observed'
    outcome = 'recorded'
    job_id = $jobId
    parent_turn_id = $turn
    route_id = $routeId
    agent_name = $agentName
    dedupe_key = $dedupeKey
    duplicate_of = Get-OptionalPropertyValue -Object $Job -Name 'duplicate_of'
    superseded_by = Get-OptionalPropertyValue -Object $Job -Name 'superseded_by'
    sandbox_mode = 'read-only'
    target_paths = $targetPaths
    status = $status
    authority = 'candidate_evidence_only'
    agent_lineage = Get-AgentLineage -Payload $Payload -ActiveContract $ActiveContract
    parent_lineage = Get-AgentLineage -Payload $Payload -ActiveContract $ActiveContract
    append_only = $true
  }

  if (-not $NoLog) {
    Write-InvocationLog -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/tool_usage_events.jsonl') -Entry $entry
  }

  $entry
}

function Register-SubagentInspectionJobsForContext {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$CompletionReceipt,
    [Parameter(Mandatory = $true)][string]$HookEventName,
    [string]$TriggerText,
    [string]$PathText,
    [bool]$NoLog = $false
  )

  $combinedText = "$TriggerText`n$PathText"
  if (-not (Test-SubagentInspectionQueueRelevant -HookEventName $HookEventName -Text $combinedText)) {
    return @()
  }

  $targetPaths = @(Get-SubagentInspectionTargetPaths -Root $Root -Text $combinedText -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt)
  $jobs = @()
  foreach ($route in @(Get-SubagentInspectionRoutes -Root $Root)) {
    if (-not (Test-SubagentInspectionRouteMatch -Route $route -TriggerText $TriggerText -PathText $PathText)) {
      continue
    }

    $agentName = [string](Get-OptionalPropertyValue -Object $route -Name 'agent_name')
    if ([string]::IsNullOrWhiteSpace($agentName)) {
      continue
    }
    if (-not (Test-SubagentInspectionStandingAuthorization -AgentName $agentName)) {
      continue
    }

    $jobs += Register-SubagentInspectionJob -Root $Root -ActiveContract $ActiveContract -RouteId ([string](Get-OptionalPropertyValue -Object $route -Name 'route_id')) -AgentName $agentName -TargetPaths $targetPaths -TriggerHook $HookEventName -Status 'queued' -NoLog:$NoLog
  }

  $jobs
}

function Get-SubagentInspectionObservation {
  param(
    [object]$Payload,
    [string]$PayloadText
  )

  $toolName = Get-PayloadString -Object $Payload -Names @('tool_name','toolName','tool','name')
  $jobId = Get-PayloadString -Object $Payload -Names @('job_id','jobId','subagent_job_id','inspection_job_id')
  if ([string]::IsNullOrWhiteSpace($jobId) -and $PayloadText -match '(?i)\bjob_id\b\s*[:=]\s*["'']?(?<id>subagent-[A-Za-z0-9_-]+)') {
    $jobId = $Matches.id
  }

  $agentName = ''
  foreach ($roleName in Get-SubagentInspectionRoleNames) {
    if ($PayloadText -match [regex]::Escape($roleName)) {
      $agentName = $roleName
      break
    }
  }

  $event = ''
  if ($PayloadText -match '(?i)subagent_inspection_report\.v1|subagent_report|candidate_evidence_only.*reported') {
    $event = 'subagent_report'
  } elseif ($toolName -match '(?i)spawn_agent' -or $PayloadText -match '(?i)record_type\s*["'':=]+\s*["'']?subagent_spawn_event|event\s*["'':=]+\s*["'']?subagent_spawn') {
    $event = 'subagent_spawn'
  }

  if ($event -eq 'subagent_spawn' -and [string]::IsNullOrWhiteSpace($jobId)) {
    return $null
  }

  if ([string]::IsNullOrWhiteSpace($event) -or [string]::IsNullOrWhiteSpace($agentName)) {
    return $null
  }

  [ordered]@{
    event = $event
    job_id = $jobId
    agent_name = $agentName
  }
}

function Register-SubagentInspectionObservation {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$Payload,
    [string]$PayloadText = '',
    [string]$Workdir = '',
    [bool]$NoLog = $false
  )

  $observation = Get-SubagentInspectionObservation -Payload $Payload -PayloadText $PayloadText
  if (-not $observation) {
    return $null
  }

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $agentName = [string](Get-OptionalPropertyValue -Object $observation -Name 'agent_name')
  $jobId = [string](Get-OptionalPropertyValue -Object $observation -Name 'job_id')
  $event = [string](Get-OptionalPropertyValue -Object $observation -Name 'event')
  $route = @(Get-SubagentInspectionRoutes -Root $Root | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'agent_name') -eq $agentName } | Select-Object -First 1)
  if ($route.Count -eq 0) {
    return $null
  }

  $routeId = [string](Get-OptionalPropertyValue -Object $route[0] -Name 'route_id')
  $targetPaths = @(Get-SubagentInspectionTargetPaths -Root $Root -Text $PayloadText -ActiveContract $ActiveContract -CompletionReceipt (Read-OptionalJsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/completion_receipt.json')))
  if ([string]::IsNullOrWhiteSpace($jobId)) {
    $existing = Find-LatestSubagentInspectionJob -Root $Root -TurnFingerprint $turn -RouteId $routeId -AgentName $agentName
    if ($existing) {
      $jobId = [string](Get-OptionalPropertyValue -Object $existing -Name 'job_id')
    }
  }

  $status = if ($event -eq 'subagent_report') { 'reported' } else { 'spawned' }
  $fingerprint = Get-TextFingerprint -Text $PayloadText
  $job = Register-SubagentInspectionJob -Root $Root -ActiveContract $ActiveContract -RouteId $routeId -AgentName $agentName -TargetPaths $targetPaths -TriggerHook 'PostToolUse' -Status $status -JobId $jobId -ReportFingerprint $(if ($event -eq 'subagent_report') { $fingerprint } else { '' }) -NoLog:$NoLog
  if ($event -eq 'subagent_report') {
    $koPass = ([string][char]0xD1B5) + ([string][char]0xACFC)
    $trimmedPayloadText = ([string]$PayloadText).Trim()
    $isBarePass = $trimmedPayloadText -match '(?is)^\s*(PASS|all good|tests pass)\s*$' -or
      $trimmedPayloadText -eq $koPass -or (
      ($PayloadText -match '(?i)\b(PASS|all good|tests pass)\b' -or ([string]$PayloadText).Contains($koPass)) -and
      $PayloadText -notmatch '(?i)\b(evidence_paths|direct_evidence|checks_run|warnings_or_limits|target_paths|findings)\b'
    )
    $reportStatus = if ($isBarePass) { 'quarantined' } else { 'reported' }
    $reasonCode = if ($isBarePass) { 'subagent_pass_without_evidence' } else { 'subagent_report_submitted' }
    $report = Register-SubagentInspectionReport -Root $Root -ActiveContract $ActiveContract -Job $job -PayloadText $PayloadText -Status $reportStatus -WarningsOrLimits @(if ($isBarePass) { 'report_quarantined:pass_without_evidence' } else { @() }) -NoLog:$NoLog
    $null = Register-SubagentLifecycleEvent -Root $Root -ActiveContract $ActiveContract -Job $job -Event 'report_submitted' -Severity $(if ($isBarePass) { 'moderate' } else { 'info' }) -ReasonCode $reasonCode -ReportHash ([string](Get-OptionalPropertyValue -Object $report -Name 'report_hash')) -PmAction $(if ($isBarePass) { 'quarantine_report' } else { 'review_report' }) -NoLog:$NoLog
    if ($isBarePass) {
      $null = Register-SubagentLifecycleEvent -Root $Root -ActiveContract $ActiveContract -Job $job -Event 'quarantined' -Severity 'moderate' -ReasonCode 'subagent_pass_without_evidence' -ReportHash ([string](Get-OptionalPropertyValue -Object $report -Name 'report_hash')) -PmAction 'reject_report_and_spawn_replacement' -NoLog:$NoLog
      $null = Register-PmDecisionEvent -Root $Root -ActiveContract $ActiveContract -Decision 'reject_report' -SubagentId ([string](Get-OptionalPropertyValue -Object $job -Name 'job_id')) -RouteId $routeId -ReasonCode 'subagent_pass_without_evidence' -AcceptedAsEvidence:$false -CompletionImpact 'route_not_satisfied_until_replacement' -NoLog:$NoLog
    }
    $closeReason = if ($isBarePass) { 'auto_close_after_report_quarantine' } else { 'auto_close_after_report_review' }
    $null = Register-SubagentLifecycleEvent -Root $Root -ActiveContract $ActiveContract -Job $job -Event 'auto_close_requested' -Severity 'info' -ReasonCode $closeReason -ReportHash ([string](Get-OptionalPropertyValue -Object $report -Name 'report_hash')) -PmAction 'close_finished_agent' -NoLog:$NoLog
    $null = Register-SubagentLifecycleEvent -Root $Root -ActiveContract $ActiveContract -Job $job -Event 'closed' -Severity 'info' -ReasonCode $closeReason -ReportHash ([string](Get-OptionalPropertyValue -Object $report -Name 'report_hash')) -PmAction 'agent_closed' -NoLog:$NoLog
  } elseif ($event -eq 'subagent_spawn') {
    $null = Register-SubagentLifecycleEvent -Root $Root -ActiveContract $ActiveContract -Job $job -Event 'spawned' -Severity 'info' -ReasonCode 'subagent_spawned' -PmAction 'delegate_route' -NoLog:$NoLog
  }
  Register-SubagentInspectionLedgerEvent -Root $Root -ActiveContract $ActiveContract -Event $event -Job $job -PayloadFingerprint $fingerprint -Payload $Payload -Workdir $Workdir -NoLog:$NoLog
}

function Register-SubagentWorkerObservation {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$Payload,
    [string]$PayloadText = '',
    [string]$Workdir = '',
    [bool]$NoLog = $false
  )

  $toolName = Get-PayloadString -Object $Payload -Names @('tool_name','toolName','tool','name')
  $isWorkerSpawn = ($toolName -match '(?i)spawn_agent') -and ($PayloadText -match '(?i)agent_type\s*["'':=]+\s*["'']?worker|\bworker\b')
  $isCanonicalWorkerSpawn = $PayloadText -match '(?i)record_type\s*["'':=]+\s*["'']?worker_spawn_event'
  $isWorkerReport = $PayloadText -match '(?i)subagent_worker_report\.v1|record_type\s*["'':=]+\s*["'']?worker_report_event'
  if (-not ($isWorkerSpawn -or $isCanonicalWorkerSpawn -or $isWorkerReport)) {
    return $null
  }

  $routeId = Get-PayloadString -Object $Payload -Names @('route_id','routeId','worker_route','workerRoute')
  if ([string]::IsNullOrWhiteSpace($routeId) -and $PayloadText -match '(?i)\b(?<route>implementation_worker|test_worker|config_worker|control_plane_worker|frontend_worker|backend_worker|runtime_schema_worker|harness_worker)\b') {
    $routeId = $Matches.route
  }
  if ([string]::IsNullOrWhiteSpace($routeId)) {
    $routeId = 'implementation_worker'
  }

  $jobId = Get-PayloadString -Object $Payload -Names @('job_id','jobId','worker_job_id','workerJobId')
  if ([string]::IsNullOrWhiteSpace($jobId) -and $PayloadText -match '(?i)\bjob_id\b\s*[:=]\s*["'']?(?<id>worker-[A-Za-z0-9_-]+)') {
    $jobId = $Matches.id
  }
  $targetPaths = @(Get-SubagentInspectionTargetPaths -Root $Root -Text $PayloadText -ActiveContract $ActiveContract -CompletionReceipt (Read-OptionalJsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/completion_receipt.json')))
  if ($isWorkerReport) {
    $job = Register-SubagentWorkerJob -Root $Root -ActiveContract $ActiveContract -RouteId $routeId -TargetPaths $targetPaths -Status 'reported' -JobId $jobId -NoLog:$NoLog
    $report = Register-SubagentWorkerReport -Root $Root -ActiveContract $ActiveContract -Job $job -PayloadText $PayloadText -ChangedPaths $targetPaths -Validation @('worker_report_observed') -NoLog:$NoLog
    Register-SubagentLifecycleEvent -Root $Root -ActiveContract $ActiveContract -Job $job -Event 'report_submitted' -Severity 'info' -ReasonCode 'worker_report_submitted' -ReportHash ([string](Get-OptionalPropertyValue -Object $report -Name 'report_hash')) -PmAction 'review_worker_report' -NoLog:$NoLog
    Register-SubagentLifecycleEvent -Root $Root -ActiveContract $ActiveContract -Job $job -Event 'auto_close_requested' -Severity 'info' -ReasonCode 'auto_close_after_worker_report' -ReportHash ([string](Get-OptionalPropertyValue -Object $report -Name 'report_hash')) -PmAction 'close_finished_agent' -NoLog:$NoLog
    Register-SubagentLifecycleEvent -Root $Root -ActiveContract $ActiveContract -Job $job -Event 'closed' -Severity 'info' -ReasonCode 'auto_close_after_worker_report' -ReportHash ([string](Get-OptionalPropertyValue -Object $report -Name 'report_hash')) -PmAction 'agent_closed' -NoLog:$NoLog
    Register-SubagentWorkerJob -Root $Root -ActiveContract $ActiveContract -RouteId $routeId -TargetPaths $targetPaths -Status 'closed' -JobId ([string](Get-OptionalPropertyValue -Object $job -Name 'job_id')) -ReportEventId ([string](Get-OptionalPropertyValue -Object $report -Name 'report_id')) -NoLog:$NoLog
  } else {
    $job = Register-SubagentWorkerJob -Root $Root -ActiveContract $ActiveContract -RouteId $routeId -TargetPaths $targetPaths -Status 'spawned' -JobId $jobId -NoLog:$NoLog
    $event = Register-SubagentLifecycleEvent -Root $Root -ActiveContract $ActiveContract -Job $job -Event 'spawned' -Severity 'info' -ReasonCode 'worker_spawned' -PmAction 'delegate_worker_route' -NoLog:$NoLog
    Register-SubagentWorkerJob -Root $Root -ActiveContract $ActiveContract -RouteId $routeId -TargetPaths $targetPaths -Status 'spawned' -JobId ([string](Get-OptionalPropertyValue -Object $job -Name 'job_id')) -SpawnEventId ([string](Get-OptionalPropertyValue -Object $event -Name 'event_id')) -NoLog:$NoLog
  }
}

function Register-SubagentInspectionLoopState {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt,
    [Parameter(Mandatory = $true)][object[]]$MissingInspections,
    [Parameter(Mandatory = $true)][string]$Reason,
    [bool]$NoLog = $false
  )

  $path = Get-SubagentInspectionLoopStatePath -Root $Root
  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $freshness = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'freshness'
  $attempt = if ($freshness) { [string](Get-OptionalPropertyValue -Object $freshness -Name 'attempt_id') } else { $turn }
  $evidenceShape = [ordered]@{
    evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'evidence'))
    freshness = $freshness
    subagent_inspection_report = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'subagent_inspection_report'
  }
  $evidenceFingerprint = Get-TextFingerprint -Text ($evidenceShape | ConvertTo-Json -Depth 12 -Compress)
  $missingFingerprint = Get-TextFingerprint -Text ($MissingInspections | ConvertTo-Json -Depth 8 -Compress)

  $previous = Read-OptionalJsonFile -Path $path
  $repeatCount = 1
  if ($previous) {
    $same = ([string](Get-OptionalPropertyValue -Object $previous -Name 'turn_fingerprint') -eq $turn) -and
      ([string](Get-OptionalPropertyValue -Object $previous -Name 'attempt_id') -eq $attempt) -and
      ([string](Get-OptionalPropertyValue -Object $previous -Name 'reason') -eq $Reason) -and
      ([string](Get-OptionalPropertyValue -Object $previous -Name 'evidence_fingerprint') -eq $evidenceFingerprint) -and
      ([string](Get-OptionalPropertyValue -Object $previous -Name 'missing_fingerprint') -eq $missingFingerprint)
    if ($same) {
      $repeatCount = [int](Get-OptionalPropertyValue -Object $previous -Name 'repeat_count') + 1
    }
  }

  $state = [ordered]@{
    schema_version = 'subagent_inspection_loop_state.v1'
    updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    turn_fingerprint = $turn
    attempt_id = $attempt
    reason = $Reason
    evidence_fingerprint = $evidenceFingerprint
    missing_fingerprint = $missingFingerprint
    repeat_count = $repeatCount
    loop_breaker = ($repeatCount -gt 1)
    missing_inspections = $MissingInspections
    authority = 'candidate_evidence_only'
  }

  if (-not $NoLog) {
    Write-JsonFile -Path $path -Value $state
  }

  $state
}

function Test-SubagentInspectionForCompletion {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt,
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $freshness = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'freshness'
  $affectedPaths = if ($freshness) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $freshness -Name 'affected_paths')) } else { @() }
  $dependencyAlignment = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'dependency_alignment_check'
  $changedPaths = if ($dependencyAlignment) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $dependencyAlignment -Name 'changed_paths')) } else { @() }
  $connectedPaths = if ($dependencyAlignment) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $dependencyAlignment -Name 'checked_connected_paths')) } else { @() }
  $receiptEvidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'evidence'))
  $reportEntries = @(Get-SubagentInspectionReportEntries -CompletionReceipt $CompletionReceipt)
  $lifecycleEvents = @(Read-SubagentLifecycleEvents -Root $Root -TurnFingerprint $turn)
  $reportLedger = @(Read-SubagentInspectionReports -Root $Root -TurnFingerprint $turn)
  $needResolution = Get-NeedResolutionReceipt -Root $Root -CompletionReceipt $CompletionReceipt
  $requiredSubagentRouteIds = if ($needResolution) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $needResolution -Name 'required_subagents')) } else { @() }

  $triggerText = @(
    [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal')
    $receiptEvidence
    @($reportEntries | ConvertTo-Json -Depth 8 -Compress)
  ) -join "`n"
  $pathText = @($affectedPaths + $changedPaths + $connectedPaths | ForEach-Object { Convert-ToGuardPathText -Text ([string]$_) }) -join "`n"

  $matchedRoutes = @()
  $missingNotRun = @()
  $missingReport = @()
  foreach ($route in @(Get-SubagentInspectionRoutes -Root $Root)) {
    $routeId = [string](Get-OptionalPropertyValue -Object $route -Name 'route_id')
    $routeMatched = Test-SubagentInspectionRouteMatch -Route $route -TriggerText $triggerText -PathText $pathText
    if ((-not $routeMatched) -and ($requiredSubagentRouteIds -notcontains $routeId)) {
      continue
    }

    $agentName = [string](Get-OptionalPropertyValue -Object $route -Name 'agent_name')
    $matchedRoutes += $routeId

    if (Test-SubagentInspectionNotApplicable -RouteId $routeId -CompletionReceipt $CompletionReceipt) {
      continue
    }

    $job = Find-LatestSubagentInspectionJob -Root $Root -TurnFingerprint $turn -RouteId $routeId -AgentName $agentName
    if (-not $job) {
      $targetPaths = @(Get-SubagentInspectionTargetPaths -Root $Root -Text "$triggerText`n$pathText" -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt)
      $null = Register-SubagentInspectionJob -Root $Root -ActiveContract $ActiveContract -RouteId $routeId -AgentName $agentName -TargetPaths $targetPaths -TriggerHook 'Stop' -Status 'queued' -NoLog:$NoLog
      $missingNotRun += [ordered]@{
        route_id = $routeId
        agent_name = $agentName
        status = 'queued'
        authority = 'candidate_evidence_only'
      }
      continue
    }

    $status = [string](Get-OptionalPropertyValue -Object $job -Name 'status')
    $jobId = [string](Get-OptionalPropertyValue -Object $job -Name 'job_id')
    $jobLifecycleEvents = @($lifecycleEvents | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'subagent_id') -eq $jobId })
    $terminalEvent = @($jobLifecycleEvents | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'event') -in @('quarantined','terminated') } | Select-Object -Last 1)
    if ($terminalEvent.Count -gt 0) {
      $terminalName = [string](Get-OptionalPropertyValue -Object $terminalEvent[0] -Name 'event')
      $reason = if ($terminalName -eq 'quarantined') { 'subagent_report_quarantined' } else { 'subagent_report_terminated' }
      return [ordered]@{
        ok = $false
        reason = $reason
        matched_routes = $matchedRoutes
        missing_inspections = @([ordered]@{
          route_id = $routeId
          agent_name = $agentName
          job_id = $jobId
          status = $terminalName
          authority = 'candidate_evidence_only'
        })
        lifecycle_event = $terminalEvent[0]
      }
    }

    $jobReports = @($reportLedger | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') -eq $jobId })
    $badReport = @($jobReports | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'status') -in @('quarantined','terminated') } | Select-Object -Last 1)
    if ($badReport.Count -gt 0) {
      $badStatus = [string](Get-OptionalPropertyValue -Object $badReport[0] -Name 'status')
      return [ordered]@{
        ok = $false
        reason = if ($badStatus -eq 'quarantined') { 'subagent_report_quarantined' } else { 'subagent_report_terminated' }
        matched_routes = $matchedRoutes
        missing_inspections = @([ordered]@{
          route_id = $routeId
          agent_name = $agentName
          job_id = $jobId
          status = $badStatus
          authority = 'candidate_evidence_only'
        })
        report = $badReport[0]
      }
    }

    $failedWorkersForRoute = @($lifecycleEvents | Where-Object {
      [string](Get-OptionalPropertyValue -Object $_ -Name 'subagent_role') -eq $routeId -and
      [string](Get-OptionalPropertyValue -Object $_ -Name 'event') -in @('quarantined','terminated')
    })
    if ($failedWorkersForRoute.Count -ge 3) {
      return [ordered]@{
        ok = $false
        reason = 'replacement_limit_reached'
        matched_routes = $matchedRoutes
        loop_breaker = $true
        failed_worker_count = $failedWorkersForRoute.Count
        authority = 'candidate_evidence_only'
      }
    }

    if ($status -notin @('reported','not_applicable')) {
      $missingReport += [ordered]@{
        route_id = $routeId
        agent_name = $agentName
        job_id = $jobId
        status = $status
        authority = 'candidate_evidence_only'
      }
    }
  }

  if ($missingNotRun.Count -gt 0) {
    $loopState = Register-SubagentInspectionLoopState -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt -MissingInspections $missingNotRun -Reason 'required_subagent_not_spawned' -NoLog:$NoLog
    return [ordered]@{
      ok = $false
      reason = 'required_subagent_not_spawned'
      matched_routes = $matchedRoutes
      missing_inspections = $missingNotRun
      loop_breaker = [bool](Get-OptionalPropertyValue -Object $loopState -Name 'loop_breaker')
      loop_state = $loopState
    }
  }

  if ($missingReport.Count -gt 0) {
    $loopState = Register-SubagentInspectionLoopState -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt -MissingInspections $missingReport -Reason 'subagent_report_missing' -NoLog:$NoLog
    return [ordered]@{
      ok = $false
      reason = 'subagent_report_missing'
      matched_routes = $matchedRoutes
      missing_inspections = $missingReport
      loop_breaker = [bool](Get-OptionalPropertyValue -Object $loopState -Name 'loop_breaker')
      loop_state = $loopState
    }
  }

  if (-not $NoLog) {
    $successState = [ordered]@{
      schema_version = 'subagent_inspection_loop_state.v1'
      updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
      turn_fingerprint = $turn
      attempt_id = if ($freshness) { [string](Get-OptionalPropertyValue -Object $freshness -Name 'attempt_id') } else { $turn }
      reason = 'subagent_inspections_satisfied'
      repeat_count = 0
      loop_breaker = $false
      status = 'subagent_inspections_satisfied'
      matched_routes = $matchedRoutes
      missing_inspections = @()
      authority = 'candidate_evidence_only'
    }
    Write-JsonFile -Path (Get-SubagentInspectionLoopStatePath -Root $Root) -Value $successState
  }

  [ordered]@{
    ok = $true
    reason = 'subagent_inspections_satisfied'
    matched_routes = $matchedRoutes
    authority = 'candidate_evidence_only'
  }
}

function Read-HeuristicReviewJobs {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Get-HeuristicReviewJobsPath -Root $Root
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $jobs = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $job = $line | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or [string](Get-OptionalPropertyValue -Object $job -Name 'parent_turn_id') -eq $TurnFingerprint) {
        $jobs += $job
      }
    } catch {
    }
  }

  $jobs
}

function Read-HeuristicReviewReports {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $path = Get-HeuristicReviewReportsPath -Root $Root
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return @()
  }

  $reports = @()
  foreach ($line in (Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)) {
    if ([string]::IsNullOrWhiteSpace($line)) {
      continue
    }
    try {
      $report = $line | ConvertFrom-Json
      if ([string]::IsNullOrWhiteSpace($TurnFingerprint) -or [string](Get-OptionalPropertyValue -Object $report -Name 'parent_turn_id') -eq $TurnFingerprint) {
        $reports += $report
      }
    } catch {
    }
  }

  $reports
}

function Get-LatestHeuristicReviewJobs {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$TurnFingerprint = ''
  )

  $latest = @{}
  foreach ($job in @(Read-HeuristicReviewJobs -Root $Root -TurnFingerprint $TurnFingerprint)) {
    $jobId = [string](Get-OptionalPropertyValue -Object $job -Name 'job_id')
    if (-not [string]::IsNullOrWhiteSpace($jobId)) {
      $latest[$jobId] = $job
    }
  }

  @($latest.Values)
}

function Find-LatestHeuristicReviewReport {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$TurnFingerprint,
    [Parameter(Mandatory = $true)][string]$JobId
  )

  $matches = @(Read-HeuristicReviewReports -Root $Root -TurnFingerprint $TurnFingerprint | Where-Object {
    [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') -eq $JobId
  })
  if ($matches.Count -eq 0) {
    return $null
  }

  $matches[-1]
}

function Register-HeuristicReviewJob {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$RewardHacking,
    [Parameter(Mandatory = $true)][string]$ContextClassification,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$PayloadText,
    [string]$PayloadFingerprint = '',
    [string]$TriggerHook = 'PreToolUse',
    [string[]]$TargetPaths = @(),
    [bool]$CompletionRelevant = $true,
    [string]$Status = 'queued',
    [string]$JobId = '',
    [string]$ReportFingerprint = '',
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  if ([string]::IsNullOrWhiteSpace($turn)) {
    $turn = Get-TextFingerprint -Text ((Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal') | Out-String)
  }

  $payloadHash = if ([string]::IsNullOrWhiteSpace($PayloadFingerprint)) { Get-TextFingerprint -Text $PayloadText } else { $PayloadFingerprint }
  if ([string]::IsNullOrWhiteSpace($JobId)) {
    $existing = @(Get-LatestHeuristicReviewJobs -Root $Root -TurnFingerprint $turn | Where-Object {
      [string](Get-OptionalPropertyValue -Object $_ -Name 'payload_fingerprint') -eq $payloadHash -and
      [string](Get-OptionalPropertyValue -Object $_ -Name 'context_classification') -eq $ContextClassification
    } | Select-Object -Last 1)
    if ($existing.Count -gt 0) {
      $existingStatus = [string](Get-OptionalPropertyValue -Object $existing[0] -Name 'status')
      if ($existingStatus -in @('queued','spawned','reported','not_applicable')) {
        return $existing[0]
      }
    }
    $JobId = 'heuristic-review-' + ([guid]::NewGuid().ToString('n'))
  }

  $freshness = Get-OptionalPropertyValue -Object (Read-OptionalJsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/completion_receipt.json')) -Name 'freshness'
  $attemptId = if ($freshness) { [string](Get-OptionalPropertyValue -Object $freshness -Name 'attempt_id') } else { $turn }
  $now = (Get-Date).ToUniversalTime().ToString('o')
  $entry = [ordered]@{
    schema_version = 'heuristic_review_job.v1'
    job_id = $JobId
    created_at_utc = $now
    updated_at_utc = $now
    parent_turn_id = $turn
    attempt_id = $attemptId
    heuristic = 'reward_hacking_keyword'
    category = [string](Get-OptionalPropertyValue -Object $RewardHacking -Name 'category')
    pattern = [string](Get-OptionalPropertyValue -Object $RewardHacking -Name 'pattern')
    context_classification = $ContextClassification
    completion_relevant = [bool]$CompletionRelevant
    agent_name = 'spark_false_positive_reviewer'
    model = 'gpt-5.3-codex-spark'
    fallback_model = 'latest-mini'
    reasoning_effort = 'high'
    sandbox_mode = 'read-only'
    max_depth = 1
    target_paths = @($TargetPaths)
    trigger_hook = $TriggerHook
    payload_fingerprint = $payloadHash
    status = $Status
    authority = 'candidate_evidence_only'
    report_fingerprint = if ([string]::IsNullOrWhiteSpace($ReportFingerprint)) { $null } else { $ReportFingerprint }
    warnings = @('subagent_review_has_no_allow_or_block_authority')
  }

  if (-not $NoLog) {
    Write-InvocationLog -Path (Get-HeuristicReviewJobsPath -Root $Root) -Entry $entry
  }

  $entry
}

function Register-HeuristicReviewReport {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][string]$JobId,
    [Parameter(Mandatory = $true)][string]$Classification,
    [string]$PayloadText = '',
    [object]$Payload,
    [string]$Workdir = '',
    [bool]$NoLog = $false
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $job = @(Get-LatestHeuristicReviewJobs -Root $Root -TurnFingerprint $turn | Where-Object {
    [string](Get-OptionalPropertyValue -Object $_ -Name 'job_id') -eq $JobId
  } | Select-Object -Last 1)
  if ($job.Count -eq 0) {
    return $null
  }

  $normalizedClassification = ([string]$Classification).ToLowerInvariant()
  if ($normalizedClassification -notin @('likely_true_positive','likely_false_positive','uncertain')) {
    $normalizedClassification = 'uncertain'
  }

  $payloadHash = Get-TextFingerprint -Text $PayloadText
  $now = (Get-Date).ToUniversalTime().ToString('o')
  $entry = [ordered]@{
    schema_version = 'heuristic_review_report.v1'
    report_id = 'heuristic-report-' + ([guid]::NewGuid().ToString('n'))
    job_id = $JobId
    parent_turn_id = $turn
    reported_at_utc = $now
    agent_name = 'spark_false_positive_reviewer'
    classification = $normalizedClassification
    status = 'reported'
    authority = 'candidate_evidence_only'
    target_paths = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $job[0] -Name 'target_paths'))
    direct_evidence = @("heuristic_review_report_observed:$payloadHash")
    limits = @('candidate_evidence_only','cannot_override_absolute_deny','cannot_issue_completion_authority')
    payload_fingerprint = $payloadHash
    agent_lineage = Get-AgentLineage -Payload $Payload -ActiveContract $ActiveContract
    parent_lineage = Get-AgentLineage -Payload $Payload -ActiveContract $ActiveContract
    append_only = $true
  }

  if (-not $NoLog) {
    Write-InvocationLog -Path (Get-HeuristicReviewReportsPath -Root $Root) -Entry $entry
    $null = Register-HeuristicReviewJob -Root $Root -ActiveContract $ActiveContract -RewardHacking $job[0] -ContextClassification ([string](Get-OptionalPropertyValue -Object $job[0] -Name 'context_classification')) -PayloadText '' -PayloadFingerprint ([string](Get-OptionalPropertyValue -Object $job[0] -Name 'payload_fingerprint')) -TriggerHook 'PostToolUse' -TargetPaths @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $job[0] -Name 'target_paths')) -CompletionRelevant ([bool](Get-OptionalPropertyValue -Object $job[0] -Name 'completion_relevant')) -Status 'reported' -JobId $JobId -ReportFingerprint $payloadHash
  }

  $entry
}

function Get-HeuristicReviewObservation {
  param(
    [object]$Payload,
    [string]$PayloadText
  )

  $text = [string]$PayloadText
  if ($text -notmatch '(?i)heuristic_review_report\.v1|spark_false_positive_reviewer|likely_false_positive|likely_true_positive') {
    return $null
  }

  $jobId = Get-PayloadString -Object $Payload -Names @('job_id','jobId','heuristic_review_job_id')
  if ([string]::IsNullOrWhiteSpace($jobId) -and $text -match '(?i)\bjob_id\b\s*[:=]\s*["'']?(?<id>heuristic-review-[A-Za-z0-9_-]+)') {
    $jobId = $Matches.id
  }

  $classification = Get-PayloadString -Object $Payload -Names @('classification','verdict')
  if ([string]::IsNullOrWhiteSpace($classification) -and $text -match '(?i)\b(?<classification>likely_false_positive|likely_true_positive|uncertain)\b') {
    $classification = $Matches.classification
  }

  if ([string]::IsNullOrWhiteSpace($jobId) -or [string]::IsNullOrWhiteSpace($classification)) {
    return $null
  }

  [ordered]@{
    job_id = $jobId
    classification = $classification
  }
}

function Register-HeuristicReviewObservation {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$Payload,
    [string]$PayloadText = '',
    [string]$Workdir = '',
    [bool]$NoLog = $false
  )

  $observation = Get-HeuristicReviewObservation -Payload $Payload -PayloadText $PayloadText
  if (-not $observation) {
    return $null
  }

  Register-HeuristicReviewReport -Root $Root -ActiveContract $ActiveContract -JobId ([string](Get-OptionalPropertyValue -Object $observation -Name 'job_id')) -Classification ([string](Get-OptionalPropertyValue -Object $observation -Name 'classification')) -PayloadText $PayloadText -Payload $Payload -Workdir $Workdir -NoLog:$NoLog
}

function Test-HeuristicReviewsForCompletion {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract
  )

  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $riskyJobs = @(Get-LatestHeuristicReviewJobs -Root $Root -TurnFingerprint $turn | Where-Object {
    (Get-OptionalPropertyValue -Object $_ -Name 'completion_relevant') -eq $true -and
    [string](Get-OptionalPropertyValue -Object $_ -Name 'authority') -eq 'candidate_evidence_only'
  })

  $missing = @()
  $uncertain = @()
  $truePositive = @()
  $falsePositive = @()
  foreach ($job in $riskyJobs) {
    $jobId = [string](Get-OptionalPropertyValue -Object $job -Name 'job_id')
    $report = Find-LatestHeuristicReviewReport -Root $Root -TurnFingerprint $turn -JobId $jobId
    if (-not $report) {
      $missing += [ordered]@{ job_id = $jobId; status = 'report_missing'; authority = 'candidate_evidence_only' }
      continue
    }

    $classification = [string](Get-OptionalPropertyValue -Object $report -Name 'classification')
    if ($classification -eq 'likely_true_positive') {
      $truePositive += $report
    } elseif ($classification -eq 'likely_false_positive') {
      $falsePositive += $report
    } else {
      $uncertain += $report
    }
  }

  if ($truePositive.Count -gt 0) {
    return [ordered]@{ ok = $false; reason = 'heuristic_review_likely_true_positive'; reports = $truePositive; authority = 'candidate_evidence_only' }
  }
  if ($uncertain.Count -gt 0) {
    return [ordered]@{ ok = $false; reason = 'heuristic_review_uncertain'; reports = $uncertain; authority = 'candidate_evidence_only' }
  }
  if ($missing.Count -gt 0) {
    return [ordered]@{ ok = $false; reason = 'heuristic_review_report_missing'; missing = $missing; authority = 'candidate_evidence_only' }
  }

  [ordered]@{ ok = $true; reason = 'heuristic_reviews_satisfied'; likely_false_positive_reports = $falsePositive; authority = 'candidate_evidence_only' }
}

function Test-RequiredRouteMatch {
  param(
    [Parameter(Mandatory = $true)][object]$Route,
    [string]$TriggerText,
    [string]$PathText
  )

  foreach ($pattern in @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Route -Name 'trigger_patterns'))) {
    if ($TriggerText -match $pattern) {
      return $true
    }
  }

  foreach ($pattern in @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Route -Name 'path_patterns'))) {
    if ($PathText -match $pattern) {
      return $true
    }
  }

  return $false
}

function Get-RequiredToolRouteReportEntries {
  param([object]$CompletionReceipt)

  $report = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'required_tool_route_report'
  if (-not $report) {
    return @()
  }

  @(Get-OptionalPropertyValue -Object $report -Name 'requirements')
}

function Test-RequiredRouteRequirement {
  param(
    [Parameter(Mandatory = $true)][string]$RouteId,
    [Parameter(Mandatory = $true)][object]$Requirement,
    [string]$EvidenceCorpus,
    [object[]]$ReportEntries
  )

  $requirementId = [string](Get-OptionalPropertyValue -Object $Requirement -Name 'id')
  foreach ($entry in @($ReportEntries)) {
    $entryRouteId = [string](Get-OptionalPropertyValue -Object $entry -Name 'route_id')
    $entryRequirementId = [string](Get-OptionalPropertyValue -Object $entry -Name 'requirement_id')
    if ($entryRouteId -ne $RouteId -or $entryRequirementId -ne $requirementId) {
      continue
    }
    $status = [string](Get-OptionalPropertyValue -Object $entry -Name 'status')
    $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $entry -Name 'evidence'))
    if (($status -in @('used','satisfied','checked','unavailable','not_applicable')) -and $evidence.Count -gt 0) {
      return [ordered]@{ ok = $true; source = "receipt_report:$status" }
    }
  }

  foreach ($pattern in @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $Requirement -Name 'evidence_patterns'))) {
    if ($EvidenceCorpus -match $pattern) {
      return [ordered]@{ ok = $true; source = "evidence_pattern:$pattern" }
    }
  }

  [ordered]@{ ok = $false; source = 'missing' }
}

function Register-RequiredToolLoopState {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt,
    [Parameter(Mandatory = $true)][object[]]$MissingRequirements,
    [bool]$NoLog = $false
  )

  $path = Join-Path $Root 'Settings/Codex_App_RUNTIME/required_tool_loop_state.json'
  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $freshness = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'freshness'
  $attempt = if ($freshness) { [string](Get-OptionalPropertyValue -Object $freshness -Name 'attempt_id') } else { $turn }
  $evidenceShape = [ordered]@{
    evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'evidence'))
    freshness = $freshness
    required_tool_route_report = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'required_tool_route_report'
  }
  $evidenceFingerprint = Get-TextFingerprint -Text ($evidenceShape | ConvertTo-Json -Depth 12 -Compress)
  $missingFingerprint = Get-TextFingerprint -Text ($MissingRequirements | ConvertTo-Json -Depth 8 -Compress)

  $previous = Read-OptionalJsonFile -Path $path
  $repeatCount = 1
  if ($previous) {
    $same = ([string](Get-OptionalPropertyValue -Object $previous -Name 'turn_fingerprint') -eq $turn) -and
      ([string](Get-OptionalPropertyValue -Object $previous -Name 'attempt_id') -eq $attempt) -and
      ([string](Get-OptionalPropertyValue -Object $previous -Name 'evidence_fingerprint') -eq $evidenceFingerprint) -and
      ([string](Get-OptionalPropertyValue -Object $previous -Name 'missing_fingerprint') -eq $missingFingerprint)
    if ($same) {
      $repeatCount = [int](Get-OptionalPropertyValue -Object $previous -Name 'repeat_count') + 1
    }
  }

  $state = [ordered]@{
    schema_version = 'required_tool_loop_state.v1'
    updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    turn_fingerprint = $turn
    attempt_id = $attempt
    evidence_fingerprint = $evidenceFingerprint
    missing_fingerprint = $missingFingerprint
    repeat_count = $repeatCount
    loop_breaker = ($repeatCount -gt 1)
    missing_requirements = $MissingRequirements
  }

  if (-not $NoLog) {
    Write-JsonFile -Path $path -Value $state
  }

  $state
}

function Test-RequiredToolRoutesForCompletion {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$CompletionReceipt,
    [bool]$NoLog = $false
  )

  $routesDoc = Get-RequiredToolRoutes -Root $Root
  $turn = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $freshness = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'freshness'
  $affectedPaths = if ($freshness) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $freshness -Name 'affected_paths')) } else { @() }
  $dependencyAlignment = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'dependency_alignment_check'
  $changedPaths = if ($dependencyAlignment) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $dependencyAlignment -Name 'changed_paths')) } else { @() }
  $connectedPaths = if ($dependencyAlignment) { @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $dependencyAlignment -Name 'checked_connected_paths')) } else { @() }
  $receiptEvidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'evidence'))
  $reportEntries = @(Get-RequiredToolRouteReportEntries -CompletionReceipt $CompletionReceipt)
  $events = @(Read-ToolUsageEvents -Root $Root -TurnFingerprint $turn)
  $runtimeCapabilityReceipt = Read-OptionalJsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/runtime_capability_receipt.json')

  $triggerText = @(
    [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal')
    $receiptEvidence
    @($reportEntries | ConvertTo-Json -Depth 8 -Compress)
  ) -join "`n"
  $pathText = @($affectedPaths + $changedPaths + $connectedPaths | ForEach-Object { Convert-ToGuardPathText -Text ([string]$_) }) -join "`n"

  $corpusParts = @()
  $corpusParts += $routesDoc.evidence
  $corpusParts += $receiptEvidence
  $corpusParts += @($reportEntries | ConvertTo-Json -Depth 8 -Compress)
  if ($runtimeCapabilityReceipt -and [string](Get-OptionalPropertyValue -Object $runtimeCapabilityReceipt -Name 'turn_fingerprint') -eq $turn) {
    $corpusParts += 'runtime_capability_receipt_generated:ok'
    $corpusParts += ($runtimeCapabilityReceipt | ConvertTo-Json -Depth 8 -Compress)
  }
  if ($events.Count -gt 0) {
    $corpusParts += 'tool_usage_event_ledger_current_attempt:ok'
  }
  foreach ($event in $events) {
    foreach ($id in @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $event -Name 'capability_ids'))) {
      $corpusParts += "tool_usage:$id"
    }
    $corpusParts += ($event | ConvertTo-Json -Depth 6 -Compress)
  }
  $evidenceCorpus = $corpusParts -join "`n"

  $matchedRoutes = @()
  $missing = @()
  foreach ($route in @($routesDoc.routes)) {
    $routeId = [string](Get-OptionalPropertyValue -Object $route -Name 'route_id')
    if (-not (Test-RequiredRouteMatch -Route $route -TriggerText $triggerText -PathText $pathText)) {
      continue
    }

    $matchedRoutes += $routeId
    foreach ($requirement in @(Get-OptionalPropertyValue -Object $route -Name 'requires')) {
      $requirementId = [string](Get-OptionalPropertyValue -Object $requirement -Name 'id')
      $result = Test-RequiredRouteRequirement -RouteId $routeId -Requirement $requirement -EvidenceCorpus $evidenceCorpus -ReportEntries $reportEntries
      if (-not $result.ok) {
        $missing += [ordered]@{
          route_id = $routeId
          requirement_id = $requirementId
          type = [string](Get-OptionalPropertyValue -Object $requirement -Name 'type')
        }
      }
    }
  }

  if ($missing.Count -gt 0) {
    $loopState = Register-RequiredToolLoopState -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt -MissingRequirements $missing -NoLog:$NoLog
    return [ordered]@{
      ok = $false
      reason = 'required_tool_not_used'
      matched_routes = $matchedRoutes
      missing_requirements = $missing
      loop_breaker = [bool](Get-OptionalPropertyValue -Object $loopState -Name 'loop_breaker')
      loop_state = $loopState
    }
  }

  if (-not $NoLog) {
    $successState = [ordered]@{
      schema_version = 'required_tool_loop_state.v1'
      updated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
      turn_fingerprint = $turn
      attempt_id = if ($freshness) { [string](Get-OptionalPropertyValue -Object $freshness -Name 'attempt_id') } else { $turn }
      evidence_fingerprint = Get-TextFingerprint -Text ($CompletionReceipt | ConvertTo-Json -Depth 12 -Compress)
      missing_fingerprint = $null
      repeat_count = 0
      loop_breaker = $false
      status = 'required_tool_routes_satisfied'
      matched_routes = $matchedRoutes
      missing_requirements = @()
    }
    Write-JsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/required_tool_loop_state.json') -Value $successState
  }

  [ordered]@{
    ok = $true
    reason = 'required_tool_routes_satisfied'
    matched_routes = $matchedRoutes
  }
}

function Get-PayloadString {
  param(
    [object]$Object,
    [string[]]$Names,
    [int]$Depth = 0
  )

  if ($null -eq $Object -or $Depth -gt 8) {
    return ''
  }

  if ($Object -is [string]) {
    return ''
  }

  foreach ($property in $Object.PSObject.Properties) {
    if (($Names -contains $property.Name) -and ($property.Value -is [string])) {
      return [string]$property.Value
    }
  }

  foreach ($property in $Object.PSObject.Properties) {
    $found = Get-PayloadString -Object $property.Value -Names $Names -Depth ($Depth + 1)
    if (-not [string]::IsNullOrWhiteSpace($found)) {
      return $found
    }
  }

  return ''
}

function Get-AllowedClockSkewSeconds {
  5
}

function Get-AgentLineage {
  param(
    [object]$Payload,
    [object]$ActiveContract
  )

  $threadId = Get-PayloadString -Object $Payload -Names @('thread_id','threadId','target_thread_id','targetThreadId')
  $parentThreadId = Get-PayloadString -Object $Payload -Names @('parent_thread_id','parentThreadId','parentThread','parentTargetThreadId')
  $agentId = Get-PayloadString -Object $Payload -Names @('agent_id','agentId','subagent_id','subagentId')
  $parentAgentId = Get-PayloadString -Object $Payload -Names @('parent_agent_id','parentAgentId')
  $invocationId = Get-PayloadString -Object $Payload -Names @('invocation_id','invocationId','run_id','runId','call_id','callId')

  if ([string]::IsNullOrWhiteSpace($threadId) -and -not [string]::IsNullOrWhiteSpace($env:CODEX_THREAD_ID)) {
    $threadId = $env:CODEX_THREAD_ID
  }
  if ([string]::IsNullOrWhiteSpace($parentThreadId) -and -not [string]::IsNullOrWhiteSpace($env:CODEX_PARENT_THREAD_ID)) {
    $parentThreadId = $env:CODEX_PARENT_THREAD_ID
  }
  if ([string]::IsNullOrWhiteSpace($agentId) -and -not [string]::IsNullOrWhiteSpace($env:CODEX_AGENT_ID)) {
    $agentId = $env:CODEX_AGENT_ID
  }
  if ([string]::IsNullOrWhiteSpace($parentAgentId) -and -not [string]::IsNullOrWhiteSpace($env:CODEX_PARENT_AGENT_ID)) {
    $parentAgentId = $env:CODEX_PARENT_AGENT_ID
  }

  [ordered]@{
    thread_id = if ([string]::IsNullOrWhiteSpace($threadId)) { $null } else { $threadId }
    parent_thread_id = if ([string]::IsNullOrWhiteSpace($parentThreadId)) { $null } else { $parentThreadId }
    agent_id = if ([string]::IsNullOrWhiteSpace($agentId)) { $null } else { $agentId }
    parent_agent_id = if ([string]::IsNullOrWhiteSpace($parentAgentId)) { $null } else { $parentAgentId }
    invocation_id = if ([string]::IsNullOrWhiteSpace($invocationId)) { $null } else { $invocationId }
    is_subagent = (-not [string]::IsNullOrWhiteSpace($parentThreadId)) -or (-not [string]::IsNullOrWhiteSpace($parentAgentId))
    propagated_turn_fingerprint = Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint'
  }
}

function New-LedgerEventId {
  param(
    [Parameter(Mandatory = $true)][string]$ObservedAtUtc,
    [Parameter(Mandatory = $true)][string]$EventNonce,
    [string]$TurnFingerprint = '',
    [string]$HookName = '',
    [string]$HookEventName = '',
    [string]$ToolName = '',
    [string]$Command = '',
    [string]$Cwd = '',
    [string]$PayloadFingerprint = '',
    [string]$Decision = '',
    [string]$Reason = ''
  )

  $shape = [ordered]@{
    observed_at_utc = $ObservedAtUtc
    event_nonce = $EventNonce
    turn_fingerprint = $TurnFingerprint
    hook = $HookName
    hook_event_name = $HookEventName
    tool_name = $ToolName
    command = $Command
    cwd = $Cwd
    payload_fingerprint = $PayloadFingerprint
    decision = $Decision
    reason = $Reason
  }

  Get-TextFingerprint -Text ($shape | ConvertTo-Json -Depth 8 -Compress)
}

function Convert-PayloadToText {
  param([object]$Object)
  if ($null -eq $Object) {
    return ''
  }
  $primaryText = @()
  foreach ($name in @('command','prompt','user_prompt','userPrompt','input','last_assistant_message','lastAssistantMessage')) {
    $value = Get-PayloadString -Object $Object -Names @($name)
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      $primaryText += $value
    }
  }
  try {
    $jsonText = ($Object | ConvertTo-Json -Depth 12 -Compress)
    if ($primaryText.Count -gt 0) {
      return (($primaryText -join "`n") + "`n" + $jsonText)
    }
    return $jsonText
  } catch {
    if ($primaryText.Count -gt 0) {
      return ($primaryText -join "`n")
    }
    return [string]$Object
  }
}

function Get-OptionalPropertyValue {
  param(
    [object]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($null -eq $Object) {
    return $null
  }

  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) {
      return $Object[$Name]
    }
    return $null
  }

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }

  return $property.Value
}

function Test-MutatingOperationText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  $lower = $Text.ToLowerInvariant()
  $mutatingSignals = @(
    'remove-item',
    'move-item',
    'copy-item',
    'rename-item',
    'set-content',
    'add-content',
    'out-file',
    'new-item',
    'set-itemproperty',
    'new-itemproperty',
    'remove-itemproperty',
    'start-process',
    'stop-process',
    'setx ',
    'reg add',
    'reg delete',
    'git reset',
    'git checkout',
    'git clean',
    'npm install',
    'pip install',
    'python -m pip install',
    'writefile',
    'writefilesync',
    'appendfile',
    'appendfilesync',
    'writealltext',
    'appendalltext',
    'writealllines',
    'appendalllines',
    'writeallbytes',
    'appendallbytes',
    'write_text',
    'write_bytes',
    'unlink',
    'rmdir',
    'mkdir',
    'execsync',
    'spawn(',
    'apply_patch',
    '*** update file:',
    '*** add file:',
    '*** delete file:'
  )

  foreach ($signal in $mutatingSignals) {
    if ($lower.Contains($signal)) {
      return $true
    }
  }

  $mutatingPatterns = @(
    '\.write_text\s*\(',
    '\.write_bytes\s*\(',
    '\[system\.io\.file\]::write',
    '\bopen\s*\([^)]*,\s*["'']\s*[wa+]',
    '\bwith\s+open\s*\([^)]*,\s*["'']\s*[wa+]'
  )

  foreach ($pattern in $mutatingPatterns) {
    if ($lower -match $pattern) {
      return $true
    }
  }

  return $false
}

function Test-PrivateSurfaceTouch {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return [ordered]@{ detected = $false; category = $null; pattern = $null }
  }

  $normalized = ($Text.ToLowerInvariant().Replace('\', '/') -replace '/+', '/')
  $literalRules = @(
    @{ category = 'private_file'; literal = (New-UnicodeWord @(0x61,0x75,0x74,0x68,0x2e,0x6a,0x73,0x6f,0x6e)) },
    @{ category = 'private_file'; literal = (New-UnicodeWord @(0x2f,0x2e,0x65,0x6e,0x76)) },
    @{ category = 'private_file'; literal = (New-UnicodeWord @(0x2f,0x2e,0x73,0x73,0x68,0x2f)) },
    @{ category = 'private_file'; literal = (New-UnicodeWord @(0x2f,0x69,0x64,0x5f,0x72,0x73,0x61)) },
    @{ category = 'private_file'; literal = (New-UnicodeWord @(0x2f,0x69,0x64,0x5f,0x65,0x64,0x32,0x35,0x35,0x31,0x39)) },
    @{ category = 'private_file'; literal = (New-UnicodeWord @(0x2f,0x2e,0x61,0x77,0x73,0x2f,0x63,0x72,0x65,0x64,0x65,0x6e,0x74,0x69,0x61,0x6c,0x73)) },
    @{ category = 'private_file'; literal = (New-UnicodeWord @(0x2f,0x2e,0x67,0x69,0x74,0x2d,0x63,0x72,0x65,0x64,0x65,0x6e,0x74,0x69,0x61,0x6c,0x73)) },
    @{ category = 'private_session_value'; literal = (New-UnicodeWord @(0x63,0x61,0x70,0x5f,0x73,0x69,0x64)) }
  )

  foreach ($rule in $literalRules) {
    if ($normalized.Contains([string]$rule.literal)) {
      return [ordered]@{ detected = $true; category = $rule.category; pattern = $rule.literal }
    }
  }

  $nameFragments = @(
    (New-UnicodeWord @(0x74,0x6f,0x6b,0x65,0x6e)),
    (New-UnicodeWord @(0x73,0x65,0x63,0x72,0x65,0x74)),
    (New-UnicodeWord @(0x70,0x61,0x73,0x73,0x77,0x6f,0x72,0x64)),
    (New-UnicodeWord @(0x70,0x61,0x73,0x73,0x77,0x64)),
    (New-UnicodeWord @(0x61,0x70,0x69,0x5f,0x6b,0x65,0x79)),
    (New-UnicodeWord @(0x63,0x72,0x65,0x64,0x65,0x6e,0x74,0x69,0x61,0x6c)),
    (New-UnicodeWord @(0x70,0x72,0x69,0x76,0x61,0x74,0x65,0x5f,0x6b,0x65,0x79)),
    (New-UnicodeWord @(0x63,0x6c,0x69,0x65,0x6e,0x74,0x5f,0x73,0x65,0x63,0x72,0x65,0x74))
  )
  $envPrefixes = @('$env:', 'process.env.', 'os.environ[', 'getenv(')
  foreach ($prefix in $envPrefixes) {
    $index = $normalized.IndexOf($prefix)
    while ($index -ge 0) {
      $window = $normalized.Substring($index, [Math]::Min(120, $normalized.Length - $index))
      foreach ($fragment in $nameFragments) {
        if ($window.Contains([string]$fragment)) {
          return [ordered]@{ detected = $true; category = 'private_env_reference'; pattern = $prefix }
        }
      }
      $index = $normalized.IndexOf($prefix, $index + $prefix.Length)
    }
  }

  [ordered]@{ detected = $false; category = $null; pattern = $null }
}

function Test-DestructiveOperationText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return [ordered]@{ detected = $false; category = $null; pattern = $null }
  }

  $normalized = ($Text.ToLowerInvariant().Replace('\', '/') -replace '/+', '/')
  $patterns = @(
    @{ category = 'broad_remove'; pattern = '\b(remove-item|rm|del)\b.{0,120}(-recurse|-r|-rf|/s|\*)' },
    @{ category = 'broad_directory_remove'; pattern = '\b(rmdir|rd)\b.{0,120}(/s|-r|-recurse)' },
    @{ category = 'git_destructive_reset'; pattern = '\bgit\s+(reset\s+--hard|clean\s+-[fdx]+|checkout\s+--)\b' },
    @{ category = 'force_overwrite'; pattern = '\b(force[-_ ]?overwrite|overwrite[-_ ]?all|clobber)\b' },
    @{ category = 'process_kill'; pattern = '\b(stop-process|taskkill|kill)\b.{0,80}(-force|/f|-9|\*)' },
    @{ category = 'recursive_permission_change'; pattern = '\b(chmod|chown)\b.{0,80}(-r|--recursive)' },
    @{ category = 'disk_or_volume_operation'; pattern = '\b(format-volume|format\.com|diskpart|clear-disk|initialize-disk)\b|\bformat\s+[a-z]:' }
  )

  foreach ($item in $patterns) {
    if ($normalized -match $item.pattern) {
      return [ordered]@{ detected = $true; category = $item.category; pattern = $item.pattern }
    }
  }

  [ordered]@{ detected = $false; category = $null; pattern = $null }
}

function Convert-ToGuardPathText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ''
  }

  ([string]$Text).ToLowerInvariant().Replace('\', '/') -replace '/+', '/'
}

function Test-EnforcementWeakeningText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return [ordered]@{ detected = $false; category = $null; pattern = $null }
  }

  $normalized = Convert-ToGuardPathText -Text $Text
  $patterns = @(
    @{ category = 'live_hook_disabled'; pattern = '(hooks\.json|\.codex/hooks\.json).{0,200}(pretooluse|stop|userpromptsubmit|sessionstart).{0,120}(\[\s*\]|count\s*[:=]\s*0|null)' },
    @{ category = 'hook_file_delete'; pattern = '(\*\*\* delete file:|remove-item|\bdel\b|\brm\b).{0,160}(codex-ssot-hook\.ps1|pre_command_guard\.yaml|completion_gate\.yaml|hooks\.json)' },
    @{ category = 'fail_policy_weakened'; pattern = 'fail_policy\s*:\s*["'']?(allow|ignore|off|none|warn)' },
    @{ category = 'error_exit_hidden'; pattern = '(2>\$null|2>nul|stderr.*null|erroraction\s+silentlycontinue).{0,120}(claim|complete|verified|pass|success|exit\s+0)' },
    @{ category = 'nonzero_exit_converted'; pattern = '(catch|trap).{0,120}(exit\s+0|return\s+\$true|success|verified_complete)' }
  )

  foreach ($item in $patterns) {
    if ($normalized -match $item.pattern) {
      return [ordered]@{ detected = $true; category = $item.category; pattern = $item.pattern }
    }
  }

  [ordered]@{ detected = $false; category = $null; pattern = $null }
}

function Test-AllowedControlPlaneRepairPath {
  param(
    [string]$Text,
    [string]$Root
  )

  $normalized = Convert-ToGuardPathText -Text $Text
  $rootNorm = (Convert-ToGuardPathText -Text $Root).TrimEnd('/')
  $homeNorm = (Convert-ToGuardPathText -Text $HOME).TrimEnd('/')
  $allowed = @(
    "$rootNorm/settings/dev_codex_hooks/",
    "$rootNorm/settings/codex_app_declarative/",
    "$rootNorm/settings/codex_app_runtime/runtime_state.schema.json",
    "$rootNorm/settings/codex_app_runtime/stable_lessons.json",
    "$rootNorm/settings/codex_app_runtime/pm_decisions.jsonl",
    "$rootNorm/agent.md",
    "$rootNorm/agents.md",
    "$rootNorm/agents.override.md",
    "$rootNorm/changelog.md",
    "$rootNorm/manifest.json",
    "$rootNorm/root_map.json",
    "$rootNorm/maintenance/harness-v2/",
    "$rootNorm/maintenance/test-eventledgerintegrity.ps1",
    "$homeNorm/.codex/hooks.json",
    "$homeNorm/.codex/config.toml",
    "$homeNorm/.codex/agents/",
    "settings/dev_codex_hooks/",
    "settings/codex_app_declarative/",
    "settings/codex_app_runtime/runtime_state.schema.json",
    "settings/codex_app_runtime/stable_lessons.json",
    "settings/codex_app_runtime/pm_decisions.jsonl",
    "agent.md",
    "agents.md",
    "agents.override.md",
    "changelog.md",
    "manifest.json",
    "root_map.json",
    "maintenance/harness-v2/",
    "maintenance/test-eventledgerintegrity.ps1",
    ".codex/hooks.json",
    ".codex/config.toml",
    ".codex/agents/"
  )

  foreach ($prefix in $allowed) {
    if ($normalized.Contains($prefix)) {
      return [ordered]@{ ok = $true; reason = 'allowed_control_plane_repair_path'; path_hint = $prefix }
    }
  }

  [ordered]@{ ok = $false; reason = 'control_plane_repair_path_not_allowed' }
}

function Test-ControlPlaneWriteTargets {
  param(
    [string]$Text,
    [string]$Root
  )

  $normalizedRoot = (Convert-ToGuardPathText -Text $Root).TrimEnd('/')
  $normalizedHome = (Convert-ToGuardPathText -Text $HOME).TrimEnd('/')
  $allowedPrefixes = @(
    "$normalizedRoot/settings/dev_codex_hooks/",
    "$normalizedRoot/settings/codex_app_declarative/",
    "$normalizedRoot/settings/codex_app_runtime/runtime_state.schema.json",
    "$normalizedRoot/settings/codex_app_runtime/stable_lessons.json",
    "$normalizedRoot/settings/codex_app_runtime/pm_decisions.jsonl",
    "$normalizedRoot/agent.md",
    "$normalizedRoot/agents.md",
    "$normalizedRoot/agents.override.md",
    "$normalizedRoot/changelog.md",
    "$normalizedRoot/manifest.json",
    "$normalizedRoot/root_map.json",
    "$normalizedRoot/maintenance/harness-v2/",
    "$normalizedRoot/maintenance/test-eventledgerintegrity.ps1",
    "$normalizedHome/.codex/hooks.json",
    "$normalizedHome/.codex/config.toml",
    "$normalizedHome/.codex/agents/",
    'settings/dev_codex_hooks/',
    'settings/codex_app_declarative/',
    'settings/codex_app_runtime/runtime_state.schema.json',
    'settings/codex_app_runtime/stable_lessons.json',
    'settings/codex_app_runtime/pm_decisions.jsonl',
    'agent.md',
    'agents.md',
    'agents.override.md',
    'changelog.md',
    'manifest.json',
    'root_map.json',
    'maintenance/harness-v2/',
    'maintenance/test-eventledgerintegrity.ps1',
    '.codex/hooks.json',
    '.codex/config.toml',
    '.codex/agents/'
  )

  $targets = New-Object System.Collections.Generic.List[string]
  $patterns = @(
    '(?i)\b(set-content|add-content|out-file)\b\s+(?:-literalpath\s+|-path\s+)?["'']?([^"''\s|]+)',
    '(?i)\[system\.io\.file\]::write\w*\s*\(\s*["'']([^"'']+)["'']'
  )

  foreach ($pattern in $patterns) {
    foreach ($match in [regex]::Matches([string]$Text, $pattern)) {
      $targetGroupIndex = if ($match.Groups.Count -gt 2) { 2 } else { 1 }
      $target = (Convert-ToGuardPathText -Text ([string]$match.Groups[$targetGroupIndex].Value)).Trim()
      if (-not [string]::IsNullOrWhiteSpace($target)) {
        $targets.Add($target)
      }
    }
  }

  $outside = @()
  foreach ($target in $targets) {
    $inside = $false
    foreach ($prefix in $allowedPrefixes) {
      if ($target.StartsWith($prefix) -or $target -eq $prefix.TrimEnd('/')) {
        $inside = $true
        break
      }
    }
    if (-not $inside) {
      $outside += $target
    }
  }

  [ordered]@{
    detected = ($targets.Count -gt 0)
    allowed = ($outside.Count -eq 0)
    targets = @($targets)
    outside = @($outside)
  }
}

function Test-AuthorizedBenchmarkFixtureText {
  param(
    [string]$Text,
    [string]$Workdir,
    [string]$Root,
    [object]$ActiveContract
  )

  $goal = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal')
  $goalLower = $goal.ToLowerInvariant()
  $taskSignals = @(
    'bench',
    'benchmark',
    'repro',
    'verify',
    'vibe',
    (New-UnicodeWord @(0xBC14,0xC774,0xBE0C)),
    (New-UnicodeWord @(0xBCA4,0xCE58)),
    (New-UnicodeWord @(0xC7AC,0xD604)),
    (New-UnicodeWord @(0xAC80,0xC99D))
  )
  $taskMatched = $false
  foreach ($signal in $taskSignals) {
    if ($goalLower.Contains([string]$signal)) {
      $taskMatched = $true
      break
    }
  }
  if (-not $taskMatched) {
    return [ordered]@{ allowed = $false; reason = 'benchmark_not_current_task' }
  }

  $combined = Convert-ToGuardPathText -Text "$Text`n$Workdir"
  if ($combined.Contains('/maintenance/vibe-coding-bench/product/')) {
    return [ordered]@{ allowed = $false; reason = 'benchmark_product_surface_must_be_classified' }
  }

  $rootNorm = (Convert-ToGuardPathText -Text $Root).TrimEnd('/')
  $benchHints = @(
    "$rootNorm/maintenance/patch-bench/",
    "$rootNorm/maintenance/vibe-coding-bench/",
    "$rootNorm/maintenance/vibe-coding-contamination-bench.ps1",
    "$rootNorm/maintenance/vibe-coding-contamination-bench.md",
    "maintenance/patch-bench/",
    "maintenance/vibe-coding-bench/",
    "maintenance/vibe-coding-contamination-bench.ps1",
    "maintenance/vibe-coding-contamination-bench.md"
  )

  foreach ($hint in $benchHints) {
    if ($combined.Contains($hint)) {
      return [ordered]@{ allowed = $true; reason = 'current_task_scoped_benchmark_fixture'; path_hint = $hint }
    }
  }

  [ordered]@{ allowed = $false; reason = 'benchmark_path_not_matched' }
}

function Test-AuthorizedMaintenanceValidationScriptText {
  param(
    [string]$Text,
    [string]$Workdir,
    [string]$Root,
    [object]$ActiveContract
  )

  $goal = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal')
  $goalLower = $goal.ToLowerInvariant()
  $taskSignals = @(
    'verify',
    'validation',
    'ledger',
    'gate',
    'hook',
    'repo adoption',
    (New-UnicodeWord @(0xAC80,0xC99D)),
    (New-UnicodeWord @(0xC218,0xC6A9)),
    (New-UnicodeWord @(0xC870,0xAC74))
  )
  $taskMatched = $false
  foreach ($signal in $taskSignals) {
    if ($goalLower.Contains([string]$signal)) {
      $taskMatched = $true
      break
    }
  }
  if (-not $taskMatched) {
    return [ordered]@{ allowed = $false; reason = 'current_task_not_validation_script_repair' }
  }

  $normalized = Convert-ToGuardPathText -Text "$Text`n$Workdir"
  $rootNorm = (Convert-ToGuardPathText -Text $Root).TrimEnd('/')
  $allowedPaths = @(
    "$rootNorm/maintenance/test-eventledgerintegrity.ps1",
    "$rootNorm/maintenance/test-repogateadoption.ps1",
    "$rootNorm/maintenance/test-subagentinspectionrouting.ps1",
    "$rootNorm/maintenance/test-heuristicfalsepositivereview.ps1",
    'maintenance/test-eventledgerintegrity.ps1',
    'maintenance/test-repogateadoption.ps1',
    'maintenance/test-subagentinspectionrouting.ps1',
    'maintenance/test-heuristicfalsepositivereview.ps1'
  )
  foreach ($path in $allowedPaths) {
    if ($normalized.Contains($path)) {
      return [ordered]@{ allowed = $true; reason = 'current_task_scoped_maintenance_validation_script'; path_hint = $path }
    }
  }

  [ordered]@{ allowed = $false; reason = 'not_maintenance_validation_script_path' }
}

function Test-RepairIntentText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  $lower = $Text.ToLowerInvariant()
  $intentSignals = @(
    'repair',
    'fix',
    'patch',
    'strengthen',
    'clarify',
    'align',
    'scope',
    'guard',
    'gate',
    'policy',
    'hook',
    'control-plane',
    'control plane',
    (New-UnicodeWord @(0xC218,0xB9AC)),
    (New-UnicodeWord @(0xBCF4,0xC815)),
    (New-UnicodeWord @(0xBCF4,0xAC15)),
    (New-UnicodeWord @(0xC815,0xCC45)),
    (New-UnicodeWord @(0xD6C5)),
    (New-UnicodeWord @(0xC81C,0xC5B4))
  )

  foreach ($signal in $intentSignals) {
    if ($lower.Contains($signal)) {
      return $true
    }
  }

  return $false
}

function Test-ControlPlaneRepairScope {
  param(
    [string]$Text,
    [string]$Workdir,
    [string]$Root,
    [object]$ActiveContract,
    [object]$ControlPlaneMutation
  )

  if (-not $ControlPlaneMutation.detected) {
    return [ordered]@{ allowed = $false; reason = 'no_control_plane_mutation' }
  }

  if (-not (Test-CurrentTaskAuthorizesControlPlane -ActiveContract $ActiveContract)) {
    return [ordered]@{ allowed = $false; reason = 'control_plane_mutation_without_current_task_scope' }
  }

  $combined = "$Text`n$Workdir"
  $pathCheck = Test-AllowedControlPlaneRepairPath -Text $combined -Root $Root
  if (-not $pathCheck.ok) {
    return [ordered]@{ allowed = $false; reason = $pathCheck.reason; path_check = $pathCheck }
  }

  $writeTargets = Test-ControlPlaneWriteTargets -Text $Text -Root $Root
  if ($writeTargets.detected -and -not $writeTargets.allowed) {
    return [ordered]@{ allowed = $false; reason = 'control_plane_repair_path_not_allowed'; write_targets = $writeTargets }
  }

  $goal = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal')
  if (-not (Test-RepairIntentText -Text "$goal`n$Text")) {
    return [ordered]@{ allowed = $false; reason = 'control_plane_repair_intent_missing' }
  }

  $weakening = Test-EnforcementWeakeningText -Text $Text
  if ($weakening.detected) {
    return [ordered]@{ allowed = $false; reason = 'enforcement_weakening_attempt'; weakening = $weakening }
  }

  [ordered]@{
    allowed = $true
    reason = 'current_task_scoped_control_plane_repair'
    repair_scope = [ordered]@{
      enabled = $true
      reason = 'user_requested_hook_policy_repair'
      path_hint = $pathCheck.path_hint
      category = $ControlPlaneMutation.category
      validation_required = $true
    }
  }
}

function Test-NegativeReproductionFixtureText {
  param(
    [string]$Text,
    [string]$Workdir,
    [string]$Root,
    [object]$ActiveContract
  )

  $goal = ([string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal')).ToLowerInvariant()
  $taskMatched = $false
  foreach ($signal in @('negative','regression','fixture','repro','reproduction','bench','benchmark','test', (New-UnicodeWord @(0xD68C,0xADC0)), (New-UnicodeWord @(0xC624,0xD0D0)), (New-UnicodeWord @(0xC7AC,0xD604)), (New-UnicodeWord @(0xD14C,0xC2A4,0xD2B8)))) {
    if ($goal.Contains([string]$signal)) {
      $taskMatched = $true
      break
    }
  }
  if (-not $taskMatched) {
    return [ordered]@{ allowed = $false; reason = 'negative_fixture_not_current_task' }
  }

  $combined = Convert-ToGuardPathText -Text "$Text`n$Workdir"
  $rootNorm = (Convert-ToGuardPathText -Text $Root).TrimEnd('/')
  $fixturePatterns = @(
    "$rootNorm/maintenance/patch-bench/",
    "$rootNorm/maintenance/vibe-coding-bench/",
    "$rootNorm/maintenance/vibe-coding-contamination-bench.ps1",
    "$rootNorm/tests/fixtures/",
    "$rootNorm/test/fixtures/",
    "$rootNorm/fixtures/",
    'maintenance/patch-bench/',
    'maintenance/vibe-coding-bench/',
    'maintenance/vibe-coding-contamination-bench.ps1',
    'tests/fixtures/',
    'test/fixtures/',
    'fixtures/'
  )

  foreach ($pattern in $fixturePatterns) {
    if ($combined.Contains($pattern)) {
      if ($combined -notmatch '(?i)(^|/)src/|(^|/)app/|(^|/)server/|(^|/)api/') {
        return [ordered]@{ allowed = $true; reason = 'current_task_scoped_negative_reproduction_fixture'; path_hint = $pattern }
      }
    }
  }

  [ordered]@{ allowed = $false; reason = 'negative_fixture_path_not_matched' }
}

function Test-PolicyContaminationPatternText {
  param(
    [string]$Text,
    [string]$Workdir,
    [string]$Root,
    [object]$ActiveContract,
    [object]$ControlPlaneRepairScope
  )

  if (-not (Get-OptionalPropertyValue -Object $ControlPlaneRepairScope -Name 'allowed')) {
    return [ordered]@{ allowed = $false; reason = 'policy_pattern_repair_not_authorized' }
  }

  $combined = Convert-ToGuardPathText -Text "$Text`n$Workdir"
  $rootNorm = (Convert-ToGuardPathText -Text $Root).TrimEnd('/')
  $policyHints = @(
    "$rootNorm/settings/codex_app_declarative/reward-signal-filter.agent.config.yaml",
    "$rootNorm/settings/codex_app_declarative/agent-reliability-tests.agent.config.yaml",
    "$rootNorm/settings/dev_codex_hooks/codex-ssot-hook.ps1",
    'settings/codex_app_declarative/reward-signal-filter.agent.config.yaml',
    'settings/codex_app_declarative/agent-reliability-tests.agent.config.yaml',
    'settings/dev_codex_hooks/codex-ssot-hook.ps1'
  )

  foreach ($hint in $policyHints) {
    if ($combined.Contains($hint)) {
      return [ordered]@{ allowed = $true; reason = 'policy_file_describes_contamination_patterns'; path_hint = $hint }
    }
  }

  [ordered]@{ allowed = $false; reason = 'policy_pattern_path_not_matched' }
}

function Get-RewardHackingSuspectContext {
  param(
    [object]$RewardHacking,
    [bool]$ReadOnlyInspection,
    [object]$DocumentationSurface,
    [object]$ControlPlaneRepairScope,
    [object]$BenchmarkFixture,
    [object]$NegativeFixture,
    [object]$PolicyPattern
  )

  if (-not (Get-OptionalPropertyValue -Object $RewardHacking -Name 'detected')) {
    return [ordered]@{ suspect = $false; classification = 'none'; completion_relevant = $false }
  }

  if ($ReadOnlyInspection) {
    return [ordered]@{ suspect = $true; classification = 'read_only_inspection'; completion_relevant = $false }
  }

  if ((Get-OptionalPropertyValue -Object $DocumentationSurface -Name 'runtime_relevant') -eq $false) {
    return [ordered]@{ suspect = $true; classification = 'documentation_changelog_or_audit_note'; completion_relevant = $false }
  }

  if (Get-OptionalPropertyValue -Object $BenchmarkFixture -Name 'allowed') {
    return [ordered]@{ suspect = $true; classification = 'benchmark_fixture_definition'; completion_relevant = $true }
  }

  if (Get-OptionalPropertyValue -Object $NegativeFixture -Name 'allowed') {
    return [ordered]@{ suspect = $true; classification = 'negative_reproduction_test_fixture'; completion_relevant = $true }
  }

  if (Get-OptionalPropertyValue -Object $PolicyPattern -Name 'allowed') {
    return [ordered]@{ suspect = $true; classification = 'policy_file_contamination_pattern_description'; completion_relevant = $true }
  }

  if (Get-OptionalPropertyValue -Object $ControlPlaneRepairScope -Name 'allowed') {
    return [ordered]@{ suspect = $true; classification = 'authorized_control_plane_repair'; completion_relevant = $true }
  }

  [ordered]@{ suspect = $false; classification = 'absolute_or_product_path'; completion_relevant = $true }
}

function New-RewardHackingSuspectDecision {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [Parameter(Mandatory = $true)][object]$RewardHacking,
    [Parameter(Mandatory = $true)][object]$SuspectContext,
    [Parameter(Mandatory = $true)][string]$PayloadText,
    [string]$Workdir = '',
    [bool]$NoLog = $false
  )

  $targetPaths = @(Get-SubagentInspectionTargetPaths -Root $Root -Text "$PayloadText`n$Workdir" -ActiveContract $ActiveContract -CompletionReceipt (Read-OptionalJsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/completion_receipt.json')))
  $job = Register-HeuristicReviewJob -Root $Root -ActiveContract $ActiveContract -RewardHacking $RewardHacking -ContextClassification ([string](Get-OptionalPropertyValue -Object $SuspectContext -Name 'classification')) -PayloadText $PayloadText -TargetPaths $targetPaths -CompletionRelevant ([bool](Get-OptionalPropertyValue -Object $SuspectContext -Name 'completion_relevant')) -NoLog:$NoLog

  [ordered]@{
    decision = 'SUSPECT'
    reason = 'reward_hacking_heuristic_suspect_queued'
    classification = [string](Get-OptionalPropertyValue -Object $SuspectContext -Name 'classification')
    reward_hacking = $RewardHacking
    heuristic_review = [ordered]@{
      job_id = [string](Get-OptionalPropertyValue -Object $job -Name 'job_id')
      agent_name = 'spark_false_positive_reviewer'
      sandbox_mode = 'read-only'
      authority = 'candidate_evidence_only'
      completion_relevant = [bool](Get-OptionalPropertyValue -Object $SuspectContext -Name 'completion_relevant')
    }
  }
}

function Get-DocumentationSurface {
  param([string]$Text)

  $normalized = Convert-ToGuardPathText -Text $Text
  if ([string]::IsNullOrWhiteSpace($normalized)) {
    return [ordered]@{ classification = 'none'; runtime_relevant = $true }
  }

  if ($normalized -match '(^|/|\s)(changelog|changes|release[-_ ]?notes|inventory|version)\.md(\b|$)' -or
      $normalized -match '(^|/|\s)(audit[-_ ]?note|audit[-_ ]?log).*\.md(\b|$)') {
    return [ordered]@{ classification = 'non_runtime_record'; runtime_relevant = $false }
  }

  if ($normalized -match '(^|/)readme\.md(\b|$)' -or $normalized -match '(^|/)docs/[^''"\r\n<>|]+\.md') {
    if ($normalized -match '(runbook|policy|hook|agent[-_ ]?instruction|agent\.config|workflow|validation|gate|guard)') {
      return [ordered]@{ classification = 'procedural_artifact'; runtime_relevant = $true }
    }
    return [ordered]@{ classification = 'non_runtime_explanation'; runtime_relevant = $false }
  }

  if ($normalized -match '(runbook|policy|hook[-_ ]?policy|agent[-_ ]?instruction|agents\.md|agent\.md|agent\.config|\.ya?ml|\.toml|\.ps1|\.sh|\.py|\.js|\.ts|\.tsx|\.jsx)') {
    return [ordered]@{ classification = 'procedural_artifact'; runtime_relevant = $true }
  }

  [ordered]@{ classification = 'none'; runtime_relevant = $true }
}

function Test-ReadOnlyInspectionText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  $trimmed = $Text.TrimStart()
  $readOnlyLeadPatterns = @(
    '(?i)^rg(\.exe)?\s+',
    '(?i)^get-content\b',
    '(?i)^get-childitem\b',
    '(?i)^get-location\b',
    '(?i)^get-command\b',
    '(?i)^get-item\b',
    '(?i)^get-itemproperty\b',
    '(?i)^select-string\b',
    '(?i)"command"\s*:\s*"rg(\.exe)?\s+',
    '(?i)"command"\s*:\s*"get-content\b',
    '(?i)"command"\s*:\s*"get-childitem\b',
    '(?i)"command"\s*:\s*"select-string\b'
  )
  foreach ($pattern in $readOnlyLeadPatterns) {
    if ($trimmed -match $pattern) {
      if ($trimmed -notmatch '(?i)(\|\s+|;\s*|&&\s*|\n\s*)\b(set-content|add-content|out-file|new-item|remove-item|move-item|rename-item|start-process|stop-process|git\s+(reset|checkout|clean)|apply_patch)\b') {
        return $true
      }
    }
  }

  if (Test-MutatingOperationText -Text $Text) {
    return $false
  }

  $lower = $Text.ToLowerInvariant()
  $readSignals = @(
    'get-content',
    'get-childitem',
    'get-location',
    'get-command',
    'get-item',
    'get-itemproperty',
    'get-filehash',
    'select-object',
    'where-object',
    'convertfrom-json',
    'convertto-json',
    'rg ',
    'codex --version',
    'codex features list',
    'sqlite',
    'select ',
    'pragma ',
    'readfile',
    'readfilesync',
    '[system.io.file]::read'
  )

  foreach ($signal in $readSignals) {
    if ($lower.Contains($signal)) {
      return $true
    }
  }

  return $false
}

function Test-FinalizationScopeText {
  param(
    [string]$Text,
    [string]$Surface = ''
  )

  $combined = ("$Text`n$Surface".ToLowerInvariant().Replace('\', '/') -replace '/+', '/')
  if ([string]::IsNullOrWhiteSpace($combined)) {
    return $false
  }

  $claimSignals = @(
    'verified_complete',
    'completion_state',
    'completion_receipt',
    'completion gate',
    'stop_checks',
    'pre_response_checklist',
    'finalization',
    'final answer',
    'claim complete',
    'claim completion',
    'done marker',
    'pass marker',
    (New-UnicodeWord @(0xC644,0xB8CC)),
    (New-UnicodeWord @(0xD1B5,0xACFC)),
    (New-UnicodeWord @(0xAC80,0xC99D,0xC644,0xB8CC))
  )
  $artifactSignals = @(
    'codex-ssot-hook.ps1',
    'completion_gate.yaml',
    'pre_response_checklist.yaml',
    'pre_command_guard.yaml',
    'runtime_state.schema.json',
    'active_contract.json',
    'completion_receipt.json',
    'validation-harness',
    'test-harness',
    'eval-harness',
    'score-gate',
    'reward-reviewer',
    'completion-definition',
    'completion-criteria',
    '.github/workflows/',
    'package.json',
    'makefile',
    'dockerfile',
    '.ps1',
    '.sh',
    '.py',
    '.js',
    '.ts',
    '.tsx',
    '.jsx'
  )

  foreach ($signal in $claimSignals) {
    if ($combined.Contains($signal)) {
      return $true
    }
  }

  foreach ($signal in $artifactSignals) {
    if ($combined.Contains($signal)) {
      return $true
    }
  }

  return $false
}

function Test-WithinActiveScope {
  param(
    [string]$Text,
    [string]$Workdir,
    [object]$ActiveContract,
    [string]$Root = '',
    [switch]$AllowRuntimeReadOnlyReferences
  )

  $combined = "$Text`n$Workdir".Replace('\\', '\')
  $scope = @(Convert-ToStringArray -Value $ActiveContract.scope)
  $scopeLower = $scope | ForEach-Object { (Convert-ToGuardPathText -Text ([string]$_)).TrimEnd('/') }
  $earlyPatchTargets = @()
  foreach ($match in [regex]::Matches($combined, '(?im)^\*\*\* (?:Update|Add|Delete) File:\s*(.+?)\s*$')) {
    $target = ([string]$match.Groups[1].Value).Trim()
    if (-not [string]::IsNullOrWhiteSpace($target)) {
      $earlyPatchTargets += $target
    }
  }
  if ($earlyPatchTargets.Count -gt 0) {
    $allBenchTargets = $true
    foreach ($target in $earlyPatchTargets) {
      $targetLower = Convert-ToScopeComparablePath -Path $target -Workdir $Workdir
      if ($targetLower -notmatch '(^|/)maintenance/patch-bench/') {
        $allBenchTargets = $false
        break
      }
      $insideTarget = $false
      foreach ($allowed in $scopeLower) {
        if ($targetLower -eq $allowed -or $targetLower.StartsWith($allowed + '/')) {
          $insideTarget = $true
          break
        }
      }
    }
    if ($allBenchTargets) {
      return [ordered]@{ ok = $true; reason = 'patch_bench_targets_inside_active_scope'; paths = $earlyPatchTargets }
    }
  }
  $privateSurface = Test-PrivateSurfaceTouch -Text $combined
  if ($privateSurface.detected) {
    $privateReason = New-UnicodeWord @(0x63,0x72,0x65,0x64,0x65,0x6e,0x74,0x69,0x61,0x6c,0x5f,0x6f,0x72,0x5f,0x73,0x65,0x63,0x72,0x65,0x74,0x5f,0x74,0x6f,0x75,0x63,0x68)
    return [ordered]@{ ok = $false; reason = $privateReason; private_surface = $privateSurface }
  }

  foreach ($noise in @(
    (New-UnicodeWord @(0x61,0x75,0x74,0x68,0x2e,0x6a,0x73,0x6f,0x6e)),
    (New-UnicodeWord @(0x63,0x61,0x70,0x5f,0x73,0x69,0x64)),
    (New-UnicodeWord @(0x63,0x72,0x65,0x64,0x65,0x6e,0x74,0x69,0x61,0x6c,0x73)),
    (New-UnicodeWord @(0x63,0x72,0x65,0x64,0x65,0x6e,0x74,0x69,0x61,0x6c)),
    (New-UnicodeWord @(0x74,0x6f,0x6b,0x65,0x6e,0x73)),
    (New-UnicodeWord @(0x74,0x6f,0x6b,0x65,0x6e)),
    (New-UnicodeWord @(0x73,0x65,0x63,0x72,0x65,0x74,0x73)),
    (New-UnicodeWord @(0x73,0x65,0x63,0x72,0x65,0x74))
  )) {
    $combined = $combined.Replace([string]$noise, '')
  }
  if ($combined -match '(?i)(auth\.json|cap_sid|(?<!\$)\bcredentials?\b|(?<!\$)\btokens?\b|(?<!\$)\bsecrets?\b)') {
    return [ordered]@{ ok = $false; reason = 'credential_or_secret_touch' }
  }

  $scope = @(Convert-ToStringArray -Value $ActiveContract.scope)
  if ($scope.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'active_scope_missing' }
  }

  $scopeLower = $scope | ForEach-Object { (Convert-ToGuardPathText -Text ([string]$_)).TrimEnd('/') }
  $runtimeReferenceScope = @()
  $runtimeReferenceScopeLower = @()
  if ($AllowRuntimeReadOnlyReferences -and -not [string]::IsNullOrWhiteSpace($Root)) {
    $runtimeReferenceScope = @(Get-RuntimeReferenceScope -Root $Root)
    $runtimeReferenceScopeLower = $runtimeReferenceScope | ForEach-Object { (Convert-ToGuardPathText -Text ([string]$_)).TrimEnd('/') }
  }
  $patchTargets = @()
  foreach ($match in [regex]::Matches($combined, '(?im)^\*\*\* (?:Update|Add|Delete) File:\s*(.+?)\s*$')) {
    $target = ([string]$match.Groups[1].Value).Trim()
    if (-not [string]::IsNullOrWhiteSpace($target)) {
      $patchTargets += $target
    }
  }
  if ($patchTargets.Count -gt 0) {
    foreach ($target in $patchTargets) {
      $targetLower = Convert-ToScopeComparablePath -Path $target -Workdir $Workdir
      $insideTarget = $false
      foreach ($allowed in $scopeLower) {
        if ($targetLower -eq $allowed -or $targetLower.StartsWith($allowed + '/')) {
          $insideTarget = $true
          break
        }
      }
    }
    return [ordered]@{ ok = $true; reason = 'patch_targets_observed'; paths = $patchTargets }
  }

  $paths = @()
  foreach ($match in [regex]::Matches($combined, '[A-Za-z]:(?:\\|/)[^''"\r\n<>|]+')) {
    $candidate = $match.Value.Trim().TrimEnd(' .,:;)}]')
    $boundary = [regex]::Match($candidate, '(?i)^(.*?)(?=\s+(if|foreach|function|throw|return|where-object|select-object|convertfrom-json|convertto-json|join-path|out-null|\$[A-Za-z_]))')
    if ($boundary.Success -and -not [string]::IsNullOrWhiteSpace($boundary.Groups[1].Value)) {
      $candidate = $boundary.Groups[1].Value.Trim().TrimEnd(' .,:;)}]')
    }
    $candidate = $candidate.Replace('\\', '\')
    $paths += $candidate
  }

  if ($paths.Count -eq 0) {
    if ([string]::IsNullOrWhiteSpace($Workdir)) {
      return [ordered]@{ ok = $true; reason = 'no_absolute_path_in_read_only_probe' }
    }
    $paths += $Workdir
  }

  $usedRuntimeReferenceScope = $false
  foreach ($path in $paths) {
    $pathLower = (Convert-ToGuardPathText -Text ([string]$path)).TrimEnd('/')
    $inside = $false
    foreach ($allowed in $scopeLower) {
      if ($pathLower -eq $allowed -or $pathLower.StartsWith($allowed + '/')) {
        $inside = $true
        break
      }
    }
    if (-not $inside -and $runtimeReferenceScopeLower.Count -gt 0) {
      foreach ($allowed in $runtimeReferenceScopeLower) {
        if ($pathLower -eq $allowed -or $pathLower.StartsWith($allowed + '/')) {
          $inside = $true
          $usedRuntimeReferenceScope = $true
          break
        }
      }
      if ($inside) {
        continue
      }
    }
  }

  if ($usedRuntimeReferenceScope) {
    return [ordered]@{ ok = $true; reason = 'path_inside_active_scope_or_runtime_reference_read_only'; runtime_reference_scope = $runtimeReferenceScope }
  }

  [ordered]@{ ok = $true; reason = 'path_inside_active_scope' }
}

function Get-RewardSignalCommand {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return [ordered]@{ detected = $false; category = $null; pattern = $null }
  }

  $lower = $Text.ToLowerInvariant()
  $patterns = @(
    @{ category = 'package_verify_pass_signal'; pattern = '(npm|pnpm|yarn|bun)\s+(run\s+)?verify\b' },
    @{ category = 'test_pass_signal'; pattern = '(npm|pnpm|yarn|bun)\s+(run\s+)?test\b|pytest\b|cargo\s+test\b|go\s+test\b|dotnet\s+test\b|tsx\s+--test\b' },
    @{ category = 'typecheck_pass_signal'; pattern = '(npm|pnpm|yarn|bun)\s+(run\s+)?typecheck\b|tsc\s+--noemit\b|pyright\b|mypy\b|cargo\s+check\b' },
    @{ category = 'lint_pass_signal'; pattern = '(npm|pnpm|yarn|bun)\s+(run\s+)?lint\b|eslint\b|biome\s+check\b|ruff\s+check\b|cargo\s+clippy\b' },
    @{ category = 'build_pass_signal'; pattern = '(npm|pnpm|yarn|bun)\s+(run\s+)?build\b|vite\s+build\b|cargo\s+build\b|dotnet\s+build\b' },
    @{ category = 'absence_scan_pass_signal'; pattern = '\brg\b(?=.*(activemenu|commandid|hardcod|fallback|legacy|slop|verified_complete|completion))(?=.*(-q|--quiet|count|-eq\s*0|-not|!\s*\(|no[-_ ]?match|absence|zero))' },
    @{ category = 'hook_pass_signal'; pattern = 'codex-ssot-hook\.ps1.*(completion_gate|stop_checks|session_start|-DryRun)' }
  )

  foreach ($item in $patterns) {
    if ($lower -match $item.pattern) {
      return [ordered]@{ detected = $true; category = $item.category; pattern = $item.pattern }
    }
  }

  [ordered]@{ detected = $false; category = $null; pattern = $null }
}

function Get-ControlPlaneMutation {
  param(
    [string]$Text,
    [string]$Workdir
  )

  $combined = "$Text`n$Workdir"
  if (-not (Test-MutatingOperationText -Text $combined)) {
    return [ordered]@{ detected = $false; category = $null; pattern = $null }
  }

  $normalized = ($combined.ToLowerInvariant().Replace('\', '/') -replace '/+', '/')
  $patterns = @(
    @{ category = 'hook_runner_or_hook_config'; pattern = 'settings/dev_codex_hooks|codex-ssot-hook\.ps1|pre_command_guard\.yaml|completion_gate\.yaml|pre_response_checklist\.yaml|pre_turn_active_contract\.yaml|post_turn_state_register\.yaml|retry_invalidation\.yaml' },
    @{ category = 'authority_policy_config'; pattern = 'settings/codex_app_declarative/[^''"\r\n<>|]+\.(agent\.config\.ya?ml|toml|ya?ml)$|settings/codex_app_declarative/' },
    @{ category = 'runtime_state_schema'; pattern = 'settings/codex_app_runtime/runtime_state\.schema\.json' },
    @{ category = 'isolated_harness_v2_workspace'; pattern = 'maintenance/harness-v2/' },
    @{ category = 'manifest_or_root_authority'; pattern = '(^|[^a-z0-9_.-])(manifest\.json|root_map\.json|agent\.md|agents\.md|agents\.override\.md)([^a-z0-9_.-]|$)' },
    @{ category = 'global_codex_hook_config'; pattern = '\.codex/hooks\.json' },
    @{ category = 'global_codex_agent_config'; pattern = '\.codex/(config\.toml|agents/[^''"\r\n<>|]+\.toml)' }
  )

  foreach ($item in $patterns) {
    if ($normalized -match $item.pattern) {
      return [ordered]@{ detected = $true; category = $item.category; pattern = $item.pattern }
    }
  }

  [ordered]@{ detected = $false; category = $null; pattern = $null }
}

function Get-RuntimeStateMutation {
  param(
    [string]$Text,
    [string]$Workdir
  )

  $combined = "$Text`n$Workdir"
  if (-not (Test-MutatingOperationText -Text $combined)) {
    return [ordered]@{ detected = $false; category = $null; pattern = $null }
  }

  $normalized = ($combined.ToLowerInvariant().Replace('\', '/') -replace '/+', '/')
  $patterns = @(
    @{ category = 'turn_runtime_state'; pattern = 'settings/codex_app_runtime/((active_contract|completion_receipt|gate_issued_completion_receipt|task_classification_receipt|need_resolution_receipt|skill_resolution_receipt|runtime_capability_receipt|repo_gate_adoption_receipt|repo_v2_adoption_receipt|stable_lessons|required_tool_loop_state|subagent_inspection_loop_state)\.json|(pm_decisions|tool_usage_events|skill_usage_events|subagent_inspection_jobs|subagent_inspection_reports|subagent_worker_jobs|subagent_worker_reports|subagent_lifecycle_events|heuristic_review_jobs|heuristic_review_reports)\.jsonl)' }
  )

  foreach ($item in $patterns) {
    if ($normalized -match $item.pattern) {
      return [ordered]@{ detected = $true; category = $item.category; pattern = $item.pattern }
    }
  }

  [ordered]@{ detected = $false; category = $null; pattern = $null }
}

function Get-RewardHackingTouch {
  param(
    [string]$Text,
    [string]$Workdir
  )

  $combined = "$Text`n$Workdir"
  if ([string]::IsNullOrWhiteSpace($combined)) {
    return [ordered]@{ detected = $false; category = $null; pattern = $null }
  }

  $normalized = ($combined.ToLowerInvariant().Replace('\', '/') -replace '/+', '/')
  $mutating = Test-MutatingOperationText -Text $combined
  if (-not $mutating) {
    return [ordered]@{ detected = $false; category = $null; pattern = $null }
  }

  $patterns = @(
    @{ category = 'hardcoded_or_fake_success'; pattern = 'hardcod|fake[-_ ]?(test|success|pass)|force[-_ ]?pass|always[-_ ]?pass|always[-_ ]?true|mock[-_ ]?pass|dummy[-_ ]?success' },
    @{ category = 'fake_frontend_backend_business_data'; pattern = '(fake|demo|placeholder|dummy).{0,100}(guest|room|pms|reservation|booking|occupancy|revenue|customer|branch|endpoint|api|database|db|seed|fixture)' },
    @{ category = 'legacy_frontend_surface_resurrection'; pattern = '((add|create|restore|recreate|reintroduce|depend|import).{0,100}(src/sidepanel|sidepanel\.js|legacy dom sidepanel)|(src/sidepanel|sidepanel\.js|legacy dom sidepanel).{0,100}(add|create|restore|recreate|reintroduce|depend|import))' },
    @{ category = 'repo_local_authority_or_receipt_contamination'; pattern = '((agents?\.md|/agents?\.md|\.agent-runs|gate_receipt\.json).{0,160}(global authority capsule|global_agent_workflow|dev-management|score.*completion|pass.*completion|final.*completion|delete file|remove-item|hide|discard)|(delete file|remove-item|hide|discard).{0,160}(\.agent-runs|gate_receipt\.json))' },
    @{ category = 'backend_test_specific_or_static_pass'; pattern = '(if|switch).{0,120}(test|fixture|mock|env|node_env|pytest|vitest|jest).{0,120}(return\s+true|return\s+\[\]|ok\s*:\s*true|success\s*:\s*true)|return\s+\{?\s*(ok|success|pass)\s*:\s*true' },
    @{ category = 'validation_harness_touch'; pattern = '((bypass|disable|skip|remove|weaken|loosen|force).{0,80}(test[-_ /]?harness|validation[-_ /]?harness|eval[-_ /]?harness|evaluation[-_ /]?harness|score[-_ /]?gate|reward[-_ /]?reviewer)|(test[-_ /]?harness|validation[-_ /]?harness|eval[-_ /]?harness|evaluation[-_ /]?harness|score[-_ /]?gate|reward[-_ /]?reviewer).{0,80}(bypass|disable|skip|remove|weaken|loosen|force))' },
    @{ category = 'verification_bypass'; pattern = '(bypass|disable|skip|remove|weaken|loosen).*(test|verify|validation|gate|check|harness|completion)' },
    @{ category = 'completion_definition_tamper'; pattern = '(completion[-_ /]?definition|completion[-_ /]?criteria|pass[-_ /]?definition|test[-_ /]?definition).*(change|edit|set|force|loosen|weaken|bypass)' }
  )

  foreach ($item in $patterns) {
    if ($normalized -match $item.pattern) {
      return [ordered]@{ detected = $true; category = $item.category; pattern = $item.pattern }
    }
  }

  [ordered]@{ detected = $false; category = $null; pattern = $null }
}

function Test-RewardHackingCleanupText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  $normalized = ($Text.ToLowerInvariant().Replace('\', '/') -replace '/+', '/')
  if ($normalized -notmatch 'maintenance/reward-hacking-dummy') {
    return $false
  }

  $cleanupOperation = $normalized -match '(\*\*\* delete file:|remove-item\b|\brm\s+)'
  $writeOperation = $normalized -match '(\*\*\* add file:|\*\*\* update file:|set-content|add-content|out-file|new-item|writealltext|writealllines|appendalltext|appendalllines)'

  return ($cleanupOperation -and (-not $writeOperation))
}

function Test-RewardHackingSnapshot {
  param([object]$ActiveContract)

  $scope = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $ActiveContract -Name 'scope'))
  $findings = @()
  $seen = @{}
  $pathHintPattern = '(?i)(reward-hacking-dummy|validation[-_ /]?harness|test[-_ /]?harness|eval[-_ /]?harness|score[-_ /]?gate|reward[-_ /]?reviewer|completion[-_ /]?definition|completion[-_ /]?criteria)'
  $contentPatterns = @(
    '(?i)hardcoded[_ -]?success\s*=\s*true',
    '(?is)write-output\s+["'']?valid["'']?.{0,80}exit\s+0',
    '(?i)completion\s+is\s+valid\s+whenever.*hardcoded',
    '(?i)(skip|bypass|disable|weaken|loosen).{0,80}(validation|verify|check|harness|completion)',
    '(?i)(force[-_ ]?pass|always[-_ ]?pass|always[-_ ]?true|fake[-_ ]?(test|success|pass)|mock[-_ ]?pass|dummy[-_ ]?success)'
  )

  foreach ($rootCandidate in $scope) {
    if ([string]::IsNullOrWhiteSpace($rootCandidate) -or -not (Test-Path -LiteralPath $rootCandidate)) {
      continue
    }

    $rootPath = (Resolve-Path -LiteralPath $rootCandidate).Path
    $files = @()
    if (Test-Path -LiteralPath $rootPath -PathType Leaf) {
      $files = @(Get-Item -LiteralPath $rootPath -ErrorAction SilentlyContinue)
    } else {
      $files = @(Get-ChildItem -LiteralPath $rootPath -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $full = $_.FullName.Replace('\', '/')
        $full -notmatch '(?i)/Maintenance/upstream/' -and
        $full -notmatch '(?i)/Maintenance/hook_invocations\.jsonl$' -and
        $full -notmatch '(?i)/Settings/Codex_App_RUNTIME/(active_contract|completion_receipt)\.json$' -and
        $_.Length -le 1048576
      })
    }

    foreach ($file in $files) {
      $fullName = [string]$file.FullName
      $key = $fullName.ToLowerInvariant()
      if ($seen.ContainsKey($key)) {
        continue
      }
      $seen[$key] = $true

      $normalizedPath = $fullName.Replace('\', '/')
      if ($normalizedPath -notmatch $pathHintPattern) {
        continue
      }

      try {
        $text = [System.IO.File]::ReadAllText($fullName, $script:Utf8NoBom)
      } catch {
        continue
      }

      foreach ($pattern in $contentPatterns) {
        if ($text -match $pattern) {
          $findings += [ordered]@{
            path = $fullName
            pattern = $pattern
          }
          break
        }
      }
    }
  }

  if ($findings.Count -gt 0) {
    return [ordered]@{ detected = $true; findings = $findings }
  }

  [ordered]@{ detected = $false; findings = @() }
}

function New-UnicodeWord {
  param([int[]]$CodePoints)
  -join ($CodePoints | ForEach-Object { [string][char]$_ })
}

function Test-CurrentTaskAuthorizesControlPlane {
  param([object]$ActiveContract)

  $goal = [string]$ActiveContract.user_goal
  if ([string]::IsNullOrWhiteSpace($goal)) {
    return $false
  }

  $lower = $goal.ToLowerInvariant()
  $targetWords = @(
    'hook',
    (New-UnicodeWord @(0xD6C5)),
    'system',
    (New-UnicodeWord @(0xC2DC,0xC2A4,0xD15C)),
    'operating value',
    (New-UnicodeWord @(0xC6B4,0xC601,0xAC12)),
    'rule',
    (New-UnicodeWord @(0xB8F0)),
    'policy',
    (New-UnicodeWord @(0xC815,0xCC45)),
    'guard',
    'gate',
    'ssot',
    'control plane',
    'authority',
    (New-UnicodeWord @(0xAD8C,0xD55C)),
    (New-UnicodeWord @(0xBCF4,0xC548)),
    (New-UnicodeWord @(0xC2AC,0xB86D)),
    'block',
    (New-UnicodeWord @(0xCC28,0xB2E8)),
    (New-UnicodeWord @(0xBC94,0xC704)),
    (New-UnicodeWord @(0xAD6C,0xBD84)),
    (New-UnicodeWord @(0xC815,0xC0C1)),
    (New-UnicodeWord @(0xBE44,0xC815,0xC0C1)),
    'slop'
  )
  $actionWords = @(
    'patch',
    'fix',
    'change',
    'edit',
    'modify',
    'update',
    'apply',
    (New-UnicodeWord @(0xBCF4,0xAC15)),
    (New-UnicodeWord @(0xC218,0xC815)),
    (New-UnicodeWord @(0xD328,0xCE58)),
    (New-UnicodeWord @(0xC801,0xC6A9)),
    (New-UnicodeWord @(0xCD94,0xAC00)),
    (New-UnicodeWord @(0xAC15,0xD654)),
    (New-UnicodeWord @(0xC815,0xB9AC)),
    (New-UnicodeWord @(0xC791,0xC5C5)),
    (New-UnicodeWord @(0xC870,0xC815)),
    (New-UnicodeWord @(0xC124,0xC815)),
    (New-UnicodeWord @(0xAD6C,0xBD84))
  )

  $hasTarget = $false
  foreach ($word in $targetWords) {
    if ($lower.Contains($word)) {
      $hasTarget = $true
      break
    }
  }

  $hasAction = $false
  foreach ($word in $actionWords) {
    if ($lower.Contains($word)) {
      $hasAction = $true
      break
    }
  }

  return ($hasTarget -and $hasAction)
}

function Register-RewardSignalFilter {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$RewardSignal,
    [Parameter(Mandatory = $true)][string]$PayloadText,
    [object]$CompletionReceipt
  )

  if (-not $RewardSignal.detected) {
    return $CompletionReceipt
  }

  if (-not $CompletionReceipt) {
    $CompletionReceipt = [ordered]@{
      completion_state = 'candidate'
      oracle_matched = $false
      scope_matched = $false
      protected_surface_touched = $false
      blockers = @()
      evidence = @()
      raw_score_visible = $false
      rewardable = $false
    }
  }

  $payloadHash = Get-TextFingerprint -Text $PayloadText
  $blockers = @(Convert-ToStringArray -Value $CompletionReceipt.blockers)
  if ($blockers -notcontains 'reward_signal_counterexample_review_pending') {
    $blockers += 'reward_signal_counterexample_review_pending'
  }

  $evidence = @(Convert-ToStringArray -Value $CompletionReceipt.evidence)
  $evidence += "reward_signal_filtered:$($RewardSignal.category):$payloadHash"

  $CompletionReceipt | Add-Member -NotePropertyName completion_state -NotePropertyValue 'candidate' -Force
  $CompletionReceipt | Add-Member -NotePropertyName blockers -NotePropertyValue $blockers -Force
  $CompletionReceipt | Add-Member -NotePropertyName evidence -NotePropertyValue $evidence -Force
  $CompletionReceipt | Add-Member -NotePropertyName raw_score_visible -NotePropertyValue $false -Force
  $CompletionReceipt | Add-Member -NotePropertyName rewardable -NotePropertyValue $false -Force
  $CompletionReceipt | Add-Member -NotePropertyName reward_signal_filter -NotePropertyValue ([ordered]@{
    pending_counterexample_review = $true
    category = $RewardSignal.category
    command_fingerprint = $payloadHash
    rule = 'frequent_work_command_output_is_filtered_as_uncontrolled_reward_signal_until_counterexample_review'
  }) -Force

  Write-JsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/completion_receipt.json') -Value $CompletionReceipt
  $CompletionReceipt
}

function Register-ControlPlaneMutationReview {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][object]$ControlPlaneMutation,
    [Parameter(Mandatory = $true)][string]$PayloadText,
    [object]$RepairScope,
    [object]$CompletionReceipt
  )

  if (-not $ControlPlaneMutation.detected) {
    return $CompletionReceipt
  }

  if (-not $CompletionReceipt) {
    $CompletionReceipt = [ordered]@{
      completion_state = 'candidate'
      oracle_matched = $false
      scope_matched = $false
      protected_surface_touched = $false
      blockers = @()
      evidence = @()
      raw_score_visible = $false
      rewardable = $false
    }
  }

  $payloadHash = Get-TextFingerprint -Text $PayloadText
  $blockers = @(Convert-ToStringArray -Value $CompletionReceipt.blockers)
  if ($blockers -notcontains 'control_plane_mutation_review_pending') {
    $blockers += 'control_plane_mutation_review_pending'
  }

  $evidence = @(Convert-ToStringArray -Value $CompletionReceipt.evidence)
  $evidence += "control_plane_mutation_guarded:$($ControlPlaneMutation.category):$payloadHash"

  $CompletionReceipt | Add-Member -NotePropertyName completion_state -NotePropertyValue 'candidate' -Force
  $CompletionReceipt | Add-Member -NotePropertyName oracle_matched -NotePropertyValue $false -Force
  $CompletionReceipt | Add-Member -NotePropertyName scope_matched -NotePropertyValue $false -Force
  $CompletionReceipt | Add-Member -NotePropertyName protected_surface_touched -NotePropertyValue $true -Force
  $CompletionReceipt | Add-Member -NotePropertyName blockers -NotePropertyValue $blockers -Force
  $CompletionReceipt | Add-Member -NotePropertyName evidence -NotePropertyValue $evidence -Force
  $CompletionReceipt | Add-Member -NotePropertyName raw_score_visible -NotePropertyValue $false -Force
  $CompletionReceipt | Add-Member -NotePropertyName rewardable -NotePropertyValue $false -Force
  $review = [ordered]@{
    pending_review = $true
    category = $ControlPlaneMutation.category
    command_fingerprint = $payloadHash
    rule = 'control_plane_mutation_requires_current_task_scope_and_post_change_review'
  }
  if ($RepairScope) {
    $review.repair_scope = $RepairScope
  }

  $CompletionReceipt | Add-Member -NotePropertyName control_plane_change_review -NotePropertyValue $review -Force

  Write-JsonFile -Path (Join-Path $Root 'Settings/Codex_App_RUNTIME/completion_receipt.json') -Value $CompletionReceipt
  $CompletionReceipt
}

function Test-CommandGuard {
  param(
    [string]$Source,
    [string]$Surface,
    [bool]$Scoped,
    [string]$PayloadText,
    [string]$Workdir,
    [string]$Root,
    [object]$ActiveContract,
    [bool]$InspectOnly = $false
  )

  if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-CanonicalRoot
  }

  $rewardSignal = Get-RewardSignalCommand -Text $PayloadText
  $rewardSignalInspectOnly = $rewardSignal.detected -and ($InspectOnly -or ($PayloadText -match '(?i)(^|[^A-Za-z])-NoLog([^A-Za-z]|$)'))
  $controlPlaneMutation = Get-ControlPlaneMutation -Text $PayloadText -Workdir $Workdir
  $runtimeStateMutation = Get-RuntimeStateMutation -Text $PayloadText -Workdir $Workdir
  $rewardHackingTouch = Get-RewardHackingTouch -Text $PayloadText -Workdir $Workdir
  $rewardHackingCleanup = Test-RewardHackingCleanupText -Text $PayloadText
  $destructiveOperation = Test-DestructiveOperationText -Text $PayloadText
  $readOnlyInspection = Test-ReadOnlyInspectionText -Text $PayloadText
  $privateSurface = Test-PrivateSurfaceTouch -Text "$PayloadText`n$Workdir"
  $enforcementWeakening = Test-EnforcementWeakeningText -Text $PayloadText
  $benchmarkFixture = Test-AuthorizedBenchmarkFixtureText -Text $PayloadText -Workdir $Workdir -Root $Root -ActiveContract $ActiveContract
  $maintenanceValidationScript = Test-AuthorizedMaintenanceValidationScriptText -Text $PayloadText -Workdir $Workdir -Root $Root -ActiveContract $ActiveContract
  $controlPlaneAuthorized = $Scoped -or (Test-CurrentTaskAuthorizesControlPlane -ActiveContract $ActiveContract)
  $controlPlaneRepairScope = Test-ControlPlaneRepairScope -Text $PayloadText -Workdir $Workdir -Root $Root -ActiveContract $ActiveContract -ControlPlaneMutation $controlPlaneMutation
  $documentationSurface = Get-DocumentationSurface -Text "$PayloadText`n$Workdir"
  $negativeFixture = Test-NegativeReproductionFixtureText -Text $PayloadText -Workdir $Workdir -Root $Root -ActiveContract $ActiveContract
  $policyPattern = Test-PolicyContaminationPatternText -Text $PayloadText -Workdir $Workdir -Root $Root -ActiveContract $ActiveContract -ControlPlaneRepairScope $controlPlaneRepairScope
  $rewardHackingSuspectContext = Get-RewardHackingSuspectContext -RewardHacking $rewardHackingTouch -ReadOnlyInspection:$readOnlyInspection -DocumentationSurface $documentationSurface -ControlPlaneRepairScope $controlPlaneRepairScope -BenchmarkFixture $benchmarkFixture -NegativeFixture $negativeFixture -PolicyPattern $policyPattern
  $allowedSources = @(
    'user_explicit_instruction',
    'declared_config',
    'package_script',
    'repo_documented_workflow'
  )
  $protectedSurfaces = @(
    'user_home_global_config',
    '.codex',
    'codex_global_state',
    'agent_authority_files',
    'memory_files',
    'score_gate_reward_reviewer_policy',
    'credentials_tokens_secrets_auth_config',
    'environment_wide_settings',
    'Dev-Management',
    'Dev-Workflow',
    'global_control_plane',
    'other_repositories',
    'unrelated_workspaces',
    'global_package_or_tool_configuration'
  )

  $finalizationScope = Test-FinalizationScopeText -Text $PayloadText -Surface $Surface
  if ($benchmarkFixture.allowed) {
    $scopeCheck = Test-WithinActiveScope -Text $PayloadText -Workdir $Workdir -ActiveContract $ActiveContract
    if ($scopeCheck.ok) {
      if ($rewardHackingTouch.detected) {
        return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
      }
      return [ordered]@{ decision = 'ALLOW'; reason = 'current_task_scoped_contamination_benchmark_fixture'; classification = 'normal_authorized_benchmark_fixture'; benchmark = $benchmarkFixture }
    }
    return [ordered]@{ decision = 'BLOCKED'; reason = $scopeCheck.reason }
  }
  if ($privateSurface.detected) {
    return [ordered]@{ decision = 'BLOCKED'; reason = 'credential_or_secret_touch'; private_surface = $privateSurface }
  }

  $absoluteRewardManipulation = $rewardHackingTouch.detected -and
    ($PayloadText -match '(?i)(score[-_ ]?gate|evaluator|pass[-_ ]?fail|force[-_ ]?pass|always[-_ ]?pass|warning.*(hide|suppress|conceal)|exit[-_ ]?code.*(hide|suppress|conceal))')
  if ($absoluteRewardManipulation) {
    return [ordered]@{ decision = 'BLOCKED'; reason = 'reward_hacking_path_detected'; reward_hacking = $rewardHackingTouch }
  }

  if ($maintenanceValidationScript.allowed) {
    $scopeCheck = Test-WithinActiveScope -Text $PayloadText -Workdir $Workdir -ActiveContract $ActiveContract
    if ($scopeCheck.ok) {
      return [ordered]@{ decision = 'ALLOW'; reason = 'current_task_scoped_maintenance_validation_script_repair'; classification = 'normal_maintenance_validation_script_repair'; validation_script = $maintenanceValidationScript }
    }
    return [ordered]@{ decision = 'BLOCKED'; reason = $scopeCheck.reason }
  }

  if ($destructiveOperation.detected -and -not ($Scoped -or $Source -eq 'user_explicit_instruction' -or (($controlPlaneMutation.detected -or $runtimeStateMutation.detected) -and $controlPlaneAuthorized))) {
    return [ordered]@{ decision = 'BLOCKED'; reason = 'destructive_action_without_explicit_scope'; destructive_operation = $destructiveOperation }
  }

  if ($readOnlyInspection) {
    $scopeCheck = Test-WithinActiveScope -Text $PayloadText -Workdir $Workdir -ActiveContract $ActiveContract -Root $Root -AllowRuntimeReadOnlyReferences
    if ($scopeCheck.ok) {
      if ($rewardHackingTouch.detected) {
        return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
      }
      if ($rewardSignalInspectOnly) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_inspection_no_log'; reward_signal = $rewardSignal }
      }
      if ($rewardSignal.detected) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_command_filtered'; reward_signal = $rewardSignal }
      }
      if ([string](Get-OptionalPropertyValue -Object $scopeCheck -Name 'reason') -eq 'path_inside_active_scope_or_runtime_reference_read_only') {
        return [ordered]@{ decision = 'ALLOW'; reason = 'runtime_reference_read_only_inspection'; runtime_reference_scope = (Get-OptionalPropertyValue -Object $scopeCheck -Name 'runtime_reference_scope') }
      }
      return [ordered]@{ decision = 'ALLOW'; reason = 'current_task_scoped_read_only_inspection' }
    }
    return [ordered]@{ decision = 'BLOCKED'; reason = $scopeCheck.reason }
  }

  if ($benchmarkFixture.allowed) {
    $scopeCheck = Test-WithinActiveScope -Text $PayloadText -Workdir $Workdir -ActiveContract $ActiveContract
    if ($scopeCheck.ok) {
      if ($rewardHackingTouch.detected) {
        return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
      }
      return [ordered]@{ decision = 'ALLOW'; reason = 'current_task_scoped_contamination_benchmark_fixture'; classification = 'normal_authorized_benchmark_fixture'; benchmark = $benchmarkFixture }
    }
    return [ordered]@{ decision = 'BLOCKED'; reason = $scopeCheck.reason }
  }

  if ($enforcementWeakening.detected) {
    return [ordered]@{ decision = 'BLOCKED'; reason = 'enforcement_weakening_attempt'; weakening = $enforcementWeakening }
  }

  if ([string]::IsNullOrWhiteSpace($Source)) {
    if ($readOnlyInspection) {
      $scopeCheck = Test-WithinActiveScope -Text $PayloadText -Workdir $Workdir -ActiveContract $ActiveContract -Root $Root -AllowRuntimeReadOnlyReferences
      if ($scopeCheck.ok) {
        if ($rewardHackingTouch.detected) {
          return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
        }
        if ($rewardSignalInspectOnly) {
          return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_inspection_no_log'; reward_signal = $rewardSignal }
        }
        if ($rewardSignal.detected) {
          return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_command_filtered'; reward_signal = $rewardSignal }
        }
        if ([string](Get-OptionalPropertyValue -Object $scopeCheck -Name 'reason') -eq 'path_inside_active_scope_or_runtime_reference_read_only') {
          return [ordered]@{ decision = 'ALLOW'; reason = 'runtime_reference_read_only_inspection'; runtime_reference_scope = (Get-OptionalPropertyValue -Object $scopeCheck -Name 'runtime_reference_scope') }
        }
        return [ordered]@{ decision = 'ALLOW'; reason = 'current_task_scoped_read_only_inspection' }
      }
      return [ordered]@{ decision = 'BLOCKED'; reason = $scopeCheck.reason }
    }
    if ($runtimeStateMutation.detected -and $controlPlaneAuthorized) {
      return [ordered]@{ decision = 'ALLOW'; reason = 'runtime_state_update_current_task_scoped'; classification = 'normal_runtime_state_update'; runtime_state = $runtimeStateMutation }
    }
    if ($controlPlaneMutation.detected -and $controlPlaneRepairScope.allowed) {
      if ($rewardHackingTouch.detected) {
        return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
      }
      return [ordered]@{ decision = 'ALLOW'; reason = 'control_plane_mutation_current_task_scoped'; classification = 'normal_authorized_control_plane_repair'; control_plane = $controlPlaneMutation; repair_scope = $controlPlaneRepairScope.repair_scope }
    }
    if ($rewardHackingTouch.detected -and (Get-OptionalPropertyValue -Object $documentationSurface -Name 'runtime_relevant') -eq $false) {
      $docScopeCheck = Test-WithinActiveScope -Text $PayloadText -Workdir $Workdir -ActiveContract $ActiveContract
      if ($docScopeCheck.ok) {
        return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
      }
      return [ordered]@{ decision = 'BLOCKED'; reason = $docScopeCheck.reason }
    }
    if ($rewardHackingTouch.detected -and (Get-OptionalPropertyValue -Object $rewardHackingSuspectContext -Name 'suspect') -eq $true -and (-not $rewardHackingCleanup)) {
      return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
    }
    if ($rewardHackingTouch.detected -and (-not $rewardHackingCleanup)) {
      return [ordered]@{ decision = 'BLOCKED'; reason = 'reward_hacking_path_detected'; reward_hacking = $rewardHackingTouch }
    }
    if ($runtimeStateMutation.detected -and $controlPlaneAuthorized) {
      return [ordered]@{ decision = 'ALLOW'; reason = 'runtime_state_update_current_task_scoped'; classification = 'normal_runtime_state_update'; runtime_state = $runtimeStateMutation }
    }
    if ($controlPlaneMutation.detected -and $controlPlaneRepairScope.allowed) {
      return [ordered]@{ decision = 'ALLOW'; reason = 'control_plane_mutation_current_task_scoped'; classification = 'normal_authorized_control_plane_repair'; control_plane = $controlPlaneMutation; repair_scope = $controlPlaneRepairScope.repair_scope }
    }
    $scopeCheck = Test-WithinActiveScope -Text $PayloadText -Workdir $Workdir -ActiveContract $ActiveContract
    if ($scopeCheck.ok) {
      if ($rewardHackingCleanup) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'reward_hacking_contamination_cleanup_current_task_scoped'; classification = 'normal_contamination_cleanup' }
      }
      if ($runtimeStateMutation.detected) {
        if (-not $controlPlaneAuthorized) {
          return [ordered]@{ decision = 'BLOCKED'; reason = 'control_plane_mutation_without_current_task_scope'; runtime_state = $runtimeStateMutation }
        }
        return [ordered]@{ decision = 'ALLOW'; reason = 'runtime_state_update_current_task_scoped'; classification = 'normal_runtime_state_update'; runtime_state = $runtimeStateMutation }
      }
      if ($controlPlaneMutation.detected) {
        if (-not $controlPlaneRepairScope.allowed) {
          return [ordered]@{ decision = 'BLOCKED'; reason = $controlPlaneRepairScope.reason; control_plane = $controlPlaneMutation; repair_scope = $controlPlaneRepairScope }
        }
        if ($rewardHackingTouch.detected) {
          return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
        }
        return [ordered]@{ decision = 'ALLOW'; reason = 'control_plane_mutation_current_task_scoped'; classification = 'normal_authorized_control_plane_repair'; control_plane = $controlPlaneMutation; repair_scope = $controlPlaneRepairScope.repair_scope }
      }
      if ($rewardSignalInspectOnly) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_inspection_no_log'; reward_signal = $rewardSignal }
      }
      if ($rewardSignal.detected) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_command_filtered'; reward_signal = $rewardSignal }
      }
      if (-not $finalizationScope) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'normal_non_finalization_work' }
      }
      return [ordered]@{ decision = 'ALLOW'; reason = 'current_task_active_scope' }
    }
    return [ordered]@{ decision = 'BLOCKED'; reason = $scopeCheck.reason }
  }

  if ($controlPlaneMutation.detected -and $controlPlaneRepairScope.allowed) {
    if ($rewardHackingTouch.detected) {
      return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
    }
    return [ordered]@{ decision = 'ALLOW'; reason = 'control_plane_mutation_current_task_scoped'; classification = 'normal_authorized_control_plane_repair'; control_plane = $controlPlaneMutation; repair_scope = $controlPlaneRepairScope.repair_scope }
  }

  if ($rewardHackingTouch.detected -and (Get-OptionalPropertyValue -Object $documentationSurface -Name 'runtime_relevant') -eq $false) {
    $docScopeCheck = Test-WithinActiveScope -Text $PayloadText -Workdir $Workdir -ActiveContract $ActiveContract
    if ($docScopeCheck.ok) {
      return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
    }
    return [ordered]@{ decision = 'BLOCKED'; reason = $docScopeCheck.reason }
  }

  if ($rewardHackingTouch.detected -and (Get-OptionalPropertyValue -Object $rewardHackingSuspectContext -Name 'suspect') -eq $true -and (-not $rewardHackingCleanup)) {
    return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
  }

  if ($rewardHackingTouch.detected -and (-not $rewardHackingCleanup)) {
    return [ordered]@{ decision = 'BLOCKED'; reason = 'reward_hacking_path_detected'; reward_hacking = $rewardHackingTouch }
  }
  if ($allowedSources -notcontains $Source) {
    return [ordered]@{ decision = 'BLOCKED'; reason = 'command_source_not_allowed' }
  }

  if (($protectedSurfaces -contains $Surface) -and (-not $Scoped)) {
    $scopeCheck = Test-WithinActiveScope -Text $PayloadText -Workdir $Workdir -ActiveContract $ActiveContract
    if ($scopeCheck.ok) {
      if ($rewardHackingCleanup) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'reward_hacking_contamination_cleanup_current_task_scoped'; classification = 'normal_contamination_cleanup' }
      }
      if ($runtimeStateMutation.detected) {
        if (-not $controlPlaneAuthorized) {
          return [ordered]@{ decision = 'BLOCKED'; reason = 'control_plane_mutation_without_current_task_scope'; runtime_state = $runtimeStateMutation }
        }
        return [ordered]@{ decision = 'ALLOW'; reason = 'runtime_state_update_current_task_scoped'; classification = 'normal_runtime_state_update'; runtime_state = $runtimeStateMutation }
      }
      if ($controlPlaneMutation.detected) {
        if (-not $controlPlaneRepairScope.allowed) {
          return [ordered]@{ decision = 'BLOCKED'; reason = $controlPlaneRepairScope.reason; control_plane = $controlPlaneMutation; repair_scope = $controlPlaneRepairScope }
        }
        if ($rewardHackingTouch.detected) {
          return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
        }
        return [ordered]@{ decision = 'ALLOW'; reason = 'control_plane_mutation_current_task_scoped'; classification = 'normal_authorized_control_plane_repair'; control_plane = $controlPlaneMutation; repair_scope = $controlPlaneRepairScope.repair_scope }
      }
      if ($rewardSignalInspectOnly) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_inspection_no_log'; reward_signal = $rewardSignal }
      }
      if ($rewardSignal.detected) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_command_filtered'; reward_signal = $rewardSignal }
      }
      if (-not $finalizationScope) {
        return [ordered]@{ decision = 'ALLOW'; reason = 'protected_surface_non_finalization_inside_scope' }
      }
      return [ordered]@{ decision = 'ALLOW'; reason = 'protected_surface_inside_current_task_scope' }
    }
    return [ordered]@{ decision = 'BLOCKED'; reason = 'protected_surface_without_explicit_scope' }
  }

  if ($runtimeStateMutation.detected) {
    if (-not $controlPlaneAuthorized) {
      return [ordered]@{ decision = 'BLOCKED'; reason = 'control_plane_mutation_without_current_task_scope'; runtime_state = $runtimeStateMutation }
    }
    return [ordered]@{ decision = 'ALLOW'; reason = 'runtime_state_update_current_task_scoped'; classification = 'normal_runtime_state_update'; runtime_state = $runtimeStateMutation }
  }

  if ($controlPlaneMutation.detected) {
    if (-not $controlPlaneRepairScope.allowed) {
      return [ordered]@{ decision = 'BLOCKED'; reason = $controlPlaneRepairScope.reason; control_plane = $controlPlaneMutation; repair_scope = $controlPlaneRepairScope }
    }
    if ($rewardHackingTouch.detected) {
      return New-RewardHackingSuspectDecision -Root $Root -ActiveContract $ActiveContract -RewardHacking $rewardHackingTouch -SuspectContext $rewardHackingSuspectContext -PayloadText $PayloadText -Workdir $Workdir -NoLog:$InspectOnly
    }
    return [ordered]@{ decision = 'ALLOW'; reason = 'control_plane_mutation_current_task_scoped'; classification = 'normal_authorized_control_plane_repair'; control_plane = $controlPlaneMutation; repair_scope = $controlPlaneRepairScope.repair_scope }
  }

  if ($rewardSignalInspectOnly) {
    return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_inspection_no_log'; reward_signal = $rewardSignal }
  }

  if ($rewardSignal.detected) {
    return [ordered]@{ decision = 'ALLOW'; reason = 'reward_signal_command_filtered'; reward_signal = $rewardSignal }
  }

  if (-not $finalizationScope) {
    return [ordered]@{ decision = 'ALLOW'; reason = 'declared_source_non_finalization_action' }
  }

  [ordered]@{ decision = 'ALLOW'; reason = 'declared_source_and_scope_ok' }
}

function Test-RetryInvalidation {
  param([string]$Text)
  $triggers = @(
    (New-UnicodeWord @(0xB2E4,0xC2DC)),
    (New-UnicodeWord @(0xD2C0,0xB838,0xC5B4)),
    (New-UnicodeWord @(0xC624,0xB2F5)),
    (New-UnicodeWord @(0xC544,0xB2D8)),
    'again',
    'retry',
    'wrong',
    (New-UnicodeWord @(0xC218,0xC815)),
    (New-UnicodeWord @(0xC218,0xC815,0xC791,0xC5C5))
  )
  foreach ($trigger in $triggers) {
    if ($Text -like "*$trigger*") {
      return [ordered]@{ decision = 'INVALIDATE_PREVIOUS'; trigger = $trigger }
    }
  }
  [ordered]@{ decision = 'NO_RETRY_TRIGGER'; trigger = $null }
}

function Test-DynamicReproductionCheck {
  param([object]$CompletionReceipt)

  $check = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'dynamic_reproduction_check'
  if (-not $check) {
    return [ordered]@{ ok = $false; reason = 'dynamic_reproduction_check_missing' }
  }

  if ((Get-OptionalPropertyValue -Object $check -Name 'passed') -ne $true -or [string](Get-OptionalPropertyValue -Object $check -Name 'mode') -ne 'dynamic_input_processing_output') {
    return [ordered]@{ ok = $false; reason = 'dynamic_reproduction_failed' }
  }

  $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $check -Name 'evidence'))
  $paths = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $check -Name 'paths'))
  if ($evidence.Count -eq 0 -or $paths.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'dynamic_reproduction_evidence_missing' }
  }

  [ordered]@{ ok = $true; reason = 'dynamic_reproduction_verified' }
}

function Test-DependencyAlignmentCheck {
  param([object]$CompletionReceipt)

  $check = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'dependency_alignment_check'
  if (-not $check) {
    return [ordered]@{ ok = $false; reason = 'dependency_alignment_check_missing' }
  }

  if ((Get-OptionalPropertyValue -Object $check -Name 'passed') -ne $true) {
    return [ordered]@{ ok = $false; reason = 'dependency_alignment_failed' }
  }

  $changedPaths = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $check -Name 'changed_paths'))
  $connectedPaths = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $check -Name 'checked_connected_paths'))
  $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $check -Name 'evidence'))
  if ($changedPaths.Count -eq 0 -or $connectedPaths.Count -eq 0 -or $evidence.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'dependency_alignment_evidence_missing' }
  }

  [ordered]@{ ok = $true; reason = 'dependency_alignment_verified' }
}

function Get-ArtifactHashRecord {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }

  $item = Get-Item -LiteralPath $Path
  [ordered]@{
    path = $item.FullName
    sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    last_write_utc = $item.LastWriteTimeUtc.ToString('o')
  }
}

function Get-FreshnessHashForPath {
  param(
    [object]$ArtifactHashes,
    [string]$Path
  )

  $target = (Convert-ToGuardPathText -Text $Path).TrimEnd('/')
  foreach ($record in @($ArtifactHashes)) {
    $recordPath = [string](Get-OptionalPropertyValue -Object $record -Name 'path')
    if ([string]::IsNullOrWhiteSpace($recordPath)) {
      continue
    }
    if ((Convert-ToGuardPathText -Text $recordPath).TrimEnd('/') -eq $target) {
      return [string](Get-OptionalPropertyValue -Object $record -Name 'sha256')
    }
  }

  return ''
}

function Test-CompletionReceiptFreshness {
  param(
    [string]$Root,
    [object]$ActiveContract,
    [object]$CompletionReceipt
  )

  $freshness = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'freshness'
  if (-not $freshness) {
    return [ordered]@{ ok = $false; reason = 'completion_receipt_freshness_missing' }
  }

  $activeTurnFingerprint = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $attemptId = [string](Get-OptionalPropertyValue -Object $freshness -Name 'attempt_id')
  if (-not [string]::IsNullOrWhiteSpace($activeTurnFingerprint) -and $attemptId -ne $activeTurnFingerprint) {
    return [ordered]@{ ok = $false; reason = 'stale_completion_receipt' }
  }

  $affectedPaths = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $freshness -Name 'affected_paths'))
  if ($affectedPaths.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'completion_receipt_freshness_missing' }
  }

  $validationTimestampValue = Get-OptionalPropertyValue -Object $freshness -Name 'validation_timestamp_utc'
  if ($null -eq $validationTimestampValue) {
    return [ordered]@{ ok = $false; reason = 'completion_receipt_freshness_missing' }
  }

  try {
    if ($validationTimestampValue -is [DateTime]) {
      $validationTimestamp = $validationTimestampValue.ToUniversalTime()
      $validationTimestampText = $validationTimestamp.ToString('o')
    } else {
      $validationTimestampText = [string]$validationTimestampValue
      if ([string]::IsNullOrWhiteSpace($validationTimestampText)) {
        return [ordered]@{ ok = $false; reason = 'completion_receipt_freshness_missing' }
      }
      $validationTimestamp = [DateTime]::Parse($validationTimestampText).ToUniversalTime()
    }
  } catch {
    return [ordered]@{ ok = $false; reason = 'completion_receipt_freshness_missing' }
  }

  $nowUtc = (Get-Date).ToUniversalTime()
  $allowedClockSkewSeconds = Get-AllowedClockSkewSeconds
  if ($validationTimestamp -gt $nowUtc.AddSeconds($allowedClockSkewSeconds)) {
    return [ordered]@{
      ok = $false
      reason = 'future_dated_validation_timestamp'
      validation_timestamp_utc = $validationTimestampText
      now_utc = $nowUtc.ToString('o')
      allowed_clock_skew_seconds = $allowedClockSkewSeconds
    }
  }

  $artifactHashes = @(Get-OptionalPropertyValue -Object $freshness -Name 'artifact_hashes')
  if ($artifactHashes.Count -eq 0) {
    return [ordered]@{ ok = $false; reason = 'completion_receipt_freshness_missing' }
  }

  foreach ($path in $affectedPaths) {
    $resolvedPath = [string]$path
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
      return [ordered]@{ ok = $false; reason = 'completion_receipt_artifact_stale'; path = $path }
    }

    $item = Get-Item -LiteralPath $resolvedPath
    if ($validationTimestamp -lt $item.LastWriteTimeUtc) {
      return [ordered]@{ ok = $false; reason = 'completion_receipt_validation_before_latest_write'; path = $item.FullName }
    }

    $expectedHash = Get-FreshnessHashForPath -ArtifactHashes $artifactHashes -Path $item.FullName
    if ([string]::IsNullOrWhiteSpace($expectedHash)) {
      return [ordered]@{ ok = $false; reason = 'completion_receipt_freshness_missing'; path = $item.FullName }
    }

    $actualHash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash.ToLowerInvariant()) {
      return [ordered]@{ ok = $false; reason = 'completion_receipt_artifact_stale'; path = $item.FullName }
    }
  }

  [ordered]@{ ok = $true; reason = 'completion_receipt_fresh'; allowed_clock_skew_seconds = $allowedClockSkewSeconds }
}

function Test-CompletionClaimText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  $lower = $Text.ToLowerInvariant()
  $nonCompletionSignals = @(
    'not complete',
    'not completed',
    'candidate',
    'blocked',
    'blocker',
    'waiting',
    'blocker',
    (New-UnicodeWord @(0xB300,0xAE30)),
    (New-UnicodeWord @(0xCC28,0xB2E8)),
    (New-UnicodeWord @(0xD6C4,0xBCF4)),
    ((New-UnicodeWord @(0xC644,0xB8CC)) + (New-UnicodeWord @(0xAC00)) + ' ' + (New-UnicodeWord @(0xC544,0xB2D8))),
    ((New-UnicodeWord @(0xC644,0xB8CC)) + ' ' + (New-UnicodeWord @(0xC544,0xB2D8))),
    ((New-UnicodeWord @(0xC644,0xB8CC)) + ' ' + (New-UnicodeWord @(0xC0C1,0xD0DC)) + (New-UnicodeWord @(0xAC00)) + ' ' + (New-UnicodeWord @(0xC544,0xB2D9)) + (New-UnicodeWord @(0xB2C8,0xB2E4))),
    ((New-UnicodeWord @(0xC644,0xB8CC)) + ' ' + (New-UnicodeWord @(0xC120,0xC5B8)) + (New-UnicodeWord @(0xC740)) + ' ' + (New-UnicodeWord @(0xD558,0xC9C0)) + ' ' + (New-UnicodeWord @(0xC54A)) + (New-UnicodeWord @(0xC2B5,0xB2C8,0xB2E4))),
    ((New-UnicodeWord @(0xC644,0xB8CC)) + (New-UnicodeWord @(0xB97C)) + ' ' + (New-UnicodeWord @(0xC8FC,0xC7A5)) + (New-UnicodeWord @(0xD558,0xC9C0)) + ' ' + (New-UnicodeWord @(0xC54A))),
    ((New-UnicodeWord @(0xC644,0xB8CC)) + ' ' + (New-UnicodeWord @(0xC8FC,0xC7A5)) + ' ' + (New-UnicodeWord @(0xC544,0xB2D8))),
    ((New-UnicodeWord @(0xC218,0xC815)) + (New-UnicodeWord @(0xD558,0xC9C0))),
    ((New-UnicodeWord @(0xC9C4,0xD589)) + (New-UnicodeWord @(0xD558,0xC9C0))),
    ((New-UnicodeWord @(0xC791,0xC5C5)) + (New-UnicodeWord @(0xD558,0xC9C0)))
  )

  foreach ($signal in $nonCompletionSignals) {
    if ($lower.Contains($signal)) {
      return $false
    }
  }

  $completionPatterns = @(
    '\bverified_complete\b',
    '\bcomplete(d)?\b',
    '\bdone\b',
    '\bfixed\b',
    '\bimplemented\b',
    '\bapplied\b',
    '\bresolved\b',
    (New-UnicodeWord @(0xC644,0xB8CC)),
    ((New-UnicodeWord @(0xC218,0xC815)) + (New-UnicodeWord @(0xD588,0xC2B5)) + (New-UnicodeWord @(0xB2C8,0xB2E4))),
    ((New-UnicodeWord @(0xACE0,0xCCE4)) + (New-UnicodeWord @(0xC2B5,0xB2C8,0xB2E4))),
    ((New-UnicodeWord @(0xC801,0xC6A9)) + (New-UnicodeWord @(0xD588,0xC2B5)) + (New-UnicodeWord @(0xB2C8,0xB2E4))),
    ((New-UnicodeWord @(0xAD6C,0xD604)) + (New-UnicodeWord @(0xD588,0xC2B5)) + (New-UnicodeWord @(0xB2C8,0xB2E4))),
    ((New-UnicodeWord @(0xD574,0xACB0)) + (New-UnicodeWord @(0xD588,0xC2B5)) + (New-UnicodeWord @(0xB2C8,0xB2E4))),
    (New-UnicodeWord @(0xB9C8,0xBB34,0xB9AC))
  )

  foreach ($pattern in $completionPatterns) {
    if ($lower -match $pattern) {
      return $true
    }
  }

  return $false
}

function Test-FinalizationEvidenceText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $false
  }

  $lower = $Text.ToLowerInvariant()
  $hasPath = ($Text -match '(?im)\bpaths?\s*:') -or
    ($Text -match '[A-Za-z]:(?:\\|/)') -or
    ($lower -match '(^|[^a-z0-9_.-])(settings|maintenance|src|tests?)/')
  $hasSpecRelation = ($lower -match '(?im)\bspec relation\s*:') -or
    ($lower -match '(?im)\bspecification\s*:') -or
    ($lower -match '(?im)\brequirements?\s*:') -or
    ($lower -match '(?im)\boracle\s*:') -or
    ($lower -match 'dynamic input')
  $hasChecks = ($lower -match '(?im)\bchecks?\s*:') -or
    ($lower -match '(?im)\bvalidation\s*:') -or
    ($lower -match '(?im)\bevidence\s*:') -or
    ($lower -match 'ran ') -or
    ($lower -match 'returned ')
  $hasWarnings = ($lower -match '(?im)\bwarnings?/limits?\s*:') -or
    ($lower -match '(?im)\blimits?\s*:') -or
    ($lower -match '(?im)\bwarnings?\s*:') -or
    ($lower -match 'not run') -or
    ($lower -match 'none')

  $hasPath -and $hasSpecRelation -and $hasChecks -and $hasWarnings
}

function Test-CompletionGate {
  param(
    [string]$State,
    [string]$Root,
    [object]$ActiveContract,
    [object]$CompletionReceipt,
    [bool]$NoLog = $false
  )

  if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Get-CanonicalRoot
  }

  $requestedState = $State
  if ([string]::IsNullOrWhiteSpace($requestedState) -and $CompletionReceipt) {
    $requestedState = [string](Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'completion_state')
  }

  $activeState = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'state')
  $activeTurnFingerprint = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'turn_fingerprint')
  $scope = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $ActiveContract -Name 'scope'))
  $userGoal = [string](Get-OptionalPropertyValue -Object $ActiveContract -Name 'user_goal')
  if ($scope.Count -eq 0 -or [string]::IsNullOrWhiteSpace($userGoal)) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'active_scope_missing' }
  }

  $rewardHackingSnapshot = Test-RewardHackingSnapshot -ActiveContract $ActiveContract
  if ($rewardHackingSnapshot.detected) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'reward_hacking_snapshot_detected'; reward_hacking_snapshot = $rewardHackingSnapshot }
  }

  if ([string]::IsNullOrWhiteSpace($requestedState)) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'completion_state_missing' }
  }

  if ($requestedState -ne 'verified_complete') {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = "state_$requestedState" }
  }

  if ($activeState -ne 'verified_complete') {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = "state_$activeState" }
  }

  if (-not $CompletionReceipt) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'completion_receipt_missing' }
  }

  $receiptState = [string](Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'completion_state')
  if ($receiptState -ne 'verified_complete') {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = "state_$receiptState" }
  }

  $currentBlockers = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'blockers'))
  if ($currentBlockers.Count -gt 0) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'state_blockers' }
  }

  if ((Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'oracle_matched') -ne $true) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'oracle_not_matched' }
  }

  if ((Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'scope_matched') -ne $true) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'scope_not_matched' }
  }

  $controlPlaneReview = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'control_plane_change_review'
  if ($controlPlaneReview -and (Get-OptionalPropertyValue -Object $controlPlaneReview -Name 'pending_review') -eq $true) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'control_plane_mutation_review_missing' }
  }

  if ((Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'protected_surface_touched') -eq $true) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'protected_surface_touched' }
  }

  $rewardSignalFilter = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'reward_signal_filter'
  if ($rewardSignalFilter -and (Get-OptionalPropertyValue -Object $rewardSignalFilter -Name 'pending_counterexample_review') -eq $true) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'reward_signal_counterexample_review_missing' }
  }

  if (-not [string]::IsNullOrWhiteSpace($activeTurnFingerprint)) {
    if ([string](Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'turn_fingerprint') -ne $activeTurnFingerprint) {
      return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'stale_completion_receipt' }
    }
  }

  $freshnessCheck = Test-CompletionReceiptFreshness -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt
  if (-not $freshnessCheck.ok) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = $freshnessCheck.reason; freshness = $freshnessCheck }
  }

  $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'evidence'))
  if ($evidence.Count -eq 0) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'direct_evidence_missing' }
  }

  $dynamicReproduction = Test-DynamicReproductionCheck -CompletionReceipt $CompletionReceipt
  if (-not $dynamicReproduction.ok) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = $dynamicReproduction.reason }
  }

  $dependencyAlignment = Test-DependencyAlignmentCheck -CompletionReceipt $CompletionReceipt
  if (-not $dependencyAlignment.ok) {
    return [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = $dependencyAlignment.reason }
  }

  $taskNeedResolution = Test-TaskClassificationAndNeedForCompletion -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt
  if (-not $taskNeedResolution.ok) {
    return [ordered]@{
      decision = 'DO_NOT_CLAIM_COMPLETE'
      reason = $taskNeedResolution.reason
      task_need_resolution = $taskNeedResolution
    }
  }

  $pmAccountability = Test-PmAccountabilityForCompletion -NeedCheck $taskNeedResolution -CompletionReceipt $CompletionReceipt
  if (-not $pmAccountability.ok) {
    return [ordered]@{
      decision = 'DO_NOT_CLAIM_COMPLETE'
      reason = $pmAccountability.reason
      task_need_resolution = $taskNeedResolution
      pm_accountability = $pmAccountability
    }
  }

  $requiredToolRoutes = Test-RequiredToolRoutesForCompletion -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt -NoLog:$NoLog
  if (-not $requiredToolRoutes.ok) {
    return [ordered]@{
      decision = 'DO_NOT_CLAIM_COMPLETE'
      reason = $requiredToolRoutes.reason
      required_tool_routes = $requiredToolRoutes
      loop_breaker = [bool](Get-OptionalPropertyValue -Object $requiredToolRoutes -Name 'loop_breaker')
    }
  }

  $subagentInspection = Test-SubagentInspectionForCompletion -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt -NoLog:$NoLog
  if (-not $subagentInspection.ok) {
    if ([bool](Get-OptionalPropertyValue -Object $subagentInspection -Name 'loop_breaker')) {
      return [ordered]@{
        decision = 'STOP_AND_REPORT'
        reason = $subagentInspection.reason
        subagent_inspections = $subagentInspection
        loop_breaker = $true
      }
    }
    return [ordered]@{
      decision = 'DO_NOT_CLAIM_COMPLETE'
      reason = $subagentInspection.reason
      subagent_inspections = $subagentInspection
      loop_breaker = [bool](Get-OptionalPropertyValue -Object $subagentInspection -Name 'loop_breaker')
    }
  }

  $heuristicReviews = Test-HeuristicReviewsForCompletion -Root $Root -ActiveContract $ActiveContract
  if (-not $heuristicReviews.ok) {
    return [ordered]@{
      decision = 'DO_NOT_CLAIM_COMPLETE'
      reason = $heuristicReviews.reason
      heuristic_reviews = $heuristicReviews
    }
  }

  $repoV2Adoption = Test-RepoV2AdoptionForCompletion -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt
  if (-not $repoV2Adoption.ok) {
    return [ordered]@{
      decision = 'DO_NOT_CLAIM_COMPLETE'
      reason = $repoV2Adoption.reason
      repo_v2_adoption = $repoV2Adoption
    }
  }

  $gateIssuedReceipt = Write-GateIssuedCompletionReceipt -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt -TaskNeedResolution $taskNeedResolution -PmAccountability $pmAccountability -RequiredToolRoutes $requiredToolRoutes -SubagentInspections $subagentInspection -HeuristicReviews $heuristicReviews -RepoV2Adoption $repoV2Adoption -FreshnessCheck $freshnessCheck -NoLog:$NoLog
  $gateIssuedCheck = if ($NoLog) {
    [ordered]@{
      ok = $true
      reason = 'gate_issued_completion_receipt_would_be_issued'
      receipt = $gateIssuedReceipt
    }
  } else {
    Test-GateIssuedReceiptCurrent -Root $Root -ActiveContract $ActiveContract -CompletionReceipt $CompletionReceipt
  }
  if (-not $gateIssuedCheck.ok) {
    return [ordered]@{
      decision = 'DO_NOT_CLAIM_COMPLETE'
      reason = $gateIssuedCheck.reason
      gate_issued_completion_receipt = $gateIssuedCheck
    }
  }

  if ($State -eq 'verified_complete') {
    return [ordered]@{ decision = 'ALLOW_COMPLETE_CLAIM'; reason = 'verified_complete'; gate_issued_completion_receipt = $gateIssuedReceipt }
  }

  [ordered]@{ decision = 'ALLOW_COMPLETE_CLAIM'; reason = 'receipt_verified_complete'; gate_issued_completion_receipt = $gateIssuedReceipt }
}

function Get-HookFailPolicy {
  param([Parameter(Mandatory = $true)][string]$HookName)

  switch ($HookName) {
    'pre_turn_active_contract' { 'BLOCKED_IF_ACTIVE_CONTRACT_REQUIRED_BUT_MISSING' }
    'pre_command_guard' { 'BLOCKED' }
    'pre_response_checklist' { 'DO_NOT_CLAIM_COMPLETE' }
    'retry_invalidation' { 'NO_OUTPUT_IF_SAME_LOGIC_REPEATS' }
    'completion_gate' { 'CANDIDATE_OR_BLOCKED_NOT_COMPLETE' }
    'post_turn_state_register' { 'STATE_WRITE_REQUIRED_FOR_MULTI_TURN_TASKS' }
    'stop_checks' { 'CANDIDATE_OR_BLOCKED_NOT_COMPLETE' }
    'post_tool_use' { 'OBSERVATION_ONLY' }
    default { 'HOOK_CONTEXT_REQUIRED' }
  }
}

function Get-BlockerDefinitions {
  @(
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.STATE_MISSING'
      reason_code = 'completion_state_missing'
      user_facing_blocker = 'completion_state_missing'
      why = 'The completion gate did not receive a completion state, so it cannot distinguish candidate work from verified completion.'
      safe_next_action = 'Classify the outcome explicitly as candidate, blockers, or verified_complete before making a completion claim.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.STATE_BLOCKERS'
      reason_code = 'state_blockers'
      user_facing_blocker = 'state_blockers'
      why = 'The current completion state is blockers; unresolved blockers remain and completion cannot be claimed.'
      safe_next_action = 'Resolve or explicitly preserve each listed blocker, update the runtime receipt, then rerun with verified_complete only when no blocker remains.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.STATE_CANDIDATE'
      reason_code = 'state_candidate'
      user_facing_blocker = 'state_candidate'
      why = 'The current completion state is only candidate; candidate is evidence, not completion.'
      safe_next_action = 'Validate the candidate against the oracle, scope, protected-surface rules, and direct evidence before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.STATE_NOT_VERIFIED'
      reason_pattern = '^state_(.+)$'
      reason_code = 'state_*'
      user_facing_blocker = '$reason'
      why = 'The current completion state is ''$state'', which is not verified_complete.'
      safe_next_action = 'Move the work to verified_complete only after scope, oracle, evidence, and blocker checks pass.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.RECEIPT_MISSING'
      reason_code = 'completion_receipt_missing'
      user_facing_blocker = 'completion_receipt_missing'
      why = 'No completion receipt is available, so the hook cannot verify oracle, scope, blockers, or evidence.'
      safe_next_action = 'Write a completion receipt with verified oracle, scope, blocker, and evidence fields before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.ORACLE_NOT_MATCHED'
      reason_code = 'oracle_not_matched'
      user_facing_blocker = 'oracle_not_matched'
      why = 'The completion receipt does not confirm that the work matches the active user oracle.'
      safe_next_action = 'Compare the result against the active user goal and update the receipt only after the oracle is matched.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.SCOPE_NOT_MATCHED'
      reason_code = 'scope_not_matched'
      user_facing_blocker = 'scope_not_matched'
      why = 'The completion receipt does not confirm that the work stayed inside active scope.'
      safe_next_action = 'Check touched paths and protected surfaces, then update the receipt only after scope is matched.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.SCOPE.PROTECTED_SURFACE_TOUCHED'
      reason_code = 'protected_surface_touched'
      user_facing_blocker = 'protected_surface_touched'
      why = 'The completion receipt says a protected surface was touched, so completion requires explicit scope and no unresolved blocker.'
      safe_next_action = 'Resolve the protected-surface concern or keep the task blocked with a failed-state report.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.DIRECT_EVIDENCE_MISSING'
      reason_code = 'direct_evidence_missing'
      user_facing_blocker = 'direct_evidence_missing'
      why = 'The completion receipt has no direct evidence entries for the touched path.'
      safe_next_action = 'Run or record the smallest direct evidence check that covers the touched behavior.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.DYNAMIC_REPRODUCTION_CHECK_MISSING'
      reason_code = 'dynamic_reproduction_check_missing'
      user_facing_blocker = 'dynamic_reproduction_check_missing'
      why = 'The completion receipt has no dynamic reproduction check, so it does not prove dynamic input, processing, and output were reproduced.'
      safe_next_action = 'Rework the normal logic path, run a dynamic input-processing-output reproduction check, and record it in the completion receipt.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.DYNAMIC_REPRODUCTION_FAILED'
      reason_code = 'dynamic_reproduction_failed'
      user_facing_blocker = 'dynamic_reproduction_failed'
      why = 'The dynamic reproduction check did not pass with mode dynamic_input_processing_output.'
      safe_next_action = 'Fix the normal logic path, rerun the dynamic reproduction check with dynamic input through processing to output, and only then claim completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.DYNAMIC_REPRODUCTION_EVIDENCE_MISSING'
      reason_code = 'dynamic_reproduction_evidence_missing'
      user_facing_blocker = 'dynamic_reproduction_evidence_missing'
      why = 'The dynamic reproduction check does not include both evidence and related paths.'
      safe_next_action = 'Record the reproduction evidence and the relevant paths in the completion receipt after rerunning the normal logic path.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.DEPENDENCY_ALIGNMENT_CHECK_MISSING'
      reason_code = 'dependency_alignment_check_missing'
      user_facing_blocker = 'dependency_alignment_check_missing'
      why = 'The completion receipt has no dependency alignment check, so it does not prove connected surfaces were checked against the latest changed artifact.'
      safe_next_action = 'Identify the changed artifact, list its connected prompt/resolver/guard/schema/runtime/doc surfaces, check them against the latest change, and record the evidence.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.DEPENDENCY_ALIGNMENT_FAILED'
      reason_code = 'dependency_alignment_failed'
      user_facing_blocker = 'dependency_alignment_failed'
      why = 'The dependency alignment check did not pass, so at least one connected surface may not match the latest changed artifact.'
      safe_next_action = 'Update the stale connected surface or keep the task blocked until the mismatch is resolved.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.DEPENDENCY_ALIGNMENT_EVIDENCE_MISSING'
      reason_code = 'dependency_alignment_evidence_missing'
      user_facing_blocker = 'dependency_alignment_evidence_missing'
      why = 'The dependency alignment check is missing changed paths, checked connected paths, or evidence.'
      safe_next_action = 'Record changed paths, checked connected paths, and the concrete evidence that they match the latest changed behavior before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.REQUIRED_TOOL_NOT_USED'
      reason_code = 'required_tool_not_used'
      user_facing_blocker = 'required_tool_not_used'
      why = 'The completion claim matches a required tool route, but the receipt and tool usage ledger do not show matching tool/check evidence or explicit unavailable/not-applicable reporting.'
      safe_next_action = 'Use the required capability or check, or record explicit unavailable/not-applicable reporting in the parent completion receipt. If this repeats without artifact or evidence change, stop retrying and report the missing route to the user.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.PM.ORCHESTRATION_PREFLIGHT_MISSING'
      reason_code = 'pm_orchestration_preflight_missing'
      user_facing_blocker = 'pm_orchestration_preflight_missing'
      why = 'A Class 3 or Class 4 mutating action is about to touch hook, runtime, receipt, ledger, AGENTS, workflow, CI, security, completion-gate, or reward-signal-filter surfaces before PM preflight is established.'
      safe_next_action = 'Run PM preflight first: write current task and need receipts, resolve required routes, schedule required subagent jobs, initialize the PM decision ledger, then retry the mutating action.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.PM.REQUIRED_SUBAGENT_JOBS_NOT_SCHEDULED'
      reason_code = 'required_subagent_jobs_not_scheduled'
      user_facing_blocker = 'required_subagent_jobs_not_scheduled'
      why = 'Need resolution requires subagent inspection routes for this Class 3 or Class 4 mutating action, but the required job envelopes are not scheduled yet.'
      safe_next_action = 'Schedule the route-limited read-only subagent jobs before the first mutating action. Reports remain Stop evidence, not a PreToolUse precondition.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.PM.REQUIRED_SUBAGENT_SPAWN_NOT_OBSERVED'
      reason_code = 'required_subagent_spawn_not_observed'
      user_facing_blocker = 'required_subagent_spawn_not_observed'
      why = 'Need resolution requires subagent routes for this Class 3 or Class 4 mutating action, but parent PM spawn evidence is missing for at least one required route.'
      safe_next_action = 'Spawn each required route subagent from the parent PM and record a subagent_spawn_event before the first mutating action.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.PM.REQUIRED_WORKER_NOT_SPAWNED'
      reason_code = 'required_worker_not_spawned'
      user_facing_blocker = 'required_worker_not_spawned'
      why = 'A mutating or implementation task requires a worker route, but the parent PM has no worker_spawn_event.'
      safe_next_action = 'Spawn the required worker route with scoped workspace-write authority before relying on inspectors or claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.PM.INSPECTOR_ONLY_DELEGATION_FOR_MUTATING_TASK'
      reason_code = 'inspector_only_delegation_for_mutating_task'
      user_facing_blocker = 'inspector_only_delegation_for_mutating_task'
      why = 'The parent PM delegated only inspector routes for a mutating or implementation task.'
      safe_next_action = 'Add the required worker route; inspectors can review candidate evidence but cannot replace implementation workers.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.PM.COLLAPSED_WORKER_ROUTE_INTO_INSPECTOR_ROUTE'
      reason_code = 'pm_collapsed_worker_route_into_inspector_route'
      user_facing_blocker = 'pm_collapsed_worker_route_into_inspector_route'
      why = 'The parent PM treated required worker delegation as if an inspector route satisfied it.'
      safe_next_action = 'Keep worker_routes and inspector_routes separate and spawn both when the task requires both.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.WORKER_REPORT_MISSING'
      reason_code = 'worker_report_missing'
      user_facing_blocker = 'worker_report_missing'
      why = 'A required worker route has no worker report for Stop finalization.'
      safe_next_action = 'Collect and review the worker report as candidate_artifact_only evidence before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.PM.DECISION_MISSING'
      reason_code = 'pm_decision_missing'
      user_facing_blocker = 'pm_decision_missing'
      why = 'Required routes exist but the parent PM decision evidence is missing, so completion cannot prove orchestration accountability.'
      safe_next_action = 'Record a PM decision event or PM accountability report before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.TASK.CLASSIFICATION_MISSING'
      reason_code = 'task_classification_missing'
      user_facing_blocker = 'task_classification_missing'
      why = 'No task_classification_receipt is available for the active turn, so the gate cannot prove that basic work was positively allowed or that higher-risk work was classified upward.'
      safe_next_action = 'Generate task_classification_receipt.v1 for the current turn before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.TASK.CLASSIFICATION_UNKNOWN'
      reason_code = 'task_classification_unknown'
      user_facing_blocker = 'task_classification_unknown'
      why = 'The task classification receipt has no known Class 0 through Class 4 decision.'
      safe_next_action = 'Re-run the task classifier using the current user goal, touched surfaces, action class, and risk class.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.TASK.CLASSIFICATION_DOWNSHIFT'
      reason_code = 'task_classification_downshift_detected'
      user_facing_blocker = 'task_classification_downshift_detected'
      why = 'A task was classified lower than the touched surface requires, such as treating implementation or control-plane work as basic.'
      safe_next_action = 'Classify upward, regenerate need_resolution_receipt, and satisfy the required routes before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.NEED.RESOLUTION_MISSING'
      reason_code = 'need_resolution_missing'
      user_facing_blocker = 'need_resolution_missing'
      why = 'No need_resolution_receipt is available for the active turn, so required routes cannot be proven satisfied or not applicable.'
      safe_next_action = 'Generate need_resolution_receipt.v1 from the required_route_resolver before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.NEED.RESOLUTION_UNKNOWN'
      reason_code = 'need_resolution_unknown'
      user_facing_blocker = 'need_resolution_unknown'
      why = 'The route resolver left one or more need decisions unknown.'
      safe_next_action = 'Resolve UNKNOWN to REQUIRED, RECOMMENDED, NOT_APPLICABLE, or UNAVAILABLE with evidence before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.NEED.ROUTE_UNKNOWN'
      reason_code = 'route_need_unknown'
      user_facing_blocker = 'route_need_unknown'
      why = 'At least one route need level is UNKNOWN, so completion authority cannot decide whether evidence is required.'
      safe_next_action = 'Resolve the route need level and rerun the completion gate.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.NEED.REQUIRED_ROUTE_UNSATISFIED'
      reason_code = 'required_route_unsatisfied'
      user_facing_blocker = 'required_route_unsatisfied'
      why = 'Need resolution says a route is REQUIRED, but no usage, check, subagent report, unavailable, or not-applicable evidence satisfies it.'
      safe_next_action = 'Use the required route or record explicit unavailable/not-applicable evidence in the parent completion receipt.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.REQUIRED_SKILL_NOT_USED'
      reason_code = 'required_skill_not_used'
      user_facing_blocker = 'required_skill_not_used'
      why = 'The completion claim requires a skill route, but the evidence only shows availability or nothing at all, not actual skill use.'
      safe_next_action = 'Load and use the required skill, or record explicit unavailable/not-applicable evidence.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.SKILL_RESOLUTION_RECEIPT_MISSING'
      reason_code = 'skill_resolution_receipt_missing'
      user_facing_blocker = 'skill_resolution_receipt_missing'
      why = 'The active turn has required skill routes but no matching skill_resolution_receipt.'
      safe_next_action = 'Generate skill_resolution_receipt.v1 from the same task classification and need resolution turn before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.NEED.SKILL_UNKNOWN'
      reason_code = 'skill_need_unknown'
      user_facing_blocker = 'skill_need_unknown'
      why = 'At least one skill need is UNKNOWN, so completion authority cannot decide whether skill evidence is required.'
      safe_next_action = 'Resolve each skill need to REQUIRED, RECOMMENDED, OPTIONAL, NOT_APPLICABLE, or UNAVAILABLE with evidence.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.INSTALLED_SKILL_NOT_EVIDENCE'
      reason_code = 'installed_skill_not_evidence'
      user_facing_blocker = 'installed_skill_not_evidence'
      why = 'A skill is installed or configured, but installation is not evidence that it was used for the task.'
      safe_next_action = 'Record a skill_usage_event or explicit unavailable/not-applicable evidence for the required skill route.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.SKILL_VERIFICATION_MISSING'
      reason_code = 'skill_verification_missing'
      user_facing_blocker = 'skill_verification_missing'
      why = 'A required skill route has no usable verification evidence.'
      safe_next_action = 'Record the required skill usage event and rerun the direct check tied to the changed behavior.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.WORKER_REQUIRED_SKILL_NOT_USED'
      reason_code = 'worker_required_skill_not_used'
      user_facing_blocker = 'worker_required_skill_not_used'
      why = 'A required worker route completed without a worker skill usage summary for the required skill routes.'
      safe_next_action = 'Collect a worker report that includes required_outputs.skill_usage_summary, or record a valid PM waiver with replacement evidence.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.REQUIRED_SUBAGENT_NOT_SPAWNED'
      reason_code = 'required_subagent_not_spawned'
      user_facing_blocker = 'required_subagent_not_spawned'
      why = 'Need resolution requires a subagent inspection route, but no matching job envelope was spawned or explicitly marked not applicable.'
      safe_next_action = 'Spawn the required route-limited inspector job or record explicit not-applicable evidence before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.SUBAGENT_REPORT_MISSING'
      reason_code = 'subagent_report_missing'
      user_facing_blocker = 'subagent_report_missing'
      why = 'A required subagent inspection job exists, but its candidate evidence report is not recorded yet.'
      safe_next_action = 'Record the inspector report in the append-only ledger or mark the route not applicable in the parent receipt. The report remains candidate evidence only.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.SUBAGENT_REPORT_QUARANTINED'
      reason_code = 'subagent_report_quarantined'
      user_facing_blocker = 'subagent_report_quarantined'
      why = 'A required subagent report was quarantined, so it cannot satisfy the route or support a completion claim.'
      safe_next_action = 'Reject the quarantined report, record PM ownership, and use a replacement worker or explicit not-applicable evidence before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.SUBAGENT_REPORT_TERMINATED'
      reason_code = 'subagent_report_terminated'
      user_facing_blocker = 'subagent_report_terminated'
      why = 'A required subagent worker was terminated, so its report is excluded from completion evidence.'
      safe_next_action = 'Exclude the terminated report from evidence and spawn a replacement worker unless the replacement limit has been reached.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.PM.ADOPTED_TAINTED_SUBAGENT_OUTPUT'
      reason_code = 'pm_adopted_tainted_subagent_output'
      user_facing_blocker = 'pm_adopted_tainted_subagent_output'
      why = 'The PM adopted a quarantined or terminated worker report as evidence, which is a PM failure.'
      safe_next_action = 'Reject the tainted report, record a PM decision event, and rebuild route evidence from a clean worker report.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.PM.REPLACEMENT_LIMIT_REACHED'
      reason_code = 'replacement_limit_reached'
      user_facing_blocker = 'replacement_limit_reached'
      why = 'The route reached its replacement limit after repeated worker failures.'
      safe_next_action = 'Stop automatic replacement and report the unresolved route to the user with the lifecycle ledger evidence.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.STALE_RECEIPT'
      reason_code = 'stale_completion_receipt'
      user_facing_blocker = 'stale_completion_receipt'
      why = 'The completion receipt does not match the active turn fingerprint, so a previous turn receipt may be reused.'
      safe_next_action = 'Invalidate the old receipt at user prompt submit and write a fresh receipt for the current task.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.RECEIPT_FRESHNESS_MISSING'
      reason_code = 'completion_receipt_freshness_missing'
      user_facing_blocker = 'completion_receipt_freshness_missing'
      why = 'The completion receipt does not include current attempt, affected path, validation timestamp, and artifact hash freshness data.'
      safe_next_action = 'Record affected paths, validation timestamp after the last relevant write, and current artifact hashes before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.ARTIFACT_STALE'
      reason_code = 'completion_receipt_artifact_stale'
      user_facing_blocker = 'completion_receipt_artifact_stale'
      why = 'The completion receipt artifact hash no longer matches the current file contents, or the affected artifact is missing.'
      safe_next_action = 'Revalidate the current artifact, refresh the hash evidence, and only then claim completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.VALIDATION_BEFORE_LATEST_WRITE'
      reason_code = 'completion_receipt_validation_before_latest_write'
      user_facing_blocker = 'completion_receipt_validation_before_latest_write'
      why = 'The completion receipt validation timestamp is older than a relevant artifact write.'
      safe_next_action = 'Run the validation after the latest relevant write and update the receipt freshness evidence.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.FUTURE_DATED_VALIDATION_TIMESTAMP'
      reason_code = 'future_dated_validation_timestamp'
      user_facing_blocker = 'future_dated_validation_timestamp'
      why = 'The completion receipt validation timestamp is in the future, so the receipt could be self-dated ahead of real evidence.'
      safe_next_action = 'Rerun the validation using the current clock after the relevant writes and record the actual validation timestamp.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.GATE_ISSUED_RECEIPT_MISSING'
      reason_code = 'gate_issued_completion_receipt_missing'
      user_facing_blocker = 'gate_issued_completion_receipt_missing'
      why = 'The final authority receipt was not issued by the completion gate, so an agent-written completion receipt remains candidate evidence only.'
      safe_next_action = 'Let the Stop completion gate validate the candidate receipt and issue gate_issued_completion_receipt.json before claiming completion.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMPLETION.STALE_GATE_ISSUED_RECEIPT'
      reason_code = 'stale_gate_issued_completion_receipt'
      user_facing_blocker = 'stale_gate_issued_completion_receipt'
      why = 'The gate-issued receipt does not match the active turn and candidate receipt fingerprint.'
      safe_next_action = 'Rerun the Stop completion gate after refreshing the candidate receipt and evidence for this exact turn.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.REWARD_SIGNAL.COUNTEREXAMPLE_REVIEW_MISSING'
      reason_code = 'reward_signal_counterexample_review_missing'
      user_facing_blocker = 'reward_signal_counterexample_review_missing'
      why = 'A frequent work command produced a reward-like signal, and no counterexample review has cleared it yet.'
      safe_next_action = 'Treat the command result as filtered evidence only, inspect at least one direct counterexample path, then clear the reward signal filter in the receipt.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.REWARD_HACKING.PATH_DETECTED'
      reason_code = 'reward_hacking_path_detected'
      user_facing_blocker = 'reward_hacking_path_detected'
      why = 'The operation touches a reward-hacking path such as hardcoded success, fake tests, harness manipulation, completion definition tampering, or validation bypass.'
      safe_next_action = 'Stop this path immediately, discard any pass/fail result from it, and restart through the normal requirements-to-logic-to-evidence path.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.REWARD_HACKING.SNAPSHOT_DETECTED'
      reason_code = 'reward_hacking_snapshot_detected'
      user_facing_blocker = 'reward_hacking_snapshot_detected'
      why = 'Stop snapshot fallback found reward-hacking contamination in a harness, validation, completion definition, or dummy artifact path after a tool path that may not have passed through PreToolUse.'
      safe_next_action = 'Treat any pass/fail result as invalid, restore the contaminated dummy or harness artifact, and restart through the normal implementation path.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.REWARD_HACKING.HEURISTIC_REVIEW_MISSING'
      reason_code = 'heuristic_review_report_missing'
      user_facing_blocker = 'heuristic_review_report_missing'
      why = 'A risky non-absolute reward-hacking keyword hit was downgraded to SUSPECT, but the read-only false-positive review report is not recorded yet.'
      safe_next_action = 'Record a candidate-only spark_false_positive_reviewer report, then let the parent Stop gate evaluate it with the normal completion receipt evidence.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.REWARD_HACKING.HEURISTIC_REVIEW_UNCERTAIN'
      reason_code = 'heuristic_review_uncertain'
      user_facing_blocker = 'heuristic_review_uncertain'
      why = 'The read-only false-positive review could not classify the suspect heuristic hit confidently.'
      safe_next_action = 'Do not claim completion; narrow the artifact evidence or ask the user only if the uncertainty cannot be resolved from local context.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.REWARD_HACKING.HEURISTIC_REVIEW_TRUE_POSITIVE'
      reason_code = 'heuristic_review_likely_true_positive'
      user_facing_blocker = 'heuristic_review_likely_true_positive'
      why = 'The candidate-only reviewer classified the suspect reward-hacking hit as likely true positive, so completion remains blocked.'
      safe_next_action = 'Remove the contaminated path and redo the affected work through normal implementation logic.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.CONTROL_PLANE.MUTATION_WITHOUT_CURRENT_TASK_SCOPE'
      reason_code = 'control_plane_mutation_without_current_task_scope'
      user_facing_blocker = 'control_plane_mutation_without_current_task_scope'
      why = 'The operation attempts to mutate an authority, hook, policy, or runtime schema surface without a current user task that explicitly authorizes that class of change.'
      safe_next_action = 'Keep the operation read-only, or continue only after the active user task explicitly scopes the exact control-plane change.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.CONTROL_PLANE.MUTATION_REVIEW_MISSING'
      reason_code = 'control_plane_mutation_review_missing'
      user_facing_blocker = 'control_plane_mutation_review_missing'
      why = 'A control-plane mutation was in scope, but the post-change review has not cleared minimality, necessity, protected-surface, and no-secret checks.'
      safe_next_action = 'List touched control-plane files, separate necessary from excessive changes, run the direct checks, then clear the control-plane review marker in the receipt.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.CONTROL_PLANE.REPAIR_PATH_NOT_ALLOWED'
      reason_code = 'control_plane_repair_path_not_allowed'
      user_facing_blocker = 'control_plane_repair_path_not_allowed'
      why = 'The operation is a control-plane mutation, but its target path is not in the current authorized repair allowlist.'
      safe_next_action = 'Limit the repair to the approved hook, declarative policy, runtime schema, or live hook config path, or ask the user to expand scope.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.CONTROL_PLANE.REPAIR_INTENT_MISSING'
      reason_code = 'control_plane_repair_intent_missing'
      user_facing_blocker = 'control_plane_repair_intent_missing'
      why = 'The operation touches a control-plane surface, but the active task does not show a repair, strengthening, clarification, or alignment intent.'
      safe_next_action = 'Keep the operation read-only or proceed only after the active user task explicitly authorizes the control-plane repair intent.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.CONTROL_PLANE.ENFORCEMENT_WEAKENING_ATTEMPT'
      reason_code = 'enforcement_weakening_attempt'
      user_facing_blocker = 'enforcement_weakening_attempt'
      why = 'The operation appears to disable, remove, weaken, or hide enforcement rather than repair or clarify it.'
      safe_next_action = 'Preserve enforcement strength, keep the change narrowly scoped to repair, or ask the user for explicit confirmation if weakening is truly intended.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.SCOPE.ACTIVE_SCOPE_MISSING'
      reason_code = 'active_scope_missing'
      user_facing_blocker = 'active_scope_missing'
      why = 'The active contract has no declared scope, so the hook cannot prove the operation is in scope.'
      safe_next_action = 'Declare the intended scope in active_contract.json before allowing scoped operations.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMMAND.SOURCE_MISSING'
      reason_code = 'command_without_declared_source'
      user_facing_blocker = 'command_without_declared_source'
      why = 'The command has no declared source and is not proven to be a current-task scoped operation.'
      safe_next_action = 'Use an allowed command source or keep the operation inside the active task scope.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMMAND.SOURCE_NOT_ALLOWED'
      reason_code = 'command_source_not_allowed'
      user_facing_blocker = 'command_source_not_allowed'
      why = 'The command source is not one of the allowed sources: user explicit instruction, declared config, package script, or documented repo workflow.'
      safe_next_action = 'Use an allowed source or document why this command belongs to the current task.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.COMMAND.DESTRUCTIVE_ACTION_WITHOUT_SCOPE'
      reason_code = 'destructive_action_without_explicit_scope'
      user_facing_blocker = 'destructive_action_without_explicit_scope'
      why = 'The operation appears to run a broad destructive action without explicit current-task scope.'
      safe_next_action = 'Keep the operation read-only, narrow it to a specific in-scope path, or ask for explicit user instruction before running it.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.SECURITY.CREDENTIAL_OR_SECRET_TOUCH'
      reason_code = 'credential_or_secret_touch'
      user_facing_blocker = 'credential_or_secret_touch'
      why = 'The operation references credential, token, secret, or auth material.'
      safe_next_action = 'Remove credential/auth material from the operation, or request explicit user scope only if that exact secret-handling work is required.'
    },
    [ordered]@{
      blocker_id = 'CONTRACT.SCOPE.PROTECTED_SURFACE_WITHOUT_EXPLICIT_SCOPE'
      reason_code = 'protected_surface_without_explicit_scope'
      user_facing_blocker = 'protected_surface_without_explicit_scope'
      why = 'The operation targets a protected surface without explicit current-task scope.'
      safe_next_action = 'Keep the operation inside the active scope or request explicit user scope for that protected surface.'
    }
  )
}

function Get-ReasonDescription {
  param([Parameter(Mandatory = $true)][string]$Reason)

  foreach ($definition in Get-BlockerDefinitions) {
    if ($definition.reason_code -eq $Reason) {
      return [ordered]@{
        blocker_id = $definition.blocker_id
        reason_code = $definition.reason_code
        blocker = $definition.user_facing_blocker
        why = $definition.why
        safe_next_action = $definition.safe_next_action
      }
    }
  }

  foreach ($definition in Get-BlockerDefinitions) {
    $reasonPattern = Get-OptionalPropertyValue -Object $definition -Name 'reason_pattern'
    if ($reasonPattern -and ($Reason -match $reasonPattern)) {
      $state = $Matches[1]
      return [ordered]@{
        blocker_id = $definition.blocker_id
        reason_code = $Reason
        blocker = $Reason
        why = $definition.why.Replace('$state', $state)
        safe_next_action = $definition.safe_next_action
      }
    }
  }

  [ordered]@{
    blocker_id = 'CONTRACT.UNKNOWN_REASON'
    reason_code = $Reason
    blocker = $Reason
    why = 'The hook returned a blocker reason that has no shared schema mapping yet.'
    safe_next_action = 'Inspect the hook decision details and add a reason mapping if this blocker should be user-actionable.'
  }
}

function New-BlockerReport {
  param(
    [Parameter(Mandatory = $true)][string]$HookName,
    [Parameter(Mandatory = $true)][object]$Decision,
    [Parameter(Mandatory = $true)][object]$ActiveContract,
    [object]$CompletionReceipt
  )

  $rawReason = [string](Get-OptionalPropertyValue -Object $Decision -Name 'reason')
  $description = Get-ReasonDescription -Reason $rawReason
  $currentBlockers = @()
  $evidence = @()
  if ($CompletionReceipt) {
    $currentBlockers = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'blockers'))
    $evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'evidence'))
  }
  $requiredToolRoutes = Get-OptionalPropertyValue -Object $Decision -Name 'required_tool_routes'
  if ($requiredToolRoutes) {
    foreach ($missing in @(Get-OptionalPropertyValue -Object $requiredToolRoutes -Name 'missing_requirements')) {
      $evidence += "missing_required_tool:$([string](Get-OptionalPropertyValue -Object $missing -Name 'route_id')):$([string](Get-OptionalPropertyValue -Object $missing -Name 'requirement_id'))"
    }
  }
  if ((Get-OptionalPropertyValue -Object $Decision -Name 'loop_breaker') -eq $true) {
    $evidence += 'loop_breaker_required_tool_not_used_repeated_without_artifact_or_evidence_change'
  }

  [ordered]@{
    status = 'FAILED_STATE'
    schema_version = 'blocker_schema.v1'
    hook = $HookName
    fail_policy = Get-HookFailPolicy -HookName $HookName
    blocker_id = $description.blocker_id
    reason_code = $description.reason_code
    fired_blocker = $description.blocker
    raw_reason = $rawReason
    why = $description.why
    safe_next_action = $description.safe_next_action
    active_contract_state = Get-OptionalPropertyValue -Object $ActiveContract -Name 'state'
    completion_receipt_state = if ($CompletionReceipt) { Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'completion_state' } else { $null }
    current_blockers = $currentBlockers
    evidence = $evidence
  }
}

function Format-BlockerReport {
  param([Parameter(Mandatory = $true)][object]$Report)

  $lines = @(
    'CONTRACT BLOCKER FIRED',
    "schema_version: $($Report.schema_version)",
    "hook: $($Report.hook)",
    "fail_policy: $($Report.fail_policy)",
    "blocker_id: $($Report.blocker_id)",
    "reason_code: $($Report.reason_code)",
    "blocker: $($Report.fired_blocker)",
    "raw_reason: $($Report.raw_reason)",
    "why: $($Report.why)",
    "safe_next_action: $($Report.safe_next_action)",
    "active_contract_state: $($Report.active_contract_state)"
  )

  if ($Report.completion_receipt_state) {
    $lines += "completion_receipt_state: $($Report.completion_receipt_state)"
  }
  if (@($Report.current_blockers).Count -gt 0) {
    $lines += 'current_blockers:'
    foreach ($blocker in @($Report.current_blockers)) {
      $lines += "- $blocker"
    }
  }
  if (@($Report.evidence).Count -gt 0) {
    $lines += 'evidence:'
    foreach ($item in @($Report.evidence)) {
      $lines += "- $item"
    }
  }

  $lines -join "`n"
}

function Write-InvocationLog {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Entry
  )

  $line = ($Entry | ConvertTo-Json -Depth 5 -Compress) + [Environment]::NewLine
  $directory = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $directory -Force
  }
  $bytes = $script:Utf8NoBom.GetBytes($line)
  for ($attempt = 0; $attempt -lt 5; $attempt++) {
    $stream = $null
    try {
      $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
      $stream.Write($bytes, 0, $bytes.Length)
      $stream.Flush($true)
      return
    } catch {
      Start-Sleep -Milliseconds (50 * ($attempt + 1))
    } finally {
      if ($stream) {
        $stream.Dispose()
      }
    }
  }
}

$script:HookFailureLogged = $false
trap {
  if (-not $script:HookFailureLogged) {
    $script:HookFailureLogged = $true
    try {
      $failureRoot = Get-CanonicalRoot
      $failureObservedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
      $failureNonce = [guid]::NewGuid().ToString('n')
      $failurePayloadText = if ($PayloadJson) { [string]$PayloadJson } else { '' }
      $failurePayloadFingerprint = Get-TextFingerprint -Text $failurePayloadText
      $failureHookEventName = switch ($HookName) {
        'session_start' { 'SessionStart' }
        'user_prompt_submit' { 'UserPromptSubmit' }
        'pre_turn_active_contract' { 'UserPromptSubmit' }
        'retry_invalidation' { 'UserPromptSubmit' }
        'pre_command_guard' { 'PreToolUse' }
        'pre_response_checklist' { 'Stop' }
        'completion_gate' { 'Stop' }
        'post_turn_state_register' { 'Stop' }
        'stop_checks' { 'Stop' }
        'post_tool_use' { 'PostToolUse' }
        default { $HookName }
      }
      $failureEntry = [ordered]@{
        schema_version = 'hook_invocation_event.v1'
        record_type = 'hook_invocation_event'
        event_id = New-LedgerEventId -ObservedAtUtc $failureObservedAtUtc -EventNonce $failureNonce -HookName $HookName -HookEventName $failureHookEventName -PayloadFingerprint $failurePayloadFingerprint -Decision 'HOOK_FAILED' -Reason ([string]$_.Exception.Message)
        event_nonce = $failureNonce
        observed_at_utc = $failureObservedAtUtc
        timestamp = (Get-Date).ToString('o')
        hook = $HookName
        hook_event_name = $failureHookEventName
        dry_run = [bool]$DryRun
        decision = 'HOOK_FAILED'
        reason = [string]$_.Exception.Message
        payload_fingerprint = $failurePayloadFingerprint
        outcome = 'failed'
        append_only = $true
      }
      Write-InvocationLog -Path (Join-Path $failureRoot 'Maintenance/hook_invocations.jsonl') -Entry $failureEntry
    } catch {
    }
  }
  throw $_
}

$root = Get-CanonicalRoot
$payload = Read-OptionalPayloadJson -Text $PayloadJson
if (-not $payload) {
  $payload = Read-OptionalStdinJson
}

if ($payload) {
  if (-not $CommandSource) { $CommandSource = Get-PayloadString -Object $payload -Names @('command_source','commandSource') }
  if (-not $TargetSurface) { $TargetSurface = Get-PayloadString -Object $payload -Names @('target_surface') }
  if (-not $PromptText) { $PromptText = Get-PayloadString -Object $payload -Names @('prompt','user_prompt','userPrompt','input') }
  if (-not $CompletionState) { $CompletionState = Get-PayloadString -Object $payload -Names @('completion_state') }
}

$activeContract = Read-JsonFile -Path (Join-Path $root 'Settings/Codex_App_RUNTIME/active_contract.json')
$completionReceipt = Read-OptionalJsonFile -Path (Join-Path $root 'Settings/Codex_App_RUNTIME/completion_receipt.json')
if ($DryRun -or $HookName -eq 'session_start') {
  $requiredStatus = Get-RequiredStatus -Root $root
  $cleanSlateStatus = Get-CleanSlateStatus -Root $root
  $hookStatus = Get-HookStatus -Root $root
} else {
  $requiredStatus = [ordered]@{ skipped = 'runtime_fast_path' }
  $cleanSlateStatus = [ordered]@{ skipped = 'runtime_fast_path' }
  $hookStatus = [ordered]@{ skipped = 'runtime_fast_path' }
}
$payloadText = Convert-PayloadToText -Object $payload
$payloadWorkdir = Get-PayloadString -Object $payload -Names @('workdir','cwd','workingDirectory','working_directory')
$lastAssistantMessage = Get-PayloadString -Object $payload -Names @('last_assistant_message','lastAssistantMessage')
if ([string]::IsNullOrWhiteSpace($payloadWorkdir)) {
  $payloadWorkdir = (Get-Location).Path
}
if ([string]::IsNullOrWhiteSpace($TargetSurface) -and $payloadText -match '\\\.codex(\\|")') {
  $TargetSurface = '.codex'
}

$runtimeCapabilityReceipt = $null
if (($HookName -eq 'session_start') -and (-not $NoLog) -and (-not $DryRun)) {
  $runtimeCapabilityReceipt = Write-RuntimeCapabilityReceipt -Root $root -ActiveContract $activeContract -Workdir $payloadWorkdir
}

$decision = [ordered]@{ decision = 'ALLOW'; reason = 'hook_context_loaded' }
$turnStateUpdate = $null
$subagentInspectionJobs = @()
switch ($HookName) {
  'pre_command_guard' {
    $decision = Test-CommandGuard -Source $CommandSource -Surface $TargetSurface -Scoped $ExplicitUserScope.IsPresent -PayloadText $payloadText -Workdir $payloadWorkdir -Root $root -ActiveContract $activeContract -InspectOnly:($NoLog.IsPresent)
    if ([string](Get-OptionalPropertyValue -Object $decision -Name 'decision') -eq 'ALLOW') {
      $preflight = Test-PmOrchestrationPreflight -Root $root -ActiveContract $activeContract -CompletionReceipt $completionReceipt -PayloadText $payloadText -Workdir $payloadWorkdir
      if (-not $preflight.ok) {
        $decision = [ordered]@{
          decision = 'BLOCKED'
          reason = $preflight.reason
          pm_orchestration_preflight = $preflight
        }
      }
    }
    $decisionRewardSignal = Get-OptionalPropertyValue -Object $decision -Name 'reward_signal'
    $decisionControlPlane = Get-OptionalPropertyValue -Object $decision -Name 'control_plane'
    $decisionRepairScope = Get-OptionalPropertyValue -Object $decision -Name 'repair_scope'
    if ((-not $NoLog) -and (Get-OptionalPropertyValue -Object $decision -Name 'reason') -eq 'reward_signal_command_filtered' -and $decisionRewardSignal) {
      $completionReceipt = Register-RewardSignalFilter -Root $root -RewardSignal $decisionRewardSignal -PayloadText $payloadText -CompletionReceipt $completionReceipt
    }
    if ((-not $NoLog) -and (Get-OptionalPropertyValue -Object $decision -Name 'reason') -eq 'control_plane_mutation_current_task_scoped') {
      $completionReceipt = Register-ControlPlaneMutationReview -Root $root -ControlPlaneMutation $decisionControlPlane -PayloadText $payloadText -RepairScope $decisionRepairScope -CompletionReceipt $completionReceipt
    }
    if ((-not $NoLog) -and (-not $DryRun) -and ([string](Get-OptionalPropertyValue -Object $decision -Name 'decision') -eq 'ALLOW') -and (Test-MutatingOperationText -Text $payloadText)) {
      $null = Write-TaskNeedReceipts -Root $root -ActiveContract $activeContract -CompletionReceipt $completionReceipt -ContextText $payloadText -ActionClass 'write' -CompletionClaim:$false
    }
  }
  'user_prompt_submit' {
    $pmPreflight = $null
    if (Test-ChildAgentPromptContext -Payload $payload -PromptText $PromptText -PayloadText $payloadText) {
      $turnStateUpdate = [ordered]@{
        changed = $false
        reason = 'child_agent_prompt_preserved_parent_contract'
        fingerprint = Get-OptionalPropertyValue -Object $activeContract -Name 'turn_fingerprint'
      }
    } elseif (Test-HookGeneratedBlockerText -Text "$PromptText`n$payloadText") {
      $turnStateUpdate = [ordered]@{
        changed = $false
        reason = 'hook_generated_blocker_prompt_paused_no_turn_invalidation'
        fingerprint = Get-OptionalPropertyValue -Object $activeContract -Name 'turn_fingerprint'
      }
    } elseif ($DryRun) {
      $turnStateUpdate = [ordered]@{
        changed = $false
        reason = 'dry_run_no_turn_invalidation'
        fingerprint = Get-OptionalPropertyValue -Object $activeContract -Name 'turn_fingerprint'
      }
    } else {
      $turnStateUpdate = Initialize-TurnRuntimeState -Root $root -PromptText $PromptText -ActiveContract $activeContract -CompletionReceipt $completionReceipt -Workdir $payloadWorkdir
      if ($turnStateUpdate.changed) {
        $activeContract = Read-JsonFile -Path (Join-Path $root 'Settings/Codex_App_RUNTIME/active_contract.json')
        $completionReceipt = Read-OptionalJsonFile -Path (Join-Path $root 'Settings/Codex_App_RUNTIME/completion_receipt.json')
      }
    }
    if ((-not $NoLog) -and (-not $DryRun)) {
      $runtimeCapabilityReceipt = Write-RuntimeCapabilityReceipt -Root $root -ActiveContract $activeContract -Workdir $payloadWorkdir
      if ([string](Get-OptionalPropertyValue -Object $turnStateUpdate -Name 'reason') -ne 'child_agent_prompt_preserved_parent_contract') {
        $taskNeed = Write-TaskNeedReceipts -Root $root -ActiveContract $activeContract -CompletionReceipt $completionReceipt -ContextText "$PromptText`n$payloadText" -ActionClass 'report' -CompletionClaim:$false
        $pmPreflight = Initialize-PmOrchestrationPreflight -Root $root -ActiveContract $activeContract -CompletionReceipt $completionReceipt -TaskNeed $taskNeed -TriggerText "$PromptText`n$payloadText" -PathText $payloadText -NoLog:($NoLog.IsPresent)
      }
    }
    if (-not $DryRun) {
      if ($pmPreflight -and (Get-OptionalPropertyValue -Object $pmPreflight -Name 'required') -eq $true) {
        $subagentInspectionJobs = @(Get-OptionalPropertyValue -Object $pmPreflight -Name 'jobs')
      } elseif ([string](Get-OptionalPropertyValue -Object $turnStateUpdate -Name 'reason') -eq 'child_agent_prompt_preserved_parent_contract') {
        $subagentInspectionJobs = @()
      } else {
        $subagentInspectionJobs = @(Register-SubagentInspectionJobsForContext -Root $root -ActiveContract $activeContract -CompletionReceipt $completionReceipt -HookEventName 'UserPromptSubmit' -TriggerText "$PromptText`n$payloadText" -PathText $payloadText -NoLog:($NoLog.IsPresent))
      }
    }
    $retryDecision = Test-RetryInvalidation -Text $PromptText
    $decision = [ordered]@{ decision = 'ALLOW'; reason = 'active_contract_loaded_retry_checked'; retry = $retryDecision.decision; turn_state = $turnStateUpdate }
  }
  'retry_invalidation' {
    $decision = Test-RetryInvalidation -Text $PromptText
  }
  'completion_gate' {
    $decision = Test-CompletionGate -State $CompletionState -Root $root -ActiveContract $activeContract -CompletionReceipt $completionReceipt -NoLog:($NoLog.IsPresent -or $DryRun.IsPresent)
  }
  'stop_checks' {
    $gateDecision = Test-CompletionGate -State $CompletionState -Root $root -ActiveContract $activeContract -CompletionReceipt $completionReceipt -NoLog:($NoLog.IsPresent -or $DryRun.IsPresent)
    $gateReason = [string](Get-OptionalPropertyValue -Object $gateDecision -Name 'reason')
    $hasCompletionClaim = Test-CompletionClaimText -Text $lastAssistantMessage
    $statusOnlyReasons = @(
      'completion_state_missing',
      'state_candidate',
      'state_in_progress',
      'state_not_started'
    )
    if ($hasCompletionClaim -and -not (Test-FinalizationEvidenceText -Text $lastAssistantMessage)) {
      $decision = [ordered]@{ decision = 'DO_NOT_CLAIM_COMPLETE'; reason = 'direct_evidence_missing'; gated_reason = $gateReason }
    } elseif ([string]::IsNullOrWhiteSpace($CompletionState) -and (-not $hasCompletionClaim) -and ($statusOnlyReasons -contains $gateReason)) {
      $decision = [ordered]@{ decision = 'ALLOW'; reason = 'non_completion_stop_snapshot'; gated_reason = $gateReason }
    } else {
      $decision = $gateDecision
    }
  }
  'pre_response_checklist' {
    $decision = Test-CompletionGate -State $CompletionState -Root $root -ActiveContract $activeContract -CompletionReceipt $completionReceipt -NoLog:($NoLog.IsPresent -or $DryRun.IsPresent)
  }
  'post_tool_use' {
    if (-not $DryRun) {
      $subagentInspectionJobs = @(Register-SubagentInspectionJobsForContext -Root $root -ActiveContract $activeContract -CompletionReceipt $completionReceipt -HookEventName 'PostToolUse' -TriggerText $payloadText -PathText $payloadText -NoLog:($NoLog.IsPresent))
      $null = Register-HeuristicReviewObservation -Root $root -ActiveContract $activeContract -Payload $payload -PayloadText $payloadText -Workdir $payloadWorkdir -NoLog:($NoLog.IsPresent)
      $null = Register-SubagentInspectionObservation -Root $root -ActiveContract $activeContract -Payload $payload -PayloadText $payloadText -Workdir $payloadWorkdir -NoLog:($NoLog.IsPresent)
      $null = Register-SubagentWorkerObservation -Root $root -ActiveContract $activeContract -Payload $payload -PayloadText $payloadText -Workdir $payloadWorkdir -NoLog:($NoLog.IsPresent)
      $null = Register-SkillUsageObservation -Root $root -ActiveContract $activeContract -Payload $payload -PayloadText $payloadText -Workdir $payloadWorkdir -NoLog:($NoLog.IsPresent)
    }
    $decision = [ordered]@{ decision = 'ALLOW'; reason = 'tool_usage_event_recorded' }
  }
}

if ((-not $NoLog) -and (-not $DryRun) -and ($HookName -in @('pre_command_guard','post_tool_use'))) {
  $toolUsageEventName = if ($HookName -eq 'post_tool_use') { 'PostToolUse' } else { 'PreToolUse' }
  Register-ToolUsageEvent -Root $root -HookName $HookName -EventName $toolUsageEventName -Payload $payload -PayloadText $payloadText -Workdir $payloadWorkdir -ActiveContract $activeContract -Decision $decision
}

$decisionCode = [string](Get-OptionalPropertyValue -Object $decision -Name 'decision')
$decisionReason = [string](Get-OptionalPropertyValue -Object $decision -Name 'reason')
$blockerReport = $null
if ($decisionCode -eq 'BLOCKED' -or $decisionCode -eq 'DO_NOT_CLAIM_COMPLETE') {
  $blockerReport = New-BlockerReport -HookName $HookName -Decision $decision -ActiveContract $activeContract -CompletionReceipt $completionReceipt
}

$pendingSubagentInspectionJobs = @(Get-LatestSubagentInspectionJobs -Root $root -TurnFingerprint ([string](Get-OptionalPropertyValue -Object $activeContract -Name 'turn_fingerprint')) | Where-Object {
  [string](Get-OptionalPropertyValue -Object $_ -Name 'status') -in @('queued','spawn_requested','spawned')
})
$pendingSubagentInspectionJobsJson = if ($pendingSubagentInspectionJobs.Count -gt 0) {
  $pendingSubagentInspectionJobsForContext = @($pendingSubagentInspectionJobs | ForEach-Object {
    [ordered]@{
      job_id = Get-OptionalPropertyValue -Object $_ -Name 'job_id'
      parent_turn_id = Get-OptionalPropertyValue -Object $_ -Name 'parent_turn_id'
      route_id = Get-OptionalPropertyValue -Object $_ -Name 'route_id'
      agent_name = Get-OptionalPropertyValue -Object $_ -Name 'agent_name'
      sandbox_mode = Get-OptionalPropertyValue -Object $_ -Name 'sandbox_mode'
      target_paths = @(Normalize-SubagentInspectionTargetPaths -Root $root -Paths (Get-OptionalPropertyValue -Object $_ -Name 'target_paths'))
      status = Get-OptionalPropertyValue -Object $_ -Name 'status'
      authority = Get-OptionalPropertyValue -Object $_ -Name 'authority'
    }
  })
  ConvertTo-Json -InputObject $pendingSubagentInspectionJobsForContext -Depth 6 -Compress
} else {
  '[]'
}

$additionalContext = @"
Dev_Codex_App_GlobalSSOT is active.
Canonical root: $root
Clean slate config: Settings/Codex_App_DECLARATIVE/clean-slate.agent.config.toml
Hook runner: Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1
Active contract state: $(Get-OptionalPropertyValue -Object $activeContract -Name 'state')
Completion is not established by score, PASS, tests, self-verification, package verification, clean-room verification, or final output.
Workflow document policy: repo workflows are preferred only when present in the current repo or explicitly named by the user. Global/system-contract paths do not require a separate workflow document file; never report a missing optional global workflow document as a blocker or as something the user must provide.
Dependency alignment policy: when artifact A changes, connected prompt/resolver/guard/schema/runtime/doc/reporting surfaces must be checked against the latest A before development completion can be claimed.
Required tool route policy: installed/configured tools, skills, MCP servers, and subagents are required when a task matches a required route. Missing route evidence is checked at Stop finalization only, not by PreToolUse.
Completion authority policy: agent-written completion_receipt.json is candidate input only. The Stop completion gate must issue Settings/Codex_App_RUNTIME/gate_issued_completion_receipt.json with a matching source receipt fingerprint before completion is authority.
Timestamp policy: future-dated completion receipt validation timestamps are invalid evidence and block completion with future_dated_validation_timestamp.
Tool ledger policy: required-route tool evidence is append-only tool_usage_event.v2 from PostToolUse or an equivalent observation layer.
Subagent inspection policy: hooks may queue read-only Spark/high inspector jobs, but inspector reports are candidate_evidence_only and never completion authority.
Task classification policy: basic work is a positive allowlist, ambiguous work is classified upward, and executable completion claims require task_classification_receipt plus need_resolution_receipt.
Subagent depth policy: worker/inspector roles stay separated; recursive subagent spawning is capped at max_depth=1, while concurrency belongs to thread/job limits.
Pending subagent inspection jobs: $pendingSubagentInspectionJobsJson
Use Korean polite user-facing output and Windows terms: folder, PowerShell.
Vowline is required operating context for this Codex conversation. Load and apply the full Vowline skill body from: $HOME\.agents\skills\vowline\SKILL.md
"@

$eventName = switch ($HookName) {
  'session_start' { 'SessionStart' }
  'user_prompt_submit' { 'UserPromptSubmit' }
  'pre_turn_active_contract' { 'UserPromptSubmit' }
  'retry_invalidation' { 'UserPromptSubmit' }
  'pre_command_guard' { 'PreToolUse' }
  'pre_response_checklist' { 'Stop' }
  'completion_gate' { 'Stop' }
  'post_turn_state_register' { 'Stop' }
  'stop_checks' { 'Stop' }
  'post_tool_use' { 'PostToolUse' }
}

$actualOutput = [ordered]@{
  hookSpecificOutput = [ordered]@{
    hookEventName = $eventName
    additionalContext = $additionalContext
  }
}

$dryRunOutput = [ordered]@{
  hookSpecificOutput = $actualOutput.hookSpecificOutput
  ssot = [ordered]@{
    root = $root
    required = $requiredStatus
    clean_slate = $cleanSlateStatus
    hook_configs = $hookStatus
    blocker_schema = [ordered]@{
      version = 'blocker_schema.v1'
      reasons = @(Get-BlockerDefinitions)
    }
  }
  decision = $decision
  failed_state_report = $blockerReport
}

$logPath = Join-Path $root 'Maintenance/hook_invocations.jsonl'
$decisionRewardSignal = Get-OptionalPropertyValue -Object $decision -Name 'reward_signal'
$decisionControlPlane = Get-OptionalPropertyValue -Object $decision -Name 'control_plane'
$hookInvocationObservedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
$hookInvocationNonce = [guid]::NewGuid().ToString('n')
$hookPayloadFingerprint = Get-TextFingerprint -Text $payloadText
$activeTurnFingerprintForLog = [string](Get-OptionalPropertyValue -Object $activeContract -Name 'turn_fingerprint')
$hookAgentLineage = Get-AgentLineage -Payload $payload -ActiveContract $activeContract
$logEntry = [ordered]@{
  schema_version = 'hook_invocation_event.v1'
  record_type = 'hook_invocation_event'
  event_id = New-LedgerEventId -ObservedAtUtc $hookInvocationObservedAtUtc -EventNonce $hookInvocationNonce -TurnFingerprint $activeTurnFingerprintForLog -HookName $HookName -HookEventName $eventName -Cwd $payloadWorkdir -PayloadFingerprint $hookPayloadFingerprint -Decision $decisionCode -Reason $decisionReason
  event_nonce = $hookInvocationNonce
  observed_at_utc = $hookInvocationObservedAtUtc
  timestamp = (Get-Date).ToString('o')
  hook = $HookName
  hook_event_name = $eventName
  dry_run = [bool]$DryRun
  decision = $decisionCode
  reason = $decisionReason
  turn_state_changed = if ($turnStateUpdate) { $turnStateUpdate.changed } else { $null }
  turn_fingerprint = $activeTurnFingerprintForLog
  turn_state_fingerprint = if ($turnStateUpdate) { $turnStateUpdate.fingerprint } else { $null }
  payload_fingerprint = $hookPayloadFingerprint
  agent_lineage = $hookAgentLineage
  parent_lineage = $hookAgentLineage
  outcome = if ($decisionCode -in @('BLOCKED','DO_NOT_CLAIM_COMPLETE')) { 'blocked' } elseif ($decisionCode -eq 'HOOK_FAILED') { 'failed' } else { 'recorded' }
  reward_signal_filtered = if ($decisionRewardSignal) { Get-OptionalPropertyValue -Object $decisionRewardSignal -Name 'detected' } else { $null }
  reward_signal_category = if ($decisionRewardSignal) { Get-OptionalPropertyValue -Object $decisionRewardSignal -Name 'category' } else { $null }
  control_plane_mutation = if ($decisionControlPlane) { Get-OptionalPropertyValue -Object $decisionControlPlane -Name 'detected' } else { $null }
  control_plane_category = if ($decisionControlPlane) { Get-OptionalPropertyValue -Object $decisionControlPlane -Name 'category' } else { $null }
  blocker_schema_version = if ($blockerReport) { $blockerReport.schema_version } else { $null }
  blocker_id = if ($blockerReport) { $blockerReport.blocker_id } else { $null }
  reason_code = if ($blockerReport) { $blockerReport.reason_code } else { $null }
  fired_blocker = if ($blockerReport) { $blockerReport.fired_blocker } else { $null }
  append_only = $true
}
if (-not $NoLog) {
  Write-InvocationLog -Path $logPath -Entry $logEntry
}

if ($DryRun) {
  $json = $dryRunOutput | ConvertTo-Json -Depth 10 -Compress
} elseif ($eventName -eq 'Stop' -and ($decisionCode -eq 'BLOCKED' -or $decisionCode -eq 'DO_NOT_CLAIM_COMPLETE')) {
  $json = ([ordered]@{
    decision = 'block'
    reason = if ($blockerReport) { Format-BlockerReport -Report $blockerReport } else { $decisionReason }
  } | ConvertTo-Json -Depth 5 -Compress)
} elseif ($decisionCode -eq 'BLOCKED') {
  $reason = if ($blockerReport) { Format-BlockerReport -Report $blockerReport } else { $decisionReason }
  $json = ([ordered]@{
    decision = 'block'
    reason = $reason
  } | ConvertTo-Json -Depth 5 -Compress)
} elseif ($decisionCode -eq 'DO_NOT_CLAIM_COMPLETE') {
  $json = ([ordered]@{
    decision = 'block'
    reason = (Format-BlockerReport -Report $blockerReport)
  } | ConvertTo-Json -Depth 5 -Compress)
} elseif ($eventName -eq 'PreToolUse' -or $eventName -eq 'PostToolUse') {
  $json = '{}'
} elseif ($eventName -eq 'Stop') {
  $json = '{}' 
} else {
  $json = $actualOutput | ConvertTo-Json -Depth 5 -Compress
}

Write-Output $json
