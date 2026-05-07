[CmdletBinding()]
param(
  [ValidateSet('ci', 'quality', 'release')]
  [string]$Gate = 'release',
  [string]$Root = '',
  [string]$ReportDir = '',
  [string[]]$ExternalRepos = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = (Resolve-Path (Join-Path $scriptRoot '../../..')).Path
}
if ([string]::IsNullOrWhiteSpace($ReportDir)) {
  $ReportDir = Join-Path (Resolve-Path (Join-Path $scriptRoot '..')).Path 'reports'
}

$devProductRoot = 'C:\Users\anise\code\Dev-Product'
if ($ExternalRepos.Count -eq 0) {
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

$localToolBin = Join-Path $env:USERPROFILE '.local/bin'
if (Test-Path -LiteralPath $localToolBin) {
  $env:Path = "$localToolBin;$env:Path"
}

function Test-CommandAvailable {
  param([Parameter(Mandatory = $true)][string]$Name)
  $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-Capture {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Script,
    [int[]]$AcceptExitCodes = @(0)
  )

  $oldExit = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
  if ($oldExit) {
    $global:LASTEXITCODE = 0
  }

  $oldPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $Script 2>&1
    $exitVar = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $exitCode = if ($exitVar -and $null -ne $exitVar.Value) { [int]$exitVar.Value } elseif ($?) { 0 } else { 1 }
    [ordered]@{
      ok = ($AcceptExitCodes -contains $exitCode)
      exit_code = $exitCode
      output = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    }
  } catch {
    [ordered]@{
      ok = $false
      exit_code = 1
      output = ($_ | Out-String).Trim()
    }
  } finally {
    $ErrorActionPreference = $oldPreference
  }
}

function New-Check {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Category,
    [Parameter(Mandatory = $true)][bool]$Required,
    [Parameter(Mandatory = $true)][string]$Status,
    [string]$Details = '',
    [string[]]$Evidence = @()
  )

  [ordered]@{
    name = $Name
    category = $Category
    required = $Required
    status = $Status
    details = $Details
    evidence = @($Evidence)
  }
}

function Add-ToolPresenceCheck {
  param(
    [System.Collections.Generic.List[object]]$Checks,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][bool]$Required,
    [string]$CommandName = $Name,
    [scriptblock]$VersionScript
  )

  if (-not (Test-CommandAvailable -Name $CommandName)) {
    $Checks.Add((New-Check -Name $Name -Category 'tool_inventory' -Required $Required -Status 'fail' -Details "$CommandName is not available"))
    return
  }

  if ($VersionScript) {
    $result = Invoke-Capture -Script $VersionScript
    $status = if ($result.ok) { 'pass' } else { 'fail' }
    $Checks.Add((New-Check -Name $Name -Category 'tool_inventory' -Required $Required -Status $status -Details $result.output))
  } else {
    $Checks.Add((New-Check -Name $Name -Category 'tool_inventory' -Required $Required -Status 'pass' -Details "$CommandName is available"))
  }
}

function ConvertTo-ShortOutput {
  param([string]$Text, [int]$Limit = 1200)
  if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
  if ($Text.Length -le $Limit) { return $Text }
  $Text.Substring(0, $Limit) + '...'
}

function Get-RepoScripts {
  param([Parameter(Mandatory = $true)][string]$Repo)

  $packageJson = Join-Path $Repo 'package.json'
  if (-not (Test-Path -LiteralPath $packageJson)) {
    return [ordered]@{
      repo = $Repo
      package_json = $false
      scripts = @()
    }
  }

  $json = Get-Content -Raw -LiteralPath $packageJson | ConvertFrom-Json
  $scripts = @()
  if ($json.scripts) {
    $json.scripts.PSObject.Properties | ForEach-Object {
      if ($_.Name -match '(verify|check|test|lint|type|build|preflight|acceptance|gate)') {
        $scripts += [ordered]@{ name = $_.Name; command = [string]$_.Value }
      }
    }
  }

  [ordered]@{
    repo = $Repo
    package_json = $true
    scripts = @($scripts)
  }
}

