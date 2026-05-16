# Guardrail predicates and repair helpers for lightweight-codex-hook.ps1.
function Deny-PreTool {
    param([string]$Reason)
    Write-HookJson @{
        hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            permissionDecision = "deny"
            permissionDecisionReason = $Reason
        }
    }
}

function Deny-Permission {
    param([string]$Reason)
    Write-HookJson @{
        hookSpecificOutput = @{
            hookEventName = "PermissionRequest"
            decision = @{
                behavior = "deny"
                message = $Reason
            }
        }
    }
}

function Test-StagedDiffSensitiveValidation {
    param([string]$Text)

    if ($Text -notmatch "(?i)\bgit\b" -or
        $Text -notmatch "(?i)\bdiff\b" -or
        $Text -notmatch "(?i)(--cached|--staged)") {
        return $false
    }

    $directReadVerb = "(?i)(?:^|[;&|]\s*|\s)(Get-Content|gc|type|cat|more)(?:\.exe)?(?=\s|$)"
    if ($Text -match $directReadVerb -or $Text -match "(?i)\bSelect-String\b.*\s-(LiteralPath|Path)\b") {
        return $false
    }

    if ($Text -notmatch "(?i)(Select-String|grep|rg|findstr|check-staged-sensitive-diff|password|secret|token|credential|api[_-]?key|api\[_-\]\?key|private key)") {
        return $false
    }

    $directSensitiveFile = "(?i)(auth\.json|\.env(\.|$|\s)|id_rsa|id_ed25519|\.pem\b)"
    if ($Text -match $directSensitiveFile) {
        return $false
    }

    return $true
}

function Test-SecretContentAccess {
    param([string]$Text)

    if (Test-StagedDiffSensitiveValidation -Text $Text) {
        return $false
    }

    $readVerb = "(?i)(?:^|[;&|]\s*|\s)(Get-Content|gc|type|cat|Select-String|more)(?:\.exe)?(?=\s|$)"
    $sensitivePath = "(?i)(auth\.json|\.env(\.|$)|id_rsa|id_ed25519|\.pem\b|(^|[\\/._-])(token|secret|credential|password|api[_-]?key|cookie)([\\/._-]|$))"
    return ($Text -match $readVerb -and $Text -match $sensitivePath)
}

function Test-DestructiveAction {
    param([string]$Text)

    if (Test-RecycleBinCleanup -Text $Text) {
        return $false
    }
    if (Test-DocumentationOnlyDestructiveRecord -Text $Text) {
        return $false
    }
    if (Test-ScopedGeneratedCacheCleanup -Text $Text) {
        return $false
    }
    if (Test-ScopedTemporaryRootCleanup -Text $Text) {
        return $false
    }

    $patterns = @(
        "(?i)\bgit\s+reset\s+--hard\b",
        "(?i)\bgit\s+clean\s+-[^\s]*f[^\s]*d",
        "(?i)\bgit\s+push\b.*--force",
        "(?i)\bRemove-Item\b.*\s-(Recurse|r)\b.*\s-(Force|f)\b",
        "(?i)\brmdir\b.*\s/s\b",
        "(?i)\bdel\b.*\s/s\b",
        "(?i)\bformat\b\s+[A-Z]:"
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }
    return $false
}

function Test-RecycleBinCleanup {
    param([string]$Text)

    if ($Text -match "(?i)SendToRecycleBin" -and
        $Text -match "(?i)Microsoft\.VisualBasic\.FileIO" -and
        $Text -match "(?i)(DeleteFile|DeleteDirectory)") {
        return $true
    }
    return $false
}

function Test-DocumentationOnlyDestructiveRecord {
    param([string]$Text)

    $normalized = $Text -replace "\\r\\n|\\n|\\r", "`n"

    if ($normalized -notmatch "(?i)\*\*\* Begin Patch") {
        return $false
    }

    $pathMatches = [regex]::Matches($normalized, "(?im)^\*\*\* (?:Add|Update) File: (.+)$")
    if ($pathMatches.Count -eq 0) {
        return $false
    }
    foreach ($match in $pathMatches) {
        $path = [string]$match.Groups[1].Value
        if ($path -notmatch "(?i)\.md$") {
            return $false
        }
    }

    return ($normalized -match "(?i)(blocked by the safety hook|blocked cleanup|not run:|fingerprint|incident)")
}
function Test-ScopedGeneratedCacheCleanup {
    param([string]$Text)

    if ($Text -notmatch "(?i)\bRemove-Item\b" -or
        $Text -notmatch "(?i)\s-(Recurse|r)\b" -or
        $Text -notmatch "(?i)\s-(Force|f)\b") {
        return $false
    }

    $codexRootPattern = [regex]::Escape((Get-CodexHomePath).TrimEnd("\"))
    $allowedRootPattern = "(?i)$codexRootPattern\\(tools|maintenance\\scripts)\\__pycache__(['`"\s;]|$)"
    if ($Text -notmatch $allowedRootPattern) {
        return $false
    }

    $guardSignals = @(
        "Resolve-Path",
        "StartsWith",
        "Refusing to remove outside CODEX_HOME"
    )
    foreach ($signal in $guardSignals) {
        if ($Text -notmatch $signal) {
            return $false
        }
    }

    return $true
}

