param(
  [string]$Root = '',
  [string]$ProductRoot = '',
  [string]$OutputPath = '',
  [switch]$NoWrite,
  [switch]$SkipTypecheck
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($ProductRoot)) {
  $devProductRoot = Join-Path $HOME 'code\Dev-Product'
  $matchedProductRoot = ''
  if (Test-Path -LiteralPath $devProductRoot -PathType Container) {
    foreach ($candidate in @(Get-ChildItem -LiteralPath $devProductRoot -Directory -ErrorAction SilentlyContinue)) {
      $packagePath = Join-Path $candidate.FullName 'package.json'
      if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { continue }
      $packageText = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $packagePath), $utf8NoBom)
      if ($packageText -match '"name"\s*:\s*"checkin-checkout-notice-extension"') {
        $matchedProductRoot = $candidate.FullName
        break
      }
    }
  }
  if ([string]::IsNullOrWhiteSpace($matchedProductRoot)) {
    throw 'Unable to locate Dev-Product package named checkin-checkout-notice-extension.'
  }
  $ProductRoot = $matchedProductRoot
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $Root 'Settings\Codex_App_RUNTIME\dev_product_repo_adoption_receipt.json'
}

function Read-OptionalJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path), $utf8NoBom) | ConvertFrom-Json } catch { $null }
}

function Read-JsonlFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  $items = @()
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $items }
  foreach ($line in [System.IO.File]::ReadLines((Resolve-Path -LiteralPath $Path), $utf8NoBom)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $items += ($line | ConvertFrom-Json) } catch { }
  }
  $items
}

function Write-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
  }
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

function Get-OptionalPropertyValue {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
  $null
}

function Convert-ToGuardPathText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
  ([string]$Text).ToLowerInvariant().Replace('\', '/') -replace '/+', '/'
}

function Get-GitDirtyState {
  param([Parameter(Mandatory = $true)][string]$RepoPath)
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    return [ordered]@{ available = $false; is_git_repo = $false; branch = $null; dirty = $null; status_short_count = $null; evidence = @('git_command_unavailable') }
  }
  $inside = (& git -C $RepoPath rev-parse --is-inside-work-tree 2>$null)
  if ($LASTEXITCODE -ne 0 -or [string]$inside -ne 'true') {
    return [ordered]@{ available = $true; is_git_repo = $false; branch = $null; dirty = $null; status_short_count = 0; evidence = @('git_worktree:not_detected') }
  }
  $branch = (& git -C $RepoPath branch --show-current 2>$null)
  $status = @(& git -C $RepoPath status --short 2>$null)
  [ordered]@{
    available = $true
    is_git_repo = $true
    branch = [string]$branch
    dirty = ($status.Count -gt 0)
    status_short_count = $status.Count
    evidence = @('git_rev_parse:is_inside_work_tree', "git_status_short_count:$($status.Count)")
  }
}

function Get-AgentsChain {
  param([Parameter(Mandatory = $true)][string]$RepoPath)
  $sources = @()
  foreach ($name in @('agents.md', 'AGENTS.md')) {
    $path = Join-Path $RepoPath $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $sources += [ordered]@{
        path = (Resolve-Path -LiteralPath $path).Path
        casing = $name
        sha256 = Get-TextFingerprint -Text ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $path), $utf8NoBom))
      }
    }
  }
  $sources
}

function Get-PackageScripts {
  param([Parameter(Mandatory = $true)][string]$RepoPath)
  $packagePath = Join-Path $RepoPath 'package.json'
  $package = Read-OptionalJsonFile -Path $packagePath
  if (-not $package) { return [ordered]@{ package_json = $packagePath; present = $false; scripts = @{} } }
  [ordered]@{
    package_json = (Resolve-Path -LiteralPath $packagePath).Path
    present = $true
    name = [string](Get-OptionalPropertyValue -Object $package -Name 'name')
    scripts = Get-OptionalPropertyValue -Object $package -Name 'scripts'
  }
}

