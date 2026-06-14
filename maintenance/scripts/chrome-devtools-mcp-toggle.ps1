# Toggle the frontend-only Chrome DevTools MCP observer.
#
# This script keeps the server registered so Codex Desktop settings can show it.
# OFF means the MCP entry remains visible in config with `enabled = false`.
# Codex CLI currently has add/remove but no enable/disable subcommands, so the
# script uses `codex mcp add/remove` for registration and a narrow config edit
# only for the supported `enabled` flag.

[CmdletBinding()]
param(
    [ValidateSet("status", "on", "off", "verify-package", "help")]
    [string] $Action = "status",

    [string] $ServerName = "chrome-devtools",

    [switch] $Visible,

    [switch] $Slim,

    [switch] $Full
)

$ErrorActionPreference = "Stop"

function Join-PathStrict {
    param(
        [Parameter(Mandatory = $true)][string] $Base,
        [Parameter(Mandatory = $true)][string] $Child
    )

    return [System.IO.Path]::Combine($Base, $Child)
}

function Resolve-CodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }

    return Join-PathStrict $env:USERPROFILE ".codex"
}

$CodexHome = Resolve-CodexHome
$ShimDir = Join-PathStrict $CodexHome "toolchains\shims"
$NpxWrapper = Join-PathStrict $ShimDir "npx.cmd"
$ConfigPath = Join-PathStrict $CodexHome "config.toml"
$CodexExe = Join-PathStrict $env:LOCALAPPDATA "OpenAI\Codex\bin\codex.exe"

if (-not (Test-Path -LiteralPath $CodexExe)) {
    $cmd = Get-Command codex -ErrorAction Stop
    $CodexExe = $cmd.Source
}

function Invoke-CodexCli {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)

    $previousPath = $env:PATH
    try {
        $env:PATH = "$ShimDir;$previousPath"
        & $CodexExe @Arguments
        $exitCode = $LASTEXITCODE
    }
    finally {
        $env:PATH = $previousPath
    }

    if ($exitCode -ne 0) {
        throw "codex exited with code $exitCode for arguments: $($Arguments -join ' ')"
    }
}

function Get-McpServerInfo {
    $previousPath = $env:PATH
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $env:PATH = "$ShimDir;$previousPath"
        $ErrorActionPreference = "Continue"
        $output = & $CodexExe mcp get $ServerName --json 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            $json = ($output | Out-String).Trim()
            return $json | ConvertFrom-Json
        }

        $message = ($output | Out-String).Trim()
        if ($message -match "No MCP server named") {
            return $null
        }

        throw "codex mcp get failed with code ${exitCode}: $message"
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        $env:PATH = $previousPath
    }
}

function Test-McpServerPresent {
    return ($null -ne (Get-McpServerInfo))
}

function Write-Utf8NoBomLines {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Lines
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

function Invoke-WithWritableConfig {
    param([Parameter(Mandatory = $true)][scriptblock] $Body)

    $wasReadOnly = $false
    $originalAttributes = $null

    if (Test-Path -LiteralPath $ConfigPath) {
        $item = Get-Item -LiteralPath $ConfigPath
        $originalAttributes = $item.Attributes
        $wasReadOnly = (($item.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0)

        if ($wasReadOnly) {
            $item.Attributes = ($item.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly))
        }
    }

    try {
        & $Body
    }
    finally {
        if ($null -ne $originalAttributes -and (Test-Path -LiteralPath $ConfigPath)) {
            $item = Get-Item -LiteralPath $ConfigPath
            $item.Attributes = $originalAttributes
        }
    }
}

function Invoke-WithConfigRollback {
    param([Parameter(Mandatory = $true)][scriptblock] $Body)

    $backupPath = $null
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-mcp-config-{0}.toml" -f ([System.Guid]::NewGuid().ToString("N")))
        Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
    }

    try {
        & $Body
    }
    catch {
        if ($null -ne $backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Copy-Item -LiteralPath $backupPath -Destination $ConfigPath -Force
        }
        throw
    }
    finally {
        if ($null -ne $backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Remove-Item -LiteralPath $backupPath -Force
        }
    }
}

function Get-DesiredArgs {
    if ($Slim -and $Full) {
        throw "Use either -Slim or -Full, not both. Full is the default."
    }

    $args = @("-y", "chrome-devtools-mcp@latest")

    if ($Slim) {
        $args += "--slim"
    }

    if (-not $Visible) {
        $args += "--headless"
    }

    $args += "--isolated"
    $args += "--no-usage-statistics"
    $args += "--no-performance-crux"

    return $args
}

