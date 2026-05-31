param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [switch]$Json,
    [switch]$ReportOnly
)

$ErrorActionPreference = "Stop"

$fallbackExpectedShims = @(
    "bun.cmd","cargo-clippy.cmd","cargo.cmd","code.cmd","codex.cmd","eslint.cmd",
    "fd.cmd","gh.cmd","git.cmd","jq.cmd","just.cmd","node.cmd","npm.cmd",
    "node_repl.cmd","npx.cmd","pip.cmd","pnpm.cmd","prettier.cmd","pwsh.cmd","py.cmd",
    "pytest.cmd","python.cmd","rg.cmd","rg.ps1","ruff.cmd","rustc.cmd",
    "rustfmt.cmd","rustup.cmd","tsc.cmd","tsx.cmd","uv.cmd","winget.cmd"
)

function Add-Check($items, $name, $status, $details) {
    $items.Add([ordered]@{ name = $name; status = $status; details = $details }) | Out-Null
}

function Get-ConfiguredSkillNames($config) {
    if ($null -eq $config.skills -or $null -eq $config.skills.config) {
        return @()
    }
    return @(@($config.skills.config) |
        Where-Object { $null -eq $_.enabled -or [bool]$_.enabled } |
        ForEach-Object { [string]$_.name } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object)
}

function Get-ExpectedShimNames {
    param(
        [string]$Root,
        [object]$Config
    )

    $keepSetPath = Join-Path $Root "maintenance\manifests\keep-set.json"
    $names = @()
    if (Test-Path -LiteralPath $keepSetPath -PathType Leaf) {
        try {
            $keepSet = Get-Content -LiteralPath $keepSetPath -Raw | ConvertFrom-Json
            $names = @($keepSet.runtime_keep_set.active_toolchain_shims | ForEach-Object { [string]$_ })
        } catch {
            $names = @()
        }
    }
    if ($names.Count -eq 0) {
        $names = @($fallbackExpectedShims)
    }

    return @($names | Sort-Object -Unique)
}

function Get-Sha256OrNull {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }
    return $null
}

function Get-ObjectPropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Test-ConfigItemEnabled {
    param([object]$Item)

    if ($null -eq $Item) {
        return $false
    }
    $enabled = $Item.PSObject.Properties["enabled"]
    if ($null -eq $enabled) {
        return $true
    }
    return [bool]$enabled.Value
}

function Resolve-CodexBundledTool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $binRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
    $direct = Join-Path $binRoot ($Name + ".exe")
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return $direct
    }

    if (Test-Path -LiteralPath $binRoot -PathType Container) {
        $match = Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $candidate = Join-Path $_.FullName ($Name + ".exe")
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Get-Item -LiteralPath $candidate
                }
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $match) {
            return $match.FullName
        }
    }

    return ""
}

function Test-FragmentReconcile {
    param([Parameter(Mandatory = $true)][string]$Root)

    $fragments = @("00-policy.toml", "10-mcp.toml", "20-hooks.toml", "30-skills.toml")
    $configText = Get-Content -LiteralPath (Join-Path $Root "config.toml") -Raw
    $missing = @()
    $mismatched = @()
    foreach ($name in $fragments) {
        $fragmentPath = Join-Path (Join-Path $Root "config.d") $name
        if (-not (Test-Path -LiteralPath $fragmentPath -PathType Leaf)) {
            $missing += $name
            continue
        }
        $fragmentText = (Get-Content -LiteralPath $fragmentPath -Raw).Trim()
        $pattern = "(?s)# BEGIN " + [regex]::Escape($name) + "\r?\n(.*?)\r?\n# END " + [regex]::Escape($name)
        $match = [regex]::Match($configText, $pattern)
        if (-not $match.Success) {
            $missing += $name
            continue
        }
        $actualFragmentText = ($match.Groups[1].Value.Trim() -replace "\r\n?", "`n")
        $expectedFragmentText = ($fragmentText -replace "\r\n?", "`n")
        if ($actualFragmentText -ne $expectedFragmentText) {
            $mismatched += $name
        }
    }

    return [ordered]@{
        ok = ($missing.Count -eq 0 -and $mismatched.Count -eq 0)
        missing = $missing
        mismatched = $mismatched
    }
}

