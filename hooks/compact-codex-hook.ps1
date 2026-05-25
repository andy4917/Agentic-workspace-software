# compact-codex-hook.ps1
# Version: v3 next-turn handoff
# Purpose: minimal Codex Desktop hooks that strongly enforce visible PM discipline
# without spending an extra Stop continuation on answer correction.
#
# Install path:
#   %USERPROFILE%\.codex\hooks\compact-codex-hook.ps1
#
# Stop behavior:
#   - never returns decision:block
#   - never forces "one more answer correction pass"
#   - records Local Optimization Error, Impact Analysis, and Context Synchronization TODOs
#   - SessionStart/UserPromptSubmit inject those TODOs once in the next turn
#
# Stored state is small, local, non-authoritative, and sanitized.
# Memento remains support-only memory; current files/tests/runtime evidence outrank it.
# It stores no raw prompt, raw assistant response, raw tool output, secrets, credentials, or full commands.

$ErrorActionPreference = "Stop"

function Write-JsonAndExit($obj) {
  $obj | ConvertTo-Json -Depth 24 -Compress
  exit 0
}

function EmptyOk { exit 0 }

function Continue-Ok { Write-JsonAndExit @{ continue = $true } }

function Add-Context($eventName, $message) {
  Write-JsonAndExit @{
    hookSpecificOutput = @{
      hookEventName = $eventName
      additionalContext = $message
    }
  }
}

function Deny-PreTool($reason) {
  Write-JsonAndExit @{
    hookSpecificOutput = @{
      hookEventName = "PreToolUse"
      permissionDecision = "deny"
      permissionDecisionReason = $reason
    }
  }
}

function Get-Prop($obj, $name, $default = $null) {
  if ($null -eq $obj) { return $default }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return $default }
  return $p.Value
}

function Sanitize-Name($s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return "unknown" }
  return ([string]$s -replace '[^A-Za-z0-9_.-]', '_')
}

function Short-Hash($s) {
  if ([string]::IsNullOrWhiteSpace($s)) { $s = "unknown" }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$s)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $hash = $sha.ComputeHash($bytes)
  return ([System.BitConverter]::ToString($hash).Replace("-", "").Substring(0, 12).ToLowerInvariant())
}

function Get-StateDir {
  $dir = Join-Path $env:TEMP "codex-compact-hooks-v3"
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  return $dir
}

function Get-StatePath($inputObj) {
  $sid = Sanitize-Name (Get-Prop $inputObj "session_id" "unknown-session")
  $tid = Sanitize-Name (Get-Prop $inputObj "turn_id" "unknown-turn")
  return (Join-Path (Get-StateDir) "$sid-$tid.state.json")
}

function Get-SessionPendingPath($inputObj) {
  $sid = Sanitize-Name (Get-Prop $inputObj "session_id" "unknown-session")
  return (Join-Path (Get-StateDir) "$sid.pending.json")
}

function Get-WorkspacePendingPath($inputObj) {
  $cwd = Get-Prop $inputObj "cwd" "unknown-cwd"
  $hash = Short-Hash $cwd
  return (Join-Path (Get-StateDir) "cwd-$hash.pending.json")
}

function New-State {
  return [ordered]@{
    requires_frame = $false
    impact_required = $false
    purpose_injected = $false
    context_synced = $false
    workframe_declared = $false
    changed = $false
    mutation_attempted = $false
    control_plane = $false
    frontend = $false
    migration = $false
    verification_seen = $false
    check_failed = $false
    mcp_used = $false
    delegation_requested = $false
    denied_secret = $false
    denied_destructive = $false
    denied_runtime_mutation = $false
    changed_paths = @()
  }
}

function ConvertTo-Hashtable($obj) {
  if ($null -eq $obj) { return @{} }
  if ($obj -is [hashtable]) { return $obj }
  $h = @{}
  foreach ($p in $obj.PSObject.Properties) {
    $h[$p.Name] = $p.Value
  }
  return $h
}

