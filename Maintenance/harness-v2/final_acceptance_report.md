# Harness V2 Final Acceptance Report

Status: `verified_candidate_evidence`

This report records PM-reviewed evidence for the current scoped task. It is not
completion authority by itself; Stop/gate-issued receipt remains the final
authority boundary.

## Scope

- Handoff target: current GlobalSSOT turn.
- Main agent role: PM/orchestrator.
- Worker policy: actual code/production workers use `gpt-5.5` with
  `reasoning_effort=medium`, `max_threads=8`, and `max_depth=1`.
- Inspector policy: Spark inspectors remain read-only
  `gpt-5.3-codex-spark`, fallback `latest-mini`,
  `reasoning_effort=high`, candidate evidence only.
- Configured subagent limits: `%USERPROFILE%\.codex\config.toml`
  `[agents].max_threads = 8` and `[agents].max_depth = 1`.
- Runtime capability receipt records disabled MCP servers, installed P0
  `agent-skills`, worker/inspector model policy, and the same depth/thread
  limits.

## Implemented Changes

- Installed the P0 `addyosmani/agent-skills` subset and recorded source commit,
  copied skills, skipped skills, and hashes in
  `Maintenance\agent-skills-integration\agent_skills_inventory.json`.
- Added `skill_resolution_receipt.v1` and `skill_usage_events.jsonl`, registered
  them in `MANIFEST.json` and `runtime_state.schema.json`, and wired them into
  the task classification, need resolution, required route, and Stop checks.
- Added `skill_routes` to `required-tool-routes.json` without mixing them into
  tool, worker, or inspector routes.
- Propagated required skills into worker job envelopes and inspector compliance
  targets while preserving candidate-only authority for all subagent reports.
- Narrowed frontend/backend surface parsing so skill catalog wording does not
  create frontend/backend routes without path or artifact evidence.
- Repaired subagent route selection so a later queued duplicate does not hide a
  reported or spawned job for the same route.
- Aligned Harness V2 flexibility with live PreToolUse behavior: Class 3/4
  control-plane writes without PM preflight or scheduled subagent jobs are
  blocked before mutation, while missing reports remain Stop evidence.
- Added coverage for Korean operational gate/worktree intent so review,
  cleanup, gate-pass, commit, and push requests classify upward to Class 3.

## Verification

- TOML/JSON/YAML parse matrix: passed.
- PowerShell parser for `Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1`: passed.
- `Maintenance\harness-v2\Invoke-HarnessV2Acceptance.ps1`: 126 total,
  126 passed, 0 failed.
- Skill route acceptance coverage: 14 skill-specific cases.
- Agent-skills inventory hash check: passed.
- Current-turn task, need, and skill receipts use a matching turn fingerprint.
- SessionStart observation refreshed `runtime_capability_receipt.json` after the
  global agent limit update.

## PM Notes

Installed/configured/available skills remain non-evidence. Required skill routes
are satisfied only by `skill_usage_event.v1` or explicit
`UNAVAILABLE`/`NOT_APPLICABLE` evidence. Worker and inspector outputs are still
candidate inputs; Stop/gate-issued receipt is the only completion authority.