function Test-BundleShimSource {
    param(
        [Parameter(Mandatory = $true)][string]$ShimRoot,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $extension = if ($Name -eq "rg-ps1") { "ps1" } else { "cmd" }
    $toolName = if ($Name -eq "rg-ps1") { "rg" } else { $Name }
    $shimName = if ($Name -eq "rg-ps1") { "rg.ps1" } else { "$Name.cmd" }
    $shimPath = Join-Path $ShimRoot $shimName
    $toolPath = Resolve-CodexBundledTool -Name $toolName
    $text = if (Test-Path -LiteralPath $shimPath -PathType Leaf) { Get-Content -LiteralPath $shimPath -Raw } else { "" }
    $usesBundleRoot = $text -match [regex]::Escape("%LOCALAPPDATA%\OpenAI\Codex\bin") -or $text -match [regex]::Escape("OpenAI\Codex\bin")
    $mentionsTool = $text -match [regex]::Escape($toolName + ".exe") -or $text -match ("(?i)(^|[^A-Za-z0-9_])" + [regex]::Escape($toolName) + "([^A-Za-z0-9_]|$)")
    return [ordered]@{
        name = $shimName
        extension = $extension
        shim = $shimPath
        bundled_tool = $toolPath
        bundled_tool_exists = (-not [string]::IsNullOrWhiteSpace($toolPath) -and (Test-Path -LiteralPath $toolPath -PathType Leaf))
        uses_bundle_root = [bool]$usesBundleRoot
        mentions_tool = [bool]$mentionsTool
        ok = ((-not [string]::IsNullOrWhiteSpace($toolPath)) -and (Test-Path -LiteralPath $toolPath -PathType Leaf) -and $usesBundleRoot -and $mentionsTool)
    }
}

function Test-FirstCommandSource {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ShimRoot
    )

    $bundleRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
    $windowsAppsCodexPattern = "*\WindowsApps\OpenAI.Codex_*\app\resources*"
    $command = @(Get-Command $Name -All -ErrorAction SilentlyContinue | Select-Object -First 1)
    $source = if ($command.Count -gt 0) {
        if (-not [string]::IsNullOrWhiteSpace([string]$command[0].Source)) {
            [string]$command[0].Source
        } elseif (-not [string]::IsNullOrWhiteSpace([string]$command[0].Path)) {
            [string]$command[0].Path
        } else {
            [string]$command[0].Definition
        }
    } else {
        ""
    }
    $ok = (
        -not [string]::IsNullOrWhiteSpace($source) -and (
            ((-not [string]::IsNullOrWhiteSpace($ShimRoot)) -and $source -like "$ShimRoot\*") -or
            ((-not [string]::IsNullOrWhiteSpace($bundleRoot)) -and $source -like "$bundleRoot\*") -or
            $source -like $windowsAppsCodexPattern
        )
    )
    return [ordered]@{
        name = $Name
        first_source = $source
        allowed_roots = @($ShimRoot, $bundleRoot, $windowsAppsCodexPattern)
        ok = [bool]$ok
    }
}

$checks = New-Object System.Collections.Generic.List[object]
$configPath = Join-Path $CodexHome "config.toml"
$hookPath = Join-Path $CodexHome "hooks\compact-codex-hook.ps1"
$manifestDir = Join-Path $CodexHome "maintenance\manifests"

Add-Check $checks "required_files" ($(if ((Test-Path $configPath) -and (Test-Path $hookPath) -and (Test-Path (Join-Path $CodexHome "AGENTS.md"))) { "pass" } else { "fail" })) @{
    config = $configPath
    hook = $hookPath
}

$fragmentReconcile = Test-FragmentReconcile -Root $CodexHome
Add-Check $checks "config_fragment_reconcile_match" ($(if ($fragmentReconcile.ok) { "pass" } else { "fail" })) @{
    missing = $fragmentReconcile.missing
    mismatched = $fragmentReconcile.mismatched
}

