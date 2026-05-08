param(
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}

$runtime = Join-Path $Root 'Settings\Codex_App_RUNTIME'
$activePath = Join-Path $runtime 'active_contract.json'
$receiptPath = Join-Path $runtime 'completion_receipt.json'
$hookPath = Join-Path $Root 'Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1'

function Read-TextLocal {
  param([Parameter(Mandatory = $true)][string]$Path)
  [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), $Utf8NoBom)
}

function Write-TextLocal {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Text
  )
  [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Write-JsonLocal {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  [System.IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 18) + [Environment]::NewLine), $Utf8NoBom)
}

function New-HashRecord {
  param([Parameter(Mandatory = $true)][string]$Path)
  $item = Get-Item -LiteralPath $Path
  [ordered]@{
    path = $item.FullName
    sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    last_write_utc = $item.LastWriteTimeUtc.ToString('o')
  }
}

$activeOriginal = Read-TextLocal -Path $activePath
$receiptOriginal = Read-TextLocal -Path $receiptPath

try {
  $turn = 'negative-live-stop-required-worker-not-spawned-20260508'
  $now = (Get-Date).ToUniversalTime().ToString('o')
  $task = [ordered]@{
    schema_version = 'task_classification_receipt.v1'
    task_id = $turn
    turn_fingerprint = $turn
    generated_at_utc = $now
    user_goal = 'Controlled negative live Stop proof: worker required and no worker spawn exists.'
    selected_class = 'Class 2'
    why_not_basic = @('worker_required_fixture')
    required_routes = @()
    required_worker_routes = @('control_plane_worker')
    required_inspector_routes = @()
    required_subagents = @()
    required_skills = @()
    completion_authority = [ordered]@{ source = 'gate_issued_receipt_only' }
  }
  $need = [ordered]@{
    schema_version = 'need_resolution_receipt.v1'
    generated_at_utc = $now
    turn_fingerprint = $turn
    task_id = $turn
    task_class = 'Class 2'
    requirements = @([ordered]@{
      route_id = 'control_plane_worker'
      requirement_id = 'control_plane_worker'
      type = 'worker'
      need_level = 'REQUIRED'
      status = 'pending'
      evidence = @()
    })
    required_routes = @()
    required_worker_routes = @('control_plane_worker')
    required_inspector_routes = @()
    required_subagents = @()
    required_skills = @()
    unknown_need = $false
    completion_authority = [ordered]@{ source = 'gate_issued_receipt_only' }
  }
  $active = [ordered]@{
    user_goal = $task.user_goal
    scope = @($Root)
    forbidden_surfaces = @()
    active_instructions = @('negative_stop_proof')
    oracle = $task.user_goal
    completion_criteria = @('worker route must be spawned')
    output_language = 'ko-KR-polite'
    state = 'verified_complete'
    completion_state = 'verified_complete'
    turn_fingerprint = $turn
  }
  $receipt = [ordered]@{
    schema_version = 'completion_receipt.v2'
    completion_state = 'verified_complete'
    oracle_matched = $true
    scope_matched = $true
    protected_surface_touched = $false
    blockers = @()
    turn_fingerprint = $turn
    source_receipt_is_candidate_only = $true
    task_classification_receipt = $task
    need_resolution_receipt = $need
    freshness = [ordered]@{
      attempt_id = $turn
      affected_paths = @((Resolve-Path -LiteralPath $hookPath).Path)
      validation_timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
      artifact_hashes = @(New-HashRecord -Path $hookPath)
    }
    evidence = @('direct_evidence:negative_live_stop_fixture')
  }

  Write-JsonLocal -Path $activePath -Value $active
  Write-JsonLocal -Path $receiptPath -Value $receipt

  $payload = @{
    last_assistant_message = '완료했습니다'
    completion_state = 'verified_complete'
    cwd = $Root
  } | ConvertTo-Json -Compress
  $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $hookPath -HookName stop_checks -CompletionState verified_complete -PayloadJson $payload -DryRun
  $decision = ($raw | ConvertFrom-Json).decision
  [ordered]@{
    schema_version = 'negative_live_stop_precedence_proof.v1'
    expected_reason = 'required_worker_not_spawned'
    actual_reason = [string]$decision.reason
    actual_decision = [string]$decision.decision
    passed = ([string]$decision.reason -eq 'required_worker_not_spawned')
  } | ConvertTo-Json -Depth 6
} finally {
  Write-TextLocal -Path $activePath -Text $activeOriginal
  Write-TextLocal -Path $receiptPath -Text $receiptOriginal
}
