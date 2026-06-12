param(
    [ValidateSet("status", "repair")]
    [string]$Mode = "status",
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "codex-bundled-tools.ps1")

function Join-PathStrict {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Child
    )
    return [IO.Path]::Combine($Base, $Child)
}

function ConvertTo-ComparablePath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    try {
        return ([IO.Path]::GetFullPath($Path)).TrimEnd("\", "/").Replace("/", "\")
    } catch {
        return ([string]$Path).TrimEnd("\", "/").Replace("/", "\")
    }
}

function Test-CmdShimPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    return ([string]$Path) -match '(?i)\.cmd$'
}

function Get-ChromeVersionCandidates {
    param([string]$CacheRoot)

    if (-not (Test-Path -LiteralPath $CacheRoot -PathType Container)) {
        return @()
    }

    @(Get-ChildItem -LiteralPath $CacheRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "latest" } |
        ForEach-Object {
            $root = $_.FullName
            $hostPath = Join-PathStrict $root "extension-host\windows\x64\extension-host.exe"
            $pluginJson = Join-PathStrict $root ".codex-plugin\plugin.json"
            $installManifest = Join-PathStrict $root "scripts\installManifest.mjs"
            $checkManifest = Join-PathStrict $root "scripts\check-native-host-manifest.js"
            [pscustomobject]@{
                version = $_.Name
                root = $root
                host = $hostPath
                plugin_json = $pluginJson
                install_manifest = $installManifest
                check_manifest = $checkManifest
                complete = ((Test-Path -LiteralPath $hostPath -PathType Leaf) -and
                    (Test-Path -LiteralPath $pluginJson -PathType Leaf) -and
                    (Test-Path -LiteralPath $installManifest -PathType Leaf) -and
                    (Test-Path -LiteralPath $checkManifest -PathType Leaf))
                last_write_utc = $_.LastWriteTimeUtc.ToString("o")
            }
        } |
        Where-Object { $_.complete } |
        Sort-Object last_write_utc -Descending)
}

function Get-LatestTarget {
    param([string]$LatestPath)

    if (-not (Test-Path -LiteralPath $LatestPath)) {
        return $null
    }

    $item = Get-Item -LiteralPath $LatestPath -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $target = @($item.Target | Select-Object -First 1)[0]
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            return [IO.Path]::GetFullPath($target)
        }
    }

    return [IO.Path]::GetFullPath($item.FullName)
}

function Set-LatestJunction {
    param(
        [string]$LatestPath,
        [string]$TargetPath
    )

    $targetFull = [IO.Path]::GetFullPath($TargetPath)
    $currentTarget = Get-LatestTarget -LatestPath $LatestPath
    if ($null -ne $currentTarget -and $currentTarget.TrimEnd("\") -ieq $targetFull.TrimEnd("\")) {
        return "latest-already-correct"
    }

    if (Test-Path -LiteralPath $LatestPath) {
        $item = Get-Item -LiteralPath $LatestPath -Force
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing to replace non-reparse latest directory: $LatestPath"
        }
        Remove-Item -LiteralPath $LatestPath -Force
    }

    New-Item -ItemType Junction -Path $LatestPath -Target $targetFull | Out-Null
    return "latest-junction-updated"
}

function Get-ExtensionHostProcesses {
    param([string]$CacheRoot)

    try {
        return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            [string]$_.Name -ieq "extension-host.exe" -or
                ([string]$_.CommandLine -match "extension-host" -and [string]$_.CommandLine -match [regex]::Escape($CacheRoot))
        } | Select-Object ProcessId, ParentProcessId, Name, CommandLine)
    } catch {
        return @(Get-Process -Name "extension-host" -ErrorAction SilentlyContinue | Select-Object @{Name = "ProcessId"; Expression = { $_.Id } }, @{Name = "ParentProcessId"; Expression = { $null } }, @{Name = "Name"; Expression = { $_.ProcessName + ".exe" } }, @{Name = "CommandLine"; Expression = { "" } })
    }
}