$parsed = & python -c "import sys,tomllib,json; p=sys.argv[1]; data=tomllib.load(open(p,'rb')); print(json.dumps(data, sort_keys=True))" $configPath
if ($LASTEXITCODE -eq 0) {
    $config = $parsed | ConvertFrom-Json
    $approvalPolicy = if ($config.PSObject.Properties["approval_policy"]) { [string]$config.approval_policy } else { "" }
    $windowsSandbox = if ($null -ne $config.windows -and $config.windows.PSObject.Properties["sandbox"]) { [string]$config.windows.sandbox } else { "" }
    $permissionPostureOk = (
        [string]$config.sandbox_mode -eq "danger-full-access" -and
        $approvalPolicy -eq "never" -and
        $windowsSandbox -eq "elevated"
    )
    Add-Check $checks "permission_posture_full_access_default" ($(if ($permissionPostureOk) { "pass" } else { "fail" })) @{
        sandbox_mode = [string]$config.sandbox_mode
        approval_policy = $approvalPolicy
        windows_sandbox = $windowsSandbox
        expected = @{
            sandbox_mode = "danger-full-access"
            approval_policy = "never"
            windows_sandbox = "elevated"
        }
        note = "User-requested workstation default is maximum local autonomy; this is execution permission, not completion authority."
    }
    $mcpServers = $config.mcp_servers
    $mcpNames = if ($null -ne $mcpServers) { @($mcpServers.PSObject.Properties.Name | Sort-Object) } else { @() }
    $requiredMcp = @("context7", "openaiDeveloperDocs")
    $retiredMcp = @("memento", "serena")
    $allowedMcp = @("chrome-devtools", "context7", "memento", "openaiDeveloperDocs", "serena")
    $mcpProblems = New-Object System.Collections.Generic.List[string]
    $missingOrDisabledMcp = New-Object System.Collections.Generic.List[string]
    foreach ($name in $requiredMcp) {
        $server = Get-ObjectPropertyValue -Object $mcpServers -Name $name
        if (-not (Test-ConfigItemEnabled -Item $server)) {
            $missingOrDisabledMcp.Add($name) | Out-Null
            $mcpProblems.Add("$name missing or disabled") | Out-Null
        }
    }
    $retiredPresentEnabled = New-Object System.Collections.Generic.List[string]
    foreach ($name in $retiredMcp) {
        $server = Get-ObjectPropertyValue -Object $mcpServers -Name $name
        if (Test-ConfigItemEnabled -Item $server) {
            $retiredPresentEnabled.Add($name) | Out-Null
            $mcpProblems.Add("$name is retired but enabled") | Out-Null
        }
    }
    $chromeServer = Get-ObjectPropertyValue -Object $mcpServers -Name "chrome-devtools"
    $chromeDefaultOff = ($null -eq $chromeServer -or -not (Test-ConfigItemEnabled -Item $chromeServer))
    if (-not $chromeDefaultOff) {
        $mcpProblems.Add("chrome-devtools is optional but enabled by default") | Out-Null
    }
    $nodeReplServer = Get-ObjectPropertyValue -Object $mcpServers -Name "node_repl"
    $nodeReplUserConfigured = ($null -ne $nodeReplServer)
    if ($nodeReplUserConfigured) {
        $mcpProblems.Add("node_repl is configured as a user MCP server") | Out-Null
    }
    $extraMcp = @($mcpNames | Where-Object { $_ -notin $allowedMcp -and $_ -ne "node_repl" })
    foreach ($name in $extraMcp) {
        $mcpProblems.Add("$name is outside the PLAN MCP baseline") | Out-Null
    }
    Add-Check $checks "mcp_plan_baseline" ($(if ($mcpProblems.Count -eq 0) { "pass" } else { "fail" })) @{
        actual = $mcpNames
        required_enabled = $requiredMcp
        missing_or_disabled_required = @($missingOrDisabledMcp.ToArray())
        retired_absent_or_disabled = $retiredMcp
        retired_present_enabled = @($retiredPresentEnabled.ToArray())
        optional_disabled_by_default = @("chrome-devtools")
        chrome_devtools_default_off = $chromeDefaultOff
        node_repl_user_mcp_configured = $nodeReplUserConfigured
        extra = $extraMcp
        problems = @($mcpProblems.ToArray())
        note = "PLAN baseline: openaiDeveloperDocs/context7 enabled, memento/serena absent or disabled, chrome-devtools absent or disabled by default, and node_repl not registered as a user MCP server."
    }
    $configJson = $config | ConvertTo-Json -Depth 20
    $hardcodedBundlePaths = @([regex]::Matches($configJson, '(?i)AppData\\\\Local\\\\OpenAI\\\\Codex\\\\bin\\\\[0-9a-f]{8,}\\\\[^"\\]+\.exe') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    $mcpCommandProblems = New-Object System.Collections.Generic.List[string]
    foreach ($name in $mcpNames) {
        $server = $config.mcp_servers.PSObject.Properties[$name].Value
        $command = [string]$server.command
        $args = @($server.args | ForEach-Object { [string]$_ })
        if ($command -in @("npx", "uvx")) {
            $mcpCommandProblems.Add("$name uses bare $command") | Out-Null
        }
        if ($args.Count -ge 2 -and $args[0] -eq "/c" -and $args[1] -in @("npx", "uvx")) {
            $mcpCommandProblems.Add("$name uses bare cmd /c $($args[1])") | Out-Null
        }
    }
    Add-Check $checks "mcp_command_sources_dynamic" ($(if ($hardcodedBundlePaths.Count -eq 0 -and $mcpCommandProblems.Count -eq 0) { "pass" } else { "fail" })) @{
        hardcoded_bundle_paths = $hardcodedBundlePaths
        command_problems = @($mcpCommandProblems.ToArray())
    }
    $marketplace = $config.marketplaces.PSObject.Properties["openai-bundled"].Value
    $marketplaceSource = if ($null -ne $marketplace) { [string]$marketplace.source } else { "" }
    $volatileMarketplaceSource = ($marketplaceSource -match '(?i)(\\\.tmp\\|\\tmp\\|bundled-marketplaces|plugins\\cache)')
    $marketplaceScript = Join-Path $CodexHome "maintenance\scripts\ensure-openai-bundled-marketplace.ps1"
    $marketplaceStatus = $null
    $marketplaceScriptOk = $false
    if (Test-Path -LiteralPath $marketplaceScript -PathType Leaf) {
        try {
            $marketplaceOutput = & $marketplaceScript -Mode status -CodexHome $CodexHome -Json 2>&1
            $marketplaceStatus = ($marketplaceOutput | Out-String) | ConvertFrom-Json
            $marketplaceScriptOk = [bool]$marketplaceStatus.ok
        } catch {
            $marketplaceScriptOk = $false
        }
    }
    Add-Check $checks "openai_bundled_marketplace_source_valid" ($(if ((-not $volatileMarketplaceSource) -and $marketplaceScriptOk) { "pass" } else { "fail" })) @{
        source = $marketplaceSource
        volatile_source = $volatileMarketplaceSource
        stable_path = $(if ($null -ne $marketplaceStatus) { $marketplaceStatus.stable_path } else { $null })
        link_target = $(if ($null -ne $marketplaceStatus) { $marketplaceStatus.link_target } else { $null })
    }
    $validatorSourcePath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $validatorText = [IO.File]::ReadAllText($validatorSourcePath, [Text.Encoding]::UTF8)
    $retiredHealthProbeTerms = @(
        ("Test-" + "TcpPort"),
        ("Get-" + "MementoEndpoint"),
        ("Test-" + "HttpHealth"),
        ("serena_" + "dashboard_auto_open_disabled"),
        ("memento_" + "http_ready")
    )
    $retiredHealthProbeHits = @($retiredHealthProbeTerms | Where-Object { $validatorText.Contains([string]$_) })
    Add-Check $checks "retired_mcp_health_probe_code_absent" ($(if ($retiredHealthProbeHits.Count -eq 0) { "pass" } else { "fail" })) @{
        forbidden_hits = $retiredHealthProbeHits
        note = "PLAN retires Serena and Memento as active MCPs. Validation must prove retirement by config/process absence, not by retired runtime health probes."
    }
    $hookCommands = @()
    foreach ($event in @("SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Stop")) {
        $groups = @($config.hooks.$event)
        foreach ($group in $groups) {
            foreach ($hook in @($group.hooks)) { $hookCommands += [string]$hook.command }
        }
    }
    $badHookCommands = @($hookCommands | Where-Object {
        [Environment]::ExpandEnvironmentVariables([string]$_) -notmatch [regex]::Escape($hookPath)
    })
    Add-Check $checks "hooks_one_runner" ($(if ($hookCommands.Count -eq 5 -and $badHookCommands.Count -eq 0) { "pass" } else { "fail" })) @{
        count = $hookCommands.Count
        bad = $badHookCommands
    }
} else {
    Add-Check $checks "config_parse" "fail" @{ path = $configPath }
}

$cleanupScript = Join-Path $CodexHome "maintenance\scripts\codex-runtime-process-cleanup.ps1"
if (Test-Path -LiteralPath $cleanupScript -PathType Leaf) {
    try {
        $cleanupOutput = & $cleanupScript -Mode status -CodexHome $CodexHome 2>&1
        $cleanupStatus = ($cleanupOutput | Out-String) | ConvertFrom-Json
        $duplicateRuntimeKeys = @($cleanupStatus.duplicate_keys)
        $appServers = @($cleanupStatus.app_servers)
        $managedRoots = @($cleanupStatus.managed_roots)
        $reportsManagedOrphans = $null -ne $cleanupStatus.PSObject.Properties["managed_orphans"]
        $managedOrphans = if ($reportsManagedOrphans -and $null -ne $cleanupStatus.managed_orphans) {
            @($cleanupStatus.managed_orphans | Where-Object { $null -ne $_ })
        } else {
            @()
        }
        Add-Check $checks "runtime_managed_roots_singleton" ($(if ($duplicateRuntimeKeys.Count -eq 0 -and $appServers.Count -le 1 -and $reportsManagedOrphans -and $managedOrphans.Count -eq 0) { "pass" } else { "fail" })) @{
            app_server_pid = $cleanupStatus.app_server_pid
            app_server_count = $appServers.Count
            duplicate_keys = $duplicateRuntimeKeys
            reports_managed_orphans = $reportsManagedOrphans
            managed_roots = @($managedRoots | ForEach-Object {
                [ordered]@{ key = $_.Key; pid = $_.ProcessId; parent_pid = $_.ParentProcessId }
            })
            managed_orphans = @($managedOrphans | ForEach-Object {
                [ordered]@{ key = $_.Key; pid = $_.ProcessId; parent_pid = $_.ParentProcessId; name = $_.Name }
            })
        }

        $watchers = @($cleanupStatus.watchers)
        $appServerPid = $cleanupStatus.app_server_pid
        $watcherMatches = @(
            if ($null -ne $appServerPid) {
                $watchers | Where-Object { $_.WatchedAppServerPid -eq $appServerPid -and [bool]$_.StopAppServerOnOwnerExit -and [bool]$_.StopAppServerOnOwnerNoVisibleWindow -and [bool]$_.CleanupRetiredRootsOnWatch }
            }
        )
        $hasCleanupWatcher = ($null -eq $appServerPid) -or (@($watcherMatches).Count -gt 0)
        Add-Check $checks "runtime_cleanup_watcher_active" ($(if ($hasCleanupWatcher) { "pass" } else { "fail" })) @{
            app_server_pid = $appServerPid
            watcher_pids = @($watcherMatches | ForEach-Object { $_.ProcessId })
            all_watchers = @($watchers | ForEach-Object {
                [ordered]@{ pid = $_.ProcessId; watched_app_server_pid = $_.WatchedAppServerPid; stop_app_server_on_owner_exit = $_.StopAppServerOnOwnerExit; stop_app_server_on_owner_no_visible_window = $_.StopAppServerOnOwnerNoVisibleWindow; cleanup_duplicate_roots_on_watch = $_.CleanupDuplicateRootsOnWatch; cleanup_retired_roots_on_watch = $_.CleanupRetiredRootsOnWatch; codex_home = $_.CodexHome; poll_seconds = $_.PollSeconds }
            })
            note = "When an app-server is live, a runtime cleanup watcher should enforce singleton MCP roots, remove retired roots, and clean up after owner exit or after the Codex owner has no visible window."
        }
    } catch {
        Add-Check $checks "runtime_cleanup_status" "fail" @{
            script = $cleanupScript
            error = $_.Exception.Message
        }
    }
} else {
    Add-Check $checks "runtime_cleanup_status" "fail" @{ script = $cleanupScript; error = "missing" }
}

$skillRoot = Join-Path $CodexHome "skills"
$actualSkills = @(Get-ChildItem -Directory -LiteralPath $skillRoot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object)
$userSkills = @($actualSkills | Where-Object { $_ -ne ".system" })
$expectedSkills = if ($null -ne $config) { @(Get-ConfiguredSkillNames $config) } else { @() }
$missingSkills = @($expectedSkills | Where-Object { $_ -notin $userSkills })
$extraSkills = @($userSkills | Where-Object { $_ -notin $expectedSkills })
Add-Check $checks "skills_exact_user_set" ($(if ($missingSkills.Count -eq 0 -and $extraSkills.Count -eq 0) { "pass" } else { "fail" })) @{
    actual_user_skills = $userSkills
    expected_from_config = $expectedSkills
    platform_exception = @($actualSkills | Where-Object { $_ -eq ".system" })
    missing = $missingSkills
    extra = $extraSkills
}

$shimRoot = Join-Path $CodexHome "toolchains\shims"
$actualShims = @(Get-ChildItem -File -LiteralPath $shimRoot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object)
$expectedShims = @(Get-ExpectedShimNames -Root $CodexHome -Config $config)
$missingShims = @($expectedShims | Where-Object { $_ -notin $actualShims })
$extraShims = @($actualShims | Where-Object { $_ -notin $expectedShims })
Add-Check $checks "shims_exact_set" ($(if ($missingShims.Count -eq 0 -and $extraShims.Count -eq 0) { "pass" } else { "fail" })) @{
    actual = $actualShims
    expected = $expectedShims
    missing = $missingShims
    extra = $extraShims
}

$bundleShimSources = @(
    (Test-BundleShimSource -ShimRoot $shimRoot -Name "codex"),
    (Test-BundleShimSource -ShimRoot $shimRoot -Name "node"),
    (Test-BundleShimSource -ShimRoot $shimRoot -Name "node_repl"),
    (Test-BundleShimSource -ShimRoot $shimRoot -Name "rg"),
    (Test-BundleShimSource -ShimRoot $shimRoot -Name "rg-ps1")
)
$badBundleShimSources = @($bundleShimSources | Where-Object { -not $_.ok })
Add-Check $checks "bundle_shim_sources_valid" ($(if ($badBundleShimSources.Count -eq 0) { "pass" } else { "fail" })) @{
    checked = $bundleShimSources
    bad = $badBundleShimSources
}

$firstCommandSources = @(
    (Test-FirstCommandSource -Name "codex" -ShimRoot $shimRoot),
    (Test-FirstCommandSource -Name "node" -ShimRoot $shimRoot),
    (Test-FirstCommandSource -Name "rg" -ShimRoot $shimRoot)
)
$badFirstCommandSources = @($firstCommandSources | Where-Object { -not $_.ok })
Add-Check $checks "official_tool_first_command_source" ($(if ($badFirstCommandSources.Count -eq 0) { "pass" } else { "fail" })) @{
    checked = $firstCommandSources
    bad = $badFirstCommandSources
}

$rgPs1 = Join-Path $shimRoot "rg.ps1"
$rgShimOutput = @()
$rgShimExit = $null
if (Test-Path -LiteralPath $rgPs1 -PathType Leaf) {
    $rgTemp = Join-Path ([IO.Path]::GetTempPath()) ("codex-rg-shim-" + [guid]::NewGuid().ToString("N") + ".txt")
    try {
        [IO.File]::WriteAllText($rgTemp, "ABC", [Text.Encoding]::ASCII)
        $rgShimOutput = @(& $rgPs1 -i "abc" $rgTemp 2>&1)
        $rgShimExit = $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $rgTemp -Force -ErrorAction SilentlyContinue
    }
}
Add-Check $checks "rg_ps1_argument_passthrough" ($(if ($rgShimExit -eq 0 -and (($rgShimOutput | Out-String) -match "ABC")) { "pass" } else { "fail" })) @{
    shim = $rgPs1
    exit_code = $rgShimExit
    output = (($rgShimOutput | Out-String).Trim())
}

$pathHits = @()
foreach ($scope in @("User","Machine")) {
    $value = [Environment]::GetEnvironmentVariable("Path", $scope)
    if ($value) {
        $pathHits += @($value -split ";" | Where-Object { $_ -match "\\.codex\\toolchains\\shims" } | ForEach-Object { "$scope`:$_" })
    }
}
Add-Check $checks "persistent_path_clean" ($(if ($pathHits.Count -eq 0) { "pass" } else { "fail" })) @{ hits = $pathHits }

$scanRoots = @(
    (Join-Path $CodexHome "AGENTS.md"),
    $configPath,
    (Join-Path $CodexHome "config.d"),
    (Join-Path $CodexHome "hooks"),
    (Join-Path $CodexHome "skills"),
    $manifestDir
)
$secretPatterns = "ghp_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|ctx7sk-[A-Za-z0-9-]+|mmcp_[A-Za-z0-9]+|BEGIN [A-Z ]*PRIVATE KEY|bearer_token\s*="
$secretHits = @()
foreach ($root in $scanRoots) {
    if (Test-Path -LiteralPath $root) {
        if ((Get-Item -LiteralPath $root).PSIsContainer) {
            $files = @(Get-ChildItem -Recurse -File -Force -LiteralPath $root -ErrorAction SilentlyContinue)
            foreach ($file in $files) {
                $secretHits += @(Select-String -Path $file.FullName -Pattern $secretPatterns -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Path):$($_.LineNumber)" })
            }
        } else {
            $secretHits += @(Select-String -Path $root -Pattern $secretPatterns -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Path):$($_.LineNumber)" })
        }
    }
}
Add-Check $checks "secret_scan" ($(if ($secretHits.Count -eq 0) { "pass" } else { "fail" })) @{ hits = $secretHits }

$managedRepoRoot = Join-Path $env:USERPROFILE "Documents\Codex"
$stateManagementDoc = Join-Path $managedRepoRoot "maintenance\CODEX_STATE_MANAGEMENT.md"
Add-Check $checks "codex_state_management_documented" ($(if (Test-Path -LiteralPath $stateManagementDoc -PathType Leaf) { "pass" } else { "fail" })) @{
    managed_repo_root = $managedRepoRoot
    document = $stateManagementDoc
    required_scope = @("cache", "logs", "memory", "folders", "files", "sync", "self-inspection")
    note = "Codex runtime state management must be documented in managed source, not inferred from old reports."
}

$selfManagementDoc = Join-Path $managedRepoRoot "maintenance\CODEX_SELF_MANAGEMENT_LOOP.md"
Add-Check $checks "codex_self_management_documented" ($(if (Test-Path -LiteralPath $selfManagementDoc -PathType Leaf) { "pass" } else { "fail" })) @{
    managed_repo_root = $managedRepoRoot
    document = $selfManagementDoc
    required_scope = @("full-access default", "managed/live sync", "automation model", "rollback")
    note = "Codex self-management and user-requested full-access posture must be documented in managed source."
}

$specOpsDoc = Join-Path $managedRepoRoot "maintenance\SPECOPS_OPERATING_MODEL.md"
$specOpsTemplates = @(
    "maintenance\templates\specops\feature-spec-template.md",
    "maintenance\templates\specops\architecture-contract-template.md",
    "maintenance\templates\specops\adr-template.md",
    "maintenance\templates\specops\spec-code-drift-report-template.md"
)
$missingSpecOpsTemplates = @($specOpsTemplates | Where-Object { -not (Test-Path -LiteralPath (Join-Path $managedRepoRoot $_) -PathType Leaf) })
Add-Check $checks "specops_operating_model_documented" ($(if ((Test-Path -LiteralPath $specOpsDoc -PathType Leaf) -and $missingSpecOpsTemplates.Count -eq 0) { "pass" } else { "fail" })) @{
    managed_repo_root = $managedRepoRoot
    document = $specOpsDoc
    templates = $specOpsTemplates
    missing_templates = $missingSpecOpsTemplates
    note = "The Vibe SpecOps pack is adapted as managed templates, not installed wholesale."
}

$activeGuidanceFiles = @(
    "AGENTS.md",
    "README.md",
    "maintenance\WORKSTATION_MAINTENANCE.md",
    "maintenance\CODEX_STATE_MANAGEMENT.md",
    "maintenance\CODEX_SELF_MANAGEMENT_LOOP.md",
    "maintenance\MCP_RUNTIME_STATUS.md",
    "maintenance\CHROME_DEVTOOLS_MCP_OBSERVER.md",
    "maintenance\AGENT_TOOL_REQUIREMENTS.md",
    "maintenance\scripts\chrome-devtools-mcp-toggle.ps1",
    "skills\codex-scaffold-validation\SKILL.md"
)
$activeGuidanceForbiddenTerms = @(
    ("memento-mcp-" + "runtime.ps1"),
    ("codex-p0-integrity-loop.ps1 -ReportOnly -Json -Skip" + "Scoop"),
    ("chrome_devtools_" + "observe"),
    ("memento_" + "http_ready"),
    ("serena_" + "dashboard_auto_open_disabled")
)
$activeGuidanceForbiddenHits = @()
foreach ($relativePath in $activeGuidanceFiles) {
    $path = Join-Path $managedRepoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }
    $text = Get-Content -LiteralPath $path -Raw
    foreach ($term in $activeGuidanceForbiddenTerms) {
        if ($text.Contains([string]$term)) {
            $activeGuidanceForbiddenHits += [ordered]@{ path = $path; term = [string]$term }
        }
    }
}
Add-Check $checks "active_guidance_retired_runtime_commands_absent" ($(if ($activeGuidanceForbiddenHits.Count -eq 0) { "pass" } else { "fail" })) @{
    scanned = @($activeGuidanceFiles)
    forbidden_hits = $activeGuidanceForbiddenHits
    note = "Active guidance must not reintroduce retired Memento/Serena checks or make ReportOnly+SkipScoop the final P0 command. Historical reports are intentionally not scanned here."
}

