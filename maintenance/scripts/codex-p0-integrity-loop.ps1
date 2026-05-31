param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [string]$RepoRoot = $(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")),
    [string]$ReportPath = "",
    [switch]$Json,
    [switch]$ReportOnly,
    [switch]$SkipScoop
)

$ErrorActionPreference = "Stop"

function Add-Check {
    param(
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Name,
        [string]$Status,
        [hashtable]$Details
    )

    $Checks.Add([ordered]@{
        name = $Name
        status = $Status
        details = $Details
    }) | Out-Null
}

function Invoke-ProcessCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $RepoRoot,
        [hashtable]$Environment = @{}
    )

    $startedUtc = (Get-Date).ToUniversalTime().ToString("o")
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $FilePath
    $process.StartInfo.WorkingDirectory = $WorkingDirectory
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        $process.StartInfo.ArgumentList.Add($argument)
    }
    foreach ($key in $Environment.Keys) {
        $process.StartInfo.Environment[$key] = [string]$Environment[$key]
    }
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $endedUtc = (Get-Date).ToUniversalTime().ToString("o")
    [ordered]@{
        file = $FilePath
        arguments = $Arguments
        command_line = (@($FilePath) + @($Arguments)) -join " "
        working_directory = $WorkingDirectory
        started_utc = $startedUtc
        ended_utc = $endedUtc
        exit_code = $process.ExitCode
        stdout = $stdout
        stderr = $stderr
    }
}

