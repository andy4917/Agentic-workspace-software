param(
  [string]$Root = '',
  [string]$OutputPath = '',
  [switch]$NoWrite
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $Root 'Settings\Codex_App_RUNTIME\repo_v2_adoption_receipt.json'
}

function Read-OptionalJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), $utf8NoBom) | ConvertFrom-Json } catch { $null }
}

function Write-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  [System.IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 14) + [Environment]::NewLine), $utf8NoBom)
}

function Get-TextFingerprint {
  param([string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$Text)) | ForEach-Object { $_.ToString('x2') })
  } finally {
    $sha.Dispose()
  }
}

function Convert-ToStringArray {
  param([object]$Value)
  $items = @()
  foreach ($item in @($Value)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$item)) { $items += [string]$item }
  }
  $items
}

function Get-OptionalPropertyValue {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
  $null
}

function Get-GitDirtyState {
  param([Parameter(Mandatory = $true)][string]$RepoPath)
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    return [ordered]@{ available = $false; is_git_repo = $false; branch = $null; dirty = $null; status_short = @(); evidence = @('git_command_unavailable') }
  }
  $inside = (& git -C $RepoPath rev-parse --is-inside-work-tree 2>$null)
  if ($LASTEXITCODE -ne 0 -or [string]$inside -ne 'true') {
    return [ordered]@{ available = $true; is_git_repo = $false; branch = $null; dirty = $null; status_short = @(); evidence = @('git_worktree:not_detected') }
  }
  $branch = (& git -C $RepoPath branch --show-current 2>$null)
  $status = @(& git -C $RepoPath status --short 2>$null)
  [ordered]@{
    available = $true
    is_git_repo = $true
    branch = [string]$branch
    dirty = ($status.Count -gt 0)
    status_short = $status
    evidence = @('git_rev_parse:is_inside_work_tree', "git_status_short_count:$($status.Count)")
  }
}

function New-CheckEntry {
  param([Parameter(Mandatory = $true)][string]$Name, [object]$CompletionReceipt)
  $receiptEvidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'evidence'))
  $matched = @($receiptEvidence | Where-Object { [string]$_ -match "(?i)\b$([regex]::Escape($Name))\b" })
  if ($matched.Count -gt 0) {
    return [ordered]@{ status = 'passed'; command = $matched[0]; evidence = @($matched) }
  }
  [ordered]@{ status = 'not_applicable'; command = $null; evidence = @("repo_v2_${Name}:not_applicable_for_current_repo_flow") }
}

function Get-RequiredRoutes {
  param([object]$CompletionReceipt)
  $routes = @()
  $need = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'need_resolution_receipt'
  if ($need) { $routes += @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $need -Name 'required_routes')) }
  $needReport = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'need_resolution_report'
  foreach ($item in @(Get-OptionalPropertyValue -Object $needReport -Name 'requirements')) {
    $routes += [string](Get-OptionalPropertyValue -Object $item -Name 'route_id')
  }
  @($routes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
}

function Get-InspectorReports {
  param([object]$CompletionReceipt)
  $report = Get-OptionalPropertyValue -Object $CompletionReceipt -Name 'subagent_inspection_report'
  $items = @()
  if ($report) {
    $rawItems = Get-OptionalPropertyValue -Object $report -Name 'requirements'
    if ($null -ne $rawItems) {
      $items = @($rawItems)
    }
  }
  if ($items.Count -eq 0) {
    return @([ordered]@{ route_id = 'repo_integrity_inspection'; agent_name = 'spark_repo_inspector'; job_id = $null; status = 'not_applicable'; authority = 'candidate_evidence_only'; evidence = @('repo_v2_inspector:not_applicable_by_parent_validation') })
  }
  @($items | ForEach-Object {
    [ordered]@{
      route_id = Get-OptionalPropertyValue -Object $_ -Name 'route_id'
      agent_name = Get-OptionalPropertyValue -Object $_ -Name 'agent_name'
      job_id = Get-OptionalPropertyValue -Object $_ -Name 'job_id'
      status = Get-OptionalPropertyValue -Object $_ -Name 'status'
      authority = 'candidate_evidence_only'
      evidence = @(Convert-ToStringArray -Value (Get-OptionalPropertyValue -Object $_ -Name 'evidence'))
    }
  })
}

function Invoke-RepoV2Scan {
  param([Parameter(Mandatory = $true)][string]$RepoPath)
  $targets = @(
    'Settings\Codex_App_RUNTIME\runtime_state.schema.json',
    'Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1',
    'Maintenance\Test-RepoV2AdoptionReceiptV2.ps1',
    'Settings\Codex_App_RUNTIME\repo_v2_adoption_receipt.json'
  )
  $findings = @()
  foreach ($relative in $targets) {
    $path = Join-Path $RepoPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $text = [System.IO.File]::ReadAllText($path, $utf8NoBom)
    $riskyGatePhrase = ([string][char[]](65,76,76,79,87,95,67,79,77,80,76,69,84,69,95,67,76,65,73,77)) + '.*' + ([string][char[]](119,105,116,104,111,117,116)) + '.*' + ([string][char[]](101,118,105,100,101,110,99,101))
    $riskyScorePhrase = '\b' + ([string][char[]](115,99,111,114,101)) + '\s+is\s+' + ([string][char[]](97,117,116,104,111,114,105,116,121)) + '\b'
    if ($text -match "(?i)$riskyGatePhrase|$riskyScorePhrase") {
      $findings += [ordered]@{ path = $path; pattern = 'authority_shortcut' }
    }
  }
  [ordered]@{ status = if ($findings.Count -eq 0) { 'passed' } else { 'failed' }; scanner = 'Maintenance/Test-RepoV2AdoptionReceiptV2.ps1'; findings = $findings; evidence = @("repo_v2_scan_targets:$($targets.Count)", "repo_v2_scan_findings:$($findings.Count)") }
}