$syncPairs = @(
    "config.d\00-policy.toml",
    "config.d\10-mcp.toml",
    "config.d\20-hooks.toml",
    "config.d\30-skills.toml",
    "hooks\compact-codex-hook.ps1",
    "maintenance\CHROME_DEVTOOLS_MCP_OBSERVER.md",
    "maintenance\scripts\compile-config.ps1",
    "maintenance\scripts\chrome-devtools-mcp-toggle.ps1",
    "maintenance\scripts\repair-chrome-plugin-runtime.ps1",
    "maintenance\scripts\codex-runtime-process-cleanup.ps1",
    "maintenance\scripts\validate-codex-scaffold.ps1",
    "maintenance\scripts\codex-p0-integrity-loop.ps1",
    "maintenance\scripts\codex-home-maintenance.ps1",
    "maintenance\NAMING_CONVENTION.md"
)
$syncStatus = @()
if (Test-Path -LiteralPath $managedRepoRoot -PathType Container) {
    foreach ($relativePath in $syncPairs) {
        $managedPath = Join-Path $managedRepoRoot $relativePath
        $livePath = Join-Path $CodexHome $relativePath
        $managedHash = Get-Sha256OrNull -Path $managedPath
        $liveHash = Get-Sha256OrNull -Path $livePath
        $syncStatus += [ordered]@{
            relative_path = $relativePath
            managed_path = $managedPath
            live_path = $livePath
            managed_sha256 = $managedHash
            live_sha256 = $liveHash
            in_sync = ($null -ne $managedHash -and $managedHash -eq $liveHash)
        }
    }
}
$syncProblems = @($syncStatus | Where-Object { -not $_.in_sync })
Add-Check $checks "managed_source_live_sync" ($(if ((Test-Path -LiteralPath $managedRepoRoot -PathType Container) -and $syncProblems.Count -eq 0) { "pass" } else { "fail" })) @{
    managed_repo_root = $managedRepoRoot
    checked = $syncStatus
    problems = $syncProblems
    note = "Public-safe scripts and docs that live instructions call directly must stay byte-synced from managed source into CODEX_HOME."
}

