param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex" }),
    [switch]$NoNodeCheck
)

$ErrorActionPreference = "Stop"

function Get-OpenAiBundledSource {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }

    $inMarketplace = $false
    foreach ($line in (Get-Content -LiteralPath $ConfigPath)) {
        if ($line -match '^\[marketplaces\.openai-bundled\]') {
            $inMarketplace = $true
            continue
        }
        if ($inMarketplace -and $line -match '^\[') {
            return $null
        }
        if ($inMarketplace -and $line -match "^\s*source\s*=\s*'([^']+)'\s*$") {
            return $Matches[1]
        }
        if ($inMarketplace -and $line -match '^\s*source\s*=\s*"([^"]+)"\s*$') {
            return $Matches[1]
        }
    }

    return $null
}

function Test-ModernBrowserClient {
    param([string]$MarketplaceSource)

    if ([string]::IsNullOrWhiteSpace($MarketplaceSource)) {
        return $false
    }

    $browserClient = Join-Path $MarketplaceSource "plugins\browser\scripts\browser-client.mjs"
    if (-not (Test-Path -LiteralPath $browserClient)) {
        return $false
    }

    $text = [System.IO.File]::ReadAllText($browserClient)
    return $text.Contains("setupBrowserRuntime") -and $text.Contains("__codexNativePipe")
}

function Get-OfficialBundledMarketplace {
    param([string]$CodexHome)

    $windowsAppsRoot = Join-Path ([Environment]::GetFolderPath("ProgramFiles")) "WindowsApps"
    if (Test-Path -LiteralPath $windowsAppsRoot) {
        $candidate = Get-ChildItem -LiteralPath $windowsAppsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "OpenAI.Codex_*" } |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { Join-Path $_.FullName "app\resources\plugins\openai-bundled" } |
            Where-Object { Test-ModernBrowserClient -MarketplaceSource $_ } |
            Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate
        }
    }

    $localBundled = Join-Path $CodexHome ".tmp\bundled-marketplaces\openai-bundled"
    if (Test-ModernBrowserClient -MarketplaceSource $localBundled) {
        return $localBundled
    }

    return $null
}