function Get-NativeManifestPath {
    return Join-PathStrict $env:LOCALAPPDATA "OpenAI\extension\com.openai.codexextension.json"
}

function Get-ChromePluginMetadata {
    param([string]$PluginRoot)

    $metadata = [ordered]@{
        channel = "prod"
        extensionId = "hehggadaopoacecdllhhajmbjkdcmajg"
        extensionHostName = "com.openai.codexextension"
    }
    $metadataPath = Join-PathStrict $PluginRoot "scripts\extension-id.json"
    if (Test-Path -LiteralPath $metadataPath -PathType Leaf) {
        try {
            $parsed = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
            if (-not [string]::IsNullOrWhiteSpace([string]$parsed.extensionId)) {
                $metadata.extensionId = [string]$parsed.extensionId
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$parsed.extensionHostName)) {
                $metadata.extensionHostName = [string]$parsed.extensionHostName
            }
        } catch {
            throw "Chrome extension metadata unreadable: $($_.Exception.Message)"
        }
    }
    return [pscustomobject]$metadata
}

function New-ExtensionHostConfig {
    param(
        [string]$PluginRoot,
        [object]$Metadata
    )

    $browserClient = Join-PathStrict $PluginRoot "scripts\browser-client.mjs"
    $codex = Resolve-CodexBundledTool -Name "codex"
    $node = Resolve-CodexBundledTool -Name "node"
    $nodeRepl = Resolve-CodexBundledTool -Name "node_repl"

    foreach ($entry in @(
            @{ Name = "browserClientPath"; Path = $browserClient },
            @{ Name = "codexCliPath"; Path = $codex },
            @{ Name = "nodePath"; Path = $node },
            @{ Name = "nodeReplPath"; Path = $nodeRepl }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Path) -or -not (Test-Path -LiteralPath ([string]$entry.Path) -PathType Leaf)) {
            throw ("Chrome extension host config dependency missing: " + $entry.Name)
        }
        if ($entry.Name -ne "browserClientPath" -and (Test-CmdShimPath -Path ([string]$entry.Path))) {
            throw ("Chrome extension host config dependency uses cmd shim: " + $entry.Name)
        }
    }

    return [ordered]@{
        schemaVersion = 1
        channel = [string]$Metadata.channel
        browserClientPath = $browserClient
        codexCliPath = $codex
        extensionId = [string]$Metadata.extensionId
        nodePath = $node
        nodeReplPath = $nodeRepl
        proxyHost = "127.0.0.1"
        proxyPort = 0
    }
}

function Write-ExtensionHostConfig {
    param(
        [string]$PluginRoot,
        [string]$ExpectedConfig,
        [object]$Metadata
    )

    $config = New-ExtensionHostConfig -PluginRoot $PluginRoot -Metadata $Metadata
    New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($ExpectedConfig)) | Out-Null
    [IO.File]::WriteAllText(
        $ExpectedConfig,
        (($config | ConvertTo-Json -Depth 8) + "`n"),
        [Text.UTF8Encoding]::new($false)
    )
    return "extension-host-config-regenerated=$ExpectedConfig"
}

function Get-NonConfigRuntimeProblems {
    param([object[]]$Problems)

    return @($Problems | Where-Object {
            $_ -notmatch '^extension-host-config\.json missing$' -and
            $_ -notmatch '^extension-host-config\.json unreadable:' -and
            $_ -notmatch '^extension host config path missing:' -and
            $_ -notmatch '^extension host config uses cmd shim:'
        })
}