$allowedTop = @("AGENTS.md","config.toml","config.d","hooks","skills","toolchains","maintenance","state","workflow")
$top = @(Get-ChildItem -Force -LiteralPath $CodexHome | Select-Object -ExpandProperty Name)
$topExtra = @($top | Where-Object { $_ -notin $allowedTop })
$liveAppServerPid = $null
try {
    if (Test-Path -LiteralPath $cleanupScript -PathType Leaf) {
        $liveStatus = (& $cleanupScript -Mode status -CodexHome $CodexHome 2>&1 | Out-String) | ConvertFrom-Json
        $liveAppServerPid = $liveStatus.app_server_pid
    }
} catch {
    $liveAppServerPid = $null
}
Add-Check $checks "offline_baseline_minimal" ($(if ($null -ne $liveAppServerPid -or $topExtra.Count -eq 0) { "pass" } else { "fail" })) @{
    live_app_server_pid = $liveAppServerPid
    extra = $topExtra
    note = "Offline baseline cleanup is enforced only after Codex is fully closed; live app-created runtime state is categorized separately."
}
$liveRuntimeNames = @(
    "artifacts",
    "automations",
    "browser",
    "cache",
    "computer-use",
    "memories",
    "node_repl",
    "packages",
    "pets",
    "plugins",
    "process_manager",
    "sessions",
    "sqlite",
    ".sandbox",
    ".sandbox-bin",
    ".tmp",
    "tmp",
    "models_cache.json",
    "session_index.jsonl"
)
$credentialNames = @("auth.json","installation_id",".sandbox-secrets")
$sourceNames = @("tools")
$configStateNames = @(".codex-global-state.json",".codex-global-state.json.bak",".personality_migration","chrome-native-hosts.json")
$quarantineNames = @("skills-disabled")
$databaseState = @($topExtra | Where-Object { $_ -match '^(goals|logs|memories|state)_[0-9]+\.sqlite(-shm|-wal)?$' })
$classifiedNames = $liveRuntimeNames + $credentialNames + $sourceNames + $configStateNames + $quarantineNames + $databaseState
$uncategorizedTopExtra = @($topExtra | Where-Object { $_ -notin $classifiedNames })
$forbiddenActiveTop = @($topExtra | Where-Object { $_ -in @("vendor_imports","bundled-marketplaces","codex-runtimes","wshobson-agents-scan") })
Add-Check $checks "live_runtime_hygiene" ($(if ($uncategorizedTopExtra.Count -eq 0 -and $forbiddenActiveTop.Count -eq 0) { "pass" } else { "fail" })) @{
    live_app_server_pid = $liveAppServerPid
    runtime_state = @($topExtra | Where-Object { $_ -in $liveRuntimeNames })
    credential_state = @($topExtra | Where-Object { $_ -in $credentialNames })
    durable_source_state = @($topExtra | Where-Object { $_ -in $sourceNames })
    config_state = @($topExtra | Where-Object { $_ -in $configStateNames })
    database_state = $databaseState
    quarantine_state = @($topExtra | Where-Object { $_ -in $quarantineNames })
    forbidden_active = $forbiddenActiveTop
    uncategorized_extra = $uncategorizedTopExtra
    note = "This check classifies live state instead of treating every live top-level path as scaffold failure."
}

