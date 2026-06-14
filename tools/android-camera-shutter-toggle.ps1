param(
    [ValidateSet("Status", "Off", "On", "Toggle")]
    [string]$Mode = "Status",

    [string]$Serial = "",

    [switch]$NoForceStop
)

$ErrorActionPreference = "Stop"

function Find-Adb {
    $candidates = @()

    if ($env:ADB -and (Test-Path -LiteralPath $env:ADB)) {
        $candidates += $env:ADB
    }

    $command = Get-Command adb -ErrorAction SilentlyContinue
    if ($command) {
        $candidates += $command.Source
    }

    $commonPaths = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe",
        "$env:TEMP\codex-platform-tools\platform-tools\adb.exe",
        "$env:USERPROFILE\Downloads\platform-tools\adb.exe",
        "$env:USERPROFILE\Desktop\platform-tools\adb.exe",
        "C:\platform-tools\adb.exe"
    )

    foreach ($path in $commonPaths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            $candidates += $path
        }
    }

    $adb = $candidates | Select-Object -First 1
    if ($adb) {
        return $adb
    }

    $zip = "$env:USERPROFILE\Downloads\platform-tools-latest-windows.zip"
    if (Test-Path -LiteralPath $zip) {
        $dest = Join-Path $env:TEMP "codex-platform-tools"
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
        $extracted = Join-Path $dest "platform-tools\adb.exe"
        if (Test-Path -LiteralPath $extracted) {
            return $extracted
        }
    }

    throw "adb.exe was not found. Install Android Platform Tools or place platform-tools-latest-windows.zip in Downloads."
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Adb,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    if ($Serial) {
        $commandArguments = @("-s", $Serial) + $Arguments
    } else {
        $commandArguments = $Arguments
    }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $Adb @commandArguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $commandText = @($Adb) + $commandArguments | ForEach-Object {
            if ($_ -match "\s") { "'$($_ -replace "'", "''")'" } else { $_ }
        }
        $details = ($output | Out-String).Trim()
        if ($details) {
            throw "adb exited with code $exitCode while running: $($commandText -join ' ')`n$details"
        }
        throw "adb exited with code $exitCode while running: $($commandText -join ' ')"
    }

    $output
}

function Get-ShutterValue {
    param([string]$Adb)

    $value = (Invoke-Adb -Adb $Adb -Arguments @("shell", "settings", "get", "system", "csc_pref_camera_forced_shuttersound_key") | Select-Object -First 1)
    return "$value".Trim()
}

$adbPath = Find-Adb
$devices = & $adbPath devices | Select-Object -Skip 1 | Where-Object { $_ -match "\S+\s+device$" }

if (-not $Serial -and @($devices).Count -ne 1) {
    & $adbPath devices -l
    throw "Expected exactly one authorized ADB device. Pass -Serial if multiple devices are connected."
}

$current = Get-ShutterValue -Adb $adbPath
$target = $null

switch ($Mode) {
    "Off" { $target = "0" }
    "On" { $target = "1" }
    "Toggle" {
        if ($current -eq "0") {
            $target = "1"
        } else {
            $target = "0"
        }
    }
}

if ($null -ne $target) {
    Invoke-Adb -Adb $adbPath -Arguments @("shell", "settings", "put", "system", "csc_pref_camera_forced_shuttersound_key", $target) | Out-Null
    if (-not $NoForceStop) {
        Invoke-Adb -Adb $adbPath -Arguments @("shell", "am", "force-stop", "com.sec.android.app.camera") | Out-Null
    }
}

$final = Get-ShutterValue -Adb $adbPath
$state = if ($final -eq "0") { "off" } elseif ($final -eq "1") { "forced-on" } else { "unknown:$final" }

[pscustomobject]@{
    Adb = $adbPath
    Mode = $Mode
    PreviousValue = $current
    CurrentValue = $final
    ShutterState = $state
    CameraRestarted = -not $NoForceStop -and $null -ne $target
}