function Read-State($inputObj) {
  $path = Get-StatePath $inputObj
  if (Test-Path $path) {
    try {
      $obj = Get-Content -Raw -Path $path | ConvertFrom-Json
      $h = ConvertTo-Hashtable $obj
      foreach ($k in (New-State).Keys) {
        if (-not $h.ContainsKey($k)) { $h[$k] = (New-State)[$k] }
      }
      return $h
    } catch {
      return New-State
    }
  }
  return New-State
}

function Save-State($inputObj, $state) {
  $path = Get-StatePath $inputObj
  ($state | ConvertTo-Json -Depth 12 -Compress) | Set-Content -Encoding UTF8 -Path $path
}

function Read-JsonFile($path) {
  if (-not (Test-Path $path)) { return $null }
  try { return Get-Content -Raw -Path $path | ConvertFrom-Json }
  catch { return $null }
}

function Write-JsonFile($path, $obj) {
  ($obj | ConvertTo-Json -Depth 16 -Compress) | Set-Content -Encoding UTF8 -Path $path
}

function Tool-Text($inputObj) {
  $ti = Get-Prop $inputObj "tool_input" $null
  if ($null -eq $ti) { return "" }
  $cmd = Get-Prop $ti "command" $null
  if ($null -ne $cmd) { return [string]$cmd }
  $patch = Get-Prop $ti "patch" $null
  if ($null -ne $patch) { return [string]$patch }
  try { return ($ti | ConvertTo-Json -Depth 10 -Compress) }
  catch { return "" }
}

function Has-Any($text, [string[]]$patterns) {
  foreach ($p in $patterns) {
    if ($text -match $p) { return $true }
  }
  return $false
}

function Add-UniquePaths($current, $paths) {
  $set = New-Object System.Collections.Generic.List[string]
  foreach ($p in @($current)) {
    if (-not [string]::IsNullOrWhiteSpace($p) -and -not $set.Contains([string]$p)) { $set.Add([string]$p) }
  }
  foreach ($p in @($paths)) {
    if (-not [string]::IsNullOrWhiteSpace($p) -and -not $set.Contains([string]$p)) { $set.Add([string]$p) }
  }
  return @($set | Select-Object -First 20)
}

function Extract-ChangedPaths($text) {
  $paths = New-Object System.Collections.Generic.List[string]
  $patterns = @(
    '(?m)^\*\*\* (?:Add|Update|Delete) File:\s+(.+?)\s*$',
    '(?m)^\+\+\+\s+b/(.+?)\s*$',
    '(?m)^---\s+a/(.+?)\s*$'
  )
  foreach ($pat in $patterns) {
    foreach ($m in [regex]::Matches([string]$text, $pat)) {
      $p = $m.Groups[1].Value.Trim()
      if ($p -and -not $paths.Contains($p)) { $paths.Add($p) }
    }
  }
  return @($paths | Select-Object -First 20)
}

function Get-PendingCandidate($inputObj) {
  $sessionPath = Get-SessionPendingPath $inputObj
  $workspacePath = Get-WorkspacePendingPath $inputObj

  $p = Read-JsonFile $sessionPath
  if ($null -eq $p) { $p = Read-JsonFile $workspacePath }

  if ($null -eq $p) { return $null }

  $delivered = Get-Prop $p "delivered" $false
  if ($delivered -eq $true) { return $null }

  $created = Get-Prop $p "created_at_utc" $null
  if ($created) {
    try {
      $age = ([DateTime]::UtcNow - [DateTime]::Parse($created)).TotalHours
      if ($age -gt 168) { return $null }
    } catch {}
  }

  return $p
}

function Mark-PendingDelivered($inputObj, $pending) {
  $pending | Add-Member -NotePropertyName delivered -NotePropertyValue $true -Force
  $pending | Add-Member -NotePropertyName delivered_at_utc -NotePropertyValue ([DateTime]::UtcNow.ToString("o")) -Force

  $sessionPath = Get-SessionPendingPath $inputObj
  $workspacePath = Get-WorkspacePendingPath $inputObj

  if (Test-Path $sessionPath) { Write-JsonFile $sessionPath $pending }
  if (Test-Path $workspacePath) { Write-JsonFile $workspacePath $pending }
}

