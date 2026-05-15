param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex" }),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-CodexBundleRoot {
    $candidate = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }
    return ""
}

function Resolve-ScoopShimTarget {
    param([string]$ShimExe)

    $shimFile = [System.IO.Path]::ChangeExtension($ShimExe, ".shim")
    if (-not (Test-Path -LiteralPath $shimFile)) {
        return ""
    }

    $text = Get-Content -LiteralPath $shimFile -Raw
    if ($text -match 'path\s*=\s*"([^"]+)"') {
        return [Environment]::ExpandEnvironmentVariables($Matches[1])
    }
    return ""
}

function Invoke-WrapperProbe {
    param(
        [string]$WrapperPath,
        [string[]]$Arguments = @(),
        [string]$ExpectedPattern = "",
        [int[]]$AllowedExitCodes = @(0)
    )

    if (-not (Test-Path -LiteralPath $WrapperPath)) {
        return [ordered]@{
            exit_code = -1
            output = ""
            target_exists = $false
            pattern_matched = $false
            ok = $false
            error = "missing wrapper"
        }
    }

    try {
        $outputText = (& $WrapperPath @Arguments 2>&1 | Out-String).Trim()
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        $matched = if ($ExpectedPattern) { $outputText -match $ExpectedPattern } else { $true }
        return [ordered]@{
            exit_code = $exitCode
            output = $outputText
            target_exists = $true
            pattern_matched = [bool]$matched
            ok = ($AllowedExitCodes -contains $exitCode) -and [bool]$matched
            error = ""
        }
    } catch {
        $errorText = $_.Exception.Message
        return [ordered]@{
            exit_code = -1
            output = $errorText
            target_exists = $true
            pattern_matched = $false
            ok = $false
            error = $errorText
        }
    }
}

function Get-PreviewText {
    param(
        [string]$Value,
        [int]$Limit = 160
    )

    $compact = ($Value -replace "\s+", " ").Trim()
    if ($compact.Length -le $Limit) {
        return $compact
    }
    return $compact.Substring(0, $Limit)
}

function Test-WrapperUsesBundle {
    param(
        [string]$WrapperPath,
        [string]$ToolName,
        [string]$BundleRoot
    )

    if (-not (Test-Path -LiteralPath $WrapperPath)) {
        return $false
    }
    $text = Get-Content -LiteralPath $WrapperPath -Raw
    $bundlePattern = [regex]::Escape("%LOCALAPPDATA%\OpenAI\Codex\bin\$ToolName.exe")
    $absolutePattern = [regex]::Escape((Join-Path $BundleRoot "$ToolName.exe"))
    return ($text -match $bundlePattern -or $text -match $absolutePattern)
}

$bundleRoot = Get-CodexBundleRoot
$workspaceRuntimeRoot = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".cache\codex-runtimes\codex-primary-runtime\dependencies"
$windowsAppsCodexPattern = "*\WindowsApps\OpenAI.Codex_*\app\resources*"
$shimDir = Join-Path $CodexHome "toolchains\shims"
$officialBundleTools = @("node", "rg")
$jsLocalChainTools = @("npm", "npx")
$checks = [System.Collections.Generic.List[object]]::new()
$rgResolutionScript = Join-Path $CodexHome "maintenance\scripts\check-rg-resolution.ps1"

foreach ($tool in $officialBundleTools) {
    $bundlePath = if ($bundleRoot) { Join-Path $bundleRoot "$tool.exe" } else { "" }
    $wrapperPath = Join-Path $shimDir "$tool.cmd"
    $bundleExists = $bundlePath -and (Test-Path -LiteralPath $bundlePath)
    $wrapperUsesBundle = Test-WrapperUsesBundle -WrapperPath $wrapperPath -ToolName $tool -BundleRoot $bundleRoot
    $checks.Add([ordered]@{
        name = "official-bundle-wrapper:$tool"
        status = if ($bundleExists -and $wrapperUsesBundle) { "pass" } else { "fail" }
        source_class = "official-bundle"
        wrapper = $wrapperPath
        bundle = $bundlePath
        bundle_exists = [bool]$bundleExists
        wrapper_uses_bundle = [bool]$wrapperUsesBundle
    })
}

foreach ($runtimeTool in @(
    @{ name = "node"; relative = "node\bin\node.exe" },
    @{ name = "python"; relative = "python\python.exe" }
)) {
    $runtimePath = Join-Path $workspaceRuntimeRoot $runtimeTool.relative
    $runtimeExists = Test-Path -LiteralPath $runtimePath
    $checks.Add([ordered]@{
        name = "workspace-runtime-bundle:$($runtimeTool.name)"
        status = if ($runtimeExists) { "pass" } else { "fail" }
        source_class = "official-bundle"
        runtime = $runtimePath
        runtime_exists = [bool]$runtimeExists
    })
}