function Test-UiVisibleMarketplaceSource {
    param([string]$MarketplaceSource)

    if ([string]::IsNullOrWhiteSpace($MarketplaceSource)) {
        return $false
    }

    $normalized = $MarketplaceSource.Replace("/", "\").ToLowerInvariant()
    return -not (
        $normalized.Contains("\.tmp\") -or
        $normalized.Contains("\tmp\") -or
        $normalized.Contains("\bundled-marketplaces\") -or
        $normalized.Contains("\plugins\cache\")
    )
}

function Get-BrowserPluginVersion {
    param([string]$MarketplaceSource)

    $manifestPath = Join-Path $MarketplaceSource "plugins\browser\.codex-plugin\plugin.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        return "0.1.0-alpha2"
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($manifest.version)) {
            return [string]$manifest.version
        }
    } catch {
        return "0.1.0-alpha2"
    }

    return "0.1.0-alpha2"
}

function Ensure-BrowserPluginCache {
    param(
        [string]$CodexHome,
        [string]$MarketplaceSource
    )

    $browserSource = Join-Path $MarketplaceSource "plugins\browser"
    if (-not (Test-ModernBrowserClient -MarketplaceSource $MarketplaceSource)) {
        return "skipped: official browser plugin source not usable at $browserSource"
    }

    $version = Get-BrowserPluginVersion -MarketplaceSource $MarketplaceSource
    $cacheRoot = Join-Path $CodexHome "plugins\cache\openai-bundled\browser"
    $versionPath = Join-Path $cacheRoot $version
    $latestPath = Join-Path $cacheRoot "latest"

    if (-not (Test-Path -LiteralPath $cacheRoot)) {
        New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
    }

    $messages = [System.Collections.Generic.List[string]]::new()
    foreach ($targetPath in @($versionPath, $latestPath)) {
        if (Test-Path -LiteralPath $targetPath) {
            $messages.Add("ok: browser plugin cache path exists at $targetPath")
            continue
        }
        New-Item -ItemType Junction -Path $targetPath -Target $browserSource | Out-Null
        $messages.Add("created: browser plugin cache junction $targetPath -> $browserSource")
    }

    return ($messages -join [Environment]::NewLine)
}

function Clear-LegacyBrowserUseAutoInstallDisabled {
    param([string]$CodexHome)

    $statePath = Join-Path $CodexHome ".codex-global-state.json"
    if (-not (Test-Path -LiteralPath $statePath)) {
        return "skipped: global state not found at $statePath"
    }

    $text = [System.IO.File]::ReadAllText($statePath)
    $pattern = '"browser-use-bundled-plugin-auto-install-disabled"\s*:\s*true'
    if (-not [regex]::IsMatch($text, $pattern)) {
        return "ok: legacy browser-use auto-install disabled flag is not true"
    }

    $backupDir = Join-Path $CodexHome "state\browser-plugin-ui-repair"
    if (-not (Test-Path -LiteralPath $backupDir)) {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    Copy-Item -LiteralPath $statePath -Destination (Join-Path $backupDir ".codex-global-state.before-auto-install-flag.$stamp.json") -Force

    $newText = [regex]::Replace($text, $pattern, '"browser-use-bundled-plugin-auto-install-disabled":false', 1)
    [System.IO.File]::WriteAllText($statePath, $newText, [System.Text.UTF8Encoding]::new($false))
    return "patched-state: browser-use bundled plugin auto-install disabled flag set to false"
}

function Get-CodexAppServerExe {
    param([string]$MarketplaceSource)

    $marketplaceItem = [System.IO.DirectoryInfo]::new($MarketplaceSource)
    $pluginsDir = $marketplaceItem.Parent
    if ($null -eq $pluginsDir) {
        return $null
    }

    $resourcesDir = $pluginsDir.Parent
    if ($null -eq $resourcesDir) {
        return $null
    }

    $codexExe = Join-Path $resourcesDir.FullName "codex.exe"
    if (Test-Path -LiteralPath $codexExe) {
        return $codexExe
    }

    return $null
}

function Read-AppServerResponse {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$ExpectedId,
        [int]$TimeoutMs = 30000
    )

    $deadline = [DateTimeOffset]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $remainingMs = [int][Math]::Max(1, ($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds)
        $readTask = $Process.StandardOutput.ReadLineAsync()
        if (-not $readTask.Wait($remainingMs)) {
            throw "timed out waiting for app-server response id=$ExpectedId"
        }

        $line = $readTask.Result
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $message = $line | ConvertFrom-Json
        } catch {
            continue
        }

        if ($message.id -eq $ExpectedId) {
            return $message
        }
    }

    throw "timed out waiting for app-server response id=$ExpectedId"
}

function Send-AppServerRequest {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$Id,
        [string]$Method,
        $Params
    )

    $request = [ordered]@{
        jsonrpc = "2.0"
        id = $Id
        method = $Method
    }
    if ($null -ne $Params) {
        $request.params = $Params
    }

    $json = $request | ConvertTo-Json -Depth 20 -Compress
    $Process.StandardInput.WriteLine($json)
    $Process.StandardInput.Flush()
}

function Get-PluginInstalledFromReadResponse {
    param($Response)

    if ($null -eq $Response -or $null -ne $Response.error) {
        return $false
    }

    $summary = $Response.result.plugin.summary
    return ($null -ne $summary -and $summary.installed -eq $true -and $summary.enabled -eq $true)
}

function Ensure-BrowserPluginInstalled {
    param(
        [string]$CodexHome,
        [string]$MarketplaceSource
    )

    $codexExe = Get-CodexAppServerExe -MarketplaceSource $MarketplaceSource
    if ([string]::IsNullOrWhiteSpace($codexExe)) {
        return "skipped: codex app-server executable not found for $MarketplaceSource"
    }

    $marketplacePath = Join-Path $MarketplaceSource ".agents\plugins\marketplace.json"
    if (-not (Test-Path -LiteralPath $marketplacePath)) {
        return "skipped: openai-bundled marketplace file not found at $marketplacePath"
    }

    $process = $null

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $codexExe
        $startInfo.ArgumentList.Add("app-server")
        $startInfo.ArgumentList.Add("--listen")
        $startInfo.ArgumentList.Add("stdio://")
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $false
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $null = $process.Start()

        Send-AppServerRequest -Process $process -Id 1 -Method "initialize" -Params ([ordered]@{
            clientInfo = [ordered]@{
                name = "codex-browser-plugin-ui-repair"
                title = "Codex Browser Plugin UI Repair"
                version = "0.0.1"
            }
            capabilities = [ordered]@{
                experimentalApi = $true
                requestAttestation = $false
                optOutNotificationMethods = @()
            }
        })
        $null = Read-AppServerResponse -Process $process -ExpectedId 1 -TimeoutMs 10000

        $readParams = [ordered]@{
            marketplacePath = $marketplacePath
            remoteMarketplaceName = $null
            pluginName = "browser"
        }
        Send-AppServerRequest -Process $process -Id 2 -Method "plugin/read" -Params $readParams
        $before = Read-AppServerResponse -Process $process -ExpectedId 2 -TimeoutMs 20000
        if (Get-PluginInstalledFromReadResponse -Response $before) {
            return "ok: browser@openai-bundled is installed and enabled"
        }

        Send-AppServerRequest -Process $process -Id 3 -Method "plugin/install" -Params $readParams
        $install = Read-AppServerResponse -Process $process -ExpectedId 3 -TimeoutMs 30000
        if ($null -ne $install.error) {
            return "failed: browser@openai-bundled install failed: $($install.error.message)"
        }

        Send-AppServerRequest -Process $process -Id 4 -Method "plugin/read" -Params $readParams
        $after = Read-AppServerResponse -Process $process -ExpectedId 4 -TimeoutMs 20000
        if (Get-PluginInstalledFromReadResponse -Response $after) {
            return "patched-plugin: browser@openai-bundled installed and enabled through app-server"
        }

        return "failed: browser@openai-bundled still not installed after app-server install"
    } catch {
        return "failed: browser@openai-bundled app-server install check failed: $($_.Exception.Message)"
    } finally {
        if ($null -ne $process) {
            try { $process.StandardInput.Close() } catch {}
            if (-not $process.HasExited) {
                try {
                    $process.Kill()
                    $process.WaitForExit(5000) | Out-Null
                } catch {}
            }
            $process.Dispose()
        }
    }
}