function ConvertFrom-JsonOutput {
    param([string]$Text)

    try {
        return ($Text | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Get-PowerShellPath {
    $candidates = @(
        (Join-Path $CodexHome "toolchains\shims\pwsh.cmd"),
        "powershell.exe"
    )
    foreach ($candidate in $candidates) {
        try {
            $command = Get-Command $candidate -ErrorAction Stop
            if ($command.Source) { return $command.Source }
            return $candidate
        } catch {
        }
    }
    return "powershell.exe"
}

function Get-MissingPid {
    $existing = @{}
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
        $existing[[int]$_.ProcessId] = $true
    }
    $candidate = 65000
    while ($existing.ContainsKey($candidate)) {
        $candidate += 1
    }
    return $candidate
}

function Get-Hash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-StringHash {
    param([string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
    } finally {
        $sha.Dispose()
    }
}

function Get-ObjectHash {
    param([object]$Value)
    Get-StringHash -Text (($Value | ConvertTo-Json -Depth 32 -Compress))
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-PolicyInput {
    param(
        [string]$Label,
        [string]$Path
    )

    [ordered]@{
        label = $Label
        path = $Path
        exists = [bool](Test-Path -LiteralPath $Path -PathType Leaf)
        sha256 = Get-Hash -Path $Path
    }
}

function Limit-Text {
    param(
        [AllowNull()][object]$Value,
        [int]$Limit = 240
    )

    $text = if ($null -eq $Value) { "" } else { [string]$Value }
    $text = $text.Trim()
    if ($text.Length -le $Limit) { return $text }
    return $text.Substring(0, $Limit) + "..."
}

function Format-MarkdownCell {
    param([AllowNull()][object]$Value)
    $text = Limit-Text -Value $Value -Limit 260
    if ([string]::IsNullOrWhiteSpace($text)) { return "none" }
    return (($text -replace "\|", "\|") -replace "`r?`n", "<br>")
}

function Test-LedgerEntry {
    param([AllowNull()][object]$Entry)

    if ($null -eq $Entry) { return $false }
    foreach ($name in @("generated_utc", "status", "codex_home", "repo_root")) {
        if ([string]::IsNullOrWhiteSpace([string]$Entry.$name)) { return $false }
    }
    return $true
}

function Repair-JsonlLedger {
    param(
        [string]$Path,
        [switch]$Repair
    )

    $summary = [ordered]@{
        exists = [bool](Test-Path -LiteralPath $Path -PathType Leaf)
        valid_count = 0
        invalid_count = 0
        archive_path = $null
    }
    if (-not $summary.exists) { return $summary }

    $validLines = New-Object System.Collections.Generic.List[string]
    $invalidLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $entry = ConvertFrom-JsonOutput -Text $line
        if (Test-LedgerEntry -Entry $entry) {
            $validLines.Add($line) | Out-Null
        } else {
            $invalidLines.Add($line) | Out-Null
        }
    }

    $summary.valid_count = $validLines.Count
    $summary.invalid_count = $invalidLines.Count
    if ($Repair -and $invalidLines.Count -gt 0) {
        $archivePath = "$Path.invalid.$((Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmss")).jsonl"
        Write-Utf8File -Path $archivePath -Content (($invalidLines -join "`n") + "`n")
        $summary.archive_path = $archivePath
        Write-Utf8File -Path $Path -Content $(if ($validLines.Count -gt 0) { ($validLines -join "`n") + "`n" } else { "" })
    }

    return $summary
}

function ConvertTo-StableManagedRootSignature {
    param([AllowNull()][object[]]$Roots)

    @($Roots | ForEach-Object {
        $root = [pscustomobject]$_
        [ordered]@{
            key = [string]$root.key
            parent_pid = $(if ($null -ne $root.parent_pid) { [int]$root.parent_pid } else { $null })
        }
    } | Sort-Object { $_.key })
}

$repoRootResolved = (Resolve-Path -LiteralPath $RepoRoot).Path
$codexHomeResolved = (Resolve-Path -LiteralPath $CodexHome).Path
$manifestDir = Join-Path $codexHomeResolved "maintenance\manifests"
$reportsDir = Join-Path $repoRootResolved "maintenance\reports"
$pwsh = Get-PowerShellPath
$checks = New-Object System.Collections.Generic.List[object]
$generatedUtc = (Get-Date).ToUniversalTime().ToString("o")

$cleanupScript = Join-Path $codexHomeResolved "maintenance\scripts\codex-runtime-process-cleanup.ps1"
$validateScript = Join-Path $codexHomeResolved "maintenance\scripts\validate-codex-scaffold.ps1"
$toolchainScript = Join-Path $codexHomeResolved "maintenance\scripts\check-toolchain-sources.ps1"
$shimRoot = Join-Path $codexHomeResolved "toolchains\shims"

$rootCauseGate = [ordered]@{
    observed_symptom = "Prior P0 reports and live manifests can be mistaken for current proof while runtime PID, watcher state, and validation output may have changed."
    source_trace = "Current validation emits fresh JSON but the existing scaffold-validation, validation-log, and clean-baseline manifests are not refreshed unless a separate manual step does it."
    strongest_supported_root_cause = "The P0 remediation existed as evidence packets and individual commands, not as one repeatable closure loop that rechecks original failure modes and refreshes manifests only from fresh evidence."
    exact_change_location = "maintenance/scripts/codex-p0-integrity-loop.ps1 plus generated manifests and report output."
    fix_goal = "Run one bounded command that gathers current diff, runtime, toolchain, doctor, Scoop, and original regression evidence, then writes fresh reviewable manifests and a report."
    minimal_change_scope = "Add an orchestrating script and generated evidence artifacts; do not alter passing cleanup or validator logic."
    original_failure_mode_to_verify = "stale manifests, missing watcher, orphan or duplicate managed roots, reserved PID loop regression, stale command route, false pass, and dead app-server cleanup safety."
    uncertainty = "Computer Use may inspect Windows screens and non-Codex apps for evidence when available. Codex Desktop app or Codex CLI input automation remains out of bounds under the Computer Use safety rules."
    stop_condition = "Any failed check leaves overall_status=fail and avoids writing a clean baseline manifest."
}

$policyDir = Join-Path $repoRootResolved "maintenance\policies"
$policyInputs = @(
    Get-PolicyInput -Label "Mandatory Root-Cause-First Modification" -Path (Join-Path $policyDir "root-cause-first-modification.md")
    Get-PolicyInput -Label "Sandcastle Integration Policy" -Path (Join-Path $policyDir "sandcastle-integration-policy.md")
    Get-PolicyInput -Label "Codex Self-Maintenance Control Plan" -Path (Join-Path $policyDir "codex-self-maintenance-control-plan.md")
    Get-PolicyInput -Label "Latest feature reflection points" -Path (Join-Path $policyDir "latest-feature-reflection-points.md")
)
$missingPolicyInputs = @($policyInputs | Where-Object { -not $_.exists })
Add-Check $checks "policy_inputs_present" ($(if ($missingPolicyInputs.Count -eq 0) { "pass" } else { "fail" })) @{
    command = "Test-Path/Get-FileHash maintenance\policies\*.md"
    cwd = $repoRootResolved
    timestamp_utc = $generatedUtc
    exit_code = $(if ($missingPolicyInputs.Count -eq 0) { 0 } else { 1 })
    evidence = "missing=$($missingPolicyInputs.Count); inputs=$($policyInputs.Count)"
    missing = @($missingPolicyInputs | ForEach-Object { $_.path })
    inputs = $policyInputs
}

$gitBranch = Invoke-ProcessCapture -FilePath "git.exe" -Arguments @("status", "--short", "--branch") -WorkingDirectory $repoRootResolved
$gitPorcelain = Invoke-ProcessCapture -FilePath "git.exe" -Arguments @("status", "--porcelain") -WorkingDirectory $repoRootResolved
$gitDiffCheck = Invoke-ProcessCapture -FilePath "git.exe" -Arguments @("diff", "--check") -WorkingDirectory $repoRootResolved
$gitDirtyPaths = @($gitPorcelain.stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$gitCommandsOk = $gitBranch.exit_code -eq 0 -and $gitPorcelain.exit_code -eq 0 -and $gitDiffCheck.exit_code -eq 0
$gitCleanEnough = [bool]$ReportOnly -or $gitDirtyPaths.Count -eq 0
Add-Check $checks "git_diff_closure" ($(if ($gitCommandsOk -and $gitCleanEnough) { "pass" } else { "fail" })) @{
    command = "git status --short --branch; git status --porcelain; git diff --check"
    cwd = $repoRootResolved
    timestamp_utc = $gitBranch.started_utc
    exit_code = $(if ($gitCommandsOk -and $gitCleanEnough) { 0 } else { 1 })
    evidence = "dirty_paths=$($gitDirtyPaths.Count); diff_check_exit_code=$($gitDiffCheck.exit_code)"
    branch = $gitBranch.stdout.Trim()
    dirty_paths = $gitDirtyPaths
    clean_required_for_baseline = -not [bool]$ReportOnly
    diff_check_exit_code = $gitDiffCheck.exit_code
    diff_check_output = ($gitDiffCheck.stdout + $gitDiffCheck.stderr).Trim()
}

$cleanupStatusRun = Invoke-ProcessCapture -FilePath $pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $cleanupScript, "-Mode", "status", "-CodexHome", $codexHomeResolved)
$cleanupStatus = ConvertFrom-JsonOutput -Text $cleanupStatusRun.stdout
$cleanupOk = $cleanupStatusRun.exit_code -eq 0 -and $null -ne $cleanupStatus
$managedOrphans = if ($cleanupOk -and $null -ne $cleanupStatus.managed_orphans) { @($cleanupStatus.managed_orphans) } else { @() }
$duplicateKeys = if ($cleanupOk -and $null -ne $cleanupStatus.duplicate_keys) { @($cleanupStatus.duplicate_keys) } else { @() }
$watchers = if ($cleanupOk -and $null -ne $cleanupStatus.watchers) { @($cleanupStatus.watchers) } else { @() }
Add-Check $checks "runtime_cleanup_status" ($(if ($cleanupOk -and $managedOrphans.Count -eq 0 -and $duplicateKeys.Count -eq 0 -and (($null -eq $cleanupStatus.app_server_pid) -or $watchers.Count -gt 0)) { "pass" } else { "fail" })) @{
    command = $cleanupStatusRun.command_line
    cwd = $cleanupStatusRun.working_directory
    timestamp_utc = $cleanupStatusRun.started_utc
    exit_code = $cleanupStatusRun.exit_code
    evidence = "app_server_pid=$($cleanupStatus.app_server_pid); watchers=$($watchers.Count); managed_orphans=$($managedOrphans.Count); duplicate_keys=$($duplicateKeys.Count)"
    app_server_pid = $(if ($cleanupOk) { $cleanupStatus.app_server_pid } else { $null })
    watcher_pids = @($watchers | ForEach-Object { $_.ProcessId })
    managed_orphan_count = $managedOrphans.Count
    duplicate_keys = @($duplicateKeys)
    stderr = $cleanupStatusRun.stderr.Trim()
}

$forbiddenPidLoop = @()
if (Test-Path -LiteralPath $cleanupScript -PathType Leaf) {
    $forbiddenPidLoop = @(Select-String -LiteralPath $cleanupScript -Pattern 'foreach\s*\(\s*\$pid\b' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Path):$($_.LineNumber)" })
}
Add-Check $checks "reserved_pid_loop_regression" ($(if ($forbiddenPidLoop.Count -eq 0) { "pass" } else { "fail" })) @{
    command = "Select-String -LiteralPath $cleanupScript -Pattern 'foreach\s*\(\s*\`$pid\b'"
    cwd = $repoRootResolved
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    exit_code = $(if ($forbiddenPidLoop.Count -eq 0) { 0 } else { 1 })
    evidence = "forbidden_hits=$($forbiddenPidLoop.Count)"
    forbidden_pattern = 'foreach ($pid ...)'
    hits = $forbiddenPidLoop
}

$deadPid = Get-MissingPid
$beforeCleanup = $cleanupStatus
$beforeRootPids = if ($null -ne $beforeCleanup -and $null -ne $beforeCleanup.managed_roots) { @($beforeCleanup.managed_roots | ForEach-Object { [int]$_.ProcessId } | Sort-Object) } else { @() }
if ($ReportOnly) {
    Add-Check $checks "dead_app_server_cleanup_regression" "pass" @{
        command = "not run: ReportOnly skips cleanup-all"
        cwd = $repoRootResolved
        timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
        exit_code = 0
        evidence = "mutation_skipped=true; before_app_server_pid=$($beforeCleanup.app_server_pid); before_root_pids=$($beforeRootPids -join ',')"
        report_only = $true
        mutation_skipped = $true
        reason = "ReportOnly is operationally read-only and does not call cleanup-all. Run full mode from a clean tree to execute this regression before refreshing clean baseline manifests."
        dead_app_server_pid = $deadPid
        before_app_server_pid = $(if ($null -ne $beforeCleanup) { $beforeCleanup.app_server_pid } else { $null })
        before_root_pids = $beforeRootPids
    }
} else {
    $deadCleanupRun = Invoke-ProcessCapture -FilePath $pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $cleanupScript, "-Mode", "cleanup-all", "-ParentPid", ([string]$deadPid), "-CodexHome", $codexHomeResolved)
    $afterStatusRun = Invoke-ProcessCapture -FilePath $pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $cleanupScript, "-Mode", "status", "-CodexHome", $codexHomeResolved)
    $afterCleanup = ConvertFrom-JsonOutput -Text $afterStatusRun.stdout
    $afterRootPids = if ($null -ne $afterCleanup -and $null -ne $afterCleanup.managed_roots) { @($afterCleanup.managed_roots | ForEach-Object { [int]$_.ProcessId } | Sort-Object) } else { @() }
    $deadCleanupSafe = (
        $deadCleanupRun.exit_code -eq 0 -and
        $afterStatusRun.exit_code -eq 0 -and
        ($null -eq $beforeCleanup -or $beforeCleanup.app_server_pid -eq $afterCleanup.app_server_pid) -and
        (($beforeRootPids -join ",") -eq ($afterRootPids -join ","))
    )
    Add-Check $checks "dead_app_server_cleanup_regression" ($(if ($deadCleanupSafe) { "pass" } else { "fail" })) @{
        command = "$($deadCleanupRun.command_line); $($afterStatusRun.command_line)"
        cwd = $deadCleanupRun.working_directory
        timestamp_utc = $deadCleanupRun.started_utc
        exit_code = $(if ($deadCleanupSafe) { 0 } else { 1 })
        evidence = "dead_pid=$deadPid; before_app_server_pid=$($beforeCleanup.app_server_pid); after_app_server_pid=$($afterCleanup.app_server_pid); before_roots=$($beforeRootPids -join ','); after_roots=$($afterRootPids -join ',')"
        report_only = $false
        dead_app_server_pid = $deadPid
        before_app_server_pid = $(if ($null -ne $beforeCleanup) { $beforeCleanup.app_server_pid } else { $null })
        after_app_server_pid = $(if ($null -ne $afterCleanup) { $afterCleanup.app_server_pid } else { $null })
        before_root_pids = $beforeRootPids
        after_root_pids = $afterRootPids
        cleanup_exit_code = $deadCleanupRun.exit_code
        status_exit_code = $afterStatusRun.exit_code
    }
}