foreach ($commandName in @("node", "rg")) {
    $commands = @(Get-Command $commandName -All -ErrorAction SilentlyContinue)
    $localDuplicates = @($commands | Where-Object {
        $_.Source -and
        $_.Source -notlike "$bundleRoot*" -and
        $_.Source -notlike "$shimDir*" -and
        $_.Source -notlike $windowsAppsCodexPattern
    } | ForEach-Object { $_.Source })
    $checks.Add([ordered]@{
        name = "local-duplicate-marked-unused:$commandName"
        status = "pass"
        source_class = "local-chain"
        reason = if ($localDuplicates.Count -gt 0) { "Local duplicate exists, but Codex wrappers do not use it; bare command use remains discouraged." } else { "No local duplicate before the Codex bundle." }
        local_duplicates = $localDuplicates
    })
}

foreach ($tool in $jsLocalChainTools) {
    $wrapperPath = Join-Path $shimDir "$tool.cmd"
    $text = if (Test-Path -LiteralPath $wrapperPath) { Get-Content -LiteralPath $wrapperPath -Raw } else { "" }
    $usesLocalPackage = $text -match [regex]::Escape("%APPDATA%\npm\$tool.cmd")
    $prefersBundleNode = $text -match [regex]::Escape("%LOCALAPPDATA%\OpenAI\Codex\bin")
    $checks.Add([ordered]@{
        name = "js-local-chain-wrapper:$tool"
        status = if ($usesLocalPackage -and $prefersBundleNode) { "pass" } else { "fail" }
        source_class = "local-chain"
        wrapper = $wrapperPath
        uses_local_package = [bool]$usesLocalPackage
        prefers_bundle_node = [bool]$prefersBundleNode
    })
}

foreach ($shim in Get-ChildItem -LiteralPath $shimDir -Filter "*.cmd" -ErrorAction SilentlyContinue) {
    $text = Get-Content -LiteralPath $shim.FullName -Raw
    foreach ($match in [regex]::Matches($text, '"([^"]+)"')) {
        $target = [Environment]::ExpandEnvironmentVariables($match.Groups[1].Value)
        if ($target -notmatch "^[A-Za-z]:\\") {
            continue
        }
        if ($target -like "*\scoop\shims\*.exe") {
            continue
        }
        if ($target -like "$bundleRoot\*") {
            continue
        }
        $exists = Test-Path -LiteralPath $target
        $checks.Add([ordered]@{
            name = "direct-wrapper-target:$($shim.Name)"
            status = if ($exists) { "pass" } else { "fail" }
            source_class = "local-chain"
            wrapper = $shim.FullName
            target = $target
            target_exists = [bool]$exists
        })
    }
}

foreach ($shim in Get-ChildItem -LiteralPath $shimDir -Filter "*.cmd" -ErrorAction SilentlyContinue) {
    $text = Get-Content -LiteralPath $shim.FullName -Raw
    foreach ($match in [regex]::Matches($text, '"([^"]+)"')) {
        $target = [Environment]::ExpandEnvironmentVariables($match.Groups[1].Value)
        if ($target -like "*\scoop\shims\*.exe") {
            $resolved = Resolve-ScoopShimTarget -ShimExe $target
            $exists = $resolved -and (Test-Path -LiteralPath $resolved)
            $checks.Add([ordered]@{
                name = "scoop-shim-target:$($shim.Name)"
                status = if ($exists) { "pass" } else { "fail" }
                source_class = "local-chain"
                wrapper = $shim.FullName
                shim = $target
                resolved_target = $resolved
                resolved_exists = [bool]$exists
            })
        }
    }
}

if (Test-Path -LiteralPath $rgResolutionScript) {
    try {
        $rgResolutionJson = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $rgResolutionScript -CodexHome $CodexHome -Json
        $rgResolutionExit = $LASTEXITCODE
        $rgResolution = $rgResolutionJson | ConvertFrom-Json
        $checks.Add([ordered]@{
            name = "rg-resolution-smoke"
            status = if ($rgResolutionExit -eq 0 -and $rgResolution.status -eq "pass") { "pass" } else { "fail" }
            source_class = "official-bundle"
            source_of_truth = $rgResolution.source_of_truth
            supported_invocations = $rgResolution.supported_invocations
            unsupported_invocations = $rgResolution.unsupported_invocations
            failures = $rgResolution.failures
            warnings = $rgResolution.warnings
        })
    } catch {
        $checks.Add([ordered]@{
            name = "rg-resolution-smoke"
            status = "fail"
            source_class = "official-bundle"
            error = $_.Exception.Message
        })
    }
} else {
    $checks.Add([ordered]@{
        name = "rg-resolution-smoke"
        status = "fail"
        source_class = "official-bundle"
        error = "missing check-rg-resolution.ps1"
    })
}

$gdbWrapper = Join-Path $shimDir "gdb.cmd"
$gdbProbe = Invoke-WrapperProbe -WrapperPath $gdbWrapper -Arguments @("--version") -ExpectedPattern "GNU gdb"
$checks.Add([ordered]@{
    name = "debugger-smoke:gdb"
    status = if ($gdbProbe.ok) { "pass" } else { "fail" }
    source_class = "local-chain"
    wrapper = $gdbWrapper
    availability = if ($gdbProbe.ok) { "active" } else { "unavailable" }
    target_scope = "GNU/UCRT native debugging"
    exit_code = $gdbProbe.exit_code
    output_preview = Get-PreviewText -Value $gdbProbe.output -Limit 160
    error = $gdbProbe.error
})

