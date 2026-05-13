param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$failures = New-Object System.Collections.Generic.List[string]
$details = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message) | Out-Null
}

function Add-Detail {
    param([string]$Message)
    $script:details.Add($Message) | Out-Null
}

$memoryRoot = Join-Path $resolvedRoot "memories"
$rawMemoryPath = Join-Path $memoryRoot "raw_memories.md"

if (-not (Test-Path -LiteralPath $memoryRoot -PathType Container)) {
    Add-Failure "memories-directory-missing"
} else {
    Add-Detail "memory_root=present"
}

if (-not (Test-Path -LiteralPath $rawMemoryPath -PathType Leaf)) {
    Add-Failure "raw-memories-file-missing"
} else {
    $rawItem = Get-Item -LiteralPath $rawMemoryPath
    if ($rawItem.Length -le 0) {
        Add-Failure "raw-memories-file-empty"
    } else {
        Add-Detail ("raw_memories_bytes={0}" -f $rawItem.Length)
    }
}

if (Test-Path -LiteralPath (Join-Path $memoryRoot ".git") -PathType Container) {
    $null = & git -C $memoryRoot status --porcelain 2>$null
    if ($LASTEXITCODE -eq 0) {
        Add-Detail "memory_git_status=usable"
    } else {
        Add-Failure "memory-git-status-failed"
    }
} else {
    Add-Failure "memory-git-metadata-missing"
}

$pythonShim = Join-Path $resolvedRoot "toolchains\shims\python.cmd"
if (-not (Test-Path -LiteralPath $pythonShim -PathType Leaf)) {
    Add-Failure "python-shim-missing"
}

$memsearchCmd = Join-Path $resolvedRoot "toolchains\shims\memsearch.cmd"
$memsearchPs1 = Join-Path $resolvedRoot "toolchains\shims\memsearch.ps1"
if (-not (Test-Path -LiteralPath $memsearchCmd -PathType Leaf)) {
    Add-Failure "memsearch-cmd-shim-missing"
}
if (-not (Test-Path -LiteralPath $memsearchPs1 -PathType Leaf)) {
    Add-Failure "memsearch-ps1-shim-missing"
}

if ((Test-Path -LiteralPath $memsearchCmd -PathType Leaf) -and (Test-Path -LiteralPath $memsearchPs1 -PathType Leaf)) {
    $retrieveOutput = @(& $memsearchCmd --query "PM workspace memory RAG support-only evidence" --limit 5 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "memsearch-retrieve-failed"
        $retrieveOutput | Select-Object -First 3 | ForEach-Object { Add-Detail ("retrieve_detail=" + [string]$_) }
    } else {
        Add-Detail "memsearch_cli=active_dependency"
        Add-Detail "memsearch_source=toolchains/shims/memsearch.cmd"
        Add-Detail "memsearch_retrieve=pass"
    }

    $memorySearchOutput = @(& $memsearchCmd --memory --query "task workflow verification" --limit 3 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "memsearch-memory-search-failed"
        $memorySearchOutput | Select-Object -First 3 | ForEach-Object { Add-Detail ("memory_search_detail=" + [string]$_) }
    } else {
        Add-Detail "memsearch_memory_search=pass"
    }
}

$reportPath = Join-Path $resolvedRoot "reports\retrieval-report.latest.json"
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    Add-Failure "retrieval-report-missing"
} else {
    try {
        $report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
        $selected = @($report.selected_context)
        $forbiddenPrefixes = @("artifacts/", "cache/", "memories/", "reports/", "sessions/", "sqlite/", "trajectories/", "node_repl/")
        if ($selected.Count -eq 0) {
            Add-Failure "retrieval-selected-context-empty"
        }
        foreach ($item in $selected) {
            $path = [string]$item.path
            foreach ($prefix in $forbiddenPrefixes) {
                if ($path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Add-Failure ("retrieval-selected-forbidden-prefix:" + $path)
                }
            }
        }
        Add-Detail ("retrieval_selected_count={0}" -f $selected.Count)
    } catch {
        Add-Failure ("retrieval-report-parse-failed:" + $_.Exception.Message)
    }
}

if ($failures.Count -gt 0) {
    Write-Output "status=fail; failures=$($failures.Count)"
    $failures | ForEach-Object { Write-Output ("failure=" + $_) }
    $details | ForEach-Object { Write-Output ("detail=" + $_) }
    exit 1
}

Write-Output "status=pass; failures=0"
$details | ForEach-Object { Write-Output ("detail=" + $_) }
