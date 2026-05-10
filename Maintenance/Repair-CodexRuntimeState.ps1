[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$WaitForCodexExit,
    [int]$WaitTimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

$CodexRoot = Split-Path -Parent $PSScriptRoot
$ArchiveRoot = Join-Path $CodexRoot 'archived_runtime_state'
$ReportRoot = Join-Path $PSScriptRoot 'reports'
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunArchiveRoot = Join-Path $ArchiveRoot "runtime-repair-$Timestamp"

$UnwantedConnectorNamespaces = @(
    'mcp__codex_apps__supabase',
    'mcp__codex_apps__hugging_face'
)
$DefaultUnexpectedAppConnectors = @(
    'Supabase',
    'Hugging Face'
)
$DefaultExpectedAppConnectors = @(
    'GitHub'
)
$DefaultForbiddenActiveSourceFragments = @(
    '\.tmp\',
    '\tmp\',
    '\archived_sessions\',
    '\vendor_imports\',
    '\bundled-marketplaces\',
    '\plugins\plugins\',
    '\wshobson-agents-scan\',
    '\quarantine\',
    '\quarantined\',
    '\Maintenance\upstream\'
)
$DefaultRuntimeTransientRootNames = @(
    '.tmp',
    'tmp',
    'vendor_imports'
)

function Get-CodexProcesses {
    @(Get-Process -Name Codex -ErrorAction SilentlyContinue)
}

function Wait-CodexExitIfRequested {
    if (-not $WaitForCodexExit) {
        return
    }

    $deadline = (Get-Date).AddSeconds($WaitTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-CodexProcesses).Count -eq 0) {
            return
        }
        Start-Sleep -Seconds 2
    }

    throw "Codex is still running after waiting $WaitTimeoutSeconds seconds."
}