$cdbWrapper = Join-Path $shimDir "cdb.cmd"
$cdbProbe = Invoke-WrapperProbe -WrapperPath $cdbWrapper -Arguments @("-version") -ExpectedPattern "cdb version"
$checks.Add([ordered]@{
    name = "debugger-smoke:cdb"
    status = if ($cdbProbe.ok) { "pass" } else { "fail" }
    source_class = "local-chain"
    wrapper = $cdbWrapper
    availability = if ($cdbProbe.ok) { "active" } else { "unavailable" }
    target_scope = "Windows Debugging Tools for dump/MSVC-native investigations"
    exit_code = $cdbProbe.exit_code
    output_preview = Get-PreviewText -Value $cdbProbe.output -Limit 160
    error = $cdbProbe.error
})

$pythonWrapper = Join-Path $shimDir "python.cmd"
$pdbProbe = Invoke-WrapperProbe -WrapperPath $pythonWrapper -Arguments @("-c", "import pdb, sys; print('pdb available ' + sys.version.split()[0])") -ExpectedPattern "pdb available"
$checks.Add([ordered]@{
    name = "debugger-smoke:python-pdb"
    status = if ($pdbProbe.ok) { "pass" } else { "fail" }
    source_class = "local-chain"
    wrapper = $pythonWrapper
    availability = if ($pdbProbe.ok) { "active_builtin" } else { "unavailable" }
    target_scope = "Python built-in debugger"
    exit_code = $pdbProbe.exit_code
    output_preview = Get-PreviewText -Value $pdbProbe.output -Limit 160
    error = $pdbProbe.error
})

$debugpyProbe = Invoke-WrapperProbe -WrapperPath $pythonWrapper -Arguments @("-c", "import importlib.util; print('debugpy=' + ('available' if importlib.util.find_spec('debugpy') else 'not_installed'))") -ExpectedPattern "debugpy="
$debugpyAvailable = $debugpyProbe.output -match "debugpy=available"
$checks.Add([ordered]@{
    name = "debugger-conditional:debugpy"
    status = if ($debugpyProbe.ok) { "pass" } else { "fail" }
    source_class = "local-chain"
    wrapper = $pythonWrapper
    availability = if ($debugpyAvailable) { "active" } else { "optional_not_installed" }
    target_scope = "Python IDE/attach debugger; project-environment optional"
    exit_code = $debugpyProbe.exit_code
    output_preview = Get-PreviewText -Value $debugpyProbe.output -Limit 160
    error = $debugpyProbe.error
})

$rustupWrapper = Join-Path $shimDir "rustup.cmd"
$activeRustToolchain = ""
if (Test-Path -LiteralPath $rustupWrapper) {
    $activeRustToolchain = (& $rustupWrapper show active-toolchain 2>&1 | Out-String).Trim()
}

foreach ($rustDebugger in @("rust-gdb", "rust-lldb")) {
    $wrapper = Join-Path $shimDir "$rustDebugger.cmd"
    $probe = Invoke-WrapperProbe -WrapperPath $wrapper -Arguments @("--version")
    $probeText = "$($probe.output) $($probe.error)"
    $conditionalMsvc = (-not $probe.ok) -and ($probeText -match "not applicable") -and ($activeRustToolchain -match "pc-windows-msvc")
    $checks.Add([ordered]@{
        name = "debugger-conditional:$rustDebugger"
        status = if ($probe.ok -or $conditionalMsvc) { "pass" } else { "fail" }
        source_class = "local-chain"
        wrapper = $wrapper
        availability = if ($probe.ok) { "active" } elseif ($conditionalMsvc) { "conditional_not_active" } else { "unavailable" }
        active_rust_toolchain = $activeRustToolchain
        target_scope = "Rustup debugger wrapper; conditional on compatible Rust toolchain"
        exit_code = $probe.exit_code
        output_preview = Get-PreviewText -Value $probe.output -Limit 220
        error = $probe.error
    })
}

$failures = @($checks | Where-Object { $_.status -eq "fail" })
$warnings = @($checks | Where-Object { $_.status -eq "warn" })
$report = [ordered]@{
    status = if ($failures.Count -eq 0) { "pass" } else { "fail" }
    codex_home = $CodexHome
    bundle_root = $bundleRoot
    failures = $failures.Count
    warnings = $warnings.Count
    checks = $checks
}

if ($Json) {
    $report | ConvertTo-Json -Depth 8
} else {
    "status=$($report.status); failures=$($report.failures); warnings=$($report.warnings)"
    foreach ($item in $checks) {
        "$($item.status) $($item.name)"
    }
}

if ($failures.Count -gt 0) {
    exit 1
}
