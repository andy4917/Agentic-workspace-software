[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Report', 'Clean')]
    [string]$Mode = 'Report',
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [switch]$IncludeTmp,
    [switch]$IncludeVendorImports,
    [switch]$IncludeDotTmp
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic

function New-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-DirectorySummary {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{
            path = $Path
            exists = $false
            item_count = 0
            bytes = 0
            last_write_time = $null
        }
    }

    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) {
        return [ordered]@{
            path = $Path
            exists = $true
            item_type = 'file'
            item_count = 0
            bytes = [int64]$item.Length
            last_write_time = $item.LastWriteTime.ToString('o')
        }
    }

    $children = @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue)
    $files = @($children | Where-Object { -not $_.PSIsContainer })
    $sum = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0 }

    return [ordered]@{
        path = $Path
        exists = $true
        item_type = 'directory'
        item_count = $children.Count
        bytes = [int64]$sum
        last_write_time = $item.LastWriteTime.ToString('o')
    }
}

function Get-ActiveReferenceMatches {
    param([string]$Root)

    $activeFiles = @(
        (Join-Path $Root 'config.toml'),
        (Join-Path $Root 'hooks.json'),
        (Join-Path $Root 'AGENTS.md')
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $pattern = '\\.tmp|\\tmp\\|vendor_imports|bundled-marketplaces|plugins\\plugins|wshobson-agents-scan|cache\\codex_apps_tools|plugins\\cache'
    $matches = @()
    foreach ($file in $activeFiles) {
        $hits = @(Select-String -LiteralPath $file -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue)
        foreach ($hit in $hits) {
            $matches += [ordered]@{
                path = $hit.Path
                line = $hit.LineNumber
                text = ($hit.Line.Trim() -replace '\s+', ' ')
            }
        }
    }
    return $matches
}

function Get-AppToolCacheSummary {
    param([string]$Root)

    $cacheRoot = Join-Path $Root 'cache\codex_apps_tools'
    if (-not (Test-Path -LiteralPath $cacheRoot)) {
        return @()
    }

    $summaries = @()
    foreach ($file in Get-ChildItem -LiteralPath $cacheRoot -File -Filter '*.json' -ErrorAction SilentlyContinue) {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $summaries += [ordered]@{
            file = $file.FullName
            bytes = $file.Length
            github_mentions = ([regex]::Matches($text, 'github', 'IgnoreCase')).Count
            supabase_mentions = ([regex]::Matches($text, 'supabase', 'IgnoreCase')).Count
            hugging_face_mentions = ([regex]::Matches($text, 'hugging|hugging-face', 'IgnoreCase')).Count
            twilio_mentions = ([regex]::Matches($text, 'twilio', 'IgnoreCase')).Count
            temporal_mentions = ([regex]::Matches($text, 'temporal', 'IgnoreCase')).Count
        }
    }
    return $summaries
}

function Send-ToRecycleBin {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $Path,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
}

function Compress-DirectoryIfNeeded {
    param(
        [string]$Path,
        [string]$ArchiveRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { return $null }

    New-Directory -Path $ArchiveRoot
    $leaf = Split-Path -Leaf $Path
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zip = Join-Path $ArchiveRoot "$leaf-$stamp.zip"
    Compress-Archive -LiteralPath $Path -DestinationPath $zip -Force
    return $zip
}

function Stop-GitFsmonitorUnderRoot {
    param([string]$Source)

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return @()
    }

    $repoRoots = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath (Join-Path $Source '.git')) {
        $repoRoots.Add($Source) | Out-Null
    }

    foreach ($gitDir in @(Get-ChildItem -LiteralPath $Source -Recurse -Force -Directory -Filter '.git' -ErrorAction SilentlyContinue)) {
        $repoRoot = Split-Path -Parent $gitDir.FullName
        if (-not [string]::IsNullOrWhiteSpace($repoRoot) -and $repoRoot -notin $repoRoots) {
            $repoRoots.Add($repoRoot) | Out-Null
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($repoRoot in @($repoRoots.ToArray())) {
        $statusOutput = $null
        $stopOutput = $null
        $statusExitCode = $null
        $stopExitCode = $null
        try {
            $statusOutput = & git -C $repoRoot fsmonitor--daemon status 2>&1
            $statusExitCode = $LASTEXITCODE
        } catch {
            $statusOutput = $_.Exception.Message
            $statusExitCode = 1
        }
        if (($statusOutput | Out-String) -match 'is watching') {
            try {
                $stopOutput = & git -C $repoRoot fsmonitor--daemon stop 2>&1
                $stopExitCode = $LASTEXITCODE
            } catch {
                $stopOutput = $_.Exception.Message
                $stopExitCode = 1
            }
        }
        $results.Add([ordered]@{
            repo_root = $repoRoot
            status_exit_code = $statusExitCode
            status = (($statusOutput | Out-String) -replace '\s+', ' ').Trim()
            stop_exit_code = $stopExitCode
            stop = (($stopOutput | Out-String) -replace '\s+', ' ').Trim()
        }) | Out-Null
    }

    return @($results.ToArray())
}

function Remove-TransientRoot {
    param(
        [string]$Source,
        [string]$ArchiveRoot
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return [ordered]@{
            source = $Source
            action = 'absent'
            destination = $null
            error = $null
        }
    }

    if ($PSCmdlet.ShouldProcess($Source, 'Send transient root to Recycle Bin')) {
        $fsmonitorStops = @(Stop-GitFsmonitorUnderRoot -Source $Source)
        $zip = $null
        try {
            $zip = Compress-DirectoryIfNeeded -Path $Source -ArchiveRoot $ArchiveRoot
            Send-ToRecycleBin -Path $Source
            return [ordered]@{
                source = $Source
                action = if ($zip) { 'compressed_then_recycled' } else { 'recycled' }
                archive = $zip
                destination = 'Recycle Bin'
                git_fsmonitor = $fsmonitorStops
                error = $null
            }
        }
        catch {
            return [ordered]@{
                source = $Source
                action = 'recycle_failed'
                archive = $zip
                destination = 'Recycle Bin'
                git_fsmonitor = $fsmonitorStops
                error = $_.Exception.Message
            }
        }
    }

    return [ordered]@{
        source = $Source
        action = 'would_recycle'
        archive = $null
        destination = 'Recycle Bin'
        git_fsmonitor = @()
        error = $null
    }
}

function Get-SentinelBlockerSummary {
    param([string]$Root)

    $targets = @(
        (Join-Path $Root 'vendor_imports'),
        (Join-Path $Root 'plugins\plugins')
    )

    return @($targets | ForEach-Object {
        $item = if (Test-Path -LiteralPath $_) { Get-Item -LiteralPath $_ -Force } else { $null }
        [ordered]@{
            path = $_
            exists = ($null -ne $item)
            item_type = if ($null -eq $item) { $null } elseif ($item.PSIsContainer) { 'directory' } else { 'file' }
            readonly = ($null -ne $item -and $item.IsReadOnly)
        }
    })
}

function Get-RuntimeGuardSummary {
    param([string]$Root)

    $configPath = Join-Path $Root 'config.toml'
    $statePath = Join-Path $Root '.codex-global-state.json'
    $config = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw } else { '' }
    $state = if (Test-Path -LiteralPath $statePath) { Get-Content -LiteralPath $statePath -Raw } else { '' }
    $configItem = if (Test-Path -LiteralPath $configPath) { Get-Item -LiteralPath $configPath -Force } else { $null }
    $stateItem = if (Test-Path -LiteralPath $statePath) { Get-Item -LiteralPath $statePath -Force } else { $null }

    return [ordered]@{
        config_readonly = ($null -ne $configItem -and $configItem.IsReadOnly)
        global_state_readonly = ($null -ne $stateItem -and $stateItem.IsReadOnly)
        features_plugins_enabled = ($config -match '(?m)^\s*plugins\s*=\s*true\s*$')
        workspace_dependencies_enabled = ($config -match '(?m)^\s*workspace_dependencies\s*=\s*true\s*$')
        bundled_marketplace_source_is_installed_app_bundle = ($config -match '(?s)\[marketplaces\.[^\]]*openai-bundled[^\]]*\].*?Program Files\\WindowsApps\\OpenAI\.Codex_')
        temp_or_bundled_source_absent = ($config -notmatch '(?i)(\\\.tmp\\|\\tmp\\|vendor_imports|bundled-marketplaces|plugins\\cache)')
        bundled_browser_plugin_disabled = ($config -match '(?s)\[plugins\."browser-use@openai-bundled"\].*?enabled\s*=\s*false')
        curated_github_plugin_disabled_to_avoid_temp_marketplace_clone = ($config -match '(?s)\[plugins\."github@openai-curated"\].*?enabled\s*=\s*false')
        browser_use_auto_install_disabled = ($state -match '"browser-use-bundled-plugin-auto-install-disabled"\s*:\s*true')
        site_creator_auto_install_disabled = ($state -match '"site-creator-bundled-plugin-auto-install-disabled"\s*:\s*true')
        run_codex_in_wsl_disabled = ($state -match '"runCodexInWindowsSubsystemForLinux"\s*:\s*false')
    }
}

function Get-NativeMessagingHostSummary {
    param([string]$Root)

    $userProfile = Split-Path -Parent $Root
    $manifestPath = Join-Path $userProfile 'AppData\Local\OpenAI\extension\com.openai.codexextension.json'
    $registryPath = 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension'
    $registryDefault = $null
    if (Test-Path -LiteralPath $registryPath) {
        try {
            $registryDefault = (Get-ItemProperty -LiteralPath $registryPath).'(default)'
        }
        catch {
            $registryDefault = '<unreadable>'
        }
    }

    $manifestHostPath = $null
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $manifestHostPath = $manifest.path
        }
        catch {
            $manifestHostPath = '<unreadable>'
        }
    }

    $staleFragments = @('plugins\cache', '\.tmp\', '\tmp\', 'bundled-marketplaces', 'codex-runtimes')
    $combined = @($registryDefault, $manifestHostPath) -join "`n"
    $hasStaleCacheReference = $false
    foreach ($fragment in $staleFragments) {
        if ($combined -like "*$fragment*") {
            $hasStaleCacheReference = $true
            break
        }
    }

    return [ordered]@{
        chrome_registry_key_exists = (Test-Path -LiteralPath $registryPath)
        chrome_registry_default = $registryDefault
        codex_extension_manifest_exists = (Test-Path -LiteralPath $manifestPath)
        codex_extension_manifest_path = $manifestPath
        codex_extension_host_path = $manifestHostPath
        stale_cache_reference = $hasStaleCacheReference
    }
}

