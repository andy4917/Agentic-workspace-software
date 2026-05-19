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

function Get-LegacyBrowserUseAutoInstallDisabledStatus {
    param([string]$CodexHome)

    $statePath = Join-Path $CodexHome ".codex-global-state.json"
    if (-not (Test-Path -LiteralPath $statePath)) {
        return "skipped: global state not found at $statePath"
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return "failed: global state JSON could not be parsed"
    }

    $property = $state.PSObject.Properties['browser-use-bundled-plugin-auto-install-disabled']
    if ($null -eq $property) {
        return "ok: legacy browser-use auto-install disabled flag is absent"
    }

    return "observed-app-state: legacy browser-use auto-install disabled flag is $($property.Value)"
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

    if ($null -eq $Process -or $null -eq $Process.StandardOutput) {
        throw "app-server stdout is unavailable for response id=$ExpectedId"
    }

    $deadline = [DateTimeOffset]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ($Process.HasExited) {
            throw "app-server exited before response id=$ExpectedId exitCode=$($Process.ExitCode)"
        }

        $remainingMs = [int][Math]::Max(1, ($deadline - [DateTimeOffset]::UtcNow).TotalMilliseconds)
        $readTask = $Process.StandardOutput.ReadLineAsync()
        if ($null -eq $readTask) {
            throw "app-server stdout read returned null for response id=$ExpectedId"
        }
        if (-not $readTask.Wait($remainingMs)) {
            throw "timed out waiting for app-server response id=$ExpectedId"
        }

        $line = $readTask.Result
        if ($null -eq $line) {
            if ($Process.HasExited) {
                throw "app-server closed stdout before response id=$ExpectedId exitCode=$($Process.ExitCode)"
            }
            continue
        }
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

    if ($null -eq $Process -or $null -eq $Process.StandardInput) {
        throw "app-server stdin is unavailable for request id=$Id method=$Method"
    }

    $request = [ordered]@{
        id = $Id
        method = $Method
    }
    if ($null -ne $Params) {
        $request.params = $Params
    }

    $json = $request | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
    $Process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $Process.StandardInput.BaseStream.Flush()
}

function Get-PluginInstalledFromReadResponse {
    param($Response)

    if ($null -eq $Response -or $null -ne $Response.error) {
        return $false
    }

    if ($null -eq $Response.result -or $null -eq $Response.result.plugin) {
        return $false
    }

    $summary = $Response.result.plugin.summary
    return ($null -ne $summary -and $summary.installed -eq $true -and $summary.enabled -eq $true)
}

