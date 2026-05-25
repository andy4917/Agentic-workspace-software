param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path

function Get-LineDigest {
    param([string]$Value)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
}

$diff = @(& git -C $resolvedRoot diff --cached --unified=0 --no-color -- . 2>&1)
if ($LASTEXITCODE -ne 0) {
    Write-Output "status=fail; reason=git-diff-cached-failed"
    $diff | Select-Object -First 5 | ForEach-Object { Write-Output ("detail=" + [string]$_) }
    exit 1
}

$patterns = @(
    @{
        name = "credential_assignment"
        regex = "(?i)\b(api[_-]?key|credential|password|secret|token)\b\s*[:=]\s*['""]?[A-Za-z0-9_./+=:-]{8,}"
    },
    @{
        name = "private_key_header"
        regex = "(?i)BEGIN [A-Z0-9 ]{0,32}PRIVATE KEY"
    },
    @{
        name = "env_sensitive_assignment"
        regex = "\b[A-Z0-9_]*(API_KEY|CREDENTIAL|PASSWORD|SECRET|TOKEN)[A-Z0-9_]*\s*="
        case_sensitive = $true
    }
)

$currentFile = ""
$addedLines = 0
$findings = New-Object System.Collections.Generic.List[object]

foreach ($line in $diff) {
    $text = [string]$line
    if ($text -match "^diff --git a/(.+?) b/(.+)$") {
        $currentFile = $matches[2]
        continue
    }
    if ($text -match "^\+\+\+ b/(.+)$") {
        $currentFile = $matches[1]
        continue
    }
    if (-not $text.StartsWith("+") -or $text.StartsWith("+++")) {
        continue
    }

    $addedLines += 1
    $content = $text.Substring(1)
    foreach ($pattern in $patterns) {
        $isMatch = if ($pattern.case_sensitive -eq $true) {
            $content -cmatch [string]$pattern.regex
        } else {
            $content -match [string]$pattern.regex
        }
        if ($isMatch) {
            $findings.Add([pscustomobject]@{
                file = $currentFile
                category = [string]$pattern.name
                line_sha256 = Get-LineDigest -Value $content
            }) | Out-Null
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Output "status=fail; findings=$($findings.Count); scanned_added_lines=$addedLines"
    $findings |
        Sort-Object file, category, line_sha256 -Unique |
        ForEach-Object {
            Write-Output ("finding file={0}; category={1}; line_sha256={2}" -f $_.file, $_.category, $_.line_sha256)
        }
    exit 1
}

Write-Output "status=pass; findings=0; scanned_added_lines=$addedLines"
