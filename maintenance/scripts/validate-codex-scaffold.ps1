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

$script:KeepSetManifest = $null
$script:KeepSetManifestStatus = [ordered]@{
    path = $null
    exists = $false
    parse_ok = $false
    fallback_used = $true
    error = $null
}

function Add-Check($items, $name, $status, $details) {
    $items.Add([ordered]@{ name = $name; status = $status; details = $details }) | Out-Null
}

function Get-NonNullArray {
    param([AllowNull()][object]$Value)

    $items = if ($null -eq $Value) {
        @()
    } else {
        @($Value | Where-Object { $null -ne $_ })
    }
    return ,$items
}

function Get-NonNullCount {
    param([AllowNull()][object]$Value)

    return (Get-NonNullArray -Value $Value).Count
}

function Get-RuntimeStatusView {
    param(
        [string]$CleanupScript,
        [string]$Root,
        [string]$Phase
    )

    $view = [ordered]@{
        phase = $Phase
        ok = $false
        status = $null
        error = $null
        app_servers = @()
        managed_roots = @()
        managed_orphans = @()
        optional_disabled_roots = @()
        duplicate_keys = @()
        watchers = @()
        reports_managed_orphans = $false
        reports_optional_disabled_roots = $false
    }

    try {
        $cleanupOutput = & $CleanupScript -Mode status -CodexHome $Root 2>&1
        $cleanupStatus = ($cleanupOutput | Out-String) | ConvertFrom-Json
        $view.ok = $true
        $view.status = $cleanupStatus
        $view.app_servers = Get-NonNullArray -Value $cleanupStatus.app_servers
        $view.managed_roots = Get-NonNullArray -Value $cleanupStatus.managed_roots
        $view.duplicate_keys = Get-NonNullArray -Value $cleanupStatus.duplicate_keys
        $view.watchers = Get-NonNullArray -Value $cleanupStatus.watchers
        $view.reports_managed_orphans = $null -ne $cleanupStatus.PSObject.Properties["managed_orphans"]
        $view.managed_orphans = if ($view.reports_managed_orphans) {
            Get-NonNullArray -Value $cleanupStatus.managed_orphans
        } else {
            @()
        }
        $view.reports_optional_disabled_roots = $null -ne $cleanupStatus.PSObject.Properties["optional_disabled_roots"]
        $view.optional_disabled_roots = if ($view.reports_optional_disabled_roots) {
            Get-NonNullArray -Value $cleanupStatus.optional_disabled_roots
        } else {
            @()
        }
    } catch {
        $view.error = $_.Exception.Message
    }

    return [pscustomobject]$view
}

function Test-RuntimeStatusViewClean {
    param([object]$View)

    return (
        $View.ok -and
        (Get-NonNullCount -Value $View.duplicate_keys) -eq 0 -and
        (Get-NonNullCount -Value $View.app_servers) -le 1 -and
        [bool]$View.reports_managed_orphans -and
        (Get-NonNullCount -Value $View.managed_orphans) -eq 0 -and
        [bool]$View.reports_optional_disabled_roots -and
        (Get-NonNullCount -Value $View.optional_disabled_roots) -eq 0
    )
}

function Get-KeepSetManifest {
    param([string]$Root)

    $keepSetPath = Join-Path $Root "maintenance\manifests\keep-set.json"
    if ($script:KeepSetManifestStatus.path -eq $keepSetPath -and $null -ne $script:KeepSetManifestStatus.path) {
        return $script:KeepSetManifest
    }

    $script:KeepSetManifest = $null
    $script:KeepSetManifestStatus = [ordered]@{
        path = $keepSetPath
        exists = $false
        parse_ok = $false
        fallback_used = $true
        error = $null
    }

    if (-not (Test-Path -LiteralPath $keepSetPath -PathType Leaf)) {
        $script:KeepSetManifestStatus.error = "missing"
        return $null
    }

    $script:KeepSetManifestStatus.exists = $true
    try {
        $script:KeepSetManifest = Get-Content -LiteralPath $keepSetPath -Raw | ConvertFrom-Json
        $script:KeepSetManifestStatus.parse_ok = $true
        $script:KeepSetManifestStatus.fallback_used = $false
    } catch {
        $script:KeepSetManifestStatus.error = $_.Exception.Message
    }

    return $script:KeepSetManifest
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

    $names = @()
    $keepSet = Get-KeepSetManifest -Root $Root
    if ($null -ne $keepSet) {
        $names = @($keepSet.runtime_keep_set.active_toolchain_shims | ForEach-Object { [string]$_ })
    }
    if ($names.Count -eq 0) {
        $script:KeepSetManifestStatus.fallback_used = $true
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

function Convert-ToComparablePath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    try {
        return ([IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))).TrimEnd("\").ToLowerInvariant()
    } catch {
        return $Path.TrimEnd("\").ToLowerInvariant()
    }
}

function Get-PluginRoot {
    param(
        [string]$CacheRoot,
        [string[]]$RequiredRelativePaths = @()
    )

    $latest = Join-Path $CacheRoot "latest"
    if (Test-Path -LiteralPath $latest -PathType Container) {
        $missingFromLatest = @($RequiredRelativePaths | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $latest $_))
        })
        if ($missingFromLatest.Count -eq 0) {
            return (Get-Item -LiteralPath $latest).FullName
        }
    }

    $versions = @()
    if (Test-Path -LiteralPath $CacheRoot -PathType Container) {
        $versions = @(Get-ChildItem -LiteralPath $CacheRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "latest" } |
            Where-Object {
                $root = $_.FullName
                @($RequiredRelativePaths | Where-Object {
                    -not (Test-Path -LiteralPath (Join-Path $root $_))
                }).Count -eq 0
            } |
            Sort-Object LastWriteTimeUtc -Descending)
    }

    if ($versions.Count -gt 0) {
        return $versions[0].FullName
    }
    return $null
}