function Invoke-AppServerPluginEnsureWithPython {
    param(
        [string]$CodexHome,
        [string]$CodexExe,
        [string]$MarketplacePath
    )

    $shimPython = Join-Path $CodexHome "toolchains\shims\python.cmd"
    $pythonSource = $null
    if (Test-Path -LiteralPath $shimPython -PathType Leaf) {
        $pythonSource = $shimPython
    } else {
        $python = Get-Command python -ErrorAction SilentlyContinue
        if ($null -ne $python) {
            $pythonSource = $python.Source
        }
    }
    if ([string]::IsNullOrWhiteSpace($pythonSource)) {
        return $null
    }

    $oldExe = $env:CODEX_APP_SERVER_EXE
    $oldMarketplace = $env:CODEX_APP_SERVER_MARKETPLACE
    $env:CODEX_APP_SERVER_EXE = $CodexExe
    $env:CODEX_APP_SERVER_MARKETPLACE = $MarketplacePath

    $script = @'
import json
import os
import queue
import subprocess
import sys
import threading
import time

exe = os.environ["CODEX_APP_SERVER_EXE"]
marketplace = os.environ["CODEX_APP_SERVER_MARKETPLACE"]
proc = None

def send(proc, request_id, method, params=None):
    request = {"id": request_id, "method": method}
    if params is not None:
        request["params"] = params
    proc.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
    proc.stdin.flush()

def read_response(lines, expected_id, timeout_seconds):
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            line = lines.get(timeout=max(0.1, deadline - time.time()))
        except queue.Empty:
            break
        if not line.strip():
            continue
        message = json.loads(line)
        if message.get("id") == expected_id:
            return message
    raise TimeoutError(f"timed out waiting for app-server response id={expected_id}")

def is_installed(response):
    summary = response.get("result", {}).get("plugin", {}).get("summary")
    return bool(summary and summary.get("installed") is True and summary.get("enabled") is True)

try:
    proc = subprocess.Popen(
        [exe, "app-server", "--listen", "stdio://"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
    )
    lines = queue.Queue()

    def reader():
        for item in proc.stdout:
            lines.put(item)

    threading.Thread(target=reader, daemon=True).start()
    send(proc, 1, "initialize", {
        "clientInfo": {"name": "codex-browser-plugin-ui-repair", "title": "Codex Browser Plugin UI Repair", "version": "0.0.1"},
        "capabilities": {"experimentalApi": True, "requestAttestation": False, "optOutNotificationMethods": []},
    })
    read_response(lines, 1, 15)
    params = {"marketplacePath": marketplace, "remoteMarketplaceName": None, "pluginName": "browser"}
    send(proc, 2, "plugin/read", params)
    before = read_response(lines, 2, 30)
    if is_installed(before):
        print("ok: browser@openai-bundled is installed and enabled")
        sys.exit(0)
    send(proc, 3, "plugin/install", params)
    install = read_response(lines, 3, 45)
    if install.get("error"):
        print("failed: browser@openai-bundled install failed: " + str(install["error"].get("message", install["error"])))
        sys.exit(0)
    send(proc, 4, "plugin/read", params)
    after = read_response(lines, 4, 30)
    if is_installed(after):
        print("patched-plugin: browser@openai-bundled installed and enabled through app-server")
    else:
        print("failed: browser@openai-bundled still not installed after app-server install")
except Exception as exc:
    print("failed: browser@openai-bundled app-server python check failed: " + str(exc))
finally:
    if proc is not None:
        try:
            proc.stdin.close()
        except Exception:
            pass
        try:
            proc.kill()
        except Exception:
            pass
        try:
            proc.wait(timeout=5)
        except Exception:
            pass
'@

    $tempScript = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-app-server-plugin-ensure-" + [guid]::NewGuid().ToString("N") + ".py")
    try {
        [System.IO.File]::WriteAllText($tempScript, $script, [System.Text.UTF8Encoding]::new($false))
        $output = & $pythonSource $tempScript
        if ($LASTEXITCODE -eq 0 -and $null -ne $output) {
            return [string]($output | Select-Object -Last 1)
        }
        return "failed: browser@openai-bundled app-server python check failed with exit=$LASTEXITCODE"
    }
    finally {
        Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        $env:CODEX_APP_SERVER_EXE = $oldExe
        $env:CODEX_APP_SERVER_MARKETPLACE = $oldMarketplace
    }
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

    $pythonResult = Invoke-AppServerPluginEnsureWithPython -CodexHome $CodexHome -CodexExe $codexExe -MarketplacePath $marketplacePath
    if (-not [string]::IsNullOrWhiteSpace($pythonResult)) {
        return $pythonResult
    }

    $process = $null

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $codexExe
        $startInfo.Arguments = "app-server --listen stdio://"
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        if ($null -ne $startInfo.PSObject.Properties["StandardInputEncoding"]) {
            $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
        }
        if ($null -ne $startInfo.PSObject.Properties["StandardOutputEncoding"]) {
            $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        }
        if ($null -ne $startInfo.PSObject.Properties["StandardErrorEncoding"]) {
            $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
        }
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $process.add_ErrorDataReceived({ })
        $null = $process.Start()
        $process.BeginErrorReadLine()

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
        $position = ($_.InvocationInfo.PositionMessage -replace '\s+', ' ').Trim()
        return "failed: browser@openai-bundled app-server install check failed: $($_.Exception.Message) at $position"
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
Write-Output (Get-LegacyBrowserUseAutoInstallDisabledStatus -CodexHome $CodexHome)