$validationRun = Invoke-ProcessCapture -FilePath $pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $validateScript, "-CodexHome", $codexHomeResolved, "-Json")
$validation = ConvertFrom-JsonOutput -Text $validationRun.stdout
Add-Check $checks "scaffold_validation_current" ($(if ($validationRun.exit_code -eq 0 -and $null -ne $validation -and $validation.overall_status -eq "pass") { "pass" } else { "fail" })) @{
    command = $validationRun.command_line
    cwd = $validationRun.working_directory
    timestamp_utc = $validationRun.started_utc
    exit_code = $validationRun.exit_code
    evidence = "overall_status=$($validation.overall_status); fail_count=$($validation.fail_count); generated_utc=$($validation.generated_utc)"
    overall_status = $(if ($null -ne $validation) { $validation.overall_status } else { $null })
    fail_count = $(if ($null -ne $validation) { $validation.fail_count } else { $null })
    generated_utc = $(if ($null -ne $validation) { $validation.generated_utc } else { $null })
    stderr = $validationRun.stderr.Trim()
}

$toolchainRun = Invoke-ProcessCapture -FilePath $pwsh -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $toolchainScript, "-Json")
$toolchain = ConvertFrom-JsonOutput -Text $toolchainRun.stdout
Add-Check $checks "toolchain_sources_current" ($(if ($toolchainRun.exit_code -eq 0 -and $null -ne $toolchain -and $toolchain.status -eq "pass" -and [int]$toolchain.failures -eq 0 -and [int]$toolchain.warnings -eq 0) { "pass" } else { "fail" })) @{
    command = $toolchainRun.command_line
    cwd = $toolchainRun.working_directory
    timestamp_utc = $toolchainRun.started_utc
    exit_code = $toolchainRun.exit_code
    evidence = "status=$($toolchain.status); failures=$($toolchain.failures); warnings=$($toolchain.warnings)"
    status = $(if ($null -ne $toolchain) { $toolchain.status } else { $null })
    failures = $(if ($null -ne $toolchain) { $toolchain.failures } else { $null })
    warnings = $(if ($null -ne $toolchain) { $toolchain.warnings } else { $null })
    stderr = $toolchainRun.stderr.Trim()
}