function Test-InNoMistakesWorktree {
    $noMistakesWorktreeRoot = Join-Path $env:USERPROFILE ".no-mistakes\worktrees"
    try {
        $noMistakesWorktreeRootFull = ([System.IO.Path]::GetFullPath($noMistakesWorktreeRoot)).TrimEnd("\") + "\"
        $scriptFull = [System.IO.Path]::GetFullPath($PSCommandPath)
        $cwdFull = [System.IO.Path]::GetFullPath((Get-Location).Path)
        return (
            $scriptFull.StartsWith($noMistakesWorktreeRootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
            $cwdFull.StartsWith($noMistakesWorktreeRootFull, [System.StringComparison]::OrdinalIgnoreCase)
        )
    } catch {
        return $false
    }
}

function Remove-NoMistakesReposProjectTrustBlock {
    param([Parameter(Mandatory = $true)][string]$Text)

    $noMistakesReposPath = (Join-Path $env:USERPROFILE ".no-mistakes\repos") -replace "/", "\"
    $escapedNoMistakesReposPath = [regex]::Escape($noMistakesReposPath)
    $pattern = "(?im)^\s*\[projects\.'$escapedNoMistakesReposPath'\]\s*\r?\n\s*trust_level\s*=\s*`"trusted`"\s*(\r?\n)?"
    return [regex]::Replace($Text, $pattern, "")
}

function Test-FragmentReconcile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$AllowNoMistakesLocalProjectOverlay
    )

    $fragments = @("00-policy.toml", "10-mcp.toml", "20-hooks.toml", "30-skills.toml")
    $configText = Get-Content -LiteralPath (Join-Path $Root "config.toml") -Raw
    $missing = @()
    $mismatched = @()
    $allowedLocalOverlays = @()
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
            if ($AllowNoMistakesLocalProjectOverlay -and $name -eq "00-policy.toml") {
                $actualWithoutNoMistakesTrust = (Remove-NoMistakesReposProjectTrustBlock -Text $actualFragmentText).Trim()
                if ($actualWithoutNoMistakesTrust -eq $expectedFragmentText) {
                    $allowedLocalOverlays += "00-policy.toml: no-mistakes repos project trust"
                    continue
                }
            }
            $mismatched += $name
        }
    }

    return [ordered]@{
        ok = ($missing.Count -eq 0 -and $mismatched.Count -eq 0)
        missing = $missing
        mismatched = $mismatched
        allowed_local_overlays = $allowedLocalOverlays
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

$fragmentReconcile = Test-FragmentReconcile -Root $CodexHome -AllowNoMistakesLocalProjectOverlay:(Test-InNoMistakesWorktree)
Add-Check $checks "config_fragment_reconcile_match" ($(if ($fragmentReconcile.ok) { "pass" } else { "fail" })) @{
    missing = $fragmentReconcile.missing
    mismatched = $fragmentReconcile.mismatched
    allowed_local_overlays = $fragmentReconcile.allowed_local_overlays
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
    $requiredMcp = @("openaiDeveloperDocs")
    $retiredMcp = @("context7", "memento", "serena")
    $allowedMcp = @("chrome-devtools", "memento", "openaiDeveloperDocs", "serena")
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
        note = "PLAN baseline: openaiDeveloperDocs enabled, context7 absent from the MCP config, memento/serena absent or disabled, chrome-devtools absent or disabled by default, and node_repl not registered as a user MCP server."
    }
    $keepSet = Get-KeepSetManifest -Root $CodexHome
    $keepSetMcpProblems = New-Object System.Collections.Generic.List[string]
    $keepSetActiveMcp = @()
    $keepSetOptionalMcp = @()
    $keepSetRetiredMcp = @()
    if (-not [bool]$script:KeepSetManifestStatus.exists) {
        $keepSetMcpProblems.Add("keep-set manifest missing") | Out-Null
    } elseif (-not [bool]$script:KeepSetManifestStatus.parse_ok) {
        $keepSetMcpProblems.Add("keep-set manifest parse failed") | Out-Null
    } else {
        $keepSetActiveMcp = @($keepSet.runtime_keep_set.mcp_servers | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $keepSetOptionalMcp = @($keepSet.runtime_keep_set.optional_mcp_servers_disabled_by_default | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $keepSetRetiredMcp = @($keepSet.runtime_keep_set.retired_mcp_servers | ForEach-Object { [string]$_ } | Sort-Object -Unique)
        $activeDiff = @(Compare-Object -ReferenceObject @($requiredMcp | Sort-Object) -DifferenceObject $keepSetActiveMcp)
        if ($activeDiff.Count -gt 0) {
            $keepSetMcpProblems.Add("active MCP keep-set does not match required baseline") | Out-Null
        }
        $optionalDiff = @(Compare-Object -ReferenceObject @("chrome-devtools") -DifferenceObject $keepSetOptionalMcp)
        if ($optionalDiff.Count -gt 0) {
            $keepSetMcpProblems.Add("optional MCP keep-set does not match disabled-by-default baseline") | Out-Null
        }
        $retiredDiff = @(Compare-Object -ReferenceObject @($retiredMcp | Sort-Object) -DifferenceObject $keepSetRetiredMcp)
        if ($retiredDiff.Count -gt 0) {
            $keepSetMcpProblems.Add("retired MCP keep-set does not match retired baseline") | Out-Null
        }
        foreach ($name in @("chrome-devtools") + $retiredMcp) {
            if ($name -in $keepSetActiveMcp) {
                $keepSetMcpProblems.Add("$name must not be listed as an active keep-set MCP") | Out-Null
            }
        }
    }
    Add-Check $checks "keep_set_mcp_baseline" ($(if ($keepSetMcpProblems.Count -eq 0) { "pass" } else { "fail" })) @{
        manifest = $script:KeepSetManifestStatus
        active = $keepSetActiveMcp
        expected_active = $requiredMcp
        optional_disabled_by_default = $keepSetOptionalMcp
        expected_optional_disabled_by_default = @("chrome-devtools")
        retired = $keepSetRetiredMcp
        expected_retired = $retiredMcp
        problems = @($keepSetMcpProblems.ToArray())
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
    $productDesignScript = Join-Path $CodexHome "maintenance\scripts\ensure-product-design-marketplace.ps1"
    $productDesignStatus = $null
    $productDesignOk = $false
    if (Test-Path -LiteralPath $productDesignScript -PathType Leaf) {
        try {
            $productDesignOutput = & $productDesignScript -Mode status -CodexHome $CodexHome -Json 2>&1
            $productDesignStatus = ($productDesignOutput | Out-String) | ConvertFrom-Json
            $productDesignOk = [bool]$productDesignStatus.ok
        } catch {
            $productDesignStatus = [pscustomobject]@{ ok = $false; problems = @($_.Exception.Message) }
        }
    }
    Add-Check $checks "product_design_marketplace_registered" ($(if ($productDesignOk) { "pass" } else { "fail" })) @{
        script = $productDesignScript
        status = $productDesignStatus
        note = "Product Design is the retired ui-ux-pro-max replacement. It must be visible through a configured marketplace, cache manifest, config registration, and codex plugin list."
    }
    $computerRoot = Get-PluginRoot -CacheRoot (Join-Path $CodexHome "plugins\cache\openai-bundled\computer-use") -RequiredRelativePaths @(
        ".codex-plugin\plugin.json",
        "scripts\computer-use-client.mjs",
        "skills\computer-use\SKILL.md",
        "node_modules\@oai\sky\bin\windows\codex-computer-use.exe"
    )
    $selectedComputerHelper = if ($computerRoot) { Join-Path $computerRoot "node_modules\@oai\sky\bin\windows\codex-computer-use.exe" } else { "" }
    $notifyItems = @()
    if ($null -ne $config.notify) {
        $notifyItems = @($config.notify | ForEach-Object { [string]$_ })
    }
    $configuredNotifyExecutable = if ($notifyItems.Count -gt 0) { [string]$notifyItems[0] } else { "" }
    $configuredNotifyExists = (-not [string]::IsNullOrWhiteSpace($configuredNotifyExecutable)) -and (Test-Path -LiteralPath $configuredNotifyExecutable -PathType Leaf)
    $notifyMatchesSelectedHelper = (Convert-ToComparablePath $configuredNotifyExecutable) -eq (Convert-ToComparablePath $selectedComputerHelper)
    Add-Check $checks "computer_use_notify_matches_selected_helper" ($(if ($computerRoot -and (Test-Path -LiteralPath $selectedComputerHelper -PathType Leaf) -and $configuredNotifyExists -and $notifyMatchesSelectedHelper) { "pass" } else { "fail" })) @{
        computer_root = $computerRoot
        selected_helper = $selectedComputerHelper
        configured_notify = $configuredNotifyExecutable
        configured_notify_exists = $configuredNotifyExists
        notify_matches_selected_helper = $notifyMatchesSelectedHelper
        note = "The active notify executable must match the selected Computer Use helper so cache-version updates cannot leave a stale turn-ended hook hidden behind passing plugin-root checks."
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
        $initialRuntimeView = Get-RuntimeStatusView -CleanupScript $cleanupScript -Root $CodexHome -Phase "initial"
        $runtimeRecoveryActions = New-Object System.Collections.Generic.List[object]
        $cleanupStatus = $initialRuntimeView.status

        if (-not (Test-RuntimeStatusViewClean -View $initialRuntimeView)) {
            $hasRecoverableRoots = (Get-NonNullCount -Value $initialRuntimeView.managed_orphans) -gt 0 -or (Get-NonNullCount -Value $initialRuntimeView.optional_disabled_roots) -gt 0
            if ($initialRuntimeView.ok -and $hasRecoverableRoots) {
                $cleanupStaleOutput = & $cleanupScript -Mode cleanup-stale -CodexHome $CodexHome 2>&1
                $cleanupStaleText = ($cleanupStaleOutput | Out-String).Trim()
                $runtimeRecoveryActions.Add([ordered]@{
                    action = "cleanup-stale"
                    reason = "managed_orphans_or_optional_disabled_roots"
                    output_preview = ($cleanupStaleText -replace "`r?`n", " ").Substring(0, [Math]::Min(500, $cleanupStaleText.Length))
                }) | Out-Null
                Start-Sleep -Seconds 1
            } elseif ($initialRuntimeView.ok) {
                $runtimeRecoveryActions.Add([ordered]@{
                    action = "wait-and-resample"
                    reason = "duplicate_or_app_server_transition"
                    seconds = 4
                }) | Out-Null
                Start-Sleep -Seconds 4
            }

            $finalRuntimeView = Get-RuntimeStatusView -CleanupScript $cleanupScript -Root $CodexHome -Phase "after-recovery"
        } else {
            $finalRuntimeView = $initialRuntimeView
        }

        $cleanupStatus = $finalRuntimeView.status
        $duplicateRuntimeKeys = Get-NonNullArray -Value $finalRuntimeView.duplicate_keys
        $appServers = Get-NonNullArray -Value $finalRuntimeView.app_servers
        $managedRoots = Get-NonNullArray -Value $finalRuntimeView.managed_roots
        $reportsManagedOrphans = [bool]$finalRuntimeView.reports_managed_orphans
        $managedOrphans = Get-NonNullArray -Value $finalRuntimeView.managed_orphans
        $reportsOptionalDisabledRoots = [bool]$finalRuntimeView.reports_optional_disabled_roots
        $optionalDisabledRoots = Get-NonNullArray -Value $finalRuntimeView.optional_disabled_roots
        $runtimeRootsClean = Test-RuntimeStatusViewClean -View $finalRuntimeView
        Add-Check $checks "runtime_managed_roots_singleton" ($(if ($runtimeRootsClean) { "pass" } else { "fail" })) @{
            app_server_pid = $cleanupStatus.app_server_pid
            app_server_count = $appServers.Count
            duplicate_keys = $duplicateRuntimeKeys
            reports_managed_orphans = $reportsManagedOrphans
            reports_optional_disabled_roots = $reportsOptionalDisabledRoots
            initial_phase_clean = (Test-RuntimeStatusViewClean -View $initialRuntimeView)
            initial_error = $initialRuntimeView.error
            initial_counts = [ordered]@{
                app_server_count = Get-NonNullCount -Value $initialRuntimeView.app_servers
                duplicate_key_count = Get-NonNullCount -Value $initialRuntimeView.duplicate_keys
                managed_orphan_count = Get-NonNullCount -Value $initialRuntimeView.managed_orphans
                optional_disabled_root_count = Get-NonNullCount -Value $initialRuntimeView.optional_disabled_roots
            }
            recovery_actions = @($runtimeRecoveryActions.ToArray())
            final_phase = $finalRuntimeView.phase
            managed_roots = @($managedRoots | ForEach-Object {
                [ordered]@{ key = $_.Key; pid = $_.ProcessId; parent_pid = $_.ParentProcessId }
            })
            managed_orphans = @($managedOrphans | ForEach-Object {
                [ordered]@{ key = $_.Key; pid = $_.ProcessId; parent_pid = $_.ParentProcessId; name = $_.Name }
            })
            optional_disabled_roots = @($optionalDisabledRoots | ForEach-Object {
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

$activeSkillRetiredUiHits = @()
foreach ($skillName in $expectedSkills) {
    $skillPath = Join-Path $skillRoot (Join-Path $skillName "SKILL.md")
    if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
        $skillText = Get-Content -LiteralPath $skillPath -Raw
        if ($skillText.Contains("ui-ux-pro-max")) {
            $activeSkillRetiredUiHits += $skillPath
        }
    }
}
Add-Check $checks "active_skills_retired_ui_ux_absent" ($(if ($activeSkillRetiredUiHits.Count -eq 0) { "pass" } else { "fail" })) @{
    scanned_skills = $expectedSkills
    retired_reference_hits = $activeSkillRetiredUiHits
    note = "ui-ux-pro-max is retired for this workstation baseline. Active configured skills must not route work back to it."
}

$keepSetSkillProblems = New-Object System.Collections.Generic.List[string]
$keepSetSkills = @()
$keepSetForSkills = Get-KeepSetManifest -Root $CodexHome
if (-not [bool]$script:KeepSetManifestStatus.exists) {
    $keepSetSkillProblems.Add("keep-set manifest missing") | Out-Null
} elseif (-not [bool]$script:KeepSetManifestStatus.parse_ok) {
    $keepSetSkillProblems.Add("keep-set manifest parse failed") | Out-Null
} else {
    $keepSetSkills = @($keepSetForSkills.runtime_keep_set.skills | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $skillDiff = @(Compare-Object -ReferenceObject @($expectedSkills | Sort-Object) -DifferenceObject @($keepSetSkills | Sort-Object))
    if ($skillDiff.Count -gt 0) {
        $keepSetSkillProblems.Add("keep-set skill list does not match active configured skills") | Out-Null
    }
    if ("ui-ux-pro-max" -in $keepSetSkills) {
        $keepSetSkillProblems.Add("retired ui-ux-pro-max is still in keep-set skills") | Out-Null
    }
}
Add-Check $checks "keep_set_skills_match_config" ($(if ($keepSetSkillProblems.Count -eq 0) { "pass" } else { "fail" })) @{
    manifest = $script:KeepSetManifestStatus
    expected_from_config = $expectedSkills
    keep_set_skills = $keepSetSkills
    problems = @($keepSetSkillProblems.ToArray())
}

$shimRoot = Join-Path $CodexHome "toolchains\shims"
$actualShims = @(Get-ChildItem -File -LiteralPath $shimRoot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object)
$expectedShims = @(Get-ExpectedShimNames -Root $CodexHome -Config $config)
$keepSetShimProblems = New-Object System.Collections.Generic.List[string]
if (-not [bool]$script:KeepSetManifestStatus.exists) {
    $keepSetShimProblems.Add("keep-set manifest missing") | Out-Null
}
if (-not [bool]$script:KeepSetManifestStatus.parse_ok) {
    $keepSetShimProblems.Add("keep-set manifest parse failed") | Out-Null
}
if ([bool]$script:KeepSetManifestStatus.fallback_used) {
    $keepSetShimProblems.Add("fallback shim list used") | Out-Null
}
if ($expectedShims.Count -eq 0) {
    $keepSetShimProblems.Add("active_toolchain_shims is empty") | Out-Null
}
Add-Check $checks "keep_set_manifest_active_toolchain_shims" ($(if ($keepSetShimProblems.Count -eq 0) { "pass" } else { "fail" })) @{
    manifest = $script:KeepSetManifestStatus
    expected_count = $expectedShims.Count
    fallback_count = $fallbackExpectedShims.Count
    problems = @($keepSetShimProblems.ToArray())
}
$missingShims = @($expectedShims | Where-Object { $_ -notin $actualShims })
$extraShims = @($actualShims | Where-Object { $_ -notin $expectedShims })
Add-Check $checks "shims_exact_set" ($(if ($missingShims.Count -eq 0 -and $extraShims.Count -eq 0) { "pass" } else { "fail" })) @{
    actual = $actualShims
    expected = $expectedShims
    missing = $missingShims
    extra = $extraShims
}

$noMistakesShim = Join-Path $shimRoot "no-mistakes.cmd"
try {
    $previousTelemetry = $env:NO_MISTAKES_TELEMETRY
    $previousUpdateCheck = $env:NO_MISTAKES_NO_UPDATE_CHECK
    $env:NO_MISTAKES_TELEMETRY = "0"
    $env:NO_MISTAKES_NO_UPDATE_CHECK = "1"
    $noMistakesWorktreeRoot = Join-Path $env:USERPROFILE ".no-mistakes\worktrees"
    $noMistakesWorktreeRootFull = ""
    $runningInsideNoMistakesWorktree = $false
    try {
        $noMistakesWorktreeRootFull = ([System.IO.Path]::GetFullPath($noMistakesWorktreeRoot)).TrimEnd("\") + "\"
        $scriptFull = [System.IO.Path]::GetFullPath($PSCommandPath)
        $cwdFull = [System.IO.Path]::GetFullPath((Get-Location).Path)
        $runningInsideNoMistakesWorktree = (
            $scriptFull.StartsWith($noMistakesWorktreeRootFull, [System.StringComparison]::OrdinalIgnoreCase) -or
            $cwdFull.StartsWith($noMistakesWorktreeRootFull, [System.StringComparison]::OrdinalIgnoreCase)
        )
    } catch {
        $runningInsideNoMistakesWorktree = $false
    }
    $noMistakesRealCliProbeAllowed = -not $runningInsideNoMistakesWorktree
    $noMistakesRealCliProbeSkippedReason = if ($noMistakesRealCliProbeAllowed) {
        ""
    } else {
        "running inside no-mistakes gate worktree; recursive CLI/daemon calls are forbidden"
    }
    $noMistakesVersionOutput = if ($noMistakesRealCliProbeAllowed -and (Test-Path -LiteralPath $noMistakesShim -PathType Leaf)) {
        (& $noMistakesShim --version 2>&1 | Out-String).Trim()
    } else {
        ""
    }
    $noMistakesVersionExit = if ($noMistakesRealCliProbeAllowed) {
        if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    } else {
        $null
    }
    $noMistakesDoctorOutput = if ($noMistakesRealCliProbeAllowed -and (Test-Path -LiteralPath $noMistakesShim -PathType Leaf)) {
        (& $noMistakesShim doctor 2>&1 | Out-String).Trim()
    } else {
        ""
    }
    $noMistakesDoctorExit = if ($noMistakesRealCliProbeAllowed) {
        if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
    } else {
        $null
    }
    $noMistakesConfigPath = Join-Path $env:USERPROFILE ".no-mistakes\config.yaml"
    $noMistakesConfigText = if (Test-Path -LiteralPath $noMistakesConfigPath -PathType Leaf) {
        Get-Content -LiteralPath $noMistakesConfigPath -Raw
    } else {
        ""
    }
    $noMistakesShimText = if (Test-Path -LiteralPath $noMistakesShim -PathType Leaf) {
        Get-Content -LiteralPath $noMistakesShim -Raw
    } else {
        ""
    }
    $noMistakesWrapperProbeError = ""
    $noMistakesWrapperPathProbeOutput = ""
    $noMistakesWrapperPathProbeExit = $null
    $noMistakesWrapperPathProbeSanitizesVariants = $false
    $noMistakesWrapperPathProbePreservesOriginalEntries = $false
    $noMistakesWrapperBangProbeOutput = ""
    $noMistakesWrapperBangProbeExit = $null
    $noMistakesWrapperPreservesBangArgs = $false
    $noMistakesWrapperProbeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-no-mistakes-wrapper-probe-" + [guid]::NewGuid().ToString("N"))
    $previousPathForNoMistakesProbe = $env:PATH
    $previousLocalAppDataForNoMistakesProbe = $env:LOCALAPPDATA
    $previousBangArgProbe = $env:NO_MISTAKES_PROBE_ARG
    try {
        if (Test-Path -LiteralPath $noMistakesShim -PathType Leaf) {
            $fakeNoMistakesDir = Join-Path $noMistakesWrapperProbeRoot "no-mistakes"
            New-Item -ItemType Directory -Path $fakeNoMistakesDir -Force | Out-Null
            Copy-Item -LiteralPath $env:ComSpec -Destination (Join-Path $fakeNoMistakesDir "no-mistakes.exe") -Force
            $shimRootForward = $shimRoot -replace "\\", "/"
            $pathProbeOriginalBangEntry = "C:\Codex!PathProbe\Tools"
            $pathProbeOriginalSlashEntry = "C:/CodexPathProbe/Tools/"
            $pathProbeInputs = @($shimRoot, "$shimRoot\", $shimRootForward, "$shimRootForward/", $pathProbeOriginalBangEntry, $pathProbeOriginalSlashEntry)
            if ($previousPathForNoMistakesProbe) {
                $pathProbeInputs += $previousPathForNoMistakesProbe
            }
            $env:LOCALAPPDATA = $noMistakesWrapperProbeRoot
            $env:PATH = $pathProbeInputs -join ";"
            $noMistakesWrapperPathProbeOutput = (& $noMistakesShim /d /s /c "set PATH" 2>&1 | Out-String).Trim()
            $noMistakesWrapperPathProbeExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
            $pathProbeLine = @($noMistakesWrapperPathProbeOutput -split "\r?\n" | Where-Object { $_ -match "(?i)^path=" } | Select-Object -First 1)
            $pathProbeValue = if ($pathProbeLine.Count -gt 0) { ($pathProbeLine[0] -replace "(?i)^path=", "") } else { "" }
            $normalizedShimRoot = ($shimRoot -replace "/", "\").TrimEnd("\")
            $normalizedPathProbeEntries = @($pathProbeValue -split ";" | ForEach-Object {
                ($_ -replace "/", "\").TrimEnd("\")
            } | Where-Object { $_ })
            $noMistakesWrapperPathProbeSanitizesVariants = (
                $noMistakesWrapperPathProbeExit -eq 0 -and
                -not (@($normalizedPathProbeEntries | Where-Object { $_ -ieq $normalizedShimRoot }).Count -gt 0)
            )
            $noMistakesWrapperPathProbePreservesOriginalEntries = (
                $noMistakesWrapperPathProbeExit -eq 0 -and
                $pathProbeValue -like "*$pathProbeOriginalBangEntry*" -and
                $pathProbeValue -like "*$pathProbeOriginalSlashEntry*"
            )

            $env:NO_MISTAKES_PROBE_ARG = "CORRUPTED"
            $noMistakesWrapperBangProbeOutput = (& $noMistakesShim /d /s /c "echo !NO_MISTAKES_PROBE_ARG!" 2>&1 | Out-String).Trim()
            $noMistakesWrapperBangProbeExit = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
            $noMistakesWrapperPreservesBangArgs = (
                $noMistakesWrapperBangProbeExit -eq 0 -and
                $noMistakesWrapperBangProbeOutput -eq "!NO_MISTAKES_PROBE_ARG!"
            )
        }
    } catch {
        $noMistakesWrapperProbeError = $_.Exception.Message
    } finally {
        $env:PATH = $previousPathForNoMistakesProbe
        $env:LOCALAPPDATA = $previousLocalAppDataForNoMistakesProbe
        $env:NO_MISTAKES_PROBE_ARG = $previousBangArgProbe
        if (Test-Path -LiteralPath $noMistakesWrapperProbeRoot) {
            Remove-Item -LiteralPath $noMistakesWrapperProbeRoot -Recurse -Force
        }
    }
    $codexBatchShimPathPattern = "\.codex[\\/]toolchains[\\/]shims[\\/]codex\.cmd"
    $noMistakesCodexAgentUsesBatchShim = [bool]($noMistakesDoctorOutput -match $codexBatchShimPathPattern)
    $noMistakesConfigReady = (
        $noMistakesConfigText -match "(?m)^agent:\s*codex\s*$" -and
        $noMistakesConfigText -match "(?m)^\s*-\s*--sandbox\s*$" -and
        $noMistakesConfigText -match "(?m)^\s*-\s*danger-full-access\s*$" -and
        $noMistakesConfigText -match "(?m)^\s*-\s*--disable\s*$" -and
        $noMistakesConfigText -match "(?m)^\s*-\s*plugins\s*$" -and
        $noMistakesConfigText -match "(?m)^\s*-\s*--skip-git-repo-check\s*$" -and
        -not ($noMistakesConfigText -match $codexBatchShimPathPattern)
    )
    $noMistakesWrapperSanitizesPath = (
        $noMistakesShimText -match "CODEX_SHIM_DIR" -and
        $noMistakesShimText -match "NM_ORIGINAL_PATH" -and
        $noMistakesShimText -match "NM_PATH_ENTRY_ORIGINAL" -and
        $noMistakesShimText -match "NM_PATH_ENTRY_NORMALIZED" -and
        $noMistakesShimText -match "NO_MISTAKES_TELEMETRY=0" -and
        $noMistakesShimText -match "NO_MISTAKES_NO_UPDATE_CHECK=1"
    )
    $noMistakesDaemonRunning = if ($noMistakesRealCliProbeAllowed) {
        [bool]($noMistakesDoctorOutput -match "(?m)daemon\s+running")
    } else {
        $null
    }
    $noMistakesCodexAgentDetected = if ($noMistakesRealCliProbeAllowed) {
        [bool]($noMistakesDoctorOutput -match "(?m)codex\s+")
    } else {
        $null
    }
    $noMistakesCliDaemonProbeReady = if ($noMistakesRealCliProbeAllowed) {
        $noMistakesVersionExit -eq 0 -and
        $noMistakesDoctorExit -eq 0 -and
        $noMistakesVersionOutput -match "no-mistakes version" -and
        $noMistakesDaemonRunning -and
        $noMistakesCodexAgentDetected -and
        -not $noMistakesCodexAgentUsesBatchShim
    } else {
        $true
    }
    $noMistakesReady = (
        (Test-Path -LiteralPath $noMistakesShim -PathType Leaf) -and
        $noMistakesCliDaemonProbeReady -and
        $noMistakesConfigReady -and
        $noMistakesWrapperSanitizesPath -and
        $noMistakesWrapperPathProbeSanitizesVariants -and
        $noMistakesWrapperPathProbePreservesOriginalEntries -and
        $noMistakesWrapperPreservesBangArgs
    )
    Add-Check $checks "no_mistakes_gate_ready" ($(if ($noMistakesReady) { "pass" } else { "fail" })) @{
        shim = $noMistakesShim
        shim_exists = (Test-Path -LiteralPath $noMistakesShim -PathType Leaf)
        wrapper_sanitizes_codex_shim_path = $noMistakesWrapperSanitizesPath
        wrapper_path_probe_sanitizes_variants = $noMistakesWrapperPathProbeSanitizesVariants
        wrapper_path_probe_preserves_original_entries = $noMistakesWrapperPathProbePreservesOriginalEntries
        wrapper_path_probe_exit_code = $noMistakesWrapperPathProbeExit
        wrapper_bang_arg_preserved = $noMistakesWrapperPreservesBangArgs
        wrapper_bang_probe_exit_code = $noMistakesWrapperBangProbeExit
        wrapper_probe_error = $noMistakesWrapperProbeError
        config = $noMistakesConfigPath
        config_ready = $noMistakesConfigReady
        codex_args_include_skip_git_repo_check = [bool]($noMistakesConfigText -match "(?m)^\s*-\s*--skip-git-repo-check\s*$")
        running_inside_no_mistakes_worktree = $runningInsideNoMistakesWorktree
        no_mistakes_worktree_root = $noMistakesWorktreeRootFull
        real_cli_daemon_probe_allowed = $noMistakesRealCliProbeAllowed
        real_cli_daemon_probe_skipped_reason = $noMistakesRealCliProbeSkippedReason
        cli_daemon_probe_ready = $noMistakesCliDaemonProbeReady
        version_exit_code = $noMistakesVersionExit
        version_output = $noMistakesVersionOutput
        doctor_exit_code = $noMistakesDoctorExit
        daemon_running = $noMistakesDaemonRunning
        codex_agent_detected = $noMistakesCodexAgentDetected
        codex_agent_uses_batch_shim = $noMistakesCodexAgentUsesBatchShim
        batch_shim_path_pattern = $codexBatchShimPathPattern
        telemetry_env = $env:NO_MISTAKES_TELEMETRY
        update_check_env = $env:NO_MISTAKES_NO_UPDATE_CHECK
        note = "no-mistakes is adopted as the outer validation gate. The wrapper must keep Codex toolchain .cmd shims out of the child PATH so Codex shell commands resolve real pwsh.exe."
    }
    $env:NO_MISTAKES_TELEMETRY = $previousTelemetry
    $env:NO_MISTAKES_NO_UPDATE_CHECK = $previousUpdateCheck
} catch {
    Add-Check $checks "no_mistakes_gate_ready" "fail" @{
        shim = $noMistakesShim
        error = $_.Exception.Message
    }
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
    "docs\codex_frontend_quality_directive.md",
    "maintenance\PROJECT_WORKFLOW_CHAIN.md",
    "maintenance\WORKSTATION_MAINTENANCE.md",
    "maintenance\CODEX_STATE_MANAGEMENT.md",
    "maintenance\CODEX_SELF_MANAGEMENT_LOOP.md",
    "maintenance\MCP_RUNTIME_STATUS.md",
    "maintenance\CHROME_DEVTOOLS_MCP_OBSERVER.md",
    "maintenance\AGENT_TOOL_REQUIREMENTS.md",
    "maintenance\MEMORY_BOUNDARY_POLICY.md",
    "maintenance\AUTOMATION_TARGET_BOUNDARY.md",
    "maintenance\scripts\chrome-devtools-mcp-toggle.ps1",
    "maintenance\scripts\check-automation-plugin-health.ps1",
    "maintenance\scripts\ensure-product-design-marketplace.ps1",
    "skills\frontend-visual-debug\SKILL.md",
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

$frontendDirectivePath = Join-Path $managedRepoRoot "docs\codex_frontend_quality_directive.md"
$frontendDirectiveProblems = New-Object System.Collections.Generic.List[string]
$frontendDirectiveForbiddenTerms = @(
    "Mandatory Frontend-Specialized Workflow: Impeccable",
    "Required Impeccable Commands",
    "If a task touches visible UI, assume Impeccable is required",
    "IMPECCABLE_UNAVAILABLE",
    "impeccable_workflow_used",
    "use the Impeccable workflow as the dedicated frontend design process"
)
$frontendDirectiveText = ""
if (-not (Test-Path -LiteralPath $frontendDirectivePath -PathType Leaf)) {
    $frontendDirectiveProblems.Add("frontend directive missing") | Out-Null
} else {
    $frontendDirectiveText = Get-Content -LiteralPath $frontendDirectivePath -Raw
    if (-not ($frontendDirectiveText.Contains("Product Design") -and $frontendDirectiveText.Contains("product-design"))) {
        $frontendDirectiveProblems.Add("frontend directive does not name Product Design and product-design plugin") | Out-Null
    }
    if (-not $frontendDirectiveText.Contains("product_design_workflow_used")) {
        $frontendDirectiveProblems.Add("frontend deployment gate does not report product_design_workflow_used") | Out-Null
    }
    if (-not $frontendDirectiveText.Contains("impeccable_compat")) {
        $frontendDirectiveProblems.Add("frontend preflight does not classify Impeccable as compatibility-only") | Out-Null
    }
    foreach ($term in $frontendDirectiveForbiddenTerms) {
        if ($frontendDirectiveText.Contains($term)) {
            $frontendDirectiveProblems.Add("forbidden mandatory Impeccable term remains: $term") | Out-Null
        }
    }
}
Add-Check $checks "frontend_directive_product_design_aligned" ($(if ($frontendDirectiveProblems.Count -eq 0) { "pass" } else { "fail" })) @{
    directive = $frontendDirectivePath
    problems = @($frontendDirectiveProblems.ToArray())
    forbidden_terms = $frontendDirectiveForbiddenTerms
    note = "Frontend policy must use Product Design as the primary workflow and keep Impeccable only as optional compatibility when installed."
}

$syncPairs = @(
    "config.d\00-policy.toml",
    "config.d\10-mcp.toml",
    "config.d\20-hooks.toml",
    "config.d\30-skills.toml",
    "hooks\compact-codex-hook.ps1",
    "maintenance\CHROME_DEVTOOLS_MCP_OBSERVER.md",
    "maintenance\AGENT_TOOL_REQUIREMENTS.md",
    "maintenance\CODEX_STATE_MANAGEMENT.md",
    "maintenance\MEMORY_BOUNDARY_POLICY.md",
    "maintenance\AUTOMATION_TARGET_BOUNDARY.md",
    "maintenance\manifests\keep-set.json",
    "maintenance\scripts\compile-config.ps1",
    "maintenance\scripts\chrome-devtools-mcp-toggle.ps1",
    "maintenance\scripts\repair-chrome-plugin-runtime.ps1",
    "maintenance\scripts\ensure-product-design-marketplace.ps1",
    "maintenance\scripts\check-automation-plugin-health.ps1",
    "maintenance\scripts\codex-benchmark.ps1",
    "maintenance\scripts\codex-compact-summary.ps1",
    "maintenance\scripts\codex-context.ps1",
    "maintenance\scripts\codex-eval.ps1",
    "maintenance\scripts\codex-global-scan.ps1",
    "maintenance\scripts\codex-harness-apply.ps1",
    "maintenance\scripts\codex-harness-audit.ps1",
    "maintenance\scripts\codex-harness-doctor.ps1",
    "maintenance\scripts\codex-harness-plan.ps1",
    "maintenance\scripts\codex-harness-repair.ps1",
    "maintenance\scripts\codex-harness-uninstall.ps1",
    "maintenance\scripts\codex-runtime-process-cleanup.ps1",
    "maintenance\scripts\codex-merge-config.ps1",
    "maintenance\scripts\codex-repo-verify.ps1",
    "maintenance\scripts\codex-retrieve.ps1",
    "maintenance\scripts\codex-trajectory.ps1",
    "maintenance\scripts\codex-verify.ps1",
    "maintenance\scripts\codex_agent_harness.py",
    "maintenance\scripts\codex_agent_harness_base.py",
    "maintenance\scripts\codex_agent_harness_calibration.py",
    "maintenance\scripts\codex_agent_harness_lifecycle.py",
    "maintenance\scripts\codex_agent_harness_merge.py",
    "maintenance\scripts\codex_agent_harness_smoke.py",
    "maintenance\scripts\codex_agent_harness_status.py",
    "maintenance\scripts\codex_agent_harness_workflows.py",
    "maintenance\scripts\worker_watcher_templates.py",
    "maintenance\scripts\validate-codex-scaffold.ps1",
    "maintenance\scripts\codex-p0-integrity-loop.ps1",
    "maintenance\scripts\codex-home-maintenance.ps1",
    "maintenance\NAMING_CONVENTION.md",
    "toolchains\README.md",
    "toolchains\shims\no-mistakes.cmd",
    "skills\frontend-visual-debug\SKILL.md",
    "skills\git-easy-korean\SKILL.md",
    "skills\test-integrity-gate\SKILL.md"
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

$harnessWrapperExitPaths = @(
    "maintenance\scripts\codex-benchmark.ps1",
    "maintenance\scripts\codex-compact-summary.ps1",
    "maintenance\scripts\codex-context.ps1",
    "maintenance\scripts\codex-eval.ps1",
    "maintenance\scripts\codex-global-scan.ps1",
    "maintenance\scripts\codex-harness-apply.ps1",
    "maintenance\scripts\codex-harness-audit.ps1",
    "maintenance\scripts\codex-harness-doctor.ps1",
    "maintenance\scripts\codex-harness-plan.ps1",
    "maintenance\scripts\codex-harness-repair.ps1",
    "maintenance\scripts\codex-harness-uninstall.ps1",
    "maintenance\scripts\codex-merge-config.ps1",
    "maintenance\scripts\codex-repo-verify.ps1",
    "maintenance\scripts\codex-retrieve.ps1",
    "maintenance\scripts\codex-trajectory.ps1",
    "maintenance\scripts\codex-verify.ps1"
)
$harnessWrapperExitProblems = @()
foreach ($relativePath in $harnessWrapperExitPaths) {
    foreach ($rootPath in @($managedRepoRoot, $CodexHome)) {
        $scriptPath = Join-Path $rootPath $relativePath
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            $harnessWrapperExitProblems += "missing:$scriptPath"
            continue
        }
        $scriptText = Get-Content -Raw -LiteralPath $scriptPath
        if ($scriptText -notmatch "(?m)^\s*exit\s+\`$LASTEXITCODE\s*$") {
            $harnessWrapperExitProblems += "missing_exit_propagation:$scriptPath"
        }
        if ($scriptText -notmatch "--root" -or $scriptText -notmatch "Documents\\Codex") {
            $harnessWrapperExitProblems += "missing_managed_root_default:$scriptPath"
        }
    }
}
Add-Check $checks "harness_wrapper_exit_propagation" ($(if ($harnessWrapperExitProblems.Count -eq 0) { "pass" } else { "fail" })) @{
    checked = $harnessWrapperExitPaths
    problems = $harnessWrapperExitProblems
    note = "Harness PowerShell wrappers must target the managed source root and propagate Python's exit code so tracebacks cannot become false-success exit 0 results."
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
    "archived_logs",
    "archived_sessions",
    "attachments",
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
    "vendor_imports",
    "worktrees",
    ".sandbox",
    ".sandbox-bin",
    ".tmp",
    "tmp",
    "generated_images",
    "memories_extensions",
    "models_cache.json",
    "session_index.jsonl"
)
$protectedStateNames = @("auth.json","installation_id",".sandbox-secrets","cap_sid")
$sourceNames = @("tools")
$configStateNames = @(".codex-global-state.json",".codex-global-state.json.bak",".personality_migration","chrome-native-hosts.json","chrome-native-hosts-v2.json")
$quarantineNames = @("skills-disabled","archive")
$databaseState = @($topExtra | Where-Object { $_ -match '^(goals|logs|memories|state)_[0-9]+\.sqlite(-shm|-wal)?$' })
$classifiedNames = $liveRuntimeNames + $protectedStateNames + $sourceNames + $configStateNames + $quarantineNames + $databaseState
$uncategorizedTopExtra = @($topExtra | Where-Object { $_ -notin $classifiedNames })
$forbiddenActiveTop = @($topExtra | Where-Object { $_ -in @("bundled-marketplaces","codex-runtimes","wshobson-agents-scan") })
Add-Check $checks "live_runtime_hygiene" ($(if ($uncategorizedTopExtra.Count -eq 0 -and $forbiddenActiveTop.Count -eq 0) { "pass" } else { "fail" })) @{
    live_app_server_pid = $liveAppServerPid
    runtime_state = @($topExtra | Where-Object { $_ -in $liveRuntimeNames })
    protected_state = @($topExtra | Where-Object { $_ -in $protectedStateNames })
    durable_source_state = @($topExtra | Where-Object { $_ -in $sourceNames })
    config_state = @($topExtra | Where-Object { $_ -in $configStateNames })
    database_state = $databaseState
    quarantine_state = @($topExtra | Where-Object { $_ -in $quarantineNames })
    forbidden_active = $forbiddenActiveTop
    uncategorized_extra = $uncategorizedTopExtra
    note = "This check classifies live state instead of treating every live top-level path as scaffold failure. vendor_imports is allowed as app-created cache state, but active config/source references to it remain forbidden by stale-reference checks."
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

$automationHealthScript = Join-Path $CodexHome "maintenance\scripts\check-automation-plugin-health.ps1"
if (Test-Path -LiteralPath $automationHealthScript -PathType Leaf) {
    try {
        $automationHealthOutput = & $automationHealthScript -CodexHome $CodexHome -Json -ReportOnly 2>&1
        $automationHealth = ($automationHealthOutput | Out-String) | ConvertFrom-Json
        $automationHealthFailures = @($automationHealth.checks | Where-Object { $_.status -ne "pass" })
        $automationHealthCheckStatus = @($automationHealth.checks | ForEach-Object {
            [ordered]@{ name = $_.name; status = $_.status }
        })
        Add-Check $checks "automation_plugins_health" ($(if ([string]$automationHealth.overall_status -eq "pass") { "pass" } else { "fail" })) @{
            summary = $automationHealth.summary
            check_status = $automationHealthCheckStatus
            failures = $automationHealthFailures
            note = "Non-GUI automation plugin coverage: Browser static/syntax readiness, Chrome static/runtime/native-host diagnostics, Computer Use static/syntax/helper readiness, and node_repl stdio execution."
        }
    } catch {
        Add-Check $checks "automation_plugins_health" "fail" @{
            script = $automationHealthScript
            error = $_.Exception.Message
        }
    }
} else {
    Add-Check $checks "automation_plugins_health" "fail" @{ script = $automationHealthScript; error = "missing" }
}

$retiredMcpRuntimeProcesses = @()
try {
    $retiredMcpRuntimeProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $processName = [string]$_.Name
        $commandLine = [string]$_.CommandLine
        if ($processName -ieq "codex.exe") {
            return $false
        }
        ($processName -ieq "serena.exe" -and $commandLine -match "start-mcp-server") -or
            ($commandLine -match "(?i)(memento-mcp-runtime\.ps1|[\\/]memento-mcp([\\/]|\\b)|state[\\/]memento-mcp|tools[\\/]memento-mcp)") -or
            ($commandLine -match "(?i)@upstash[\\/]context7-mcp")
    })
} catch {
    $retiredMcpRuntimeProcesses = @()
}
Add-Check $checks "retired_mcp_runtime_processes_absent" ($(if ($retiredMcpRuntimeProcesses.Count -eq 0) { "pass" } else { "fail" })) @{
    count = $retiredMcpRuntimeProcesses.Count
    processes = @($retiredMcpRuntimeProcesses | ForEach-Object {
        [ordered]@{ pid = $_.ProcessId; parent_pid = $_.ParentProcessId; name = $_.Name; command_line = $_.CommandLine }
    })
    note = "PLAN removes Context7 and retires Serena and Memento MCP runtimes; no active context7, serena start-mcp-server, or memento-mcp runtime process should remain after runtime cleanup or app reload."
}

$failedChecks = @($checks | Where-Object { $_.status -ne "pass" })
$result = [ordered]@{
    generated_utc = (Get-Date).ToUniversalTime().ToString("o")
    codex_home = $CodexHome
    overall_status = $(if ($failedChecks.Count -eq 0) { "pass" } else { "fail" })
    fail_count = $failedChecks.Count
    summary = [ordered]@{
        check_count = $checks.Count
        fail_count = $failedChecks.Count
    }
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
