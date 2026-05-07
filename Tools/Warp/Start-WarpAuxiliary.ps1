Set-StrictMode -Version Latest

function Add-CodexWarpWindowApi {
    if ('CodexWarpWindowApi' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CodexWarpWindowApi
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
'@
}

function Get-WarpAuxiliaryStatus {
    [CmdletBinding()]
    param()

    $warpExe = Join-Path $env:LOCALAPPDATA 'Programs\Warp\warp.exe'
    $settingsPath = Join-Path $env:LOCALAPPDATA 'warp\Warp\config\settings.toml'
    $settingsText = ''
    if (Test-Path -LiteralPath $settingsPath) {
        $settingsText = Get-Content -LiteralPath $settingsPath -Raw
    }

    [pscustomobject]@{
        WarpExe = $warpExe
        WarpExeExists = Test-Path -LiteralPath $warpExe
        SettingsPath = $settingsPath
        SettingsExists = Test-Path -LiteralPath $settingsPath
        GlobalAiDisabled = $settingsText -match 'is_any_ai_enabled\s*=\s*false'
        AgentModeDisabled = $settingsText -match 'default_session_mode\s*=\s*"terminal"'
        CloudConversationStorageDisabled = $settingsText -match 'cloud_conversation_storage_enabled\s*=\s*false'
        TelemetryDisabled = $settingsText -match 'telemetry_enabled\s*=\s*false'
        CrashReportingDisabled = $settingsText -match 'crash_reporting_enabled\s*=\s*false'
        NaturalLanguageDetectionDisabled = $settingsText -match 'nld_in_terminal_enabled\s*=\s*false'
        AuxiliaryLaunchMode = 'minimized_restore_previous_foreground'
        AllowedOperators = 'Codex and Codex-authorized subagents only'
    }
}

function Start-WarpAuxiliary {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$WorkingDirectory = (Get-Location).Path,

        [switch]$Foreground
    )

    $warpExe = Join-Path $env:LOCALAPPDATA 'Programs\Warp\warp.exe'
    if (-not (Test-Path -LiteralPath $warpExe)) {
        throw "Warp executable was not found at $warpExe."
    }

    $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path

    Add-CodexWarpWindowApi
    $previousForegroundWindow = [CodexWarpWindowApi]::GetForegroundWindow()

    $process = Start-Process `
        -FilePath $warpExe `
        -WorkingDirectory $resolvedWorkingDirectory `
        -WindowStyle Minimized `
        -PassThru

    if (-not $Foreground) {
        Start-Sleep -Milliseconds 900
        Get-Process -Name 'Warp' -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.MainWindowHandle -ne [IntPtr]::Zero) {
                [void][CodexWarpWindowApi]::ShowWindowAsync($_.MainWindowHandle, 6)
            }
        }

        if ($previousForegroundWindow -ne [IntPtr]::Zero) {
            [void][CodexWarpWindowApi]::SetForegroundWindow($previousForegroundWindow)
        }
    }

    [pscustomobject]@{
        ProcessId = $process.Id
        WorkingDirectory = $resolvedWorkingDirectory
        LaunchMode = if ($Foreground) { 'foreground_requested' } else { 'minimized_restore_previous_foreground' }
    }
}

Set-Alias -Name warpaux -Value Start-WarpAuxiliary -Scope Global