function Format-PendingContext($pending) {
  $items = Get-Prop $pending "next_turn_work_items" @()
  $loe = Get-Prop $pending "local_optimization_error" @()
  $impact = Get-Prop $pending "impact_analysis" @()
  $sync = Get-Prop $pending "context_synchronization" @()
  $risk = Get-Prop $pending "risk_level" "unknown"

  $itemText = (@($items) | Select-Object -First 8) -join "`n- "
  $loeText = (@($loe) | Select-Object -First 6) -join "`n- "
  $impactText = (@($impact) | Select-Object -First 6) -join "`n- "
  $syncText = (@($sync) | Select-Object -First 6) -join "`n- "

  if ([string]::IsNullOrWhiteSpace($itemText)) { $itemText = "none" }
  if ([string]::IsNullOrWhiteSpace($loeText)) { $loeText = "none" }
  if ([string]::IsNullOrWhiteSpace($impactText)) { $impactText = "none" }
  if ([string]::IsNullOrWhiteSpace($syncText)) { $syncText = "none" }

  return @"
NEXT_TURN_WORK_ITEMS from previous Stop hook:
Risk: $risk

Local Optimization Error:
- $loeText

Impact Analysis:
- $impactText

Context Synchronization required:
- $syncText

Required handling:
- $itemText

Instruction: Add these items to the current work plan before starting new mutation. If the new user request is unrelated, explicitly defer them with a one-line reason and keep the current task small.
"@
}

function Deliver-PendingContext($eventName, $inputObj, $prefixMessage) {
  $pending = Get-PendingCandidate $inputObj
  if ($null -eq $pending) {
    if ([string]::IsNullOrWhiteSpace($prefixMessage)) { EmptyOk }
    Add-Context $eventName $prefixMessage
  }

  $pendingContext = Format-PendingContext $pending
  Mark-PendingDelivered $inputObj $pending

  $message = $pendingContext
  if (-not [string]::IsNullOrWhiteSpace($prefixMessage)) {
    $message = $prefixMessage + "`n`n" + $pendingContext
  }
  Add-Context $eventName $message
}