function Test-ScopedTemporaryRootCleanup {
    param([string]$Text)

    if ($Text -notmatch "(?i)\bRemove-Item\b" -or
        $Text -notmatch "(?i)\s-(Recurse|r)\b" -or
        $Text -notmatch "(?i)\s-(Force|f)\b") {
        return $false
    }

    $codexRootPattern = [regex]::Escape((Get-CodexHomePath).TrimEnd("\"))
    $allowedRootPattern = "(?i)$codexRootPattern\\(\.tmp|tmp|vendor_imports)(['`"\s;]|$)"
    if ($Text -notmatch $allowedRootPattern) {
        return $false
    }

    $guardSignals = @(
        "Resolve-Path",
        "Split-Path\s+-Parent",
        "Refusing unexpected target",
        "Resolved path mismatch"
    )
    foreach ($signal in $guardSignals) {
        if ($Text -notmatch $signal) {
            return $false
        }
    }

    return $true
}

function Test-HookWeakening {
    param([string]$Text)

    $patterns = @(
        "(?i)hooks\s*=\s*false",
        "(?i)codex_hooks\s*=\s*false",
        "(?i)multi_agent\s*=\s*false",
        "(?i)(Remove-Item|rm|del)\b.*(\.codex[\\/]+hooks|hooks\.json|lightweight-codex-hook\.ps1)",
        '(?i)permissionDecision\s*=\s*[''"]allow[''"]',
        '(?i)decision\s*=\s*[''"]approve[''"]'
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }
    return $false
}

function Test-BlockedAppConnectorTool {
    param(
        $InputObject,
        $Policy
    )

    $toolName = [string]$InputObject.tool_name
    if ([string]::IsNullOrWhiteSpace($toolName)) {
        return $false
    }

    $patterns = @(
        "^mcp__codex_apps__supabase($|[._])",
        "^mcp__codex_apps__hugging_face($|[._])"
    )

    if ($null -ne $Policy.toolchain_integrity -and $null -ne $Policy.toolchain_integrity.blocked_app_connector_tool_patterns) {
        $patterns = @($Policy.toolchain_integrity.blocked_app_connector_tool_patterns)
    }

    foreach ($pattern in $patterns) {
        if ($toolName -match $pattern) {
            return $true
        }
    }

    return $false
}

function Test-PolicyOrFixtureEdit {
    param([string]$Text)

    return ($Text -match "(?i)(CODEX_WORKFLOW|FULL_TREE_SCAN|lightweight-codex-policy\.json|\.md\b|fixtures?[\\/]|negative[\\/]|tests?[\\/]|__tests__|spec[\\/])")
}

function Test-FakeSuccessInsertion {
    param([string]$Text)

    $editSignal = $Text -match "(?s)(\*\*\* (Add|Update) File:|new_str|old_str|content|Set-Content|Add-Content|Out-File)"
    if (-not $editSignal) {
        return $false
    }

    if (Test-PolicyOrFixtureEdit -Text $Text) {
        return $false
    }

    $patterns = @(
        "(?i)(\\n|`r?`n|\A)\+?\s*(exit\s+0|sys\.exit\(0\)|process\.exit\(0\))\b",
        "(?im)^\+\s*(exit\s+0|sys\.exit\(0\)|process\.exit\(0\))\b",
        "(?i)(hardcoded\s+pass|fake\s+success|force\s+pass|always\s+pass|skip\s+validation|suppress\s+warnings?)",
        "(?i)(\\n|`r?`n|\A)\+?\s*(return\s+true|return\s+0)\s*(#|//)?\s*(pass|success|valid|ok)",
        "(?im)^\+\s*(return\s+true|return\s+0)\s*(#|//)?\s*(pass|success|valid|ok)",
        "(?is)catch\s*\{[^}]*?(return\s+true|return\s+0|exit\s+0|process\.exit\(0\))"
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            return $true
        }
    }
    return $false
}

function Get-ChangedFileCount {
    param([string]$Text)

    $matches = [regex]::Matches($Text, "\*\*\* (Add|Update|Delete) File:")
    if ($matches.Count -gt 0) {
        return $matches.Count
    }
    return 0
}

function Get-ChangedLineCount {
    param([string]$Text)

    $count = 0
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match "^[+-]" -and $line -notmatch "^(\+\+\+|---|\*\*\*)") {
            $count += 1
        }
    }
    return $count
}

function Invoke-ChromeExtensionOriginRepair {
    $scriptPath = Join-Path (Get-CodexHomePath) "maintenance\scripts\ensure-chrome-extension-origin.ps1"
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        return ""
    }

    try {
        $results = @(& $scriptPath -NoNodeCheck 2>&1)
        $important = @($results | Where-Object { [string]$_ -match "^(patched|failed|error):" })
        if ($important.Count -gt 0) {
            return "Chrome extension origin repair: $($important -join '; ')"
        }
    } catch {
        return "Chrome extension origin repair failed: $($_.Exception.Message)"
    }

    return ""
}

function Join-CodepointSignal {
    param([int[]]$Codepoints)

    $chars = foreach ($codepoint in $Codepoints) {
        [string][char]$codepoint
    }
    return ($chars -join "")
}

function Test-PromptContainsAnyCodepointSignal {
    param(
        [string]$Prompt,
        [object[]]$Signals
    )

    $compact = $Prompt -replace "\s+", ""
    foreach ($signal in $Signals) {
        $word = Join-CodepointSignal -Codepoints @($signal)
        if (-not [string]::IsNullOrWhiteSpace($word) -and $compact.Contains($word)) {
            return $true
        }
    }
    return $false
}