function Invoke-TypecheckProbe {
  param([Parameter(Mandatory = $true)][string]$RepoPath)
  if ($SkipTypecheck) {
    return [ordered]@{ status = 'skipped'; command = 'npm run typecheck'; exit_code = $null; stdout_tail = @(); evidence = @('typecheck_probe:skipped_by_parameter') }
  }
  $previous = (Get-Location).Path
  try {
    Set-Location -LiteralPath $RepoPath
    $output = @(& npm run typecheck 2>&1)
    $exit = $LASTEXITCODE
    [ordered]@{
      status = if ($exit -eq 0) { 'passed' } else { 'failed' }
      command = 'npm run typecheck'
      exit_code = $exit
      stdout_tail = @($output | Select-Object -Last 12 | ForEach-Object { [string]$_ })
      evidence = @("typecheck_exit_code:$exit")
    }
  } finally {
    Set-Location -LiteralPath $previous
  }
}

$rootResolved = (Resolve-Path -LiteralPath $Root).Path
$productResolved = (Resolve-Path -LiteralPath $ProductRoot).Path
$rootKey = (Convert-ToGuardPathText -Text $rootResolved).TrimEnd('/')
$productKey = (Convert-ToGuardPathText -Text $productResolved).TrimEnd('/')

$runtimeDir = Join-Path $rootResolved 'Settings\Codex_App_RUNTIME'
$identityPath = Join-Path $runtimeDir 'runtime_identity_receipts.jsonl'
$probePath = Join-Path $runtimeDir 'hook_surface_probe.jsonl'
$gatePath = Join-Path $runtimeDir 'gate_issued_completion_receipt.json'

$identityRecords = @(Read-JsonlFile -Path $identityPath)
$productIdentity = @($identityRecords | Where-Object {
  (Convert-ToGuardPathText -Text ([string](Get-OptionalPropertyValue -Object $_ -Name 'project_root'))).TrimEnd('/') -eq $productKey -and
  [string](Get-OptionalPropertyValue -Object $_ -Name 'hook_event') -eq 'SessionStart' -and
  [string](Get-OptionalPropertyValue -Object $_ -Name 'surface') -eq 'windows_app'
} | Sort-Object { [datetime]([string](Get-OptionalPropertyValue -Object $_ -Name 'timestamp_utc')) } -Descending | Select-Object -First 1)

$probeRecords = @(Read-JsonlFile -Path $probePath)
$productProbe = @($probeRecords | Where-Object {
  (Convert-ToGuardPathText -Text ([string](Get-OptionalPropertyValue -Object $_ -Name 'project_root'))).TrimEnd('/') -eq $productKey -and
  [string](Get-OptionalPropertyValue -Object $_ -Name 'hook_event') -eq 'SessionStart' -and
  [string](Get-OptionalPropertyValue -Object $_ -Name 'surface') -eq 'windows_app'
} | Sort-Object { [datetime]([string](Get-OptionalPropertyValue -Object $_ -Name 'timestamp_utc')) } -Descending | Select-Object -First 1)

$gateReceipt = Read-OptionalJsonFile -Path $gatePath
$typecheck = Invoke-TypecheckProbe -RepoPath $productResolved
$gitState = Get-GitDirtyState -RepoPath $productResolved
$agentsChain = @(Get-AgentsChain -RepoPath $productResolved)
$packageScripts = Get-PackageScripts -RepoPath $productResolved

$identityOk = (
  $productIdentity.Count -gt 0 -and
  [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'project_kind') -eq 'product_repo' -and
  [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'trust_state') -eq 'trusted' -and
  [bool](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'user_hooks_loaded') -eq $true -and
  (Convert-ToGuardPathText -Text ([string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'ssot_root'))).TrimEnd('/') -eq $rootKey
)
$probeOk = ($productProbe.Count -gt 0 -and [string](Get-OptionalPropertyValue -Object $productProbe[0] -Name 'decision') -eq 'ALLOW')
$gateOk = ($gateReceipt -and [string](Get-OptionalPropertyValue -Object $gateReceipt -Name 'state') -eq 'verified_complete' -and [string](Get-OptionalPropertyValue -Object $gateReceipt -Name 'decision') -eq 'ALLOW_COMPLETE_CLAIM')
$typecheckOk = ($SkipTypecheck -or [string]$typecheck.status -eq 'passed')
$status = if ($identityOk -and $probeOk -and $gitState.is_git_repo -and $gateOk -and $typecheckOk) { 'verified' } else { 'blocked' }

