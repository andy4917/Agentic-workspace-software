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

    $localBundled = Join-Path $CodexHome ".tmp\bundled-marketplaces\openai-bundled"
    if (Test-ModernBrowserClient -MarketplaceSource $localBundled) {
        return $localBundled
    }

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

if ([string]::IsNullOrWhiteSpace($officialSource)) {
    Write-Output "failed: official openai-bundled marketplace with modern browser client was not found"
} elseif ($currentSource -eq $officialSource) {
    Write-Output "ok: openai-bundled source already uses official bundled marketplace"
} elseif (-not [string]::IsNullOrWhiteSpace($currentSource) -and (Test-ModernBrowserClient -MarketplaceSource $currentSource)) {
    Write-Output "ok: openai-bundled source already has modern browser client"
} else {
    Write-Output (Set-OpenAiBundledSource -ConfigPath $configPath -Source $officialSource)
    Write-Output "note: legacy browser-client mutation disabled; native bridge trust is granted only to official bundled browser-client paths"
}
