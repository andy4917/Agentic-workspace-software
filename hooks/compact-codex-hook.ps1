param()

$ErrorActionPreference = "Stop"

function Get-CodexHome {
    if ($env:CODEX_HOME) { return $env:CODEX_HOME }
    return (Join-Path $env:USERPROFILE ".codex")
}

function Read-HookPayload {
    param([string]$Raw)
    $raw = $Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ hook_event_name = "unknown"; _raw = "" }
    }
    try {
        return ($raw | ConvertFrom-Json -Depth 32)
    } catch {
        return [pscustomobject]@{ hook_event_name = "unknown"; _raw = $raw }
    }
}

function Ensure-RuntimeCleanupWatch {
    param([string]$CodexHome)

    $cleanupScript = Join-Path $CodexHome "maintenance\scripts\codex-runtime-process-cleanup.ps1"
    if (-not (Test-Path -LiteralPath $cleanupScript -PathType Leaf)) {
        return [ordered]@{
            attempted = $false
            status = "missing_cleanup_script"
            script = $cleanupScript
        }
    }

    $output = & $cleanupScript -Mode ensure-watch -CodexHome $CodexHome -CleanupStaleOnEnsure -CleanupDuplicateRootsOnWatch -CleanupRetiredRootsOnWatch -StopAppServerOnOwnerExit -StopAppServerOnOwnerNoVisibleWindow 2>&1
    $text = (($output | Out-String) -replace "\s+", " ").Trim()
    return [ordered]@{
        attempted = $true
        status = "ok"
        script = $cleanupScript
        output = $text
    }
}

function ConvertTo-HookText {
    param([object]$Value)

    if ($null -eq $Value) { return "" }
    if ($Value -is [string]) { return $Value }
    try {
        return ($Value | ConvertTo-Json -Compress -Depth 32)
    } catch {
        return ($Value | Out-String)
    }
}

function Get-HookInputText {
    param(
        [object]$Payload,
        [string]$Raw
    )

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($name in @("tool_input", "toolInput", "arguments", "input", "parameters")) {
        if ($Payload.PSObject.Properties.Name -contains $name) {
            $parts.Add((ConvertTo-HookText -Value $Payload.$name)) | Out-Null
        }
    }
    if ($parts.Count -eq 0) {
        $parts.Add($Raw) | Out-Null
    }
    return ($parts -join "`n")
}

function Get-CommandTextFromObject {
    param([object]$Value)

    if ($null -eq $Value) { return "" }
    if ($Value.PSObject.Properties.Name -contains "command") {
        return [string]$Value.command
    }
    foreach ($name in @("tool_input", "toolInput", "arguments", "input", "parameters")) {
        if ($Value.PSObject.Properties.Name -contains $name) {
            $container = $Value.$name
            if ($null -ne $container -and $container.PSObject.Properties.Name -contains "command") {
                return [string]$container.command
            }
        }
    }
    return (ConvertTo-HookText -Value $Value)
}

function Get-NestedToolCalls {
    param([object]$Payload)

    $calls = New-Object System.Collections.Generic.List[object]
    foreach ($containerName in @("tool_input", "toolInput", "arguments", "input", "parameters")) {
        if (-not ($Payload.PSObject.Properties.Name -contains $containerName)) { continue }
        $container = $Payload.$containerName
        foreach ($listName in @("tool_uses", "toolUses")) {
            if ($null -eq $container -or -not ($container.PSObject.Properties.Name -contains $listName)) { continue }
            foreach ($call in @($container.$listName)) {
                $recipient = ""
                foreach ($toolProperty in @("recipient_name", "tool_name", "toolName", "name")) {
                    if ($call.PSObject.Properties.Name -contains $toolProperty) {
                        $recipient = [string]$call.$toolProperty
                        break
                    }
                }
                $calls.Add([pscustomobject]@{
                    tool = $recipient
                    command = (Get-CommandTextFromObject -Value $call)
                    text = (ConvertTo-HookText -Value $call)
                }) | Out-Null
            }
        }
    }
    return $calls.ToArray()
}