$chromeRepairScript = Join-Path $CodexHome "maintenance\scripts\repair-chrome-plugin-runtime.ps1"
if (Test-Path -LiteralPath $chromeRepairScript -PathType Leaf) {
    try {
        $chromeOutput = & $chromeRepairScript -Mode status -CodexHome $CodexHome -Json 2>&1
        $chromeStatus = ($chromeOutput | Out-String) | ConvertFrom-Json
        Add-Check $checks "chrome_plugin_runtime_valid" ($(if ([bool]$chromeStatus.status.ok) { "pass" } else { "fail" })) @{
            latest_target = $chromeStatus.status.latest_target
            expected_host = $chromeStatus.status.expected_host
            native_manifest_path = $chromeStatus.status.native_manifest_path
            native_host_path = $chromeStatus.status.native_host_path
            problems = @($chromeStatus.status.problems)
        }
    } catch {
        Add-Check $checks "chrome_plugin_runtime_valid" "fail" @{
            script = $chromeRepairScript
            error = $_.Exception.Message
        }
    }
} else {
    Add-Check $checks "chrome_plugin_runtime_valid" "fail" @{ script = $chromeRepairScript; error = "missing" }
}

$retiredMcpRuntimeProcesses = @()
try {
    $retiredMcpRuntimeProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $processName = [string]$_.Name
        $commandLine = [string]$_.CommandLine
        ($processName -ieq "serena.exe" -and $commandLine -match "start-mcp-server") -or
            ($commandLine -match "(?i)(memento-mcp-runtime\.ps1|[\\/]memento-mcp([\\/]|\\b)|state[\\/]memento-mcp|tools[\\/]memento-mcp)")
    })
} catch {
    $retiredMcpRuntimeProcesses = @()
}
Add-Check $checks "retired_mcp_runtime_processes_absent" ($(if ($retiredMcpRuntimeProcesses.Count -eq 0) { "pass" } else { "fail" })) @{
    count = $retiredMcpRuntimeProcesses.Count
    processes = @($retiredMcpRuntimeProcesses | ForEach-Object {
        [ordered]@{ pid = $_.ProcessId; parent_pid = $_.ParentProcessId; name = $_.Name; command_line = $_.CommandLine }
    })
    note = "PLAN retires Serena and Memento MCP runtimes; no active serena start-mcp-server or memento-mcp runtime process should remain after runtime cleanup or app reload."
}

$failedChecks = @($checks | Where-Object { $_.status -ne "pass" })
$result = [ordered]@{
    generated_utc = (Get-Date).ToUniversalTime().ToString("o")
    codex_home = $CodexHome
    overall_status = $(if ($failedChecks.Count -eq 0) { "pass" } else { "fail" })
    fail_count = $failedChecks.Count
    checks = $checks
}

if ($Json) {
    $result | ConvertTo-Json -Depth 16
} else {
    "overall_status: {0}" -f $result.overall_status
    foreach ($check in $checks) {
        "{0}: {1}" -f $check.name, $check.status
    }
}

if ($failedChecks.Count -gt 0 -and -not $ReportOnly) {
    exit 1
}
