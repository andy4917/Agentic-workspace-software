param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$pythonShim = Join-Path $root "toolchains\shims\python.cmd"
$harness = Join-Path $root "maintenance\scripts\codex_agent_harness.py"

function Get-ArgumentValue {
    param(
        [string[]]$Items,
        [string]$Name,
        [string]$Default = ""
    )

    for ($index = 0; $index -lt $Items.Count; $index += 1) {
        if ($Items[$index] -eq $Name -and ($index + 1) -lt $Items.Count) {
            return $Items[$index + 1]
        }
    }
    return $Default
}

function Get-LineDigest {
    param([string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
}

function Redact-Preview {
    param([string]$Value)

    $redacted = $Value
    $redacted = $redacted -replace "sk-[A-Za-z0-9_-]{20,}", "<redacted>"
    $redacted = $redacted -replace "ghp_[A-Za-z0-9_]{20,}", "<redacted>"
    $redacted = $redacted -replace "github_pat_[A-Za-z0-9_]{20,}", "<redacted>"
    $redacted = $redacted -replace "(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*['""][^'""]{8,}['""]", '$1=<redacted>'
    if ($redacted.Length -gt 180) {
        return $redacted.Substring(0, 180)
    }
    return $redacted
}

if (-not (Test-Path -LiteralPath $pythonShim -PathType Leaf)) {
    Write-Error "python shim missing: $pythonShim"
    exit 1
}

if (-not (Test-Path -LiteralPath $harness -PathType Leaf)) {
    Write-Error "codex harness missing: $harness"
    exit 1
}

if ($Args.Count -eq 0 -or $Args -contains "--help" -or $Args -contains "-h") {
    Write-Output "Usage: memsearch [--memory] --query <text> [--limit <n>]"
    Write-Output "Default source: managed Codex shim over codex_agent_harness.py retrieve"
    Write-Output "Memory source: memories/raw_memories.md with redacted previews"
    exit 0
}

if ($Args -contains "--memory" -or $Args -contains "--memories") {
    $query = Get-ArgumentValue -Items $Args -Name "--query"
    if ([string]::IsNullOrWhiteSpace($query)) {
        Write-Error "missing required argument: --query"
        exit 1
    }

    $limitText = Get-ArgumentValue -Items $Args -Name "--limit" -Default "5"
    $limit = 5
    if (-not [int]::TryParse($limitText, [ref]$limit) -or $limit -lt 1) {
        $limit = 5
    }

    $memoryPath = Join-Path $root "memories\raw_memories.md"
    if (-not (Test-Path -LiteralPath $memoryPath -PathType Leaf)) {
        Write-Error "memory file missing: $memoryPath"
        exit 1
    }

    $terms = [System.Text.RegularExpressions.Regex]::Matches($query.ToLowerInvariant(), "[\w.-]+") |
        ForEach-Object { $_.Value } |
        Where-Object { $_.Length -gt 1 } |
        Select-Object -Unique
    if (@($terms).Count -eq 0) {
        Write-Error "query has no searchable terms"
        exit 1
    }

    $lines = Get-Content -LiteralPath $memoryPath
    $heading = ""
    $results = New-Object System.Collections.Generic.List[object]
    for ($index = 0; $index -lt $lines.Count; $index += 1) {
        $line = [string]$lines[$index]
        if ($line -match "^#{1,6}\s+(.+)$") {
            $heading = $matches[1]
        }

        $lower = $line.ToLowerInvariant()
        $score = 0
        $reasons = New-Object System.Collections.Generic.List[string]
        foreach ($term in $terms) {
            $count = ([regex]::Matches($lower, [regex]::Escape($term))).Count
            if ($count -gt 0) {
                $score += [Math]::Min($count, 5)
                $reasons.Add(("content:{0}x{1}" -f $term, $count)) | Out-Null
            }
        }
        if ($score -gt 0) {
            $results.Add([pscustomobject]@{
                path = "memories/raw_memories.md"
                line = $index + 1
                heading = $heading
                score = $score
                relevance_reasons = @($reasons)
                line_sha256 = Get-LineDigest -Value $line
                preview = Redact-Preview -Value $line
            }) | Out-Null
        }
    }

    $selected = @($results | Sort-Object @{Expression = "score"; Descending = $true}, line | Select-Object -First $limit)
    $report = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        query = $query
        mode = "memory"
        status = $(if ($selected.Count -gt 0) { "pass" } else { "fail" })
        selected_context = $selected
    }

    $reportJson = Join-Path $root "reports\memsearch-memory.latest.json"
    $reportMd = Join-Path $root "reports\memsearch-memory.latest.md"
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportJson) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportJson -Encoding UTF8
    $markdown = New-Object System.Collections.Generic.List[string]
    $markdown.Add("# MemSearch Memory Report") | Out-Null
    $markdown.Add("") | Out-Null
    $markdown.Add(("- query: {0}" -f $query)) | Out-Null
    $markdown.Add(("- status: {0}" -f $report.status)) | Out-Null
    $markdown.Add("") | Out-Null
    $markdown.Add("## Selected Context") | Out-Null
    foreach ($item in $selected) {
        $markdown.Add(("- {0}:{1} score={2} heading={3} sha256={4}" -f $item.path, $item.line, $item.score, $item.heading, $item.line_sha256)) | Out-Null
    }
    if ($selected.Count -eq 0) {
        $markdown.Add("- None") | Out-Null
    }
    $markdown | Set-Content -LiteralPath $reportMd -Encoding UTF8

    Write-Output $reportMd
    exit $(if ($selected.Count -gt 0) { 0 } else { 1 })
}

& $pythonShim $harness retrieve @Args
exit $LASTEXITCODE
