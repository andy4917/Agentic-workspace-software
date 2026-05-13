param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$scanner = Join-Path $resolvedRoot "maintenance\scripts\check-staged-sensitive-diff.ps1"

if (-not (Test-Path -LiteralPath $scanner -PathType Leaf)) {
    Write-Output "status=fail; reason=staged-scanner-missing"
    exit 1
}

$previousIndex = [Environment]::GetEnvironmentVariable("GIT_INDEX_FILE", "Process")
$tempIndex = [System.IO.Path]::GetTempFileName()
$exitCode = 1
$nativeErrorPreference = $ErrorActionPreference

try {
    $ErrorActionPreference = "Continue"
    $indexPathOutput = @(& git -C $resolvedRoot rev-parse --git-path index 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Write-Output "status=fail; reason=git-index-path-failed"
        $indexPathOutput | Select-Object -First 5 | ForEach-Object { Write-Output ("detail=" + [string]$_) }
    } else {
        $indexPath = [string]$indexPathOutput[0]
        if (-not [System.IO.Path]::IsPathRooted($indexPath)) {
            $indexPath = Join-Path $resolvedRoot $indexPath
        }

        if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
            Copy-Item -LiteralPath $indexPath -Destination $tempIndex -Force -ErrorAction Stop
        }

        [Environment]::SetEnvironmentVariable("GIT_INDEX_FILE", $tempIndex, "Process")

        $gitAddOutput = @(& git -C $resolvedRoot add -A -- . 2>&1)
        if ($LASTEXITCODE -ne 0) {
            Write-Output "status=fail; reason=temp-index-git-add-failed"
            $gitAddOutput | Select-Object -First 5 | ForEach-Object { Write-Output ("detail=" + [string]$_) }
        } else {
            $scanOutput = @(& $scanner -Root $resolvedRoot 2>&1)
            $exitCode = $LASTEXITCODE
            $scanOutput | ForEach-Object { Write-Output ([string]$_) }
            Write-Output "detail=scope=worktree_via_temp_index"
        }
    }
} catch {
    Write-Output ("status=fail; reason=worktree-sensitive-scan-error; detail=" + $_.Exception.Message)
} finally {
    $ErrorActionPreference = $nativeErrorPreference
    [Environment]::SetEnvironmentVariable("GIT_INDEX_FILE", $previousIndex, "Process")
    if (Test-Path -LiteralPath $tempIndex -PathType Leaf) {
        Remove-Item -LiteralPath $tempIndex -Force
    }
}

exit $exitCode