function Add-McpServerConfig {
    if (-not (Test-Path -LiteralPath $NpxWrapper)) {
        throw "npx wrapper not found: $NpxWrapper"
    }

    $desiredArgs = Get-DesiredArgs
    $addArgs = @(
        "mcp",
        "add",
        "--env",
        "CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1",
        "--env",
        "CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1",
        "--env",
        "SystemRoot=$env:SystemRoot",
        "--env",
        "PROGRAMFILES=$env:ProgramFiles",
        $ServerName,
        "--",
        $NpxWrapper
    ) + $desiredArgs

    Invoke-CodexCli -Arguments $addArgs
}

function Set-McpServerEnabledInConfig {
    param([Parameter(Mandatory = $true)][bool] $Enabled)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "config not found: $ConfigPath"
    }

    $sectionHeader = "[mcp_servers.$ServerName]"
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content -LiteralPath $ConfigPath)) {
        $lines.Add($line)
    }

    $sectionIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq $sectionHeader) {
            $sectionIndex = $i
            break
        }
    }

    if ($sectionIndex -lt 0) {
        throw "MCP section not found after add: $sectionHeader"
    }

    $enabledLine = "enabled = " + ($(if ($Enabled) { "true" } else { "false" }))
    $insertIndex = $sectionIndex + 1
    for ($i = $sectionIndex + 1; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed.StartsWith("[") -and $trimmed.EndsWith("]")) {
            break
        }

        if ($lines[$i] -match "^\s*enabled\s*=") {
            $lines[$i] = $enabledLine
            Write-Utf8NoBomLines -Path $ConfigPath -Lines $lines
            return
        }
    }

    $lines.Insert($insertIndex, $enabledLine)
    Write-Utf8NoBomLines -Path $ConfigPath -Lines $lines
}

function Show-HelpText {
    Write-Host "Chrome DevTools MCP observer toggle"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 status"
    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 on"
    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 off"
    Write-Host "  powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 verify-package"
    Write-Host ""
    Write-Host "Defaults:"
    Write-Host "  server=$ServerName"
    Write-Host "  command=$NpxWrapper"
    Write-Host "  args=-y chrome-devtools-mcp@latest --headless --isolated --no-usage-statistics --no-performance-crux"
    Write-Host "  env=CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1"
    Write-Host "  env=CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Visible  omit --headless for a visible isolated Chrome window"
    Write-Host "  -Slim     add --slim for the reduced basic browser tool surface"
    Write-Host "  -Full     accepted for compatibility; full is now the default"
}

if ($Action -eq "help") {
    Show-HelpText
    return
}

if ($Action -eq "status") {
    $serverInfo = Get-McpServerInfo
    if ($null -ne $serverInfo -and $serverInfo.enabled) {
        Write-Host "state=on"
        Invoke-CodexCli -Arguments @("mcp", "get", $ServerName, "--json")
    }
    elseif ($null -ne $serverInfo) {
        Write-Host "state=off"
        Write-Host "server=$ServerName is registered and disabled for UI visibility"
        Invoke-CodexCli -Arguments @("mcp", "get", $ServerName, "--json")
    }
    else {
        Write-Host "state=missing"
        Write-Host "server=$ServerName is not configured; run off to register disabled or on to enable"
    }
    return
}

if ($Action -eq "verify-package") {
    if (-not (Test-Path -LiteralPath $NpxWrapper)) {
        throw "npx wrapper not found: $NpxWrapper"
    }

    Write-Host "package_probe=chrome-devtools-mcp@latest --help"
    & $NpxWrapper -y chrome-devtools-mcp@latest --help
    if ($LASTEXITCODE -ne 0) {
        throw "chrome-devtools-mcp package probe failed with exit code $LASTEXITCODE"
    }
    return
}

if ($Action -eq "on") {
    if (-not (Test-Path -LiteralPath $NpxWrapper)) {
        throw "npx wrapper not found: $NpxWrapper"
    }

    Invoke-WithWritableConfig {
        Invoke-WithConfigRollback {
            if (Test-McpServerPresent) {
                Invoke-CodexCli -Arguments @("mcp", "remove", $ServerName)
            }

            Add-McpServerConfig
            Set-McpServerEnabledInConfig -Enabled $true
        }
    }

    Write-Host "state=on"
    Write-Host "note=restart_or_reload_codex_app_before_expecting_mcp_tools_in_this_session"
    Invoke-CodexCli -Arguments @("mcp", "get", $ServerName, "--json")
    return
}

if ($Action -eq "off") {
    Invoke-WithWritableConfig {
        Invoke-WithConfigRollback {
            if (-not (Test-McpServerPresent)) {
                Add-McpServerConfig
            }

            Set-McpServerEnabledInConfig -Enabled $false
        }
    }

    Write-Host "state=off"
    Write-Host "server=$ServerName registered and disabled for UI visibility"
    Invoke-CodexCli -Arguments @("mcp", "get", $ServerName, "--json")
    return
}
