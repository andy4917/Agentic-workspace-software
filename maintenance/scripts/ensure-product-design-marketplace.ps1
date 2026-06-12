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
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    try {
        return [IO.Path]::GetFullPath($Path).TrimEnd("\").ToLowerInvariant()
    } catch {
        return ([string]$Path).TrimEnd("\").ToLowerInvariant()
    }
}

function Get-ProductDesignCacheVersion {
    $cacheRoot = Join-PathStrict $CodexHome "plugins\cache\openai-curated-remote\product-design"
    if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
        return $null
    }
    $versions = @(Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            (Test-Path -LiteralPath (Join-PathStrict $_.FullName ".codex-plugin\plugin.json") -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-PathStrict $_.FullName "skills\index\SKILL.md") -PathType Leaf)
        } |
        Sort-Object LastWriteTimeUtc -Descending)
    if ($versions.Count -eq 0) { return $null }
    return $versions[0]
}

function Get-JunctionTarget {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSObject.Properties["Target"] -and $item.Target) {
        if ($item.Target -is [array]) {
            return [string]$item.Target[0]
        }
        return [string]$item.Target
    }
    return ""
}

function New-MarketplaceJson {
    [ordered]@{
        name = "openai-curated-remote"
        interface = [ordered]@{
            displayName = "OpenAI curated remote"
        }
        plugins = @(
            [ordered]@{
                name = "product-design"
                source = [ordered]@{
                    source = "local"
                    path = "./plugins/product-design"
                }
                policy = [ordered]@{
                    installation = "AVAILABLE"
                    authentication = "ON_USE"
                    products = @("CODEX")
                }
                category = "Design"
            }
        )
    }
}

function Test-ConfigRegistration {
    $configPath = Join-PathStrict $CodexHome "config.toml"
    $expectedSource = Join-PathStrict $CodexHome "plugins\marketplaces\openai-curated-remote"
    $result = [ordered]@{
        config_path = $configPath
        marketplace_section = $false
        plugin_section = $false
        source_mentions_expected_root = $false
        ok = $false
    }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return $result
    }
    $text = Get-Content -LiteralPath $configPath -Raw
    $result.marketplace_section = $text -match '\[marketplaces\.openai-curated-remote\]'
    $result.plugin_section = $text -match '\[plugins\."product-design@openai-curated-remote"\]'
    $result.source_mentions_expected_root = ((ConvertTo-ComparablePath -Path $text) -match [regex]::Escape((ConvertTo-ComparablePath -Path $expectedSource)))
    $result.ok = [bool]($result.marketplace_section -and $result.plugin_section -and $result.source_mentions_expected_root)
    return $result
}

function Invoke-CodexPluginListProbe {
    $codexExe = Resolve-CodexBundledTool -Name "codex"
    if ([string]::IsNullOrWhiteSpace($codexExe)) {
        return [ordered]@{ ok = $false; command = "codex.exe plugin list -m openai-curated-remote"; exit_code = $null; output = "missing bundled codex.exe" }
    }
    $output = @(& $codexExe plugin list -m openai-curated-remote 2>&1)
    $text = (($output | Out-String).Trim())
    return [ordered]@{
        ok = ($LASTEXITCODE -eq 0 -and $text -match "product-design@openai-curated-remote" -and $text -match "installed,\s*enabled")
        command = "$codexExe plugin list -m openai-curated-remote"
        exit_code = $LASTEXITCODE
        output = $text
    }
}

