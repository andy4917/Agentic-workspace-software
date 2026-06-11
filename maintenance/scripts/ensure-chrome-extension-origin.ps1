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

function Copy-PatchedMarketplace {
    param(
        [string]$Source,
        [string]$Destination
    )

    if ([string]::IsNullOrWhiteSpace($Source) -or -not (Test-Path -LiteralPath $Source)) {
        return "skipped: source marketplace not found at $Source"
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    }

    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $Destination ".codex-patched-source.txt"),
        $Source,
        [System.Text.UTF8Encoding]::new($false)
    )
    return "copied: openai-bundled marketplace to $Destination"
}

function Repair-BrowserClient {
    param([string]$BrowserClient)

    if (-not (Test-Path -LiteralPath $BrowserClient)) {
        return "skipped: browser-client.mjs not found at $BrowserClient"
    }

    $oldPolicy = 'return e.protocol==="http:"||e.protocol==="https:"}'
    $newPolicy = 'return e.protocol==="http:"||e.protocol==="https:"||e.protocol==="chrome-extension:"}'
    $text = [System.IO.File]::ReadAllText($BrowserClient)

    if ($text.Contains($newPolicy)) {
        return "ok: chrome-extension origin already allowed at $BrowserClient"
    }

    $matchCount = ([regex]::Matches($text, [regex]::Escape($oldPolicy))).Count
    if ($matchCount -ne 1) {
        throw "Expected exactly one browser URL policy match in $BrowserClient, found $matchCount"
    }

    [System.IO.File]::WriteAllText(
        $BrowserClient,
        $text.Replace($oldPolicy, $newPolicy),
        [System.Text.UTF8Encoding]::new($false)
    )

    if (-not $NoNodeCheck) {
        $node = Resolve-CodexBundledExe -Name "node"
        if ([string]::IsNullOrWhiteSpace($node) -or -not (Test-Path -LiteralPath $node -PathType Leaf)) {
            throw "Bundled node.exe not found for browser-client syntax check."
        }
        & $node --check $BrowserClient | Out-Null
    }

    return "patched: chrome-extension origin allowed at $BrowserClient"
}

function Resolve-CodexBundledExe {
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
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -ne $match) {
            return $match.FullName
        }
    }

    return $null
}

$configPath = Join-Path $CodexHome "config.toml"
$patchedMarketplace = Join-Path $CodexHome "plugins\patched\openai-bundled"
$marketplaceSource = Get-OpenAiBundledSource -ConfigPath $configPath
$setupResults = [System.Collections.Generic.List[string]]::new()

if (-not [string]::IsNullOrWhiteSpace($marketplaceSource) -and $marketplaceSource -match '\\WindowsApps\\') {
    try {
        $setupResults.Add((Copy-PatchedMarketplace -Source $marketplaceSource -Destination $patchedMarketplace))
        $setupResults.Add((Set-OpenAiBundledSource -ConfigPath $configPath -Source $patchedMarketplace))
        $marketplaceSource = $patchedMarketplace
    } catch {
        $setupResults.Add("failed: patched marketplace setup - $($_.Exception.Message)")
    }
}

$targets = [System.Collections.Generic.List[string]]::new()
$cacheClient = Join-Path $CodexHome "plugins\cache\openai-bundled\chrome\latest\scripts\browser-client.mjs"
$targets.Add($cacheClient)

if (-not [string]::IsNullOrWhiteSpace($marketplaceSource)) {
    $bundleClient = Join-Path $marketplaceSource "plugins\chrome\scripts\browser-client.mjs"
    if (-not $targets.Contains($bundleClient)) {
        $targets.Add($bundleClient)
    }
} elseif (Test-Path -LiteralPath $patchedMarketplace) {
    $patchedClient = Join-Path $patchedMarketplace "plugins\chrome\scripts\browser-client.mjs"
    if (-not $targets.Contains($patchedClient)) {
        $targets.Add($patchedClient)
    }
}

$results = foreach ($target in $targets) {
    try {
        Repair-BrowserClient -BrowserClient $target
    } catch {
        "failed: $target - $($_.Exception.Message)"
    }
}

$setupResults | ForEach-Object { Write-Output $_ }
$results | ForEach-Object { Write-Output $_ }