$doctorEnv = @{ PATH = "$shimRoot;$env:PATH" }
$doctorRun = Invoke-ProcessCapture -FilePath "cmd.exe" -Arguments @("/c", (Join-Path $shimRoot "codex.cmd"), "doctor", "--json") -WorkingDirectory $repoRootResolved -Environment $doctorEnv
$doctor = ConvertFrom-JsonOutput -Text $doctorRun.stdout
Add-Check $checks "codex_doctor_current" ($(if ($doctorRun.exit_code -eq 0 -and $null -ne $doctor -and $doctor.overallStatus -eq "ok") { "pass" } else { "fail" })) @{
    command = $doctorRun.command_line
    cwd = $doctorRun.working_directory
    timestamp_utc = $doctorRun.started_utc
    exit_code = $doctorRun.exit_code
    evidence = "overallStatus=$($doctor.overallStatus); codexVersion=$($doctor.codexVersion)"
    overall_status = $(if ($null -ne $doctor) { $doctor.overallStatus } else { $null })
    codex_version = $(if ($null -ne $doctor) { $doctor.codexVersion } else { $null })
    stderr = $doctorRun.stderr.Trim()
}

if ($SkipScoop) {
    Add-Check $checks "scoop_health_current" "pass" @{
        command = "not run: SkipScoop"
        cwd = $repoRootResolved
        timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
        exit_code = 0
        evidence = "SkipScoop was set."
        skipped = $true
        reason = "SkipScoop was set."
    }
} else {
    $scoopStatusRun = Invoke-ProcessCapture -FilePath "cmd.exe" -Arguments @("/c", "scoop", "status") -WorkingDirectory $repoRootResolved
    $scoopCheckupRun = Invoke-ProcessCapture -FilePath "cmd.exe" -Arguments @("/c", "scoop", "checkup") -WorkingDirectory $repoRootResolved
    Add-Check $checks "scoop_health_current" ($(if ($scoopStatusRun.exit_code -eq 0 -and $scoopCheckupRun.exit_code -eq 0) { "pass" } else { "fail" })) @{
        command = "$($scoopStatusRun.command_line); $($scoopCheckupRun.command_line)"
        cwd = $repoRootResolved
        timestamp_utc = $scoopStatusRun.started_utc
        exit_code = $(if ($scoopStatusRun.exit_code -eq 0 -and $scoopCheckupRun.exit_code -eq 0) { 0 } else { 1 })
        evidence = "status_exit_code=$($scoopStatusRun.exit_code); checkup_exit_code=$($scoopCheckupRun.exit_code); status=$(Limit-Text -Value (($scoopStatusRun.stdout + $scoopStatusRun.stderr).Trim()) -Limit 80); checkup=$(Limit-Text -Value (($scoopCheckupRun.stdout + $scoopCheckupRun.stderr).Trim()) -Limit 80)"
        status_exit_code = $scoopStatusRun.exit_code
        status_output = ($scoopStatusRun.stdout + $scoopStatusRun.stderr).Trim()
        checkup_exit_code = $scoopCheckupRun.exit_code
        checkup_output = ($scoopCheckupRun.stdout + $scoopCheckupRun.stderr).Trim()
    }
}

