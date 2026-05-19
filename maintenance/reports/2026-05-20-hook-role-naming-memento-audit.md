# Hook Role, Naming, and Memento Audit

- Date: 2026-05-20 KST
- Scope: `%USERPROFILE%\.codex` and `%USERPROFILE%\.agents` maintenance surfaces.
- User clarification: the two active hooks are intentional. The issue is that
  hooks were obstructing or pretending to cover roles they were not reliably
  performing.

## Classification

- Active runtime hooks: `SessionStart`, `UserPromptSubmit`.
- Intentionally inactive hooks: `PreToolUse`, `PermissionRequest`,
  `PostToolUse`, `Stop`.
- Synthetic smoke samples for inactive hooks are contract tests only. They are
  not evidence that disabled lifecycle hooks are active runtime enforcement.

## Root Cause

The hook control plane did not explicitly verify the runtime active/inactive
state, while the hook smoke test exercised disabled lifecycle paths as if they
were part of the live runtime story. That made the system look stricter than it
actually was and let stale final-gate assumptions survive in docs and smoke
expectations. The missing check also meant a disabled hook could be discussed as
if it was protecting the workflow, while the user's observed workflow improved
when those hooks stayed off.

A secondary naming issue came from keeping an active `.codex\skills\vowline`
compatibility mirror next to the real `.agents\skills\vowline` skill. The two
copies were identical, but the duplicate active lookup surface weakened the
new naming convention and made future same-name drift more likely.

## Corrections

- Added `hooks.runtime_state` to `hooks\lightweight-codex-policy.json` so the
  intended active and inactive hook events are machine-readable.
- Added `hook_runtime_state` to core and extended doctor checks.
- Added `hook_smoke_respects_runtime_active_state` to `hook-policy-smoke`.
- Normalized hook event names so config keys such as `pre_tool_use` and policy
  names such as `PreToolUse` compare as the same event.
- Added `maintenance\scripts\check-naming-conventions.ps1` and wired it into
  doctor and verify.
- Updated `using-agent-skills` and `maintenance\NAMING_CONVENTION.md` to forbid
  same-name nested directories and active cross-root skill duplicates.
- Moved duplicate `.codex\skills\vowline` to the Windows Recycle Bin; the
  canonical active copy is `%USERPROFILE%\.agents\skills\vowline`.
- Kept Memento MCP enabled in local config and documented default-use behavior
  for PM support context and relevant recall.

## Direct Checks

- `python maintenance/scripts/codex_agent_harness.py doctor --tier core --json`
  passed.
- `python maintenance/scripts/codex_agent_harness.py doctor --tier extended --json`
  passed.
- `python maintenance/scripts/codex_agent_harness.py eval --eval-id hook-policy-smoke`
  passed.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/check-naming-conventions.ps1 -Json`
  passed with `finding_count=0` and `blocking_count=0`.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/memento-mcp-runtime.ps1 verify`
  passed with required Memento tools present and `context`, `recall`, and
  `tool_feedback` checks passing.
- PowerShell parser check for `hooks\lightweight-codex-hook.ps1` and
  `hooks\lib\*.ps1` passed.
- PowerShell parser check for modified hook and maintenance scripts passed.
- `python maintenance/scripts/codex_agent_harness.py verify` passed after the
  self-test fixture was updated for the new hook runtime-state and naming
  checks.
- `python maintenance/scripts/codex_agent_harness.py repo-verify` passed.
- `python maintenance/scripts/codex_agent_harness.py benchmark` passed.
- `python maintenance/scripts/codex_agent_harness.py audit --json` passed with
  score `100.0`.

## Residual Risk

- Memento tools may still require a new Codex session reload before
  `mcp__memento__...` tools are exposed to an already-running agent session.
- Disabled lifecycle hooks remain present as code and smoke fixtures. They must
  stay classified as dormant contract surfaces unless the user intentionally
  re-enables them.
- Plugin cache content is still runtime material; naming checks intentionally
  avoid treating ignored official plugin cache copies as user-owned source.
