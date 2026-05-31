param(
    [ValidateSet("status", "repair")]
    [string]$Mode = "status",
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

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

function Resolve-CodexBundledTool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $shim = Join-PathStrict $CodexHome ("toolchains\shims\" + $Name + ".cmd")
    if (Test-Path -LiteralPath $shim -PathType Leaf) {
        return $shim
    }

    $binRoot = Join-PathStrict $env:LOCALAPPDATA "OpenAI\Codex\bin"
    $direct = Join-PathStrict $binRoot ($Name + ".exe")
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return $direct
    }

    if (Test-Path -LiteralPath $binRoot -PathType Container) {
        $match = Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $candidate = Join-PathStrict $_.FullName ($Name + ".exe")
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

    return $null
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

    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        [string]$_.Name -ieq "extension-host.exe" -or
            ([string]$_.CommandLine -match "extension-host" -and [string]$_.CommandLine -match [regex]::Escape($CacheRoot))
    } | Select-Object ProcessId, ParentProcessId, Name, CommandLine)
}

function Get-NativeManifestPath {
    return Join-PathStrict $env:LOCALAPPDATA "OpenAI\extension\com.openai.codexextension.json"
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
    }

    return [pscustomobject]@{
        ok = ($problems.Count -eq 0)
        cache_root = $CacheRoot
        selected_version = $SelectedVersion
        latest_path = $latestPath
        latest_target = $latestTarget
        expected_host = $expectedHost
        expected_config = $expectedConfig
        native_manifest_path = $nativeManifestPath
        native_host_path = $nativeHostPath
        config_paths = $configPaths
        extension_host_processes = @(Get-ExtensionHostProcesses -CacheRoot $CacheRoot)
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
            throw ("Codex bundled " + $entry.Name + " executable or shim not found.")
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
    if (-not $preStatus.ok -and @($preStatus.extension_host_processes).Count -gt 0) {
        throw "Chrome extension host is running from the plugin cache; close Chrome or disconnect the extension before repairing mutable native-host paths."
    }

    $latestPath = Join-PathStrict $cacheRoot "latest"
    $actions.Add((Set-LatestJunction -LatestPath $latestPath -TargetPath $selected.root)) | Out-Null
    $actions.Add("install-manifest=" + (Invoke-InstallManifest -SelectedVersion $selected)) | Out-Null
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
