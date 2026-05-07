[CmdletBinding()]
param(
  [string]$Root = '',
  [string[]]$ExternalRepos = @(),
  [string]$OutputPath = '',
  [switch]$AsObject
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Resolve-Path (Join-Path $scriptRoot '../../..')).Path
}

if ($ExternalRepos.Count -eq 0) {
  $devProductRoot = 'C:\Users\anise\code\Dev-Product'
  $noticeRepoName = -join @(
    [char]0xC785, [char]0xC2E4, [char]0xD1F4, [char]0xC2E4, [char]0x20,
    [char]0xC548, [char]0xB0B4, [char]0xBB38, [char]0x20,
    [char]0xC0DD, [char]0xC131, [char]0xAE30
  )
  $ExternalRepos = @(
    (Join-Path $devProductRoot $noticeRepoName),
    (Join-Path $devProductRoot 'reservation-system')
  )
}

function Convert-ToUnixPath {
  param([Parameter(Mandatory = $true)][string]$PathText)
  ([string]$PathText).Replace('\', '/') -replace '/+', '/'
}

function Get-RelativePathSafe {
  param(
    [Parameter(Mandatory = $true)][string]$Base,
    [Parameter(Mandatory = $true)][string]$PathText
  )

  try {
    [System.IO.Path]::GetRelativePath($Base, $PathText)
  } catch {
    $PathText
  }
}

function Get-GitStatusEntries {
  param([Parameter(Mandatory = $true)][string]$Repo)

  if (-not (Test-Path -LiteralPath $Repo)) {
    return @([ordered]@{
      repository = $Repo
      status = 'missing'
      path = ''
      source = 'external_repo'
    })
  }

  $gitDir = Join-Path $Repo '.git'
  if (-not (Test-Path -LiteralPath $gitDir)) {
    return @([ordered]@{
      repository = $Repo
      status = 'not_git_repository'
      path = ''
      source = 'external_repo'
    })
  }

  $lines = & git -C $Repo status --porcelain=v1 -uall 2>$null
  if ($LASTEXITCODE -ne 0) {
    return @([ordered]@{
      repository = $Repo
      status = 'git_status_failed'
      path = ''
      source = 'external_repo'
    })
  }

  foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $status = $line.Substring(0, [Math]::Min(2, $line.Length)).Trim()
    $path = if ($line.Length -gt 3) { $line.Substring(3).Trim() } else { '' }
    if ($path.Contains(' -> ')) {
      $path = ($path -split ' -> ')[-1]
    }
    [ordered]@{
      repository = $Repo
      status = $status
      path = $path
      source = 'external_repo'
    }
  }
}

function Get-SsotEntries {
  param([Parameter(Mandatory = $true)][string]$Root)

  $paths = @()
  foreach ($relative in @(
    'Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1',
    'Maintenance/vibe-coding-contamination-bench.ps1'
  )) {
    $full = Join-Path $Root $relative
    if (Test-Path -LiteralPath $full) {
      $paths += $full
    }
  }

  $patchBenchRoot = Join-Path $Root 'Maintenance/patch-bench'
  if (Test-Path -LiteralPath $patchBenchRoot) {
    $paths += Get-ChildItem -LiteralPath $patchBenchRoot -Recurse -File | Where-Object {
      $relative = Convert-ToUnixPath -PathText (Get-RelativePathSafe -Base $Root -PathText $_.FullName)
      $relative -notmatch '^Maintenance/patch-bench/reports/' -and
        $relative -notmatch '^Maintenance/patch-bench/tooling/node_modules/' -and
        $relative -notmatch '^Maintenance/patch-bench/tooling/coverage/' -and
        $relative -notmatch '^Maintenance/patch-bench/tooling/generated/'
    } | ForEach-Object { $_.FullName }
  }

  foreach ($path in ($paths | Sort-Object -Unique)) {
    [ordered]@{
      repository = $Root
      status = 'bench_surface'
      path = (Get-RelativePathSafe -Base $Root -PathText $path)
      source = 'ssot'
    }
  }
}