function Get-PowerShellCommandTokens {
    param([string]$CommandText)

    if ([string]::IsNullOrWhiteSpace($CommandText)) {
        return @()
    }
    try {
        $parseErrors = $null
        return @([System.Management.Automation.PSParser]::Tokenize($CommandText, [ref]$parseErrors))
    } catch {
        return @()
    }
}

function Get-ExecutableLeaf {
    param([string]$Command)

    $trimmed = ([string]$Command).Trim().Trim('"', "'")
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return "" }
    try {
        $leaf = [System.IO.Path]::GetFileName($trimmed)
        if (-not [string]::IsNullOrWhiteSpace($leaf)) {
            return $leaf
        }
    } catch {
        return $trimmed
    }
    return $trimmed
}

function Test-TextContainsEncodedPowerShellInvocation {
    param([string]$CommandText)

    return ($CommandText -match '(?i)\b(powershell|pwsh)(\.exe)?\b[^\r\n]*(^|[\s"'',`])-(EncodedCommand|enc|ec|e)(?=$|[\s"''`:=,])')
}

function Get-StartProcessNestedCommandText {
    param([object[]]$Segment)

    $target = ""
    $arguments = New-Object System.Collections.Generic.List[string]
    $expectFilePath = $false
    $expectStartProcessParameterValue = $false
    $collectArgumentList = $false
    foreach ($segmentValue in $Segment) {
        $value = [string]$segmentValue
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq ",") { continue }
        if ($expectStartProcessParameterValue) {
            $expectStartProcessParameterValue = $false
            continue
        }
        if ($expectFilePath) {
            $target = $value
            $expectFilePath = $false
            continue
        }
        if ($value -match '(?i)^-(FilePath|File|F)$') {
            $expectFilePath = $true
            $collectArgumentList = $false
            continue
        }
        if ($value -match '(?i)^-(ArgumentList|Arg|Args)$') {
            $collectArgumentList = $true
            continue
        }
        if ($value -match '(?i)^-(WorkingDirectory|WindowStyle|Verb|Credential|RedirectStandardInput|RedirectStandardOutput|RedirectStandardError|Environment)$') {
            $expectStartProcessParameterValue = $true
            $collectArgumentList = $false
            continue
        }
        if ($value -match '(?i)^-(NoNewWindow|PassThru|Wait|LoadUserProfile|UseNewEnvironment)$') {
            $collectArgumentList = $false
            continue
        }
        if ($collectArgumentList) {
            $arguments.Add($value) | Out-Null
            continue
        }
        if (-not $target -and $value -notmatch '^-') {
            $target = $value
            continue
        }
        if ($target -and $value -notmatch '^-') {
            $arguments.Add($value) | Out-Null
        }
    }
    if ([string]::IsNullOrWhiteSpace($target)) { return "" }
    $argumentText = ($arguments -join " ")
    return "$target $argumentText".Trim()
}

function Get-ApplyPatchTargetPaths {
    param([string]$Text)

    $targets = New-Object System.Collections.Generic.List[string]
    $textVariants = @($Text, ($Text -replace '\\r\\n|\\n', "`n"))
    foreach ($textVariant in $textVariants) {
        foreach ($line in ($textVariant -split "\r?\n")) {
            $cleanLine = $line.Trim().Trim('"')
            if ($cleanLine -match '^\*\*\*\s+(Add|Update|Delete)\s+File:\s*(.+?)\s*$') {
                $targets.Add($Matches[2]) | Out-Null
                continue
            }
            if ($cleanLine -match '^\*\*\*\s+Move\s+to:\s*(.+?)\s*$') {
                $targets.Add($Matches[1]) | Out-Null
            }
        }
    }
    return $targets.ToArray()
}