$existingCleanManifestPath = Join-Path $manifestDir "clean-baseline-manifest.json"
$existingCleanManifest = $null
if (Test-Path -LiteralPath $existingCleanManifestPath -PathType Leaf) {
    $existingCleanManifest = ConvertFrom-JsonOutput -Text (Get-Content -LiteralPath $existingCleanManifestPath -Raw)
}
$repoLoopScriptPath = Join-Path $repoRootResolved "maintenance\scripts\codex-p0-integrity-loop.ps1"
$liveLoopScriptPath = Join-Path $codexHomeResolved "maintenance\scripts\codex-p0-integrity-loop.ps1"
$repoLoopScriptHash = Get-Hash -Path $repoLoopScriptPath
$liveLoopScriptHash = Get-Hash -Path $liveLoopScriptPath
$currentWatcherPids = @($watchers | ForEach-Object { [int]$_.ProcessId } | Sort-Object)
$currentWatcherCount = $currentWatcherPids.Count
$currentManagedRoots = if ($cleanupOk -and $null -ne $cleanupStatus.managed_roots) {
    @($cleanupStatus.managed_roots | Sort-Object Key | ForEach-Object {
        [ordered]@{ key = $_.Key; pid = [int]$_.ProcessId; parent_pid = [int]$_.ParentProcessId }
    })
} else {
    @()
}
$currentManagedRootSignature = ConvertTo-StableManagedRootSignature -Roots $currentManagedRoots
$currentRuntimeSignature = Get-ObjectHash -Value ([ordered]@{
    app_server_pid = $(if ($cleanupOk) { $cleanupStatus.app_server_pid } else { $null })
    watcher_count = $currentWatcherCount
    managed_root_signature = $currentManagedRootSignature
    managed_orphan_count = $managedOrphans.Count
    duplicate_keys = @($duplicateKeys)
})
$currentValidationSummary = [ordered]@{
    overall_status = $(if ($null -ne $validation) { $validation.overall_status } else { $null })
    fail_count = $(if ($null -ne $validation) { $validation.fail_count } else { $null })
    checks = $(if ($null -ne $validation -and $null -ne $validation.checks) {
        @($validation.checks | ForEach-Object { [ordered]@{ name = $_.name; status = $_.status } })
    } else {
        @()
    })
}
$currentValidationSummaryHash = Get-ObjectHash -Value $currentValidationSummary
$currentPolicyInputsHash = Get-ObjectHash -Value $policyInputs
$staleReasons = New-Object System.Collections.Generic.List[string]
if ($null -eq $existingCleanManifest) {
    $staleReasons.Add("missing_clean_baseline_manifest") | Out-Null
} else {
    $existingWatcherCount = if ($null -ne $existingCleanManifest.watcher_count) {
        [int]$existingCleanManifest.watcher_count
    } else {
        @($existingCleanManifest.watcher_pids).Count
    }
    $existingManagedRootSignature = if ($null -ne $existingCleanManifest.managed_root_signature) {
        ConvertTo-StableManagedRootSignature -Roots @($existingCleanManifest.managed_root_signature)
    } else {
        ConvertTo-StableManagedRootSignature -Roots @($existingCleanManifest.managed_roots)
    }
    if ([string]$existingCleanManifest.app_server_pid -ne [string]$(if ($cleanupOk) { $cleanupStatus.app_server_pid } else { $null })) { $staleReasons.Add("app_server_pid_changed") | Out-Null }
    if ($existingWatcherCount -ne $currentWatcherCount) { $staleReasons.Add("watcher_count_changed") | Out-Null }
    if ((Get-ObjectHash -Value $existingManagedRootSignature) -ne (Get-ObjectHash -Value $currentManagedRootSignature)) { $staleReasons.Add("managed_root_signature_changed") | Out-Null }
    if ([string]$existingCleanManifest.toolchain_status -ne [string]$toolchain.status -or [string]$existingCleanManifest.toolchain_failures -ne [string]$toolchain.failures -or [string]$existingCleanManifest.toolchain_warnings -ne [string]$toolchain.warnings) { $staleReasons.Add("toolchain_result_changed") | Out-Null }
    if ([string]$existingCleanManifest.codex_doctor_status -ne [string]$doctor.overallStatus -or [string]$existingCleanManifest.codex_version -ne [string]$doctor.codexVersion) { $staleReasons.Add("doctor_result_changed") | Out-Null }
    if ([string]$existingCleanManifest.loop_script_sha256 -ne [string]$repoLoopScriptHash) { $staleReasons.Add("managed_loop_script_hash_changed") | Out-Null }
    if ([string]$existingCleanManifest.live_loop_script_sha256 -ne [string]$liveLoopScriptHash) { $staleReasons.Add("live_loop_script_hash_changed") | Out-Null }
    if ([string]$existingCleanManifest.runtime_signature_sha256 -ne [string]$currentRuntimeSignature) { $staleReasons.Add("runtime_signature_changed") | Out-Null }
    if ([string]$existingCleanManifest.validation_summary_sha256 -ne [string]$currentValidationSummaryHash) { $staleReasons.Add("validation_summary_changed") | Out-Null }
    if ([string]$existingCleanManifest.policy_inputs_sha256 -ne [string]$currentPolicyInputsHash) { $staleReasons.Add("policy_inputs_changed") | Out-Null }
    if ($gitDirtyPaths.Count -gt 0) { $staleReasons.Add("git_dirty_paths_present") | Out-Null }
}
$staleBeforeRefresh = $staleReasons.Count -gt 0
Add-Check $checks "manifest_staleness_detected_before_refresh" "pass" @{
    command = "Compare clean-baseline-manifest.json against current runtime, script, validation, toolchain, doctor, policy, and git signatures"
    cwd = $repoRootResolved
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    exit_code = 0
    evidence = "stale_before_refresh=$staleBeforeRefresh; stale_reasons=$(@($staleReasons) -join ',')"
    stale_before_refresh = [bool]$staleBeforeRefresh
    stale_reasons = @($staleReasons)
    previous_app_server_pid = $(if ($null -ne $existingCleanManifest) { $existingCleanManifest.app_server_pid } else { $null })
    current_app_server_pid = $(if ($cleanupOk) { $cleanupStatus.app_server_pid } else { $null })
    note = "This is informational. The loop refreshes manifests only after all checks pass."
}