function Test-ChromePluginRuntime {
    param(
        [string]$CacheRoot,
        [object]$SelectedVersion
    )

    $latestPath = Join-PathStrict $CacheRoot "latest"
    $latestTarget = Get-LatestTarget -LatestPath $latestPath
    $expectedHost = Join-PathStrict $latestPath "extension-host\windows\x64\extension-host.exe"
    $expectedConfig = Join-PathStrict $latestPath "extension-host\windows\x64\extension-host-config.json"
    $pluginMetadata = if ($null -ne $SelectedVersion) { Get-ChromePluginMetadata -PluginRoot ([string]$SelectedVersion.root) } else { $null }
    $nativeManifestPath = Get-NativeManifestPath
    $nativeManifest = $null
    $nativeManifestProblem = $null
    $nativeHostPath = $null
    if (Test-Path -LiteralPath $nativeManifestPath -PathType Leaf) {
        try {
            $nativeManifest = Get-Content -LiteralPath $nativeManifestPath -Raw | ConvertFrom-Json
            $nativeHostPath = [string]$nativeManifest.path
        } catch {
            $nativeManifestProblem = $_.Exception.Message
        }
    }

    $config = $null
    $configProblem = $null
    if (Test-Path -LiteralPath $expectedConfig -PathType Leaf) {
        try {
            $config = Get-Content -LiteralPath $expectedConfig -Raw | ConvertFrom-Json
        } catch {
            $configProblem = $_.Exception.Message
        }
    }

    $configPaths = @()
    if ($null -ne $config) {
        foreach ($property in @("browserClientPath", "codexCliPath", "nodePath", "nodeReplPath")) {
            $value = [string]$config.$property
            $configPaths += [pscustomobject]@{
                name = $property
                path = $value
                exists = (-not [string]::IsNullOrWhiteSpace($value) -and (Test-Path -LiteralPath $value -PathType Leaf))
                uses_cmd_shim = (Test-CmdShimPath -Path $value)
            }
        }
    }

    $problems = New-Object System.Collections.Generic.List[string]
    if ($null -eq $SelectedVersion) { $problems.Add("no complete chrome plugin cache version found") | Out-Null }
    if ($null -eq $latestTarget) { $problems.Add("chrome latest link is missing") | Out-Null }
    elseif ($null -ne $SelectedVersion -and (ConvertTo-ComparablePath -Path $latestTarget) -ine (ConvertTo-ComparablePath -Path ([string]$SelectedVersion.root))) {
        $problems.Add("chrome latest link does not target selected installed version") | Out-Null
    }
    if (-not (Test-Path -LiteralPath $expectedHost -PathType Leaf)) { $problems.Add("native host executable missing at latest path") | Out-Null }
    if (-not (Test-Path -LiteralPath $nativeManifestPath -PathType Leaf)) { $problems.Add("native host manifest file missing") | Out-Null }
    if ($nativeManifestProblem) { $problems.Add("native host manifest unreadable: $nativeManifestProblem") | Out-Null }
    if ((ConvertTo-ComparablePath -Path $nativeHostPath) -ine (ConvertTo-ComparablePath -Path $expectedHost)) { $problems.Add("native host manifest path does not match latest host path") | Out-Null }
    if (-not (Test-Path -LiteralPath $expectedConfig -PathType Leaf)) { $problems.Add("extension-host-config.json missing") | Out-Null }
    if ($configProblem) { $problems.Add("extension-host-config.json unreadable: $configProblem") | Out-Null }
    foreach ($entry in $configPaths) {
        if (-not $entry.exists) {
            $problems.Add(("extension host config path missing: " + $entry.name)) | Out-Null
        }
        if ($entry.name -ne "browserClientPath" -and $entry.uses_cmd_shim) {
            $problems.Add(("extension host config uses cmd shim: " + $entry.name)) | Out-Null
        }
    }

    return [pscustomobject]@{
        ok = ($problems.Count -eq 0)
        cache_root = $CacheRoot
        selected_version = $SelectedVersion
        latest_path = $latestPath
        latest_target = $latestTarget
        expected_host = $expectedHost
        expected_config = $expectedConfig
        plugin_metadata = $pluginMetadata
        native_manifest_path = $nativeManifestPath
        native_host_path = $nativeHostPath
        config_paths = $configPaths
        extension_host_processes = @(Get-ExtensionHostProcesses -CacheRoot $CacheRoot)
        config_only_problems = @(Get-NonConfigRuntimeProblems -Problems @($problems.ToArray())).Count -eq 0
        problems = @($problems.ToArray())
    }
}