function Test-ApplyPatchTargetRisk {
    param(
        [string]$Text,
        [string]$SensitivePathPattern
    )

    foreach ($target in (Get-ApplyPatchTargetPaths -Text $Text)) {
        $clean = ([string]$target).Trim().Trim('"', "'")
        $normalized = ($clean -replace '/', '\').Trim()
        if ([string]::IsNullOrWhiteSpace($normalized)) { continue }
        if ($normalized -match $SensitivePathPattern) {
            return "sensitive target $clean"
        }
        if ($clean -match '^[\\/]' -or $normalized -match '^\\') {
            return "broad target $clean"
        }
        if ($normalized -match '(?i)^([A-Z]:\\|\\+|/+)' -or $normalized -match '(^|\\)\.\.(\\|$)' -or $normalized -match '(?i)^([A-Z]:\\?|\\+|/+|\.{1,2}|~|\*)$') {
            return "broad target $clean"
        }
    }
    return ""
}

function Test-EncodedPowerShellCommand {
    param([string]$CommandText)

    $parsedItems = @(Get-PowerShellCommandTokens -CommandText $CommandText)
    if ($parsedItems.Count -eq 0) {
        return (Test-TextContainsEncodedPowerShellInvocation -CommandText $CommandText)
    }

    for ($index = 0; $index -lt $parsedItems.Count; $index++) {
        $parsedItem = $parsedItems[$index]
        if ([string]$parsedItem.Type -ne "Command") { continue }
        $command = [string]$parsedItem.Content
        $commandLeaf = Get-ExecutableLeaf -Command $command
        $segment = New-Object System.Collections.Generic.List[string]
        for ($cursor = $index + 1; $cursor -lt $parsedItems.Count; $cursor++) {
            if ([string]$parsedItems[$cursor].Type -eq "Command") { break }
            $segment.Add([string]$parsedItems[$cursor].Content) | Out-Null
        }
        $segmentText = ($segment -join " ")

        if ($commandLeaf -match '(?i)^(powershell|pwsh|powershell\.exe|pwsh\.exe)$') {
            if ($segmentText -match '(?i)(^|[\s"''`])-(EncodedCommand|enc|ec|e)(?=$|[\s"''`:=])') {
                return $true
            }
            for ($segmentIndex = 0; $segmentIndex -lt $segment.Count; $segmentIndex++) {
                if ($segment[$segmentIndex] -notmatch '(?i)^-(Command|c)$') { continue }
                if ($segmentIndex + 1 -ge $segment.Count) { continue }
                $nestedCommand = ($segment[($segmentIndex + 1)..($segment.Count - 1)] -join " ")
                if (Test-EncodedPowerShellCommand -CommandText $nestedCommand) {
                    return $true
                }
                break
            }
            continue
        }

        if ($commandLeaf -match '(?i)^(Start-Process|saps|start)$') {
            $launcherCommand = Get-StartProcessNestedCommandText -Segment $segment
            if (
                (Test-TextContainsEncodedPowerShellInvocation -CommandText $segmentText) -or
                (Test-TextContainsEncodedPowerShellInvocation -CommandText $launcherCommand)
            ) {
                return $true
            }
            $startsPowerShell = $false
            foreach ($segmentValue in $segment) {
                $segmentLeaf = Get-ExecutableLeaf -Command $segmentValue
                if ($segmentLeaf -match '(?i)^(powershell|pwsh|powershell\.exe|pwsh\.exe)$') {
                    $startsPowerShell = $true
                    break
                }
            }
            if (
                $startsPowerShell -and
                $segmentText -match '(?i)(^|[\s"'',`])-(EncodedCommand|enc|ec|e)(?=$|[\s"''`:=,])'
            ) {
                return $true
            }
            continue
        }

        if ($commandLeaf -match '(?i)^cmd(\.exe)?$') {
            for ($segmentIndex = 0; $segmentIndex -lt $segment.Count; $segmentIndex++) {
                if ($segment[$segmentIndex] -notmatch '(?i)^/c$') { continue }
                if ($segmentIndex + 1 -ge $segment.Count) { continue }
                $nestedCommand = ($segment[($segmentIndex + 1)..($segment.Count - 1)] -join " ")
                if (Test-EncodedPowerShellCommand -CommandText $nestedCommand) {
                    return $true
                }
                break
            }
        }
    }

    return $false
}

function Test-HighRiskDestructiveCommand {
    param(
        [string]$CommandText,
        [string]$BroadTargetPattern,
        [string]$RecursiveFlagPattern
    )

    $parsedItems = @(Get-PowerShellCommandTokens -CommandText $CommandText)
        if ($parsedItems.Count -eq 0) {
        return (
            ($CommandText -match '(?i)\bgit\s+reset\s+--hard\b') -or
            (
                ($CommandText -match '(?i)\bgit(?:\.exe|\.cmd)?\b[^\r\n]*\bclean\b') -and
                ($CommandText -notmatch '(?i)(^|[\s"''`])(--dry-run|-n[A-Za-z]*)(?=$|[\s"''`])') -and
                ($CommandText -match '(?i)(^|[\s"''`])(--force(?:=\S*)?|-[A-Za-z]*f[A-Za-z]*)(?=$|[\s"''`])')
            ) -or
            ($CommandText -match '(?i)\bgit(?:\.exe|\.cmd)?\s+push\b[^\r\n]*(--force(?:=|$)|--force-with-lease(?:=|$)|--delete(?:=|$)|--mirror(?:=|$)|--prune(?:=|$)|-[A-Za-z]*f[A-Za-z]*|(^|[\s"''`])-d(?=$|[\s"''`])|(^|[\s"''`])\+[^"''`\s]+|(^|[\s"''`]):[^"''`\s]+)') -or
            (
                ($CommandText -match '(?i)\b(Remove-Item|ri|rm|rd|rmdir|del)\b') -and
                ($CommandText -match $RecursiveFlagPattern) -and
                ($CommandText -match $BroadTargetPattern)
            )
        )
    }

    for ($index = 0; $index -lt $parsedItems.Count; $index++) {
        $parsedItem = $parsedItems[$index]
        if ([string]$parsedItem.Type -ne "Command") { continue }
        $command = [string]$parsedItem.Content
        $commandLeaf = Get-ExecutableLeaf -Command $command
        $segment = New-Object System.Collections.Generic.List[string]
        for ($cursor = $index + 1; $cursor -lt $parsedItems.Count; $cursor++) {
            if ([string]$parsedItems[$cursor].Type -eq "Command") { break }
            $segment.Add([string]$parsedItems[$cursor].Content) | Out-Null
        }
        $segmentText = ($segment -join " ")

        if ($commandLeaf -match '(?i)^(Remove-Item|ri|rm|rd|rmdir|del)$') {
            if (($segmentText -match $RecursiveFlagPattern) -and ($segmentText -match $BroadTargetPattern)) {
                return $true
            }
            continue
        }

        if ($commandLeaf -match '(?i)^git(\.exe|\.cmd)?$') {
            $gitParts = @($segment | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -notin @("@(", "@{", "(", ")", "{", "}", "[", "]", ",")
            })
            $gitSubcommand = ""
            $gitRemaining = @()
            for ($gitIndex = 0; $gitIndex -lt $gitParts.Count; $gitIndex++) {
                $gitPart = [string]$gitParts[$gitIndex]
                if ($gitPart -match '(?i)^(-C|--git-dir|--work-tree|--namespace|--config-env|-c)$') {
                    $gitIndex++
                    continue
                }
                if ($gitPart -match '^-') { continue }
                $gitSubcommand = $gitPart
                if ($gitIndex + 1 -lt $gitParts.Count) {
                    $gitRemaining = @($gitParts[($gitIndex + 1)..($gitParts.Count - 1)])
                }
                break
            }
            $gitRemainingText = ($gitRemaining -join " ")
            if (($gitSubcommand -match '(?i)^reset$') -and ($gitRemainingText -match '(?i)--hard\b')) {
                return $true
            }
            if ($gitSubcommand -match '(?i)^clean$') {
                $gitCleanIsDryRun = $false
                foreach ($gitRemainingPart in $gitRemaining) {
                    if (
                        ([string]$gitRemainingPart -match '(?i)^--dry-run(?:=|$)') -or
                        ([string]$gitRemainingPart -match '(?i)^-[A-Za-z]*n[A-Za-z]*')
                    ) {
                        $gitCleanIsDryRun = $true
                        break
                    }
                }
                if ($gitCleanIsDryRun) {
                    continue
                }
                foreach ($gitRemainingPart in $gitRemaining) {
                    if (
                        ([string]$gitRemainingPart -match '(?i)^--force(?:=|$)') -or
                        ([string]$gitRemainingPart -match '(?i)^-[A-Za-z]*f[A-Za-z]*')
                    ) {
                        return $true
                    }
                }
            }
            if ($gitSubcommand -match '(?i)^push$') {
                foreach ($gitRemainingPart in $gitRemaining) {
                    if (
                        ([string]$gitRemainingPart -match '(?i)^--force(?:=|$)') -or
                        ([string]$gitRemainingPart -match '(?i)^--force-with-lease(?:=|$)') -or
                        ([string]$gitRemainingPart -match '(?i)^--delete(?:=|$)') -or
                        ([string]$gitRemainingPart -match '(?i)^--mirror(?:=|$)') -or
                        ([string]$gitRemainingPart -match '(?i)^--prune(?:=|$)') -or
                        ([string]$gitRemainingPart -match '(?i)^-[A-Za-z]*f[A-Za-z]*') -or
                        ([string]$gitRemainingPart -match '(?i)^-d$') -or
                        ([string]$gitRemainingPart -match '^\+') -or
                        ([string]$gitRemainingPart -match '^:')
                    ) {
                        return $true
                    }
                }
            }
            continue
        }

        if ($commandLeaf -match '(?i)^(Start-Process|saps|start)$') {
            $launcherCommand = Get-StartProcessNestedCommandText -Segment $segment
            if (
                $launcherCommand -and
                (Test-HighRiskDestructiveCommand -CommandText $launcherCommand -BroadTargetPattern $BroadTargetPattern -RecursiveFlagPattern $RecursiveFlagPattern)
            ) {
                return $true
            }
            continue
        }

        if ($commandLeaf -match '(?i)^(powershell|pwsh|powershell\.exe|pwsh\.exe)$') {
            for ($segmentIndex = 0; $segmentIndex -lt $segment.Count; $segmentIndex++) {
                if ($segment[$segmentIndex] -notmatch '(?i)^-(Command|c)$') { continue }
                if ($segmentIndex + 1 -ge $segment.Count) { continue }
                $nestedCommand = ($segment[($segmentIndex + 1)..($segment.Count - 1)] -join " ")
                if (Test-HighRiskDestructiveCommand -CommandText $nestedCommand -BroadTargetPattern $BroadTargetPattern -RecursiveFlagPattern $RecursiveFlagPattern) {
                    return $true
                }
                break
            }
            continue
        }

        if ($commandLeaf -match '(?i)^cmd(\.exe)?$') {
            for ($segmentIndex = 0; $segmentIndex -lt $segment.Count; $segmentIndex++) {
                if ($segment[$segmentIndex] -notmatch '(?i)^/c$') { continue }
                if ($segmentIndex + 1 -ge $segment.Count) { continue }
                $nestedCommand = ($segment[($segmentIndex + 1)..($segment.Count - 1)] -join " ")
                if (Test-HighRiskDestructiveCommand -CommandText $nestedCommand -BroadTargetPattern $BroadTargetPattern -RecursiveFlagPattern $RecursiveFlagPattern) {
                    return $true
                }
                break
            }
        }
    }

    return $false
}