$loopLatestPath = Join-Path $manifestDir "p0-integrity-loop.latest.json"
$loopLedgerPath = Join-Path $manifestDir "p0-integrity-loop-log.jsonl"
$validationLatestPath = Join-Path $manifestDir "scaffold-validation.latest.json"
$validationLogJsonPath = Join-Path $manifestDir "validation-log.json"
$validationLogTextPath = Join-Path $manifestDir "validation-log.txt"
$ledgerProbe = Repair-JsonlLedger -Path $loopLedgerPath
Add-Check $checks "loop_ledger_integrity" ($(if ($ledgerProbe.invalid_count -eq 0 -or -not [bool]$ReportOnly) { "pass" } else { "fail" })) @{
    command = "Parse $loopLedgerPath and require generated_utc/status/codex_home/repo_root for each JSONL row"
    cwd = $repoRootResolved
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    exit_code = $(if ($ledgerProbe.invalid_count -eq 0 -or -not [bool]$ReportOnly) { 0 } else { 1 })
    evidence = "exists=$($ledgerProbe.exists); valid=$($ledgerProbe.valid_count); invalid=$($ledgerProbe.invalid_count); repair_allowed=$(-not [bool]$ReportOnly)"
    ledger = $ledgerProbe
}

$failedChecks = @($checks | Where-Object { $_.status -ne "pass" })
$overallStatus = if ($failedChecks.Count -eq 0) { "pass" } else { "fail" }

