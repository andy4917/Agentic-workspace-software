function Test-FinalAuditReady {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $hasShortPreflightSignal = $Message -match "(?i)\bFINAL\s+PREFLIGHT\b"
    $hasDone = $Message -match "(?i)(Done:|inspected|executed|completed)"
    $hasFixedChanged = $Message -match "(?i)(Fixed\s*/\s*changed:|Fixed:|changed:|files? changed|settings? changed)"
    $hasVerification = $Message -match "(?i)(Verification:|verified|checks? run|test|lint|typecheck|build|direct checks?)"
    $hasRemaining = $Message -match "(?i)(Remaining\s*/\s*separate issues:|Remaining:|separate issues:|not[-_ ]?run|not checked|blocked|risk|residual)"
    $hasRelatedCompatibility = $Message -match "(?i)(Related-scope compatibility:|compatibility|adjacent|rollback)"
    $hasCommitStatus = $Message -match "(?i)(Commit status:|not committed|committed|pushed|push status)"

    $shortPreflightReady = $hasShortPreflightSignal -and $hasDone -and $hasFixedChanged -and $hasVerification -and $hasRemaining -and $hasRelatedCompatibility -and $hasCommitStatus

    $hasLegacyAuditSignal = $Message -match "(?i)(FINAL_GOAL_AUDIT|final goal audit|goal audit|completion audit)"
    $hasLegacyChecked = $Message -match "(?i)(checked|checks? run|verified|verification|test|lint|typecheck|build|direct checks?)"
    $hasLegacyNotRun = $Message -match "(?i)(not[-_ ]?run|checks? not run|not checked|unable to run|skipped)"
    $hasLegacyRisks = $Message -match "(?i)(risk|risks|residual|remaining)"
    $hasLegacyStatus = $Message -match "(?i)(status|decision|complete|blocked|continue|current status)"
    $hasLegacyPmVerification = $Message -match "(?i)(PM independent|independent verification)"
    $legacyAuditReady = $hasLegacyAuditSignal -and $hasLegacyChecked -and $hasLegacyNotRun -and $hasLegacyRisks -and $hasLegacyStatus -and $hasLegacyPmVerification

    return ($shortPreflightReady -or $legacyAuditReady)
}

function Test-WatcherCoverageReady {
    param(
        $State,
        [string]$Message
    )

    if (-not [bool]$State.watcherExpected) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $hasWatcherReport = $Message -match "(?i)(WATCHER_REPORT|watcher report|watcher evidence)"
    $hasWatcherNotUsed = $Message -match "(?i)(WATCHER_NOT_USED|watcher not used)"
    $hasAcceptedRejectedEvidence = $Message -match "(?i)(accepted and rejected subagent evidence|accepted/rejected subagent evidence|accepted subagent evidence|rejected subagent evidence|subagent evidence)"
    $hasWatcherNotUsedReason = $Message -match "(?i)(reason|because)"
    $hasWatcherNotUsedRisk = $Message -match "(?i)(risk|residual)"
    $hasWatcherNotUsedSubstitute = $Message -match "(?i)(substitute check|substitute evidence|pm independent verification|direct check)"
    $hasWatcherNotUsedConfidence = $Message -match "(?i)(confidence impact|confidence)"

    $watcherReportReady = $hasWatcherReport -and $hasAcceptedRejectedEvidence
    $watcherOmissionReady = $hasWatcherNotUsed -and $hasWatcherNotUsedReason -and $hasWatcherNotUsedRisk -and $hasWatcherNotUsedSubstitute -and $hasWatcherNotUsedConfidence

    return ($watcherReportReady -or $watcherOmissionReady)
}

function Test-AnomalyTraceReady {
    param(
        $State,
        [string]$Message
    )

    if (-not [bool]$State.anomalyPauseExpected) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $hasPause = $Message -match "(?i)(pause|paused|stop-the-line|anomaly pause|stop active path)"
    $hasTrace = $Message -match "(?i)(trace|traced|root cause|first mismatch|failure point|mismatch)"
    $hasOutcome = $Message -match "(?i)(verified|verification|blocked|continue|complete|risk|residual)"

    return ($hasPause -and $hasTrace -and $hasOutcome)
}

function Test-SubagentDecisionReady {
    param(
        $State,
        [string]$Message
    )

    $hasSubagentEvent = @($State.subagentEvents).Count -gt 0
    if (-not ([bool]$State.subagentDecisionRequired -or $hasSubagentEvent)) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $hasMarker = $Message -match "(?i)SUBAGENT_CALL\s+(used|not_used|not used)"
    $hasReason = $Message -match "(?i)(reason|because)"
    $hasEvidence = $Message -match "(?i)(evidence|verified|direct evidence|substitute check)"
    $hasRisk = $Message -match "(?i)(risk|residual)"

    return ($hasMarker -and $hasReason -and $hasEvidence -and $hasRisk)
}

function Test-SkillEvidenceReady {
    param(
        $State,
        [string]$Message
    )

    $hasSkillEvent = @($State.skillEvents).Count -gt 0
    if (-not ([bool]$State.skillEvidenceRequired -or $hasSkillEvent)) {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $hasMarker = $Message -match "(?i)SKILL_EVIDENCE\s+(used|not_used|not used)"
    $hasReason = $Message -match "(?i)(reason|because)"
    $hasEvidence = $Message -match "(?i)(evidence|direct evidence|checked|read|loaded)"
    $hasRisk = $Message -match "(?i)(risk|residual)"

    return ($hasMarker -and $hasReason -and $hasEvidence -and $hasRisk)
}
