param(
    [string] $CodexHome = "$env:USERPROFILE\.codex",
    [switch] $Json,
    [switch] $WriteReport,
    [switch] $CheckStoreUpgrade
)

$ErrorActionPreference = "Stop"

$script:Checks = New-Object System.Collections.Generic.List[object]

function Resolve-FullPathMaybe {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    $clean = $Path -replace '^\\\\\?\\', ''
    try {
        return ([System.IO.Path]::GetFullPath($clean)).TrimEnd('\')
    } catch {
        return $clean.TrimEnd('\')
    }
}

function Expand-TemplatePath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    $expanded = $Path.Replace("%USERPROFILE%", $env:USERPROFILE).Replace("%LOCALAPPDATA%", $env:LOCALAPPDATA)
    return [Environment]::ExpandEnvironmentVariables($expanded)
}

function Get-StateArray {
    param($Value, [string[]] $Fallback)
    if ($null -eq $Value) {
        return $Fallback
    }
    return @($Value | ForEach-Object { [string]$_ })
}

function Add-Check {
    param(
        [string] $Name,
        [ValidateSet("pass", "fail", "warn")] [string] $Status,
        [string] $Message,
        [hashtable] $Data = @{}
    )
    $orderedData = [ordered]@{}
    foreach ($key in $Data.Keys) {
        $orderedData[$key] = $Data[$key]
    }
    $script:Checks.Add([ordered]@{
        name = $Name
        status = $Status
        message = $Message
        data = $orderedData
    })
}

function Get-TomlSection {
    param([string] $Text, [string] $Name)
    $escaped = [regex]::Escape($Name)
    $match = [regex]::Match($Text, "(?ms)^\[$escaped\]\s*(?<body>.*?)(?=^\[|\z)")
    if ($match.Success) {
        return $match.Groups["body"].Value
    }
    return $null
}

function Get-TomlValue {
    param([string] $Body, [string] $Key)
    if ($null -eq $Body) {
        return $null
    }
    $escaped = [regex]::Escape($Key)
    $single = [regex]::Match($Body, "(?m)^\s*$escaped\s*=\s*'(?<v>[^']*)'")
    if ($single.Success) {
        return $single.Groups["v"].Value
    }
    $double = [regex]::Match($Body, "(?m)^\s*$escaped\s*=\s*`"(?<v>[^`"]*)`"")
    if ($double.Success) {
        return $double.Groups["v"].Value
    }
    $bare = [regex]::Match($Body, "(?m)^\s*$escaped\s*=\s*(?<v>[^\r\n#]+)")
    if ($bare.Success) {
        return $bare.Groups["v"].Value.Trim()
    }
    return $null
}

function Get-TomlBool {
    param([string] $Body, [string] $Key)
    $value = Get-TomlValue -Body $Body -Key $Key
    if ($null -eq $value) {
        return $null
    }
    if ($value -match '^(?i:true)$') {
        return $true
    }
    if ($value -match '^(?i:false)$') {
        return $false
    }
    return $null
}

function Invoke-VersionLine {
    param([string] $Command, [string[]] $Arguments)
    try {
        $output = & $Command @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) {
            return [ordered]@{ ok = $false; line = (($output | Select-Object -First 1) -join "`n"); exit = $LASTEXITCODE }
        }
        return [ordered]@{ ok = $true; line = (($output | Select-Object -First 1) -join "`n"); exit = 0 }
    } catch {
        return [ordered]@{ ok = $false; line = $_.Exception.Message; exit = $null }
    }
}

function Test-Prefix {
    param([string] $Path, [string[]] $Prefixes)
    $normalized = Resolve-FullPathMaybe $Path
    foreach ($prefix in $Prefixes) {
        $normalizedPrefix = Resolve-FullPathMaybe $prefix
        if ($normalized -and $normalizedPrefix -and $normalized.StartsWith($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

$codexHomePath = Resolve-FullPathMaybe $CodexHome
$configPath = Join-Path $codexHomePath "config.toml"
$statePath = Join-Path $codexHomePath "maintenance\CODEX_HOME_STRUCTURE_STATE.json"
$contractPath = Join-Path $codexHomePath "maintenance\CODEX_HOME_STRUCTURE_CONTRACT.md"
$structureState = $null
$nativeCriteria = $null

if (Test-Path -LiteralPath $statePath) {
    try {
        $structureState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        $nativeCriteria = $structureState.native_alignment
        Add-Check "structure_state_present" "pass" "Freshness-sensitive Codex home structure state JSON exists and parses." @{
            path = $statePath
            schema_version = [string]$structureState.schema_version
        }
        if ($structureState.records.structure_policy_md) {
            $contractPath = Join-Path $codexHomePath ([string]$structureState.records.structure_policy_md)
        }
    } catch {
        Add-Check "structure_state_present" "fail" "Freshness-sensitive Codex home structure state JSON failed to parse." @{
            path = $statePath
            error = $_.Exception.Message
        }
    }
} else {
    Add-Check "structure_state_present" "fail" "Freshness-sensitive Codex home structure state JSON is missing." @{
        path = $statePath
    }
}

if (Test-Path -LiteralPath $contractPath) {
    Add-Check "structure_contract_present" "pass" "Stale-tolerant Codex home structure Markdown policy exists." @{ path = $contractPath }
} else {
    Add-Check "structure_contract_present" "fail" "Stale-tolerant Codex home structure Markdown policy is missing." @{ path = $contractPath }
}

if (-not (Test-Path -LiteralPath $configPath)) {
    Add-Check "config_present" "fail" "config.toml is missing." @{ path = $configPath }
    $configText = ""
} else {
    $configText = Get-Content -Raw -LiteralPath $configPath
    Add-Check "config_present" "pass" "config.toml is present." @{ path = $configPath }
}

$featuresSection = Get-TomlSection -Text $configText -Name "features"
$workspaceDeps = Get-TomlBool -Body $featuresSection -Key "workspace_dependencies"
$workspaceDepsExpected = if ($nativeCriteria -and $nativeCriteria.required_features -and $null -ne $nativeCriteria.required_features.workspace_dependencies) {
    [bool]$nativeCriteria.required_features.workspace_dependencies
} else {
    $true
}
if ($workspaceDeps -eq $workspaceDepsExpected) {
    Add-Check "workspace_dependencies_enabled" "pass" "workspace_dependencies is enabled." @{}
} else {
    Add-Check "workspace_dependencies_enabled" "fail" "workspace_dependencies must remain enabled unless a task explicitly replaces it." @{ observed = $workspaceDeps }
}

$storePackageName = if ($nativeCriteria -and $nativeCriteria.store_app_package_name) { [string]$nativeCriteria.store_app_package_name } else { "OpenAI.Codex" }
$bundledSourceSuffix = if ($nativeCriteria -and $nativeCriteria.openai_bundled_source_suffix) {
    ([string]$nativeCriteria.openai_bundled_source_suffix) -replace '/', '\'
} else {
    "app\resources\plugins\openai-bundled"
}

$package = Get-AppxPackage -Name $storePackageName -ErrorAction SilentlyContinue |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1

$officialResources = $null
$officialBundled = $null
if ($package) {
    $officialResources = Resolve-FullPathMaybe (Join-Path $package.InstallLocation "app\resources")
    $officialBundled = Resolve-FullPathMaybe (Join-Path $package.InstallLocation $bundledSourceSuffix)
    $statusOk = ([int]$package.Status -eq 0)
    $storeSigned = ([int]$package.SignatureKind -eq 3)
    if ($statusOk -and $storeSigned -and (Test-Path -LiteralPath $officialResources)) {
        Add-Check "official_app_package" "pass" "$storePackageName Store app package is installed and healthy." @{
            version = [string]$package.Version
            package_full_name = [string]$package.PackageFullName
            install_location = [string]$package.InstallLocation
        }
    } else {
        Add-Check "official_app_package" "fail" "$storePackageName package is present but not healthy." @{
            version = [string]$package.Version
            status = [string]$package.Status
            signature_kind = [string]$package.SignatureKind
            install_location = [string]$package.InstallLocation
        }
    }
} else {
    Add-Check "official_app_package" "fail" "$storePackageName Store app package is not installed." @{}
}

$bundledSection = Get-TomlSection -Text $configText -Name "marketplaces.openai-bundled"
$bundledSource = Get-TomlValue -Body $bundledSection -Key "source"
$bundledSourceNorm = Resolve-FullPathMaybe $bundledSource
if ($officialBundled -and $bundledSourceNorm -and $bundledSourceNorm.Equals($officialBundled, [System.StringComparison]::OrdinalIgnoreCase)) {
    Add-Check "openai_bundled_source" "pass" "openai-bundled source points at the installed Store app bundle." @{
        source = $bundledSourceNorm
    }
} else {
    Add-Check "openai_bundled_source" "fail" "openai-bundled source must point at the current installed Store app bundle." @{
        observed = $bundledSourceNorm
        expected = $officialBundled
    }
}

$manifestPath = if ($officialBundled) { Join-Path $officialBundled ".agents\plugins\marketplace.json" } else { $null }
if ($manifestPath -and (Test-Path -LiteralPath $manifestPath)) {
    try {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $enabledMissing = @()
        foreach ($plugin in @($manifest.plugins)) {
            $relativePath = [string]$plugin.source.path
            $pluginSection = Get-TomlSection -Text $configText -Name "plugins.`"$($plugin.name)@openai-bundled`""
            if ((Get-TomlBool -Body $pluginSection -Key "enabled") -eq $true) {
                $sourcePath = Resolve-FullPathMaybe (Join-Path $officialBundled ($relativePath -replace '/', '\'))
                if (-not (Test-Path -LiteralPath $sourcePath)) {
                    $record = [pscustomobject]@{ plugin = [string]$plugin.name; path = $sourcePath }
                    $enabledMissing += $record
                }
            }
        }
        if (@($enabledMissing).Count -gt 0) {
            Add-Check "official_bundled_manifest_paths" "fail" "An enabled official bundled plugin points at a missing app path." @{
                manifest = $manifestPath
                missing_enabled = @($enabledMissing)
            }
        } else {
            Add-Check "official_bundled_manifest_paths" "pass" "Enabled official bundled plugin paths exist." @{
                manifest = $manifestPath
            }
        }
    } catch {
        Add-Check "official_bundled_manifest_paths" "fail" "Failed to parse official bundled marketplace manifest." @{
            manifest = $manifestPath
            error = $_.Exception.Message
        }
    }
} else {
    Add-Check "official_bundled_manifest_paths" "fail" "Official bundled marketplace manifest is missing." @{
        manifest = $manifestPath
    }
}

$primarySection = Get-TomlSection -Text $configText -Name "marketplaces.openai-primary-runtime"
$primarySource = Resolve-FullPathMaybe (Get-TomlValue -Body $primarySection -Key "source")
$primaryRootTemplate = if ($nativeCriteria -and $nativeCriteria.primary_runtime_marketplace_source_template) {
    [string]$nativeCriteria.primary_runtime_marketplace_source_template
} else {
    "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\plugins\openai-primary-runtime"
}
$expectedPrimaryRoot = Resolve-FullPathMaybe (Expand-TemplatePath $primaryRootTemplate)
if ($primarySource -and $primarySource.Equals($expectedPrimaryRoot, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $primarySource)) {
    Add-Check "openai_primary_runtime_source" "pass" "openai-primary-runtime source points at the primary workspace runtime cache." @{
        source = $primarySource
    }
} else {
    Add-Check "openai_primary_runtime_source" "fail" "openai-primary-runtime source must point at the primary workspace runtime cache." @{
        observed = $primarySource
        expected = $expectedPrimaryRoot
    }
}

$runtimePlugins = Get-StateArray $nativeCriteria.required_primary_runtime_plugins @("documents", "presentations", "spreadsheets")
$runtimeVersions = New-Object System.Collections.Generic.List[string]
$missingRuntime = New-Object System.Collections.Generic.List[string]
foreach ($pluginName in $runtimePlugins) {
    $pluginJson = Join-Path $expectedPrimaryRoot "plugins\$pluginName\.codex-plugin\plugin.json"
    if (-not (Test-Path -LiteralPath $pluginJson)) {
        $missingRuntime.Add($pluginName)
        continue
    }
    try {
        $pluginJsonData = Get-Content -Raw -LiteralPath $pluginJson | ConvertFrom-Json
        $runtimeVersions.Add([string]$pluginJsonData.version)
    } catch {
        $missingRuntime.Add($pluginName)
    }
}
$versionSet = @($runtimeVersions | Sort-Object -Unique)
if ($missingRuntime.Count -eq 0 -and $versionSet.Count -eq 1) {
    Add-Check "workspace_runtime_plugins" "pass" "Workspace runtime plugins are present and share one runtime version." @{
        plugins = $runtimePlugins
        version = $versionSet[0]
    }
} else {
    Add-Check "workspace_runtime_plugins" "fail" "Workspace runtime plugins are missing or version-divergent." @{
        missing = @($missingRuntime)
        versions = @($versionSet)
    }
}

$forbiddenPaths = Get-StateArray $nativeCriteria.forbidden_active_paths @(
    "plugins\patched",
    "vendor_imports",
    "plugins\plugins",
    "plugins\cache\openai-bundled\browser-use",
    "plugins\cache\openai-primary-runtime",
    "plugins\local-marketplaces",
    ".tmp\plugins"
)
$presentForbidden = @()
foreach ($relative in $forbiddenPaths) {
    $relative = $relative -replace '/', '\'
    $candidate = Join-Path $codexHomePath $relative
    if (Test-Path -LiteralPath $candidate) {
        $presentForbidden += $candidate
    }
}
if ($presentForbidden.Count -eq 0) {
    Add-Check "forbidden_active_sources_absent" "pass" "Forbidden active fallback, patched, duplicate, and stale cache paths are absent." @{}
} else {
    Add-Check "forbidden_active_sources_absent" "fail" "Forbidden active fallback, patched, duplicate, or stale cache paths are present." @{
        present = $presentForbidden
    }
}

$boundedRuntimeTempPaths = Get-StateArray $nativeCriteria.bounded_runtime_temp_paths @(".tmp\bundled-marketplaces")
$presentRuntimeTemp = @()
foreach ($relative in $boundedRuntimeTempPaths) {
    $relative = $relative -replace '/', '\'
    $candidate = Join-Path $codexHomePath $relative
    if (Test-Path -LiteralPath $candidate) {
        $presentRuntimeTemp += $candidate
    }
}
if ($presentRuntimeTemp.Count -eq 0) {
    Add-Check "bounded_runtime_temp_paths" "pass" "No bounded app-generated runtime temp marketplace mirrors are present." @{}
} else {
    Add-Check "bounded_runtime_temp_paths" "pass" "Bounded app-generated runtime temp marketplace mirrors are present but not active config sources." @{
        present = $presentRuntimeTemp
    }
}

$curatedSnapshot = if ($nativeCriteria -and $nativeCriteria.official_curated_temp_snapshot) {
    $nativeCriteria.official_curated_temp_snapshot
} else {
    $null
}
if ($curatedSnapshot) {
    $snapshotRelative = if ($curatedSnapshot.path) { [string]$curatedSnapshot.path } else { ".tmp\plugins" }
    $snapshotShaRelative = if ($curatedSnapshot.sha_path) { [string]$curatedSnapshot.sha_path } else { ".tmp\plugins.sha" }
    $snapshotManifestRelative = if ($curatedSnapshot.manifest) { [string]$curatedSnapshot.manifest } else { ".agents\plugins\marketplace.json" }
    $snapshotRemoteExpected = if ($curatedSnapshot.remote_url) { [string]$curatedSnapshot.remote_url } else { "https://github.com/openai/plugins.git" }
    $snapshotNameExpected = if ($curatedSnapshot.marketplace_name) { [string]$curatedSnapshot.marketplace_name } else { "openai-curated" }
    $snapshotPath = Join-Path $codexHomePath ($snapshotRelative -replace '/', '\')
    $snapshotShaPath = Join-Path $codexHomePath ($snapshotShaRelative -replace '/', '\')
    if (Test-Path -LiteralPath $snapshotPath) {
        $snapshotManifestPath = Join-Path $snapshotPath ($snapshotManifestRelative -replace '/', '\')
        $snapshotGitConfigPath = Join-Path $snapshotPath ".git\config"
        $remoteOk = $false
        $manifestOk = $false
        $shaOk = $false
        $manifestName = $null
        $manifestPluginCount = $null
        $shaValue = $null
        if (Test-Path -LiteralPath $snapshotGitConfigPath) {
            $snapshotGitConfig = Get-Content -Raw -LiteralPath $snapshotGitConfigPath
            $remoteOk = $snapshotGitConfig -match [regex]::Escape("url = $snapshotRemoteExpected")
        }
        if (Test-Path -LiteralPath $snapshotManifestPath) {
            try {
                $snapshotManifest = Get-Content -Raw -LiteralPath $snapshotManifestPath | ConvertFrom-Json
                $manifestName = [string]$snapshotManifest.name
                $manifestPluginCount = @($snapshotManifest.plugins).Count
                $manifestOk = ($manifestName -eq $snapshotNameExpected -and $manifestPluginCount -gt 0)
            } catch {
                $manifestOk = $false
            }
        }
        if (Test-Path -LiteralPath $snapshotShaPath) {
            $shaValue = (Get-Content -Raw -LiteralPath $snapshotShaPath).Trim()
            $shaOk = $shaValue -match '^[0-9a-fA-F]{40}$'
        }
        if ($remoteOk -and $manifestOk -and $shaOk) {
            Add-Check "official_curated_temp_snapshot" "pass" "The configured .tmp plugins snapshot matches the expected official runtime snapshot shape." @{
                path = $snapshotPath
                remote = $snapshotRemoteExpected
                marketplace = $manifestName
                plugin_count = $manifestPluginCount
                sha = $shaValue
            }
        } else {
            Add-Check "official_curated_temp_snapshot" "fail" "The configured .tmp plugins snapshot is present but does not match the expected official runtime snapshot shape." @{
                path = $snapshotPath
                remote_ok = $remoteOk
                manifest_ok = $manifestOk
                sha_ok = $shaOk
                marketplace = $manifestName
                plugin_count = $manifestPluginCount
                sha = $shaValue
            }
        }
    } else {
        Add-Check "official_curated_temp_snapshot" "pass" "No configured .tmp plugins snapshot is present." @{}
    }
} else {
    $snapshotPath = Join-Path $codexHomePath ".tmp\plugins"
    $snapshotShaPath = Join-Path $codexHomePath ".tmp\plugins.sha"
    $presentCuratedTemp = @()
    if (Test-Path -LiteralPath $snapshotPath) { $presentCuratedTemp += $snapshotPath }
    if (Test-Path -LiteralPath $snapshotShaPath) { $presentCuratedTemp += $snapshotShaPath }
    if ($presentCuratedTemp.Count -eq 0) {
        Add-Check "official_curated_temp_snapshot" "pass" "Curated .tmp plugins snapshot acceptance is disabled and no snapshot is present." @{}
    } else {
        Add-Check "official_curated_temp_snapshot" "fail" "Curated .tmp plugins snapshot acceptance is disabled; remove the regenerated snapshot." @{
            present = $presentCuratedTemp
        }
    }
}

$tmpRoot = Join-Path $codexHomePath ".tmp"
$pluginCloneResidues = @()
if (Test-Path -LiteralPath $tmpRoot) {
    $pluginCloneResidues = @(Get-ChildItem -LiteralPath $tmpRoot -Directory -Force -Filter "plugins-clone-*" -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName })
}
if ($pluginCloneResidues.Count -eq 0) {
    Add-Check "stale_plugin_clone_residue_absent" "pass" "No incomplete temporary plugin clone directories are present." @{}
} else {
    Add-Check "stale_plugin_clone_residue_absent" "fail" "Incomplete temporary plugin clone directories are present." @{
        paths = $pluginCloneResidues
    }
}

$staleBackupPaths = Get-StateArray $nativeCriteria.stale_backup_paths @(".codex-global-state.json.bak")
$presentBackups = @()
foreach ($relativeBackup in $staleBackupPaths) {
    $backupPath = Join-Path $codexHomePath ($relativeBackup -replace '/', '\')
    if (Test-Path -LiteralPath $backupPath) {
        $presentBackups += $backupPath
    }
}
if ($presentBackups.Count -gt 0) {
    Add-Check "stale_backup_paths_absent" "warn" "Stale backup residue is present; recycle it if it is not actively required by the app." @{
        paths = $presentBackups
    }
} else {
    Add-Check "stale_backup_paths_absent" "pass" "No stale backup residue is present." @{}
}

$cacheRoot = Join-Path $codexHomePath "plugins\cache"
if (Test-Path -LiteralPath $cacheRoot) {
    $cacheNames = @(Get-ChildItem -LiteralPath $cacheRoot -Directory -Force | ForEach-Object { $_.Name })
    $allowedCacheRoots = Get-StateArray $nativeCriteria.allowed_plugin_cache_roots @("openai-bundled", "openai-curated")
    $unexpected = @($cacheNames | Where-Object { $_ -notin $allowedCacheRoots })
    if ($unexpected.Count -eq 0) {
        Add-Check "plugin_cache_roots" "pass" "Plugin cache roots are bounded to known app-generated marketplaces." @{
            roots = $cacheNames
        }
    } else {
        Add-Check "plugin_cache_roots" "warn" "Unexpected plugin cache roots are present; verify ownership before cleanup." @{
            roots = $cacheNames
            unexpected = $unexpected
        }
    }
} else {
    Add-Check "plugin_cache_roots" "warn" "plugins\\cache is absent; app may recreate it when plugins load." @{}
}

$chromeServerName = if ($nativeCriteria -and $nativeCriteria.chrome_devtools -and $nativeCriteria.chrome_devtools.server_name) {
    [string]$nativeCriteria.chrome_devtools.server_name
} else {
    "chrome_devtools_observe"
}
$chromeDefaultEnabled = if ($nativeCriteria -and $nativeCriteria.chrome_devtools -and $null -ne $nativeCriteria.chrome_devtools.default_enabled) {
    [bool]$nativeCriteria.chrome_devtools.default_enabled
} else {
    $false
}
$chromeProcessPattern = if ($nativeCriteria -and $nativeCriteria.chrome_devtools -and $nativeCriteria.chrome_devtools.process_pattern) {
    [string]$nativeCriteria.chrome_devtools.process_pattern
} else {
    "chrome-devtools-mcp"
}

$chromeSection = Get-TomlSection -Text $configText -Name "mcp_servers.$chromeServerName"
$chromeEnabled = Get-TomlBool -Body $chromeSection -Key "enabled"
if ($chromeEnabled -eq $chromeDefaultEnabled) {
    Add-Check "chrome_devtools_observe_off" "pass" "$chromeServerName is at its configured default enabled state." @{}
} else {
    Add-Check "chrome_devtools_observe_off" "fail" "$chromeServerName should stay at its configured default outside an active frontend observation task." @{
        observed = $chromeEnabled
        expected = $chromeDefaultEnabled
    }
}

$chromeDevtoolsProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -match [regex]::Escape($chromeProcessPattern) } |
    Select-Object ProcessId,Name,CommandLine)
if ($chromeDevtoolsProcesses.Count -eq 0) {
    Add-Check "chrome_devtools_process_absent" "pass" "No chrome-devtools-mcp process is running." @{}
} else {
    Add-Check "chrome_devtools_process_absent" "fail" "chrome-devtools-mcp process is running while the observer is OFF." @{
        processes = @($chromeDevtoolsProcesses)
    }
}

$prefixTemplates = Get-StateArray $nativeCriteria.toolchain.allowed_command_prefix_templates @(
    "%USERPROFILE%/.codex/toolchains/shims",
    "%LOCALAPPDATA%/OpenAI/Codex/bin",
    "OFFICIAL_APP_RESOURCES"
)
$allowedCommandPrefixes = @()
foreach ($prefixTemplate in $prefixTemplates) {
    if ($prefixTemplate -eq "OFFICIAL_APP_RESOURCES") {
        if ($officialResources) {
            $allowedCommandPrefixes += $officialResources
        }
    } else {
        $allowedCommandPrefixes += (Expand-TemplatePath $prefixTemplate)
    }
}

$versionMatchCommands = Get-StateArray $nativeCriteria.toolchain.version_match_commands @("node", "rg", "codex")
$versionArgs = @{}
if ($nativeCriteria -and $nativeCriteria.toolchain -and $nativeCriteria.toolchain.version_args) {
    foreach ($property in $nativeCriteria.toolchain.version_args.PSObject.Properties) {
        $versionArgs[$property.Name] = @($property.Value | ForEach-Object { [string]$_ })
    }
}
$officialExeNames = @{
    node = "node.exe"
    rg = "rg.exe"
    codex = "codex.exe"
}

foreach ($commandName in $versionMatchCommands) {
    $commands = @(Get-Command $commandName -All -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) {
        Add-Check "toolchain_resolution_$commandName" "fail" "$commandName is not resolvable." @{}
        continue
    }
    $firstSource = Resolve-FullPathMaybe ([string]$commands[0].Source)
    if (Test-Prefix -Path $firstSource -Prefixes $allowedCommandPrefixes) {
        Add-Check "toolchain_resolution_$commandName" "pass" "$commandName resolves first to a Codex-owned shim or official bundle path." @{
            first_source = $firstSource
        }
    } else {
        Add-Check "toolchain_resolution_$commandName" "fail" "$commandName resolves first to a non-Codex path." @{
            first_source = $firstSource
        }
    }

    $officialExeName = if ($officialExeNames.ContainsKey($commandName)) { $officialExeNames[$commandName] } else { "$commandName.exe" }
    $officialExe = if ($officialResources) { Join-Path $officialResources $officialExeName } else { $null }
    if ($officialExe -and (Test-Path -LiteralPath $officialExe)) {
        $args = if ($versionArgs.ContainsKey($commandName)) { [string[]]$versionArgs[$commandName] } else { [string[]]@("--version") }
        $observed = Invoke-VersionLine -Command $commandName -Arguments $args
        $official = Invoke-VersionLine -Command $officialExe -Arguments $args
        if ($observed.ok -and $official.ok -and $observed.line -eq $official.line) {
            Add-Check "toolchain_version_$commandName" "pass" "$commandName wrapper version matches the current official app resource." @{
                observed = $observed.line
                official = $official.line
            }
        } else {
            Add-Check "toolchain_version_$commandName" "fail" "$commandName wrapper version does not match the current official app resource." @{
                observed = $observed
                official = $official
            }
        }
    } else {
        Add-Check "toolchain_version_$commandName" "warn" "Official app resource for $commandName was not found for version comparison." @{
            official = $officialExe
        }
    }
}

$resolutionOnlyCommands = Get-StateArray $nativeCriteria.toolchain.resolution_only_commands @("node_repl")
foreach ($resolutionCommand in $resolutionOnlyCommands) {
    $resolutionCommands = @(Get-Command $resolutionCommand -All -ErrorAction SilentlyContinue)
    if ($resolutionCommands.Count -eq 0) {
        Add-Check "toolchain_resolution_$resolutionCommand" "fail" "$resolutionCommand is not resolvable." @{}
    } else {
        $firstResolutionSource = Resolve-FullPathMaybe ([string]$resolutionCommands[0].Source)
        if (Test-Prefix -Path $firstResolutionSource -Prefixes $allowedCommandPrefixes) {
            Add-Check "toolchain_resolution_$resolutionCommand" "pass" "$resolutionCommand resolves first to a Codex-owned shim or official bundle path." @{
                first_source = $firstResolutionSource
            }
        } else {
            Add-Check "toolchain_resolution_$resolutionCommand" "fail" "$resolutionCommand resolves first to a non-Codex path." @{
                first_source = $firstResolutionSource
            }
        }
    }
}

if ($CheckStoreUpgrade) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            $upgradeOutput = (& winget upgrade --source msstore 2>&1) -join "`n"
            if ($upgradeOutput -match '(?i)(\bCodex\b|OpenAI\.Codex|9PLM9XGG6VKS)') {
                Add-Check "store_upgrade_available" "warn" "Microsoft Store reports a possible Codex upgrade candidate." @{
                    output = $upgradeOutput
                }
            } else {
                Add-Check "store_upgrade_available" "pass" "Microsoft Store source reports no matching Codex upgrade." @{
                    output = $upgradeOutput
                }
            }
        } catch {
            Add-Check "store_upgrade_available" "warn" "winget upgrade check failed." @{
                error = $_.Exception.Message
            }
        }
    } else {
        Add-Check "store_upgrade_available" "warn" "winget is not available for Store upgrade check." @{}
    }
}

$failCount = @($script:Checks | Where-Object { $_.status -eq "fail" }).Count
$warnCount = @($script:Checks | Where-Object { $_.status -eq "warn" }).Count
$overall = if ($failCount -gt 0) { "fail" } elseif ($warnCount -gt 0) { "warn" } else { "pass" }
$checksArray = [object[]]$script:Checks.ToArray()

$result = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    codex_home = $codexHomePath
    criteria_path = $statePath
    criteria_schema_version = if ($structureState) { [string]$structureState.schema_version } else { $null }
    status = $overall
    failures = $failCount
    warnings = $warnCount
    observed = [ordered]@{
        official_app_version = if ($package) { [string]$package.Version } else { $null }
        official_app_install_location = if ($package) { [string]$package.InstallLocation } else { $null }
        workspace_runtime_versions = @($versionSet)
        allowed_plugin_cache_roots = if ($cacheNames) { @($cacheNames) } else { @() }
    }
    checks = $checksArray
}

if ($WriteReport) {
    $reportDir = Join-Path $codexHomePath "maintenance\reports"
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $latestPath = Join-Path $reportDir "codex-native-alignment.latest.json"
    $jsonText = $result | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($latestPath, $jsonText, [System.Text.UTF8Encoding]::new($false))
    $result.report_path = $latestPath
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
} else {
    "status=$overall; failures=$failCount; warnings=$warnCount"
    foreach ($check in $script:Checks) {
        "$($check.status) $($check.name): $($check.message)"
    }
    if ($result.Contains("report_path")) {
        "report_path=$($result.report_path)"
    }
}

if ($failCount -gt 0) {
    exit 1
}