function Get-PathSummary {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{
            path = $Path
            exists = $false
            item_count = 0
            bytes = 0
        }
    }

    $children = @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue)
    $files = @($children | Where-Object { -not $_.PSIsContainer })
    $sum = ($files | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0 }

    return [ordered]@{
        path = $Path
        exists = $true
        item_count = $children.Count
        bytes = [int64]$sum
    }
}

function Get-CommandResolutionSummary {
    param(
        [string[]]$Commands,
        [string]$ShimRoot
    )

    $summaries = @()
    $oldPath = $env:Path
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($ShimRoot) {
        $env:Path = "$ShimRoot;$userPath;$machinePath"
    }
    foreach ($command in $Commands) {
        $hits = @(where.exe $command 2>$null)
        $first = if ($hits.Count -gt 0) { $hits[0] } else { $null }
        $summaries += [ordered]@{
            command = $command
            count = $hits.Count
            first = $first
            uses_codex_shim = ($null -ne $first -and $first.StartsWith($ShimRoot, [System.StringComparison]::OrdinalIgnoreCase))
            all = $hits
        }
    }
    $env:Path = $oldPath
    return $summaries
}

function Get-PathHygieneSummary {
    $badPattern = '(?i)\\\.codex\\tmp|OpenAI\\Codex\\python|codex-runtimes|openai-primary-runtime|bundled-marketplaces'
    $userPath = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ })
    $processPath = @($env:Path -split ';' | Where-Object { $_ })

    return [ordered]@{
        user_bad_entries = @($userPath | Where-Object { $_ -match $badPattern })
        process_bad_entries = @($processPath | Where-Object { $_ -match $badPattern })
        user_missing_entries = @(
            foreach ($entry in $userPath) {
                $expanded = [Environment]::ExpandEnvironmentVariables($entry)
                if (-not (Test-Path -LiteralPath $expanded)) { $entry }
            }
        )
    }
}