function Get-Status {
    $selected = Get-ProductDesignCacheVersion
    $marketplaceRoot = Join-PathStrict $CodexHome "plugins\marketplaces\openai-curated-remote"
    $marketplaceJson = Join-PathStrict $marketplaceRoot ".agents\plugins\marketplace.json"
    $pluginLink = Join-PathStrict $marketplaceRoot "plugins\product-design"
    $linkTarget = Get-JunctionTarget -Path $pluginLink
    $expectedTarget = if ($null -ne $selected) { [string]$selected.FullName } else { "" }
    $manifestAtLink = Join-PathStrict $pluginLink ".codex-plugin\plugin.json"
    $indexAtLink = Join-PathStrict $pluginLink "skills\index\SKILL.md"
    $marketplace = $null
    $marketplaceParseOk = $false
    $marketplaceProblem = $null
    if (Test-Path -LiteralPath $marketplaceJson -PathType Leaf) {
        try {
            $marketplace = Get-Content -LiteralPath $marketplaceJson -Raw | ConvertFrom-Json
            $marketplaceParseOk = $true
        } catch {
            $marketplaceProblem = $_.Exception.Message
        }
    } else {
        $marketplaceProblem = "missing"
    }
    $marketplaceEntryOk = $false
    if ($marketplaceParseOk) {
        $entry = @($marketplace.plugins | Where-Object { [string]$_.name -eq "product-design" } | Select-Object -First 1)
        $marketplaceEntryOk = (
            [string]$marketplace.name -eq "openai-curated-remote" -and
            $entry.Count -eq 1 -and
            [string]$entry[0].source.source -eq "local" -and
            [string]$entry[0].source.path -eq "./plugins/product-design"
        )
    }
    $configRegistration = Test-ConfigRegistration
    $pluginListProbe = Invoke-CodexPluginListProbe
    $problems = New-Object System.Collections.Generic.List[string]
    if ($null -eq $selected) { $problems.Add("product-design cache version missing") | Out-Null }
    if (-not (Test-Path -LiteralPath $marketplaceRoot -PathType Container)) { $problems.Add("marketplace root missing") | Out-Null }
    if (-not $marketplaceParseOk) { $problems.Add("marketplace json unreadable: $marketplaceProblem") | Out-Null }
    if (-not $marketplaceEntryOk) { $problems.Add("marketplace entry missing or mismatched") | Out-Null }
    if (-not (Test-Path -LiteralPath $pluginLink -PathType Container)) { $problems.Add("product-design marketplace path missing") | Out-Null }
    if ((ConvertTo-ComparablePath -Path $linkTarget) -ne (ConvertTo-ComparablePath -Path $expectedTarget)) { $problems.Add("product-design marketplace junction target mismatch") | Out-Null }
    if (-not (Test-Path -LiteralPath $manifestAtLink -PathType Leaf)) { $problems.Add("product-design manifest missing from marketplace path") | Out-Null }
    if (-not (Test-Path -LiteralPath $indexAtLink -PathType Leaf)) { $problems.Add("product-design index skill missing from marketplace path") | Out-Null }
    if (-not [bool]$configRegistration.ok) { $problems.Add("config registration missing or mismatched") | Out-Null }
    if (-not [bool]$pluginListProbe.ok) { $problems.Add("codex plugin list does not report installed enabled product-design") | Out-Null }

    return [ordered]@{
        ok = ($problems.Count -eq 0)
        codex_home = $CodexHome
        selected_cache = $(if ($null -ne $selected) { [ordered]@{ version = $selected.Name; root = $selected.FullName } } else { $null })
        marketplace_root = $marketplaceRoot
        marketplace_json = $marketplaceJson
        plugin_path = $pluginLink
        plugin_path_target = $linkTarget
        expected_target = $expectedTarget
        marketplace_parse_ok = $marketplaceParseOk
        marketplace_entry_ok = $marketplaceEntryOk
        config_registration = $configRegistration
        plugin_list_probe = $pluginListProbe
        problems = @($problems.ToArray())
    }
}

function Invoke-Repair {
    $selected = Get-ProductDesignCacheVersion
    if ($null -eq $selected) {
        throw "product-design cache version missing"
    }
    $marketplaceRoot = Join-PathStrict $CodexHome "plugins\marketplaces\openai-curated-remote"
    $pluginDir = Join-PathStrict $marketplaceRoot "plugins"
    $agentDir = Join-PathStrict $marketplaceRoot ".agents\plugins"
    $pluginLink = Join-PathStrict $pluginDir "product-design"
    New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
    New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
    if (Test-Path -LiteralPath $pluginLink) {
        $target = Get-JunctionTarget -Path $pluginLink
        if ((ConvertTo-ComparablePath -Path $target) -ne (ConvertTo-ComparablePath -Path ([string]$selected.FullName))) {
            $item = Get-Item -LiteralPath $pluginLink -Force
            if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "product-design marketplace path exists but is not a reparse point: $pluginLink"
            }
            Remove-Item -LiteralPath $pluginLink -Force
            New-Item -ItemType Junction -Path $pluginLink -Target ([string]$selected.FullName) | Out-Null
        }
    } else {
        New-Item -ItemType Junction -Path $pluginLink -Target ([string]$selected.FullName) | Out-Null
    }
    $marketplaceJson = Join-PathStrict $agentDir "marketplace.json"
    $json = New-MarketplaceJson | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($marketplaceJson, $json + "`n", [Text.UTF8Encoding]::new($false))
}

if ($Mode -eq "repair") {
    Invoke-Repair
}

$status = Get-Status
if ($Json) {
    $status | ConvertTo-Json -Depth 12
} else {
    "ok={0}" -f $status.ok
    foreach ($problem in @($status.problems)) {
        "problem={0}" -f $problem
    }
}

if (-not [bool]$status.ok) {
    exit 1
}
