param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Assert-Condition {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Get-McpServerBlocks {
  param([string]$ConfigText)

  $servers = @()
  foreach ($match in [regex]::Matches($ConfigText, '(?ms)^\s*\[mcp_servers\.("?[^"\].\s]+"?)\]\s*(?<body>.*?)(?=^\s*\[|\z)')) {
    $servers += [ordered]@{
      name = $match.Groups[1].Value.Trim('"')
      body = $match.Groups['body'].Value
    }
  }
  @($servers)
}

function Get-TomlArrayItems {
  param(
    [string]$Body,
    [string]$Name
  )

  $match = [regex]::Match($Body, "(?m)^\s*$([regex]::Escape($Name))\s*=\s*\[(?<value>.*?)\]\s*(?:#.*)?$")
  if (-not $match.Success) {
    return @()
  }

  $items = @()
  foreach ($itemMatch in [regex]::Matches($match.Groups['value'].Value, "'(?<single>[^']*)'|""(?<double>[^""]*)""|(?<bare>[A-Za-z0-9_@./:\\-]+)")) {
    $items += if ($itemMatch.Groups['single'].Success) {
      $itemMatch.Groups['single'].Value
    } elseif ($itemMatch.Groups['double'].Success) {
      $itemMatch.Groups['double'].Value
    } else {
      $itemMatch.Groups['bare'].Value
    }
  }
  @($items)
}

function Get-LineCount {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return 0
  }
  @((Get-Content -LiteralPath $Path -ErrorAction Stop) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
}

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$configPath = Join-Path $HOME '.codex\config.toml'
$reportPath = Join-Path $rootPath 'Maintenance\reports\MCP_INTEGRATION_RESULT.latest.md'
$hookPath = Join-Path $rootPath 'Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1'
$runtimeCapabilityPath = Join-Path $rootPath 'Settings\Codex_App_RUNTIME\runtime_capability_receipt.json'
$mcpUsagePath = Join-Path $rootPath 'Settings\Codex_App_RUNTIME\mcp_tool_usage_events.jsonl'

Assert-Condition (Test-Path -LiteralPath $configPath -PathType Leaf) 'Codex config.toml is missing.'
Assert-Condition (Test-Path -LiteralPath $hookPath -PathType Leaf) 'codex-ssot-hook.ps1 is missing.'

$configText = Get-Content -LiteralPath $configPath -Raw
$servers = @(Get-McpServerBlocks -ConfigText $configText)
$serverNames = @($servers | ForEach-Object { [string]$_.name } | Sort-Object)
$expectedServers = @('context7','sequential_thinking','windows_powershell')

Assert-Condition ($serverNames.Count -eq 3) "Expected exactly three MCP server blocks; found $($serverNames.Count)."
foreach ($expected in $expectedServers) {
  Assert-Condition ($serverNames -contains $expected) "Missing MCP server block: $expected."
}
Assert-Condition ($serverNames -notcontains 'chrome-devtools') 'Disabled chrome-devtools MCP block must not remain in active MCP set.'

$context7 = $servers | Where-Object { $_.name -eq 'context7' } | Select-Object -First 1
$windows = $servers | Where-Object { $_.name -eq 'windows_powershell' } | Select-Object -First 1
$contextEnvVars = @(Get-TomlArrayItems -Body $context7.body -Name 'env_vars')
$windowsEnabledTools = @(Get-TomlArrayItems -Body $windows.body -Name 'enabled_tools')
$windowsDisabledTools = @(Get-TomlArrayItems -Body $windows.body -Name 'disabled_tools')

Assert-Condition ($contextEnvVars -contains 'CONTEXT7_API_KEY') 'Context7 must reference CONTEXT7_API_KEY through env_vars.'
Assert-Condition ($configText -notmatch ('ctx7' + 'sk-')) 'A Context7 secret literal was written to config.toml.'
Assert-Condition (($windowsEnabledTools.Count -eq 1) -and ($windowsEnabledTools[0] -eq 'Show-TextFiles')) 'Windows PowerShell MCP must expose only the read-only Show-TextFiles tool.'
foreach ($tool in @('Add-LinesToFile','Update-LinesInFile','Update-MatchInFile','Remove-LinesFromFile','Stop-AllPwsh')) {
  Assert-Condition ($windowsDisabledTools -contains $tool) "Windows PowerShell MCP missing disabled mutating tool: $tool."
}

$secretPattern = 'ctx7' + 'sk-'
$secretHitFiles = @(& git -C $rootPath grep -l $secretPattern -- . 2>$null)
Assert-Condition ($secretHitFiles.Count -eq 0) 'A Context7 secret-like literal was found in tracked repository content.'

$usageCountBefore = Get-LineCount -Path $mcpUsagePath
$payload = @{ workdir = $rootPath } | ConvertTo-Json -Compress
& $hookPath -HookName session_start -PayloadJson $payload | Out-Null
$usageCountAfter = Get-LineCount -Path $mcpUsagePath
Assert-Condition ($usageCountAfter -eq $usageCountBefore) 'Config-only session_start must not write mcp_tool_usage_event evidence.'

$runtimeCapability = Get-Content -LiteralPath $runtimeCapabilityPath -Raw | ConvertFrom-Json
$runtimeServers = @(if ($runtimeCapability.mcp_servers) { $runtimeCapability.mcp_servers } else { $runtimeCapability.available_mcp_servers })
Assert-Condition ($runtimeServers.Count -eq 3) "Runtime capability receipt must list three MCP servers; found $($runtimeServers.Count)."
foreach ($expected in $expectedServers) {
  $entry = $runtimeServers | Where-Object { $_.name -eq $expected } | Select-Object -First 1
  Assert-Condition ($null -ne $entry) "Runtime capability receipt missing MCP server: $expected."
  Assert-Condition ($entry.configured_is_not_usage_evidence -eq $true) "Runtime capability must mark $expected as not usage evidence."
  Assert-Condition ([string]$entry.result_authority -eq 'candidate_evidence_only') "Runtime capability must mark $expected result authority as candidate only."
}

$contextRuntime = $runtimeServers | Where-Object { $_.name -eq 'context7' } | Select-Object -First 1
$sequentialRuntime = $runtimeServers | Where-Object { $_.name -eq 'sequential_thinking' } | Select-Object -First 1
$windowsRuntime = $runtimeServers | Where-Object { $_.name -eq 'windows_powershell' } | Select-Object -First 1
Assert-Condition ([string]$sequentialRuntime.status -eq 'available') 'Sequential Thinking MCP command must be available.'
Assert-Condition ([string]$windowsRuntime.status -eq 'available') 'Windows PowerShell MCP proxy must be available.'
Assert-Condition ([string]$contextRuntime.status -in @('available','configured_missing_env')) 'Context7 MCP must be command-available, with only env readiness allowed to vary.'

$timestamp = (Get-Date).ToUniversalTime().ToString('o')
$contextStatus = [string]$contextRuntime.status
$lines = @(
  '# MCP Integration Runtime Proof',
  '',
  "generated_at_utc: $timestamp",
  'status: PASS',
  '',
  '## Evidence',
  '',
  '- config.toml has exactly three active MCP server blocks: context7, sequential_thinking, windows_powershell.',
  '- Context7 uses env_vars = ["CONTEXT7_API_KEY"]; no literal Context7 secret was written to config or tracked repo content.',
  '- Windows PowerShell MCP is installed and limited to Show-TextFiles; mutating tools are disabled in config.',
  '- runtime_capability_receipt.json lists all three MCP servers and marks configuration as not usage evidence.',
  "- Context7 runtime status: $contextStatus.",
  '- session_start did not write mcp_tool_usage_events.jsonl; MCP usage evidence is only written from actual post_tool_use observations.',
  '- MCP outputs remain candidate_evidence_only and do not replace worker/inspector spawn, report, PM decision, Stop, or gate-issued receipt.'
)

$reportDir = Split-Path -Parent $reportPath
if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
  $null = New-Item -ItemType Directory -Path $reportDir -Force
}
Set-Content -LiteralPath $reportPath -Value $lines -Encoding utf8

[ordered]@{
  status = 'PASS'
  report = $reportPath
  runtime_mcp_servers = @($runtimeServers | ForEach-Object { [ordered]@{ name = $_.name; status = $_.status; authority = $_.result_authority } })
  mcp_usage_events_unchanged_by_config_only = $true
} | ConvertTo-Json -Depth 6