$loopResult = [ordered]@{
    generated_utc = $generatedUtc
    status = $overallStatus
    codex_home = $codexHomeResolved
    repo_root = $repoRootResolved
    root_cause_gate = $rootCauseGate
    policy_inputs = $policyInputs
    checks = $checks
    validation = $validation
    toolchain = $toolchain
    runtime_status = $cleanupStatus
    doctor = $doctor
    ledger_integrity = $ledgerProbe
    computer_use_boundary = [ordered]@{
        status = "environment_evidence_allowed"
        note = "Computer Use may inspect Windows screens and non-Codex apps for evidence when available. It must not automate Codex Desktop app or Codex CLI input."
    }
    sandcastle_boundary = [ordered]@{
        status = "not_used"
        note = "Sandcastle is reserved for isolated parallel repo work; this slice mutates active runtime manifests and is not a speculative sandbox task."
    }
}

if (-not $ReportOnly) {
    New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
    Write-Utf8File -Path $loopLatestPath -Content (($loopResult | ConvertTo-Json -Depth 32) + "`n")
    $ledgerRepair = Repair-JsonlLedger -Path $loopLedgerPath -Repair
    $ledgerEntry = [ordered]@{
        generated_utc = $generatedUtc
        status = $overallStatus
        codex_home = $codexHomeResolved
        repo_root = $repoRootResolved
        report_only = [bool]$ReportOnly
        git_dirty_count = $gitDirtyPaths.Count
        failed_checks = @($failedChecks | ForEach-Object { $_.name })
        repaired_invalid_entries = $ledgerRepair.invalid_count
        invalid_archive_path = $ledgerRepair.archive_path
    }
    ($ledgerEntry | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $loopLedgerPath -Encoding UTF8
}

if (-not $ReportOnly -and $overallStatus -eq "pass" -and $null -ne $validation) {
    Write-Utf8File -Path $validationLatestPath -Content (($validation | ConvertTo-Json -Depth 32) + "`n")
    Write-Utf8File -Path $validationLogJsonPath -Content (($validation | ConvertTo-Json -Depth 32) + "`n")
}

if (-not $ReportOnly -and $overallStatus -eq "pass") {
    $validationHash = Get-Hash -Path $validationLatestPath
    $cleanManifest = [ordered]@{
        generated_utc = $generatedUtc
        status = "pass"
        reason = "Fresh closed-loop P0 validation snapshot after current file, runtime, diff, doctor, toolchain, Scoop, stale-manifest, reserved-PID, watcher, orphan, duplicate-root, and dead-app-server regression checks."
        validation_log = $validationLatestPath
        validation_log_sha256 = $validationHash
        p0_integrity_loop_log = $loopLatestPath
        loop_script = $repoLoopScriptPath
        loop_script_sha256 = $repoLoopScriptHash
        live_loop_script = $liveLoopScriptPath
        live_loop_script_sha256 = $liveLoopScriptHash
        policy_inputs = $policyInputs
        policy_inputs_sha256 = $currentPolicyInputsHash
        runtime_signature_sha256 = $currentRuntimeSignature
        validation_summary_sha256 = $currentValidationSummaryHash
        toolchain_status = $toolchain.status
        toolchain_failures = $toolchain.failures
        toolchain_warnings = $toolchain.warnings
        codex_doctor_status = $doctor.overallStatus
        codex_version = $doctor.codexVersion
        app_server_pid = $cleanupStatus.app_server_pid
        managed_roots = $currentManagedRoots
        managed_root_signature = $currentManagedRootSignature
        managed_orphan_count = $managedOrphans.Count
        duplicate_keys = @($duplicateKeys)
        watcher_pids = $currentWatcherPids
        watcher_count = $currentWatcherCount
        git_branch = $gitBranch.stdout.Trim()
        git_dirty_paths = $gitDirtyPaths
        stale_before_refresh = [bool]$staleBeforeRefresh
        stale_reasons_before_refresh = @($staleReasons)
    }
    Write-Utf8File -Path $existingCleanManifestPath -Content (($cleanManifest | ConvertTo-Json -Depth 16) + "`n")

    $validationText = @(
        "Closed-loop P0 integrity validation log",
        "Generated UTC: $generatedUtc",
        "Validation: $($validation.overall_status), fail_count=$($validation.fail_count)",
        "Toolchain: $($toolchain.status), failures=$($toolchain.failures), warnings=$($toolchain.warnings)",
        "Runtime app_server_pid=$($cleanupStatus.app_server_pid), managed_orphans=$($managedOrphans.Count), duplicate_keys=$($duplicateKeys.Count), watcher_pids=$(@($watchers | ForEach-Object { $_.ProcessId }) -join ',')",
        "Codex doctor: $($doctor.overallStatus), version=$($doctor.codexVersion)",
        "Git: $($gitBranch.stdout.Trim())",
        "Stale manifest before refresh: $staleBeforeRefresh",
        "Clean manifest: pass"
    ) -join "`n"
    Write-Utf8File -Path $validationLogTextPath -Content ($validationText + "`n")
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $reportsDir "2026-05-31-codex-p0-integrity-loop.md"
}

$watcherPidText = if ($currentWatcherPids.Count -gt 0) { $currentWatcherPids -join ", " } else { "none" }
$duplicateKeyText = if ($duplicateKeys.Count -gt 0) { @($duplicateKeys) -join ", " } else { "none" }
$staleReasonText = if ($staleReasons.Count -gt 0) { @($staleReasons) -join ", " } else { "none" }
$checkEvidenceRows = @($checks | ForEach-Object {
    $detail = $_.details
    "| $(Format-MarkdownCell $_.name) | $(Format-MarkdownCell $detail["command"]) | $(Format-MarkdownCell $detail["cwd"]) | $(Format-MarkdownCell $detail["timestamp_utc"]) | $(Format-MarkdownCell $detail["exit_code"]) | $(Format-MarkdownCell $_.status) | $(Format-MarkdownCell $detail["evidence"]) |"
}) -join "`n"

$report = @"
# Codex P0 Integrity Closed Loop

Generated UTC: $generatedUtc

## Root-Cause Gate

- Observed symptom: $($rootCauseGate.observed_symptom)
- Source trace: $($rootCauseGate.source_trace)
- Strongest supported root cause: $($rootCauseGate.strongest_supported_root_cause)
- Exact change location: $($rootCauseGate.exact_change_location)
- Fix goal: $($rootCauseGate.fix_goal)
- Minimal change scope: $($rootCauseGate.minimal_change_scope)
- Original failure mode to verify: $($rootCauseGate.original_failure_mode_to_verify)
- Uncertainty: $($rootCauseGate.uncertainty)
- Stop condition: $($rootCauseGate.stop_condition)

## Policy Inputs

| Document | Managed Path | SHA256 | Present |
|---|---|---|---|
$(@($policyInputs | ForEach-Object { "| $($_.label) | $($_.path) | $($_.sha256) | $($_.exists) |" }) -join "`n")

## Evidence Ledger

| Check | Status |
|---|---|
$(@($checks | ForEach-Object { "| $($_.name) | $($_.status) |" }) -join "`n")

## Checks Run Detail

| Check | Command | CWD | Timestamp UTC | Exit code | Result | Evidence |
|---|---|---|---|---|---|---|
$checkEvidenceRows

## Current Runtime

- App-server PID: $($cleanupStatus.app_server_pid)
- Watcher PIDs: $watcherPidText
- Managed orphan count: $($managedOrphans.Count)
- Duplicate keys: $duplicateKeyText

## Closure

- Overall status: $overallStatus
- Manifest stale before refresh: $staleBeforeRefresh
- Stale reasons before refresh: $staleReasonText
- Report-only mode: $([bool]$ReportOnly)
- Clean tree required for baseline: $(-not [bool]$ReportOnly)
- Computer Use boundary: Windows screen and non-Codex app evidence is allowed when the tool is available; Codex Desktop app or Codex CLI input automation is not.
- Sandcastle boundary: not used for this active-runtime slice.

## Artifacts

- Loop latest manifest: $loopLatestPath
- Loop ledger: $loopLedgerPath
- Scaffold validation manifest: $validationLatestPath
- Clean baseline manifest: $existingCleanManifestPath

## Not Run

- Physical Codex Desktop close-button click was not automated because the Computer Use policy does not allow automating Codex Desktop app or Codex CLI input. Close lifecycle evidence must use user-performed close actions plus post-close process evidence, or non-Codex Windows tools such as Task Manager when Computer Use is available.
- ReportOnly cleanup-all regression skip: $([bool]$ReportOnly)
"@

if (-not $ReportOnly) {
    Write-Utf8File -Path $ReportPath -Content ($report + "`n")
}

if ($Json) {
    $loopResult | ConvertTo-Json -Depth 32
} else {
    "overall_status: $overallStatus"
    "report: $ReportPath"
    foreach ($check in $checks) {
        "{0}: {1}" -f $check.name, $check.status
    }
}

if ($overallStatus -ne "pass") {
    exit 1
}
