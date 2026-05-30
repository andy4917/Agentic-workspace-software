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

function Resolve-CodexBundledTool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $binRoot = Get-CodexBundleRoot
    if ([string]::IsNullOrWhiteSpace($binRoot)) {
        return ""
    }

    $direct = Join-Path $binRoot ($Name + ".exe")
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return $direct
    }

    $match = Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $candidate = Join-Path $_.FullName ($Name + ".exe")
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                Get-Item -LiteralPath $candidate
            }
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -ne $match) {
        return $match.FullName
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
    $dynamicBundlePattern = [regex]::Escape("%LOCALAPPDATA%\OpenAI\Codex\bin")
    return ($text -match $bundlePattern -or $text -match $absolutePattern -or ($text -match $dynamicBundlePattern -and $text -match [regex]::Escape("$ToolName.exe")))
}

function Test-OfficialWrapperSourcePolicy {
    param(
        [string]$WrapperPath
    )

    if (-not (Test-Path -LiteralPath $WrapperPath)) {
        return [ordered]@{
            ok = $false
            disallowed_before_bundle = @("missing wrapper")
        }
    }

    $text = Get-Content -LiteralPath $WrapperPath -Raw
    $bundleNeedle = "%LOCALAPPDATA%\OpenAI\Codex\bin"
    $bundleIndex = $text.IndexOf($bundleNeedle, [System.StringComparison]::OrdinalIgnoreCase)
    $disallowed = @(
        @{ name = "standalone_package"; needle = "\.codex\packages\standalone" },
        @{ name = "scoop_app"; needle = "\scoop\apps\" },
        @{ name = "scoop_shim"; needle = "\scoop\shims\" }
    )
    $hits = @()
    foreach ($entry in $disallowed) {
        $index = $text.IndexOf($entry.needle, [System.StringComparison]::OrdinalIgnoreCase)
        if ($index -ge 0 -and ($bundleIndex -lt 0 -or $index -lt $bundleIndex)) {
            $hits += $entry.name
        }
    }

    return [ordered]@{
        ok = ($hits.Count -eq 0)
        disallowed_before_bundle = $hits
    }
}

$bundleRoot = Get-CodexBundleRoot
$workspaceRuntimeRoot = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".cache\codex-runtimes\codex-primary-runtime\dependencies"
$windowsAppsCodexPattern = "*\WindowsApps\OpenAI.Codex_*\app\resources*"
$shimDir = Join-Path $CodexHome "toolchains\shims"
$officialBundleTools = @("codex", "node", "rg")
$jsLocalChainTools = @("npm", "npx")
$checks = [System.Collections.Generic.List[object]]::new()
$rgResolutionScript = Join-Path $CodexHome "maintenance\scripts\check-rg-resolution.ps1"
if (-not (Test-Path -LiteralPath $rgResolutionScript -PathType Leaf)) {
    $candidate = Join-Path $PSScriptRoot "check-rg-resolution.ps1"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $rgResolutionScript = $candidate
    }
}

foreach ($tool in $officialBundleTools) {
    $bundlePath = Resolve-CodexBundledTool -Name $tool
    $wrapperPath = Join-Path $shimDir "$tool.cmd"
    $bundleExists = $bundlePath -and (Test-Path -LiteralPath $bundlePath)
    $wrapperUsesBundle = Test-WrapperUsesBundle -WrapperPath $wrapperPath -ToolName $tool -BundleRoot $bundleRoot
    $wrapperSourcePolicy = Test-OfficialWrapperSourcePolicy -WrapperPath $wrapperPath
    $checks.Add([ordered]@{
        name = "official-bundle-wrapper:$tool"
        status = if ($bundleExists -and $wrapperUsesBundle -and $wrapperSourcePolicy.ok) { "pass" } else { "fail" }
        source_class = "official-bundle"
        wrapper = $wrapperPath
        bundle = $bundlePath
        bundle_exists = [bool]$bundleExists
        wrapper_uses_bundle = [bool]$wrapperUsesBundle
        wrapper_source_policy = $wrapperSourcePolicy
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

foreach ($commandName in @("codex", "node", "rg")) {
    $commands = @(Get-Command $commandName -All -ErrorAction SilentlyContinue)
    $firstCommand = @($commands | Select-Object -First 1)
    $firstSource = if ($firstCommand.Count -gt 0) {
        if (-not [string]::IsNullOrWhiteSpace([string]$firstCommand[0].Source)) {
            [string]$firstCommand[0].Source
        } elseif (-not [string]::IsNullOrWhiteSpace([string]$firstCommand[0].Path)) {
            [string]$firstCommand[0].Path
        } else {
            [string]$firstCommand[0].Definition
        }
    } else {
        ""
    }
    $firstAllowed = (
        -not [string]::IsNullOrWhiteSpace($firstSource) -and (
            ((-not [string]::IsNullOrWhiteSpace($shimDir)) -and $firstSource -like "$shimDir\*") -or
            ((-not [string]::IsNullOrWhiteSpace($bundleRoot)) -and $firstSource -like "$bundleRoot\*") -or
            $firstSource -like $windowsAppsCodexPattern
        )
    )
    $checks.Add([ordered]@{
        name = "first-command-source:$commandName"
        status = if ($firstAllowed) { "pass" } else { "fail" }
        source_class = "official-bundle"
        first_source = $firstSource
        allowed_roots = @($shimDir, $bundleRoot, $windowsAppsCodexPattern)
    })
    $localDuplicates = @($commands | Where-Object {
        $_.Source -and
        $_.Source -notlike "$bundleRoot\*" -and
        $_.Source -notlike "$shimDir\*" -and
        $_.Source -notlike $windowsAppsCodexPattern
    } | ForEach-Object { $_.Source })
    $localDuplicateTargets = @($localDuplicates | ForEach-Object {
        $source = [string]$_
        $resolved = if ($source -like "*\scoop\shims\*.exe") { Resolve-ScoopShimTarget -ShimExe $source } else { $source }
        [ordered]@{
            source = $source
            resolved = $resolved
            target_exists = (-not [string]::IsNullOrWhiteSpace($resolved) -and (Test-Path -LiteralPath $resolved))
        }
    })
    $brokenLocalDuplicates = @($localDuplicateTargets | Where-Object { -not $_.target_exists })
    $checks.Add([ordered]@{
        name = "local-duplicate-marked-unused:$commandName"
        status = if ($brokenLocalDuplicates.Count -eq 0) { "pass" } else { "fail" }
        source_class = "local-chain"
        reason = if ($localDuplicates.Count -gt 0) { "Local duplicate exists, but Codex wrappers do not use it; duplicate targets must still be valid for normal PowerShell PATH fallback." } else { "No local duplicate before the Codex bundle." }
        local_duplicates = $localDuplicates
        local_duplicate_targets = $localDuplicateTargets
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
    status = if ($gdbProbe.ok -or -not (Test-Path -LiteralPath $gdbWrapper -PathType Leaf)) { "pass" } else { "fail" }
    source_class = "local-chain"
    wrapper = $gdbWrapper
    availability = if ($gdbProbe.ok) { "active" } elseif (-not (Test-Path -LiteralPath $gdbWrapper -PathType Leaf)) { "optional_not_restored" } else { "unavailable" }
    target_scope = "GNU/UCRT native debugging"
    exit_code = $gdbProbe.exit_code
    output_preview = Get-PreviewText -Value $gdbProbe.output -Limit 160
    error = $gdbProbe.error
})

$cdbWrapper = Join-Path $shimDir "cdb.cmd"
$cdbProbe = Invoke-WrapperProbe -WrapperPath $cdbWrapper -Arguments @("-version") -ExpectedPattern "cdb version"
$checks.Add([ordered]@{
    name = "debugger-smoke:cdb"
    status = if ($cdbProbe.ok -or -not (Test-Path -LiteralPath $cdbWrapper -PathType Leaf)) { "pass" } else { "fail" }
    source_class = "local-chain"
    wrapper = $cdbWrapper
    availability = if ($cdbProbe.ok) { "active" } elseif (-not (Test-Path -LiteralPath $cdbWrapper -PathType Leaf)) { "optional_not_restored" } else { "unavailable" }
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
    $missingOptional = -not (Test-Path -LiteralPath $wrapper -PathType Leaf)
    $checks.Add([ordered]@{
        name = "debugger-conditional:$rustDebugger"
        status = if ($probe.ok -or $conditionalMsvc -or $missingOptional) { "pass" } else { "fail" }
        source_class = "local-chain"
        wrapper = $wrapper
        availability = if ($probe.ok) { "active" } elseif ($conditionalMsvc) { "conditional_not_active" } elseif ($missingOptional) { "optional_not_restored" } else { "unavailable" }
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