function Compute-Handoff($inputObj, $state) {
  $msg = [string](Get-Prop $inputObj "last_assistant_message" "")
  $loe = New-Object System.Collections.Generic.List[string]
  $impact = New-Object System.Collections.Generic.List[string]
  $sync = New-Object System.Collections.Generic.List[string]
  $items = New-Object System.Collections.Generic.List[string]

  if ($state["denied_secret"]) {
    $loe.Add("SECRET_READ_BLOCKED: prior turn attempted to read or expose credential-like material.")
    $items.Add("Use metadata-only inspection or request exact-file authorization before touching secret boundaries.")
  }
  if ($state["denied_destructive"]) {
    $loe.Add("DESTRUCTIVE_ACTION_BLOCKED: prior turn attempted a destructive command.")
    $items.Add("Before any destructive operation, obtain explicit approval, impact analysis, and rollback/safe-stop plan.")
  }
  if ($state["denied_runtime_mutation"]) {
    $loe.Add("ACTIVE_RUNTIME_MUTATION_BLOCKED: prior turn attempted live runtime/toolchain/MCP mutation.")
    $items.Add("Treat runtime/toolchain/MCP changes as managed maintenance with approval, source class, active path, verification, and rollback.")
  }
  if ($state["changed"] -and -not $state["verification_seen"]) {
    $loe.Add("VERIFICATION_NOT_RUN: changes were made without a recorded direct verification command.")
    $items.Add("Run the smallest relevant direct check or document a precise not-run reason before continuing.")
  }
  if ($state["check_failed"]) {
    $loe.Add("CHECK_FAILED: a verification command appeared to fail.")
    $items.Add("Start next turn by inspecting the failed check and either fix, rerun, or mark status blocked/continue.")
  }
  if ($state["changed"] -and -not $state["context_synced"]) {
    $loe.Add("CONTEXT_SYNC_MISSING: mutation occurred without recorded read-only context sync.")
    $items.Add("Run git status/diff and inspect relevant AGENTS/runbook/files before further mutation.")
  }
  if ($state["impact_required"] -and $state["changed"] -and -not $state["workframe_declared"]) {
    $loe.Add("IMPACT_FRAME_MISSING: impact-required work changed files without HOOK_WORKFRAME.")
    $items.Add("Declare purpose, affected surfaces, checks, and rollback before further mutation.")
  }
  if ($state["frontend"] -and $state["changed"] -and ($msg -notmatch '(?i)(browser|playwright|visual|render|not run|not-run|not_run)')) {
    $loe.Add("FRONTEND_RUNTIME_VERIFICATION_MISSING: UI-related change lacks rendered/browser/Playwright verification or not-run reason.")
    $items.Add("For UI behavior, run browser/Playwright/rendered verification or record exact not-run reason.")
  }
  if ($state["delegation_requested"] -and ($msg -notmatch 'SUBAGENT_CALL')) {
    $loe.Add("DELEGATION_DECISION_MISSING: delegation was requested but SUBAGENT_CALL used/not_used was not recorded.")
    $items.Add("Add SUBAGENT_CALL used/not_used with reason, substitute check, and residual risk.")
  }
  if ($state["mcp_used"] -and ($msg -notmatch '(?i)(MCP|direct evidence|candidate evidence|configured|exposed)')) {
    $loe.Add("MCP_EVIDENCE_STATUS_UNCLEAR: MCP was used without explicit candidate-evidence/direct-check framing.")
    $items.Add("Clarify configured vs exposed MCP status and verify MCP output against direct files/tests/runtime evidence.")
  }

  if ($state["changed"]) { $impact.Add("Changed surface exists; review git diff/status before continuing.") }
  if ($state["control_plane"]) { $impact.Add("Control-plane surface touched: AGENTS/hooks/skills/MCP/toolchain/workflow docs may affect future agent behavior.") }
  if ($state["frontend"]) { $impact.Add("Frontend/UI surface touched: rendered behavior, accessibility, interaction state, and regression tests may be affected.") }
  if ($state["migration"]) { $impact.Add("Migration surface touched: avoid compatibility shims unless explicitly approved; verify target-native behavior.") }
  if ($state["mcp_used"]) { $impact.Add("MCP used: treat tool output as candidate evidence only.") }

  $changedPaths = @($state["changed_paths"]) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 12
  if ($changedPaths.Count -gt 0) {
    $impact.Add(("Changed path hints: " + (($changedPaths) -join ", ")))
  }

  $sync.Add("Run a read-only status/diff context sync and inspect the current diff before further edits.")
  if ($changedPaths.Count -gt 0) {
    $sync.Add(("Inspect changed paths: " + (($changedPaths) -join ", ")))
  }
  if ($state["control_plane"]) {
    $sync.Add("Re-read scoped AGENTS.md and the relevant maintenance runbook before further control-plane changes.")
  }
  if ($state["frontend"]) {
    $sync.Add("Identify owning frontend domain/feature path and relevant test before further UI changes.")
  }
  if ($state["mcp_used"]) {
    $sync.Add("Confirm MCP server was actually exposed in-session; do not treat configured MCP as proof of use.")
  }

  $risk = "P3"
  if ($state["denied_secret"] -or $state["denied_destructive"]) { $risk = "P0" }
  elseif ($state["check_failed"] -or ($state["impact_required"] -and $state["changed"] -and -not $state["workframe_declared"])) { $risk = "P1" }
  elseif ($state["changed"] -and (-not $state["verification_seen"] -or -not $state["context_synced"])) { $risk = "P2" }

  if ($loe.Count -eq 0 -and $items.Count -eq 0) { return $null }

  return [ordered]@{
    kind = "next_turn_handoff"
    profile = "codex_desktop_compact_hooks_v3_next_turn_handoff"
    created_at_utc = [DateTime]::UtcNow.ToString("o")
    source_session_id = (Get-Prop $inputObj "session_id" "")
    source_turn_id = (Get-Prop $inputObj "turn_id" "")
    cwd_hash = (Short-Hash (Get-Prop $inputObj "cwd" ""))
    delivered = $false
    risk_level = $risk
    local_optimization_error = @($loe)
    impact_analysis = @($impact)
    context_synchronization = @($sync)
    next_turn_work_items = @($items)
    surface_flags = [ordered]@{
      changed = [bool]$state["changed"]
      control_plane = [bool]$state["control_plane"]
      frontend = [bool]$state["frontend"]
      migration = [bool]$state["migration"]
      mcp_used = [bool]$state["mcp_used"]
      delegation_requested = [bool]$state["delegation_requested"]
    }
    changed_paths = @($changedPaths)
  }
}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try { $inputObj = $raw | ConvertFrom-Json }
catch { exit 0 }