function Get-EverythingNameSummary {
    param([string[]]$Queries)

    $es = Get-Command es.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $es) {
        return @([ordered]@{
            query = '<es.exe unavailable>'
            total = 0
            outside_recycle_and_desktop = 0
            samples = @()
        })
    }

    $summaries = @()
    foreach ($query in $Queries) {
        try {
            $raw = @(& $es.Source -path 'C:\' -p $query 2>&1)
            $exitCode = $LASTEXITCODE
        }
        catch {
            $summaries += [ordered]@{
                query = $query
                total = 0
                outside_recycle_and_desktop = 0
                samples = @()
                error = $_.Exception.Message
            }
            continue
        }

        if ($exitCode -ne 0) {
            $summaries += [ordered]@{
                query = $query
                total = 0
                outside_recycle_and_desktop = 0
                samples = @()
                error = ("es.exe exit " + [string]$exitCode + ": " + (($raw | Select-Object -First 1) -replace '\s+', ' '))
            }
            continue
        }

        $all = @($raw | ForEach-Object { [string]$_ })
        $outside = @($all | Where-Object {
            $_ -notlike 'C:\$Recycle.Bin\*' -and
            $_ -notlike 'C:\$SysReset\OldOS\$Recycle.Bin\*' -and
            $_ -notlike (Join-Path ([Environment]::GetFolderPath('Desktop')) '*')
        })
        $summaries += [ordered]@{
            query = $query
            total = $all.Count
            outside_recycle_and_desktop = $outside.Count
            samples = @($outside | Select-Object -First 10)
        }
    }
    return $summaries
}

