param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex" }),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-PathItems {
    param([AllowNull()][string]$Value)
    if (-not $Value) {
        return @()
    }
    return @($Value -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') })
}

function Invoke-VersionCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [string[]]$Arguments = @("--version")
    )

    $global:LASTEXITCODE = $null
    try {
        $output = & $Executable @Arguments 2>&1
        $exitCode = if ($null -eq $LASTEXITCODE) {
            if ($?) { 0 } else { 1 }
        } else {
            $LASTEXITCODE
        }
        return [ordered]@{
            ok = ($exitCode -eq 0)
            exit_code = $exitCode
            output = @($output | ForEach-Object { $_.ToString() })
        }
    } catch {
        return [ordered]@{
            ok = $false
            exit_code = 1
            output = @($_.Exception.Message)
        }
    }
}

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Checks,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [hashtable]$Data = @{}
    )

    $item = [ordered]@{
        name = $Name
        status = $Status
        detail = $Detail
    }
    foreach ($key in $Data.Keys) {
        $item[$key] = $Data[$key]
    }
    $Checks.Add($item) | Out-Null
}

function Test-RipgrepOutput {
    param([object]$Result)
    if (-not $Result.ok) {
        return $false
    }
    return (@($Result.output) -join "`n") -match "ripgrep\s+\d+\."
}

function Test-RipgrepNoMatch {
    param([object]$Result)
    return ($Result.exit_code -eq 1 -and @($Result.output).Count -eq 0)
}

function ConvertTo-EncodedPowerShellCommand {
    param([Parameter(Mandatory = $true)][string]$Command)
    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
}

$bundleRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
$shimDir = Join-Path $CodexHome "toolchains\shims"
$cmdShimPath = Join-Path $shimDir "rg.cmd"
$psShimPath = Join-Path $shimDir "rg.ps1"
$windowsAppsCodexPattern = "*\WindowsApps\OpenAI.Codex_*\app\resources*"
$checks = [System.Collections.Generic.List[object]]::new()