New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$benchRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$toolingRoot = Join-Path $benchRoot 'tooling'
$configRoot = Join-Path $benchRoot 'config'
$fixtureRoot = Join-Path $benchRoot 'fixtures'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonReportPath = Join-Path $ReportDir "patch-bench-report-$timestamp.json"
$markdownReportPath = Join-Path $ReportDir "patch-bench-report-$timestamp.md"
$gitleaksReportPath = Join-Path $ReportDir "gitleaks-smoke-$timestamp.json"
$semgrepReportPath = Join-Path $ReportDir "semgrep-smoke-$timestamp.json"
$changeImpactPath = Join-Path $ReportDir "change-impact-$timestamp.json"

$checks = [System.Collections.Generic.List[object]]::new()

Add-ToolPresenceCheck -Checks $checks -Name 'node' -CommandName 'node' -Required $true -VersionScript { node --version }
Add-ToolPresenceCheck -Checks $checks -Name 'npm' -CommandName 'npm' -Required $true -VersionScript { npm --version }
Add-ToolPresenceCheck -Checks $checks -Name 'python' -CommandName 'python' -Required $false -VersionScript { python --version }
Add-ToolPresenceCheck -Checks $checks -Name 'git' -CommandName 'git' -Required $true -VersionScript { git --version }
Add-ToolPresenceCheck -Checks $checks -Name 'semgrep' -CommandName 'semgrep' -Required $true -VersionScript { semgrep --version }
Add-ToolPresenceCheck -Checks $checks -Name 'gitleaks' -CommandName 'gitleaks' -Required $true -VersionScript { gitleaks version }
Add-ToolPresenceCheck -Checks $checks -Name 'conftest' -CommandName 'conftest' -Required $true -VersionScript { conftest --version }
Add-ToolPresenceCheck -Checks $checks -Name 'opa' -CommandName 'opa' -Required $false -VersionScript { opa version }
Add-ToolPresenceCheck -Checks $checks -Name 'pre-commit' -CommandName 'pre-commit' -Required $false -VersionScript { pre-commit --version }
Add-ToolPresenceCheck -Checks $checks -Name 'bazel' -CommandName 'bazel' -Required $true -VersionScript { bazel --version }

$astFiles = @(
  (Join-Path $Root 'Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1'),
  (Join-Path $Root 'Maintenance/vibe-coding-contamination-bench.ps1')
) + @(Get-ChildItem -LiteralPath (Join-Path $benchRoot 'scripts') -Filter '*.ps1' -File | ForEach-Object { $_.FullName })

foreach ($file in ($astFiles | Sort-Object -Unique)) {
  if (-not (Test-Path -LiteralPath $file)) {
    $checks.Add((New-Check -Name "powershell_ast:$file" -Category 'policy_config_validator' -Required $true -Status 'fail' -Details 'missing file'))
    continue
  }
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
  $status = if (@($errors).Count -eq 0) { 'pass' } else { 'fail' }
  $details = if (@($errors).Count -eq 0) { 'AST_OK' } else { (@($errors) | ForEach-Object { $_.Message }) -join '; ' }
  $checks.Add((New-Check -Name "powershell_ast:$file" -Category 'policy_config_validator' -Required $true -Status $status -Details $details -Evidence @($file)))
}

$yamlFiles = @(
  (Join-Path $configRoot 'bench-manifest.yaml'),
  (Join-Path $configRoot 'quality-gates.yaml'),
  (Join-Path $configRoot 'semgrep-rules.yaml'),
  (Join-Path $configRoot 'openapi-smoke.yaml'),
  (Join-Path $benchRoot '.pre-commit-config.yaml')
)
foreach ($file in $yamlFiles) {
  if (-not (Test-Path -LiteralPath $file)) {
    $checks.Add((New-Check -Name "yaml:$file" -Category 'policy_config_validator' -Required $true -Status 'fail' -Details 'missing file'))
    continue
  }
  if (Test-CommandAvailable -Name 'yq') {
    $result = Invoke-Capture -Script { yq e '.' $file }
    $checks.Add((New-Check -Name "yaml:$file" -Category 'policy_config_validator' -Required $true -Status $(if ($result.ok) { 'pass' } else { 'fail' }) -Details (ConvertTo-ShortOutput -Text $result.output) -Evidence @($file)))
  } else {
    $checks.Add((New-Check -Name "yaml:$file" -Category 'policy_config_validator' -Required $true -Status 'fail' -Details 'yq is not available' -Evidence @($file)))
  }
}

