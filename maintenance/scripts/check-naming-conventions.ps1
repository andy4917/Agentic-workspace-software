param(
    [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
    [string]$AgentsHome = (Join-Path $env:USERPROFILE ".agents"),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-ExistingRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $null
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Test-IsSkippedDirectory {
    param([System.IO.DirectoryInfo]$Directory)

    $skipNames = @(".git", "node_modules", "__pycache__")
    if ($skipNames -contains $Directory.Name) {
        return $true
    }

    $full = $Directory.FullName
    $skipFragments = @(
        "\state\memento-mcp\pgdata",
        "\sessions",
        "\logs",
        "\reports",
        "\artifacts\tool-results",
        "\cache\codex_apps_tools"
    )
    foreach ($fragment in $skipFragments) {
        if ($full.IndexOf($fragment, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Get-RelativePath {
    param(
        [string]$Root,
        [string]$Path
    )
    $rootWithSlash = $Root.TrimEnd("\") + "\"
    if ($Path.StartsWith($rootWithSlash, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($rootWithSlash.Length)
    }
    return $Path
}

function Find-SameNameChildren {
    param([string]$Root)

    $findings = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
    $stack.Push([System.IO.DirectoryInfo]::new($Root))

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        if (Test-IsSkippedDirectory -Directory $current) {
            continue
        }

        $children = @()
        try {
            $children = Get-ChildItem -LiteralPath $current.FullName -Directory -Force -ErrorAction Stop
        } catch {
            $findings.Add([pscustomobject]@{
                type = "scan_error"
                root = $Root
                path = (Get-RelativePath -Root $Root -Path $current.FullName)
                message = $_.Exception.Message
            }) | Out-Null
            continue
        }

        foreach ($child in $children) {
            if ($child.Name.Equals($current.Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                $findings.Add([pscustomobject]@{
                    type = "same_name_child"
                    root = $Root
                    path = (Get-RelativePath -Root $Root -Path $child.FullName)
                    parent = (Get-RelativePath -Root $Root -Path $current.FullName)
                    name = $child.Name
                }) | Out-Null
            }
            if (-not (Test-IsSkippedDirectory -Directory $child)) {
                $stack.Push($child)
            }
        }
    }
    return $findings.ToArray()
}

function Test-ForbiddenPath {
    param(
        [string]$Root,
        [string[]]$RelativePaths
    )

    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($relative in $RelativePaths) {
        $path = Join-Path $Root $relative
        if (Test-Path -LiteralPath $path) {
            $findings.Add([pscustomobject]@{
                type = "forbidden_active_path"
                root = $Root
                path = $relative
            }) | Out-Null
        }
    }
    return $findings.ToArray()
}

function Find-CrossRootSkillDuplicates {
    param(
        [string]$CodexRoot,
        [string]$AgentsRoot
    )

    if ([string]::IsNullOrWhiteSpace($CodexRoot) -or [string]::IsNullOrWhiteSpace($AgentsRoot)) {
        return @()
    }

    $codexSkills = Join-Path $CodexRoot "skills"
    $agentsSkills = Join-Path $AgentsRoot "skills"
    if (-not (Test-Path -LiteralPath $codexSkills -PathType Container) -or -not (Test-Path -LiteralPath $agentsSkills -PathType Container)) {
        return @()
    }

    $codexNames = @{}
    foreach ($item in Get-ChildItem -LiteralPath $codexSkills -Directory -Force) {
        if ($item.Name.StartsWith("_") -or $item.Name.StartsWith(".")) {
            continue
        }
        $codexNames[$item.Name.ToLowerInvariant()] = $item.FullName
    }

    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($item in Get-ChildItem -LiteralPath $agentsSkills -Directory -Force) {
        $key = $item.Name.ToLowerInvariant()
        if ($codexNames.ContainsKey($key)) {
            $findings.Add([pscustomobject]@{
                type = "cross_root_skill_duplicate"
                name = $item.Name
                primary_candidate = (Join-Path $AgentsRoot ("skills\" + $item.Name))
                duplicate_candidate = $codexNames[$key]
            }) | Out-Null
        }
    }
    return $findings.ToArray()
}

$resolvedCodex = Resolve-ExistingRoot -Path $CodexHome
$resolvedAgents = Resolve-ExistingRoot -Path $AgentsHome
$roots = @($resolvedCodex, $resolvedAgents) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$findings = New-Object System.Collections.Generic.List[object]
foreach ($root in $roots) {
    foreach ($finding in Find-SameNameChildren -Root $root) {
        $findings.Add($finding) | Out-Null
    }
}

if ($resolvedCodex) {
    foreach ($finding in Test-ForbiddenPath -Root $resolvedCodex -RelativePaths @(
        "plugins\plugins",
        "skills\skills",
        "agents\agents",
        "vendor_imports",
        "plugins\local-marketplaces",
        "plugins\cache\openai-primary-runtime"
    )) {
        $findings.Add($finding) | Out-Null
    }
}

if ($resolvedAgents) {
    foreach ($finding in Test-ForbiddenPath -Root $resolvedAgents -RelativePaths @(
        "skills\skills",
        "agents\agents",
        "upstream\upstream"
    )) {
        $findings.Add($finding) | Out-Null
    }
}

foreach ($finding in Find-CrossRootSkillDuplicates -CodexRoot $resolvedCodex -AgentsRoot $resolvedAgents) {
    $findings.Add($finding) | Out-Null
}

$blocking = @($findings | Where-Object { $_.type -ne "scan_error" })
$status = if ($blocking.Count -eq 0) { "pass" } else { "fail" }
$allFindings = @($findings.ToArray())
$result = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    status = $status
    roots = $roots
    finding_count = $allFindings.Count
    blocking_count = $blocking.Count
    findings = $allFindings
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
} else {
    "status=$status"
    "finding_count=$($result.finding_count)"
    "blocking_count=$($result.blocking_count)"
    foreach ($finding in $findings) {
        "detail=$($finding.type):$($finding.path)$($finding.name)"
    }
}

if ($status -eq "pass") {
    exit 0
}
exit 1