function Invoke-InstallManifest {
    param([object]$SelectedVersion)

    $node = Resolve-CodexBundledTool -Name "node"
    if ([string]::IsNullOrWhiteSpace($node) -or -not (Test-Path -LiteralPath $node -PathType Leaf)) {
        throw "Codex bundled node executable not found."
    }
    $codex = Resolve-CodexBundledTool -Name "codex"
    $nodeRepl = Resolve-CodexBundledTool -Name "node_repl"
    foreach ($entry in @(
            @{ Name = "codex"; Path = $codex },
            @{ Name = "node_repl"; Path = $nodeRepl }
        )) {
        if ([string]::IsNullOrWhiteSpace([string]$entry.Path) -or -not (Test-Path -LiteralPath ([string]$entry.Path) -PathType Leaf)) {
            throw ("Codex bundled " + $entry.Name + " executable not found.")
        }
        if (Test-CmdShimPath -Path ([string]$entry.Path)) {
            throw ("Codex bundled " + $entry.Name + " resolved to cmd shim.")
        }
    }

    $installUri = ([Uri](Get-Item -LiteralPath $SelectedVersion.install_manifest).FullName).AbsoluteUri
    $optionsJson = @{
        appServerRuntimePaths = @{
            codexCliPath = $codex
            nodePath = $node
            nodeReplPath = $nodeRepl
        }
    } | ConvertTo-Json -Compress -Depth 8
    $optionsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($optionsJson))
    $code = "const opts = JSON.parse(Buffer.from('$optionsBase64', 'base64').toString('utf8')); import('$installUri').then(m => m.install(opts))"
    $output = @(& $node "--input-type=module" "-e" $code 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (($output | Out-String).Trim())
    }
    return (($output | Out-String).Trim())
}

$cacheRoot = Join-PathStrict $CodexHome "plugins\cache\openai-bundled\chrome"
$versions = @(Get-ChromeVersionCandidates -CacheRoot $cacheRoot)
$selected = @($versions | Select-Object -First 1)[0]
$actions = New-Object System.Collections.Generic.List[string]

if ($Mode -eq "repair") {
    if ($null -eq $selected) {
        throw "No complete chrome plugin cache version found under $cacheRoot"
    }

    $preStatus = Test-ChromePluginRuntime -CacheRoot $cacheRoot -SelectedVersion $selected
    $nonConfigProblems = @(Get-NonConfigRuntimeProblems -Problems @($preStatus.problems))
    if (-not $preStatus.ok -and @($preStatus.extension_host_processes).Count -gt 0 -and $nonConfigProblems.Count -gt 0) {
        throw "Chrome extension host is running from the plugin cache; close Chrome or disconnect the extension before repairing mutable native-host paths."
    }

    $latestPath = Join-PathStrict $cacheRoot "latest"
    if (-not $preStatus.ok -and $nonConfigProblems.Count -eq 0) {
        $metadata = Get-ChromePluginMetadata -PluginRoot ([string]$selected.root)
        $expectedConfig = Join-PathStrict $latestPath "extension-host\windows\x64\extension-host-config.json"
        $actions.Add((Write-ExtensionHostConfig -PluginRoot $latestPath -ExpectedConfig $expectedConfig -Metadata $metadata)) | Out-Null
    } else {
        $actions.Add((Set-LatestJunction -LatestPath $latestPath -TargetPath $selected.root)) | Out-Null
        $actions.Add("install-manifest=" + (Invoke-InstallManifest -SelectedVersion $selected)) | Out-Null
    }
}

$status = Test-ChromePluginRuntime -CacheRoot $cacheRoot -SelectedVersion $selected
$result = [ordered]@{
    generated_utc = (Get-Date).ToUniversalTime().ToString("o")
    mode = $Mode
    actions = @($actions.ToArray())
    status = $status
}

if ($Json) {
    $result | ConvertTo-Json -Depth 16
} else {
    "ok={0}" -f $status.ok
    if ($status.problems.Count -gt 0) {
        "problems={0}" -f ($status.problems -join "; ")
    }
    foreach ($action in $actions) { "action=$action" }
}

if (-not $status.ok) {
    exit 1
}