function New-RelativeArchivePath {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Base
    )

    $sourceFull = [System.IO.Path]::GetFullPath($Source)
    $baseFull = [System.IO.Path]::GetFullPath($Base).TrimEnd('\') + '\'
    if (-not $sourceFull.StartsWith($baseFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to archive path outside expected base: $Source"
    }

    $relative = $sourceFull.Substring($baseFull.Length)
    return Join-Path $RunArchiveRoot $relative
}

function Move-ToArchive {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Actions
    )

    $destination = New-RelativeArchivePath -Source $Path -Base $Base
    $destinationParent = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
    Move-Item -LiteralPath $Path -Destination $destination
    $Actions.Add([pscustomobject]@{
        action = 'archived'
        source = $Path
        destination = $destination
    })
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Test-TomlParse {
    $configPath = Join-Path $CodexRoot 'config.toml'
    $script = @"
import pathlib, tomllib
p = pathlib.Path(r'''$configPath''')
tomllib.loads(p.read_text(encoding='utf-8'))
print('ok')
"@
    $result = $script | python -
    return (($result -join "`n").Trim() -eq 'ok')
}

function Read-CodexConfigState {
    $configPath = Join-Path $CodexRoot 'config.toml'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    $script = @"
import json, pathlib, tomllib
p = pathlib.Path(r'''$configPath''')
data = tomllib.loads(p.read_text(encoding='utf-8-sig'))
maintenance = data.get('maintenance') or {}
policy = maintenance.get('contamination_prevention') or {}
naming = maintenance.get('naming_convention') or {}
marketplaces = data.get('marketplaces') or {}
sources = []
for name, value in sorted(marketplaces.items()):
    if isinstance(value, dict) and value.get('source'):
        sources.append({'id': name, 'source': str(value.get('source'))})
print(json.dumps({
    'policy_present': bool(policy),
    'policy': policy,
    'naming_policy_present': bool(naming),
    'naming_policy': naming,
    'marketplace_sources': sources,
}, ensure_ascii=False))
"@
    $result = ($script | python -) -join "`n"
    if (-not $result.Trim()) {
        return $null
    }
    return $result | ConvertFrom-Json
}

function Test-PathUnderAnyRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Roots
    )

    if ($Roots.Count -eq 0) {
        return $true
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($root in $Roots) {
        $fullRoot = [System.IO.Path]::GetFullPath([string]$root).TrimEnd('\')
        if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith($fullRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Test-PathHasFragment {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Fragments
    )

    $normalizedPath = $Path.Replace('/', '\').ToLowerInvariant()
    foreach ($fragment in $Fragments) {
        if ($normalizedPath.Contains(([string]$fragment).Replace('/', '\').ToLowerInvariant())) {
            return $true
        }
    }
    return $false
}

function Get-PolicyArray {
    param(
        $Policy,
        [Parameter(Mandatory)][string]$PropertyName,
        [object[]]$Default = @()
    )

    if ($null -ne $Policy -and $Policy.PSObject.Properties.Name -contains $PropertyName) {
        return @($Policy.$PropertyName)
    }
    return @($Default)
}

function Get-EarliestProcessStartTime {
    param([object[]]$Processes)

    $starts = @()
    foreach ($process in @($Processes)) {
        try {
            if ($null -ne $process.StartTime) {
                $starts += $process.StartTime
            }
        } catch {
            continue
        }
    }

    if ($starts.Count -eq 0) {
        return $null
    }
    return @($starts | Sort-Object)[0]
}

function Get-DirectoryStats {
    param([Parameter(Mandatory)][string]$Path)

    $fileCount = 0
    $directoryCount = 0
    [int64]$bytes = 0

    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue) {
        if ($item.PSIsContainer) {
            $directoryCount += 1
            continue
        }

        $fileCount += 1
        $bytes += [int64]$item.Length
    }

    return [pscustomobject]@{
        file_count = $fileCount
        directory_count = $directoryCount
        bytes = $bytes
        mb = [math]::Round($bytes / 1MB, 2)
    }
}

function Add-RuntimeTransientRootFindings {
    param(
        [Parameter(Mandatory)][string[]]$RootNames,
        $Policy,
        $EarliestCodexStartTime,
        [bool]$CodexRunning,
        [bool]$Apply,
        [System.Collections.Generic.List[object]]$Findings,
        [System.Collections.Generic.List[object]]$Actions
    )

    $unexpectedPluginIds = @(Get-PolicyArray -Policy $Policy -PropertyName 'unexpected_plugin_ids' -Default @())
    $unexpectedPluginIdsLower = @($unexpectedPluginIds | ForEach-Object { ([string]$_).ToLowerInvariant() })

    foreach ($rootName in @($RootNames | Sort-Object -Unique)) {
        $rootPath = Join-Path $CodexRoot $rootName
        if (-not (Test-Path -LiteralPath $rootPath)) {
            $Findings.Add([pscustomobject]@{
                surface = 'runtime_transient_root'
                root_name = $rootName
                path = $rootPath
                status = 'absent'
            })
            continue
        }

        $rootItem = Get-Item -LiteralPath $rootPath -Force
        $stats = Get-DirectoryStats -Path $rootPath
        $pluginManifestFiles = @(Get-ChildItem -LiteralPath $rootPath -Recurse -Force -File -Filter 'plugin.json' -ErrorAction SilentlyContinue)
        $marketplaceFiles = @(Get-ChildItem -LiteralPath $rootPath -Recurse -Force -File -Filter 'marketplace.json' -ErrorAction SilentlyContinue)
        $nestedGitDirs = @(Get-ChildItem -LiteralPath $rootPath -Recurse -Force -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq '.git' })
        $unexpectedPluginDirs = @()
        if ($unexpectedPluginIdsLower.Count -gt 0) {
            $unexpectedPluginDirs = @(Get-ChildItem -LiteralPath $rootPath -Recurse -Force -Directory -ErrorAction SilentlyContinue |
                Where-Object { $unexpectedPluginIdsLower -contains $_.Name.ToLowerInvariant() } |
                Select-Object -ExpandProperty FullName)
        }

        $createdDuringCurrentCodexSession = $false
        if ($CodexRunning -and $null -ne $EarliestCodexStartTime) {
            $createdDuringCurrentCodexSession = $rootItem.CreationTime -ge $EarliestCodexStartTime.AddSeconds(-10)
        }

        $status = if ($createdDuringCurrentCodexSession) {
            'runtime_generated_current_session'
        } elseif ($CodexRunning) {
            'stale_or_preexisting_runtime_root_needs_archive_after_exit'
        } else {
            'needs_archive'
        }

        $Findings.Add([pscustomobject]@{
            surface = 'runtime_transient_root'
            root_name = $rootName
            path = $rootPath
            status = $status
            creation_time = $rootItem.CreationTime.ToString('o')
            last_write_time = $rootItem.LastWriteTime.ToString('o')
            created_during_current_codex_session = $createdDuringCurrentCodexSession
            file_count = $stats.file_count
            directory_count = $stats.directory_count
            bytes = $stats.bytes
            mb = $stats.mb
            plugin_manifest_count = $pluginManifestFiles.Count
            marketplace_file_count = $marketplaceFiles.Count
            nested_git_count = $nestedGitDirs.Count
            unexpected_plugin_dir_count = $unexpectedPluginDirs.Count
            unexpected_plugin_dirs = @($unexpectedPluginDirs)
            apply_behavior = if ($CodexRunning) { 'blocked_until_codex_exits' } else { 'archive_entire_root' }
        })

        if ($Apply) {
            Move-ToArchive -Path $rootPath -Base $CodexRoot -Actions $Actions
        }
    }
}

Wait-CodexExitIfRequested

$codexProcesses = @(Get-CodexProcesses)
$codexRunning = $codexProcesses.Count -gt 0
if ($Apply -and $codexRunning) {
    throw "Codex is running. Re-run with Codex closed, or pass -WaitForCodexExit and close Codex before the timeout."
}

New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

$actions = [System.Collections.Generic.List[object]]::new()
$findings = [System.Collections.Generic.List[object]]::new()
$earliestCodexStartTime = Get-EarliestProcessStartTime -Processes $codexProcesses

$configPath = Join-Path $CodexRoot 'config.toml'
$configState = $null
if (Test-Path -LiteralPath $configPath) {
    $configText = Get-Content -LiteralPath $configPath -Raw
    $hasWorkspaceDependencies = $configText -match '(?m)^\s*workspace_dependencies\s*='
    $hasExtendedPathPrefix = $configText -match '\\\\\?\\'
    $parseOk = Test-TomlParse
    if ($parseOk) {
        $configState = Read-CodexConfigState
    }
    $findings.Add([pscustomobject]@{
        surface = 'config.toml'
        status = if ($hasWorkspaceDependencies -or $hasExtendedPathPrefix) { 'needs_fix' } else { 'ok' }
        detail = if ($hasWorkspaceDependencies) { 'unsupported workspace_dependencies flag is present' } elseif ($hasExtendedPathPrefix) { 'extended Windows path prefix is present' } else { 'unsupported workspace_dependencies flag and extended Windows path prefix not present' }
        parse_ok = $parseOk
    })
}

$policy = if ($null -ne $configState -and $configState.policy_present) { $configState.policy } else { $null }
$expectedAppConnectors = @(Get-PolicyArray -Policy $policy -PropertyName 'expected_app_connectors' -Default $DefaultExpectedAppConnectors)
$unexpectedAppConnectors = @(Get-PolicyArray -Policy $policy -PropertyName 'unexpected_app_connectors' -Default $DefaultUnexpectedAppConnectors)
$unexpectedConnectorNamespaces = @(Get-PolicyArray -Policy $policy -PropertyName 'unexpected_app_tool_namespaces' -Default $UnwantedConnectorNamespaces)
$allowedMarketplaceSourceRoots = @(Get-PolicyArray -Policy $policy -PropertyName 'allowed_marketplace_source_roots' -Default @())
$forbiddenActiveSourceFragments = @(Get-PolicyArray -Policy $policy -PropertyName 'forbidden_active_source_fragments' -Default $DefaultForbiddenActiveSourceFragments)

$findings.Add([pscustomobject]@{
    surface = 'contamination_prevention_policy'
    status = if ($null -ne $policy) { 'ok' } else { 'missing' }
    profile = if ($null -ne $policy -and $policy.PSObject.Properties.Name -contains 'profile') { [string]$policy.profile } else { $null }
    expected_app_connectors = $expectedAppConnectors
    unexpected_app_connectors = $unexpectedAppConnectors
    unexpected_tool_namespaces = $unexpectedConnectorNamespaces
})

$namingPolicy = if ($null -ne $configState -and $configState.naming_policy_present) { $configState.naming_policy } else { $null }
$findings.Add([pscustomobject]@{
    surface = 'naming_convention_policy'
    status = if ($null -ne $namingPolicy) { 'ok' } else { 'missing' }
    profile = if ($null -ne $namingPolicy -and $namingPolicy.PSObject.Properties.Name -contains 'profile') { [string]$namingPolicy.profile } else { $null }
    log_archive_name_format = if ($null -ne $namingPolicy -and $namingPolicy.PSObject.Properties.Name -contains 'log_archive_name_format') { [string]$namingPolicy.log_archive_name_format } else { $null }
    app_tool_cache_file_rule = if ($null -ne $namingPolicy -and $namingPolicy.PSObject.Properties.Name -contains 'app_tool_cache_file_rule') { [string]$namingPolicy.app_tool_cache_file_rule } else { $null }
})

Add-RuntimeTransientRootFindings `
    -RootNames $DefaultRuntimeTransientRootNames `
    -Policy $policy `
    -EarliestCodexStartTime $earliestCodexStartTime `
    -CodexRunning $codexRunning `
    -Apply $Apply `
    -Findings $findings `
    -Actions $actions

if ($null -ne $configState) {
    foreach ($source in @($configState.marketplace_sources)) {
        $sourcePath = [string]$source.source
        $exists = Test-Path -LiteralPath $sourcePath
        $allowed = Test-PathUnderAnyRoot -Path $sourcePath -Roots $allowedMarketplaceSourceRoots
        $forbidden = Test-PathHasFragment -Path $sourcePath -Fragments $forbiddenActiveSourceFragments
        $findings.Add([pscustomobject]@{
            surface = 'marketplace_source'
            marketplace = [string]$source.id
            path = $sourcePath
            status = if ($exists -and $allowed -and -not $forbidden) { 'ok' } else { 'needs_fix' }
            exists = $exists
            allowed_root = $allowed
            forbidden_fragment = $forbidden
        })
    }
}

$appsToolsDir = Join-Path $CodexRoot 'cache\codex_apps_tools'
if (Test-Path -LiteralPath $appsToolsDir) {
    foreach ($file in Get-ChildItem -LiteralPath $appsToolsDir -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        $json = Read-JsonFile -Path $file.FullName
        $tools = @($json.tools)
        $unexpectedConnectorsLower = @($unexpectedAppConnectors | ForEach-Object { ([string]$_).ToLowerInvariant() })
        $expectedConnectorsLower = @($expectedAppConnectors | ForEach-Object { ([string]$_).ToLowerInvariant() })
        $unexpectedNamespacesLower = @($unexpectedConnectorNamespaces | ForEach-Object { ([string]$_).ToLowerInvariant() })
        $unwanted = @($tools | Where-Object {
            $connector = ([string]$_.connector_name).ToLowerInvariant()
            $namespace = ([string]$_.tool_namespace).ToLowerInvariant()
            ($unexpectedNamespacesLower -contains $namespace) -or
            ($unexpectedConnectorsLower -contains $connector) -or
            ($expectedConnectorsLower.Count -gt 0 -and $connector -and -not ($expectedConnectorsLower -contains $connector))
        })
        $connectorNames = @($unwanted | ForEach-Object { [string]$_.connector_name } | Sort-Object -Unique)
        $allConnectorNames = @($tools | ForEach-Object { [string]$_.connector_name } | Sort-Object -Unique)
        $allNamespaces = @($tools | ForEach-Object { [string]$_.tool_namespace } | Sort-Object -Unique)
        $findings.Add([pscustomobject]@{
            surface = 'codex_apps_tools'
            path = $file.FullName
            status = if ($unwanted.Count -gt 0) { 'needs_archive' } else { 'ok' }
            tool_count = $tools.Count
            connectors = $allConnectorNames
            namespaces = $allNamespaces
            unwanted_tool_count = $unwanted.Count
            unwanted_connectors = $connectorNames
        })

        if ($Apply -and $unwanted.Count -gt 0) {
            Move-ToArchive -Path $file.FullName -Base $CodexRoot -Actions $actions
        }
    }
}

$codexHomeLogs = @(Get-ChildItem -LiteralPath $CodexRoot -Filter 'logs_2.sqlite*' -File -Force -ErrorAction SilentlyContinue)
if ($codexHomeLogs.Count -gt 0) {
    $logBytes = ($codexHomeLogs | Measure-Object -Property Length -Sum).Sum
    $findings.Add([pscustomobject]@{
        surface = 'codex_home_logs'
        status = if ($logBytes -gt 64MB) { 'needs_compression' } else { 'ok' }
        file_count = $codexHomeLogs.Count
        bytes = [int64]$logBytes
        mb = [math]::Round($logBytes / 1MB, 1)
        compression_rule = if ($null -ne $namingPolicy -and $namingPolicy.PSObject.Properties.Name -contains 'log_archive_name_format') { [string]$namingPolicy.log_archive_name_format } else { 'codex-logs-{yyyymmdd-HHMMSS}.zip' }
        detail = 'Use keep_codex_fast.py --compress-live-logs-snapshot while Codex is running; use --apply after Codex exits to rotate compressed logs.'
    })
}

$chromeCacheDir = Join-Path $CodexRoot 'plugins\cache\openai-bundled\chrome'
if (Test-Path -LiteralPath $chromeCacheDir) {
    foreach ($dir in Get-ChildItem -LiteralPath $chromeCacheDir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.incomplete-*' }) {
        $fileStats = Get-ChildItem -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        $findings.Add([pscustomobject]@{
            surface = 'chrome_plugin_cache'
            path = $dir.FullName
            status = 'needs_archive'
            file_count = $fileStats.Count
            bytes = [int64]$fileStats.Sum
        })

        if ($Apply) {
            Move-ToArchive -Path $dir.FullName -Base $CodexRoot -Actions $actions
        }
    }
}

$legacyTmpPluginRoot = Join-Path $CodexRoot '.tmp\plugins'
if (Test-Path -LiteralPath $legacyTmpPluginRoot) {
    $legacyTmpPluginItem = Get-Item -LiteralPath $legacyTmpPluginRoot -Force
    $legacyGeneratedThisSession = $false
    if ($codexRunning -and $null -ne $earliestCodexStartTime) {
        $legacyGeneratedThisSession = $legacyTmpPluginItem.CreationTime -ge $earliestCodexStartTime.AddSeconds(-10)
    }
    $manifestFiles = @(Get-ChildItem -LiteralPath $legacyTmpPluginRoot -Recurse -Force -File -Filter 'plugin.json' -ErrorAction SilentlyContinue)
    $marketplaceFiles = @(Get-ChildItem -LiteralPath $legacyTmpPluginRoot -Recurse -Force -File -Filter 'marketplace.json' -ErrorAction SilentlyContinue)
    $unwantedTmpPlugins = @($manifestFiles | Where-Object {
        $_.FullName -match '\\plugins\\(supabase|hugging-face)\\\.codex-plugin\\plugin\.json$'
    })

    $findings.Add([pscustomobject]@{
        surface = 'legacy_tmp_plugins_marketplace'
        path = $legacyTmpPluginRoot
        status = if ($manifestFiles.Count -gt 0 -and $legacyGeneratedThisSession) { 'runtime_generated_current_session_needs_archive_after_exit' } elseif ($manifestFiles.Count -gt 0) { 'needs_archive' } else { 'ok' }
        created_during_current_codex_session = $legacyGeneratedThisSession
        plugin_manifest_count = $manifestFiles.Count
        marketplace_file_count = $marketplaceFiles.Count
        unwanted_plugin_manifest_count = $unwantedTmpPlugins.Count
        detail = 'Temporary plugin marketplace clone is runtime-generated; it must not be persisted as a marketplace source and is archived only when Codex is closed.'
    })

    if ($Apply -and $manifestFiles.Count -gt 0) {
        Move-ToArchive -Path $legacyTmpPluginRoot -Base $CodexRoot -Actions $actions
    }
}

$unrecognizedToolsRoot = Join-Path $CodexRoot 'Tools'
if (Test-Path -LiteralPath $unrecognizedToolsRoot) {
    $toolItems = @(Get-ChildItem -LiteralPath $unrecognizedToolsRoot -Recurse -Force -ErrorAction SilentlyContinue)
    if ($toolItems.Count -gt 0) {
        $findings.Add([pscustomobject]@{
            surface = 'unrecognized_tools_root'
            path = $unrecognizedToolsRoot
            status = 'needs_migration'
            item_count = $toolItems.Count
            detail = 'Files under .codex\Tools are not automatically exposed as Codex skills, plugins, or MCP servers.'
        })
    }
}

$todayLogDir = Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\Logs'
if (Test-Path -LiteralPath $todayLogDir) {
    $recentLogs = @(Get-ChildItem -LiteralPath $todayLogDir -Recurse -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-2) })
    $parseErrors = 0
    $fileLockErrors = 0
    $unsupportedFeatureErrors = 0
    foreach ($log in $recentLogs) {
        $parseErrors += @(Select-String -LiteralPath $log.FullName -SimpleMatch 'Failed to parse MCP message' -ErrorAction SilentlyContinue).Count
        $fileLockErrors += @(Select-String -LiteralPath $log.FullName -SimpleMatch 'plugin_cache_windows_file_lock' -ErrorAction SilentlyContinue).Count
        $unsupportedFeatureErrors += @(Select-String -LiteralPath $log.FullName -SimpleMatch 'unsupported feature enablement `workspace_dependencies`' -ErrorAction SilentlyContinue).Count
    }
    $findings.Add([pscustomobject]@{
        surface = 'codex_app_logs_recent'
        status = if (($parseErrors + $fileLockErrors + $unsupportedFeatureErrors) -gt 0) { 'observed_errors' } else { 'ok' }
        mcp_parse_errors = $parseErrors
        plugin_file_lock_errors = $fileLockErrors
        unsupported_workspace_dependencies_errors = $unsupportedFeatureErrors
        scanned_log_count = $recentLogs.Count
    })
}

$report = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    codex_root = $CodexRoot
    apply = [bool]$Apply
    codex_running = $codexRunning
    codex_process_ids = @($codexProcesses | ForEach-Object { $_.Id })
    archive_root = if ($actions.Count -gt 0) { $RunArchiveRoot } else { $null }
    expected_app_connectors = $expectedAppConnectors
    unexpected_app_connectors = $unexpectedAppConnectors
    unwanted_connector_namespaces = $unexpectedConnectorNamespaces
    findings = @($findings)
    actions = @($actions)
    next_verification = @(
        'Close Codex and run this script with -Apply to archive .tmp, tmp, and vendor_imports transient runtime roots.',
        'Restart Codex after apply mode archives caches.',
        'Run tool_search for Supabase/Hugging Face and confirm they are absent or intentionally re-authorized.',
        'Run browser-use verification and confirm in-app browser still works.',
        'Confirm .tmp\plugins may be recreated as runtime scratch but is not persisted as an enabled marketplace source.',
        'Re-scan recent Codex logs for new workspace_dependencies, plugin_cache_windows_file_lock, and MCP parse errors.'
    )
}

$jsonPath = Join-Path $ReportRoot 'CODEX_RUNTIME_STATE_REPAIR.latest.json'
$mdPath = Join-Path $ReportRoot 'CODEX_RUNTIME_STATE_REPAIR.latest.md'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8

$summaryLines = @(
    '# Codex Runtime State Repair',
    '',
    "- Generated: $($report.generated_at)",
    "- Mode: $(if ($Apply) { 'apply' } else { 'report-only' })",
    "- Codex running: $codexRunning",
    "- Actions: $($actions.Count)",
    '',
    '## Findings'
)

foreach ($finding in $findings) {
    $summaryLines += "- $($finding.surface): $($finding.status)"
}

if ($actions.Count -gt 0) {
    $summaryLines += ''
    $summaryLines += '## Actions'
    foreach ($action in $actions) {
        $summaryLines += "- Archived ``$($action.source)`` to ``$($action.destination)``"
    }
}

$summaryLines += ''
$summaryLines += '## Next Verification'
foreach ($item in $report.next_verification) {
    $summaryLines += "- $item"
}

Set-Content -LiteralPath $mdPath -Value $summaryLines -Encoding utf8

Write-Output "Report: $jsonPath"
Write-Output "Summary: $mdPath"
if ($actions.Count -gt 0) {
    Write-Output "Archived actions: $($actions.Count)"
} else {
    Write-Output "Archived actions: 0"
}