$receipt = [ordered]@{
  schema_version = 'dev_product_repo_adoption_receipt.v1'
  receipt_id = 'dev-product-' + (Get-TextFingerprint -Text "$productResolved`n$($productIdentity[0].receipt_id)`n$($productProbe[0].event_id)").Substring(0, 16)
  generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  status = $status
  ssot_root = $rootResolved
  product_repo = [ordered]@{
    path = $productResolved
    project_root_expected = $productResolved
    project_root_from_app_session = if ($productIdentity.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'project_root') } else { $null }
    project_kind = if ($productIdentity.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'project_kind') } else { $null }
    trust_state = if ($productIdentity.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'trust_state') } else { $null }
  }
  app_session_marker = [ordered]@{
    status = if ($identityOk) { 'observed' } else { 'missing_or_invalid' }
    runtime_identity_receipt_path = $identityPath
    receipt_id = if ($productIdentity.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'receipt_id') } else { $null }
    thread_id = if ($productIdentity.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'thread_id') } else { $null }
    hook_event = if ($productIdentity.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'hook_event') } else { $null }
    surface = if ($productIdentity.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'surface') } else { $null }
    timestamp_utc = if ($productIdentity.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'timestamp_utc') } else { $null }
    user_hooks_loaded = if ($productIdentity.Count -gt 0) { [bool](Get-OptionalPropertyValue -Object $productIdentity[0] -Name 'user_hooks_loaded') } else { $false }
  }
  hook_surface_probe = [ordered]@{
    status = if ($probeOk) { 'observed' } else { 'missing_or_invalid' }
    path = $probePath
    event_id = if ($productProbe.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productProbe[0] -Name 'event_id') } else { $null }
    decision = if ($productProbe.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productProbe[0] -Name 'decision') } else { $null }
    reason = if ($productProbe.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productProbe[0] -Name 'reason') } else { $null }
    timestamp_utc = if ($productProbe.Count -gt 0) { [string](Get-OptionalPropertyValue -Object $productProbe[0] -Name 'timestamp_utc') } else { $null }
  }
  active_agents_chain = $agentsChain
  git_dirty_state = $gitState
  package_scripts = $packageScripts
  checks = [ordered]@{
    typecheck = $typecheck
    build = [ordered]@{ status = 'not_run'; command = 'npm run build'; reason = 'build writes dist/manifest and is not required for repo adoption proof'; evidence = @('build_probe:not_run_to_avoid_product_artifact_mutation') }
    test = [ordered]@{ status = 'not_run'; command = 'npm test'; reason = 'runtime adoption proof is hook/project-root linkage; product behavior tests were not in scope'; evidence = @('product_tests:not_authority_for_ssot_runtime_adoption') }
  }
  gate_issued_receipt = [ordered]@{
    status = if ($gateOk) { 'observed' } else { 'missing_or_invalid' }
    path = $gatePath
    state = if ($gateReceipt) { [string](Get-OptionalPropertyValue -Object $gateReceipt -Name 'state') } else { $null }
    decision = if ($gateReceipt) { [string](Get-OptionalPropertyValue -Object $gateReceipt -Name 'decision') } else { $null }
    reason = if ($gateReceipt) { [string](Get-OptionalPropertyValue -Object $gateReceipt -Name 'reason') } else { $null }
  }
  evidence = @(
    if ($identityOk) { 'product_runtime_identity_session_start:observed' } else { 'product_runtime_identity_session_start:missing_or_invalid' }
    if ($probeOk) { 'product_hook_surface_probe:observed' } else { 'product_hook_surface_probe:missing_or_invalid' }
    if ($gitState.is_git_repo) { 'product_git_root:observed' } else { 'product_git_root:missing' }
    if ($typecheckOk) { 'product_typecheck:passed_or_skipped' } else { 'product_typecheck:failed' }
    if ($gateOk) { 'ssot_gate_issued_receipt:observed' } else { 'ssot_gate_issued_receipt:missing_or_invalid' }
  )
}

if (-not $NoWrite) {
  Write-JsonFile -Path $OutputPath -Value $receipt
}

$receipt | ConvertTo-Json -Depth 14
if ($status -ne 'verified') { exit 1 }