function Get-PreToolUseDecision {
    param(
        [string]$ToolName,
        [object]$Payload,
        [string]$Raw
    )

    $toolText = if ($ToolName) { $ToolName } else { "" }
    $inputText = Get-HookInputText -Payload $Payload -Raw $Raw
    $combined = "$toolText`n$inputText"
    $commandText = Get-CommandTextFromObject -Value $Payload
    $inspectionText = "$toolText`n$commandText"
    $isShellLike = $toolText -match '(?i)(^|\.|_)(bash|shell|shell_command|powershell|pwsh|cmd)$'
    $contentReadCommandPattern = '(?i)\b(Get-Content|type|cat|gc|more)\b'
    $sensitivePathPattern = '(?i)(\.env(\.[\w.-]+)?|auth\.json|\.credentials\.json|credentials?\.json|id_rsa|id_ed25519|\.pem\b|\.pfx\b|\.key\b|(?:api[-_]?key|credential|password|passwd|secret|token|cookie|session)[\w.-]*\.(json|txt|toml|ya?ml|env|key|pem))'
    $sensitivePathWithDirectoryPattern = '(?i)(\.codex[\\/]|C:\\|%USERPROFILE%|\$env:USERPROFILE|~[\\/])[^"''\s]*(\.env(\.[\w.-]+)?|auth\.json|\.credentials\.json|credentials?\.json|id_rsa|id_ed25519|\.pem\b|\.pfx\b|\.key\b|(?:api[-_]?key|credential|password|passwd|secret|token|cookie|session)[\w.-]*\.(json|txt|toml|ya?ml|env|key|pem))'
    $safeReferenceSearchPattern = '(?i)((^|[\r\n])\s*(rg|grep)\b(?:\s+-[^\r\n\s]+)*\s+["'']?(auth\.json|\.env|credentials?\.json|api[-_]?key|credential|password|passwd|secret|token|cookie|session)["'']?\s+["'']?(docs?|maintenance|AGENTS\.md|README(\.md)?)["'']?\s*$|\bSelect-String\b[^\r\n]*-Pattern\s+["'']?(auth\.json|\.env|credentials?\.json|api[-_]?key|credential|password|passwd|secret|token|cookie|session)["'']?[^\r\n]*(?:-Path|-LiteralPath)\s+["'']?(docs?|maintenance|AGENTS\.md|README(\.md)?)["'']?\s*$)'
    $selectStringExplicitPathPattern = '(?i)\bSelect-String\b[^\r\n]*(?:-Path|-LiteralPath)\s+["'']?[^"''\s]*(\.env(\.[\w.-]+)?|auth\.json|\.credentials\.json|credentials?\.json|id_rsa|id_ed25519|\.pem\b|\.pfx\b|\.key\b|(?:api[-_]?key|credential|password|passwd|secret|token|cookie|session)[\w.-]*\.(json|txt|toml|ya?ml|env|key|pem))'
    $selectStringPositionalPathPattern = '(?i)\bSelect-String\b(?:[^\r\n]*\s-Pattern\s+\S+|\s+(?!-)\S+)\s+["'']?[^"''\s]*(\.env(\.[\w.-]+)?|auth\.json|\.credentials\.json|credentials?\.json|id_rsa|id_ed25519|\.pem\b|\.pfx\b|\.key\b|(?:api[-_]?key|credential|password|passwd|secret|token|cookie|session)[\w.-]*\.(json|txt|toml|ya?ml|env|key|pem))'
    $fileReadMcpPattern = '(?i)^mcp__(?:[^_\s]*(?:fs|file|filesystem)[^_\s]*__|.*(?:__|[._-])(?:read|get|fetch|download|cat)[_-]?file\b|.*(?:__|[._-])read[_-]?path\b)'
    $broadTargetPattern = '(?i)([A-Z]:[\\/]|%USERPROFILE%|\$env:USERPROFILE|\$\{env:USERPROFILE\}|\$HOME|\$\{HOME\}|\$PWD|\$\{PWD\}|(^|[\s"''`])(HOME|PWD)(?=$|[\s"''`])|~|\*|(^|[\s"''`])(\.|\.\.|[\\/])([\\/\s"''`]|$))'
    $recursiveFlagPattern = '(?i)(^|[\s"''`])(-r(?:e(?:c(?:u(?:r(?:s(?:e)?)?)?)?)?)?(?::\s*\$?true)?|-rf|-fr|/s)(?=$|[\s"''`])'
    $isFileReadMcp = $toolText -match $fileReadMcpPattern
    if ($isFileReadMcp -and $combined -match $sensitivePathPattern) {
        return [ordered]@{ decision = "deny"; reason = "direct credential or secret-file reads require explicit user approval and a narrower non-secret metadata route" }
    }

    if ($toolText -match '(?i)^multi_tool_use(\.|$)') {
        foreach ($nestedCall in (Get-NestedToolCalls -Payload $Payload)) {
            $nestedToolText = if ($nestedCall.tool) { [string]$nestedCall.tool } else { "" }
            $nestedCombined = "$nestedToolText`n$($nestedCall.text)"
            $nestedInspection = "$nestedToolText`n$($nestedCall.command)"
            $nestedIsFileReadMcp = $nestedToolText -match $fileReadMcpPattern
            if ($nestedIsFileReadMcp -and $nestedCombined -match $sensitivePathPattern) {
                return [ordered]@{ decision = "deny"; reason = "nested credential or secret-file reads require explicit user approval and a narrower non-secret metadata route" }
            }
            $nestedIsApplyPatch = $nestedToolText -match '(?i)(^|[._-])apply_patch$'
            if ($nestedIsApplyPatch) {
                $nestedApplyPatchRisk = Test-ApplyPatchTargetRisk -Text $nestedCombined -SensitivePathPattern $sensitivePathPattern
                if ($nestedApplyPatchRisk) {
                    return [ordered]@{ decision = "deny"; reason = "nested apply_patch targets $nestedApplyPatchRisk and requires explicit approval" }
                }
            }
            $nestedIsShellLike = $nestedToolText -match '(?i)(^|\.|_)(bash|shell|shell_command|powershell|pwsh|cmd)$'
            if (-not $nestedIsShellLike) { continue }
            if (Test-EncodedPowerShellCommand -CommandText $nestedCall.command) {
                return [ordered]@{ decision = "deny"; reason = "nested encoded PowerShell commands are blocked at the hook boundary because their payload cannot be safely inspected before execution" }
            }
            if ($nestedInspection -match $contentReadCommandPattern -and $nestedInspection -match $sensitivePathPattern) {
                return [ordered]@{ decision = "deny"; reason = "nested credential or secret-file reads require explicit user approval and a narrower non-secret metadata route" }
            }
            if ($nestedInspection -match $selectStringExplicitPathPattern -or $nestedInspection -match $selectStringPositionalPathPattern) {
                return [ordered]@{ decision = "deny"; reason = "nested credential or secret-file reads require explicit user approval and a narrower non-secret metadata route" }
            }
            if (($nestedInspection -match $sensitivePathPattern) -and -not (($nestedInspection -match $safeReferenceSearchPattern) -and ($nestedInspection -notmatch $sensitivePathWithDirectoryPattern))) {
                return [ordered]@{ decision = "deny"; reason = "nested credential or secret-file reads require explicit user approval and a narrower non-secret metadata route" }
            }
            if (Test-HighRiskDestructiveCommand -CommandText $nestedCall.command -BroadTargetPattern $broadTargetPattern -RecursiveFlagPattern $recursiveFlagPattern) {
                return [ordered]@{ decision = "deny"; reason = "nested broad destructive operations must be scoped and explicitly approved before hook execution" }
            }
        }
    }

    $isApplyPatch = $toolText -match '(?i)(^|[._-])apply_patch$'
    if ($isApplyPatch) {
        $applyPatchRisk = Test-ApplyPatchTargetRisk -Text $inputText -SensitivePathPattern $sensitivePathPattern
        if ($applyPatchRisk) {
            return [ordered]@{ decision = "deny"; reason = "apply_patch targets $applyPatchRisk and requires explicit approval" }
        }
    }

    if (-not $isShellLike) {
        return [ordered]@{ decision = "allow"; reason = "compact scaffold hook records evidence and blocks only immediate high-risk operations" }
    }

    if (Test-EncodedPowerShellCommand -CommandText $commandText) {
        return [ordered]@{ decision = "deny"; reason = "encoded PowerShell commands are blocked at the hook boundary because their payload cannot be safely inspected before execution" }
    }

    if ($inspectionText -match $contentReadCommandPattern -and $inspectionText -match $sensitivePathPattern) {
        return [ordered]@{ decision = "deny"; reason = "direct credential or secret-file reads require explicit user approval and a narrower non-secret metadata route" }
    }
    if ($inspectionText -match $selectStringExplicitPathPattern -or $inspectionText -match $selectStringPositionalPathPattern) {
        return [ordered]@{ decision = "deny"; reason = "direct credential or secret-file reads require explicit user approval and a narrower non-secret metadata route" }
    }
    if (($inspectionText -match $sensitivePathPattern) -and -not (($inspectionText -match $safeReferenceSearchPattern) -and ($inspectionText -notmatch $sensitivePathWithDirectoryPattern))) {
        return [ordered]@{ decision = "deny"; reason = "direct credential or secret-file reads require explicit user approval and a narrower non-secret metadata route" }
    }

    if (Test-HighRiskDestructiveCommand -CommandText $commandText -BroadTargetPattern $broadTargetPattern -RecursiveFlagPattern $recursiveFlagPattern) {
        return [ordered]@{ decision = "deny"; reason = "broad destructive operations must be scoped and explicitly approved before hook execution" }
    }

    return [ordered]@{ decision = "allow"; reason = "compact scaffold hook records evidence and blocks only immediate high-risk operations" }
}