function Get-ImpactClasses {
  param([Parameter(Mandatory = $true)][string]$PathText)

  $path = (Convert-ToUnixPath -PathText $PathText).ToLowerInvariant()
  $classes = New-Object System.Collections.Generic.List[string]

  if ($path -match '(^|/)(settings/dev_codex_hooks|settings/codex_app_declarative|runtime/|maintenance/patch-bench/config|maintenance/patch-bench/scripts)') {
    $classes.Add('control_plane_or_gate_tooling')
  }
  if ($path -match '(^|/)(src|app|apps|frontend|ui|components)/' -or $path -match '\.(tsx|jsx|svelte|css|scss|html)$') {
    $classes.Add('frontend_surface')
  }
  if ($path -match '\.(ts|js|mjs|cjs|py|ps1|go|rs|java|cs)$') {
    $classes.Add('backend_or_logic_surface')
  }
  if ($path -match '(^|/)(test|tests|spec|__tests__)/' -or $path -match '\.(test|spec)\.(ts|js|tsx|jsx)$') {
    $classes.Add('test_surface')
  }
  if ($path -match '\.(md|mdx|txt|rst)$') {
    $classes.Add('documentation_surface')
  }
  if ($path -match '(^|/)(\.env|\.ssh|auth|credential|token|secret|key)(/|\.|$)') {
    $classes.Add('private_surface_risk')
  }
  if ($classes.Count -eq 0) {
    $classes.Add('other_surface')
  }

  @($classes | Sort-Object -Unique)
}

function Get-RequiredGateFamilies {
  param([Parameter(Mandatory = $true)][string[]]$Classes)

  $gates = New-Object System.Collections.Generic.List[string]
  $gates.Add('definition_of_done')
  $gates.Add('event_ledger')

  if ($Classes -contains 'control_plane_or_gate_tooling') {
    $gates.Add('policy_config_validator')
    $gates.Add('local_gate_script')
    $gates.Add('powershell_ast')
  }
  if ($Classes -contains 'frontend_surface') {
    $gates.Add('test_runner')
    $gates.Add('lint')
    $gates.Add('typecheck')
    $gates.Add('semgrep')
  }
  if ($Classes -contains 'backend_or_logic_surface') {
    $gates.Add('test_runner')
    $gates.Add('typecheck')
    $gates.Add('semgrep')
  }
  if ($Classes -contains 'test_surface') {
    $gates.Add('test_runner')
    $gates.Add('coverage_tool')
  }
  if ($Classes -contains 'private_surface_risk') {
    $gates.Add('secret_scanner')
  }
  if ($Classes -contains 'documentation_surface') {
    $gates.Add('change_impact_analysis')
  }

  @($gates | Sort-Object -Unique)
}

$entries = @()
$entries += Get-SsotEntries -Root $Root
foreach ($repo in $ExternalRepos) {
  $entries += Get-GitStatusEntries -Repo $repo
}

$classified = foreach ($entry in $entries) {
  $classes = if ([string]::IsNullOrWhiteSpace($entry.path)) {
    @('repository_state')
  } else {
    Get-ImpactClasses -PathText $entry.path
  }
  [ordered]@{
    repository = $entry.repository
    source = $entry.source
    status = $entry.status
    path = $entry.path
    impact_classes = @($classes)
    required_gate_families = @(Get-RequiredGateFamilies -Classes $classes)
  }
}

$allClasses = @($classified | ForEach-Object { $_.impact_classes } | Sort-Object -Unique)
$allGateFamilies = @($classified | ForEach-Object { $_.required_gate_families } | Sort-Object -Unique)

$result = [ordered]@{
  schema_version = 'patch_bench.change_impact.v1'
  generated_at = (Get-Date).ToString('o')
  root = $Root
  external_repositories = @($ExternalRepos)
  total_entries = @($classified).Count
  impact_classes = @($allClasses)
  required_gate_families = @($allGateFamilies)
  entries = @($classified)
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
  $dir = Split-Path -Parent $OutputPath
  if (-not [string]::IsNullOrWhiteSpace($dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

if ($AsObject) {
  $result
} else {
  $result | ConvertTo-Json -Depth 12
}