$event = [string](Get-Prop $inputObj "hook_event_name" "")

$destructive = @(
  '(?i)\brm\s+-rf\s+[/\\*]',
  '(?i)\bRemove-Item\b.*-(Recurse|r)\b.*-(Force|f)\b',
  '(?i)\bgit\s+reset\s+--hard\b',
  '(?i)\bgit\s+clean\s+-f',
  '(?i)\bgit\s+push\s+--force\b',
  '(?i)\bdiskpart\b',
  '(?i)\bformat\s+[A-Z]:'
)

$secretRead = @(
  '(?i)\b(cat|type|Get-Content|gc)\b.*(\.env|auth\.json|id_rsa|id_ed25519|\.pem|\.pfx|\.key|credentials|secret)',
  '(?i)(OPENAI_API_KEY|GITHUB_TOKEN|ANTHROPIC_API_KEY|DATABASE_URL)\s*='
)

$runtimeMutation = @(
  '(?i)\bsetx\s+PATH\b',
  '(?i)\b(codex\s+mcp\s+(add|remove)|claude\s+mcp\s+(add|remove))\b',
  '(?i)\b(npm|pnpm|yarn)\s+install\s+-g\b',
  '(?i)\bpip\s+install\s+--user\b'
)

$controlPlanePattern = '(?i)(AGENTS\.md|hooks/|hooks\\|maintenance/|maintenance\\|\.agents/|\.agents\\|SKILL\.md|config\.toml|mcp|toolchain|workflow|subagent|agent|skill)'
$frontendPattern = '(?i)(frontend|ui|component|css|tailwind|browser|playwright|msw|modal|hover|focus|responsive|screen|view|render|visual)'
$migrationPattern = '(?i)(migration|migrate|upgrade|framework|schema|compatibility)'
$verifyPattern = '(?i)(test|pytest|vitest|playwright|typecheck|tsc|lint|eslint|build|cargo test|go test|npm run)'
$readContextPattern = '(?i)(git\s+status|git\s+diff|git\s+ls-files|rg\b|grep\b|findstr\b|Get-Content\b|gc\b|cat\b|ls\b|dir\b|tree\b|Test-Path\b|Get-ChildItem\b|npm\s+run\b.*--help|--help)'
$mutationPattern = '(?i)(Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Move-Item|Copy-Item|git\s+add|git\s+commit|npm\s+install|pnpm\s+add|yarn\s+add|pip\s+install|uv\s+add|>\s*[^&]|>>\s*[^&])'
$workframePattern = '(?i)HOOK_WORKFRAME'