$stdinRaw = ""
try {
    $stdinStream = [Console]::OpenStandardInput()
    $stdinReader = [System.IO.StreamReader]::new($stdinStream, [System.Text.Encoding]::UTF8)
    $stdinRaw = $stdinReader.ReadToEnd()
} catch {
    $stdinRaw = ""
}
if ([string]::IsNullOrWhiteSpace($stdinRaw)) {
    $stdinRaw = ($input | Out-String)
}

$payload = Read-HookPayload -Raw $stdinRaw
$event = if ($payload.hook_event_name) { [string]$payload.hook_event_name } elseif ($payload.hookEventName) { [string]$payload.hookEventName } else { "unknown" }
$tool = if ($payload.tool_name) { [string]$payload.tool_name } elseif ($payload.toolName) { [string]$payload.toolName } else { $null }
$codexHome = Get-CodexHome
$stateDir = Join-Path $codexHome "state"
$ledger = Join-Path $stateDir "hook-ledger.jsonl"

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$runtimeCleanupWatch = $null
if ($event -eq "SessionStart" -or $event -eq "UserPromptSubmit") {
    if ($env:CODEX_HOOK_SMOKE -eq "1") {
        $runtimeCleanupWatch = [ordered]@{
            attempted = $false
            status = "smoke_skipped"
        }
    } else {
        try {
            $runtimeCleanupWatch = Ensure-RuntimeCleanupWatch -CodexHome $codexHome
        } catch {
            $runtimeCleanupWatch = [ordered]@{
                attempted = $true
                status = "error"
                error = $_.Exception.Message
            }
        }
    }
}

