# Toggle the frontend-only Chrome DevTools MCP observer.
#
# This script intentionally uses `codex mcp add/remove` instead of editing
# config.toml by hand. OFF means the server entry is absent from config so Codex
# Desktop does not load the MCP server for non-frontend work.

[CmdletBinding()]
param(
    [ValidateSet("status", "on", "off", "verify-package", "help")]
    [string] $Action = "status",

    [string] $ServerName = "chrome_devtools_observe",

    [switch] $Visible,

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
$BackupRoot = Join-PathStrict $CodexHome "state\mcp-toggle-backups"
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

function Test-McpServerPresent {
    $previousPath = $env:PATH
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $env:PATH = "$ShimDir;$previousPath"
        $ErrorActionPreference = "Continue"
        $output = & $CodexExe mcp get $ServerName --json 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            return $true
        }

        $message = ($output | Out-String).Trim()
        if ($message -match "No MCP server named") {
            return $false
        }

        throw "codex mcp get failed with code ${exitCode}: $message"
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        $env:PATH = $previousPath
    }
}

function Save-ConfigBackup {
    param([Parameter(Mandatory = $true)][string] $Reason)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return
    }

    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $destination = Join-PathStrict $BackupRoot "config.$Reason.$stamp.toml"
    Copy-Item -LiteralPath $ConfigPath -Destination $destination -Force
    Write-Host "backup=$destination"
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

function Get-DesiredArgs {
    $args = @("-y", "chrome-devtools-mcp@latest")

    if (-not $Full) {
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
    Write-Host "  args=-y chrome-devtools-mcp@latest --slim --headless --isolated --no-usage-statistics --no-performance-crux"
    Write-Host "  env=CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1"
    Write-Host "  env=CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Visible  omit --headless for a visible isolated Chrome window"
    Write-Host "  -Full     omit --slim and expose the full MCP tool surface"
}

if ($Action -eq "help") {
    Show-HelpText
    return
}

if ($Action -eq "status") {
    if (Test-McpServerPresent) {
        Write-Host "state=on"
        Invoke-CodexCli -Arguments @("mcp", "get", $ServerName, "--json")
    }
    else {
        Write-Host "state=off"
        Write-Host "server=$ServerName is not configured"
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

    Save-ConfigBackup -Reason "before-chrome-devtools-on"

    Invoke-WithWritableConfig {
        if (Test-McpServerPresent) {
            Invoke-CodexCli -Arguments @("mcp", "remove", $ServerName)
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

    Write-Host "state=on"
    Write-Host "note=restart_or_reload_codex_app_before_expecting_mcp_tools_in_this_session"
    Invoke-CodexCli -Arguments @("mcp", "get", $ServerName, "--json")
    return
}

if ($Action -eq "off") {
    if (-not (Test-McpServerPresent)) {
        Write-Host "state=off"
        Write-Host "server=$ServerName already absent"
        return
    }

    Save-ConfigBackup -Reason "before-chrome-devtools-off"

    Invoke-WithWritableConfig {
        Invoke-CodexCli -Arguments @("mcp", "remove", $ServerName)
    }

    Write-Host "state=off"
    Write-Host "server=$ServerName removed from MCP config"
    return
}