switch ($event) {
  "SessionStart" {
    $base = @"
Compact workspace rails:
- Codex Desktop is the only development client.
- Hooks are rails, not completion authority.
- Stop hook records next-turn handoff only; it does not force answer correction.
- Before mutation on non-trivial work: sync context with read-only evidence.
- For control-plane/frontend/MCP/toolchain/skill/hook/migration/multi-agent work: declare HOOK_WORKFRAME before mutation.
- Skills: pm-workflow, define-plan, build-verify, review-quality, source-research, frontend-runtime, memory-handoff.
- Memento is support-only; direct files/tests/runtime evidence outrank memory.
"@
    Deliver-PendingContext "SessionStart" $inputObj $base
  }

  "UserPromptSubmit" {
    $prompt = [string](Get-Prop $inputObj "prompt" "")
    $state = New-State

    $state["delegation_requested"] = ($prompt -match '(?i)(multi-agent|subagent|spawn_agent|parallel agent|delegate|delegation|delegated|sidecar|worker|watcher)')
    $state["frontend"] = ($prompt -match $frontendPattern)
    $state["control_plane"] = ($prompt -match '(?i)(hook|mcp|skill|agent|workflow|toolchain|config|AGENTS|runbook|harness|policy)')
    $state["migration"] = ($prompt -match $migrationPattern)

    $isMutationIntent = ($prompt -match '(?i)(apply|implement|modify|change|fix|repair|create|update|delete|install|configure|migrate|patch|write|edit)')
    $isNonTrivial = ($isMutationIntent -or $state["control_plane"] -or $state["frontend"] -or $state["migration"] -or $state["delegation_requested"] -or $prompt.Length -gt 160)

    $state["requires_frame"] = [bool]$isNonTrivial
    $state["impact_required"] = [bool]($state["control_plane"] -or $state["frontend"] -or $state["migration"] -or $state["delegation_requested"] -or ($prompt -match '(?i)(multi-surface|workflow|hook|mcp|toolchain|config|skill|agent|multiple files|cross-surface)'))
    $state["purpose_injected"] = $true
    Save-State $inputObj $state

    $skillHint = "Task frame: keep simple if read-only; otherwise sync context before mutation."
    if ($state["frontend"]) { $skillHint = "Skill hint: frontend-runtime. One domain, one feature, one behavior; use regression test/MSW/browser/Playwright when applicable." }
    elseif ($state["control_plane"]) { $skillHint = "Skill hint: pm-workflow + build-verify. Control-plane changes need context sync, impact frame, parser/runtime checks, and rollback." }
    elseif ($prompt -match '(?i)(bug|fix|fail|error|test|failure)') { $skillHint = "Skill hint: build-verify. Reproduce/inspect first, patch smallest slice, verify directly." }
    elseif ($prompt -match '(?i)(review|refactor|audit|inspect)') { $skillHint = "Skill hint: review-quality. Findings first, evidence, impact, PM decision." }
    elseif ($prompt -match '(?i)(latest|docs|api|library|version|current|documentation)') { $skillHint = "Skill hint: source-research. Use current/official docs or exposed MCP when needed." }
    elseif ($prompt -match '(?i)(plan|design|spec|architecture|requirements)') { $skillHint = "Skill hint: define-plan. Clarify goal, boundary, assumptions, and acceptance checks." }

    if ($state["delegation_requested"]) {
      $skillHint += "`nDelegation hint: explicit delegation detected. Subagents may be used; final evidence should include SUBAGENT_CALL used/not_used."
    }

    $frame = @"
TASK_PURPOSE:
Use the user's current prompt as the purpose. State the purpose before non-trivial work.

COMPACT_GATES:
- First mutation on non-trivial work requires read-only context sync.
- Risky/control-plane/frontend/MCP/toolchain/skill/hook/migration/multi-agent mutation requires:
  Write-Output "HOOK_WORKFRAME purpose=<why>; surface=<target>; impact=<affected surfaces>; checks=<direct checks>; rollback=<plan>"
- Stop will not ask for answer correction; it will record unresolved local optimization errors for the next turn.
$skillHint
"@

    Deliver-PendingContext "UserPromptSubmit" $inputObj $frame
  }

  "PreToolUse" {
    $tool = [string](Get-Prop $inputObj "tool_name" "")
    $text = Tool-Text $inputObj
    $state = Read-State $inputObj

    if (Has-Any $text $secretRead) {
      $state["denied_secret"] = $true
      Save-State $inputObj $state
      Deny-PreTool "Blocked: command appears to read or expose secret/credential material. Use metadata-only inspection or get explicit exact-file authorization."
    }

    if (Has-Any $text $destructive) {
      $state["denied_destructive"] = $true
      Save-State $inputObj $state
      Deny-PreTool "Blocked: destructive command requires explicit user approval, impact analysis, and rollback/safe-stop plan."
    }

    if (Has-Any $text $runtimeMutation) {
      $state["denied_runtime_mutation"] = $true
      Save-State $inputObj $state
      Deny-PreTool "Blocked: active runtime/toolchain/MCP mutation requires explicit approval and managed-maintenance handoff."
    }

    $isWorkframeMarker = ($text -match $workframePattern)
    $isMutation = (($tool -match '^(apply_patch|functions\.apply_patch|Edit|Write)$') -or ($text -match $mutationPattern))
    $isContextRead = ($text -match $readContextPattern)

    if (($isContextRead -or $isWorkframeMarker) -and -not $isMutation) { EmptyOk }

    if ($state["requires_frame"] -eq $true -and $isMutation -and $state["context_synced"] -ne $true) {
      Deny-PreTool "Blocked: context sync required before mutation. First run read-only inspection such as git status/diff plus relevant AGENTS/runbook/files/tests."
    }

    if ($state["impact_required"] -eq $true -and $isMutation -and $state["workframe_declared"] -ne $true) {
      Deny-PreTool "Blocked: impact frame required before this mutation. Run: Write-Output `"HOOK_WORKFRAME purpose=<why>; surface=<target>; impact=<affected surfaces>; checks=<direct checks>; rollback=<plan>`""
    }

    if ($tool -match '^mcp__') {
      Add-Context "PreToolUse" "MCP call: candidate evidence only. Verify configured vs exposed status and confirm with files/tests/runtime evidence."
    }

    if ($text -match $controlPlanePattern) {
      Add-Context "PreToolUse" "Control-plane surface: keep the slice small, avoid duplicate policy, verify parser/runtime impact, and preserve rollback."
    }

    EmptyOk
  }

  "PostToolUse" {
    $tool = [string](Get-Prop $inputObj "tool_name" "")
    $text = Tool-Text $inputObj
    $responseText = ""
    $toolResponse = Get-Prop $inputObj "tool_response" $null
    if ($null -ne $toolResponse) {
      try { $responseText = ($toolResponse | ConvertTo-Json -Depth 10 -Compress) }
      catch { $responseText = "" }
    }

    $state = Read-State $inputObj

    if ($tool -match '^(apply_patch|functions\.apply_patch|Edit|Write)$') {
      $state["changed"] = $true
      $state["mutation_attempted"] = $true
      $state["changed_paths"] = Add-UniquePaths $state["changed_paths"] (Extract-ChangedPaths $text)
    }

    if ($text -match $mutationPattern) {
      $state["changed"] = $true
      $state["mutation_attempted"] = $true
      $state["changed_paths"] = Add-UniquePaths $state["changed_paths"] (Extract-ChangedPaths $text)
    }

    if ($tool -match '^mcp__') { $state["mcp_used"] = $true }
    if ($text -match $controlPlanePattern) { $state["control_plane"] = $true }
    if ($text -match $frontendPattern) { $state["frontend"] = $true }
    if ($text -match $migrationPattern) { $state["migration"] = $true }
    if ($text -match $verifyPattern) { $state["verification_seen"] = $true }
    if ($text -match $readContextPattern) { $state["context_synced"] = $true }

    if ($text -match $workframePattern) {
      if (($text -match '(?i)purpose\s*=') -and ($text -match '(?i)impact\s*=') -and ($text -match '(?i)checks\s*=')) {
        $state["workframe_declared"] = $true
      }
    }

    if ($responseText -match '(?i)("exit_code"\s*:\s*[1-9]|"status"\s*:\s*"failed"|failed|error|Traceback|AssertionError)') {
      if ($text -match $verifyPattern) { $state["check_failed"] = $true }
    }

    Save-State $inputObj $state
    EmptyOk
  }

  "Stop" {
    # Critical v3 behavior:
    # Do not answer-correct. Do not continue the model. Only record next-turn work.
    $state = Read-State $inputObj
    $handoff = Compute-Handoff $inputObj $state

    if ($null -ne $handoff) {
      Write-JsonFile (Get-SessionPendingPath $inputObj) $handoff
      Write-JsonFile (Get-WorkspacePendingPath $inputObj) $handoff
    }

    Continue-Ok
  }

  default { EmptyOk }
}