$preToolUseDecision = $null
if ($event -eq "PreToolUse") {
    $preToolUseDecision = Get-PreToolUseDecision -ToolName $tool -Payload $payload -Raw $stdinRaw
}

$record = [ordered]@{
    ts = (Get-Date).ToUniversalTime().ToString("o")
    runner = "compact-codex-hook"
    version = 2
    event = $event
    tool = $tool
    cwd = if ($payload.cwd) { [string]$payload.cwd } else { $null }
    action = if ($preToolUseDecision -and [string]$preToolUseDecision.decision -eq "deny") { "deny" } else { "continue" }
    decision_reason = if ($preToolUseDecision) { [string]$preToolUseDecision.reason } else { $null }
    runtime_cleanup_watch = $runtimeCleanupWatch
}
($record | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $ledger -Encoding UTF8

$out = [ordered]@{}

if ($event -eq "PreToolUse") {
    $out["hookSpecificOutput"] = [ordered]@{
        hookEventName = "PreToolUse"
        permissionDecision = [string]$preToolUseDecision.decision
        permissionDecisionReason = [string]$preToolUseDecision.reason
    }
} elseif ($event -eq "SessionStart") {
    $out["hookSpecificOutput"] = [ordered]@{
        hookEventName = "SessionStart"
        additionalContext = "Minimal scaffold active: use current evidence, keep runtime cleanup watcher active, treat claims as candidate until direct evidence supports them, avoid stale runtime state, and verify before completion."
    }
} elseif ($event -eq "UserPromptSubmit") {
    $out["hookSpecificOutput"] = [ordered]@{
        hookEventName = "UserPromptSubmit"
        additionalContext = "Compact hook active: keep workflow compact, use matching skills, treat claims as candidate until direct evidence supports them, verify from current files and commands, and report not-run checks."
    }
}

if ($out.Count -gt 0) {
    $out | ConvertTo-Json -Compress -Depth 8
}
