param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$expectedSkills = @(
    "andrej-karpathy-skill",
    "vowline",
    "keep-codex-fast",
    "clean-all-slop",
    "code-review-and-quality",
    "debugging-and-error-recovery",
    "roast-workstation-workflow"
)
$expectedMcp = @("chrome-devtools", "context7", "memento", "serena")
$expectedShims = @(
    "bun.cmd","cargo-clippy.cmd","cargo.cmd","code.cmd","codex.cmd","eslint.cmd",
    "fd.cmd","gh.cmd","git.cmd","jq.cmd","just.cmd","node.cmd","npm.cmd",
    "npx.cmd","pip.cmd","pnpm.cmd","prettier.cmd","pwsh.cmd","py.cmd",
    "pytest.cmd","python.cmd","rg.cmd","rg.ps1","ruff.cmd","rustc.cmd",
    "rustfmt.cmd","rustup.cmd","tsc.cmd","tsx.cmd","uv.cmd","winget.cmd"
)

function Add-Check($items, $name, $status, $details) {
    $items.Add([ordered]@{ name = $name; status = $status; details = $details }) | Out-Null
}

function Test-TcpPort($hostName, $port, $timeoutMs) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($hostName, $port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($timeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
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
        if ($match.Groups[1].Value.Trim() -ne $fragmentText) {
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
    $mentionsTool = $text -match [regex]::Escape($toolName + ".exe")
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
    $mcpNames = @($config.mcp_servers.PSObject.Properties.Name | Sort-Object)
    $missingMcp = @($expectedMcp | Where-Object { $_ -notin $mcpNames })
    $extraMcp = @($mcpNames | Where-Object { $_ -notin $expectedMcp })
    Add-Check $checks "mcp_exact_set" ($(if ($missingMcp.Count -eq 0 -and $extraMcp.Count -eq 0) { "pass" } else { "fail" })) @{
        actual = $mcpNames
        missing = $missingMcp
        extra = $extraMcp
    }
    $serenaArgs = @($config.mcp_servers.serena.args)
    $openFlagIndex = [Array]::IndexOf($serenaArgs, "--open-web-dashboard")
    $serenaArgDisablesOpen = ($openFlagIndex -ge 0 -and $serenaArgs.Count -gt ($openFlagIndex + 1) -and [string]$serenaArgs[$openFlagIndex + 1] -match "^(?i:false)$")
    $serenaConfigPath = Join-Path $env:USERPROFILE ".serena\serena_config.yml"
    $serenaGlobalDisablesOpen = $false
    if (Test-Path -LiteralPath $serenaConfigPath -PathType Leaf) {
        $serenaGlobalDisablesOpen = [bool](Select-String -LiteralPath $serenaConfigPath -Pattern "^\s*web_dashboard_open_on_launch:\s*false\s*$" -Quiet)
    }
    Add-Check $checks "serena_dashboard_auto_open_disabled" ($(if ($serenaArgDisablesOpen -and $serenaGlobalDisablesOpen) { "pass" } else { "fail" })) @{
        codex_args_has_open_false = $serenaArgDisablesOpen
        global_config_has_open_false = $serenaGlobalDisablesOpen
        global_config = $serenaConfigPath
    }
    Add-Check $checks "memento_http_ready" ($(if (Test-TcpPort "127.0.0.1" 57332 750) { "pass" } else { "fail" })) @{
        url = "http://127.0.0.1:57332/mcp"
        note = "Registration is not enough; the local HTTP server must be listening for tools to load."
    }
    $hookCommands = @()
    foreach ($event in @("SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Stop")) {
        $groups = @($config.hooks.$event)
        foreach ($group in $groups) {
            foreach ($hook in @($group.hooks)) { $hookCommands += [string]$hook.command }
        }
    }
    $badHookCommands = @($hookCommands | Where-Object { $_ -notmatch [regex]::Escape($hookPath) })
    Add-Check $checks "hooks_one_runner" ($(if ($hookCommands.Count -eq 5 -and $badHookCommands.Count -eq 0) { "pass" } else { "fail" })) @{
        count = $hookCommands.Count
        bad = $badHookCommands
    }
} else {
    Add-Check $checks "config_parse" "fail" @{ path = $configPath }
}

$skillRoot = Join-Path $CodexHome "skills"
$actualSkills = @(Get-ChildItem -Directory -LiteralPath $skillRoot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object)
$userSkills = @($actualSkills | Where-Object { $_ -ne ".system" })
$missingSkills = @($expectedSkills | Where-Object { $_ -notin $userSkills })
$extraSkills = @($userSkills | Where-Object { $_ -notin $expectedSkills })
Add-Check $checks "skills_exact_user_set" ($(if ($missingSkills.Count -eq 0 -and $extraSkills.Count -eq 0) { "pass" } else { "fail" })) @{
    actual_user_skills = $userSkills
    platform_exception = @($actualSkills | Where-Object { $_ -eq ".system" })
    missing = $missingSkills
    extra = $extraSkills
}

$shimRoot = Join-Path $CodexHome "toolchains\shims"
$actualShims = @(Get-ChildItem -File -LiteralPath $shimRoot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Sort-Object)
$missingShims = @($expectedShims | Where-Object { $_ -notin $actualShims })
$extraShims = @($actualShims | Where-Object { $_ -notin $expectedShims })
Add-Check $checks "shims_exact_set" ($(if ($missingShims.Count -eq 0 -and $extraShims.Count -eq 0) { "pass" } else { "fail" })) @{
    actual = $actualShims
    missing = $missingShims
    extra = $extraShims
}

$bundleShimSources = @(
    (Test-BundleShimSource -ShimRoot $shimRoot -Name "codex"),
    (Test-BundleShimSource -ShimRoot $shimRoot -Name "node"),
    (Test-BundleShimSource -ShimRoot $shimRoot -Name "rg"),
    (Test-BundleShimSource -ShimRoot $shimRoot -Name "rg-ps1")
)
$badBundleShimSources = @($bundleShimSources | Where-Object { -not $_.ok })
Add-Check $checks "bundle_shim_sources_valid" ($(if ($badBundleShimSources.Count -eq 0) { "pass" } else { "fail" })) @{
    checked = $bundleShimSources
    bad = $badBundleShimSources
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

$allowedTop = @("AGENTS.md","config.toml","config.d","hooks","skills","toolchains","maintenance","state","workflow")
$top = @(Get-ChildItem -Force -LiteralPath $CodexHome | Select-Object -ExpandProperty Name)
$topExtra = @($top | Where-Object { $_ -notin $allowedTop })
Add-Check $checks "hot_runtime_top_level_minimal" ($(if ($topExtra.Count -eq 0) { "pass" } else { "fail" })) @{
    extra = $topExtra
    note = "Run only after Codex is fully closed if live app-created state must be removed."
}

$serenaServerProcesses = @()
try {
    $serenaServerProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        [string]$_.Name -ieq "serena.exe" -and [string]$_.CommandLine -match "start-mcp-server"
    })
} catch {
    $serenaServerProcesses = @()
}
Add-Check $checks "serena_single_server_process" ($(if ($serenaServerProcesses.Count -le 1) { "pass" } else { "fail" })) @{
    count = $serenaServerProcesses.Count
    process_ids = @($serenaServerProcesses | ForEach-Object { $_.ProcessId })
    note = "Counts Serena server roots, not wrapper cmd/uv/python helper processes."
}

$result = [ordered]@{
    generated_utc = (Get-Date).ToUniversalTime().ToString("o")
    codex_home = $CodexHome
    checks = $checks
}

if ($Json) {
    $result | ConvertTo-Json -Depth 16
} else {
    foreach ($check in $checks) {
        "{0}: {1}" -f $check.name, $check.status
    }
}