function Get-ToolchainInventory {
    param([string]$Root)

    $userProfile = Split-Path -Parent $Root
    $rootPaths = @(
        (Join-Path $Root 'bin'),
        (Join-Path $Root 'cache'),
        (Join-Path $Root 'plugins'),
        (Join-Path $Root 'skills'),
        (Join-Path $Root 'toolchains'),
        (Join-Path $Root 'local-environments'),
        (Join-Path $userProfile 'AppData\Roaming\npm'),
        (Join-Path $userProfile 'AppData\Local\npm-cache'),
        (Join-Path $userProfile 'AppData\Local\pip\Cache'),
        (Join-Path $userProfile 'AppData\Local\uv\cache'),
        (Join-Path $userProfile 'AppData\Local\pnpm\store'),
        (Join-Path $userProfile 'scoop'),
        (Join-Path $userProfile '.cargo'),
        (Join-Path $userProfile '.rustup'),
        (Join-Path $userProfile '.vscode\cli\servers'),
        (Join-Path $userProfile 'AppData\Local\OpenAI\Codex')
    )

    return [ordered]@{
        command_resolution = Get-CommandResolutionSummary -ShimRoot (Join-Path $Root 'toolchains\shims') -Commands @(
            'node', 'npm', 'npx', 'pnpm', 'bun', 'deno',
            'python', 'py', 'pip', 'pipx', 'uv',
            'git', 'gh', 'rg', 'fd', 'fzf', 'jq', 'es', '7z', 'code', 'pwsh',
            'biome', 'eslint', 'prettier', 'pyright', 'tsc', 'tsserver', 'tsx', 'yarn', 'zx',
            'ruff', 'pytest', 'mypy', 'black', 'poetry', 'pdm', 'pre-commit', 'semgrep',
            'rustc', 'cargo', 'rustup', 'rustfmt', 'cargo-nextest', 'just', 'rust-analyzer',
            'java', 'javac', 'mvn', 'gradle', 'cmake', 'zig', 'cl', 'nmake', 'link', 'lib', 'dumpbin', 'rc',
            'scoop', 'winget', 'choco'
        )
        path_hygiene = Get-PathHygieneSummary
        root_summaries = @($rootPaths | ForEach-Object { Get-PathSummary -Path $_ })
        everything_name_audit = Get-EverythingNameSummary -Queries @(
            'openai-bundled',
            'openai-curated',
            'codex-runtime',
            'codex-runtimes',
            'bundled-marketplaces',
            'vendor_imports',
            'plugins\\plugins',
            'skills\\skills',
            'agents\\agents',
            'node_modules\\node_modules'
        )
        desktop_excluded = $true
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$maintenanceRoot = Join-Path $CodexHome 'maintenance'
$reportsRoot = Join-Path $maintenanceRoot 'reports'
$compressedRoot = Join-Path $maintenanceRoot 'compressed'
New-Directory -Path $reportsRoot

$transientRoots = @()
if ($IncludeDotTmp -or $Mode -eq 'Report') { $transientRoots += Join-Path $CodexHome '.tmp' }
if ($IncludeTmp -or $Mode -eq 'Report') { $transientRoots += Join-Path $CodexHome 'tmp' }
if ($IncludeVendorImports -or $Mode -eq 'Report') { $transientRoots += Join-Path $CodexHome 'vendor_imports' }

$before = @()
foreach ($root in $transientRoots) {
    $before += Get-DirectorySummary -Path $root
}

$moves = @()
if ($Mode -eq 'Clean') {
    foreach ($root in $transientRoots) {
        $moves += Remove-TransientRoot -Source $root -ArchiveRoot $compressedRoot
    }
}

$after = @()
foreach ($root in $transientRoots) {
    $after += Get-DirectorySummary -Path $root
}

$activeReferenceMatches = @(Get-ActiveReferenceMatches -Root $CodexHome)
$appToolCache = @(Get-AppToolCacheSummary -Root $CodexHome)

$report = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    mode = $Mode
    codex_home = $CodexHome
    cleanup_target = if ($Mode -eq 'Clean') { 'Recycle Bin' } else { $null }
    active_reference_matches = $activeReferenceMatches
    runtime_guards = Get-RuntimeGuardSummary -Root $CodexHome
    native_messaging_hosts = Get-NativeMessagingHostSummary -Root $CodexHome
    sentinel_blockers = Get-SentinelBlockerSummary -Root $CodexHome
    naming_convention = [ordered]@{
        document = (Join-Path $maintenanceRoot 'NAMING_CONVENTION.md')
        tool_and_cache_surfaces_visible_in_gitignore = $true
        desktop_excluded_from_mutation = $true
    }
    toolchain_inventory = Get-ToolchainInventory -Root $CodexHome
    transient_roots_before = $before
    transient_root_moves = $moves
    transient_roots_after = $after
    app_tool_cache = $appToolCache
    root_cause = 'Codex bundled marketplace registration uses .tmp/marketplaces as a runtime work directory. File sentinels at .tmp or tmp break plugin loading; guard temp paths by auditing active references and bounded contents instead of blocking directory creation.'
    policy = [ordered]@{
        keep_active_plugin_cache = @('plugins\cache as Codex plugin runtime cache only')
        keep_app_connector_tool_cache = @('cache\codex_apps_tools entries where connector_name is GitHub')
        plugin_feature_allowed = $true
        do_not_use_as_active_source = @('.tmp', 'tmp', 'vendor_imports', 'bundled-marketplaces', 'plugins\cache', 'plugins\plugins')
        remove_native_messaging_hosts_that_point_to_runtime_cache = $true
        temp_roots_are_not_blocked_by_sentinel = $true
        plugin_cache_roots_are_blocked_by_sentinel_until_runtime_fix = $false
        legacy_cleanup_target = 'Recycle Bin'
    }
}

$reportPath = Join-Path $reportsRoot 'codex-home-maintenance.latest.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report