function Set-OpenAiBundledSource {
    param(
        [string]$ConfigPath,
        [string]$Source
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return "skipped: config.toml not found at $ConfigPath"
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content -LiteralPath $ConfigPath)) {
        $lines.Add($line)
    }

    $inMarketplace = $false
    $changed = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -match '^\[marketplaces\.openai-bundled\]') {
            $inMarketplace = $true
            continue
        }
        if ($inMarketplace -and $line -match '^\[') {
            break
        }
        if ($inMarketplace -and $line -match '^\s*source\s*=') {
            $newLine = "source = '$Source'"
            if ($line -ne $newLine) {
                $lines[$index] = $newLine
                $changed = $true
            }
            break
        }
    }

    if (-not $changed) {
        return "ok: openai-bundled source already set to $Source"
    }

    [System.IO.File]::WriteAllLines($ConfigPath, $lines, [System.Text.UTF8Encoding]::new($false))
    return "patched-config: openai-bundled source set to $Source"
}

$configPath = Join-Path $CodexHome "config.toml"
$currentSource = Get-OpenAiBundledSource -ConfigPath $configPath
$officialSource = Get-OfficialBundledMarketplace -CodexHome $CodexHome
$currentSourceUiVisible = Test-UiVisibleMarketplaceSource -MarketplaceSource $currentSource

if ([string]::IsNullOrWhiteSpace($officialSource)) {
    Write-Output "failed: official openai-bundled marketplace with modern browser client was not found"
} elseif (($currentSource -eq $officialSource) -and $currentSourceUiVisible) {
    Write-Output "ok: openai-bundled source already uses official bundled marketplace"
} elseif (-not [string]::IsNullOrWhiteSpace($currentSource) -and $currentSourceUiVisible -and (Test-ModernBrowserClient -MarketplaceSource $currentSource)) {
    Write-Output "ok: openai-bundled source already has modern browser client"
} else {
    Write-Output (Set-OpenAiBundledSource -ConfigPath $configPath -Source $officialSource)
    Write-Output "note: legacy browser-client mutation disabled; native bridge trust is granted only to official bundled browser-client paths"
    Write-Output "note: active openai-bundled source should not point at .tmp, bundled-marketplaces, or plugin cache because app UI indexing may hide those sources"
}

Write-Output (Ensure-BrowserPluginCache -CodexHome $CodexHome -MarketplaceSource $officialSource)
Write-Output (Ensure-BrowserPluginInstalled -CodexHome $CodexHome -MarketplaceSource $officialSource)
Write-Output (Clear-LegacyBrowserUseAutoInstallDisabled -CodexHome $CodexHome)