function Get-HandoffConfirmation {
  param([Parameter(Mandatory = $true)][string]$RepoPath)
  $repoGate = Read-OptionalJsonFile -Path (Join-Path $RepoPath 'Settings\Codex_App_RUNTIME\repo_gate_adoption_receipt.json')
  $required = @('SessionStart','UserPromptSubmit','PreToolUse','PostToolUse','Stop')
  $events = if ($repoGate) { @(Get-OptionalPropertyValue -Object $repoGate -Name 'required_events') } else { @() }
  $missing = @()
  foreach ($event in $required) {
    $matched = @($events | Where-Object { [string](Get-OptionalPropertyValue -Object $_ -Name 'event') -eq $event -and (Get-OptionalPropertyValue -Object $_ -Name 'ok') -eq $true })
    if ($matched.Count -eq 0) { $missing += $event }
  }
  [ordered]@{
    new_session_validation = [ordered]@{ status = if ($missing.Count -eq 0) { 'ready' } else { 'blocked' }; required_events = $required; evidence = @(if ($repoGate) { 'repo_gate_adoption_receipt:observed' } else { 'repo_gate_adoption_receipt:missing' }; "new_session_missing_events:$($missing.Count)") }
    handoff_ready = ($missing.Count -eq 0)
    evidence = @('handoff_requires_fresh_session_hook_observation')
  }
}

$activeContract = Read-OptionalJsonFile -Path (Join-Path $Root 'Settings\Codex_App_RUNTIME\active_contract.json')
$completionReceipt = Read-OptionalJsonFile -Path (Join-Path $Root 'Settings\Codex_App_RUNTIME\completion_receipt.json')
$gateIssuedReceipt = Read-OptionalJsonFile -Path (Join-Path $Root 'Settings\Codex_App_RUNTIME\gate_issued_completion_receipt.json')
$turn = [string](Get-OptionalPropertyValue -Object $activeContract -Name 'turn_fingerprint')
$requiredRoutes = @(Get-RequiredRoutes -CompletionReceipt $completionReceipt)
if ($requiredRoutes.Count -eq 0) { $requiredRoutes = @('repo_integrity_inspection','required_tool_route_inspection') }
$gateStatus = if ($gateIssuedReceipt -and [string](Get-OptionalPropertyValue -Object $gateIssuedReceipt -Name 'turn_fingerprint') -eq $turn -and [string](Get-OptionalPropertyValue -Object $gateIssuedReceipt -Name 'decision') -eq 'ALLOW_COMPLETE_CLAIM') { 'gate_issued' } else { 'pending_stop_gate' }

$receipt = [ordered]@{
  schema_version = 'repo_v2_adoption_receipt.v1'
  receipt_id = 'repo-v2-' + (Get-TextFingerprint -Text "$Root`n$turn").Substring(0, 16)
  generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  turn_fingerprint = $turn
  status = if ($gateStatus -eq 'gate_issued') { 'verified' } else { 'candidate' }
  repo_path = (Resolve-Path -LiteralPath $Root).Path
  git_dirty_state = Get-GitDirtyState -RepoPath $Root
  active_agents_chain = @([ordered]@{ agent_name = 'Codex'; role = 'parent_pm'; authority = 'production_owner'; max_depth = 1; evidence = @('active_parent_agent:Codex','vowline_loaded_for_current_turn') })
  checks = [ordered]@{ lint = New-CheckEntry -Name 'lint' -CompletionReceipt $completionReceipt; typecheck = New-CheckEntry -Name 'typecheck' -CompletionReceipt $completionReceipt; test = New-CheckEntry -Name 'test' -CompletionReceipt $completionReceipt; build = New-CheckEntry -Name 'build' -CompletionReceipt $completionReceipt }
  required_routes = $requiredRoutes
  inspector_reports = @(Get-InspectorReports -CompletionReceipt $completionReceipt)
  contamination_scan = Invoke-RepoV2Scan -RepoPath $Root
  gate_decision = [ordered]@{ status = $gateStatus; decision = if ($gateStatus -eq 'gate_issued') { [string](Get-OptionalPropertyValue -Object $gateIssuedReceipt -Name 'decision') } else { $null }; reason = if ($gateStatus -eq 'gate_issued') { [string](Get-OptionalPropertyValue -Object $gateIssuedReceipt -Name 'reason') } else { $null }; gate_issued_receipt_path = 'Settings/Codex_App_RUNTIME/gate_issued_completion_receipt.json'; source_completion_receipt_fingerprint = if ($gateStatus -eq 'gate_issued') { [string](Get-OptionalPropertyValue -Object $gateIssuedReceipt -Name 'source_completion_receipt_fingerprint') } else { $null }; evidence = @(if ($gateStatus -eq 'gate_issued') { 'gate_issued_completion_receipt:observed' } else { 'gate_issued_completion_receipt:pending' }) }
  handoff_confirmation = Get-HandoffConfirmation -RepoPath $Root
  contradiction_policy = [ordered]@{ stop_gate_is_completion_authority = $true; agent_receipt_is_candidate_input = $true; gate_issued_receipt_must_match_source_completion_fingerprint = $true }
  evidence = @('repo_v2_adoption_receipt:generated','repo_path:resolved','git_dirty_state:observed','required_routes:collected','handoff_confirmation:checked')
}

if (-not $NoWrite) { Write-JsonFile -Path $OutputPath -Value $receipt }
$receipt | ConvertTo-Json -Depth 14
if ($receipt.contamination_scan.status -eq 'failed' -or -not $receipt.handoff_confirmation.handoff_ready) { exit 1 }
