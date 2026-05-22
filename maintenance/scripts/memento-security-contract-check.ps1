param(
    [string]$SourceRoot,
    [switch]$SkipTestCi,
    [switch]$Json
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

function Join-PathStrict {
    param([string]$Base, [string]$Child)
    return [System.IO.Path]::GetFullPath((Join-Path $Base $Child))
}

function Add-Check {
    param(
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Name,
        [string]$Status,
        [string]$Evidence
    )
    $Checks.Add([pscustomobject]@{
        name = $Name
        status = $Status
        evidence = $Evidence
    }) | Out-Null
}

function Invoke-CheckedCommand {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    $output = New-Object System.Collections.Generic.List[string]
    Push-Location -LiteralPath $WorkingDirectory
    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $Command @Arguments 2>&1 | ForEach-Object { $output.Add([string]$_) | Out-Null }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
        Pop-Location
    }

    return [pscustomobject]@{
        exit_code = $exitCode
        output = ($output -join "`n")
    }
}

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-PathStrict $env:USERPROFILE ".codex\tools\memento-mcp"
}

$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$packagePath = Join-PathStrict $SourceRoot "package.json"
$readmePath = Join-PathStrict $SourceRoot "README.md"
$readmeEnPath = Join-PathStrict $SourceRoot "README.en.md"
$docsRoot = Join-PathStrict $SourceRoot "docs"
$libRoot = Join-PathStrict $SourceRoot "lib"
$testsRoot = Join-PathStrict $SourceRoot "tests"
$npm = Join-PathStrict (Join-PathStrict $env:USERPROFILE ".codex\toolchains\shims") "npm.cmd"

$checks = New-Object "System.Collections.Generic.List[object]"

if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "package.json not found: $packagePath"
}

$package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
$scripts = $package.scripts
$scriptNames = @($scripts.PSObject.Properties.Name)

$hasMigrationLint = $scriptNames -contains "lint:migrations"
$hasTestCi = $scriptNames -contains "test:ci"
$scriptStatus = if ($hasMigrationLint -and $hasTestCi) { "pass" } else { "fail" }
Add-Check $checks "package_scripts_present" $scriptStatus ("lint:migrations={0}; test:ci={1}" -f $hasMigrationLint, $hasTestCi)

$rbacPath = Join-PathStrict $libRoot "rbac.js"
$rbacTestPath = Join-PathStrict $testsRoot "unit\rbac-default-deny.test.js"
$rbacText = if (Test-Path -LiteralPath $rbacPath -PathType Leaf) { Get-Content -LiteralPath $rbacPath -Raw } else { "" }
$rbacTestText = if (Test-Path -LiteralPath $rbacTestPath -PathType Leaf) { Get-Content -LiteralPath $rbacTestPath -Raw } else { "" }
$rbacPass = (
    $rbacText -match "TOOL_PERMISSIONS" -and
    $rbacText -match "if \(!required\) return \{ allowed: false" -and
    $rbacTestText -match "unknown_tool" -and
    $rbacTestText -match "master"
)
$rbacStatus = if ($rbacPass) { "pass" } else { "fail" }
Add-Check $checks "rbac_default_deny_contract" $rbacStatus "lib/rbac.js default-deny plus tests/unit/rbac-default-deny.test.js"

$forbiddenTenantPatterns = @(
    "key_id\s+IS\s+NULL\s+OR\s+key_id",
    "::text\s+IS\s+NULL\s+OR.*key_id"
)
$tenantMatches = New-Object "System.Collections.Generic.List[string]"
if (Test-Path -LiteralPath $libRoot -PathType Container) {
    foreach ($file in Get-ChildItem -LiteralPath $libRoot -Recurse -File -Filter "*.js") {
        foreach ($pattern in $forbiddenTenantPatterns) {
            Select-String -LiteralPath $file.FullName -Pattern $pattern -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $tenantMatches.Add(("{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim())) | Out-Null
                }
        }
    }
}
$tenantTestPaths = @(
    (Join-PathStrict $testsRoot "unit\tenant-isolation.test.js"),
    (Join-PathStrict $testsRoot "unit\symbolic\claim-store-tenant.test.js")
)
$tenantTestsPresent = @($tenantTestPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -eq $tenantTestPaths.Count
$tenantStatus = if ($tenantMatches.Count -eq 0 -and $tenantTestsPresent) { "pass" } else { "fail" }
Add-Check $checks "tenant_isolation_forbidden_patterns" $tenantStatus ("forbidden_matches={0}; required_tests_present={1}" -f $tenantMatches.Count, $tenantTestsPresent)

$docFiles = @()
foreach ($path in @($readmePath, $readmeEnPath)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { $docFiles += Get-Item -LiteralPath $path }
}
if (Test-Path -LiteralPath $docsRoot -PathType Container) {
    $docFiles += Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter "*.md"
}
$staleDocMatches = New-Object "System.Collections.Generic.List[string]"
foreach ($file in $docFiles) {
    Select-String -LiteralPath $file.FullName -Pattern "test:ci.*test:e2e" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $staleDocMatches.Add(("{0}:{1}:{2}" -f $_.Path, $_.LineNumber, $_.Line.Trim())) | Out-Null
        }
}
$docStatus = if ($staleDocMatches.Count -eq 0) { "pass" } else { "fail" }
Add-Check $checks "readme_package_script_alignment" $docStatus ("stale_test_ci_doc_matches={0}" -f $staleDocMatches.Count)

if (Test-Path -LiteralPath $npm -PathType Leaf) {
    if ($hasMigrationLint) {
        $lintResult = Invoke-CheckedCommand -Command $npm -Arguments @("run", "lint:migrations") -WorkingDirectory $SourceRoot
        $lintStatus = if ($lintResult.exit_code -eq 0) { "pass" } else { "fail" }
        Add-Check $checks "migration_lint" $lintStatus ("exit={0}" -f $lintResult.exit_code)
    } else {
        Add-Check $checks "migration_lint" "fail" "package script lint:migrations is missing"
    }

    if ($SkipTestCi) {
        Add-Check $checks "test_ci" "not_run" "SkipTestCi was set"
    } elseif ($hasTestCi) {
        $testCiResult = Invoke-CheckedCommand -Command $npm -Arguments @("run", "test:ci") -WorkingDirectory $SourceRoot
        $testCiStatus = if ($testCiResult.exit_code -eq 0) { "pass" } else { "fail" }
        Add-Check $checks "test_ci" $testCiStatus ("exit={0}" -f $testCiResult.exit_code)
    } else {
        Add-Check $checks "test_ci" "fail" "package script test:ci is missing"
    }
} else {
    Add-Check $checks "npm_shim_available" "fail" "npm shim not found: $npm"
    Add-Check $checks "migration_lint" "not_run" "npm shim unavailable"
    Add-Check $checks "test_ci" "not_run" "npm shim unavailable"
}

$failures = @($checks | Where-Object { $_.status -eq "fail" })
$notRun = @($checks | Where-Object { $_.status -eq "not_run" })
$result = [pscustomobject]@{
    status = if ($failures.Count -eq 0) { "pass" } else { "fail" }
    source_root = $SourceRoot
    checked_at = (Get-Date).ToString("o")
    checks = $checks
    failure_count = $failures.Count
    not_run_count = $notRun.Count
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
} else {
    "status=$($result.status) failures=$($result.failure_count) not_run=$($result.not_run_count)"
    foreach ($check in $checks) {
        "- $($check.name): $($check.status) ($($check.evidence))"
    }
}

if ($failures.Count -gt 0) {
    exit 1
}