$userPathItems = Get-PathItems ([Environment]::GetEnvironmentVariable("Path", "User"))
$machinePathItems = Get-PathItems ([Environment]::GetEnvironmentVariable("Path", "Machine"))
$processPathItems = Get-PathItems $env:Path
$normalizedShimDir = $shimDir.TrimEnd('\')

$persistentContainsShim = @($userPathItems + $machinePathItems | Where-Object { $_ -ieq $normalizedShimDir })
Add-Check -Checks $checks -Name "persistent-path-excludes-shim-root" -Status $(if ($persistentContainsShim.Count -eq 0) { "pass" } else { "fail" }) -Detail "The managed shim root must not be in persistent User or Machine PATH." -Data @{
    shim_root = $shimDir
    persistent_hits = @($persistentContainsShim)
}

$bundleRg = Join-Path $bundleRoot "rg.exe"
Add-Check -Checks $checks -Name "codex-bundled-rg-exists" -Status $(if (Test-Path -LiteralPath $bundleRg) { "pass" } else { "fail" }) -Detail "Codex Desktop bundled rg.exe is the source of truth for rg." -Data @{
    bundle_rg = $bundleRg
}

$rgCommands = @(Get-Command rg -All -ErrorAction SilentlyContinue)
$firstRg = $rgCommands | Select-Object -First 1
$firstRgSource = if ($firstRg) { $firstRg.Source } else { "" }
$firstIsExpected = $firstRgSource -and (
    $firstRgSource.StartsWith($bundleRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
    $firstRgSource.StartsWith($shimDir, [System.StringComparison]::OrdinalIgnoreCase) -or
    $firstRgSource -like $windowsAppsCodexPattern
)
$bareRgVersion = Invoke-VersionCommand -Executable "rg"
Add-Check -Checks $checks -Name "bare-rg-resolves-to-codex-source" -Status $(if ($firstIsExpected -and (Test-RipgrepOutput $bareRgVersion)) { "pass" } else { "fail" }) -Detail "Bare rg may be used only when it resolves to a Codex-owned source and runs successfully." -Data @{
    first_source = $firstRgSource
    all_sources = @($rgCommands | ForEach-Object { $_.Source })
    version_exit_code = $bareRgVersion.exit_code
    version_head = @($bareRgVersion.output | Select-Object -First 2)
}

$rgCmdCommands = @(Get-Command rg.cmd -All -ErrorAction SilentlyContinue)
if ($rgCmdCommands.Count -eq 0) {
    Add-Check -Checks $checks -Name "bare-rg-cmd-is-not-required" -Status "pass" -Detail "Bare rg.cmd is expected to be unavailable when the managed shim root is not on PATH; use explicit shim path or process-local PATH."
} else {
    $rgCmdSources = @($rgCmdCommands | ForEach-Object { $_.Source })
    $owned = @($rgCmdSources | Where-Object { $_.StartsWith($shimDir, [System.StringComparison]::OrdinalIgnoreCase) })
    Add-Check -Checks $checks -Name "bare-rg-cmd-owned-if-present" -Status $(if ($owned.Count -eq $rgCmdSources.Count) { "pass" } else { "fail" }) -Detail "If rg.cmd is visible as a bare command, it must be the managed Codex shim." -Data @{
        sources = $rgCmdSources
    }
}

$explicitCmdShimVersion = Invoke-VersionCommand -Executable $cmdShimPath
Add-Check -Checks $checks -Name "explicit-rg-cmd-version" -Status $(if ((Test-Path -LiteralPath $cmdShimPath) -and (Test-RipgrepOutput $explicitCmdShimVersion)) { "pass" } else { "fail" }) -Detail "The cmd compatibility shim should work for simple rg invocations." -Data @{
    shim_path = $cmdShimPath
    version_exit_code = $explicitCmdShimVersion.exit_code
    version_head = @($explicitCmdShimVersion.output | Select-Object -First 2)
}

$explicitPsShimVersion = Invoke-VersionCommand -Executable $psShimPath
Add-Check -Checks $checks -Name "explicit-rg-ps1-version" -Status $(if ((Test-Path -LiteralPath $psShimPath) -and (Test-RipgrepOutput $explicitPsShimVersion)) { "pass" } else { "fail" }) -Detail "The PowerShell shim should work for rg invocations without cmd.exe argument reparsing." -Data @{
    shim_path = $psShimPath
    version_exit_code = $explicitPsShimVersion.exit_code
    version_head = @($explicitPsShimVersion.output | Select-Object -First 2)
}

$metacharArgs = @("--fixed-strings", "AGENTS|NO_SUCH_PATTERN", (Join-Path $CodexHome "AGENTS.md"))
$bundleMetachar = Invoke-VersionCommand -Executable $bundleRg -Arguments $metacharArgs
$psShimMetachar = Invoke-VersionCommand -Executable $psShimPath -Arguments $metacharArgs
Add-Check -Checks $checks -Name "powershell-shim-metachar-forwarding" -Status $(if ((Test-RipgrepNoMatch $bundleMetachar) -and (Test-RipgrepNoMatch $psShimMetachar)) { "pass" } else { "fail" }) -Detail "The PowerShell rg shim must match bundled rg.exe behavior for cmd metacharacters such as pipe." -Data @{
    bundle_exit_code = $bundleMetachar.exit_code
    ps_shim_exit_code = $psShimMetachar.exit_code
    ps_shim_output_head = @($psShimMetachar.output | Select-Object -First 2)
}

$cmdMetachar = Invoke-VersionCommand -Executable "cmd.exe" -Arguments @("/d", "/c", "`"$cmdShimPath`" --fixed-strings AGENTS^|NO_SUCH_PATTERN `"$CodexHome\AGENTS.md`"")
Add-Check -Checks $checks -Name "cmd-shim-escaped-metachar-forwarding" -Status $(if (Test-RipgrepNoMatch $cmdMetachar) { "pass" } else { "fail" }) -Detail "The cmd rg shim should work for cmd.exe callers when metacharacters are escaped at the cmd boundary." -Data @{
    cmd_shim_exit_code = $cmdMetachar.exit_code
    cmd_shim_output_head = @($cmdMetachar.output | Select-Object -First 2)
}

$unescapedCmdMetachar = Invoke-VersionCommand -Executable $cmdShimPath -Arguments $metacharArgs
Add-Check -Checks $checks -Name "rg-cmd-powershell-metachar-limitation-recorded" -Status $(if ($unescapedCmdMetachar.exit_code -ne $psShimMetachar.exit_code -or @($unescapedCmdMetachar.output).Count -gt 0) { "pass" } else { "fail" }) -Detail "Direct rg.cmd from PowerShell with unescaped cmd metacharacters is a known unsupported path; use rg.ps1, bare rg, or bundled rg.exe." -Data @{
    cmd_shim_exit_code = $unescapedCmdMetachar.exit_code
    cmd_shim_output_head = @($unescapedCmdMetachar.output | Select-Object -First 2)
}

$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pwsh) {
    $pwshCommand = '$env:PATH = "' + $shimDir + ';" + $env:PATH; rg.ps1 --version'
    $encoded = ConvertTo-EncodedPowerShellCommand -Command $pwshCommand
    $pwshShimVersion = Invoke-VersionCommand -Executable $pwsh.Source -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded)
    Add-Check -Checks $checks -Name "new-pwsh-process-local-rg-ps1-shim" -Status $(if (Test-RipgrepOutput $pwshShimVersion) { "pass" } else { "fail" }) -Detail "A new pwsh process can use rg.ps1 when the shim root is added only to that process PATH." -Data @{
        version_exit_code = $pwshShimVersion.exit_code
        version_head = @($pwshShimVersion.output | Select-Object -First 2)
    }
} else {
    Add-Check -Checks $checks -Name "new-pwsh-process-local-rg-ps1-shim" -Status "warn" -Detail "pwsh was not available for process-local PowerShell shim validation."
}

$cmdShimVersion = Invoke-VersionCommand -Executable "cmd.exe" -Arguments @("/d", "/c", "set PATH=$shimDir;%PATH%&&rg.cmd --version")
Add-Check -Checks $checks -Name "new-cmd-process-local-rg-shim" -Status $(if (Test-RipgrepOutput $cmdShimVersion) { "pass" } else { "fail" }) -Detail "A new cmd.exe process can use rg.cmd when the shim root is added only to that process PATH." -Data @{
    version_exit_code = $cmdShimVersion.exit_code
    version_head = @($cmdShimVersion.output | Select-Object -First 2)
}

$oldLocation = Get-Location
try {
    Set-Location -LiteralPath ([Environment]::GetFolderPath("UserProfile"))
    $homeRgVersion = Invoke-VersionCommand -Executable "rg"
} finally {
    Set-Location -LiteralPath $oldLocation
}
Add-Check -Checks $checks -Name "bare-rg-different-cwd" -Status $(if (Test-RipgrepOutput $homeRgVersion) { "pass" } else { "fail" }) -Detail "Bare rg resolution is stable outside CODEX_HOME." -Data @{
    cwd = [Environment]::GetFolderPath("UserProfile")
    version_exit_code = $homeRgVersion.exit_code
    version_head = @($homeRgVersion.output | Select-Object -First 2)
}

$failures = @($checks | Where-Object { $_.status -eq "fail" })
$warnings = @($checks | Where-Object { $_.status -eq "warn" })
$report = [ordered]@{
    status = if ($failures.Count -eq 0) { "pass" } else { "fail" }
    codex_home = $CodexHome
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    source_of_truth = $bundleRg
    supported_invocations = @(
        "rg --version",
        "$psShimPath --version",
        "$cmdShimPath --version for cmd-compatible arguments",
        "process-local PATH + rg.ps1 --version in PowerShell",
        "process-local PATH + rg.cmd --version in cmd.exe"
    )
    unsupported_invocations = @(
        "bare rg.cmd without process-local PATH",
        "direct rg.cmd from PowerShell with unescaped cmd metacharacters"
    )
    process_path_contains_shim_root = [bool](@($processPathItems | Where-Object { $_ -ieq $normalizedShimDir }).Count)
    failures = $failures.Count
    warnings = $warnings.Count
    checks = $checks
}

$reportDir = Join-Path $CodexHome "reports"
if (-not (Test-Path -LiteralPath $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}
$reportJson = $report | ConvertTo-Json -Depth 8
Set-Content -LiteralPath (Join-Path $reportDir "rg-resolution.latest.json") -Value $reportJson -Encoding UTF8

if ($Json) {
    $reportJson
} else {
    "status=$($report.status); failures=$($report.failures); warnings=$($report.warnings)"
    foreach ($item in $checks) {
        "$($item.status) $($item.name) - $($item.detail)"
    }
}

if ($failures.Count -gt 0) {
    exit 1
}