$jsonValidation = Invoke-Capture -Script { node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')); console.log('JSON_OK')" (Join-Path $toolingRoot 'package.json') }
$checks.Add((New-Check -Name 'json:tooling-package' -Category 'policy_config_validator' -Required $true -Status $(if ($jsonValidation.ok) { 'pass' } else { 'fail' }) -Details (ConvertTo-ShortOutput -Text $jsonValidation.output) -Evidence @((Join-Path $toolingRoot 'package.json'))))

if (Test-CommandAvailable -Name 'semgrep') {
  $semgrep = Invoke-Capture -Script { semgrep --config (Join-Path $configRoot 'semgrep-rules.yaml') $fixtureRoot --json --output $semgrepReportPath }
  $semgrepDetected = $false
  if (Test-Path -LiteralPath $semgrepReportPath) {
    try {
      $semgrepJson = Get-Content -Raw -LiteralPath $semgrepReportPath | ConvertFrom-Json
      $semgrepDetected = @($semgrepJson.results).Count -gt 0
    } catch {
      $semgrepDetected = $false
    }
  }
  if (-not $semgrepDetected -and $semgrep.output -match 'Findings:\s*[1-9]') {
    $semgrepDetected = $true
  }
  $checks.Add((New-Check -Name 'semgrep_fixture_detection' -Category 'quality_gate' -Required $true -Status $(if ($semgrep.ok -and $semgrepDetected) { 'pass' } else { 'fail' }) -Details "detected=$semgrepDetected; $(ConvertTo-ShortOutput -Text $semgrep.output)" -Evidence @($semgrepReportPath, (Join-Path $configRoot 'semgrep-rules.yaml'))))
}

if (Test-CommandAvailable -Name 'gitleaks') {
  $gitleaks = Invoke-Capture -Script { gitleaks detect --no-git --source $fixtureRoot --config (Join-Path $configRoot 'gitleaks.toml') --report-format json --report-path $gitleaksReportPath --exit-code 7 } -AcceptExitCodes @(7)
  $checks.Add((New-Check -Name 'gitleaks_fixture_detection' -Category 'quality_gate' -Required $true -Status $(if ($gitleaks.ok) { 'pass' } else { 'fail' }) -Details (ConvertTo-ShortOutput -Text $gitleaks.output) -Evidence @($gitleaksReportPath, (Join-Path $configRoot 'gitleaks.toml'))))
}

if (Test-CommandAvailable -Name 'conftest') {
  $conftest = Invoke-Capture -Script { conftest test (Join-Path $configRoot 'bench-manifest.yaml') --policy (Join-Path $configRoot 'conftest') --output json }
  $checks.Add((New-Check -Name 'conftest_policy_validator' -Category 'policy_config_validator' -Required $true -Status $(if ($conftest.ok) { 'pass' } else { 'fail' }) -Details (ConvertTo-ShortOutput -Text $conftest.output) -Evidence @((Join-Path $configRoot 'conftest/policy.rego'), (Join-Path $configRoot 'bench-manifest.yaml'))))
}

if (Test-CommandAvailable -Name 'pre-commit') {
  $preCommit = Invoke-Capture -Script { pre-commit validate-config (Join-Path $benchRoot '.pre-commit-config.yaml') }
  $checks.Add((New-Check -Name 'pre_commit_config_validator' -Category 'quality_gate' -Required $false -Status $(if ($preCommit.ok) { 'pass' } else { 'warn' }) -Details (ConvertTo-ShortOutput -Text $preCommit.output) -Evidence @((Join-Path $benchRoot '.pre-commit-config.yaml'))))
}

$npmScripts = @(
  @{ name = 'npm_test_runner'; script = 'test'; category = 'ci_gate'; required = $true },
  @{ name = 'npm_lint'; script = 'lint'; category = 'quality_gate'; required = $true },
  @{ name = 'npm_typecheck'; script = 'typecheck'; category = 'ci_gate'; required = $true },
  @{ name = 'coverage_tool'; script = 'coverage:smoke'; category = 'quality_gate'; required = $false },
  @{ name = 'openapi_schema_generator'; script = 'openapi:types'; category = 'quality_gate'; required = $false },
  @{ name = 'nx_version'; script = 'tool:nx'; category = 'ci_gate'; required = $true },
  @{ name = 'turbo_version'; script = 'tool:turbo'; category = 'ci_gate'; required = $true }
)
foreach ($item in $npmScripts) {
  $result = Invoke-Capture -Script { npm --prefix $toolingRoot run $item.script }
  $checks.Add((New-Check -Name $item.name -Category $item.category -Required ([bool]$item.required) -Status $(if ($result.ok) { 'pass' } else { 'fail' }) -Details (ConvertTo-ShortOutput -Text $result.output) -Evidence @((Join-Path $toolingRoot 'package.json'))))
}

$npmAudit = Invoke-Capture -Script { npm --prefix $toolingRoot audit --audit-level=high }
$checks.Add((New-Check -Name 'npm_audit_high' -Category 'quality_gate' -Required $true -Status $(if ($npmAudit.ok) { 'pass' } else { 'fail' }) -Details (ConvertTo-ShortOutput -Text $npmAudit.output) -Evidence @((Join-Path $toolingRoot 'package-lock.json'))))

$vibeBenchPath = Join-Path $Root 'Maintenance/vibe-coding-contamination-bench.ps1'
if (Test-Path -LiteralPath $vibeBenchPath) {
  $vibeBench = Invoke-Capture -Script { powershell -NoProfile -ExecutionPolicy Bypass -File $vibeBenchPath }
  $vibePassed = $false
  try {
    $vibeJson = $vibeBench.output | ConvertFrom-Json
    $vibePassed = ($vibeJson.failed -eq 0 -and $vibeJson.passed -eq $vibeJson.total)
  } catch {
    $vibePassed = $false
  }
  $checks.Add((New-Check -Name 'vibe_contamination_bench' -Category 'release_gate' -Required $true -Status $(if ($vibeBench.ok -and $vibePassed) { 'pass' } else { 'fail' }) -Details (ConvertTo-ShortOutput -Text $vibeBench.output) -Evidence @($vibeBenchPath)))
}

$changeImpact = Invoke-Capture -Script { powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Invoke-ChangeImpact.ps1') -Root $Root -OutputPath $changeImpactPath }
$checks.Add((New-Check -Name 'change_impact_analysis' -Category 'release_gate' -Required $true -Status $(if ($changeImpact.ok -and (Test-Path -LiteralPath $changeImpactPath)) { 'pass' } else { 'fail' }) -Details (ConvertTo-ShortOutput -Text $changeImpact.output) -Evidence @($changeImpactPath)))

$repoScripts = @()
foreach ($repo in $ExternalRepos) {
  $repoScripts += Get-RepoScripts -Repo $repo
}
$checks.Add((New-Check -Name 'external_repo_gate_script_discovery' -Category 'change_impact_analysis' -Required $true -Status 'pass' -Details 'Read-only discovery of verify/check/test/build/preflight gate scripts from individual repos.' -Evidence @($ExternalRepos)))

$requiredFailures = @($checks | Where-Object { $_.required -and $_.status -ne 'pass' })
$gateStatus = if ($requiredFailures.Count -eq 0) { 'pass' } else { 'fail' }

$result = [ordered]@{
  schema_version = 'patch_bench.report.v1'
  generated_at = (Get-Date).ToString('o')
  gate = $Gate
  status = $gateStatus
  root = $Root
  bench_root = [string]$benchRoot
  report_paths = [ordered]@{
    json = $jsonReportPath
    markdown = $markdownReportPath
    semgrep = $semgrepReportPath
    gitleaks = $gitleaksReportPath
    change_impact = $changeImpactPath
  }
  implemented_gates = [ordered]@{
    definition_of_done = 'config/quality-gates.yaml plus report completion evidence requirements'
    ci_gate = 'scripts/Invoke-LocalGate.ps1 and npm test/lint/typecheck/Nx/Turborepo checks'
    release_gate = 'scripts/Invoke-PatchBench.ps1 -Gate release with contamination bench and change impact'
    quality_gate = 'Semgrep, Gitleaks, Conftest, pre-commit config, coverage, OpenAPI type generation'
    change_impact_analysis = 'scripts/Invoke-ChangeImpact.ps1'
  }
  repo_script_basis = @($repoScripts)
  checks = @($checks)
  required_failures = @($requiredFailures)
  gpt_pro_discussion_packet = [ordered]@{
    position = 'PreToolUse remains an action-safety gate; Stop remains the completion/evidence gate; receipts are completion authority.'
    practical_evidence = 'The bench combines frontend fake data, backend static success, repo-local AGENTS authority drift, stale receipt/subagent PASS cases, and policy/config validators.'
    ask = @(
      'Review whether the fixture set reflects the user pain points from frontend/backend vibe-coding contamination.',
      'Review whether receipt freshness should include artifact hashes for every release-gate path.',
      'Review whether individual dirty repos should remain read-only evidence sources or receive per-repo gate adapters.'
    )
  }
}

$result | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $jsonReportPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Patch Bench Report")
$lines.Add("")
$lines.Add("- Generated: $($result.generated_at)")
$lines.Add("- Gate: $Gate")
$lines.Add("- Status: $gateStatus")
$lines.Add("- Root: $Root")
$lines.Add("")
$lines.Add("## Implemented Gate Map")
foreach ($property in $result.implemented_gates.GetEnumerator()) {
  $lines.Add("- $($property.Key): $($property.Value)")
}
$lines.Add("")
$lines.Add("## Required Tooling Result")
$toolChecks = @($checks | Where-Object { $_.category -eq 'tool_inventory' })
foreach ($check in $toolChecks) {
  $lines.Add("- $($check.name): $($check.status) - $($check.details)")
}
$lines.Add("")
$lines.Add("## Bench Checks")
$lines.Add("| Check | Category | Required | Status |")
$lines.Add("| --- | --- | --- | --- |")
foreach ($check in $checks) {
  $lines.Add("| $($check.name) | $($check.category) | $($check.required) | $($check.status) |")
}
$lines.Add("")
$lines.Add("## External Repo Script Basis")
foreach ($repo in $repoScripts) {
  $lines.Add("- $($repo.repo): package_json=$($repo.package_json)")
  foreach ($script in $repo.scripts) {
    $lines.Add("  - $($script.name): $($script.command)")
  }
}
$lines.Add("")
$lines.Add("## GPT Pro Discussion Packet")
$lines.Add("- Position: $($result.gpt_pro_discussion_packet.position)")
$lines.Add("- Practical evidence: $($result.gpt_pro_discussion_packet.practical_evidence)")
foreach ($ask in $result.gpt_pro_discussion_packet.ask) {
  $lines.Add("- Discussion ask: $ask")
}
$lines.Add("")
$lines.Add("## Evidence Files")
foreach ($path in $result.report_paths.GetEnumerator()) {
  $lines.Add("- $($path.Key): $($path.Value)")
}
if ($requiredFailures.Count -gt 0) {
  $lines.Add("")
  $lines.Add("## Required Failures")
  foreach ($failure in $requiredFailures) {
    $lines.Add("- $($failure.name): $($failure.details)")
  }
}

$lines | Set-Content -LiteralPath $markdownReportPath -Encoding UTF8

Write-Output ($result | ConvertTo-Json -Depth 16)
if ($gateStatus -eq 'pass') {
  exit 0
}
exit 1
